extends SceneTree

## Hermetic orchestration checks for Issue #147. Child panels and persistence
## stores are fakes, so this test does not touch MainUI or platform state.

const CONTROLLER_PATH := "res://game/ui/source_options_controller.gd"
var checks := 0
var failures := 0
var settings_events: Array = []
var date_events: Array = []
var hotkey_events: Array = []
var commands: Array = []
var finished_count := 0


class FakeStore extends RefCounted:
	var settings := {"speed": 1, "animation": true, "music_level": 4, "sound_level": 4, "autosave": true, "view": 1}
	var bindings := [1, 2, 3]
	var read_calls: Array = []
	var write_calls: Array = []
	var fail_read := false
	var fail_write := false

	func read_settings(path: String) -> Dictionary:
		read_calls.append(path)
		return {"ok": false, "error": "invalid_json"} if fail_read else {"ok": true, "status": "loaded", "settings": settings.duplicate(true)}

	func write_settings(path: String, value: Dictionary) -> Dictionary:
		write_calls.append([path, value.duplicate(true)])
		return {"ok": false, "error": "write_failed"} if fail_write else {"ok": true, "settings": value.duplicate(true)}

	func read_bindings(path: String) -> Dictionary:
		read_calls.append(path)
		return {"ok": false, "error": "invalid_json"} if fail_read else {"ok": true, "status": "loaded", "bindings": bindings.duplicate(true)}

	func write_bindings(path: String, value: Array) -> Dictionary:
		write_calls.append([path, value.duplicate(true)])
		return {"ok": false, "error": "write_failed"} if fail_write else {"ok": true, "bindings": value.duplicate(true)}


class FakePanel extends Control:
	signal accepted(value: Variant)
	signal cancelled
	signal command_requested(command: String)
	signal preview_requested(track: int)
	var model: Dictionary = {}
	var suspended := false

	func set_visual_accessor(_value: Variant) -> void: pass
	func set_view_model(value: Dictionary) -> bool:
		model = value.duplicate(true)
		show()
		return true
	func restore_draft(value: Dictionary) -> bool:
		model["settings"] = value.duplicate(true)
		return true
	func suspend_input(value: bool) -> void: suspended = value
	func set_current_track(_track: int) -> void: pass
	func accept(value: Variant = null) -> void: accepted.emit(value if value != null else model.get("settings", {}))
	func cancel_panel() -> void: cancelled.emit()


class FakeDatePanel extends FakePanel:
	func accept_date(value: Dictionary) -> void: accepted.emit(value)


class FakeHotkeysPanel extends FakePanel:
	func accept_bindings(value: Array) -> void: accepted.emit(value)


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
	if not FileAccess.file_exists(CONTROLLER_PATH):
		push_error("FAIL: source options controller is absent")
		quit(1)
		return
	var script: Script = load(CONTROLLER_PATH)
	var controller: Control = script.new()
	root.add_child(controller)
	var settings_store := FakeStore.new()
	var hotkeys_store := FakeStore.new()
	var owner_a := Node.new()
	var owner_b := Node.new()
	controller.settings_store = settings_store
	controller.hotkeys_store = hotkeys_store
	controller.host_status_text = "部分選項尚未接入"
	controller.settings_path = "user://issue147-settings-test.json"
	controller.hotkeys_path = "user://issue147-hotkeys-test.json"
	controller.options_panel_factory = func() -> Control: return FakePanel.new()
	controller.date_panel_factory = func() -> Control: return FakeDatePanel.new()
	controller.hotkeys_panel_factory = func() -> Control: return FakeHotkeysPanel.new()
	controller.settings_committed.connect(func(value: Dictionary) -> void: settings_events.append(value))
	controller.date_committed.connect(func(value: Dictionary) -> void: date_events.append(value))
	controller.hotkeys_committed.connect(func(value: Array) -> void: hotkey_events.append(value))
	controller.command_requested.connect(func(value: String) -> void: commands.append(value))
	controller.finished.connect(func() -> void: finished_count += 1)
	await _settle()

	_expect(controller.open(owner_a, "title", "Game", null, {"year": 1998, "month": 1, "day": 1}, {"year": 2025, "month": 1, "day": 1}), "controller opens valid owner/session")
	_expect(settings_store.read_calls.has(controller.settings_path), "open explicitly loads settings")
	_expect(hotkeys_store.read_calls.has(controller.hotkeys_path), "open explicitly loads hotkeys")
	var status: Label = controller.status_label
	_expect(status.visible and status.text == "部分選項尚未接入", "host status note is visible when configured")
	_expect(not Rect2(status.position, status.size).intersects(Rect2(147, 59, 347, 363)), "host status note stays outside source options frame")
	var options: FakePanel = controller.options_panel
	options.command_requested.emit("help")
	_expect(options.suspended and commands == ["help"], "help suspends parent and emits command")
	controller.resume_parent()
	_expect(not options.suspended, "resume_parent restores parent input")
	options.command_requested.emit("restart")
	_expect(options.suspended and commands == ["help", "restart"], "confirmation commands suspend parent until resume")
	controller.resume_parent()

	options.command_requested.emit("date")
	var date: FakeDatePanel = controller.date_panel
	_expect(date != null and options.suspended, "date child nests under suspended options parent")
	date.accept_date({"year": 2025, "month": 2, "day": 3})
	_expect(date_events == [{"year": 2025, "month": 2, "day": 3}] and settings_store.write_calls.is_empty(), "date commits at runtime without persistence")
	_expect(controller.date_panel == null and not options.suspended, "date completion resumes parent")

	options.command_requested.emit("hotkeys")
	var hotkeys: FakeHotkeysPanel = controller.hotkeys_panel
	hotkeys_store.fail_write = true
	hotkeys.accept_bindings([4, 5, 6])
	_expect(controller.is_open() and controller.hotkeys_panel != null and options.suspended, "hotkey write failure keeps retryable child session")
	hotkeys_store.fail_write = false
	hotkeys = controller.hotkeys_panel
	hotkeys.accept_bindings([4, 5, 6])
	_expect(hotkey_events == [[4, 5, 6]] and not options.suspended, "hotkey child persists independently and resumes parent")

	settings_store.fail_write = true
	options.accept({"speed": 2, "animation": true, "music_level": 4, "sound_level": 4, "autosave": true, "view": 1})
	_expect(controller.is_open() and controller.options_panel.visible, "settings write failure reopens retryable parent draft")
	settings_store.fail_write = false
	options = controller.options_panel
	options.accept(options.model["settings"])
	_expect(settings_events.size() == 1 and not controller.is_open(), "settings emits only after parent persistence succeeds")
	var finished_before := finished_count
	_expect(controller.open(owner_a, "game", "Game", null, {}, {}), "session can reopen after successful close")
	var old_options: FakePanel = controller.options_panel
	_expect(controller.open(owner_b, "title", "Game", null, {}, {}), "owner replacement starts a fresh generation")
	old_options.accept({})
	_expect(controller.is_open() and controller.current_owner() == owner_b, "stale callback cannot close active session")
	controller.cancel()
	_expect(finished_count == finished_before + 2 and not controller.is_open(), "outer cancel closes active session")
	owner_a.free()
	owner_b.free()
	controller.queue_free()
	await _settle()
	print("Source options controller checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
