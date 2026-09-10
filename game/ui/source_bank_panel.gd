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
var _edition := "Game"
var _model_valid := false
var _bank_scene := "front"
var _has_source_visual := false
var _selected_action := ""
var _amount_text := ""
var _amount_pad: Node = null
var _amount_modal: Control = null
var _feedback: Label
var _amount_bar: HSlider
var _amount_value: Label
var _source_digits: Control
var _source_progress: Control
var _source_percent: Control


func _init() -> void:
	name = "SourceBankPanel"
	custom_minimum_size = ATM_SIZE
	size = ATM_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


## Replace the displayed snapshot.  The caller's dictionary is copied deeply
## so selection, rendering and validation cannot mutate host state.
func set_view_model(model: Dictionary) -> void:
	var was_rear := _mode == "loan" and _bank_scene == "rear"
	_model = model.duplicate(true)
	_mode = str(_model.get("entry_mode", "atm")).to_lower().strip_edges()
	var edition_value: Variant = _model.get("edition", "Game")
	_edition = _canonical_edition(edition_value)
	_model_valid = _mode in ["atm", "loan"] and not _edition.is_empty()
	if not was_rear or _mode != "loan" or not _can_enter_rear():
		_bank_scene = "front"
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
	if not visible or not is_visible_in_tree() or _mode != "atm" or _amount_pad != null or not event is InputEventKey:
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
	_close_amount_pad()
	_clear_children()
	var screen_size := ATM_SIZE if _mode == "atm" else BANK_SIZE
	custom_minimum_size = screen_size
	size = screen_size
	_has_source_visual = false
	_amount_bar = null
	_amount_value = null
	_feedback = null
	_source_digits = null
	_source_progress = null
	_source_percent = null
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
	_amount_bar.add_theme_stylebox_override("slider", _style(Color("#294f4c"), Color("#bdc885"), 1))
	_amount_bar.add_theme_stylebox_override("grabber_area", _style(Color("#6e9e77"), Color("#edf0b3"), 1))
	if _has_source_visual:
		_set_slider_transparent(_amount_bar)
	_amount_bar.value_changed.connect(_on_amount_bar_changed)
	add_child(_amount_bar)
	if _has_source_visual:
		_amount_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_amount_bar.hide()
		_source_digits = Control.new()
		_source_digits.name = "ATMSourceDigits"
		_source_digits.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_source_digits)
		_source_progress = Control.new()
		_source_progress.name = "ATMSourceProgress"
		_source_progress.position = Vector2(58, 139)
		_source_progress.clip_contents = true
		_source_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_source_progress)
		_source_percent = Control.new()
		_source_percent.name = "ATMPercent"
		_source_percent.position = Vector2(53, 137)
		_source_percent.size = Vector2(215, 29)
		_source_percent.gui_input.connect(_on_source_percent_input)
		add_child(_source_percent)
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
	if _bank_scene == "rear" and _can_enter_rear():
		_build_special_scene()
	else:
		_bank_scene = "front"
		_build_loan_scene()


func _build_loan_scene() -> void:
	_add_nonowner_rear_blind()
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
	_add_rear_entry_target()
	if _has_source_visual:
		_centered_label("申請貸款", "LoanBorrowLabel", Vector2(345, 345), Vector2(160, 40), 26, Color("#101010"))
		_centered_label("償還貸款", "LoanRepayLabel", Vector2(530, 345), Vector2(160, 40), 26, Color("#101010"))
		if _can_enter_rear():
			_centered_label("特別融資", "BankRearEntryLabel", Vector2(492, 245), Vector2(150, 24), 14, Color("#808080"))
	_feedback = _make_label("請選擇銀行操作", Rect2(250, 252, 270, 28), 12, Color("#e8dca1"), HORIZONTAL_ALIGNMENT_CENTER, "BankFeedback")
	add_child(_feedback)
	_refresh_action_buttons()


func _build_special_scene() -> void:
	_add_special_summary()
	for item in [["客戶存款總額", "SpecialOtherDepositsLabel", 147], ["目前融資金額", "SpecialPrincipalLabel", 195], ["尚可融資金額", "SpecialAvailableLabel", 243]]:
		_centered_label(item[0], item[1], Vector2(78, item[2]), Vector2(136, 24), 16, Color("#202020"))
	for item in [[_display_value("other_deposits"), "SpecialOtherDeposits", 163], [_display_value("special_principal"), "SpecialPrincipal", 211], [_display_value_for_limit("take_special_finance"), "SpecialAvailable", 259]]:
		add_child(_make_label(_source_money(item[0]) if _has_source_visual else item[0], Rect2(10, int(item[2]) - 12, 118, 24), 16, Color("#f0f0f0"), HORIZONTAL_ALIGNMENT_RIGHT, item[1]))
	var borrow := _make_source_button("週轉現金", "SpecialBorrow", Rect2(11, 305, 114, 40))
	borrow.pressed.connect(func() -> void: _select_action("take_special_finance"))
	add_child(borrow)
	var repay := _make_source_button("歸還款項", "SpecialRepay", Rect2(11, 362, 114, 40))
	repay.pressed.connect(func() -> void: _select_action("repay_special_finance"))
	add_child(repay)
	var exit := _make_source_button("EXIT", "BankExit", Rect2(11, 419, 80, 40))
	exit.pressed.connect(_exit_bank_scene)
	add_child(exit)
	if _has_source_visual:
		_centered_label("週轉現金", "SpecialBorrowLabel", Vector2(67, 324), Vector2(112, 32), 20, Color("#f0f0f0"))
		_centered_label("歸還款項", "SpecialRepayLabel", Vector2(67, 382), Vector2(112, 32), 20, Color("#f0f0f0"))
	_centered_label("特別融資", "SpecialWindowTitle", Vector2(443, 427), Vector2(220, 40), 26, Color("#101010"))
	_refresh_action_buttons()


func _add_rear_entry_target() -> void:
	if not _can_enter_rear():
		return
	var target := _make_source_hit_target("BankRearEntry", Rect2(268, 51, 323, 222))
	target.pressed.connect(_enter_rear)
	add_child(target)


func _add_nonowner_rear_blind() -> void:
	if _can_enter_rear():
		return
	var visual: Variant = _resolve_chunk_visual(23, 1, "%s.Panel23.chunk1" % _source_edition())
	if visual is Texture2D:
		_add_source_layer("SourceRearBlind", visual, Vector2(258, 42), Vector2(344, 240))


func _add_special_summary() -> void:
	var visual: Variant = _resolve_chunk_visual(23, 20, "%s.Panel23.chunk20" % _source_edition())
	if visual is Texture2D:
		_add_source_layer("SourceSpecialSummary", visual, Vector2(10, 125), Vector2(137, 165))


func _add_source_layer(node_name: String, visual: Texture2D, origin: Vector2, logical_size: Vector2) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.name = node_name
	texture_rect.position = origin
	texture_rect.size = logical_size
	texture_rect.texture = visual
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(texture_rect)
	move_child(texture_rect, mini(1, get_child_count() - 1))
	return texture_rect


func _enter_rear() -> void:
	if _amount_pad != null:
		return
	if not _can_enter_rear():
		_show_feedback("僅銀行主席可用")
		return
	call_deferred("_switch_bank_scene", "rear")


func _switch_bank_scene(scene: String) -> void:
	if _amount_pad != null:
		return
	if scene == "rear" and not _can_enter_rear():
		return
	_bank_scene = scene
	_selected_action = ""
	_amount_text = ""
	_close_amount_pad()
	_build_screen()
	grab_focus()


func _exit_bank_scene() -> void:
	if _amount_pad != null:
		return
	if _bank_scene == "rear":
		call_deferred("_switch_bank_scene", "front")
		return
	_close_flow()


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
		_has_source_visual = true
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
	if _bank_scene == "rear":
		return "%s.Panel23.rear" % source_edition
	return "%s.Panel23.front" % source_edition


func _source_edition() -> String:
	return _edition if _edition in ["Game", "MultiverseJourney"] else ""


func _resolve_visual(key: String) -> Variant:
	if _visual_accessor == null:
		return null
	if _visual_accessor is Dictionary:
		return _resolve_dictionary_visual(_visual_accessor, key)
	if _visual_accessor is Callable:
		return _visual_accessor.call(key)
	if _visual_accessor is Object:
		# OriginalVisuals exposes ui(edition, archive, resource, chunk) and
		# texture(frame).  Resolve this shape without making the presenter own
		# any path or file handling.
		if _visual_accessor.has_method("ui") and _visual_accessor.has_method("texture"):
			var resource := 24 if _mode == "atm" else 23
			var chunk := 2 if _bank_scene == "rear" else 0
			var frame: Variant = _visual_accessor.call("ui", _source_edition(), "Panel", resource, chunk)
			if frame is Dictionary:
				return _visual_accessor.call("texture", frame)
		for method in ["texture", "get_texture", "visual", "resolve"]:
			if _visual_accessor.has_method(method):
				return _visual_accessor.call(method, key)
	return null


func _resolve_chunk_visual(resource: int, chunk: int, key: String) -> Variant:
	if _visual_accessor == null:
		return null
	if _visual_accessor is Dictionary:
		var visuals: Dictionary = _visual_accessor
		var direct: Variant = _resolve_dictionary_visual(visuals, key)
		if direct != null:
			return direct
		for candidate in [
			"%s.Panel%d.%d" % [_source_edition(), resource, chunk],
			"%s.Panel%d.chunk%d" % [_source_edition(), resource, chunk],
			"%s.Panel%d/chunk%d" % [_source_edition(), resource, chunk],
		]:
			direct = _resolve_dictionary_visual(visuals, candidate)
			if direct != null:
				return direct
		return null
	if _visual_accessor is Callable:
		return _visual_accessor.call(key)
	if _visual_accessor is Object and _visual_accessor.has_method("ui") and _visual_accessor.has_method("texture"):
		var frame: Variant = _visual_accessor.call("ui", _source_edition(), "Panel", resource, chunk)
		if frame is Dictionary:
			return _visual_accessor.call("texture", frame)
	return null


func _resolve_dictionary_visual(visuals: Dictionary, key: String) -> Variant:
	var aliases := [key, key.to_lower(), key.to_upper(), key.replace(".", "/"), key.replace(".", "_")]
	if key.begins_with("MultiverseJourney"):
		aliases.append(key.replace("MultiverseJourney", "MJ"))
	for alias in aliases:
		if visuals.has(alias):
			return visuals.get(alias)
	return null


func _canonical_edition(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var normalized := str(value).to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	if normalized in ["game", "g"]:
		return "Game"
	if normalized in ["multiversejourney", "multiverse_journey", "mj", "journey"]:
		return "MultiverseJourney"
	return ""


func _select_action(action: String) -> bool:
	if _amount_pad != null:
		return false
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
	# Panel21 runs a nested source input loop: the bank scene remains visible
	# but cannot receive pointer or keyboard activation until it returns.
	_amount_modal = Control.new()
	_amount_modal.name = "AmountModalBoundary"
	_amount_modal.size = BANK_SIZE
	_amount_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_amount_modal.z_index = 19
	add_child(_amount_modal)
	focus_mode = Control.FOCUS_NONE
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
	var submitted_action := _selected_action
	_close_amount_pad()
	_selected_action = ""
	_refresh_action_buttons()
	action_requested.emit(submitted_action, amount)
	if _feedback != null:
		_feedback.text = "已送出 %s：%d" % [_action_label(submitted_action), amount]


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
	_show_feedback("已送出 %s：%d" % [_action_label(_selected_action), int(result.get("amount", 0))])
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
	if not _action_allowed_in_scene(action):
		return false
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


func _action_allowed_in_scene(action: String) -> bool:
	if _mode == "atm":
		return action in ["withdraw", "deposit"]
	if _bank_scene == "rear":
		return action in ["take_special_finance", "repay_special_finance"]
	return action in ["take_loan", "repay_loan"]


func _can_enter_rear() -> bool:
	return _mode == "loan" and _model_valid and typeof(_model.get("can_special", false)) == TYPE_BOOL and bool(_model.get("can_special", false))


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
	return "目前不可用：%s" % _action_label(action)


func _action_label(action: String) -> String:
	match action:
		"withdraw": return "提款"
		"deposit": return "存款"
		"take_loan": return "申請貸款"
		"repay_loan": return "償還貸款"
		"take_special_finance": return "週轉現金"
		"repay_special_finance": return "歸還款項"
		"exit": return "EXIT"
	return "銀行操作"


func _refresh_action_buttons() -> void:
	for node_name in ["BankExit", "BankRearEntry"]:
		var parent_button := find_child(node_name, true, false) as BaseButton
		if parent_button != null:
			parent_button.disabled = _amount_pad != null
	var button_names := {
		"withdraw": "ATMWithdraw", "deposit": "ATMDeposit", "take_loan": "LoanBorrow",
		"repay_loan": "LoanRepay", "take_special_finance": "SpecialBorrow",
		"repay_special_finance": "SpecialRepay",
	}
	for action in button_names:
		var button := find_child(str(button_names[action]), true, false) as BaseButton
		if button == null:
			continue
		button.disabled = _amount_pad != null or not _is_action_allowed(action)
		if button is Button:
			if _has_source_visual:
				_set_button_transparent(button as Button)
				_refresh_source_button(button)
			else:
				(button as Button).add_theme_stylebox_override("normal", _style(Color("#3a5d57"), Color("#c5c889"), 1))
				if action == _selected_action:
					(button as Button).add_theme_stylebox_override("normal", _style(Color("#695f32"), Color("#fff4bc"), 2))


func _on_amount_bar_changed(value: float) -> void:
	var amount := clampi(roundi(value), 0, _current_limit())
	_amount_text = str(amount) if amount > 0 else ""
	_refresh_amount_display()


func _append_digit(digit: String) -> void:
	_amount_text = AmountPadScript.append_source_digit(_amount_text, digit, _current_limit())
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
	_refresh_atm_source_art()


func _show_feedback(message: String) -> void:
	if _feedback != null:
		_feedback.text = message


func _close_amount_pad() -> void:
	if _amount_pad != null and is_instance_valid(_amount_pad):
		# Cancellation may originate inside the calculator's input callback.
		_amount_pad.hide()
		_amount_pad.queue_free()
	_amount_pad = null
	if _amount_modal != null and is_instance_valid(_amount_modal):
		_amount_modal.hide()
		_amount_modal.queue_free()
	_amount_modal = null
	focus_mode = Control.FOCUS_ALL


func _close_flow() -> void:
	if _amount_pad != null:
		return
	_close_amount_pad()
	closed.emit()


func _clear_children() -> void:
	for child in get_children():
		child.free()


func _make_source_button(text_value: String, node_name: String, button_rect: Rect2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = "" if _has_source_visual else text_value
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
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
	if _has_source_visual:
		_set_button_transparent(button)
		_bind_source_button(button)
	return button


func _make_source_hit_target(node_name: String, target_rect: Rect2) -> Button:
	var target := Button.new()
	target.name = node_name
	target.position = target_rect.position
	target.size = target_rect.size
	target.custom_minimum_size = target_rect.size
	target.focus_mode = Control.FOCUS_NONE
	target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	target.text = ""
	_set_button_transparent(target)
	return target


func _set_button_transparent(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, empty)


func _set_slider_transparent(slider: HSlider) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["slider", "grabber_area", "grabber_area_highlight", "grabber", "grabber_highlight", "focus"]:
		slider.add_theme_stylebox_override(state, empty)


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
	if _has_source_visual and node_name in ["ATMTitle", "ATMCash", "ATMDepositValue", "ATMAmountValue", "ATMFeedback", "LoanTitle", "LoanCash", "LoanDeposit", "LoanBalance", "LoanDueDate", "BankFeedback", "SpecialTitle"]:
		label.hide()
	return label


func _style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(1)
	return style


func _centered_label(text: String, key: String, center: Vector2, box: Vector2, font: int, color: Color) -> void:
	add_child(_make_label(text, Rect2(center - box * 0.5, box), font, color if _has_source_visual else Color("#f4e7ae"), HORIZONTAL_ALIGNMENT_CENTER, key))


func _source_money(value: String) -> String:
	if not value.is_valid_int(): return "—"
	var grouped := ""
	while value.length() > 3:
		grouped = "," + value.right(3) + grouped
		value = value.left(value.length() - 3)
	return "$" + value + grouped


func _sprite(texture: Texture2D, logical_size: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture
	art.size = logical_size
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


func _refresh_atm_source_art() -> void:
	if _source_digits == null: return
	for child in _source_digits.get_children(): child.free()
	for child in _source_progress.get_children(): child.free()
	var text := _amount_text
	if text.is_empty() or not text.is_valid_int() or int(text) < 0: text = "0"
	# Source-sized balances use their original ten glyph positions. Exceptional
	# larger remake balances retain every digit within the same display width.
	var ratio := minf(1.0, 10.0 / float(text.length()))
	for index in range(text.length()):
		var chunk := 19 + int(text[text.length() - 1 - index])
		var texture: Variant = _resolve_chunk_visual(24, chunk, "%s.Panel24.chunk%d" % [_edition, chunk])
		if texture is Texture2D:
			var art := _sprite(texture, Vector2(18 * ratio, 32))
			art.position = Vector2(244 + 18 * (1.0 - ratio) - index * 20 * ratio, 101)
			art.set_meta("source_chunk", chunk)
			_source_digits.add_child(art)
	var width := floori(clampf(float(current_amount()) / float(maxi(1, _current_limit())), 0.0, 1.0) * 34.0) * 6
	_source_progress.size = Vector2(width, 26)
	var bar: Variant = _resolve_chunk_visual(24, 4, "%s.Panel24.chunk4" % _edition)
	if bar is Texture2D: _source_progress.add_child(_sprite(bar, Vector2(204, 26)))


func _on_source_percent_input(event: InputEvent) -> void:
	if _selected_action.is_empty() or _current_limit() <= 0: return
	var active: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	active = active or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0)
	if not active: return
	var x: float = event.position.x + 53.0
	var limit := _current_limit()
	var amount := 0
	if x >= 262.0: amount = limit
	elif x > 58.0: amount = mini(limit, (floori((x - 58.0) / 6.0) + 1) * (floori(float(limit) / 34.0) + 1))
	set_amount_text(str(amount))
	_source_percent.accept_event()


func _source_button_spec(key: String) -> Dictionary:
	if _mode == "atm":
		var names := ["ATMWithdraw", "ATMDeposit", "ATMExit"]
		if key in names: return {"resource": 24, "normal": -1, "active": names.find(key) + 1}
		names = ["ATMDigit7", "ATMDigit8", "ATMDigit9", "ATMDigit4", "ATMDigit5", "ATMDigit6", "ATMDigit1", "ATMDigit2", "ATMDigit3", "ATMClear", "ATMDigit0", "ATMBackspace", "ATMMax", "ATMEnter"]
		if key in names: return {"resource": 24, "normal": -1, "active": names.find(key) + 5}
	elif _bank_scene == "rear":
		if key in ["SpecialBorrow", "SpecialRepay"]: return {"resource": 23, "normal": 16, "active": 17}
		if key == "BankExit": return {"resource": 23, "normal": 18, "active": 19}
	return {}


func _bind_source_button(button: Button) -> void:
	var spec := _source_button_spec(str(button.name))
	if spec.is_empty(): return
	var art := _sprite(null, button.size)
	art.name = "SourceButtonArt"
	button.add_child(art)
	button.mouse_entered.connect(func() -> void:
		button.set_meta("source_hot", true)
		_refresh_source_button(button))
	button.mouse_exited.connect(func() -> void:
		button.set_meta("source_hot", false)
		_refresh_source_button(button))
	button.button_down.connect(func() -> void: _refresh_source_button(button))
	button.button_up.connect(func() -> void: _refresh_source_button(button))
	_refresh_source_button(button)


func _refresh_source_button(button: Button) -> void:
	var spec := _source_button_spec(str(button.name))
	var art := button.get_node_or_null("SourceButtonArt") as TextureRect
	if spec.is_empty() or art == null: return
	var selected := (button.name == "ATMWithdraw" and _selected_action == "withdraw") or (button.name == "ATMDeposit" and _selected_action == "deposit")
	var active := selected or button.button_pressed or bool(button.get_meta("source_hot", false))
	var chunk := int(spec.active if active and not button.disabled else spec.normal)
	art.visible = chunk >= 0
	if chunk >= 0:
		art.texture = _resolve_chunk_visual(int(spec.resource), chunk, "%s.Panel%d.chunk%d" % [_edition, spec.resource, chunk]) as Texture2D
		art.set_meta("source_chunk", chunk)
