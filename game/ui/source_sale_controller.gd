extends Control

## Owns ephemeral picker/amount/confirmation views of a durable public session.
signal opened
signal closed
signal finished
signal action_requested(method: String, args: Array)
const AmountPad = preload("res://game/ui/source_amount_pad.gd")
const Confirmation = preload("res://game/ui/source_sale_confirmation.gd")
const Sale = preload("res://game/core/source_sale_flow.gd")
const Hotkeys = preload("res://game/platform/system_hotkeys.gd")
var panel: Control
var amount_pad: Control
var confirmation: Control
var _owner: Object
var _session_id := 0
var _generation := 0
var _child_generation := 0
var _blocked := true
var _action_pending := false
var _last_method := ""
var _visuals: Variant
var _bindings: Array = Hotkeys.DEFAULTS.duplicate()
var _view := "board"
var _category := "stock"
var _selected_item := {}
var _selected_offer := {}
var _quantity := 1
var _amount_stage := ""
var _feedback := ""
var _focus_epoch := 0

func _init() -> void:
	name = "SourceSaleController"
	size = Vector2(640,480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

func set_visuals(accessor: Variant) -> void:
	_visuals = accessor
	if is_instance_valid(panel): panel.set_visual_accessor(accessor)

func set_bindings(bindings: Array) -> void:
	_bindings = bindings.duplicate()

func is_open() -> bool:
	return _owner != null and _session_id > 0

func sync(owner: Object, blocked: bool) -> void:
	if owner != _owner:
		cancel()
		_owner = owner
	var model: Dictionary = owner.sale_snapshot() if owner != null and owner.has_method("sale_snapshot") else {}
	if model.is_empty():
		cancel()
		return
	if _session_id != int(model.session_id):
		cancel()
		_owner = owner
		_session_id = int(model.session_id)
		_view = "board"
		_category = "stock"
		_feedback = ""
		opened.emit()
	if blocked != _blocked:
		_focus_epoch += 1
	_blocked = blocked
	if not is_instance_valid(panel):
		var script: Script = load("res://game/ui/source_sale_panel.gd")
		if script == null: return
		panel = script.new()
		var generation := _generation
		var instance := panel
		panel.action_requested.connect(func(action: String, params: Dictionary) -> void:
			if _callback_current(generation,instance): _on_action(action,params))
		panel.cancelled.connect(func() -> void:
			if _callback_current(generation,instance): close_current())
		add_child(panel)
		panel.set_visual_accessor(_visuals)
	_render(model)
	visible = not blocked
	panel.visible = not blocked

func _callback_current(generation: int, instance: Control) -> bool:
	if generation != _generation or instance != panel or _blocked or _action_pending or _owner == null: return false
	var model: Dictionary = _owner.sale_snapshot()
	return not model.is_empty() and int(model.session_id) == _session_id

func _render(model: Dictionary = {}) -> void:
	if not is_instance_valid(panel) or _owner == null: return
	if model.is_empty(): model = _owner.sale_snapshot()
	if model.is_empty(): return
	model = model.duplicate(true)
	model["view"] = _view
	model["category"] = _category
	model["selected_offer"] = _selected_offer.duplicate(true)
	model["selected_item"] = _selected_item.duplicate(true)
	model["feedback"] = _feedback
	model["focus_epoch"] = _focus_epoch
	model["reference_y"] = 42
	model["reference_message"] = "請輸入欲賣出的張數" if _amount_stage == "quantity" else "請輸入欲拍賣的價格\n\n（市價：%d元）" % int(_selected_item.get("reference_value",0))
	model["maximum_asking"] = Sale.maximum_asking(int(_selected_item.get("reference_value",0)))
	if panel.view_model() != model: panel.configure(model)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE if is_instance_valid(amount_pad) or is_instance_valid(confirmation) else Control.MOUSE_FILTER_STOP
	panel.set_process_input(not is_instance_valid(amount_pad) and not is_instance_valid(confirmation))

func _on_action(action: String, params: Dictionary) -> void:
	if is_instance_valid(amount_pad) or is_instance_valid(confirmation): return
	if action == "category_selected":
		if params.get("category") not in Sale.CATEGORIES: return
		_category = str(params.category)
		_view = "picker"
		_feedback = ""
	elif action == "back":
		_view = "board"
		_selected_offer = {}
		_selected_item = {}
	elif action == "item_selected":
		var model: Dictionary = _owner.sale_snapshot()
		if str(params.get("category", "")) != _category: return
		_selected_item = {}
		for item in model.holdings.get(_category, []):
			if int(item.source_id) == int(params.get("source_id", -1)) and (_category != "card" or int(item.held_index) == int(params.get("held_index", -1))):
				_selected_item = item.duplicate(true)
				break
		if _selected_item.is_empty(): return
		_quantity = 1
		_show_amount("quantity" if _category == "stock" else "asking")
		return
	elif action == "offer_selected":
		_selected_offer = _find_offer(int(params.get("offer_id",0)), int(params.get("revision",0)))
		if _selected_offer.is_empty(): return
		_category = str(_selected_offer.category)
		_view = "detail"
		_feedback = ""
	elif action == "detail_primary":
		if _selected_offer.is_empty() or int(params.get("offer_id",0)) != int(_selected_offer.offer_id) or int(params.get("revision",0)) != int(_selected_offer.revision): return
		if int(_selected_offer.seller_id) == int(_owner.state.current_player):
			_request("sale_cancel_offer",[_offer_request()])
		else: _show_confirmation()
		return
	_render()

func _find_offer(offer_id: int, revision: int) -> Dictionary:
	var model: Dictionary = _owner.sale_snapshot()
	for player in model.get("players", []):
		for offer in player.offers:
			if int(offer.offer_id) == offer_id and int(offer.revision) == revision: return offer.duplicate(true)
	return {}

func _offer_request() -> Dictionary:
	return {"session_id": _session_id, "offer_id": int(_selected_offer.offer_id), "revision": int(_selected_offer.revision)}

func _show_amount(stage: String) -> void:
	_clear_children()
	_amount_stage = stage
	_view = "reference"
	amount_pad = AmountPad.new()
	amount_pad.name = "SourceSaleAmountPad"
	amount_pad.position = Vector2(256,144)
	var generation := _generation
	var child_generation := _child_generation
	var instance := amount_pad
	amount_pad.confirmed.connect(func(amount: int) -> void:
		if _child_current(generation,child_generation,instance): _amount_confirmed(amount))
	amount_pad.cancelled.connect(func() -> void:
		if _child_current(generation,child_generation,instance): _cancel_amount())
	add_child(amount_pad)
	var model: Dictionary = _owner.sale_snapshot()
	amount_pad.set_visuals(_visuals,str(model.edition))
	var maximum := int(_selected_item.quantity) if stage == "quantity" else Sale.maximum_asking(int(_selected_item.reference_value))
	amount_pad.configure("sale_" + stage,maximum,0)
	_render(model)

func _child_current(generation: int, child_generation: int, instance: Control) -> bool:
	return _callback_current(generation,panel) and child_generation == _child_generation and instance in [amount_pad,confirmation]

func _amount_confirmed(amount: int) -> void:
	if amount <= 0:
		_cancel_amount()
		return
	if _amount_stage == "quantity":
		_quantity = amount
		_selected_item.reference_value = Sale.reference_value(_owner,"stock",int(_selected_item.source_id),amount)
		_show_amount("asking")
		return
	var params := {"session_id": _session_id, "category": _category, "source_id": int(_selected_item.source_id), "quantity": _quantity, "asking": amount}
	_clear_children()
	_request("sale_create_offer",[params])

func _cancel_amount() -> void:
	_clear_children()
	_amount_stage = ""
	_view = "picker"
	_render()

func _show_confirmation() -> void:
	_clear_children()
	confirmation = Confirmation.new()
	var generation := _generation
	var child_generation := _child_generation
	var instance := confirmation
	confirmation.decided.connect(func(accepted: bool) -> void:
		if not _child_current(generation,child_generation,instance): return
		_clear_children()
		if accepted: _request("sale_accept_offer",[_offer_request()])
		else: _render())
	add_child(confirmation)
	confirmation.configure(_visuals,str(_owner.sale_snapshot().edition),_bindings)
	_render()

func _request(method: String, args: Array) -> void:
	if _owner == null or _blocked or _action_pending: return
	_action_pending = true
	_last_method = method
	action_requested.emit(method,args)

func apply_action_result(result: Dictionary) -> void:
	_action_pending = false
	if _owner == null: return
	var model: Dictionary = _owner.sale_snapshot()
	if model.is_empty():
		cancel()
		finished.emit()
		return
	_feedback = str(result.get("message", ""))
	if result.get("ok", false) and _last_method in ["sale_create_offer","sale_cancel_offer","sale_accept_offer"]:
		_view = "board"
		_selected_item = {}
		_selected_offer = {}
		_amount_stage = ""
	elif _last_method == "sale_create_offer": _view = "picker"
	_render(model)

func close_current() -> void:
	if _owner == null: return
	_clear_children()
	_request("close_sale",[_session_id])

func _clear_children() -> void:
	_child_generation += 1
	for child in [amount_pad,confirmation]:
		if is_instance_valid(child):
			child.hide()
			remove_child(child)
			child.queue_free()
	amount_pad = null
	confirmation = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_open():
		_focus_epoch += 1
		if is_instance_valid(confirmation): confirmation.reset_hover()
		_render()

func cancel() -> void:
	var was_open := is_open()
	_generation += 1
	_session_id = 0
	_owner = null
	_action_pending = false
	_blocked = true
	_clear_children()
	if is_instance_valid(panel):
		panel.hide()
		remove_child(panel)
		panel.queue_free()
	panel = null
	hide()
	if was_open: closed.emit()
