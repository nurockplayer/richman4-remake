extends "res://tests/source_title_ui.gd"
class HostAudio extends RefCounted:
	var volume := 0.5
	var enabled := true
	var writes := 0
	func set_volume(value: float, persist := true) -> void:
		volume = value
		if persist: writes += 1
	func set_enabled(value: bool, persist := true) -> void:
		enabled = value
		if persist: writes += 1

class OptionsTestUI extends "res://game/ui/main_ui.gd":
	func _init() -> void:
		var folder := "/tmp/richman4-options-host-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
		DirAccess.make_dir_recursive_absolute(folder)
		source_settings_path = folder.path_join("settings.json")
		source_hotkeys_path = folder.path_join("hotkeys.json")
	func _setup_audio() -> void: pass
	func _load_map_catalog(path: String = "", _fallback: bool = false) -> void:
		if not OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
			super._load_map_catalog(path)
			return
		_map_catalog = []
		for edition in ["Game", "MultiverseJourney"]:
			for number in range(1, 5 if edition == "Game" else 9):
				var definition: Dictionary = Fixture.definition().duplicate(true)
				definition.id = "%s:%d" % [edition, number]
				definition.source.edition = edition
				definition.source.map_number = number
				definition.source.archive = edition + "/map.mkf"
				definition.source.entry_index = number
				_map_catalog.append(definition)
		_map_catalog_complete = _catalog_has_complete_original_content(_map_catalog)
		_map_catalog_ok = _map_catalog_complete
		_selected_map_definition = _map_catalog[0].duplicate(true)
		_update_map_selector()

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = true
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var ui := OptionsTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	if OS.get_environment("RICHMAN4_OPTIONS_TEST_EDITION") == "MultiverseJourney":
		var expansion := find_map(ui, "MultiverseJourney", 7)
		check(ui._new_game(14707, 4, expansion, ui._default_setup_options(4, expansion)), "requested expansion uses actual factory and catalog")
		ui.source_shell.show_title()
		await settle()
	var edition := str(ui.source_shell.get("_source_edition"))
	check(ui._map_catalog_complete and ui.game_state != null, "host uses ordinary validated catalog entry")
	var game: Object = ui.game_state
	var before: String = game.to_json()
	press(viewport, ui.source_shell.title_option_button)
	await settle()
	var controller: Control = ui.source_options_controller
	check(controller.is_open(), "actual title OPTION opens host")
	if not controller.is_open():
		viewport.queue_free()
		await settle()
		quit(1)
		return
	await inspect_options(ui, "title")
	check(controller.options_panel.view_model().get("mode") == "title", "title mode derives from visible title despite initialized game")
	check(ui._source_modal_open() and ui._load_blocked_by_presentation(), "options blocks modal and load paths")
	for method in ["roll", "run_ai_turn", "end_turn"]:
		check(not ui._invoke_game(method).get("ok", false), "options gates " + method)
	ui._on_ai_timer_timeout()
	ui._on_source_save_requested()
	ui._on_source_load_requested()
	ui._on_source_start_requested()
	ui._on_source_map_requested()
	ui._on_source_inspect_requested()
	check(not ui.source_save_menu.visible and not ui.source_shell.is_setup_visible() and not ui.source_shell.is_player_inspector_visible(), "options gates background source entries")
	check(game.to_json() == before, "inspection and blocked actions preserve exact ledger and RNG")
	var date := {"year": 2031, "month": 4, "day": 12}
	click_panel(viewport, controller.options_panel, "modecmd0")
	await settle()
	check(controller.options_panel.is_input_suspended(), "date suspends parent")
	await inspect_options(ui, "date")
	controller.date_panel.set_view_model({"edition": edition, "date": date, "system_date": date})
	click_panel(viewport, controller.date_panel, "accept")
	await settle()
	check(ui._future_start_date() == date, "date child updates future runtime date immediately")
	click_panel(viewport, controller.options_panel, "cancel")
	await settle()
	check(ui.source_shell.is_title_visible(), "closing title options preserves the title surface")
	check(not controller.is_open() and ui._future_start_date() == date, "outer cancel preserves child date")
	check(game.to_json() == before and not FileAccess.file_exists(ui.source_settings_path), "date and outer cancel do not change current match or persist settings")
	press(viewport, ui.source_shell.title_option_button)
	await settle()
	click_panel(viewport, controller.options_panel, "modecmd1")
	await settle()
	check(controller.hotkeys_panel != null and controller.options_panel.is_input_suspended(), "ordinary hotkey child opens with suspended parent")
	await inspect_options(ui, "hotkeys")
	var bindings: Array = ui._source_bindings.duplicate(true)
	bindings[21] = 0x42
	controller.hotkeys_panel.set_view_model({"edition": edition, "bindings": bindings})
	click_panel(viewport, controller.hotkeys_panel, "accept")
	await settle()
	click_panel(viewport, controller.options_panel, "modecmd2")
	await settle()
	check(ui.source_help_controller.is_open() and controller.options_panel.is_input_suspended(), "help nests over options")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	viewport.push_input(release, true)
	await settle()
	check(not ui.source_help_controller.is_open() and controller.is_open() and not controller.options_panel.is_input_suspended(), "help right release returns only to parent without cancelling it")
	click_panel(viewport, controller.options_panel, "cancel")
	await settle()
	check(ui._source_bindings == bindings and FileAccess.file_exists(ui.source_hotkeys_path), "hotkey child commits survive outer cancel")
	check(not FileAccess.file_exists(ui.source_settings_path), "child commits still leave six settings unpersisted")
	press(viewport, ui.source_shell.title_start_button)
	await settle()
	check(ui.source_shell.is_setup_visible(), "ordinary START remains reachable")
	var setup: Control = ui.source_shell.source_setup_panel
	check(setup.collect_options().get("options", {}).get("start_date") == date, "ordinary setup receives runtime-selected date")
	setup.cancel()
	await settle()
	ui.source_shell.show_game()
	ui._refresh_from_state()
	await settle()
	var button: Button = ui.source_shell.toolbar_buttons.options
	check(not button.disabled, "board options toolbar is enabled")
	press(viewport, button)
	await settle()
	check(controller.is_open() and controller.options_panel.view_model().get("mode") == "game", "actual board toolbar selects game mode")
	await inspect_options(ui, "game")
	click_panel(viewport, controller.options_panel, "modecmd0")
	await settle()
	check(ui._source_options_confirmation.visible, "restart requires confirmation")
	ui._source_options_confirmation.hide()
	ui._cancel_source_options_command()
	check(controller.is_open() and game.to_json() == before, "confirmation cancel preserves match and options")
	controller.cancel()
	ui._refresh_from_state()
	var key := InputEventKey.new()
	key.keycode = KEY_B
	key.pressed = true
	ui._unhandled_input(key)
	check(controller.is_open(), "committed remapped system hotkey reaches options")
	var audio := HostAudio.new()
	ui.audio_controller = audio
	ui._source_preferences.capture_audio_baseline(audio)
	var draft: Dictionary = ui._source_settings.duplicate(true)
	draft.view = 2
	draft.speed = 2
	draft.music_level = 1
	controller.options_panel.set_view_model({"edition": edition, "mode": "game", "settings": draft})
	click_panel(viewport, controller.options_panel, "accept")
	await settle()
	check(ui.source_shell.view_mode == 2, "successful parent persistence applies combined view")
	check(ui._source_settings.speed == 2 and FileAccess.file_exists(ui.source_settings_path), "parent OK commits actual presentation preference")
	check(is_equal_approx(audio.volume, 0.3) and audio.writes == 0, "parent OK reaches runtime-only baseline music consumer")
	ui.audio_controller = null
	check(game.to_json() == before, "all options visits preserve exact match")
	ui.source_shell.show_title()
	ui._on_source_start_requested()
	await settle()
	var chosen: Dictionary = ui.source_shell.source_setup_panel.collect_options()
	check(chosen.get("ok", false), "future normal setup retains valid human selection")
	ui.source_shell.source_setup_panel._confirm()
	await settle()
	check(ui.game_state != game and ui.state.get("date", {}) == date, "ordinary confirmation creates a new match at selected date")
	check(ui.state.get("original_companies", false) and ui.game_state.get_stock_symbols().size() == 12, "ordinary new match preserves validated market capability")
	var movement_definition: Dictionary = Fixture.definition()
	check(ui._new_game(1, 2, movement_definition, ui._default_setup_options(2, movement_definition)), "movement consumer fixture creates through factory")
	ui.board_view.set_process(false)
	for player_id in range(2): ui.game_state.set_player_ai(player_id, false)
	ui.game_state.state.players[0].position = 0
	ui.game_state.state.players[0].previous_position = -1
	ui._refresh_from_state()
	var rolled: Dictionary = ui._invoke_game("roll")
	ui._handle_result(rolled)
	check(rolled.get("ok", false) and ui._presentation_busy, "actual roll reaches movement presentation consumer")
	check(is_equal_approx(ui.board_view.get("_movement_step_seconds"), 0.08), "committed speed reaches real BoardView timing")
	var after_roll: String = ui.game_state.to_json()
	ui.board_view._advance_movement(100.0)
	check(ui.game_state.to_json() == after_roll, "presentation pacing and completion preserve simulation and RNG")
	viewport.queue_free()
	await settle()
	print("Source options UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func inspect_options(_ui: Control, _label: String) -> void:
	pass

func click_panel(viewport: SubViewport, panel: Control, key: String) -> void:
	var geometry: Dictionary = panel.source_geometry()
	var rect: Rect2 = panel.source_hitboxes()[key]
	var point := panel.get_global_transform_with_canvas() * (Vector2(geometry.frame_origin) + rect.get_center())
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		viewport.push_input(event, true)
