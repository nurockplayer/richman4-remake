extends SceneTree

const Maps = preload("res://game/content/original_maps.gd")
const BoardView = preload("res://game/ui/board_view.gd")
const CAPTURE_SCHEMA := "richman4.board-camera-capture/v1"

func _initialize() -> void:
	call_deferred("run")

func _vector_json(value: Vector2) -> Array:
	return [value.x, value.y]

func _rect_json(value: Rect2) -> Dictionary:
	return {
		"x": value.position.x,
		"y": value.position.y,
		"width": value.size.x,
		"height": value.size.y,
	}

func _camera_json(camera: Dictionary) -> Dictionary:
	var corners: Array = []
	for value in camera.get("viewport_corners", []):
		if value is Vector2:
			corners.append(_vector_json(value))
	return {
		"map_bounds": _rect_json(camera.get("map_bounds", Rect2())),
		"viewport": _rect_json(camera.get("viewport", Rect2())),
		"viewport_corners": corners,
		"viewport_size": _vector_json(camera.get("viewport_size", Vector2.ZERO)),
		"zoom": camera.get("zoom", 1.0),
		"pan": _vector_json(camera.get("pan", Vector2.ZERO)),
		"rotation": camera.get("rotation", 0.0),
		"focus": _vector_json(camera.get("focus", Vector2.ZERO)),
	}

func run() -> void:
	var catalog_path := OS.get_environment("RICHMAN4_MAP_CATALOG")
	var scene_manifest_path := OS.get_environment("RICHMAN4_SCENE_MANIFEST")
	var capture_path := OS.get_environment("BOARD_CAMERA_CAPTURE_PATH")
	var capture_head := OS.get_environment("BOARD_CAMERA_CAPTURE_HEAD")
	var capture_position := 1
	var position_text := OS.get_environment("BOARD_CAMERA_CAPTURE_POSITION")
	if position_text.is_valid_int():
		capture_position = int(position_text)
	var capture_rotation := 0.0
	var rotation_text := OS.get_environment("BOARD_CAMERA_CAPTURE_ROTATION")
	if rotation_text.is_valid_float():
		capture_rotation = float(rotation_text)
	if catalog_path.is_empty() or scene_manifest_path.is_empty() or capture_path.is_empty() or capture_head.is_empty():
		push_error("RICHMAN4_MAP_CATALOG, RICHMAN4_SCENE_MANIFEST, BOARD_CAMERA_CAPTURE_PATH, and BOARD_CAMERA_CAPTURE_HEAD are required")
		quit(2)
		return
	if not FileAccess.file_exists(catalog_path) or not FileAccess.file_exists(scene_manifest_path):
		push_error("capture catalog and scene manifest must exist")
		quit(2)
		return
	var head_pattern := RegEx.new()
	head_pattern.compile("^[0-9a-fA-F]{40}$")
	if head_pattern.search(capture_head) == null:
		push_error("BOARD_CAMERA_CAPTURE_HEAD must be a full 40-character commit SHA")
		quit(2)
		return
	var catalog_sha256 := FileAccess.get_sha256(catalog_path)
	var scene_manifest_sha256 := FileAccess.get_sha256(scene_manifest_path)
	if catalog_sha256.is_empty() or scene_manifest_sha256.is_empty():
		push_error("capture catalog and scene manifest must have readable SHA-256 digests")
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
	var sidecar_path := capture_path.get_basename() + ".state.json"
	var sidecar := {
		"schema": CAPTURE_SCHEMA,
		"head": capture_head,
		"map": {
			"id": definition.get("id", ""),
			"source": definition.get("source", {}),
		},
		"fixture_state": {
			"kind": "synthetic_board_camera_fixture",
			"phase": "idle",
			"capture_position": capture_position,
			"capture_rotation": capture_rotation,
			"current_player_index": 0,
			"players": players,
			"viewport_size": [viewport.size.x, viewport.size.y],
		},
		"catalog": {"path": catalog_path, "sha256": catalog_sha256},
		"scene_manifest": {"path": scene_manifest_path, "sha256": scene_manifest_sha256},
		"image": {"path": capture_path, "sha256": FileAccess.get_sha256(capture_path)},
		"camera": _camera_json(camera),
		"runner": "tests/board_camera_capture.gd",
		"renderer": OS.get_environment("BOARD_CAMERA_CAPTURE_RENDERER"),
		"packaged_capture": false,
		"simulation_mutated": false,
	}
	var sidecar_file := FileAccess.open(sidecar_path, FileAccess.WRITE)
	if sidecar_file == null:
		push_error("failed to write capture sidecar: %s" % sidecar_path)
		quit(2)
		return
	sidecar_file.store_string(JSON.stringify(sidecar, "\t"))
	sidecar_file.close()
	print("board camera capture: %s" % capture_path)
	print("board camera sidecar: %s" % sidecar_path)
	print("map bounds: %s size=%s" % [camera.map_bounds, camera.map_bounds.size])
	print("camera viewport: %s size=%s zoom=%s rotation=%s" % [camera.viewport, camera.viewport.size, camera.zoom, camera.rotation])
	viewport.queue_free()
	await process_frame
	quit(0)
