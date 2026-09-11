extends "res://tests/source_monthly_ui.gd"

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.handle_input_locally = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	var edition := OS.get_environment("RICHMAN4_TRUSTEE_EDITION")
	if edition.is_empty(): edition = "Game"
	var definition := find_map(ui, edition, 1)
	var options: Dictionary = ui._default_setup_options(3, definition)
	options.human_flags = [true, true, false]
	check(ui._new_game(811, 3, definition, options), "ordinary catalog factory creates mixed-origin game")
	ui.source_shell.show_game()
	ui._refresh_from_state()
	await settle()
	var game: Object = ui.game_state
	check(Core.validate_save(game.to_dict()).get("ok", false), "host setup is a valid save")
	check(ui.has_method("_source_trustee_modal_open"), "ordinary toolbar trustee host is implemented")
	check(not ui.source_shell.toolbar_buttons.ai.disabled, "ordinary toolbar trustee button is enabled")
	if not ui.has_method("_source_trustee_modal_open"):
		viewport.queue_free()
		await settle()
		quit(1)
		return
	var before: String = game.to_json()
	var original_quit := auto_accept_quit
	press(viewport, ui.source_shell.toolbar_buttons.ai)
	await settle()
	var controller: Control = ui.source_trustee_controller
	check(controller.is_open() and controller.get_parent() == ui.source_shell.reference_canvas, "ordinary toolbar opens source canvas trustee")
	check(game.to_json() == before, "opening and inspecting leave full state/RNG unchanged")
	check(ui._source_modal_open() and ui._load_blocked_by_presentation() and not ui._is_human_turn(), "trustee joins all host action and persistence gates")
	check(not auto_accept_quit, "OS close cannot quit app while draft is pending")
	controller.dialog.set_ratio(0, "cash_ratio", 80)
	controller.dialog.set_ratio(1, "stock_ratio", 0)
	controller.dialog.select_player(1)
	check(not controller.draft_rows()[1].trustee, "other human row selects without toggling")
	controller.dialog.select_player(1)
	check(controller.draft_rows()[1].trustee, "selected row toggles")
	ui._on_roll_pressed()
	ui._on_source_map_requested()
	ui._on_source_inspect_requested()
	ui._on_source_stocks_requested()
	ui._on_source_load_requested()
	ui._on_source_start_requested()
	ui._on_ai_timer_timeout(ui._presentation_generation - 1)
	check(game.to_json() == before and not ui.source_save_menu.visible and not ui.source_stock_panel.visible and not ui.source_shell.is_setup_visible(), "open draft rejects board/new/load/stocks and stale AI callbacks")
	await inspect_trustee(ui, "selected-draft")
	controller.cancel()
	await settle()
	check(game.to_json() == before and not ui._source_modal_open() and auto_accept_quit == original_quit, "Cancel preserves state and restores host window policy")
	ui._on_source_ai_requested()
	controller = ui.source_trustee_controller
	controller.dialog.set_ratio(0, "cash_ratio", 80)
	controller.dialog.set_ratio(1, "stock_ratio", 0)
	controller.dialog.select_player(1)
	controller.dialog.select_player(1)
	controller.dialog.accept_dialog()
	await settle()
	check(game.trustee_rows()[0].cash_ratio == 80 and not game.state.players[0].is_ai and game.state.players[1].is_ai and game.state.players[2].is_ai, "OK atomically commits preferences for human and trustee while preserving native AI")
	var committed: String = game.to_json()
	check(Core.validate_save(game.to_dict()).get("ok", false), "accepted settings are save-valid")
	ui._on_source_ai_requested()
	controller = ui.source_trustee_controller
	check(controller.draft_rows()[0].cash_ratio == 80 and controller.draft_rows()[1].stock_ratio == 0, "reopen loads both committed row preferences")
	controller.dialog.set_ratio(0, "cash_ratio", 0)
	ui.get_window().close_requested.emit()
	await settle()
	check(not controller.is_open() and game.to_json() == committed and auto_accept_quit == original_quit, "Window close signal cancels draft without ledger/RNG changes or app quit")
	ui._on_source_ai_requested()
	var old_controller: Control = ui.source_trustee_controller
	var stale: Array = old_controller.draft_rows()
	old_controller.cancel()
	ui._on_source_ai_requested()
	controller = ui.source_trustee_controller
	stale[0].trustee = true
	old_controller.accepted.emit(stale)
	old_controller.cancelled.emit()
	check(controller.is_open() and game.to_json() == committed, "stale prior modal signals cannot commit or cancel the new session")
	controller.cancel()
	await settle()
	ui._on_source_ai_requested()
	controller = ui.source_trustee_controller
	var replacement: Object = Core.from_dict(JSON.parse_string(committed))
	ui.game_state = replacement
	ui._refresh_from_state()
	check(not controller.is_open() and replacement.to_json() == committed, "owner replacement cancels old draft")
	controller.accepted.emit(stale)
	check(replacement.to_json() == committed and game.to_json() == committed, "old owner acceptance cannot write either game")
	ui._cancel_presentation()
	game = monthly_game(14)
	ui.game_state = game
	ui._source_settings.autosave = true
	ui._refresh_from_state()
	ui._on_end_turn_pressed()
	await settle()
	check(ui.source_monthly_controller.is_open() and ui._source_autosave.pending(), "real daily wrap queues report and automatic checkpoint")
	ui._on_source_ai_requested()
	check(not ui._source_trustee_modal_open(), "trustee cannot bypass pending monthly/autosave sequencing")
	ui.source_monthly_controller.report_panel.continued.emit()
	await settle()
	check(not ui._source_autosave.pending(), "report acknowledgment completes normal automatic checkpoint")
	ui._on_source_ai_requested()
	controller = ui.source_trustee_controller
	check(controller.is_open(), "trustee becomes reachable after stable checkpoint")
	for row in controller.draft_rows():
		controller.dialog.select_player(int(row.player_id))
		if not controller.draft_rows()[int(row.player_id)].trustee:
			controller.dialog.toggle_selected()
	controller.dialog.accept_dialog()
	await settle()
	var release := InputEventKey.new()
	release.keycode = KEY_ESCAPE
	release.pressed = false
	ui._unhandled_input(release)
	check(bool(game.state.get("trustee_recovery_requested", false)) and game.state.players[0].is_ai, "all-trustee Escape release requests delayed recovery")
	var result: Dictionary = game.run_ai_turn()
	check(result.get("ok", false) and not game.state.players[0].is_ai and game.state.players[1].is_ai, "next real actor boundary recovers source player0 only")
	viewport.queue_free()
	await settle()
	print("Trustee MainUI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func inspect_trustee(_ui: Control, _label: String) -> void:
	pass
