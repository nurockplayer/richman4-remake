extends "res://tests/source_title_ui.gd"
const Core = preload("res://game/core/game_state.gd")

func run() -> void:
	var catalog := OS.get_environment("RICHMAN4_MAP_CATALOG")
	if catalog.is_empty() or FileAccess.get_sha256(catalog) != "ac6a07666ceb9d8b4f1be8a6df3d486a3ffbb1f643cd383fd58daf81c5449565":
		print("PRECONDITION_UNMET actual installed catalog identity required")
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640,480)
	root.add_child(viewport)
	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	if not ui._map_catalog_complete or ui._map_catalog.size() != 12:
		print("PRECONDITION_UNMET incomplete actual catalog")
		quit(2)
		return
	for edition in ["Game", "MultiverseJourney"]:
		var definition := find_map(ui,edition,1 if edition == "Game" else 7)
		var options: Dictionary = ui._default_setup_options(4,definition)
		options.human_flags = [true,true,true,true]
		check(ui._new_game(162,4,definition,options),"actual definition-derived MainUI game starts: " + edition)
		var game: Object = normal_shop(definition,options)
		check(game != null,"ordinary public movement reaches source shop: " + edition)
		if game == null: continue
		check(game.state.phase == "await_shop","ordinary shop landing owns pending source visit: " + edition)
		check(game.state.action_options.is_empty(),"human shop excludes ordinary actions")
		var before: Dictionary = game.to_dict()
		var runner: Dictionary = game.run_ai_match(1)
		check(not runner.get("ok",false) and runner.get("completed_turns",-1) == 0 and runner.get("awaiting_response",false) and game.to_dict() == before,"AI match cannot take over or count a pending human shop")
		# Restore the same naturally reached world after checking runner invariance.
		game = Core.from_dict(before)
		check(game != null,"ordinary visit save restores")
		if game == null: continue
		var actor := int(game.state.current_player)
		game.state.players[actor].points = 10000 # Legal transaction budget fixture after ordinary entry.
		before = game.to_dict()
		var trade: Dictionary = game.choose_action("buy_item",{"item_kind":"tool","item_id":"機車","quantity":2})
		check(not trade.get("ok",false) and game.to_dict() == before,"normal public shop rejects unrestricted bulk bypass atomically")
		var has_snapshot := game.has_method("shop_visit_snapshot")
		check(has_snapshot,"ordinary shop exposes finite public visit snapshot")
		if has_snapshot:
			var visit: Dictionary = game.call("shop_visit_snapshot")
			var cards: Array = visit.get("card_offers",[])
			check(cards.size() >= 6 and cards.size() <= 15,"normal source visit samples six to fifteen card copies")
			check(visit.get("tool_offers",[]).size() <= 8,"normal source visit has at most eight tool rows")
			before = game.to_dict()
			game.call("shop_visit_snapshot")
			check(game.to_dict() == before,"public repaint snapshot never rerolls or reserves supply")
		ui.game_state = game
		ui.state = game.get_snapshot()
		ui._update_all()
		await settle()
		var panel := ui.source_shell.find_child("SourceShopPanel",true,false)
		check(panel != null and panel.has_method("is_open") and panel.call("is_open"),"ordinary pending landing opens actual MainUI source Panel10")
		check(not ui.shop_popup.visible,"ordinary source entry does not open generic quantity form")
	viewport.queue_free()
	await settle()
	print("Source shop actual catalog checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)

func normal_shop(definition: Dictionary, options: Dictionary) -> Object:
	for seed_value in range(1,33):
		var game: Object = Core.new_game_on_board(seed_value,4,definition,options)
		if game == null: return null
		game.configure_minigames(false) # Public animation-off option settles unrelated minigame entry.
		for step in range(320):
			var result: Dictionary = {"ok":false}
			if not game.pending_bank_visit().is_empty():
				result = game.resume_bank_visit() if game.pending_bank_visit().kind == "pass" else game.complete_bank_visit()
			elif game.state.phase == "await_roll": result = game.roll()
			elif game.state.phase == "await_action": result = game.end_turn()
			elif game.state.phase == "await_route": result = game.choose_route(int(game.state.route_options[0]))
			elif game.state.phase == "await_lottery": result = game.leave_lottery()
			elif game.state.phase == "await_minigame": result = game.finish_minigame(int(game.minigame_snapshot().encounter_id))
			else: break
			if not result.get("ok",false): break
			var actor := int(game.state.current_player)
			var tile: Dictionary = game.state.board[int(game.state.players[actor].position)]
			if game.state.phase not in ["await_action","await_shop"] or int(tile.get("event_code",0)) != 15: continue
			print("SHOP_NORMAL_ENTRY edition=%s seed=%d step=%d node=%d phase=%s" % [str(game.state.map_source.edition),seed_value,step,int(tile.index),str(game.state.phase)])
			return game
	return null
