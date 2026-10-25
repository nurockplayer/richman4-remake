extends SceneTree

## Focused MainUI integration for the source calendar presenter and the three
## source window groups.  The ordinary snapshot refresh must keep the chosen
## view, fill the calendar from the detached state date, and never mutate the
## simulation or consume RNG.  A worktree-local settings path is injected so
## the owner's settings file is never read or written.

const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const BaseMap = preload("res://tests/fixtures/original_map_fixture.gd")

const SUNDAY_RED := Color("#ff0000")
const NORMAL_INK := Color("#101010")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _settle() -> void:
	await process_frame
	await process_frame


func _run() -> void:
	var scratch := ProjectSettings.globalize_path("res://.local/source-calendar-main-ui-%d" % OS.get_process_id())
	_expect(not DirAccess.dir_exists_absolute(scratch), "calendar fixture requires a new temporary directory")
	_expect(DirAccess.make_dir_recursive_absolute(scratch) == OK, "calendar fixture directory is created")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var ui: Control = MainScene.instantiate()
	ui.settings_path = scratch.path_join("settings.json")
	viewport.add_child(ui)
	await _settle()
	ui.set_process(false)
	var normalized: Dictionary = Maps.normalize_map(BaseMap.make())
	_expect(bool(normalized.get("ok", false)), "calendar fixture map normalizes")
	var definition: Dictionary = normalized.get("definition", {})
	ui._set_development_path(true)
	var options: Dictionary = ui._default_setup_options(2, definition)
	options.start_date = {"year": 2024, "month": 3, "day": 2}
	options.human_flags = [true, true]
	_expect(ui._new_game(153, 2, definition, options), "ordinary factory starts a human dated game")
	var shell: Control = ui.source_shell
	shell.show_game()
	ui._refresh_from_state()
	await _settle()
	var game: Object = ui.game_state
	var panel: Control = shell.calendar_panel
	_expect(panel != null and bool(panel.call("is_snapshot_valid")), "calendar presents the started game date")
	_expect(ui._source_view_operation_allowed(), "calendar host input is available in the ordinary game")
	for scale_factor in [1, 2]:
		viewport.size = Vector2i(640, 480) * scale_factor
		ui.size = Vector2(viewport.size)
		shell.size = ui.size
		shell._layout_reference_canvas()
		for mode in [0, 1, 2]:
			# Legal fixture dates isolate the ordinary refresh boundary; this is
			# not a simulated end-turn or monthly settlement claim.
			game.state.day = 1
			game._sync_state()
			ui._refresh_from_state()
			shell.set_view_mode(mode)
			for day in [1, 2]:
				game.state.day = day
				game._sync_state()
				var before: String = game.to_json()
				var camera: Dictionary = ui.board_view.get_camera_state()
				panel.call("set_style", "day")
				ui._refresh_from_state()
				await _settle()
				var context := "mode%d day%d %dx" % [mode, day, scale_factor]
				_expect(shell.view_mode == mode, "refresh retains runtime view: " + context)
				_expect(panel.visible == (mode != 1) and panel.is_visible_in_tree() == (mode != 1), "ordinary refresh retains calendar visibility: " + context)
				_expect(shell.minimap.visible == (mode != 0), "refresh retains minimap visibility: " + context)
				_expect(shell.hud_panel.size == Vector2(200, 80 if mode == 2 else 280), "refresh retains full/compact HUD geometry: " + context)
				_expect(ui.board_view.get_camera_state() == camera, "refresh preserves camera state: " + context)
				_expect(panel.call("snapshot").get("date") == game.state.date, "calendar receives the ordinary refreshed date: " + context)
				var expected_color := SUNDAY_RED if day == 2 else NORMAL_INK
				for label_name in ["SourceCalendarDay", "SourceCalendarWeekday"]:
					var label: Label = panel.find_child(label_name, true, false) as Label
					_expect(label != null and label.get_theme_color("font_color") == expected_color, "source day-style weekday/Sunday ink through MainUI: " + label_name + " " + context)
				_click_calendar_moon(viewport, panel)
				await _settle()
				_expect(panel.call("style") == ("day" if mode == 1 else "month"), "real viewport pointer respects calendar visibility: " + context)
				if mode == 1:
					var release := InputEventMouseButton.new()
					release.button_index = MOUSE_BUTTON_LEFT
					release.pressed = false
					release.position = Vector2(52, 21)
					panel._gui_input(release)
					_expect(panel.call("style") == "day", "hidden calendar rejects stale direct input after refresh: " + context)
				panel.call("set_style", "day")
				_expect(game.to_json() == before, "refresh/display inputs preserve full save and RNG: " + context)
	viewport.queue_free()
	await _settle()
	if DirAccess.dir_exists_absolute(scratch):
		DirAccess.remove_absolute(scratch)
	print("Source calendar MainUI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _click_calendar_moon(viewport: SubViewport, panel: Control) -> void:
	var point: Vector2 = panel.get_global_transform_with_canvas() * Vector2(52, 21)
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
