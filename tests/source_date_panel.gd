extends SceneTree

## Focused hermetic checks for the Issue #143 source date presenter.
##
## The panel receives detached date snapshots and an injected visual accessor;
## it does not read the system clock or construct GameState/MainUI.  A missing
## script is availability RED, while malformed model cases are presenter
## behaviour checks.

const PANEL_SCRIPT_PATH := "res://game/ui/source_date_panel.gd"
const REFERENCE_SIZE := Vector2(640, 480)
const FRAME_ORIGIN := Vector2(221, 130)
const FRAME_SIZE := Vector2(199, 220)
const HITBOXES := {
	"month_down": Rect2(74, 21, 16, 10),
	"month_up": Rect2(74, 31, 16, 10),
	"year_down": Rect2(160, 21, 16, 10),
	"year_up": Rect2(160, 31, 16, 10),
	"system": Rect2(9, 180, 55, 30),
	"cancel": Rect2(72, 180, 55, 30),
	"accept": Rect2(134, 180, 55, 30),
	"daygrid": Rect2(15, 70, 166, 107),
}
const MONTH_LABELS := [
	"一月", "二月", "三月", "四月", "五月", "六月",
	"七月", "八月", "九月", "十月", "十一月", "十二月",
]

var checks := 0
var failures := 0
var _accepted: Array = []
var _cancelled_count := 0


class FakeVisuals extends RefCounted:
	var calls: Array = []
	var texture_calls: Array = []
	var blocked_editions: Array = []
	var physical_scale := 2
	var _cache: Dictionary = {}

	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		calls.append([edition, archive, resource, chunk])
		if edition in blocked_editions:
			return {}
		var size := _logical(chunk)
		return {
			"edition": edition,
			"archive": archive,
			"resource": resource,
			"chunk": chunk,
			"logical": {"width": float(size.x), "height": float(size.y), "anchor_x": 0.0, "anchor_y": 0.0},
		}

	func texture(frame: Dictionary) -> Texture2D:
		texture_calls.append(frame.duplicate(true))
		var logical: Dictionary = frame.get("logical", {})
		var width := maxi(1, int(round(float(logical.get("width", 1.0)))) * physical_scale)
		var height := maxi(1, int(round(float(logical.get("height", 1.0)))) * physical_scale)
		var key := "%s:%d:%d" % [str(frame.get("edition", "")), int(frame.get("chunk", 0)), width]
		if _cache.has(key):
			return _cache[key]
		var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.1 + 0.03 * float(int(frame.get("chunk", 0))), 0.4, 0.55, 1.0))
		var result := ImageTexture.create_from_image(image)
		_cache[key] = result
		return result

	func _logical(chunk: int) -> Vector2:
		match chunk:
			2: return Vector2(199, 220)
			12, 13: return Vector2(17, 11)
			14: return Vector2(56, 31)
		return Vector2.ONE


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _settle() -> void:
	await process_frame
	await process_frame


func _model(date := {"year": 1998, "month": 1, "day": 31}, system_date := {"year": 2025, "month": 6, "day": 15}, edition := "Game") -> Dictionary:
	return {
		"edition": edition,
		"date": date.duplicate(true),
		"system_date": system_date.duplicate(true),
	}


func _mouse_event(position: Vector2, button: MouseButton, pressed: bool, double_click := false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	event.double_click = double_click
	return event


func _new_panel() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var script: Variant = load(PANEL_SCRIPT_PATH)
	var panel: Control = script.new()
	viewport.add_child(panel)
	return {"viewport": viewport, "panel": panel}


func _present(panel: Control, model: Dictionary, visuals: Object = null) -> void:
	if visuals != null:
		panel.call("set_visual_accessor", visuals)
	panel.call("set_view_model", {})
	panel.call("set_view_model", model)
	await _settle()


func _push_click(viewport: SubViewport, point: Vector2, release_point := Vector2(-1, -1)) -> void:
	var down_point := FRAME_ORIGIN + point
	var up_point := down_point if release_point.x < 0 else release_point
	viewport.push_input(_mouse_event(down_point, MOUSE_BUTTON_LEFT, true), true)
	await _settle()
	viewport.push_input(_mouse_event(up_point, MOUSE_BUTTON_LEFT, false), true)
	await _settle()


func _push_press(viewport: SubViewport, point: Vector2) -> void:
	viewport.push_input(_mouse_event(FRAME_ORIGIN + point, MOUSE_BUTTON_LEFT, true), true)
	await _settle()


func _push_release(viewport: SubViewport, point := Vector2(2, 2)) -> void:
	viewport.push_input(_mouse_event(FRAME_ORIGIN + point, MOUSE_BUTTON_LEFT, false), true)
	await _settle()


func _right_release(viewport: SubViewport, point := Vector2(3, 3)) -> void:
	viewport.push_input(_mouse_event(point, MOUSE_BUTTON_RIGHT, false), true)
	await _settle()


func _find(panel: Node, node_name: String) -> Node:
	return panel.find_child(node_name, true, false)


func _run() -> void:
	if not FileAccess.file_exists(PANEL_SCRIPT_PATH):
		checks += 1
		failures += 1
		print("FAIL: source date presenter is absent (availability RED, not a behaviour failure)")
		print("Source date panel RED: implementation absent; checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var script: Variant = load(PANEL_SCRIPT_PATH)
	if script == null:
		checks += 1
		failures += 1
		print("FAIL: source date presenter script could not load (availability RED)")
		quit(1)
		return
	var pair := _new_panel()
	var viewport: SubViewport = pair["viewport"]
	var panel: Control = pair["panel"]
	panel.connect("accepted", Callable(self, "_on_accepted"))
	panel.connect("cancelled", Callable(self, "_on_cancelled"))
	await _settle()

	if _check_public_api(panel):
		await _test_geometry_and_art(panel)
		await _test_calendar_and_draft(panel, viewport)
		await _test_press_release_and_invalid_date(panel, viewport)
		await _test_lifecycle_and_suspension(panel, viewport)
		await _test_invalid_models_and_edition_resolution(panel)

	viewport.queue_free()
	await _settle()
	print("Source date panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _check_public_api(panel: Control) -> bool:
	var methods := [
		"set_view_model", "set_visual_accessor", "set_visuals", "view_model", "is_model_valid", "is_open",
		"draft_date", "source_art_available", "source_art_status", "source_frames", "source_geometry",
		"source_hitboxes", "suspend_input", "close_date", "day_centers", "invalid_confirm_message",
	]
	var ok := true
	for method in methods:
		var present := panel.has_method(method)
		_expect(present, "source date presenter exposes " + method)
		ok = ok and present
	for signal_name in ["accepted", "cancelled"]:
		var present := panel.has_signal(signal_name)
		_expect(present, "source date presenter exposes " + signal_name + " signal")
		ok = ok and present
	_expect_equal(panel.size, REFERENCE_SIZE, "date presenter keeps the 640x480 logical canvas")
	_expect_equal(panel.mouse_filter, Control.MOUSE_FILTER_STOP, "date presenter consumes modal mouse input")
	return ok


func _test_geometry_and_art(panel: Control) -> void:
	var visuals := FakeVisuals.new()
	await _present(panel, _model(), visuals)
	_expect(bool(panel.call("is_model_valid")), "valid Game date model is accepted")
	var geometry: Dictionary = panel.call("source_geometry")
	_expect_equal(geometry.get("canvas"), REFERENCE_SIZE, "geometry reports the logical canvas")
	_expect_equal(geometry.get("frame_origin"), FRAME_ORIGIN, "frame origin is (221,130)")
	_expect_equal(geometry.get("frame_size"), FRAME_SIZE, "frame reports Data3 chunk2 logical size")
	var hitboxes: Dictionary = geometry.get("hitboxes", {})
	for key in HITBOXES:
		_expect_equal(hitboxes.get(key), HITBOXES[key], "source hitbox %s is exact" % key)
	var frame := _find(panel, "SourceDateFrame") as TextureRect
	_expect(frame != null, "source frame chunk2 is rendered")
	if frame != null:
		_expect_equal(frame.position, FRAME_ORIGIN, "source frame keeps logical origin")
		_expect_equal(frame.size, FRAME_SIZE, "2x source frame uses logical size")
		_expect(frame.texture != null and frame.texture.get_size() == Vector2(398, 440), "2x source frame texture is accepted")
	var backdrop := _find(panel, "SourceDateFrameBackdrop") as ColorRect
	_expect(backdrop != null and backdrop.visible, "date frame has an opaque backing")
	if backdrop != null:
		_expect_equal(backdrop.position, FRAME_ORIGIN, "date backdrop starts at source frame origin")
		_expect_equal(backdrop.size, FRAME_SIZE, "date backdrop stays inside frame")
	_expect(bool(panel.call("source_art_available")), "complete resolver reports source art available")
	var frames: Dictionary = panel.call("source_frames")
	_expect_equal(frames.size(), 4, "four source date chunks are reported")
	var statuses: Dictionary = panel.call("source_art_status")
	_expect_equal(statuses.size(), 4, "source art status covers all date chunks")
	for chunk in [2, 12, 13, 14]:
		var saw := false
		for call in visuals.calls:
			if call[0] == "Game" and call[1] == "Data" and int(call[2]) == 3 and int(call[3]) == chunk:
				saw = true
		_expect(saw, "resolver is asked for Data3 chunk %d" % chunk)
	var month_label := _find(panel, "SourceDateMonth") as Label
	_expect(month_label != null and month_label.text == MONTH_LABELS[0], "current month label keeps source text")
	_expect((_find(panel, "SourceDateYear") as Label) != null, "year label is present")
	for name_value in ["SourceDateSystemLabel", "SourceDateCancelLabel", "SourceDateAcceptLabel"]:
		var footer := _find(panel, name_value) as Label
		_expect(footer != null and not footer.text.is_empty(), "footer label %s is readable" % name_value)
	for day in [1, 2, 31]:
		var day_label := _find(panel, "SourceDateDay%d" % day) as Label
		_expect(day_label != null and not day_label.text.is_empty(), "day label %d is rendered" % day)
		if day_label != null:
			_expect_equal(int(day_label.get_theme_font_size("font_size")), 15, "day %d uses source font 15" % day)


func _test_calendar_and_draft(panel: Control, viewport: SubViewport) -> void:
	var original := _model({"year": 1998, "month": 1, "day": 31})
	await _present(panel, original)
	var draft: Dictionary = panel.call("draft_date")
	_expect_equal(draft, original["date"], "draft starts as detached date copy")
	var exposed: Dictionary = panel.call("draft_date")
	exposed["day"] = 1
	_expect_equal(panel.call("draft_date")["day"], 31, "draft_date returns an independent copy")
	var centers: Dictionary = panel.call("day_centers")
	_expect(centers.has(1) and centers.has(31), "day_centers exposes current month days")
	if centers.has(1):
		var day_one: Vector2 = centers[1]
		_expect_equal(day_one.x, 28.0 + 23.0 * 4.0, "1998-01-01 starts on source Thursday")
		_expect_equal(day_one.y, 80.0, "first-row day center uses source y=80")
	# Source month change wraps without changing year or day.
	await _push_click(viewport, Vector2(74 + 2, 31 + 2))
	_expect_equal(panel.call("draft_date"), {"year": 1998, "month": 2, "day": 31}, "month up keeps year and day byte")
	_expect_equal(panel.call("day_centers").has(31), false, "invalid February 31 has no day center")
	await _push_click(viewport, Vector2(74 + 2, 21 + 2))
	_expect_equal(panel.call("draft_date"), {"year": 1998, "month": 1, "day": 31}, "month down returns to January")
	# Year changes preserve month/day and stop at core supported bounds.
	await _push_click(viewport, Vector2(160 + 2, 31 + 2))
	_expect_equal(panel.call("draft_date")["year"], 1999, "year up increments year")
	for _index in range(4):
		await _push_click(viewport, Vector2(160 + 2, 21 + 2))
	_expect_equal(panel.call("draft_date")["year"], 1998, "year down caps at 1998")
	var maximum := _model({"year": 9999, "month": 12, "day": 31})
	await _present(panel, maximum)
	await _push_click(viewport, Vector2(160 + 2, 31 + 2))
	_expect_equal(panel.call("draft_date")["year"], 9999, "year up caps at 9999")
	# System reset uses a detached captured date.
	await _push_click(viewport, Vector2(9 + 2, 180 + 2))
	_expect_equal(panel.call("draft_date"), maximum["system_date"], "system button restores captured system date")
	var model_copy: Dictionary = panel.call("view_model")
	model_copy["system_date"]["day"] = 1
	_expect_equal(panel.call("view_model")["system_date"]["day"], 15, "view_model keeps system date detached")


func _test_press_release_and_invalid_date(panel: Control, viewport: SubViewport) -> void:
	var original := _model({"year": 1998, "month": 1, "day": 31})
	await _present(panel, original)
	_accepted.clear()
	# Pressed arrow art appears on down and release dispatches remembered action
	# even after the pointer leaves the source rectangle.
	await _push_press(viewport, Vector2(74 + 2, 31 + 2))
	var month_pressed := _find(panel, "SourceDateMonthUpPressed") as TextureRect
	_expect(month_pressed != null and month_pressed.visible, "month up uses pressed chunk12 on down")
	await _push_release(viewport, Vector2(2, 2))
	_expect_equal(panel.call("draft_date"), {"year": 1998, "month": 2, "day": 31}, "month action dispatches on release outside")
	# Invalid date is retained as draft but blocks confirmation and shows a
	# short explicit message.
	await _push_click(viewport, Vector2(134 + 2, 180 + 2))
	_expect(_accepted.is_empty(), "invalid date cannot emit accepted")
	_expect(bool(panel.call("is_open")), "invalid confirmation keeps panel open")
	var invalid_message := str(panel.call("invalid_confirm_message"))
	_expect(not invalid_message.is_empty(), "invalid confirmation exposes a short message")
	var message_label := _find(panel, "SourceDateInvalidConfirm") as Label
	_expect(message_label != null and message_label.visible, "invalid confirmation label is visible")
	# Select February 28 by its source center, then confirm.
	var centers: Dictionary = panel.call("day_centers")
	_expect(centers.has(28), "valid February 28 center remains selectable")
	if centers.has(28):
		await _push_click(viewport, centers[28])
	_expect_equal(panel.call("draft_date")["day"], 28, "day selection mutates on left down")
	await _push_press(viewport, Vector2(134 + 2, 180 + 2))
	var accept_pressed := _find(panel, "SourceDateAcceptPressed") as TextureRect
	_expect(accept_pressed != null and accept_pressed.visible, "accept uses pressed chunk14 on down")
	await _push_release(viewport, Vector2(2, 2))
	_expect_equal(_accepted.size(), 1, "valid date emits accepted once")
	if not _accepted.is_empty():
		_expect_equal(_accepted[0], {"year": 1998, "month": 2, "day": 28}, "accepted carries selected date")
	_expect(not bool(panel.call("is_open")), "accept closes the presenter")
	await _right_release(viewport)
	_expect_equal(_accepted.size(), 1, "post-accept input cannot duplicate acceptance")


func _test_lifecycle_and_suspension(panel: Control, viewport: SubViewport) -> void:
	await _present(panel, _model({"year": 2024, "month": 2, "day": 29}))
	var before: Dictionary = panel.call("draft_date")
	var accepted_before := _accepted.size()
	panel.call("suspend_input", true)
	await _push_click(viewport, Vector2(74 + 2, 31 + 2))
	await _push_click(viewport, Vector2(134 + 2, 180 + 2))
	_expect_equal(panel.call("draft_date"), before, "suspended input keeps draft unchanged")
	_expect_equal(_accepted.size(), accepted_before, "suspended input cannot emit acceptance")
	panel.call("suspend_input", false)
	await _push_click(viewport, Vector2(74 + 2, 31 + 2))
	_expect_equal(panel.call("draft_date")["month"], 3, "resumed input reaches presenter")
	var cancelled_before := _cancelled_count
	panel.call("close_date")
	_expect_equal(_cancelled_count, cancelled_before + 1, "close_date emits one cancellation")
	panel.call("close_date")
	_expect_equal(_cancelled_count, cancelled_before + 1, "close_date cannot double emit")
	await _present(panel, _model({"year": 2024, "month": 2, "day": 29}))
	_expect(bool(panel.call("is_open")), "new model call starts a new session")
	# A same-model refresh while open retains an unsaved date draft.
	await _push_click(viewport, Vector2(74 + 2, 31 + 2))
	var changed: Dictionary = panel.call("draft_date")
	panel.call("set_view_model", _model({"year": 2024, "month": 2, "day": 29}))
	await _settle()
	_expect_equal(panel.call("draft_date"), changed, "same active model refresh keeps unsaved draft")
	await _right_release(viewport)
	_expect_equal(_cancelled_count, cancelled_before + 2, "right release cancels from outside panel")


func _test_invalid_models_and_edition_resolution(panel: Control) -> void:
	var base := _model()
	var cases := [
		{},
		_model({"year": 1997, "month": 1, "day": 1}),
		_model({"year": 1998, "month": 2, "day": 29}),
		_model({"year": 2024, "month": 2, "day": 29}, {"year": 2023, "month": 2, "day": 29}),
		_model({"year": 2024, "month": 2, "day": 29}, {"year": 2024, "month": 2, "day": 29}, "Unknown"),
	]
	for index in range(cases.size()):
		panel.call("set_view_model", cases[index])
		await _settle()
		_expect(not bool(panel.call("is_model_valid")), "invalid model %d fails closed" % index)
		_expect(not bool(panel.call("source_art_available")), "invalid model %d cannot claim source art" % index)
		var unavailable := _find(panel, "SourceDateUnavailable") as Label
		_expect(unavailable != null and unavailable.visible and not unavailable.text.is_empty(), "invalid model %d is explicitly unavailable" % index)
	# Restore valid MJ and ensure resolver calls never borrow Game art.
	var visuals := FakeVisuals.new()
	await _present(panel, base, visuals)
	visuals.calls.clear()
	panel.call("set_view_model", _model({"year": 2024, "month": 2, "day": 29}, {"year": 2025, "month": 6, "day": 15}, "MultiverseJourney"))
	await _settle()
	var only_mj := true
	for call in visuals.calls:
		only_mj = only_mj and call[0] == "MultiverseJourney"
	_expect(only_mj, "MultiverseJourney never borrows Game art")


func _on_accepted(date: Dictionary) -> void:
	_accepted.append(date.duplicate(true))


func _on_cancelled() -> void:
	_cancelled_count += 1
