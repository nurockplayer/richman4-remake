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
	var definition: Dictionary = Fixture.definition()
	definition.companies[0].company_type=11
	var game = Game.new_game_on_board(42,4,definition,{"original_facilities":true,"original_gods":true,"original_companies":true,"start_date":{"year":1998,"month":1,"day":1}})
	game.state.god_objects=[]
	game.state.players[0].stocks.s01=1
	game.state.companies[0].treasury-=1
	game._update_company_owners()
	game.state.board[2].owner=1
	game.state.players[1].properties=[2]
	game._recalculate_property_values()
	return game
func visit(game: Object, player_id: int) -> void:
	game.state.current_player=player_id
	game.state.players[player_id].position=5
	game.state.players[player_id].previous_position=4
	game.state.phase="await_action"
	game._resolve_company_visit(player_id,game.state.board[5])
	game._set_action_options(player_id)
func valid(game: Object) -> void:
	var result: Dictionary = Game.validate_save(game.to_dict())
	expect(result.get("ok",false),"construction state valid: "+str(result.get("errors",[])))
	var restored = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored!=null and restored.to_json()==game.to_json(),"construction pending state JSON roundtrip")
func _initialize() -> void:
	var game = make_game()
	expect(game.state.has("company_service_pending"),"construction company has explicit pending state")
	if not game.state.has("company_service_pending"):
		print("Company construction checks: %d, failures: %d"%[checks,failures]);quit(1);return
	visit(game,1)
	expect(game.state.company_service_pending==1 and game.get_company_upgrade_targets(1)==[2],"visitor chooses their own eligible property")
	valid(game)
	var before: Dictionary = game.to_dict()
	expect(not game.end_turn().get("ok",false) and game.to_dict()==before,"cannot skip pending construction choice")
	expect(not game.choose_action("company_upgrade",{"tile_id":3}).get("ok",false) and game.to_dict()==before,"unowned target rejected without side effects")
	var cash: int = game.state.players[1].cash
	expect(game.choose_action("company_upgrade",{"tile_id":2}).get("ok",false),"visitor construction succeeds")
	expect(game.state.board[2].building_level==1 and game.state.players[1].cash==cash-1000,"paid construction adds one level and charges target land price")
	expect(game.state.companies[0].monthly_profit==1000 and game.state.company_service_pending==0,"construction earnings recorded and service consumed")
	before=game.to_dict()
	expect(not game.choose_action("company_upgrade",{"tile_id":2}).get("ok",false) and game.to_dict()==before,"construction cannot repeat at same visit")
	valid(game)
	game=make_game()
	game.state.board[2].owner=0
	game.state.players[1].properties=[]
	game.state.players[0].properties=[2]
	game._recalculate_property_values()
	visit(game,0)
	cash=game.state.players[0].cash
	expect(game.choose_action("company_upgrade",{"tile_id":2}).get("ok",false),"company owner construction succeeds")
	expect(game.state.board[2].building_level==2 and game.state.players[0].cash==cash,"owner receives two free levels")
	game.state.board[2].building_level=4
	game._recalculate_property_values()
	visit(game,0)
	expect(game.choose_action("company_upgrade",{"tile_id":2}).get("ok",false) and game.state.board[2].building_level==5,"owner free construction stops at housing cap")
	valid(game)
	game=make_game()
	cash=game.state.players[2].cash
	visit(game,2)
	expect(game.state.company_service_pending==0 and game.state.players[2].cash==cash-1000,"visitor without target pays source fallback fee")
	valid(game)
	var definition: Dictionary = Fixture.construction_definition()
	game=Game.new_game_on_board(42,4,definition,{"original_facilities":true,"original_gods":true,"original_companies":true,"start_date":{"year":1998,"month":1,"day":1}})
	expect(game!=null,"shared facility construction fixture starts: "+str(Game.validate_board_definition(definition,true).get("errors",[]))+str(Game._company_definition_errors(definition,4)))
	if game!=null:
		game.state.god_objects=[]
		game.state.players[0].stocks.s01=1
		game.state.companies[0].treasury-=1
		game._update_company_owners()
		game._update_facility_records(1,{"owner":0})
		game.state.players[0].properties=[1]
		game._recalculate_property_values()
		visit(game,0)
		expect(game.get_company_upgrade_targets(0)==[1],"shared facility is one construction target")
		before=game.to_dict()
		expect(not game.choose_action("company_upgrade",{"tile_id":1,"facility_type":4}).get("ok",false) and game.to_dict()==before,"research construction rejected atomically")
		expect(game.choose_action("company_upgrade",{"tile_id":1,"facility_type":1}).get("ok",false),"company owner builds chosen facility type")
		expect(game.state.board[1].building_level==2 and game.state.board[4].building_level==2 and game.state.board[4].facility_type==1,"two-level construction syncs all facility nodes")
		valid(game)
	print("Company construction checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
