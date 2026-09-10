extends SceneTree

const SourceSavePanelScript = preload("res://game/ui/source_save_panel.gd")

var checks := 0
var failures := 0


class FakeVisuals extends RefCounted:
	var ui_calls: Array = []
	var texture_calls: Array = []
	var texture_value: Texture2D

	func _init() -> void:
		var image := Image.create(555, 451, false, Image.FORMAT_RGBA8)
		image.fill(Color("#8daea7"))
		texture_value = ImageTexture.create_from_image(image)

	func ui(edition: String, archive: String, resource: int, chunk: int = 0) -> Dictionary:
		ui_calls.append({"edition": edition, "archive": archive, "resource": resource, "chunk": chunk})
		return {
			"path": "images/source.png",
			"sha256": "a".repeat(64),
			"width": 555,
			"height": 451,
			"logical": {"width": 555, "height": 451, "anchor_x": 0, "anchor_y": 0},
		}

	func texture(frame: Dictionary) -> Texture2D:
		texture_calls.append(frame.duplicate(true))
		return texture_value


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	await _test_load_rows_and_geometry()
	await _test_save_selection_and_overwrite()
	await _test_no_io_and_payload_isolation()
	print("Source save panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _panel() -> Control:
	var panel: Control = SourceSavePanelScript.new()
	panel.size = Vector2(1280.0, 800.0)
	root.add_child(panel)
	return panel


func _valid_preview(slot_id: int, fingerprint: String = "") -> Dictionary:
	return {
		"ok": true,
		"status": "valid",
		"slot": slot_id,
		"path": "/tmp/richman4-slot-%d.json" % slot_id,
		"fingerprint": fingerprint if not fingerprint.is_empty() else ("%x" % slot_id).repeat(64).substr(0, 64),
		"metadata": {
			"date_text": "1998-01-01",
			"map_name": "臺北市",
			"player_names": ["約翰喬", "沙隆巴斯"],
			"player_character_ids": [0, 1],
		},
	}


func _empty_preview(slot_id: int) -> Dictionary:
	return {"ok": true, "status": "empty", "slot": slot_id, "path": "/tmp/slot-%d.json" % slot_id, "fingerprint": "", "metadata": {}}


func _invalid_preview(slot_id: int, status: String) -> Dictionary:
	return {"ok": false, "status": status, "slot": slot_id, "path": "/tmp/slot-%d.json" % slot_id, "fingerprint": "b".repeat(64), "error": "fixture_%s" % status, "metadata": {}}


func _test_load_rows_and_geometry() -> void:
	var panel := _panel()
	var visuals := FakeVisuals.new()
	var rows: Array = [_valid_preview(0, "c".repeat(64))]
	for slot_id in range(1, 6):
		rows.append(_invalid_preview(slot_id, "invalid" if slot_id == 1 else "corrupt" if slot_id == 2 else "unreadable" if slot_id == 3 else "empty"))
	# Keep row 4/5 explicitly empty with canonical fields.
	rows[4] = _empty_preview(4)
	rows[5] = _empty_preview(5)
	panel.configure("Game", "load", {"ok": true, "status": "scanned", "slots": rows}, visuals)
	await process_frame
	expect_equal(panel.get_mode(), "load", "load mode is retained")
	expect_equal(panel.get_edition(), "Game", "edition is retained")
	expect_equal(panel.get_row_count(), 6, "load exposes six source rows")
	expect_equal(panel.row_buttons.size(), 6, "load builds six row hit controls")
	var load_geometry: Dictionary = panel.get_source_geometry()
	expect_equal(load_geometry.get("canvas"), Vector2(640, 480), "picker uses the source 640x480 reference canvas")
	expect_equal(load_geometry.get("image_position"), Vector2(40, 15), "load art uses the source centered y placement")
	expect_equal(load_geometry.get("image_size"), Vector2(555, 451), "load art keeps the source dimensions")
	expect_equal(panel.get_row_rect(0), Rect2(129, 24, 448, 72), "load row zero mirrors source callback geometry")
	expect_equal(panel.get_row_rect(5), Rect2(129, 384, 448, 72), "load row five mirrors 72px source spacing")
	expect(not panel.get_row_rect(5).intersects(Rect2(panel.action_bar.position, panel.action_bar.size)), "load action controls do not occlude the final row hit region")
	expect(panel.row_buttons[0].disabled == false, "valid row zero is loadable")
	expect(panel.row_buttons[1].disabled, "invalid load row is disabled")
	expect(panel.row_buttons[2].disabled, "corrupt load row is disabled")
	expect(panel.row_buttons[3].disabled, "unreadable load row is disabled")
	expect(panel.row_buttons[4].disabled, "empty load row is disabled")
	expect(panel.select_slot(1) == false, "disabled invalid load row cannot be selected")
	expect(panel.select_slot(0), "valid load row can be selected")
	expect_equal(panel.selected_fingerprint(), "c".repeat(64), "selection retains preview fingerprint")
	expect(visuals.ui_calls.size() > 0 and visuals.ui_calls[0].resource == 479 and visuals.ui_calls[0].chunk == 0, "Game load uses mapped Data479 chunk zero")
	expect(visuals.ui_calls.any(func(call: Dictionary) -> bool: return call.resource == 2 and call.chunk == 0), "portrait uses the existing mapped Data2 accessor")
	panel.size = Vector2(700.0, 600.0)
	await process_frame
	expect(is_equal_approx(panel.reference_canvas.scale.x, minf(700.0 / 640.0, 600.0 / 480.0)), "reference canvas uses contain scaling on resize")
	var before_cancel: Array = panel.get_previews()
	var cancelled: Array = []
	panel.cancelled.connect(func(slot_id: int, fingerprint: String, preview: Dictionary) -> void: cancelled.append([slot_id, fingerprint, preview]))
	panel.cancel_selection()
	expect_equal(cancelled.size(), 1, "cancel emits one selection event")
	expect_equal(cancelled[0][0], 0, "cancel includes selected slot id")
	expect_equal(cancelled[0][1], "c".repeat(64), "cancel includes selected fingerprint")
	expect_equal(panel.get_previews(), before_cancel, "cancel leaves row previews unchanged")
	panel.queue_free()


func _test_save_selection_and_overwrite() -> void:
	var panel := _panel()
	var visuals := FakeVisuals.new()
	var rows: Array = [_empty_preview(1), _valid_preview(2, "d".repeat(64)), _empty_preview(3), _invalid_preview(4, "corrupt"), _empty_preview(5)]
	panel.configure("MultiverseJourney", "save", rows, visuals)
	await process_frame
	expect_equal(panel.get_row_count(), 5, "save exposes five source rows")
	var save_geometry: Dictionary = panel.get_source_geometry()
	expect_equal(save_geometry.get("image_position"), Vector2(40, 48), "save art uses the source (40,48) placement")
	expect_equal(save_geometry.get("image_size"), Vector2(555, 381), "save art keeps the source dimensions")
	expect_equal(panel.get_row_rect(1), Rect2(129, 57, 448, 72), "save row one uses source y 0x39")
	expect_equal(panel.get_row_rect(5), Rect2(129, 345, 448, 72), "save row five uses source y 0x39 plus four rows")
	expect(not panel.get_row_rect(5).intersects(Rect2(panel.action_bar.position, panel.action_bar.size)), "save action controls do not occlude the final row hit region")
	expect(panel.row_buttons[1].disabled == false and panel.row_buttons[2].disabled == false, "save rows stay selectable for empty and occupied paths")
	expect(panel.select_slot(1), "empty save row can be selected")
	var confirmed: Array = []
	var overwrite_requests: Array = []
	panel.confirmed.connect(func(slot_id: int, fingerprint: String, preview: Dictionary) -> void: confirmed.append([slot_id, fingerprint, preview]))
	panel.overwrite_confirmation_requested.connect(func(slot_id: int, fingerprint: String, preview: Dictionary) -> void: overwrite_requests.append([slot_id, fingerprint, preview]))
	expect(panel.confirm_selection(), "empty save row confirms without overwrite prompt")
	expect_equal(confirmed.size(), 1, "empty save confirmation emits one event")
	expect_equal(confirmed[0][0], 1, "save confirmation includes selected slot id")
	expect_equal(confirmed[0][1], "", "empty save confirmation includes empty fingerprint")
	expect(panel.select_slot(2), "occupied save row can be selected")
	expect(panel.confirm_selection() == false, "occupied save row waits for reversible confirmation")
	expect(panel.is_overwrite_confirmation_visible(), "occupied save row opens custom overwrite overlay")
	expect_equal(overwrite_requests.size(), 1, "overwrite request is emitted before mutation")
	expect_equal(overwrite_requests[0][0], 2, "overwrite request includes selected slot id")
	expect_equal(overwrite_requests[0][1], "d".repeat(64), "overwrite request includes preview fingerprint")
	var rows_before_cancel: Array = panel.get_previews()
	panel.cancel_overwrite()
	expect(not panel.is_overwrite_confirmation_visible(), "overwrite cancel closes source overlay")
	expect_equal(panel.get_previews(), rows_before_cancel, "overwrite cancel leaves previews unchanged")
	expect(panel.select_slot(2), "occupied row remains selected after overwrite cancel")
	expect(panel.confirm_selection() == false and panel.confirm_overwrite(), "overwrite can be confirmed explicitly")
	expect_equal(confirmed.size(), 2, "confirmed overwrite emits one final event")
	panel.queue_free()


func _test_no_io_and_payload_isolation() -> void:
	var panel := _panel()
	var row := _valid_preview(0, "e".repeat(64))
	var rows: Array = [row]
	for slot_id in range(1, 6):
		rows.append(_empty_preview(slot_id))
	var payload := {"seed": 117, "phase": "await_roll"}
	panel.configure("Game", "load", rows, null, payload)
	await process_frame
	var before: Array = panel.get_previews()
	expect(panel.save_payload == payload, "optional payload is copied without live game adoption")
	panel.select_slot(0)
	var selected: Dictionary = panel.selected_preview()
	selected.metadata.map_name = "mutated outside panel"
	expect_equal(panel.selected_preview().metadata.map_name, "臺北市", "selected preview is deep copied for callers")
	panel.cancel_selection()
	expect_equal(panel.get_previews(), before, "cancel does not mutate validated row payloads")
	# No SaveSlots instance, FileAccess call, or path is supplied to the panel;
	# the only source lookup is the optional accessor and it was null here.
	expect(panel.visuals == null, "panel has no default filesystem-backed visual accessor")
	panel.queue_free()
