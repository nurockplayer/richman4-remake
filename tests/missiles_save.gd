extends SceneTree

## Issue #80 save-boundary seed for missile and nuclear missile actions.
##
## Every positive action starts from a v13 graph save and is replayed through
## JSON.  Cancellation and malformed target inputs must preserve the exact
## serialized state.  Current production reports the intentionally qualified
## RED "此道具效果尚未還原" for the two positive public actions.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/missile_fixture.gd")

const V13 := 13
const MISSILE := "飛彈"
const NUCLEAR := "核子飛彈"
const CENTRE := 1
const ORDINARY_HOUSE := 2
const CHAIN_HOUSE := 3

var checks: int = 0
var failures: int = 0
var qualified_red: int = 0


func _initialize() -> void:
	_test_clean_v13_json_round_trip()
	_test_cancel_and_invalid_save_atomicity()
	_test_missile_success_json_replay()
	_test_nuclear_success_json_replay()
	print("Missile save checks: %d, failures: %d, qualified_red: %d" % [checks, failures, qualified_red])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_game(seed_value: int, player_count: int = 4) -> Object:
	var game: Object = Fixture.new_game(seed_value, player_count)
	_expect(game != null, "v13 missile save fixture starts")
	if game == null:
		return null
	_expect_equal(int(game.state.get("version", -1)), V13, "save fixture uses v13")
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), "fresh v13 save fixture validates: " + str(validation.get("errors", [])))
	return game


func _prepare_action(game: Object, player_id: int, position: int, phase: String = "await_roll") -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state["players"][player_id]["position"] = position
	game.state["players"][player_id]["previous_position"] = -1
	game._set_action_options(player_id)


func _stage_missile(game: Object, player_id: int = 0) -> bool:
	var result: Dictionary = Inventory.grant_tool(game.state["inventory_supply"], game.state["players"][player_id]["tools"], MISSILE, 1)
	_expect(bool(result.get("ok", false)), "save fixture stages a finite missile")
	return bool(result.get("ok", false))


func _public_use(game: Object, params: Dictionary, label: String) -> Dictionary:
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), label + " validates immediately before public use_tool: " + str(validation.get("errors", [])))
	_expect(game.state.get("action_options", []).has("use_tool"), label + " exposes a legal use_tool action")
	return game.choose_action("use_tool", params)


func _mark_red(result: Dictionary, label: String) -> void:
	if not bool(result.get("ok", false)) and str(result.get("message", "")).contains("尚未還原"):
		qualified_red += 1
		print("QUALIFIED RED: %s -> %s" % [label, str(result.get("message", ""))])


func _test_clean_v13_json_round_trip() -> void:
	var game: Object = _new_game(8150, 4)
	if game == null:
		return
	var encoded: String = game.to_json()
	var parsed: Variant = JSON.parse_string(encoded)
	_expect(parsed is Dictionary, "clean v13 save JSON parses")
	if not parsed is Dictionary:
		return
	var restored: Object = Game.from_dict(parsed)
	_expect(restored != null, "clean v13 save restores through from_dict")
	if restored == null:
		return
	_expect_equal(restored.to_json(), encoded, "clean v13 save round-trips byte-for-byte")
	var validation: Dictionary = Game.validate_save(restored.to_dict())
	_expect(bool(validation.get("ok", false)), "restored clean v13 save validates: " + str(validation.get("errors", [])))


func _assert_rejected_atomic(game: Object, params: Dictionary, label: String) -> void:
	var before_json: String = game.to_json()
	var before_rng: String = str(game.state.get("rng_state_text", ""))
	var before_event: Dictionary = game.state.get("last_event", {}).duplicate(true)
	var before_supply: int = int(game.state["inventory_supply"]["tools"].get(MISSILE, -1))
	var before_held: int = int(game.state["players"][0]["tools"].get(MISSILE, 0))
	var result: Dictionary = _public_use(game, params, label)
	_mark_red(result, label)
	_expect(not bool(result.get("ok", false)), label + " is rejected")
	_expect(not str(result.get("message", "")).contains("尚未還原"), label + " reaches strict target/type validation")
	_expect_equal(game.to_json(), before_json, label + " preserves exact JSON")
	_expect_equal(str(game.state.get("rng_state_text", "")), before_rng, label + " preserves RNG continuation")
	_expect_equal(game.state.get("last_event", {}), before_event, label + " does not append an event")
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(MISSILE, -1)), before_supply, label + " preserves finite missile supply")
	_expect_equal(int(game.state["players"][0]["tools"].get(MISSILE, 0)), before_held, label + " preserves the held missile")


func _test_cancel_and_invalid_save_atomicity() -> void:
	var cancelled: Object = _new_game(8151, 4)
	if cancelled != null and _stage_missile(cancelled):
		_prepare_action(cancelled, 0, CENTRE)
		var before_json: String = cancelled.to_json()
		var before_event: Dictionary = cancelled.state.get("last_event", {}).duplicate(true)
		var result: Dictionary = _public_use(cancelled, {"tool_id": MISSILE, "cancel": true}, "missile save cancellation")
		_mark_red(result, "missile save cancellation")
		_expect(bool(result.get("ok", false)), "missile cancellation succeeds at save boundary")
		_expect_equal(cancelled.to_json(), before_json, "missile cancellation preserves exact JSON")
		_expect_equal(cancelled.state.get("last_event", {}), before_event, "missile cancellation preserves last event")

	var cases: Array = [
		{"label": "missile save missing tile", "params": {"tool_id": MISSILE}},
		{"label": "missile save off-map tile", "params": {"tool_id": MISSILE, "tile_id": 10}},
		{"label": "missile save malformed cancel", "params": {"tool_id": MISSILE, "tile_id": ORDINARY_HOUSE, "cancel": "yes"}},
	]
	for offset in range(cases.size()):
		var game: Object = _new_game(8152 + offset, 4)
		if game == null or not _stage_missile(game):
			continue
		_prepare_action(game, 0, CENTRE)
		var case_value: Dictionary = cases[offset]
		_assert_rejected_atomic(game, case_value["params"], str(case_value["label"]))


func _configure_missile_world(game: Object) -> void:
	Fixture.set_property(game, ORDINARY_HOUSE, 1, 2, false)
	Fixture.set_property(game, CHAIN_HOUSE, 1, 1, true)
	Fixture.set_facility(game, 1, 1, 2, 1, 0x50, 0, 0)
	for player_value in game.state["players"]:
		player_value["hospital_days"] = 0
		player_value["prison_days"] = 0
		player_value["god_id"] = 0
	game.state["players"][0]["position"] = CENTRE
	game.state["players"][1]["position"] = ORDINARY_HOUSE


func _test_missile_success_json_replay() -> void:
	var game: Object = _new_game(8160, 4)
	if game == null:
		return
	_configure_missile_world(game)
	var supply_before: int = int(game.state["inventory_supply"]["tools"].get(MISSILE, -1))
	if not _stage_missile(game):
		return
	_prepare_action(game, 0, CENTRE)
	var result: Dictionary = _public_use(game, {"tool_id": MISSILE, "tile_id": CENTRE}, "missile save replay")
	if not bool(result.get("ok", false)):
		_mark_red(result, "missile save replay")
		_expect(false, "missile save replay succeeds: " + str(result.get("message", "")))
		return
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(MISSILE, -1)), supply_before, "missile replay recycles exactly one finite supply unit")
	_expect_equal(int(game.state["players"][0]["tools"].get(MISSILE, 0)), 0, "missile replay removes the held tool")
	var encoded: String = game.to_json()
	var parsed: Variant = JSON.parse_string(encoded)
	_expect(parsed is Dictionary, "missile success JSON parses")
	if not parsed is Dictionary:
		return
	var restored: Object = Game.from_dict(parsed)
	_expect(restored != null, "missile success save restores")
	if restored == null:
		return
	_expect_equal(restored.to_json(), encoded, "missile success save preserves exact event/state JSON")
	var validation: Dictionary = Game.validate_save(restored.to_dict())
	_expect(bool(validation.get("ok", false)), "missile success save validates after restore: " + str(validation.get("errors", [])))


func _configure_nuclear_world(game: Object) -> void:
	Fixture.set_property(game, ORDINARY_HOUSE, 1, 2, false)
	Fixture.set_property(game, CHAIN_HOUSE, 1, 1, true)
	Fixture.set_facility(game, 1, 0, 5, 4, 0x50, 5, 0)
	Fixture.set_facility(game, 2, 1, 2, 2, 0x50, 0, 0)
	for player_value in game.state["players"]:
		player_value["hospital_days"] = 0
		player_value["prison_days"] = 0
		player_value["god_id"] = 0
	game.state["players"][0]["position"] = CENTRE
	game.state["players"][1]["position"] = ORDINARY_HOUSE


func _test_nuclear_success_json_replay() -> void:
	var game: Object = _new_game(8170, 2)
	if game == null:
		return
	_configure_nuclear_world(game)
	var nuclear_supply_before: int = int(game.state["inventory_supply"]["tools"].get(NUCLEAR, -1))
	var grant: Dictionary = Inventory.grant_tool(game.state["inventory_supply"], game.state["players"][0]["tools"], NUCLEAR, 1)
	_expect(bool(grant.get("ok", false)), "save fixture stages research-produced nuclear missile")
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(NUCLEAR, -1)), nuclear_supply_before, "research-produced nuclear staging keeps shared supply at zero")
	_prepare_action(game, 0, CENTRE)
	var result: Dictionary = _public_use(game, {"tool_id": NUCLEAR, "tile_id": CENTRE}, "nuclear save replay")
	if not bool(result.get("ok", false)):
		_mark_red(result, "nuclear save replay")
		_expect(false, "nuclear save replay succeeds: " + str(result.get("message", "")))
		return
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(NUCLEAR, -1)), nuclear_supply_before, "nuclear replay keeps research tool supply unbounded")
	_expect_equal(int(game.state["players"][0]["tools"].get(NUCLEAR, 0)), 0, "nuclear replay removes the held research tool")
	var encoded: String = game.to_json()
	var parsed: Variant = JSON.parse_string(encoded)
	_expect(parsed is Dictionary, "nuclear success JSON parses")
	if not parsed is Dictionary:
		return
	var restored: Object = Game.from_dict(parsed)
	_expect(restored != null, "nuclear success save restores")
	if restored == null:
		return
	_expect_equal(restored.to_json(), encoded, "nuclear success save preserves exact event/state JSON")
	var validation: Dictionary = Game.validate_save(restored.to_dict())
	_expect(bool(validation.get("ok", false)), "nuclear success save validates after restore: " + str(validation.get("errors", [])))
