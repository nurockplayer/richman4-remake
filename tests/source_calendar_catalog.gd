extends "res://tests/source_options_ui.gd"
func run() -> void:
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty() or OS.get_environment("RICHMAN4_SCENE_MANIFEST").is_empty():
		print("PRECONDITION_UNMET: actual catalog and source scene manifest required")
		quit(2)
		return
	var directory := OS.get_environment("RICHMAN4_CALENDAR_CAPTURE")
	var edition := OS.get_environment("RICHMAN4_CALENDAR_EDITION")
	if edition.is_empty(): edition = "Game"
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
	check(ui._map_catalog_complete and ui._map_catalog.size() == 12, "actual catalog provides all12 maps")
	check(definition.get("source", {}).get("edition") == edition, "requested edition resolves actual catalog identity")
	var options: Dictionary = ui._default_setup_options(4, definition)
	options.start_date = {"year": 2024, "month": 2, "day": 29}
	options.human_flags = [true, true, true, true]
	check(ui._new_game(202409, 4, definition, options), "normal catalog factory creates four-human dated match")
	ui.source_shell.show_game()
	ui._refresh_from_state()
	await settle()
	var shell: Control = ui.source_shell
	check(shell.get("_source_edition") == edition and ui.game_state.state.map_source.edition == edition, "normal shell and core preserve requested edition")
	var before: String = ui.game_state.to_json()
	if not directory.is_empty(): DirAccess.make_dir_recursive_absolute(directory)
	for scale_factor in [1, 2]:
		viewport.size = Vector2i(640, 480) * scale_factor
		ui.size = Vector2(viewport.size)
		shell.size = ui.size
		shell._layout_reference_canvas()
		for mode in range(3):
			var camera: Dictionary = ui.board_view.get_camera_state()
			shell.set_view_mode(mode)
			check(ui.board_view.get_camera_state() == camera, "view change preserves exact camera state")
			for style_name in ["day", "month"]:
				shell.calendar_panel.set_style(style_name)
				await settle()
				check(shell.calendar_panel.style() == style_name, "day/month independent from view%d" % mode)
				check(shell._hud_art.texture != null, "actual source HUD art mode%d" % mode)
				check(shell.calendar_panel.source_art_available(), "actual calendar seasonal art resolves")
				if not directory.is_empty() and DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					var path := directory.path_join("%s-view%d-%s-%dx.png" % [edition, mode, style_name, scale_factor])
					check(viewport.get_texture().get_image().save_png(path) == OK, "native capture saves")
	check(ui.game_state.to_json() == before, "complete presentation matrix preserves state/RNG")
	viewport.queue_free()
	await settle()
	print("Source calendar catalog: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
