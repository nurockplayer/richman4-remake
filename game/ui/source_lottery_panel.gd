extends Control
class_name RichmanSourceLotteryPanel

## Source-shaped S29/S30 lottery presenter.
##
## The host supplies a detached snapshot and owns all financial/state changes.
## This control only presents the snapshot and emits an explicit ticket/return
## intent; it never mutates the supplied dictionary or performs payment/RNG.

signal ticket_selected(number: int)
signal cancelled
signal continued

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const GRID_ORIGIN := Vector2(30.0, 271.0)
const CELL_SIZE := Vector2(64.0, 48.0)
const SOLD_ORIGIN := Vector2(31.0, 272.0)
const SOLD_SIZE := Vector2(62.0, 46.0)
const TICKET_COUNT := 36
const TICKET_PRICE := 1000
const VALID_EDITIONS := ["Game", "MultiverseJourney"]

const SOURCE_LOGICAL_SIZES := {
	"purchase_background": Vector2(640.0, 480.0),
	"dealer": Vector2(358.0, 298.0),
	"speech": Vector2(237.0, 192.0),
	"amount": Vector2(172.0, 28.0),
	"draw_background": Vector2(640.0, 480.0),
	"heart": Vector2(187.0, 140.0),
	"burst": Vector2(233.0, 192.0),
	"red_burst": Vector2(295.0, 262.0),
}

var _model: Dictionary = {}
var _visual_accessor: Variant = null
var _kind := ""
var _edition := ""
var _model_valid := false
var _is_open := false
var _closed := false
var _pressed_ticket := -1
var _selected_number := 0
var _continued_emitted := false
var _source_art_available := false
var _source_frames: Dictionary = {}


func _init() -> void:
	name = "SourceLotteryPanel"
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Replace the detached purchase/draw snapshot.  The presenter does not write
## to the caller's arrays or dictionaries.
func set_view_model(model: Dictionary) -> bool:
	_model = model.duplicate(true)
	_kind = _canonical_kind(_model.get("kind", null))
	_edition = _canonical_edition(_model.get("edition", null))
	_model_valid = _validate_model(_model)
	_is_open = _model_valid
	_closed = false
	_pressed_ticket = -1
	_selected_number = 0
	_continued_emitted = false
	_source_frames.clear()
	_render()
	show()
	return _model_valid


## Install a caller-owned original-art resolver.  A dictionary, Callable, or
## object exposing ui()/texture() is accepted; animation providers may expose
## animation_frame()/frame()/animation().
func set_visuals(accessor: Variant) -> void:
	if accessor is Dictionary:
		_visual_accessor = (accessor as Dictionary).duplicate(true)
	else:
		_visual_accessor = accessor
	if not _model.is_empty():
		_render()


func set_visual_accessor(accessor: Variant) -> void:
	set_visuals(accessor)


func view_model() -> Dictionary:
	return _model.duplicate(true)


func model() -> Dictionary:
	return view_model()


func kind() -> String:
	return _kind


func is_model_valid() -> bool:
	return _model_valid


func is_open() -> bool:
	return _is_open and _model_valid and visible


func selected_number() -> int:
	return _selected_number


func source_art_available() -> bool:
	return _source_art_available


func has_source_art() -> bool:
	return source_art_available()


func source_frames() -> Dictionary:
	return _source_frames.duplicate(true)


func source_art_status() -> Dictionary:
	return {
		"available": _source_art_available,
		"kind": _kind,
		"edition": _edition,
		"frames": source_frames(),
	}


## Contract for the optional decoded FLIC provider.  The provider returns one
## RGBA Texture2D for a requested frame through
## animation_frame(edition, archive, resource, frame_index).  Palette index 0
## is already transparent for 14/17 and opaque for 16; the presenter never
## infers transparency from RGB values.
func source_animation_contract() -> Dictionary:
	return {
		14: {"origin": Vector2(8.0, 8.0), "size": Vector2(213.0, 68.0), "flags": 5, "interval_ms": 100, "loop": true, "index_zero_transparent": true},
		16: {"origin": Vector2(183.0, 75.0), "size": Vector2(275.0, 270.0), "flags": 8, "interval_ms": 50, "loop": false, "index_zero_transparent": false},
		17: {"origin": Vector2(205.0, 0.0), "size": Vector2(280.0, 480.0), "flags": 1, "interval_ms": 50, "loop": false, "index_zero_transparent": true},
	}


func get_source_animation_contract() -> Dictionary:
	return source_animation_contract()


func source_geometry() -> Dictionary:
	return {
		"canvas": REFERENCE_SIZE,
		"kind": _kind,
		"edition": _edition,
		"grid_origin": GRID_ORIGIN,
		"cell_size": CELL_SIZE,
		"ticket_count": TICKET_COUNT,
		"sold_transform": {"origin": SOLD_ORIGIN, "cell_size": SOLD_SIZE},
		"dealer_origin": Vector2(210.0, -5.0),
		"draw_animation_origins": {
			"drum": Vector2(183.0, 75.0),
			"red_ball": Vector2(205.0, 0.0),
		},
	}


func get_source_geometry() -> Dictionary:
	return source_geometry()


func source_hitboxes() -> Dictionary:
	return {
		"grid": Rect2(GRID_ORIGIN, Vector2(CELL_SIZE.x * 9.0, CELL_SIZE.y * 4.0)),
		"return": Rect2(Vector2.ZERO, REFERENCE_SIZE),
	}


func get_source_hitboxes() -> Dictionary:
	return source_hitboxes()


func ticket_at(point: Vector2) -> int:
	var local := point - GRID_ORIGIN
	if local.x < 0.0 or local.y < 0.0:
		return 0
	var column := int(floor(local.x / CELL_SIZE.x))
	var row := int(floor(local.y / CELL_SIZE.y))
	if column < 0 or column >= 9 or row < 0 or row >= 4:
		return 0
	var number := row * 9 + column + 1
	return number if number >= 1 and number <= TICKET_COUNT else 0


func is_ticket_sold(number: int) -> bool:
	if number < 1 or number > TICKET_COUNT:
		return false
	var tickets: Array = _model.get("tickets", [])
	if tickets.size() != TICKET_COUNT:
		return false
	return _slot_sold(tickets[number - 1])


func can_select_ticket(number: int) -> bool:
	if not _model_valid or _kind != "purchase" or not _is_open:
		return false
	if number < 1 or number > TICKET_COUNT or is_ticket_sold(number):
		return false
	var cash_value: Variant = _model.get("cash", -1)
	return _numeric_int(cash_value, TICKET_PRICE)


func continue_draw() -> bool:
	if not _model_valid or _kind != "draw" or not _is_open or _continued_emitted:
		return false
	_continued_emitted = true
	_is_open = false
	_closed = true
	hide()
	continued.emit()
	return true


func close_lottery() -> bool:
	if not _is_open or _closed:
		return false
	_closed = true
	_is_open = false
	_pressed_ticket = -1
	hide()
	cancelled.emit()
	return true


func close() -> bool:
	return close_lottery()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	accept_event()
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		if not mouse.pressed:
			close_lottery()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT or not _is_open:
		return
	if _kind == "purchase":
		var number := ticket_at(mouse.position)
		if mouse.pressed:
			_pressed_ticket = number
			# Source selection is immediate; a valid number is consumed on the
			# first left press, and there is exactly one ticket per encounter.
			if number > 0 and can_select_ticket(number):
				_select_ticket(number)
		else:
			_pressed_ticket = -1
	elif not mouse.pressed:
		continue_draw()


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree() or not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT and not mouse.pressed:
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		close_lottery()


func _select_ticket(number: int) -> bool:
	if not can_select_ticket(number):
		return false
	_selected_number = number
	_is_open = false
	_closed = true
	hide()
	ticket_selected.emit(number)
	return true


func _render() -> void:
	for child in get_children():
		child.free()
	_source_frames.clear()
	_source_art_available = false
	if not _model_valid:
		size = REFERENCE_SIZE
		custom_minimum_size = REFERENCE_SIZE
		_add_fallback_surface("資料格式無法顯示")
		return
	if _kind == "purchase":
		_render_purchase()
	else:
		_render_draw()


func _render_purchase() -> void:
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	_add_source_or_fallback("LotteryPurchaseBackground", 12, 0, Vector2.ZERO, REFERENCE_SIZE, "purchase_background")
	_add_source_or_fallback("LotteryDealer", 12, 1, Vector2(210.0, -5.0), SOURCE_LOGICAL_SIZES.dealer, "dealer")
	_add_source_or_fallback("LotteryAmountPlaque", 12, 9, Vector2(8.0, 8.0), SOURCE_LOGICAL_SIZES.amount, "amount")
	# Panel12 already contains the 01–36 legends.  Targets are transparent.
	for number in range(1, TICKET_COUNT + 1):
		var cell := number - 1
		var rect := Rect2(GRID_ORIGIN + Vector2(float(cell % 9) * CELL_SIZE.x, float(cell / 9) * CELL_SIZE.y), CELL_SIZE)
		var target := Button.new()
		target.name = "LotteryTicket%02d" % number
		target.position = rect.position
		target.size = rect.size
		target.custom_minimum_size = rect.size
		target.text = ""
		target.focus_mode = Control.FOCUS_NONE
		target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_set_button_transparent(target)
		target.gui_input.connect(_on_ticket_gui_input.bind(number))
		add_child(target)
		if is_ticket_sold(number):
			_add_sold_overlay(number, cell)
	if _selected_number > 0:
		_add_selected_overlay(_selected_number)
	var cash := _numeric_display(_model.get("cash", null))
	var jackpot := _numeric_display(_model.get("jackpot", null))
	_add_dynamic_label("LotteryCash", "現金 %s" % cash, Rect2(16, 38, 165, 24), 14, Color("#f5eab0"))
	_add_dynamic_label("LotteryJackpot", "獎金池 %s" % jackpot, Rect2(16, 8, 172, 28), 15, Color("#f5eab0"))
	_add_dynamic_label("LotteryPrompt", "選擇 01–36", Rect2(28, 246, 270, 24), 16, Color("#f5eab0"))
	_add_dynamic_label("LotteryPlayer", _player_name(int(_model.get("player_id", -1))), Rect2(420, 235, 180, 26), 15, Color("#f5eab0"))
	if _source_art_available:
		# The original background contains static legends; do not draw a second
		# title/number grid over it. Runtime values remain inspectable in nodes.
		for key in ["LotteryCash", "LotteryJackpot", "LotteryPrompt", "LotteryPlayer"]:
			var label := find_child(key, true, false) as Label
			if label != null:
				label.hide()


func _render_draw() -> void:
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	_add_source_or_fallback("LotteryDrawBackground", 15, 0, Vector2.ZERO, REFERENCE_SIZE, "draw_background")
	_add_source_or_fallback("LotteryDrawHeart", 15, 22, Vector2(40.0, 210.0), SOURCE_LOGICAL_SIZES.heart, "heart")
	_add_source_or_fallback("LotteryDrawBurst", 15, 23, Vector2(120.0, 98.0), SOURCE_LOGICAL_SIZES.burst, "burst")
	_add_source_or_fallback("LotteryDrawRedBurst", 15, 24, Vector2(147.0, 130.0), SOURCE_LOGICAL_SIZES.red_burst, "red_burst")
	# FLIC callers preserve palette index zero for Panel14/17 and use opaque
	# Panel16.  The accessor may supply a decoded first frame by this contract.
	_add_animation_or_placeholder("LotteryPoolAnimation", 14, Vector2(8.0, 8.0), Vector2(213.0, 68.0), 5)
	_add_animation_or_placeholder("LotteryDrumAnimation", 16, Vector2(183.0, 75.0), Vector2(275.0, 270.0), 8)
	_add_animation_or_placeholder("LotteryRedBallAnimation", 17, Vector2(205.0, 0.0), Vector2(280.0, 480.0), 1)
	var number := int(_model.get("number", 0))
	var winner: Variant = _model.get("winner_id", null)
	var winner_text: String = "無人中獎" if winner == null or int(winner) < 0 else _player_name(int(winner))
	_add_dynamic_label("LotteryDrawNumber", "開獎號碼 %02d" % number if number > 0 else "本期無開獎", Rect2(332, 266, 272, 34), 22, Color("#f5eab0"))
	_add_dynamic_label("LotteryWinner", "中獎者 %s" % winner_text, Rect2(332, 306, 272, 30), 18, Color("#fff2b4"))
	_add_dynamic_label("LotteryAward", "獎金 %s" % _numeric_display(_model.get("amount", 0)), Rect2(332, 342, 272, 30), 18, Color("#fff2b4"))
	_add_dynamic_label("LotteryPool", "獎金池 %s" % _numeric_display(_model.get("jackpot", 0)), Rect2(332, 378, 272, 28), 15, Color("#fff2b4"))
	var participants := _participant_text()
	_add_dynamic_label("LotteryParticipants", participants, Rect2(332, 410, 272, 44), 13, Color("#fff2b4"))
	_add_dynamic_label("LotteryContinue", "左鍵返回", Rect2(492, 447, 120, 24), 14, Color("#fff2b4"))
	if _source_art_available:
		for key in ["LotteryDrawNumber", "LotteryWinner", "LotteryAward", "LotteryPool", "LotteryParticipants", "LotteryContinue"]:
			var label := find_child(key, true, false) as Label
			if label != null:
				label.hide()


func _on_ticket_gui_input(event: InputEvent, number: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT and not mouse.pressed:
		close_lottery()
		return
	if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		_select_ticket(number)


func _add_sold_overlay(number: int, cell: int) -> void:
	var overlay := ColorRect.new()
	overlay.name = "LotterySold%02d" % number
	overlay.position = SOLD_ORIGIN + Vector2(float(cell % 9) * CELL_SIZE.x, float(cell / 9) * CELL_SIZE.y)
	overlay.size = SOLD_SIZE
	overlay.color = Color(0.12, 0.12, 0.12, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	move_child(overlay, 1)


func _add_selected_overlay(number: int) -> void:
	var cell := number - 1
	var overlay := ColorRect.new()
	overlay.name = "LotterySelected%02d" % number
	overlay.position = GRID_ORIGIN + Vector2(float(cell % 9) * CELL_SIZE.x + 2.0, float(cell / 9) * CELL_SIZE.y + 2.0)
	overlay.size = Vector2(60.0, 44.0)
	overlay.color = Color(0.95, 0.82, 0.18, 0.28)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)


func _add_source_or_fallback(node_name: String, resource: int, chunk: int, origin: Vector2, logical_size: Vector2, role: String) -> void:
	var visual: Variant = _resolve_chunk_visual(resource, chunk, "%s.Panel%d.chunk%d" % [_edition, resource, chunk])
	if visual is Texture2D:
		var item := _sprite(visual, logical_size)
		item.name = node_name
		item.position = origin
		add_child(item)
		_source_frames[role] = {"resource": resource, "chunk": chunk, "origin": origin, "size": logical_size}
		_source_art_available = _source_art_available or (role in ["purchase_background", "draw_background"])
		return
	if role in ["purchase_background", "draw_background"]:
		var fallback := ColorRect.new()
		fallback.name = node_name + "Fallback"
		fallback.position = origin
		fallback.size = logical_size
		fallback.color = Color("#173e49") if _kind == "purchase" else Color("#293b65")
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fallback)


func _add_animation_or_placeholder(node_name: String, resource: int, origin: Vector2, logical_size: Vector2, flags: int) -> void:
	var visual: Variant = _resolve_animation_frame(resource, 0, "%s.Panel%d.frame0" % [_edition, resource])
	if visual is Texture2D:
		var item := _sprite(visual, logical_size)
		item.name = node_name
		item.position = origin
		item.set_meta("source_resource", resource)
		item.set_meta("source_flags", flags)
		add_child(item)
		_source_frames["animation_%d" % resource] = {"resource": resource, "frame": 0, "origin": origin, "size": logical_size, "flags": flags, "available": true}
		return
	# Keep a named inert boundary when animation data is unavailable, so the
	# presenter never fakes a source frame from a solid RGB key.
	var placeholder := Control.new()
	placeholder.name = node_name + "Unavailable"
	placeholder.position = origin
	placeholder.size = logical_size
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placeholder.set_meta("source_resource", resource)
	placeholder.set_meta("source_flags", flags)
	add_child(placeholder)
	_source_frames["animation_%d" % resource] = {"resource": resource, "frame": 0, "origin": origin, "size": logical_size, "flags": flags, "available": false}


func _add_fallback_surface(message: String) -> void:
	var panel := Panel.new()
	panel.name = "LotteryUnavailable"
	panel.size = REFERENCE_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#203a3a")
	style.border_color = Color("#b9bd7d")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_add_dynamic_label("LotteryUnavailableMessage", message, Rect2(24, 24, 592, 34), 18, Color("#ffb3a4"))


func _add_dynamic_label(node_name: String, text_value: String, rect: Rect2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.name = node_name
	label.position = rect.position
	label.size = rect.size
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _sprite(texture: Texture2D, logical_size: Vector2) -> TextureRect:
	var item := TextureRect.new()
	item.texture = texture
	item.size = logical_size
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.stretch_mode = TextureRect.STRETCH_SCALE
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item


func _set_button_transparent(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, empty)


func _resolve_chunk_visual(resource: int, chunk: int, key: String) -> Variant:
	if _visual_accessor == null or _edition.is_empty():
		return null
	if _visual_accessor is Dictionary:
		var visuals: Dictionary = _visual_accessor
		for candidate in [key, "%s.Panel%d.%d" % [_edition, resource, chunk], "%s.Panel%d.chunk%d" % [_edition, resource, chunk], "%s.Panel%d/chunk%d" % [_edition, resource, chunk]]:
			var value: Variant = _resolve_dictionary_visual(visuals, candidate)
			if value != null:
				return value
		return null
	if _visual_accessor is Callable:
		return _visual_accessor.call(key)
	if _visual_accessor is Object and _visual_accessor.has_method("ui") and _visual_accessor.has_method("texture"):
		var frame: Variant = _visual_accessor.call("ui", _edition, "Panel", resource, chunk)
		if frame is Dictionary:
			var texture: Variant = _visual_accessor.call("texture", frame)
			if texture is Texture2D:
				return texture
	for method in ["texture", "get_texture", "visual", "resolve"]:
		if _visual_accessor is Object and _visual_accessor.has_method(method):
			var result: Variant = _visual_accessor.call(method, key)
			if result != null:
				return result
	return null


func _resolve_animation_frame(resource: int, frame_index: int, key: String) -> Variant:
	if _visual_accessor == null or _edition.is_empty():
		return null
	if _visual_accessor is Dictionary:
		var visuals: Dictionary = _visual_accessor
		for candidate in [key, "%s.Panel%d.frame%d" % [_edition, resource, frame_index], "%s.Panel%d.animation%d" % [_edition, resource, frame_index]]:
			var value: Variant = _resolve_dictionary_visual(visuals, candidate)
			if value != null:
				return value
		return null
	if _visual_accessor is Object:
		for method in ["animation_frame", "frame", "animation"]:
			if not _visual_accessor.has_method(method):
				continue
			var result: Variant
			if method == "animation_frame":
				result = _visual_accessor.call(method, _edition, "Panel", resource, frame_index)
			else:
				result = _visual_accessor.call(method, "%s.Panel%d.frame%d" % [_edition, resource, frame_index])
			if result is Texture2D:
				return result
	return _resolve_chunk_visual(resource, frame_index, key)


func _resolve_dictionary_visual(visuals: Dictionary, key: String) -> Variant:
	var aliases := [key, key.to_lower(), key.to_upper(), key.replace(".", "/"), key.replace(".", "_")]
	if key.begins_with("MultiverseJourney"):
		aliases.append(key.replace("MultiverseJourney", "MJ"))
	for alias in aliases:
		if visuals.has(alias):
			return visuals.get(alias)
	return null


func _canonical_kind(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var normalized := str(value).to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	if normalized in ["purchase", "buy", "ticket", "lottery_purchase"]:
		return "purchase"
	if normalized in ["draw", "result", "lottery_draw"]:
		return "draw"
	return ""


func _canonical_edition(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var normalized := str(value).to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	if normalized in ["game", "g"]:
		return "Game"
	if normalized in ["multiversejourney", "multiverse_journey", "mj", "journey"]:
		return "MultiverseJourney"
	return ""


func _validate_model(model: Dictionary) -> bool:
	if _kind not in ["purchase", "draw"] or _edition not in VALID_EDITIONS:
		return false
	var tickets_value: Variant = model.get("tickets", null)
	if typeof(tickets_value) != TYPE_ARRAY or (tickets_value as Array).size() != TICKET_COUNT:
		return false
	for slot in tickets_value as Array:
		if not _valid_ticket_slot(slot):
			return false
	if not _valid_nonnegative_integer(model.get("jackpot", null)):
		return false
	if typeof(model.get("players", null)) != TYPE_ARRAY:
		return false
	if _kind == "purchase":
		return _valid_nonnegative_integer(model.get("cash", null)) and _valid_nonnegative_integer(model.get("player_id", null))
	if not _valid_integer_in_range(model.get("number", null), 0, TICKET_COUNT):
		return false
	if not _valid_nonnegative_integer(model.get("amount", null)):
		return false
	var winner: Variant = model.get("winner_id", null)
	return winner == null or _valid_integer_in_range(winner, -1, 2147483647)


func _valid_ticket_slot(value: Variant) -> bool:
	if value == null:
		return true
	if typeof(value) == TYPE_BOOL:
		return false
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		var number := float(value)
		return is_finite(number) and floor(number) == number and number >= -1.0
	return false


func _valid_nonnegative_integer(value: Variant) -> bool:
	return _valid_integer_in_range(value, 0, 1000000000000)


func _valid_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_BOOL or typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and floor(number) == number and number >= float(minimum) and number <= float(maximum)


func _numeric_int(value: Variant, minimum: int) -> bool:
	return _valid_integer_in_range(value, minimum, 1000000000000)


func _slot_sold(value: Variant) -> bool:
	if value == null:
		return false
	if typeof(value) in [TYPE_INT, TYPE_FLOAT] and typeof(value) != TYPE_BOOL:
		return float(value) > 0.0
	return true


func _numeric_display(value: Variant) -> String:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or typeof(value) == TYPE_BOOL:
		return "—"
	var number := float(value)
	if not is_finite(number) or floor(number) != number:
		return "—"
	return _group_integer(int(number))


func _group_integer(value: int) -> String:
	var text := str(value)
	var sign := ""
	if text.begins_with("-"):
		sign = "-"
		text = text.substr(1)
	var grouped := ""
	while text.length() > 3:
		grouped = "," + text.right(3) + grouped
		text = text.left(text.length() - 3)
	return sign + text + grouped


func _player_name(player_id: int) -> String:
	var players: Array = _model.get("players", [])
	for player in players:
		if not player is Dictionary:
			continue
		var candidate: Variant = player.get("id", player.get("player_id", null))
		if _valid_integer_in_range(candidate, -2147483648, 2147483647) and int(candidate) == player_id:
			var name_value: Variant = player.get("name", player.get("display_name", ""))
			if typeof(name_value) == TYPE_STRING and not str(name_value).is_empty():
				return str(name_value)
	return "玩家 %d" % player_id if player_id >= 0 else "—"


func _participant_text() -> String:
	var tickets: Array = _model.get("tickets", [])
	var names: Array[String] = []
	for index in range(mini(TICKET_COUNT, tickets.size())):
		if not _slot_sold(tickets[index]):
			continue
		var owner := int(tickets[index]) if typeof(tickets[index]) in [TYPE_INT, TYPE_FLOAT] else -1
		var name := _player_name(owner)
		names.append("%02d %s" % [index + 1, name])
		if names.size() >= 6:
			break
	if names.is_empty():
		return "參與者：無"
	return "參與者：" + "、".join(names)
