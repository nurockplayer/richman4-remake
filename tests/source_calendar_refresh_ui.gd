extends "res://tests/source_options_ui.gd"
const RecoveryCore = preload("res://game/core/game_state.gd")

func calendar_pointer(viewport: SubViewport, panel: Control) -> void:
	var point := panel.get_global_transform_with_canvas() * Vector2(52, 21)
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

func run() -> void:
	var edition := OS.get_environment("RICHMAN4_CALENDAR_EDITION")
	if edition.is_empty(): edition = "Game"
	var directory := OS.get_environment("RICHMAN4_CALENDAR_RECOVERY_CAPTURE")
	if not directory.is_empty() and (OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty() or OS.get_environment("RICHMAN4_SCENE_MANIFEST").is_empty()):
		print("PRECONDITION_UNMET: native capture requires actual catalog and source manifest")
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var ui := OptionsTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	var definition := find_map(ui, edition, 1)
	check(not definition.is_empty() and definition.get("source", {}).get("edition") == edition, "precondition: requested source edition resolves")
	var options: Dictionary = ui._default_setup_options(2, definition)
	options.start_date = {"year": 2024, "month": 3, "day": 2}
	options.human_flags = [true, true]
	check(ui._new_game(153, 2, definition, options), "precondition: ordinary factory starts human dated game")
	var shell: Control = ui.source_shell
	shell.show_game()
	ui._refresh_from_state()
	await settle()
	var game: Object = ui.game_state
	var panel: Control = shell.calendar_panel
	check(ui._source_view_operation_allowed(), "precondition: calendar host input is available")
	check(shell.get("_source_edition") == edition and game.state.map_source.edition == edition, "precondition: shell and core retain requested edition")
	if not directory.is_empty(): DirAccess.make_dir_recursive_absolute(directory)
	for scale_factor in [1, 2]:
		viewport.size = Vector2i(640, 480) * scale_factor
		ui.size = Vector2(viewport.size)
		shell.size = ui.size
		shell._layout_reference_canvas()
		for mode in [0, 1, 2]:
			# Legal fixture dates isolate the ordinary host refresh boundary;
			# this is not a simulated end-turn or monthly settlement claim.
			game.state.day = 1
			game._sync_state()
			ui._refresh_from_state()
			shell.set_view_mode(mode)
			for day in [1, 2]:
				game.state.day = day
				game._sync_state()
				check(RecoveryCore.validate_save(game.to_dict()).get("ok", false), "precondition: same/new-date fixture is a valid save")
				var before: String = game.to_json()
				var camera: Dictionary = ui.board_view.get_camera_state()
				panel.set_style("day")
				ui._refresh_from_state()
				await settle()
				var context := "mode%d day%d %dx" % [mode, day, scale_factor]
				check(shell.view_mode == mode, "refresh retains runtime view: " + context)
				check(panel.visible == (mode != 1) and panel.is_visible_in_tree() == (mode != 1), "ordinary same/new-date refresh retains calendar visibility: " + context)
				check(shell.minimap.visible == (mode != 0), "refresh retains minimap visibility: " + context)
				check(shell.hud_panel.size == Vector2(200, 80 if mode == 2 else 280), "refresh retains full/compact HUD geometry: " + context)
				check(ui.board_view.get_camera_state() == camera, "refresh preserves camera state: " + context)
				check(panel.snapshot().date == game.state.date, "calendar receives ordinary refreshed date: " + context)
				var expected_color := Color("#ff0000") if day == 2 else Color("#101010")
				for label_name in ["SourceCalendarDay", "SourceCalendarWeekday"]:
					var label: Label = panel.find_child(label_name, true, false)
					check(label != null and label.get_theme_color("font_color") == expected_color, "source day-style weekday/Sunday ink through MainUI: " + label_name + " " + context)
				if not directory.is_empty() and day == 2 and mode in [0, 1] and DisplayServer.get_name() != "headless":
					check(panel.source_art_available() and shell._hud_art.texture != null, "native source art resolves after ordinary refresh")
					await RenderingServer.frame_post_draw
					var path := directory.path_join("%s-refreshed-view%d-sunday-%dx.png" % [edition, mode, scale_factor])
					check(viewport.get_texture().get_image().save_png(path) == OK, "bounded native recovery capture saves")
				calendar_pointer(viewport, panel)
				check(panel.style() == ("day" if mode == 1 else "month"), "real viewport pointer respects refreshed visibility: " + context)
				if mode == 1:
					# A stale direct component callback must also reject a hidden
					# control; ordinary pointer routing alone can be masked by the
					# minimap sibling layered over a resurrected calendar.
					var release := InputEventMouseButton.new()
					release.button_index = MOUSE_BUTTON_LEFT
					release.pressed = false
					release.position = Vector2(52, 21)
					panel._gui_input(release)
					check(panel.style() == "day", "hidden calendar rejects stale direct input after refresh: " + context)
				check(game.to_json() == before, "refresh/display inputs preserve full save and RNG: " + context)
	viewport.queue_free()
	await settle()
	print("Source calendar refresh UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
