extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_vehicle_tools_and_remote_dice()
	_test_turn_and_equal_poor_cards()
	_test_effect_save_round_trip_and_legacy()
	print("Inventory effect checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures else 0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _options() -> Dictionary:
	return {"start_date": {"year": 1998, "month": 1, "day": 1}, "original_inventory": true}


func _new_inventory(seed_value: int = 510) -> Object:
	return GameState.new_game(seed_value, 2, _options())


func _new_graph_inventory(seed_value: int = 520) -> Object:
	var normalized: Dictionary = Maps.normalize_map(Fixture.make())
	if not bool(normalized.get("ok", false)):
		return null
	return GameState.new_game_on_board(seed_value, 2, normalized["definition"], _options())


func _stage_tool(game: Object, player_id: int, tool_id: String, quantity: int = 1) -> bool:
	return bool(Inventory.grant_tool(game.state["inventory_supply"], game.state["players"][player_id]["tools"], tool_id, quantity).get("ok", false))


func _stage_card(game: Object, player_id: int, card_id: String) -> bool:
	return bool(Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id).get("ok", false))


func _prepare_roll(game: Object) -> void:
	game.state["current_player"] = 0
	game.state["phase"] = "await_roll"
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["pending_remote_dice"] = {}
	game._set_action_options(0)


func _test_vehicle_tools_and_remote_dice() -> void:
	var game: Object = _new_inventory()
	_expect(game != null, "inventory effects fixture creates a game")
	if game == null:
		return
	var player: Dictionary = game.state["players"][0]
	var supply: Dictionary = game.state["inventory_supply"]
	_expect(game.item_is_implemented("tool", "機車"), "motorcycle tool is implemented")
	_expect(game.item_is_implemented("tool", "汽車"), "car tool is implemented")
	_expect(game.item_is_implemented("tool", "遙控骰子"), "remote dice tool is implemented")
	_expect(_stage_tool(game, 0, "機車"), "motorcycle can be staged")
	_expect(_stage_tool(game, 0, "汽車"), "car can be staged")
	var motorcycle_supply: int = int(supply["tools"]["機車"])
	var car_supply: int = int(supply["tools"]["汽車"])
	_prepare_roll(game)
	var motorcycle: Dictionary = game.choose_action("use_tool", {"tool_id": "機車"})
	_expect(bool(motorcycle.get("ok", false)), "motorcycle tool selects two dice")
	_expect_equal(player["vehicle"], "motorcycle", "motorcycle becomes active")
	_expect_equal(player["dice_count"], 2, "motorcycle selects two dice")
	_expect_equal(player["tools"].get("機車", 0), 0, "active motorcycle leaves held tools")
	_expect_equal(int(supply["tools"]["機車"]), motorcycle_supply, "active motorcycle stays out of shared pool")
	var car: Dictionary = game.choose_action("use_tool", {"tool_id": "汽車"})
	_expect(bool(car.get("ok", false)), "car tool switches from motorcycle")
	_expect_equal(player["vehicle"], "car", "car becomes active")
	_expect_equal(player["dice_count"], 3, "car selects three dice")
	_expect_equal(player["tools"].get("機車", 0), 1, "switching returns motorcycle to inventory")
	_expect_equal(player["tools"].get("汽車", 0), 0, "switching consumes car inventory")
	_expect_equal(int(supply["tools"]["汽車"]), car_supply, "active car stays out of shared pool")
	var walking: Dictionary = game.set_vehicle("walking")
	_expect(bool(walking.get("ok", false)), "walking switch returns active car")
	_expect_equal(player["vehicle"], "walking", "walking becomes active")
	_expect_equal(player["dice_count"], 1, "walking uses one die")
	_expect_equal(player["tools"].get("汽車", 0), 1, "walking returns car to inventory")
	_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "active vehicle inventory remains conserved")

	_prepare_roll(game)
	_expect(_stage_tool(game, 0, "遙控骰子"), "remote dice can be staged")
	var remote_owned_before: int = int(player["tools"].get("遙控骰子", 0))
	var remote_supply_before: int = int(supply["tools"]["遙控骰子"])
	var cancelled: Dictionary = game.choose_action("use_tool", {"tool_id": "遙控骰子", "cancel": true})
	_expect(bool(cancelled.get("ok", false)), "remote dice cancellation succeeds")
	_expect_equal(player["tools"].get("遙控骰子", 0), remote_owned_before, "cancelled remote dice stays in inventory")
	_expect_equal(int(supply["tools"]["遙控骰子"]), remote_supply_before, "cancelled remote dice leaves supply unchanged")
	var remote: Dictionary = game.choose_action("use_tool", {"tool_id": "遙控骰子", "value": 4})
	_expect(bool(remote.get("ok", false)), "remote dice accepts one to six")
	_expect_equal(player["tools"].get("遙控骰子", 0), remote_owned_before - 1, "remote dice is consumed on selection")
	_expect_equal(int(supply["tools"]["遙控骰子"]), remote_supply_before + 1, "consumed remote dice returns to supply")
	_expect_equal(game.state["pending_remote_dice"]["value"], 4, "remote value is pending for the next roll")
	var stacked: Dictionary = game.choose_action("use_tool", {"tool_id": "遙控骰子", "value": 5})
	_expect(not bool(stacked.get("ok", false)), "remote dice cannot be stacked")
	var roll: Dictionary = game.roll()
	_expect(bool(roll.get("ok", false)), "pending remote dice roll succeeds")
	_expect_equal(roll.get("dice", []), [4], "pending remote dice controls the next roll")
	_expect_equal(roll.get("total", -1), 4, "pending remote dice controls total")
	_expect_equal(game.state["pending_remote_dice"], {}, "remote dice clears after the controlled roll")
	_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "remote state after roll validates")


func _test_turn_and_equal_poor_cards() -> void:
	var game: Object = _new_graph_inventory(511)
	_expect(game != null, "card effects fixture creates a game")
	if game == null:
		return
	var actor: Dictionary = game.state["players"][0]
	var target: Dictionary = game.state["players"][1]
	_expect(game.item_is_implemented("card", "轉向"), "turn card is implemented")
	_expect(game.item_is_implemented("card", "均貧"), "equal poor card is implemented")
	_expect(_stage_card(game, 0, "轉向"), "turn card can be staged")
	_prepare_roll(game)
	target["position"] = 1
	target["previous_position"] = 0
	var target_position_before: int = int(target["position"])
	var old_previous: int = int(target["previous_position"])
	var turn: Dictionary = game.choose_action("use_card", {"card_id": "轉向", "target_id": 1})
	_expect(bool(turn.get("ok", false)), "turn card targets a living player")
	_expect_equal(int(target["position"]), target_position_before, "turn card leaves target position unchanged")
	_expect(target["previous_position"] >= 0 and target["previous_position"] != old_previous, "turn card changes target direction anchor")
	_expect_equal(actor["cards"].size(), 0, "turn card leaves actor hand")
	_expect_equal(int(game.state["inventory_supply"]["cards"]["轉向"]), 3, "turn card returns to supply after use")
	_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "turn card graph state remains valid")
	var invalid_target: Dictionary = game.choose_action("use_card", {"card_id": "轉向", "target_id": 99})
	_expect(not bool(invalid_target.get("ok", false)), "turn card rejects an invalid target")

	var poor_game: Object = _new_inventory(512)
	if poor_game == null:
		return
	var poor_actor: Dictionary = poor_game.state["players"][0]
	var poor_target: Dictionary = poor_game.state["players"][1]
	_expect(_stage_card(poor_game, 0, "均貧"), "equal poor card can be staged")
	poor_actor["cash"] = 101
	poor_target["cash"] = 202
	poor_game.state["current_player"] = 0
	poor_game.state["phase"] = "await_action"
	poor_game._set_action_options(0)
	var poor: Dictionary = poor_game.choose_action("use_card", {"card_id": "均貧", "target_id": 1})
	_expect(bool(poor.get("ok", false)), "equal poor card targets a living opponent")
	_expect_equal(poor_actor["cash"], 151, "equal poor uses floor average for actor")
	_expect_equal(poor_target["cash"], 151, "equal poor uses floor average for target")
	_expect_equal(poor.get("event", {}).get("rounding_remainder", -1), 1, "equal poor records discarded rounding remainder")
	poor_game.state["players"][1]["alive"] = false
	poor_game.state["players"][1]["bankrupt"] = true
	_expect(_stage_card(poor_game, 0, "均貧"), "second equal poor card can be staged")
	poor_game._set_action_options(0)
	var dead_target: Dictionary = poor_game.choose_action("use_card", {"card_id": "均貧", "target_id": 1})
	_expect(not bool(dead_target.get("ok", false)), "equal poor rejects dead opponents")
	_expect(poor_actor["cards"].has("均貧"), "invalid equal poor target does not consume card")


func _test_effect_save_round_trip_and_legacy() -> void:
	var game: Object = _new_inventory(513)
	if game == null:
		return
	_prepare_roll(game)
	_stage_tool(game, 0, "遙控骰子")
	var remote: Dictionary = game.choose_action("use_tool", {"tool_id": "遙控骰子", "value": 6})
	_expect(bool(remote.get("ok", false)), "remote state fixture stages")
	var saved: Dictionary = game.to_dict()
	_expect(bool(GameState.validate_save(saved).get("ok", false)), "pending remote save validates")
	var restored: Object = GameState.from_dict(JSON.parse_string(game.to_json()))
	_expect(restored != null, "pending remote save round trips")
	if restored != null:
		_expect_equal(restored.to_json(), game.to_json(), "pending remote state round trip is deterministic")
	var malformed: Dictionary = saved.duplicate(true)
	malformed["pending_remote_dice"]["value"] = 7
	_expect(not bool(GameState.validate_save(malformed).get("ok", false)), "remote value outside one to six is rejected")
	var legacy: Object = GameState.new_game(514, 2)
	_expect(legacy != null, "legacy game still creates")
	if legacy != null:
		legacy.state["phase"] = "await_roll"
		legacy._set_action_options(0)
		_expect(not legacy.state["action_options"].has("use_tool"), "legacy game does not expose inventory tools")
		_expect(not bool(legacy.choose_action("use_tool", {"tool_id": "機車"}).get("ok", false)), "legacy game rejects inventory tool action")
		_expect(bool(GameState.validate_save(legacy.to_dict()).get("ok", false)), "legacy save remains valid")
