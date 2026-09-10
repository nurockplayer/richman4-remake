extends SceneTree

const PanelScript = preload("res://game/ui/source_setup_panel.gd")
var checks := 0
var failures := 0

class FakeVisuals extends RefCounted:
	var calls: Array = []
	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		calls.append([edition, archive, resource, chunk])
		var width := 72
		var height := 72
		if archive == "jump":
			if resource < (4 if edition == "Game" else 8):
				width = 640
				height = 480
			elif resource == (4 if edition == "Game" else 8):
				width = 440 if chunk % 20 == 0 else 192
				height = 155 if chunk % 20 == 0 else 461
		return {"logical": {"width": width, "height": height, "anchor_x": 36, "anchor_y": 72}}
	func texture(frame: Dictionary) -> Texture2D:
		if frame.is_empty(): return null
		var image := Image.create(int(frame.logical.width), int(frame.logical.height), false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		return ImageTexture.create_from_image(image)
	func scene_for(_definition: Dictionary) -> Dictionary: return {}
	func character(_edition: String, _id: int, _frame: int) -> Dictionary: return {}


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func click(viewport: SubViewport, at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame


func humans(panel: Control) -> Array:
	return panel.collect_options().get("options", {}).get("human_character_ids", [])


func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	root.add_child(viewport)
	var panel: Control = PanelScript.new()
	var visuals := FakeVisuals.new()
	panel.set("_visuals", visuals)
	viewport.add_child(panel)
	await process_frame
	var catalog: Array = []
	for edition in ["Game", "MultiverseJourney"]:
		for number in range(1, 5 if edition == "Game" else 9):
			catalog.append({"id": "%s:%d" % [edition, number], "source": {"edition":edition,"map_number":number}})
	panel.set_catalog(catalog, catalog[0], {"player_count":4,"character_ids":[0,1,2,3],"human_flags":[true,false,false,false]})
	panel.show()
	await process_frame
	expect(humans(panel) == [0], "only initial humans are selected")
	expect(panel.find_child("PlayerSlots", true, false) == null, "no invented per-player slots")
	expect(panel.find_child("MapStage", true, false) == null and panel.find_child("MapEdition_MJ", true, false) == null, "stage remains upstream, without hidden setup controls")
	expect(panel.get_node("SourcePortraitFrame").position == Vector2(4,10), "top frame source origin")
	expect(panel.get_node("SourceSettingsFrame").position == Vector2(445,10), "side frame source origin")
	expect(not panel.get_node("SourceMapFallback").visible, "raw map hides fallback")
	expect(not panel.get_node("MapChoiceLabel_0").visible, "baked labels have no overlaid duplicate")
	await click(viewport, Vector2(8 + 4 * 72 + 36, 15 + 36))
	expect(humans(panel) == [0,4], "portrait click appends a human in order")
	await click(viewport, Vector2(8 + 36, 15 + 36))
	expect(humans(panel) == [4], "click selected portrait removes and compacts")
	await click(viewport, Vector2(8 + 36, 15 + 72 + 36))
	expect(humans(panel) == [4,6], "second-row hit grid selects correct character")
	visuals.calls.clear()
	var vehicle: OptionButton = panel.get_node("InitialVehicle")
	vehicle.select(2)
	vehicle.item_selected.emit(2)
	expect(visuals.calls.has(["Game","jump",19,0]) and visuals.calls.has(["Game","jump",25,0]), "vehicle event reloads both selected human previews")
	await click(viewport, Vector2(500,110))
	expect(panel.get_map_background_resource() == 2, "source map row hit changes background")
	var result: Dictionary = panel.collect_options()
	expect(bool(result.get("ok", false)), "ordered human setup is valid")
	expect(panel.has_method("resolve_players"), "confirmation has deterministic unique AI fill")
	if panel.has_method("resolve_players"):
		var first: Dictionary = panel.call("resolve_players", result.options, 4, 115)
		var again: Dictionary = panel.call("resolve_players", result.options, 4, 115)
		expect(first == again, "same seed resolves the same AI choices")
		expect(first.get("character_ids", []).slice(0,2) == [4,6] and first.get("human_flags", []) == [true,true,false,false], "confirmation preserves human order before AI")
		var unique: Dictionary = {}
		for value in first.get("character_ids", []): unique[value] = true
		expect(unique.size() == 4, "AI fills unique unused portraits")
		expect(not first.has("human_character_ids") and not first.has("player_count"), "UI selection fields never enter strict factory options")
		var alternatives: Dictionary = {}
		for seed_value in range(16):
			alternatives[JSON.stringify(panel.call("resolve_players", result.options, 4, seed_value).get("character_ids", []))] = true
		expect(alternatives.size() > 1, "different seeds can select different AI")
	var count: OptionButton = panel.get_node("PlayerCount")
	count.select(0)
	count.item_selected.emit(0)
	await click(viewport, Vector2(8 + 5 * 72 + 36, 15 + 36))
	expect(humans(panel) == [4,6], "cannot select more humans than total players")
	await click(viewport, Vector2(8 + 4 * 72 + 36, 15 + 36))
	await click(viewport, Vector2(8 + 36, 15 + 72 + 36))
	expect(not bool(panel.collect_options().get("ok", false)), "zero humans cannot start")
	panel.set_catalog(catalog, catalog[8], {"player_count":4,"character_ids":[0,1,2,3],"human_flags":[true,false,false,false]})
	expect(panel.get_stage() == 1 and panel.get_map_background_resource() == 4, "MJ stage is selected by upstream definition")
	expect(panel.get_setup_atlas_offset() == 21, "MJ stage one selects its own source atlas")
	panel.queue_free()
	viewport.queue_free()
	await process_frame
	print("Source setup interaction checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
