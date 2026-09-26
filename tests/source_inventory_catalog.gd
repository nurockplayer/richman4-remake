extends "res://tests/source_inventory_test_helper.gd"

func run() -> void:
	var catalog := OS.get_environment("RICHMAN4_MAP_CATALOG")
	if catalog.is_empty() or FileAccess.get_sha256(catalog) != "ac6a07666ceb9d8b4f1be8a6df3d486a3ffbb1f643cd383fd58daf81c5449565":
		print("PRECONDITION_UNMET actual installed catalog identity required")
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var ui: Variant = make_ui(viewport)
	await settle()
	ui.set_process(false)
	if not ui._map_catalog_complete or ui._map_catalog.size() != 12:
		print("PRECONDITION_UNMET incomplete catalog")
		quit(2)
		return
	for edition in ["Game", "MultiverseJourney"]:
		var definition := find_map(ui, edition, 1 if edition == "Game" else 7)
		var requested_map_number := 1 if edition == "Game" else 7
		var requested_source: Variant = definition.get("source", {})
		check(not definition.is_empty(), "requested catalog definition exists before factory: %s/%d" % [edition, requested_map_number])
		check(requested_source is Dictionary and str(requested_source.get("edition", "")) == edition and int(requested_source.get("map_number", -1)) == requested_map_number, "requested definition source metadata matches %s/%d before factory" % [edition, requested_map_number])
		if definition.is_empty() or not (requested_source is Dictionary):
			continue
		check(ui._new_game(160,4,definition,ui._default_setup_options(4,definition)), "actual catalog-derived game starts: " + edition)
		var active_source: Variant = ui._active_map_definition.get("source", {})
		check(active_source is Dictionary and str(active_source.get("edition", "")) == edition and int(active_source.get("map_number", -1)) == requested_map_number, "factory activates requested catalog map %s/%d" % [edition, requested_map_number])
		check(ui._has_original_inventory(), "actual catalogue enables source inventory")
		await settle()
		for mode in ["cards", "tools"]:
			var button: Button = ui.source_shell.toolbar_buttons[mode]
			check(not button.disabled, "ordinary " + mode + " toolbar is reachable: " + edition)
			var before: String = ui.game_state.to_json()
			press(viewport, button)
			await settle()
			var panel: Node = ui.source_shell.find_child("SourceInventoryPanel",true,false)
			var opened := panel != null and panel.has_method("is_open") and bool(panel.call("is_open"))
			check(opened, "ordinary toolbar opens source held list: " + mode + "/" + edition)
			check(not ui.cards_popup.visible, "ordinary source list replaces combined generic inventory")
			check(ui.game_state.to_json() == before, "list entry preserves core/RNG/supply")
			if opened:
				check(str(panel.call("view_model").get("mode", "")) == mode, "cards and tools are distinct held lists")
				var cancel := InputEventMouseButton.new()
				cancel.button_index = MOUSE_BUTTON_RIGHT
				cancel.pressed = false
				cancel.position = Vector2(40,160)
				viewport.push_input(cancel)
				await settle()
				check(not bool(panel.call("is_open")), "right release returns to board")
				check(ui.game_state.to_json() == before, "list cancellation preserves inventory")
	viewport.queue_free()
	await settle()
	print("Source inventory actual catalog checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
