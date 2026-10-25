extends "res://tests/source_options_panel.gd"

func _run() -> void:
	var pair := _new_panel()
	var viewport: SubViewport = pair.viewport
	var panel: Control = pair.panel
	var visuals := FakeVisuals.new()
	for edition in ["Game", "MultiverseJourney"]:
		for mode in ["title", "game"]:
			await _present(panel, _model(mode, edition), visuals)
			_expect(panel.is_model_valid() and panel.source_art_available(), "rendering fixture has a valid model and complete source-shaped atlas")
			var plate: TextureRect = panel.find_child("SourceOptionsCommandPlate", true, false)
			_expect(plate.position == FRAME_ORIGIN + Vector2(168,2), "source entry composites command plate at local168,2")
			for index in range(3):
				var label: Label = panel.find_child("SourceOptionsCommand%d" % index, true, false)
				_expect(label.get_theme_font_size("font_size") == 20, "source command label retains entry font20")
				_expect(label.position + label.size/2 == FRAME_ORIGIN + Vector2(276,[33,87,138][index]), "command text uses source plate-relative table centers")
			for title in ["日、月曆", "縮小地圖", "組合畫面"]:
				var matching := 0
				for label in panel.find_children("*", "Label", true, false):
					if label.text == title: matching += 1
				_expect(matching == 1, "each source view choice is drawn once")
			for index in range(8):
				var label: Label = panel.find_child("SourceOptionsTrackLabel%d" % index, true, false)
				_expect(label.position.x == FRAME_ORIGIN.x + 26 and is_equal_approx(label.position.y + label.size.y/2, FRAME_ORIGIN.y+233+15*index), "source track label left/center anchors follow the draw call")
				_expect(label.get_theme_color("font_color") == Color("#f0f0f0"), "source music names use light text")
			_expect(panel.find_child("SourceOptionsCancelArt", true, false) == null and panel.find_child("SourceOptionsAcceptArt", true, false) == null, "idle footer uses the buttons already present in chunk0")
			_expect(panel.find_child("SourceOptionsCancelLabel", true, false).text == "取 消" and panel.find_child("SourceOptionsAcceptLabel", true, false).text == "確 定", "source footer caption spacing is retained")
			for kind in ["Cancel", "Accept"]:
				var point := Vector2(204,324) if kind == "Cancel" else Vector2(276,324)
				viewport.push_input(_mouse_event(FRAME_ORIGIN+point,MOUSE_BUTTON_LEFT,true),true)
				await _settle()
				var art: TextureRect = panel.find_child("SourceOptions%sPressed" % kind,true,false)
				_expect(art != null and art.get_meta("source_chunk") == (3 if kind == "Cancel" else 4), "footer press uses Data3chunk3/4 rather than date arrow7/8")
				await _present(panel, _model(mode,edition), visuals)
	_expect(panel.has_method("set_current_track"), "host can report the actually playing track for source highlight")
	if panel.has_method("set_current_track"):
		panel.set_current_track(3)
		await _settle()
		var selected := panel.find_child("SourceOptionsTrackHighlight",true,false)
		_expect(selected != null and selected.position == FRAME_ORIGIN+Vector2(18,271) and selected.size == Vector2(159,14), "actual track4 highlight uses the source row rectangle")
		panel.set_current_track(-1)
		await _settle()
		_expect(panel.find_child("SourceOptionsTrackHighlight",true,false) == null, "unknown current music does not invent a highlighted track")
	viewport.queue_free()
	await _settle()
	print("Source options rendering checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
