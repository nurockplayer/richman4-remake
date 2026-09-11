extends "res://tests/source_title_ui.gd"
const Core = preload("res://game/core/game_state.gd")
var capture_directory := OS.get_environment("RICHMAN4_INVENTORY_CAPTURE")
var capture_records: Array = []
const Inventory = preload("res://game/core/inventory_rules.gd")

func run() -> void:
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("PRECONDITION_UNMET actual catalog required")
		quit(2)
		return
	var view := SubViewport.new()
	var scale_value := int(OS.get_environment("RICHMAN4_INVENTORY_SCALE"))
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
	var edition := OS.get_environment("RICHMAN4_INVENTORY_EDITION")
	if edition.is_empty(): edition = "Game"
	var definition := find_map(ui,edition,1 if edition == "Game" else 7)
	check(ui._new_game(160,4,definition,ui._default_setup_options(4,definition)), "actual factory for legal held-item fixtures")
	var game: Object = ui.game_state
	var actor: Dictionary = game.state.players[0]
	for card in ["免費","停留","均富"]:
		check(Inventory.grant_card(game.state.inventory_supply,actor.cards,card).ok, "grant legal source card " + card)
	check(Inventory.grant_tool(game.state.inventory_supply,actor.tools,"機車",9).ok, "grant ordinary quantity nine")
	check(Core.validate_save(game.to_dict()).ok, "fixture respects core capacity and shared supply")
	game.state.phase = "await_action"
	game._set_action_options(0)
	ui._refresh_from_state()
	var before: String = game.to_json()
	var prior_quit := auto_accept_quit
	press(view,ui.source_shell.toolbar_buttons.cards)
	await settle()
	await capture(view,ui,"cards-held")
	check(ui._source_modal_open() and ui._load_blocked_by_presentation() and not ui._is_human_turn(), "list joins human/modal/load gates")
	check(not auto_accept_quit, "list holds close policy")
	ui._on_roll_pressed()
	ui._on_source_stocks_requested()
	ui._on_source_start_requested()
	ui._on_source_load_requested()
	ui._on_new_game_pressed()
	ui._on_ai_timer_timeout(ui._presentation_generation)
	check(game.to_json() == before and not ui.source_save_menu.visible and not ui.source_shell.is_setup_visible(), "list blocks roll/stocks/new/load/AI without mutation")
	await select(view,ui,0)
	await settle()
	await capture(view,ui,"cards-passive-return")
	check(ui.source_inventory_panel.is_open() and game.to_json() == before, "passive card failure returns unchanged held list")
	await select(view,ui,1)
	await settle()
	check(ui.cards_popup.visible and not ui.source_inventory_panel.is_open(), "targeted card opens existing validated target adapter")
	check(ui.cards_popup.size.y <= view.size.y, "target adapter and its close control fit the source host")
	await capture(view,ui,"card-target-adapter")
	var old_use: Button = ui.cards_popup.find_child("UseCard_停留",true,false)
	var target: OptionButton = ui.cards_popup.find_child("CardTarget_停留",true,false)
	target.add_item("invalid target fixture",999)
	target.select(target.item_count-1)
	old_use.pressed.emit()
	await settle()
	check(ui.source_inventory_panel.is_open() and game.to_json() == before, "core-rejected target returns list without consuming")
	await capture(view,ui,"cards-invalid-return")
	await select(view,ui,1)
	await settle()
	old_use = ui.cards_popup.find_child("UseCard_停留",true,false)
	ui.cards_popup.hide()
	await settle()
	await capture(view,ui,"cards-target-cancel")
	check(ui.source_inventory_panel.is_open() and game.to_json() == before, "target cancellation returns unchanged source list")
	old_use.pressed.emit()
	check(ui.source_inventory_panel.is_open() and game.to_json() == before, "cancelled target callback cannot consume within reopened list")
	ui.get_window().close_requested.emit()
	await settle()
	check(not ui._source_modal_open() and game.to_json() == before and auto_accept_quit == prior_quit, "injected close_requested cancels and restores quit policy")
	old_use.pressed.emit()
	check(game.to_json() == before, "stale target callback cannot consume after close")
	press(view,ui.source_shell.toolbar_buttons.cards)
	await settle()
	await select(view,ui,2)
	await settle()
	await capture(view,ui,"card-success-board")
	check(not ui._source_modal_open() and not actor.cards.has("均富"), "untargeted card successfully uses public core exactly once")
	check(Core.validate_save(game.to_dict()).ok, "successful card consumption returns shared supply")
	game.state.phase = "await_roll"
	game._set_action_options(0)
	ui._refresh_from_state()
	press(view,ui.source_shell.toolbar_buttons.tools)
	await settle()
	await capture(view,ui,"tools-held-nine")
	var map_ids: Array = []
	for slot in range(15): map_ids.append(ui.source_inventory_panel.slot_source_id(slot))
	await select(view,ui,map_ids.find(5))
	await settle()
	check(actor.vehicle == "motorcycle" and int(actor.tools.get("機車",0)) == 8, "tool compact selection uses source ID and public equip")
	check(Inventory.grant_tool(game.state.inventory_supply,actor.tools,"機車").ok, "equipped vehicle plus ordinary nine is legal")
	ui._refresh_from_state()
	press(view,ui.source_shell.toolbar_buttons.tools)
	await settle()
	await capture(view,ui,"tools-equipped-return")
	await select(view,ui,14)
	await settle()
	check(actor.vehicle == "walking" and int(actor.tools.get("機車",0)) == 10 and int(actor.dice_count) == 1, "source14 returns equipped vehicle nine-to-ten without loss")
	check(Core.validate_save(game.to_dict()).ok, "vehicle return exception preserves core save and supply")
	press(view,ui.source_shell.toolbar_buttons.tools)
	await settle()
	await capture(view,ui,"tools-returned-ten")
	ui.get_window().close_requested.emit()
	await settle()
	press(view,ui.source_shell.toolbar_buttons.cards)
	await settle()
	var old_panel: Control = ui.source_inventory_panel
	before = game.to_json()
	var replacement: Object = Core.from_dict(game.to_dict())
	ui.game_state = replacement
	ui._refresh_from_state()
	check(not old_panel.is_open() and not ui._source_modal_open(), "owner replacement clears stale list")
	old_panel.selected.emit(1)
	check(JSON.parse_string(game.to_json()) == JSON.parse_string(before) and JSON.parse_string(replacement.to_json()) == JSON.parse_string(before), "old owner callback cannot affect either game")
	ui._on_source_cards_requested()
	ui._cancel_presentation()
	await settle()
	check(not ui._source_modal_open() and auto_accept_quit == prior_quit, "presentation reset releases list lifetime")
	if not capture_directory.is_empty():
		FileAccess.open(capture_directory.path_join("captures.json"),FileAccess.WRITE).store_string(JSON.stringify(capture_records,"\t"))
	view.queue_free()
	await settle()
	print("Source inventory host checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)

func select(view: SubViewport, ui: Control, slot: int) -> void:
	check(slot >= 0 and slot < 15, "selection addresses a source cell")
	if slot < 0 or slot >= 15: return
	var point: Vector2 = ui.source_inventory_panel.get_global_transform_with_canvas() * (Vector2(19,135)+Vector2(slot%5*80,slot/5*56)+Vector2(20,20))
	var motion := InputEventMouseMotion.new()
	motion.position = point
	view.push_input(motion,true)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point if down else Vector2(view.size)-Vector2(10,10)
		view.push_input(event,true)
		if down and slot == 0 and ui._inventory_mode == "cards": await capture(view,ui,"pressed-card")

func capture(view: SubViewport, ui: Control, label: String) -> void:
	if capture_directory.is_empty(): return
	if DisplayServer.get_name() == "headless":
		print("PRECONDITION_UNMET native renderer required for capture")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(capture_directory)
	if ui.source_inventory_panel.is_open():
		check(ui.source_inventory_panel.source_art_available(), "actual source Panel11 art loaded: " + label)
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	var path := capture_directory.path_join(label + ".png")
	check(picture != null and picture.get_size() == view.size, "native actual host dimensions: " + label)
	check(picture.save_png(path) == OK, "native actual host capture: " + label)
	capture_records.append({"path":path,"sha256":FileAccess.get_sha256(path),"size":[view.size.x,view.size.y],"input":"native injected SubViewport, not physical OS", "model":ui.source_inventory_panel.view_model(), "panel_open":ui.source_inventory_panel.is_open(), "geometry":ui.source_inventory_panel.source_geometry(), "phase":ui.state.get("phase",""), "actor":ui._current_player()})
