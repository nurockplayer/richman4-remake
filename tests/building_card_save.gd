extends SceneTree

## Issue #44 save contract for the original 天使／惡魔／怪獸 building cards.
##
## The v13 constructor is attempted first.  While production is still v12,
## the fallback stamps a v12 game with the v13 marker so save validation and
## the public JSON boundary report their own RED instead of hiding behind the
## missing constructor.
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")

const BUILDING_CARD_SAVE_VERSION := 13
const V12_SAVE_VERSION := 12
const SAVE_PREREQUISITES := [
	"original_facilities",
	"original_gods",
	"original_companies",
	"original_statuses",
	"original_hazards",
	"original_property_cards",
	"original_remodel",
	"original_research",
]
const OPTION_PREREQUISITES := [
	"original_inventory",
	"original_facilities",
	"original_gods",
	"original_companies",
	"original_statuses",
	"original_hazards",
	"original_property_cards",
	"original_remodel",
	"original_research",
]

var checks := 0
var failures := 0
var bootstrap_version_red := 0
var bootstrap_reported := false


func _initialize() -> void:
	_test_v13_effect_save_round_trip_and_continuation()
	_test_v12_compatibility()
	_test_strict_v13_markers_and_prerequisites()
	_test_v13_constructor_option_guards()
	print("Original building-card save checks: %d, failures: %d, bootstrap_version_red: %d" % [checks, failures, bootstrap_version_red])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_v13_game(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.new_game_options())
	if game != null:
		return game
	bootstrap_version_red += 1
	if not bootstrap_reported:
		bootstrap_reported = true
		print("BOOTSTRAP VERSION RED: v13 constructor is unavailable; save checks use a v12 instance stamped v13/original_building_cards in the test harness")
	var legacy: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.v12_game_options())
	_expect(legacy != null, "v12 predecessor fixture bootstraps the v13 save harness")
	if legacy == null:
		return null
	legacy.state["version"] = BUILDING_CARD_SAVE_VERSION
	legacy.state["original_building_cards"] = true
	legacy._sync_state()
	return legacy


func _new_v12_game(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.v12_game_options())
	_expect(game != null, "v12 predecessor fixture starts")
	return game


func _prepare_action(game: Object, player_id: int, position: int, phase: String = "await_action") -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state["players"][player_id]["position"] = position
	game.state["players"][player_id]["previous_position"] = -1
	for candidate in game.state.get("players", []):
		candidate["hospital_days"] = 0
		candidate["prison_days"] = 0
		candidate["god_id"] = 0
	game.state["god_objects"] = []
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
	game.state["pending_remote_dice"] = {}
	game._set_action_options(player_id)


func _stage_card(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	_expect(bool(result.get("ok", false)), "save fixture stages " + card_id)
	if bool(result.get("ok", false)):
		# Granting inventory does not refresh the public action snapshot.
		game._set_action_options(player_id)
	return bool(result.get("ok", false))


func _set_owner(game: Object, tile_id: int, owner_id: int) -> void:
	var board: Array = game.state.get("board", [])
	if tile_id < 0 or tile_id >= board.size() or typeof(board[tile_id]) != TYPE_DICTIONARY:
		return
	var tile: Dictionary = board[tile_id]
	var asset_id := tile_id
	if tile.get("kind", "") == "facility":
		var source_id := int(tile.get("source_object_id", -1))
		asset_id = int(tile.get("facility_node_index", tile_id))
		for candidate_value in board:
			if typeof(candidate_value) == TYPE_DICTIONARY and candidate_value.get("kind", "") == "facility" and int(candidate_value.get("source_object_id", -1)) == source_id:
				candidate_value["owner"] = owner_id
	else:
		tile["owner"] = owner_id
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = player_value
		var properties: Array = player.get("properties", []).duplicate(true)
		while properties.has(asset_id):
			properties.erase(asset_id)
		player["properties"] = properties
	if owner_id >= 0 and owner_id < game.state.get("players", []).size():
		var owner_properties: Array = game.state["players"][owner_id].get("properties", []).duplicate(true)
		if not owner_properties.has(asset_id):
			owner_properties.append(asset_id)
		game.state["players"][owner_id]["properties"] = owner_properties


func _set_property_state(game: Object, tile_id: int, owner_id: int, level: int, chain: bool, group_name: String) -> void:
	_set_owner(game, tile_id, owner_id)
	var tile: Dictionary = game.state["board"][tile_id]
	tile["building_level"] = level
	tile["is_chain_store"] = chain
	tile["group"] = group_name
	game._update_tile_rent(tile)
	game._recalculate_property_values()


func _facility_indices(game: Object, source_id: int) -> Array:
	var result: Array = []
	for tile_value in game.state.get("board", []):
		if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "facility" and int(tile_value.get("source_object_id", -1)) == source_id:
			result.append(int(tile_value.get("index", -1)))
	return result


func _set_facility_state(game: Object, source_id: int, owner_id: int, level: int, facility_type: int, facility_state: int, research_tool: int, research_turns: int) -> void:
	var indices: Array = _facility_indices(game, source_id)
	_expect(not indices.is_empty(), "save fixture contains facility source %d" % source_id)
	for index_value in indices:
		var tile: Dictionary = game.state["board"][int(index_value)]
		tile["building_level"] = level
		tile["facility_type"] = facility_type
		tile["facility_state"] = facility_state
		tile["research_tool"] = research_tool
		tile["research_turns"] = research_turns
	if not indices.is_empty():
		_set_owner(game, int(indices[0]), owner_id)
	game._recalculate_property_values()


func _facility_snapshots(data: Dictionary, source_id: int) -> Array:
	var result: Array = []
	for tile_value in data.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility":
			continue
		if int(tile_value.get("source_object_id", -1)) != source_id:
			continue
		result.append({
			"owner": tile_value.get("owner", null),
			"building_level": tile_value.get("building_level", null),
			"facility_type": tile_value.get("facility_type", null),
			"facility_state": tile_value.get("facility_state", null),
			"research_tool": tile_value.get("research_tool", null),
			"research_turns": tile_value.get("research_turns", null),
		})
	return result


func _test_v13_effect_save_round_trip_and_continuation() -> void:
	var game: Object = _new_v13_game(7401)
	_expect(game != null, "v13 building-card save fixture starts")
	if game == null:
		return
	_expect_equal(int(game.state.get("version", -1)), BUILDING_CARD_SAVE_VERSION, "v13 save version is thirteen")
	_expect_equal(bool(game.state.get("original_building_cards", false)), true, "v13 save carries building-card marker")
	for flag in SAVE_PREREQUISITES:
		_expect(bool(game.state.get(flag, false)), "v13 save carries prerequisite marker: " + flag)

	_set_property_state(game, 2, 1, 4, false, "angel-save-group")
	_set_property_state(game, 3, 2, 1, true, "angel-save-group")
	_prepare_action(game, 0, 2)
	if _stage_card(game, 0, "天使"):
		var angel_result: Dictionary = game.choose_action("use_card", {"card_id": "天使", "tile_id": 2})
		_expect(bool(angel_result.get("ok", false)), "v13 Angel property effect reaches the save boundary")
		_expect_equal(int(game.state["board"][2].get("building_level", -1)), 5, "saved Angel property keeps the normal cap result")
		_expect_equal(int(game.state["board"][3].get("building_level", -1)), 1, "saved Angel property keeps the chain cap result")

	_set_facility_state(game, 2, 1, 3, 4, 0x51, 2, 3)
	_prepare_action(game, 0, 8)
	if _stage_card(game, 0, "天使"):
		var facility_result: Dictionary = game.choose_action("use_card", {"card_id": "天使", "tile_id": 8})
		_expect(bool(facility_result.get("ok", false)), "v13 Angel facility effect reaches the save boundary")
		for snapshot in _facility_snapshots(game.to_dict(), 2):
			_expect_equal(int(snapshot.get("building_level", -1)), 4, "saved Angel facility keeps its upgraded level")
			_expect_equal(int(snapshot.get("facility_type", -1)), 4, "saved Angel facility keeps the lab type")
			_expect_equal(int(snapshot.get("facility_state", -1)), 0x51, "saved Angel facility preserves status state")
			_expect_equal(int(snapshot.get("research_tool", -1)), 2, "saved Angel facility preserves research rank")
			_expect_equal(int(snapshot.get("research_turns", -1)), 3, "saved Angel facility preserves research countdown")

	var data: Dictionary = game.to_dict()
	_expect_equal(int(data["inventory_supply"]["cards"].get("天使", -1)), 2, "v13 save records the recycled Angel supply")
	_expect(not data["players"][0].get("cards", []).has("天使"), "v13 save records that the Angel cards were consumed")
	var last_event: Dictionary = data.get("last_event", {})
	_expect_equal(str(last_event.get("type", "")), "card_used", "v13 save retains the final card event")
	_expect_equal(str(last_event.get("card_id", "")), "天使", "v13 save retains the final card identifier")
	_expect(bool(Game.validate_save(data).get("ok", false)), "valid v13 building-card save validates: " + str(Game.validate_save(data).get("errors", [])))
	var parsed: Variant = JSON.parse_string(game.to_json())
	_expect(parsed is Dictionary, "v13 building-card save JSON parses")
	var restored: Object = Game.from_dict(parsed if parsed is Dictionary else {})
	_expect(restored != null, "v13 building-card save restores through from_dict")
	if restored == null:
		return
	_expect_equal(restored.to_json(), game.to_json(), "v13 building-card JSON round trip is exact")
	_expect_equal(_facility_snapshots(restored.to_dict(), 2), _facility_snapshots(data, 2), "v13 restored facility aliases retain all effect fields")
	_prepare_non_action_turn(game, 0)
	_prepare_non_action_turn(restored, 0)
	var original_turn: Dictionary = game.end_turn()
	var restored_turn: Dictionary = restored.end_turn()
	_expect(bool(original_turn.get("ok", false)) and bool(restored_turn.get("ok", false)), "restored v13 save continues through public end_turn")
	_expect_equal(restored.to_json(), game.to_json(), "v13 save continuation remains deterministic")


func _test_v12_compatibility() -> void:
	var legacy: Object = _new_v12_game(7402)
	if legacy == null:
		return
	_expect_equal(int(legacy.state.get("version", -1)), V12_SAVE_VERSION, "v12 predecessor remains version twelve")
	_expect(not bool(legacy.state.get("original_building_cards", false)), "v12 save has no building-card marker")
	var legacy_data: Dictionary = legacy.to_dict()
	_expect(bool(Game.validate_save(legacy_data).get("ok", false)), "clean v12 save remains valid")
	var restored: Object = Game.from_dict(JSON.parse_string(legacy.to_json()))
	_expect(restored != null, "clean v12 save restores")
	if restored != null:
		_expect_equal(restored.to_json(), legacy.to_json(), "clean v12 JSON round trip is exact")
	_expect(not legacy.item_is_implemented("card", "天使"), "v12 does not advertise 天使")
	_prepare_action(legacy, 0, 2)
	if _stage_card(legacy, 0, "天使"):
		var before: String = legacy.to_json()
		var result: Dictionary = legacy.choose_action("use_card", {"card_id": "天使", "tile_id": 2})
		_expect(not bool(result.get("ok", false)), "v12 rejects 天使 as unimplemented")
		_expect_equal(legacy.to_json(), before, "v12 天使 rejection is atomic")

	var marked: Dictionary = legacy_data.duplicate(true)
	marked["original_building_cards"] = true
	_expect(not bool(Game.validate_save(marked).get("ok", false)), "v12 plus building-card marker is rejected")
	_expect(Game.from_dict(marked) == null, "v12 plus building-card marker cannot restore")


func _test_strict_v13_markers_and_prerequisites() -> void:
	var game: Object = _new_v13_game(7403)
	_expect(game != null, "strict v13 save fixture starts")
	if game == null:
		return
	var valid: Dictionary = game.to_dict()
	_expect(bool(Game.validate_save(valid).get("ok", false)), "strict v13 fixture starts valid")
	for mutation in ["missing", "false", "wrong_type"]:
		var malformed: Dictionary = valid.duplicate(true)
		match mutation:
			"missing": malformed.erase("original_building_cards")
			"false": malformed["original_building_cards"] = false
			"wrong_type": malformed["original_building_cards"] = "yes"
		_expect(not bool(Game.validate_save(malformed).get("ok", false)), "v13 rejects building-card marker mutation: " + mutation)
		_expect(Game.from_dict(malformed) == null, "v13 rejects building-card marker JSON: " + mutation)

	var v12_marked: Object = _new_v12_game(7404)
	if v12_marked != null:
		var v12_data: Dictionary = v12_marked.to_dict()
		v12_data["original_building_cards"] = true
		_expect(not bool(Game.validate_save(v12_data).get("ok", false)), "v12 version with building-card marker is rejected")
		_expect(Game.from_dict(v12_data) == null, "v12 version with building-card marker cannot restore")

	for prerequisite in SAVE_PREREQUISITES:
		var malformed: Dictionary = valid.duplicate(true)
		malformed[prerequisite] = false
		_expect(not bool(Game.validate_save(malformed).get("ok", false)), "v13 rejects false prerequisite marker: " + prerequisite)
		_expect(Game.from_dict(malformed) == null, "v13 rejects false prerequisite JSON: " + prerequisite)
		var missing: Dictionary = valid.duplicate(true)
		missing.erase(prerequisite)
		_expect(not bool(Game.validate_save(missing).get("ok", false)), "v13 rejects missing prerequisite marker: " + prerequisite)
		_expect(Game.from_dict(missing) == null, "v13 rejects missing prerequisite JSON: " + prerequisite)


func _test_v13_constructor_option_guards() -> void:
	var valid_options: Dictionary = Fixture.new_game_options()
	var v12_options: Dictionary = Fixture.v12_game_options()
	var omitted: Object = Game.new_game_on_board(7405, 4, Fixture.definition(), v12_options)
	_expect(omitted != null, "omitting original_building_cards keeps a v12 constructor")
	if omitted != null:
		_expect_equal(int(omitted.state.get("version", -1)), V12_SAVE_VERSION, "omitting original_building_cards selects v12")

	var explicitly_disabled: Dictionary = valid_options.duplicate(true)
	explicitly_disabled["original_building_cards"] = false
	var disabled: Object = Game.new_game_on_board(7406, 4, Fixture.definition(), explicitly_disabled)
	_expect(disabled != null, "false original_building_cards keeps a v12 constructor")
	if disabled != null:
		_expect_equal(int(disabled.state.get("version", -1)), V12_SAVE_VERSION, "false original_building_cards selects v12")

	for malformed_value in ["yes", 1, {}, []]:
		var malformed: Dictionary = valid_options.duplicate(true)
		malformed["original_building_cards"] = malformed_value
		_expect(Game.new_game_on_board(7410 + checks, 4, Fixture.definition(), malformed) == null, "constructor rejects malformed original_building_cards type: " + str(malformed_value))

	for prerequisite in OPTION_PREREQUISITES:
		var malformed: Dictionary = valid_options.duplicate(true)
		malformed.erase(prerequisite)
		_expect(Game.new_game_on_board(7420 + checks, 4, Fixture.definition(), malformed) == null, "constructor rejects building cards without prerequisite: " + prerequisite)
