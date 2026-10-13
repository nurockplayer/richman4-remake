extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")
const LIMIT := 1000000000000
var checks := 0
var failures := 0


func _initialize() -> void:
	_test_source_wealth_and_repayment()
	_test_capacity_and_ownership()
	_test_rejections_and_save()
	print("Special finance checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func valid(game: Object, label: String) -> void:
	var result: Dictionary = Game.validate_save(game.to_dict())
	expect(bool(result.ok), label + str(result.get("errors", [])))


func enter(game: Object, player_id: int) -> void:
	game.state.current_player = player_id
	game.state.phase = "await_action"
	game.state.players[player_id].position = 5
	game.state.players[player_id].previous_position = 4
	game.state.bank_access = false
	game.state.bank_landing = false
	game._resolve_company_visit(player_id, game.state.board[5])
	game._set_action_options(player_id)


func make_game() -> Object:
	var definition: Dictionary = Fixture.definition()
	definition.companies[0].company_type = 7
	var game: Object = Game.new_game_on_board(124, 4, definition, {"original_facilities": true, "original_gods": true, "original_companies": true, "start_date": {"year": 1998, "month": 1, "day": 1}})
	game.state.god_objects = []
	enter(game, 0)
	valid(game, "type7 bank fixture")
	expect(bool(game.choose_action("buy_company", {"quantity": 1}).get("ok", false)), "public share purchase establishes chair")
	return game


func principal(game: Object, player_id: int = 0) -> int:
	return int(game.state.players[player_id].get("special_finance", 0))


func capacity(game: Object, action: String = "take_special_finance") -> int:
	expect(game.has_method("special_finance_limit"), "read-only special financing limit exists")
	return int(game.call("special_finance_limit", action)) if game.has_method("special_finance_limit") else -1


func take(game: Object, amount: int) -> bool:
	var result: Dictionary = game.choose_action("take_special_finance", {"amount": amount})
	expect(bool(result.get("ok", false)), "public special financing succeeds")
	return bool(result.get("ok", false))


func rejected(game: Object, action: String, amount: Variant, label: String) -> void:
	var before: String = game.to_json()
	expect(not bool(game.choose_action(action, {"amount": amount}).get("ok", false)), label + " rejects")
	expect(game.to_json() == before, label + " preserves state/RNG")


func balances(game: Object, player_id: int, cash: int, deposit: int) -> void:
	var player: Dictionary = game.state.players[player_id]
	game.state.bank.deposits += deposit - int(player.deposit)
	player.cash = cash
	player.deposit = deposit
	game._set_action_options(int(game.state.current_player))
	valid(game, "staged balance")


func _test_source_wealth_and_repayment() -> void:
	var game: Object = make_game()
	var cash: int = game.state.players[0].cash
	var deposit: int = game.state.players[0].deposit
	var bank: Dictionary = game.state.bank.duplicate(true)
	var wealth: int = game.get_player_wealth(0)
	var maximum := 0
	for player in game.state.players:
		if int(player.id) != 0:
			maximum += int(player.deposit)
	expect(game.state.action_options.has("take_loan") and game.state.action_options.has("deposit"), "type7 company bank admits ordinary banking")
	expect(capacity(game) == maximum, "chair credit equals other deposits")
	if not take(game, 1000):
		return
	expect(game.state.players[0].deposit == deposit + 1000 and game.state.players[0].cash == cash and principal(game) == 1000, "source financing increases deposit and separate principal")
	expect(game.state.players[0].loan == 0 and game.state.players[0].loan_due_day == 0, "special financing never becomes ordinary loan")
	expect(game.get_player_wealth(0) == wealth + 1000, "source oddity: financing contributes to wealth")
	expect(game.state.bank.cash == bank.cash and game.state.bank.loans == bank.loans and game.state.bank.deposits == bank.deposits + 1000, "financing uses deposit mirror without normal loan ledger or bank cash")
	expect(capacity(game) == maximum - 1000, "outstanding special principal reduces new credit")
	expect(bool(game.choose_action("repay_special_finance", {"amount": 400}).get("ok", false)), "partial special repayment succeeds")
	expect(game.state.players[0].deposit == deposit + 600 and game.state.players[0].cash == cash and principal(game) == 600, "partial repayment uses deposits first")
	expect(bool(game.choose_action("repay_special_finance", {"amount": 600}).get("ok", false)), "full special repayment succeeds")
	expect(principal(game) == 0 and game.get_player_wealth(0) == wealth and game.state.bank == bank, "full repayment restores wealth and bank ledger")
	valid(game, "voluntary repayment")
	if not take(game, 2000):
		return
	balances(game, 0, 3000, 500)
	bank = game.state.bank.duplicate(true)
	expect(bool(game.choose_action("repay_special_finance", {"amount": 1500}).get("ok", false)), "cash completes partial repayment")
	expect(game.state.players[0].deposit == 0 and game.state.players[0].cash == 2000 and principal(game) == 500, "cash supplement follows exhausted deposit")
	expect(game.state.bank.cash == bank.cash + 1000 and game.state.bank.deposits == bank.deposits - 500 and game.state.bank.loans == bank.loans, "special cash repayment mirrors only actual cash")
	valid(game, "cash supplemented repayment")


func _test_capacity_and_ownership() -> void:
	var game: Object = make_game()
	for i in range(1, 4):
		balances(game, i, 10000, 1000)
	if not take(game, 3000):
		return
	var before_deposit: int = game.state.players[0].deposit
	enter(game, 1)
	expect(bool(game.choose_action("withdraw", {"amount": 500}).get("ok", false)), "another player withdraws through company bank")
	expect(principal(game) == 2500 and game.state.players[0].deposit == before_deposit - 500, "other withdrawal immediately collects capacity shortfall")
	expect(game.state.current_player == 1, "forced repayment preserves the withdrawing actor")
	valid(game, "capacity contraction")
	expect(bool(game.choose_action("buy_company", {"quantity": 2}).get("ok", false)), "another player publicly takes chair")
	expect(game.state.companies[0].owner == 1 and principal(game) == 0, "chair loss immediately clears former chair financing")
	valid(game, "chair takeover")
	game = make_game()
	if not take(game, 1000):
		return
	balances(game, 0, 0, 0)
	enter(game, 1)
	expect(bool(game.choose_action("buy_company", {"quantity": 2}).get("ok", false)), "takeover triggering insolvent former chair settles")
	expect(not game.state.players[0].alive and principal(game) == 0 and game.state.current_player == 1, "insolvent former chair uses bankruptcy cleanup without replacing actor")
	expect(game.state.bank.loans == 0, "special bankruptcy does not invent ordinary bank loan assets")
	valid(game, "forced special bankruptcy")


func _test_rejections_and_save() -> void:
	var game: Object = make_game()
	for amount in [0, -1, true, "1", 1.5, NAN, INF, {}, [], LIMIT + 1]:
		rejected(game, "take_special_finance", amount, "invalid financing " + str(amount))
	for amount in [0, -1, true, "1", 1.5, NAN, INF, {}, [], 1]:
		rejected(game, "repay_special_finance", amount, "invalid repayment " + str(amount))
	enter(game, 1)
	rejected(game, "take_special_finance", 1, "nonowner entry")
	enter(game, 0)
	game.state.players[0].loan_block_days = 3
	game._set_action_options(0)
	rejected(game, "take_special_finance", 1, "news borrowing block")
	game.state.players[0].loan_block_days = 0
	game._set_action_options(0)
	if not take(game, 200):
		return
	var snapshot: Dictionary = game.to_dict()
	var copy: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(copy != null, "financing snapshot reloads")
	if copy != null:
		expect(copy.to_json() == game.to_json(), "financing JSON exact")
		game.choose_action("repay_special_finance", {"amount": 100})
		copy.choose_action("repay_special_finance", {"amount": 100})
		game.end_turn()
		copy.end_turn()
		game.roll()
		copy.roll()
		expect(copy.to_json() == game.to_json(), "financing and later RNG continue identically")
	for bad in [-1, true, "1", 1.5, INF, LIMIT + 1]:
		var malformed := snapshot.duplicate(true)
		malformed.players[0].special_finance = bad
		expect(not bool(Game.validate_save(malformed).ok), "malformed financing metadata rejected")
	var legacy: Object = Game.new_game(124, 4)
	var grafted: Dictionary = legacy.to_dict()
	grafted.players[0].special_finance = 1
	expect(not bool(Game.validate_save(grafted).ok), "finance metadata cannot be grafted onto demo")
	legacy.state.phase = "await_action"
	legacy._set_action_options(0)
	rejected(legacy, "take_special_finance", 1, "demo excludes special finance")
