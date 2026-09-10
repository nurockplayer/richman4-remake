extends Control
class_name RichmanSourceAmountPad

## Panel21 calculator presenter.  It owns only text, selection and signals;
## the host remains responsible for validating and applying the action.

signal confirmed(amount: int)
signal cancelled
signal invalid_input(reason: String)

const SOURCE_SIZE := Vector2(128.0, 192.0)
const PERCENT_THRESHOLDS := [3, 6, 9, 12, 15, 19, 22, 25, 28, 31, 34, 38, 41, 44, 47, 50, 53, 57, 60, 63, 66, 69, 73, 76, 79, 82, 85, 88, 92, 95, 98, 101, 104, 107]

var action := ""
var maximum := 0
var input_field: LineEdit
var amount_label: Label
var limit_label: Label
var error_label: Label
var submit_button: Button
var max_button: Button

var _available := false
var _availability_message := ""
var _visual_accessor: Variant = null
var _edition := "Game"
var _has_source_visual := false
var _percent: Control
var _progress: Control
var _empty_progress: TextureRect
var _digits: Control


func _init() -> void:
	name = "SourceAmountPad"
	custom_minimum_size = SOURCE_SIZE
	size = SOURCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_build()


func _build() -> void:
	var surface := Panel.new()
	surface.name = "AmountPadSurface"
	surface.position = Vector2.ZERO
	surface.size = SOURCE_SIZE
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_theme_stylebox_override("panel", _style(Color("#1b3030"), Color("#d8c37c"), 1))
	add_child(surface)

	var title := Label.new()
	title.name = "AmountPadTitle"
	title.position = Vector2(5, 3)
	title.size = Vector2(118, 17)
	title.text = "金額"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color("#f4e7ae"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	input_field = LineEdit.new()
	input_field.name = "AmountInput"
	input_field.position = Vector2(7, 20)
	input_field.size = Vector2(114, 23)
	input_field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	input_field.placeholder_text = "0"
	input_field.focus_mode = Control.FOCUS_ALL
	input_field.add_theme_font_size_override("font_size", 13)
	input_field.add_theme_color_override("font_color", Color("#1d2d28"))
	input_field.add_theme_color_override("font_placeholder_color", Color("#587263"))
	input_field.add_theme_stylebox_override("normal", _style(Color("#d9e5af"), Color("#f4e7ae"), 1))
	input_field.text_changed.connect(_on_text_changed)
	input_field.text_submitted.connect(func(_value: String) -> void: _submit())
	add_child(input_field)

	amount_label = Label.new()
	amount_label.name = "AmountValue"
	amount_label.position = Vector2(4, 44)
	amount_label.size = Vector2(120, 16)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_label.add_theme_font_size_override("font_size", 9)
	amount_label.add_theme_color_override("font_color", Color("#f4e7ae"))
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(amount_label)

	limit_label = Label.new()
	limit_label.name = "AmountLimit"
	limit_label.position = Vector2(4, 59)
	limit_label.size = Vector2(120, 14)
	limit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	limit_label.add_theme_font_size_override("font_size", 8)
	limit_label.add_theme_color_override("font_color", Color("#b7caa1"))
	limit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(limit_label)

	# Panel21 的按鍵直接放在來源座標附近，避免使用會改變視覺層次的
	# 現代表單版面。Panel22 沒有視覺資源，這裡不會捏造它的圖像。
	for key in [
		["C", "AmountClear", Vector2(8, 95)],
		["0", "AmountDigit0", Vector2(48, 95)],
		["←", "AmountBackspace", Vector2(88, 95)],
	]:
		var button := _make_button(str(key[0]), str(key[1]), Rect2(key[2], Vector2(33, 17)))
		add_child(button)
		if button.name == "AmountClear":
			button.pressed.connect(_clear)
		elif button.name == "AmountDigit0":
			button.pressed.connect(func() -> void: _append_digit("0"))
		else:
			button.pressed.connect(_backspace)

	var rows := [["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"]]
	for row_index in rows.size():
		for column_index in rows[row_index].size():
			var digit: String = rows[row_index][column_index]
			var button_name := "AmountDigit" + digit
			var button_position := Vector2(8 + column_index * 40, 119 + row_index * 24)
			var button := _make_button(digit, button_name, Rect2(button_position, Vector2(33, 17)))
			add_child(button)
			button.pressed.connect(func() -> void: _append_digit(digit))

	max_button = _make_button("MAX", "AmountMax", Rect2(Vector2(8, 63), Vector2(49, 25)))
	max_button.pressed.connect(_fill_maximum)
	add_child(max_button)
	submit_button = _make_button("ENTER", "AmountEnter", Rect2(Vector2(64, 63), Vector2(57, 25)))
	submit_button.pressed.connect(_submit)
	add_child(submit_button)

	error_label = Label.new()
	error_label.name = "AmountError"
	error_label.position = Vector2(4, 135)
	error_label.size = Vector2(120, 19)
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_font_size_override("font_size", 8)
	error_label.add_theme_color_override("font_color", Color("#ffb2a4"))
	error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(error_label)

	_digits = Control.new()
	_digits.name = "AmountSourceDigits"
	_digits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_digits)
	_empty_progress = _sprite(null, Vector2(108, 12))
	_empty_progress.name = "AmountSourceEmptyProgress"
	_empty_progress.position = Vector2(10, 42)
	add_child(_empty_progress)
	_progress = Control.new()
	_progress.name = "AmountSourceProgress"
	_progress.position = Vector2(10, 42)
	_progress.clip_contents = true
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress)
	_percent = Control.new()
	_percent.name = "AmountPercent"
	_percent.position = Vector2(10, 42)
	_percent.size = Vector2(108, 12)
	_percent.mouse_filter = Control.MOUSE_FILTER_STOP
	_percent.gui_input.connect(_on_percent_input)
	add_child(_percent)
	_percent.hide()
	_refresh_display()


func configure(action_value: String, maximum_value: int, initial_amount: int = 0) -> void:
	action = action_value.to_lower().strip_edges()
	maximum = maxi(0, maximum_value)
	_available = maximum > 0
	_availability_message = "" if _available else "目前沒有可用額度"
	input_field.text = ""
	if initial_amount > 0 and initial_amount <= maximum:
		input_field.text = str(initial_amount)
	_refresh_display()
	if is_inside_tree():
		_focus_entry()


func set_available(available: bool, message: String = "") -> void:
	_available = available and maximum > 0
	_availability_message = message if not message.is_empty() else ("目前不可用" if not _available else "")
	_refresh_display()


func set_visuals(accessor: Variant, edition_value: String = "Game") -> void:
	if accessor is Dictionary:
		_visual_accessor = accessor.duplicate(true)
	else:
		_visual_accessor = accessor
	_edition = edition_value if edition_value in ["Game", "MultiverseJourney"] else "Game"
	_apply_visual()


func set_amount_text(value: String) -> void:
	if input_field == null:
		return
	input_field.text = value
	input_field.caret_column = input_field.text.length()
	_refresh_display()


func raw_text() -> String:
	return input_field.text if input_field != null else ""


func parsed_amount() -> Dictionary:
	return parse_amount(raw_text(), maximum)


static func parse_amount(raw: String, maximum_value: int) -> Dictionary:
	if raw.is_empty():
		return {"ok": false, "amount": 0, "reason": "請輸入金額"}
	if raw.strip_edges() != raw:
		return {"ok": false, "amount": 0, "reason": "金額不可含空白"}
	var digits := RegEx.new()
	digits.compile("^[0-9]+$")
	if digits.search(raw) == null:
		return {"ok": false, "amount": 0, "reason": "金額必須是整數"}
	if maximum_value <= 0:
		return {"ok": false, "amount": 0, "reason": "目前沒有可用額度"}
	var maximum_text := str(maximum_value)
	if raw.length() > maximum_text.length() or (raw.length() == maximum_text.length() and raw > maximum_text):
		return {"ok": false, "amount": 0, "reason": "超過目前上限 %d" % maximum_value}
	var amount := int(raw)
	if amount <= 0:
		return {"ok": false, "amount": 0, "reason": "金額必須大於 0"}
	if amount > maximum_value:
		return {"ok": false, "amount": 0, "reason": "超過目前上限 %d" % maximum_value}
	return {"ok": true, "amount": amount, "reason": ""}


func cancel() -> void:
	cancelled.emit()


func _apply_visual() -> void:
	var visual: Variant = _resolve_visual()
	if not visual is Texture2D:
		_has_source_visual = false
		_set_source_layering(false)
		var stale := get_node_or_null("AmountPadSourceVisual")
		if stale != null:
			stale.free()
		_refresh_source_art()
		return
	_has_source_visual = true
	_set_source_layering(true)
	var existing := get_node_or_null("AmountPadSourceVisual") as TextureRect
	if existing != null:
		existing.texture = visual
		_refresh_source_art()
		return
	var texture_rect := TextureRect.new()
	texture_rect.name = "AmountPadSourceVisual"
	texture_rect.position = Vector2.ZERO
	texture_rect.size = SOURCE_SIZE
	texture_rect.texture = visual
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(texture_rect)
	move_child(texture_rect, 0)
	_refresh_source_art()


func _resolve_visual(chunk: int = 0) -> Variant:
	if _visual_accessor == null:
		return null
	var key := "%s.Panel21" % _edition if chunk == 0 else "%s.Panel21.chunk%d" % [_edition, chunk]
	if _visual_accessor is Dictionary:
		var visuals: Dictionary = _visual_accessor
		var aliases := [key, key.to_lower(), key.to_upper(), key.replace(".", "/"), key.replace(".", "_")]
		if key.begins_with("MultiverseJourney"):
			aliases.append(key.replace("MultiverseJourney", "MJ"))
		for alias in aliases:
			if visuals.has(alias):
				return visuals.get(alias)
		return null
	if _visual_accessor is Callable:
		return _visual_accessor.call(key)
	if _visual_accessor is Object:
		if _visual_accessor.has_method("ui") and _visual_accessor.has_method("texture"):
			var frame: Variant = _visual_accessor.call("ui", _edition, "Panel", 21, chunk)
			if frame is Dictionary:
				return _visual_accessor.call("texture", frame)
		for method in ["texture", "get_texture", "visual", "resolve"]:
			if _visual_accessor.has_method(method):
				return _visual_accessor.call(method, key)
	return null


func _set_source_layering(enabled: bool) -> void:
	var surface := get_node_or_null("AmountPadSurface") as Panel
	if surface != null:
		surface.add_theme_stylebox_override("panel", StyleBoxEmpty.new() if enabled else _style(Color("#1b3030"), Color("#d8c37c"), 1))
	if input_field != null:
		input_field.add_theme_stylebox_override("normal", StyleBoxEmpty.new() if enabled else _style(Color("#d9e5af"), Color("#f4e7ae"), 1))
		input_field.add_theme_stylebox_override("focus", StyleBoxEmpty.new() if enabled else _style(Color("#d9e5af"), Color("#f4e7ae"), 1))
	for key in ["AmountPadTitle", "AmountInput", "AmountValue", "AmountLimit", "AmountError"]:
		var child := get_node_or_null(key) as CanvasItem
		if child != null: child.visible = not enabled
	for child in get_children():
		if child is Button:
			child.text = "" if enabled else str(child.get_meta("fallback_text", ""))
			if enabled:
				_set_button_transparent(child as Button)
			else:
				_restore_button_style(child as Button)
				var art := child.get_node_or_null("SourceButtonArt") as CanvasItem
				if art != null: art.hide()


func _set_button_transparent(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, empty)


func _restore_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _style(Color("#355955"), Color("#c4c98d"), 1))
	button.add_theme_stylebox_override("hover", _style(Color("#4d7465"), Color("#fff0b2"), 1))
	button.add_theme_stylebox_override("pressed", _style(Color("#1f3938"), Color("#fff4c8"), 1))
	button.add_theme_stylebox_override("disabled", _style(Color("#273635"), Color("#65766b"), 1))


func _gui_input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree() or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if _handle_key(key_event):
		accept_event()


func _handle_key(event: InputEventKey) -> bool:
	if event.keycode == KEY_ESCAPE:
		cancel()
		return true
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_submit()
		return true
	if event.keycode == KEY_BACKSPACE or event.keycode == KEY_DELETE:
		_backspace()
		return true
	if event.keycode == KEY_C:
		_clear()
		return true
	var digit := _digit_from_event(event)
	if not digit.is_empty():
		_append_digit(digit)
		return true
	return false


func _digit_from_event(event: InputEventKey) -> String:
	if event.unicode >= 48 and event.unicode <= 57:
		return String.chr(event.unicode)
	var digit_codes := {
		KEY_0: "0", KEY_1: "1", KEY_2: "2", KEY_3: "3", KEY_4: "4",
		KEY_5: "5", KEY_6: "6", KEY_7: "7", KEY_8: "8", KEY_9: "9",
	}
	return str(digit_codes.get(event.keycode, ""))


func _append_digit(digit: String) -> void:
	if input_field.text == "0": input_field.text = ""
	input_field.text += digit
	input_field.caret_column = input_field.text.length()
	_focus_entry()
	_refresh_display()


func _fill_maximum() -> void:
	if maximum <= 0:
		_refresh_display()
		return
	input_field.text = str(maximum)
	input_field.caret_column = input_field.text.length()
	_focus_entry()
	_refresh_display()


func _clear() -> void:
	input_field.text = ""
	input_field.caret_column = 0
	_focus_entry()
	_refresh_display()


func _backspace() -> void:
	if not input_field.text.is_empty():
		input_field.text = input_field.text.left(input_field.text.length() - 1)
	input_field.caret_column = input_field.text.length()
	_focus_entry()
	_refresh_display()


func _on_text_changed(_value: String) -> void:
	_refresh_display()


func _submit() -> bool:
	var result := parsed_amount()
	if not bool(result.get("ok", false)):
		var reason := str(result.get("reason", "金額無效"))
		error_label.text = reason
		invalid_input.emit(reason)
		return false
	if not _available:
		var unavailable := _availability_message if not _availability_message.is_empty() else "目前不可用"
		error_label.text = unavailable
		invalid_input.emit(unavailable)
		return false
	confirmed.emit(int(result.get("amount", 0)))
	return true


func _refresh_display() -> void:
	if input_field == null:
		return
	var parsed := parsed_amount()
	amount_label.text = "已選 %s" % (str(parsed.get("amount", 0)) if bool(parsed.get("ok", false)) else "—")
	limit_label.text = "上限 %d" % maximum
	if not _available and not _availability_message.is_empty():
		error_label.text = _availability_message
	elif input_field.text.is_empty() or bool(parsed.get("ok", false)):
		error_label.text = ""
	else:
		error_label.text = str(parsed.get("reason", "金額無效"))
	if max_button != null:
		max_button.disabled = not _available
	if submit_button != null:
		submit_button.disabled = not _available
	_refresh_source_art()


func _make_button(text_value: String, node_name: String, button_rect: Rect2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.set_meta("fallback_text", text_value)
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.position = button_rect.position
	button.size = button_rect.size
	button.custom_minimum_size = button_rect.size
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_color_override("font_color", Color("#f4e7ae"))
	button.add_theme_stylebox_override("normal", _style(Color("#355955"), Color("#c4c98d"), 1))
	button.add_theme_stylebox_override("hover", _style(Color("#4d7465"), Color("#fff0b2"), 1))
	button.add_theme_stylebox_override("pressed", _style(Color("#1f3938"), Color("#fff4c8"), 1))
	button.add_theme_stylebox_override("disabled", _style(Color("#273635"), Color("#65766b"), 1))
	return button


func _style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(1)
	return style


func _focus_entry() -> void:
	if not is_inside_tree(): return
	if _has_source_visual: grab_focus()
	else: input_field.grab_focus()


func _sprite(texture: Texture2D, logical_size: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture
	art.size = logical_size
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


func _refresh_source_art() -> void:
	if _digits == null: return
	_digits.visible = _has_source_visual
	_empty_progress.visible = _has_source_visual
	_progress.visible = _has_source_visual
	_percent.visible = _has_source_visual
	for child in _digits.get_children(): child.free()
	for child in _progress.get_children(): child.free()
	if not _has_source_visual: return
	var text := raw_text()
	if text.is_empty() or not text.is_valid_int() or int(text) < 0: text = "0"
	# Existing remake balances can exceed the source's nine-digit width. Keep
	# every entered digit visible, compressing only that exceptional display.
	var ratio := minf(1.0, 9.0 / float(text.length()))
	for index in range(text.length()):
		var chunk := 16 + int(text[text.length() - 1 - index])
		var texture: Variant = _resolve_visual(chunk)
		if texture is Texture2D:
			var art := _sprite(texture, Vector2(9 * ratio, 19))
			art.position = Vector2(107 + 9 * (1.0 - ratio) - index * 12 * ratio, 11)
			art.set_meta("source_chunk", chunk)
			_digits.add_child(art)
	var value := int(parsed_amount().get("amount", 0))
	var step := clampi(floori(float(value) * 33.0 / float(maxi(1, maximum))), 0, 33)
	var width := int(PERCENT_THRESHOLDS[step]) if value > 0 else 0
	_progress.size = Vector2(width, 12)
	# Chunk1 is the empty strip. The source restores the filled prefix from
	# background0 over it; clipping chunk1 itself would reverse the display.
	_empty_progress.texture = _resolve_visual(1) as Texture2D
	var background: Variant = _resolve_visual(0)
	if background is Texture2D:
		var filled := AtlasTexture.new()
		filled.atlas = background
		var pixel_scale: Vector2 = background.get_size() / SOURCE_SIZE
		filled.region = Rect2(Vector2(10, 42) * pixel_scale, Vector2(108, 12) * pixel_scale)
		_progress.add_child(_sprite(filled, Vector2(108, 12)))
	var names := ["AmountMax", "AmountEnter", "AmountClear", "AmountDigit0", "AmountBackspace", "AmountDigit7", "AmountDigit8", "AmountDigit9", "AmountDigit4", "AmountDigit5", "AmountDigit6", "AmountDigit1", "AmountDigit2", "AmountDigit3"]
	for index in range(names.size()):
		var button := get_node_or_null(names[index]) as Button
		if button == null: continue
		var art := button.get_node_or_null("SourceButtonArt") as TextureRect
		var texture: Variant = _resolve_visual(index + 2)
		if art == null:
			art = _sprite(texture as Texture2D, button.size)
			art.name = "SourceButtonArt"
			art.set_meta("source_chunk", index + 2)
			button.add_child(art)
			button.button_down.connect(func() -> void: art.visible = _has_source_visual)
			button.button_up.connect(func() -> void: art.hide())
		art.texture = texture as Texture2D
		art.visible = button.button_pressed and _has_source_visual


func _on_percent_input(event: InputEvent) -> void:
	if not _has_source_visual or not _available: return
	var active: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	active = active or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0)
	if not active: return
	var offset := clampf(event.position.x, 0.0, 107.0)
	var index := 0
	while index < 33 and float(PERCENT_THRESHOLDS[index]) < offset: index += 1
	set_amount_text(str(int(floor(float(maximum) * float(index) / 33.0))))
	_percent.accept_event()
	_focus_entry()
