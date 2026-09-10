extends Control
class_name RichmanSourceBankPanel

## Source ATM / bank presenter for S11–S13.
##
## The host gives this component a validated snapshot and receives only an
## explicit, confirmed action.  This script never references simulation,
## persistence, random state or an asset cache.

signal action_requested(action: String, amount: int)
signal closed

const AmountPadScript = preload("res://game/ui/source_amount_pad.gd")

const ATM_SIZE := Vector2(320.0, 338.0)
const BANK_SIZE := Vector2(640.0, 480.0)
const CALCULATOR_SIZE := Vector2(128.0, 192.0)
const ATM_BOARD_ORIGIN := Vector2(60.0, 71.0)

var _model: Dictionary = {}
var _visual_accessor: Variant = null
var _mode := "atm"
var _edition := "game"
var _model_valid := false
var _selected_action := ""
var _amount_text := ""
var _amount_pad: Node = null
var _feedback: Label
var _amount_bar: HSlider
var _amount_value: Label


func _init() -> void:
	name = "SourceBankPanel"
	custom_minimum_size = ATM_SIZE
	size = ATM_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


## Replace the displayed snapshot.  The caller's dictionary is copied deeply
## so selection, rendering and validation cannot mutate host state.
func set_view_model(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_mode = str(_model.get("entry_mode", "atm")).to_lower().strip_edges()
	_edition = str(_model.get("edition", "game")).to_lower().strip_edges()
	var edition_value: Variant = _model.get("edition", "game")
	_model_valid = _mode in ["atm", "loan"] and (not _model.has("edition") or typeof(edition_value) == TYPE_STRING)
	_selected_action = ""
	_amount_text = ""
	_close_amount_pad()
	_build_screen()


## Install a host-provided visual resolver.  Supported resolver shapes are a
## dictionary, Callable, or object exposing texture/get_texture/visual/resolve.
## Missing visuals keep the source-coordinate fallback surface visible.
func set_visuals(accessor: Variant) -> void:
	if accessor is Dictionary:
		_visual_accessor = accessor.duplicate(true)
	else:
		_visual_accessor = accessor
	if not _model.is_empty():
		_build_screen()


func view_model() -> Dictionary:
	return _model.duplicate(true)


func current_action() -> String:
	return _selected_action


func current_amount() -> int:
	if _amount_pad != null and is_instance_valid(_amount_pad):
		var parsed: Dictionary = _amount_pad.call("parsed_amount")
		return int(parsed.get("amount", 0)) if bool(parsed.get("ok", false)) else 0
	var parsed: Dictionary = AmountPadScript.parse_amount(_amount_text, _current_limit())
	return int(parsed.get("amount", 0)) if bool(parsed.get("ok", false)) else 0


func set_amount_text(value: String) -> void:
	if _amount_pad != null and is_instance_valid(_amount_pad):
		_amount_pad.call("set_amount_text", value)
		return
	_amount_text = value
	if _amount_bar != null:
		var parsed: Dictionary = AmountPadScript.parse_amount(_amount_text, _current_limit())
		_amount_bar.set_value_no_signal(float(parsed.get("amount", 0)) if bool(parsed.get("ok", false)) else 0.0)
	_refresh_amount_display()


func confirm_amount() -> bool:
	if _amount_pad != null and is_instance_valid(_amount_pad):
		return bool(_amount_pad.call("_submit"))
	return _confirm_current_amount()


func cancel_amount() -> void:
	if _amount_pad != null and is_instance_valid(_amount_pad):
		_amount_pad.call("cancel")
		return
	_selected_action = ""
	_amount_text = ""
	_refresh_amount_display()


func select_action(action: String) -> bool:
	return _select_action(action)


func _input(event: InputEvent) -> void:
	# ATM 按鍵由父 panel 處理；貸款／特殊融資的鍵盤焦點交給子計算器。
	if _mode != "atm" or _amount_pad != null or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if _handle_atm_key(key_event):
		get_viewport().set_input_as_handled()


func _handle_atm_key(event: InputEventKey) -> bool:
	if event.keycode == KEY_ESCAPE:
		if not _selected_action.is_empty():
			cancel_amount()
		else:
			_close_flow()
		return true
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_confirm_current_amount()
		return true
	if event.keycode == KEY_BACKSPACE or event.keycode == KEY_DELETE:
		_backspace_amount()
		return true
	if event.keycode == KEY_C:
		_clear_amount()
		return true
	var digit := _digit_from_key(event)
	if not digit.is_empty():
		_append_digit(digit)
		return true
	return false


func _digit_from_key(event: InputEventKey) -> String:
	if event.unicode >= 48 and event.unicode <= 57:
		return String.chr(event.unicode)
	var digits := {
		KEY_0: "0", KEY_1: "1", KEY_2: "2", KEY_3: "3", KEY_4: "4",
		KEY_5: "5", KEY_6: "6", KEY_7: "7", KEY_8: "8", KEY_9: "9",
	}
	return str(digits.get(event.keycode, ""))


func action_allowed(action: String) -> bool:
	return _is_action_allowed(_canonical_action(action))


func action_limit(action: String) -> int:
	return _limit_for(_canonical_action(action))


func _build_screen() -> void:
	_clear_children()
	var screen_size := ATM_SIZE if _mode == "atm" else BANK_SIZE
	custom_minimum_size = screen_size
	size = screen_size
	_amount_bar = null
	_amount_value = null
	_feedback = null
	_add_source_background(_visual_key(), screen_size)
	if not _model_valid:
		_feedback = _make_label("資料格式無法顯示", Rect2(24, 24, screen_size.x - 48, 34), 16, Color("#ffb3a4"))
		add_child(_feedback)
		return
	if _mode == "atm":
		_build_atm()
	else:
		_build_bank_scene()


func _build_atm() -> void:
	add_child(_make_label("提款機", Rect2(8, 6, 125, 22), 16, Color("#f4e7ae"), HORIZONTAL_ALIGNMENT_LEFT, "ATMTitle"))
	add_child(_make_label("現金 %s" % _display_value("cash"), Rect2(8, 88, 145, 20), 11, Color("#eff0bf"), HORIZONTAL_ALIGNMENT_LEFT, "ATMCash"))
	add_child(_make_label("存款 %s" % _display_value("deposit"), Rect2(8, 108, 145, 20), 11, Color("#eff0bf"), HORIZONTAL_ALIGNMENT_LEFT, "ATMDepositValue"))

	var withdraw := _make_source_button("提款", "ATMWithdraw", Rect2(57, 49, 80, 41))
	withdraw.pressed.connect(func() -> void: _select_action("withdraw"))
	add_child(withdraw)
	var deposit := _make_source_button("存款", "ATMDeposit", Rect2(139, 49, 80, 41))
	deposit.pressed.connect(func() -> void: _select_action("deposit"))
	add_child(deposit)
	var exit := _make_source_button("EXIT", "ATMExit", Rect2(221, 49, 43, 41))
	exit.pressed.connect(_close_flow)
	add_child(exit)

	_amount_bar = HSlider.new()
	_amount_bar.name = "ATMAmountBar"
	_amount_bar.position = Vector2(53, 137)
	_amount_bar.size = Vector2(215, 29)
	_amount_bar.custom_minimum_size = _amount_bar.size
	_amount_bar.min_value = 0.0
	_amount_bar.step = 1.0
	_amount_bar.focus_mode = Control.FOCUS_ALL
	_amount_bar.tooltip_text = "選擇金額"
	_amount_bar.add_theme_stylebox_override("slider", _style(Color("#294f4c"), Color("#bdc885"), 1))
	_amount_bar.add_theme_stylebox_override("grabber_area", _style(Color("#6e9e77"), Color("#edf0b3"), 1))
	_amount_bar.value_changed.connect(_on_amount_bar_changed)
	add_child(_amount_bar)
	_amount_value = _make_label("金額 —", Rect2(53, 168, 215, 22), 11, Color("#f4e7ae"), HORIZONTAL_ALIGNMENT_CENTER, "ATMAmountValue")
	add_child(_amount_value)

	for row_index in 3:
		var digits: Array = [["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"]][row_index]
		for column_index in 3:
			var digit: String = digits[column_index]
			var button := _make_source_button(digit, "ATMDigit" + digit, Rect2(Vector2(58 + column_index * 39, 211 + row_index * 19), Vector2(33, 17)))
			button.pressed.connect(func() -> void: _append_digit(digit))
			add_child(button)
	var clear := _make_source_button("C", "ATMClear", Rect2(58, 268, 33, 17))
	clear.pressed.connect(_clear_amount)
	add_child(clear)
	var zero := _make_source_button("0", "ATMDigit0", Rect2(97, 268, 33, 17))
	zero.pressed.connect(func() -> void: _append_digit("0"))
	add_child(zero)
	var backspace := _make_source_button("←", "ATMBackspace", Rect2(136, 268, 33, 17))
	backspace.pressed.connect(_backspace_amount)
	add_child(backspace)
	var max_button := _make_source_button("MAX", "ATMMax", Rect2(183, 233, 49, 25))
	max_button.pressed.connect(_fill_maximum)
	add_child(max_button)
	var enter := _make_source_button("ENTER", "ATMEnter", Rect2(175, 260, 57, 25))
	enter.pressed.connect(func() -> void: _confirm_current_amount())
	add_child(enter)

	_feedback = _make_label("請先選擇提款或存款", Rect2(18, 296, 285, 24), 10, Color("#e8dca1"), HORIZONTAL_ALIGNMENT_CENTER, "ATMFeedback")
	add_child(_feedback)
	_refresh_action_buttons()
	_refresh_amount_display()


func _build_bank_scene() -> void:
	var special := _is_rear_edition()
	if special:
		_build_special_scene()
	else:
		_build_loan_scene()


func _build_loan_scene() -> void:
	add_child(_make_label("銀行", Rect2(24, 24, 160, 28), 21, Color("#f4e7ae"), HORIZONTAL_ALIGNMENT_LEFT, "LoanTitle"))
	add_child(_make_label("現金 %s" % _display_value("cash"), Rect2(30, 84, 205, 22), 13, Color("#eff0bf"), HORIZONTAL_ALIGNMENT_LEFT, "LoanCash"))
	add_child(_make_label("存款 %s" % _display_value("deposit"), Rect2(30, 108, 205, 22), 13, Color("#eff0bf"), HORIZONTAL_ALIGNMENT_LEFT, "LoanDeposit"))
	add_child(_make_label("貸款 %s" % _display_value("loan"), Rect2(30, 132, 205, 22), 13, Color("#eff0bf"), HORIZONTAL_ALIGNMENT_LEFT, "LoanBalance"))
	add_child(_make_label("到期日 %s" % _display_value("due_date"), Rect2(30, 156, 205, 22), 13, Color("#eff0bf"), HORIZONTAL_ALIGNMENT_LEFT, "LoanDueDate"))
	var borrow := _make_source_button("申請貸款", "LoanBorrow", Rect2(282, 324, 126, 42))
	borrow.pressed.connect(func() -> void: _select_action("take_loan"))
	add_child(borrow)
	var repay := _make_source_button("償還貸款", "LoanRepay", Rect2(470, 326, 120, 40))
	repay.pressed.connect(func() -> void: _select_action("repay_loan"))
	add_child(repay)
	var exit := _make_source_button("EXIT", "BankExit", Rect2(548, 431, 80, 40))
	exit.pressed.connect(_close_flow)
	add_child(exit)
	_feedback = _make_label("請選擇銀行操作", Rect2(250, 252, 270, 28), 12, Color("#e8dca1"), HORIZONTAL_ALIGNMENT_CENTER, "BankFeedback")
	add_child(_feedback)
	_refresh_action_buttons()


func _build_special_scene() -> void:
	add_child(_make_label("銀行", Rect2(8, 22, 180, 28), 21, Color("#f4e7ae"), HORIZONTAL_ALIGNMENT_LEFT, "SpecialTitle"))
	add_child(_make_label("客戶存款總額", Rect2(10, 136, 136, 22), 12, Color("#f4e7ae"), HORIZONTAL_ALIGNMENT_CENTER, "SpecialOtherDepositsLabel"))
	add_child(_make_label(_display_value("other_deposits"), Rect2(10, 153, 118, 20), 16, Color("#fff2b6"), HORIZONTAL_ALIGNMENT_RIGHT, "SpecialOtherDeposits"))
	add_child(_make_label("目前融資金額", Rect2(10, 184, 136, 22), 12, Color("#f4e7ae"), HORIZONTAL_ALIGNMENT_CENTER, "SpecialPrincipalLabel"))
	add_child(_make_label(_display_value("special_principal"), Rect2(10, 201, 118, 20), 16, Color("#fff2b6"), HORIZONTAL_ALIGNMENT_RIGHT, "SpecialPrincipal"))
	add_child(_make_label("尚可融資金額", Rect2(10, 232, 136, 22), 12, Color("#f4e7ae"), HORIZONTAL_ALIGNMENT_CENTER, "SpecialAvailableLabel"))
	add_child(_make_label(_display_value_for_limit("take_special_finance"), Rect2(10, 249, 118, 20), 16, Color("#fff2b6"), HORIZONTAL_ALIGNMENT_RIGHT, "SpecialAvailable"))
	var borrow := _make_source_button("週轉現金", "SpecialBorrow", Rect2(11, 305, 114, 40))
	borrow.tooltip_text = "來源文字保留；實際款項進入存款"
	borrow.pressed.connect(func() -> void: _select_action("take_special_finance"))
	add_child(borrow)
	var repay := _make_source_button("歸還款項", "SpecialRepay", Rect2(11, 362, 114, 40))
	repay.pressed.connect(func() -> void: _select_action("repay_special_finance"))
	add_child(repay)
	var exit := _make_source_button("EXIT", "BankExit", Rect2(11, 419, 80, 40))
	exit.pressed.connect(_close_flow)
	add_child(exit)
	add_child(_make_label("特別融資", Rect2(443, 427, 190, 24), 14, Color("#f4e7ae"), HORIZONTAL_ALIGNMENT_RIGHT, "SpecialWindowTitle"))
	_feedback = _make_label("僅銀行主席可用", Rect2(162, 294, 280, 28), 12, Color("#e8dca1"), HORIZONTAL_ALIGNMENT_LEFT, "BankFeedback")
	add_child(_feedback)
	_refresh_action_buttons()


func _add_source_background(key: String, screen_size: Vector2) -> void:
	var visual: Variant = _resolve_visual(key)
	if visual is Texture2D:
		var texture_rect := TextureRect.new()
		texture_rect.name = "SourceVisual"
		texture_rect.position = Vector2.ZERO
		texture_rect.size = screen_size
		texture_rect.texture = visual
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(texture_rect)
		move_child(texture_rect, 0)
		return
	var panel := Panel.new()
	panel.name = "SourceVisualFallback"
	panel.position = Vector2.ZERO
	panel.size = screen_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color("#203a3a"), Color("#b9bd7d"), 1))
	add_child(panel)
	move_child(panel, 0)


func _visual_key() -> String:
	var source_edition := _source_edition()
	if _mode == "atm":
		return "%s.Panel24" % source_edition
	if _is_rear_edition():
		return "%s.Panel23.rear" % source_edition
	return "%s.Panel23.front" % source_edition


func _source_edition() -> String:
	return "MultiverseJourney" if _edition in ["multiversejourney", "multiverse_journey", "mj", "journey"] else "Game"


func _resolve_visual(key: String) -> Variant:
	if _visual_accessor == null:
		return null
	if _visual_accessor is Dictionary:
		var visuals: Dictionary = _visual_accessor
		if visuals.has(key):
			return visuals.get(key)
		for alias in [key.to_lower(), key.to_upper(), key.replace(".", "/"), key.replace(".", "_")]:
			if visuals.has(alias):
				return visuals.get(alias)
		return null
	if _visual_accessor is Callable:
		return _visual_accessor.call(key)
	if _visual_accessor is Object:
		# OriginalVisuals exposes ui(edition, archive, resource, chunk) and
		# texture(frame).  Resolve this shape without making the presenter own
		# any path or file handling.
		if _visual_accessor.has_method("ui") and _visual_accessor.has_method("texture"):
			var resource := 24 if _mode == "atm" else 23
			var chunk := 2 if _is_rear_edition() else 0
			var frame: Variant = _visual_accessor.call("ui", _source_edition(), "Panel", resource, chunk)
			if frame is Dictionary:
				return _visual_accessor.call("texture", frame)
		for method in ["texture", "get_texture", "visual", "resolve"]:
			if _visual_accessor.has_method(method):
				return _visual_accessor.call(method, key)
	return null


func _select_action(action: String) -> bool:
	var canonical := _canonical_action(action)
	if canonical.is_empty() or not _is_action_allowed(canonical):
		_selected_action = ""
		if _feedback != null:
			_feedback.text = _unavailable_message(canonical)
		_refresh_action_buttons()
		return false
	_selected_action = canonical
	_amount_text = ""
	if _mode == "loan":
		_open_amount_pad(canonical)
	else:
		if _amount_bar != null:
			_amount_bar.max_value = float(_limit_for(canonical))
			_amount_bar.set_value_no_signal(0.0)
		_refresh_amount_display()
	_refresh_action_buttons()
	return true


func _open_amount_pad(action: String) -> void:
	_close_amount_pad()
	_amount_pad = AmountPadScript.new()
	_amount_pad.name = "SourceAmountPad"
	_amount_pad.position = Vector2(256, 144)
	_amount_pad.size = CALCULATOR_SIZE
	_amount_pad.z_index = 20
	_amount_pad.call("set_visuals", _visual_accessor, _source_edition())
	_amount_pad.call("configure", action, _limit_for(action))
	_amount_pad.connect("confirmed", Callable(self, "_on_pad_confirmed"))
	_amount_pad.connect("cancelled", Callable(self, "_on_pad_cancelled"))
	_amount_pad.connect("invalid_input", Callable(self, "_on_pad_invalid"))
	add_child(_amount_pad)
	_amount_pad.call_deferred("grab_focus")


func _on_pad_confirmed(amount: int) -> void:
	if _selected_action.is_empty():
		return
	if amount <= 0 or amount > _limit_for(_selected_action) or not _is_action_allowed(_selected_action):
		_on_pad_invalid("金額已超過目前可用上限")
		return
	action_requested.emit(_selected_action, amount)
	if _feedback != null:
		_feedback.text = "已送出 %s：%d" % [_selected_action, amount]


func _on_pad_cancelled() -> void:
	_close_amount_pad()
	_selected_action = ""
	_amount_text = ""
	if _feedback != null:
		_feedback.text = "請選擇銀行操作"
	_refresh_action_buttons()
	grab_focus()


func _on_pad_invalid(reason: String) -> void:
	if _feedback != null:
		_feedback.text = reason


func _confirm_current_amount() -> bool:
	if _selected_action.is_empty():
		_show_feedback("請先選擇操作")
		return false
	if not _is_action_allowed(_selected_action):
		_show_feedback(_unavailable_message(_selected_action))
		return false
	var result: Dictionary = AmountPadScript.parse_amount(_amount_text, _current_limit())
	if not bool(result.get("ok", false)):
		_show_feedback(str(result.get("reason", "金額無效")))
		return false
	action_requested.emit(_selected_action, int(result.get("amount", 0)))
	_show_feedback("已送出 %s：%d" % [_selected_action, int(result.get("amount", 0))])
	return true


func _current_limit() -> int:
	return _limit_for(_selected_action)


func _limit_for(action: String) -> int:
	var limits_value: Variant = _model.get("action_limits", {})
	if typeof(limits_value) != TYPE_DICTIONARY:
		return 0
	var limits: Dictionary = limits_value
	var canonical := _canonical_action(action)
	var raw: Variant = null
	for alias in _action_aliases(canonical):
		if limits.has(alias):
			raw = limits.get(alias)
			break
	if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or typeof(raw) == TYPE_BOOL:
		return 0
	var numeric := float(raw)
	if not is_finite(numeric) or numeric <= 0.0 or floor(numeric) != numeric:
		return 0
	return mini(int(numeric), 9223372036854775807)


func _is_action_allowed(action: String) -> bool:
	if action.is_empty() or not _model_valid:
		return false
	if action in ["exit", "back"]:
		return true
	var allowed_value: Variant = _model.get("allowed_actions", [])
	var permitted := false
	if typeof(allowed_value) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		for item in allowed_value:
			if typeof(item) == TYPE_STRING and _canonical_action(str(item)) == action:
				permitted = true
				break
	elif typeof(allowed_value) == TYPE_DICTIONARY:
		var allowed: Dictionary = allowed_value
		for alias in _action_aliases(action):
			if allowed.has(alias):
				permitted = typeof(allowed.get(alias)) == TYPE_BOOL and bool(allowed.get(alias))
				break
	if not permitted:
		return false
	if action in ["take_special_finance", "repay_special_finance"]:
		if typeof(_model.get("can_special", false)) != TYPE_BOOL or not bool(_model.get("can_special", false)):
			return false
	return _limit_for(action) > 0


func _canonical_action(action: String) -> String:
	var normalized := action.to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	if normalized in ["withdraw", "atm_withdraw", "bank_withdraw", "提款"]:
		return "withdraw"
	if normalized in ["deposit", "atm_deposit", "bank_deposit", "存款"]:
		return "deposit"
	if normalized in ["take_loan", "borrow", "loan_borrow", "apply_loan", "申請貸款"]:
		return "take_loan"
	if normalized in ["repay_loan", "repay", "loan_repay", "償還貸款"]:
		return "repay_loan"
	if normalized in ["take_special_finance", "special_finance", "special_borrow", "working_capital", "週轉現金"]:
		return "take_special_finance"
	if normalized in ["repay_special_finance", "special_repay", "repay_special", "歸還款項"]:
		return "repay_special_finance"
	if normalized in ["exit", "back", "cancel", "離開", "返回"]:
		return "exit"
	return ""


func _action_aliases(action: String) -> Array:
	match action:
		"withdraw": return ["withdraw", "atm_withdraw", "bank_withdraw", "提款"]
		"deposit": return ["deposit", "atm_deposit", "bank_deposit", "存款"]
		"take_loan": return ["take_loan", "borrow", "loan_borrow", "apply_loan", "申請貸款"]
		"repay_loan": return ["repay_loan", "repay", "loan_repay", "償還貸款"]
		"take_special_finance": return ["take_special_finance", "special_finance", "special_borrow", "working_capital", "週轉現金"]
		"repay_special_finance": return ["repay_special_finance", "special_repay", "repay_special", "歸還款項"]
		"exit": return ["exit", "back", "cancel", "離開", "返回"]
	return []


func _is_rear_edition() -> bool:
	if _edition in ["rear", "back", "special", "special_finance", "panel23.rear"] or _edition.ends_with("rear"):
		return true
	var allowed_value: Variant = _model.get("allowed_actions", [])
	if typeof(allowed_value) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		for item in allowed_value:
			if typeof(item) == TYPE_STRING and _canonical_action(str(item)) in ["take_special_finance", "repay_special_finance"]:
				return true
	if allowed_value is Dictionary:
		for action in ["take_special_finance", "repay_special_finance"]:
			for alias in _action_aliases(action):
				if allowed_value.has(alias) and typeof(allowed_value.get(alias)) == TYPE_BOOL and bool(allowed_value.get(alias)):
					return true
	return false


func _display_value(key: String) -> String:
	var value: Variant = _model.get(key, null)
	if typeof(value) in [TYPE_INT, TYPE_FLOAT] and typeof(value) != TYPE_BOOL:
		var numeric := float(value)
		if is_finite(numeric) and floor(numeric) == numeric:
			return str(int(numeric))
	if typeof(value) == TYPE_STRING and not str(value).is_empty():
		return str(value)
	return "—"


func _display_value_for_limit(action: String) -> String:
	var limit := _limit_for(action)
	return str(limit) if _has_limit_value(action) else "—"


func _has_limit_value(action: String) -> bool:
	var limits_value: Variant = _model.get("action_limits", {})
	if typeof(limits_value) != TYPE_DICTIONARY:
		return false
	var limits: Dictionary = limits_value
	for alias in _action_aliases(_canonical_action(action)):
		if not limits.has(alias):
			continue
		var raw: Variant = limits.get(alias)
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or typeof(raw) == TYPE_BOOL:
			return false
		var numeric := float(raw)
		return is_finite(numeric) and floor(numeric) == numeric and numeric >= 0.0
	return false


func _unavailable_message(action: String) -> String:
	if action.is_empty():
		return "目前不可用的銀行操作"
	if action in ["take_special_finance", "repay_special_finance"] and not bool(_model.get("can_special", false)):
		return "僅銀行主席可用"
	return "目前不可用：%s" % action


func _refresh_action_buttons() -> void:
	var button_names := {
		"withdraw": "ATMWithdraw", "deposit": "ATMDeposit", "take_loan": "LoanBorrow",
		"repay_loan": "LoanRepay", "take_special_finance": "SpecialBorrow",
		"repay_special_finance": "SpecialRepay",
	}
	for action in button_names:
		var button := find_child(str(button_names[action]), true, false) as BaseButton
		if button == null:
			continue
		button.disabled = not _is_action_allowed(action)
		if button is Button:
			button.tooltip_text = "目前不可用" if button.disabled else "選擇後輸入金額"
			(button as Button).add_theme_stylebox_override("normal", _style(Color("#3a5d57"), Color("#c5c889"), 1))
			if action == _selected_action:
				(button as Button).add_theme_stylebox_override("normal", _style(Color("#695f32"), Color("#fff4bc"), 2))


func _on_amount_bar_changed(value: float) -> void:
	var amount := clampi(roundi(value), 0, _current_limit())
	_amount_text = str(amount) if amount > 0 else ""
	_refresh_amount_display()


func _append_digit(digit: String) -> void:
	_amount_text += digit
	if _amount_bar != null:
		var parsed: Dictionary = AmountPadScript.parse_amount(_amount_text, _current_limit())
		_amount_bar.set_value_no_signal(float(parsed.get("amount", 0)) if bool(parsed.get("ok", false)) else 0.0)
	_refresh_amount_display()


func _fill_maximum() -> void:
	var maximum := _current_limit()
	_amount_text = str(maximum) if maximum > 0 else ""
	if _amount_bar != null:
		_amount_bar.set_value_no_signal(float(maximum))
	_refresh_amount_display()


func _clear_amount() -> void:
	_amount_text = ""
	if _amount_bar != null:
		_amount_bar.set_value_no_signal(0.0)
	_refresh_amount_display()


func _backspace_amount() -> void:
	if not _amount_text.is_empty():
		_amount_text = _amount_text.left(_amount_text.length() - 1)
	if _amount_bar != null:
		var parsed: Dictionary = AmountPadScript.parse_amount(_amount_text, _current_limit())
		_amount_bar.set_value_no_signal(float(parsed.get("amount", 0)) if bool(parsed.get("ok", false)) else 0.0)
	_refresh_amount_display()


func _refresh_amount_display() -> void:
	if _amount_value == null:
		return
	var parsed: Dictionary = AmountPadScript.parse_amount(_amount_text, _current_limit())
	_amount_value.text = "金額 %s / 上限 %d" % [str(parsed.get("amount", 0)) if bool(parsed.get("ok", false)) else "—", _current_limit()]
	var can_enter := not _selected_action.is_empty() and _limit_for(_selected_action) > 0
	var max_button := find_child("ATMMax", true, false) as BaseButton
	var enter_button := find_child("ATMEnter", true, false) as BaseButton
	if max_button != null:
		max_button.disabled = not can_enter
	if enter_button != null:
		enter_button.disabled = not can_enter
	if _amount_bar != null:
		_amount_bar.editable = can_enter
	if _feedback != null and _selected_action.is_empty():
		_feedback.text = "請先選擇提款或存款"


func _show_feedback(message: String) -> void:
	if _feedback != null:
		_feedback.text = message


func _close_amount_pad() -> void:
	if _amount_pad != null and is_instance_valid(_amount_pad):
		_amount_pad.free()
	_amount_pad = null


func _close_flow() -> void:
	_close_amount_pad()
	closed.emit()


func _clear_children() -> void:
	for child in get_children():
		child.free()


func _make_source_button(text_value: String, node_name: String, button_rect: Rect2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = button_rect.position
	button.size = button_rect.size
	button.custom_minimum_size = button_rect.size
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color("#f4e7ae"))
	button.add_theme_stylebox_override("normal", _style(Color("#3a5d57"), Color("#c5c889"), 1))
	button.add_theme_stylebox_override("hover", _style(Color("#557b6c"), Color("#fff0b2"), 1))
	button.add_theme_stylebox_override("pressed", _style(Color("#263f3c"), Color("#fff4c8"), 2))
	button.add_theme_stylebox_override("disabled", _style(Color("#2a3736"), Color("#657469"), 1))
	return button


func _make_label(text_value: String, label_rect: Rect2, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, node_name: String = "") -> Label:
	var label := Label.new()
	if not node_name.is_empty():
		label.name = node_name
	label.position = label_rect.position
	label.size = label_rect.size
	label.text = text_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(1)
	return style
