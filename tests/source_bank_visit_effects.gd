extends SceneTree

## Issue #135 supplementary RED coverage for source bank pauses.
##
## The controller suite proves the bank token itself.  This seed keeps the
## movement suffix and source-road objects in the same save so the core must
## suspend the ordinary encounter pipeline at the bank and resume it exactly
## once after the ATM closes.
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/source_bank_visit_fixture.gd")

const V7_OPTIONS := {
	"original_facilities": true,
	"original_gods": true,
	"original_companies": true,
	"start_date": {"year": 1998, "month": 1, "day": 1},
}
const V9_OPTIONS := {
	"original_facilities": true,
	"original_gods": true,
	"original_companies": true,
	"original_statuses": true,
	"original_hazards": true,
	"start_date": {"year": 1998, "month": 1, "day": 1},
}

var checks: int = 0
var failures: int = 0
var setup_failures: int = 0
var definition: Dictionary = {}


func _initialize() -> void:
	definition = Fixture.definition()
	_setup_expect(not definition.is_empty(), "source bank effects fixture normalizes")
	var v7: Object = _new_game(V7_OPTIONS, 13511)
	if v7 != null:
		_setup_expect(_valid_save(v7), "fresh v7 source bank effects save validates")
	var v9: Object = _new_game(V9_OPTIONS, 13512)
	if v9 != null:
		_setup_expect(_valid_save(v9), "fresh v9 source bank effects save validates")
	if setup_failures > 0:
		_finish(2)
		return

	_test_v7_attached_god_follows_bank()
	_test_v7_unbound_god_deferred_until_resume()
	_test_v7_roadblock_deferred_until_resume()
	_test_v9_carried_bomb_deferred_until_resume()
	_test_v9_ground_objects_survive_bank_pauses()
	_test_pass_withdraw_then_property_fee()
	_finish(1 if failures > 0 else 0)


func _finish(exit_status: int) -> void:
	print("Source bank visit effects checks: %d, failures: %d, setup_failures: %d" % [checks, failures, setup_failures])
	quit(exit_status)


func _expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	return condition


func _setup_expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		setup_failures += 1
		push_error("SETUP FAIL: " + message)
	return condition


func _new_game(options: Dictionary, seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 2, definition, options)
	if game == null:
		_setup_expect(false, "source bank effects game starts for seed %d" % seed_value)
		return null
	# The second actor is parked away from the bank under test.  Both source and
	# hazard validators then see an unambiguous, reachable setup.
	game.state.players[1]["position"] = 8
	game.state.players[1]["previous_position"] = 6
	game.state.god_objects = []
	game._sync_state()
	game._set_action_options(0)
	return game


func _prepare_roll(game: Object, origin: int = 0, previous: int = -1) -> void:
	game.state["current_player"] = 0
	game.state["phase"] = "await_roll"
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["bank_access"] = false
	game.state["bank_landing"] = false
	game.state["property_action_used"] = false
	var player: Dictionary = game.state.players[0]
	player["position"] = origin
	player["previous_position"] = previous
	player["hospital_days"] = 0
	if player.has("prison_days"):
		player["prison_days"] = 0
	game.state.erase("pending_bank_visit")
	game._sync_state()
	game._set_action_options(0)


func _arm_two_step_roll(game: Object, label: String, value: int = 2) -> bool:
	# Facilities imply the v7 inventory boundary, so a serialized remote die is a
	# deterministic roll for both versions.  Validate this exact state before the
	# public roll call; a malformed fixture is setup failure rather than encounter
	# RED.  Most cases use two steps; the branch fixture supplies four explicitly.
	game.state["pending_remote_dice"] = {"player_id": 0, "value": value}
	game._set_action_options(0)
	return _setup_expect(_valid_save(game), label + " setup validates before roll")


func _valid_save(game: Object) -> bool:
	var validation: Dictionary = Game.validate_save(game.to_dict())
	return bool(validation.get("ok", false))


func _expect_valid_save(game: Object, label: String) -> bool:
	var validation: Dictionary = Game.validate_save(game.to_dict())
	return _expect(bool(validation.get("ok", false)), label + ": " + str(validation.get("errors", [])))


func _event_count(game: Object, event_type: String) -> int:
	var count: int = 0
	for event_value in game.state.get("event_log", []):
		if typeof(event_value) == TYPE_DICTIONARY and str(event_value.get("type", "")) == event_type:
			count += 1
	return count


func _event_count_with_field(game: Object, event_type: String, field: String, expected: Variant) -> int:
	var count: int = 0
	for event_value in game.state.get("event_log", []):
		if typeof(event_value) != TYPE_DICTIONARY or str(event_value.get("type", "")) != event_type:
			continue
		if event_value.get(field, null) == expected:
			count += 1
	return count


func _pending_pass(game: Object, node_id: int, remaining: int, label: String) -> bool:
	var token: Variant = game.state.get("pending_bank_visit", null)
	var token_ok: bool = typeof(token) == TYPE_DICTIONARY and token.get("kind", "") == "pass" and int(token.get("player_id", -1)) == 0 and int(token.get("node_id", -1)) == node_id
	_expect(token_ok, label + " stores a pass bank token")
	if not token_ok:
		return false
	_expect(str(game.state.get("phase", "")) == "await_bank", label + " waits in await_bank")
	_expect(int(game.state.get("remaining_steps", -1)) == remaining, label + " preserves the movement suffix")
	_expect(game.state.get("route_options", []) == [], label + " clears route choices while bank is open")
	var pending_movement: Variant = game.state.get("pending_movement", null)
	var movement_ok: bool = typeof(pending_movement) == TYPE_DICTIONARY and int(pending_movement.get("player_id", -1)) == 0 and int(pending_movement.get("current_node", -1)) == node_id and int(pending_movement.get("previous_node", -1)) == int(game.state.players[0].get("previous_position", -2))
	_expect(movement_ok, label + " keeps the parked movement continuation")
	return movement_ok


func _test_v7_attached_god_follows_bank() -> void:
	var game: Object = _new_game(V7_OPTIONS, 13521)
	if game == null:
		return
	_prepare_roll(game)
	game.state.god_objects = [{"id": 12, "node": 0, "owner": 0, "days": 7}]
	game.state.players[0]["god_id"] = 12
	if not _arm_two_step_roll(game, "v7 attached god"):
		return
	var rolled: Dictionary = game.roll()
	_expect(bool(rolled.get("ok", false)), "v7 attached god roll reaches the bank")
	if not _pending_pass(game, 1, 1, "v7 attached god"):
		return
	var actor: Dictionary = game.state.god_objects[0]
	_expect(int(actor.get("owner", -1)) == 0, "attached god keeps its owner at the bank pause")
	# The current RED is the missing sync on admission: an attached god must
	# follow the player before this pending save is exposed to persistence.
	_expect(int(actor.get("node", -1)) == 1, "attached god follows the player onto the bank node")
	_expect_valid_save(game, "v7 attached god pending save")


func _test_v7_unbound_god_deferred_until_resume() -> void:
	var game: Object = _new_game(V7_OPTIONS, 13522)
	if game == null:
		return
	_prepare_roll(game)
	game.state.god_objects = [{"id": 12, "node": 1, "owner": -1, "days": 0}]
	if not _arm_two_step_roll(game, "v7 unbound god"):
		return
	var rolled: Dictionary = game.roll()
	_expect(bool(rolled.get("ok", false)), "v7 unbound god roll reaches the bank")
	if not _pending_pass(game, 1, 1, "v7 unbound god"):
		return
	var before_resume: Dictionary = game.state.god_objects[0]
	_expect(int(before_resume.get("node", -1)) == 1 and int(before_resume.get("owner", -1)) == -1, "unbound god stays on the bank while ATM is open")
	_expect(_event_count(game, "god_attached") == 0, "unbound god is not encountered before ATM close")
	var paused_rng: String = str(game.to_dict().get("rng_state_text", ""))
	_expect_valid_save(game, "v7 unbound god pending save")
	var saved_json: String = game.to_json()
	var restored: Object = Game.from_dict(JSON.parse_string(saved_json))
	_expect(restored != null, "v7 unbound god pending JSON restores")
	if restored == null:
		return
	_expect(restored.to_json() == saved_json, "v7 unbound god pending JSON roundtrips exactly")
	_expect(str(restored.to_dict().get("rng_state_text", "")) == paused_rng, "bank pause keeps RNG stable")

	var first_resume: Dictionary = game.resume_bank_visit()
	var second_resume: Dictionary = restored.resume_bank_visit()
	_expect(bool(first_resume.get("ok", false)) and bool(second_resume.get("ok", false)), "fresh and restored unbound gods resume")
	_expect(game.to_json() == restored.to_json(), "fresh and restored god continuations are identical")
	_expect(game.state.get("pending_bank_visit", {}).is_empty(), "unbound god resume consumes the bank token")
	_expect(_event_count(game, "god_attached") == 1, "unbound god is encountered exactly once after resume")
	var attached: Dictionary = game.state.god_objects[0]
	_expect(int(game.state.players[0].get("god_id", 0)) == 12 and int(attached.get("owner", -1)) == 0, "resumed god attaches to the moving player")
	_expect(int(attached.get("node", -1)) == int(game.state.players[0].get("position", -2)), "attached god follows the resumed suffix")
	_expect(int(game.state.players[0].get("position", -1)) == 2, "unbound god resume reaches the points landing")


func _test_v7_roadblock_deferred_until_resume() -> void:
	var game: Object = _new_game(V7_OPTIONS, 13523)
	if game == null:
		return
	_prepare_roll(game)
	var placement: Dictionary = game.choose_action("use_tool", {"tool_id": "路障", "tile_id": 1})
	_expect(bool(placement.get("ok", false)), "v7 roadblock places on the bank road")
	if not bool(placement.get("ok", false)):
		return
	if not _arm_two_step_roll(game, "v7 bank roadblock"):
		return
	var rolled: Dictionary = game.roll()
	_expect(bool(rolled.get("ok", false)), "v7 roadblock roll reaches the bank")
	if not _pending_pass(game, 1, 1, "v7 bank roadblock"):
		return
	_expect(game.state.roadblocks.has("1"), "roadblock remains while ATM is open")
	_expect(_event_count(game, "roadblock_hit") == 0, "roadblock waits for bank resume")
	var saved_json: String = game.to_json()
	_expect_valid_save(game, "v7 bank roadblock pending save")
	var restored: Object = Game.from_dict(JSON.parse_string(saved_json))
	_expect(restored != null, "v7 bank roadblock pending JSON restores")
	if restored == null:
		return
	var first_resume: Dictionary = game.resume_bank_visit()
	var second_resume: Dictionary = restored.resume_bank_visit()
	_expect(bool(first_resume.get("ok", false)) and bool(second_resume.get("ok", false)), "fresh and restored roadblocks resume")
	_expect(game.to_json() == restored.to_json(), "fresh and restored roadblock continuations are identical")
	_expect(not game.state.roadblocks.has("1"), "roadblock is consumed after bank resume")
	_expect(_event_count(game, "roadblock_hit") == 1, "roadblock collision is recorded exactly once")
	var landing_token: Variant = game.state.get("pending_bank_visit", null)
	var landing_token_ok: bool = typeof(landing_token) == TYPE_DICTIONARY and landing_token.get("kind", "") == "landing" and int(landing_token.get("player_id", -1)) == 0 and int(landing_token.get("node_id", -1)) == 1
	_expect(landing_token_ok, "roadblock resume exposes the exact bank landing token")
	_expect(int(game.state.get("remaining_steps", -1)) == 0, "roadblock landing has no remaining movement")
	_expect(game.state.get("pending_movement", {}) == {}, "roadblock landing clears pending movement")
	_expect(str(game.state.get("phase", "")) == "await_action" and game.state.get("bank_landing", false) == true, "roadblock landing returns to the action phase")
	var after_resume: String = game.to_json()
	var repeated: Dictionary = game.resume_bank_visit()
	_expect(not bool(repeated.get("ok", false)) and game.to_json() == after_resume, "duplicate roadblock resume is rejected atomically")
	var completed: Dictionary = game.complete_bank_visit()
	var restored_completed: Dictionary = restored.complete_bank_visit()
	_expect(bool(completed.get("ok", false)) and bool(restored_completed.get("ok", false)), "roadblock landing completes after resume")
	_expect(game.to_json() == restored.to_json(), "fresh and restored roadblock completions are identical")
	_expect(game.state.get("pending_bank_visit", {}).is_empty(), "roadblock completion consumes the landing token")
	_expect(str(game.state.get("phase", "")) == "await_action" and game.state.action_options.has("end_turn"), "roadblock completion restores normal action options")


func _test_v9_carried_bomb_deferred_until_resume() -> void:
	var game: Object = _new_game(V9_OPTIONS, 13524)
	if game == null:
		return
	_prepare_roll(game)
	var bomb_supply_before: int = int(game.state.inventory_supply.tools.get("定時炸彈", -1))
	game.state.players[0].tools.erase("定時炸彈")
	game.state.players[0]["bomb_steps"] = 1
	if not _arm_two_step_roll(game, "v9 carried bomb"):
		return
	var rolled: Dictionary = game.roll()
	_expect(bool(rolled.get("ok", false)), "v9 carried bomb roll reaches the bank")
	if not _pending_pass(game, 1, 1, "v9 carried bomb"):
		return
	_expect(int(game.state.players[0].get("bomb_steps", -1)) == 1, "carried bomb countdown is untouched while ATM is open")
	_expect(_event_count(game, "bomb_countdown") == 0 and _event_count(game, "bomb_exploded") == 0, "carried bomb has no effect before bank resume")
	_expect_valid_save(game, "v9 carried bomb pending save")
	var saved_json: String = game.to_json()
	var restored: Object = Game.from_dict(JSON.parse_string(saved_json))
	_expect(restored != null, "v9 carried bomb pending JSON restores")
	if restored == null:
		return
	var first_resume: Dictionary = game.resume_bank_visit()
	var second_resume: Dictionary = restored.resume_bank_visit()
	_expect(bool(first_resume.get("ok", false)) and bool(second_resume.get("ok", false)), "fresh and restored carried bombs resume")
	_expect(game.to_json() == restored.to_json(), "fresh and restored bomb continuations are identical")
	_expect(game.state.get("pending_bank_visit", {}).is_empty(), "carried bomb resume consumes the bank token")
	_expect(_event_count(game, "bomb_countdown") == 1 and _event_count(game, "bomb_exploded") == 1, "carried bomb countdown and explosion happen exactly once")
	_expect(int(game.state.players[0].get("bomb_steps", -1)) == 0, "explosion clears the carried bomb")
	_expect(int(game.state.players[0].get("hospital_days", -1)) == 5, "bank bomb explosion admits five hospital days")
	_expect(int(game.state.players[0].get("position", -1)) == 7, "bank bomb explosion uses the canonical hospital node")
	_expect(int(game.state.inventory_supply.tools.get("定時炸彈", -1)) == bomb_supply_before + 1, "exploded bomb returns to the finite supply")
	_expect_valid_save(game, "v9 carried bomb post-resume save")
	var after_resume: String = game.to_json()
	var repeated: Dictionary = game.resume_bank_visit()
	_expect(not bool(repeated.get("ok", false)) and game.to_json() == after_resume, "duplicate carried bomb resume is rejected atomically")


func _test_v9_ground_objects_survive_bank_pauses() -> void:
	var first: Object = _new_game(V9_OPTIONS, 13525)
	if first == null:
		return
	_prepare_roll(first)
	var mine: Dictionary = first.choose_action("use_tool", {"tool_id": "地雷", "tile_id": 1})
	var timed_bomb: Dictionary = first.choose_action("use_tool", {"tool_id": "定時炸彈", "tile_id": 3})
	_expect(bool(mine.get("ok", false)) and bool(timed_bomb.get("ok", false)), "v9 bank ground objects place on separate bank nodes")
	if not bool(mine.get("ok", false)) or not bool(timed_bomb.get("ok", false)):
		return
	if not _arm_two_step_roll(first, "v9 first ground object bank", 4):
		return
	var rolled: Dictionary = first.roll()
	_expect(bool(rolled.get("ok", false)), "v9 first ground object roll reaches the first bank")
	if not _pending_pass(first, 1, 3, "v9 first ground object"):
		return
	_expect(first.state.ground_hazards.get("1", {}).get("kind", "") == "mine", "mine remains under the bank pause")
	_expect_valid_save(first, "v9 mine and bank overlap pending save")
	var first_json: String = first.to_json()
	var first_restored: Object = Game.from_dict(JSON.parse_string(first_json))
	_expect(first_restored != null, "v9 first ground object pending JSON restores")
	if first_restored == null:
		return
	var first_resume: Dictionary = first.resume_bank_visit()
	var first_restored_resume: Dictionary = first_restored.resume_bank_visit()
	_expect(bool(first_resume.get("ok", false)) and bool(first_restored_resume.get("ok", false)), "fresh and restored first bank pauses resume")
	_expect(first.to_json() == first_restored.to_json(), "first ground object continuation is deterministic")
	_expect(first.state.get("phase", "") == "await_route" and first.state.route_options == [3, 4] and int(first.state.get("remaining_steps", -1)) == 2, "first bank resume preserves the later branch")

	# Select the second bank on both copies.  The timed bomb is then at the
	# moving actor's bank node while the second pass token is persisted.
	var first_route: Dictionary = first.choose_route(3)
	var restored_route: Dictionary = first_restored.choose_route(3)
	_expect(bool(first_route.get("ok", false)) and bool(restored_route.get("ok", false)), "second bank route is selectable after resume")
	if not _pending_pass(first, 3, 1, "v9 second ground object"):
		return
	if not _pending_pass(first_restored, 3, 1, "v9 restored second ground object"):
		return
	_expect(first.state.ground_hazards.get("3", {}).get("kind", "") == "timed_bomb", "timed bomb remains under the second bank pause")
	_expect_valid_save(first, "v9 timed bomb and bank overlap pending save")
	var second_json: String = first.to_json()
	var second_restored: Object = Game.from_dict(JSON.parse_string(second_json))
	_expect(second_restored != null, "v9 second ground object pending JSON restores")
	if second_restored == null:
		return
	var second_resume: Dictionary = first.resume_bank_visit()
	var second_restored_resume: Dictionary = second_restored.resume_bank_visit()
	_expect(bool(second_resume.get("ok", false)) and bool(second_restored_resume.get("ok", false)), "fresh and restored second bank pauses resume")
	_expect(first.to_json() == second_restored.to_json(), "second ground object continuation is deterministic")
	_expect(first.state.ground_hazards.get("1", {}).get("kind", "") == "mine" and first.state.ground_hazards.get("3", {}).get("kind", "") == "timed_bomb", "ground objects survive both bank pass resumes")


func _test_pass_withdraw_then_property_fee() -> void:
	var game: Object = _new_game(V7_OPTIONS, 13526)
	if game == null:
		return
	_prepare_roll(game)
	var property: Dictionary = game.state.board[4]
	property["owner"] = 1
	property["building_level"] = 1
	property["rent"] = 250
	property["base_rent"] = 100
	property["rent_by_level"] = [100, 250, 600, 1200, 2400, 4800]
	game.state.players[1]["properties"] = [4]
	game._recalculate_property_values()
	if not _arm_two_step_roll(game, "v7 withdraw before property fee"):
		return
	# A three-step remote roll is needed here: bank 1, point 2, then the branch
	# at point 2 can select the owned property 4.  The setup check above covers
	# the required pre-roll contract; replace only the deterministic die face for
	# this optional longer suffix.
	game.state.pending_remote_dice = {"player_id": 0, "value": 3}
	game._set_action_options(0)
	var pre_roll_validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(pre_roll_validation.get("ok", false)), "v7 withdraw-before-fee setup validates before roll")
	var rolled: Dictionary = game.roll()
	_expect(bool(rolled.get("ok", false)), "v7 withdraw-before-fee roll reaches the bank")
	if not _pending_pass(game, 1, 2, "v7 withdraw before property fee"):
		return
	var deposit_before: int = int(game.state.players[0].get("deposit", -1))
	var cash_before: int = int(game.state.players[0].get("cash", -1))
	var withdrawal: Dictionary = game.choose_action("withdraw", {"amount": 1000})
	_expect(bool(withdrawal.get("ok", false)), "pass bank permits withdrawal before suffix")
	_expect(int(game.state.players[0].get("deposit", -1)) == deposit_before - 1000 and int(game.state.players[0].get("cash", -1)) == cash_before + 1000, "pass withdrawal updates balances before suffix")
	var resumed: Dictionary = game.resume_bank_visit()
	_expect(bool(resumed.get("ok", false)), "withdraw-before-fee bank resumes")
	_expect(game.state.get("phase", "") == "await_route" and game.state.route_options == [3, 4], "withdraw-before-fee resume preserves property branch")
	var property_route: Dictionary = game.choose_route(4)
	_expect(bool(property_route.get("ok", false)), "withdraw-before-fee chooses owned property")
	_expect(_event_count_with_field(game, "payment", "reason", "rent") == 1, "later property fee is charged exactly once")
	_expect(int(game.state.players[0].get("deposit", -1)) == deposit_before - 1000, "later property fee does not consume the prior withdrawal twice")
	_expect_valid_save(game, "withdraw-before-fee post-landing save")
