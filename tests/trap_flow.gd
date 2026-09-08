extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/status_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func make_game() -> Object:
	var game := Game.new_game_on_board(4848,4,Fixture.definition(),{"original_statuses":true,"original_companies":true,"original_gods":true,"original_facilities":true,"start_date":{"year":1998,"month":1,"day":1}})
	game.state.god_objects=[]
	for p in game.state.players:
		game.set_player_ai(int(p.id),false)
		for card in p.cards.duplicate(): Inventory.consume_card(game.state.inventory_supply,p.cards,card)
	game._set_action_options(0)
	return game
func give(game: Object, player_id: int, card_id: String) -> void:
	expect(Inventory.grant_card(game.state.inventory_supply,game.state.players[player_id].cards,card_id).get("ok",false),"fixture grants "+card_id)
	game._set_action_options(int(game.state.current_player))
func trap(game: Object, target_id: int = 1) -> Dictionary:
	return game.choose_action("use_card",{"card_id":"陷害","target_id":target_id})
func valid(game: Object, label: String) -> void:
	var check: Dictionary = Game.validate_save(game.to_dict())
	expect(check.get("ok",false),label+str(check.get("errors",[])))
func _initialize() -> void:
	var game := make_game()
	give(game,0,"陷害")
	var before: String = game.to_json()
	expect(game.choose_action("use_card",{"card_id":"陷害","cancel":true}).get("ok",false),"initial selection cancellation succeeds")
	expect(game.to_json()==before,"initial cancellation is identical state")
	expect(not trap(game,0).get("ok",false) and game.to_json()==before,"initial self-target rejected without consumption")
	expect(trap(game).get("ok",false),"trap sends ordinary opponent to prison")
	expect(int(game.state.players[1].prison_days)==5 and int(game.state.players[1].position)==game._status_node_index("prison"),"ordinary victim jailed five turns at source node")
	expect(not game.state.players[0].cards.has("陷害"),"valid attack consumes card")
	valid(game,"ordinary trap save")
	if not game.has_method("trap_response_targets"):
		expect(false,"trap reaction API exists")
		finish();return
	game=make_game()
	give(game,0,"陷害");give(game,1,"免罪");give(game,1,"嫁禍");give(game,1,"復仇")
	expect(trap(game).get("ok",false),"immunity resolves valid attack")
	expect(int(game.state.players[1].prison_days)==0 and int(game.state.players[0].prison_days)==0,"immunity prevents both jail and revenge")
	expect(not game.state.players[1].cards.has("免罪") and game.state.players[1].cards.has("嫁禍") and game.state.players[1].cards.has("復仇"),"immunity has first priority and consumes only immunity")
	expect(game.state.pending_trap.is_empty(),"immunity requires no human response")
	valid(game,"immunity save")
	game=make_game();give(game,0,"陷害");give(game,1,"復仇")
	expect(trap(game).get("ok",false),"revenge resolves")
	expect(int(game.state.players[0].prison_days)==5 and int(game.state.players[1].prison_days)==5,"revenge jails both for five turns")
	expect(not game.state.players[1].cards.has("復仇"),"revenge automatically consumed")
	valid(game,"revenge save")
	game=make_game();give(game,0,"陷害");give(game,1,"嫁禍");give(game,1,"復仇")
	expect(trap(game).get("ok",false),"human response is pending")
	expect(game.state.pending_trap=={"caster_id":0,"target_id":1},"pending reaction persists caster and original target")
	expect(int(game.state.players[1].prison_days)==0 and not game.state.players[0].cards.has("陷害"),"attack consumed before waiting, victim not yet punished")
	valid(game,"pending reaction save")
	before=game.to_json()
	for action in ["roll","end_turn","set_vehicle","buy_stock","use_card"]:
		var result: Dictionary = game.call(action) if action in ["roll","end_turn"] else game.choose_action(action,{"vehicle":"walking","card_id":"嫁禍","symbol":"s01","quantity":1})
		expect(not result.get("ok",false) and game.to_json()==before,"pending reaction blocks "+action+" atomically")
	expect(not game.choose_action("respond_trap",{"target_id":1}).get("ok",false) and game.to_json()==before,"redirect to holder rejected atomically")
	expect(not game.set_player_ai(1,true) and game.to_json()==before,"pending response cannot convert holder to AI and invalidate save")
	expect(not game.run_ai_match(10).get("ok",false) and game.to_json()==before,"AI match takeover waits for pending response without changing controls")
	var restored: Object = Game.from_dict(JSON.parse_string(before))
	expect(restored!=null,"pending reaction JSON restores")
	expect(game.choose_action("respond_trap",{"cancel":true}).get("ok",false),"decline accepts original punishment")
	expect(int(game.state.players[1].prison_days)==5 and int(game.state.players[0].prison_days)==5 and game.state.players[1].cards.has("嫁禍"),"decline preserves scapegoat and triggers revenge")
	if restored!=null:
		restored.choose_action("respond_trap",{"cancel":true})
		expect(game.to_json()==restored.to_json(),"pending save continuation identical")
	valid(game,"declined response save")
	game=make_game();give(game,0,"陷害");give(game,1,"嫁禍");give(game,1,"復仇");give(game,0,"免罪")
	trap(game)
	expect(game.choose_action("respond_trap",{"target_id":0}).get("ok",false),"scapegoat can target original caster")
	expect(int(game.state.players[0].prison_days)==4 and int(game.state.players[1].prison_days)==0,"redirect to caster means four turns")
	expect(game.state.players[0].cards.has("免罪") and game.state.players[1].cards.has("復仇") and not game.state.players[1].cards.has("嫁禍"),"redirect never recursively triggers defense/revenge")
	valid(game,"self redirected save")
	game=make_game();give(game,0,"陷害");give(game,1,"嫁禍");give(game,2,"免罪")
	game._admit_player_status(2,"hospital",3)
	expect(not game.trap_target_players(0).has(2),"initial targets exclude detained opponents")
	trap(game)
	expect(game.trap_response_targets().has(2),"scapegoat may target detained opponents")
	expect(game.choose_action("respond_trap",{"target_id":2}).get("ok",false),"scapegoat transfers hospital victim to prison")
	expect(int(game.state.players[2].hospital_days)==0 and int(game.state.players[2].prison_days)==5 and game.state.players[2].cards.has("免罪"),"redirect applies mutually exclusive admission without recursive immunity")
	valid(game,"third-party redirected save")
	finish()
func finish() -> void:
	print("Trap flow checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
