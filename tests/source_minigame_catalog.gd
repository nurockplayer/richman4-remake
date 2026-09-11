extends "res://tests/source_title_ui.gd"
const Core = preload("res://game/core/game_state.gd")
func run() -> void:
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("PRECONDITION_UNMET actual installed catalog required")
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,720)
	root.add_child(viewport)
	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	if not ui._map_catalog_complete or ui._map_catalog.size() != 12:
		print("PRECONDITION_UNMET incomplete installed catalog")
		quit(2)
		return
	check(true, "actual installed twelve-map catalog is complete")
	for edition in ["Game", "MultiverseJourney"]:
		var definition := find_map(ui, edition, 1 if edition == "Game" else 7)
		var options: Dictionary = ui._default_setup_options(4, definition)
		options.human_flags = [true,true,true,true]
		for event_code in [6,7,8]:
			var found := false
			for seed_value in range(1,33):
				var game: Object = Core.new_game_on_board(seed_value,4,definition,options)
				if game == null: break
				for step in range(256):
					var result: Dictionary = {"ok":false}
					if not game.pending_bank_visit().is_empty():
						result = game.resume_bank_visit() if game.pending_bank_visit().kind == "pass" else game.complete_bank_visit()
					elif game.state.phase == "await_roll": result = game.roll()
					elif game.state.phase == "await_action": result = game.end_turn()
					elif game.state.phase == "await_route": result = game.choose_route(int(game.state.route_options[0]))
					elif game.state.phase == "await_lottery": result = game.leave_lottery()
					elif game.state.phase == "await_shop": result = game.leave_shop(int(game.shop_visit_snapshot().visit_id))
					else: break
					if not result.get("ok",false): break
					var actor := int(game.state.current_player)
					var tile: Dictionary = game.state.board[int(game.state.players[actor].position)]
					if game.state.phase not in ["await_action","await_minigame"] or int(tile.get("event_code",0)) != event_code or int(tile.get("type_and_idx",0)) >= 2000: continue
					found = true
					check(game.state.phase == "await_minigame", "ordinary source event%d enters playable pending game: %s" % [event_code,edition])
					check(game.state.action_options.is_empty(), "minigame landing excludes ordinary actions")
					var before: Dictionary = game.to_dict()
					check(not game.roll().ok and not game.end_turn().ok and game.to_dict() == before, "pending minigame excludes roll/end without mutation")
					print("MINIGAME_NORMAL_ENTRY edition=%s event=%d seed=%d node=%d phase=%s" % [edition,event_code,seed_value,int(before.players[actor].position),str(before.phase)])
					break
				if found: break
			check(found, "public movement reaches event%d in %s" % [event_code,edition])
	viewport.queue_free()
	await settle()
	print("Minigame catalog checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
