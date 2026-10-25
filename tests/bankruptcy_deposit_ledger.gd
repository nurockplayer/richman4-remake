extends SceneTree

## A bankrupt player's deposit is forfeited, so the bank deposit ledger has to
## drop by the same amount or the next save fails validation.

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run()
	print("Bankruptcy deposit ledger checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _fresh() -> Object:
	var game: Object = Game.new_game_on_board(4242, 4, Fixture.definition(), {"original_facilities": true, "original_gods": true, "original_companies": true, "start_date": {"year": 1998, "month": 1, "day": 14}})
	if game == null:
		return null
	for player in game.state.players:
		player.deposit = 0
	game.state.bank.deposits = 0
	return game


func _bank_deposits(game: Object) -> int:
	var total := 0
	for player in game.state.players:
		total += int(player.deposit)
	return total


func _run() -> void:
	var game = _fresh()
	_expect(game != null, "company fixture constructs")
	if game == null:
		return
	var current: Dictionary = game.state.players[0]
	current.deposit = 5000
	game.state.bank.deposits = 5000
	_expect(Game.validate_save(game.to_dict()).ok, "funded fixture validates before bankruptcy")
	game._declare_bankruptcy(0, -1, 3000, "test")
	_expect(int(current.deposit) == 0, "bankrupt player forfeits the deposit")
	_expect(int(game.state.bank.deposits) == _bank_deposits(game), "bank ledger matches remaining player deposits")
	_expect(Game.validate_save(game.to_dict()).ok, "save after a deposit bankruptcy validates")
	_expect(int(game.state.current_player) != 0, "current bankrupt actor advances")

	# An unrelated debtor's bankruptcy follows the same ledger rule while the
	# current actor keeps its turn.
	var other = _fresh()
	other.state.players[2].deposit = 1200
	other.state.bank.deposits = 1200
	var actor := int(other.state.current_player)
	other._declare_bankruptcy(2, -1, 900, "test")
	_expect(int(other.state.bank.deposits) == 0 and _bank_deposits(other) == 0, "other debtor deposit leaves the ledger")
	_expect(int(other.state.current_player) == actor, "unrelated bankruptcy keeps the current actor")
	_expect(Game.validate_save(other.to_dict()).ok, "save after an unrelated deposit bankruptcy validates")

	# A legacy save whose ledger already trails the player balance must clamp
	# instead of writing a negative bank deposit.
	var trailing = _fresh()
	trailing.state.players[1].deposit = 700
	trailing.state.bank.deposits = 200
	trailing._declare_bankruptcy(1, -1, 100, "test")
	_expect(int(trailing.state.bank.deposits) == 0, "ledger reduction is clamped at zero")

	# Action-phase bankruptcy is advanced by its caller exactly once. end_turn
	# settles the loan itself and then advances, so the auto-advance list must
	# not claim await_action or the same turn would be skipped twice.
	var loan = _fresh()
	loan.state.phase = "await_action"
	loan._set_action_options(0)
	loan.state.players[0].cash = 0
	loan.state.players[0].deposit = 0
	loan.state.players[0].loan = 5000
	loan.state.players[0].loan_due_day = 1
	var turn_before := int(loan.state.turn)
	_expect(bool(loan.end_turn().ok), "loan-due end turn succeeds")
	_expect(not bool(loan.state.players[0].alive), "loan due bankrupts the unpaid debtor")
	_expect(int(loan.state.current_player) == 1 and str(loan.state.phase) == "await_roll", "caller advances to the next actor")
	_expect(int(loan.state.turn) == turn_before + 1, "the action-phase bankruptcy advances exactly one turn")
	_expect(Game.validate_save(loan.to_dict()).ok, "save after a loan bankruptcy validates")
