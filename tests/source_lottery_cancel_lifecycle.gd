extends "res://tests/source_autosave_ui.gd"

var lottery_finishes := 0
func mouse_button(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.position = Vector2(320,240)
	event.global_position = event.position
	return event

func qualified_game() -> Object:
	var game := monthly_game(14)
	for i in range(11): game.state.lottery_tickets[i] = 1
	game.state.jackpot = 11000
	return game

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	var folder := "/tmp/richman4-lottery-cancel-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	var storage := CountSlots.new(folder.path_join("slots"),folder.path_join("legacy.json"))
	ui.source_save_menu.storage = storage
	ui.source_lottery_controller.finished.connect(func() -> void: lottery_finishes += 1)
	var game := qualified_game()
	if not Core.validate_save(game.to_dict()).ok:
		print("PRECONDITION_UNMET: valid day14 lottery fixture")
		quit(2)
		return
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state()
	ui._on_end_turn_pressed()
	await settle()
	check(ui.source_monthly_controller.is_open() and ui.source_lottery_controller.report_panel == null, "monthly report precedes queued draw")
	check(storage.attempts == 0 and ui._source_autosave.pending(), "both modals hold daily autosave")
	ui.source_monthly_controller.report_panel.continued.emit()
	await settle()
	var controller: Control = ui.source_lottery_controller
	var panel: Control = controller.report_panel
	if panel == null or not panel.visible or panel.view_model().kind != "draw":
		print("PRECONDITION_UNMET: real draw panel did not open")
		quit(2)
		return
	var before: String = game.to_json()
	var stale_cancel: Callable = panel.cancelled.get_connections()[0].callable
	print("TRACE before right release: ", {"pending":controller.pending_count(),"visible":panel.visible,"finishes":lottery_finishes,"autosaves":storage.attempts})
	# Dispatch actual mouse input through the viewport, not a new close helper.
	viewport.push_input(mouse_button(true),true)
	viewport.push_input(mouse_button(false),true)
	viewport.push_input(mouse_button(false),true)
	await settle()
	print("TRACE after right release: ", {"pending":controller.pending_count(),"visible":is_instance_valid(controller.report_panel) and controller.report_panel.visible,"finishes":lottery_finishes,"autosaves":storage.attempts})
	check(not controller.is_open() and controller.pending_count() == 0 and controller.report_panel == null, "right release clears draw modal instead of hidden-but-pending")
	check(lottery_finishes == 1 and storage.attempts == 1 and not ui._source_autosave.pending(), "duplicate right release finishes and autosaves once")
	check(game.to_json() == before, "draw right close never repeats award or RNG")
	check(ui._source_save_operation_allowed(), "right close releases ordinary load/save gate")
	var roll: Dictionary = ui._invoke_game("roll")
	check(bool(roll.ok), "next actor can roll after draw right close")
	# A callback from the old owner must not cancel a replacement draw.
	ui._cancel_presentation()
	game = qualified_game()
	ui.game_state = game
	ui._refresh_from_state()
	ui._on_end_turn_pressed()
	await settle()
	ui.source_monthly_controller.report_panel.continued.emit()
	await settle()
	panel = controller.report_panel
	before = game.to_json()
	stale_cancel.call()
	await settle()
	check(controller.pending_count() == 1 and controller.report_panel == panel and panel.visible and game.to_json() == before, "stale cancelled connection cannot close replacement owner draw")
	var old_finishes := lottery_finishes
	var old_attempts := storage.attempts
	# Also exercise the real GUI callback branch used by right-button release.
	panel.call("_gui_input",mouse_button(false))
	panel.cancelled.emit()
	await settle()
	check(not controller.is_open() and lottery_finishes == old_finishes+1 and storage.attempts == old_attempts+1, "GUI right release and duplicate cancel finish replacement once")
	check(game.to_json() == before, "replacement acknowledgement preserves settled ledger")
	viewport.queue_free()
	await settle()
	print("Lottery cancel lifecycle acceptance [%s native/injected or headless/controlled]: %d checks, %d failures" % [DisplayServer.get_name(),checks,failures])
	quit(1 if failures else 0)
