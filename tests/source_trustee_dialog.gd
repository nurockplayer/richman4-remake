extends SceneTree

## Focused S04 source trustee presenter/controller checks.  These use a
## synthetic visual resolver and detached rows; no original art is committed.

const DIALOG_PATH := "res://game/ui/source_trustee_dialog.gd"
const CONTROLLER_PATH := "res://game/ui/source_trustee_controller.gd"
const ORIGIN := Vector2(102, 62)

var checks := 0
var failures := 0
var accepted_rows: Array = []
var cancelled_count := 0
var dialog_cancelled_count := 0


class FakeVisuals extends RefCounted:
	var calls: Array = []

	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		calls.append([edition, archive, resource, chunk])
		return {"edition": edition, "archive": archive, "resource": resource, "chunk": chunk,
			"logical": {"width": 435, "height": 355, "anchor_x": 0, "anchor_y": 0}}

	func texture(_frame: Dictionary) -> Texture2D:
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color("#336699"))
		return ImageTexture.create_from_image(image)


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


func _rows() -> Array:
	return [
		{"player_id": 0, "name": "甲", "trustee": false, "use_cards": true, "use_tools": true, "personality": 0, "cash_ratio": 0, "stock_ratio": 100},
		{"player_id": 2, "name": "丙", "trustee": true, "use_cards": false, "use_tools": true, "personality": 2, "cash_ratio": 50, "stock_ratio": 50},
	]


func _mouse(position: Vector2, button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	return event


func _run() -> void:
	if not FileAccess.file_exists(DIALOG_PATH) or not FileAccess.file_exists(CONTROLLER_PATH):
		push_error("FAIL: source trustee presenter/controller is absent")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var dialog: Control = load(DIALOG_PATH).new()
	viewport.add_child(dialog)
	var visuals := FakeVisuals.new()
	_expect(bool(dialog.call("configure", _rows(), 0, "Game")), "dialog configures valid detached rows")
	_expect(dialog.call("is_model_valid"), "configured model is valid")
	visuals.calls.clear()
	dialog.set_visual_accessor(visuals)
	var geometry: Dictionary = dialog.call("source_geometry")
	_expect(geometry.get("panel_origin") == ORIGIN and geometry.get("panel_size") == Vector2(435, 355), "source Panel77 geometry is 435x355 at 102,62")
	var hitboxes: Dictionary = dialog.call("source_hitboxes")
	var row_hitboxes: Array = hitboxes.get("rows", [])
	_expect(row_hitboxes.size() == 2 and row_hitboxes[0].size == Vector2(116, 83), "source rows use the measured identity hitbox")
	_expect(hitboxes.get("accept") == ORIGIN + Vector2(377, 97) and hitboxes.get("cancel") == ORIGIN + Vector2(377, 185), "source actions use the right vertical button strip")
	_expect(dialog.call("source_art_available"), "injected resolver supplies Panel77 art")
	_expect(visuals.calls.has(["Game", "Panel", 77, 0]) and visuals.calls.has(["Game", "Panel", 77, 1]) and visuals.calls.has(["Game", "Panel", 77, 2]) and visuals.calls.all(func(call: Array) -> bool: return call[0] == "Game" and call[1] == "Panel" and call[2] == 77), "Game Panel77 lookup preserves archive/resource/edition")
	await _settle()

	_expect(dialog.call("selected_player_id") == 0, "current player is initially selected")
	dialog.call("select_player", 2)
	_expect(dialog.call("selected_player_id") == 2 and bool(dialog.call("draft_rows")[1].get("trustee")), "first click on another row only selects")
	dialog.call("select_player", 2)
	_expect(not bool(dialog.call("draft_rows")[1].get("trustee")), "second click on selected row toggles trustee")
	dialog.call("set_flag", 0, "use_cards", false)
	dialog.call("set_flag", 0, "use_tools", false)
	dialog.call("set_personality", 0, 1)
	dialog.call("set_ratio", 0, "cash_ratio", 20)
	dialog.call("adjust_ratio", 0, "stock_ratio", -1)
	var draft: Array = dialog.call("draft_rows")
	_expect(not bool(draft[0].get("use_cards")) and not bool(draft[0].get("use_tools")), "card/tool flags are independently mutable")
	_expect(int(draft[0].get("personality")) == 1 and int(draft[0].get("cash_ratio")) == 20, "personality and cash ratio remain in draft")
	_expect(int(draft[0].get("stock_ratio")) == 90, "ratio changes move in ten point increments")
	dialog.cancelled.connect(func() -> void: dialog_cancelled_count += 1)
	_expect(bool(dialog.call("configure", _rows(), 0, "Game")), "dialog reopens for input release checks")
	dialog.call("_gui_input", _mouse(ORIGIN + Vector2(224, 277), MOUSE_BUTTON_LEFT, true))
	dialog.call("_gui_input", _mouse(ORIGIN + Vector2(224, 277), MOUSE_BUTTON_LEFT, false))
	_expect(int(dialog.call("draft_rows")[0].get("cash_ratio")) == 20, "cash ratio bar click snaps to ten point increments")
	dialog.call("_gui_input", _mouse(ORIGIN + Vector2(200, 55), MOUSE_BUTTON_LEFT, true))
	dialog.call("_gui_input", _mouse(ORIGIN + Vector2(200, 55), MOUSE_BUTTON_LEFT, false))
	_expect(not bool(dialog.call("draft_rows")[0].get("use_cards")), "card flag click changes only the selected row flag")
	dialog.call("_gui_input", _mouse(Vector2(2, 2), MOUSE_BUTTON_RIGHT, false))
	_expect(dialog_cancelled_count == 1 and not dialog.call("is_open"), "right button release cancels and discards the dialog")
	_expect(bool(dialog.call("configure", _rows(), 0, "Game")), "dialog reopens for Escape check")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	dialog.call("_gui_input", escape)
	_expect(dialog_cancelled_count == 2 and not dialog.call("is_open"), "Escape cancels the dialog")
	_expect(bool(dialog.call("configure", _rows(), 0, "MultiverseJourney")), "dialog configures the expansion edition")
	visuals.calls.clear()
	dialog.set_visual_accessor(visuals)
	_expect(visuals.calls.has(["MultiverseJourney", "Panel", 77, 0]) and visuals.calls.has(["MultiverseJourney", "Panel", 77, 1]) and visuals.calls.all(func(call: Array) -> bool: return call[0] == "MultiverseJourney" and call[1] == "Panel" and call[2] == 77), "MJ Panel77 lookup is edition-specific and observable")

	_expect(bool(dialog.call("configure", _rows(), 0, "Game")), "dialog reopens for explicit cancel check")
	var before_cancel: Array = dialog.call("committed_rows")
	_expect(bool(dialog.call("cancel_dialog")), "cancel closes dialog")
	_expect(dialog.call("committed_rows") == before_cancel, "cancel does not mutate committed snapshot")
	_expect(not dialog.call("is_open"), "cancelled presenter is closed")

	var controller: Control = load(CONTROLLER_PATH).new()
	viewport.add_child(controller)
	controller.accepted.connect(func(value: Array) -> void: accepted_rows.append(value))
	controller.cancelled.connect(func() -> void: cancelled_count += 1)
	var controller_rows := _rows()
	_expect(bool(controller.call("configure", controller_rows, 0, "MultiverseJourney", "")), "controller configures MJ rows")
	var exposed: Array = controller.call("draft_rows")
	exposed[0]["name"] = "外部修改"
	_expect(str(controller.call("draft_rows")[0].get("name")) == "甲", "controller exposes deep copied draft")
	controller.dialog.call("select_player", 0)
	controller.dialog.call("accept_dialog")
	await _settle()
	_expect(accepted_rows.size() == 1 and not controller.call("is_open"), "controller emits accepted only after OK")
	_expect(int(accepted_rows[0][0].get("player_id")) == 0, "accepted rows preserve player identity")
	_expect(bool(controller.call("configure", _rows(), 0, "Game", "")), "controller can open a fresh session")
	controller.call("cancel")
	_expect(cancelled_count == 1 and not controller.call("is_open"), "controller relays cancel without state writes")

	viewport.queue_free()
	await _settle()
	print("Source trustee dialog checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
