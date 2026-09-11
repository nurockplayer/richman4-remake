extends SceneTree
const Controller = preload("res://game/ui/source_options_controller.gd")
const Settings = preload("res://game/platform/system_settings.gd")
const Hotkeys = preload("res://game/platform/system_hotkeys.gd")
class Store extends RefCounted:
	var fail := true
	var corrupt := false
	var settings: Dictionary = Settings.new().defaults()
	var bindings: Array = Hotkeys.new().defaults()
	func read_settings(_path: String) -> Dictionary:
		return {"ok": false, "error": "invalid_json"} if corrupt else {"ok": true, "settings": settings}
	func read_bindings(_path: String) -> Dictionary:
		return {"ok": true, "bindings": bindings}
	func write_settings(_path: String, value: Dictionary) -> Dictionary:
		if fail: return {"ok": false, "error": "write_failed"}
		settings = value.duplicate(true)
		return {"ok": true}
	func write_bindings(_path: String, value: Array) -> Dictionary:
		if fail: return {"ok": false, "error": "write_failed"}
		bindings = value.duplicate(true)
		return {"ok": true}
var checks := 0
var failures := 0
var previews := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var store := Store.new()
	store.settings.music_level = 0
	controller.settings_store = store
	controller.hotkeys_store = store
	controller.preview_requested.connect(func(_track: int) -> void: previews += 1)
	var date := {"year": 2031, "month": 4, "day": 12}
	controller.open(self, "title", "Game", null, date, date)
	check(controller.options_panel.is_model_valid(), "controller supplies exactly the real options model contract")
	var draft: Dictionary = store.settings.duplicate(true)
	draft.music_level = 4
	draft.speed = 2
	controller.options_panel.restore_draft(draft)
	controller.options_panel._accept()
	check(controller.is_open() and controller.options_panel.is_open(), "failed persistence reopens real options panel")
	check(controller.error_label.visible and not controller.persistence_error().is_empty(), "failed persistence remains visible")
	check(controller.options_panel.draft_settings() == draft, "retry preserves all six unpersisted settings")
	check(controller.options_panel.committed_settings().music_level == 0, "retry retains opening music permission")
	controller.options_panel._handle_left_down(Vector2(30, 230))
	controller.options_panel._handle_left_up(Vector2(30, 230))
	check(previews == 0, "failed mute-to-enabled draft cannot grant track-preview permission")
	store.fail = false
	controller.options_panel._accept()
	check(not controller.is_open() and store.settings == draft, "retry success persists and closes")
	controller.open(self, "title", "Game", null, date, date)
	controller.options_panel.command_requested.emit("hotkeys")
	var attempted: Array = store.bindings.duplicate()
	attempted[21] = 0x42
	controller.hotkeys_panel.set_view_model({"edition": "Game", "bindings": attempted})
	store.fail = true
	controller.hotkeys_panel._accept()
	check(controller.hotkeys_panel.is_open() and controller.error_label.visible, "failed hotkey write reopens actual child with visible error")
	controller.hotkeys_panel._cancel()
	controller.options_panel.command_requested.emit("hotkeys")
	check(controller.hotkeys_panel.draft_bindings() == store.bindings, "child cancellation discards unsuccessful write draft")
	controller.cancel()
	store.corrupt = true
	controller.open(self, "title", "Game", null, date, date)
	check(not controller.options_panel.is_model_valid() and controller.error_label.visible, "corrupt settings never silently become defaults")
	controller.options_panel._cancel()
	check(not controller.is_open(), "unavailable real model still has cancel exit")
	controller.queue_free()
	await process_frame
	print("Source options retry checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
