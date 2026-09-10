extends Control
class_name RichmanSourceQuantityPad

## Source-shaped quantity input for the stock buy/sell flow.
##
## The pad deliberately keeps the text entered by the player intact.  The
## source calculator treats zero as cancel, while malformed, fractional,
## negative, blank and over-limit values are rejected before a trade signal can
## be emitted.  The game state remains the authority for the final trade.

signal accepted(quantity: int)
signal cancelled
signal invalid_input(reason: String)

var action := ""
var symbol := ""
var price := 0.0
var maximum := 0

var input_field: LineEdit
var amount_label: Label
var limit_label: Label
var error_label: Label
var submit_button: Button

var _available := true
var _availability_message := ""


func _init() -> void:
	name = "SourceQuantityPad"
	custom_minimum_size = Vector2(124.0, 206.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var panel := Panel.new()
	panel.name = "QuantityPadSurface"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color("#0f2527"), Color("#a8d9c2"), 1))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "QuantityPadMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var column := VBoxContainer.new()
	column.name = "QuantityPadColumn"
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var heading := Label.new()
	heading.name = "QuantityPadHeading"
	heading.text = "交易股數"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Color("#f5efc4"))
	column.add_child(heading)

	input_field = LineEdit.new()
	input_field.name = "QuantityInput"
	input_field.placeholder_text = "輸入股數"
	input_field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	input_field.custom_minimum_size.y = 25
	input_field.focus_mode = Control.FOCUS_ALL
	input_field.add_theme_font_size_override("font_size", 13)
	input_field.add_theme_color_override("font_color", Color("#073c2d"))
	input_field.add_theme_color_override("font_placeholder_color", Color("#397a62"))
	input_field.add_theme_stylebox_override("normal", _style(Color("#67d0ac"), Color("#d8ffe3"), 1))
	input_field.text_changed.connect(_on_text_changed)
	input_field.text_submitted.connect(func(_value: String) -> void: _submit())
	column.add_child(input_field)

	amount_label = Label.new()
	amount_label.name = "QuantityAmount"
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_label.add_theme_font_size_override("font_size", 10)
	amount_label.add_theme_color_override("font_color", Color("#f5efc4"))
	column.add_child(amount_label)

	limit_label = Label.new()
	limit_label.name = "QuantityLimit"
	limit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	limit_label.add_theme_font_size_override("font_size", 9)
	limit_label.add_theme_color_override("font_color", Color("#b8d4c2"))
	column.add_child(limit_label)

	var keypad := GridContainer.new()
	keypad.name = "QuantityKeypad"
	keypad.columns = 4
	keypad.add_theme_constant_override("h_separation", 2)
	keypad.add_theme_constant_override("v_separation", 2)
	keypad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(keypad)

	var max_button := _make_button("MAX", "QuantityMax")
	max_button.pressed.connect(_fill_maximum)
	keypad.add_child(max_button)
	var spacer_a := Control.new()
	spacer_a.custom_minimum_size = Vector2(25, 22)
	keypad.add_child(spacer_a)
	var spacer_b := Control.new()
	spacer_b.custom_minimum_size = Vector2(25, 22)
	keypad.add_child(spacer_b)
	var back_button := _make_button("←", "QuantityBackspace")
	back_button.pressed.connect(_backspace)
	keypad.add_child(back_button)

	var clear_button := _make_button("C", "QuantityClear")
	clear_button.pressed.connect(_clear)
	keypad.add_child(clear_button)
	var zero_button := _make_button("0", "QuantityDigit0")
	zero_button.pressed.connect(func() -> void: _append_digit("0"))
	keypad.add_child(zero_button)
	var spacer_c := Control.new()
	spacer_c.custom_minimum_size = Vector2(25, 22)
	keypad.add_child(spacer_c)
	submit_button = _make_button("↵", "QuantitySubmit")
	submit_button.pressed.connect(_submit)
	keypad.add_child(submit_button)

	for row in [["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"]]:
		for digit in row:
			var button := _make_button(digit, "QuantityDigit" + digit)
			button.pressed.connect(func() -> void: _append_digit(digit))
			keypad.add_child(button)
		var row_spacer := Control.new()
		row_spacer.custom_minimum_size = Vector2(25, 22)
		keypad.add_child(row_spacer)

	error_label = Label.new()
	error_label.name = "QuantityError"
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_font_size_override("font_size", 9)
	error_label.add_theme_color_override("font_color", Color("#ffb6a9"))
	error_label.custom_minimum_size.y = 22
	column.add_child(error_label)

	_refresh_display()


func configure(action_value: String, symbol_value: String, price_value: float, maximum_value: int, account_value := 0) -> void:
	action = action_value.to_lower().strip_edges()
	symbol = symbol_value.to_lower().strip_edges()
	price = price_value
	maximum = maxi(0, maximum_value)
	input_field.text = ""
	_available = true
	_availability_message = ""
	if maximum <= 0:
		_available = false
		_availability_message = "目前沒有可交易股數"
	_refresh_display()


func set_available(available: bool, message := "") -> void:
	_available = available
	_availability_message = message
	_refresh_display()


func cancel() -> void:
	cancelled.emit()


func raw_text() -> String:
	return input_field.text if input_field != null else ""


func parsed_quantity() -> Dictionary:
	return parse_quantity(raw_text(), maximum)


static func parse_quantity(raw: String, maximum_value: int) -> Dictionary:
	if raw == "0":
		return {"ok": false, "cancel": true, "quantity": 0, "reason": "cancel"}
	if raw.is_empty():
		return {"ok": false, "cancel": false, "quantity": 0, "reason": "請輸入股數"}
	if raw.strip_edges() != raw:
		return {"ok": false, "cancel": false, "quantity": 0, "reason": "股數不可含空白"}
	var digits := RegEx.new()
	digits.compile("^[1-9][0-9]*$")
	if digits.search(raw) == null:
		return {"ok": false, "cancel": false, "quantity": 0, "reason": "股數必須是正整數"}
	if maximum_value <= 0:
		return {"ok": false, "cancel": false, "quantity": 0, "reason": "目前沒有可交易股數"}
	var maximum_text := str(maximum_value)
	if raw.length() > maximum_text.length() or (raw.length() == maximum_text.length() and raw > maximum_text):
		return {"ok": false, "cancel": false, "quantity": 0, "reason": "超過目前可交易上限 %d 股" % maximum_value}
	var quantity := int(raw)
	if quantity <= 0 or quantity > maximum_value:
		return {"ok": false, "cancel": false, "quantity": 0, "reason": "超過目前可交易上限 %d 股" % maximum_value}
	return {"ok": true, "cancel": false, "quantity": quantity, "reason": ""}


func _submit() -> void:
	var result := parsed_quantity()
	if bool(result.get("cancel", false)):
		cancelled.emit()
		return
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("reason", "股數無效")))
		invalid_input.emit(str(result.get("reason", "股數無效")))
		return
	if not _available:
		_show_error(_availability_message if not _availability_message.is_empty() else "目前不可交易")
		invalid_input.emit(_availability_message)
		return
	accepted.emit(int(result.quantity))


func _append_digit(digit: String) -> void:
	input_field.text += digit
	input_field.caret_column = input_field.text.length()
	input_field.grab_focus()
	_refresh_display()


func _fill_maximum() -> void:
	input_field.text = str(maximum) if maximum > 0 else "0"
	input_field.caret_column = input_field.text.length()
	input_field.grab_focus()
	_refresh_display()


func _clear() -> void:
	input_field.text = ""
	input_field.grab_focus()
	_refresh_display()


func _backspace() -> void:
	if not input_field.text.is_empty():
		input_field.text = input_field.text.left(input_field.text.length() - 1)
	input_field.caret_column = input_field.text.length()
	input_field.grab_focus()
	_refresh_display()


func _on_text_changed(_value: String) -> void:
	_refresh_display()


func _refresh_display() -> void:
	if input_field == null:
		return
	var parsed := parsed_quantity()
	if bool(parsed.get("ok", false)) and is_finite(price):
		amount_label.text = "金額 %d" % int(price * int(parsed.quantity))
	else:
		amount_label.text = "金額 —"
	limit_label.text = "上限 %d 股" % maximum
	if not _available and not _availability_message.is_empty():
		error_label.text = _availability_message
	elif bool(parsed.get("ok", false)) or input_field.text.is_empty():
		error_label.text = ""
	else:
		error_label.text = str(parsed.get("reason", "股數無效"))
	if submit_button != null:
		submit_button.disabled = not _available


func _show_error(message: String) -> void:
	error_label.text = message


func _make_button(text_value: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.custom_minimum_size = Vector2(25, 22)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", Color("#f5efc4"))
	button.add_theme_stylebox_override("normal", _style(Color("#285151"), Color("#8bb8a4"), 1))
	button.add_theme_stylebox_override("hover", _style(Color("#3c7070"), Color("#e1f2c3"), 1))
	button.add_theme_stylebox_override("pressed", _style(Color("#183637"), Color("#f6e79a"), 1))
	button.add_theme_stylebox_override("disabled", _style(Color("#203334"), Color("#678071"), 1))
	return button


func _style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(1)
	return style
