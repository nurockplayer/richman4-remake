extends SceneTree

const Maps = preload("res://game/content/original_maps.gd")
const BoardView = preload("res://game/ui/board_view.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var catalog_path := OS.get_environment("RICHMAN4_MAP_CATALOG")
	var capture_path := OS.get_environment("BOARD_CAMERA_CAPTURE_PATH")
	var capture_position := 1
	var position_text := OS.get_environment("BOARD_CAMERA_CAPTURE_POSITION")
	if position_text.is_valid_int():
		capture_position = int(position_text)
	var capture_rotation := 0.0
	var rotation_text := OS.get_environment("BOARD_CAMERA_CAPTURE_ROTATION")
	if rotation_text.is_valid_float():
		capture_rotation = float(rotation_text)
	if catalog_path.is_empty() or capture_path.is_empty():
		push_error("RICHMAN4_MAP_CATALOG and BOARD_CAMERA_CAPTURE_PATH are required")
		quit(2)
		return
	var catalog := Maps.load_catalog(catalog_path, true)
	if not bool(catalog.get("ok", false)):
		push_error(str(catalog.get("error", "map catalog unavailable")))
		quit(2)
		return
	var definition: Dictionary = {}
	for candidate in catalog.get("maps", []):
		if candidate is Dictionary and candidate.get("id", "") == "Game:1":
			definition = candidate
			break
	if definition.is_empty():
		push_error("Game:1 map is unavailable")
		quit(2)
		return

	var viewport := SubViewport.new()
	viewport.size = Vector2i(440, 440)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var board: Control = BoardView.new()
	board.size = Vector2(440, 440)
	viewport.add_child(board)
	var players := []
	for index in range(4):
		players.append({"id": index, "position": capture_position, "character_id": index})
	board.set_game_data(definition.board, players, 0, definition)
	if not is_zero_approx(capture_rotation):
		board.set_map_rotation(capture_rotation)
	await process_frame
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("viewport image capture is empty")
		quit(2)
		return
	var save_error := image.save_png(capture_path)
	if save_error != OK:
		push_error("failed to write capture: %s" % save_error)
		quit(2)
		return
	var camera: Dictionary = board.get_camera_state()
	print("board camera capture: %s" % capture_path)
	print("map bounds: %s size=%s" % [camera.map_bounds, camera.map_bounds.size])
	print("camera viewport: %s size=%s zoom=%s rotation=%s" % [camera.viewport, camera.viewport.size, camera.zoom, camera.rotation])
	viewport.queue_free()
	await process_frame
	quit(0)
