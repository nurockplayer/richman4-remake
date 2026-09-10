extends SceneTree

const SourceSavePanelScript = preload("res://game/ui/source_save_panel.gd")
const SaveSlotsScript = preload("res://game/platform/save_slots.gd")
const GameStateScript = preload("res://game/core/game_state.gd")

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
	await _test_real_scan_consumer_and_source_atlas()
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
			"date": {"year": 1998, "month": 1, "day": 1},
			"map_name": "臺北市",
			"map_edition": "Game",
			"map_number": 2,
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
	var reference_canvas_rect := Rect2(Vector2.ZERO, Vector2(640.0, 480.0))
	var load_confirm_rect := Rect2(panel.action_bar.position + panel.confirm_button.position, panel.confirm_button.size * panel.confirm_button.scale)
	var load_cancel_rect := Rect2(panel.action_bar.position + panel.cancel_button.position, panel.cancel_button.size * panel.cancel_button.scale)
	expect_equal(load_confirm_rect, Rect2(222, 456, 94, 24), "load confirm action rect is anchored to the source footer")
	expect_equal(load_cancel_rect, Rect2(324, 456, 94, 24), "load cancel action rect is anchored to the source footer")
	expect(reference_canvas_rect.encloses(load_confirm_rect), "load confirm action rect stays inside the source canvas")
	expect(reference_canvas_rect.encloses(load_cancel_rect), "load cancel action rect stays inside the source canvas")
	expect(visuals.ui_calls.size() > 0 and visuals.ui_calls[0].resource == 479 and visuals.ui_calls[0].chunk == 0, "Game load uses mapped Data479 chunk zero")
	expect(visuals.ui_calls.any(func(call: Dictionary) -> bool: return call.resource == 479 and call.chunk == 6), "Game load uses mapped Data479 slot label chunk")
	expect(visuals.ui_calls.any(func(call: Dictionary) -> bool: return call.resource == 479 and call.chunk == 3), "Game load maps source map number two to Data479 chunk three")
	expect(visuals.ui_calls.any(func(call: Dictionary) -> bool: return call.resource == 2 and call.chunk == 0), "portrait uses the existing mapped Data2 accessor")
	expect_equal(panel.get_row_visual_rect(0, "slot_label"), Rect2(129, 24, 72, 72), "slot label atlas is drawn at source row origin")
	# Label keeps the theme's 23px line box; the source callback alignment is
	# asserted by the absolute position, while the line box remains unclipped.
	expect_equal(panel.get_row_visual_rect(0, "date_year"), Rect2(165, 60, 44, 23), "date year uses source absolute x and y offset")
	expect_equal(panel.get_row_visual_rect(0, "date_month_day"), Rect2(165, 81, 44, 23), "date month/day uses source absolute x and y offset")
	expect_equal(panel.get_row_visual_rect(0, "map"), Rect2(209, 24, 72, 72), "map thumbnail uses source absolute row geometry")
	expect_equal(panel.get_row_visual_rect(0, "portrait_0"), Rect2(289, 24, 72, 72), "portrait zero uses source absolute row geometry")
	expect_equal(panel.get_row_visual_rect(0, "portrait_1"), Rect2(361, 24, 72, 72), "portrait one advances by source 72px")
	var original_label_node: Node = panel.row_content[0].find_child("OriginalSaveLabel", true, false)
	expect(original_label_node is Label, "row zero has a visible existing-save label")
	if original_label_node is Label:
		var original_label: Label = original_label_node
		expect_equal(original_label.text, "原有存檔", "row zero is explicitly labelled as the existing save")
		var row_zero_rect: Rect2 = panel.get_row_rect(0)
		var label_rect: Rect2 = Rect2(row_zero_rect.position + original_label.position, original_label.size)
		var year_rect: Rect2 = panel.get_row_visual_rect(0, "date_year")
		var month_day_rect: Rect2 = panel.get_row_visual_rect(0, "date_month_day")
		expect(label_rect.position.x >= row_zero_rect.position.x, "existing-save label stays inside row bounds horizontally")
		expect(label_rect.end.x <= row_zero_rect.end.x, "existing-save label does not overflow the row bounds")
		expect(label_rect.end.y <= year_rect.position.y, "existing-save label stays above the source date")
		expect(not label_rect.intersects(year_rect), "existing-save label does not intrude into the date year")
		expect(not label_rect.intersects(month_day_rect), "existing-save label does not intrude into the date month/day")
	expect(panel.row_content[0].find_child("SlotNumber", true, false) == null, "source frame slot number is not duplicated by a child label")
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
	var save_canvas_rect := Rect2(Vector2.ZERO, Vector2(640.0, 480.0))
	var save_confirm_rect := Rect2(panel.action_bar.position + panel.confirm_button.position, panel.confirm_button.size * panel.confirm_button.scale)
	var save_cancel_rect := Rect2(panel.action_bar.position + panel.cancel_button.position, panel.cancel_button.size * panel.cancel_button.scale)
	expect_equal(save_confirm_rect, Rect2(222, 438, 94, 24), "save confirm action rect is anchored to the source footer")
	expect_equal(save_cancel_rect, Rect2(324, 438, 94, 24), "save cancel action rect is anchored to the source footer")
	expect(save_canvas_rect.encloses(save_confirm_rect), "save confirm action rect stays inside the source canvas")
	expect(save_canvas_rect.encloses(save_cancel_rect), "save cancel action rect stays inside the source canvas")
	expect(visuals.ui_calls.size() > 0 and visuals.ui_calls[0].edition == "MultiverseJourney" and visuals.ui_calls[0].resource == 520 and visuals.ui_calls[0].chunk == 1, "save frame stays on the panel edition")
	expect(visuals.ui_calls.any(func(call: Dictionary) -> bool: return call.edition == "Game" and call.resource == 479 and call.chunk == 3), "save row uses each preview's Game map atlas")
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


func _test_real_scan_consumer_and_source_atlas() -> void:
	var temp_base := OS.get_environment("TMPDIR")
	if temp_base.is_empty():
		temp_base = "/tmp"
	var root_path := temp_base.path_join("richman4-source-panel-%d-%d" % [Time.get_ticks_usec(), OS.get_process_id()])
	var slots_path := root_path.path_join("slots")
	var default_path := root_path.path_join("default.json")
	expect(DirAccess.make_dir_recursive_absolute(root_path) == OK, "integration test creates an isolated save root")
	var store := SaveSlotsScript.new(slots_path, default_path)
	var game: Object = GameStateScript.new_game(11704, 4)
	expect(game != null, "integration fixture creates a four-player state")
	if game == null:
		return
	var payload: Dictionary = game.to_dict()
	payload = _with_fixture_identity(payload, "Game", 2, "臺北市")
	var write_result: Dictionary = store.write(1, payload, "")
	expect(bool(write_result.get("ok", false)), "integration fixture writes through SaveSlots")
	if not bool(write_result.get("ok", false)):
		DirAccess.remove_absolute(root_path)
		return
	var multiverse_payload: Dictionary = _with_fixture_identity(payload, "MultiverseJourney", 5, "異界都市")
	var multiverse_write := store.write(2, multiverse_payload, "")
	expect(bool(multiverse_write.get("ok", false)), "integration fixture writes a mixed-edition SaveSlots row")
	var unknown_payload: Dictionary = payload.duplicate(true)
	unknown_payload.erase("map_id")
	unknown_payload.erase("map_name")
	unknown_payload.erase("map_source")
	var unknown_write := store.write(3, unknown_payload, "")
	expect(bool(unknown_write.get("ok", false)), "integration fixture writes an explicit unknown-source row")
	var scan: Dictionary = store.scan()
	expect(bool(scan.get("ok", false)), "integration consumer receives a successful scan")
	var row: Dictionary = scan.get("slots", [])[1]
	expect_equal(row.get("status"), SaveSlotsScript.STATUS_VALID, "integration scan row is valid")
	expect_equal(row.get("metadata", {}).get("player_character_ids"), [0, 1, 2, 3], "metadata preserves all four explicit character ids")
	expect_equal(row.get("metadata", {}).get("map_edition"), "Game", "metadata preserves the Game source edition")
	expect_equal(row.get("metadata", {}).get("map_number"), 2, "metadata preserves source map number")
	expect_equal(row.get("metadata", {}).get("map_preview_chunk"), 3, "metadata maps source map number to the atlas chunk")
	var mixed_row: Dictionary = scan.get("slots", [])[2]
	expect_equal(mixed_row.get("status"), SaveSlotsScript.STATUS_VALID, "mixed-edition scan row is valid")
	expect_equal(mixed_row.get("metadata", {}).get("map_edition"), "MultiverseJourney", "metadata preserves the MultiverseJourney source edition")
	expect_equal(mixed_row.get("metadata", {}).get("map_number"), 5, "mixed-edition metadata preserves its source map number")
	var unknown_row: Dictionary = scan.get("slots", [])[3]
	expect_equal(unknown_row.get("metadata", {}).get("map_edition"), "", "metadata leaves unknown source edition empty")
	expect_equal(unknown_row.get("metadata", {}).get("map_preview_chunk"), -1, "metadata leaves unknown map preview unavailable")
	var panel := _panel()
	var visuals := FakeVisuals.new()
	panel.configure("Game", "load", scan, visuals)
	await process_frame
	expect(panel.select_slot(1), "panel selects the real scanned valid row")
	expect(visuals.ui_calls.any(func(call: Dictionary) -> bool: return call.resource == 479 and call.chunk == 3), "panel requests the real Game map preview chunk")
	for chunk in range(4):
		expect(visuals.ui_calls.any(func(call: Dictionary) -> bool: return call.resource == 2 and call.chunk == chunk), "panel requests source portrait chunk %d" % chunk)
	# The provisional v1 fixture stores month/day only, so year stays absent
	# rather than being invented in the preview.
	expect_equal(panel.get_row_visual_rect(1, "date_year"), Rect2(), "integrated date year stays unavailable without source metadata")
	expect_equal(panel.get_row_visual_rect(1, "date_month_day"), Rect2(165, 153, 44, 23), "integrated date month/day remains source aligned")
	expect_equal(panel.get_row_visual_rect(1, "map"), Rect2(209, 96, 72, 72), "integrated map preview remains source aligned")
	for index in range(4):
		expect_equal(panel.get_row_visual_rect(1, "portrait_%d" % index), Rect2(289 + index * 72, 96, 72, 72), "integrated portrait %d remains source aligned" % index)
	expect(visuals.ui_calls.any(func(call: Dictionary) -> bool: return call.edition == "MultiverseJourney" and call.resource == 520 and call.chunk == 6), "panel selects mixed row map atlas from row metadata")
	for chunk in range(4):
		expect(visuals.ui_calls.any(func(call: Dictionary) -> bool: return call.edition == "MultiverseJourney" and call.resource == 2 and call.chunk == chunk), "mixed row requests source portrait chunk %d from row edition" % chunk)
	expect_equal(panel.get_row_visual_rect(2, "map"), Rect2(209, 168, 72, 72), "mixed row map preview remains source aligned")
	for index in range(4):
		expect_equal(panel.get_row_visual_rect(2, "portrait_%d" % index), Rect2(289 + index * 72, 168, 72, 72), "mixed row portrait %d remains source aligned" % index)
	expect_equal(panel.get_row_visual_rect(3, "map"), Rect2(), "unknown row source does not guess a map atlas")
	expect_equal(panel.get_row_visual_rect(3, "portrait_0"), Rect2(), "unknown row source does not guess a portrait atlas")
	expect(panel.row_content[1].find_child("SlotNumber", true, false) == null, "integrated row does not duplicate source slot number")
	expect(not panel.get_row_rect(5).intersects(Rect2(panel.action_bar.position, panel.action_bar.size)), "integrated footer remains outside the final row hit region")
	panel.queue_free()
	DirAccess.remove_absolute(store.slot_path(1))
	DirAccess.remove_absolute(slots_path)
	DirAccess.remove_absolute(root_path)


func _with_fixture_identity(payload: Dictionary, source_edition: String, map_number: int, map_name: String) -> Dictionary:
	var result := payload.duplicate(true)
	var fixture_players: Array = result.get("players", []).duplicate(true)
	for index in range(4):
		var fixture_player: Dictionary = fixture_players[index].duplicate(true)
		fixture_player["character_id"] = index
		fixture_player["name"] = ["約翰喬", "沙隆巴斯", "忍太郎", "錢夫人"][index]
		fixture_players[index] = fixture_player
	result["players"] = fixture_players
	result["map_id"] = "%s:%d" % [source_edition, map_number]
	result["map_name"] = map_name
	result["map_source"] = {"edition": source_edition, "map_number": map_number}
	return result
