extends SceneTree

const BoardView = preload("res://game/ui/board_view.gd")
const Visuals = preload("res://game/platform/original_visuals.gd")

class TextBoard extends "res://game/ui/board_view.gd":
	var texts: Array = []

	func _draw_text(text: String, _position: Vector2, _width: float, _font_size: int, _color: Color, _alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
		texts.append(text)

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func close_enough(a: Vector2, b: Vector2, tolerance := 0.5) -> bool:
	return a.distance_to(b) <= tolerance

func _make_definition() -> Dictionary:
	var board: Array = []
	var coordinates := [Vector2(720, 720), Vector2(960, 720), Vector2(960, 960), Vector2(720, 960)]
	for index in range(coordinates.size()):
		var adjacent: Array = [(index + 1) % coordinates.size()]
		board.append({
			"index": index,
			"x": coordinates[index].x,
			"y": coordinates[index].y,
			"adjacent": adjacent,
			"visual_index": 0,
			"kind": "property",
			"name": "測試格位 %d" % (index + 1),
		})
	return {
		"id": "Game:1",
		"source": {"edition": "Game", "map_number": 1, "source_file_sha256": "archive", "payload_sha256": "graph"},
		"board": board,
	}

func _make_visuals() -> Visuals:
	var folder := "user://board-camera-fixture"
	DirAccess.make_dir_recursive_absolute(folder)
	var scene := {
		"id": "Game:1",
		"source_file_sha256": "archive",
		"graph_payload_sha256": "graph",
		"world_rect": {"x": 0, "y": 0, "width": 2304, "height": 2304},
		"image": {"path": "images/missing.png", "sha256": "0".repeat(64), "width": 1, "height": 1},
		"lands": [],
		"house_sprites": [],
		"scenery": [],
		"scenery_sprites": [],
		"road_sprites": [],
	}
	var path := folder.path_join("manifest.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": "richman4.scene-images/v1", "maps": [scene], "characters": {}}))
	file.close()
	return Visuals.new(path)

func _players(position: int) -> Array:
	return [{"id": 0, "position": position, "character_id": 0}]

func _run_frames(count := 2) -> void:
	for _index in range(count):
		await process_frame

func run() -> void:
	var definition := _make_definition()
	var board := BoardView.new()
	board.visuals = _make_visuals()
	board.size = Vector2(440, 440)
	root.add_child(board)
	board.set_game_data(definition.board, _players(0), 0, definition)
	await _run_frames()

	check(board.get_map_bounds() == Rect2(0, 0, 2304, 2304), "camera uses source scene world bounds")
	check(close_enough(board.get_camera_viewport().size, Vector2(440, 440), 0.01), "camera uses the inferred 440 world-unit logical crop")
	check(close_enough(board.get_screen_position_for_index(0), board.size * 0.5), "initial active player is centered")
	check(board.get_camera_state().has_all(["map_bounds", "viewport", "viewport_corners", "zoom", "pan", "rotation"]), "camera state exposes minimap inputs")

	board.set_game_data(definition.board, _players(1), 0, definition)
	await _run_frames()
	check(close_enough(board.get_screen_position_for_index(1), board.size * 0.5), "active player follow recenters on a new tile")

	board.play_movement([{"player_id": 0, "from": 1, "to": 2, "direction": 0}], 1.0)
	board._advance_movement(0.5)
	await _run_frames()
	check(close_enough(board.get_player_screen_position(0), board.size * 0.5), "movement follow keeps the moving player in view")

	var map_point := Vector2(960, 960)
	board.set_map_rotation(PI / 4.0, board.size * 0.5)
	var rotated_screen := board.map_to_screen(map_point)
	check(close_enough(board.screen_to_map(rotated_screen), map_point, 0.75), "rotation preserves inverse map projection")
	check(board.select_at_position(board.get_screen_position_for_index(2)) == 2, "rotated node remains clickable at its projected position")
	for sprite_kind in ["road_icon", "house", "scenery", "player"]:
		check(is_zero_approx(board.get_sprite_rotation(sprite_kind)), "%s sprite remains upright while its world position rotates" % sprite_kind)
	var minimap := Rect2(0, 0, 200, 200)
	var minimap_polygon := board.get_minimap_viewport_polygon(minimap)
	check(minimap_polygon.size() == 4, "minimap receives the four camera viewport corners")
	check(board.map_to_minimap(Vector2.ZERO, minimap) == minimap.position, "minimap projection uses source bounds")

	var text_board := TextBoard.new()
	text_board.size = Vector2(440, 440)
	root.add_child(text_board)
	text_board.set_game_data(definition.board, _players(0), 0, definition)
	await _run_frames()
	check(not text_board.texts.has("原版路網") and not text_board.texts.has("原版地圖預覽"), "ordinary player view hides graph debug labels")
	text_board.set_preview_definition(definition)
	await _run_frames()
	check(text_board.texts.has("原版地圖預覽"), "preview view retains graph labels")

	board.queue_free()
	text_board.queue_free()
	await process_frame
	print("Board camera checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
