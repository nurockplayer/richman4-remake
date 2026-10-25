extends SceneTree

## Focused MainUI checks for the source view hotkey and the existing options
## boundary.  Source slot7 TAB cycles the three window groups in memory, the
## host gates keep it out of every modal/pending-action state, and only a
## successful parent OK persists and re-applies the chosen view.  A
## worktree-local settings path keeps the owner's settings untouched.

const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const BaseMap = preload("res://tests/fixtures/original_map_fixture.gd")
const SystemSettings = preload("res://game/platform/system_settings.gd")

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


func _click(panel: Control, point: Vector2) -> void:
	panel.call("_handle_left_down", point)
	panel.call("_handle_left_up", point)


func _key(keycode: int, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.echo = echo
	return event


func _run() -> void:
	var scratch := ProjectSettings.globalize_path("res://.local/source-view-modes-main-ui-%d" % OS.get_process_id())
	_expect(not DirAccess.dir_exists_absolute(scratch), "view fixture requires a new temporary directory")
	_expect(DirAccess.make_dir_recursive_absolute(scratch) == OK, "view fixture directory is created")
	var settings_file := scratch.path_join("settings.json")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 960)
	viewport.handle_input_locally = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var ui: Control = MainScene.instantiate()
	ui.settings_path = settings_file
	viewport.add_child(ui)
	await _settle()
	ui.set_process(false)
	var shell: Control = ui.source_shell
	_expect(int(shell.get("view_mode")) == 1, "a missing settings file keeps the source view1 default")
	viewport.push_input(_key(KEY_TAB), true)
	await _settle()
	_expect(int(shell.get("view_mode")) == 1, "title rejects the view hotkey")

	var normalized: Dictionary = Maps.normalize_map(BaseMap.make())
	_expect(bool(normalized.get("ok", false)), "view fixture map normalizes")
	var definition: Dictionary = normalized.get("definition", {})
	ui._set_development_path(true)
	var options: Dictionary = ui._default_setup_options(2, definition)
	options.start_date = {"year": 2024, "month": 3, "day": 2}
	options.human_flags = [true, true]
	_expect(ui._new_game(154, 2, definition, options), "ordinary factory starts a human dated game")
	var game: Object = ui.game_state
	for player_id in range(2):
		game.set_player_ai(player_id, false)
		game.state.players[player_id].position = 0
		game.state.players[player_id].previous_position = -1
	game.state.current_player = 0
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	await _settle()
	_expect(shell.view_mode == 1, "ordinary game keeps the source view1 default")
	var before: String = game.to_json()
	shell.roll_button.grab_focus()
	viewport.push_input(_key(KEY_TAB), true)
	await _settle()
	_expect(shell.view_mode == 2 and not FileAccess.file_exists(settings_file), "TAB cycles once without a disk write")
	viewport.push_input(_key(KEY_TAB, true), true)
	await _settle()
	_expect(shell.view_mode == 2, "TAB echo does not cycle")
	var shifted := _key(KEY_TAB)
	shifted.shift_pressed = true
	viewport.push_input(shifted, true)
	await _settle()
	_expect(shell.view_mode == 2, "Shift+Tab keeps ordinary focus traversal")
	var controlled := _key(KEY_TAB)
	controlled.ctrl_pressed = true
	viewport.push_input(controlled, true)
	await _settle()
	_expect(shell.view_mode == 2, "Ctrl+Tab is not the source view binding")

	ui._presentation_busy = true
	viewport.push_input(_key(KEY_TAB), true)
	await _settle()
	_expect(shell.view_mode == 2, "movement busy rejects the view hotkey")
	ui._presentation_busy = false
	ui.state["pending_finance"] = {"kind": "test_pending"}
	viewport.push_input(_key(KEY_TAB), true)
	await _settle()
	_expect(shell.view_mode == 2, "pending finance blocks display input")
	ui.state.erase("pending_finance")
	ui._ai_pending = true
	viewport.push_input(_key(KEY_TAB), true)
	await _settle()
	_expect(shell.view_mode == 2, "queued actor transition blocks display input")
	ui._ai_pending = false
	ui._on_source_ai_requested()
	if ui.source_trustee_controller != null and ui.source_trustee_controller.is_open():
		viewport.push_input(_key(KEY_TAB), true)
		await _settle()
		_expect(shell.view_mode == 2, "trustee modal rejects the view hotkey")
		ui.source_trustee_controller.cancel()
		await _settle()

	# Reopening Options reflects the in-session choice; Cancel keeps it.
	ui._on_source_option_requested()
	await _settle()
	var panel: Control = ui.source_options_panel
	_expect(panel.call("is_open"), "ordinary options entry opens the source presenter")
	_expect(int(panel.call("draft_settings").get("view", -1)) == 2, "reopen options reflects the runtime TAB choice")
	viewport.push_input(_key(KEY_TAB), true)
	await _settle()
	_expect(shell.view_mode == 2, "options modal rejects the view hotkey")
	panel.call("close_options")
	await _settle()
	_expect(shell.view_mode == 2 and not FileAccess.file_exists(settings_file), "Cancel preserves the runtime view and writes nothing")

	ui._on_source_map_requested()
	var full_map: bool = shell.full_map_visible
	_expect(full_map, "source map command opens the separate full map")
	viewport.push_input(_key(KEY_TAB), true)
	await _settle()
	_expect(shell.view_mode == 0 and shell.full_map_visible == full_map, "view cycle preserves the separate full map")
	ui._on_source_map_requested()
	await _settle()
	_expect(not shell.full_map_visible, "source map command closes the separate full map")

	# Only a successful parent OK persists and applies the chosen group.
	ui._on_source_option_requested()
	await _settle()
	_click(panel, Vector2(227, 224))
	_expect(int(panel.call("draft_settings").get("view", -1)) == 0, "view_calendar click records the calendar group")
	_click(panel, Vector2(276, 324))
	await _settle()
	var settings := SystemSettings.new()
	var loaded: Dictionary = settings.read_settings(settings_file)
	_expect(bool(loaded.get("ok", false)), "accepted options persist a readable settings file")
	_expect(int((loaded.get("settings", {}) as Dictionary).get("view", -1)) == 0, "accepted options persist the chosen view")
	_expect(shell.view_mode == 0 and shell.calendar_panel.visible and not shell.minimap.visible, "successful persistence applies the calendar group")
	_expect(game.to_json() == before, "all view actions preserve the complete save and RNG")

	ui.queue_free()
	await create_timer(0.15).timeout
	var restarted: Control = MainScene.instantiate()
	restarted.settings_path = settings_file
	viewport.add_child(restarted)
	await _settle()
	restarted.set_process(false)
	_expect(int(restarted.source_shell.get("view_mode")) == 0, "a successful settings load applies the persisted view on relaunch")
	restarted.queue_free()
	await create_timer(0.15).timeout
	viewport.queue_free()
	await _settle()
	if FileAccess.file_exists(settings_file):
		DirAccess.remove_absolute(settings_file)
	if DirAccess.dir_exists_absolute(scratch):
		DirAccess.remove_absolute(scratch)
	print("Source view modes MainUI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
