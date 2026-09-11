extends "res://tests/source_shop_catalog.gd"
const Inventory = preload("res://game/core/inventory_rules.gd")
var capture_directory := OS.get_environment("RICHMAN4_SHOP_CAPTURE")
var capture_records: Array = []

func run() -> void:
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("PRECONDITION_UNMET installed catalog required")
		quit(2)
		return
	var view := SubViewport.new()
	var scale_value := int(OS.get_environment("RICHMAN4_SHOP_SCALE"))
	if scale_value not in [1,2]: scale_value = 1
	view.size = Vector2i(640,480) * scale_value
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.handle_input_locally = true
	view.gui_embed_subwindows = true
	root.add_child(view)
	view.notify_mouse_entered()
	var ui := TitleTestUI.new()
	view.add_child(ui)
	await settle()
	ui.set_process(false)
	var edition := OS.get_environment("RICHMAN4_SHOP_EDITION")
	if edition.is_empty(): edition = "Game"
	var definition := find_map(ui,edition,1 if edition == "Game" else 7)
	var options: Dictionary = ui._default_setup_options(4,definition)
	options.human_flags = [true,true,true,true]
	check(ui._new_game(1,4,definition,options),"actual catalog-derived MainUI game")
	ui._source_settings["animation"] = false
	var game: Object = await natural_shop_in_host(ui)
	if game == null:
		print("PRECONDITION_UNMET normal shop entry unavailable")
		quit(2)
		return
	# Only the post-entry budget is a fixture; entry and offers are ordinary.
	var actor_id := int(game.state.current_player)
	game.state.players[actor_id].points = 10000
	ui._refresh_from_state()
	await settle()
	var controller: Control = ui.source_shop_controller
	var panel: Control = controller.panel
	check(panel != null and panel.is_open(),"ordinary shop landing opens full source canvas")
	if panel == null or not panel.is_open():
		quit(1)
		return
	var prior_quit := ui._shop_prior_auto_quit
	check(ui._source_modal_open() and ui._load_blocked_by_presentation() and not ui._source_save_operation_allowed(),"shop owns modal/save/load gates")
	check(not auto_accept_quit,"shop owns window-close policy")
	var before: String = game.to_json()
	ui._on_roll_pressed()
	ui._on_source_stocks_requested()
	ui._on_source_start_requested()
	ui._on_source_load_requested()
	ui._on_source_cards_requested()
	ui._on_source_tools_requested()
	ui._on_new_game_pressed()
	ui._on_ai_timer_timeout(ui._presentation_generation)
	check(game.to_json() == before and not ui.source_save_menu.visible and not ui.source_shell.is_setup_visible(),"pending shop blocks competing human/AI/load/new operations")
	await capture(view,ui,"cards-ready")
	var initial: Dictionary = game.shop_visit_snapshot()
	var row: Dictionary = initial.card_offers[0]
	var points_before := int(game.state.players[actor_id].points)
	var hand_before: int = game.state.players[actor_id].cards.size()
	await pointer(view,panel,Vector2(60,90),MOUSE_BUTTON_LEFT,true)
	await settle()
	check(game.state.players[actor_id].cards.size() == hand_before+1 and game.state.players[actor_id].points == points_before-int(row.price),"native viewport left-down buys exactly one card")
	check(game.shop_visit_snapshot().card_offers[0].is_empty(),"native purchase leaves the precise source row hole")
	before = game.to_json()
	await pointer(view,panel,Vector2(60,90),MOUSE_BUTTON_LEFT,false)
	await pointer(view,panel,Vector2(60,90),MOUSE_BUTTON_LEFT,true)
	await pointer(view,panel,Vector2(60,90),MOUSE_BUTTON_LEFT,false)
	check(game.to_json() == before,"release and consumed row do not repurchase")
	await capture(view,ui,"cards-purchased-hole")
	var held: Dictionary = game.shop_visit_snapshot().cards[0]
	points_before = int(game.state.players[actor_id].points)
	hand_before = game.state.players[actor_id].cards.size()
	await pointer(view,panel,Vector2(250,315),MOUSE_BUTTON_LEFT,true)
	await pointer(view,panel,Vector2(250,315),MOUSE_BUTTON_LEFT,false)
	check(game.state.players[actor_id].cards.size() == hand_before-1 and game.state.players[actor_id].points == points_before+Inventory.quote_sale("card",held.id),"native held-grid sale credits ninety percent for one card")
	var offers_before: Array = game.state.shop_visit.card_offers.duplicate()
	var rng_before: int = game._rng.state
	await pointer(view,panel,Vector2(550,30),MOUSE_BUTTON_LEFT,true)
	await capture(view,ui,"tab-pressed")
	await pointer(view,panel,Vector2(1,479),MOUSE_BUTTON_LEFT,false)
	await settle()
	check(panel.view_model().mode == "tools" and game.state.shop_visit.card_offers == offers_before and game._rng.state == rng_before,"native tab latch releases outside without reroll")
	await capture(view,ui,"tools-ready")
	var tool: Dictionary = game.shop_visit_snapshot().tool_offers[0]
	var quantity_before := int(game.state.players[actor_id].tools.get(tool.id,0))
	await pointer(view,panel,Vector2(70,90),MOUSE_BUTTON_LEFT,true)
	await pointer(view,panel,Vector2(70,90),MOUSE_BUTTON_LEFT,false)
	check(int(game.state.players[actor_id].tools.get(tool.id,0)) == quantity_before+1 and game.shop_visit_snapshot().tool_offers[0].is_empty(),"native tool row buys one and leaves a hole")
	check(panel.view_model().mode == "tools","successful trade retains selected source tab")
	var held_tool: Dictionary = game.shop_visit_snapshot().tools[0]
	quantity_before = int(game.state.players[actor_id].tools[held_tool.id])
	points_before = int(game.state.players[actor_id].points)
	await pointer(view,panel,Vector2(250,315),MOUSE_BUTTON_LEFT,true)
	await pointer(view,panel,Vector2(250,315),MOUSE_BUTTON_LEFT,false)
	check(int(game.state.players[actor_id].tools.get(held_tool.id,0)) == quantity_before-1 and game.state.players[actor_id].points == points_before+Inventory.quote_sale("tool",held_tool.id),"native tool held-grid sells one stack unit")
	await capture(view,ui,"tools-traded")
	var snapshot: Dictionary = game.to_dict()
	check(Core.validate_save(snapshot).ok,"native traded pending visit is valid persistence")
	var file := "/tmp/richman4-shop-pending-%d.json" % OS.get_process_id()
	check(game.save_to_path(file),"pending source visit saves through public persistence")
	var replacement: Object = Core.load_from_path(file)
	check(replacement != null and replacement.to_json() == game.to_json(),"pending visit save/load preserves RNG/holes/transactions")
	var old_panel := panel
	var stale_request := {"visit_id":initial.visit_id,"item_kind":"tool","source_id":2,"offer_index":1}
	ui._apply_loaded_game(replacement,replacement.to_dict(),false)
	var old_before_callback: String = game.to_json()
	var new_before_callback: String = replacement.to_json()
	old_panel.action_requested.emit("buy_item",stale_request)
	# Public JSON serialization is canonical across the loader's numeric
	# normalization; raw pre-JSON dictionaries can differ in numeric types.
	check(game.to_dict() == snapshot and game.to_json() == old_before_callback and replacement.to_json() == new_before_callback and new_before_callback == old_before_callback,"stale previous-owner panel cannot trade in either owner")
	await settle()
	game = replacement
	controller = ui.source_shop_controller
	panel = controller.panel
	check(panel != old_panel and panel.is_open() and not auto_accept_quit,"replacement reopens same persisted visit with fresh callback ownership")
	var inventory_before: Dictionary = {"cards":game.state.players[actor_id].cards.duplicate(),"tools":game.state.players[actor_id].tools.duplicate(),"points":game.state.players[actor_id].points,"supply":game.state.inventory_supply.duplicate(true),"rng":game._rng.state}
	await pointer(view,panel,Vector2(570,260),MOUSE_BUTTON_LEFT,true)
	await capture(view,ui,"exit-pressed")
	await pointer(view,panel,Vector2(1,479),MOUSE_BUTTON_LEFT,false)
	await settle()
	check(game.state.phase == "await_action" and not ui._source_shop_modal_open(),"source EXIT latch returns to board outside release coordinates")
	check(game.state.players[actor_id].cards == inventory_before.cards and game.state.players[actor_id].tools == inventory_before.tools and game.state.players[actor_id].points == inventory_before.points and game.state.inventory_supply == inventory_before.supply and game._rng.state == inventory_before.rng,"EXIT preserves all completed trades and RNG")
	check(auto_accept_quit == prior_quit,"shop close restores original window policy")
	await capture(view,ui,"returned-board")
	before = game.to_json()
	ui._on_shop_pressed()
	check(not ui._source_shop_modal_open() and not ui.shop_popup.visible and game.to_json() == before,"same-visit shop reopen cannot replenish offers")
	check(game.end_turn().ok,"ordinary turn advances after shop return")
	# Separate legal repeat-entry fixture proves right-up cancel and injected
	# window close; neither is described as physical OS input.
	game = Core.from_dict(snapshot)
	ui._apply_loaded_game(game,game.to_dict(),false)
	await create_timer(2.1).timeout
	await settle()
	panel = ui.source_shop_controller.panel
	var supply_before: Dictionary = game.state.inventory_supply.duplicate(true)
	await pointer(view,panel,Vector2(400,230),MOUSE_BUTTON_RIGHT,false)
	await settle()
	check(game.state.phase == "await_action" and game.state.inventory_supply == supply_before and auto_accept_quit == prior_quit,"right-up cancel closes while retaining completed transactions")
	game = Core.from_dict(snapshot)
	ui._apply_loaded_game(game,game.to_dict(),false)
	await create_timer(2.1).timeout
	await settle()
	ui.get_window().close_requested.emit()
	await settle()
	check(game.state.phase == "await_action" and not ui._source_shop_modal_open() and auto_accept_quit == prior_quit,"injected window close leaves shop safely without quitting")
	check(Core.validate_save(game.to_dict()).ok,"final return remains a valid game")
	if not capture_directory.is_empty():
		FileAccess.open(capture_directory.path_join("captures.json"),FileAccess.WRITE).store_string(JSON.stringify(capture_records,"\t"))
	view.queue_free()
	await settle()
	print("Source shop host checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)

func pointer(view: SubViewport, panel: Control, logical: Vector2, button: MouseButton, down: bool) -> void:
	var point: Vector2 = panel.get_global_transform_with_canvas() * logical
	var motion := InputEventMouseMotion.new()
	motion.position = point
	view.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = down
	view.push_input(event,true)

func capture(view: SubViewport, ui: Control, label: String) -> void:
	if capture_directory.is_empty(): return
	if DisplayServer.get_name() == "headless":
		print("PRECONDITION_UNMET native rendering required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(capture_directory)
	var panel: Control = ui.source_shop_controller.panel
	if is_instance_valid(panel): check(panel.source_art_available(),"actual private Panel10/11 art loaded: " + label)
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	var path := capture_directory.path_join(label + ".png")
	check(picture != null and picture.get_size() == view.size,"actual native host dimensions: " + label)
	check(picture.save_png(path) == OK,"actual native host capture: " + label)
	capture_records.append({"path":path,"sha256":FileAccess.get_sha256(path),"size":[view.size.x,view.size.y],"input":"native injected SubViewport; not physical OS","model":panel.view_model() if is_instance_valid(panel) else {},"phase":ui.state.get("phase", ""),"actor":ui._current_player()})

# The same MainUI-created owner advances through host-dispatched public actions.
# This is a natural entry proof; only transaction budget and later rare reloads
# are explicitly injected fixtures. No position/event/offer mutation is used.
func natural_shop_in_host(ui: Object) -> Object:
	var owner: Object = ui.game_state
	for step in range(320):
		var method := ""
		var args: Array = []
		if not owner.pending_bank_visit().is_empty():
			method = "resume_bank_visit" if owner.pending_bank_visit().kind == "pass" else "complete_bank_visit"
		elif owner.state.phase == "await_roll": method = "roll"
		elif owner.state.phase == "await_action": method = "end_turn"
		elif owner.state.phase == "await_route":
			method = "choose_route"
			args = [int(owner.state.route_options[0])]
		elif owner.state.phase == "await_lottery": method = "leave_lottery"
		elif owner.state.phase == "await_minigame":
			method = "finish_minigame"
			args = [int(owner.minigame_snapshot().encounter_id)]
		else: return null
		var result: Dictionary = ui._invoke_game(method,args)
		if not result.get("ok",false):
			var popups: Array = []
			for popup in [ui.new_game_popup,ui.bank_popup,ui.cards_popup,ui.facility_popup,ui.shop_popup,ui.stocks_popup,ui.company_popup,ui.trap_popup,ui.financial_popup,ui.research_popup,ui.content_error_dialog]:
				if popup != null and popup.visible: popups.append(str(popup.name))
			print("HOST_ENTRY_ACTION_FAILED " + JSON.stringify({"step":step,"method":method,"message":result.get("message",""),"popups":popups,"autosave_failed":ui._source_autosave.failed(),"autosave_result":ui._source_autosave.last_result,"monthly":ui._source_monthly_modal_open(),"save_allowed":ui._source_save_operation_allowed(),"validate":Core.validate_save(owner.to_dict())}))
			return null
		ui._handle_result(result)
		await settle()
		var deadline := Time.get_ticks_msec()+10000
		while ui._presentation_busy or ui.fate_popup.visible or ui.news_popup.visible:
			if Time.get_ticks_msec() > deadline:
				print("HOST_ENTRY_PRESENTATION_TIMEOUT step=%d" % step)
				return null
			await process_frame
		await settle()
		# Monthly reports are real intermediate decisions. Acknowledge through
		# their public continuation boundary before the daily autosave resumes.
		# This does not exercise or change the held monthly native-focus lane.
		while ui._source_monthly_modal_open():
			var report: Control = ui.source_monthly_controller.report_panel
			if not is_instance_valid(report) or not report.visible: return null
			report.continue_report()
			await settle()
		if owner.state.phase == "await_shop":
			check(ui.game_state == owner,"natural entry keeps the exact MainUI new-game owner")
			print("SHOP_MAINUI_NATURAL_ENTRY edition=%s step=%d node=%d" % [str(owner.state.map_source.edition),step,int(owner.state.players[int(owner.state.current_player)].position)])
			return owner
	return null
