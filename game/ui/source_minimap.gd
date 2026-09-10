extends Control
class_name RichmanSourceMinimap

## Small source-oriented map view.  It only projects the public board snapshot;
## panning is sent back to MainUI so this module never mutates simulation data.

signal pan_requested(delta: Vector2)
signal node_selected(index: int)

const PLAYER_COLORS := [
	Color("#ef6a65"),
	Color("#4ba6e8"),
	Color("#e6b84f"),
	Color("#73c989"),
]

var snapshot: Dictionary = {}
var map_definition: Dictionary = {}
var board_view: Control
var _dragging := false
var _last_pointer := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(200.0, 200.0)
	set_process_input(false)


func set_board_view(view: Control) -> void:
	board_view = view
	queue_redraw()


func set_snapshot(next_snapshot: Dictionary, next_definition: Dictionary = {}) -> void:
	snapshot = next_snapshot.duplicate(true)
	map_definition = next_definition.duplicate(true)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_last_pointer = event.position
			_focus_at(event.position)
		else:
			_dragging = false
		accept_event()
		return
	if event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = event.position - _last_pointer
		_last_pointer = event.position
		if delta.length_squared() > 0.0:
			pan_requested.emit(-delta * 2.2)
			queue_redraw()
		accept_event()


func _focus_at(pointer: Vector2) -> void:
	var points := _board_points()
	if points.is_empty():
		return
	var nearest := -1
	var nearest_distance := INF
	for index in range(points.size()):
		var distance := pointer.distance_squared_to(points[index])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = index
	if nearest >= 0:
		node_selected.emit(nearest)
	if board_view == null or not board_view.has_method("pan_by"):
		return
	var center := size * 0.5
	var scale := maxf(0.01, minf(size.x, size.y) / 2.0)
	var offset := (pointer - center) / scale
	var board_size := board_view.size
	if board_size.x <= 0.0 or board_size.y <= 0.0:
		return
	pan_requested.emit(-Vector2(offset.x * board_size.x, offset.y * board_size.y))


func _board_points() -> Array[Vector2]:
	var board: Variant = map_definition.get("board", [])
	if not board is Array or board.is_empty():
		board = snapshot.get("board", [])
	if not board is Array or board.is_empty():
		return []
	var coordinates: Array[Vector2] = []
	var has_coordinates := false
	for value in board:
		if value is Dictionary and value.has("x") and value.has("y"):
			has_coordinates = true
			break
	if has_coordinates:
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for value in board:
			var tile: Dictionary = value if value is Dictionary else {}
			var point := Vector2(float(tile.get("x", 0)), float(tile.get("y", 0)))
			coordinates.append(point)
			minimum.x = minf(minimum.x, point.x)
			minimum.y = minf(minimum.y, point.y)
			maximum.x = maxf(maximum.x, point.x)
			maximum.y = maxf(maximum.y, point.y)
		return _normalize_points(coordinates, Rect2(minimum, maximum - minimum))
	var perimeter: Array[Vector2] = []
	var side := 8
	while side < 14 and 4 * (side - 1) < board.size():
		side += 1
	var cells: Array[Vector2] = []
	for x in range(side):
		cells.append(Vector2(x, 0))
	for y in range(1, side):
		cells.append(Vector2(side - 1, y))
	for x in range(side - 2, -1, -1):
		cells.append(Vector2(x, side - 1))
	for y in range(side - 2, 0, -1):
		cells.append(Vector2(0, y))
	for index in range(board.size()):
		perimeter.append(cells[index % cells.size()])
	return _normalize_points(perimeter, Rect2(Vector2.ZERO, Vector2(side - 1, side - 1)))


func _normalize_points(points: Array[Vector2], bounds: Rect2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var extent := Vector2(maxf(1.0, bounds.size.x), maxf(1.0, bounds.size.y))
	for point in points:
		result.append(Vector2(12.0, 12.0) + (point - bounds.position) / extent * (size - Vector2(24.0, 24.0)))
	return result


func _draw() -> void:
	var points := _board_points()
	var board: Variant = map_definition.get("board", [])
	if not board is Array or board.is_empty():
		board = snapshot.get("board", [])
	if points.is_empty() or not board is Array:
		return
	for index in range(board.size()):
		var tile: Dictionary = board[index] if board[index] is Dictionary else {}
		for neighbor_value in tile.get("adjacent", []):
			var neighbor := int(neighbor_value)
			if neighbor <= index or neighbor < 0 or neighbor >= points.size():
				continue
			draw_line(points[index], points[neighbor], Color(0.92, 0.86, 0.58, 0.6), 1.0, true)
	for index in range(points.size()):
		var tile: Dictionary = board[index] if board[index] is Dictionary else {}
		var kind := str(tile.get("kind", "road"))
		var color := Color("#f2d68d") if kind in ["start", "stock", "bank"] else Color("#d7e5db")
		if kind in ["property", "facility"]:
			color = Color("#74b9a8")
		draw_circle(points[index], 2.6, color)
	var players: Array = snapshot.get("players", [])
	for player_index in range(players.size()):
		var player: Dictionary = players[player_index] if players[player_index] is Dictionary else {}
		var position := int(player.get("position", -1))
		if position < 0 or position >= points.size():
			continue
		draw_circle(points[position], 4.0, PLAYER_COLORS[player_index % PLAYER_COLORS.size()])
	var visible: Array = []
	if board_view != null and board_view.has_method("visible_node_indices"):
		var candidate: Variant = board_view.call("visible_node_indices")
		if candidate is Array:
			visible = candidate
	if visible.is_empty() or visible.size() >= points.size():
		draw_rect(Rect2(Vector2(10.0, 10.0), size - Vector2(20.0, 20.0)), Color("#f1d28a"), false, 1.0)
	else:
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for value in visible:
			var index := int(value)
			if index < 0 or index >= points.size():
				continue
			minimum.x = minf(minimum.x, points[index].x)
			minimum.y = minf(minimum.y, points[index].y)
			maximum.x = maxf(maximum.x, points[index].x)
			maximum.y = maxf(maximum.y, points[index].y)
		if minimum.x != INF:
			var viewport := Rect2(minimum - Vector2(6.0, 6.0), maximum - minimum + Vector2(12.0, 12.0))
			draw_rect(viewport, Color("#f1d28a"), false, 1.4)
