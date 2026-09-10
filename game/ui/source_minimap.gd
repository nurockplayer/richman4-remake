extends Control
class_name RichmanSourceMinimap

## Small source-oriented map view.  It only projects the public board snapshot;
## panning is sent back to MainUI so this module never mutates simulation data.

const OriginalVisuals = preload("res://game/platform/original_visuals.gd")

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
var _visuals = OriginalVisuals.new()
var _source_scene: Dictionary = {}
var _source_scene_texture: Texture2D
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
	_source_scene = _visuals.scene_for(map_definition)
	_source_scene_texture = _visuals.texture(_source_scene.get("image", {}))
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
	# MainUI owns the board camera and centers the selected node in response to
	# node_selected.  Do not emit a second approximate pan from the minimap;
	# that would apply the camera movement twice and drift after rotation.


func _board_points() -> Array[Vector2]:
	var board: Variant = map_definition.get("board", [])
	if not board is Array or board.is_empty():
		board = snapshot.get("board", [])
	if not board is Array or board.is_empty():
		return []
	if board_view != null and board_view.has_method("get_map_bounds") and board_view.has_method("map_to_minimap"):
		var map_bounds: Variant = board_view.call("get_map_bounds")
		if map_bounds is Rect2 and map_bounds.has_area():
			var projected: Array[Vector2] = []
			var minimap_rect := Rect2(Vector2.ZERO, size)
			for value in board:
				if not value is Dictionary or not value.has("x") or not value.has("y"):
					projected.clear()
					break
				var tile: Dictionary = value
				var coordinate := Vector2(float(tile.get("x", 0)), float(tile.get("y", 0)))
				var point: Variant = board_view.call("map_to_minimap", coordinate, minimap_rect)
				if not point is Vector2:
					projected.clear()
					break
				projected.append(point)
			if projected.size() == board.size():
				return projected
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
	if _source_scene_texture != null and _visuals.world_rect(_source_scene).has_area():
		draw_texture_rect(_source_scene_texture, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#183f42"), true)
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
	var viewport_polygon: Array[Vector2] = _viewport_polygon()
	if viewport_polygon.size() < 3:
		draw_rect(Rect2(Vector2(10.0, 10.0), size - Vector2(20.0, 20.0)), Color("#f1d28a"), false, 1.0)
	else:
		var outline := PackedVector2Array(viewport_polygon)
		outline.append(viewport_polygon[0])
		draw_polyline(outline, Color("#f1d28a"), 1.4, true)


func _viewport_polygon() -> Array[Vector2]:
	if board_view == null or not board_view.has_method("get_minimap_viewport_polygon") or not board_view.has_method("get_map_bounds"):
		return []
	var map_bounds: Variant = board_view.call("get_map_bounds")
	if not map_bounds is Rect2 or not map_bounds.has_area():
		return []
	var polygon_value: Variant = board_view.call("get_minimap_viewport_polygon", Rect2(Vector2.ZERO, size))
	if not polygon_value is Array or polygon_value.size() < 3:
		return []
	var polygon: Array[Vector2] = []
	for point_value in polygon_value:
		if not point_value is Vector2:
			return []
		polygon.append(point_value)
	return polygon
