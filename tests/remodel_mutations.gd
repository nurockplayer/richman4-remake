extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/property_card_fixture.gd")

const REMODEL_SAVE_VERSION := 11

var checks: int = 0
var failures: int = 0
var bootstrap_red: int = 0
var bootstrap_reported: bool = false


func _initialize() -> void:
	_test_worker_respects_chain_cap()
	_test_demolition_clears_chain_flag()
	_test_god_mutations_respect_chain_state()
	_test_hazard_damage_clears_chain_flag()
	print("Original remodel mutation checks: %d, failures: %d, bootstrap_red: %d" % [checks, failures, bootstrap_red])
	quit(1 if failures or bootstrap_red > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_remodel_game(seed_value: int) -> Object:
	var definition: Dictionary = Fixture.definition()
	definition["supports_original_remodel"] = true
	for tile_value in definition.get("board", []):
		if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "property":
			tile_value["is_chain_store"] = false
	var options: Dictionary = Fixture.new_game_options()
	options["original_remodel"] = true
	var game: Object = Game.new_game_on_board(seed_value, 4, definition, options)
	if game == null:
		bootstrap_red += 1
		if not bootstrap_reported:
			bootstrap_reported = true
			print("BOOTSTRAP RED: v11 remodel factory is unavailable; mutation checks use a stamped v11 fallback")
		var fallback: Object = Game.new_game_on_board(seed_value, 4, definition, Fixture.new_game_options())
		_expect(fallback != null, "v10 property-card fixture bootstraps remodel fallback")
		if fallback == null:
			return null
		fallback.state["version"] = REMODEL_SAVE_VERSION
		fallback.state["original_remodel"] = true
		for tile_value in fallback.state.get("board", []):
			if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "property":
				tile_value["is_chain_store"] = false
		game = fallback
	_expect(game != null, "v11 remodel fixture starts")
	if game == null:
		return null
	game.state["god_objects"] = []
	game.state["current_player"] = 0
	game.state["phase"] = "await_roll"
	game.state["property_action_used"] = false
	game.state["players"][0]["position"] = 1
	game._set_action_options(0)
	return game


func _set_chain_property(game: Object, owner_id: int = 0, level: int = 1) -> Dictionary:
	var tile: Dictionary = game.state["board"][2]
	tile["owner"] = owner_id
	tile["building_level"] = level
	tile["is_chain_store"] = true
	game._update_tile_rent(tile)
	for player in game.state["players"]:
		var properties: Array = []
		if int(player.get("id", -1)) == owner_id:
			properties.append(2)
		player["properties"] = properties
	game._recalculate_property_values()
	return tile


func _stage_card(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	_expect(bool(result.get("ok", false)), "mutation fixture stages %s" % card_id)
	return bool(result.get("ok", false))


func _test_worker_respects_chain_cap() -> void:
	var game: Object = _new_remodel_game(5101)
	if game == null:
		return
	var tile: Dictionary = _set_chain_property(game, 0, 1)
	var before: String = game.to_json()
	var tool_before: int = int(game.state["players"][0]["tools"].get("機器工人", 0))
	var result: Dictionary = game.choose_action("use_tool", {"tool_id": "機器工人", "tile_id": 2})
	_expect(not bool(result.get("ok", false)), "worker rejects a level-one chain store")
	_expect_equal(int(tile.get("building_level", -1)), 1, "rejected chain worker preserves level one")
	_expect(bool(tile.get("is_chain_store", false)), "rejected chain worker preserves chain flag")
	_expect_equal(int(game.state["players"][0]["tools"].get("機器工人", 0)), tool_before, "rejected chain worker preserves tool")
	_expect(game.to_json() == before, "rejected chain worker is atomic")


func _test_demolition_clears_chain_flag() -> void:
	var game: Object = _new_remodel_game(5102)
	if game == null:
		return
	var tile: Dictionary = _set_chain_property(game, 1, 1)
	game.state["phase"] = "await_action"
	game._set_action_options(0)
	if not _stage_card(game, 0, "拆除"):
		return
	var supply_before: int = int(game.state["inventory_supply"]["cards"]["拆除"])
	var result: Dictionary = game.choose_action("use_card", {"card_id": "拆除", "tile_id": 2})
	_expect(bool(result.get("ok", false)), "demolition can target a chain store")
	_expect_equal(int(tile.get("building_level", -1)), 0, "demolition removes the chain store level")
	_expect(not bool(tile.get("is_chain_store", true)), "demolition clears the chain flag")
	_expect_equal(int(tile.get("owner", -1)), 1, "demolition preserves property ownership")
	_expect_equal(int(game.state["inventory_supply"]["cards"]["拆除"]), supply_before + 1, "demolition recycles its finite card")


func _test_god_mutations_respect_chain_state() -> void:
	var demon_game: Object = _new_remodel_game(5103)
	if demon_game == null:
		return
	var demon_tile: Dictionary = _set_chain_property(demon_game, 1, 1)
	demon_game.state["players"][0]["god_id"] = 10
	demon_game._apply_god_property_effect(0, demon_tile, true)
	_expect_equal(int(demon_tile.get("building_level", -1)), 0, "demon lowers a chain store to level zero")
	_expect(not bool(demon_tile.get("is_chain_store", true)), "demon clears the chain flag at level zero")

	var angel_game: Object = _new_remodel_game(5104)
	if angel_game == null:
		return
	var angel_tile: Dictionary = _set_chain_property(angel_game, 1, 1)
	angel_game.state["players"][0]["god_id"] = 9
	angel_game._apply_god_property_effect(0, angel_tile, true)
	_expect_equal(int(angel_tile.get("building_level", -1)), 1, "angel does not raise a level-one chain store")
	_expect(bool(angel_tile.get("is_chain_store", false)), "angel preserves the chain flag at its cap")


func _test_hazard_damage_clears_chain_flag() -> void:
	var game: Object = _new_remodel_game(5105)
	if game == null:
		return
	var tile: Dictionary = _set_chain_property(game, 1, 1)
	var damage: Dictionary = game._hazard_damage_property(2)
	_expect(bool(damage.get("damaged", false)), "hazard damage reaches a chain store")
	_expect_equal(int(tile.get("building_level", -1)), 0, "hazard damage removes the chain store level")
	_expect(not bool(tile.get("is_chain_store", true)), "hazard damage clears the chain flag")
	_expect_equal(int(tile.get("owner", -1)), 1, "hazard damage preserves property ownership")
