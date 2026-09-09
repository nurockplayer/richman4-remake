extends SceneTree

## Issue #65 frozen regression seed.
##
## A destructive building card can leave a God 9 AI's enemy landing at level
## zero before end_turn applies the angel effect.  The AI must decide about the
## engineering vehicle from the final landed state, so the expected result is
## one engineering tool spent and a level-zero final landing.  This test keeps
## the fixture on the existing v13 building-card/research graph and exercises
## only the public run_ai_turn/end_turn boundaries.
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")

const ENGINEERING_TOOL := "工程車"
const ENGINEERING_VEHICLE := "engineering"
const GOD9 := 9
const GOD9_DAYS := 7

var checks: int = 0
var failures: int = 0
var fixture_failures: int = 0


func _initialize() -> void:
	var case_index: int = 0
	for kind in ["property", "facility"]:
		for card_id in ["惡魔", "怪獸"]:
			_test_god9_ai_landing(card_id, kind, 13100 + case_index)
			case_index += 1
	_test_human_end_turn_does_not_autoactivate()
	for card_id in ["惡魔", "怪獸"]:
		_test_no_god_destructive_landing(card_id, 13110 + case_index)
		case_index += 1
	print("Engineering vehicle landing AI checks: %d, failures: %d, fixture_failures: %d" % [checks, failures, fixture_failures])
	quit(1 if failures or fixture_failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_fixture(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		fixture_failures += 1
		push_error("FIXTURE FAIL: " + message)


func _return_actor_inventory(game: Object) -> void:
	var actor: Dictionary = game.state["players"][0]
	for card_value in actor.get("cards", []).duplicate(true):
		var returned_card: Dictionary = Inventory.consume_card(game.state["inventory_supply"], actor["cards"], str(card_value))
		_expect_fixture(bool(returned_card.get("ok", false)), "fixture returns opening card")
	for tool_value in actor.get("tools", {}).keys().duplicate():
		var tool_id: String = str(tool_value)
		var quantity: int = int(actor["tools"].get(tool_id, 0))
		if quantity <= 0:
			continue
		var returned_tool: Dictionary = Inventory.consume_tool(game.state["inventory_supply"], actor["tools"], tool_id, quantity)
		_expect_fixture(bool(returned_tool.get("ok", false)), "fixture returns opening tool " + tool_id)


func _clear_landings(game: Object) -> void:
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		player_value["properties"] = []
		player_value["god_id"] = 0
	for tile_value in game.state.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = tile_value
		if str(tile.get("kind", "")) == "property":
			tile["owner"] = -1
			tile["building_level"] = 0
			tile["is_chain_store"] = false
			game._update_tile_rent(tile)
	var facility_sources: Dictionary = {}
	for tile_value in game.state.get("board", []):
		if typeof(tile_value) == TYPE_DICTIONARY and str(tile_value.get("kind", "")) == "facility":
			facility_sources[int(tile_value.get("source_object_id", -1))] = true
	for source_id in facility_sources.keys():
		game._update_facility_records(int(source_id), {"owner": -1, "building_level": 0, "facility_type": 0, "facility_state": 0, "research_tool": 0, "research_turns": 0})
	game.state["god_objects"] = []
	game._recalculate_property_values()


func _target_index(game: Object, kind: String) -> int:
	for index in range(game.state.get("board", []).size()):
		var tile_value: Variant = game.state["board"][index]
		if typeof(tile_value) == TYPE_DICTIONARY and str(tile_value.get("kind", "")) == kind:
			return index
	return -1


func _set_enemy_landing(game: Object, kind: String, target_id: int, level: int = 3) -> void:
	var enemy: Dictionary = game.state["players"][1]
	enemy["properties"] = []
	var tile: Dictionary = game.state["board"][target_id]
	if kind == "facility":
		var source_id: int = int(tile.get("source_object_id", -1))
		game._update_facility_records(source_id, {"owner": 1, "building_level": level, "facility_type": 1, "facility_state": 0, "research_tool": 0, "research_turns": 0})
		enemy["properties"] = [int(tile.get("facility_node_index", target_id))]
	else:
		tile["owner"] = 1
		tile["building_level"] = level
		tile["is_chain_store"] = false
		tile["group"] = "issue65-enemy"
		game._update_tile_rent(tile)
		enemy["properties"] = [target_id]
	game._recalculate_property_values()


func _set_turn_boundary(game: Object, target_id: int) -> void:
	var actor: Dictionary = game.state["players"][0]
	actor["position"] = target_id
	actor["previous_position"] = -1
	actor["cash"] = 0
	actor["vehicle"] = "walking"
	actor["dice_count"] = 1
	actor.erase("engineering_vehicle")
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = true
	game.state["research_action_used"] = true
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state["bank_access"] = false
	game.state["bank_landing"] = false
	game.state["doubles_count"] = 0
	game._set_action_options(0)


func _set_god9(game: Object, target_id: int) -> void:
	game.state["god_objects"] = [{"id": GOD9, "node": target_id, "owner": 0, "days": GOD9_DAYS}]
	game.state["players"][0]["god_id"] = GOD9


func _stage_case(seed_value: int, card_id: String, kind: String, ai_enabled: bool, with_god9: bool) -> Dictionary:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.new_game_options())
	_expect_fixture(game != null, "v13 building/research fixture starts")
	if game == null:
		return {}
	_return_actor_inventory(game)
	_clear_landings(game)
	var target_id: int = _target_index(game, kind)
	_expect_fixture(target_id >= 0, kind + " fixture has a target landing")
	if target_id < 0:
		return {}
	_set_enemy_landing(game, kind, target_id)
	var actor: Dictionary = game.state["players"][0]
	var card_result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], actor["cards"], card_id)
	_expect_fixture(bool(card_result.get("ok", false)), "fixture grants finite " + card_id)
	var tool_result: Dictionary = Inventory.grant_tool(game.state["inventory_supply"], actor["tools"], ENGINEERING_TOOL, 2)
	_expect_fixture(bool(tool_result.get("ok", false)), "fixture stages two engineering tools")
	for player_id in range(4):
		_expect_fixture(bool(game.set_player_ai(player_id, player_id == 0 and ai_enabled)), "fixture sets player AI mode")
	_set_turn_boundary(game, target_id)
	if with_god9:
		_set_god9(game, target_id)
	else:
		game.state["god_objects"] = []
		game.state["players"][0]["god_id"] = 0
	game._set_action_options(0)
	return {"game": game, "target_id": target_id, "kind": kind}


func _assert_god_metadata(game: Object, target_id: int, label: String) -> void:
	var gods: Variant = game.state.get("god_objects", null)
	_expect_fixture(typeof(gods) == TYPE_ARRAY and gods.size() == 1, label + " stores one God 9 actor")
	if typeof(gods) != TYPE_ARRAY or gods.size() != 1:
		return
	var actor: Variant = gods[0]
	_expect_fixture(typeof(actor) == TYPE_DICTIONARY, label + " God 9 actor is a dictionary")
	if typeof(actor) != TYPE_DICTIONARY:
		return
	for key in ["id", "node", "owner", "days"]:
		_expect_fixture(actor.has(key), label + " God 9 metadata includes " + key)
	_expect_fixture(int(actor.get("id", -1)) == GOD9 and int(actor.get("node", -1)) == target_id and int(actor.get("owner", -1)) == 0 and int(actor.get("days", -1)) == GOD9_DAYS, label + " God 9 metadata follows its owner")
	_expect_fixture(int(game.state["players"][0].get("god_id", -1)) == GOD9, label + " player points to God 9")


func _assert_pre_round_trip(game: Object, label: String, target_id: int, with_god9: bool) -> Object:
	var before: Dictionary = game.to_dict()
	var validation: Dictionary = Game.validate_save(before)
	_expect_fixture(bool(validation.get("ok", false)), label + " fixture validates before turn: " + str(validation.get("errors", [])))
	if with_god9:
		_assert_god_metadata(game, target_id, label)
	var parsed: Variant = JSON.parse_string(game.to_json())
	_expect_fixture(parsed is Dictionary, label + " fixture JSON parses")
	var mirror: Object = Game.from_dict(parsed if parsed is Dictionary else {})
	_expect_fixture(mirror != null, label + " fixture reloads from JSON")
	if mirror != null:
		var mirror_validation: Dictionary = Game.validate_save(mirror.to_dict())
		_expect_fixture(bool(mirror_validation.get("ok", false)), label + " reloaded fixture validates: " + str(mirror_validation.get("errors", [])))
		_expect_fixture(mirror.to_json() == game.to_json(), label + " fixture JSON round trips exactly")
	return mirror


func _assert_post_round_trip(game: Object, mirror: Object, label: String, replay_ai: bool = true) -> void:
	var after_validation: Dictionary = Game.validate_save(game.to_dict())
	_expect_fixture(bool(after_validation.get("ok", false)), label + " final state validates: " + str(after_validation.get("errors", [])))
	var after_parsed: Variant = JSON.parse_string(game.to_json())
	_expect_fixture(after_parsed is Dictionary, label + " final JSON parses")
	var after_mirror: Object = Game.from_dict(after_parsed if after_parsed is Dictionary else {})
	_expect_fixture(after_mirror != null, label + " final state reloads from JSON")
	if after_mirror != null:
		var reloaded_validation: Dictionary = Game.validate_save(after_mirror.to_dict())
		_expect_fixture(bool(reloaded_validation.get("ok", false)), label + " reloaded final state validates: " + str(reloaded_validation.get("errors", [])))
		_expect_fixture(after_mirror.to_json() == game.to_json(), label + " final JSON round trips exactly")
	if mirror != null and replay_ai:
		var replay: Dictionary = mirror.run_ai_turn()
		_expect_fixture(bool(replay.get("ok", false)) and bool(replay.get("completed", false)), label + " JSON-restored AI turn completes")
		_expect_fixture(mirror.to_json() == game.to_json(), label + " JSON-restored AI state matches exactly")


func _latest_event(game: Object, event_type: String) -> Dictionary:
	var events: Variant = game.state.get("event_log", [])
	if typeof(events) != TYPE_ARRAY:
		return {}
	for index in range(events.size() - 1, -1, -1):
		if typeof(events[index]) == TYPE_DICTIONARY and str(events[index].get("type", "")) == event_type:
			return events[index]
	return {}


func _test_god9_ai_landing(card_id: String, kind: String, seed_value: int) -> void:
	var label := "God9 AI " + kind + " " + card_id
	var staged: Dictionary = _stage_case(seed_value, card_id, kind, true, true)
	if staged.is_empty():
		return
	var game: Object = staged["game"]
	var target_id: int = int(staged["target_id"])
	var mirror: Object = _assert_pre_round_trip(game, label, target_id, true)
	var result: Dictionary = game.run_ai_turn()
	_expect(bool(result.get("ok", false)) and bool(result.get("completed", false)), label + " completes through run_ai_turn")
	var card_event: Dictionary = _latest_event(game, "card_used")
	_expect(str(card_event.get("card_id", "")) == card_id and int(card_event.get("player_id", -1)) == 0, label + " uses the destructive card")
	var god_event: Dictionary = _latest_event(game, "god_property_effect")
	_expect(int(god_event.get("god_id", -1)) == GOD9 and str(god_event.get("effect", "")) == "angel_raise", label + " applies the complete God 9 effect")
	var target: Dictionary = game.state["board"][target_id]
	if kind == "facility":
		target = game._facility_record(target_id)
	_expect(int(target.get("building_level", -1)) == 0, label + " ends with a level-zero enemy landing")
	_expect(int(game.state["players"][0]["tools"].get(ENGINEERING_TOOL, 0)) == 1, label + " spends exactly one engineering tool")
	_expect(str(game.state["players"][0].get("vehicle", "")) == ENGINEERING_VEHICLE, label + " leaves the AI in engineering vehicle mode")
	var engineering_event: Dictionary = _latest_event(game, "tool_used")
	_expect(str(engineering_event.get("tool_id", "")) == ENGINEERING_TOOL and int(engineering_event.get("player_id", -1)) == 0, label + " records engineering activation")
	var demolition_event: Dictionary = _latest_event(game, "engineering_demolition")
	_expect(int(demolition_event.get("to_level", -1)) == 0 and int(demolition_event.get("tile_id", -1)) == target_id, label + " records final landing demolition")
	_assert_post_round_trip(game, mirror, label)


func _test_human_end_turn_does_not_autoactivate() -> void:
	var label := "human God9 end_turn"
	var staged: Dictionary = _stage_case(13120, "惡魔", "property", false, true)
	if staged.is_empty():
		return
	var game: Object = staged["game"]
	var target_id: int = int(staged["target_id"])
	var mirror: Object = _assert_pre_round_trip(game, label, target_id, true)
	var use_result: Dictionary = game.choose_action("use_card", {"card_id": "惡魔", "tile_id": target_id})
	_expect(bool(use_result.get("ok", false)), label + " uses the destructive card through the human action boundary")
	_expect(int(game.state["board"][target_id].get("building_level", -1)) == 0, label + " clears the enemy building before end_turn")
	var card_validation: Dictionary = Game.validate_save(game.to_dict())
	_expect_fixture(bool(card_validation.get("ok", false)), label + " post-card state validates: " + str(card_validation.get("errors", [])))
	var end_result: Dictionary = game.end_turn()
	_expect(bool(end_result.get("ok", false)), label + " ends through public end_turn")
	_expect(int(game.state["board"][target_id].get("building_level", -1)) == 1, label + " applies God 9 without an engineering follow-up")
	_expect(int(game.state["players"][0]["tools"].get(ENGINEERING_TOOL, 0)) == 2, label + " preserves both engineering tools")
	_expect(str(game.state["players"][0].get("vehicle", "")) == "walking", label + " does not autoactivate engineering")
	_expect(game.state["players"][0].get("engineering_vehicle", null) == null, label + " leaves no engineering metadata")
	_expect(_latest_event(game, "engineering_demolition").is_empty(), label + " emits no engineering demolition")
	_assert_post_round_trip(game, mirror, label, false)


func _test_no_god_destructive_landing(card_id: String, seed_value: int) -> void:
	var label := "no-God AI property " + card_id
	var staged: Dictionary = _stage_case(seed_value, card_id, "property", true, false)
	if staged.is_empty():
		return
	var game: Object = staged["game"]
	var target_id: int = int(staged["target_id"])
	var mirror: Object = _assert_pre_round_trip(game, label, target_id, false)
	var result: Dictionary = game.run_ai_turn()
	_expect(bool(result.get("ok", false)) and bool(result.get("completed", false)), label + " completes through run_ai_turn")
	_expect(int(game.state["board"][target_id].get("building_level", -1)) == 0, label + " keeps the card-cleared landing at level zero")
	_expect(int(game.state["players"][0]["tools"].get(ENGINEERING_TOOL, 0)) == 2, label + " preserves both engineering tools")
	_expect(str(game.state["players"][0].get("vehicle", "")) == "walking", label + " does not activate engineering after a completed destructive card")
	_expect(_latest_event(game, "engineering_demolition").is_empty(), label + " emits no wasted engineering demolition")
	_assert_post_round_trip(game, mirror, label)
