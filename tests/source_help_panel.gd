extends SceneTree

## Focused hermetic checks for the Issue #139 source help presenter.
##
## Missing implementation is availability RED. Worker could not commit its
## initial snapshot; parent preserves the tests and reports that chronology.
## The suite never instantiates GameState, MainUI, persistence, audio, RNG or
## any owner save/IO.  All model text below is synthetic test-only data.

var checks := 0
var failures := 0
var _closed_count := 0

const EXPECTED_TOPIC_COUNTS := [1, 6, 12, 3, 16, 18, 30, 13]
const EXPECTED_SECTION_LABELS := ["SEC0", "SEC1", "SEC2", "SEC3", "SEC4", "SEC5", "SEC6", "SEC7"]
const FRAME_ORIGIN := Vector2(120.0, 40.0)


class FakeVisuals extends RefCounted:
	var calls: Array = []
	var texture_calls: Array = []
	var physical_scale := 2
	var blocked_editions: Array = []
	var _cache: Dictionary = {}

	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		calls.append([edition, archive, resource, chunk])
		if edition in blocked_editions:
			return {}
		var size := _logical(chunk)
		# JSON integers arrive as integral floats; exercise that metadata path.
		return {
			"edition": edition,
			"archive": archive,
			"resource": resource,
			"chunk": chunk,
			"logical": {"width": float(size.x), "height": float(size.y), "anchor_x": 0.0, "anchor_y": 0.0},
		}

	func texture(frame: Dictionary) -> Texture2D:
		texture_calls.append(frame.duplicate(true))
		var logical: Dictionary = frame.get("logical", {})
		var key := "%s:%d:%s" % [str(frame.get("edition", "")), int(frame.get("chunk", 0)), str(logical)]
		if _cache.has(key):
			return _cache[key]
		var width := maxi(1, int(round(float(logical.get("width", 1.0)))) * physical_scale)
		var height := maxi(1, int(round(float(logical.get("height", 1.0)))) * physical_scale)
		var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.1 + 0.05 * float(int(frame.get("chunk", 0))), 0.4, 0.55, 1.0))
		var result := ImageTexture.create_from_image(image)
		_cache[key] = result
		return result

	func chunks_called() -> Array:
		var result: Array = []
		for call in calls:
			result.append(int(call[3]))
		return result

	func _logical(chunk: int) -> Vector2:
		match chunk:
			0: return Vector2(400, 400)
			1: return Vector2(66, 33)
			2: return Vector2(85, 33)
			3: return Vector2(87, 33)
			4: return Vector2(22, 18)
			5: return Vector2(22, 15)
			6: return Vector2(20, 18)
			7: return Vector2(18, 14)
			8: return Vector2(23, 32)
			9: return Vector2(23, 35)
			10: return Vector2(23, 32)
			11: return Vector2(23, 30)
		return Vector2(1, 1)


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


func _present(panel: Control, model: Dictionary) -> void:
	# Force replacement semantics: an unavailable view first, then the model, so
	# a content-identical model built for an earlier test cannot look like a
	# same-model refresh that preserves browsing state.
	panel.call("set_view_model", {})
	panel.call("set_view_model", model)
	await _settle()


func _run() -> void:
	var source_path := "res://game/ui/source_help_panel.gd"
	if not FileAccess.file_exists(source_path):
		checks += 1
		failures += 1
		print("FAIL: source help presenter is absent (availability RED, not a behaviour failure)")
		print("Source help panel RED: implementation absent; checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var source_script: Variant = load(source_path)
	if source_script == null:
		checks += 1
		failures += 1
		print("FAIL: source help presenter script could not load (availability RED)")
		quit(1)
		return
	var panel_value: Variant = source_script.new()
	if not panel_value is Control:
		checks += 1
		failures += 1
		print("FAIL: source help presenter did not instantiate as a Control")
		quit(1)
		return
	var panel: Control = panel_value
	root.add_child(panel)
	panel.connect("closed", Callable(self, "_on_closed"))
	await process_frame

	if _check_public_api(panel):
		await _test_geometry(panel)
		await _test_section_and_topic_content(panel)
		await _test_topic_paging_and_selected_slot(panel)
		await _test_body_pages(panel)
		await _test_invalid_models(panel)
		await _test_deep_copies(panel)
		await _test_edition_resolution(panel)
		await _test_native_input_ordering(source_script)

	panel.queue_free()
	await process_frame
	print("Source help panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _on_closed() -> void:
	_closed_count += 1


func _check_public_api(panel: Control) -> bool:
	var methods := [
		"set_view_model",
		"set_visuals",
		"view_model",
		"is_model_valid",
		"source_art_available",
		"source_art_status",
		"source_frames",
		"source_geometry",
	]
	var ok := true
	for method in methods:
		var present := panel.has_method(method)
		expect(present, "help presenter exposes " + method)
		ok = ok and present
	var signal_present := panel.has_signal("closed")
	expect(signal_present, "help presenter exposes the closed signal")
	expect(panel.size == Vector2(640, 480), "help presenter keeps the 640x480 logical canvas")
	expect(panel.mouse_filter == Control.MOUSE_FILTER_STOP, "help presenter consumes modal mouse input")
	return ok and signal_present


func _build_model(edition := "Game") -> Dictionary:
	var sections: Array = []
	var resource_index := 1
	for section_id in range(8):
		var topics: Array = []
		for topic_index in range(int(EXPECTED_TOPIC_COUNTS[section_id])):
			topics.append({
				"resource_index": resource_index,
				"title": "S%dT%d" % [section_id, topic_index],
				"payload_sha256": "b".repeat(64),
				"pages": _pages_for(section_id, topic_index),
			})
			resource_index += 1
		sections.append({"id": section_id, "label": EXPECTED_SECTION_LABELS[section_id], "topics": topics})
	return {
		"schema": "richman4.help-edition/v1",
		"edition": edition,
		"archive_sha256": "a".repeat(64),
		"sections": sections,
	}


func _pages_for(section_id: int, topic_index: int) -> Array:
	if section_id == 0 and topic_index == 0:
		return [_lines("P0", 14), _lines("P1", 2), _lines("P2", 5)]
	if section_id == 1 and topic_index == 0:
		return [_lines("A", 14), _lines("B", 14)]
	return [_lines("L", 2)]


func _lines(prefix: String, count: int) -> Array:
	var result: Array = []
	for index in range(count):
		result.append("%s%02d" % [prefix, index])
	return result


func _find(panel: Node, node_name: String) -> Node:
	return panel.find_child(node_name, true, false)


func _body_lines(panel: Node) -> Array:
	var lines: Array = []
	for index in range(14):
		var label := _find(panel, "SourceHelpBodyLine%d" % index) as Label
		if label == null:
			break
		lines.append(label)
	return lines


func _rendered_rows(panel: Node) -> Array:
	var rows: Array = []
	for row in range(8):
		var art := _find(panel, "SourceHelpTopicRow%d" % row) as TextureRect
		if art == null:
			break
		var label := _find(panel, "SourceHelpTopicLabel%d" % row) as Label
		rows.append({
			"row": row,
			"art": art,
			"label": label,
			"selected": int(art.get_meta("source_chunk", -1)) == 3,
		})
	return rows


func _test_geometry(panel: Control) -> void:
	var visuals := FakeVisuals.new()
	panel.call("set_visuals", visuals)
	panel.call("set_view_model", _build_model())
	await _settle()
	expect(bool(panel.call("is_model_valid")), "valid synthetic Game model is accepted")

	var geometry: Dictionary = panel.call("source_geometry")
	expect_equal(geometry.get("canvas"), Vector2(640, 480), "geometry keeps the 640x480 logical canvas")
	expect_equal(geometry.get("frame_origin"), Vector2(120, 40), "geometry centers the 400x400 frame at (120,40)")
	expect_equal(geometry.get("frame_size"), Vector2(400, 400), "geometry reports the source frame size")
	var section: Dictionary = geometry.get("section", {})
	expect_equal(section.get("origin"), Vector2(26, 58), "section art origin is local (26,58)")
	expect_equal(float(section.get("step", 0.0)), 36.0, "section rows step by 36")
	expect_equal(section.get("size"), Vector2(66, 33), "section art stays 66x33")
	expect_equal(section.get("label_center"), Vector2(59, 73), "section label center is local (59,73)")
	expect_equal(int(section.get("label_font_size", 0)), 12, "section labels keep source font 12")
	var topics: Dictionary = geometry.get("topic_list", {})
	expect_equal(topics.get("title_center"), Vector2(140, 57), "topic list title is local (140,57)")
	expect_equal(topics.get("origin"), Vector2(108, 78), "topic rows start at local (108,78)")
	expect_equal(float(topics.get("step", 0.0)), 34.0, "topic rows step by 34")
	expect_equal(topics.get("unselected_size"), Vector2(85, 33), "unselected topic art is 85x33")
	expect_equal(topics.get("selected_size"), Vector2(87, 33), "selected topic art is 87x33")
	expect_equal(int(topics.get("visible_rows", 0)), 8, "only eight topic rows are visible")
	expect_equal(topics.get("up_hit"), Rect2(170, 43, 22, 15), "topic list up hitbox matches the source")
	expect_equal(topics.get("down_hit"), Rect2(170, 59, 22, 15), "topic list down hitbox matches the source")
	var body: Dictionary = geometry.get("body", {})
	expect_equal(body.get("header_center"), Vector2(270, 63), "body header center is local (270,63)")
	expect_equal(body.get("line_origin"), Vector2(232, 90), "body lines start at local (232,90)")
	expect_equal(float(body.get("line_step", 0.0)), 18.0, "body lines step by 18")
	expect_equal(int(body.get("max_lines", 0)), 14, "body pages cap at fourteen lines")
	expect_equal(body.get("prev_hit"), Rect2(322, 48, 23, 32), "body previous hitbox matches the source")
	expect_equal(body.get("next_hit"), Rect2(343, 48, 23, 32), "body next hitbox matches the source")

	var frame_art := _find(panel, "SourceHelpFrame") as TextureRect
	expect(frame_art != null, "source frame chunk0 is drawn")
	if frame_art != null:
		expect_equal(frame_art.position, FRAME_ORIGIN, "frame art uses the logical frame origin")
		expect_equal(frame_art.size, Vector2(400, 400), "frame art uses logical size, not the 2x texture size")
		expect(frame_art.texture != null and frame_art.texture.get_size() == Vector2(800, 800), "2x frame texture is accepted")
	var backdrop := _find(panel, "SourceHelpFrameBackdrop") as ColorRect
	expect(backdrop != null and backdrop.visible, "the frame region keeps an opaque source backdrop")
	if backdrop != null:
		expect_equal(backdrop.position, FRAME_ORIGIN, "frame backdrop is anchored on the source frame")
		expect_equal(backdrop.size, Vector2(400, 400), "frame backdrop never covers the board outside the frame")

	expect(bool(panel.call("source_art_available")), "a complete resolver reports source art available")
	var frames: Dictionary = panel.call("source_frames")
	expect(frames.size() == 12, "all twelve source chunks are reported (actual=%d)" % frames.size())
	var status: Dictionary = panel.call("source_art_status")
	expect(status.size() == 12, "source art status covers all twelve chunks")
	for chunk in range(12):
		expect(visuals.chunks_called().has(chunk), "resolver was asked for help chunk %d" % chunk)

	var section_art := _find(panel, "SourceHelpSectionArt") as TextureRect
	expect(section_art != null, "the selected section overlay is drawn")
	if section_art != null:
		expect_equal(section_art.position, FRAME_ORIGIN + Vector2(26, 58), "selected section art sits on section row 0")
		expect_equal(section_art.size, Vector2(66, 33), "selected section art keeps logical size")
		expect_equal(int(section_art.get_meta("source_chunk", -1)), 1, "selected section uses chunk1")

	panel.call("select_section", 2)
	expect(_find(panel, "SourceHelpTopicUpArt") != null, "topic list arrows are drawn for an 8+ topic section")
	var game_calls := 0
	for call in visuals.calls:
		if call[0] == "Game" and call[1] == "help" and int(call[2]) == 0:
			game_calls += 1
	expect(game_calls >= 12, "Game help art resolves through the help archive/resource 0")


func _test_section_and_topic_content(panel: Control) -> void:
	panel.call("set_visuals", FakeVisuals.new())
	var model := _build_model()
	await _present(panel, model)
	var sections: Array = model["sections"]

	for section_id in range(8):
		expect(bool(panel.call("select_section", section_id)), "section %d can be selected" % section_id)
		var header := _find(panel, "SourceHelpSectionTitle") as Label
		expect(header != null and header.text == EXPECTED_SECTION_LABELS[section_id], "topic list title follows section %d" % section_id)
		for label_index in range(8):
			var section_label := _find(panel, "SourceHelpSectionLabel%d" % label_index) as Label
			expect(section_label != null, "section list draws label %d" % label_index)
			if section_label != null:
				expect_equal(section_label.text, EXPECTED_SECTION_LABELS[label_index], "section label %d keeps its own text" % label_index)
				expect(abs(section_label.position.x + section_label.size.x / 2.0 - (FRAME_ORIGIN.x + 59.0)) < 0.6, "section label %d keeps the source x center" % label_index)
				expect(abs(section_label.position.y + section_label.size.y / 2.0 - (FRAME_ORIGIN.y + 73.0 + 36.0 * label_index)) < 0.6, "section label %d keeps the source y center" % label_index)

		var topics: Array = sections[section_id]["topics"]
		var covered: Dictionary = {}
		while true:
			var offset := int(panel.call("topic_page_offset"))
			var rows := _rendered_rows(panel)
			expect(rows.size() == mini(8, topics.size() - offset), "section %d offset %d renders the expected visible rows" % [section_id, offset])
			for row_index in range(rows.size()):
				var topic_index := offset + row_index
				covered[topic_index] = true
				# Selecting a topic rebuilds labels; reacquire each row after it.
				var row_label: Label = _rendered_rows(panel)[row_index]["label"]
				expect(row_label != null and row_label.text == str(topics[topic_index]["title"]), "section %d topic %d renders its own title" % [section_id, topic_index])
				expect(bool(panel.call("select_topic", topic_index)), "section %d topic %d can be selected" % [section_id, topic_index])
				var selected_rows := _rendered_rows(panel)
				var highlighted := -1
				for check_row in range(selected_rows.size()):
					if bool(selected_rows[check_row]["selected"]):
						highlighted = check_row
				expect_equal(highlighted, row_index, "selecting section %d topic %d highlights its visible row" % [section_id, topic_index])
				var body_header := _find(panel, "SourceHelpBodyHeader") as Label
				expect(body_header != null and body_header.text == str(topics[topic_index]["title"]), "body header follows section %d topic %d" % [section_id, topic_index])
			if not bool(panel.call("page_topics", 1)):
				break
		expect(covered.size() == topics.size(), "section %d exposes every topic while paging (actual=%d)" % [section_id, covered.size()])

		# Refresh the same model: browsing state must survive an identical refresh.
	panel.call("select_section", 7)
	panel.call("page_topics", 1)
	var kept_offset := int(panel.call("topic_page_offset"))
	var kept_topic := int(panel.call("selected_topic"))
	panel.call("set_view_model", _build_model())
	await _settle()
	expect_equal(int(panel.call("topic_page_offset")), kept_offset, "an identical model refresh keeps the per-section topic offset")
	expect_equal(int(panel.call("selected_topic")), kept_topic, "an identical model refresh keeps the selected topic")
	expect_equal(int(panel.call("selected_section")), 7, "an identical model refresh keeps the selected section")
	panel.call("set_view_model", _build_model("MultiverseJourney"))
	await _settle()
	expect_equal(int(panel.call("selected_section")), 0, "a replacement model resets the selected section")
	expect_equal(int(panel.call("selected_topic")), 0, "a replacement model resets the selected topic")
	expect_equal(int(panel.call("selected_body_page")), 0, "a replacement model resets the body page")


func _test_topic_paging_and_selected_slot(panel: Control) -> void:
	panel.call("set_visuals", FakeVisuals.new())
	var model := _build_model()
	await _present(panel, model)
	var sections: Array = model["sections"]

	# Section 7 has thirteen topics: the last page shift is partial (5, not 8).
	panel.call("select_section", 7)
	expect_equal(int(panel.call("topic_page_offset")), 0, "a fresh section starts at topic offset 0")
	expect(bool(panel.call("select_topic", 4)), "topic 4 can be selected")
	var rows := _rendered_rows(panel)
	expect(bool(rows[4]["selected"]), "selected topic 4 keeps visible slot 4 before paging")
	expect(bool(panel.call("page_topics", 1)), "down paging moves the topic list")
	expect_equal(int(panel.call("topic_page_offset")), 5, "thirteen topics page to the partial last offset 5")
	expect_equal(int(panel.call("selected_topic")), 9, "paging moves the selection by the same delta")
	rows = _rendered_rows(panel)
	expect(rows.size() == 8, "the partial last page still shows eight rows")
	expect(bool(rows[4]["selected"]), "paging preserves the selected visible slot")
	expect_equal((rows[0]["label"] as Label).text, str((sections[7]["topics"] as Array)[5]["title"]), "the last page starts on the correct topic")
	expect(not bool(panel.call("page_topics", 1)), "paging past the last page is a no-op")
	expect_equal(int(panel.call("topic_page_offset")), 5, "a no-op page keeps the offset")
	expect(bool(panel.call("page_topics", -1)), "up paging returns to the first page")
	expect_equal(int(panel.call("topic_page_offset")), 0, "up paging restores offset 0")
	expect_equal(int(panel.call("selected_topic")), 4, "up paging restores the selected slot")
	rows = _rendered_rows(panel)
	expect(bool(rows[4]["selected"]), "up paging keeps the selection in its visible slot")

	# Section 2 has twelve topics: the second page shifts by four.
	panel.call("select_section", 2)
	expect(bool(panel.call("select_topic", 3)), "topic 3 of section 2 can be selected")
	expect(bool(panel.call("page_topics", 1)), "section 2 pages down")
	expect_equal(int(panel.call("topic_page_offset")), 4, "twelve topics page to the partial offset 4")
	expect_equal(int(panel.call("selected_topic")), 7, "section 2 selection moves by the same delta")
	rows = _rendered_rows(panel)
	expect(rows.size() == 8, "section 2 last page fills the visible window")
	expect(bool(rows[3]["selected"]), "section 2 keeps the selected visible slot on the last page")
	expect(not bool(panel.call("page_topics", 1)), "section 2 last page cannot page further")

	# Sections with eight or fewer topics expose no list arrows.
	panel.call("select_section", 1)
	await _settle()
	expect(_find(panel, "SourceHelpTopicUpArt") == null, "sections with <=8 topics hide the list up arrow")
	expect(_find(panel, "SourceHelpTopicDownArt") == null, "sections with <=8 topics hide the list down arrow")
	expect(not bool(panel.call("page_topics", 1)), "sections with <=8 topics cannot page the list")


func _test_body_pages(panel: Control) -> void:
	panel.call("set_visuals", FakeVisuals.new())
	var model := _build_model()
	await _present(panel, model)
	panel.call("select_section", 0)
	panel.call("select_topic", 0)
	await _settle()

	var pages: Array = model["sections"][0]["topics"][0]["pages"]
	expect_equal(int(panel.call("selected_body_page")), 0, "a topic starts on body page 0")
	var lines := _body_lines(panel)
	expect(lines.size() == 14, "a fourteen line page renders fourteen source lines (actual=%d)" % lines.size())
	for index in range(lines.size()):
		expect_equal((lines[index] as Label).text, str(pages[0][index]), "body line %d keeps its source text" % index)
		expect(abs((lines[index] as Label).position.x - (FRAME_ORIGIN.x + 232.0)) < 0.6, "body line %d keeps the source x origin" % index)
		expect(abs((lines[index] as Label).position.y - (FRAME_ORIGIN.y + 90.0 + 18.0 * index)) < 0.6, "body line %d keeps the source top y" % index)
	expect(not bool(panel.call("page_body", -1)), "the first body page cannot page up")
	expect(bool(panel.call("page_body", 1)), "the body pages down")
	expect_equal(int(panel.call("selected_body_page")), 1, "body page index follows paging")
	lines = _body_lines(panel)
	expect(lines.size() == 2, "a two line page renders two source lines")
	expect_equal((lines[0] as Label).text, str(pages[1][0]), "body page 1 keeps its first line")
	expect(bool(panel.call("page_body", 1)), "the body pages to the final page")
	expect_equal(_body_lines(panel).size(), 5, "the final body page renders its own line count")
	expect(not bool(panel.call("page_body", 1)), "the last body page cannot page down")

	panel.call("select_section", 1)
	panel.call("select_topic", 1)
	await _settle()
	expect(_find(panel, "SourceHelpBodyPrevArt") == null, "single page topics hide the body previous arrow")
	expect(_find(panel, "SourceHelpBodyNextArt") == null, "single page topics hide the body next arrow")
	expect(not bool(panel.call("page_body", 1)), "single page topics cannot page the body")
	expect(not bool(panel.call("page_body", -1)), "single page topics cannot page the body backwards")


func _test_invalid_models(panel: Control) -> void:
	var visuals := FakeVisuals.new()
	panel.call("set_visuals", visuals)
	var cases := {
		"missing sections": func(model: Dictionary) -> void: model["sections"] = (model["sections"] as Array).slice(0, 7),
		"wrong section id": func(model: Dictionary) -> void: model["sections"][3]["id"] = 9,
		"extra topic": func(model: Dictionary) -> void: model["sections"][0]["topics"].append({"resource_index": 100, "title": "X", "pages": [["a"]]}),
		"missing topic": func(model: Dictionary) -> void: model["sections"][2]["topics"].pop_back(),
		"broken resource index": func(model: Dictionary) -> void: model["sections"][1]["topics"][2]["resource_index"] = 9,
		"float resource index": func(model: Dictionary) -> void: model["sections"][1]["topics"][0]["resource_index"] = 2.5,
		"boolean resource index": func(model: Dictionary) -> void: model["sections"][1]["topics"][0]["resource_index"] = true,
		"unknown edition": func(model: Dictionary) -> void: model["edition"] = "UnknownEdition",
		"wrong schema": func(model: Dictionary) -> void: model["schema"] = "richman4.help-edition/v2",
		"empty page": func(model: Dictionary) -> void: model["sections"][0]["topics"][0]["pages"] = [[]],
		"long page": func(model: Dictionary) -> void: model["sections"][0]["topics"][0]["pages"] = [_lines("X", 15)],
		"non string line": func(model: Dictionary) -> void: model["sections"][0]["topics"][0]["pages"] = [[1, 2]],
		"pages not array": func(model: Dictionary) -> void: model["sections"][0]["topics"][0]["pages"] = "nope",
		"missing title": func(model: Dictionary) -> void: model["sections"][0]["topics"][0]["title"] = 7,
	}
	for case_name in cases:
		var model := _build_model()
		(cases[case_name] as Callable).call(model)
		panel.call("set_view_model", model)
		await _settle()
		expect(not bool(panel.call("is_model_valid")), "invalid model rejected: %s" % case_name)
		expect(not bool(panel.call("source_art_available")), "invalid model cannot claim source art: %s" % case_name)
		var unavailable := _find(panel, "SourceHelpUnavailable") as Label
		expect(unavailable != null and unavailable.visible and not unavailable.text.is_empty(), "invalid model shows a coherent unavailable view: %s" % case_name)
		expect(_find(panel, "SourceHelpBodyLine0") == null, "invalid model never renders fake manual body text: %s" % case_name)

	var calls_before := visuals.calls.size()
	panel.call("set_view_model", {"edition": "Game"})
	await _settle()
	expect(not bool(panel.call("is_model_valid")), "an empty model is rejected")
	expect(visuals.calls.size() == calls_before, "an invalid model never touches the resolver")


func _test_deep_copies(panel: Control) -> void:
	var model := _build_model()
	var before := model.duplicate(true)
	panel.call("set_visuals", FakeVisuals.new())
	await _present(panel, model)
	expect(model == before, "set_view_model does not mutate the host model")

	var exposed: Dictionary = panel.call("view_model")
	exposed["sections"][0]["topics"][0]["pages"][0][0] = "外部修改"
	model["sections"][0]["topics"][0]["pages"][0][0] = "主機修改"
	var retained: Dictionary = panel.call("view_model")
	var retained_line: String = retained["sections"][0]["topics"][0]["pages"][0][0]
	expect_equal(retained_line, "P000", "view_model returns an immutable deep copy")
	panel.call("set_visuals", FakeVisuals.new())
	await _settle()
	var rendered_line := _find(panel, "SourceHelpBodyLine0") as Label
	expect(rendered_line != null and rendered_line.text == "P000", "rendering is not affected by host or view_model mutations")


func _test_edition_resolution(panel: Control) -> void:
	var visuals := FakeVisuals.new()
	panel.call("set_visuals", visuals)
	await _present(panel, _build_model("Game"))
	expect(bool(panel.call("source_art_available")), "Game help art is available independently")
	var game_only := true
	for call in visuals.calls:
		game_only = game_only and call[0] == "Game" and call[1] == "help" and int(call[2]) == 0
	expect(game_only, "Game content only resolves Game help art")

	visuals.calls.clear()
	panel.call("set_view_model", _build_model("MultiverseJourney"))
	await _settle()
	expect(bool(panel.call("source_art_available")), "MultiverseJourney help art is available independently")
	var mj_only := true
	var mj_chunks: Array = []
	for call in visuals.calls:
		mj_only = mj_only and call[0] == "MultiverseJourney" and call[1] == "help" and int(call[2]) == 0
		mj_chunks.append(int(call[3]))
	expect(mj_only, "MultiverseJourney content never borrows Game help art")
	for chunk in range(12):
		expect(mj_chunks.has(chunk), "MultiverseJourney resolves help chunk %d" % chunk)
	var frame_art := _find(panel, "SourceHelpFrame") as TextureRect
	expect(frame_art != null and frame_art.texture != null and frame_art.texture.get_size() == Vector2(800, 800), "2x textures still use 400x400 logical geometry")

	visuals.calls.clear()
	visuals.blocked_editions = ["MultiverseJourney"]
	panel.call("set_view_model", _build_model("MultiverseJourney"))
	await _settle()
	expect(not bool(panel.call("source_art_available")), "a blocked edition reports source art unavailable")
	var borrowed := false
	for call in visuals.calls:
		borrowed = borrowed or call[0] == "Game"
	expect(not borrowed, "a missing edition never falls back to Game help art")
	var fallback := _find(panel, "SourceHelpArtFallback") as Label
	expect(fallback != null and fallback.visible, "missing source art shows an explicit fallback note")


func _test_native_input_ordering(source_script: Script) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var modal_value: Variant = source_script.new()
	if not modal_value is Control:
		expect(false, "native input test creates an isolated help instance")
		viewport.queue_free()
		return
	var modal: Control = modal_value
	viewport.add_child(modal)
	var events: Array = []
	modal.connect("closed", func() -> void: events.append(true))
	var visuals := FakeVisuals.new()
	modal.call("set_visuals", visuals)
	modal.call("set_view_model", _build_model())
	await _settle()

	# Section selection happens on left press; the release must not reselect.
	viewport.push_input(_mouse_event(FRAME_ORIGIN + Vector2(59, 58 + 36 + 16), MOUSE_BUTTON_LEFT, true), true)
	await _settle()
	var header := _find(modal, "SourceHelpSectionTitle") as Label
	expect(header != null and header.text == "SEC1", "left press selects a section")
	expect_equal(int(modal.call("selected_section")), 1, "left press updates the selected section index")
	viewport.push_input(_mouse_event(FRAME_ORIGIN + Vector2(59, 58 + 36 + 16), MOUSE_BUTTON_LEFT, false), true)
	await _settle()
	expect_equal(int(modal.call("selected_section")), 1, "left release does not reselect a section")

	# Topic selection also happens on press only.
	viewport.push_input(_mouse_event(FRAME_ORIGIN + Vector2(150, 78 + 34 * 2 + 16), MOUSE_BUTTON_LEFT, true), true)
	await _settle()
	expect_equal(int(modal.call("selected_topic")), 2, "left press selects the topic row")
	viewport.push_input(_mouse_event(FRAME_ORIGIN + Vector2(150, 78 + 34 * 2 + 16), MOUSE_BUTTON_LEFT, false), true)
	await _settle()
	expect_equal(int(modal.call("selected_topic")), 2, "left release does not reselect a topic")

	# Topic list arrow: press shows pressed art, release performs.  Section 6 has
	# thirty topics, so the first page step is a full eight topics.
	viewport.push_input(_mouse_event(FRAME_ORIGIN + Vector2(59, 58 + 36 * 6 + 16), MOUSE_BUTTON_LEFT, true), true)
	await _settle()
	expect_equal(int(modal.call("selected_section")), 6, "left press selects the thirty topic section")
	viewport.push_input(_mouse_event(FRAME_ORIGIN + Vector2(181, 66), MOUSE_BUTTON_LEFT, true), true)
	await _settle()
	var down_art := _find(modal, "SourceHelpTopicDownArt") as TextureRect
	expect(down_art != null and int(down_art.get_meta("source_chunk", -1)) == 7, "topic down press shows the pressed art")
	expect_equal(int(modal.call("topic_page_offset")), 0, "an unreleased arrow press does not shift the list")
	viewport.push_input(_mouse_event(FRAME_ORIGIN + Vector2(181, 66), MOUSE_BUTTON_LEFT, false), true)
	await _settle()
	expect_equal(int(modal.call("topic_page_offset")), 8, "topic down release shifts the list by eight")
	down_art = _find(modal, "SourceHelpTopicDownArt") as TextureRect
	expect(down_art != null and int(down_art.get_meta("source_chunk", -1)) == 5, "released arrow art returns to normal")
	var offset_after_release := int(modal.call("topic_page_offset"))
	viewport.push_input(_mouse_event(FRAME_ORIGIN + Vector2(181, 66), MOUSE_BUTTON_LEFT, false), true)
	await _settle()
	expect_equal(int(modal.call("topic_page_offset")), offset_after_release, "a release without a matching press cannot shift the list")

	# Body arrow ordering on a multi-page topic.
	modal.call("select_section", 0)
	modal.call("select_topic", 0)
	await _settle()
	expect_equal(int(modal.call("selected_body_page")), 0, "body starts on page 0")
	viewport.push_input(_mouse_event(FRAME_ORIGIN + Vector2(354, 64), MOUSE_BUTTON_LEFT, true), true)
	await _settle()
	var next_art := _find(modal, "SourceHelpBodyNextArt") as TextureRect
	expect(next_art != null and int(next_art.get_meta("source_chunk", -1)) == 11, "body next press shows the pressed art")
	expect_equal(int(modal.call("selected_body_page")), 0, "an unreleased body arrow does not page")
	viewport.push_input(_mouse_event(FRAME_ORIGIN + Vector2(354, 64), MOUSE_BUTTON_LEFT, false), true)
	await _settle()
	expect_equal(int(modal.call("selected_body_page")), 1, "body next release pages the body")
	next_art = _find(modal, "SourceHelpBodyNextArt") as TextureRect
	expect(next_art != null and int(next_art.get_meta("source_chunk", -1)) == 9, "released body arrow art returns to normal")

	# PgUp/PgDn page the body on keydown, ignore echo, and clear on keyup.
	viewport.push_input(_key_event(KEY_PAGEDOWN, true), true)
	await _settle()
	expect_equal(int(modal.call("selected_body_page")), 2, "PgDn keydown pages the body forward")
	viewport.push_input(_key_event(KEY_PAGEDOWN, true, true), true)
	await _settle()
	expect_equal(int(modal.call("selected_body_page")), 2, "PgDn echo repeats do not page again")
	viewport.push_input(_key_event(KEY_PAGEDOWN, false), true)
	viewport.push_input(_key_event(KEY_PAGEDOWN, true), true)
	await _settle()
	expect_equal(int(modal.call("selected_body_page")), 2, "PgDn at the last page is a no-op")
	viewport.push_input(_key_event(KEY_PAGEDOWN, false), true)
	viewport.push_input(_key_event(KEY_PAGEUP, true), true)
	await _settle()
	expect_equal(int(modal.call("selected_body_page")), 1, "PgUp keydown pages the body backward")
	viewport.push_input(_key_event(KEY_PAGEUP, false), true)

	# Right release closes anywhere without requiring a right press.
	viewport.push_input(_mouse_event(Vector2(10, 10), MOUSE_BUTTON_RIGHT, true), true)
	await _settle()
	expect(events.is_empty(), "a right press does not close the help window")
	viewport.push_input(_mouse_event(Vector2(10, 10), MOUSE_BUTTON_RIGHT, false), true)
	await _settle()
	expect(events.size() == 1, "right release closes the help window once")
	expect(not bool(modal.call("is_open")), "a closed help window reports itself closed")
	viewport.push_input(_mouse_event(Vector2(620, 470), MOUSE_BUTTON_RIGHT, false), true)
	await _settle()
	expect(events.size() == 1, "a second right release cannot double close")

	# The unavailable view must still honour the right release close.
	modal.call("set_view_model", {"schema": "richman4.help-edition/v1", "edition": "Game", "sections": []})
	await _settle()
	expect(not bool(modal.call("is_model_valid")), "the unavailable model is rejected")
	viewport.push_input(_mouse_event(Vector2(320, 240), MOUSE_BUTTON_RIGHT, false), true)
	await _settle()
	expect(events.size() == 2, "the unavailable view still closes on right release")

	viewport.queue_free()
	await process_frame


func _mouse_event(position: Vector2, button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	return event


func _key_event(keycode: Key, pressed: bool, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	event.echo = echo
	return event
