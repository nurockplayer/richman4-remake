extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func make_game() -> Object:
	var game = Game.new_game_on_board(42,4,Fixture.definition(),{"original_facilities":true,"original_gods":true,"original_companies":true,"start_date":{"year":1998,"month":1,"day":1}})
	game.state.god_objects = []
	return game
func shares(game: Object, player_id: int, quantity: int) -> void:
	game.state.players[player_id].stocks.s01 += quantity
	game.state.companies[0].treasury -= quantity
	game._update_company_owners()
func valid(game: Object, label: String) -> void:
	game._sync_state()
	game._set_action_options(int(game.state.current_player))
	var result: Dictionary = Game.validate_save(game.to_dict())
	expect(result.get("ok",false), label + str(result.get("errors",[])))
	var copy = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(copy != null and copy.to_json()==game.to_json(), label + " survives JSON")
func _initialize() -> void:
	var game = make_game()
	shares(game,0,2)
	shares(game,1,2)
	expect(game.state.companies[0].owner==0,"equal holding preserves incumbent")
	shares(game,1,1)
	expect(game.state.companies[0].owner==1,"larger holding replaces incumbent")
	shares(game,0,1)
	expect(game.state.companies[0].owner==1,"new equal holding preserves new incumbent")
	game.state.companies[0].monthly_profit=101
	game.state.companies[0].cumulative_profit=400
	game.state.day_of_month=14
	var deposit0: int = game.state.players[0].deposit
	game._settle_company_dividends()
	expect(game.state.companies[0].monthly_profit==101,"no dividend before fifteenth")
	game.state.day_of_month=15
	var deposit1: int = game.state.players[1].deposit
	game._settle_company_dividends()
	expect(game.state.players[0].deposit==deposit0+50 and game.state.players[1].deposit==deposit1+50,"dividend uses player held total and truncates each payment")
	expect(game.state.companies[0].monthly_profit==0 and game.state.companies[0].cumulative_profit==400,"settlement clears monthly only")
	valid(game,"positive dividend")
	game=make_game()
	game.state.companies[0].monthly_profit=101
	game.state.day_of_month=15
	game._settle_company_dividends()
	expect(game.state.companies[0].monthly_profit==101,"no holders preserve undistributed pool")
	shares(game,0,100)
	game.state.players[0].deposit=70
	game.state.bank.deposits=70
	for player_id in [1,2,3]: game.state.players[player_id].deposit=0
	game.state.players[0].cash=100
	game.state.companies[0].monthly_profit=-120
	game._settle_company_dividends()
	expect(game.state.players[0].deposit==0 and game.state.players[0].cash==50,"negative dividend consumes deposits then cash")
	expect(game.state.players[0].alive,"covered loss keeps shareholder alive")
	valid(game,"negative dividend")
	game.state.day_of_month=15
	game.state.companies[0].monthly_profit=-60
	game.state.current_player=3
	var supply: int = game.state.market.rows.s01.market_supply
	var available: int = game.state.market.rows.s01.turn_supply
	game._settle_company_dividends()
	expect(not game.state.players[0].alive,"uncovered company loss bankrupts holder")
	expect(game.state.players[0].stocks.s01==0 and game.state.market.rows.s01.market_supply==supply+100 and game.state.market.rows.s01.turn_supply==available+100,"bankruptcy returns stocks to market and turn supply")
	expect(game.state.jackpot==10000 and game.state.companies[0].owner==-1,"bankruptcy stock proceeds enter jackpot and release company")
	valid(game,"insolvent dividend")
	game=make_game()
	shares(game,0,1)
	game.state.elapsed=4
	var company: Dictionary = game.state.companies[0]
	var cash: int = game.state.players[1].cash
	game._resolve_company_visit(1,game.state.board[5])
	expect(game.state.players[1].cash==cash-600,"type3 elapsed fee excludes price index")
	expect(company.monthly_profit==600 and company.cumulative_profit==600,"service credits both company ledgers")
	cash=game.state.players[0].cash
	game._resolve_company_visit(0,game.state.board[5])
	expect(game.state.players[0].cash==cash,"owner receives own service free")
	for kind in [5,6,12]:
		company.company_type=kind
		game.state.last_roll_total=3
		game.state.players[1].vehicle="car"
		game.state.players[1].dice_count=3
		game.state.players[1].vehicles.car=true
		cash=game.state.players[1].cash
		game._resolve_company_visit(1,game.state.board[5])
		var amount: int = (700 if kind==5 else 500)*3*2 if kind!=12 else 150*3
		expect(game.state.players[1].cash==cash-amount,"source company type %d service charge"%kind)
	game.state.last_roll_total=0
	game.state.players[1].vehicle="walking"
	game.state.players[1].dice_count=1
	game.state.players[1].vehicles.car=false
	valid(game,"company services")
	print("Company finance checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
