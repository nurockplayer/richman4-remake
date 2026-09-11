extends Control
class_name RichmanSourceShopPanel

## Source-shaped S20 shop presenter for a detached host-supplied visit snapshot.

const CANVAS := Vector2(640, 480)
const PANEL10 := 10
const PANEL11 := 11
const HELD_ORIGIN := Vector2(227, 293)
const GRID_ORIGIN := Vector2(232, 298)
const CELL := Vector2(80, 56)
const TAB_RECT := Rect2(542, 13, 86, 86)
const EXIT_RECT := Rect2(556, 246, 81, 41)
const VALID_EDITIONS := ["Game", "MultiverseJourney"]
const VALID_MODES := ["cards", "tools"]
const GRID_COLUMNS := 5
const GRID_ROWS := 3
const SLOT_COUNT := GRID_COLUMNS * GRID_ROWS
const CARD_COUNT := 30
const TOOL_COUNT := 13
const TOOL_OFFER_COUNT := 8
const MAX_TOOL_QUANTITY := 9
const CATALOG_CHUNKS := {"cards": 1, "tools": 17}
const MERCHANT_READY_CHUNKS := {"cards": 2, "tools": 18}
const MERCHANT_CLOSING_CHUNKS := {"cards": 3, "tools": 19}
const TAB_NORMAL_CHUNKS := {"cards": 13, "tools": 29}
const TAB_PRESSED_CHUNKS := {"cards": 14, "tools": 30}
const POINTS_CHUNK := 37
const EXIT_NORMAL_CHUNK := 35
const EXIT_PRESSED_CHUNK := 36
const CATALOG_ORIGIN := Vector2(5, 10)
const POINTS_ORIGIN := Vector2(230, 246)
const POINTS_ANCHOR := Vector2(310, 257)
const MERCHANT_CENTER := Vector2(320, 240)
const SOURCE_TEXT := Color("#ffffff")
const SOURCE_OUTLINE := Color("#101010")
const FALLBACK_PANEL_COLOR := Color("#202c3a")
const FALLBACK_CELL_COLOR := Color("#42566a")
const SOURCE_FONT_SIZE := 20
const SOURCE_FONT_FLAGS := 3

signal action_requested(action: String, params: Dictionary)
signal cancelled

var _model: Dictionary = {}
var _visual_accessor: Variant = null
var _edition := ""
var _mode := ""
var _is_open := false
var _model_valid := false
var _pressed_mode := false
var _pressed_exit := false
var _closing := false
var _source_art_available := false
var _source_art_status := {}
var _source_frames := {}
var _surface: Control

func _init() -> void:
	name = "SourceShopPanel"
	size = CANVAS
	custom_minimum_size = CANVAS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_surface = Control.new()
	_surface.name = "SourceShopSurface"
	_surface.size = CANVAS
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)
	hide()

func configure(model: Dictionary) -> bool:
	_model = model.duplicate(true)
	_edition = str(_model.get("edition", ""))
	_mode = str(_model.get("mode", ""))
	_model_valid = _validate(_model)
	# A pending owned-venue gift is still a visible modal visit.  The host
	# advances it after the source message lifetime; this presenter only gates
	# trading and mode changes until ready becomes true.
	_is_open = _model_valid
	_pressed_mode = false
	_pressed_exit = false
	_closing = false
	_render()
	if _is_open: show()
	else: hide()
	return _model_valid

func set_visual_accessor(accessor: Variant) -> void:
	_visual_accessor = accessor.duplicate(true) if accessor is Dictionary else accessor
	_render()

func set_visuals(accessor: Variant) -> void:
	set_visual_accessor(accessor)

func view_model() -> Dictionary:
	var result := _model.duplicate(true)
	result["mode"] = _mode
	return result

func is_open() -> bool:
	return _is_open and _model_valid and visible

func close() -> bool:
	if not is_open(): return false
	_is_open = false
	_pressed_mode = false
	_pressed_exit = false
	_closing = false
	hide()
	cancelled.emit()
	return true

func source_art_available() -> bool:
	return _source_art_available

func has_source_art() -> bool:
	return source_art_available()

func source_art_status() -> Dictionary:
	return _source_art_status.duplicate(true)

func source_frames() -> Dictionary:
	return _source_frames.duplicate(true)

func source_geometry() -> Dictionary:
	return {"canvas": CANVAS, "edition": _edition, "mode": _mode, "held_origin": HELD_ORIGIN, "held_grid_origin": GRID_ORIGIN, "held_cell": CELL, "columns": GRID_COLUMNS, "rows": GRID_ROWS, "tab": TAB_RECT, "exit": EXIT_RECT, "catalog_origin": CATALOG_ORIGIN, "points_origin": POINTS_ORIGIN, "points_anchor": POINTS_ANCHOR, "merchant_center": MERCHANT_CENTER, "card_offer": Rect2(14, 81, 202, 360), "tool_offer": Rect2(12, 80, 202, 384), "merchant_ready_chunk": _merchant_ready_chunk(), "merchant_closing_chunk": _merchant_closing_chunk(), "tab_normal_chunk": _tab_normal_chunk(), "tab_pressed_chunk": _tab_pressed_chunk(), "points_chunk": POINTS_CHUNK, "exit_chunk": EXIT_NORMAL_CHUNK, "exit_pressed_chunk": EXIT_PRESSED_CHUNK}

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		if not mouse.pressed: _cancel()
		accept_event()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT or not is_open():
		accept_event()
		return
	if mouse.pressed: _press(mouse.position)
	else: _release()
	accept_event()

func _input(event: InputEvent) -> void:
	if is_open() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		get_viewport().set_input_as_handled()
		_cancel()

func _press(point: Vector2) -> void:
	var ready := _is_ready_state()
	_pressed_mode = ready and TAB_RECT.has_point(point)
	_pressed_exit = EXIT_RECT.has_point(point)
	_closing = _pressed_exit
	if _pressed_mode or _pressed_exit:
		_render()
		return
	if not ready: return
	var offer := _offer_index(point)
	if offer >= 0 and _offer_source_id(offer) > 0:
		action_requested.emit("buy_item", {"item_kind": "card" if _mode == "cards" else "tool", "source_id": _offer_source_id(offer), "offer_index": offer, "visit_id": int(_model.get("visit_id", -1))})
		return
	var held := _held_index(point)
	if held >= 0 and _held_source_id(held) > 0:
		action_requested.emit("sell_item", {"item_kind": "card" if _mode == "cards" else "tool", "source_id": _held_source_id(held), "held_index": held, "visit_id": int(_model.get("visit_id", -1))})

func _release() -> void:
	if _pressed_mode:
		_pressed_mode = false
		_mode = "tools" if _mode == "cards" else "cards"
		_model["mode"] = _mode
		_render()
	elif _pressed_exit:
		_pressed_exit = false
		_closing = false
		_cancel()

func _cancel() -> void:
	if not is_open(): return
	_is_open = false
	_pressed_mode = false
	_pressed_exit = false
	_closing = false
	hide()
	cancelled.emit()

func _offer_index(point: Vector2) -> int:
	if _mode == "cards":
		if point.x < 14 or point.x > 215 or point.y < 81 or point.y >= 441: return -1
		var index := int(floor((point.y - 81) / 24.0))
		return index if index >= 0 and index < 15 else -1
	if point.x < 12 or point.x > 213 or point.y < 80 or point.y >= 464: return -1
	var tool_index := int(floor((point.y - 80) / 48.0))
	return tool_index if tool_index >= 0 and tool_index < 8 else -1

func _held_index(point: Vector2) -> int:
	if not (point.x > 232 and point.x < 632 and point.y > 298 and point.y < 466): return -1
	var index := int(floor((point.y - 298) / 56.0)) * 5 + int(floor((point.x - 232) / 80.0))
	var held := _held_records()
	return index if index >= 0 and index < held.size() else -1

func _offer_source_id(index: int) -> int:
	var offers: Array = _model.get("card_offers", []) if _mode == "cards" else _model.get("tool_offers", [])
	if index < 0 or index >= offers.size() or not offers[index] is Dictionary: return 0
	return int(offers[index].get("source_id", 0))

func _held_source_id(index: int) -> int:
	var held := _held_records()
	return int(held[index].get("source_id", 0)) if index >= 0 and index < held.size() else 0

func _held_records() -> Array:
	if _mode == "cards": return _model.get("cards", []) if _model.get("cards", []) is Array else []
	var result: Array = []
	var tools: Array = _model.get("tools", [])
	for value in tools:
		if value is Dictionary and int(value.get("count", 0)) > 0: result.append(value)
	return result

func _is_ready_state() -> bool:
	return bool(_model.get("ready", false))

func _validate(model: Dictionary) -> bool:
	for key in ["edition", "visit_id", "mode", "card_offers", "tool_offers", "cards", "tools", "points", "ready", "feedback", "gift_message"]:
		if not model.has(key): return false
	if str(model.get("edition", "")) not in VALID_EDITIONS or str(model.get("mode", "")) not in VALID_MODES or not model.get("ready") is bool: return false
	if not _is_integral(model.get("visit_id")) or not _is_integral(model.get("points")): return false
	if not model.get("card_offers") is Array or not model.get("tool_offers") is Array or not model.get("cards") is Array or not model.get("tools") is Array: return false
	if model.card_offers.size() > 15 or model.tool_offers.size() > TOOL_OFFER_COUNT or model.cards.size() > SLOT_COUNT: return false
	for value in model.card_offers:
		if not value is Dictionary: return false
		if value.is_empty(): continue
		if not _valid_record(value, 1, CARD_COUNT): return false
	for value in model.tool_offers:
		if not value is Dictionary: return false
		if value.is_empty(): continue
		if not _valid_record(value, 1, TOOL_OFFER_COUNT): return false
	var seen_tools: Dictionary = {}
	for value in model.cards:
		if not value is Dictionary: return false
		if not _valid_record(value, 1, CARD_COUNT): return false
	for value in model.tools:
		if not value is Dictionary or not _valid_record(value, 1, TOOL_COUNT): return false
		var source_id := int(value.get("source_id", 0))
		var count_value: Variant = value.get("count", null)
		var capacity := MAX_TOOL_QUANTITY + (1 if source_id in [5,6] else 0) # Accepted returned-vehicle storage exception.
		if not _is_integral(count_value) or int(count_value) < 0 or int(count_value) > capacity or seen_tools.has(source_id): return false
		seen_tools[source_id] = true
	return true

func _valid_record(value: Dictionary, minimum: int, maximum: int) -> bool:
	var source_id: Variant = value.get("source_id", null)
	return _is_integral(source_id) and int(source_id) >= minimum and int(source_id) <= maximum and value.get("name") is String

func _is_integral(value: Variant) -> bool:
	if not value is int and not value is float: return false
	return is_finite(float(value)) and floor(float(value)) == float(value)

func _render() -> void:
	for child in _surface.get_children(): child.free()
	_source_art_available = false
	_source_art_status.clear()
	_source_frames.clear()
	if not _model_valid: return
	var bg_chunk := 0 if _mode == "cards" else 16
	var bg := _resolve("Panel", PANEL10, bg_chunk)
	_source_frames["background"] = bg.get("frame", {}).duplicate(true)
	_source_art_status["background"] = bg.get("texture") is Texture2D
	_add_art(bg, "SourceShopPanel10", Vector2.ZERO, Vector2(640, 480), bg_chunk)
	var merchant_chunk := _merchant_closing_chunk() if _closing else _merchant_ready_chunk()
	var merchant := _resolve("Panel", PANEL10, merchant_chunk)
	var merchant_role := "closing" if _closing else "merchant"
	_source_frames[merchant_role] = merchant.get("frame", {}).duplicate(true)
	_source_art_status[merchant_role] = merchant.get("texture") is Texture2D
	_add_anchored_art(merchant, "SourceShopMerchantClosing" if _closing else "SourceShopMerchant", MERCHANT_CENTER, merchant_chunk)
	var catalog_chunk: int = int(CATALOG_CHUNKS.get(_mode, 1))
	var catalog := _resolve("Panel", PANEL10, catalog_chunk)
	_source_frames["catalog"] = catalog.get("frame", {}).duplicate(true)
	_source_art_status["catalog"] = catalog.get("texture") is Texture2D
	_add_art(catalog, "SourceShopCatalog", CATALOG_ORIGIN, _logical_size(catalog, Vector2(222, 462)), catalog_chunk)
	var tab_chunk := _tab_pressed_chunk() if _pressed_mode else _tab_normal_chunk()
	var tab := _resolve("Panel", PANEL10, tab_chunk)
	var tab_role := "tab_pressed" if _pressed_mode else "tab"
	_source_frames[tab_role] = tab.get("frame", {}).duplicate(true)
	_source_art_status[tab_role] = tab.get("texture") is Texture2D
	_add_art(tab, "SourceShopTabPressed" if _pressed_mode else "SourceShopTab", TAB_RECT.position, _logical_size(tab, Vector2(90, 40)), tab_chunk)
	var exit_chunk := EXIT_PRESSED_CHUNK if _pressed_exit else EXIT_NORMAL_CHUNK
	var exit := _resolve("Panel", PANEL10, exit_chunk)
	_source_frames["exit"] = exit.get("frame", {}).duplicate(true)
	_source_art_status["exit"] = exit.get("texture") is Texture2D
	_add_art(exit, "SourceShopExit", EXIT_RECT.position, _logical_size(exit, Vector2(80, 40)), exit_chunk)
	var held_chunk := 0 if _mode == "cards" else 1
	var held := _resolve("Panel", PANEL11, held_chunk)
	_source_frames["held"] = held.get("frame", {}).duplicate(true)
	_source_art_status["held"] = held.get("texture") is Texture2D
	_add_art(held, "SourceShopHeldPanel11", HELD_ORIGIN, Vector2(412, 180), held_chunk)
	_source_art_available = bool(_source_art_status.background) and bool(_source_art_status.held)
	var points := _resolve("Panel", PANEL10, POINTS_CHUNK)
	_source_frames["points"] = points.get("frame", {}).duplicate(true)
	_source_art_status["points"] = points.get("texture") is Texture2D
	_add_art(points, "SourceShopPoints", POINTS_ORIGIN, _logical_size(points, Vector2(90, 40)), POINTS_CHUNK)
	var offers: Array = _model.get("card_offers", []) if _mode == "cards" else _model.get("tool_offers", [])
	for index in range(offers.size()):
		if not offers[index] is Dictionary or offers[index].is_empty(): continue
		var record: Dictionary = offers[index]
		var name_anchor := CATALOG_ORIGIN + (Vector2(90, 83 + index * 24) if _mode == "cards" else Vector2(90, 92 + index * 48))
		var price_anchor := CATALOG_ORIGIN + (Vector2(194, 75 + index * 24) if _mode == "cards" else Vector2(194, 84 + index * 48))
		var name_label := _make_source_text("SourceShopOffer%d" % index, str(record.get("name", "")), name_anchor, Vector2(160, 24), SOURCE_FONT_SIZE, true)
		name_label.set_meta("source_id", int(record.get("source_id", 0)))
		if record.has("price"):
			var price_label := _make_source_text("SourceShopPrice%d" % index, str(record.price), price_anchor, Vector2(80, 24), SOURCE_FONT_SIZE)
			price_label.set_meta("source_id", int(record.get("source_id", 0)))
	var points_label := _make_source_text("SourceShopPointsValue", str(_model.get("points", 0)), POINTS_ANCHOR, Vector2(100, 24), SOURCE_FONT_SIZE)
	points_label.set_meta("source_chunk", POINTS_CHUNK)
	var held_records := _held_records()
	for index in range(held_records.size()):
		var record: Dictionary = held_records[index]
		var cell := GRID_ORIGIN + Vector2(float(index % GRID_COLUMNS) * CELL.x, float(index / GRID_COLUMNS) * CELL.y)
		if _mode == "cards":
			var card_label := _make_source_text("SourceShopHeld%d" % index, str(record.get("name", "")), HELD_ORIGIN + Vector2(45.0 + float(index % GRID_COLUMNS) * CELL.x, 33.0 + float(index / GRID_COLUMNS) * CELL.y), Vector2(76.0, 24.0), SOURCE_FONT_SIZE, true)
			card_label.set_meta("source_id", int(record.get("source_id", 0)))
		else:
			var source_id := int(record.get("source_id", 0))
			var chunk := source_id + 1
			var icon := _resolve("Panel", PANEL11, chunk)
			_source_frames["held_%d" % index] = icon.get("frame", {}).duplicate(true)
			_source_art_status["held_%d" % index] = icon.get("texture") is Texture2D
			var icon_rect := _icon_rect(icon, cell)
			_add_art(icon, "SourceShopHeldIcon%d" % index, icon_rect.position, icon_rect.size, chunk)
			_make_source_text("SourceShopHeldQty%d" % index, str(record.get("count", 0)), HELD_ORIGIN + Vector2(79.0 + float(index % GRID_COLUMNS) * CELL.x, 23.0 + float(index / GRID_COLUMNS) * CELL.y), Vector2(28.0, 24.0), SOURCE_FONT_SIZE)
	_source_art_available = _source_art_available and _all_displayed_art_available()
	if not _source_art_available: _make_centered_label("SourceShopFallback", "來源畫面素材未載入", Vector2(320, 250), Vector2(220, 22), 14, Color("#b6d5cf"))
	if not _is_ready_state() and not str(_model.get("gift_message", "")).is_empty():
		_make_centered_label("SourceShopGiftMessage", str(_model.get("gift_message", "")), Vector2(320, 440), Vector2(360, 26), 16, SOURCE_TEXT)
	elif _is_ready_state() and not str(_model.get("feedback", "")).is_empty():
		_make_centered_label("SourceShopFeedback", str(_model.get("feedback", "")), Vector2(320, 440), Vector2(360, 26), 16, SOURCE_TEXT)

func _make_text(node_name: String, value: String, origin: Vector2, extent: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = value
	label.position = origin
	label.size = extent
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", SOURCE_TEXT)
	label.add_theme_color_override("font_outline_color", SOURCE_OUTLINE)
	label.add_theme_constant_override("outline_size", 1)
	_apply_source_font(label)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(label)
	return label

func _make_centered_label(node_name: String, value: String, center: Vector2, extent: Vector2, font_size: int, color := SOURCE_TEXT) -> Label:
	var label := _make_source_text(node_name, value, center, extent, font_size, true)
	label.add_theme_color_override("font_color", color)
	return label

func _make_source_text(node_name: String, value: String, anchor: Vector2, extent: Vector2, font_size: int, centered := false) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = value
	label.size = extent
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", SOURCE_TEXT)
	label.add_theme_color_override("font_outline_color", SOURCE_OUTLINE)
	label.add_theme_constant_override("outline_size", 1)
	_apply_source_font(label)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if centered else VERTICAL_ALIGNMENT_TOP
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(label)
	label.position = anchor - (extent / 2.0 if centered else Vector2(extent.x, 0.0))
	return label

func _apply_source_font(label: Label) -> void:
	label.set_meta("source_font_height", label.get_theme_font_size("font_size"))
	label.set_meta("source_font_foreground", SOURCE_TEXT)
	label.set_meta("source_font_outline", SOURCE_OUTLINE)
	label.set_meta("source_font_flags", SOURCE_FONT_FLAGS)

func _merchant_ready_chunk() -> int:
	return int(MERCHANT_READY_CHUNKS.get(_mode, 2))

func _merchant_closing_chunk() -> int:
	return int(MERCHANT_CLOSING_CHUNKS.get(_mode, 3))

func _tab_normal_chunk() -> int:
	return int(TAB_NORMAL_CHUNKS.get(_mode, 13))

func _tab_pressed_chunk() -> int:
	return int(TAB_PRESSED_CHUNKS.get(_mode, 14))

func _icon_rect(result: Dictionary, cell: Vector2) -> Rect2:
	var frame: Variant = result.get("frame", {})
	var logical: Variant = frame.get("logical", {}) if frame is Dictionary else {}
	var size := Vector2(40.0, 34.0)
	var anchor := Vector2(20.0, 17.0)
	if logical is Dictionary:
		size = Vector2(float(logical.get("width", size.x)), float(logical.get("height", size.y)))
		anchor = Vector2(float(logical.get("anchor_x", anchor.x)), float(logical.get("anchor_y", anchor.y)))
	var source_origin := HELD_ORIGIN + Vector2(29.0 + float(cell.x - GRID_ORIGIN.x), 33.0 + float(cell.y - GRID_ORIGIN.y))
	return Rect2(source_origin - anchor, size)

func _logical_size(result: Dictionary, fallback: Vector2) -> Vector2:
	var frame: Variant = result.get("frame", {})
	var logical: Variant = frame.get("logical", {}) if frame is Dictionary else {}
	if logical is Dictionary and logical.has("width") and logical.has("height"):
		return Vector2(float(logical.width), float(logical.height))
	return fallback

func _add_anchored_art(result: Dictionary, node_name: String, center: Vector2, chunk: int) -> void:
	var frame: Variant = result.get("frame", {})
	var logical: Variant = frame.get("logical", {}) if frame is Dictionary else {}
	var size := _logical_size(result, Vector2.ONE)
	var anchor := Vector2.ZERO
	if logical is Dictionary:
		anchor = Vector2(float(logical.get("anchor_x", 0)), float(logical.get("anchor_y", 0)))
	_add_art(result, node_name, center - anchor, size, chunk)

func _all_displayed_art_available() -> bool:
	for key in _source_art_status:
		if not bool(_source_art_status[key]): return false
	return true

func _add_art(result: Dictionary, node_name: String, origin: Vector2, extent: Vector2, chunk: int) -> void:
	if not result.get("texture") is Texture2D:
		var fallback := ColorRect.new()
		fallback.name = node_name + "Fallback"
		fallback.position = origin
		fallback.size = extent
		fallback.color = FALLBACK_PANEL_COLOR if chunk in [0, 16] else FALLBACK_CELL_COLOR
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_surface.add_child(fallback)
		return
	var art := TextureRect.new()
	art.name = node_name
	art.position = origin
	art.size = extent
	art.texture = result.texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_meta("source_chunk", chunk)
	art.set_meta("source_frame", (result.get("frame", {}) as Dictionary).duplicate(true))
	_surface.add_child(art)

func _resolve(archive: String, resource: int, chunk: int) -> Dictionary:
	var key := "%s.%s.%d.%d" % [_edition, archive, resource, chunk]
	var frame: Dictionary = {}
	var texture: Texture2D = null
	if _visual_accessor is Object and (_visual_accessor as Object).has_method("ui"):
		var value: Variant = (_visual_accessor as Object).call("ui", _edition, archive, resource, chunk)
		if value is Dictionary: frame = value.duplicate(true)
	if frame.is_empty() and _visual_accessor is Dictionary:
		var value: Variant = (_visual_accessor as Dictionary).get(key, null)
		if value is Dictionary: frame = value.duplicate(true)
	if frame.get("ui_texture") is Texture2D: texture = frame.ui_texture
	if texture == null and _visual_accessor is Object and (_visual_accessor as Object).has_method("texture") and not frame.is_empty():
		var value: Variant = (_visual_accessor as Object).call("texture", frame)
		if value is Texture2D: texture = value
	return {"frame": frame, "texture": texture}
