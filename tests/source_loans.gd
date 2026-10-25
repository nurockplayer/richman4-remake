extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")
const Calendar = preload("res://game/core/game_calendar.gd")
const MONEY_MAX := 1000000000000
var checks := 0
var failures := 0


func _initialize() -> void:
	_test_borrow_and_repay()
	_test_limits_and_rejections()
	_test_term_and_continuation()
	_test_maturity_and_legacy()
	print("Source loan checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func make_game(date: Dictionary = {"year": 1998, "month": 1, "day": 1}) -> Object:
	var definition: Dictionary = Fixture.definition()
	var tile: Dictionary = definition.board[5]
	tile.event_code = 14
	tile.source_status_bits = 14
	tile.kind = "bank"
	var game: Object = Game.new_game_on_board(122, 4, definition, {"original_facilities": true, "original_gods": true, "original_companies": true, "start_date": date})
	game.state.god_objects = []
	game.state.current_player = 0
	game.state.phase = "await_action"
	game.state.players[0].position = 5
	game.state.players[0].previous_position = -1
	game.state.bank_access = true
	game.state.bank_landing = true
	game._set_action_options(0)
	valid(game, "legal bank fixture")
	return game


func valid(game: Object, label: String) -> void:
	var result: Dictionary = Game.validate_save(game.to_dict())
	expect(bool(result.ok), label + str(result.get("errors", [])))


func limit(game: Object, action: String) -> int:
	expect(game.has_method("bank_loan_limit"), "public loan amount query exists")
	return int(game.call("bank_loan_limit", action)) if game.has_method("bank_loan_limit") else -1


func rejected(game: Object, action: String, amount: Variant, label: String) -> void:
	var before: String = game.to_json()
	var result: Dictionary = game.choose_action(action, {"amount": amount})
	expect(not bool(result.get("ok", false)), label + " rejects")
	expect(game.to_json() == before, label + " preserves complete state and RNG")


func set_money(game: Object, cash: int, deposit: int, loan: int, due: int = 91) -> void:
	var player: Dictionary = game.state.players[0]
	game.state.bank.deposits += deposit - int(player.deposit)
	game.state.bank.loans += loan - int(player.loan)
	player.cash = cash
	player.deposit = deposit
	player.loan = loan
	player.loan_due_day = due if loan else 0
	game._set_action_options(0)
	valid(game, "staged balances")


func _test_borrow_and_repay() -> void:
	var game: Object = make_game()
	var wealth: int = game.get_player_wealth(0)
	var cash: int = game.state.players[0].cash
	var deposit: int = game.state.players[0].deposit
	var bank: Dictionary = game.state.bank.duplicate(true)
	expect(limit(game, "take_loan") == wealth, "unborrowed credit equals opening net wealth")
	var borrowed: Dictionary = game.choose_action("take_loan", {"amount": 12000})
	expect(bool(borrowed.get("ok", false)), "source loan may exceed demo 10000 cap")
	if not bool(borrowed.get("ok", false)):
		return
	expect(game.state.players[0].cash == cash and game.state.players[0].deposit == deposit + 12000, "loan enters deposit, cash unchanged")
	expect(game.state.bank.cash == bank.cash and game.state.bank.deposits == bank.deposits + 12000 and game.state.bank.loans == bank.loans + 12000, "source loan balances bank deposits and loan assets")
	expect(limit(game, "take_loan") == wealth - 12000, "remaining credit subtracts outstanding principal")
	var due: int = game.state.players[0].loan_due_day
	expect(bool(game.choose_action("repay_loan", {"amount": 2000}).get("ok", false)), "partial early repayment admitted")
	expect(game.state.players[0].cash == cash and game.state.players[0].deposit == deposit + 10000 and game.state.players[0].loan == 10000, "partial repayment consumes deposit first")
	expect(game.state.players[0].loan_due_day == due, "partial repayment keeps original due date")
	expect(bool(game.choose_action("repay_loan", {"amount": 10000}).get("ok", false)), "full early repayment admitted")
	expect(game.state.players[0].cash == cash and game.state.players[0].deposit == deposit and game.state.players[0].loan == 0 and game.state.players[0].loan_due_day == 0, "full repayment clears principal and date")
	expect(game.state.bank == bank, "borrow and full deposit repayment restore bank accounts")
	valid(game, "full early repayment")
	set_money(game, 7000, 1000, 6000)
	bank = game.state.bank.duplicate(true)
	expect(limit(game, "repay_loan") == 6000, "repayment cap is principal bounded by liquid assets")
	expect(bool(game.choose_action("repay_loan", {"amount": 4000}).get("ok", false)), "mixed deposit and cash repayment admitted")
	expect(game.state.players[0].deposit == 0 and game.state.players[0].cash == 4000 and game.state.players[0].loan == 2000, "mixed repayment uses deposit before cash")
	expect(game.state.bank.cash == bank.cash + 3000 and game.state.bank.deposits == bank.deposits - 1000 and game.state.bank.loans == bank.loans - 4000, "only cash portion increases bank cash")
	valid(game, "mixed repayment")


func _test_limits_and_rejections() -> void:
	var game: Object = make_game()
	for amount in [0, -1, true, "1", 1.5, NAN, INF, {}, [], MONEY_MAX + 1]:
		rejected(game, "take_loan", amount, "malformed borrow " + str(amount))
	set_money(game, 1000, 2000, 500)
	for amount in [0, -1, true, "1", 1.5, NAN, INF, {}, [], 501]:
		rejected(game, "repay_loan", amount, "invalid repayment " + str(amount))
	rejected(game, "take_loan", 2001, "borrow above net wealth less principal")
	game.state.players[0].loan_block_days = 4
	game._set_action_options(0)
	rejected(game, "take_loan", 1, "news blocks borrowing")
	expect(game.state.action_options.has("repay_loan"), "loan-block news still permits repayment")
	expect(bool(game.choose_action("repay_loan", {"amount": 100}).get("ok", false)), "repayment remains legal under loan block")
	game = make_game()
	game.state.bank.cash = 0
	expect(bool(game.choose_action("take_loan", {"amount": 1.0}).get("ok", false)), "integral JSON number accepted without bank cash requirement")
	valid(game, "deposit loan with zero bank cash")
	for key in ["deposits", "loans"]:
		game = make_game()
		game.state.bank[key] = MONEY_MAX
		expect(limit(game, "take_loan") == 0, "bank " + key + " headroom caps credit")
		rejected(game, "take_loan", 1, "bank " + key + " overflow")
	game = make_game()
	set_money(game, 10, 1, 8)
	game.state.bank.cash = MONEY_MAX
	expect(limit(game, "repay_loan") == 1, "cash headroom still allows deposit repayment")
	rejected(game, "repay_loan", 2, "repayment cash overflow")
	for gate in ["position", "phase", "hospital"]:
		game = make_game()
		set_money(game, 1000, 1000, 100)
		if gate == "position":
			game.state.players[0].position = 0
			game.state.bank_landing = false
		elif gate == "phase":
			game.state.phase = "await_roll"
		else:
			game.state.players[0].hospital_days = 2
		game._set_action_options(0)
		rejected(game, "repay_loan", 1, "repayment " + gate + " gate")


func _test_term_and_continuation() -> void:
	# Monday + 90 days falls on Sunday; source pushes the deadline to Monday.
	var game: Object = make_game({"year": 1998, "month": 1, "day": 5})
	expect(bool(game.choose_action("take_loan", {"amount": 100}).get("ok", false)), "first Monday loan admitted")
	expect(game.state.players[0].loan_due_day == 92, "Sunday maturity is postponed by one day")
	game.state.day += 1
	game._sync_state()
	game._set_action_options(0)
	expect(bool(game.choose_action("take_loan", {"amount": 100}).get("ok", false)), "repeat loan admitted")
	expect(game.state.players[0].loan_due_day == 92, "repeat borrowing does not extend first due day")
	valid(game, "repeat loan")
	var saved: String = game.to_json()
	var loaded: Object = Game.from_dict(JSON.parse_string(saved))
	expect(loaded != null, "loan state reloads")
	if loaded != null:
		expect(loaded.to_json() == saved, "loan JSON round trip exact")
		game.choose_action("repay_loan", {"amount": 50})
		loaded.choose_action("repay_loan", {"amount": 50})
		game.end_turn()
		loaded.end_turn()
		game.roll()
		loaded.roll()
		expect(game.to_json() == loaded.to_json(), "repayment and later RNG continuation match")
	game = make_game({"year": 1998, "month": 1, "day": 4})
	set_money(game, 1000, 1000, 100)
	rejected(game, "take_loan", 1, "Sunday borrow")
	rejected(game, "repay_loan", 1, "Sunday early repayment")


func _test_maturity_and_legacy() -> void:
	var game: Object = make_game()
	set_money(game, 5000, 3000, 2000, 1)
	var bank: Dictionary = game.state.bank.duplicate(true)
	expect(bool(game.end_turn().get("ok", false)), "due loan uses public end turn")
	expect(game.state.players[0].cash == 5000 and game.state.players[0].deposit == 1000 and game.state.players[0].loan == 0, "maturity also consumes deposit first")
	expect(game.state.bank.cash == bank.cash and game.state.bank.deposits == bank.deposits - 2000 and game.state.bank.loans == bank.loans - 2000, "maturity preserves deposit accounting")
	valid(game, "maturity")
	game = make_game()
	set_money(game, 100, 200, 1000, 1)
	expect(bool(game.end_turn().get("ok", false)), "insolvent maturity completes")
	expect(not game.state.players[0].alive and game.state.players[0].loan == 0, "insufficient maturity retains bankruptcy cleanup")
	valid(game, "insolvent maturity")
	var legacy: Object = Game.new_game(122, 4)
	for tile in legacy.state.board:
		if tile.kind == "bank":
			legacy.state.players[0].position = tile.index
			break
	legacy.state.phase = "await_action"
	legacy.state.bank_access = true
	legacy.state.bank_landing = true
	legacy._set_action_options(0)
	var cash: int = legacy.state.players[0].cash
	var deposit: int = legacy.state.players[0].deposit
	expect(bool(legacy.choose_action("take_loan", {"amount": 100}).get("ok", false)), "existing demo borrowing still works")
	expect(legacy.state.players[0].cash == cash + 100 and legacy.state.players[0].deposit == deposit, "existing demo keeps cash-based loan behavior")
	rejected(legacy, "repay_loan", 1, "source-only repayment absent from legacy")
	valid(legacy, "legacy contract")
