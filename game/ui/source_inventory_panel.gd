extends Control
class_name RichmanSourceInventoryPanel

## Source-shaped inventory presenter for S19.
##
## The host supplies a detached inventory snapshot.  This control only maps
## source mouse gestures to a source ID; it never consumes a card/tool,
## changes the equipped vehicle, or calls the game core.

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const PANEL_ORIGIN := Vector2(14.0, 130.0)
const PANEL_SIZE := Vector2(412.0, 180.0)
const GRID_ORIGIN := Vector2(19.0, 135.0)
const CELL_SIZE := Vector2(80.0, 56.0)
const GRID_COLUMNS := 5
const GRID_ROWS := 3
const SLOT_COUNT := GRID_COLUMNS * GRID_ROWS
const VALID_EDITIONS := ["Game", "MultiverseJourney"]
const VALID_MODES := ["cards", "tools"]
const VALID_VEHICLES := ["walking", "motorcycle", "car", "engineering"]
const ARCHIVE := "Panel"
const SOURCE_RESOURCE := 11
const VEHICLE_SOURCE_ID := 14
const VEHICLE_SLOT := 14
const VEHICLE_ORIGIN := Vector2(325.0, 117.0)
const VEHICLE_CHUNKS := {"motorcycle": 15, "car": 16}
const SOURCE_TEXT := Color("#ffffff")
const SOURCE_OUTLINE := Color("#101010")
const FALLBACK_PANEL_COLOR := Color("#202c3a")
const FALLBACK_CELL_COLOR := Color("#42566a")
const SOURCE_FONT_SIZE := 20

signal selected(source_id: int)
signal cancelled

var _model: Dictionary = {}
var _visual_accessor: Variant = null
var _model_valid := false
var _edition := ""
var _mode := ""
var _vehicle := "walking"
var _is_open := false
var _closed := false
var _pressed_source_id := 0
var _pressed_slot := -1
var _slot_source_ids: Array[int] = []
var _slot_records: Array[Dictionary] = []
var _source_art_available := false
var _source_art_status: Dictionary = {}
var _source_frames: Dictionary = {}
var _surface: Control
var _built := false


func _init() -> void:
	name = "SourceInventoryPanel"
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build()
	# A host may instantiate the child before it has a snapshot.  Keep the
	# unconfigured control hidden so it cannot intercept ordinary toolbar input.
	hide()


func configure(model: Dictionary) -> bool:
	_model = model.duplicate(true)
	_edition = str(_model.get("edition", ""))
	_mode = str(_model.get("mode", ""))
	_vehicle = str(_model.get("vehicle", "walking"))
	_model_valid = _validate_model(_model)
	_slot_source_ids.clear()
	_slot_records.clear()
	_pressed_source_id = 0
	_pressed_slot = -1
	_closed = false
	_is_open = _model_valid
	_rebuild_mapping()
	_render()
	if _model_valid:
		show()
	else:
		hide()
	return _model_valid


func set_visual_accessor(accessor: Variant) -> void:
	_visual_accessor = accessor
	_render()


func is_open() -> bool:
	return _is_open and _model_valid and visible


func close() -> bool:
	if not is_open():
		return false
	_is_open = false
	_closed = true
	_pressed_source_id = 0
	_pressed_slot = -1
	hide()
	cancelled.emit()
	return true


func view_model() -> Dictionary:
	return _model.duplicate(true)


func source_art_available() -> bool:
	return _source_art_available


func has_source_art() -> bool:
	return source_art_available()


func source_art_status() -> Dictionary:
	return _source_art_status.duplicate(true)


func source_frames() -> Dictionary:
	return _source_frames.duplicate(true)


func source_geometry() -> Dictionary:
	return {
		"canvas": REFERENCE_SIZE,
		"edition": _edition,
		"mode": _mode,
		"panel_origin": PANEL_ORIGIN,
		"panel_size": PANEL_SIZE,
		"grid_origin": GRID_ORIGIN,
		"cell_size": CELL_SIZE,
		"columns": GRID_COLUMNS,
		"rows": GRID_ROWS,
		"slot_count": SLOT_COUNT,
		"grid_hitbox": Rect2(GRID_ORIGIN, Vector2(CELL_SIZE.x * GRID_COLUMNS, CELL_SIZE.y * GRID_ROWS)),
		"vehicle_slot": VEHICLE_SLOT,
		"vehicle_origin": VEHICLE_ORIGIN,
		"vehicle_source_id": VEHICLE_SOURCE_ID,
		"card_text_origin": PANEL_ORIGIN + Vector2(45.0, 33.0),
		"tool_icon_center": PANEL_ORIGIN + Vector2(29.0, 33.0),
		"tool_quantity_origin": PANEL_ORIGIN + Vector2(79.0, 23.0),
		"pressed_cell": Rect2(Vector2(1.0, 1.0), Vector2(78.0, 54.0)),
	}


func slot_source_id(slot: int) -> int:
	if slot < 0 or slot >= _slot_source_ids.size():
		return 0
	return _slot_source_ids[slot]


func source_at(point: Vector2) -> int:
	var slot := _slot_at(point)
	return slot_source_id(slot)


func source_hitboxes() -> Dictionary:
	return {"grid": Rect2(GRID_ORIGIN, Vector2(CELL_SIZE.x * GRID_COLUMNS, CELL_SIZE.y * GRID_ROWS))}


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		if not mouse.pressed:
			_close_as_cancel()
		accept_event()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if not is_open():
		accept_event()
		return
	if mouse.pressed:
		_begin_left_press(mouse.position)
	else:
		_commit_left_release()
	accept_event()


func _input(event: InputEvent) -> void:
	# Source right-up cancels from anywhere in the modal, including outside the
	# 640x480 panel control.  A closed panel ignores stale release events.
	if not is_open() or not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT and not mouse.pressed:
		get_viewport().set_input_as_handled()
		_close_as_cancel()


func _begin_left_press(point: Vector2) -> void:
	_pressed_slot = _slot_at(point)
	_pressed_source_id = slot_source_id(_pressed_slot)
	# Empty entries and outside presses reset the source's latched selection.
	if _pressed_source_id <= 0:
		_pressed_source_id = 0
		_pressed_slot = -1
	_render()


func _commit_left_release() -> void:
	var source_id := _pressed_source_id
	_pressed_source_id = 0
	_pressed_slot = -1
	_render()
	if source_id <= 0 or not is_open():
		return
	_is_open = false
	_closed = true
	hide()
	selected.emit(source_id)


func _close_as_cancel() -> void:
	if not is_open():
		return
	_is_open = false
	_closed = true
	_pressed_source_id = 0
	_pressed_slot = -1
	_render()
	hide()
	cancelled.emit()


func _slot_at(point: Vector2) -> int:
	var local := point - GRID_ORIGIN
	# The source accepts x in [19,419), y in [135,303).
	if local.x < 0.0 or local.y < 0.0 or local.x >= CELL_SIZE.x * GRID_COLUMNS or local.y >= CELL_SIZE.y * GRID_ROWS:
		return -1
	var column := int(floor(local.x / CELL_SIZE.x))
	var row := int(floor(local.y / CELL_SIZE.y))
	return row * GRID_COLUMNS + column


func _rebuild_mapping() -> void:
	_slot_source_ids.resize(SLOT_COUNT)
	_slot_source_ids.fill(0)
	_slot_records.resize(SLOT_COUNT)
	_slot_records.fill({})
	if not _model_valid:
		return
	if _mode == "cards":
		var cards: Array = _model.get("cards", [])
		for index in range(mini(cards.size(), SLOT_COUNT)):
			var record: Dictionary = cards[index]
			_slot_source_ids[index] = int(record.get("source_id", 0))
			_slot_records[index] = record.duplicate(true)
		return
	var tools: Array = _model.get("tools", [])
	# Renderer order is source tool ID order, independent of caller array order.
	var by_source: Dictionary = {}
	for value in tools:
		var record: Dictionary = value
		by_source[int(record.get("source_id", 0))] = record
	var slot := 0
	for source_id in range(1, 14):
		if not by_source.has(source_id) or int(by_source[source_id].get("count", 0)) <= 0:
			continue
		if slot >= SLOT_COUNT:
			break
		_slot_source_ids[slot] = source_id
		_slot_records[slot] = (by_source[source_id] as Dictionary).duplicate(true)
		slot += 1
	if _vehicle in ["motorcycle", "car"]:
		_slot_source_ids[VEHICLE_SLOT] = VEHICLE_SOURCE_ID
		_slot_records[VEHICLE_SLOT] = {"source_id": VEHICLE_SOURCE_ID, "name": _vehicle}


func _validate_model(model: Dictionary) -> bool:
	for required in ["mode", "edition", "cards", "tools", "vehicle"]:
		if not model.has(required):
			return false
	if str(model.get("edition", "")) not in VALID_EDITIONS or str(model.get("mode", "")) not in VALID_MODES:
		return false
	var vehicle := str(model.get("vehicle", "walking"))
	if vehicle not in VALID_VEHICLES:
		return false
	if not model.get("cards", []) is Array or not model.get("tools", []) is Array:
		return false
	var cards: Array = model.get("cards", [])
	if cards.size() > SLOT_COUNT:
		return false
	var seen_cards: Dictionary = {}
	for value in cards:
		if not value is Dictionary:
			return false
		var source_id_value: Variant = value.get("source_id", null)
		if not _is_integral(source_id_value):
			return false
		var source_id := int(source_id_value)
		if source_id < 1 or source_id > 30 or not value.has("name") or not value.get("name") is String:
			return false
		# Duplicates are source-faithful and intentionally accepted.
		seen_cards[source_id] = true
	var tools: Array = model.get("tools", [])
	var seen_tools: Dictionary = {}
	for value in tools:
		if not value is Dictionary:
			return false
		var source_id_value: Variant = value.get("source_id", null)
		var count_value: Variant = value.get("count", null)
		if not _is_integral(source_id_value) or not _is_integral(count_value):
			return false
		var source_id := int(source_id_value)
		var count := int(count_value)
		if source_id < 1 or source_id > 13 or count < 0 or not value.has("name") or not value.get("name") is String or seen_tools.has(source_id):
			return false
		seen_tools[source_id] = true
	return true


func _is_integral(value: Variant) -> bool:
	if not value is int and not value is float:
		return false
	return is_finite(float(value)) and floor(float(value)) == float(value)


func _build() -> void:
	if _built:
		return
	_built = true
	_surface = Control.new()
	_surface.name = "SourceInventorySurface"
	_surface.position = Vector2.ZERO
	_surface.size = REFERENCE_SIZE
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)


func _render() -> void:
	if not _built:
		return
	for child in _surface.get_children():
		child.free()
	_source_frames.clear()
	_source_art_status.clear()
	_source_art_available = false
	if not _model_valid:
		return
	_draw_inventory()


func _draw_inventory() -> void:
	var background_chunk := 0 if _mode == "cards" else 1
	var background := _resolve_chunk(background_chunk)
	_source_frames["background"] = (background.get("frame", {}) as Dictionary).duplicate(true)
	_source_art_status["background"] = background.get("texture") is Texture2D
	_add_art(background, "SourceInventoryBackground", PANEL_ORIGIN, PANEL_SIZE, background_chunk)
	var art_ok := bool(_source_art_status["background"])
	for slot in range(SLOT_COUNT):
		var source_id := _slot_source_ids[slot]
		if source_id <= 0:
			continue
		var record: Dictionary = _slot_records[slot]
		var cell := _cell_origin(slot)
		if _mode == "tools":
			var chunk := source_id + 1 if source_id != VEHICLE_SOURCE_ID else _vehicle_chunk()
			var icon := _resolve_chunk(chunk)
			_source_frames["slot_%d" % slot] = (icon.get("frame", {}) as Dictionary).duplicate(true)
			_source_art_status["slot_%d" % slot] = icon.get("texture") is Texture2D
			art_ok = art_ok and bool(_source_art_status["slot_%d" % slot])
			var icon_rect := _icon_rect(icon, cell, slot)
			_add_art(icon, "SourceInventoryIcon%d" % slot, icon_rect.position, icon_rect.size, chunk)
		if _mode == "cards":
			var card_origin := PANEL_ORIGIN + Vector2(45.0 + float(slot % GRID_COLUMNS) * CELL_SIZE.x, 33.0 + float(slot / GRID_COLUMNS) * CELL_SIZE.y)
			var label := _make_source_text("SourceInventoryCard%d" % slot, str(record.get("name", "")), card_origin, Vector2(76.0, 24.0), SOURCE_FONT_SIZE, true)
			label.set_meta("source_id", source_id)
		elif slot != VEHICLE_SLOT:
			var quantity_origin := PANEL_ORIGIN + Vector2(79.0 + float(slot % GRID_COLUMNS) * CELL_SIZE.x, 23.0 + float(slot / GRID_COLUMNS) * CELL_SIZE.y)
			var quantity := _make_source_text("SourceInventoryQuantity%d" % slot, str(int(record.get("count", 0))), quantity_origin, Vector2(28.0, 24.0), SOURCE_FONT_SIZE)
			quantity.set_meta("source_id", source_id)
	if _mode == "tools" and _vehicle in ["motorcycle", "car"]:
		# Vehicle art is anchored at the source's fixed screen-local position.
		_source_frames["vehicle"] = _source_frames.get("slot_%d" % VEHICLE_SLOT, {}).duplicate(true)
	if _pressed_slot >= 0 and _pressed_source_id > 0:
		var pressed := Panel.new()
		pressed.name = "SourceInventoryPressedCell"
		pressed.position = _cell_origin(_pressed_slot) + Vector2(1.0, 1.0)
		pressed.size = Vector2(78.0, 54.0)
		pressed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		style.border_color = SOURCE_OUTLINE
		style.border_width_top = 1
		style.border_width_left = 1
		for child in _surface.get_children():
			if str(child.name) in ["SourceInventoryCard%d" % _pressed_slot, "SourceInventoryIcon%d" % _pressed_slot, "SourceInventoryQuantity%d" % _pressed_slot]:
				child.position += Vector2.ONE
		pressed.add_theme_stylebox_override("panel", style)
		_surface.add_child(pressed)
	_source_art_available = art_ok
	if not _source_art_available:
		_make_centered_label("SourceInventoryArtFallback", "來源畫面素材未載入", Vector2(220.0, 320.0), Vector2(200.0, 20.0), 13, Color("#b6d5cf"))


func _cell_origin(slot: int) -> Vector2:
	return GRID_ORIGIN + Vector2(float(slot % GRID_COLUMNS) * CELL_SIZE.x, float(slot / GRID_COLUMNS) * CELL_SIZE.y)


func _vehicle_chunk() -> int:
	return int(VEHICLE_CHUNKS.get(_vehicle, 15))


func _icon_rect(result: Dictionary, cell: Vector2, slot: int) -> Rect2:
	if slot == VEHICLE_SLOT:
		return Rect2(PANEL_ORIGIN + VEHICLE_ORIGIN, CELL_SIZE)
	var frame: Variant = result.get("frame", {})
	var logical: Variant = frame.get("logical", {}) if frame is Dictionary else {}
	if logical is Dictionary and logical.has("width") and logical.has("height"):
		var size := Vector2(float(logical.get("width", 40.0)), float(logical.get("height", 34.0)))
		# Caller x=45-16+80*col; the drawing helper subtracts the
		# source graph anchor, independently of texture dimensions.
		var anchor := Vector2(float(logical.get("anchor_x", size.x / 2.0)), float(logical.get("anchor_y", size.y / 2.0)))
		var source_origin := PANEL_ORIGIN + Vector2(29.0 + float(slot % GRID_COLUMNS) * CELL_SIZE.x, 33.0 + float(slot / GRID_COLUMNS) * CELL_SIZE.y)
		return Rect2(source_origin - anchor, size)
	var fallback_center := PANEL_ORIGIN + Vector2(29.0 + float(slot % GRID_COLUMNS) * CELL_SIZE.x, 33.0 + float(slot / GRID_COLUMNS) * CELL_SIZE.y)
	return Rect2(fallback_center - Vector2(20.0, 17.0), Vector2(40.0, 34.0))


func _add_art(result: Dictionary, node_name: String, origin: Vector2, logical_size: Vector2, chunk: int) -> TextureRect:
	var texture: Variant = result.get("texture", null)
	if not texture is Texture2D:
		var fallback := ColorRect.new()
		fallback.name = node_name + "Fallback"
		fallback.position = origin
		fallback.size = logical_size
		fallback.color = FALLBACK_PANEL_COLOR if chunk <= 1 else FALLBACK_CELL_COLOR
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_surface.add_child(fallback)
		return null
	var art := TextureRect.new()
	art.name = node_name
	art.position = origin
	art.size = logical_size
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_meta("source_chunk", chunk)
	art.set_meta("source_frame", (result.get("frame", {}) as Dictionary).duplicate(true))
	_surface.add_child(art)
	return art


func _make_centered_label(node_name: String, text_value: String, center: Vector2, logical_size: Vector2, font_size: int, color := SOURCE_TEXT) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.position = Vector2(center.x - logical_size.x / 2.0, center.y - logical_size.y / 2.0)
	label.size = logical_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(label)
	return label


func _make_source_text(node_name: String, text_value: String, origin: Vector2, logical_size: Vector2, font_size: int, centered := false) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.size = logical_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", SOURCE_TEXT)
	label.add_theme_color_override("font_outline_color", SOURCE_OUTLINE)
	label.add_theme_constant_override("outline_size", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if centered else VERTICAL_ALIGNMENT_TOP
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(label)
	label.size = logical_size.max(label.get_combined_minimum_size())
	label.position = origin - (label.size / 2.0 if centered else Vector2(label.size.x, 0.0))
	return label


func _resolve_chunk(chunk: int) -> Dictionary:
	# Same bounded resolver contract as OriginalVisuals and the test accessor.
	if not _visual_accessor is Object or not _visual_accessor.has_method("ui") or not _visual_accessor.has_method("texture"):
		return {"frame": {}, "texture": null}
	var record: Variant = _visual_accessor.ui(_edition, ARCHIVE, SOURCE_RESOURCE, chunk)
	if not record is Dictionary or record.is_empty():
		return {"frame": {}, "texture": null}
	var texture: Variant = _visual_accessor.texture(record)
	return {"frame": record.duplicate(true), "texture": texture if texture is Texture2D else null}
