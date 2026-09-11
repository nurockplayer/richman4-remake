extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const SourceAutosave = preload("res://game/ui/source_autosave.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const FinanceFixture = preload("res://tests/fixtures/building_card_fixture.gd")

var checks := 0
var failures := 0


class MemoryStorage extends RefCounted:
	var writes: Array = []
	var fail_next := false

	func write_automatic(payload: Variant) -> Dictionary:
		writes.append(payload.duplicate(true) if payload is Dictionary else payload)
		if fail_next:
			fail_next = false
			return {"ok": false, "status": "error", "error": "transient_storage_failure"}
		return {"ok": true, "status": "written", "source_identity": "automatic"}


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _initialize() -> void:
	_test_human_cycle_and_ledger_identity()
	_test_ai_wrap_and_nonwrap()
	_test_disabled_wrap_is_not_backfilled()
	_test_duplicate_capture_flushes_once()
	_test_owner_replacement_discards_stale_pending()
	_test_failed_retry_and_skip()
	_test_pending_finance_waits_for_final_day_wrap()
	print("Source autosave checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _new_game(seed_value: int, player_count: int = 2) -> Object:
	return GameState.new_game(seed_value, player_count)


func _complete_public_turn(game: Object) -> Array:
	var before: Dictionary = game.to_dict()
	if str(game.state.get("phase", "")) == "await_roll":
		var rolled: Dictionary = game.roll()
		expect(bool(rolled.get("ok", false)), "public roll completes for autosave cycle")
	if str(game.state.get("phase", "")) == "await_action":
		var ended: Dictionary = game.end_turn()
		expect(bool(ended.get("ok", false)), "public end_turn completes for autosave cycle")
	return [before, game.to_dict()]


func _capture_and_flush(autosave: Object, game: Object, storage: Object, before: Dictionary, after: Dictionary, enabled: bool) -> Dictionary:
	autosave.capture_transition(game, before, after, enabled)
	return autosave.flush(game, storage, false)


func _test_human_cycle_and_ledger_identity() -> void:
	var game := _new_game(14101)
	var autosave := SourceAutosave.new()
	var storage := MemoryStorage.new()
	var first := _complete_public_turn(game)
	var first_flush := _capture_and_flush(autosave, game, storage, first[0], first[1], true)
	expect(first_flush.is_empty(), "non-wrapping human actor does not checkpoint")
	var before_wrap_json: String = game.to_json()
	var second := _complete_public_turn(game)
	var second_flush := _capture_and_flush(autosave, game, storage, second[0], second[1], true)
	expect(bool(second_flush.get("ok", false)), "wrapping human actor checkpoints")
	expect_equal(storage.writes.size(), 1, "human cycle emits one automatic write at day wrap")
	if storage.writes.size() == 1:
		expect_equal(storage.writes[0], second[1], "checkpoint is the post-wrap owner snapshot")
	expect_equal(int(second[1].get("day", 0)), 2, "human cycle advances the real day at wrap")
	expect(game.to_json() != before_wrap_json, "public human cycle changes the game before checkpoint")
	var after_flush_json: String = game.to_json()
	expect_equal(after_flush_json, JSON.stringify(second[1]), "capture and flush leave owner ledger unchanged")
	expect_equal(int(game.state.get("rng_state", -1)), int(second[1].get("rng_state", -2)), "capture and flush leave RNG state unchanged")


func _test_ai_wrap_and_nonwrap() -> void:
	var game := _new_game(14102)
	for player in game.state.players:
		player.is_ai = true
		player.is_human = false
	var autosave := SourceAutosave.new()
	var storage := MemoryStorage.new()
	var before_nonwrap: Dictionary = game.to_dict()
	var nonwrap_result: Dictionary = game.run_ai_turn()
	expect(bool(nonwrap_result.get("ok", false)), "AI non-wrapping public turn completes")
	var after_nonwrap: Dictionary = game.to_dict()
	var nonwrap_flush := _capture_and_flush(autosave, game, storage, before_nonwrap, after_nonwrap, true)
	expect(nonwrap_flush.is_empty(), "AI non-wrapping turn does not checkpoint")
	var before_wrap: Dictionary = game.to_dict()
	var wrap_result: Dictionary = game.run_ai_turn()
	expect(bool(wrap_result.get("ok", false)), "AI wrapping public turn completes")
	var after_wrap: Dictionary = game.to_dict()
	var wrap_flush := _capture_and_flush(autosave, game, storage, before_wrap, after_wrap, true)
	expect(bool(wrap_flush.get("ok", false)), "AI wrapping turn checkpoints")
	expect_equal(storage.writes.size(), 1, "AI cycle emits one automatic write at day wrap")
	expect_equal(int(after_wrap.get("day", 0)), 2, "AI cycle advances the real day at wrap")


func _test_disabled_wrap_is_not_backfilled() -> void:
	var game := _new_game(14103)
	var autosave := SourceAutosave.new()
	var storage := MemoryStorage.new()
	for _actor in range(2):
		var transition := _complete_public_turn(game)
		var flush_result := _capture_and_flush(autosave, game, storage, transition[0], transition[1], false)
		expect(flush_result.is_empty(), "disabled autosave ignores the wrapped transition")
	expect(not autosave.pending(), "disabled wrap does not retain pending work")
	var later := _complete_public_turn(game)
	var later_flush := _capture_and_flush(autosave, game, storage, later[0], later[1], true)
	expect(later_flush.is_empty(), "enabling autosave later does not backfill disabled wrap")
	expect_equal(storage.writes.size(), 0, "disabled wrap remains absent after re-enable")


func _test_duplicate_capture_flushes_once() -> void:
	var game := _new_game(14104)
	var transition := _complete_public_turn(game)
	var second_transition := _complete_public_turn(game)
	var autosave := SourceAutosave.new()
	var storage := MemoryStorage.new()
	autosave.capture_transition(game, second_transition[0], second_transition[1], true)
	autosave.capture_transition(game, second_transition[0], second_transition[1], true)
	var first := autosave.flush(game, storage, false)
	var second := autosave.flush(game, storage, false)
	expect(bool(first.get("ok", false)), "first duplicate flush succeeds")
	expect(second.is_empty(), "second duplicate flush is suppressed")
	expect_equal(storage.writes.size(), 1, "duplicate capture and flush write once")
	expect(transition[1].get("day", 0) == 1 and second_transition[1].get("day", 0) == 2, "duplicate fixture covers nonwrap then wrap")


func _test_owner_replacement_discards_stale_pending() -> void:
	var owner_a := _new_game(14105)
	var owner_b := _new_game(14106)
	var transition := _complete_public_turn(owner_a)
	transition = _complete_public_turn(owner_a)
	var autosave := SourceAutosave.new()
	var storage := MemoryStorage.new()
	autosave.capture_transition(owner_a, transition[0], transition[1], true)
	expect(autosave.pending(), "owner A has pending checkpoint")
	autosave.sync_owner(owner_b)
	expect(not autosave.pending(), "owner replacement clears owner A checkpoint")
	expect(autosave.flush(owner_b, storage, false).is_empty(), "owner B cannot flush owner A checkpoint")
	expect_equal(storage.writes.size(), 0, "owner replacement emits no stale write")


func _test_failed_retry_and_skip() -> void:
	var game := _new_game(14107)
	var transition := _complete_public_turn(game)
	transition = _complete_public_turn(game)
	var autosave := SourceAutosave.new()
	var storage := MemoryStorage.new()
	autosave.capture_transition(game, transition[0], transition[1], true)
	storage.fail_next = true
	var failed := autosave.flush(game, storage, false)
	expect(not bool(failed.get("ok", true)), "transient automatic write failure is surfaced")
	expect(autosave.failed() and autosave.pending(), "failed write retains pending checkpoint")
	expect(autosave.flush(game, storage, false).is_empty(), "failed checkpoint is once-only until retry")
	autosave.retry()
	var retried := autosave.flush(game, storage, false)
	expect(bool(retried.get("ok", false)), "retry resubmits the unchanged checkpoint")
	expect(not autosave.pending(), "successful retry clears pending checkpoint")
	var before: Dictionary = game.to_dict()
	var after: Dictionary = before.duplicate(true)
	after.day = int(before.day) + 1
	after.phase = "await_roll"
	autosave.capture_transition(game, before, after, true)
	expect(autosave.pending(), "second fixture creates a pending checkpoint")
	autosave.skip()
	expect(not autosave.pending() and autosave.flush(game, storage, false).is_empty(), "skip clears pending checkpoint without a write")


func _test_pending_finance_waits_for_final_day_wrap() -> void:
	var definition: Dictionary = FinanceFixture.definition()
	definition.board[2].rent_by_level = [2000, 2000, 2000, 2000, 2000, 2000]
	definition.board[2].base_rent = 2000
	definition.board[2].rent = 2000
	var game: Object = GameState.new_game_on_board(14108, 4, definition, FinanceFixture.new_game_options())
	expect(game != null, "focused financial fixture constructs for autosave")
	if game == null:
		return
	game.state.god_objects = []
	for player_id in range(4):
		game.set_player_ai(player_id, false)
		game.state.players[player_id].position = 1
		game.state.players[player_id].previous_position = 0
	game.state.board[2].owner = 1
	game.state.board[2].building_level = 1
	game.state.players[1].properties = [2]
	game._update_tile_rent(game.state.board[2])
	game._recalculate_property_values()
	expect(bool(Inventory.grant_card(game.state.inventory_supply, game.state.players[3].cards, "免費").get("ok", false)), "focused finance fixture grants free card")
	game.state.day = 14
	game.state.current_player = 3
	game.state.phase = "await_roll"
	game.state.players[3].turtle_days = 1
	game._sync_state()
	game._set_action_options(3)
	var setup_validation: Dictionary = GameState.validate_save(game.to_dict())
	if not bool(setup_validation.get("ok", false)):
		push_error("SETUP FAILURE: focused finance fixture is invalid: " + str(setup_validation.get("errors", [])))
		quit(2)
		return
	var before_roll: Dictionary = game.to_dict()
	var rolled: Dictionary = game.roll()
	expect(bool(rolled.get("ok", false)), "focused finance fixture reaches fee by public roll")
	if str(game.state.get("phase", "")) == "await_route":
		var route_result: Dictionary = game.choose_route(2)
		expect(bool(route_result.get("ok", false)), "focused finance fixture reaches fee by public route")
	var pending: Dictionary = game.financial_response()
	expect(not pending.is_empty(), "real public landing creates pending finance response")
	var autosave := SourceAutosave.new()
	var storage := MemoryStorage.new()
	var pending_snapshot: Dictionary = game.to_dict()
	var transient := _capture_and_flush(autosave, game, storage, before_roll, pending_snapshot, true)
	expect(transient.is_empty() and storage.writes.is_empty(), "pending finance transient does not checkpoint")
	expect(not bool(game.end_turn().get("ok", true)), "pending finance blocks transient end_turn")
	expect(bool(game.choose_action("respond_finance", {"cancel": false}).get("ok", false)), "focused finance response resolves publicly")
	# The same actor's real public end_turn crosses day 14 -> 15. Autosave is
	# evaluated only after that final day wrap, once the transient is gone.
	var before_wrap: Dictionary = game.to_dict()
	expect(bool(game.end_turn().get("ok", false)), "final actor public end_turn crosses day boundary")
	var after_wrap: Dictionary = game.to_dict()
	var final_write := _capture_and_flush(autosave, game, storage, before_wrap, after_wrap, true)
	expect(bool(final_write.get("ok", false)), "final day wrap triggers automatic checkpoint")
	expect_equal(storage.writes.size(), 1, "finance transient is not written before final day wrap")
	expect_equal(int(storage.writes[0].get("day", 0)), 15, "automatic checkpoint is the final wrapped day")
	expect(not storage.writes[0].has("pending_finance") or storage.writes[0].pending_finance.is_empty(), "final checkpoint has no transient finance response")
