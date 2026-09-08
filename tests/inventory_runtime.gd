extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_inventory_setup_and_round_trip()
	_test_inventory_validation_and_conservation()
	_test_shop_landing_and_atomic_trades()
	_test_inventory_card_lifecycle()
	_test_inventory_ai_skips_unsupported_cards()
	_test_inventory_remote_turn_guards()
	_test_v3_remains_legacy()
	_test_inventory_ai_continuation()
	print("Inventory runtime checks: %d, failures: %d" % [_checks, _failures])
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


func _new_graph_inventory() -> Object:
	var raw: Dictionary = Fixture.make()
	raw["nodes"][1]["event_code"] = 15
	var normalized: Dictionary = Maps.normalize_map(raw)
	if not bool(normalized.get("ok", false)):
		return null
	return GameState.new_game_on_board(101, 2, normalized["definition"], _options())


func _shop_player(game: Object) -> void:
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["players"][0]["position"] = 1
	game._set_action_options(0)


func _card_conservation_sum(game: Object) -> int:
	var total: int = 0
	for item in game.shop_items():
		if item.get("item_kind", "") == "card":
			total += int(item.get("stock", 0))
	for player in game.state.get("players", []):
		total += player.get("cards", []).size()
	return total


func _seed_for_card(identifier: String, starting_supply: Dictionary = {}) -> int:
	for seed in range(1, 10000):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var supply: Dictionary = Inventory.new_supply() if starting_supply.is_empty() else starting_supply.duplicate(true)
		if Inventory.draw_card(supply, rng) == identifier:
			return seed
	return -1


func _test_inventory_setup_and_round_trip() -> void:
	var game: Object = GameState.new_game(100, 2, _options())
	_expect(game != null, "original inventory setup creates a game")
	if game == null:
		return
	_expect_equal(game.state["version"], 4, "original inventory setup uses version four")
	_expect(game.state.has("inventory_supply"), "inventory setup persists shared supply")
	_expect_equal(game.state["players"][0]["points"], 0, "inventory setup initializes points")
	_expect_equal(game.state["players"][0]["tools"].size(), 6, "inventory setup initializes opening tools")
	_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "new inventory save validates")
	var parsed: Variant = JSON.parse_string(game.to_json())
	_expect(parsed is Dictionary, "inventory JSON parses")
	var restored: Object = GameState.from_dict(parsed if parsed is Dictionary else {})
	_expect(restored != null, "inventory JSON round trips")
	if restored != null:
		_expect_equal(restored.to_json(), game.to_json(), "inventory JSON round trip is deterministic")
	var path := "user://inventory-runtime-round-trip.json"
	_expect(game.save_to_path(path), "inventory save writes to disk")
	var disk_restored: Object = GameState.load_from_path(path)
	_expect(disk_restored != null, "inventory save reloads from disk")
	if disk_restored != null:
		_expect_equal(disk_restored.to_json(), game.to_json(), "inventory disk round trip is deterministic")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_inventory_validation_and_conservation() -> void:
	var game: Object = GameState.new_game(102, 2, _options())
	_expect(game != null, "inventory validation fixture creates a game")
	if game == null:
		return
	var valid: Dictionary = game.to_dict()
	var missing_supply: Dictionary = valid.duplicate(true)
	missing_supply["inventory_supply"]["cards"].erase("均富")
	_expect(not bool(GameState.validate_save(missing_supply).get("ok", false)), "missing catalogue supply key is rejected")
	var conservation: Dictionary = valid.duplicate(true)
	conservation["inventory_supply"]["cards"]["均富"] += 1
	_expect(not bool(GameState.validate_save(conservation).get("ok", false)), "card conservation mismatch is rejected")
	var unknown_card: Dictionary = valid.duplicate(true)
	unknown_card["players"][0]["cards"].append("不存在")
	_expect(not bool(GameState.validate_save(unknown_card).get("ok", false)), "unknown v4 card is rejected")
	for malformed_count in [{"bad": true}, ["bad"], "bad", 1.5]:
		var malformed: Dictionary = valid.duplicate(true)
		malformed["inventory_supply"]["cards"]["均富"] = malformed_count
		var malformed_result: Dictionary = GameState.validate_save(malformed)
		_expect(not bool(malformed_result.get("ok", false)), "malformed card supply count is rejected: " + str(malformed_count))
		_expect(GameState.from_dict(malformed) == null, "malformed card supply count cannot load: " + str(malformed_count))
		var malformed_tool: Dictionary = valid.duplicate(true)
		malformed_tool["inventory_supply"]["tools"]["機車"] = malformed_count
		var malformed_tool_result: Dictionary = GameState.validate_save(malformed_tool)
		_expect(not bool(malformed_tool_result.get("ok", false)), "malformed tool supply count is rejected: " + str(malformed_count))
		_expect(GameState.from_dict(malformed_tool) == null, "malformed tool supply count cannot load: " + str(malformed_count))
	var json_numbers: Dictionary = valid.duplicate(true)
	json_numbers["players"][0]["points"] = 0.0
	json_numbers["inventory_supply"]["cards"]["均富"] = float(json_numbers["inventory_supply"]["cards"]["均富"])
	json_numbers["inventory_supply"]["tools"]["機車"] = float(json_numbers["inventory_supply"]["tools"]["機車"])
	_expect(bool(GameState.validate_save(json_numbers).get("ok", false)), "integral JSON floats remain valid")
	var canonical: Object = GameState.from_dict(json_numbers)
	_expect(canonical != null, "integral JSON floats canonicalize on load")
	if canonical != null:
		_expect_equal(typeof(canonical.state["players"][0]["points"]), TYPE_INT, "canonicalized points use integer storage")
		_expect(bool(GameState.validate_save(canonical.to_dict()).get("ok", false)), "canonicalized inventory save validates")


func _test_shop_landing_and_atomic_trades() -> void:
	var game: Object = _new_graph_inventory()
	_expect(game != null, "inventory shop fixture creates a graph game")
	if game == null:
		return
	_shop_player(game)
	_expect(game.is_shop_available(), "event code fifteen landing opens the shop")
	_expect(game.state["board"][1]["kind"] == "unsupported", "OriginalMaps classification remains unchanged")
	_expect(game.state["action_options"].has("buy_item"), "shop landing exposes buy action")
	_expect(game.state["action_options"].has("sell_item"), "shop landing exposes sell action")
	var items: Array = game.shop_items()
	_expect_equal(items.size(), 38, "shop lists all cards and finite tools")
	var implemented_cards: int = 0
	var research_tools: int = 0
	for item in items:
		if item.get("item_kind", "") == "card" and bool(item.get("implemented", false)):
			implemented_cards += 1
		if item.get("item_kind", "") == "tool" and bool(item.get("implemented", false)):
			research_tools += 1
	_expect_equal(implemented_cards, 7, "shop metadata marks exactly seven implemented cards")
	_expect_equal(research_tools, 3, "shop metadata marks exactly three implemented tools")
	_expect(game.item_is_implemented("card", "均富"), "implemented card metadata is public")
	_expect(not game.item_is_implemented("card", "天使"), "unimplemented card metadata is public")
	_expect(game.item_is_implemented("tool", "機車"), "implemented tool metadata is public")
	var player: Dictionary = game.state["players"][0]
	player["points"] = 500
	var buy_card: Dictionary = game.choose_action("buy_item", {"item_kind": "card", "item_id": "均貧", "quantity": 1})
	_expect(bool(buy_card.get("ok", false)), "shop buys a catalogue card")
	_expect(player["cards"].has("均貧"), "bought card enters the hand")
	_expect_equal(player["points"], 300, "card purchase debits points")
	var sell_card: Dictionary = game.choose_action("sell_item", {"item_kind": "card", "item_id": "均貧", "quantity": 1})
	_expect(bool(sell_card.get("ok", false)), "shop sells a catalogue card")
	_expect_equal(player["points"], 480, "card sale returns the listed sale price")
	var before_error: Dictionary = game.to_dict()
	var invalid_quantity: Dictionary = game.choose_action("buy_item", {"item_kind": "card", "item_id": "均貧", "quantity": 2})
	_expect(not bool(invalid_quantity.get("ok", false)), "card quantity greater than one is rejected")
	_expect_equal(game.state["players"][0]["points"], before_error["players"][0]["points"], "invalid trade leaves points unchanged")
	_expect_equal(game.state["inventory_supply"], before_error["inventory_supply"], "invalid trade leaves supply unchanged")
	player["points"] = 0
	var insufficient_points: Dictionary = game.choose_action("buy_item", {"item_kind": "tool", "item_id": "機車", "quantity": 1})
	_expect(not bool(insufficient_points.get("ok", false)), "insufficient points reject purchase")
	_expect_equal(game.state["players"][0]["tools"].get("機車", 0), 0, "insufficient points leave tools unchanged")
	player["points"] = 500
	var buy_tool: Dictionary = game.choose_action("buy_item", {"item_kind": "tool", "item_id": "機車", "quantity": 2})
	_expect(bool(buy_tool.get("ok", false)), "shop buys a finite tool quantity")
	_expect_equal(player["tools"].get("機車", 0), 2, "bought tools enter the inventory")
	var sell_tool: Dictionary = game.choose_action("sell_item", {"item_kind": "tool", "item_id": "機車", "quantity": 2})
	_expect(bool(sell_tool.get("ok", false)), "shop sells a finite tool quantity")
	_expect_equal(player["tools"].get("機車", 0), 0, "sold tools leave the inventory")
	_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "post-trade inventory save validates")
	var trade_restored: Object = GameState.from_dict(JSON.parse_string(game.to_json()))
	_expect(trade_restored != null, "post-trade inventory JSON reloads")
	_expect(not bool(game.choose_action("buy_vehicle", {"vehicle": "car"}).get("ok", false)), "inventory mode rejects cash vehicle purchase")
	var pass_game: Object = _new_graph_inventory()
	if pass_game != null:
		pass_game.state["phase"] = "await_roll"
		pass_game.state["players"][0]["position"] = 0
		pass_game._set_action_options(0)
		_expect(not pass_game.is_shop_available(), "shop is unavailable away from landing")


func _test_inventory_card_lifecycle() -> void:
	var game: Object = _new_graph_inventory()
	_expect(game != null, "inventory card fixture creates a graph game")
	if game == null:
		return
	var player: Dictionary = game.state["players"][0]
	var supply: Dictionary = game.state["inventory_supply"]
	var before_total: int = _card_conservation_sum(game)
	var draw_before: int = player["cards"].size()
	game._draw_event_card(0)
	_expect_equal(player["cards"].size(), draw_before + 1, "card landing receives one card")
	_expect_equal(_card_conservation_sum(game), before_total, "draw conserves the finite card pool")
	var pass_game: Object = _new_graph_inventory()
	_expect(pass_game != null, "graph pass fixture creates a game")
	if pass_game == null:
		return
	var pass_player: Dictionary = pass_game.state["players"][0]
	var pass_supply: Dictionary = pass_game.state["inventory_supply"]
	var direct_before: int = _card_conservation_sum(pass_game)
	var nonlegacy_seed: int = _seed_for_card("均貧", pass_supply)
	_expect(nonlegacy_seed > 0, "weighted card probe finds a non-legacy card seed")
	pass_game._rng.seed = nonlegacy_seed
	pass_game.state["current_player"] = 0
	pass_game.state["phase"] = "await_roll"
	pass_player["position"] = 1
	pass_player["previous_position"] = -1
	pass_game.state["last_total"] = 3
	pass_game.state["last_roll"] = [3]
	pass_game._graph_begin_movement(0, 3)
	_expect(pass_game.state["phase"] == "await_route", "graph pass enters the first route choice")
	pass_game.choose_route(2)
	pass_game.choose_route(5)
	if pass_game.state["phase"] == "await_route":
		pass_game.choose_route(5)
	_expect(pass_player["cards"].has("均貧"), "graph pass receives the weighted non-legacy card")
	_expect_equal(_card_conservation_sum(pass_game), direct_before, "graph pass conserves the finite card pool")
	var empty_game: Object = _new_graph_inventory()
	if empty_game != null:
		for card_id in empty_game.state["inventory_supply"]["cards"].keys():
			empty_game.state["inventory_supply"]["cards"][card_id] = 0
		empty_game._rng.seed = 700
		var empty_rng_state: int = int(empty_game._rng.state)
		empty_game._grant_random_card(0, "empty_card_pass_test")
		_expect_equal(int(empty_game._rng.state), empty_rng_state, "empty card pool does not consume RNG")
		_expect(empty_game.state["players"][0]["cards"].is_empty(), "empty card pool does not grant a card")
	var grant: Dictionary = Inventory.grant_card(supply, player["cards"], "停留")
	_expect(bool(grant.get("ok", false)), "implemented card can be staged for use")
	game.state["phase"] = "await_roll"
	game._set_action_options(0)
	var phase_before: String = str(game.state["phase"])
	var supply_before_use: int = int(supply["cards"]["停留"])
	var used: Dictionary = game.choose_action("use_card", {"card_id": "停留"})
	_expect(bool(used.get("ok", false)), "inventory card can be used before rolling")
	_expect_equal(game.state["phase"], phase_before, "card use keeps the current phase")
	_expect_equal(int(supply["cards"]["停留"]), supply_before_use + 1, "successful card use returns the card to supply")
	var unknown_grant: Dictionary = Inventory.grant_card(supply, player["cards"], "天使")
	_expect(bool(unknown_grant.get("ok", false)), "unimplemented card can be held")
	var unknown_cards: Array = player["cards"].duplicate(true)
	var unknown_supply: Dictionary = supply.duplicate(true)
	var unknown_use: Dictionary = game.choose_action("use_card", {"card_id": "天使"})
	_expect(not bool(unknown_use.get("ok", false)), "unimplemented card use returns an error")
	_expect_equal(player["cards"], unknown_cards, "unknown card error does not consume the card")
	_expect_equal(supply, unknown_supply, "unknown card error does not change supply")
	game.state["phase"] = "await_route"
	game._set_action_options(0)
	_expect(not bool(game.choose_action("use_card", {"card_id": "天使"}).get("ok", false)), "route phase rejects card use")
	game.state["phase"] = "await_roll"
	game._set_action_options(0)
	game.state["players"][0]["cash"] = 0
	var deposit_before_bankruptcy: int = int(game.state["players"][0]["deposit"])
	game.state["players"][0]["deposit"] = 0
	game.state["bank"]["deposits"] -= deposit_before_bankruptcy
	game._declare_bankruptcy(0, -1, 1, "inventory_test")
	_expect(not bool(game.state["players"][0]["alive"]), "bankruptcy marks the player dead")
	_expect(game.state["players"][0]["cards"].size() > 0, "bankruptcy preserves held cards")
	_expect(game.state["players"][0]["tools"].size() > 0, "bankruptcy preserves held tools")
	_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "bankruptcy-preserved inventory remains conserved")


func _test_v3_remains_legacy() -> void:
	var game: Object = GameState.new_game(103, 2, {"start_date": {"year": 1998, "month": 1, "day": 1}, "original_inventory": false})
	_expect(game != null, "explicitly disabled inventory keeps setup game")
	if game == null:
		return
	_expect_equal(game.state["version"], 3, "disabled inventory keeps version three")
	_expect(not game.state.has("inventory_supply"), "legacy setup has no inventory supply")
	_expect(not game.state["players"][0].has("tools"), "legacy setup has no tool field")
	_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "legacy setup save remains valid")


func _test_inventory_ai_skips_unsupported_cards() -> void:
	var game: Object = GameState.new_game(104, 2, _options())
	_expect(game != null, "inventory AI card fixture creates a game")
	if game == null:
		return
	var player: Dictionary = game.state["players"][0]
	player["cash"] = 0
	player["cards"] = []
	var supply: Dictionary = game.state["inventory_supply"]
	_expect(bool(Inventory.grant_card(supply, player["cards"], "天使").get("ok", false)), "AI fixture grants unsupported card")
	_expect(bool(Inventory.grant_card(supply, player["cards"], "停留").get("ok", false)), "AI fixture grants implemented card after it")
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game._set_action_options(0)
	game._ai_action(0)
	_expect(player["cards"].has("天使"), "AI retains unsupported card")
	_expect(not player["cards"].has("停留"), "AI scans past unsupported card")
	_expect_equal(player["stay_next"], 1, "AI uses later implemented card")
	_expect_equal(int(supply["cards"]["停留"]), 4, "AI use returns implemented card to pool")


func _test_inventory_remote_turn_guards() -> void:
	var blocked_cases := [
		{"field": "skip_turns", "message": "skip turn"},
		{"field": "turtle_days", "message": "turtle turn"},
		{"field": "stay_next", "message": "stay turn"},
	]
	for blocked_case in blocked_cases:
		var blocked: Object = GameState.new_game(106 + _checks, 2, _options())
		_expect(blocked != null, "remote guard fixture creates a game: " + str(blocked_case.message))
		if blocked == null:
			continue
		var blocked_player: Dictionary = blocked.state["players"][0]
		var blocked_supply: Dictionary = blocked.state["inventory_supply"]
		var remote_before: int = int(blocked_player["tools"].get("遙控骰子", 0))
		var remote_pool_before: int = int(blocked_supply["tools"]["遙控骰子"])
		blocked_player[blocked_case.field] = 1
		blocked.state["phase"] = "await_roll"
		blocked._set_action_options(0)
		var blocked_use: Dictionary = blocked.choose_action("use_tool", {"tool_id": "遙控骰子", "value": 4})
		_expect(not bool(blocked_use.get("ok", false)), "remote rejects unusable " + str(blocked_case.message))
		_expect_equal(int(blocked_player["tools"].get("遙控骰子", 0)), remote_before, "rejected remote leaves tool for " + str(blocked_case.message))
		_expect_equal(int(blocked_supply["tools"]["遙控骰子"]), remote_pool_before, "rejected remote leaves supply for " + str(blocked_case.message))
		_expect(not blocked.state["action_options"].has("use_tool"), "unusable remote is absent from options for " + str(blocked_case.message))

	var pending_game: Object = GameState.new_game(120, 2, _options())
	_expect(pending_game != null, "pending remote guard fixture creates a game")
	if pending_game == null:
		return
	var pending_player: Dictionary = pending_game.state["players"][0]
	var pending_supply: Dictionary = pending_game.state["inventory_supply"]
	pending_game.state["phase"] = "await_roll"
	pending_game._set_action_options(0)
	var pending_use: Dictionary = pending_game.choose_action("use_tool", {"tool_id": "遙控骰子", "value": 6})
	_expect(bool(pending_use.get("ok", false)), "remote can be staged for pending guard")
	var stay_supply_before: int = int(pending_supply["cards"]["停留"])
	_expect(bool(Inventory.grant_card(pending_supply, pending_player["cards"], "停留").get("ok", false)), "pending guard stages movement card")
	var pending_cards_before: Array = pending_player["cards"].duplicate(true)
	var pending_card_use: Dictionary = pending_game.choose_action("use_card", {"card_id": "停留"})
	_expect(not bool(pending_card_use.get("ok", false)), "pending remote rejects stay card")
	_expect_equal(pending_player["cards"], pending_cards_before, "pending remote leaves movement card held")
	_expect_equal(int(pending_supply["cards"]["停留"]), stay_supply_before - 1, "pending remote leaves card supply unchanged after staging")
	var pending_vehicle: Dictionary = pending_game.choose_action("set_vehicle", {"vehicle": "walking"})
	_expect(not bool(pending_vehicle.get("ok", false)), "pending remote rejects vehicle changes")
	_expect_equal(pending_game.state["pending_remote_dice"]["value"], 6, "pending remote remains after rejected movement actions")
	_expect(not pending_game.state["action_options"].has("use_card"), "pending remote hides card action")
	_expect(not pending_game.state["action_options"].has("use_tool"), "pending remote hides tool action")
	var pending_save: Dictionary = pending_game.to_dict()
	_expect(bool(GameState.validate_save(pending_save).get("ok", false)), "clean pending remote save validates")
	for modifier in ["skip_turns", "turtle_days", "stay_next"]:
		for malformed_value in [{}, [], "invalid", 0.5]:
			var malformed_modifier_save: Dictionary = pending_save.duplicate(true)
			malformed_modifier_save["players"][0][modifier] = malformed_value
			var malformed_modifier_result: Variant = GameState.validate_save(malformed_modifier_save)
			_expect(malformed_modifier_result is Dictionary and not bool(malformed_modifier_result.get("ok", true)), "malformed pending movement modifier is rejected without runtime error: " + modifier)
	var blocked_save: Dictionary = pending_save.duplicate(true)
	blocked_save["players"][0]["skip_turns"] = 1
	_expect(not bool(GameState.validate_save(blocked_save).get("ok", false)), "pending remote with skip turn cannot load")
	_expect(GameState.from_dict(blocked_save) == null, "pending remote with skip turn is rejected on load")
	var blocked_turtle_save: Dictionary = pending_save.duplicate(true)
	blocked_turtle_save["players"][0]["turtle_days"] = 1
	_expect(not bool(GameState.validate_save(blocked_turtle_save).get("ok", false)), "pending remote with turtle turn cannot load")
	var blocked_stay_save: Dictionary = pending_save.duplicate(true)
	blocked_stay_save["players"][0]["stay_next"] = 1
	_expect(not bool(GameState.validate_save(blocked_stay_save).get("ok", false)), "pending remote with stay turn cannot load")


func _test_inventory_ai_continuation() -> void:
	var game: Object = _new_graph_inventory()
	_expect(game != null, "inventory AI fixture creates a graph game")
	if game == null:
		return
	game.set_player_ai(0, true)
	var result: Dictionary = game.run_ai_turn()
	_expect(bool(result.get("ok", false)), "AI completes a legal inventory turn")
	_expect(not game.state.get("action_options", []).has("buy_vehicle"), "AI inventory options do not expose cash vehicle purchase")
	_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "AI inventory turn leaves a valid save")
