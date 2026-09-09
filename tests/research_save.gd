extends SceneTree

## Issue #39 save contract for the original research extension.
##
## The fixture is source-shaped but asset-free.  Until the v12 constructor is
## implemented, the helpers deliberately stamp a v11 predecessor so the
## assertions remain executable and report the missing versioned contract.
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/research_fixture.gd")

const RESEARCH_SAVE_VERSION := 12

var checks: int = 0
var failures: int = 0
var bootstrap_version_red: int = 0
var bootstrap_reported: bool = false


func _initialize() -> void:
	_test_v12_round_trip_and_continuation()
	_test_v11_compatibility()
	_test_strict_v12_fields()
	print("Original research save checks: %d, failures: %d, bootstrap_version_red: %d" % [checks, failures, bootstrap_version_red])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_v12_game(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.new_game_options())
	if game != null:
		return game
	bootstrap_version_red += 1
	if not bootstrap_reported:
		bootstrap_reported = true
		print("BOOTSTRAP VERSION RED: v12 constructor is unavailable; save checks use a v11 instance stamped v12/original_research in the test harness")
	var legacy: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.v11_game_options())
	_expect(legacy != null, "v11 predecessor fixture bootstraps the v12 save harness")
	if legacy == null:
		return null
	legacy.state["version"] = RESEARCH_SAVE_VERSION
	legacy.state["original_research"] = true
	legacy.state["research_action_used"] = false
	for tile_value in legacy.state.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility":
			continue
		tile_value["research_tool"] = 0
		tile_value["research_turns"] = 0
	legacy._sync_state()
	return legacy


func _new_v11_game(seed_value: int) -> Object:
	return Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.v11_game_options())


func _facility_indices(game: Object, source_id: int) -> Array:
	var result: Array = []
	for index in range(game.state.get("board", []).size()):
		var tile: Dictionary = game.state["board"][index]
		if tile.get("kind", "") == "facility" and int(tile.get("source_object_id", -1)) == source_id:
			result.append(index)
	return result


func _set_facility(game: Object, source_id: int, owner_id: int, level: int, facility_type: int, research_tool: int, research_turns: int) -> void:
	var indices: Array = _facility_indices(game, source_id)
	_expect(not indices.is_empty(), "save fixture contains facility source %d" % source_id)
	if indices.is_empty():
		return
	var canonical: int = int(game.state["board"][int(indices[0])].get("facility_node_index", int(indices[0])))
	for index_value in indices:
		var tile: Dictionary = game.state["board"][int(index_value)]
		tile["owner"] = owner_id
		tile["building_level"] = level
		tile["facility_type"] = facility_type
		tile["facility_state"] = 0
		tile["research_tool"] = research_tool
		tile["research_turns"] = research_turns
	for player in game.state.get("players", []):
		var properties: Array = player.get("properties", []).duplicate(true)
		while properties.has(canonical):
			properties.erase(canonical)
		if int(player.get("id", -1)) == owner_id and owner_id >= 0:
			properties.append(canonical)
		player["properties"] = properties
	game._recalculate_property_values()


func _prepare_landing(game: Object, player_id: int, position: int) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["remaining_steps"] = 0
	game.state["route_options"] = []
	game.state["pending_movement"] = {}
	game.state["players"][player_id]["position"] = position
	game.state["players"][player_id]["previous_position"] = -1
	game._set_action_options(player_id)


func _prepare_non_action_turn(game: Object, player_id: int) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = "await_action"
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game._set_action_options(player_id)


func _research_aliases(data: Dictionary, source_id: int) -> Array:
	var result: Array = []
	var board: Array = data.get("board", [])
	for index in range(board.size()):
		var tile: Variant = board[index]
		if typeof(tile) == TYPE_DICTIONARY and tile.get("kind", "") == "facility" and int(tile.get("source_object_id", -1)) == source_id:
			result.append(index)
	return result


func _test_v12_round_trip_and_continuation() -> void:
	var game: Object = _new_v12_game(4701)
	_expect(game != null, "v12 research save fixture starts")
	if game == null:
		return
	_set_facility(game, 1, 0, 3, 4, 0, 0)
	_prepare_landing(game, 0, 1)
	var scheduled: Dictionary = game.choose_action("choose_research", {"tool_id": "傳送機"})
	_expect(bool(scheduled.get("ok", false)), "scheduled research can be saved through public action")
	var data: Dictionary = game.to_dict()
	_expect_equal(int(data.get("version", -1)), RESEARCH_SAVE_VERSION, "research save version is twelve")
	_expect_equal(data.get("original_research", false), true, "research save carries original research marker")
	_expect(typeof(data.get("research_action_used", null)) == TYPE_BOOL, "research save carries action guard")
	_expect_equal(bool(data.get("research_action_used", false)), true, "scheduled research records action guard")
	var aliases: Array = _research_aliases(data, 1)
	_expect(aliases.size() >= 2, "research save retains every facility entrance")
	for index_value in aliases:
		var tile: Dictionary = data["board"][int(index_value)]
		_expect_equal(int(tile.get("research_tool", -1)), 3, "scheduled research save keeps product on every alias")
		_expect_equal(int(tile.get("research_turns", -1)), 5, "scheduled research save keeps countdown on every alias")
	var validation: Dictionary = Game.validate_save(data)
	_expect(bool(validation.get("ok", false)), "scheduled v12 research save validates: " + str(validation.get("errors", [])))
	var parsed: Variant = JSON.parse_string(game.to_json())
	_expect(parsed is Dictionary, "research save JSON parses")
	var restored: Object = Game.from_dict(parsed if parsed is Dictionary else {})
	_expect(restored != null, "scheduled v12 research save restores")
	if restored == null:
		return
	_expect_equal(restored.to_json(), game.to_json(), "scheduled research JSON round trip is exact")
	_prepare_non_action_turn(game, 0)
	_prepare_non_action_turn(restored, 0)
	var first_turn: Dictionary = game.end_turn()
	var resumed_turn: Dictionary = restored.end_turn()
	_expect(bool(first_turn.get("ok", false)) and bool(resumed_turn.get("ok", false)), "restored research save can continue through public end_turn")
	_expect_equal(restored.to_json(), game.to_json(), "research save continuation remains deterministic")


func _test_v11_compatibility() -> void:
	var legacy: Object = _new_v11_game(4702)
	_expect(legacy != null, "v11 predecessor save fixture starts")
	if legacy == null:
		return
	_expect_equal(int(legacy.state.get("version", -1)), 11, "v11 predecessor remains version eleven")
	_expect(not bool(legacy.state.get("original_research", false)), "v11 save has no original research marker")
	_expect(not legacy.state.has("research_action_used"), "v11 save has no research action guard")
	var legacy_data: Dictionary = legacy.to_dict()
	_expect(bool(Game.validate_save(legacy_data).get("ok", false)), "clean v11 save remains valid")
	var restored: Object = Game.from_dict(JSON.parse_string(legacy.to_json()))
	_expect(restored != null, "clean v11 save restores")
	if restored != null:
		_expect_equal(restored.to_json(), legacy.to_json(), "clean v11 JSON round trip is exact")
	var marked: Dictionary = legacy_data.duplicate(true)
	marked["original_research"] = true
	_expect(not bool(Game.validate_save(marked).get("ok", false)), "v11 plus research marker is rejected")
	_expect(Game.from_dict(marked) == null, "v11 plus research marker cannot restore")


func _test_strict_v12_fields() -> void:
	var game: Object = _new_v12_game(4703)
	_expect(game != null, "strict v12 save fixture starts")
	if game == null:
		return
	_set_facility(game, 1, 0, 2, 4, 2, 3)
	_prepare_landing(game, 0, 1)
	var valid: Dictionary = game.to_dict()
	_expect(bool(Game.validate_save(valid).get("ok", false)), "strict v12 fixture starts valid")
	var downgraded: Dictionary = valid.duplicate(true)
	for index_value in _research_aliases(downgraded, 1):
		downgraded["board"][int(index_value)]["building_level"] = 1
	_expect(bool(Game.validate_save(downgraded).get("ok", false)), "v12 accepts a pending job after a legal lab downgrade")
	_expect(Game.from_dict(downgraded) != null, "v12 restores a pending job after a legal lab downgrade")
	var marker_mutations: Array = ["missing_research", "false_research", "wrong_research_type", "missing_action", "wrong_action_type"]
	for mutation in marker_mutations:
		var malformed: Dictionary = valid.duplicate(true)
		match mutation:
			"missing_research": malformed.erase("original_research")
			"false_research": malformed["original_research"] = false
			"wrong_research_type": malformed["original_research"] = "yes"
			"missing_action": malformed.erase("research_action_used")
			"wrong_action_type": malformed["research_action_used"] = "yes"
		_expect(not bool(Game.validate_save(malformed).get("ok", false)), "v12 rejects research marker mutation: " + mutation)
		_expect(Game.from_dict(malformed) == null, "v12 rejects research marker JSON: " + mutation)

	var aliases: Array = _research_aliases(valid, 1)
	_expect(aliases.size() >= 2, "strict v12 fixture has aliased facility entries")
	if aliases.is_empty():
		return
	var field_mutations: Array = ["missing_tool", "wrong_tool_type", "tool_out_of_range", "missing_turns", "wrong_turns_type", "turns_out_of_range", "alias_mismatch", "empty_tool_with_countdown"]
	for mutation in field_mutations:
		var malformed: Dictionary = valid.duplicate(true)
		var first_index: int = int(aliases[0])
		match mutation:
			"missing_tool": malformed["board"][first_index].erase("research_tool")
			"wrong_tool_type": malformed["board"][first_index]["research_tool"] = "2"
			"tool_out_of_range": malformed["board"][first_index]["research_tool"] = 6
			"missing_turns": malformed["board"][first_index].erase("research_turns")
			"wrong_turns_type": malformed["board"][first_index]["research_turns"] = "3"
			"turns_out_of_range": malformed["board"][first_index]["research_turns"] = 6
			"alias_mismatch": malformed["board"][int(aliases[1])]["research_tool"] = 1
			"empty_tool_with_countdown": malformed["board"][first_index]["research_tool"] = 0
		if mutation == "empty_tool_with_countdown":
			malformed["board"][first_index]["research_turns"] = 1
		_expect(not bool(Game.validate_save(malformed).get("ok", false)), "v12 rejects research field mutation: " + mutation)
		_expect(Game.from_dict(malformed) == null, "v12 rejects research field JSON: " + mutation)
