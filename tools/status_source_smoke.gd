extends SceneTree
## Owner-catalog acceptance; source content stays outside the public code repo.
const Maps=preload("res://game/content/original_maps.gd")
const Game=preload("res://game/core/game_state.gd")
var failures:=0
func fail(label: String) -> void:
	failures+=1
	push_error(label)
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():
		fail("Provide an owner-authorized complete catalog path")
		quit(1);return
	var catalog:=Maps.load_catalog(args[0],true)
	if not catalog.get("ok",false):
		fail(str(catalog.get("error","Catalog load failed")))
		quit(1);return
	var map_count:=0
	for definition in catalog.maps:
		var id:=str(definition.id)
		var seed_value:=6 if id=="Game:1" else 42727
		var game:=Game.new_game_on_board(seed_value,4,definition,{"original_facilities":true,"original_gods":true,"original_companies":true,"original_statuses":true,"day_limit":30,"start_date":{"year":1998,"month":1,"day":1}})
		if game==null:
			fail(id+" cannot start status game");continue
		map_count+=1
		if id=="Game:1":
			var occupied:=false
			for god in game.state.god_objects:
				if god.owner==-1 and god.node==game._status_node_index("hospital"): occupied=true
			if not occupied: fail("Game:1 seed 6 must exercise admission onto an unbound god")
		for player_id in range(4): game.set_player_ai(player_id,true)
		game._admit_player_status(2,"hospital",3)
		game._admit_player_status(3,"prison",2)
		var restored: Object=Game.from_dict(JSON.parse_string(game.to_json()))
		if restored==null:
			fail(id+" initial status snapshot rejected");continue
		var turns:=0
		while game.state.phase!="game_over" and turns<300:
			var result: Dictionary=game.run_ai_turn()
			var counterpart: Dictionary=restored.run_ai_turn()
			if not result.get("ok",false) or not counterpart.get("ok",false) or not result.get("completed",false):
				fail(id+" AI turn incomplete: "+str(result.get("message","")));break
			turns+=1
			var validation: Dictionary=Game.validate_save(game.to_dict())
			if not validation.get("ok",false):
				fail(id+" invalid save: "+str(validation.get("errors",[])));break
			if game.to_json()!=restored.to_json():
				fail(id+" JSON continuation differs at turn "+str(turns));break
			restored=Game.from_dict(JSON.parse_string(game.to_json()))
			if restored==null:
				fail(id+" turn snapshot cannot reload");break
		if game.state.phase!="game_over": fail(id+" did not finish 30-day match")
		print("Status source ",id," version=",game.state.version," turns=",turns," phase=",game.state.phase)
	if map_count!=12: fail("Expected twelve status-capable source maps")
	print("Status source acceptance: ",map_count," maps, ",failures," failures")
	quit(1 if failures else 0)
