extends "res://tests/source_date_panel.gd"

func _run() -> void:
	var pair := _new_panel()
	var viewport: SubViewport = pair.viewport
	var panel: Control = pair.panel
	var visuals := FakeVisuals.new()
	for edition in ["Game", "MultiverseJourney"]:
		await _present(panel, _model({"year":1998,"month":1,"day":31}, {"year":2026,"month":9,"day":11}, edition), visuals)
		_expect(panel.is_model_valid() and panel.source_art_available(), "render fixture is valid with source-shaped art")
		for action in ["month_down","month_up","year_down","year_up"]:
			await _present(panel, _model({"year":1998,"month":1,"day":31}, {"year":2026,"month":9,"day":11}, edition), visuals)
			var area: Rect2 = HITBOXES[action]
			viewport.push_input(_mouse_event(FRAME_ORIGIN + area.get_center(), MOUSE_BUTTON_LEFT, true), true)
			await _settle()
			var label: String = ("Month" if action.begins_with("month") else "Year") + ("Down" if action.ends_with("down") else "Up")
			var art: TextureRect = panel.find_child("SourceDate%sPressed" % label, true, false)
			_expect(art != null and int(art.get_meta("source_chunk")) == (12 if action.ends_with("down") else 13), "source arrow chunk follows direction for either field")
		for item in [["system","System",Vector2(38,196)],["cancel","Cancel",Vector2(101,196)],["accept","Accept",Vector2(163,196)]]:
			await _present(panel, _model({"year":1998,"month":1,"day":31}, {"year":2026,"month":9,"day":11}, edition), visuals)
			var area: Rect2 = HITBOXES[item[0]]
			viewport.push_input(_mouse_event(FRAME_ORIGIN + area.get_center(), MOUSE_BUTTON_LEFT, true), true)
			await _settle()
			var label: Label = panel.find_child("SourceDate%sLabel" % item[1], true, false)
			var art: TextureRect = panel.find_child("SourceDate%sPressed" % item[1], true, false)
			_expect(art != null and label.get_parent() == art.get_parent() and label.get_index() > art.get_index(), "pressed footer caption draws above the opaque pressed art")
			_expect(label.position + label.size / 2 == FRAME_ORIGIN + item[2] + Vector2.ONE, "pressed footer caption follows source one-pixel shift")
	for field in ["date","system_date"]:
		for key in ["year","month","day"]:
			var model := _model()
			model[field][key] = float(model[field][key])
			panel.set_view_model(model)
			_expect(not panel.is_model_valid(), "public date model rejects float fields even when whole")
		var extra := _model()
		extra[field]["extra"] = 0
		panel.set_view_model(extra)
		_expect(not panel.is_model_valid(), "date dictionaries have exactly three fields")
	var extra_root := _model()
	extra_root["extra"] = 0
	panel.set_view_model(extra_root)
	_expect(not panel.is_model_valid(), "source date model has exactly the three declared fields")
	viewport.queue_free()
	await _settle()
	print("Source date rendering checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
