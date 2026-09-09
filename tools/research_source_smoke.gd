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
		var game:=Game.new_game_on_board(seed_value,4,definition,{"original_inventory":true,"original_facilities":true,"original_gods":true,"original_companies":true,"original_statuses":true,"original_hazards":true,"original_property_cards":true,"original_remodel":true,"original_research":true,"day_limit":30,"start_date":{"year":1998,"month":1,"day":1}})
		if game==null:
			fail(id+" cannot start research game");continue
		map_count+=1
		if game.state.version != 12:
			fail(id+" did not start v12");continue
		for player_id in range(4): game.set_player_ai(player_id,true)
		var lab: Dictionary = {}
		for tile in game.state.board:
			if tile.get("kind", "") == "facility":
				lab = tile
				break
		if lab.is_empty():
			fail(id + " has no research facility site"); continue
		var canonical: int = game._facility_canonical_index(int(lab.index))
		game._update_facility_records(int(lab.source_object_id), {"owner": 0, "facility_type": 4, "building_level": 1})
		game.state.players[0].properties.append(canonical)
		game.state.players[0].position = canonical
		game.state.players[0].previous_position = -1
		game.state.phase = "await_action"
		game.state.last_roll = [1]
		game.state.last_total = 1
		game.state.last_roll_total = 1
		game.state.property_action_used = true
		game._recalculate_property_values()
		game._set_action_options(0)
		if not game.choose_action("choose_research", {"tool_id": "機器工人"}).get("ok", false):
			fail(id + " cannot select research product through public action"); continue
		game._admit_player_status(2,"hospital",3)
		game._admit_player_status(3,"prison",2)
		var restored: Object=Game.from_dict(JSON.parse_string(game.to_json()))
		if restored==null:
			fail(id+" initial status snapshot rejected");continue
		var turns:=0
		var products:=0
		while game.state.phase!="game_over" and turns<300:
			var started_turn:=int(game.state.turn)
			var result: Dictionary=game.run_ai_turn()
			var counterpart: Dictionary=restored.run_ai_turn()
			if not result.get("ok",false) or not counterpart.get("ok",false) or not result.get("completed",false):
				fail(id+" AI turn incomplete: "+str(result.get("message","")));break
			turns+=1
			for event in game.state.event_log:
				if event.get("type","")=="research_produced" and bool(event.get("granted", false)) and int(event.get("turn",-1))==started_turn:
					products+=1
			var validation: Dictionary=Game.validate_save(game.to_dict())
			if not validation.get("ok",false):
				fail(id+" invalid save: "+str(validation.get("errors",[])));break
			if game.to_json()!=restored.to_json():
				fail(id+" JSON continuation differs at turn "+str(turns));break
			restored=Game.from_dict(JSON.parse_string(game.to_json()))
			if restored==null:
				fail(id+" turn snapshot cannot reload");break
		if game.state.phase!="game_over": fail(id+" did not finish 30-day match")
		if products < 1: fail(id + " did not produce its scheduled research tool")
		print("Research source ",id," version=",game.state.version," turns=",turns," products=",products," phase=",game.state.phase)
	if map_count!=12: fail("Expected twelve research-capable source maps")
	print("Research source acceptance: ",map_count," maps, ",failures," failures")
	quit(1 if failures else 0)
