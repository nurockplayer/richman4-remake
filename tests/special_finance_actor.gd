extends "res://tests/special_finance.gd"


func _initialize() -> void:
	for phase in ["await_action", "await_roll"]:
		_test_self_sale(0, phase)
		_test_self_sale(3, phase)
	_test_last_survivor()
	_test_solvent_sale()
	print("Special finance actor checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func financed_actor(player_id: int) -> Object:
	var game: Object = make_game()
	if player_id != 0:
		enter(game, player_id)
		expect(bool(game.choose_action("buy_company", {"quantity": 2}).ok), "later actor takes chair")
	expect(bool(game.choose_action("take_special_finance", {"amount": 1000}).ok), "current chair finances before self sale")
	balances(game, player_id, 0, 0)
	return game


func sell_all(game: Object, player_id: int) -> Dictionary:
	return game.choose_action("sell_stock", {"symbol": "s01", "quantity": int(game.state.players[player_id].stocks.s01)})


func _test_self_sale(player_id: int, phase: String) -> void:
	var game: Object = financed_actor(player_id)
	game.state.phase = phase
	game._set_action_options(player_id)
	valid(game, "self sale initial phase " + phase)
	var copy: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(copy != null, "self sale initial state reloads")
	var turn_before: int = game.state.turn
	var day_before: int = game.state.day
	expect(bool(sell_all(game, player_id).ok), "self sale resolves through public action")
	expect(not bool(game.state.players[player_id].alive) and principal(game, player_id) == 0, "self sale liquidates insolvent chair")
	var next_id := (player_id + 1) % 4
	expect(int(game.state.current_player) == next_id and game.state.phase == "await_roll", "self sale admits next living actor")
	expect(game.state.turn == turn_before + 1 and game.state.day == day_before + (1 if player_id == 3 else 0), "self sale advances exactly one turn and only wraps day")
	expect(game.state.action_options.has("buy_stock") and game.state.action_options.has("sell_stock"), "new actor retains its legal stock actions")
	expect(not game.state.bank_access and not game.state.bank_landing and game.state.company_purchase_remaining == 1000, "new actor has fresh bank and company visit boundaries")
	valid(game, "self sale result " + phase)
	if copy != null:
		expect(bool(sell_all(copy, player_id).ok) and copy.to_json() == game.to_json(), "self sale continuation is deterministic")
	var reloaded: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(reloaded != null, "post sale save remains loadable")
	if reloaded != null and int(game.state.current_player) == next_id:
		var rolled: Dictionary = game.roll()
		var replay: Dictionary = reloaded.roll()
		expect(bool(rolled.ok) and bool(replay.ok), "next living actor can roll")
		expect(game.to_json() == reloaded.to_json(), "next actor RNG continues after load")


func _test_last_survivor() -> void:
	var game: Object = financed_actor(0)
	balances(game, 2, 0, 0)
	balances(game, 3, 0, 0)
	game._declare_bankruptcy(2, -1, 1, "actor_fixture")
	game._declare_bankruptcy(3, -1, 1, "actor_fixture")
	game._set_action_options(0)
	valid(game, "two survivor fixture")
	var turn_before: int = game.state.turn
	expect(bool(sell_all(game, 0).ok), "final debtor sale resolves")
	expect(game.state.phase == "game_over" and game.state.winner == 1 and game.state.action_options.is_empty(), "last survivor ends match")
	expect(game.state.turn == turn_before, "game over does not admit another turn")
	valid(game, "final chair bankruptcy")


func _test_solvent_sale() -> void:
	var game: Object = make_game()
	expect(bool(game.choose_action("take_special_finance", {"amount": 1000}).ok), "solvent chair borrows")
	var turn_before: int = game.state.turn
	expect(bool(sell_all(game, 0).ok), "solvent chair sells")
	expect(game.state.players[0].alive and principal(game) == 0, "solvent chair repays without bankruptcy")
	expect(game.state.current_player == 0 and game.state.phase == "await_action" and game.state.turn == turn_before, "solvent sale preserves actor and turn")
	expect(game.state.action_options.has("end_turn"), "solvent actor can finish turn")
	valid(game, "solvent self sale")
