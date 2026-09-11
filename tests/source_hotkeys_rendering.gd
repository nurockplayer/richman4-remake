extends "res://tests/source_hotkeys_panel.gd"

func _run() -> void:
	var pair := _new_viewport()
	var viewport: SubViewport = pair.viewport
	var panel: Control = pair.panel
	var visuals := FakeVisuals.new()
	var bindings: Array = load(PLATFORM_PATH).new().defaults()
	for edition in ["Game", "MultiverseJourney"]:
		panel.set_visual_accessor(visuals)
		panel.set_view_model({"edition":edition,"bindings":bindings})
		await _settle()
		_expect(panel.is_model_valid() and panel.source_art_available(), "render fixture has valid source-shaped art")
		for item in [["Reset",RESET,Vector2(52,296)],["Cancel",CANCEL,Vector2(165,296)],["Accept",ACCEPT,Vector2(278,296)]]:
			panel.close_hotkeys()
			panel.set_view_model({"edition":edition,"bindings":bindings})
			await _settle()
			var area: Rect2 = item[1]
			viewport.push_input(mouse_event(FRAME_ORIGIN+area.get_center()), true)
			await _settle()
			var label: Label = panel.find_child("SourceHotkeys%sLabel" % item[0],true,false)
			_expect(label.position + label.size/2 == FRAME_ORIGIN+item[2]+Vector2.ONE,"source pressed footer caption shifts one pixel within the depressed button")
			var effect: Control = panel.find_child("SourceHotkeysPressed",true,false)
			_expect(effect != null and effect.position == FRAME_ORIGIN+area.position and effect.size == area.size,"each footer gets the source rectangle depression")
		panel.close_hotkeys()
		panel.set_view_model({"edition":edition,"bindings":bindings})
		await _settle()
		var title: Label = panel.title_labels[8]
		var original_position: Vector2 = title.position
		viewport.push_input(mouse_event(FRAME_ORIGIN+Vector2(132,161)),true)
		await _settle()
		_expect(panel.title_labels[8].position == original_position,"pressing a key cell leaves the title outside the source pressed rectangle stationary")
	viewport.queue_free()
	await _settle()
	print("Source hotkeys rendering checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func mouse_event(at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event
