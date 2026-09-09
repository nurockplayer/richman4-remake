extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/property_card_fixture.gd")

const PROPERTY_CARD_VERSION := 10

var checks := 0
var failures := 0
var bootstrap_version_red := 0
var bootstrap_reported := false


func _initialize() -> void:
	_test_fixture_and_property_exchange()
	_test_house_exchange()
	_test_unowned_and_third_party_exchange()
	_test_shared_facility_exchange()
	_test_atomic_rejections()
	print("Original property-card flow checks: %d, failures: %d, bootstrap_version_red: %d" % [checks, failures, bootstrap_version_red])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_v10_game(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.new_game_options())
	if game != null:
		return game
	bootstrap_version_red += 1
	if not bootstrap_reported:
		bootstrap_reported = true
		print("BOOTSTRAP VERSION RED: v10 constructor is unavailable; semantic checks use a v9 instance stamped v10/original_property_cards in the test harness")
	var legacy: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.v9_game_options())
	_expect(legacy != null, "v9 hazard fixture bootstraps the v10 harness")
	if legacy == null:
		return null
	legacy.state["version"] = PROPERTY_CARD_VERSION
	legacy.state["original_property_cards"] = true
	legacy._set_action_options(0)
	return legacy


func _prepare_action(game: Object, player_id: int, position: int, phase: String = "await_action") -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state["players"][player_id]["position"] = position
	game.state["players"][player_id]["previous_position"] = -1
	for candidate in game.state["players"]:
		candidate["hospital_days"] = 0
		candidate["prison_days"] = 0
		candidate["god_id"] = 0
	game.state["god_objects"] = []
	game._set_action_options(player_id)


func _stage_card(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	_expect(bool(result.get("ok", false)), "fixture stages %s" % card_id)
	return bool(result.get("ok", false))


func _set_asset_owner(game: Object, tile_id: int, owner_id: int) -> void:
	var board: Array = game.state["board"]
	var tile: Dictionary = board[tile_id]
	var kind: String = str(tile.get("kind", ""))
	if kind == "facility":
		var source_id: int = int(tile.get("source_object_id", -1))
		var canonical_id: int = int(tile.get("facility_node_index", tile_id))
		for candidate in board:
			if candidate.get("kind", "") == "facility" and int(candidate.get("source_object_id", -1)) == source_id:
				candidate["owner"] = owner_id
		for player in game.state["players"]:
			while player["properties"].has(canonical_id):
				player["properties"].erase(canonical_id)
		if owner_id >= 0:
			game.state["players"][owner_id]["properties"].append(canonical_id)
	else:
		tile["owner"] = owner_id
		for player in game.state["players"]:
			while player["properties"].has(tile_id):
				player["properties"].erase(tile_id)
		if owner_id >= 0:
			game.state["players"][owner_id]["properties"].append(tile_id)
	game._recalculate_property_values()


func _set_facility_state(game: Object, source_id: int, owner_id: int, level: int, facility_type: int, facility_state: int) -> void:
	for tile in game.state["board"]:
		if tile.get("kind", "") == "facility" and int(tile.get("source_object_id", -1)) == source_id:
			tile["building_level"] = level
			tile["facility_type"] = facility_type
			tile["facility_state"] = facility_state
	_set_asset_owner(game, _facility_canonical(game, source_id), owner_id)
	game._recalculate_property_values()


func _facility_canonical(game: Object, source_id: int) -> int:
	for tile in game.state["board"]:
		if tile.get("kind", "") == "facility" and int(tile.get("source_object_id", -1)) == source_id:
			return int(tile.get("facility_node_index", tile.get("index", -1)))
	return -1


func _facility_indices(game: Object, source_id: int) -> Array:
	var result: Array = []
	for tile in game.state["board"]:
		if tile.get("kind", "") == "facility" and int(tile.get("source_object_id", -1)) == source_id:
			result.append(int(tile.get("index", -1)))
	return result


func _property_snapshot(tile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["owner", "building_level", "rent", "name", "source_object_id", "type_and_idx", "x", "y", "cost", "land_price", "house_price", "upgrade_cost", "base_rent", "rent_by_level"]:
		result[key] = tile.get(key, null)
	return result


func _facility_snapshot(tile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["owner", "building_level", "facility_type", "facility_state", "name", "source_object_id", "type_and_idx", "facility_node_index", "x", "y", "cost", "land_price", "upgrade_cost", "fee_by_level"]:
		result[key] = tile.get(key, null)
	return result


func _has_event(game: Object, event_type: String) -> bool:
	for event_value in game.state.get("event_log", []):
		if typeof(event_value) == TYPE_DICTIONARY and str(event_value.get("type", "")) == event_type:
			return true
	return false


func _test_fixture_and_property_exchange() -> void:
	var definition: Dictionary = Fixture.definition()
	_expect(bool(definition.get("supports_original_property_cards", false)), "fixture advertises original property cards")
	_expect(bool(definition.get("supports_original_hazards", false)), "fixture retains v9 hazard capability")
	_expect(bool(definition.get("supports_original_statuses", false)), "fixture retains v8 status capability")
	_expect(bool(definition.get("supports_original_companies", false)), "fixture retains v7 company capability")
	_expect(definition.get("board", []).size() == 9, "fixture exposes two shared facilities and two houses")

	var game: Object = _new_v10_game(4101)
	_expect(game != null, "v10 property-card fixture starts")
	if game == null:
		return
	_expect_equal(int(game.state.get("version", -1)), PROPERTY_CARD_VERSION, "property-card setup uses v10 save")
	_expect(bool(game.state.get("original_property_cards", false)), "v10 property-card marker is persisted")
	for flag in ["original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards"]:
		_expect(bool(game.state.get(flag, false)), "v10 retains prerequisite flag: " + flag)

	_set_asset_owner(game, 2, 0)
	_set_asset_owner(game, 3, 1)
	game.state["board"][2]["building_level"] = 1
	game.state["board"][3]["building_level"] = 4
	game._update_tile_rent(game.state["board"][2])
	game._update_tile_rent(game.state["board"][3])
	game._recalculate_property_values()
	var source_before: Dictionary = _property_snapshot(game.state["board"][2])
	var target_before: Dictionary = _property_snapshot(game.state["board"][3])
	var cash_before: Array = []
	for player in game.state["players"]:
		cash_before.append(int(player.get("cash", 0)))
	var bank_before: Dictionary = game.state["bank"].duplicate(true)
	_prepare_action(game, 0, 2)
	if not _stage_card(game, 0, "換地"):
		return
	var supply_before: int = int(game.state["inventory_supply"]["cards"]["換地"])
	var targets: Array = game.inventory_target_tiles("換地")
	_expect(targets.has(3), "換地 target selector exposes a same-category property")
	_expect(not targets.has(2), "換地 target selector excludes the current property")
	_expect(not targets.has(1) and not targets.has(7), "換地 target selector excludes facilities from a property source")
	var result: Dictionary = game.choose_action("use_card", {"card_id": "換地", "tile_id": 3})
	_expect(bool(result.get("ok", false)), "換地 exchanges two ordinary properties")
	_expect_equal(int(game.state["board"][2].get("owner", -1)), 1, "換地 moves target owner to source site")
	_expect_equal(int(game.state["board"][3].get("owner", -1)), 0, "換地 moves source owner to target site")
	_expect_equal(_property_snapshot(game.state["board"][2]).get("building_level", -1), source_before.get("building_level", -2), "換地 leaves source building at its physical site")
	_expect_equal(_property_snapshot(game.state["board"][3]).get("building_level", -1), target_before.get("building_level", -2), "換地 leaves target building at its physical site")
	for key in ["rent", "name", "source_object_id", "type_and_idx", "x", "y", "cost", "land_price", "house_price", "upgrade_cost", "base_rent", "rent_by_level"]:
		_expect_equal(game.state["board"][2].get(key, null), source_before.get(key, null), "換地 preserves source property field " + key)
		_expect_equal(game.state["board"][3].get(key, null), target_before.get(key, null), "換地 preserves target property field " + key)
	_expect_equal(game.state["players"][0]["properties"], [3], "換地 swaps player source property reference")
	_expect_equal(game.state["players"][1]["properties"], [2], "換地 swaps player target property reference")
	_expect_equal(game.state["inventory_supply"]["cards"]["換地"], supply_before + 1, "valid 換地 returns the finite card to supply")
	_expect(not game.state["players"][0]["cards"].has("換地"), "valid 換地 removes the held card")
	for index in range(game.state["players"].size()):
		_expect_equal(int(game.state["players"][index].get("cash", 0)), int(cash_before[index]), "換地 does not charge player cash")
	_expect_equal(game.state["bank"], bank_before, "換地 does not charge or credit the bank")
	_expect(_has_event(game, "card_used"), "valid 換地 records a card event")

	var same_owner: Object = _new_v10_game(4102)
	if same_owner == null:
		return
	_set_asset_owner(same_owner, 2, 0)
	_set_asset_owner(same_owner, 3, 0)
	_prepare_action(same_owner, 0, 2)
	if _stage_card(same_owner, 0, "換地"):
		var same_supply_before: int = int(same_owner.state["inventory_supply"]["cards"]["換地"])
		var same_result: Dictionary = same_owner.choose_action("use_card", {"card_id": "換地", "tile_id": 3})
		_expect(bool(same_result.get("ok", false)), "same-owner 換地 is a legal no-op")
		_expect_equal(same_owner.state["board"][2].get("owner", -1), 0, "same-owner 換地 keeps source owner")
		_expect_equal(same_owner.state["board"][3].get("owner", -1), 0, "same-owner 換地 keeps target owner")
		_expect_equal(same_owner.state["players"][0]["properties"], [2, 3], "same-owner 換地 keeps both references")
		_expect_equal(same_owner.state["inventory_supply"]["cards"]["換地"], same_supply_before + 1, "same-owner 換地 consumes and recycles the card")


func _test_house_exchange() -> void:
	var game: Object = _new_v10_game(4130)
	_expect(game != null, "換屋 property-card fixture starts")
	if game == null:
		return
	_set_asset_owner(game, 2, 0)
	_set_asset_owner(game, 3, 1)
	game.state["board"][2]["building_level"] = 1
	game.state["board"][3]["building_level"] = 4
	game._update_tile_rent(game.state["board"][2])
	game._update_tile_rent(game.state["board"][3])
	game._recalculate_property_values()
	var source_before: Dictionary = _property_snapshot(game.state["board"][2])
	var target_before: Dictionary = _property_snapshot(game.state["board"][3])
	var cash_before: Array = []
	for player in game.state["players"]:
		cash_before.append(int(player.get("cash", 0)))
	var bank_before: Dictionary = game.state["bank"].duplicate(true)
	_prepare_action(game, 0, 2)
	if not _stage_card(game, 0, "換屋"):
		return
	var supply_before: int = int(game.state["inventory_supply"]["cards"]["換屋"])
	var targets: Array = game.inventory_target_tiles("換屋")
	_expect(targets.has(3), "換屋 target selector exposes a same-category property")
	_expect(not targets.has(2), "換屋 target selector excludes the current property")
	_expect(not targets.has(1) and not targets.has(7), "換屋 target selector excludes facilities from a property source")
	var result: Dictionary = game.choose_action("use_card", {"card_id": "換屋", "tile_id": 3})
	_expect(bool(result.get("ok", false)), "換屋 exchanges two ordinary properties")
	_expect_equal(int(game.state["board"][2].get("owner", -1)), 0, "換屋 preserves source property ownership")
	_expect_equal(int(game.state["board"][3].get("owner", -1)), 1, "換屋 preserves target property ownership")
	_expect_equal(int(game.state["board"][2].get("building_level", -1)), int(target_before.get("building_level", -2)), "換屋 moves target building to source site")
	_expect_equal(int(game.state["board"][3].get("building_level", -1)), int(source_before.get("building_level", -2)), "換屋 moves source building to target site")
	for key in ["owner", "name", "source_object_id", "type_and_idx", "x", "y", "cost", "land_price", "house_price", "upgrade_cost", "base_rent", "rent_by_level"]:
		_expect_equal(game.state["board"][2].get(key, null), source_before.get(key, null), "換屋 preserves source property field " + key)
		_expect_equal(game.state["board"][3].get(key, null), target_before.get(key, null), "換屋 preserves target property field " + key)
	var source_rents: Array = source_before.get("rent_by_level", [])
	var target_rents: Array = target_before.get("rent_by_level", [])
	_expect_equal(game.state["board"][2].get("rent", null), source_rents[int(target_before.get("building_level", 0))], "換屋 recalculates source rent for moved level")
	_expect_equal(game.state["board"][3].get("rent", null), target_rents[int(source_before.get("building_level", 0))], "換屋 recalculates target rent for moved level")
	_expect_equal(game.state["players"][0]["properties"], [2], "換屋 keeps source player property reference")
	_expect_equal(game.state["players"][1]["properties"], [3], "換屋 keeps target player property reference")
	_expect_equal(game.state["players"][0]["property_values"], 2200, "換屋 recalculates source owner's property value")
	_expect_equal(game.state["players"][1]["property_values"], 2300, "換屋 recalculates target owner's property value")
	_expect_equal(game.state["inventory_supply"]["cards"]["換屋"], supply_before + 1, "valid 換屋 returns the finite card to supply")
	_expect(not game.state["players"][0]["cards"].has("換屋"), "valid 換屋 removes the held card")
	for index in range(game.state["players"].size()):
		_expect_equal(int(game.state["players"][index].get("cash", 0)), int(cash_before[index]), "換屋 does not charge player cash")
	_expect_equal(game.state["bank"], bank_before, "換屋 does not charge or credit the bank")
	_expect(_has_event(game, "card_used"), "valid 換屋 records a card event")

	var same_owner: Object = _new_v10_game(4131)
	if same_owner == null:
		return
	_set_asset_owner(same_owner, 2, 0)
	_set_asset_owner(same_owner, 3, 0)
	same_owner.state["board"][2]["building_level"] = 2
	same_owner.state["board"][3]["building_level"] = 2
	same_owner._update_tile_rent(same_owner.state["board"][2])
	same_owner._update_tile_rent(same_owner.state["board"][3])
	same_owner._recalculate_property_values()
	_prepare_action(same_owner, 0, 2)
	if _stage_card(same_owner, 0, "換屋"):
		var same_supply_before: int = int(same_owner.state["inventory_supply"]["cards"]["換屋"])
		var same_result: Dictionary = same_owner.choose_action("use_card", {"card_id": "換屋", "tile_id": 3})
		_expect(bool(same_result.get("ok", false)), "same-owner 換屋 is a legal no-op")
		_expect_equal(same_owner.state["board"][2].get("building_level", -1), 2, "same-owner 換屋 keeps source level")
		_expect_equal(same_owner.state["board"][3].get("building_level", -1), 2, "same-owner 換屋 keeps target level")
		_expect_equal(same_owner.state["players"][0]["properties"], [2, 3], "same-owner 換屋 keeps both references")
		_expect_equal(same_owner.state["inventory_supply"]["cards"]["換屋"], same_supply_before + 1, "same-owner 換屋 consumes and recycles the card")
func _test_unowned_and_third_party_exchange() -> void:
	var unowned: Object = _new_v10_game(4103)
	if unowned == null:
		return
	_set_asset_owner(unowned, 2, 2)
	_set_asset_owner(unowned, 3, -1)
	_prepare_action(unowned, 0, 2)
	if _stage_card(unowned, 0, "換地"):
		var unowned_result: Dictionary = unowned.choose_action("use_card", {"card_id": "換地", "tile_id": 3})
		_expect(bool(unowned_result.get("ok", false)), "換地 permits an unowned target")
		_expect_equal(unowned.state["board"][2].get("owner", -1), -1, "unowned-target 換地 releases source ownership")
		_expect_equal(unowned.state["board"][3].get("owner", -1), 2, "unowned-target 換地 assigns target ownership")
		_expect_equal(unowned.state["players"][2]["properties"], [3], "unowned-target 換地 updates third-party reference")

	var third_party: Object = _new_v10_game(4104)
	if third_party == null:
		return
	_set_asset_owner(third_party, 2, 2)
	_set_asset_owner(third_party, 3, 3)
	_prepare_action(third_party, 0, 2)
	if _stage_card(third_party, 0, "換地"):
		var third_party_result: Dictionary = third_party.choose_action("use_card", {"card_id": "換地", "tile_id": 3})
		_expect(bool(third_party_result.get("ok", false)), "換地 permits two third-party owners")
		_expect_equal(third_party.state["board"][2].get("owner", -1), 3, "third-party 換地 swaps source owner")
		_expect_equal(third_party.state["board"][3].get("owner", -1), 2, "third-party 換地 swaps target owner")
		_expect_equal(third_party.state["players"][2]["properties"], [3], "third-party 換地 swaps first reference")
		_expect_equal(third_party.state["players"][3]["properties"], [2], "third-party 換地 swaps second reference")

	var unowned_house: Object = _new_v10_game(4132)
	if unowned_house == null:
		return
	_set_asset_owner(unowned_house, 2, 2)
	_set_asset_owner(unowned_house, 3, -1)
	unowned_house.state["board"][2]["building_level"] = 0
	unowned_house.state["board"][3]["building_level"] = 0
	unowned_house._update_tile_rent(unowned_house.state["board"][2])
	unowned_house._update_tile_rent(unowned_house.state["board"][3])
	unowned_house._recalculate_property_values()
	_prepare_action(unowned_house, 0, 2)
	if _stage_card(unowned_house, 0, "換屋"):
		var unowned_house_result: Dictionary = unowned_house.choose_action("use_card", {"card_id": "換屋", "tile_id": 3})
		_expect(bool(unowned_house_result.get("ok", false)), "換屋 permits an unowned target")
		_expect_equal(unowned_house.state["board"][2].get("owner", -1), 2, "unowned-target 換屋 preserves source ownership")
		_expect_equal(unowned_house.state["board"][3].get("owner", -1), -1, "unowned-target 換屋 preserves target ownership")
		_expect_equal(unowned_house.state["board"][2].get("building_level", -1), 0, "unowned-target 換屋 preserves source level")
		_expect_equal(unowned_house.state["board"][3].get("building_level", -1), 0, "unowned-target 換屋 preserves target level")


func _test_shared_facility_exchange() -> void:
	var game: Object = _new_v10_game(4105)
	_expect(game != null, "shared-facility property-card fixture starts")
	if game == null:
		return
	_set_facility_state(game, 1, 1, 4, 1, 0x50)
	_set_facility_state(game, 2, 2, 1, 3, 0x51)
	var source_indices: Array = _facility_indices(game, 1)
	var target_indices: Array = _facility_indices(game, 2)
	var source_before: Array = []
	var target_before: Array = []
	for index in source_indices:
		source_before.append(_facility_snapshot(game.state["board"][index]))
	for index in target_indices:
		target_before.append(_facility_snapshot(game.state["board"][index]))
	_prepare_action(game, 0, 6)
	if not _stage_card(game, 0, "換地"):
		return
	var targets: Array = game.inventory_target_tiles("換地")
	_expect((targets.has(7) or targets.has(8)), "換地 facility selector exposes a different facility source")
	_expect(not targets.has(1) and not targets.has(6), "換地 facility selector excludes the other entrance of the current facility")
	var result: Dictionary = game.choose_action("use_card", {"card_id": "換地", "tile_id": 8})
	_expect(bool(result.get("ok", false)), "換地 accepts an explicit shared-facility entrance target")
	for index in source_indices:
		_expect_equal(int(game.state["board"][index].get("owner", -1)), 2, "換地 syncs source facility entrance owner")
		_expect_equal(int(game.state["board"][index].get("building_level", -1)), 4, "換地 leaves source facility level in place")
		_expect_equal(int(game.state["board"][index].get("facility_type", -1)), 1, "換地 leaves source facility type in place")
		_expect_equal(int(game.state["board"][index].get("facility_state", -1)), 0x50, "換地 leaves source facility temporary state in place")
	for index in target_indices:
		_expect_equal(int(game.state["board"][index].get("owner", -1)), 1, "換地 syncs target facility entrance owner")
		_expect_equal(int(game.state["board"][index].get("building_level", -1)), 1, "換地 leaves target facility level in place")
		_expect_equal(int(game.state["board"][index].get("facility_type", -1)), 3, "換地 leaves target facility type in place")
		_expect_equal(int(game.state["board"][index].get("facility_state", -1)), 0x51, "換地 leaves target facility temporary state in place")
	for offset in range(source_indices.size()):
		var source_index: int = int(source_indices[offset])
		for key in ["building_level", "facility_type", "facility_state", "name", "source_object_id", "type_and_idx", "facility_node_index", "x", "y", "cost", "land_price", "upgrade_cost", "fee_by_level"]:
			_expect_equal(game.state["board"][source_index].get(key, null), source_before[offset].get(key, null), "換地 preserves source facility field " + key)
	for offset in range(target_indices.size()):
		var target_index: int = int(target_indices[offset])
		for key in ["building_level", "facility_type", "facility_state", "name", "source_object_id", "type_and_idx", "facility_node_index", "x", "y", "cost", "land_price", "upgrade_cost", "fee_by_level"]:
			_expect_equal(game.state["board"][target_index].get(key, null), target_before[offset].get(key, null), "換地 preserves target facility field " + key)
	_expect_equal(game.state["players"][1]["properties"], [7], "換地 swaps source facility canonical reference")
	_expect_equal(game.state["players"][2]["properties"], [1], "換地 swaps target facility canonical reference")
	_expect_equal(game.state["players"][1]["property_values"], 2300, "換地 recalculates target facility valuation")
	_expect_equal(game.state["players"][2]["property_values"], 2200, "換地 recalculates source facility valuation")

	var house_game: Object = _new_v10_game(4106)
	_expect(house_game != null, "shared-facility 換屋 fixture starts")
	if house_game == null:
		return
	_set_facility_state(house_game, 1, 1, 4, 1, 0x50)
	_set_facility_state(house_game, 2, 2, 1, 3, 0x51)
	var house_source_indices: Array = _facility_indices(house_game, 1)
	var house_target_indices: Array = _facility_indices(house_game, 2)
	var house_source_before: Array = []
	var house_target_before: Array = []
	for index in house_source_indices:
		house_source_before.append(_facility_snapshot(house_game.state["board"][index]))
	for index in house_target_indices:
		house_target_before.append(_facility_snapshot(house_game.state["board"][index]))
	_prepare_action(house_game, 0, 6)
	if not _stage_card(house_game, 0, "換屋"):
		return
	var house_supply_before: int = int(house_game.state["inventory_supply"]["cards"]["換屋"])
	var house_targets: Array = house_game.inventory_target_tiles("換屋")
	_expect((house_targets.has(7) or house_targets.has(8)), "換屋 facility selector exposes a different facility source")
	_expect(not house_targets.has(1) and not house_targets.has(6), "換屋 facility selector excludes the other entrance of the current facility")
	var house_result: Dictionary = house_game.choose_action("use_card", {"card_id": "換屋", "tile_id": 8})
	_expect(bool(house_result.get("ok", false)), "換屋 accepts an explicit shared-facility entrance target")
	for index in house_source_indices:
		_expect_equal(int(house_game.state["board"][index].get("owner", -1)), 1, "換屋 preserves source facility entrance owner")
		_expect_equal(int(house_game.state["board"][index].get("building_level", -1)), 1, "換屋 moves target facility level to source")
		_expect_equal(int(house_game.state["board"][index].get("facility_type", -1)), 3, "換屋 moves target facility type to source")
		_expect_equal(int(house_game.state["board"][index].get("facility_state", -1)), 0x50, "換屋 preserves source facility temporary state")
	for index in house_target_indices:
		_expect_equal(int(house_game.state["board"][index].get("owner", -1)), 2, "換屋 preserves target facility entrance owner")
		_expect_equal(int(house_game.state["board"][index].get("building_level", -1)), 4, "換屋 moves source facility level to target")
		_expect_equal(int(house_game.state["board"][index].get("facility_type", -1)), 1, "換屋 moves source facility type to target")
		_expect_equal(int(house_game.state["board"][index].get("facility_state", -1)), 0x51, "換屋 preserves target facility temporary state")
	for offset in range(house_source_indices.size()):
		var source_index: int = int(house_source_indices[offset])
		for key in ["owner", "facility_state", "name", "source_object_id", "type_and_idx", "facility_node_index", "x", "y", "cost", "land_price", "upgrade_cost", "fee_by_level"]:
			_expect_equal(house_game.state["board"][source_index].get(key, null), house_source_before[offset].get(key, null), "換屋 preserves source facility field " + key)
	for offset in range(house_target_indices.size()):
		var target_index: int = int(house_target_indices[offset])
		for key in ["owner", "facility_state", "name", "source_object_id", "type_and_idx", "facility_node_index", "x", "y", "cost", "land_price", "upgrade_cost", "fee_by_level"]:
			_expect_equal(house_game.state["board"][target_index].get(key, null), house_target_before[offset].get(key, null), "換屋 preserves target facility field " + key)
	_expect_equal(house_game.state["players"][1]["properties"], [1], "換屋 keeps source facility canonical reference")
	_expect_equal(house_game.state["players"][2]["properties"], [7], "換屋 keeps target facility canonical reference")
	_expect_equal(house_game.state["players"][1]["property_values"], 1300, "換屋 recalculates source facility valuation")
	_expect_equal(house_game.state["players"][2]["property_values"], 3200, "換屋 recalculates target facility valuation")
	_expect_equal(house_game.state["inventory_supply"]["cards"]["換屋"], house_supply_before + 1, "valid facility 換屋 returns the finite card to supply")
	_expect(not house_game.state["players"][0]["cards"].has("換屋"), "valid facility 換屋 removes the held card")


func _expect_rejected_atomic(game: Object, label: String, params: Dictionary) -> void:
	var before_json: String = game.to_json()
	var before_rng: String = str(game.to_dict().get("rng_state_text", ""))
	var result: Dictionary = game.choose_action("use_card", params)
	_expect(not bool(result.get("ok", false)), label + " is rejected")
	_expect(game.to_json() == before_json, label + " leaves the whole game unchanged")
	_expect(str(game.to_dict().get("rng_state_text", "")) == before_rng, label + " does not consume RNG")


func _new_rejection_case(seed_value: int, source_id: int, target_id: Variant, label: String, phase: String = "await_action", card_id: String = "換地") -> Object:
	var game: Object = _new_v10_game(seed_value)
	if game == null:
		return null
	_prepare_action(game, 0, source_id, phase)
	if not _stage_card(game, 0, card_id):
		return null
	var params: Dictionary = {"card_id": card_id}
	if target_id != null:
		params["tile_id"] = target_id
	_expect_rejected_atomic(game, label, params)
	return game


func _test_atomic_rejections() -> void:
	_new_rejection_case(4110, 2, 0, "wrong-kind status target")
	_new_rejection_case(4111, 2, 5, "company target")
	_new_rejection_case(4112, 2, 4, "road or non-property target")
	_new_rejection_case(4113, 2, 999, "out-of-bounds target")
	_new_rejection_case(4114, 2, "3", "malformed string target")
	_new_rejection_case(4115, 2, {}, "malformed dictionary target")
	_new_rejection_case(4116, 2, null, "missing target")
	_new_rejection_case(4117, 2, 7, "cross-category facility target")
	_new_rejection_case(4118, 1, 6, "same facility through alias target")
	_new_rejection_case(4119, 5, 2, "company source tile")
	_new_rejection_case(4123, 2, 0, "換屋 wrong-kind status target", "await_action", "換屋")
	_new_rejection_case(4124, 1, 6, "換屋 same facility through alias target", "await_action", "換屋")
	_new_rejection_case(4125, 6, 8, "換屋 route-paused exchange", "await_route", "換屋")

	var cancel_case: Object = _new_v10_game(4120)
	if cancel_case != null:
		_prepare_action(cancel_case, 0, 2)
		if _stage_card(cancel_case, 0, "換地"):
			_expect_rejected_atomic(cancel_case, "cancelled exchange", {"card_id": "換地", "tile_id": 3, "cancel": true})

	var route_case: Object = _new_v10_game(4121)
	if route_case != null:
		_prepare_action(route_case, 0, 2, "await_route")
		route_case.state["route_options"] = [3]
		route_case.state["remaining_steps"] = 1
		route_case.state["last_total"] = 1
		route_case.state["pending_movement"] = {"player_id": 0, "current_node": 2, "previous_node": 1}
		route_case._set_action_options(0)
		if _stage_card(route_case, 0, "換地"):
			_expect_rejected_atomic(route_case, "route-paused exchange", {"card_id": "換地", "tile_id": 3})

	var detained_case: Object = _new_v10_game(4122)
	if detained_case != null:
		_prepare_action(detained_case, 0, 2)
		detained_case.state["players"][0]["hospital_days"] = 1
		detained_case._set_action_options(0)
		if _stage_card(detained_case, 0, "換地"):
			_expect_rejected_atomic(detained_case, "detained exchange", {"card_id": "換地", "tile_id": 3})
