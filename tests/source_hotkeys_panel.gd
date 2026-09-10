extends SceneTree

## Focused hermetic checks for the Issue #143 source hotkey child presenter.
##
## This test owns no GameState, MainUI, settings file, native input, audio, or
## full asset cache.  A missing presenter/platform module is reported as an
## availability RED so setup failure is not confused with behaviour failure.

const PANEL_PATH := "res://game/ui/source_hotkeys_panel.gd"
const PLATFORM_PATH := "res://game/platform/system_hotkeys.gd"
const FRAME_ORIGIN := Vector2(156, 72)
const FRAME_SIZE := Vector2(328, 336)
const SOURCE_LABELS := [
	"游標上移", "游標右移", "游標下移", "游標左移", "確定執行", "取消指令",
	"切換選項", "切換視窗組", "是<YES>", "否<NO>", "前進指令", "選擇骰子數",
	"股市", "交易", "卡片", "道具", "查詢", "地圖", "地圖向左旋轉", "地圖向右旋轉",
	"託管", "系統", "SAVE GAME", "LOAD GAME", "輔助說明", "向上換頁", "向下換頁", "結束程式",
]
const FIRST_COLUMN := Rect2(105, 25, 56, 240)
const SECOND_COLUMN := Rect2(257, 25, 56, 208)
const RESET := Rect2(17, 281, 71, 31)
const CANCEL := Rect2(130, 281, 71, 31)
const ACCEPT := Rect2(242, 281, 71, 31)

var checks := 0
var failures := 0
var _accepted: Array = []
var _cancelled := 0


class FakeVisuals extends RefCounted:
	var calls: Array = []
	var physical_scale := 2

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
		var logical: Dictionary = frame.get("logical", {})
		var width := maxi(1, int(round(float(logical.get("width", 1.0)))) * physical_scale)
		var height := maxi(1, int(round(float(logical.get("height", 1.0)))) * physical_scale)
		var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
		image.fill(Color("#335f72"))
		return ImageTexture.create_from_image(image)


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _settle() -> void:
	await process_frame
	await process_frame


func _new_viewport() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var panel: Control = load(PANEL_PATH).new()
	viewport.add_child(panel)
	panel.accepted.connect(_on_accepted)
	panel.cancelled.connect(_on_cancelled)
	return {"viewport": viewport, "panel": panel}


func _event_key(code: Key, pressed := true, ctrl := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	return event


func _mouse(position: Vector2, button: MouseButton, pressed: bool, double_click := false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	event.double_click = double_click
	return event


func _click(viewport: SubViewport, point: Vector2) -> void:
	viewport.push_input(_mouse(FRAME_ORIGIN + point, MOUSE_BUTTON_LEFT, true), true)
	await _settle()
	viewport.push_input(_mouse(FRAME_ORIGIN + point, MOUSE_BUTTON_LEFT, false), true)
	await _settle()


func _left_down_up(viewport: SubViewport, point: Vector2) -> void:
	await _click(viewport, point)


func _right_release(viewport: SubViewport, point := Vector2(320, 240)) -> void:
	viewport.push_input(_mouse(point, MOUSE_BUTTON_RIGHT, false), true)
	await _settle()


func _model(platform: Object, edition := "Game") -> Dictionary:
	return {"edition": edition, "bindings": platform.defaults()}


func _run() -> void:
	if not FileAccess.file_exists(PANEL_PATH) or not FileAccess.file_exists(PLATFORM_PATH):
		checks += 1
		failures += 1
		print("FAIL: source hotkeys presenter/platform absent (availability RED, not a behaviour failure)")
		print("Source hotkeys panel RED: implementation unavailable; checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var panel_script: Variant = load(PANEL_PATH)
	var platform_script: Variant = load(PLATFORM_PATH)
	if panel_script == null or platform_script == null:
		checks += 1
		failures += 1
		print("FAIL: source hotkeys presenter/platform could not load (availability RED)")
		quit(1)
		return
	var platform: Object = platform_script.new()
	var pair := _new_viewport()
	var viewport: SubViewport = pair["viewport"]
	var panel: Control = pair["panel"]
	await _settle()
	if _check_public_api(panel):
		await _test_geometry_and_art(panel, platform)
		await _test_copy_and_fixed_slots(panel, viewport, platform)
		await _test_editing_rules(panel, viewport, platform)
		await _test_footer_and_lifecycle(panel, viewport, platform)
		await _test_suspend_and_editions(panel, viewport, platform)
	viewport.queue_free()
	await _settle()
	print("Source hotkeys panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _check_public_api(panel: Control) -> bool:
	var methods := [
		"set_view_model", "set_visual_accessor", "set_visuals", "view_model", "is_model_valid", "is_open",
		"draft_bindings", "source_art_available", "source_frames", "source_geometry", "source_hitboxes",
		"suspend_input", "close_hotkeys", "pending_blink_visible",
	]
	var ok := true
	for method in methods:
		var present := panel.has_method(method)
		_expect(present, "source hotkeys presenter exposes " + method)
		ok = ok and present
	for signal_name in ["accepted", "cancelled"]:
		var present := panel.has_signal(signal_name)
		_expect(present, "source hotkeys presenter exposes " + signal_name + " signal")
		ok = ok and present
	_expect_equal(panel.size, Vector2(640, 480), "hotkeys keeps the 640x480 logical canvas")
	return ok


func _present(panel: Control, model: Dictionary, visuals: Object = null) -> void:
	if visuals != null:
		panel.set_visual_accessor(visuals)
	panel.set_view_model({})
	panel.set_view_model(model)
	await _settle()


func _test_geometry_and_art(panel: Control, platform: Object) -> void:
	var visuals := FakeVisuals.new()
	await _present(panel, _model(platform), visuals)
	_expect(panel.is_model_valid() and panel.is_open(), "valid source model opens")
	var geometry: Dictionary = panel.source_geometry()
	_expect_equal(geometry.get("canvas"), Vector2(640, 480), "geometry reports source canvas")
	_expect_equal(geometry.get("frame_origin"), FRAME_ORIGIN, "hotkey frame keeps source origin")
	_expect_equal(geometry.get("frame_size"), FRAME_SIZE, "hotkey frame keeps source logical size")
	var hitboxes: Dictionary = geometry.get("hitboxes", {})
	_expect_equal(hitboxes.get("first_column"), FIRST_COLUMN, "first column hitbox is source bounded")
	_expect_equal(hitboxes.get("second_column"), SECOND_COLUMN, "second column hitbox is source bounded")
	_expect_equal(hitboxes.get("reset"), RESET, "reset hitbox includes source edges")
	_expect_equal(hitboxes.get("cancel"), CANCEL, "cancel hitbox includes source edges")
	_expect_equal(hitboxes.get("accept"), ACCEPT, "accept hitbox includes source edges")
	var frame := panel.find_child("SourceHotkeysFrame", true, false) as TextureRect
	_expect(frame != null and frame.texture != null, "source hotkey frame is rendered")
	if frame != null:
		_expect_equal(frame.position, FRAME_ORIGIN, "frame keeps logical origin")
		_expect_equal(frame.size, FRAME_SIZE, "2x art does not change logical frame")
		_expect(frame.texture.get_size() == Vector2(656, 672), "2x source texture remains available")
	_expect(panel.source_art_available(), "source chunk 1 is available through resolver")
	_expect_equal(panel.source_frames().size(), 1, "only required source Data3 chunk is exposed")
	for call in visuals.calls:
		_expect_equal(call, ["Game", "Data", 3, 1], "resolver uses Game Data3 chunk1")
	var labels: Array = panel.get("key_labels")
	_expect_equal(labels.size(), 28, "all source key labels are exposed")
	for index in range(mini(labels.size(), SOURCE_LABELS.size())):
		_expect_equal((labels[index] as Label).text, SOURCE_LABELS[index], "source label %d retains source order" % index)
		var expected_color := Color("#00f0f0") if index < 8 else Color("#f0f000")
		_expect_equal((labels[index] as Label).get_theme_color("font_color"), expected_color, "slot %d uses source color" % index)
	_expect(panel.find_child("SourceHotkeysPressed", true, false) == null, "idle state has no pressed overlay")


func _test_copy_and_fixed_slots(panel: Control, viewport: SubViewport, platform: Object) -> void:
	var model := _model(platform)
	var before: Array = model.bindings.duplicate(true)
	await _present(panel, model)
	var exposed: Array = panel.draft_bindings()
	exposed[8] = 0
	_expect_equal(panel.draft_bindings()[8], before[8], "draft bindings are detached")
	await _left_down_up(viewport, Vector2(105 + 1, 25 + 2 * 16 + 1))
	_expect_equal(panel.draft_bindings()[2], before[2], "fixed slot 2 cannot be edited")
	await _left_down_up(viewport, Vector2(105 + 1, 25 + 8 * 16 + 1))
	_expect_equal(panel.draft_bindings()[8], 0, "editable slot clears its temporary value")
	_expect_equal(model.bindings, before, "presenter never mutates host model")


func _test_editing_rules(panel: Control, viewport: SubViewport, platform: Object) -> void:
	await _present(panel, _model(platform))
	var defaults: Array = platform.defaults()
	# Ctrl-only is source's sticky 0x1100 prefix and remains editable.
	await _left_down_up(viewport, Vector2(105 + 1, 25 + 8 * 16 + 1))
	viewport.push_input(_event_key(KEY_CTRL, true), true)
	await _settle()
	viewport.push_input(_event_key(KEY_CTRL, false), true)
	await _settle()
	_expect_equal(panel.draft_bindings()[8], 0x1100, "Ctrl-only stores the sticky source prefix")
	_expect(panel.pending_blink_visible(), "pending field blinks while active and focused")
	# Duplicate candidate is rejected against every other current binding.
	viewport.push_input(_event_key(KEY_UP, true), true)
	await _settle()
	_expect_equal(panel.draft_bindings()[8], 0x1100, "duplicate candidate is rejected and editing remains")
	# A fresh allowed key commits and exits the edit state.
	viewport.push_input(_event_key(KEY_Z, true), true)
	await _settle()
	_expect_equal(panel.draft_bindings()[8], KEY_Z, "allowed key commits its source VK")
	_expect(not panel.pending_blink_visible(), "completed edit removes pending blink")
	# Reopening a slot clears it, and right release restores its saved binding.
	await _left_down_up(viewport, Vector2(105 + 1, 25 + 8 * 16 + 1))
	_expect_equal(panel.draft_bindings()[8], 0, "reopened edit starts from a cleared temporary value")
	await _right_release(viewport, FRAME_ORIGIN + Vector2(105 + 1, 25 + 8 * 16 + 1))
	_expect_equal(panel.draft_bindings()[8], KEY_Z, "right release while editing restores the old binding")
	_expect(panel.is_open(), "right restore leaves child open")
	# Explicitly reject unsupported DELETE and modifier-only non-Ctrl input.
	await _left_down_up(viewport, Vector2(105 + 1, 25 + 8 * 16 + 1))
	viewport.push_input(_event_key(KEY_DELETE, true), true)
	await _settle()
	_expect_equal(panel.draft_bindings()[8], 0, "unsupported DELETE is rejected")
	viewport.push_input(_event_key(KEY_A, true, true), true)
	await _settle()
	_expect_equal(panel.draft_bindings()[8], 0, "Ctrl candidate without source Ctrl prefix is not invented")
	# Avoid an unused local warning while keeping the default source snapshot explicit.
	_expect(defaults.size() == 28, "source defaults contain exactly 28 slots")


func _test_footer_and_lifecycle(panel: Control, viewport: SubViewport, platform: Object) -> void:
	await _present(panel, _model(platform))
	var defaults: Array = platform.defaults()
	await _left_down_up(viewport, Vector2(105 + 1, 25 + 8 * 16 + 1))
	viewport.push_input(_event_key(KEY_CTRL, true), true)
	await _settle()
	viewport.push_input(_event_key(KEY_CTRL, false), true)
	await _settle()
	await _click(viewport, Vector2(17 + 1, 281 + 1))
	_expect_equal(panel.draft_bindings(), defaults, "reset restores all defaults and exits editing")
	# Zero/unbound is valid and can be accepted while the field is pending.
	await _left_down_up(viewport, Vector2(105 + 1, 25 + 8 * 16 + 1))
	_expect_equal(panel.draft_bindings()[8], 0, "reset edit clears slot to unbound")
	await _click(viewport, Vector2(242 + 1, 281 + 1))
	_expect_equal(_accepted.size(), 1, "accept emits once")
	if not _accepted.is_empty():
		_expect_equal((_accepted[0] as Array)[8], 0, "accept preserves an unbound source value")
	_expect(not panel.is_open(), "accept closes the child")
	await _click(viewport, Vector2(242 + 1, 281 + 1))
	_expect_equal(_accepted.size(), 1, "post-accept input cannot duplicate acceptance")
	# A second right release cancels the still-open session exactly once.
	await _present(panel, _model(platform))
	var cancelled_before := _cancelled
	await _right_release(viewport)
	_expect_equal(_cancelled, cancelled_before + 1, "right release cancels an open child")
	await _right_release(viewport)
	_expect_equal(_cancelled, cancelled_before + 1, "second right release cannot duplicate cancellation")
	_expect(not panel.is_open(), "right cancellation closes the child")


func _test_suspend_and_editions(panel: Control, viewport: SubViewport, platform: Object) -> void:
	await _present(panel, _model(platform))
	var before: Array = panel.draft_bindings()
	panel.suspend_input(true)
	await _left_down_up(viewport, Vector2(105 + 1, 25 + 8 * 16 + 1))
	viewport.push_input(_event_key(KEY_Z, true), true)
	await _settle()
	_expect_equal(panel.draft_bindings(), before, "suspended child ignores mouse and key input")
	_expect(not panel.pending_blink_visible(), "suspended child hides pending blink")
	panel.suspend_input(false)
	await _left_down_up(viewport, Vector2(105 + 1, 25 + 8 * 16 + 1))
	viewport.push_input(_event_key(KEY_Z, true), true)
	await _settle()
	_expect_equal(panel.draft_bindings()[8], KEY_Z, "resumed child accepts allowed key")
	var visuals := FakeVisuals.new()
	await _present(panel, _model(platform, "MultiverseJourney"), visuals)
	for call in visuals.calls:
		_expect_equal(call[0], "MultiverseJourney", "second edition never borrows Game art")
	# Invalid/short/extra models fail closed and remain closable.
	for invalid in [
		{}, {"edition": "Unknown", "bindings": platform.defaults()},
		{"edition": "Game", "bindings": []}, {"edition": "Game", "bindings": platform.defaults() + [0]},
	]:
		panel.set_view_model(invalid)
		await _settle()
		_expect(not panel.is_model_valid() and not panel.source_art_available(), "invalid model is unavailable")
		_expect(panel.close_hotkeys(), "invalid presenter remains explicitly closable")


func _on_accepted(bindings: Array) -> void:
	_accepted.append(bindings.duplicate(true))


func _on_cancelled() -> void:
	_cancelled += 1
