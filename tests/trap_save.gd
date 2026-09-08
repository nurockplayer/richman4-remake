extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/status_fixture.gd")
const CompanyFixture = preload("res://tests/fixtures/company_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, label: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(label)
func rejected(data: Dictionary, label: String) -> void:
	expect(not Game.validate_save(data).get("ok",false),label+" validator rejects")
	expect(Game.from_dict(data)==null,label+" loader rejects")
func _initialize() -> void:
	var game := Game.new_game_on_board(8585,4,Fixture.definition(),{"original_statuses":true,"original_companies":true,"original_gods":true,"original_facilities":true,"start_date":{"year":1998,"month":1,"day":1}})
	game.state.god_objects=[]
	for player_id in range(4):
		game.set_player_ai(player_id,false)
		var p: Dictionary=game.state.players[player_id]
		for card in p.cards.duplicate(): Inventory.consume_card(game.state.inventory_supply,p.cards,card)
	Inventory.grant_card(game.state.inventory_supply,game.state.players[0].cards,"陷害")
	Inventory.grant_card(game.state.inventory_supply,game.state.players[1].cards,"嫁禍")
	game.choose_action("use_card",{"card_id":"陷害","target_id":1})
	expect(not game.state.get("pending_trap",{}).is_empty(),"fixture awaits human response")
	if game.state.get("pending_trap",{}).is_empty(): finish();return
	var good: Dictionary=game.to_dict()
	expect(Game.validate_save(good).get("ok",false),"pending original validates")
	var restored: Object=Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored!=null,"pending JSON restores")
	if restored!=null:
		expect(restored.state.action_options==["respond_trap"],"restored pending offers response only")
	var malformed: Array=[null,[],0,"pending",{"caster_id":0},{"target_id":1},{"caster_id":1,"target_id":1},{"caster_id":2,"target_id":1},{"caster_id":0,"target_id":0},{"caster_id":0,"target_id":9},{"caster_id":{},"target_id":1},{"caster_id":0,"target_id":[]},{"caster_id":0.5,"target_id":1},{"caster_id":0,"target_id":true},{"caster_id":0,"target_id":1,"extra":true}]
	for index in range(malformed.size()):
		var data: Dictionary=good.duplicate(true)
		data.pending_trap=malformed[index]
		rejected(data,"malformed pending %d"%index)
	var missing: Dictionary=good.duplicate(true)
	missing.erase("pending_trap")
	rejected(missing,"v8 missing pending field")
	for phase in ["await_route","game_over"]:
		var data: Dictionary=good.duplicate(true)
		data.phase=phase
		rejected(data,"pending incompatible phase "+phase)
	for status in ["hospital_days","prison_days"]:
		var data: Dictionary=good.duplicate(true)
		data.players[1][status]=2
		data.players[1].position=game._status_node_index("hospital" if status=="hospital_days" else "prison")
		data.players[1].previous_position=-1
		rejected(data,"pending detained target "+status)
	var ai: Dictionary=good.duplicate(true)
	ai.players[1].is_ai=true;ai.players[1].is_human=false
	rejected(ai,"pending target must be human")
	var missing_card: Dictionary=good.duplicate(true)
	Inventory.consume_card(missing_card.inventory_supply,missing_card.players[1].cards,"嫁禍")
	rejected(missing_card,"pending target no scapegoat")
	var immunity: Dictionary=good.duplicate(true)
	Inventory.grant_card(immunity.inventory_supply,immunity.players[1].cards,"免罪")
	rejected(immunity,"pending target immunity already should resolve")
	var detained_caster: Dictionary=good.duplicate(true)
	detained_caster.players[0].prison_days=2
	detained_caster.players[0].position=game._status_node_index("prison")
	detained_caster.players[0].previous_position=-1
	rejected(detained_caster,"pending caster cannot be detained")
	var remote: Dictionary=good.duplicate(true)
	remote.pending_remote_dice={"player_id":0,"value":2}
	rejected(remote,"pending reaction cannot coexist with remote dice")
	var action_pending: Dictionary=good.duplicate(true)
	action_pending.phase="await_action"
	expect(Game.validate_save(action_pending).get("ok",false),"pending reaction valid after landing before end turn")
	var action_restored: Object=Game.from_dict(JSON.parse_string(JSON.stringify(action_pending)))
	expect(action_restored!=null,"pending action-phase reaction restores")
	if action_restored!=null:
		expect(action_restored.choose_action("respond_trap",{"cancel":true}).get("ok",false),"restored action-phase reaction resumes")
		expect(Game.validate_save(action_restored.to_dict()).get("ok",false),"resolved action-phase save validates")
	var legacy := Game.new_game_on_board(8586,4,CompanyFixture.definition(),{"original_companies":true,"original_gods":true,"original_facilities":true,"start_date":{"year":1998,"month":1,"day":1}})
	var legacy_data: Dictionary=legacy.to_dict()
	expect(Game.validate_save(legacy_data).get("ok",false),"unchanged v7 validates")
	legacy_data.pending_trap={"caster_id":0,"target_id":1}
	rejected(legacy_data,"v7 cannot smuggle active reaction")
	finish()
func finish() -> void:
	print("Trap save checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
