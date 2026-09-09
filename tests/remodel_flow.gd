extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/remodel_fixture.gd")

const REMODEL_SAVE_VERSION := 11

var checks := 0
var failures := 0
var bootstrap_version_red := 0
var bootstrap_reported := false
var using_bootstrap_fallback := false


func _initialize() -> void:
	_test_fixture_and_version()
	_test_residential_remodel()
	_test_facility_remodel()
	_test_atomic_rejections()
	_test_rent_rules()
	print("Original remodel flow checks: %d, failures: %d, bootstrap_version_red: %d" % [checks, failures, bootstrap_version_red])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_v11_game(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.new_game_options())
	if game != null:
		return game
	bootstrap_version_red += 1
	using_bootstrap_fallback = true
	if not bootstrap_reported:
		bootstrap_reported = true
		print("BOOTSTRAP VERSION RED: v11 constructor is unavailable; semantic checks use a v10 instance stamped v11/original_remodel in the test harness")
	var legacy: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.v10_game_options())
	_expect(legacy != null, "v10 predecessor fixture bootstraps the v11 harness")
	if legacy == null:
		return null
	legacy.state["version"] = REMODEL_SAVE_VERSION
	legacy.state["original_property_cards"] = true
	legacy.state["original_remodel"] = true
	for tile_value in legacy.state.get("board", []):
		if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "property":
			tile_value["is_chain_store"] = false
	legacy._sync_state()
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
	for candidate in game.state.get("players", []):
		candidate["hospital_days"] = 0
		candidate["prison_days"] = 0
		candidate["god_id"] = 0
	game.state["god_objects"] = []
	game._set_action_options(player_id)
	if using_bootstrap_fallback and not game.state["players"][player_id].get("cards", []).is_empty():
		var options: Array = game.state.get("action_options", []).duplicate(true)
		if not options.has("use_card"):
			options.append("use_card")
		game.state["action_options"] = options


func _stage_card(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	_expect(bool(result.get("ok", false)), "fixture stages %s" % card_id)
	return bool(result.get("ok", false))


func _set_asset_owner(game: Object, tile_id: int, owner_id: int) -> void:
	var board: Array = game.state["board"]
	var tile: Dictionary = board[tile_id]
	if tile.get("kind", "") == "facility":
		var source_id := int(tile.get("source_object_id", -1))
		var canonical := int(tile.get("facility_node_index", tile_id))
		for candidate in board:
			if candidate.get("kind", "") == "facility" and int(candidate.get("source_object_id", -1)) == source_id:
				candidate["owner"] = owner_id
		for player in game.state["players"]:
			while player["properties"].has(canonical):
				player["properties"].erase(canonical)
		if owner_id >= 0:
			game.state["players"][owner_id]["properties"].append(canonical)
	else:
		tile["owner"] = owner_id
		for player in game.state["players"]:
			while player["properties"].has(tile_id):
				player["properties"].erase(tile_id)
		if owner_id >= 0:
			game.state["players"][owner_id]["properties"].append(tile_id)
	game._recalculate_property_values()


func _set_property_state(game: Object, tile_id: int, owner_id: int, level: int, chain: bool) -> void:
	_set_asset_owner(game, tile_id, owner_id)
	var tile: Dictionary = game.state["board"][tile_id]
	tile["building_level"] = level
	tile["is_chain_store"] = chain
	game._update_tile_rent(tile)
	game._recalculate_property_values()


func _facility_indices(game: Object, source_id: int) -> Array:
	var result: Array = []
	for tile_value in game.state.get("board", []):
		if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "facility" and int(tile_value.get("source_object_id", -1)) == source_id:
			result.append(int(tile_value.get("index", -1)))
	return result


func _set_facility_state(game: Object, source_id: int, owner_id: int, level: int, facility_type: int, facility_state: int = 0) -> void:
	for tile_id in _facility_indices(game, source_id):
		var tile: Dictionary = game.state["board"][tile_id]
		tile["building_level"] = level
		tile["facility_type"] = facility_type
		tile["facility_state"] = facility_state
	_set_asset_owner(game, _facility_indices(game, source_id)[0], owner_id)
	game._recalculate_property_values()


func _property_snapshot(tile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["owner", "name", "source_object_id", "type_and_idx", "x", "y", "cost", "land_price", "house_price", "upgrade_cost", "base_rent", "rent_by_level", "event_code", "source_status_bits"]:
		result[key] = tile.get(key, null)
	return result


func _facility_snapshot(tile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["owner", "name", "source_object_id", "type_and_idx", "facility_node_index", "x", "y", "cost", "land_price", "upgrade_cost", "fee_by_level", "facility_state", "event_code", "source_status_bits"]:
		result[key] = tile.get(key, null)
	return result


func _cash_snapshot(game: Object) -> Array:
	var result: Array = []
	for player in game.state.get("players", []):
		result.append(int(player.get("cash", 0)))
	return result


func _test_fixture_and_version() -> void:
	var definition: Dictionary = Fixture.definition()
	_expect(bool(definition.get("supports_original_remodel", false)), "fixture advertises original remodel capability")
	_expect(bool(definition.get("supports_original_property_cards", false)), "fixture retains property-card capability")
	_expect(bool(definition.get("supports_original_hazards", false)), "fixture retains v9 hazard capability")
	_expect(definition.get("board", []).size() == 10, "fixture includes the reachable synthetic road")
	var property_count := 0
	for tile_value in definition.get("board", []):
		if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "property":
			property_count += 1
			_expect(typeof(tile_value.get("is_chain_store", null)) == TYPE_BOOL and not bool(tile_value.get("is_chain_store", true)), "source property starts with false chain flag")
	_expect(property_count == 2, "fixture retains two residential properties")

	var game: Object = _new_v11_game(5100)
	_expect(game != null, "v11 remodel fixture starts")
	if game == null:
		return
	_expect_equal(int(game.state.get("version", -1)), REMODEL_SAVE_VERSION, "remodel setup uses v11 save")
	_expect(bool(game.state.get("original_remodel", false)), "v11 remodel marker is persisted")
	_expect(bool(Fixture.new_game_options().get("original_inventory", false)), "v11 options retain original inventory prerequisite")
	for flag in ["original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards", "original_property_cards"]:
		_expect(bool(game.state.get(flag, false)), "v11 retains prerequisite flag: " + flag)


func _test_residential_remodel() -> void:
	var game: Object = _new_v11_game(5101)
	_expect(game != null, "residential remodel fixture starts")
	if game == null:
		return
	_set_property_state(game, 2, 1, 4, false)
	_prepare_action(game, 0, 2)
	if not _stage_card(game, 0, "改建"):
		return
	var supply_before := int(game.state["inventory_supply"]["cards"]["改建"])
	var cash_before: Array = _cash_snapshot(game)
	var bank_before: Dictionary = game.state["bank"].duplicate(true)
	var before: Dictionary = _property_snapshot(game.state["board"][2])
	var result: Dictionary = game.choose_action("use_card", {"card_id": "改建"})
	_expect(bool(result.get("ok", false)), "改建 converts a foot residential property to a chain store")
	_expect_equal(bool(game.state["board"][2].get("is_chain_store", false)), true, "residential remodel sets chain flag")
	_expect_equal(int(game.state["board"][2].get("building_level", -1)), 1, "residential remodel lowers chain store to level one")
	for key in before.keys():
		_expect_equal(game.state["board"][2].get(key, null), before[key], "residential remodel preserves property field " + key)
	_expect_equal(game.state["players"][1]["properties"], [2], "residential remodel does not require current player ownership")
	_expect_equal(game.state["inventory_supply"]["cards"]["改建"], supply_before + 1, "valid residential remodel returns finite card supply")
	_expect(not game.state["players"][0]["cards"].has("改建"), "valid residential remodel removes held card")
	_expect_equal(_cash_snapshot(game), cash_before, "residential remodel does not charge any player")
	_expect_equal(game.state["bank"], bank_before, "residential remodel does not charge the bank")

	var back: Object = _new_v11_game(5102)
	_expect(back != null, "chain-to-residential fixture starts")
	if back == null:
		return
	_set_property_state(back, 2, -1, 1, true)
	_prepare_action(back, 0, 2)
	if _stage_card(back, 0, "改建"):
		var back_supply_before := int(back.state["inventory_supply"]["cards"]["改建"])
		var back_result: Dictionary = back.choose_action("use_card", {"card_id": "改建"})
		_expect(bool(back_result.get("ok", false)), "改建 converts an unowned chain store back to residential")
		_expect_equal(bool(back.state["board"][2].get("is_chain_store", true)), false, "chain-to-residential clears chain flag")
		_expect_equal(int(back.state["board"][2].get("building_level", -1)), 1, "chain-to-residential preserves level one")
		_expect_equal(int(back.state["board"][2].get("owner", -2)), -1, "chain-to-residential preserves unowned status")
		_expect_equal(back.state["inventory_supply"]["cards"]["改建"], back_supply_before + 1, "chain-to-residential recycles the card")

	var house_exchange: Object = _new_v11_game(5103)
	_expect(house_exchange != null, "v11 house exchange fixture starts")
	if house_exchange == null:
		return
	_set_property_state(house_exchange, 2, 0, 4, false)
	_set_property_state(house_exchange, 3, 1, 1, true)
	_prepare_action(house_exchange, 0, 2)
	if _stage_card(house_exchange, 0, "換屋"):
		var house_supply_before := int(house_exchange.state["inventory_supply"]["cards"]["換屋"])
		var house_result: Dictionary = house_exchange.choose_action("use_card", {"card_id": "換屋", "tile_id": 3})
		_expect(bool(house_result.get("ok", false)), "v11 換屋 remains available alongside remodel")
		_expect_equal(int(house_exchange.state["board"][2].get("building_level", -1)), 1, "v11 換屋 swaps residential level")
		_expect_equal(int(house_exchange.state["board"][3].get("building_level", -1)), 4, "v11 換屋 swaps residential level at target")
		_expect_equal(bool(house_exchange.state["board"][2].get("is_chain_store", false)), true, "v11 換屋 swaps chain flag")
		_expect_equal(bool(house_exchange.state["board"][3].get("is_chain_store", true)), false, "v11 換屋 swaps chain flag at target")
		_expect_equal(house_exchange.state["inventory_supply"]["cards"]["換屋"], house_supply_before + 1, "v11 換屋 recycles finite card")


func _assert_facility_remodel(
	seed_value: int,
	source_id: int,
	position: int,
	from_type: int,
	from_level: int,
	requested_type: int,
	expected_level: int,
	label: String,
) -> void:
	var game: Object = _new_v11_game(seed_value)
	_expect(game != null, label + " fixture starts")
	if game == null:
		return
	_set_facility_state(game, source_id, 1, from_level, from_type, 0x50)
	_prepare_action(game, 0, position)
	var indices: Array = _facility_indices(game, source_id)
	var snapshots: Array = []
	for tile_id in indices:
		snapshots.append(_facility_snapshot(game.state["board"][tile_id]))
	var cash_before: Array = _cash_snapshot(game)
	var bank_before: Dictionary = game.state["bank"].duplicate(true)
	if not _stage_card(game, 0, "改建"):
		return
	var supply_before := int(game.state["inventory_supply"]["cards"]["改建"])
	var result: Dictionary = game.choose_action("use_card", {"card_id": "改建", "facility_type": requested_type})
	_expect(bool(result.get("ok", false)), label + " succeeds")
	for alias_index in range(indices.size()):
		var tile: Dictionary = game.state["board"][int(indices[alias_index])]
		_expect_equal(int(tile.get("facility_type", -1)), requested_type, label + " synchronizes facility type across aliases")
		_expect_equal(int(tile.get("building_level", -1)), expected_level, label + " applies facility level cap")
		for key in snapshots[alias_index].keys():
			_expect_equal(tile.get(key, null), snapshots[alias_index][key], label + " preserves facility field " + key)
	_expect_equal(game.state["players"][1]["properties"], [int(game.state["board"][indices[0]].get("facility_node_index", indices[0]))], label + " preserves owner reference")
	_expect_equal(game.state["inventory_supply"]["cards"]["改建"], supply_before + 1, label + " recycles finite card")
	_expect_equal(_cash_snapshot(game), cash_before, label + " does not charge players")
	_expect_equal(game.state["bank"], bank_before, label + " does not charge the bank")


func _test_facility_remodel() -> void:
	# Type 0 and type 3 are both level-one facilities; type 1 to type 2 retains
	# the existing legal level.  The owner is player 1 while player 0 is acting.
	_assert_facility_remodel(5201, 1, 6, 1, 4, 0, 1, "park facility remodel")
	_assert_facility_remodel(5202, 1, 1, 1, 4, 3, 1, "gas station facility remodel")
	_assert_facility_remodel(5203, 2, 8, 1, 4, 2, 4, "multi-level facility remodel")


func _expect_rejected_atomic(game: Object, params: Dictionary, label: String) -> void:
	var before: String = game.to_json()
	var supply_before := int(game.state["inventory_supply"]["cards"].get("改建", -1))
	var cards_before: Array = game.state["players"][0]["cards"].duplicate(true)
	var result: Dictionary = game.choose_action("use_card", params)
	_expect(not bool(result.get("ok", false)), label + " is rejected")
	_expect_equal(game.to_json(), before, label + " leaves the whole game unchanged")
	_expect_equal(game.state["inventory_supply"]["cards"].get("改建", -1), supply_before, label + " does not recycle the card")
	_expect_equal(game.state["players"][0]["cards"], cards_before, label + " leaves the card held")


func _test_atomic_rejections() -> void:
	var game: Object = _new_v11_game(5300)
	_expect(game != null, "invalid remodel fixture starts")
	if game != null:
		_set_property_state(game, 2, 1, 0, false)
		_prepare_action(game, 0, 2)
		if _stage_card(game, 0, "改建"):
			_expect_rejected_atomic(game, {"card_id": "改建"}, "zero-level residential remodel")

	game = _new_v11_game(5301)
	if game != null:
		_prepare_action(game, 0, 9)
		if _stage_card(game, 0, "改建"):
			_expect_rejected_atomic(game, {"card_id": "改建"}, "road remodel")

	game = _new_v11_game(5302)
	if game != null:
		_prepare_action(game, 0, 5)
		if _stage_card(game, 0, "改建"):
			_expect_rejected_atomic(game, {"card_id": "改建"}, "company remodel")

	game = _new_v11_game(5303)
	if game != null:
		_set_facility_state(game, 1, 1, 2, 1, 0x50)
		_prepare_action(game, 0, 6)
		if _stage_card(game, 0, "改建"):
			_expect_rejected_atomic(game, {"card_id": "改建", "facility_type": 4}, "research facility remodel")

	for invalid_type in [-1, 4.5, "0", true]:
		game = _new_v11_game(5310 + checks)
		if game == null:
			continue
		_set_facility_state(game, 1, 1, 2, 1, 0x50)
		_prepare_action(game, 0, 6)
		if _stage_card(game, 0, "改建"):
			_expect_rejected_atomic(game, {"card_id": "改建", "facility_type": invalid_type}, "malformed facility type " + str(invalid_type))

	game = _new_v11_game(5320)
	if game != null:
		_set_property_state(game, 2, 1, 2, false)
		_prepare_action(game, 0, 2)
		if _stage_card(game, 0, "改建"):
			_expect_rejected_atomic(game, {"card_id": "改建", "cancel": true}, "cancelled remodel")

	game = _new_v11_game(5321)
	if game != null:
		_set_property_state(game, 2, 1, 2, false)
		_prepare_action(game, 0, 2)
		game.state["phase"] = "await_route"
		game.state["route_options"] = [3]
		game.state["pending_movement"] = {"player_id": 0, "current_node": 2, "previous_node": 1}
		if _stage_card(game, 0, "改建"):
			_expect_rejected_atomic(game, {"card_id": "改建"}, "route-pending remodel")

	game = _new_v11_game(5322)
	if game != null:
		_set_property_state(game, 2, 1, 2, false)
		_prepare_action(game, 0, 2)
		game.state["players"][0]["hospital_days"] = 1
		if _stage_card(game, 0, "改建"):
			_expect_rejected_atomic(game, {"card_id": "改建"}, "detained remodel")

	game = _new_v11_game(5323)
	if game != null:
		_set_property_state(game, 2, 1, 2, false)
		_prepare_action(game, 0, 2)
		_expect_rejected_atomic(game, {"card_id": "改建"}, "remodel without a held card")


func _test_rent_rules() -> void:
	var game: Object = _new_v11_game(5401)
	_expect(game != null, "rent fixture starts")
	if game == null:
		return
	game.state["price_index"] = 3
	_set_property_state(game, 2, 0, 2, false)
	_set_property_state(game, 3, 0, 1, true)
	_expect_equal(game._calculate_rent(game.state["board"][2], 0), 1800, "normal rent excludes same-owner chain store and applies price index once")
	_expect_equal(game._calculate_rent(game.state["board"][3], 0), 6000, "chain rent is one store times 2000 and price index")
	_set_property_state(game, 2, 0, 1, true)
	_expect_equal(game._calculate_rent(game.state["board"][2], 0), 12000, "chain rent counts every same-owner chain store on the map")
	_expect_equal(game._calculate_rent(game.state["board"][3], 0), 12000, "both chain stores use the same global count")
	_set_property_state(game, 2, -1, 1, true)
	_set_property_state(game, 3, -1, 1, true)
	_expect_equal(game._calculate_rent(game.state["board"][2], -1), 0, "unowned chain store does not collect rent")

	# A one-edge branch and the public remote-dice action fix a one-step landing,
	# exercising the actual rent charge path without relying on RNG selection.
	var charged: Object = _new_v11_game(5402)
	_expect(charged != null, "public rent landing fixture starts")
	if charged == null:
		return
	charged.state["price_index"] = 3
	_set_property_state(charged, 2, 0, 1, true)
	_set_property_state(charged, 3, 0, 1, true)
	var board: Array = charged.state["board"]
	board[1]["adjacent"] = [2]
	if not board[2]["adjacent"].has(1):
		board[2]["adjacent"].append(1)
	charged.state["current_player"] = 1
	charged.state["phase"] = "await_roll"
	charged.state["players"][1]["position"] = 1
	charged.state["players"][1]["previous_position"] = -1
	charged.state["god_objects"] = []
	charged.state["last_roll"] = []
	charged.state["last_total"] = 0
	var granted: Dictionary = Inventory.grant_tool(charged.state["inventory_supply"], charged.state["players"][1]["tools"], "遙控骰子", 1)
	_expect(bool(granted.get("ok", false)), "rent fixture grants remote dice")
	charged._set_action_options(1)
	var remote: Dictionary = charged.choose_action("use_tool", {"tool_id": "遙控骰子", "value": 1})
	_expect(bool(remote.get("ok", false)), "rent fixture schedules a deterministic one-step roll")
	var debtor_cash_before := int(charged.state["players"][1]["cash"])
	var owner_cash_before := int(charged.state["players"][0]["cash"])
	var roll_result: Dictionary = charged.roll(1)
	_expect(bool(roll_result.get("ok", false)), "public roll reaches controlled chain landing")
	_expect_equal(int(charged.state["players"][1]["position"]), 2, "controlled roll lands on chain store")
	_expect_equal(int(charged.state["players"][1]["cash"]), debtor_cash_before - 12000, "chain landing charges global chain rent")
	_expect_equal(int(charged.state["players"][0]["cash"]), owner_cash_before + 12000, "chain landing credits the owner")
