extends SceneTree
const Visuals = preload("res://game/platform/original_visuals.gd")
const Board = preload("res://game/ui/board_view.gd")
class TracedBoard extends "res://game/ui/board_view.gd":
	var paint_order: Array = []
	func _draw() -> void:
		paint_order.clear()
		super._draw()
	func _draw_original_node(index: int, tile: Dictionary, center: Vector2, radius: float) -> void:
		paint_order.append("overlay")
		super._draw_original_node(index, tile, center, radius)
	func _draw_scene_fallback(job: Dictionary) -> void:
		paint_order.append("fallback:" + str(job.get("fallback", "")))
		super._draw_scene_fallback(job)
	func _draw_sprite(frame: Dictionary, center: Vector2, scale_factor: float) -> bool:
		paint_order.append("sprite")
		return super._draw_sprite(frame, center, scale_factor)

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
	var picture := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	picture.fill(Color.GREEN)
	picture.save_png(folder.path_join("images/test.png"))
	var record := {"path": "images/test.png", "width": 4, "height": 4, "sha256": FileAccess.get_sha256(folder.path_join("images/test.png"))}
	var road_frame := record.duplicate(true)
	road_frame.logical = {"width": 20, "height": 30, "anchor_x": 5, "anchor_y": 10}
	var scene := {"id": "Game:1", "source_file_sha256": "archive", "graph_payload_sha256": "graph", "world_rect": {"x": 0, "y": 0, "width": 2304, "height": 2304}, "image": record, "lands": [], "house_sprites": []}
	scene.lands = [{"id": 1, "x": 10, "y": 20, "direction": 0}]
	scene.house_sprites = [{"level": 1, "frames": [road_frame.duplicate(true)]}]
	scene.road_source = {"archive_sha256": "archive", "resource_index": 12, "signature": "SMP", "chunk_count": 1, "transparent_word_zero": true}
	scene.road_sprites = [{"visual_index": 1, "frames": [road_frame.duplicate(true)]}]
	var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": "richman4.scene-images/v1", "maps": [scene], "characters": {"Game": {"sprites": [{"character_id": 0, "frames": [road_frame.duplicate(true)]}]}}}))
	file.close()
	var visuals = Visuals.new(folder.path_join("manifest.json"))
	var definition := {"source": {"edition": "Game", "map_number": 1, "source_file_sha256": "archive", "payload_sha256": "graph"}, "board": [{"x": 10, "y": 20, "adjacent": [1], "visual_index": 1, "kind": "property", "source_object_id": 1, "building_level": 1}, {"x": 40, "y": 30, "adjacent": [0], "visual_index": 0, "kind": "rest"}]}
	expect(not visuals.scene_for(definition).is_empty(), "matching scene loads")
	expect(visuals.road(visuals.manifest.maps[0], 0).is_empty(), "zero visual index suppresses icon")
	expect(not visuals.road(visuals.manifest.maps[0], 1).is_empty(), "one-based visual index loads first icon")
	visuals.manifest.maps[0].road_source.archive_sha256 = "other-archive"
	expect(visuals.scene_for(definition).is_empty(), "road source provenance cannot be substituted")
	visuals.manifest.maps[0].road_source.archive_sha256 = "archive"
	var wrong := definition.duplicate(true)
	wrong.source.payload_sha256 = "different"
	expect(visuals.scene_for(wrong).is_empty(), "different map provenance cannot load")
	expect(visuals.texture(record) != null, "verified PNG loads")
	expect(visuals.texture({"path": "images/test.png", "sha256": "wrong"}) == null, "wrong digest cannot load")
	for path in ["../test.png", "/tmp/test.png", "images/../test.png", "images/..\\test.png"]:
		expect(visuals.texture({"path": path, "sha256": record.sha256}) == null, "path escape rejected")
	var board = TracedBoard.new()
	board.visuals = visuals
	board.size = Vector2(700, 600)
	root.add_child(board)
	board.set_game_data(definition.board, [{"position": 0, "character_id": 0}], 0, definition, [1])
	await process_frame
	await process_frame
	expect(board._background != null, "original background used by drawing")
	expect(board.paint_order.find("overlay") > board.paint_order.rfind("sprite"), "ownership and route overlays paint after opaque sprites")
	var road_job_index := -1
	var house_job_index := -1
	var player_job_index := -1
	for job_index in range(board._scene_draws.size()):
		var job: Dictionary = board._scene_draws[job_index]
		if job.get("kind", "") == "road_icon":
			road_job_index = job_index
		elif job.get("kind", "") == "house":
			house_job_index = job_index
		elif job.get("kind", "") == "player":
			player_job_index = job_index
	expect(road_job_index >= 0, "road icon is emitted as a draw job")
	expect(house_job_index > road_job_index and player_job_index > house_job_index, "road icon is layered under house and player")
	if road_job_index >= 0:
		var road_job: Dictionary = board._scene_draws[road_job_index]
		expect(road_job.center == board.get_screen_position_for_index(0), "road icon uses map node coordinate")
	var ordering_definition := definition.duplicate(true)
	ordering_definition.board[1].visual_index = 1
	board.set_game_data(ordering_definition.board, [{"position": 0, "character_id": 0}], 0, ordering_definition, [1])
	await process_frame
	await process_frame
	var first_non_road_index := -1
	var last_road_index := -1
	for job_index in range(board._scene_draws.size()):
		var job: Dictionary = board._scene_draws[job_index]
		if job.get("kind", "") == "road_icon":
			last_road_index = job_index
		elif first_non_road_index < 0:
			first_non_road_index = job_index
	expect(last_road_index >= 0 and first_non_road_index > last_road_index, "all road icons draw before the combined world-object sort")
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
	var original_point: Vector2 = board.get_screen_position_for_index(1)
	var original_pan: Vector2 = board.map_pan
	var original_zoom: float = board.map_zoom
	for multiplier in [1, 2, 4]:
		var replacement := Image.create(4 * multiplier, 4 * multiplier, false, Image.FORMAT_RGBA8)
		replacement.fill(Color.BLUE)
		replacement.save_png(folder.path_join("images/test.png"))
		var updated := record.duplicate(true)
		updated.width = 4 * multiplier
		updated.height = 4 * multiplier
		updated.sha256 = FileAccess.get_sha256(folder.path_join("images/test.png"))
		visuals.manifest.maps[0].image = updated
		var frame := updated.duplicate(true)
		frame.logical = {"width": 20, "height": 30, "anchor_x": 5, "anchor_y": 10}
		visuals.manifest.maps[0].house_sprites = [{"level": 1, "frames": [frame]}]
		visuals.manifest.characters = {"Game": {"sprites": [{"character_id": 0, "frames": [frame]}]}}
		var updated_road := updated.duplicate(true)
		updated_road.logical = {"width": 20, "height": 30, "anchor_x": 5, "anchor_y": 10}
		visuals.manifest.maps[0].road_sprites = [{"visual_index": 1, "frames": [updated_road]}]
		expect(visuals.texture(updated).get_width() == 4 * multiplier, "replacement texture pixels load")
		for sprite in [visuals.house(visuals.manifest.maps[0], 1, 0), visuals.character("Game", 0)]:
			expect(visuals.sprite_rect(sprite, Vector2(100, 100), 2) == Rect2(90, 80, 40, 60), "replacement preserves sprite logical rectangle and anchor")
		board.set_game_data(definition.board, [{"position": 1}], 0, definition, [1])
		await process_frame
		await process_frame
		expect(board._background != null and board._background.get_width() == 4 * multiplier, "replacement background stays active")
		var replacement_road_loaded := false
		for job in board._scene_draws:
			if job.get("kind", "") == "road_icon" and visuals.texture(job.frame) != null and visuals.texture(job.frame).get_width() == 4 * multiplier:
				replacement_road_loaded = true
		expect(replacement_road_loaded, "replacement road icon pixels stay active")
		expect(visuals.world_rect(board._scene) == Rect2(0, 0, 2304, 2304), "replacement retains ground world bounds")
		expect(board.map_pan == original_pan and board.map_zoom == original_zoom, "replacement retains camera")
		expect(board.get_screen_position_for_index(1) == original_point and board.select_at_position(original_point) == 1, "replacement retains route hitbox")
	expect(board.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "low-resolution images use explicit nearest filtering")
	var missing_icon_definition := definition.duplicate(true)
	missing_icon_definition.board[1].visual_index = 2
	board.set_game_data(missing_icon_definition.board, [{"position": 1, "character_id": 0}], 0, missing_icon_definition, [1])
	await process_frame
	await process_frame
	expect(board._graph_fallback_edges, "missing road icon keeps graph edges visible")
	expect(board.select_at_position(board.get_screen_position_for_index(1)) == 1, "missing road icon keeps route hitbox")
	visuals.manifest.characters = {}
	visuals.manifest.maps[0].house_sprites = []
	board.set_game_data(definition.board, [{"position": 0, "character_id": 0}], 0, definition)
	await process_frame
	await process_frame
	var fallback_player := -1
	var fallback_house := -1
	var final_road := -1
	for index in range(board._scene_draws.size()):
		var job: Dictionary = board._scene_draws[index]
		if job.get("kind") == "road_icon":
			final_road = index
		if job.get("fallback") == "player":
			fallback_player = index
		if job.get("fallback") == "house":
			fallback_house = index
	expect(fallback_player > final_road, "missing character is queued visibly above opaque road icons")
	expect(fallback_house > final_road, "missing house retains a level marker above opaque road icons")
	expect(board.paint_order.has("fallback:player") and board.paint_order.has("fallback:house"), "missing sprite fallback markers are actually painted")
	board.set_game_data(definition.board, [], 0, wrong)
	await process_frame
	await process_frame
	expect(board._background == null, "mismatched scene falls back to graph")
	board.queue_free()
	print("Scene visuals: %d checks passed" % checks)
	quit()
