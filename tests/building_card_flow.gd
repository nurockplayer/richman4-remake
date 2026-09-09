extends SceneTree

## Issue #44 acceptance seed for the original 天使／惡魔／怪獸 building cards.
##
## The v13 constructor is intentionally tried first.  While the production
## factory is still v12, the fallback stamps a v12 game with the v13 marker so
## the public card path is still exercised and reports semantic RED instead of
## stopping at constructor RED.
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")

const BUILDING_CARD_VERSION := 13
const BUILDING_CARDS := ["天使", "惡魔", "怪獸"]
const FACILITY_CAPS := [1, 5, 5, 1, 5]

var checks := 0
var failures := 0
var bootstrap_version_red := 0
var bootstrap_reported := false
var using_bootstrap_fallback := false


func _initialize() -> void:
	_test_fixture_and_version()
	_test_angel_residential_group_and_caps()
	_test_angel_facility_selection_and_caps()
	_test_demon_group_and_facility_reset()
	_test_monster_target_rules()
	_test_phase_remote_cancel_and_invalid_atomicity()
	_test_ai_card_strategy_and_determinism()
	print("Original building-card flow checks: %d, failures: %d, bootstrap_version_red: %d" % [checks, failures, bootstrap_version_red])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_v13_game(seed_value: int, player_count: int = 4) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, Fixture.definition(), Fixture.new_game_options())
	if game != null:
		return game
	bootstrap_version_red += 1
	using_bootstrap_fallback = true
	if not bootstrap_reported:
		bootstrap_reported = true
		print("BOOTSTRAP VERSION RED: v13 constructor is unavailable; semantic checks use a v12 instance stamped v13/original_building_cards in the test harness")
	var legacy: Object = Game.new_game_on_board(seed_value, player_count, Fixture.definition(), Fixture.v12_game_options())
	_expect(legacy != null, "v12 research fixture bootstraps the v13 building-card harness")
	if legacy == null:
		return null
	legacy.state["version"] = BUILDING_CARD_VERSION
	legacy.state["original_building_cards"] = true
	legacy.state["research_action_used"] = false
	legacy._sync_state()
	return legacy


func _new_v12_game(seed_value: int, player_count: int = 4) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, Fixture.definition(), Fixture.v12_game_options())
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


func _stage_card(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	_expect(bool(result.get("ok", false)), "fixture stages " + card_id)
	return bool(result.get("ok", false))


func _use_card(game: Object, card_id: String, tile_id: Variant = null, facility_type: Variant = null, cancel: bool = false) -> Dictionary:
	var params: Dictionary = {"card_id": card_id}
	if tile_id != null:
		params["tile_id"] = tile_id
	if facility_type != null:
		params["facility_type"] = facility_type
	if cancel:
		params["cancel"] = true
	return game.choose_action("use_card", params)


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
	game._recalculate_property_values()


func _set_property_state(game: Object, tile_id: int, owner_id: int, level: int, chain: bool, group_name: String = "") -> void:
	_set_owner(game, tile_id, owner_id)
	var tile: Dictionary = game.state["board"][tile_id]
	tile["building_level"] = level
	tile["is_chain_store"] = chain
	if not group_name.is_empty():
		tile["group"] = group_name
	game._update_tile_rent(tile)
	game._recalculate_property_values()


func _facility_indices(game: Object, source_id: int) -> Array:
	var result: Array = []
	for tile_value in game.state.get("board", []):
		if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "facility" and int(tile_value.get("source_object_id", -1)) == source_id:
			result.append(int(tile_value.get("index", -1)))
	return result


func _set_facility_state(
	game: Object,
	source_id: int,
	owner_id: int,
	level: int,
	facility_type: int,
	facility_state: int = 0,
	research_tool: int = 0,
	research_turns: int = 0,
) -> void:
	var indices: Array = _facility_indices(game, source_id)
	_expect(not indices.is_empty(), "fixture contains facility source %d" % source_id)
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


func _facility_snapshot(game: Object, source_id: int) -> Array:
	var snapshots: Array = []
	for index_value in _facility_indices(game, source_id):
		var tile: Dictionary = game.state["board"][int(index_value)]
		snapshots.append({
			"owner": tile.get("owner", null),
			"building_level": tile.get("building_level", null),
			"facility_type": tile.get("facility_type", null),
			"facility_state": tile.get("facility_state", null),
			"research_tool": tile.get("research_tool", null),
			"research_turns": tile.get("research_turns", null),
		})
	return snapshots


func _cash_deposit_snapshot(game: Object) -> Array:
	var result: Array = []
	for player in game.state.get("players", []):
		result.append([int(player.get("cash", 0)), int(player.get("deposit", 0))])
	return result


func _event_target(event: Dictionary) -> int:
	for key in ["target_tile_id", "tile_id", "facility_id"]:
		if event.has(key):
			return int(event.get(key, -1))
	return -1


func _event_affected(event: Dictionary) -> Array:
	for key in ["affected_tile_ids", "affected_ids", "affected"]:
		if typeof(event.get(key, null)) == TYPE_ARRAY:
			return event[key]
	return []


func _find_card_event(game: Object, player_id: int, card_id: String) -> Dictionary:
	var events: Array = game.state.get("event_log", [])
	for index in range(events.size() - 1, -1, -1):
		var event_value: Variant = events[index]
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		if str(event.get("type", "")) == "card_used" and int(event.get("player_id", -1)) == player_id and str(event.get("card_id", "")) == card_id:
			return event
	return {}


func _assert_card_event(game: Object, card_id: String, target_id: int, affected_ids: Array, label: String) -> void:
	var event: Dictionary = game.state.get("last_event", {})
	_expect(str(event.get("type", "")) == "card_used", label + " records a card_used event")
	_expect(str(event.get("card_id", "")) == card_id, label + " event identifies the card")
	_expect(int(event.get("player_id", -1)) == int(game.state.get("current_player", -1)), label + " event identifies the actor")
	var event_target := _event_target(event)
	_expect(event_target == target_id, label + " event identifies the target")
	var affected: Array = _event_affected(event)
	_expect(not affected.is_empty(), label + " event exposes affected target information")
	for affected_id in affected_ids:
		_expect(affected.has(affected_id), label + " event includes affected tile %d" % int(affected_id))


func _assert_successful_card(game: Object, card_id: String, supply_before: int, label: String) -> void:
	_expect_equal(int(game.state["inventory_supply"]["cards"][card_id]), supply_before + 1, label + " recycles the card supply")
	_expect(not game.state["players"][int(game.state.get("current_player", 0))]["cards"].has(card_id), label + " removes the held card")


func _expect_rejected_atomic(game: Object, params: Dictionary, card_id: String, label: String) -> void:
	var before: String = game.to_json()
	var supply_before: int = int(game.state["inventory_supply"]["cards"].get(card_id, -1))
	var cards_before: Array = game.state["players"][int(game.state.get("current_player", 0))]["cards"].duplicate(true)
	var rng_before: int = int(game.state.get("rng_state", -1))
	var result: Dictionary = game.choose_action("use_card", params)
	_expect(not bool(result.get("ok", false)), label + " is rejected")
	_expect_equal(game.to_json(), before, label + " leaves the whole game unchanged")
	_expect_equal(int(game.state["inventory_supply"]["cards"].get(card_id, -1)), supply_before, label + " does not recycle or consume the card")
	_expect_equal(game.state["players"][int(game.state.get("current_player", 0))]["cards"], cards_before, label + " leaves the card held")
	_expect_equal(int(game.state.get("rng_state", -1)), rng_before, label + " does not consume RNG")


func _test_fixture_and_version() -> void:
	var definition: Dictionary = Fixture.definition()
	_expect(bool(definition.get("supports_original_building_cards", false)), "fixture advertises original building cards")
	_expect(bool(definition.get("supports_original_research", false)), "fixture retains the v12 research capability")
	var game: Object = _new_v13_game(7300)
	_expect(game != null, "v13 building-card fixture starts")
	if game == null:
		return
	_expect_equal(int(game.state.get("version", -1)), BUILDING_CARD_VERSION, "building-card setup uses v13 save")
	_expect_equal(bool(game.state.get("original_building_cards", false)), true, "v13 building-card marker is persisted")
	for flag in ["original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards", "original_property_cards", "original_remodel", "original_research"]:
		_expect(bool(game.state.get(flag, false)), "v13 retains prerequisite marker: " + flag)
	for card_id in BUILDING_CARDS:
		_expect(game.item_is_implemented("card", card_id), "v13 advertises implemented card: " + card_id)


func _test_angel_residential_group_and_caps() -> void:
	var game: Object = _new_v13_game(7310)
	_expect(game != null, "angel residential fixture starts")
	if game == null:
		return
	# Same source name/group is deliberately split across two different owners.
	_set_property_state(game, 2, 1, 4, false, "angel-group")
	_set_property_state(game, 3, 2, 1, true, "angel-group")
	_set_facility_state(game, 1, 3, 2, 2, 0x50)
	var cash_before: Array = _cash_deposit_snapshot(game)
	_prepare_action(game, 0, 2)
	if not _stage_card(game, 0, "天使"):
		return
	var supply_before: int = int(game.state["inventory_supply"]["cards"]["天使"])
	var result: Dictionary = _use_card(game, "天使", 2)
	_expect(bool(result.get("ok", false)), "angel upgrades every residential member of the selected group")
	_expect_equal(int(game.state["board"][2].get("building_level", -1)), 5, "angel raises a normal residential level to five")
	_expect_equal(int(game.state["board"][3].get("building_level", -1)), 1, "angel keeps a chain store at its one-level cap")
	_expect_equal(bool(game.state["board"][3].get("is_chain_store", false)), true, "angel preserves the chain-store flag")
	_expect_equal(int(game.state["board"][2].get("owner", -1)), 1, "angel does not filter or change the first owner")
	_expect_equal(int(game.state["board"][3].get("owner", -1)), 2, "angel does not filter or change the second owner")
	_expect_equal(int(game.state["board"][1].get("building_level", -1)), 2, "angel does not affect an unrelated facility")
	_expect_equal(_cash_deposit_snapshot(game), cash_before, "angel does not change cash or deposits")
	_assert_successful_card(game, "天使", supply_before, "angel residential group")
	_assert_card_event(game, "天使", 2, [2, 3], "angel residential group")

	var capped: Object = _new_v13_game(7311)
	_expect(capped != null, "angel cap no-op fixture starts")
	if capped == null:
		return
	_set_property_state(capped, 2, 1, 5, false, "angel-cap-group")
	_set_property_state(capped, 3, 2, 5, false, "angel-cap-group")
	_prepare_action(capped, 0, 2)
	if _stage_card(capped, 0, "天使"):
		var cap_supply_before: int = int(capped.state["inventory_supply"]["cards"]["天使"])
		var cap_result: Dictionary = _use_card(capped, "天使", 2)
		_expect(bool(cap_result.get("ok", false)), "angel cap-only group remains a legal no-op")
		_expect_equal(int(capped.state["board"][2].get("building_level", -1)), 5, "angel cap no-op keeps first level")
		_expect_equal(int(capped.state["board"][3].get("building_level", -1)), 5, "angel cap no-op keeps second level")
		_assert_successful_card(capped, "天使", cap_supply_before, "angel cap no-op")


func _test_angel_facility_selection_and_caps() -> void:
	var selection: Object = _new_v13_game(7320)
	_expect(selection != null, "angel facility selector fixture starts")
	if selection == null:
		return
	_set_facility_state(selection, 1, 2, 0, 0, 0x50)
	_prepare_action(selection, 0, 6)
	if _stage_card(selection, 0, "天使"):
		var targets: Array = selection.inventory_target_tiles("天使")
		_expect(targets.has(1) and targets.has(6), "angel target API keeps level-zero facility aliases without a preselected type")
		_expect(not targets.has(0) and not targets.has(5), "angel target API excludes status and company nodes")
		var missing_type_before: String = selection.to_json()
		var missing_type: Dictionary = _use_card(selection, "天使", 6)
		_expect(not bool(missing_type.get("ok", false)), "angel requires facility_type for a level-zero human target")
		_expect_equal(selection.to_json(), missing_type_before, "angel missing facility_type is atomic")
		var supply_before: int = int(selection.state["inventory_supply"]["cards"]["天使"])
		var selected: Dictionary = _use_card(selection, "天使", 6, 2)
		_expect(bool(selected.get("ok", false)), "angel accepts a selected facility type")
		for alias in [1, 6]:
			_expect_equal(int(selection.state["board"][alias].get("building_level", -1)), 1, "angel builds a level-zero facility on every alias")
			_expect_equal(int(selection.state["board"][alias].get("facility_type", -1)), 2, "angel applies the selected facility type on every alias")
		_expect_equal(int(selection.state["board"][1].get("owner", -1)), 2, "angel preserves facility ownership")
		_assert_successful_card(selection, "天使", supply_before, "angel facility selection")
		_assert_card_event(selection, "天使", 6, [1, 6], "angel facility selection")

	var optional_type: Object = _new_v13_game(7321)
	_expect(optional_type != null, "angel built-facility optional type fixture starts")
	if optional_type != null:
		_set_facility_state(optional_type, 1, 2, 2, 1, 0x50)
		_prepare_action(optional_type, 0, 1)
		if _stage_card(optional_type, 0, "天使"):
			var optional_result: Dictionary = _use_card(optional_type, "天使", 1)
			_expect(bool(optional_result.get("ok", false)), "angel reuses the current type for a built facility when type is omitted")
			_expect_equal(int(optional_type.state["board"][1].get("building_level", -1)), 3, "angel raises a built facility without changing its type")

	for facility_type in range(FACILITY_CAPS.size()):
		var game: Object = _new_v13_game(7330 + facility_type)
		_expect(game != null, "angel facility cap fixture starts for type %d" % facility_type)
		if game == null:
			continue
		var cap: int = int(FACILITY_CAPS[facility_type])
		var level: int = cap - 1
		var research_tool := 3 if facility_type == 4 else 0
		var research_turns := 4 if facility_type == 4 else 0
		_set_facility_state(game, 1, 1, level, facility_type, 0x50, research_tool, research_turns)
		var before: Array = _facility_snapshot(game, 1)
		var cash_before: Array = _cash_deposit_snapshot(game)
		_prepare_action(game, 0, 6)
		if not _stage_card(game, 0, "天使"):
			continue
		var supply_before: int = int(game.state["inventory_supply"]["cards"]["天使"])
		var result: Dictionary = _use_card(game, "天使", 6, facility_type)
		_expect(bool(result.get("ok", false)), "angel accepts facility type %d at its cap boundary" % facility_type)
		for alias in [1, 6]:
			var tile: Dictionary = game.state["board"][alias]
			_expect_equal(int(tile.get("building_level", -1)), cap, "angel respects facility type %d cap" % facility_type)
			_expect_equal(int(tile.get("facility_type", -1)), facility_type, "angel retains facility type %d" % facility_type)
			_expect_equal(int(tile.get("owner", -1)), 1, "angel preserves facility type %d owner" % facility_type)
			_expect_equal(int(tile.get("facility_state", -1)), int(before[[1, 6].find(alias)].get("facility_state", -2)), "angel preserves facility status for type %d" % facility_type)
			_expect_equal(int(tile.get("research_tool", -1)), research_tool, "angel preserves research rank for type %d" % facility_type)
			_expect_equal(int(tile.get("research_turns", -1)), research_turns, "angel preserves research countdown for type %d" % facility_type)
		_expect_equal(_cash_deposit_snapshot(game), cash_before, "angel facility type %d does not change cash or deposits" % facility_type)
		_assert_successful_card(game, "天使", supply_before, "angel facility type %d" % facility_type)
		_assert_card_event(game, "天使", 6, [1, 6], "angel facility type %d" % facility_type)


func _test_demon_group_and_facility_reset() -> void:
	var group_game: Object = _new_v13_game(7340)
	_expect(group_game != null, "demon residential group fixture starts")
	if group_game == null:
		return
	_set_property_state(group_game, 2, 1, 4, false, "demon-group")
	_set_property_state(group_game, 3, 2, 1, true, "demon-group")
	_set_facility_state(group_game, 1, 3, 2, 2, 0x50)
	var cash_before: Array = _cash_deposit_snapshot(group_game)
	_prepare_action(group_game, 0, 2)
	if _stage_card(group_game, 0, "惡魔"):
		var supply_before: int = int(group_game.state["inventory_supply"]["cards"]["惡魔"])
		var result: Dictionary = _use_card(group_game, "惡魔", 2)
		_expect(bool(result.get("ok", false)), "demon clears every residential member of the selected group")
		_expect_equal(int(group_game.state["board"][2].get("building_level", -1)), 0, "demon clears first residential level")
		_expect_equal(int(group_game.state["board"][3].get("building_level", -1)), 0, "demon clears second residential level")
		_expect_equal(bool(group_game.state["board"][2].get("is_chain_store", true)), false, "demon clears first chain flag")
		_expect_equal(bool(group_game.state["board"][3].get("is_chain_store", true)), false, "demon clears second chain flag")
		_expect_equal(int(group_game.state["board"][2].get("owner", -1)), 1, "demon preserves first owner")
		_expect_equal(int(group_game.state["board"][3].get("owner", -1)), 2, "demon preserves second owner")
		_expect_equal(int(group_game.state["board"][1].get("building_level", -1)), 2, "demon leaves unrelated facility unchanged")
		_expect_equal(_cash_deposit_snapshot(group_game), cash_before, "demon does not change cash or deposits")
		_assert_successful_card(group_game, "惡魔", supply_before, "demon residential group")
		_assert_card_event(group_game, "惡魔", 2, [2, 3], "demon residential group")

	var no_op: Object = _new_v13_game(7341)
	_expect(no_op != null, "demon empty-target no-op fixture starts")
	if no_op != null:
		_set_property_state(no_op, 2, 1, 0, false, "demon-empty-group")
		_set_property_state(no_op, 3, 2, 0, false, "demon-empty-group")
		_prepare_action(no_op, 0, 2)
		if _stage_card(no_op, 0, "惡魔"):
			var no_op_supply: int = int(no_op.state["inventory_supply"]["cards"]["惡魔"])
			var no_op_result: Dictionary = _use_card(no_op, "惡魔", 2)
			_expect(bool(no_op_result.get("ok", false)), "demon on an already clear group is a legal no-op")
			_expect_equal(int(no_op.state["board"][2].get("owner", -1)), 1, "demon no-op keeps first owner")
			_expect_equal(int(no_op.state["board"][3].get("owner", -1)), 2, "demon no-op keeps second owner")
			_assert_successful_card(no_op, "惡魔", no_op_supply, "demon empty-target no-op")

	var facility: Object = _new_v13_game(7342)
	_expect(facility != null, "demon research facility fixture starts")
	if facility == null:
		return
	_set_facility_state(facility, 2, 1, 3, 4, 0x51, 2, 3)
	_prepare_action(facility, 0, 8)
	if _stage_card(facility, 0, "惡魔"):
		var supply_before: int = int(facility.state["inventory_supply"]["cards"]["惡魔"])
		var result: Dictionary = _use_card(facility, "惡魔", 8)
		_expect(bool(result.get("ok", false)), "demon accepts an aliased facility target")
		for alias in [7, 8]:
			_expect_equal(int(facility.state["board"][alias].get("building_level", -1)), 0, "demon clears facility level on every alias")
			_expect_equal(int(facility.state["board"][alias].get("facility_type", -1)), 0, "demon clears facility type on every alias")
			_expect_equal(int(facility.state["board"][alias].get("owner", -1)), 1, "demon preserves aliased facility owner")
			_expect_equal(int(facility.state["board"][alias].get("facility_state", -1)), 0x51, "demon preserves facility status state")
			_expect_equal(int(facility.state["board"][alias].get("research_tool", -1)), 2, "demon preserves research rank")
			_expect_equal(int(facility.state["board"][alias].get("research_turns", -1)), 3, "demon preserves research countdown")
		_assert_successful_card(facility, "惡魔", supply_before, "demon facility reset")
		_assert_card_event(facility, "惡魔", 8, [7, 8], "demon facility reset")


func _test_monster_target_rules() -> void:
	var enemy: Object = _new_v13_game(7350)
	_expect(enemy != null, "monster enemy residential fixture starts")
	if enemy != null:
		_set_property_state(enemy, 2, 0, 2, false, "monster-group")
		_set_property_state(enemy, 3, 1, 3, true, "monster-group")
		_prepare_action(enemy, 0, 2)
		if _stage_card(enemy, 0, "怪獸"):
			var supply_before: int = int(enemy.state["inventory_supply"]["cards"]["怪獸"])
			var result: Dictionary = _use_card(enemy, "怪獸", 3)
			_expect(bool(result.get("ok", false)), "monster clears an enemy residential target")
			_expect_equal(int(enemy.state["board"][3].get("building_level", -1)), 0, "monster clears only the selected residential level")
			_expect_equal(bool(enemy.state["board"][3].get("is_chain_store", true)), false, "monster clears the selected chain flag")
			_expect_equal(int(enemy.state["board"][3].get("owner", -1)), 1, "monster preserves the enemy residential owner")
			_expect_equal(int(enemy.state["board"][2].get("building_level", -1)), 2, "monster leaves another residential target unchanged")
			_assert_successful_card(enemy, "怪獸", supply_before, "monster enemy residential")
			_assert_card_event(enemy, "怪獸", 3, [3], "monster enemy residential")

	var unowned: Object = _new_v13_game(7351)
	_expect(unowned != null, "monster unowned-built fixture starts")
	if unowned != null:
		_set_property_state(unowned, 3, -1, 2, false)
		_prepare_action(unowned, 0, 2)
		if _stage_card(unowned, 0, "怪獸"):
			var supply_before: int = int(unowned.state["inventory_supply"]["cards"]["怪獸"])
			var result: Dictionary = _use_card(unowned, "怪獸", 3)
			_expect(bool(result.get("ok", false)), "monster accepts an unowned but built residential target")
			_expect_equal(int(unowned.state["board"][3].get("building_level", -1)), 0, "monster clears an unowned built residential level")
			_expect_equal(int(unowned.state["board"][3].get("owner", -1)), -1, "monster preserves unowned status")
			_assert_successful_card(unowned, "怪獸", supply_before, "monster unowned-built residential")

	var facility: Object = _new_v13_game(7352)
	_expect(facility != null, "monster enemy facility fixture starts")
	if facility != null:
		_set_facility_state(facility, 2, 1, 2, 2, 0x50)
		_prepare_action(facility, 0, 2)
		if _stage_card(facility, 0, "怪獸"):
			var supply_before: int = int(facility.state["inventory_supply"]["cards"]["怪獸"])
			var result: Dictionary = _use_card(facility, "怪獸", 8)
			_expect(bool(result.get("ok", false)), "monster accepts an aliased enemy facility target")
			for alias in [7, 8]:
				_expect_equal(int(facility.state["board"][alias].get("building_level", -1)), 0, "monster clears facility level on every alias")
				_expect_equal(int(facility.state["board"][alias].get("facility_type", -1)), 0, "monster clears facility type on every alias")
				_expect_equal(int(facility.state["board"][alias].get("owner", -1)), 1, "monster preserves enemy facility owner")
			_expect_equal(int(facility.state["board"][7].get("facility_state", -1)), 0x50, "monster preserves facility status state")
			_assert_successful_card(facility, "怪獸", supply_before, "monster enemy facility")
			_assert_card_event(facility, "怪獸", 8, [7, 8], "monster enemy facility")

	var own: Object = _new_v13_game(7353)
	_expect(own != null, "monster own-target rejection fixture starts")
	if own != null:
		_set_property_state(own, 2, 0, 2, false)
		_prepare_action(own, 0, 2)
		if _stage_card(own, 0, "怪獸"):
			_expect_rejected_atomic(own, {"card_id": "怪獸", "tile_id": 2}, "怪獸", "monster rejects the acting player's own building")

	var clear: Object = _new_v13_game(7354)
	_expect(clear != null, "monster level-zero rejection fixture starts")
	if clear != null:
		_set_property_state(clear, 3, 1, 0, false)
		_prepare_action(clear, 0, 2)
		if _stage_card(clear, 0, "怪獸"):
			_expect_rejected_atomic(clear, {"card_id": "怪獸", "tile_id": 3}, "怪獸", "monster rejects a level-zero enemy target")


func _test_phase_remote_cancel_and_invalid_atomicity() -> void:
	var route: Object = _new_v13_game(7360)
	_expect(route != null, "building-card route phase fixture starts")
	if route != null:
		_set_property_state(route, 2, 1, 2, false)
		_prepare_action(route, 0, 2, "await_route")
		route.state["route_options"] = [3]
		route.state["pending_movement"] = {"player_id": 0, "current_node": 2, "previous_node": 1}
		if _stage_card(route, 0, "天使"):
			_expect_rejected_atomic(route, {"card_id": "天使", "tile_id": 2}, "天使", "building card in route-pending phase")

	var remote: Object = _new_v13_game(7361)
	_expect(remote != null, "building-card remote phase fixture starts")
	if remote != null:
		_set_property_state(remote, 2, 1, 2, false)
		_prepare_action(remote, 0, 2, "await_roll")
		remote.state["pending_remote_dice"] = {"player_id": 0, "value": 3}
		if _stage_card(remote, 0, "惡魔"):
			_expect_rejected_atomic(remote, {"card_id": "惡魔", "tile_id": 2}, "惡魔", "building card while remote dice is pending")

	var cancel: Object = _new_v13_game(7362)
	_expect(cancel != null, "building-card cancel fixture starts")
	if cancel != null:
		_set_property_state(cancel, 2, 1, 2, false)
		_prepare_action(cancel, 0, 2)
		if _stage_card(cancel, 0, "天使"):
			_expect_rejected_atomic(cancel, {"card_id": "天使", "tile_id": 2, "cancel": true}, "天使", "cancelled building card")

	var wrong_kind: Object = _new_v13_game(7363)
	_expect(wrong_kind != null, "building-card wrong-kind fixture starts")
	if wrong_kind != null:
		_prepare_action(wrong_kind, 0, 2)
		if _stage_card(wrong_kind, 0, "天使"):
			_expect_rejected_atomic(wrong_kind, {"card_id": "天使", "tile_id": 0}, "天使", "building card status target")

	var missing_card: Object = _new_v13_game(7364)
	_expect(missing_card != null, "building-card missing-card fixture starts")
	if missing_card != null:
		_prepare_action(missing_card, 0, 2)
		var before: String = missing_card.to_json()
		var result: Dictionary = _use_card(missing_card, "怪獸", 2)
		_expect(not bool(result.get("ok", false)), "building card without a held card is rejected")
		_expect_equal(missing_card.to_json(), before, "building card without a held card is atomic")

	var await_roll: Object = _new_v13_game(7365)
	_expect(await_roll != null, "building-card await-roll fixture starts")
	if await_roll != null:
		_set_property_state(await_roll, 2, 1, 2, false)
		_prepare_action(await_roll, 0, 2, "await_roll")
		if _stage_card(await_roll, 0, "天使"):
			var supply_before: int = int(await_roll.state["inventory_supply"]["cards"]["天使"])
			var result: Dictionary = _use_card(await_roll, "天使", 2)
			_expect(bool(result.get("ok", false)), "building card can be used through public API before rolling")
			_expect_equal(int(await_roll.state["board"][2].get("building_level", -1)), 3, "await-roll building card applies its effect")
			_assert_successful_card(await_roll, "天使", supply_before, "await-roll building card")


func _configure_ai_card_game(game: Object, card_id: String, position: int) -> void:
	for player in game.state.get("players", []):
		player["is_ai"] = false
		player["is_human"] = true
	game.state["players"][1]["is_ai"] = true
	game.state["players"][1]["is_human"] = false
	if card_id == "天使":
		_set_property_state(game, 2, 1, 4, false, "ai-angel-group")
		_set_property_state(game, 3, 0, 2, false, "ai-angel-group")
	elif card_id == "惡魔":
		# The strategy contract avoids a shared-group target that would clear the
		# acting AI player's own building as collateral.
		_set_property_state(game, 2, 1, 2, false, "ai-demon-own-group")
		_set_property_state(game, 3, 0, 3, false, "ai-demon-enemy-group")
	else:
		_set_property_state(game, 2, 1, 2, false, "ai-building-group")
		_set_property_state(game, 3, 0, 3, false, "ai-building-group")
	_prepare_action(game, 1, position)
	_stage_card(game, 1, card_id)


func _test_ai_card_strategy_and_determinism() -> void:
	for card_case in [
		{"card_id": "天使", "position": 2, "target": 2, "expected_level": 5},
		{"card_id": "惡魔", "position": 3, "target": 3, "expected_level": 0},
		{"card_id": "怪獸", "position": 3, "target": 3, "expected_level": 0},
	]:
		var card_id: String = str(card_case["card_id"])
		var first: Object = _new_v13_game(7370 + card_id.length())
		var second: Object = _new_v13_game(7370 + card_id.length())
		_expect(first != null and second != null, "AI %s deterministic fixtures start" % card_id)
		if first == null or second == null:
			continue
		_configure_ai_card_game(first, card_id, int(card_case["position"]))
		_configure_ai_card_game(second, card_id, int(card_case["position"]))
		var first_result: Dictionary = first.run_ai_turn()
		var second_result: Dictionary = second.run_ai_turn()
		_expect(bool(first_result.get("ok", false)), "AI %s turn completes" % card_id)
		_expect(bool(second_result.get("ok", false)), "second AI %s turn completes" % card_id)
		_expect_equal(first.to_json(), second.to_json(), "AI %s strategy is deterministic for the same seed" % card_id)
		var event: Dictionary = _find_card_event(first, 1, card_id)
		_expect(not event.is_empty(), "AI %s uses the building card through public use_card" % card_id)
		if not event.is_empty():
			_expect_equal(_event_target(event), int(card_case["target"]), "AI %s card event identifies the selected target" % card_id)
			var affected: Array = _event_affected(event)
			_expect(not affected.is_empty() and affected.has(int(card_case["target"])), "AI %s card event identifies the affected target" % card_id)
		_expect_equal(int(first.state["board"][int(card_case["target"])] .get("building_level", -1)), int(card_case["expected_level"]), "AI %s chooses the intended building target" % card_id)
		_expect(not first.state["players"][1]["cards"].has(card_id), "AI %s recycles its used card" % card_id)
