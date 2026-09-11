extends Control
class_name RichmanSourceSalePanel

## Source-shaped S21 SALE presenter for a detached host-supplied snapshot.
##
## The panel renders real source frames (shared Project2 Panel resources 73/74)
## through an injected visual accessor, keeps every gesture latch locally, and
## emits intents only.  It owns no game state, mutates no money and never
## constructs a confirmation dialog; the host controller decides outcomes.

signal action_requested(action: String, params: Dictionary)
signal cancelled

const CANVAS := Vector2(640, 480)
const EDITIONS := ["Game", "MultiverseJourney"]
const VIEWS := ["board", "picker", "detail", "reference"]
const CATEGORIES := ["stock", "property", "tool", "card"]
const CATEGORY_INDEX := {"stock": 0, "property": 1, "tool": 2, "card": 3}
const CATEGORY_PICKER_CHUNK := {"stock": 1, "property": 2, "tool": 3, "card": 4}
const CATEGORY_DETAIL_CHUNK := {"stock": 7, "property": 8, "tool": 6, "card": 6}
const CATEGORY_DETAIL_ORIGIN := {
	"stock": Vector2(224, 112),
	"property": Vector2(224, 96),
	"tool": Vector2(224, 128),
	"card": Vector2(224, 128),
}
const CATEGORY_DETAIL_SIZE := {
	"stock": Vector2(192, 256),
	"property": Vector2(192, 288),
	"tool": Vector2(192, 224),
	"card": Vector2(192, 224),
}
const CATEGORY_DETAIL_BASELINE := {"stock": 236, "property": 265, "tool": 203, "card": 203}
const CATEGORY_FALLBACK_LABEL := {"stock": "股票買賣", "property": "地產買賣", "tool": "道具買賣", "card": "卡片買賣"}

const BOARD_CHUNK := 0
const MENU_CHUNK := 17
const CHECKER_CHUNK := 18
const PAGE_TAB_CHUNK := 19
const REFERENCE_CHUNK := 5
const TOOL_ICON_RESOURCE := 74
const TOOL_ICON_COUNT := 13
const SEX_TILE_CHUNK := {"female": 9, "male": 13}

const BOARD_RECT := Rect2(22, 66, 596, 348)
const BOARD_CREATE_RECT := Rect2(464, 74, 72, 40)
const BOARD_CLOSE_RECT := Rect2(536, 74, 72, 40)
const OFFER_ORIGIN := Vector2(104, 114)
const OFFER_CELL := Vector2(72, 72)
const OFFER_COLUMNS := 7
const MENU_RECT := Rect2(464, 116, 144, 96)
const MENU_GRID := Rect2(473, 125, 125, 77)
const MENU_COLUMN := 63.0
const MENU_ROW := 39.0
const MENU_CELL := Vector2(62, 38)
const PORTRAIT_ORIGIN := Vector2(44, 84)
const PORTRAIT_SIZE := Vector2(36, 36)
const PORTRAIT_STRIDE := 72.0
const PORTRAIT_DIRECTION := 0
const CHARACTER_COUNT := 12
const NAME_CENTER := Vector2(62, 128)
const OFFER_TILE_BASE := 9

const STOCK_PANEL_RECT := Rect2(152, 32, 336, 416)
const STOCK_ROWS_RECT := Rect2(152, 64, 336, 384)
const STOCK_ROW_HEIGHT := 32.0
const STOCK_NAME_X := 200.0
const STOCK_QUANTITY_X := 332.0
const STOCK_VALUE_X := 478.0
const STOCK_ROW_LIMIT := 12
const STOCK_CLOSE_RECT := Rect2(463, 38, 21, 21)
const STOCK_CHECKER_SIZE := Vector2(21, 21)
const STOCK_CHECKER_X := 166.0

const PROPERTY_PANEL_RECT := Rect2(112, 32, 416, 416)
const PROPERTY_TAB_RECT := Rect2(112, 32, 400, 30)
const PROPERTY_TAB_WIDTH := 80.0
const PROPERTY_TAB_COUNT := 5
const PROPERTY_TAB_LABELS := ["全  部", "住宅區", "商業區", "房  屋", "連鎖店"]
const PROPERTY_ROWS_RECT := Rect2(112, 96, 416, 352)
const PROPERTY_ROW_HEIGHT := 32.0
const PROPERTY_ROWS_PER_PAGE := 11
const PROPERTY_TABLE_LABELS := ["地  點", "開發狀況", "價  格", "收  費", "租  期"]
const PROPERTY_TABLE_X := [147.0, 231.0, 319.0, 395.0, 471.0]
const PROPERTY_HEADER_Y := 80.0
const PROPERTY_CLOSE_RECT := Rect2(511, 32, 17, 19)
const PROPERTY_UP_RECT := Rect2(511, 64, 17, 32)
const PROPERTY_DOWN_RECT := Rect2(511, 96, 17, 32)

const PICKER_PANEL_RECT := Rect2(140, 160, 360, 128)
const PICKER_GRID_RECT := Rect2(140, 192, 360, 96)
const PICKER_CELL := Vector2(72, 32)
const PICKER_COLUMNS := 5
const PICKER_ROWS := 3
const PICKER_CLOSE_RECT := Rect2(428, 160, 72, 32)
const PICKER_SLOT_LIMIT := 15
const TOOL_ICON_X := 160.0
const TOOL_QUANTITY_X := 206.0
const PICKER_LABEL_CENTER_X := 176.0
const PICKER_ROW_CENTER_Y := 208.0

const REFERENCE_X := 227.0
const REFERENCE_Y_DEFAULT := 42.0
const REFERENCE_SIZE := Vector2(184, 88)
const REFERENCE_MAX_MULTIPLIER := 10

const DETAIL_PRIMARY_X := 16.0
const DETAIL_SECONDARY_X := 104.0
const DETAIL_BUTTON_WIDTH := 72.0
const DETAIL_BUTTON_HALF_HEIGHT := 12.0
const DETAIL_PRIMARY_CENTER_X := 52.0
const DETAIL_SECONDARY_CENTER_X := 140.0
const PRIMARY_LABEL_OWN := "撤 件"
const PRIMARY_LABEL_OTHER := "購 買"
const SECONDARY_LABEL := "EXIT"
const FEEDBACK_BOARD_FULL := "公佈欄已滿\n\n請先撤件！"
const FEEDBACK_ART_MISSING := "來源畫面素材未載入"

const SOURCE_TEXT := Color("#ffffff")
const SOURCE_OUTLINE := Color("#101010")
const FALLBACK_PANEL := Color("#2c3630")
const FALLBACK_SLOT := Color("#42566a")
const FALLBACK_HILITE := Color("#f4f0a0")
const SOURCE_FONT_SIZE := 16
const SOURCE_FONT_FLAGS := 3

var _model: Dictionary = {}
var _visual_accessor: Variant = null
var _edition := ""
var _view := ""
var _category := ""
var _is_open := false
var _model_valid := false
var _source_art_available := false
var _source_art_status := {}
var _surface: Control

var _menu_open := false
var _menu_hover := -1
var _pressed_create := false
var _pressed_close := false
var _pressed_offer := -1
var _hover_offer := -1

var _picker_pressed_close := false
var _picker_pressed_row := -1
var _picker_hover_row := -1
var _picker_pressed_tab := -1
var _picker_pressed_arrow := 0
var _picker_hover_arrow := 0
var _picker_pressed_slot := -1
var _picker_hover_slot := -1
var _property_filter := 0
var _property_page := 0

var _detail_pressed := 0

func _init() -> void:
	name = "SourceSalePanel"
	size = CANVAS
	custom_minimum_size = CANVAS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_surface = Control.new()
	_surface.name = "SourceSaleSurface"
	_surface.size = CANVAS
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)
	hide()

func configure(model: Dictionary) -> bool:
	var unchanged := _model_valid and _deep_equal(_model, model)
	_model = model.duplicate(true) if model is Dictionary else {}
	_edition = str(_model.get("edition", ""))
	_view = str(_model.get("view", ""))
	_category = str(_model.get("category", ""))
	_model_valid = _validate(_model)
	_is_open = _model_valid
	if not unchanged:
		_reset_latches()
	_render()
	if _is_open:
		show()
	else:
		hide()
	return _model_valid

func set_visual_accessor(accessor: Variant) -> void:
	_visual_accessor = accessor.duplicate(true) if accessor is Dictionary else accessor
	_render()

func set_visuals(accessor: Variant) -> void:
	set_visual_accessor(accessor)

func view_model() -> Dictionary:
	return _model.duplicate(true)

func is_open() -> bool:
	return _is_open and _model_valid and visible

func close() -> bool:
	if not is_open():
		return false
	_is_open = false
	_reset_latches()
	hide()
	cancelled.emit()
	return true

func source_art_available() -> bool:
	return _source_art_available

func has_source_art() -> bool:
	return source_art_available()

func source_art_status() -> Dictionary:
	return _source_art_status.duplicate(true)

func source_geometry() -> Dictionary:
	var reference_y := float(_model.get("reference_y", REFERENCE_Y_DEFAULT)) if _model_valid else REFERENCE_Y_DEFAULT
	var baseline := int(CATEGORY_DETAIL_BASELINE.get(_category, 203))
	var origin: Vector2 = CATEGORY_DETAIL_ORIGIN.get(_category, Vector2(224, 128))
	return {
		"canvas": CANVAS,
		"edition": _edition,
		"view": _view,
		"category": _category,
		"board": {
			"rect": BOARD_RECT,
			"create": BOARD_CREATE_RECT,
			"close": BOARD_CLOSE_RECT,
			"offer_origin": OFFER_ORIGIN,
			"offer_cell": OFFER_CELL,
			"offer_columns": OFFER_COLUMNS,
			"menu": MENU_RECT,
			"menu_grid": MENU_GRID,
			"menu_column": MENU_COLUMN,
			"menu_row": MENU_ROW,
			"menu_cell": MENU_CELL,
			"portrait_origin": PORTRAIT_ORIGIN,
			"portrait_size": PORTRAIT_SIZE,
			"portrait_stride": PORTRAIT_STRIDE,
			"name_center": NAME_CENTER,
			"sex_tiles": SEX_TILE_CHUNK,
			"chunk": BOARD_CHUNK,
			"menu_chunk": MENU_CHUNK,
		},
		"picker": {
			"panel": PICKER_PANEL_RECT,
			"grid": PICKER_GRID_RECT,
			"cell": PICKER_CELL,
			"columns": PICKER_COLUMNS,
			"rows": PICKER_ROWS,
			"close": PICKER_CLOSE_RECT,
			"chunk": int(CATEGORY_PICKER_CHUNK.get(_category, 1)),
			"tool_icon_resource": TOOL_ICON_RESOURCE,
			"tool_icon_x": TOOL_ICON_X,
			"tool_quantity_x": TOOL_QUANTITY_X,
			"label_center_x": PICKER_LABEL_CENTER_X,
			"row_center_y": PICKER_ROW_CENTER_Y,
			"stock": {
				"panel": STOCK_PANEL_RECT,
				"rows": STOCK_ROWS_RECT,
				"row_height": STOCK_ROW_HEIGHT,
				"name_x": STOCK_NAME_X,
				"quantity_x": STOCK_QUANTITY_X,
				"value_x": STOCK_VALUE_X,
				"row_limit": STOCK_ROW_LIMIT,
				"close": STOCK_CLOSE_RECT,
				"chunk": int(CATEGORY_PICKER_CHUNK["stock"]),
				"checker_chunk": CHECKER_CHUNK,
				"checker_x": STOCK_CHECKER_X,
			},
			"property": {
				"panel": PROPERTY_PANEL_RECT,
				"tabs": PROPERTY_TAB_RECT,
				"tab_width": PROPERTY_TAB_WIDTH,
				"tab_count": PROPERTY_TAB_COUNT,
				"rows": PROPERTY_ROWS_RECT,
				"row_height": PROPERTY_ROW_HEIGHT,
				"rows_per_page": PROPERTY_ROWS_PER_PAGE,
				"columns": PROPERTY_TABLE_X,
				"header_y": PROPERTY_HEADER_Y,
				"close": PROPERTY_CLOSE_RECT,
				"up": PROPERTY_UP_RECT,
				"down": PROPERTY_DOWN_RECT,
				"chunk": int(CATEGORY_PICKER_CHUNK["property"]),
				"tab_chunk": PAGE_TAB_CHUNK,
			},
		},
		"detail": {
			"origin": origin,
			"size": CATEGORY_DETAIL_SIZE.get(_category, Vector2(192, 224)),
			"baseline": baseline,
			"primary": Rect2(origin.x + DETAIL_PRIMARY_X, origin.y + float(baseline) - 12.0, DETAIL_BUTTON_WIDTH, 24.0),
			"secondary": Rect2(origin.x + DETAIL_SECONDARY_X, origin.y + float(baseline) - 12.0, DETAIL_BUTTON_WIDTH, 24.0),
			"primary_center_x": DETAIL_PRIMARY_CENTER_X,
			"secondary_center_x": DETAIL_SECONDARY_CENTER_X,
			"chunk": int(CATEGORY_DETAIL_CHUNK.get(_category, 6)),
		},
		"reference": {
			"rect": Rect2(REFERENCE_X, reference_y, REFERENCE_SIZE.x, REFERENCE_SIZE.y),
			"origin_x": REFERENCE_X,
			"y": reference_y,
			"size": REFERENCE_SIZE,
			"chunk": REFERENCE_CHUNK,
			"max_multiplier": REFERENCE_MAX_MULTIPLIER,
		},
	}

func _reset_latches() -> void:
	_menu_open = false
	_menu_hover = -1
	_pressed_create = false
	_pressed_close = false
	_pressed_offer = -1
	_hover_offer = -1
	_picker_pressed_close = false
	_picker_pressed_row = -1
	_picker_hover_row = -1
	_picker_pressed_tab = -1
	_picker_pressed_arrow = 0
	_picker_hover_arrow = 0
	_picker_pressed_slot = -1
	_picker_hover_slot = -1
	_property_filter = 0
	_property_page = 0
	_detail_pressed = 0

# --------------------------------------------------------------------------
# Input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if is_open():
			_motion(motion.position)
		accept_event()
		return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if not is_open():
		accept_event()
		return
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		if not mouse.pressed:
			_right_release()
		accept_event()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		accept_event()
		return
	if mouse.pressed:
		_press(mouse.position)
	else:
		_release()
	accept_event()

func _input(event: InputEvent) -> void:
	# Hosts replay right-button releases without a matching press (programmatic
	# tests and the source close gesture); the global hook keeps that reachable.
	if not is_open():
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT and not mouse.pressed:
			get_viewport().set_input_as_handled()
			_right_release()

func _right_release() -> void:
	match _view:
		"board":
			_is_open = false
			_reset_latches()
			hide()
			cancelled.emit()
		"picker", "detail", "reference":
			action_requested.emit("back", {})

func _motion(point: Vector2) -> void:
	match _view:
		"board":
			if _menu_open:
				_menu_hover = _menu_index(point)
			_hover_offer = _offer_index(point)
		"picker":
			if _category == "stock":
				_picker_hover_row = _stock_row(point)
			elif _category == "property":
				_picker_hover_row = _property_row(point)
				_picker_hover_arrow = 1 if _strict_hit(point, PROPERTY_UP_RECT) else (2 if _strict_hit(point, PROPERTY_DOWN_RECT) else 0)
			else:
				_picker_hover_slot = _picker_slot(point)
		_:
			pass

func _press(point: Vector2) -> void:
	match _view:
		"board":
			_press_board(point)
		"picker":
			_press_picker(point)
		"detail":
			_press_detail(point)
		_:
			pass

func _press_board(point: Vector2) -> void:
	if _menu_open:
		var index := _menu_index(point)
		if index >= 0:
			_menu_hover = index
		return
	if _strict_hit(point, BOARD_CREATE_RECT):
		if not _can_open_menu():
			# The source refuses before drawing the create menu; the refusal
			# stays silent unless the host supplied its own visible feedback.
			_render()
			return
		_menu_open = true
		_menu_hover = -1
		_render()
		return
	_pressed_close = _strict_hit(point, BOARD_CLOSE_RECT)
	_pressed_offer = _offer_index(point)

func _release() -> void:
	match _view:
		"board":
			_release_board()
		"picker":
			_release_picker()
		"detail":
			_release_detail()
		_:
			pass

func _release_board() -> void:
	if _menu_open:
		var index := _menu_hover
		if index >= 0:
			_menu_hover = -1
			_menu_open = false
			_reset_board_press()
			_render()
			action_requested.emit("category_selected", {"category": CATEGORIES[index]})
			return
		_render()
		return
	if _pressed_close:
		_pressed_close = false
		_is_open = false
		_reset_latches()
		hide()
		cancelled.emit()
		return
	if _pressed_offer >= 0:
		var index := _pressed_offer
		_pressed_offer = -1
		var record := _offer_at(index)
		if not record.is_empty():
			action_requested.emit("offer_selected", {"offer_id": int(record.get("offer_id", 0)), "revision": int(record.get("revision", 0))})
		_render()
		return
	_reset_board_press()

func _release_picker() -> void:
	if _picker_pressed_close:
		_picker_pressed_close = false
		_render()
		action_requested.emit("back", {})
		return
	if _category == "stock":
		var row := _picker_pressed_row
		_picker_pressed_row = -1
		var rows := _stock_rows()
		if row >= 0 and row < rows.size():
			var record: Dictionary = rows[row]
			_render()
			action_requested.emit("item_selected", {"category": "stock", "source_id": int(record.get("source_id", 0)), "held_index": -1})
			return
		_render()
		return
	if _category == "property":
		var arrow := _picker_pressed_arrow
		_picker_pressed_arrow = 0
		if arrow == 1:
			_property_page = maxi(0, _property_page - 1)
			_render()
			return
		if arrow == 2:
			var pages := maxi(1, int(ceil(float(_property_rows().size()) / float(PROPERTY_ROWS_PER_PAGE))))
			_property_page = mini(pages - 1, _property_page + 1)
			_render()
			return
		var row := _picker_pressed_row
		_picker_pressed_row = -1
		var rows := _property_rows()
		var absolute := _property_page * PROPERTY_ROWS_PER_PAGE + row
		if row >= 0 and absolute >= 0 and absolute < rows.size():
			var record: Dictionary = rows[absolute]
			_render()
			action_requested.emit("item_selected", {"category": "property", "source_id": int(record.get("source_id", 0)), "held_index": -1})
			return
		_render()
		return
	var slot := _picker_pressed_slot
	_picker_pressed_slot = -1
	var items := _picker_items()
	if slot >= 0 and slot < items.size():
		var record: Dictionary = items[slot]
		_render()
		action_requested.emit("item_selected", {
			"category": _category,
			"source_id": int(record.get("source_id", 0)),
			"held_index": int(record.get("held_index", -1)) if _category == "card" else -1,
		})
		return
	_render()

func _press_picker(point: Vector2) -> void:
	_picker_pressed_close = _strict_hit(point, _picker_close_rect())
	if _category == "stock":
		_picker_pressed_row = _stock_row(point)
	elif _category == "property":
		var tab := _property_tab(point)
		if tab >= 0:
			_picker_pressed_tab = tab
			_property_filter = tab
			_property_page = 0
			_render()
			return
		_picker_pressed_row = _property_row(point)
		if _strict_hit(point, PROPERTY_UP_RECT):
			_picker_pressed_arrow = 1
		elif _strict_hit(point, PROPERTY_DOWN_RECT):
			_picker_pressed_arrow = 2
	else:
		_picker_pressed_slot = _picker_slot(point)

func _press_detail(point: Vector2) -> void:
	var geometry := _detail_rects()
	_detail_pressed = 0
	if _strict_hit(point, geometry[0]):
		_detail_pressed = 1
	elif _strict_hit(point, geometry[1]):
		_detail_pressed = 2

func _release_detail() -> void:
	var pressed := _detail_pressed
	_detail_pressed = 0
	if pressed == 1:
		var record := _selected_record()
		if record.is_empty():
			return
		# The detail stays open: the host owns the YES/NO resolution.
		action_requested.emit("detail_primary", {"offer_id": int(record.get("offer_id", 0)), "revision": int(record.get("revision", 0))})
	elif pressed == 2:
		action_requested.emit("back", {})

func _reset_board_press() -> void:
	_pressed_create = false
	_pressed_close = false
	_pressed_offer = -1

func _strict_hit(point: Vector2, rect: Rect2) -> bool:
	return point.x > rect.position.x and point.x < rect.end.x and point.y > rect.position.y and point.y < rect.end.y

func _menu_index(point: Vector2) -> int:
	if not _strict_hit(point, MENU_GRID):
		return -1
	var column := int(floor((point.x - MENU_GRID.position.x) / MENU_COLUMN))
	var row := int(floor((point.y - MENU_GRID.position.y) / MENU_ROW))
	var index := column * 2 + row
	return index if index >= 0 and index < CATEGORIES.size() else -1

func _menu_cell_rect(index: int) -> Rect2:
	var column := index / 2
	var row := index % 2
	return Rect2(MENU_GRID.position + Vector2(float(column) * MENU_COLUMN, float(row) * MENU_ROW), MENU_CELL)

func _offer_index(point: Vector2) -> int:
	var players := _players()
	if players.is_empty():
		return -1
	var rows := players.size()
	if not _strict_hit(point, Rect2(OFFER_ORIGIN, Vector2(OFFER_CELL.x * OFFER_COLUMNS, OFFER_CELL.y * rows))):
		return -1
	var column := int(floor((point.x - OFFER_ORIGIN.x) / OFFER_CELL.x))
	var row := int(floor((point.y - OFFER_ORIGIN.y) / OFFER_CELL.y))
	if column < 0 or column >= OFFER_COLUMNS or row < 0 or row >= rows:
		return -1
	var index := row * OFFER_COLUMNS + column
	return index if not _offer_at(index).is_empty() else -1

func _stock_row(point: Vector2) -> int:
	if not _strict_hit(point, STOCK_ROWS_RECT):
		return -1
	var row := int(floor((point.y - STOCK_ROWS_RECT.position.y) / STOCK_ROW_HEIGHT))
	var rows := _stock_rows()
	return row if row >= 0 and row < mini(rows.size(), STOCK_ROW_LIMIT) else -1

func _property_tab(point: Vector2) -> int:
	if not _strict_hit(point, PROPERTY_TAB_RECT):
		return -1
	var index := int(floor((point.x - PROPERTY_TAB_RECT.position.x) / PROPERTY_TAB_WIDTH))
	return index if index >= 0 and index < PROPERTY_TAB_COUNT else -1

func _property_row(point: Vector2) -> int:
	if not _strict_hit(point, PROPERTY_ROWS_RECT):
		return -1
	var row := int(floor((point.y - PROPERTY_ROWS_RECT.position.y) / PROPERTY_ROW_HEIGHT))
	if row < 0 or row >= PROPERTY_ROWS_PER_PAGE:
		return -1
	var absolute := _property_page * PROPERTY_ROWS_PER_PAGE + row
	return row if absolute < _property_rows().size() else -1

func _picker_slot(point: Vector2) -> int:
	if not _strict_hit(point, PICKER_GRID_RECT):
		return -1
	var column := int(floor((point.x - PICKER_GRID_RECT.position.x) / PICKER_CELL.x))
	var row := int(floor((point.y - PICKER_GRID_RECT.position.y) / PICKER_CELL.y))
	if column < 0 or column >= PICKER_COLUMNS or row < 0 or row >= PICKER_ROWS:
		return -1
	var index := row * PICKER_COLUMNS + column
	return index if index < _picker_items().size() else -1

func _picker_close_rect() -> Rect2:
	return STOCK_CLOSE_RECT if _category == "stock" else PROPERTY_CLOSE_RECT if _category == "property" else PICKER_CLOSE_RECT

func _detail_rects() -> Array:
	var origin: Vector2 = CATEGORY_DETAIL_ORIGIN.get(_category, Vector2(224, 128))
	var baseline := float(CATEGORY_DETAIL_BASELINE.get(_category, 203))
	var top := origin.y + baseline - DETAIL_BUTTON_HALF_HEIGHT
	var primary := Rect2(origin.x + DETAIL_PRIMARY_X, top, DETAIL_BUTTON_WIDTH, DETAIL_BUTTON_HALF_HEIGHT * 2.0)
	var secondary := Rect2(origin.x + DETAIL_SECONDARY_X, top, DETAIL_BUTTON_WIDTH, DETAIL_BUTTON_HALF_HEIGHT * 2.0)
	return [primary, secondary]

# --------------------------------------------------------------------------
# Model access

func _players() -> Array:
	var value: Variant = _model.get("players", [])
	return value if value is Array else []

func _holdings() -> Dictionary:
	var value: Variant = _model.get("holdings", {})
	return value if value is Dictionary else {}

func _current_player() -> Dictionary:
	var player_id := int(_model.get("player_id", -1))
	for value in _players():
		if value is Dictionary and int(value.get("player_id", -2)) == player_id:
			return value
	return {}

func _current_offers() -> Array:
	var offers: Variant = _current_player().get("offers", [])
	return offers if offers is Array else []

func _can_open_menu() -> bool:
	return bool(_model.get("can_create", false)) and _current_offers().size() < OFFER_COLUMNS

func _offer_at(index: int) -> Dictionary:
	var players := _players()
	var row := index / OFFER_COLUMNS
	var column := index % OFFER_COLUMNS
	if row < 0 or row >= players.size() or not players[row] is Dictionary:
		return {}
	var offers: Variant = players[row].get("offers", [])
	if not offers is Array or column >= offers.size() or not offers[column] is Dictionary:
		return {}
	if offers[column].is_empty():
		return {}
	return offers[column]

func _offer_seller(record: Dictionary) -> Dictionary:
	var seller_id := int(record.get("seller_id", -1))
	for value in _players():
		if value is Dictionary and int(value.get("player_id", -2)) == seller_id:
			return value
	return {}

func _stock_rows() -> Array:
	var result: Array = []
	var stock: Variant = _holdings().get("stock", [])
	if not stock is Array:
		return result
	for value in stock:
		if value is Dictionary and int(value.get("quantity", 0)) > 0:
			result.append(value)
		if result.size() >= STOCK_ROW_LIMIT:
			break
	return result

func _property_rows() -> Array:
	var result: Array = []
	var property: Variant = _holdings().get("property", [])
	if not property is Array:
		return result
	for value in property:
		if value is Dictionary and _property_filter_match(value):
			result.append(value)
	return result

func _property_filter_match(record: Dictionary) -> bool:
	var kind := str(record.get("kind", ""))
	var level := int(record.get("building_level", 0))
	var building := int(record.get("building_type", 0))
	match _property_filter:
		1:
			return kind == "land"
		2:
			return kind == "facility"
		3:
			return kind == "land" and level > 0 and building == 0
		4:
			return kind == "land" and level > 0 and building != 0
		_:
			return true

func _picker_items() -> Array:
	var result: Array = []
	if _category == "card":
		var card: Variant = _holdings().get("card", [])
		if not card is Array:
			return result
		for value in card:
			if value is Dictionary:
				result.append(value)
		return result
	var tool: Variant = _holdings().get("tool", [])
	if not tool is Array:
		return result
	for value in tool:
		if value is Dictionary and int(value.get("quantity", 0)) > 0:
			result.append(value)
	return result

func _selected_record() -> Dictionary:
	var offer: Variant = _model.get("selected_offer", {})
	if offer is Dictionary and not offer.is_empty():
		return offer
	var item: Variant = _model.get("selected_item", {})
	if item is Dictionary:
		return item
	return {}

# --------------------------------------------------------------------------
# Validation

func _validate(model: Dictionary) -> bool:
	if not model is Dictionary or model.is_empty():
		return false
	for key in ["session_id", "player_id", "edition", "view", "category", "players", "holdings", "can_create", "selected_offer", "selected_item", "feedback"]:
		if not model.has(key):
			return false
	if not _is_integral(model.get("session_id")) or int(model.get("session_id")) <= 0:
		return false
	if not _is_integral(model.get("player_id")) or int(model.get("player_id")) < 0:
		return false
	if str(model.get("edition", "")) not in EDITIONS:
		return false
	if str(model.get("view", "")) not in VIEWS:
		return false
	if str(model.get("category", "")) not in CATEGORIES:
		return false
	if not model.get("can_create") is bool:
		return false
	if not model.get("selected_offer") is Dictionary or not model.get("selected_item") is Dictionary:
		return false
	if not model.get("feedback") is String:
		return false
	if not model.get("players") is Array or not model.get("holdings") is Dictionary:
		return false
	for value in model.players:
		if not value is Dictionary or not _valid_player(value):
			return false
	return _valid_holdings(model.holdings)

func _valid_player(value: Dictionary) -> bool:
	for key in ["player_id", "name", "character_id", "sex", "alive", "offers"]:
		if not value.has(key):
			return false
	if not _is_integral(value.get("player_id")) or int(value.get("player_id")) < 0:
		return false
	if not value.get("name") is String or not _is_integral(value.get("character_id")):
		return false
	if not _is_integral(value.get("sex")) or int(value.get("sex")) not in [0, 1]:
		return false
	if not value.get("alive") is bool or not value.get("offers") is Array:
		return false
	for offer in value.offers:
		if not offer is Dictionary:
			return false
		if offer.is_empty():
			continue
		if not _valid_offer(offer):
			return false
	return true

func _valid_offer(offer: Dictionary) -> bool:
	for key in ["offer_id", "revision", "seller_id", "category", "source_id", "quantity", "asking", "name", "reference_value"]:
		if not offer.has(key):
			return false
	if not _is_integral(offer.get("offer_id")) or int(offer.get("offer_id")) <= 0:
		return false
	if not _is_integral(offer.get("revision")) or int(offer.get("revision")) < 0:
		return false
	if not _is_integral(offer.get("seller_id")) or int(offer.get("seller_id")) < 0:
		return false
	if str(offer.get("category", "")) not in CATEGORIES:
		return false
	if not _is_integral(offer.get("source_id")) or int(offer.get("source_id")) < (0 if offer.get("category") == "stock" else 1):
		return false
	if not _is_integral(offer.get("quantity")) or int(offer.get("quantity")) <= 0:
		return false
	if not _is_integral(offer.get("asking")) or int(offer.get("asking")) < 0:
		return false
	if not _is_integral(offer.get("reference_value")) or int(offer.get("reference_value")) < 0:
		return false
	if not offer.get("name") is String:
		return false
	if str(offer.get("category", "")) == "property":
		for key in ["location", "development", "rent", "lease", "building_level", "building_type", "property_kind"]:
			if not offer.has(key):
				return false
		if not offer.get("location") is String or not offer.get("development") is String:
			return false
		if not _is_integral(offer.get("rent")) or not _is_integral(offer.get("lease")):
			return false
		if not _is_integral(offer.get("building_level")) or not _is_integral(offer.get("building_type")):
			return false
		if not offer.get("property_kind") is String:
			return false
	return true

func _valid_holdings(holdings: Dictionary) -> bool:
	for key in CATEGORIES:
		if not holdings.has(key) or not holdings.get(key) is Array:
			return false
	for value in holdings.get("stock", []):
		if not value is Dictionary:
			return false
		if not _valid_holding(value, true):
			return false
	for value in holdings.get("tool", []):
		if not value is Dictionary or not _valid_holding(value):
			return false
	for value in holdings.get("card", []):
		if not value is Dictionary or not _valid_holding(value):
			return false
		if not value.has("held_index") or not _is_integral(value.get("held_index")) or int(value.get("held_index")) < 0:
			return false
	for value in holdings.get("property", []):
		if not value is Dictionary or not _valid_holding(value):
			return false
		for key in ["kind", "building_level", "building_type", "location", "development", "rent", "lease"]:
			if not value.has(key):
				return false
		if str(value.get("kind", "")) not in ["land", "facility"]:
			return false
		if not _is_integral(value.get("building_level")) or not _is_integral(value.get("building_type")):
			return false
		if not _is_integral(value.get("rent")) or not _is_integral(value.get("lease")):
			return false
		if not value.get("location") is String or not value.get("development") is String:
			return false
	return true

func _valid_holding(value: Dictionary, stock: bool = false) -> bool:
	if not value.has("source_id") or not value.has("name") or not value.has("quantity") or not value.has("reference_value"):
		return false
	if not _is_integral(value.get("source_id")) or int(value.get("source_id")) < (0 if stock else 1):
		return false
	if not value.get("name") is String:
		return false
	if not _is_integral(value.get("quantity")) or int(value.get("quantity")) < 0:
		return false
	if not _is_integral(value.get("reference_value")) or int(value.get("reference_value")) < 0:
		return false
	return true

func _is_integral(value: Variant) -> bool:
	if not value is int and not value is float:
		return false
	return is_finite(float(value)) and floor(float(value)) == float(value)

func _deep_equal(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _deep_equal(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not _deep_equal(left[index], right[index]):
				return false
		return true
	if left is float or right is float:
		return typeof(left) == typeof(right) and float(left) == float(right)
	return left == right

# --------------------------------------------------------------------------
# Rendering

func _render() -> void:
	for child in _surface.get_children():
		child.free()
	_source_art_available = false
	_source_art_status.clear()
	if not _model_valid:
		return
	match _view:
		"board":
			_render_board()
		"picker":
			_render_picker()
		"detail":
			_render_detail()
		"reference":
			_render_reference()
		_:
			pass
	_source_art_available = _all_art_present()
	if not _source_art_available:
		_add_text("SourceSaleArtFallback", FEEDBACK_ART_MISSING, Vector2(320, 464), Vector2(240, 18), 14, 1, Color("#b6d5cf"))

func _all_art_present() -> bool:
	if _source_art_status.is_empty():
		return false
	for key in _source_art_status:
		if not bool(_source_art_status[key]):
			return false
	return true

func _render_board() -> void:
	var board := _resolve("Panel", 73, BOARD_CHUNK)
	_add_role("board", board)
	_add_art(board, "SourceSaleBoard", BOARD_RECT, BOARD_CHUNK, "公佈欄")
	var players := _players()
	for row in range(players.size()):
		var player: Dictionary = players[row]
		var portrait := Rect2(PORTRAIT_ORIGIN + Vector2(0, PORTRAIT_STRIDE * float(row)), PORTRAIT_SIZE)
		# The SALE board portrait is a composition fallback built from the existing
		# authorized character/chunk0 identity sprite (direction 0), not a verified
		# original SALE portrait.  source_art_status still reports the real Source
		# texture honestly instead of claiming an original portrait exists.
		var character_id := int(player.get("character_id", -1))
		var portrait_art: Dictionary = {"frame": {}, "texture": null}
		if character_id >= 0 and character_id < CHARACTER_COUNT:
			portrait_art = _resolve_character(character_id, PORTRAIT_DIRECTION)
		_source_art_status["portrait_%d" % row] = portrait_art.get("texture") is Texture2D
		_add_portrait(portrait_art, "SourceSalePortrait%d" % row, portrait, character_id)
		_add_text("SourceSalePlayerName%d" % row, str(player.get("name", "")), NAME_CENTER + Vector2(0, PORTRAIT_STRIDE * float(row)), Vector2(72, 16), 14, 1)
		var offers_value: Variant = player.get("offers", [])
		var offers: Array = offers_value if offers_value is Array else []
		for column in range(mini(offers.size(), OFFER_COLUMNS)):
			if not offers[column] is Dictionary or offers[column].is_empty():
				continue
			var record: Dictionary = offers[column]
			var category := str(record.get("category", "stock"))
			var sex := int(player.get("sex", 0))
			var tile_chunk := OFFER_TILE_BASE + int(CATEGORY_INDEX.get(category, 0)) + sex * 4
			var tile := _resolve("Panel", 73, tile_chunk)
			var role := "offer_%s_%d" % ["female" if sex == 0 else "male", int(CATEGORY_INDEX.get(category, 0))]
			_add_role(role, tile)
			var rect := Rect2(OFFER_ORIGIN + Vector2(OFFER_CELL.x * float(column), OFFER_CELL.y * float(row)), OFFER_CELL)
			_add_art(tile, "SourceSaleOffer%d_%d" % [row, column], rect, tile_chunk, str(record.get("name", "")))
		if _pressed_offer >= 0 and _pressed_offer / OFFER_COLUMNS == row:
			var column := _pressed_offer % OFFER_COLUMNS
			_add_border("SourceSaleOfferLatch", Rect2(OFFER_ORIGIN + Vector2(OFFER_CELL.x * float(column), OFFER_CELL.y * float(row)), OFFER_CELL))
	if _menu_open:
		var menu := _resolve("Panel", 73, MENU_CHUNK)
		_add_role("menu", menu)
		_add_art(menu, "SourceSaleMenu", MENU_RECT, MENU_CHUNK, "分類選單")
		if _menu_hover >= 0:
			_add_border("SourceSaleMenuHover", _menu_cell_rect(_menu_hover))
	var feedback := str(_model.get("feedback", ""))
	if not feedback.is_empty():
		_add_text("SourceSaleFeedback", feedback, Vector2(320, 430), Vector2(420, 40), 16, 1)

func _render_picker() -> void:
	match _category:
		"stock":
			_render_stock_picker()
		"property":
			_render_property_picker()
		"tool":
			_render_slot_picker()
		"card":
			_render_slot_picker()
		_:
			pass

func _render_stock_picker() -> void:
	var panel := _resolve("Panel", 73, int(CATEGORY_PICKER_CHUNK["stock"]))
	_add_role("stock_picker", panel)
	_add_art(panel, "SourceSaleStockPicker", STOCK_PANEL_RECT, int(CATEGORY_PICKER_CHUNK["stock"]), "商品選擇")
	var rows := _stock_rows()
	for index in range(mini(rows.size(), STOCK_ROW_LIMIT)):
		var record: Dictionary = rows[index]
		var center := Vector2(0, 80.0 + STOCK_ROW_HEIGHT * float(index))
		_add_text("SourceSaleStockName%d" % index, str(record.get("name", "")), center + Vector2(STOCK_NAME_X, 0), Vector2(140, 18), SOURCE_FONT_SIZE, 1)
		_add_text("SourceSaleStockQuantity%d" % index, str(record.get("quantity", 0)), center + Vector2(STOCK_QUANTITY_X, 0), Vector2(84, 18), SOURCE_FONT_SIZE, 2)
		_add_text("SourceSaleStockValue%d" % index, "%d元" % int(record.get("reference_value", 0)), center + Vector2(STOCK_VALUE_X, 0), Vector2(120, 18), SOURCE_FONT_SIZE, 2)
	var marked := _picker_pressed_row if _picker_pressed_row >= 0 else _picker_hover_row
	if marked >= 0 and marked < rows.size():
		var checker := _resolve("Panel", 73, CHECKER_CHUNK)
		_add_role("stock_checker", checker)
		var rect := Rect2(Vector2(STOCK_CHECKER_X - STOCK_CHECKER_SIZE.x / 2.0, 80.0 + STOCK_ROW_HEIGHT * float(marked) - STOCK_CHECKER_SIZE.y / 2.0), STOCK_CHECKER_SIZE)
		_add_art(checker, "SourceSaleStockChecker", rect, CHECKER_CHUNK, "已選")
	if _picker_pressed_close:
		_add_border("SourceSaleStockClose", STOCK_CLOSE_RECT)

func _render_property_picker() -> void:
	var panel := _resolve("Panel", 73, int(CATEGORY_PICKER_CHUNK["property"]))
	_add_role("property_picker", panel)
	_add_art(panel, "SourceSalePropertyPicker", PROPERTY_PANEL_RECT, int(CATEGORY_PICKER_CHUNK["property"]), "地產選擇")
	var tab := _resolve("Panel", 73, PAGE_TAB_CHUNK)
	_add_role("property_tab", tab)
	_add_art(tab, "SourceSalePropertyTab", Rect2(PROPERTY_TAB_RECT.position + Vector2(PROPERTY_TAB_WIDTH * float(_property_filter), 0), Vector2(PROPERTY_TAB_WIDTH, PROPERTY_TAB_RECT.size.y)), PAGE_TAB_CHUNK, PROPERTY_TAB_LABELS[_property_filter])
	for index in range(PROPERTY_TAB_COUNT):
		_add_text("SourceSalePropertyTabLabel%d" % index, PROPERTY_TAB_LABELS[index], Vector2(PROPERTY_TAB_RECT.position.x + PROPERTY_TAB_WIDTH * (float(index) + 0.5), PROPERTY_TAB_RECT.position.y + PROPERTY_TAB_RECT.size.y / 2.0), Vector2(80, 24), 20, 1, Color("#101010"))
	for index in range(PROPERTY_TABLE_LABELS.size()):
		_add_text("SourceSalePropertyHeader%d" % index, PROPERTY_TABLE_LABELS[index], Vector2(PROPERTY_TABLE_X[index], PROPERTY_HEADER_Y), Vector2(96, 24), 20, 1)
	var rows := _property_rows()
	var start := _property_page * PROPERTY_ROWS_PER_PAGE
	for index in range(PROPERTY_ROWS_PER_PAGE):
		var absolute := start + index
		if absolute >= rows.size():
			break
		var record: Dictionary = rows[absolute]
		var center_y := PROPERTY_ROWS_RECT.position.y + PROPERTY_ROW_HEIGHT * (float(index) + 0.5)
		var values := [
			str(record.get("location", "")),
			str(record.get("development", "")),
			"%d元" % int(record.get("reference_value", 0)),
			"%d元" % int(record.get("rent", 0)),
			str(int(record.get("lease", 0))) + "月",
		]
		for column in range(values.size()):
			_add_text("SourceSalePropertyCell%d_%d" % [index, column], values[column], Vector2(PROPERTY_TABLE_X[column], center_y), Vector2(96, 24), 20, 1)
	if _picker_pressed_arrow == 1 or _picker_hover_arrow == 1:
		_add_border("SourceSalePropertyUp", PROPERTY_UP_RECT)
	if _picker_pressed_arrow == 2 or _picker_hover_arrow == 2:
		_add_border("SourceSalePropertyDown", PROPERTY_DOWN_RECT)
	if _picker_pressed_close:
		_add_border("SourceSalePropertyClose", PROPERTY_CLOSE_RECT)

func _render_slot_picker() -> void:
	var chunk: int = int(CATEGORY_PICKER_CHUNK.get(_category, 3))
	var panel := _resolve("Panel", 73, chunk)
	_add_role("%s_picker" % _category, panel)
	_add_art(panel, "SourceSale%sPicker" % _category.capitalize(), PICKER_PANEL_RECT, chunk, CATEGORY_FALLBACK_LABEL.get(_category, ""))
	var items := _picker_items()
	for index in range(mini(items.size(), PICKER_SLOT_LIMIT)):
		var record: Dictionary = items[index]
		var column := index % PICKER_COLUMNS
		var row := index / PICKER_COLUMNS
		var cell_origin := PICKER_GRID_RECT.position + Vector2(PICKER_CELL.x * float(column), PICKER_CELL.y * float(row))
		if _category == "tool":
			var icon_chunk := clampi(int(record.get("source_id", 1)) - 1, 0, TOOL_ICON_COUNT - 1)
			var icon := _resolve("Panel", TOOL_ICON_RESOURCE, icon_chunk)
			_add_role("tool_icon_%d" % icon_chunk, icon)
			var anchor := Vector2(TOOL_ICON_X + PICKER_CELL.x * float(column), PICKER_ROW_CENTER_Y + PICKER_CELL.y * float(row))
			var icon_rect := _icon_rect(icon, anchor, Vector2(24, 24))
			_add_art(icon, "SourceSaleToolIcon%d" % index, icon_rect, icon_chunk, str(record.get("name", "")), TOOL_ICON_RESOURCE)
			_add_text("SourceSaleToolQuantity%d" % index, str(record.get("quantity", 0)), Vector2(TOOL_QUANTITY_X + PICKER_CELL.x * float(column), PICKER_ROW_CENTER_Y + PICKER_CELL.y * float(row)), Vector2(40, 16), SOURCE_FONT_SIZE, 2)
		else:
			_add_text("SourceSaleCardLabel%d" % index, str(record.get("name", "")), Vector2(PICKER_LABEL_CENTER_X + PICKER_CELL.x * float(column), PICKER_ROW_CENTER_Y + PICKER_CELL.y * float(row)), Vector2(68, 16), SOURCE_FONT_SIZE, 1)
		if _picker_pressed_slot == index:
			_add_border("SourceSaleSlotLatch%d" % index, Rect2(cell_origin, PICKER_CELL))
	if _picker_pressed_close:
		_add_border("SourceSalePickerClose", PICKER_CLOSE_RECT)

func _render_detail() -> void:
	var chunk: int = int(CATEGORY_DETAIL_CHUNK.get(_category, 6))
	var origin: Vector2 = CATEGORY_DETAIL_ORIGIN.get(_category, Vector2(224, 128))
	var detail_size: Vector2 = CATEGORY_DETAIL_SIZE.get(_category, Vector2(192, 224))
	var panel := _resolve("Panel", 73, chunk)
	_add_role("detail", panel)
	_add_art(panel, "SourceSaleDetail", Rect2(origin, detail_size), chunk, CATEGORY_FALLBACK_LABEL.get(_category, ""))
	var record := _selected_record()
	if record.is_empty():
		return
	var seller := _offer_seller(record)
	_add_text("SourceSaleDetailSeller", str(seller.get("name", str(record.get("seller_name", "")))), origin + Vector2(58, 40), Vector2(150, 18), SOURCE_FONT_SIZE, 1)
	_add_text("SourceSaleDetailName", str(record.get("name", "")), origin + Vector2(96, 92), Vector2(176, 18), SOURCE_FONT_SIZE, 1)
	var rows := _detail_rows(record)
	for index in range(rows.size()):
		var center_y := origin.y + 128.0 + 20.0 * float(index)
		_add_text("SourceSaleDetailLabel%d" % index, rows[index][0], Vector2(origin.x + 16, center_y), Vector2(72, 16), SOURCE_FONT_SIZE - 2, 0)
		_add_text("SourceSaleDetailValue%d" % index, rows[index][1], Vector2(origin.x + 178, center_y), Vector2(120, 16), SOURCE_FONT_SIZE - 2, 2)
	var baseline: float = float(CATEGORY_DETAIL_BASELINE.get(_category, 203))
	var own := int(record.get("seller_id", -1)) == int(_model.get("player_id", -1))
	_add_text("SourceSaleDetailPrimary", PRIMARY_LABEL_OWN if own else PRIMARY_LABEL_OTHER, Vector2(origin.x + DETAIL_PRIMARY_CENTER_X, origin.y + baseline), Vector2(DETAIL_BUTTON_WIDTH, 18), SOURCE_FONT_SIZE, 1)
	_add_text("SourceSaleDetailSecondary", SECONDARY_LABEL, Vector2(origin.x + DETAIL_SECONDARY_CENTER_X, origin.y + baseline), Vector2(DETAIL_BUTTON_WIDTH, 18), SOURCE_FONT_SIZE, 1)
	if _detail_pressed == 1:
		_add_border("SourceSaleDetailPrimaryLatch", _detail_rects()[0])
	elif _detail_pressed == 2:
		_add_border("SourceSaleDetailSecondaryLatch", _detail_rects()[1])

func _detail_rows(record: Dictionary) -> Array:
	match _category:
		"stock":
			return [["張數：", "%d張" % int(record.get("quantity",0))], ["市價：", "%d元" % int(record.get("reference_value",0))], ["賣價：", "%d元" % int(record.get("asking",0))]]
		"property":
			return [["地點：", str(record.get("location",""))], ["開發狀況：", str(record.get("development",""))], ["市價：", "%d元" % int(record.get("reference_value",0))], ["賣價：", "%d元" % int(record.get("asking",0))]]
		_:
			return [["市價：", "%d元" % int(record.get("reference_value",0))], ["賣價：", "%d元" % int(record.get("asking",0))]]

func _render_reference() -> void:
	var reference_y := float(_model.get("reference_y", REFERENCE_Y_DEFAULT))
	var rect := Rect2(REFERENCE_X, reference_y, REFERENCE_SIZE.x, REFERENCE_SIZE.y)
	var panel := _resolve("Panel", 73, REFERENCE_CHUNK)
	_add_role("reference", panel)
	_add_art(panel, "SourceSaleReference", rect, REFERENCE_CHUNK, "拍賣參考價")
	var record := _selected_record()
	var message := str(_model.get("reference_message", "請輸入欲拍賣的價格\n\n（市價：%d元）" % int(record.get("reference_value",0))))
	_add_text("SourceSaleReferenceMessage", message, Vector2(320, reference_y + 44), Vector2(180, 80), SOURCE_FONT_SIZE, 1, Color("#101010"))

# --------------------------------------------------------------------------
# Art helpers (mirror the accepted S20 SourceShopPanel resolver)

func _resolve(archive: String, resource: int, chunk: int) -> Dictionary:
	var key := "%s.%s.%d.%d" % [_edition, archive, resource, chunk]
	var frame: Dictionary = {}
	var texture: Texture2D = null
	if _visual_accessor is Object and (_visual_accessor as Object).has_method("ui"):
		var value: Variant = (_visual_accessor as Object).call("ui", _edition, archive, resource, chunk)
		if value is Dictionary:
			frame = value.duplicate(true)
	if frame.is_empty() and _visual_accessor is Dictionary:
		var value: Variant = (_visual_accessor as Dictionary).get(key, null)
		if value is Dictionary:
			frame = value.duplicate(true)
	if frame.get("ui_texture") is Texture2D:
		texture = frame.ui_texture
	if texture == null and frame.get("texture") is Texture2D:
		texture = frame.texture
	if texture == null and _visual_accessor is Object and (_visual_accessor as Object).has_method("texture") and not frame.is_empty():
		var value: Variant = (_visual_accessor as Object).call("texture", frame)
		if value is Texture2D:
			texture = value
	return {"frame": frame, "texture": texture}

func _add_role(role: String, result: Dictionary) -> void:
	_source_art_status[role] = result.get("texture") is Texture2D

func _resolve_character(character_id: int, direction: int) -> Dictionary:
	var frame: Dictionary = {}
	var texture: Texture2D = null
	if _visual_accessor is Object and (_visual_accessor as Object).has_method("character"):
		var value: Variant = (_visual_accessor as Object).call("character", _edition, character_id, direction)
		if value is Dictionary:
			frame = value.duplicate(true)
	if frame.is_empty() and _visual_accessor is Dictionary:
		var key := "%s.character.%d.%d" % [_edition, character_id, direction]
		var value: Variant = (_visual_accessor as Dictionary).get(key, null)
		if value is Dictionary:
			frame = value.duplicate(true)
	if frame.get("ui_texture") is Texture2D:
		texture = frame.ui_texture
	if texture == null and frame.get("texture") is Texture2D:
		texture = frame.texture
	if texture == null and _visual_accessor is Object and (_visual_accessor as Object).has_method("texture") and not frame.is_empty():
		var value: Variant = (_visual_accessor as Object).call("texture", frame)
		if value is Texture2D:
			texture = value
	return {"frame": frame, "texture": texture}

func _add_portrait(result: Dictionary, node_name: String, slot: Rect2, character_id: int) -> void:
	if not result.get("texture") is Texture2D:
		_add_placeholder(node_name, slot, FALLBACK_SLOT)
		return
	var art := TextureRect.new()
	art.name = node_name
	art.position = slot.position
	art.size = slot.size
	art.texture = result.texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_meta("source_character_id", character_id)
	art.set_meta("source_direction", PORTRAIT_DIRECTION)
	art.set_meta("source_frame", (result.get("frame", {}) as Dictionary).duplicate(true))
	_surface.add_child(art)

func _add_art(result: Dictionary, node_name: String, rect: Rect2, chunk: int, fallback_label: String, resource: int = 73) -> void:
	if not result.get("texture") is Texture2D:
		_add_placeholder(node_name, rect, FALLBACK_PANEL)
		if not fallback_label.is_empty():
			_add_text(node_name + "Fallback", fallback_label, rect.position + rect.size / 2.0, Vector2(minf(rect.size.x, 200.0), 18), 14, 1, Color("#d8e4dc"))
		return
	var art := TextureRect.new()
	art.name = node_name
	art.position = rect.position
	art.size = rect.size
	art.texture = result.texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_meta("source_resource", resource)
	art.set_meta("source_chunk", chunk)
	art.set_meta("source_frame", (result.get("frame", {}) as Dictionary).duplicate(true))
	_surface.add_child(art)

func _add_placeholder(node_name: String, rect: Rect2, color: Color) -> void:
	var fallback := ColorRect.new()
	fallback.name = node_name
	fallback.position = rect.position
	fallback.size = rect.size
	fallback.color = color
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(fallback)

func _add_border(node_name: String, rect: Rect2) -> void:
	var border := ColorRect.new()
	border.name = node_name
	border.position = rect.position
	border.size = rect.size
	border.color = Color(FALLBACK_HILITE.r, FALLBACK_HILITE.g, FALLBACK_HILITE.b, 0.28)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(border)

func _icon_rect(result: Dictionary, anchor: Vector2, fallback: Vector2) -> Rect2:
	var size := fallback
	var frame: Variant = result.get("frame", {})
	if frame is Dictionary:
		var logical: Variant = frame.get("logical", {})
		if logical is Dictionary and logical.has("width") and logical.has("height"):
			size = Vector2(float(logical.width), float(logical.height))
	return Rect2(anchor - size / 2.0, size)

func _add_text(node_name: String, value: String, anchor: Vector2, extent: Vector2, font_size: int, align: int, color := SOURCE_TEXT) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = value
	label.size = extent
	label.position = anchor - Vector2(extent.x / 2.0 if align == 1 else (extent.x if align == 2 else 0.0), extent.y / 2.0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", SOURCE_OUTLINE)
	label.add_theme_constant_override("outline_size", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if align == 1 else (HORIZONTAL_ALIGNMENT_RIGHT if align == 2 else HORIZONTAL_ALIGNMENT_LEFT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("source_font_height", font_size)
	label.set_meta("source_font_foreground", color)
	label.set_meta("source_font_outline", SOURCE_OUTLINE)
	label.set_meta("source_font_flags", SOURCE_FONT_FLAGS)
	_surface.add_child(label)
	return label
