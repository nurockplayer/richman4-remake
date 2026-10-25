extends SceneTree

## Paying one holder can bankrupt it mid-settlement. That bankruptcy cascades
## through company ownership and chair financing, which may bankrupt another
## holder before the settlement loop reaches its precomputed payout. Paying a
## dividend into the dead account leaks money that validate_save cannot see,
## because the bank ledger and the dead deposit move together.

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run()
	print("Dividend cascade checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


## The shared fixture only has one company. A negative pool and a positive pool
## are both needed so a holder can be bankrupted by one company while another
## company still owes it money.
func _definition() -> Dictionary:
	var result: Dictionary = Fixture.definition()
	result.stock_rows[1].company_id = 2
	result.stock_rows[1].market_supply = 5000
	result.companies.append({"id":2,"display_name":"測試投資","company_type":3,"stock_index":1,"stock_value":400000,"toll_fee":150,"monthly_profit":0,"cumulative_profit":0,"treasury":5000,"source_owner":0})
	var tile: Dictionary = result.board[4]
	tile["type_and_idx"] = 6002
	tile["event_code"] = 0
	tile["source_status_bits"] = 0
	tile["kind"] = "unsupported"
	tile["source_company_id"] = 2
	tile["company_node_index"] = 4
	return result


func _bank_deposits(game: Object) -> int:
	var total := 0
	for player in game.state.players:
		total += int(player.deposit)
	return total


func _paid_events(game: Object, player_id: int) -> int:
	var count := 0
	for event in game.state.event_log:
		if str(event.get("type", "")) == "company_dividend_paid" and int(event.get("player_id", -1)) == player_id:
			count += 1
	return count


func _bankrupt_reason(game: Object, player_id: int) -> String:
	for event in game.state.event_log:
		if str(event.get("type", "")) == "bankruptcy" and int(event.get("player_id", -1)) == player_id:
			return str(event.get("reason", ""))
	return ""


func _run() -> void:
	var game: Object = Game.new_game_on_board(42, 4, _definition(), {"original_facilities": true, "original_gods": true, "original_companies": true, "start_date": {"year": 1998, "month": 1, "day": 14}})
	_expect(game != null, "two-company fixture starts")
	if game == null:
		return
	game.state.god_objects = []
	for player in game.state.players:
		player.cash = 0
		player.deposit = 0
	game.state.bank.deposits = 0
	game.state.current_player = 3
	game.state.phase = "await_action"
	# Player 0 alone holds the losing company; player 2 alone holds the paying
	# one. Player 0 goes bankrupt first, so player 2 is collected before its
	# own turn in the payout loop.
	game.state.players[0].stocks["s01"] = 1
	game.state.companies[0].treasury -= 1
	game.state.players[2].stocks["s02"] = 1
	game.state.companies[1].treasury -= 1
	game._update_company_owners()
	# Staged last: the next ownership reconciliation collects chair financing
	# from every living player, so the fixture must not trigger one early.
	game.state.players[2].special_finance = 5000
	game.state.companies[0].monthly_profit = -100
	game.state.companies[1].monthly_profit = 900
	# The fixture starts on 1998-01-14, so elapsed day two is the fifteenth.
	game.state.day = 2
	game._sync_state()
	game._set_action_options(3)
	var setup: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(setup.get("ok", false)), "cascade fixture validates before settlement: " + str(setup.get("errors", [])))
	game._settle_company_dividends()
	_expect(not bool(game.state.players[0].alive), "negative dividend bankrupts its holder")
	_expect(not bool(game.state.players[2].alive), "holder bankruptcy cascades into chair financing")
	_expect(_bankrupt_reason(game, 2) == "special_finance_chair_loss", "cascade bankruptcy keeps its cause")
	_expect(int(game.state.players[2].deposit) == 0 and int(game.state.players[2].cash) == 0, "dead holder keeps no balance")
	_expect(int(game.state.bank.deposits) == _bank_deposits(game), "bank ledger matches the surviving deposits")
	_expect(_paid_events(game, 2) == 0, "dead holder receives no dividend payment record")
	var after: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(after.get("ok", false)), "settled cascade state validates: " + str(after.get("errors", [])))
