extends "res://tests/source_title_ui.gd"

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	var definition := find_map(ui, "Game", 1)
	check(ui._map_catalog_complete and not definition.is_empty(), "help entry fixture uses a complete source-capable catalog")
	check(ui._new_game(13901, 4, definition, ui._default_setup_options(4, definition)), "help entry fixture starts through the public source factory")
	await settle()
	var game: Object = ui.game_state
	var before: String = game.to_json()
	var help_button: Button = ui.source_shell.toolbar_buttons.help
	check(not ui.source_shell.is_title_visible() and not ui._presentation_busy, "help entry fixture is on the idle board")
	check(not help_button.disabled, "ordinary board help command is enabled")
	# Existing public entry is callable on the baseline, so a missing response is
	# an observed entry failure; the unexecuted lifetime checks are not RED proof.
	ui._on_source_help_requested()
	await settle()
	var controller: Control = _controller(ui)
	check(controller != null and controller.is_open(), "ordinary help request opens the source help window")
	if controller == null or not controller.is_open():
		viewport.queue_free()
		await settle()
		print("Source help UI checks: %d, failures: %d" % [checks, failures])
		quit(1 if failures else 0)
		return
	var panel: Control = controller.help_panel
	check(panel != null and panel.visible and panel.has_method("is_model_valid"), "help uses the real presenter including its explicit unavailable state")
	if not OS.get_environment("RICHMAN4_HELP_MANIFEST").is_empty():
		check(panel.is_model_valid() and panel.view_model().get("edition") == "Game", "supplied help bundle must present valid Game content")
	if not OS.get_environment("RICHMAN4_SCENE_MANIFEST").is_empty() and not OS.get_environment("RICHMAN4_HELP_MANIFEST").is_empty():
		check(panel.source_art_available(), "supplied Game help art must resolve")
	await inspect_help(panel, "Game")
	check(ui._source_modal_open() and ui._load_blocked_by_presentation(), "help participates in modal and load guards")
	check(game.to_json() == before, "opening help preserves the full ledger and RNG")
	ui._on_source_help_requested()
	ui._refresh_from_state()
	await settle()
	check(controller.help_panel == panel, "repeated request and refresh retain the current help window")
	for method in ["roll", "run_ai_turn", "end_turn"]:
		var result: Dictionary = ui._invoke_game(method)
		check(not bool(result.get("ok", false)), "help blocks underlying action %s" % method)
	ui._on_ai_timer_timeout()
	ui._on_source_save_requested()
	ui._on_source_load_requested()
	ui._on_source_stocks_requested()
	ui._on_source_map_requested()
	ui._on_source_inspect_requested()
	ui._on_source_start_requested()
	await settle()
	check(not ui.source_save_menu.visible and not ui.source_stock_panel.visible and not ui.source_shell.is_player_inspector_visible() and not ui.source_shell.is_setup_visible(), "help blocks other source windows and new-game entry")
	check(ui.game_state == game and game.to_json() == before, "blocked actions preserve the current match and RNG")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = panel.get_global_transform_with_canvas() * Vector2(320, 240)
	release.global_position = release.position
	viewport.push_input(release, true)
	await settle()
	check(not controller.is_open() and not ui._source_modal_open(), "source right-button release closes help and returns to the board")
	check(game.to_json() == before, "help acknowledgment preserves the full ledger and RNG")
	check(not help_button.disabled and not ui._load_blocked_by_presentation(), "board commands return after help closes")
	press(viewport, help_button)
	await settle()
	check(controller.is_open(), "the actual toolbar button reopens help")
	var old_panel: Control = controller.help_panel
	var expansion := find_map(ui, "MultiverseJourney", 7)
	check(ui._new_game(13907, 4, expansion, ui._default_setup_options(4, expansion)), "explicit game replacement adopts the next source edition")
	await settle()
	check(not controller.is_open(), "game replacement cancels the previous help session")
	ui._on_source_help_requested()
	await settle()
	check(controller.is_open() and controller.help_panel != old_panel, "replacement game creates a new help session")
	check(controller.current_edition() == "MultiverseJourney", "help content follows the adopted edition")
	if not OS.get_environment("RICHMAN4_HELP_MANIFEST").is_empty():
		check(controller.help_panel.is_model_valid() and controller.help_panel.view_model().get("edition") == "MultiverseJourney", "supplied help bundle must present valid replacement edition content")
	if not OS.get_environment("RICHMAN4_SCENE_MANIFEST").is_empty() and not OS.get_environment("RICHMAN4_HELP_MANIFEST").is_empty():
		check(controller.help_panel.source_art_available(), "supplied expansion help art must resolve")
	await inspect_help(controller.help_panel, "MultiverseJourney")
	controller.cancel()
	viewport.queue_free()
	await settle()
	print("Source help UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func _controller(ui: Control) -> Control:
	for property in ui.get_property_list():
		if property.name == "source_help_controller":
			return ui.get("source_help_controller")
	return null

func inspect_help(_panel: Control, _edition: String) -> void:
	# Private native capture subclasses can inspect the real public-entry panel.
	pass
