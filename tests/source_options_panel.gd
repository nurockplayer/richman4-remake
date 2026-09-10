extends SceneTree

## Focused hermetic checks for the Issue #141 source general-options presenter.
##
## The panel receives a detached model and an injected visual accessor.  These
## checks never construct GameState/MainUI, touch owner files, play audio, or
## invoke platform input.  A missing script is reported as availability RED;
## that setup failure is kept separate from presenter behaviour failures.

const PANEL_SCRIPT_PATH := "res://game/ui/source_options_panel.gd"
const REFERENCE_SIZE := Vector2(640, 480)
const FRAME_ORIGIN := Vector2(147, 59)
const FRAME_SIZE := Vector2(347, 363)
const HITBOXES := {
	"speed": Rect2(81, 17, 47, 16),
	"music_level": Rect2(89, 81, 63, 16),
	"sound_level": Rect2(89, 113, 63, 16),
	"animation": Rect2(98, 50, 15, 15),
	"music_toggle": Rect2(66, 82, 15, 15),
	"sound_toggle": Rect2(66, 114, 15, 15),
	"autosave": Rect2(98, 146, 15, 15),
	"view_calendar": Rect2(217, 214, 107, 22),
	"view_map": Rect2(217, 246, 107, 22),
	"view_combined": Rect2(217, 278, 107, 22),
	"modecmd0": Rect2(227, 14, 100, 35),
	"modecmd1": Rect2(227, 68, 100, 35),
	"modecmd2": Rect2(227, 119, 100, 35),
	"track": Rect2(18, 226, 159, 119),
	"cancel": Rect2(194, 314, 62, 30),
	"accept": Rect2(266, 314, 62, 30),
}

var checks := 0
var failures := 0
var _last_accepted: Array = []
var _cancelled_count := 0
var _commands: Array = []
var _previews: Array = []


class FakeVisuals extends RefCounted:
	var calls: Array = []
	var texture_calls: Array = []
	var physical_scale := 2
	var blocked_editions: Array = []

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
		var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.1 + 0.02 * float(int(frame.get("chunk", 0))), 0.4, 0.55, 1.0))
		return ImageTexture.create_from_image(image)

	func _logical(chunk: int) -> Vector2:
		match chunk:
			0: return Vector2(347, 363)
			1: return Vector2(328, 336)
			2: return Vector2(199, 220)
			3, 4: return Vector2(62, 30)
			5: return Vector2(15, 16)
			6: return Vector2(101, 36)
			7, 8: return Vector2(16, 16)
			9: return Vector2(15, 15)
			10, 11: return Vector2(177, 174)
			12, 13: return Vector2(17, 11)
			14: return Vector2(56, 31)
			15: return Vector2(80, 41)
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


func _model(mode := "title", edition := "Game") -> Dictionary:
	return {
		"edition": edition,
		"mode": mode,
		"settings": {
			"speed": 1,
			"animation": true,
			"music_level": 4,
			"sound_level": 4,
			"autosave": true,
			"view": 1,
		},
	}


func _present(panel: Control, model: Dictionary, visuals: Object = null) -> void:
	if visuals != null:
		panel.call("set_visual_accessor", visuals)
	panel.call("set_view_model", {})
	panel.call("set_view_model", model)
	await _settle()


func _mouse_event(position: Vector2, button: MouseButton, pressed: bool, double_click := false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	event.double_click = double_click
	return event


func _click(viewport: SubViewport, point: Vector2) -> void:
	viewport.push_input(_mouse_event(FRAME_ORIGIN + point, MOUSE_BUTTON_LEFT, true), true)
	await _settle()
	viewport.push_input(_mouse_event(FRAME_ORIGIN + point, MOUSE_BUTTON_LEFT, false), true)
	await _settle()


func _right_release(viewport: SubViewport, point := Vector2(320, 240)) -> void:
	viewport.push_input(_mouse_event(point, MOUSE_BUTTON_RIGHT, false), true)
	await _settle()


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


func _run() -> void:
	if not FileAccess.file_exists(PANEL_SCRIPT_PATH):
		checks += 1
		failures += 1
		print("FAIL: source options presenter is absent (availability RED, not a behaviour failure)")
		print("Source options panel RED: implementation absent; checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var script: Variant = load(PANEL_SCRIPT_PATH)
	if script == null:
		checks += 1
		failures += 1
		print("FAIL: source options presenter script could not load (availability RED)")
		quit(1)
		return
	var pair := _new_panel()
	var viewport: SubViewport = pair["viewport"]
	var panel: Control = pair["panel"]
	panel.connect("accepted", Callable(self, "_on_accepted"))
	panel.connect("cancelled", Callable(self, "_on_cancelled"))
	panel.connect("command_requested", Callable(self, "_on_command"))
	panel.connect("preview_requested", Callable(self, "_on_preview"))
	await _settle()

	if _check_public_api(panel):
		await _test_geometry_and_art(panel)
		await _test_settings_and_draft(panel, viewport)
		await _test_source_down_up_and_commands(panel, viewport)
		await _test_preview_and_music_boundary(panel, viewport)
		await _test_lifecycle_and_suspension(panel, viewport)
		await _test_invalid_models_and_copies(panel)

	viewport.queue_free()
	await _settle()
	print("Source options panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _check_public_api(panel: Control) -> bool:
	var methods := [
		"set_view_model", "set_visual_accessor", "set_visuals", "view_model", "is_model_valid",
		"is_open", "draft_settings", "committed_settings", "source_art_available", "source_frames",
		"source_art_status", "source_geometry", "suspend_input", "close_options",
	]
	var ok := true
	for method in methods:
		var present := panel.has_method(method)
		_expect(present, "source options presenter exposes " + method)
		ok = ok and present
	for signal_name in ["accepted", "cancelled", "command_requested", "preview_requested"]:
		var present := panel.has_signal(signal_name)
		_expect(present, "source options presenter exposes " + signal_name + " signal")
		ok = ok and present
	_expect_equal(panel.size, REFERENCE_SIZE, "options presenter keeps the 640x480 logical canvas")
	_expect_equal(panel.mouse_filter, Control.MOUSE_FILTER_STOP, "options presenter consumes modal mouse input")
	return ok


func _test_geometry_and_art(panel: Control) -> void:
	var visuals := FakeVisuals.new()
	await _present(panel, _model(), visuals)
	_expect(bool(panel.call("is_model_valid")), "valid title model is accepted")
	var geometry: Dictionary = panel.call("source_geometry")
	_expect_equal(geometry.get("canvas"), REFERENCE_SIZE, "geometry reports the logical canvas")
	_expect_equal(geometry.get("frame_origin"), FRAME_ORIGIN, "frame origin is centered at (147,59)")
	_expect_equal(geometry.get("frame_size"), FRAME_SIZE, "frame reports Data3 chunk0 logical size")
	var hitboxes: Dictionary = geometry.get("hitboxes", {})
	for key in HITBOXES:
		_expect_equal(hitboxes.get(key), HITBOXES[key], "source hitbox %s is exact" % key)
	var frame := panel.find_child("SourceOptionsFrame", true, false) as TextureRect
	_expect(frame != null, "source frame is rendered")
	if frame != null:
		_expect_equal(frame.position, FRAME_ORIGIN, "source frame keeps logical origin")
		_expect_equal(frame.size, FRAME_SIZE, "2x source frame still uses logical geometry")
		_expect(frame.texture != null and frame.texture.get_size() == Vector2(694, 726), "2x source frame texture is accepted")
	var backdrop := panel.find_child("SourceOptionsFrameBackdrop", true, false) as ColorRect
	_expect(backdrop != null and backdrop.visible, "frame has an opaque backing only within its bounds")
	if backdrop != null:
		_expect_equal(backdrop.position, FRAME_ORIGIN, "backdrop starts at the source frame origin")
		_expect_equal(backdrop.size, FRAME_SIZE, "backdrop does not cover the board outside frame")
	var frames: Dictionary = panel.call("source_frames")
	_expect_equal(frames.size(), 16, "all sixteen Data3 source frames are reported")
	var statuses: Dictionary = panel.call("source_art_status")
	_expect_equal(statuses.size(), 16, "source art status covers all Data3 chunks")
	for chunk in range(16):
		var saw := false
		for call in visuals.calls:
			if int(call[2]) == 3 and int(call[3]) == chunk and call[0] == "Game" and call[1] == "Data":
				saw = true
		_expect(saw, "resolver is asked for Data3 chunk %d" % chunk)
	var labels: Array = panel.get("field_labels") if "field_labels" in panel else []
	_expect(labels.size() == 10, "ten source field labels are exposed")
	for label in labels:
		_expect(label is Label and not (label as Label).text.is_empty(), "source field labels remain readable")


func _test_settings_and_draft(panel: Control, viewport: SubViewport) -> void:
	var original := _model()
	await _present(panel, original)
	var before := original.duplicate(true)
	var draft: Dictionary = panel.call("draft_settings")
	_expect_equal(draft, original["settings"], "draft starts as a detached committed copy")
	var exposed: Dictionary = panel.call("draft_settings")
	exposed["speed"] = 0
	exposed["music_level"] = 0
	_expect_equal(panel.call("draft_settings")["speed"], 1, "draft_settings returns an independent copy")
	_expect_equal(panel.call("draft_settings")["music_level"], 4, "draft music remains detached")
	await _click(viewport, Vector2(81 + 16 * 2 + 1, 17 + 4))
	_expect_equal(panel.call("draft_settings")["speed"], 2, "speed mutates on left down")
	await _click(viewport, Vector2(89 + 16 * 0 + 1, 81 + 4))
	_expect_equal(panel.call("draft_settings")["music_level"], 1, "music level uses one-based source markers")
	await _click(viewport, Vector2(89 + 16 * 3 + 1, 113 + 4))
	_expect_equal(panel.call("draft_settings")["sound_level"], 4, "sound level uses the fourth source marker")
	await _click(viewport, Vector2(98 + 4, 50 + 4))
	await _click(viewport, Vector2(98 + 4, 146 + 4))
	await _click(viewport, Vector2(217 + 32 + 4, 214 + 4))
	var mutated: Dictionary = panel.call("draft_settings")
	_expect(not bool(mutated["animation"]), "animation toggles on left down")
	_expect(not bool(mutated["autosave"]), "autosave toggles on left down")
	_expect_equal(mutated["view"], 0, "view radio uses its selected source row")
	_expect_equal(original, before, "set_view_model and input do not mutate the host model")
	# Identical refresh while open keeps the unsaved draft.
	panel.call("set_view_model", original)
	await _settle()
	_expect_equal(panel.call("draft_settings"), mutated, "same active model refresh keeps unsaved draft")
	# Cancel discards all draft changes and emits once.
	var cancelled_before := _cancelled_count
	await _right_release(viewport, Vector2(3, 3))
	_expect_equal(_cancelled_count, cancelled_before + 1, "right release cancels once from anywhere")
	_expect(not bool(panel.call("is_open")), "cancel closes the open presenter")
	_expect_equal(panel.call("draft_settings"), before["settings"], "cancel discards the draft")


func _test_source_down_up_and_commands(panel: Control, viewport: SubViewport) -> void:
	await _present(panel, _model("title"))
	_commands.clear()
	var command_point := Vector2(227 + 10, 14 + 10)
	viewport.push_input(_mouse_event(FRAME_ORIGIN + command_point, MOUSE_BUTTON_LEFT, true), true)
	await _settle()
	_expect(_commands.is_empty(), "title command waits for left release")
	var pressed := panel.find_child("SourceOptionsCommand0Pressed", true, false) as TextureRect
	_expect(pressed != null and pressed.visible, "command press shows source pressed art")
	viewport.push_input(_mouse_event(Vector2(5, 5), MOUSE_BUTTON_LEFT, false), true)
	await _settle()
	_expect_equal(_commands, ["date"], "release dispatches the remembered command")
	_expect(bool(panel.call("is_open")), "command request keeps the options presenter open")
	# A second release without a matching press cannot duplicate the request.
	viewport.push_input(_mouse_event(Vector2(5, 5), MOUSE_BUTTON_LEFT, false), true)
	await _settle()
	_expect_equal(_commands, ["date"], "unmatched release does not duplicate command")
	for index in range(3):
		await _click(viewport, Vector2(227 + 10, [14, 68, 119][index] + 10))
	_expect_equal(_commands, ["date", "date", "hotkeys", "help"], "title commands retain source order")
	await _present(panel, _model("game"))
	_commands.clear()
	for index in range(3):
		await _click(viewport, Vector2(227 + 10, [14, 68, 119][index] + 10))
	_expect_equal(_commands, ["restart", "surrender", "quit"], "game commands map to host confirmation intents")
	_expect(bool(panel.call("is_open")), "game command requests do not close the presenter")
	# No invented Escape path.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	viewport.push_input(escape, true)
	await _settle()
	_expect(bool(panel.call("is_open")), "Escape does not invent a source close path")


func _test_preview_and_music_boundary(panel: Control, viewport: SubViewport) -> void:
	await _present(panel, _model())
	_previews.clear()
	await _click(viewport, Vector2(18 + 10, 226 + 15 * 3 + 4))
	_expect_equal(_previews, [], "track preview emits on down only and source music is permitted")
	# The helper click includes a release; preview should have been emitted once.
	_expect_equal(_previews, [3], "track preview uses a zero-based index")
	# Draft music can be muted without revoking preview permission: committed is 4.
	await _click(viewport, Vector2(66 + 4, 82 + 4))
	_expect_equal(panel.call("draft_settings")["music_level"], 0, "music switch toggles nonzero draft to zero")
	await _click(viewport, Vector2(18 + 10, 226 + 15 * 2 + 4))
	_expect_equal(_previews, [3, 2], "preview permission follows committed music, not draft music")
	# Accept commits the detached draft and only emits once.
	_last_accepted.clear()
	await _click(viewport, Vector2(266 + 10, 314 + 10))
	_expect_equal(_last_accepted.size(), 1, "OK emits accepted once")
	if not _last_accepted.is_empty():
		_expect_equal((_last_accepted[0] as Dictionary)["music_level"], 0, "accepted carries the committed draft")
	_expect(not bool(panel.call("is_open")), "OK closes the presenter")
	await _right_release(viewport)
	_expect_equal(_last_accepted.size(), 1, "post-accept input cannot duplicate acceptance")


func _test_lifecycle_and_suspension(panel: Control, viewport: SubViewport) -> void:
	await _present(panel, _model())
	_commands.clear()
	var before: Dictionary = panel.call("draft_settings")
	panel.call("suspend_input", true)
	await _click(viewport, Vector2(81 + 16 * 2 + 1, 17 + 4))
	await _click(viewport, Vector2(227 + 10, 14 + 10))
	_expect_equal(panel.call("draft_settings"), before, "suspended input keeps the draft unchanged")
	_expect(_commands.is_empty(), "suspended input cannot emit a parent command")
	panel.call("suspend_input", false)
	await _click(viewport, Vector2(81 + 1, 17 + 4))
	_expect_equal(panel.call("draft_settings")["speed"], 0, "resumed input reaches the presenter")
	# Programmatic close is the same once-only cancellation boundary.
	var cancelled_before := _cancelled_count
	panel.call("close_options")
	_expect_equal(_cancelled_count, cancelled_before + 1, "close_options emits one cancellation")
	panel.call("close_options")
	_expect_equal(_cancelled_count, cancelled_before + 1, "close_options cannot double emit")
	panel.call("set_view_model", _model())
	await _settle()
	_expect(bool(panel.call("is_open")), "a new model call starts a new session")


func _test_invalid_models_and_copies(panel: Control) -> void:
	var cases := [
		_model(),
		_model("title", "Unknown"),
		_model("other"),
		_model(),
		_model(),
	]
	(cases[1] as Dictionary)["edition"] = "Unknown"
	(cases[2] as Dictionary)["mode"] = "other"
	(cases[3] as Dictionary)["settings"]["speed"] = 3
	(cases[4] as Dictionary)["settings"]["music_level"] = 1.5
	for index in range(cases.size()):
		if index == 0:
			continue
		panel.call("set_view_model", cases[index])
		await _settle()
		_expect(not bool(panel.call("is_model_valid")), "invalid model %d fails closed" % index)
		_expect(not bool(panel.call("source_art_available")), "invalid model %d cannot claim source art" % index)
		var unavailable := panel.find_child("SourceOptionsUnavailable", true, false) as Label
		_expect(unavailable != null and unavailable.visible and not unavailable.text.is_empty(), "invalid model %d is explicitly unavailable" % index)
		_expect(panel.find_child("SourceOptionsSpeedLabel", true, false) == null, "invalid model %d does not render settings" % index)
	# Invalid content remains closable without an acceptance event.
	var accepted_before := _last_accepted.size()
	panel.call("close_options")
	_expect_equal(_last_accepted.size(), accepted_before, "invalid model cannot emit acceptance")
	# Restore a valid edition independently for the two edition resolver paths.
	var visuals := FakeVisuals.new()
	await _present(panel, _model(), visuals)
	visuals.calls.clear()
	panel.call("set_view_model", _model("title", "MultiverseJourney"))
	await _settle()
	var only_mj := true
	for call in visuals.calls:
		only_mj = only_mj and call[0] == "MultiverseJourney"
	_expect(only_mj, "MultiverseJourney never borrows Game art")


func _on_accepted(settings: Dictionary) -> void:
	_last_accepted.append(settings.duplicate(true))


func _on_cancelled() -> void:
	_cancelled_count += 1


func _on_command(command: String) -> void:
	_commands.append(command)


func _on_preview(track: int) -> void:
	_previews.append(track)
