extends Control
class_name RichmanBoardView

## Draws the legacy forty tile perimeter or a local original map graph.
## Geometry is read from board[].x/y/adjacent; mutable values come from the
## current snapshot supplied by MainUI.

signal tile_selected(index: int)
signal route_selected(next_index: int)

const BOARD_INSET := 24.0
const MIN_ZOOM := 0.55
const MAX_ZOOM := 3.2
const PLAYER_COLORS := [
	Color("#ef6a65"),
	Color("#4ba6e8"),
	Color("#e6b84f"),
	Color("#73c989"),
]

const OriginalVisuals = preload("res://game/platform/original_visuals.gd")
var visuals = OriginalVisuals.new()
var _scene: Dictionary = {}
var _background: Texture2D
var _scene_draws: Array = []
var _graph_fallback_edges := false
var _focused_player_position := Vector2i(-1, -1)
var _focused_map_identity := ""
var _focused_viewport_size := Vector2.ZERO

var board_data: Array = []
var players_data: Array = []
var current_player_index := 0
var selected_index := -1
var route_options: Array = []
var roadblocks_data: Dictionary = {}
var map_definition: Dictionary = {}
var preview_mode := false
var map_zoom := 1.0
var map_pan := Vector2.ZERO

var _cell_rects: Array[Rect2] = []
var _node_positions: Array = []
var _node_radii: Array = []
var _dragging := false
var _drag_button := MOUSE_BUTTON_NONE
var _drag_start := Vector2.ZERO
var _pan_start := Vector2.ZERO
var _layout_size := Vector2.ZERO

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(true)
	queue_redraw()

func set_game_data(next_board: Array, next_players: Array, current_index: int, definition: Dictionary = {}, next_route_options: Array = [], next_roadblocks: Dictionary = {}) -> void:
	board_data = next_board.duplicate(true)
	players_data = next_players.duplicate(true)
	current_player_index = current_index
	route_options = next_route_options.duplicate(true)
	roadblocks_data = next_roadblocks.duplicate(true)
	if not definition.is_empty():
		_reset_for_geometry_change(definition)
		map_definition = definition.duplicate(true)
		preview_mode = false
	elif _has_coordinate_board(next_board):
		_reset_for_geometry_change({"board": next_board})
		map_definition = {"board": next_board.duplicate(true)}
		preview_mode = false
	if selected_index >= _geometry_board().size():
		selected_index = -1
	_layout_size = Vector2.ZERO
	queue_redraw()

func _focus_moving_player() -> void:
	if size.x < 40 or size.y < 40:
		return
	var map_identity := str(map_definition.get("id", ""))
	var position := _current_position()
	var identity := Vector2i(current_player_index, position)
	if (identity == _focused_player_position and map_identity == _focused_map_identity and size == _focused_viewport_size) or position < 0 or position >= _geometry_board().size():
		return
	_focused_player_position = identity
	_focused_map_identity = map_identity
	_focused_viewport_size = size
	var scene: Dictionary = visuals.scene_for(map_definition)
	if scene.is_empty() or visuals.texture(scene.get("image")) == null:
		return
	map_zoom = maxf(map_zoom, 1.8)
	var tile: Dictionary = _geometry_board()[position]
	var bounds := _map_bounds(_geometry_board())
	var point := Vector2(float(tile.get("x", 0)), float(tile.get("y", 0)))
	map_pan = -(point - bounds.get_center()) * _map_scale() * map_zoom
	_layout_size = Vector2.ZERO

func _reset_for_geometry_change(definition: Dictionary) -> void:
	if _geometry_signature(map_definition) != _geometry_signature(definition):
		_focused_player_position = Vector2i(-1, -1)
		reset_view()

func _geometry_signature(definition: Dictionary) -> Array:
	var result: Array = [definition.get("id", ""), definition.get("source", {})]
	for tile in definition.get("board", []):
		if tile is Dictionary:
			result.append([tile.get("x"), tile.get("y"), tile.get("adjacent", [])])
	return result


func set_map_definition(definition: Dictionary, is_preview := true) -> void:
	_reset_for_geometry_change(definition)
	map_definition = definition.duplicate(true)
	preview_mode = is_preview
	var geometry: Variant = map_definition.get("board", [])
	if geometry is Array:
		board_data = geometry.duplicate(true)
	if is_preview:
		players_data = []
		route_options = []
		roadblocks_data = {}
	if selected_index >= _geometry_board().size():
		selected_index = -1
	_layout_size = Vector2.ZERO
	queue_redraw()

func set_preview_definition(definition: Dictionary) -> void:
	set_map_definition(definition, true)

func clear_map_definition() -> void:
	reset_view()
	map_definition = {}
	roadblocks_data = {}
	_focused_player_position = Vector2i(-1, -1)
	preview_mode = false
	_layout_size = Vector2.ZERO
	queue_redraw()

func select_tile(index: int) -> void:
	selected_index = index if index >= 0 and index < _geometry_board().size() else -1
	queue_redraw()

func select_at_position(position: Vector2) -> int:
	var index := _tile_at_position(position)
	if index >= 0:
		_activate_tile(index)
	return index

func get_screen_position_for_index(index: int) -> Vector2:
	if is_original_map():
		_layout_map()
		if index < 0 or index >= _node_positions.size():
			return Vector2.ZERO
		return _node_positions[index]
	_layout_legacy_cells()
	if index < 0 or index >= _cell_rects.size():
		return Vector2.ZERO
	return _cell_rects[index].get_center()

func get_zoom() -> float:
	return map_zoom

func visible_node_indices() -> Array:
	var visible: Array = []
	if not is_original_map() or size.x < 40 or size.y < 40:
		return visible
	_layout_map()
	var viewport := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	for index in range(_node_positions.size()):
		if viewport.has_point(_node_positions[index]):
			visible.append(index)
	return visible

func set_zoom(value: float, focus := Vector2.ZERO) -> void:
	if not is_original_map():
		return
	_layout_map()
	var actual_focus := focus if focus != Vector2.ZERO else size * 0.5
	var map_point := _screen_to_map(actual_focus)
	map_zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	var projected := _map_to_screen(map_point)
	map_pan += actual_focus - projected
	_layout_size = Vector2.ZERO
	queue_redraw()

func zoom_by(factor: float, focus := Vector2.ZERO) -> void:
	set_zoom(map_zoom * factor, focus)

func pan_by(delta: Vector2) -> void:
	if not is_original_map():
		return
	map_pan += delta
	_layout_size = Vector2.ZERO
	queue_redraw()

func reset_view() -> void:
	map_zoom = 1.0
	map_pan = Vector2.ZERO
	_layout_size = Vector2.ZERO
	queue_redraw()

func is_original_map() -> bool:
	var geometry := _geometry_board()
	return not geometry.is_empty() and _tile_has_coordinates(geometry[0])

func board_mode() -> String:
	return "original" if is_original_map() else "legacy"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_by(1.12, event.position)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_by(1.0 / 1.12, event.position)
			accept_event()
			return
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				_dragging = true
				_drag_button = event.button_index
				_drag_start = event.position
				_pan_start = map_pan
			else:
				_dragging = false
				_drag_button = MOUSE_BUTTON_NONE
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var index := select_at_position(event.position)
			if index >= 0:
				accept_event()
			return
	if event is InputEventMouseMotion and _dragging and _drag_button in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		map_pan = _pan_start + event.position - _drag_start
		_layout_size = Vector2.ZERO
		queue_redraw()
		accept_event()

func _draw() -> void:
	if size.x < 40.0 or size.y < 40.0:
		return
	if is_original_map():
		_draw_original_board()
	else:
		_draw_legacy_board()

func _draw_legacy_board() -> void:
	_layout_legacy_cells()
	var board_count: int = max(1, board_data.size())
	var side := 8
	while side < 14 and 4 * (side - 1) < board_count:
		side += 1
	var tile_size := _legacy_tile_size(side)
	var board_size := Vector2(tile_size * side, tile_size * side)
	var origin := (size - board_size) * 0.5
	var outer_rect := Rect2(origin - Vector2(7.0, 7.0), board_size + Vector2(14.0, 14.0))
	_draw_style_box(outer_rect, Color("#162538"), Color("#304b61"), 18.0, 2.0)
	var field_rect := Rect2(origin + Vector2(tile_size, tile_size), board_size - Vector2(tile_size * 2.0, tile_size * 2.0))
	_draw_style_box(field_rect, Color("#153b3d"), Color("#2f6660"), 13.0, 1.0)
	draw_circle(field_rect.get_center(), min(field_rect.size.x, field_rect.size.y) * 0.26, Color("#1a4848"))
	draw_circle(field_rect.get_center(), min(field_rect.size.x, field_rect.size.y) * 0.19, Color("#205252"))
	_draw_text("大富翁 4", field_rect.position + Vector2(0.0, field_rect.size.y * 0.48), field_rect.size.x, 22, Color("#d9e8d7"), HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text("城市地圖", field_rect.position + Vector2(0.0, field_rect.size.y * 0.48 + 27.0), field_rect.size.x, 11, Color("#8ab5a8"), HORIZONTAL_ALIGNMENT_CENTER)
	for index in range(board_count):
		var cell_rect: Rect2 = _cell_rects[index]
		_draw_tile(cell_rect, index, board_data[index] if index < board_data.size() else {})
	_draw_players()

func _draw_original_board() -> void:
	_focus_moving_player()
	_layout_map()
	var geometry := _geometry_board()
	var frame := Rect2(Vector2(8.0, 8.0), size - Vector2(16.0, 16.0))
	_draw_style_box(frame, Color("#11283a"), Color("#36546b"), 14.0, 1.0)
	_scene = visuals.scene_for(map_definition)
	_background = visuals.texture(_scene.get("image"))
	if _background != null:
		var bounds: Rect2 = visuals.world_rect(_scene)
		draw_texture_rect(_background, Rect2(_map_to_screen(bounds.position), bounds.size * _map_scale() * map_zoom), false)
	_graph_fallback_edges = _background == null or _road_icons_missing(geometry)
	_draw_text("原版路網" if not preview_mode else "原版地圖預覽", Vector2(18.0, 28.0), size.x - 36.0, 13, Color("#d9e8d7"), HORIZONTAL_ALIGNMENT_LEFT)
	_draw_text("滾輪縮放 · 中鍵／右鍵平移", Vector2(18.0, 47.0), size.x - 36.0, 9, Color("#8fb0bc"), HORIZONTAL_ALIGNMENT_LEFT)
	for index in range(geometry.size()):
		var tile: Dictionary = geometry[index] if geometry[index] is Dictionary else {}
		var from: Vector2 = _node_positions[index]
		for neighbor_value in _as_array(tile.get("adjacent", [])):
			var neighbor := int(neighbor_value)
			if neighbor < 0 or neighbor >= geometry.size() or neighbor <= index:
				continue
			if _graph_fallback_edges:
				draw_line(from, _node_positions[neighbor], Color("#638697"), 2.0, true)
	var current_position := _current_position()
	if current_position >= 0 and current_position < _node_positions.size():
		for option in route_options:
			var next_index := int(option)
			if next_index >= 0 and next_index < _node_positions.size():
				draw_line(_node_positions[current_position], _node_positions[next_index], Color("#e0a958"), 4.0, true)
	if _background == null:
		for index in range(geometry.size()):
			_draw_original_node(index, _merged_tile(index), _node_positions[index], _node_radii[index])
	_scene_draws.clear()
	_draw_original_node_icons(geometry)
	_draw_original_houses()
	_draw_original_players()
	_scene_draws.sort_custom(func(a, b):
		var a_is_road: bool = a.get("kind", "") == "road_icon"
		var b_is_road: bool = b.get("kind", "") == "road_icon"
		if a_is_road != b_is_road:
			return a_is_road
		if a_is_road:
			return a.get("center", Vector2.ZERO).y < b.get("center", Vector2.ZERO).y
		if is_equal_approx(float(a.get("center", Vector2.ZERO).y), float(b.get("center", Vector2.ZERO).y)):
			return int(a.get("layer", 1)) < int(b.get("layer", 1))
		return a.get("center", Vector2.ZERO).y < b.get("center", Vector2.ZERO).y
	)
	for job in _scene_draws:
		var painted := _draw_sprite(job.frame, job.center, _map_scale() * map_zoom)
		if not painted:
			_draw_scene_fallback(job)
		if painted and job.has("color"):
			draw_arc(job.center, 8.0, 0.0, TAU, 24, job.color, 2.0)
	if _background != null:
		for index in range(geometry.size()):
			_draw_original_node(index, _merged_tile(index), _node_positions[index], _node_radii[index])
	_draw_roadblocks()

func _draw_roadblocks() -> void:
	for key in roadblocks_data:
		if not str(key).is_valid_int():
			continue
		var index := int(key)
		if index < 0 or index >= _node_positions.size():
			continue
		var center: Vector2 = _node_positions[index]
		draw_line(center + Vector2(-9, 0), center + Vector2(-9, 11), Color.WHITE, 3)
		draw_line(center + Vector2(9, 0), center + Vector2(9, 11), Color.WHITE, 3)
		draw_rect(Rect2(center + Vector2(-15, -6), Vector2(30, 12)), Color("#ffc65a"))
		for offset in [-10, -2, 6]:
			draw_line(center + Vector2(offset, -5), center + Vector2(offset + 5, 5), Color("#172433"), 4)

func _draw_original_node(index: int, tile: Dictionary, center: Vector2, radius: float) -> void:
	if _background != null:
		var visual_index := int(tile.get("visual_index", 0))
		var road_frame := _road_icon_frame(tile)
		if visual_index > 0 and (road_frame.is_empty() or visuals.texture(road_frame) == null):
			draw_circle(center, maxf(4.0, radius * 0.32), Color("#21354a"))
			draw_arc(center, maxf(4.0, radius * 0.32), 0.0, TAU, 20, Color("#8fb0bc"), 1.0)
		var owner := int(tile.get("owner", -1))
		if owner >= 0:
			draw_circle(center, 4.0, PLAYER_COLORS[owner % PLAYER_COLORS.size()])
		if selected_index == index or _route_options_has(index):
			draw_arc(center, radius, 0.0, TAU, 32, Color("#ffe098"), 3.0)
			if _route_options_has(index):
				_draw_text("選擇", center + Vector2(-18, -radius - 4), 36, 11, Color.WHITE)
		return
	var kind := String(tile.get("kind", "rest"))
	var color := _tile_color(kind)
	var border := Color("#f1d28a") if selected_index == index else Color("#d6e5d6")
	var border_width := 3.0 if selected_index == index else 1.2
	if _route_options_has(index):
		draw_circle(center, radius + 6.0, Color(0.88, 0.66, 0.34, 0.22))
		draw_arc(center, radius + 6.0, 0.0, TAU, 24, Color("#e0a958"), 2.0)
	draw_circle(center, radius, Color("#21354a"))
	draw_circle(center, max(4.0, radius - 2.0), color)
	draw_arc(center, radius, 0.0, TAU, 24, border, border_width)
	var name := String(tile.get("name", "格位 %02d" % (index + 1)))
	if kind == "unsupported":
		name = "待還原 · " + name.replace("（待還原）", "")
	_draw_text(str(index + 1).pad_zeros(2), center + Vector2(-radius, -radius - 5.0), radius * 2.0, 8, Color("#8fb0bc"), HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(_short_text(name, 10), center + Vector2(-radius * 1.7, radius + 14.0), radius * 3.4, 9, Color("#edf3f0"), HORIZONTAL_ALIGNMENT_CENTER)
	if _route_options_has(index):
		_draw_text("選擇", center + Vector2(-radius * 1.5, 4.0), radius * 3.0, 8, Color("#fff1c9"), HORIZONTAL_ALIGNMENT_CENTER)

func _draw_original_players() -> void:
	var positions: Dictionary = {}
	for player_index in range(players_data.size()):
		var player: Dictionary = players_data[player_index] if players_data[player_index] is Dictionary else {}
		var tile_index := int(player.get("position", 0))
		if tile_index < 0 or tile_index >= _node_positions.size():
			continue
		if not positions.has(tile_index):
			positions[tile_index] = []
		positions[tile_index].append(player_index)
	for tile_index in positions:
		var occupants: Array = positions[tile_index]
		for occupant_index in range(occupants.size()):
			var player_index: int = occupants[occupant_index]
			var angle: float = TAU * float(occupant_index) / max(1.0, float(occupants.size()))
			var radius: float = _node_radii[int(tile_index)]
			var center: Vector2 = _node_positions[int(tile_index)] + Vector2(cos(angle), sin(angle)) * min(13.0, radius * 0.68)
			var frame: Dictionary = visuals.character(str(map_definition.get("source", {}).get("edition", "")), int(players_data[player_index].get("character_id", player_index))) if _background != null else {}
			if visuals.texture(frame) != null:
				_scene_draws.append({"kind": "player", "layer": 2, "frame": frame, "center": center, "color": PLAYER_COLORS[player_index % PLAYER_COLORS.size()]})
				continue
			_scene_draws.append({"kind": "player", "layer": 2, "frame": {}, "center": center,
				"fallback": "player", "player_index": player_index})

func _draw_scene_fallback(job: Dictionary) -> void:
	var center: Vector2 = job.center
	if job.get("fallback", "") == "player":
		var player_index := int(job.player_index)
		var active := player_index == current_player_index
		var marker_radius := 9.0 if active else 7.0
		draw_circle(center + Vector2(0.0, 2.0), marker_radius, Color(0.0, 0.0, 0.0, 0.38))
		draw_circle(center, marker_radius, PLAYER_COLORS[player_index % PLAYER_COLORS.size()])
		draw_arc(center, marker_radius, 0.0, TAU, 20, Color("#f7f3df"), 1.4 if active else 0.8)
		_draw_text(str(player_index + 1), center + Vector2(-5.0, 4.0), 10.0, 9, Color("#173047"), HORIZONTAL_ALIGNMENT_CENTER)
	elif job.get("fallback", "") == "house":
		var owner := int(job.get("owner", -1))
		var border: Color = PLAYER_COLORS[owner % PLAYER_COLORS.size()] if owner >= 0 else Color("#b6d3c5")
		var marker := Rect2(center + Vector2(-10.0, -18.0), Vector2(20.0, 18.0))
		draw_rect(marker, Color("#21354a"))
		draw_rect(marker, border, false, 2.0)
		_draw_text(str(job.get("level", 0)), center + Vector2(-8.0, -4.0), 16.0, 10, Color("#edf3f0"), HORIZONTAL_ALIGNMENT_CENTER)

func _draw_tile(cell_rect: Rect2, index: int, tile: Dictionary) -> void:
	var kind := String(tile.get("kind", "property"))
	var base_color := _tile_color(kind)
	var is_selected := selected_index == index
	var owner := int(tile.get("owner", -1))
	var border := Color("#f1d28a") if is_selected else Color("#34536a")
	var border_width := 2.5 if is_selected else 1.0
	_draw_style_box(cell_rect, Color("#21354a"), border, 8.0, border_width)
	var color_band := Rect2(cell_rect.position + Vector2(1.0, 1.0), Vector2(cell_rect.size.x - 2.0, min(8.0, cell_rect.size.y * 0.2)))
	draw_rect(color_band, base_color)
	if owner >= 0:
		var owner_color: Color = PLAYER_COLORS[owner % PLAYER_COLORS.size()]
		draw_rect(Rect2(cell_rect.position + Vector2(1.0, color_band.size.y + 1.0), Vector2(4.0, cell_rect.size.y - color_band.size.y - 2.0)), owner_color)
	var tile_number := str(index + 1).pad_zeros(2)
	_draw_text(tile_number, cell_rect.position + Vector2(7.0, 22.0), cell_rect.size.x - 12.0, 9, Color("#89a5b4"), HORIZONTAL_ALIGNMENT_LEFT)
	var name := String(tile.get("name", _fallback_tile_name(index, kind)))
	if kind == "unsupported":
		name = "待還原"
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
	var positions: Dictionary = {}
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
			var center: Vector2 = cell_rect.get_center() + Vector2(cos(angle), sin(angle)) * min(9.0, cell_rect.size.x * 0.16) + Vector2(0.0, 5.0)
			var player_color: Color = PLAYER_COLORS[player_index % PLAYER_COLORS.size()]
			var active := player_index == current_player_index
			draw_circle(center + Vector2(0.0, 2.0), 8.0 if active else 6.5, Color(0.0, 0.0, 0.0, 0.35))
			draw_circle(center, 8.0 if active else 6.5, player_color)
			draw_arc(center, 8.0 if active else 6.5, 0.0, TAU, 20, Color("#f7f3df"), 1.4 if active else 0.8)
			_draw_text(str(player_index + 1), center + Vector2(-5.0, 4.0), 10.0, 9, Color("#173047"), HORIZONTAL_ALIGNMENT_CENTER)

func _activate_tile(index: int) -> void:
	selected_index = index
	tile_selected.emit(index)
	if _route_options_has(index):
		route_selected.emit(index)
	queue_redraw()

func _tile_at_position(position: Vector2) -> int:
	if is_original_map():
		_layout_map()
		var best := -1
		var best_distance := INF
		for index in range(_node_positions.size()):
			var distance := position.distance_to(_node_positions[index])
			if distance <= _node_radii[index] + 10.0 and distance < best_distance:
				best = index
				best_distance = distance
		return best
	_layout_legacy_cells()
	for index in range(_cell_rects.size()):
		if _cell_rects[index].has_point(position):
			return index
	return -1

func _geometry_board() -> Array:
	var geometry: Variant = map_definition.get("board", []) if not map_definition.is_empty() else []
	if geometry is Array and not geometry.is_empty():
		return geometry
	return board_data

func _merged_tile(index: int) -> Dictionary:
	var geometry := _geometry_board()
	var tile: Dictionary = geometry[index].duplicate(true) if index >= 0 and index < geometry.size() and geometry[index] is Dictionary else {}
	if index >= 0 and index < board_data.size() and board_data[index] is Dictionary:
		var runtime: Dictionary = board_data[index]
		for key in ["owner", "building_level", "cost", "upgrade_cost", "base_rent", "rent", "group", "tax_amount"]:
			if runtime.has(key):
				tile[key] = runtime[key]
		if tile.is_empty():
			tile = runtime.duplicate(true)
	return tile

func _layout_legacy_cells() -> void:
	var board_count: int = max(1, board_data.size())
	var side := 8
	while side < 14 and 4 * (side - 1) < board_count:
		side += 1
	var tile_size := _legacy_tile_size(side)
	var board_size := Vector2(tile_size * side, tile_size * side)
	var origin := (size - board_size) * 0.5
	var cells := _perimeter_cells(side)
	_cell_rects.clear()
	_cell_rects.resize(board_count)
	for index in range(board_count):
		var grid_cell: Vector2i = cells[index % cells.size()]
		_cell_rects[index] = Rect2(origin + Vector2(grid_cell) * tile_size + Vector2(2.0, 2.0), Vector2(tile_size - 4.0, tile_size - 4.0))

func _legacy_tile_size(side: int) -> float:
	return min((size.x - BOARD_INSET * 2.0) / float(side), (size.y - BOARD_INSET * 2.0) / float(side))

func _layout_map() -> void:
	var geometry := _geometry_board()
	if geometry.is_empty():
		_node_positions.clear()
		_node_radii.clear()
		return
	if _layout_size == size and _node_positions.size() == geometry.size():
		return
	var bounds := _map_bounds(geometry)
	var center := bounds.position + bounds.size * 0.5
	var scale := _map_scale_for_bounds(bounds)
	var view_center := size * 0.5
	_node_positions.resize(geometry.size())
	_node_radii.resize(geometry.size())
	for index in range(geometry.size()):
		var tile: Dictionary = geometry[index] if geometry[index] is Dictionary else {}
		var coordinate := Vector2(float(tile.get("x", index)), float(tile.get("y", 0)))
		_node_positions[index] = view_center + map_pan + (coordinate - center) * scale * map_zoom
		_node_radii[index] = clampf(13.0 * map_zoom, 8.0, 22.0)
	_layout_size = size

func _map_scale() -> float:
	return _map_scale_for_bounds(_map_bounds(_geometry_board()))

func _map_scale_for_bounds(bounds: Rect2) -> float:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return 1.0
	return max(0.01, min((size.x - 72.0) / bounds.size.x, (size.y - 112.0) / bounds.size.y))

func _map_bounds(geometry: Array) -> Rect2:
	if geometry.is_empty():
		return Rect2()
	var first: Dictionary = geometry[0] if geometry[0] is Dictionary else {}
	var minimum := Vector2(float(first.get("x", 0)), float(first.get("y", 0)))
	var maximum := minimum
	for value in geometry:
		if not value is Dictionary:
			continue
		var point := Vector2(float(value.get("x", 0)), float(value.get("y", 0)))
		minimum.x = min(minimum.x, point.x)
		minimum.y = min(minimum.y, point.y)
		maximum.x = max(maximum.x, point.x)
		maximum.y = max(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)

func _map_to_screen(coordinate: Vector2) -> Vector2:
	var bounds := _map_bounds(_geometry_board())
	var coordinate_center := bounds.position + bounds.size * 0.5
	return size * 0.5 + map_pan + (coordinate - coordinate_center) * _map_scale() * map_zoom

func _screen_to_map(screen_position: Vector2) -> Vector2:
	var bounds := _map_bounds(_geometry_board())
	var coordinate_center := bounds.position + bounds.size * 0.5
	var scale: float = max(0.0001, _map_scale() * map_zoom)
	return (screen_position - size * 0.5 - map_pan) / scale + coordinate_center

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

func _has_coordinate_board(value: Array) -> bool:
	return not value.is_empty() and _tile_has_coordinates(value[0])

func _tile_has_coordinates(value: Variant) -> bool:
	return value is Dictionary and (value as Dictionary).has("x") and (value as Dictionary).has("y")

func _route_options_has(index: int) -> bool:
	for option in route_options:
		if int(option) == index:
			return true
	return false

func _current_position() -> int:
	if current_player_index >= 0 and current_player_index < players_data.size() and players_data[current_player_index] is Dictionary:
		return int(players_data[current_player_index].get("position", -1))
	return -1

func _tile_color(kind: String) -> Color:
	match kind:
		"start":
			return Color("#d79b55")
		"event", "card":
			return Color("#bc78cf")
		"tax", "unsupported":
			return Color("#df6e6e")
		"bank":
			return Color("#5ca9a0")
		"stock":
			return Color("#e2b25b")
		"points":
			return Color("#8b78d0")
		"property":
			return Color("#4d83a5")
		_:
			return Color("#728c9c")

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
		"card":
			return "卡片"
		"points":
			return "點數"
		"unsupported":
			return "待還原"
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

func _as_array(value: Variant) -> Array:
	return value if value is Array else []

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

func _draw_sprite(frame: Dictionary, center: Vector2, scale_factor: float) -> bool:
	var sprite: Texture2D = visuals.texture(frame)
	if sprite == null:
		return false
	draw_texture_rect(sprite, visuals.sprite_rect(frame, center, scale_factor), false)
	return true

func _road_icon_frame(tile: Dictionary) -> Dictionary:
	return visuals.road(_scene, int(tile.get("visual_index", 0)))

func _road_icons_missing(geometry: Array) -> bool:
	if not visuals.has_road_sprites(_scene):
		return true
	for index in range(geometry.size()):
		var tile: Dictionary = _merged_tile(index)
		if int(tile.get("visual_index", 0)) <= 0:
			continue
		var frame := _road_icon_frame(tile)
		if frame.is_empty() or visuals.texture(frame) == null:
			return true
	return false

func _draw_original_node_icons(geometry: Array) -> void:
	for index in range(geometry.size()):
		var tile: Dictionary = _merged_tile(index)
		var visual_index := int(tile.get("visual_index", 0))
		if visual_index <= 0:
			continue
		var frame := visuals.road(_scene, visual_index)
		if frame.is_empty() or visuals.texture(frame) == null:
			continue
		_scene_draws.append({"kind": "road_icon", "layer": 0, "node_index": index, "visual_index": visual_index, "frame": frame, "center": _node_positions[index]})

func _draw_original_houses() -> void:
	if _background == null:
		return
	var properties: Dictionary = {}
	for index in range(_geometry_board().size()):
		var tile := _merged_tile(index)
		if tile.get("kind") == "property":
			properties[int(tile.get("source_object_id", 0))] = tile
	for land in _scene.get("lands", []):
		if not land is Dictionary or not properties.has(int(land.get("id", 0))):
			continue
		var tile: Dictionary = properties[int(land.id)]
		var level := int(tile.get("building_level", 0))
		if level > 0:
			var frame: Dictionary = visuals.house(_scene, level, int(land.get("direction", 0)))
			var job := {"kind": "house", "layer": 1, "frame": frame, "center": _map_to_screen(Vector2(float(land.get("x", 0)), float(land.get("y", 0)))), "level": level, "owner": int(tile.get("owner", -1))}
			if visuals.texture(frame) == null:
				job["fallback"] = "house"
			_scene_draws.append(job)
	for item in _scene.get("scenery", []):
		_scene_draws.append({"kind": "scenery", "layer": 1, "frame": visuals.scenery(_scene, int(item.get("sprite_id", 0)), int(item.direction)), "center": _map_to_screen(Vector2(float(item.x), float(item.y)))})
