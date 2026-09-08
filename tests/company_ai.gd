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
	var game = Game.new_game_on_board(31415,4,Fixture.definition(),{"original_facilities":true,"original_gods":true,"original_companies":true,"day_limit":30,"start_date":{"year":1998,"month":1,"day":1}})
	game.state.god_objects=[]
	for player in game.state.players:
		player.is_ai=true
		player.is_human=false
	game.state.phase="await_action"
	game.state.players[0].position=5
	game.state.players[0].previous_position=4
	game._set_action_options(0)
	var cash: int = game.state.players[0].cash
	game._ai_action(0)
	expect(game.state.players[0].stocks.s01==1000 and game.state.companies[0].treasury==4000,"AI buys company shares through shared action")
	expect(game.state.players[0].cash==cash-40000 and game.state.company_purchase_remaining==0,"AI obeys direct cash price and visit cap")
	var restored = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored!=null,"AI company state loads")
	if restored==null: quit(1);return
	for turn in range(500):
		if game.state.phase=="game_over": break
		var first: Dictionary = game.run_ai_turn()
		var second: Dictionary = restored.run_ai_turn()
		expect(first.get("ok",false) and second.get("ok",false),"both AI continuations complete turn")
		var validation: Dictionary = Game.validate_save(game.to_dict())
		expect(validation.get("ok",false),"company AI turn saves valid: "+str(validation.get("errors",[])))
		expect(game.to_json()==restored.to_json(),"company AI original and restored JSON identical at turn %d"%turn)
		if failures: break
		# Reload every turn to expose accumulating float serialization drift.
		restored=Game.from_dict(JSON.parse_string(restored.to_json()))
		expect(restored!=null,"every AI turn reloads")
		if restored==null: break
	expect(game.state.phase=="game_over","company AI completes thirty-day game")
	print("Company AI checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
