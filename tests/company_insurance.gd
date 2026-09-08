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
func _initialize() -> void:
	var definition: Dictionary = Fixture.definition()
	definition.companies[0].company_type=4
	var game = Game.new_game_on_board(42,4,definition,{"original_facilities":true,"original_gods":true,"original_companies":true,"start_date":{"year":1998,"month":1,"day":1}})
	expect(game.state.players[0].has("insurance_status"),"company player has source insurance state")
	if not game.state.players[0].has("insurance_status"):
		print("Company insurance checks: %d, failures: %d"%[checks,failures]);quit(1);return
	game.state.god_objects=[]
	game.state.players[0].stocks.s01=1
	game.state.companies[0].treasury-=1
	game._update_company_owners()
	var cash: int = game.state.players[0].cash
	game._resolve_company_visit(0,game.state.board[5])
	var days: int = game.state.players[0].insurance_status
	expect(days in [5,3,30,20,15,10],"insurance duration uses source roulette outcomes")
	expect(game.state.players[0].cash==cash,"company owner receives free coverage")
	cash=game.state.players[1].cash
	game._resolve_company_visit(1,game.state.board[5])
	days=game.state.players[1].insurance_status
	expect(game.state.players[1].cash==cash-days*150,"visitor pays premium per granted day")
	var earnings: int = game.state.companies[0].monthly_profit
	cash=game.state.players[1].cash
	game.state.god_objects=[{"id":11,"owner":-1,"node":2,"days":0}]
	expect(game._encounter_dog(1,2),"insured pedestrian dog encounter causes hospital")
	expect(game.state.players[1].cash==cash+6000,"three added hospital days pay insured player cash")
	expect(game.state.companies[0].monthly_profit==earnings-6000 and game.state.companies[0].cumulative_profit==earnings-6000,"insurance payout debits both company ledgers")
	expect(game.state.players[1].insurance_status==days,"payout does not consume insurance")
	game.state.players[1].insurance_status=1
	game._tick_company_insurance()
	expect(game.state.players[1].insurance_status==128,"last insurance day retains source expiry marker")
	cash=game.state.players[1].cash
	game._pay_company_insurance(1,2)
	expect(game.state.players[1].cash==cash+4000,"expiry day still pays full added hospital days")
	game._tick_company_insurance()
	expect(game.state.players[1].insurance_status==0,"next daily sweep expires coverage")
	cash=game.state.players[1].cash
	game._pay_company_insurance(1,2)
	expect(game.state.players[1].cash==cash,"expired coverage has no payout")
	game.state.god_objects=[]
	game._sync_state()
	game._set_action_options(0)
	var result: Dictionary = Game.validate_save(game.to_dict())
	expect(result.get("ok",false),"insurance state valid: "+str(result.get("errors",[])))
	var restored = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored!=null and restored.to_json()==game.to_json(),"insurance JSON roundtrip")
	for value in [-1,129,1.5,"1",null]:
		var broken: Dictionary = game.to_dict()
		broken.players[0].insurance_status=value
		expect(not Game.validate_save(broken).get("ok",false),"malformed insurance rejected")
	print("Company insurance checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
