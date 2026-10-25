extends SceneTree

## Focused checks for the Issue #141 general-options entry in the ordinary UI.
##
## The title OPTION button and the in-game toolbar command must reach the source
## presenter, accepted drafts must persist through the injected settings path,
## and cancelling must leave the committed file untouched.  Only an explicit
## worktree-local path is used, so the owner's settings and saves are never read
## or written.

const MainScene = preload("res://game/main.tscn")
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


func _run() -> void:
	var scratch := ProjectSettings.globalize_path("res://.local/source-options-main-ui-%d" % OS.get_process_id())
	_expect(not DirAccess.dir_exists_absolute(scratch), "options fixture requires a new temporary directory")
	_expect(DirAccess.make_dir_recursive_absolute(scratch) == OK, "options fixture directory is created")
	var settings_file := scratch.path_join("settings.json")

	var ui: Control = MainScene.instantiate()
	root.add_child(ui)
	await _settle()
	ui.set_process(false)
	ui.settings_path = settings_file
	if ui.audio_controller != null:
		ui.audio_controller.call("set_enabled", true, false)
	var shell: Control = ui.source_shell
	var panel: Control = ui.source_options_panel

	_expect(panel != null, "source options presenter is mounted on the reference canvas")
	if panel == null:
		await _finish(ui, scratch, settings_file)
		return

	# Title entry: available regardless of the toolbar state.
	_expect(shell.title_screen.visible, "normal launch keeps the source title visible")
	_expect(not shell.title_option_button.disabled, "title OPTION is enabled now that the presenter exists")
	shell.title_option_button.pressed.emit()
	await _settle()
	_expect(panel.call("is_open"), "title OPTION opens the presenter")
	var model: Dictionary = panel.call("view_model")
	_expect(model.get("mode") == "title", "title entry presents source title commands")
	_expect_equal(model.get("edition"), str(shell.get("_source_edition")), "title entry uses the active source edition")
	_expect(not FileAccess.file_exists(settings_file), "opening options does not create a settings file")

	# Accepted draft persists through the injected path and applies the switch.
	_click(panel, Vector2(81 + 1, 17 + 4))
	_click(panel, Vector2(66 + 4, 82 + 4))
	_expect_equal(panel.call("draft_settings")["speed"], 0, "options draft records the pressed speed row")
	_expect_equal(panel.call("draft_settings")["music_level"], 0, "options draft records the music switch")
	_click(panel, Vector2(266 + 10, 314 + 10))
	await _settle()
	_expect(not panel.call("is_open"), "OK closes the presenter")
	_expect(FileAccess.file_exists(settings_file), "OK persists the six-field settings file")
	var settings: RefCounted = SystemSettings.new()
	var loaded: Dictionary = settings.read_settings(settings_file)
	_expect(bool(loaded.get("ok", false)), "persisted options read back cleanly")
	_expect_equal(int((loaded.get("settings", {}) as Dictionary).get("speed", -1)), 0, "persisted options keep the accepted speed")
	_expect_equal(int((loaded.get("settings", {}) as Dictionary).get("music_level", -1)), 0, "persisted options keep the accepted music level")
	if ui.audio_controller != null:
		_expect(not bool(ui.audio_controller.get("enabled")), "music switch turns off runtime playback")

	# Reopening presents the committed file and cancel leaves it untouched.
	shell.title_option_button.pressed.emit()
	await _settle()
	_expect(panel.call("is_open"), "title OPTION reopens the presenter")
	_expect_equal(panel.call("draft_settings")["speed"], 0, "reopen presents the committed settings")
	_click(panel, Vector2(89 + 1, 81 + 4))
	_expect_equal(panel.call("draft_settings")["music_level"], 1, "reopen allows further draft changes")
	panel.call("close_options")
	await _settle()
	var after_cancel: Dictionary = settings.read_settings(settings_file)
	_expect_equal(int((after_cancel.get("settings", {}) as Dictionary).get("music_level", -1)), 0, "cancel keeps the committed file")

	# In-game toolbar entry: the handler now opens the game-mode presenter.
	shell.show_game()
	shell.set_toolbar_enabled("options", true)
	_expect(not shell.toolbar_buttons["options"].disabled, "in-game toolbar OPTION entry is enabled")
	ui._on_source_option_requested()
	await _settle()
	_expect(panel.call("is_open"), "in-game toolbar OPTION opens the presenter")
	_expect(panel.call("view_model").get("mode") == "game", "in-game entry presents the game commands")
	panel.call("close_options")

	await _finish(ui, scratch, settings_file)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _finish(ui: Control, scratch: String, settings_file: String) -> void:
	ui.queue_free()
	await create_timer(0.15).timeout
	if FileAccess.file_exists(settings_file):
		DirAccess.remove_absolute(settings_file)
	if DirAccess.dir_exists_absolute(scratch):
		DirAccess.remove_absolute(scratch)
	print("Source options main UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
