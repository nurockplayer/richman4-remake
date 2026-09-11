extends "res://tests/source_title_ui.gd"
const Core = preload("res://game/core/game_state.gd")
func run() -> void:
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("SKIP: actual RICHMAN4_MAP_CATALOG required for lottery catalog test")
		quit(0)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,720)
	root.add_child(viewport)
	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	check(ui._map_catalog_complete and ui._map_catalog.size() == 12, "actual installed catalog admits complete source factory without injected capabilities")
	for edition in ["Game", "MultiverseJourney"]:
		var definition := find_map(ui, edition, 1 if edition == "Game" else 7)
		var options: Dictionary = ui._default_setup_options(4, definition)
		check(options.get("original_companies", false), "normal options enable shared lottery capability: " + edition)
		options.human_flags = [true,true,true,true]
		var found := false
		for seed_value in range(1, 17):
			var game: Object = Core.new_game_on_board(seed_value, 4, definition, options)
			if game == null:
				check(false, "actual catalog constructs")
				break
			var result: Dictionary = {"ok": true}
			for _step in range(256):
				if not result.get("ok", false): break
				if not game.pending_bank_visit().is_empty():
					result = game.resume_bank_visit() if game.pending_bank_visit().kind == "pass" else game.complete_bank_visit()
				elif game.state.phase == "await_roll": result = game.roll()
				elif game.state.phase == "await_action": result = game.end_turn()
				elif game.state.phase == "await_route": result = game.choose_route(int(game.state.route_options[0]))
				else: break
			if game.state.phase != "await_lottery": continue
			found = true
			var actor := int(game.state.current_player)
			var node := int(game.state.players[actor].position)
			check(int(game.state.board[node].event_code) == 9 and game.state.action_options.is_empty(), "public roll reaches source event9 and excludes ordinary actions")
			check(Core.validate_save(game.to_dict()).ok, "normal catalog lottery encounter validates")
			var before: Dictionary = game.to_dict()
			check(not game.choose_action("buy_stock", {"symbol":"s01","quantity":1}).ok and game.to_dict() == before, "pending lottery excludes stock trade")
			check(game.purchase_lottery(1).ok and game.state.lottery_tickets[0] == actor + 1, "public purchase works after normal catalog movement")
			print("LOTTERY_NORMAL_ENTRY edition=%s seed=%d node=%d" % [edition,seed_value,node])
			break
		check(found, "normal public roll finds lottery within bounded seed search: " + edition)
	viewport.queue_free()
	await settle()
	print("Lottery actual catalog checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
