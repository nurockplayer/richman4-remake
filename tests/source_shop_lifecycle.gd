extends "res://tests/source_shop_core.gd"

func run() -> void:
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("PRECONDITION_UNMET installed catalog required")
		quit(2)
		return
	var view := SubViewport.new()
	view.size = Vector2i(640,480)
	view.gui_embed_subwindows = true
	root.add_child(view)
	var ui := TitleTestUI.new()
	view.add_child(ui)
	await settle()
	ui.set_process(false)
	definition = find_map(ui,"Game",1)
	options = ui._default_setup_options(4,definition)
	options.human_flags = [true,true,true,true]
	for tile in definition.board:
		if int(tile.get("event_code",0)) == 15:
			node_id = int(tile.index)
			break
	check(ui._new_game(1,4,definition,options),"lifecycle ordinary catalog host created")
	var prior_quit := auto_accept_quit
	var game := game_at_shop(22,true,false)
	var company: Dictionary = game.get_company_at(node_id)
	var symbol: String = game.get_stock_symbols()[int(company.stock_index)]
	check(game.choose_action("buy_stock",{"symbol":symbol,"quantity":1}).ok,"rare gift fixture acquires real venue through public market")
	game._resolve_landing(0,false)
	var before: Dictionary = game.to_dict()
	var visit: Dictionary = game.shop_visit_snapshot()
	ui._apply_loaded_game(game,before,false)
	await settle()
	var controller: Control = ui.source_shop_controller
	var panel: Control = controller.panel
	check(panel.is_open() and panel.visible and not panel.view_model().ready and panel.find_child("SourceShopGiftMessage",true,false) != null,"gift is visible for its pending modal interval")
	check(not ui._source_save_operation_allowed() and ui._load_blocked_by_presentation() and not auto_accept_quit,"gift interval owns the same save/load/quit gates")
	await create_timer(0.4).timeout
	check(game.to_dict() == before and not game.shop_visit_snapshot().ready,"gift does not settle before source 1500ms interval")
	# Blocking another presenter pauses the visible interval without touching RNG.
	controller.sync(game,true)
	await create_timer(1.2).timeout
	check(game.to_dict() == before,"hidden gift interval cannot complete behind another modal")
	ui._sync_source_shop()
	await create_timer(1.2).timeout
	await settle()
	check(game.shop_visit_snapshot().ready and panel.is_open() and panel.visible,"gift naturally settles once then opens same shop")
	# Public acknowledgement updates only gift_pending and normal result metadata.
	check(game.state.shop_visit.card_offers == before.shop_visit.card_offers and game.state.shop_visit.tool_offers == before.shop_visit.tool_offers and game.state.inventory_supply == before.inventory_supply and game.state.players == before.players and game._rng.state == int(before.rng_state),"gift timer does not grant again, reroll, or transact")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(550,30)
	panel._gui_input(down)
	ui._sync_source_shop()
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(1,479)
	panel._gui_input(up)
	check(panel.view_model().mode == "tools","unchanged owner repaint preserves a held source tab latch")
	before = game.to_dict()
	await create_timer(0.2).timeout
	check(game.to_dict() == before,"completed gift never repeats acknowledgement")
	controller.cancel()
	check(game.to_dict() == before and ui._source_shop_modal_open(),"controller cancellation preserves pending core ownership")
	ui._sync_source_shop()
	await settle()
	check(controller.panel.is_open() and controller.panel != panel and not auto_accept_quit,"same persisted visit resumes with new presenter ownership")
	check(ui._new_game(2,4,definition,options),"formal new-game replacement succeeds")
	await settle()
	check(ui.game_state != game and game.to_dict() == before and not ui._source_shop_modal_open() and auto_accept_quit == prior_quit,"new game releases shop policy without mutating old pending world")
	ui._apply_loaded_game(game,before,false)
	await settle()
	check(ui._source_shop_modal_open() and not auto_accept_quit,"loaded pending visit reacquires policy")
	view.queue_free()
	await settle()
	check(auto_accept_quit == prior_quit and game.to_dict() == before,"tree exit releases policy and preserves pending world")
	print("Source shop lifecycle checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
