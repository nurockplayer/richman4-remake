extends SceneTree

const PanelScript = preload("res://game/ui/source_title_panel.gd")

var checks := 0
var failures := 0


class FakeVisuals extends RefCounted:
	var calls: Array = []
	var texture_calls: Array = []
	var missing_frames: Dictionary = {}
	var missing_textures: Dictionary = {}
	var physical_scale := 2

	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		calls.append({"edition": edition, "archive": archive, "resource": resource, "chunk": chunk})
		if missing_frames.has(chunk):
			return {}
		var logical := {"width": 640, "height": 480, "anchor_x": 0, "anchor_y": 0}
		match chunk:
			2:
				logical = {"width": 116, "height": 113, "anchor_x": 59, "anchor_y": 57}
			4:
				logical = {"width": 114, "height": 99, "anchor_x": 55, "anchor_y": 54}
			6:
				logical = {"width": 103, "height": 98, "anchor_x": 53, "anchor_y": 46}
			7:
				logical = {"width": 53, "height": 18, "anchor_x": 27, "anchor_y": 9}
			8:
				logical = {"width": 58, "height": 19, "anchor_x": 29, "anchor_y": 10}
			10:
				logical = {"width": 90, "height": 107, "anchor_x": 45, "anchor_y": 52}
			_:
				pass
		return {
			"edition": edition,
			"archive": archive,
			"resource": resource,
			"chunk": chunk,
			"logical": logical,
		}

	func texture(frame: Dictionary) -> Texture2D:
		texture_calls.append(frame.duplicate(true))
		var chunk := int(frame.get("chunk", -1))
		if missing_textures.has(chunk):
			return null
		var logical: Dictionary = frame.get("logical", {})
		var width := maxi(1, int(logical.get("width", 1)) * physical_scale)
		var height := maxi(1, int(logical.get("height", 1)) * physical_scale)
		var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.1 + float((chunk + 2) % 5) * 0.1, 0.35, 0.45, 1.0))
		return ImageTexture.create_from_image(image)


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	return viewport


func _new_panel(viewport: SubViewport, next_edition: String, visuals: Object) -> Control:
	var panel: Control = PanelScript.new()
	viewport.add_child(panel)
	panel.configure(next_edition, visuals)
	panel.show()
	await process_frame
	await process_frame
	return panel


func _move(viewport: SubViewport, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)
	await process_frame


func _click(viewport: SubViewport, point: Vector2) -> void:
	await _move(viewport, point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame


func _has_call(calls: Array, edition: String, chunk: int) -> bool:
	for call in calls:
		if call is Dictionary and call.get("edition") == edition and int(call.get("chunk", -1)) == chunk:
			return true
	return false


func run() -> void:
	await _test_game_geometry_and_input()
	await _test_missing_art_fallback_and_invalid_edition()
	await _test_multiverse_stage()
	print("Source title panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _test_game_geometry_and_input() -> void:
	var viewport := _new_viewport()
	var visuals := FakeVisuals.new()
	var panel: Control = await _new_panel(viewport, "Game", visuals)
	var expected := {
		"start": Rect2(131, 323, 116, 113),
		"load": Rect2(273, 326, 114, 99),
		"option": Rect2(415, 332, 103, 98),
		"exit": Rect2(299, 440, 58, 19),
	}
	expect_equal(panel.get_reference_size(), Vector2(640, 480), "title surface keeps the source logical size")
	expect_equal(panel.scale, Vector2.ONE, "title component leaves scaling to its host")
	var public_keys_ok := true
	for source_key in ["start", "load", "option", "exit", "new_stage"]:
		public_keys_ok = public_keys_ok and panel.buttons.has(source_key)
	expect(public_keys_ok, "public button map exposes stable action keys")
	expect(panel.find_child("SourceTitleNewStage", true, false) == null, "Game title has no expansion stage node")
	expect(not (panel.buttons["new_stage"] as Button).visible, "Game NEW STAGE is unavailable")
	expect(panel.background_art.texture != null and panel.background_art.size == Vector2(640, 480), "background uses the injected Data1 frame")
	expect(panel.exit_normal_art.visible, "EXIT normal art is drawn separately")
	expect_equal(panel.exit_normal_art.position, Vector2(301, 441), "EXIT normal art uses its source anchor")
	expect_equal(panel.exit_normal_art.size, Vector2(53, 18), "EXIT normal art uses source logical size")
	for source_key in expected:
		var button: Button = panel.buttons[source_key]
		expect_equal(panel.get_button_rect(source_key), expected[source_key], source_key + " uses hover logical hit bounds")
		expect_equal(button.position, expected[source_key].position, source_key + " button keeps source position")
		expect_equal(button.size, expected[source_key].size, source_key + " button keeps source size")
		expect_equal(button.name, {
			"start": "SourceTitleStart",
			"load": "SourceTitleLoad",
			"option": "SourceTitleOption",
			"exit": "SourceTitleExit",
		}[source_key], source_key + " has the host-facing node name")
		expect_equal(button.get_meta("source_key"), source_key, source_key + " has source_key metadata")
		expect(button.get_theme_stylebox("normal").bg_color.a == 0.0, source_key + " hit area stays transparent over source art")
		expect(button.text.is_empty(), source_key + " does not duplicate baked source labels")
	expect(_has_call(visuals.calls, "Game", 0), "Game requests Data1 background chunk zero")
	for chunk in [2, 4, 6, 8, 7]:
		expect(_has_call(visuals.calls, "Game", chunk), "Game requests source title chunk %d" % chunk)
	expect(not _has_call(visuals.calls, "Game", 9) and not _has_call(visuals.calls, "Game", 10), "Game never requests expansion title chunks")

	var before_rects: Dictionary = panel.get_button_rects()
	var start_rect: Rect2 = expected["start"]
	await _move(viewport, start_rect.position + Vector2(2, 2))
	expect_equal(panel.get_hover_key(), "start", "pointer enters the first source hit region")
	expect(panel.hover_art.visible, "first hover art becomes visible")
	expect_equal(panel.hover_art.get_meta("source_chunk"), 2, "first hover uses START hover chunk")
	expect_equal(panel.hover_art.position, start_rect.position, "hover art starts at source hit top-left")
	expect_equal(panel.hover_art.size, start_rect.size, "hover art uses source logical size")
	expect_equal(panel.get_button_rects(), before_rects, "hover does not change button geometry")
	await _move(viewport, start_rect.position + start_rect.size - Vector2(1, 1))
	expect_equal(panel.get_hover_key(), "start", "pointer reaches the last pixel of the first hit region")
	await _move(viewport, Vector2(8, 8))
	expect_equal(panel.get_hover_key(), "", "neutral pointer clears hover state")
	expect(not panel.hover_art.visible, "neutral pointer hides hover art")
	expect(panel.exit_normal_art.visible, "neutral pointer leaves EXIT normal art visible")

	var starts: Array = []
	var loads: Array = []
	var options: Array = []
	var quits: Array = []
	var load_rect: Rect2 = expected["load"]
	var option_rect: Rect2 = expected["option"]
	var exit_rect: Rect2 = expected["exit"]
	panel.start_requested.connect(func(stage: int) -> void: starts.append(stage))
	panel.load_requested.connect(func() -> void: loads.append(true))
	panel.option_requested.connect(func() -> void: options.append(true))
	panel.quit_requested.connect(func() -> void: quits.append(true))
	await _click(viewport, start_rect.position + start_rect.size * 0.5)
	await _click(viewport, load_rect.position + load_rect.size * 0.5)
	await _click(viewport, option_rect.position + option_rect.size * 0.5)
	await _click(viewport, exit_rect.position + exit_rect.size * 0.5)
	expect_equal(starts, [0], "START emits stage zero")
	expect_equal(loads.size(), 1, "LOAD emits one intent")
	expect_equal(options.size(), 1, "OPTION is enabled by default and emits intent")
	expect_equal(quits.size(), 1, "EXIT emits one quit intent")
	panel.set_option_enabled(false)
	await _click(viewport, option_rect.position + option_rect.size * 0.5)
	expect_equal(options.size(), 1, "host-disabled OPTION emits no intent")
	panel.set_option_enabled(true)
	panel.hide()
	await _click(viewport, start_rect.position + start_rect.size * 0.5)
	expect_equal(starts, [0], "hidden title does not receive START input")
	expect_equal(panel.get_hover_key(), "", "hidden title has no hover state")
	panel.free()
	viewport.free()
	await process_frame


func _test_missing_art_fallback_and_invalid_edition() -> void:
	var viewport := _new_viewport()
	var panel: Control = await _new_panel(viewport, "Game", null)
	expect(panel.background_art.texture == null, "missing visuals leave background texture empty")
	expect(panel.find_child("SourceTitleFallbackBackground", true, false).visible, "missing visuals show the bounded fallback background")
	for source_key in ["start", "load", "option", "exit"]:
		expect(not (panel.buttons[source_key] as Button).text.is_empty(), source_key + " has a readable fallback label")
	expect(panel.buttons["option"].disabled == false, "OPTION fallback remains enabled for host policy")
	var visuals := FakeVisuals.new()
	visuals.missing_frames[4] = true
	panel.configure("Game", visuals)
	panel.show()
	await process_frame
	expect_equal(panel.get_button_rect("load"), Rect2(273, 326, 114, 99), "missing hover frame keeps safe LOAD metadata")
	await _move(viewport, Vector2(280, 330))
	expect_equal(panel.get_hover_key(), "load", "missing hover texture still has a stable source hit region")
	expect(not panel.hover_art.visible, "missing hover texture does not invent opaque art")
	panel.configure("UnknownEdition", visuals)
	panel.show()
	await process_frame
	expect_equal(panel.get_edition(), "", "unknown edition is normalized to empty")
	expect(not panel.is_valid_edition(), "unknown edition fails closed")
	expect(not panel.get_node("SourceTitleSurface").visible, "unknown edition hides the title surface")
	var starts := 0
	panel.start_requested.connect(func(_stage: int) -> void: starts += 1)
	await _click(viewport, Vector2(150, 350))
	expect_equal(starts, 0, "unknown edition cannot emit START intent")
	panel.free()
	viewport.free()
	await process_frame


func _test_multiverse_stage() -> void:
	var viewport := _new_viewport()
	var visuals := FakeVisuals.new()
	var panel: Control = await _new_panel(viewport, "MultiverseJourney", visuals)
	var stage_button: Button = panel.buttons["new_stage"]
	expect(stage_button.visible and stage_button.get_parent() != null, "MJ title attaches NEW STAGE")
	expect(panel.find_child("SourceTitleNewStage", true, false) == stage_button, "MJ exposes the named NEW STAGE node")
	expect_equal(panel.get_button_rect("new_stage"), Rect2(17, 328, 90, 107), "NEW STAGE uses source hover geometry")
	expect(_has_call(visuals.calls, "MultiverseJourney", 0), "MJ requests Data1 background chunk zero")
	expect(_has_call(visuals.calls, "MultiverseJourney", 10), "MJ requests NEW STAGE hover chunk")
	expect(not _has_call(visuals.calls, "MultiverseJourney", 9), "MJ normal NEW STAGE is supplied by the baked background")
	var starts: Array = []
	panel.start_requested.connect(func(stage: int) -> void: starts.append(stage))
	var before: Rect2 = panel.get_button_rect("new_stage")
	await _move(viewport, before.position + Vector2(1, 1))
	expect_equal(panel.get_hover_key(), "new_stage", "pointer enters MJ NEW STAGE")
	expect_equal(panel.hover_art.get_meta("source_chunk"), 10, "MJ hover uses chunk ten")
	expect_equal(panel.get_button_rect("new_stage"), before, "MJ hover keeps NEW STAGE hit bounds stable")
	await _click(viewport, before.position + before.size * 0.5)
	expect_equal(starts, [1], "NEW STAGE emits stage one")
	panel.free()
	viewport.free()
	await process_frame
