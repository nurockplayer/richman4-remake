extends SceneTree

## Focused hermetic S19 presenter checks.  No GameState, MainUI, persistence,
## inventory rules or owner/controller is instantiated by this suite.

const PANEL_PATH := "res://game/ui/source_inventory_panel.gd"
const ORIGIN := Vector2(19, 135)
const STRIDE := Vector2(80, 56)

var checks := 0
var failures := 0
var selected_ids: Array[int] = []
var cancelled_count := 0


class FakeVisuals extends RefCounted:
	var calls: Array = []
	var texture_calls: Array = []
	var physical_scale := 2

	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		calls.append([edition, archive, resource, chunk])
		var size := Vector2(412, 180) if chunk <= 1 else Vector2(40, 34)
		if chunk >= 15:
			size = Vector2(80, 56)
		return {"edition": edition, "archive": archive, "resource": resource, "chunk": chunk, "logical": {"width": size.x, "height": size.y, "anchor_x": 20 if chunk in range(2,15) else 0, "anchor_y": 17 if chunk in range(2,15) else 0}}

	func texture(frame: Dictionary) -> Texture2D:
		texture_calls.append(frame.duplicate(true))
		var logical: Dictionary = frame.get("logical", {})
		var image := Image.create(maxi(1, int(logical.get("width", 1)) * physical_scale), maxi(1, int(logical.get("height", 1)) * physical_scale), false, Image.FORMAT_RGBA8)
		image.fill(Color(0.15 + 0.02 * int(frame.get("chunk", 0)), 0.4, 0.5, 1))
		return ImageTexture.create_from_image(image)


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _settle() -> void:
	await process_frame
	await process_frame


func _event(point: Vector2, button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	return event


func _click(viewport: SubViewport, point: Vector2, release_point := Vector2.INF) -> void:
	var up := point if release_point == Vector2.INF else release_point
	viewport.push_input(_event(point, MOUSE_BUTTON_LEFT, true), true)
	await _settle()
	viewport.push_input(_event(up, MOUSE_BUTTON_LEFT, false), true)
	await _settle()


func _new_pair() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var panel: Control = load(PANEL_PATH).new()
	viewport.add_child(panel)
	panel.selected.connect(func(source_id: int) -> void: selected_ids.append(source_id))
	panel.cancelled.connect(func() -> void: cancelled_count += 1)
	return {"viewport": viewport, "panel": panel}


func _cards(count: int, duplicate_id := 0) -> Array:
	var result: Array = []
	for index in range(count):
		var source_id := duplicate_id if duplicate_id > 0 and index == 1 else index + 1
		result.append({"source_id": source_id, "name": "卡%d" % source_id})
	return result


func _tools(ids: Array, count := 1) -> Array:
	var result: Array = []
	for source_id in ids:
		result.append({"source_id": source_id, "name": "具%d" % source_id, "count": count})
	return result


func _model(mode: String, cards: Array = [], tools: Array = [], vehicle := "walking") -> Dictionary:
	return {"mode": mode, "edition": "Game", "cards": cards, "tools": tools, "vehicle": vehicle}


func _run() -> void:
	if not FileAccess.file_exists(PANEL_PATH):
		expect(false, "source inventory presenter exists")
		print("Source inventory panel RED: implementation absent; checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var pair := _new_pair()
	var viewport: SubViewport = pair.viewport
	var panel: Control = pair.panel
	var visuals := FakeVisuals.new()
	expect(not panel.visible and not panel.is_open(), "unconfigured panel starts hidden and inert")
	panel.set_visual_accessor(visuals)

	var original_cards := _cards(15, 4)
	var card_model := _model("cards", original_cards)
	expect(panel.configure(card_model), "15-card model accepted")
	expect(panel.is_open(), "configured inventory is open")
	expect_equal(panel.view_model(), card_model, "model is a complete detached snapshot")
	expect_equal(panel.source_geometry().get("grid_origin"), ORIGIN, "source grid origin is exact")
	expect_equal(panel.source_geometry().get("cell_size"), STRIDE, "source grid stride is exact")
	expect_equal(panel.slot_source_id(0), 1, "card order starts at source ID 1")
	expect_equal(panel.slot_source_id(1), 4, "duplicate card remains in source order")
	card_model.cards[0].name = "caller mutation"
	expect_equal(panel.view_model().cards[0].name, "卡1", "caller mutation cannot change snapshot")
	var background := panel.find_child("SourceInventoryBackground", true, false) as TextureRect
	expect(background != null and background.texture.get_size() == Vector2(824, 360), "2x source texture keeps logical panel geometry")
	var card_label := panel.find_child("SourceInventoryCard0", true, false) as Label
	expect(card_label != null and card_label.position + card_label.size/2.0 == Vector2(59, 163) and card_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and card_label.get_theme_font_size("font_size") == 20, "card text centers on source mode2 anchor with source font size")
	visuals.physical_scale = 1
	panel.set_visual_accessor(visuals)
	background = panel.find_child("SourceInventoryBackground", true, false) as TextureRect
	expect(background != null and background.texture.get_size() == Vector2(412, 180), "1x source texture keeps logical panel geometry")
	visuals.physical_scale = 2

	selected_ids.clear()
	viewport.push_input(_event(ORIGIN + Vector2(1, 1), MOUSE_BUTTON_LEFT, true), true)
	await _settle()
	var pressed := panel.find_child("SourceInventoryPressedCell", true, false) as Panel
	expect(pressed != null and pressed.position == Vector2(20, 136) and pressed.size == Vector2(78, 54), "down paints source inset-1 pressed cell")
	viewport.push_input(_event(Vector2(500, 400), MOUSE_BUTTON_LEFT, false), true)
	await _settle()
	expect_equal(selected_ids, [1], "left-down inside then release outside commits latched card")
	expect(not panel.is_open(), "successful selection closes the list")

	panel.configure(card_model)
	selected_ids.clear()
	await _click(viewport, ORIGIN + STRIDE * Vector2(1, 0) + Vector2(1, 1))
	expect_equal(selected_ids, [4], "duplicate entry selects its source ID")

	panel.configure(_model("cards", _cards(1)))
	selected_ids.clear()
	await _click(viewport, ORIGIN + STRIDE * Vector2(1, 0) + Vector2(1, 1))
	expect_equal(selected_ids, [], "empty slot press is inert")
	expect(panel.is_open(), "empty slot does not close")
	await _click(viewport, Vector2(500, 400))
	expect_equal(selected_ids, [], "release-only is inert")
	var before_cancel := cancelled_count
	await _right_release(viewport, Vector2(500, 400))
	expect_equal(cancelled_count, before_cancel + 1, "right release cancels from outside")

	panel.configure(_model("tools", [], _tools(range(1, 14))))
	expect_equal(panel.slot_source_id(0), 1, "tool source IDs start compactly")
	expect_equal(panel.slot_source_id(12), 13, "all 13 positive tool types are compact")
	expect_equal(panel.source_at(ORIGIN + STRIDE * Vector2(2, 2) + Vector2(1, 1)), 13, "last ordinary tool occupies compact slot 13")
	var quantity_label := panel.find_child("SourceInventoryQuantity0", true, false) as Label
	expect(quantity_label != null and quantity_label.text == "1", "tool quantity is rendered")
	expect(quantity_label.position.x + quantity_label.size.x == 93 and quantity_label.position.y == 153 and quantity_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "quantity mode1 is right-aligned at source79,23 plus panel origin")
	expect(panel.find_child("SourceInventoryCard0", true, false) == null and panel.find_child("SourceInventoryName0", true, false) == null, "tools render icon and quantity without invented names")
	var tool_icon := panel.find_child("SourceInventoryIcon0", true, false) as TextureRect
	expect(tool_icon != null and tool_icon.position == Vector2(23, 146), "tool icon subtracts graph anchor from caller x29,y33 plus panel origin")

	panel.configure(_model("tools", [], _tools([1, 2], 9), "walking"))
	quantity_label = panel.find_child("SourceInventoryQuantity1", true, false) as Label
	expect(quantity_label != null and quantity_label.text == "9", "quantity nine is preserved")
	panel.configure(_model("tools", [], _tools([1], 10), "walking"))
	quantity_label = panel.find_child("SourceInventoryQuantity0", true, false) as Label
	expect(quantity_label != null and quantity_label.text == "10", "quantity ten is preserved")

	panel.configure(_model("tools", [], _tools([1]), "motorcycle"))
	expect_equal(panel.slot_source_id(14), 14, "motorcycle return is fixed source ID 14")
	expect_equal(panel.source_frames().vehicle.get("chunk"), 15, "motorcycle return uses Panel11 chunk 15")
	panel.configure(_model("tools", [], _tools([1]), "car"))
	expect_equal(panel.slot_source_id(14), 14, "car return is fixed source ID 14")
	expect_equal(panel.source_frames().vehicle.get("chunk"), 16, "car return uses Panel11 chunk 16")
	expect_equal(panel.source_geometry().get("vehicle_origin"), Vector2(325, 117), "vehicle origin is source exact")
	var vehicle_icon := panel.find_child("SourceInventoryIcon14", true, false) as TextureRect
	expect(vehicle_icon != null and vehicle_icon.position == Vector2(339, 247), "vehicle icon uses panel origin plus source-local position")
	selected_ids.clear()
	await _click(viewport, ORIGIN + STRIDE * Vector2(4, 2) + Vector2(1, 1))
	expect_equal(selected_ids, [14], "vehicle fixed slot emits source ID 14")
	panel.configure(_model("tools", [], _tools([1]), "engineering"))
	expect(panel.is_open() and panel.slot_source_id(14) == 0, "engineering vehicle is valid without ordinary source-14 slot")

	panel.configure(_model("tools", [], [], "walking"))
	selected_ids.clear()
	await _click(viewport, ORIGIN + Vector2(1, 1))
	expect_equal(selected_ids, [], "empty tools remain inert")
	panel.configure({})
	expect(not panel.is_open(), "invalid model is closed")
	expect(not panel.source_art_available(), "missing asset accessor cannot claim actual art")

	viewport.queue_free()
	await _settle()
	print("Source inventory panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _right_release(viewport: SubViewport, point: Vector2) -> void:
	viewport.push_input(_event(point, MOUSE_BUTTON_RIGHT, false), true)
	await _settle()
