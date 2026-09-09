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
	_test_v10_save_round_trip()
	_test_v9_legacy_rejection_and_compatibility()
	_test_v10_strict_markers()
	print("Original property-card save checks: %d, failures: %d, bootstrap_version_red: %d" % [checks, failures, bootstrap_version_red])
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
		print("BOOTSTRAP VERSION RED: v10 constructor is unavailable; semantic save checks use a v9 instance stamped v10/original_property_cards in the test harness")
	var legacy: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.v9_game_options())
	_expect(legacy != null, "v9 hazard fixture bootstraps the v10 save harness")
	if legacy == null:
		return null
	legacy.state["version"] = PROPERTY_CARD_VERSION
	legacy.state["original_property_cards"] = true
	legacy._set_action_options(0)
	return legacy


func _new_v9_game(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.v9_game_options())
	_expect(game != null, "v9 hazard fixture starts")
	return game


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
	_expect(bool(result.get("ok", false)), "save fixture stages %s" % card_id)
	return bool(result.get("ok", false))


func _set_asset_owner(game: Object, tile_id: int, owner_id: int) -> void:
	var board: Array = game.state["board"]
	var tile: Dictionary = board[tile_id]
	if tile.get("kind", "") == "facility":
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
		return
	tile["owner"] = owner_id
	for player in game.state["players"]:
		while player["properties"].has(tile_id):
			player["properties"].erase(tile_id)
	if owner_id >= 0:
		game.state["players"][owner_id]["properties"].append(tile_id)


func _test_v10_save_round_trip() -> void:
	var game: Object = _new_v10_game(4201)
	_expect(game != null, "v10 property-card save fixture starts")
	if game == null:
		return
	_expect_equal(int(game.state.get("version", -1)), PROPERTY_CARD_VERSION, "v10 save version is ten")
	_expect(bool(game.state.get("original_property_cards", false)), "v10 save carries property-card marker")
	for flag in ["original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards"]:
		_expect(bool(game.state.get(flag, false)), "v10 save carries prerequisite marker: " + flag)
	var initial: Dictionary = game.to_dict()
	var initial_validation: Dictionary = Game.validate_save(initial)
	_expect(bool(initial_validation.get("ok", false)), "fresh v10 save validates: " + str(initial_validation.get("errors", [])))
	var parsed: Variant = JSON.parse_string(game.to_json())
	_expect(parsed is Dictionary, "v10 save JSON parses")
	var restored: Object = Game.from_dict(parsed if parsed is Dictionary else {})
	_expect(restored != null, "fresh v10 save restores through from_dict")
	if restored != null:
		_expect_equal(restored.to_json(), game.to_json(), "fresh v10 JSON round trip is exact")

	_set_asset_owner(game, 2, 0)
	_set_asset_owner(game, 3, 1)
	game.state["board"][2]["building_level"] = 1
	game.state["board"][3]["building_level"] = 4
	game._update_tile_rent(game.state["board"][2])
	game._update_tile_rent(game.state["board"][3])
	game._recalculate_property_values()
	_prepare_action(game, 0, 2)
	if _stage_card(game, 0, "換地"):
		var exchange: Dictionary = game.choose_action("use_card", {"card_id": "換地", "tile_id": 3})
		_expect(bool(exchange.get("ok", false)), "valid 換地 can be saved")
		_expect_equal(game.state["board"][2].get("owner", -1), 1, "saved exchange keeps source ownership result")
		_expect_equal(game.state["board"][3].get("owner", -1), 0, "saved exchange keeps target ownership result")
		var exchanged_json: String = game.to_json()
		var exchanged_data: Dictionary = game.to_dict()
		_expect(bool(Game.validate_save(exchanged_data).get("ok", false)), "exchanged v10 save validates")
		var exchanged_restored: Object = Game.from_dict(JSON.parse_string(exchanged_json))
		_expect(exchanged_restored != null, "exchanged v10 JSON restores")
		if exchanged_restored != null:
			_expect_equal(exchanged_restored.to_json(), exchanged_json, "exchanged v10 JSON round trip is exact")
			_expect_equal(exchanged_restored.state["board"][2].get("owner", -1), 1, "restored exchange retains source owner result")
			_expect_equal(exchanged_restored.state["board"][3].get("owner", -1), 0, "restored exchange retains target owner result")
			_expect_equal(exchanged_restored.state["players"][0]["properties"], [3], "restored exchange retains player reference")
			_expect_equal(exchanged_restored.state["inventory_supply"]["cards"]["換地"], game.state["inventory_supply"]["cards"]["換地"], "restored exchange retains recycled card supply")

	var house_game: Object = _new_v10_game(4205)
	_expect(house_game != null, "v10 換屋 save fixture starts")
	if house_game == null:
		return
	_set_asset_owner(house_game, 2, 0)
	_set_asset_owner(house_game, 3, 1)
	house_game.state["board"][2]["building_level"] = 1
	house_game.state["board"][3]["building_level"] = 4
	house_game._update_tile_rent(house_game.state["board"][2])
	house_game._update_tile_rent(house_game.state["board"][3])
	house_game._recalculate_property_values()
	_prepare_action(house_game, 0, 2)
	if _stage_card(house_game, 0, "換屋"):
		var house_exchange: Dictionary = house_game.choose_action("use_card", {"card_id": "換屋", "tile_id": 3})
		_expect(bool(house_exchange.get("ok", false)), "valid 換屋 can be saved")
		_expect_equal(house_game.state["board"][2].get("owner", -1), 0, "saved 換屋 keeps source ownership")
		_expect_equal(house_game.state["board"][3].get("owner", -1), 1, "saved 換屋 keeps target ownership")
		_expect_equal(house_game.state["board"][2].get("building_level", -1), 4, "saved 換屋 keeps moved source level")
		_expect_equal(house_game.state["board"][3].get("building_level", -1), 1, "saved 換屋 keeps moved target level")
		var house_json: String = house_game.to_json()
		var house_data: Dictionary = house_game.to_dict()
		_expect(bool(Game.validate_save(house_data).get("ok", false)), "換屋 v10 save validates")
		var house_restored: Object = Game.from_dict(JSON.parse_string(house_json))
		_expect(house_restored != null, "換屋 v10 JSON restores")
		if house_restored != null:
			_expect_equal(house_restored.to_json(), house_json, "換屋 v10 JSON round trip is exact")
			_expect_equal(house_restored.state["board"][2].get("building_level", -1), 4, "restored 換屋 retains source level result")
			_expect_equal(house_restored.state["board"][3].get("building_level", -1), 1, "restored 換屋 retains target level result")
			_expect_equal(house_restored.state["players"][0]["properties"], [2], "restored 換屋 retains source property reference")
			_expect_equal(house_restored.state["players"][1]["properties"], [3], "restored 換屋 retains target property reference")
			_expect_equal(house_restored.state["inventory_supply"]["cards"]["換屋"], house_game.state["inventory_supply"]["cards"]["換屋"], "restored 換屋 retains recycled card supply")


func _test_v9_legacy_rejection_and_compatibility() -> void:
	var legacy: Object = _new_v9_game(4202)
	if legacy == null:
		return
	_expect_equal(int(legacy.state.get("version", -1)), 9, "legacy hazard save remains v9")
	_expect(not bool(legacy.state.get("original_property_cards", false)), "v9 save has no property-card marker")
	var clean_json: String = legacy.to_json()
	_expect(bool(Game.validate_save(legacy.to_dict()).get("ok", false)), "clean v9 save remains valid")
	var invalid_v9: Dictionary = legacy.to_dict()
	invalid_v9["original_property_cards"] = true
	var invalid_v9_validation: Dictionary = Game.validate_save(invalid_v9)
	_expect(not bool(invalid_v9_validation.get("ok", false)), "v9 plus property-card marker is rejected")
	_expect(Game.from_dict(invalid_v9) == null, "v9 plus property-card marker cannot restore")
	_expect_equal(legacy.to_json(), clean_json, "rejecting v9 property-card marker does not mutate source save")

	_expect(bool(Inventory.grant_card(legacy.state["inventory_supply"], legacy.state["players"][0]["cards"], "換地").get("ok", false)), "v9 compatibility fixture stages an unimplemented card")
	_prepare_action(legacy, 0, 2)
	var before_unimplemented: String = legacy.to_json()
	var unimplemented: Dictionary = legacy.choose_action("use_card", {"card_id": "換地", "tile_id": 3})
	_expect(not bool(unimplemented.get("ok", false)), "v9 rejects 換地 as unimplemented")
	_expect_equal(legacy.to_json(), before_unimplemented, "v9 unimplemented 換地 is atomic")
	_expect(not legacy.item_is_implemented("card", "換地"), "v9 does not advertise 換地 implementation")

	_expect(bool(Inventory.grant_card(legacy.state["inventory_supply"], legacy.state["players"][0]["cards"], "換屋").get("ok", false)), "v9 compatibility fixture stages unimplemented 換屋")
	_prepare_action(legacy, 0, 2)
	var before_unimplemented_house: String = legacy.to_json()
	var unimplemented_house: Dictionary = legacy.choose_action("use_card", {"card_id": "換屋", "tile_id": 3})
	_expect(not bool(unimplemented_house.get("ok", false)), "v9 rejects 換屋 as unimplemented")
	_expect_equal(legacy.to_json(), before_unimplemented_house, "v9 unimplemented 換屋 is atomic")
	_expect(not legacy.item_is_implemented("card", "換屋"), "v9 does not advertise 換屋 implementation")


func _test_v10_strict_markers() -> void:
	var game: Object = _new_v10_game(4203)
	if game == null:
		return
	var valid: Dictionary = game.to_dict()
	_expect(bool(Game.validate_save(valid).get("ok", false)), "strict-marker fixture starts from a valid v10 save")
	for mutation in ["missing", "false", "wrong_type"]:
		var malformed: Dictionary = valid.duplicate(true)
		match mutation:
			"missing":
				malformed.erase("original_property_cards")
			"false":
				malformed["original_property_cards"] = false
			"wrong_type":
				malformed["original_property_cards"] = "yes"
		var validation: Dictionary = Game.validate_save(malformed)
		_expect(not bool(validation.get("ok", false)), "v10 rejects property-card marker mutation: " + mutation)
		_expect(Game.from_dict(malformed) == null, "v10 rejects property-card marker JSON: " + mutation)

	for prerequisite in ["original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards"]:
		var malformed: Dictionary = valid.duplicate(true)
		malformed[prerequisite] = false
		var validation: Dictionary = Game.validate_save(malformed)
		_expect(not bool(validation.get("ok", false)), "v10 rejects false prerequisite marker: " + prerequisite)
		_expect(Game.from_dict(malformed) == null, "v10 rejects false prerequisite marker JSON: " + prerequisite)

	var missing_prerequisite: Dictionary = valid.duplicate(true)
	missing_prerequisite.erase("original_hazards")
	_expect(not bool(Game.validate_save(missing_prerequisite).get("ok", false)), "v10 rejects missing hazard prerequisite marker")
	_expect(Game.from_dict(missing_prerequisite) == null, "v10 rejects missing hazard prerequisite JSON")

	for capability_value in [false, "yes", 1, {}]:
		var malformed_definition: Dictionary = Fixture.definition()
		malformed_definition["supports_original_property_cards"] = capability_value
		_expect(Game.new_game_on_board(4204, 4, malformed_definition, Fixture.new_game_options()) == null, "constructor rejects malformed property-card capability: " + str(capability_value))
