extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)
func make_game() -> Object:
	return Game.new_game_on_board(42,4,Fixture.definition(),{"original_facilities":true,"original_gods":true,"original_companies":true,"start_date":{"year":1998,"month":1,"day":1}})
func valid(game: Object, label: String) -> void:
	var check: Dictionary = Game.validate_save(game.to_dict())
	expect(check.get("ok",false),label+str(check.get("errors",[])))
	var restored = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored!=null,label+" JSON loads")
	if restored!=null: expect(restored.to_json()==game.to_json(),label+" full JSON matches")
func _initialize() -> void:
	var game = make_game()
	expect(game!=null,"source company capability starts executable v7 game")
	if game==null:
		print("Company flow checks: %d, failures: %d"%[checks,failures]);quit(1);return
	expect(game.state.version==7,"company state explicitly uses v7")
	expect(game.get_stock_symbols().size()==12,"source game exposes twelve original stocks")
	valid(game,"initial companies")
	var cash_before: int = game.state.players[0].cash
	var deposit_before: int = game.state.players[0].deposit
	var supply_before: int = game.state.market.rows.s01.market_supply
	expect(game.choose_action("buy_stock",{"symbol":"s01","quantity":3}).get("ok",false),"market buy succeeds")
	expect(game.state.players[0].deposit==deposit_before-300 and game.state.players[0].cash==cash_before,"market buy uses deposits only")
	expect(game.state.market.rows.s01.market_supply==supply_before-3 and game.state.players[0].stocks.s01==3,"market shares conserve supply")
	expect(game.state.companies[0].owner==0,"largest holder receives company management")
	valid(game,"market buy")
	expect(game.choose_action("sell_stock",{"symbol":"s01","quantity":3}).get("ok",false),"market sale succeeds")
	expect(game.state.players[0].deposit==deposit_before and game.state.market.rows.s01.market_supply==supply_before,"market sale returns deposits and supply")
	expect(game.state.companies[0].owner==-1,"zero holdings release management")
	game.state.god_objects=[]
	game.state.phase="await_action"
	game.state.players[0].position=5
	game.state.players[0].previous_position=4
	game._set_action_options(0)
	valid(game,"direct issue prestate")
	var before: Dictionary = game.to_dict()
	expect(not game.choose_action("buy_company",{"quantity":1001}).get("ok",false),"company visit rejects more than thousand shares")
	expect(game.to_dict()==before,"over-limit direct purchase is atomic")
	expect(game.choose_action("buy_company",{"quantity":500}).get("ok",false),"direct company purchase succeeds")
	expect(game.state.players[0].cash==cash_before-20000 and game.state.players[0].deposit==deposit_before,"direct issue uses face price and cash")
	expect(game.state.companies[0].treasury==4500 and game.state.market.rows.s01.market_supply==supply_before,"direct issue consumes separate treasury")
	expect(game.state.companies[0].monthly_profit==0 and game.state.companies[0].cumulative_profit==0,"direct share issue does not count as company service earnings")
	valid(game,"company direct issue")
	print("Company flow checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
