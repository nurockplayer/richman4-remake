extends SceneTree

## Issue #50 regression seed for an engineering vehicle on a stationary turn.
##
## A positive roll is not evidence of movement when 停留 keeps the actor on the
## same node.  The landing and AI checks below use an actually activated
## engineering vehicle and validate the save before dispatching the public
## transition.  The final cycle fixture makes sure a real route that returns to
## its origin still counts as a landing.
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/god_card_fixture.gd")

const ENGINEERING_TOOL := "工程車"
const ENGINEERING_VEHICLE := "engineering"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_stationary_public_landing()
	_test_stationary_ai_landing()
	_test_actual_route_return_landing()
	print("Engineering vehicle stationary checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_game(seed_value: int, definition: Dictionary = {}, player_count: int = 2) -> Object:
	var selected_definition: Dictionary = definition if not definition.is_empty() else Fixture.definition()
	var game: Object = Game.new_game_on_board(seed_value, player_count, selected_definition, Fixture.new_game_options())
	_expect(game != null, "stationary fixture starts")
	if game == null:
		return null
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), "stationary fixture is save-valid: %s" % str(validation.get("errors", [])))
	return game


func _prepare_turn(game: Object, player_id: int, phase: String = "await_roll", position: int = -1) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state["bank_access"] = false
	game.state["bank_landing"] = false
	game.state["extra_roll"] = false
	game.state["doubles_count"] = 0
	if position >= 0:
		var player: Dictionary = game.state["players"][player_id]
		player["position"] = position
		player["previous_position"] = -1
	game.call("_set_action_options", player_id)


func _property_indices(game: Object) -> Array:
	var result: Array = []
	for index in range(game.state.get("board", []).size()):
		var tile: Variant = game.state["board"][index]
		if typeof(tile) == TYPE_DICTIONARY and tile.get("kind", "") == "property":
			result.append(index)
	return result


func _set_enemy_property(game: Object, tile_id: int, level: int = 2) -> void:
	var tile: Dictionary = game.state["board"][tile_id]
	tile["owner"] = 1
	tile["building_level"] = level
	tile["is_chain_store"] = false
	game.call("_update_tile_rent", tile)
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var properties: Array = player_value.get("properties", []).duplicate(true)
		while properties.has(tile_id):
			properties.erase(tile_id)
		if int(player_value.get("id", -1)) == 1:
			properties.append(tile_id)
		player_value["properties"] = properties
	game.call("_recalculate_property_values")


func _activate_engineering(game: Object, player_id: int = 0) -> bool:
	var supply_before: Dictionary = game.state["inventory_supply"]["tools"].duplicate(true)
	var player: Dictionary = game.state["players"][player_id]
	var grant: Dictionary = Inventory.grant_tool(game.state["inventory_supply"], player["tools"], ENGINEERING_TOOL)
	_expect(bool(grant.get("ok", false)), "stationary fixture stages 工程車")
	if not bool(grant.get("ok", false)):
		return false
	_expect_equal(game.state["inventory_supply"]["tools"], supply_before, "staging 工程車 leaves its unbounded supply unchanged")
	_prepare_turn(game, player_id)
	var pre_activation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(pre_activation.get("ok", false)), "staged stationary fixture validates: %s" % str(pre_activation.get("errors", [])))
	var result: Dictionary = game.choose_action("use_tool", {"tool_id": ENGINEERING_TOOL})
	_expect(bool(result.get("ok", false)), "stationary fixture activates 工程車 through use_tool")
	if not bool(result.get("ok", false)):
		return false
	player = game.state["players"][player_id]
	_expect_equal(str(player.get("vehicle", "")), ENGINEERING_VEHICLE, "activation selects engineering vehicle")
	_expect_equal(int(player.get("dice_count", -1)), 1, "activation fixes one die")
	_expect_equal(int(player.get("tools", {}).get(ENGINEERING_TOOL, 0)), 0, "activation consumes one staged 工程車")
	var active_validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(active_validation.get("ok", false)), "active stationary fixture validates: %s" % str(active_validation.get("errors", [])))
	return true


func _event_count(game: Object, event_type: String) -> int:
	var count: int = 0
	for event_value in game.state.get("event_log", []):
		if typeof(event_value) == TYPE_DICTIONARY and str(event_value.get("type", "")) == event_type:
			count += 1
	return count


func _test_stationary_public_landing() -> void:
	var game: Object = _new_game(7201)
	if game == null:
		return
	game.state["god_objects"] = []
	var properties: Array = _property_indices(game)
	_expect(not properties.is_empty(), "stationary fixture contains an ordinary property")
	if properties.is_empty() or not _activate_engineering(game):
		return
	var target: int = int(properties[0])
	_set_enemy_property(game, target, 2)
	var player: Dictionary = game.state["players"][0]
	player["position"] = target
	player["previous_position"] = -1
	player["stay_next"] = 1
	_prepare_turn(game, 0, "await_roll", target)
	player["stay_next"] = 1
	var prestate: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(prestate.get("ok", false)), "stationary public pre-roll state validates: %s" % str(prestate.get("errors", [])))
	var reloaded: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	_expect(reloaded != null, "stationary public pre-roll state reloads")
	var supply_before: Dictionary = game.state["inventory_supply"]["tools"].duplicate(true)
	var roll_result: Dictionary = game.roll()
	_expect(bool(roll_result.get("ok", false)), "stationary public roll succeeds")
	if not bool(roll_result.get("ok", false)):
		return
	_expect_equal(int(player.get("position", -1)), target, "停留 keeps the player on the enemy property")
	_expect_equal(int(player.get("stay_next", -1)), 0, "停留 consumes its one stationary turn")
	_expect_equal(str(game.state.get("phase", "")), "await_action", "stationary roll reaches the action phase")
	_expect(bool(game.state.get("last_roll", []).size() > 0), "stationary positive roll remains observable")
	var after_roll_validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(after_roll_validation.get("ok", false)), "stationary action-phase state validates before save")
	var action_reloaded: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	_expect(action_reloaded != null, "stationary action-phase save reloads before end_turn")
	var end_result: Dictionary = game.end_turn()
	_expect(bool(end_result.get("ok", false)), "stationary public end_turn succeeds")
	_expect_equal(int(game.state["board"][target].get("building_level", -1)), 2, "stationary public landing does not demolish the enemy building")
	_expect_equal(_event_count(game, "engineering_demolition"), 0, "stationary public landing records no engineering demolition")
	_expect_equal(game.state["inventory_supply"]["tools"], supply_before, "stationary public turn preserves finite tool supply")
	var poststate: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(poststate.get("ok", false)), "stationary public post-turn state validates: %s" % str(poststate.get("errors", [])))
	if action_reloaded != null:
		_expect(bool(action_reloaded.end_turn().get("ok", false)), "loaded stationary action ends successfully")
		_expect_equal(int(action_reloaded.state["board"][target].building_level), 2, "loaded stationary action does not demolish")
		_expect_equal(action_reloaded.to_json(), game.to_json(), "stationary save continues with exact canonical JSON")


func _clear_inventory(game: Object, player_id: int) -> bool:
	var player: Dictionary = game.state["players"][player_id]
	for card_id in player.get("cards", []).duplicate():
		var card_result: Dictionary = Inventory.consume_card(game.state["inventory_supply"], player["cards"], str(card_id))
		_expect(bool(card_result.get("ok", false)), "stationary AI returns its starter card")
		if not bool(card_result.get("ok", false)):
			return false
	var tool_ids: Array = player.get("tools", {}).keys()
	for tool_id_value in tool_ids:
		var tool_id: String = str(tool_id_value)
		var quantity: int = int(player["tools"].get(tool_id, 0))
		if quantity <= 0:
			continue
		var tool_result: Dictionary = Inventory.consume_tool(game.state["inventory_supply"], player["tools"], tool_id, quantity)
		_expect(bool(tool_result.get("ok", false)), "stationary AI returns starter tool %s" % tool_id)
		if not bool(tool_result.get("ok", false)):
			return false
	return true


func _test_stationary_ai_landing() -> void:
	var game: Object = _new_game(7202)
	if game == null:
		return
	game.state["god_objects"] = []
	if not _clear_inventory(game, 0):
		return
	var properties: Array = _property_indices(game)
	_expect(not properties.is_empty(), "stationary AI fixture contains an ordinary property")
	if properties.is_empty():
		return
	var player: Dictionary = game.state["players"][0]
	var grant: Dictionary = Inventory.grant_tool(game.state["inventory_supply"], player["tools"], ENGINEERING_TOOL)
	_expect(bool(grant.get("ok", false)), "stationary AI stages 工程車")
	if not bool(grant.get("ok", false)):
		return
	_expect(bool(game.set_player_ai(0, true)), "stationary AI actor is enabled")
	_expect(bool(game.set_player_ai(1, false)), "stationary AI opponent is human")
	var target: int = int(properties[0])
	_set_enemy_property(game, target, 2)
	player["cash"] = 0
	player["position"] = target
	player["previous_position"] = -1
	player["stay_next"] = 1
	_prepare_turn(game, 0, "await_roll", target)
	player["stay_next"] = 1
	var prestate: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(prestate.get("ok", false)), "stationary AI pre-roll state validates: %s" % str(prestate.get("errors", [])))
	var supply_before: Dictionary = game.state["inventory_supply"]["tools"].duplicate(true)
	var tool_before: int = int(player.get("tools", {}).get(ENGINEERING_TOOL, 0))
	var result: Dictionary = game.run_ai_turn()
	_expect(bool(result.get("ok", false)) and bool(result.get("completed", false)), "stationary AI turn completes")
	_expect_equal(tool_before, 1, "stationary AI starts with one 工程車")
	_expect_equal(int(player.get("tools", {}).get(ENGINEERING_TOOL, 0)), tool_before, "stationary AI does not consume 工程車")
	_expect_equal(str(player.get("vehicle", "")), "walking", "stationary AI does not activate engineering")
	_expect(not player.has("engineering_vehicle"), "stationary AI keeps no engineering metadata")
	_expect_equal(int(game.state["board"][target].get("building_level", -1)), 2, "stationary AI landing does not demolish the enemy building")
	_expect_equal(_event_count(game, "engineering_demolition"), 0, "stationary AI records no engineering demolition")
	_expect_equal(game.state["inventory_supply"]["tools"], supply_before, "stationary AI preserves finite tool supply")
	var poststate: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(poststate.get("ok", false)), "stationary AI post-turn state validates: %s" % str(poststate.get("errors", [])))


func _cycle_definition() -> Dictionary:
	var definition: Dictionary = Fixture.definition()
	var properties: Array = []
	for index in range(definition.get("board", []).size()):
		var tile: Variant = definition["board"][index]
		if typeof(tile) == TYPE_DICTIONARY and tile.get("kind", "") == "property":
			properties.append(index)
	if properties.size() >= 2:
		var first: int = int(properties[0])
		var second: int = int(properties[1])
		if not definition["board"][first]["adjacent"].has(second):
			definition["board"][first]["adjacent"].append(second)
		if not definition["board"][second]["adjacent"].has(first):
			definition["board"][second]["adjacent"].append(first)
	return definition


func _test_actual_route_return_landing() -> void:
	var game: Object = _new_game(1, _cycle_definition())
	if game == null:
		return
	game.state["god_objects"] = []
	var properties: Array = _property_indices(game)
	if properties.size() < 2 or not _activate_engineering(game):
		return
	var target: int = int(properties[0])
	var branch: int = int(properties[1])
	_set_enemy_property(game, target, 2)
	var player: Dictionary = game.state["players"][0]
	player["position"] = target
	player["previous_position"] = -1
	_prepare_turn(game, 0, "await_roll", target)
	var prestate: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(prestate.get("ok", false)), "return-landing pre-roll state validates: %s" % str(prestate.get("errors", [])))
	var roll_result: Dictionary = game.roll()
	_expect(bool(roll_result.get("ok", false)), "return-landing roll succeeds")
	_expect_equal(int(roll_result.get("total", -1)), 3, "return-landing fixture uses a three-step engineering roll")
	_expect_equal(str(game.state.get("phase", "")), "await_route", "return-landing roll exposes the route")
	if str(game.state.get("phase", "")) != "await_route":
		return
	var first_route: Dictionary = game.choose_route(branch)
	_expect(bool(first_route.get("ok", false)), "return-landing chooses the other property branch")
	var second_route: Dictionary = game.choose_route(4)
	_expect(bool(second_route.get("ok", false)), "return-landing chooses the shared intersection")
	var final_route: Dictionary = game.choose_route(target)
	_expect(bool(final_route.get("ok", false)), "return-landing chooses the origin property")
	_expect_equal(int(player.get("position", -1)), target, "actual route returns to its origin")
	_expect_equal(str(game.state.get("phase", "")), "await_action", "actual return resolves as a landing")
	var end_result: Dictionary = game.end_turn()
	_expect(bool(end_result.get("ok", false)), "return-landing end_turn succeeds")
	_expect_equal(int(game.state["board"][target].get("building_level", -1)), 0, "actual return landing demolishes the enemy building")
	_expect_equal(_event_count(game, "engineering_demolition"), 1, "actual return landing records one engineering demolition")
	var poststate: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(poststate.get("ok", false)), "return-landing post-turn state validates: %s" % str(poststate.get("errors", [])))
