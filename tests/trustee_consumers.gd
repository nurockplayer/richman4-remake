extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	for ratio in [20, 80]:
		var game: Object = staged(false)
		game.state.players[0].cash = 5000
		game.state.players[0].deposit = 5000
		game.state.bank.deposits = 5000 + int(game.state.players[1].deposit)
		game.state.bank_access = true
		configure(game, {"cash_ratio":ratio})
		qualify(game, "bank ratio %d" % ratio)
		check(game.run_ai_turn().get("ok", false), "bank ratio AI completes")
		check(game.state.players[0].cash == ratio * 100, "bank target consumes runtime ratio %d" % ratio)
	for ratio in [0, 10, 100]:
		var game: Object = staged(false)
		game.state.players[0].cash = 4000
		game.state.players[0].deposit = 0
		game.state.bank.deposits = int(game.state.players[1].deposit)
		configure(game, {"stock_ratio":ratio})
		qualify(game, "stock ratio %d" % ratio)
		check(game.run_ai_turn().get("ok", false), "stock ratio AI completes")
		var count := 0
		for quantity in game.state.players[0].stocks.values(): count += int(quantity)
		var unit_price := int(game.state.market.prices[game.get_stock_symbols()[0]])
		var expected := 0 if ratio == 0 else int(400 / unit_price) if ratio == 10 else int(1000 / unit_price) + 1
		check(count == expected, "stock budget consumes runtime ratio %d (shares %d)" % [ratio,count])
	for enabled in [false, true]:
		var game: Object = staged(true)
		var player: Dictionary = game.state.players[0]
		player.cash = 1000
		check(Inventory.grant_card(game.state.inventory_supply, player.cards, "紅").ok, "stage real inventory card")
		configure(game, {"use_cards":enabled})
		qualify(game, "card flag")
		check(game.run_ai_turn().get("ok", false), "card AI completes")
		check(player.cards.has("紅") != enabled, "card flag gates actual automatic card consumption")
		game = staged(true)
		player = game.state.players[0]
		check(Inventory.grant_tool(game.state.inventory_supply, player.tools, "遙控骰子", 1).ok, "stage real inventory tool")
		game.state.phase = "await_roll"
		configure(game, {"use_tools":enabled})
		qualify(game, "tool flag")
		check(game.run_ai_turn().get("ok", false), "tool AI completes")
		check(int(player.tools.get("遙控骰子", 0)) == (0 if enabled else 1), "tool flag gates actual automatic tool consumption")
	for reserve_cash in [250, 750]:
		for personality in range(3):
			var game: Object = staged(false)
			var tile: Dictionary = {}
			for candidate in game.state.board:
				if candidate.kind == "property":
					tile = candidate
					break
			tile.owner = 0
			game.state.players[0].properties.append(int(tile.index))
			game.state.players[0].position = tile.index
			game.state.players[0].cash = game._upgrade_price(tile) + reserve_cash
			game._recalculate_property_values()
			configure(game, {"personality":personality})
			qualify(game, "personality")
			check(game.run_ai_turn().get("ok", false), "personality AI completes")
			var should_upgrade: bool = reserve_cash >= [1000,500,0][personality]
			check((int(tile.building_level) == 1) == should_upgrade, "three personalities consume distinct reserve policy")
	print("Trustee consumer checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
func staged(inventory: bool) -> Object:
	var game: Object = Game.new_game(510, 2, {"start_date":{"year":1998,"month":1,"day":1}, "original_inventory":inventory})
	var player: Dictionary = game.state.players[0]
	if inventory:
		for card in player.cards.duplicate(): Inventory.consume_card(game.state.inventory_supply, player.cards, card)
		for tool in player.tools.keys():
			if int(player.tools[tool]) > 0: Inventory.consume_tool(game.state.inventory_supply, player.tools, tool, int(player.tools[tool]))
	else:
		player.cards = []
	game.set_player_ai(0, true)
	game.state.phase = "await_action"
	game.state.bank_access = false
	return game
func configure(game: Object, patch: Dictionary) -> void:
	var preferences := {"use_cards":false,"use_tools":false,"personality":1,"cash_ratio":50,"stock_ratio":0}
	preferences.merge(patch,true)
	game.state.trustee_preferences = {"0":preferences}
	game._sync_state()
	game._set_action_options(0)
func qualify(game: Object, label: String) -> void:
	var result: Dictionary = Game.validate_save(game.to_dict())
	check(result.get("ok", false), "qualified save " + label + " " + str(result.get("errors", [])))
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
