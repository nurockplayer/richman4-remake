extends Control

## A short-lived view of a persistent core visit. Rebuilding or replacing this
## controller never changes offers, inventory, RNG or accounting by itself.
signal opened
signal closed
signal finished
signal action_requested(method: String, args: Array)

var panel: Control
var _owner: Object
var _visit_id := 0
var _generation := 0
var _blocked := true
var _action_pending := false
var _visuals: Variant
var _gift_elapsed := 0.0
var _mode := "cards"
var _feedback := ""

func _init() -> void:
	name = "SourceShopController"
	size = Vector2(640,480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

func set_visuals(accessor: Variant) -> void:
	_visuals = accessor
	if is_instance_valid(panel): panel.set_visual_accessor(accessor)

func is_open() -> bool:
	return _owner != null and _visit_id > 0

func sync(owner: Object, blocked: bool) -> void:
	if owner != _owner:
		cancel()
		_owner = owner
	var model: Dictionary = owner.shop_visit_snapshot() if owner != null and owner.has_method("shop_visit_snapshot") else {}
	if model.is_empty() or not bool(model.get("human", false)):
		cancel()
		return
	if _visit_id != int(model.visit_id):
		cancel()
		_owner = owner
		_visit_id = int(model.visit_id)
		_mode = "cards"
		_gift_elapsed = 0.0
		_feedback = ""
		opened.emit()
	_blocked = blocked
	if not is_instance_valid(panel):
		var script: Script = load("res://game/ui/source_shop_panel.gd")
		if script == null: return
		panel = script.new()
		var generation := _generation
		var instance := panel
		panel.action_requested.connect(func(action: String, params: Dictionary) -> void:
			if _callback_current(generation,instance): _request("choose_action",[action,params]))
		panel.cancelled.connect(func() -> void:
			if _callback_current(generation,instance): close_current())
		add_child(panel)
		panel.set_visual_accessor(_visuals)
	_render(model)
	visible = not blocked
	panel.visible = not blocked

func _callback_current(generation: int, instance: Control) -> bool:
	if generation != _generation or instance != panel or _blocked or _action_pending or _owner == null: return false
	var model: Dictionary = _owner.shop_visit_snapshot()
	return not model.is_empty() and int(model.visit_id) == _visit_id

func _render(model: Dictionary) -> void:
	if not is_instance_valid(panel): return
	var previous: Dictionary = panel.view_model()
	if previous.get("mode", "") in ["cards", "tools"]: _mode = str(previous.mode)
	model = model.duplicate(true)
	model.mode = _mode
	model["feedback"] = _feedback
	# Repainting an unchanged owner snapshot must preserve a held tab/EXIT latch.
	if model != previous: panel.configure(model)

func _request(method: String, args: Array) -> void:
	if _owner == null or _blocked or _action_pending: return
	_action_pending = true
	action_requested.emit(method,args)

func apply_action_result(result: Dictionary) -> void:
	_action_pending = false
	if _owner == null: return
	var model: Dictionary = _owner.shop_visit_snapshot()
	if model.is_empty():
		cancel()
		finished.emit()
		return
	_feedback = str(result.get("message", ""))
	_render(model)

func close_current() -> void:
	_request("leave_shop",[_visit_id])

func _process(delta: float) -> void:
	if _owner == null or _blocked or _action_pending or not is_instance_valid(panel) or not panel.visible: return
	var model: Dictionary = _owner.shop_visit_snapshot()
	if model.is_empty() or int(model.visit_id) != _visit_id:
		cancel()
		return
	if bool(model.get("gift_pending",false)):
		_gift_elapsed += maxf(0.0,delta)
		if _gift_elapsed >= 1.5: _request("acknowledge_shop_gift",[_visit_id])

func cancel() -> void:
	var was_open := is_open()
	_generation += 1
	_visit_id = 0
	_owner = null
	_action_pending = false
	_blocked = true
	_gift_elapsed = 0.0
	if is_instance_valid(panel):
		panel.hide()
		remove_child(panel)
		panel.queue_free()
	panel = null
	hide()
	if was_open: closed.emit()
