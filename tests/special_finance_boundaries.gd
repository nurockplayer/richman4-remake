extends "res://tests/special_finance.gd"


func _initialize() -> void:
	_test_public_admission()
	_test_ledger_headroom()
	_test_collection_headroom()
	print("Special finance boundary checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _test_public_admission() -> void:
	var game: Object = make_game()
	var before: String = game.to_json()
	expect(game.special_finance_limit("take_special_finance", 1) == 0, "query cannot borrow for another actor")
	expect(game.to_json() == before, "limit query is read-only")
	for stage in ["await_roll", "await_route"]:
		game.state.phase = stage
		rejected(game, "take_special_finance", 1, "wrong phase " + stage)
	game.state.phase = "await_action"
	game.state.players[0].hospital_days = 2
	game._set_action_options(0)
	rejected(game, "take_special_finance", 1, "hospitalized borrower")
	game.state.players[0].hospital_days = 0
	game.state.players[0]["winter_sleep_days"] = 2
	game._set_action_options(0)
	rejected(game, "take_special_finance", 1, "sleeping borrower")
	game.state.players[0].erase("winter_sleep_days")
	game.state.day = 4
	game._sync_state()
	game._set_action_options(0)
	rejected(game, "take_special_finance", 1, "Sunday bank closure")
	game.state.day = 1
	game._sync_state()
	enter(game, 0)
	if not take(game, 100):
		return
	game.state.players[0].loan_block_days = 2
	game._set_action_options(0)
	rejected(game, "take_special_finance", 1, "borrowing restriction retains prior debt")
	expect(bool(game.choose_action("repay_special_finance", {"amount": 100}).ok), "news restriction still permits repayment")
	valid(game, "repayment during borrowing restriction")


func _test_ledger_headroom() -> void:
	var game: Object = make_game()
	var other_deposits := 0
	for index in range(1, 4):
		other_deposits += int(game.state.players[index].deposit)
	game.state.players[0].deposit = LIMIT - other_deposits
	game.state.bank.deposits = LIMIT
	game._set_action_options(0)
	valid(game, "saturated deposit mirror fixture")
	rejected(game, "take_special_finance", 1, "saturated bank deposit mirror")
	game = make_game()
	game.state.players[0].cash = 1000
	game.state.players[0].deposit = LIMIT - 2
	for index in range(1, 4):
		game.state.players[index].deposit = 1 if index == 1 else 0
	game.state.bank.deposits = LIMIT - 1
	game._set_action_options(0)
	valid(game, "staged exact player and bank headroom")
	expect(capacity(game) == 1, "player deposit headroom bounds financing")
	if take(game, 1):
		rejected(game, "take_special_finance", 1, "full player deposit")
		valid(game, "maximum deposit financing")


func _test_collection_headroom() -> void:
	var game: Object = make_game()
	if not take(game, 1000):
		return
	balances(game, 0, 2000, 0)
	game.state.bank.cash = LIMIT
	game._set_action_options(0)
	rejected(game, "repay_special_finance", 1, "bank cash headroom prevents manual overflow")
	enter(game, 1)
	expect(bool(game.choose_action("buy_company", {"quantity": 2}).ok), "chair takeover while cash counter is full")
	expect(game.state.players[0].alive and principal(game) == 1000, "solvent former chair is deferred at bank cash bound")
	expect(game.state.bank.cash == LIMIT and game.state.bank.loans == 0, "deferred collection cannot overflow or become normal loan")
	valid(game, "deferred owner loss")
	game.state.bank.cash -= 1000
	game._update_company_owners()
	expect(principal(game) == 0 and game.state.players[0].cash == 1000, "next source reconciliation completes deferred collection")
	expect(game.state.current_player == 1 and game.state.bank.cash == LIMIT, "completion preserves actor and cash bound")
	valid(game, "deferred collection complete")
