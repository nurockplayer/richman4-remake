extends Control
class_name RichmanSourceOptionsController

## Host for the source-shaped options presenter and its independent children.
## This node owns orchestration and persistence; the presenters own drafts and
## never perform settings, hotkey, date, or owner I/O themselves.

const SETTINGS_SCRIPT := preload("res://game/platform/system_settings.gd")
const HOTKEYS_SCRIPT := preload("res://game/platform/system_hotkeys.gd")

signal finished
signal settings_committed(settings: Dictionary)
signal date_committed(date: Dictionary)
signal hotkeys_committed(bindings: Array)
signal preview_requested(track: int)
signal command_requested(command: String)

## These paths are intentionally public. Tests and preview hosts can point them
## at an owned temporary directory without changing platform defaults.
var settings_path: String = SETTINGS_SCRIPT.DEFAULT_PATH
var hotkeys_path: String = HOTKEYS_SCRIPT.DEFAULT_PATH

## Stores may be the platform RefCounted objects, a Callable, or a small fake
## exposing read_settings/write_settings (read/write for convenience).
var settings_store: Variant = null
var hotkeys_store: Variant = null

## Factories are public injection seams for hermetic controller tests.
var options_panel_factory: Callable
var date_panel_factory: Callable
var hotkeys_panel_factory: Callable

var options_panel: Control
var date_panel: Control
var hotkeys_panel: Control
var status_label: Label

var _host_status_text := ""
var host_status_text: String:
	get:
		return _host_status_text
	set(value):
		_host_status_text = value
		_show_status(value)

var _owner: Object
var _mode := ""
var _edition := ""
var _visuals: Variant = null
var _runtime_date: Dictionary = {}
var _system_date: Dictionary = {}
var _settings: Dictionary = {}
var _settings_draft: Dictionary = {}
var _hotkeys: Array = []
var _hotkeys_draft: Array = []
var _settings_result: Dictionary = {}
var _hotkeys_result: Dictionary = {}
var _generation := 0
var _open := false
var error_label: Label
var _error_message := ""


func _init() -> void:
	name = "SourceOptionsController"
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func _ready() -> void:
	hide()


## Open the source options session for one owner. The captured dates are used
## by the date child; this controller never reads the system clock.
func open(owner: Object, mode: String, edition: String, visuals: Variant, runtime_date: Dictionary, system_date: Dictionary, runtime_view: Variant = null) -> bool:
	if owner == null or mode not in ["title", "game"] or edition not in ["Game", "MultiverseJourney"]:
		return false
	if _open:
		if owner == _owner:
			return false
		cancel()
	_generation += 1
	_open = true
	_owner = owner
	_mode = mode
	_edition = edition
	_visuals = visuals
	_runtime_date = runtime_date.duplicate(true)
	_system_date = system_date.duplicate(true)
	_settings_result = _read_settings()
	_hotkeys_result = _read_hotkeys()
	_settings = _valid_settings(_settings_result)
	# Overlay only a validated runtime presentation choice after a successful
	# read. Read failures stay visible and never acquire fabricated settings.
	if not _settings.is_empty() and typeof(runtime_view) == TYPE_INT and runtime_view >= 0 and runtime_view <= 2:
		_settings["view"] = runtime_view
	_settings_draft = _settings.duplicate(true)
	_hotkeys = _valid_hotkeys(_hotkeys_result)
	_hotkeys_draft = _hotkeys.duplicate(true)
	var generation := _generation
	var panel := _new_panel(options_panel_factory, "res://game/ui/source_options_panel.gd")
	if panel == null:
		_open = false
		_owner = null
		return false
	options_panel = panel
	options_panel.name = "SourceOptionsPanel"
	options_panel.set("position", Vector2.ZERO)
	add_child(options_panel)
	_connect(options_panel, "accepted", Callable(self, "_on_options_accepted").bind(generation, options_panel))
	_connect(options_panel, "cancelled", Callable(self, "_on_options_cancelled").bind(generation, options_panel))
	_connect(options_panel, "command_requested", Callable(self, "_on_options_command").bind(generation, options_panel))
	_connect(options_panel, "preview_requested", Callable(self, "_on_preview").bind(generation, options_panel))
	if options_panel.has_method("set_visual_accessor"):
		options_panel.call("set_visual_accessor", visuals)
	elif options_panel.has_method("set_visuals"):
		options_panel.call("set_visuals", visuals)
	options_panel.call("set_view_model", _options_model(_settings))
	_show_error(_read_error_message(_settings_result, _hotkeys_result))
	_show_status(_host_status_text)
	show()
	return true


func is_open() -> bool:
	return _open and _owner != null and is_instance_valid(options_panel)


func current_owner() -> Object:
	return _owner


func current_mode() -> String:
	return _mode


func current_edition() -> String:
	return _edition


func settings() -> Dictionary:
	return _settings_draft.duplicate(true)


func hotkeys() -> Array:
	return _hotkeys_draft.duplicate(true)


func settings_load_result() -> Dictionary:
	return _settings_result.duplicate(true)


func hotkeys_load_result() -> Dictionary:
	return _hotkeys_result.duplicate(true)


func persistence_error() -> String:
	return _error_message


func set_host_status_text(value: String) -> void:
	host_status_text = value


func sync(owner: Object) -> void:
	if is_open() and owner != _owner:
		cancel()


func set_current_track(track: int) -> void:
	if is_instance_valid(options_panel) and options_panel.has_method("set_current_track"):
		options_panel.call("set_current_track", track)


## Resume the options parent after MainUI's existing help controller finishes.
func resume_parent() -> void:
	if is_instance_valid(options_panel) and options_panel.has_method("suspend_input"):
		options_panel.call("suspend_input", false)


func cancel() -> bool:
	if not _open:
		return false
	_generation += 1
	_clear_child(date_panel)
	_clear_child(hotkeys_panel)
	_clear_child(options_panel)
	date_panel = null
	hotkeys_panel = null
	options_panel = null
	_open = false
	_owner = null
	_mode = ""
	_edition = ""
	_settings = {}
	_settings_draft = {}
	_hotkeys = []
	_hotkeys_draft = []
	_clear_error()
	_show_status(_host_status_text)
	hide()
	finished.emit()
	return true


func close() -> bool:
	return cancel()


func _new_panel(factory: Callable, script_path: String) -> Control:
	var panel: Variant = factory.call() if factory.is_valid() else null
	if panel == null:
		var script: Script = load(script_path)
		if script == null:
			return null
		panel = script.new()
	return panel as Control


func _connect(panel: Control, signal_name: String, callback: Callable) -> void:
	if panel != null and panel.has_signal(signal_name):
		panel.connect(signal_name, callback)


func _options_model(settings: Dictionary) -> Dictionary:
	return {
		"edition": _edition,
		"mode": _mode,
		"settings": settings.duplicate(true),
	}


func _date_model() -> Dictionary:
	return {
		"edition": _edition,
		"date": _runtime_date.duplicate(true),
		"system_date": _system_date.duplicate(true),
	}


func _hotkeys_model(bindings: Array) -> Dictionary:
	return {"edition": _edition, "bindings": bindings.duplicate(true)}


func _on_options_accepted(settings: Dictionary, generation: int, panel: Control) -> void:
	if not _current(generation, options_panel, panel):
		return
	_settings_draft = settings.duplicate(true)
	var result := _write_settings(_settings_draft)
	if not bool(result.get("ok", false)):
		# The source panel has already closed on accepted. Rebuild its visible
		# session with the same draft so retry and outer cancel remain available.
		_reopen_options(generation)
		_show_error(_error_text("設定", result))
		return
	_settings = _settings_draft.duplicate(true)
	_clear_error()
	settings_committed.emit(_settings.duplicate(true))
	_close_session(generation)


func _on_options_cancelled(generation: int, panel: Control) -> void:
	if not _current(generation, options_panel, panel):
		return
	_close_session(generation)


func _on_options_command(command: String, generation: int, panel: Control) -> void:
	if not _current(generation, options_panel, panel):
		return
	if command == "date":
		_open_date(generation)
	elif command == "hotkeys":
		_open_hotkeys(generation)
	elif command == "help":
		if panel.has_method("suspend_input"):
			panel.call("suspend_input", true)
		command_requested.emit(command)
	else:
		if panel.has_method("suspend_input"):
			panel.call("suspend_input", true)
		command_requested.emit(command)


func _on_preview(track: int, generation: int, panel: Control) -> void:
	if _current(generation, options_panel, panel):
		preview_requested.emit(track)


func _open_date(generation: int) -> void:
	if not _open or generation != _generation or is_instance_valid(date_panel) or is_instance_valid(hotkeys_panel):
		return
	if is_instance_valid(options_panel) and options_panel.has_method("suspend_input"):
		options_panel.call("suspend_input", true)
	var panel := _new_panel(date_panel_factory, "res://game/ui/source_date_panel.gd")
	if panel == null:
		resume_parent()
		return
	date_panel = panel
	panel.name = "SourceDatePanel"
	add_child(panel)
	_connect(panel, "accepted", Callable(self, "_on_date_accepted").bind(generation, panel))
	_connect(panel, "cancelled", Callable(self, "_on_date_cancelled").bind(generation, panel))
	_set_visuals(panel)
	panel.call("set_view_model", _date_model())


func _on_date_accepted(date: Dictionary, generation: int, panel: Control) -> void:
	if not _current(generation, date_panel, panel):
		return
	_runtime_date = date.duplicate(true)
	date_committed.emit(_runtime_date.duplicate(true))
	_clear_child(panel)
	date_panel = null
	resume_parent()


func _on_date_cancelled(generation: int, panel: Control) -> void:
	if not _current(generation, date_panel, panel):
		return
	_clear_child(panel)
	date_panel = null
	resume_parent()


func _open_hotkeys(generation: int) -> void:
	if not _open or generation != _generation or is_instance_valid(date_panel) or is_instance_valid(hotkeys_panel):
		return
	if is_instance_valid(options_panel) and options_panel.has_method("suspend_input"):
		options_panel.call("suspend_input", true)
	var panel := _new_panel(hotkeys_panel_factory, "res://game/ui/source_hotkeys_panel.gd")
	if panel == null:
		resume_parent()
		return
	hotkeys_panel = panel
	panel.name = "SourceHotkeysPanel"
	add_child(panel)
	_connect(panel, "accepted", Callable(self, "_on_hotkeys_accepted").bind(generation, panel))
	_connect(panel, "cancelled", Callable(self, "_on_hotkeys_cancelled").bind(generation, panel))
	_set_visuals(panel)
	panel.call("set_view_model", _hotkeys_model(_hotkeys_draft))


func _on_hotkeys_accepted(bindings: Array, generation: int, panel: Control) -> void:
	if not _current(generation, hotkeys_panel, panel):
		return
	_hotkeys_draft = bindings.duplicate(true)
	var result := _write_hotkeys(_hotkeys_draft)
	if not bool(result.get("ok", false)):
		_reopen_hotkeys(generation)
		_show_error(_error_text("熱鍵", result))
		return
	_hotkeys = _hotkeys_draft.duplicate(true)
	_clear_error()
	hotkeys_committed.emit(_hotkeys.duplicate(true))
	_clear_child(panel)
	hotkeys_panel = null
	resume_parent()


func _on_hotkeys_cancelled(generation: int, panel: Control) -> void:
	if not _current(generation, hotkeys_panel, panel):
		return
	_hotkeys_draft = _hotkeys.duplicate(true)
	_clear_error()
	_clear_child(panel)
	hotkeys_panel = null
	resume_parent()


func _reopen_options(generation: int) -> void:
	if not _open or generation != _generation:
		return
	if is_instance_valid(options_panel):
		options_panel.call("set_view_model", _options_model(_settings))
		if options_panel.has_method("restore_draft"):
			options_panel.call("restore_draft", _settings_draft)
		_set_visuals(options_panel)
		options_panel.show()


func _reopen_hotkeys(generation: int) -> void:
	if not _open or generation != _generation:
		return
	if is_instance_valid(hotkeys_panel):
		hotkeys_panel.call("set_view_model", _hotkeys_model(_hotkeys_draft))
		_set_visuals(hotkeys_panel)
		hotkeys_panel.show()


func _set_visuals(panel: Control) -> void:
	if panel.has_method("set_visual_accessor"):
		panel.call("set_visual_accessor", _visuals)
	elif panel.has_method("set_visuals"):
		panel.call("set_visuals", _visuals)


func _close_session(generation: int) -> void:
	if not _open or generation != _generation:
		return
	_generation += 1
	_clear_child(date_panel)
	_clear_child(hotkeys_panel)
	_clear_child(options_panel)
	date_panel = null
	hotkeys_panel = null
	options_panel = null
	_open = false
	_owner = null
	_mode = ""
	_edition = ""
	_clear_error()
	_show_status(_host_status_text)
	hide()
	finished.emit()


func _clear_child(node: Control) -> void:
	if is_instance_valid(node):
		if node.get_parent() == self:
			remove_child(node)
		node.queue_free()


func _current(generation: int, expected: Control, actual: Control) -> bool:
	return _open and generation == _generation and is_instance_valid(expected) and expected == actual


func _read_settings() -> Dictionary:
	var store: Variant = settings_store
	if store == null:
		store = SETTINGS_SCRIPT.new()
	return _invoke_read(store, settings_path, "settings")


func _read_hotkeys() -> Dictionary:
	var store: Variant = hotkeys_store
	if store == null:
		store = HOTKEYS_SCRIPT.new()
	return _invoke_read(store, hotkeys_path, "bindings")


func _invoke_read(store: Variant, path: String, kind: String) -> Dictionary:
	var result: Variant = null
	if store is Callable:
		result = store.call(path)
	elif store is Dictionary and store.get("read") is Callable:
		result = store.get("read").call(path)
	elif store is Object:
		if store.has_method("read_" + kind):
			result = store.call("read_" + kind, path)
		elif store.has_method("read"):
			result = store.call("read", path)
	if result is Dictionary:
		return result.duplicate(true)
	return {"ok": false, "status": "unavailable", "error": "read_failed"}


func _write_settings(settings: Dictionary) -> Dictionary:
	var store: Variant = settings_store
	if store == null:
		store = SETTINGS_SCRIPT.new()
	return _invoke_write(store, settings_path, settings, "settings")


func _write_hotkeys(bindings: Array) -> Dictionary:
	var store: Variant = hotkeys_store
	if store == null:
		store = HOTKEYS_SCRIPT.new()
	return _invoke_write(store, hotkeys_path, bindings, "bindings")


func _invoke_write(store: Variant, path: String, value: Variant, kind: String) -> Dictionary:
	var result: Variant = null
	if store is Callable:
		result = store.call(path, value)
	elif store is Dictionary and store.get("write") is Callable:
		result = store.get("write").call(path, value)
	elif store is Object:
		if store.has_method("write_" + kind):
			result = store.call("write_" + kind, path, value)
		elif store.has_method("write"):
			result = store.call("write", path, value)
	if result is Dictionary:
		return result.duplicate(true)
	return {"ok": false, "status": "unavailable", "error": "write_failed"}


func _valid_settings(result: Dictionary) -> Dictionary:
	return result.get("settings", {}).duplicate(true) if bool(result.get("ok", false)) and result.get("settings") is Dictionary else {}


func _valid_hotkeys(result: Dictionary) -> Array:
	return result.get("bindings", []).duplicate(true) if bool(result.get("ok", false)) and result.get("bindings") is Array else []


func _read_error_message(settings_result: Dictionary, hotkeys_result: Dictionary) -> String:
	if not bool(settings_result.get("ok", false)):
		return _error_text("設定", settings_result)
	if not bool(hotkeys_result.get("ok", false)):
		return _error_text("熱鍵", hotkeys_result)
	return ""


func _error_text(kind: String, result: Dictionary) -> String:
	var reason := str(result.get("error", "unavailable"))
	return "%s資料無法讀寫（%s）；請重試或取消。" % [kind, reason]


func _show_error(message: String) -> void:
	_error_message = message
	if error_label == null or not is_instance_valid(error_label):
		error_label = Label.new()
		error_label.name = "SourceOptionsPersistenceError"
		error_label.add_theme_font_size_override("font_size", 14)
		error_label.add_theme_constant_override("outline_size", 4)
		error_label.add_theme_color_override("font_outline_color", Color.BLACK)
		error_label.position = Vector2(18, 12)
		error_label.size = Vector2(604, 34)
		error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		error_label.z_index = 100
		error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(error_label)
	error_label.text = message
	error_label.visible = not message.is_empty()


func _clear_error() -> void:
	_error_message = ""
	if error_label != null and is_instance_valid(error_label):
		error_label.text = ""
		error_label.hide()


func _show_status(message: String) -> void:
	if status_label == null or not is_instance_valid(status_label):
		status_label = Label.new()
		status_label.name = "SourceOptionsHostStatus"
		status_label.add_theme_font_size_override("font_size", 12)
		status_label.add_theme_constant_override("outline_size", 4)
		status_label.add_theme_color_override("font_outline_color", Color.BLACK)
		status_label.position = Vector2(12, 438)
		status_label.size = Vector2(616, 30)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_label.z_index = 100
		add_child(status_label)
	status_label.text = message
	status_label.visible = not message.is_empty() and _open
