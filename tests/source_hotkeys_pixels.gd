extends SceneTree

## Native SubViewport pixel regression for the source hotkey pressed effect.
## This intentionally samples captured pixels rather than node metadata.  A
## headless run is an explicit SKIP because it cannot prove native rendering.

const PANEL_PATH := "res://game/ui/source_hotkeys_panel.gd"
const PLATFORM_PATH := "res://game/platform/system_hotkeys.gd"
const FRAME_ORIGIN := Vector2(156, 72)
const FRAME_SIZE := Vector2(328, 336)
const RESET := Rect2(17, 281, 71, 31)

var checks := 0
var failures := 0


class PixelVisuals extends RefCounted:
	var physical_scale := 1
	var calls: Array = []
	var _cache: Dictionary = {}

	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		calls.append([edition, archive, resource, chunk])
		return {
			"edition": edition,
			"archive": archive,
			"resource": resource,
			"chunk": chunk,
			"logical": {"width": 328.0, "height": 336.0, "anchor_x": 0.0, "anchor_y": 0.0},
		}

	func texture(frame: Dictionary) -> Texture2D:
		var key := "%s:%d" % [str(frame.get("edition", "")), physical_scale]
		if _cache.has(key):
			return _cache[key]
		var width := int(FRAME_SIZE.x) * physical_scale
		var height := int(FRAME_SIZE.y) * physical_scale
		var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
		for y in range(height):
			for x in range(width):
				# A high-contrast source-shaped gradient makes one-pixel movement
				# observable while avoiding any private/original asset.
				image.set_pixel(x, y, Color8((31 + x * 3) % 241, (47 + y * 5) % 241, (83 + x + y) % 241, 255))
		var result := ImageTexture.create_from_image(image)
		_cache[key] = result
		return result


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _settle() -> void:
	await process_frame
	await process_frame


func _mouse(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


func _new_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.disable_3d = true
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _capture(viewport: SubViewport) -> Image:
	var texture := viewport.get_texture()
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return null
	var image := texture.get_image()
	return image if image != null and not image.is_empty() else null


func _pixel(image: Image, local: Vector2) -> Color:
	return image.get_pixelv(Vector2i(FRAME_ORIGIN + local))


func _close_enough(actual: Color, expected: Color, tolerance := 2) -> bool:
	var actual_channels := [actual.r, actual.g, actual.b]
	var expected_channels := [expected.r, expected.g, expected.b]
	for index in range(actual_channels.size()):
		if absf((actual_channels[index] - expected_channels[index]) * 255.0) > tolerance:
			return false
	return true


func _minus_sixteen(value: Color) -> Color:
	return Color8(
		maxi(0, int(round(value.r * 255.0)) - 16),
		maxi(0, int(round(value.g * 255.0)) - 16),
		maxi(0, int(round(value.b * 255.0)) - 16),
		255,
	)


func _exercise(viewport: SubViewport, panel: Control, visuals: PixelVisuals, edition: String, scale: int) -> void:
	visuals.physical_scale = scale
	panel.call("set_visual_accessor", visuals)
	panel.call("set_view_model", {"edition": edition, "bindings": load(PLATFORM_PATH).new().defaults()})
	await _settle()
	var before := _capture(viewport)
	if before == null:
		_expect(false, "native SubViewport baseline image is available")
		return
	_expect(not _close_enough(_pixel(before, Vector2(108, 28)), _pixel(before, Vector2(109, 29)), 0), "gradient fixture produces distinct baseline pixels")
	# Fixed row 0: interior (108,28), top edge (111,25), left edge (105,30).
	viewport.push_input(_mouse(FRAME_ORIGIN + Vector2(132, 33), true), true)
	await _settle()
	var down := _capture(viewport)
	_expect(down != null, "native SubViewport captures the key press")
	if down == null:
		return
	_expect(_close_enough(_pixel(down, Vector2(108, 28)), _pixel(before, Vector2(107, 27))), "key interior shifts right/down one logical pixel")
	_expect(_close_enough(_pixel(down, Vector2(111, 25)), _minus_sixteen(_pixel(before, Vector2(111, 25)))), "key top edge darkens source RGB by sixteen")
	_expect(_close_enough(_pixel(down, Vector2(105, 30)), _minus_sixteen(_pixel(before, Vector2(105, 30)))), "key left edge darkens source RGB by sixteen")
	viewport.push_input(_mouse(FRAME_ORIGIN + Vector2(132, 33), false), true)
	await _settle()
	var released := _capture(viewport)
	_expect(released != null, "native SubViewport captures the key release")
	if released != null:
		_expect(_close_enough(_pixel(released, Vector2(108, 28)), _pixel(before, Vector2(108, 28))), "key release restores interior pixels")
		_expect(_close_enough(_pixel(released, Vector2(111, 25)), _pixel(before, Vector2(111, 25))), "key release restores top edge")
		_expect(_close_enough(_pixel(released, Vector2(105, 30)), _pixel(before, Vector2(105, 30))), "key release restores left edge")
	# Footer reset: samples stay in its early corner away from the caption glyph.
	panel.call("set_view_model", {"edition": edition, "bindings": load(PLATFORM_PATH).new().defaults()})
	await _settle()
	var footer_before := _capture(viewport)
	viewport.push_input(_mouse(FRAME_ORIGIN + RESET.get_center(), true), true)
	await _settle()
	var footer_down := _capture(viewport)
	_expect(footer_before != null and footer_down != null, "native SubViewport captures footer baseline and press")
	if footer_before != null and footer_down != null:
		_expect(_close_enough(_pixel(footer_down, Vector2(20, 285)), _pixel(footer_before, Vector2(19, 284))), "footer interior shifts right/down one logical pixel")
		_expect(_close_enough(_pixel(footer_down, Vector2(25, 281)), _minus_sixteen(_pixel(footer_before, Vector2(25, 281)))), "footer top edge darkens source RGB by sixteen")
		_expect(_close_enough(_pixel(footer_down, Vector2(17, 286)), _minus_sixteen(_pixel(footer_before, Vector2(17, 286)))), "footer left edge darkens source RGB by sixteen")
	viewport.push_input(_mouse(FRAME_ORIGIN + RESET.get_center(), false), true)
	await _settle()
	var footer_released := _capture(viewport)
	_expect(footer_released != null, "native SubViewport captures footer release")
	if footer_released != null:
		_expect(_close_enough(_pixel(footer_released, Vector2(20, 285)), _pixel(footer_before, Vector2(20, 285))), "footer release restores interior pixels")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: source hotkey pixel regression requires a native rendered SubViewport; headless is not a PASS")
		quit(0)
		return
	if not FileAccess.file_exists(PANEL_PATH) or not FileAccess.file_exists(PLATFORM_PATH):
		print("SKIP: source hotkey pixel regression modules unavailable")
		quit(0)
		return
	var viewport := _new_viewport()
	var panel: Control = load(PANEL_PATH).new()
	viewport.add_child(panel)
	for scale in [1, 2]:
		var visuals := PixelVisuals.new()
		for edition in ["Game", "MultiverseJourney"]:
			await _exercise(viewport, panel, visuals, edition, scale)
	viewport.queue_free()
	await _settle()
	print("Source hotkeys pixel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
