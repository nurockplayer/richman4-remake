extends SceneTree
const Visuals = preload("res://game/platform/original_visuals.gd")
const Board = preload("res://game/ui/board_view.gd")
var checks := 0
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var folder := "user://scene-fixture"
	DirAccess.make_dir_recursive_absolute(folder.path_join("images"))
	var picture := Image.create(2304, 2304, false, Image.FORMAT_RGBA8)
	picture.fill(Color.GREEN)
	picture.save_png(folder.path_join("images/test.png"))
	var record := {"path": "images/test.png", "sha256": FileAccess.get_sha256(folder.path_join("images/test.png"))}
	var scene := {"id": "Game:1", "source_file_sha256": "archive", "graph_payload_sha256": "graph", "width": 2304, "height": 2304, "image": record, "lands": [], "house_sprites": []}
	var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": "richman4.scene-images/v1", "maps": [scene], "characters": {}}))
	file.close()
	var visuals = Visuals.new(folder.path_join("manifest.json"))
	var definition := {"source": {"edition": "Game", "map_number": 1, "source_file_sha256": "archive", "payload_sha256": "graph"}, "board": [{"x": 10, "y": 20, "adjacent": [1]}, {"x": 40, "y": 30, "adjacent": [0]}]}
	expect(not visuals.scene_for(definition).is_empty(), "matching scene loads")
	var wrong := definition.duplicate(true)
	wrong.source.payload_sha256 = "different"
	expect(visuals.scene_for(wrong).is_empty(), "different map provenance cannot load")
	expect(visuals.texture(record) != null, "verified PNG loads")
	expect(visuals.texture({"path": "images/test.png", "sha256": "wrong"}) == null, "wrong digest cannot load")
	for path in ["../test.png", "/tmp/test.png", "images/../test.png", "images/..\\test.png"]:
		expect(visuals.texture({"path": path, "sha256": record.sha256}) == null, "path escape rejected")
	var board = Board.new()
	board.visuals = visuals
	board.size = Vector2(700, 600)
	root.add_child(board)
	board.set_game_data(definition.board, [{"position": 0}], 0, definition, [1])
	await process_frame
	await process_frame
	expect(board._background != null, "original background used by drawing")
	expect(board.get_screen_position_for_index(0).distance_to(board.size * 0.5) < 1, "camera centers the active player")
	var point: Vector2 = board.get_screen_position_for_index(1)
	expect(board.select_at_position(point) == 1, "route remains clickable over background")
	board.zoom_by(1.8)
	board.pan_by(Vector2(30, -15))
	expect(board.select_at_position(board.get_screen_position_for_index(1)) == 1, "route remains clickable after zoom and pan")
	board.set_game_data(definition.board, [{"position": 1}], 0, definition)
	await process_frame
	await process_frame
	expect(board.get_screen_position_for_index(1).distance_to(board.size * 0.5) < 1, "camera follows movement")
	board.set_game_data(definition.board, [], 0, wrong)
	await process_frame
	await process_frame
	expect(board._background == null, "mismatched scene falls back to graph")
	board.queue_free()
	print("Scene visuals: %d checks passed" % checks)
	quit()
