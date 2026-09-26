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
	view.notify_mouse_entered()
	var ui := MainScene.instantiate()
	view.add_child(ui)
	await settle()
	ui.set_process(false)
	definition = find_map(ui,"Game",1)
	options = ui._default_setup_options(4,definition)
	for tile in definition.board:
		if int(tile.get("event_code",0)) == 15:
			node_id = int(tile.index)
			break
	check(ui._new_game(1,4,definition,options),"lifecycle ordinary catalog host created")
	var prior_quit: bool = root.get_tree().auto_accept_quit
	var game := game_at_shop(22,true,false)
	var company: Dictionary = game.get_company_at(node_id)
	company.owner = 0 # Explicit rare-state fixture: exercise an already-owned catalog venue's visit gift.
	game._resolve_landing(0,false)
	var before: Dictionary = game.to_dict()
	var visit: Dictionary = game.shop_visit_snapshot()
	ui._apply_loaded_game(game,before,false)
	ui._sync_source_shop()
	await settle()
	var controller: Control = ui.source_shop_controller
	var panel: Control = controller.panel
	check(panel.is_open() and panel.visible and not panel.view_model().ready and panel.find_child("SourceShopGiftMessage",true,false) != null,"gift is visible for its pending modal interval")
	check(not ui._source_save_operation_allowed() and ui._load_blocked_by_presentation() and not root.get_tree().auto_accept_quit,"gift interval owns the same save/load/quit gates")
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
	before = game.to_dict()
	controller.sync(game,true)
	await _push_view(view,panel,Vector2(1,1),MOUSE_BUTTON_RIGHT,false)
	check(game.to_dict() == before and panel.visible and not panel.is_visible_in_tree(),"blocked ancestor rejects global right-up without cancelling the local panel")
	controller.sync(game,false)
	check(panel.is_open() and panel.is_visible_in_tree(),"unblocking unchanged snapshot restores an interactive open panel")
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
	check(game.to_dict() == before and ui._source_shop_modal_open() and root.get_tree().auto_accept_quit == prior_quit,"controller cancellation restores prior true quit policy and preserves pending core ownership")
	root.get_tree().auto_accept_quit = false
	prior_quit = false
	ui._sync_source_shop()
	await settle()
	check(controller.panel.is_open() and controller.panel != panel and not root.get_tree().auto_accept_quit,"same persisted visit resumes with new presenter ownership")
	controller.cancel()
	check(root.get_tree().auto_accept_quit == prior_quit and game.to_dict() == before,"second cancellation restores prior false quit policy")
	ui._sync_source_shop()
	await settle()
	controller = ui.source_shop_controller
	check(controller.panel.is_open() and not root.get_tree().auto_accept_quit,"visit reopens after false-policy cancellation")
	check(ui._new_game(2,4,definition,options),"formal new-game replacement succeeds")
	await settle()
	check(ui.game_state != game and game.to_dict() == before and not ui._source_shop_modal_open() and root.get_tree().auto_accept_quit == prior_quit,"new game releases shop policy without mutating old pending world")
	ui._apply_loaded_game(game,before,false)
	ui._sync_source_shop()
	await settle()
	check(ui._source_shop_modal_open() and not root.get_tree().auto_accept_quit,"loaded pending visit reacquires policy")
	view.queue_free()
	await settle()
	check(root.get_tree().auto_accept_quit == prior_quit and game.to_dict() == before,"tree exit releases policy and preserves pending world")
	root.get_tree().auto_accept_quit = true
	var true_view := SubViewport.new()
	true_view.size = Vector2i(640,480)
	root.add_child(true_view)
	var true_ui := MainScene.instantiate()
	true_view.add_child(true_ui)
	await settle()
	true_ui.set_process(false)
	true_ui._apply_loaded_game(game,before,false)
	true_ui._sync_source_shop()
	await settle()
	check(not root.get_tree().auto_accept_quit,"true-policy replacement fixture opens shop gate")
	check(true_ui._new_game(3,4,definition,options),"true-policy replacement starts new game")
	await settle()
	check(root.get_tree().auto_accept_quit,"shop replacement restores prior true quit policy")
	true_ui._apply_loaded_game(game,before,false)
	true_ui._sync_source_shop()
	await settle()
	true_view.queue_free()
	await settle()
	check(root.get_tree().auto_accept_quit,"tree exit restores prior true quit policy")
	print("Source shop lifecycle checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)

func _push_view(view: SubViewport, panel: Control, point: Vector2, button: MouseButton, down: bool) -> void:
	var canvas_point: Vector2 = panel.get_global_transform_with_canvas() * point
	var event := InputEventMouseButton.new()
	event.position = canvas_point
	event.global_position = canvas_point
	event.button_index = button
	event.pressed = down
	view.push_input(event,true)
	await process_frame
