extends SceneTree

## Focused checks for the Issue #141 general-options entry in the ordinary UI.
##
## The title OPTION button and the in-game toolbar command must reach the source
## presenter, accepted drafts must persist through the injected settings path,
## cancelling must leave the committed file untouched, and the music switch must
## survive a relaunch.  Only an explicit worktree-local path is injected before
## the scene enters the tree, so the owner's settings and saves are never read
## or written.

const MainScene = preload("res://game/main.tscn")
const SystemSettings = preload("res://game/platform/system_settings.gd")
const SystemHotkeys = preload("res://game/platform/system_hotkeys.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _settle() -> void:
	await process_frame
	await process_frame


func _click(panel: Control, point: Vector2) -> void:
	panel.call("_handle_left_down", point)
	panel.call("_handle_left_up", point)


## Child presenters take a frame-local point and dispatch on release.
func _click_date(panel: Control, point: Vector2) -> void:
	panel.call("_handle_left_down", point)
	panel.call("_handle_left_up")
	await _settle()


func _click_hotkeys(panel: Control, point: Vector2) -> void:
	panel.call("_handle_left_down", point, false)
	panel.call("_handle_left_up")
	await _settle()


## Dispatch through the real viewport so _input ordering and handled flags are
## exercised, not just the panel's close helper.
func _right_release(viewport: Viewport, point: Vector2 = Vector2(10, 400)) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = false
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)
	await _settle()


func _new_ui(settings_file: String, hotkeys_file: String) -> Control:
	var ui: Control = MainScene.instantiate()
	# Must be set before entering the tree: _ready applies committed settings.
	ui.settings_path = settings_file
	ui.hotkeys_path = hotkeys_file
	root.add_child(ui)
	return ui


func _run() -> void:
	var scratch := ProjectSettings.globalize_path("res://.local/source-options-main-ui-%d" % OS.get_process_id())
	_expect(not DirAccess.dir_exists_absolute(scratch), "options fixture requires a new temporary directory")
	_expect(DirAccess.make_dir_recursive_absolute(scratch) == OK, "options fixture directory is created")
	var settings_file := scratch.path_join("settings.json")
	var hotkeys_file := scratch.path_join("hotkeys.json")

	var ui := _new_ui(settings_file, hotkeys_file)
	await _settle()
	ui.set_process(false)
	var shell: Control = ui.source_shell
	var panel: Control = ui.source_options_panel

	_expect(panel != null, "source options presenter is mounted on the reference canvas")
	if panel == null:
		await _finish(ui, scratch, settings_file, hotkeys_file)
		return

	# Without a committed file, a mirrored music field must not override the
	# existing audio preference when the player accepts an unrelated change.
	_expect(shell.title_screen.visible, "normal launch keeps the source title visible")
	if ui.audio_controller != null:
		ui.audio_controller.call("set_enabled", false, false)
	_expect(not shell.title_option_button.disabled, "title OPTION is enabled now that the presenter exists")
	shell.title_option_button.pressed.emit()
	await _settle()
	_expect(panel.call("is_open"), "title OPTION opens the presenter")
	_expect_equal(panel.call("draft_settings")["music_level"], 0, "options mirror disabled audio when no settings file exists")
	panel.call("close_options")
	await _settle()
	_expect(not FileAccess.file_exists(settings_file), "opening and cancelling options does not create a settings file")

	if ui.audio_controller != null:
		ui.audio_controller.call("set_enabled", true, false)
	shell.title_option_button.pressed.emit()
	await _settle()
	_expect(panel.call("is_open"), "title OPTION reopens the presenter")
	var model: Dictionary = panel.call("view_model")
	_expect(model.get("mode") == "title", "title entry presents source title commands")
	_expect_equal(model.get("edition"), str(shell.get("_source_edition")), "title entry uses the active source edition")
	_expect_equal(panel.call("draft_settings")["music_level"], 4, "options mirror enabled audio when no settings file exists")

	_click(panel, Vector2(81 + 1, 17 + 4))
	_expect_equal(panel.call("draft_settings")["speed"], 0, "options draft records the pressed speed row")
	_click(panel, Vector2(227 + 10, 119 + 10))
	await _settle()
	_expect(ui.source_help_controller != null and ui.source_help_controller.is_open(), "help command opens the existing help host")
	_expect(panel.call("is_open"), "help keeps the parent options presenter open")
	# The release lands outside both 640x480 panels, so only _input can close
	# help; the suspended options panel must not swallow it first.
	await _right_release(root)
	_expect(not ui.source_help_controller.is_open(), "real right release closes help from options")
	_expect(panel.call("is_open") and not bool(panel.call("is_input_suspended")), "options input resumes after help")
	_expect_equal(panel.call("draft_settings")["speed"], 0, "help does not discard the parent options draft")

	# Issue #143 date child: confirming keeps the committed date even after the
	# outer options are cancelled, and never writes the settings file.
	var date_panel: Control = ui.source_date_panel
	_click(panel, Vector2(227 + 10, 14 + 10))
	await _settle()
	_expect(date_panel != null and date_panel.call("is_open"), "date command opens the date child")
	_expect(bool(panel.call("is_input_suspended")), "date child suspends the options input")
	var seeded: Dictionary = date_panel.call("draft_date")
	var centers: Dictionary = date_panel.call("day_centers")
	var target_day := 15 if int(seeded.get("day", 0)) != 15 else 14
	await _click_date(date_panel, centers[target_day])
	await _click_date(date_panel, Vector2(134 + 10, 180 + 10))
	var expected_date := {
		"year": int(seeded.get("year", 0)),
		"month": int(seeded.get("month", 0)),
		"day": target_day,
	}
	_expect(not date_panel.call("is_open"), "date OK closes the date child")
	_expect_equal(date_panel.call("committed_date"), expected_date, "date OK commits the chosen day")
	_expect_equal(ui._system_start_date(), expected_date, "committed date seeds the next start date")
	_expect(panel.call("is_open") and not bool(panel.call("is_input_suspended")), "options input resumes after the date child")
	_expect(not FileAccess.file_exists(settings_file), "date confirmation writes no settings file")
	panel.call("close_options")
	await _settle()
	_expect_equal(ui._system_start_date(), expected_date, "outer options cancel keeps the committed date")
	# The ordinary New Game dialog must start on the confirmed date, not the
	# running game's start date.
	ui._on_new_game_pressed()
	await _settle()
	ui._on_new_game_confirm()
	await _settle()
	_expect_equal(ui.state.get("start_date"), expected_date, "New Game starts on the confirmed options date")
	if ui.new_game_popup != null:
		ui.new_game_popup.hide()
	_expect_equal(ui._default_setup_options(4).get("start_date"), expected_date, "default setup options honour the confirmed date")
	# Reopen in title mode directly: help may have left the title screen.
	ui._open_source_options("title")
	await _settle()
	_expect(panel.call("is_open") and panel.call("view_model").get("mode") == "title", "title options reopen after the date child")

	# Issue #143 hotkey child: confirmation persists through its own injected
	# path and survives the outer options cancel.
	var hotkeys_panel: Control = ui.source_hotkeys_panel
	# A corrupt file must not lock the player out: the child opens on the
	# source defaults and confirmation repairs the file.
	var corrupt := FileAccess.open(hotkeys_file, FileAccess.WRITE)
	corrupt.store_string("not json")
	corrupt.close()
	_click(panel, Vector2(227 + 10, 68 + 10))
	await _settle()
	_expect(hotkeys_panel != null and hotkeys_panel.call("is_open"), "hotkey command opens the 28-slot child")
	_expect(bool(panel.call("is_input_suspended")), "hotkey child suspends the options input")
	_expect_equal(FileAccess.get_file_as_string(hotkeys_file), "not json", "opening hotkeys leaves the corrupt file untouched")
	_expect_equal(hotkeys_panel.call("draft_bindings"), SystemHotkeys.new().defaults(), "corrupt hotkeys file opens on the source defaults")
	await _click_hotkeys(hotkeys_panel, Vector2(242 + 10, 281 + 10))
	_expect(not hotkeys_panel.call("is_open"), "hotkey OK closes the child")
	_expect(FileAccess.file_exists(hotkeys_file), "hotkey OK writes the injected bindings file")
	var key_store := SystemHotkeys.new()
	var loaded_keys: Dictionary = key_store.read_bindings(hotkeys_file)
	_expect(bool(loaded_keys.get("ok", false)), "saved hotkeys read back cleanly")
	_expect_equal(loaded_keys.get("bindings", []), key_store.defaults(), "saved hotkeys keep the source defaults")
	_expect(panel.call("is_open") and not bool(panel.call("is_input_suspended")), "options input resumes after the hotkey child")
	_click(panel, Vector2(227 + 10, 68 + 10))
	await _settle()
	await _click_hotkeys(hotkeys_panel, Vector2(130 + 10, 281 + 10))
	_expect(not hotkeys_panel.call("is_open"), "hotkey cancel closes the child")
	panel.call("close_options")
	await _settle()
	_expect(FileAccess.file_exists(hotkeys_file), "outer options cancel keeps the committed hotkeys")

	# A failed save keeps the accepted session bindings when the child reopens.
	var session_keys: Array = key_store.defaults()
	session_keys[8] = 0x5a
	var saved_path: String = ui.hotkeys_path
	ui.hotkeys_path = scratch.path_join("missing-dir/hotkeys.json")
	ui._on_source_hotkeys_accepted(session_keys)
	ui.hotkeys_path = saved_path
	ui._open_source_options("title")
	await _settle()
	ui._open_source_hotkeys_child()
	await _settle()
	_expect_equal(hotkeys_panel.call("draft_bindings"), session_keys, "reopen after a failed save keeps the session bindings")
	hotkeys_panel.call("close_hotkeys")
	panel.call("close_options")
	await _settle()
	ui._open_source_options("title")
	await _settle()
	_expect(panel.call("is_open"), "title options reopen after the hotkey child")
	# The outer cancels above discarded the earlier speed draft; set it again.
	_click(panel, Vector2(81 + 1, 17 + 4))

	_click(panel, Vector2(66 + 4, 82 + 4))
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
		_expect(is_equal_approx(float(ui.audio_controller.get("volume")), 0.0), "music level zero applies a zero runtime gain")
	# Issue #148: accepted values reach the runtime consumers, not just the file.
	_expect_equal(int(ui._source_settings.get("speed", -1)), 0, "accepted speed reaches the runtime settings")
	_expect_equal(ui._source_preferences.movement_seconds(ui._source_settings), 0.24, "accepted speed paces movement presentation only")
	_expect_equal(ui.source_hotkeys_bindings.size(), 28, "startup loads a complete ordinary key set")

	# The HUD music switch must keep the same committed preference, otherwise
	# the next launch reverts it from system-options.json.
	ui._sync_audio_music_level(true)
	loaded = settings.read_settings(settings_file)
	_expect_equal(int((loaded.get("settings", {}) as Dictionary).get("music_level", -1)), 4, "HUD music switch persists its enabled state")
	ui._sync_audio_music_level(false)
	loaded = settings.read_settings(settings_file)
	_expect_equal(int((loaded.get("settings", {}) as Dictionary).get("music_level", -1)), 0, "HUD music switch persists its disabled state")

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

	shell.show_game()
	shell.set_toolbar_enabled("options", true)
	_expect(not shell.toolbar_buttons["options"].disabled, "in-game toolbar OPTION entry is enabled")
	ui._on_source_option_requested()
	await _settle()
	_expect(panel.call("is_open"), "in-game toolbar OPTION opens the presenter")
	_expect(panel.call("view_model").get("mode") == "game", "in-game entry presents the game commands")
	panel.call("close_options")
	await _settle()

	# Issue #148: the default source V binding reaches the same host through
	# the ordinary key dispatch.
	var options_key := InputEventKey.new()
	options_key.keycode = KEY_V
	options_key.pressed = true
	ui._unhandled_input(options_key)
	await _settle()
	_expect(panel.call("is_open"), "source default V binding opens the in-game options host")
	panel.call("close_options")
	await _settle()

	# An unavailable edition (for example the synthetic fallback board) must
	# fail closed: no visible overlay that the modal gate does not know about.
	panel.call("set_view_model", {
		"edition": "test:classic40",
		"mode": "game",
		"settings": SystemSettings.new().defaults(),
	})
	await _settle()
	_expect(not panel.call("is_open"), "unavailable edition is not an open presenter")
	_expect(not panel.visible, "unavailable edition leaves no visible overlay")
	panel.call("close_options")

	ui.queue_free()
	await create_timer(0.15).timeout

	# Relaunch: the committed switch wins over audio.cfg, which still says on.
	var restarted := _new_ui(settings_file, hotkeys_file)
	await _settle()
	restarted.set_process(false)
	if restarted.audio_controller != null:
		_expect(not bool(restarted.audio_controller.get("enabled")), "persisted music switch applies on the next launch")
	else:
		_expect(true, "audio controller is optional for the persisted settings check")
	await _finish(restarted, scratch, settings_file, hotkeys_file)


func _finish(ui: Control, scratch: String, settings_file: String, hotkeys_file: String) -> void:
	ui.queue_free()
	await create_timer(0.15).timeout
	if FileAccess.file_exists(settings_file):
		DirAccess.remove_absolute(settings_file)
	if FileAccess.file_exists(hotkeys_file):
		DirAccess.remove_absolute(hotkeys_file)
	if DirAccess.dir_exists_absolute(scratch):
		DirAccess.remove_absolute(scratch)
	print("Source options main UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
