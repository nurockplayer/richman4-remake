extends Control
class_name RichmanBoardView

## A clean, asset-free board renderer for the desktop build.
##
## The original game's packed visual assets remain local to the owner's
## installation.  This view deliberately draws the board with Godot controls
## and vector primitives so the game is usable on a clean checkout while the
## content and rules are restored incrementally.

signal tile_selected(index: int)

const BOARD_INSET := 24.0
const PLAYER_COLORS := [
	Color("#ef6a65"),
	Color("#4ba6e8"),
	Color("#e6b84f"),
	Color("#73c989"),
]

var board_data: Array = []
var players_data: Array = []
var current_player_index := 0
var selected_index := -1
var _cell_rects: Array[Rect2] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(true)
	queue_redraw()

func set_game_data(next_board: Array, next_players: Array, current_index: int) -> void:
	board_data = next_board
	players_data = next_players
	current_player_index = current_index
	if selected_index >= board_data.size():
		selected_index = -1
	queue_redraw()

func select_tile(index: int) -> void:
	selected_index = index if index >= 0 and index < board_data.size() else -1
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for index in range(_cell_rects.size()):
			if _cell_rects[index].has_point(event.position):
				selected_index = index
				tile_selected.emit(index)
				queue_redraw()
				accept_event()
				return

func _draw() -> void:
	var view_size := size
	if view_size.x < 40.0 or view_size.y < 40.0:
		return

	var board_count: int = max(1, board_data.size())
	var side := 8
	while side < 14 and 4 * (side - 1) < board_count:
		side += 1
	var tile_size: float = min((view_size.x - BOARD_INSET * 2.0) / float(side), (view_size.y - BOARD_INSET * 2.0) / float(side))
	var board_size := Vector2(tile_size * side, tile_size * side)
	var origin := (view_size - board_size) * 0.5

	var outer_rect := Rect2(origin - Vector2(7.0, 7.0), board_size + Vector2(14.0, 14.0))
	_draw_style_box(outer_rect, Color("#162538"), Color("#304b61"), 18.0, 2.0)
	var field_rect := Rect2(origin + Vector2(tile_size, tile_size), board_size - Vector2(tile_size * 2.0, tile_size * 2.0))
	_draw_style_box(field_rect, Color("#153b3d"), Color("#2f6660"), 13.0, 1.0)

	# Subtle field decoration keeps the centre readable without an image asset.
	draw_circle(field_rect.get_center(), min(field_rect.size.x, field_rect.size.y) * 0.26, Color("#1a4848"))
	draw_circle(field_rect.get_center(), min(field_rect.size.x, field_rect.size.y) * 0.19, Color("#205252"))
	_draw_text("大富翁 4", field_rect.position + Vector2(0.0, field_rect.size.y * 0.48), field_rect.size.x, 22, Color("#d9e8d7"), HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text("城市地圖", field_rect.position + Vector2(0.0, field_rect.size.y * 0.48 + 27.0), field_rect.size.x, 11, Color("#8ab5a8"), HORIZONTAL_ALIGNMENT_CENTER)

	var cells := _perimeter_cells(side)
	_cell_rects.clear()
	_cell_rects.resize(board_count)
	for index in range(board_count):
		var grid_cell: Vector2i = cells[index % cells.size()]
		var cell_rect := Rect2(origin + Vector2(grid_cell) * tile_size + Vector2(2.0, 2.0), Vector2(tile_size - 4.0, tile_size - 4.0))
		_cell_rects[index] = cell_rect
		_draw_tile(cell_rect, index, board_data[index] if index < board_data.size() else {})

	_draw_players()

func _draw_tile(cell_rect: Rect2, index: int, tile: Dictionary) -> void:
	var kind := String(tile.get("kind", "property"))
	var base_color := _tile_color(kind)
	var is_selected := selected_index == index
	var is_current := false
	var owner := int(tile.get("owner", -1))
	if owner >= 0:
		is_current = owner == current_player_index

	var border := Color("#f1d28a") if is_selected else Color("#34536a")
	var border_width := 2.5 if is_selected else 1.0
	_draw_style_box(cell_rect, Color("#21354a"), border, 8.0, border_width)
	var color_band := Rect2(cell_rect.position + Vector2(1.0, 1.0), Vector2(cell_rect.size.x - 2.0, min(8.0, cell_rect.size.y * 0.2)))
	draw_rect(color_band, base_color)
	if owner >= 0:
		var owner_color: Color = PLAYER_COLORS[owner % PLAYER_COLORS.size()]
		draw_rect(Rect2(cell_rect.position + Vector2(1.0, color_band.size.y + 1.0), Vector2(4.0, cell_rect.size.y - color_band.size.y - 2.0)), owner_color)
	if is_current:
		draw_circle(cell_rect.position + Vector2(cell_rect.size.x - 10.0, 15.0), 4.0, Color("#f1d28a"))

	var tile_number := str(index + 1).pad_zeros(2)
	_draw_text(tile_number, cell_rect.position + Vector2(7.0, 22.0), cell_rect.size.x - 12.0, 9, Color("#89a5b4"), HORIZONTAL_ALIGNMENT_LEFT)
	var name := String(tile.get("name", _fallback_tile_name(index, kind)))
	_draw_text(_short_text(name, 6), cell_rect.position + Vector2(6.0, cell_rect.size.y * 0.61), cell_rect.size.x - 12.0, 11, Color("#edf3f0"), HORIZONTAL_ALIGNMENT_CENTER)

	if kind == "property":
		var level := int(tile.get("building_level", 0))
		for dot_index in range(min(level, 4)):
			draw_circle(cell_rect.position + Vector2(9.0 + dot_index * 8.0, cell_rect.size.y - 10.0), 2.4, Color("#e7ad57"))
		var price := int(tile.get("cost", 0))
		if price > 0:
			_draw_text("$" + _compact_money(price), cell_rect.position + Vector2(6.0, cell_rect.size.y - 5.0), cell_rect.size.x - 12.0, 8, Color("#8fb9aa"), HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_draw_text(_kind_label(kind), cell_rect.position + Vector2(6.0, cell_rect.size.y - 6.0), cell_rect.size.x - 12.0, 8, Color("#a9c4b9"), HORIZONTAL_ALIGNMENT_CENTER)

func _draw_players() -> void:
	var positions := {}
	for player_index in range(players_data.size()):
		var player: Dictionary = players_data[player_index] if players_data[player_index] is Dictionary else {}
		var tile_index := int(player.get("position", 0))
		if tile_index < 0 or tile_index >= _cell_rects.size():
			continue
		if not positions.has(tile_index):
			positions[tile_index] = []
		positions[tile_index].append(player_index)

	for tile_index in positions:
		var cell_rect: Rect2 = _cell_rects[int(tile_index)]
		var occupants: Array = positions[tile_index]
		for occupant_index in range(occupants.size()):
			var player_index: int = occupants[occupant_index]
			var angle: float = TAU * float(occupant_index) / max(1.0, float(occupants.size()))
			var offset: Vector2 = Vector2(cos(angle), sin(angle)) * min(9.0, cell_rect.size.x * 0.16)
			var center: Vector2 = cell_rect.get_center() + offset + Vector2(0.0, 5.0)
			var player_color: Color = PLAYER_COLORS[player_index % PLAYER_COLORS.size()]
			var is_active := player_index == current_player_index
			draw_circle(center + Vector2(0.0, 2.0), 8.0 if is_active else 6.5, Color(0.0, 0.0, 0.0, 0.35))
			draw_circle(center, 8.0 if is_active else 6.5, player_color)
			draw_arc(center, 8.0 if is_active else 6.5, 0.0, TAU, 20, Color("#f7f3df"), 1.4 if is_active else 0.8)
			_draw_text(str(player_index + 1), center + Vector2(-5.0, 4.0), 10.0, 9, Color("#173047"), HORIZONTAL_ALIGNMENT_CENTER)

func _perimeter_cells(side: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(side):
		cells.append(Vector2i(x, 0))
	for y in range(1, side):
		cells.append(Vector2i(side - 1, y))
	for x in range(side - 2, -1, -1):
		cells.append(Vector2i(x, side - 1))
	for y in range(side - 2, 0, -1):
		cells.append(Vector2i(0, y))
	return cells

func _tile_color(kind: String) -> Color:
	match kind:
		"start":
			return Color("#d79b55")
		"event":
			return Color("#bc78cf")
		"tax":
			return Color("#df6e6e")
		"bank":
			return Color("#5ca9a0")
		"stock":
			return Color("#e2b25b")
		"rest":
			return Color("#728c9c")
		_:
			return Color("#4d83a5")

func _kind_label(kind: String) -> String:
	match kind:
		"start":
			return "起點"
		"event":
			return "事件"
		"tax":
			return "稅務"
		"bank":
			return "銀行"
		"stock":
			return "股市"
		"rest":
			return "休息"
		_:
			return "地點"

func _fallback_tile_name(index: int, kind: String) -> String:
	if kind != "property":
		return _kind_label(kind)
	return "街區 %02d" % (index + 1)

func _compact_money(value: int) -> String:
	if abs(value) >= 1000000:
		return "%.1fM" % (float(value) / 1000000.0)
	if abs(value) >= 1000:
		return "%.1fk" % (float(value) / 1000.0)
	return str(value)

func _short_text(value: String, max_length: int) -> String:
	if value.length() <= max_length:
		return value
	return value.substr(0, max(1, max_length - 1)) + "…"

func _draw_text(text: String, position: Vector2, width: float, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	draw_string(font, position, text, alignment, width, font_size, color)

func _draw_style_box(rect: Rect2, background: Color, border: Color, radius: float, border_width: float) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(int(border_width))
	style.set_corner_radius_all(int(radius))
	draw_style_box(style, rect)
