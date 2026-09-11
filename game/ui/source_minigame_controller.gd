extends Control

## Owner-guarded bridge for the source S31/S32/S33 presenter.
##
## Core owns the encounter, RNG and reward.  This controller only forwards
## pointer/tick requests to the core and emits `finish_minigame` after the
## presenter's result hold.  Generation checks make callbacks from an old
## owner harmless after a load, turn change or cancellation.

signal finished
signal action_requested(method: String, args: Array)

const PanelScript = preload("res://game/ui/source_minigame_panel.gd")
const REFERENCE_SIZE := Vector2(640.0, 480.0)

var panel_factory: Callable
var model_factory: Callable
var panel: Control
var visual_accessor: Variant = null

var _owner: Object = null
var _worker: Variant = null
var _generation := 0
var _display_id := 0
var _blocked := true
var _pending := false
var _action_pending := false
var _closing := false
var _kind := ""
var _encounter_id := 0
var _tick_elapsed_ms := 0.0
var _scale_factor := 1.0


func _init() -> void:
	name = "SourceMinigameController"
	size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func set_visuals(accessor: Variant) -> void:
	visual_accessor = accessor.duplicate(true) if accessor is Dictionary else accessor
	if is_instance_valid(panel) and panel.has_method("set_visuals"):
		panel.call("set_visuals", visual_accessor)


func set_visual_accessor(accessor: Variant) -> void:
	set_visuals(accessor)


func set_scale_factor(value: float) -> bool:
	if not is_finite(value) or value not in [1.0, 2.0]:
		return false
	_scale_factor = value
	if is_instance_valid(panel) and panel.has_method("set_scale_factor"):
		return bool(panel.call("set_scale_factor", value))
	return true


func scale_factor() -> float:
	return _scale_factor


func is_open() -> bool:
	return _pending and _owner != null


func pending() -> bool:
	return is_open()


func current_panel() -> Control:
	return panel


func current_model() -> Dictionary:
	if is_instance_valid(panel) and panel.has_method("snapshot"):
		return panel.call("snapshot")
	return {}


## Reconcile against the live owner.  `blocked` delays showing a new panel but
## never starts its intro/game timers while another modal owns the screen.
func sync(owner: Object, blocked: bool) -> void:
	if owner != _owner:
		cancel()
		_owner = owner
	if owner == null:
		return
	_blocked = blocked
	if not _owner_is_waiting(owner):
		if _pending:
			cancel()
		return
	var live_id := int(_minigame_snapshot(owner).get("encounter_id",0))
	if is_instance_valid(panel) and live_id != _encounter_id:
		cancel()
		_owner = owner
		_blocked = blocked
	_pending = true
	if not is_instance_valid(panel):
		_open_for_owner(owner)
	if not blocked:
		show()
		if is_instance_valid(panel):
			panel.show()
	else:
		# Keep the logical encounter pending, while the panel and its timers stay
		# stopped until the host removes the modal block.
		hide()
		if is_instance_valid(panel):
			panel.hide()


func cancel() -> void:
	_generation += 1
	_pending = false
	_action_pending = false
	_closing = false
	_blocked = true
	_worker = null
	_kind = ""
	_encounter_id = 0
	_tick_elapsed_ms = 0.0
	_clear_panel()
	_owner = null
	hide()


func _open_for_owner(owner: Object) -> void:
	var snapshot := _minigame_snapshot(owner)
	_kind = _canonical_kind(str(snapshot.get("kind", snapshot.get("minigame_kind", ""))))
	_encounter_id = int(snapshot.get("encounter_id", snapshot.get("id", 0)))
	_tick_elapsed_ms = 0.0
	if _kind.is_empty():
		_pending = false
		return
	_worker = _make_worker(_kind)
	var instance: Variant = panel_factory.call() if panel_factory.is_valid() else PanelScript.new()
	if not instance is Control:
		_pending = false
		_worker = null
		return
	panel = instance
	_display_id += 1
	var generation := _generation
	var display_id := _display_id
	panel.set_meta("source_minigame_generation", generation)
	panel.set_meta("source_minigame_display_id", display_id)
	if panel.has_signal("pointer_requested"):
		panel.connect("pointer_requested", _on_pointer.bind(generation, display_id))
	if panel.has_signal("finish_requested"):
		panel.connect("finish_requested", _on_finish_requested.bind(generation, display_id))
	add_child(panel)
	panel.set_process(false)
	panel.position = Vector2.ZERO
	if panel.has_method("set_visuals"):
		panel.call("set_visuals", visual_accessor)
	if panel.has_method("set_scale_factor"):
		panel.call("set_scale_factor", _scale_factor)
	var input_data: Variant = snapshot.get("input_data", snapshot.get("input", snapshot.get("model", {})))
	var seed := int(snapshot.get("seed", snapshot.get("rng_seed", 0)))
	if _worker != null and _worker is Object and _worker.has_method("configure"):
		_worker.call("configure", _kind, seed, input_data)
	if panel.has_method("configure"):
		panel.call("configure", _kind, seed, input_data)
	if panel.has_method("set_view_model"):
		panel.call("set_view_model", snapshot)
	if bool(snapshot.get("shortcut", false)):
		panel.call("show_result", snapshot)


func _process(delta: float) -> void:
	var paused := is_instance_valid(panel) and panel.has_method("is_paused") and bool(panel.call("is_paused"))
	if not _pending or _blocked or _closing or _owner == null or not is_instance_valid(panel) or paused:
		return
	if not panel.has_method("is_playing") or not bool(panel.call("is_playing")):
		panel.call("tick", delta)
		return
	_tick_elapsed_ms += maxf(0.0, delta) * 1000.0
	var live_snapshot := _minigame_snapshot(_owner)
	var model: Variant = live_snapshot.get("model", {}) if live_snapshot is Dictionary else {}
	var tick_ms := int(model.get("tick_ms", 100) if model is Dictionary else 100)
	if tick_ms <= 0:
		tick_ms = 100
	if _tick_elapsed_ms < tick_ms:
		return
	# Rendering may be slower or faster than the source callback. Preserve every
	# active tick; focus/blocked frames never enter this accumulator.
	while _tick_elapsed_ms + 0.00001 >= tick_ms:
		_tick_elapsed_ms -= tick_ms
		if _worker != null and _worker is Object and _worker.has_method("tick"):
			_worker.call("tick")
		var response: Variant = _call_owner("minigame_tick", [_encounter_id])
		live_snapshot = _minigame_snapshot(_owner)
		_apply_core_snapshot(live_snapshot if not live_snapshot.is_empty() else response)
		if _core_finished(live_snapshot):
			panel.call("show_result", _snapshot_for_panel(live_snapshot))
			_tick_elapsed_ms = 0.0
			break


func _on_pointer(position: Vector2, pressed: bool, generation: int, display_id: int) -> void:
	if generation != _generation or display_id != _display_id or _blocked or _closing or not _pending or _owner == null:
		return
	if not Rect2(Vector2.ZERO, REFERENCE_SIZE).has_point(position):
		return
	if _worker != null and _worker is Object and _worker.has_method("pointer"):
		_worker.call("pointer", position, pressed)
	var response: Variant = _call_owner("minigame_pointer", [_encounter_id, position, pressed])
	var live_snapshot := _minigame_snapshot(_owner)
	_apply_core_snapshot(live_snapshot if not live_snapshot.is_empty() else response)
	if _core_finished(live_snapshot) and is_instance_valid(panel) and panel.has_method("show_result"):
		panel.call("show_result", _snapshot_for_panel(live_snapshot))


func _on_finish_requested(generation: int, display_id: int) -> void:
	if generation != _generation or display_id != _display_id or _closing or _action_pending or not _pending or _owner == null:
		return
	# MainUI/core remains the sole authority for validating completion and
	# consuming the reward; no reward is attached to this intent.
	_action_pending = true
	action_requested.emit("finish_minigame", [_encounter_id])


func apply_action_result(result: Dictionary) -> void:
	_action_pending = false
	if not bool(result.get("ok", false)) and is_instance_valid(panel):
		if panel.has_method("set_view_model"):
			panel.call("set_view_model", _minigame_snapshot(_owner))
		return
	# A successful core action normally changes phase before the next sync.  Do
	# not close optimistically here, because an owner replacement may race it.


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_instance_valid(panel) and panel.has_method("set_paused"):
			panel.call("set_paused", true)
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if is_instance_valid(panel) and panel.has_method("set_paused"):
			panel.call("set_paused", false)


func _clear_panel() -> void:
	if is_instance_valid(panel):
		if panel.has_method("cancel"):
			panel.call("cancel")
		panel.queue_free()
	panel = null


func _owner_is_waiting(owner: Object) -> bool:
	if owner.has_method("minigame_snapshot"):
		var value: Variant = owner.call("minigame_snapshot")
		return value is Dictionary and not value.is_empty() and str(value.get("phase", "await_minigame")) in ["await_minigame", ""]
	if owner.has_method("get_snapshot"):
		var snapshot: Variant = owner.call("get_snapshot")
		if snapshot is Dictionary:
			return str(snapshot.get("phase", "")) == "await_minigame" or (owner.get("state") != null and owner.state.get("phase", "") == "await_minigame")
	return false


func _minigame_snapshot(owner: Object) -> Dictionary:
	if owner == null:
		return {}
	if owner.has_method("minigame_snapshot"):
		var value: Variant = owner.call("minigame_snapshot")
		return value.duplicate(true) if value is Dictionary else {}
	return {}


func _call_owner(method: String, args: Array) -> Variant:
	if _owner == null or not _owner.has_method(method):
		return {}
	return _owner.callv(method, args)


func _apply_core_snapshot(value: Variant) -> void:
	if value is Dictionary and is_instance_valid(panel) and panel.has_method("set_view_model"):
		panel.call("set_view_model", value)


func _snapshot_for_panel(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else _minigame_snapshot(_owner)


func _core_finished(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var model: Variant = value.get("model", value)
	return bool(value.get("finished", false)) or (model is Dictionary and bool(model.get("finished", model.get("done", false))))


func _make_worker(kind: String) -> Variant:
	if not model_factory.is_valid():
		return null
	var result: Variant = model_factory.call(kind)
	return result


func _canonical_kind(value: String) -> String:
	var normalized := value.to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	if normalized in ["balloon", "balloon_game", "s31", "31"]:
		return "balloon"
	if normalized in ["penguin", "penguin_game", "s32", "32"]:
		return "penguin"
	if normalized in ["catching", "catch", "catch_game", "s33", "33"]:
		return "catching"
	return ""
