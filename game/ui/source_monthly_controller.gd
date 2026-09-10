extends Control

## Action-scoped reports are acknowledged without calling the financial core.
## Sync never scans a loaded save's historical log for reports.
signal finished
const Events = preload("res://game/ui/movement_presentation.gd")

var panel_factory: Callable
var report_panel: Control
var _visuals: Variant
var _owner: Object
var _queue: Array = []
var _generation := 0
var _display_id := 0
var _closing := false
var _blocked := true
var _last_transition := ""

func _init() -> void:
	name = "SourceMonthlyController"
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

func set_visuals(accessor: Variant) -> void:
	if typeof(accessor) == typeof(_visuals) and accessor == _visuals: return
	_visuals = accessor
	if is_instance_valid(report_panel): report_panel.set_visuals(accessor)

func is_open() -> bool:
	return not _queue.is_empty()

func pending_count() -> int:
	return _queue.size()

func current_report() -> Dictionary:
	return {} if _queue.is_empty() else _queue[0].duplicate(true)

func capture_transition(owner: Object, before: Dictionary, after: Dictionary) -> void:
	if owner != _owner:
		cancel()
		_owner = owner
	if owner == null: return
	# Only the latest action identity is retained. A time rewind followed by a
	# new settlement can show its report again; duplicate delivery cannot.
	var identity := JSON.stringify([before.get("event_log", []), after.get("event_log", [])]).sha256_text()
	if identity == _last_transition: return
	_last_transition = identity
	var delta: Dictionary = Events._event_delta(before.get("event_log", []), after.get("event_log", []))
	if not bool(delta.get("ok", false)): return
	for event in delta.get("events", []):
		if not event is Dictionary or event.get("type", "") != "monthly_statement": continue
		var report: Variant = event.get("report", null)
		if report is Dictionary and report.get("kind", "") in ["dividend", "interest"]:
			_queue.append(report.duplicate(true))

func sync(owner: Object, blocked: bool) -> void:
	if owner != _owner:
		cancel()
		_owner = owner
	_blocked = blocked
	if not blocked and not _closing: _show_next()

func cancel() -> void:
	_generation += 1
	_queue.clear()
	_owner = null
	_last_transition = ""
	_closing = false
	_blocked = true
	_clear_panel()
	hide()

func _clear_panel() -> void:
	if is_instance_valid(report_panel):
		report_panel.hide()
		report_panel.queue_free()
	report_panel = null

func _show_next() -> void:
	if _blocked or _closing or _queue.is_empty() or is_instance_valid(report_panel): return
	if panel_factory.is_valid():
		report_panel = panel_factory.call()
	else:
		var script: Script = load("res://game/ui/source_monthly_panel.gd")
		if script == null: return
		report_panel = script.new()
	_display_id += 1
	var generation := _generation
	var display_id := _display_id
	report_panel.continued.connect(func() -> void: _on_continued(generation, display_id))
	add_child(report_panel)
	report_panel.position = Vector2.ZERO
	# The real presenter starts its source timer when it receives the model.
	# Attach first so that timer has a scene-tree lifetime.
	report_panel.set_visuals(_visuals)
	report_panel.set_view_model(_queue[0])
	show()

func _on_continued(generation: int, display_id: int) -> void:
	if generation != _generation or display_id != _display_id or _closing or _queue.is_empty(): return
	_closing = true
	_queue.pop_front()
	_clear_panel()
	call_deferred("_after_close", generation)

func _after_close(generation: int) -> void:
	if generation != _generation: return
	_closing = false
	if _queue.is_empty():
		hide()
		finished.emit()
	else:
		_show_next()
