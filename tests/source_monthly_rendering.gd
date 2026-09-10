extends SceneTree

const PanelScript := preload("res://game/ui/source_monthly_panel.gd")

var checks := 0
var failures := 0
var skipped := 0


class FakeVisuals extends RefCounted:

	var source_color := Color("#3cc27b")

	func _logical(width: float, height: float, anchor_x: float = 0.0, anchor_y: float = 0.0) -> Dictionary:
		return JSON.parse_string(JSON.stringify({"width": width, "height": height, "anchor_x": anchor_x, "anchor_y": anchor_y}))

	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		var logical := _logical(1.0, 1.0)
		if resource == 25 and chunk == 0:
			logical = _logical(640.0, 480.0)
		elif resource == 25 and chunk == 24:
			logical = _logical(233.0, 410.0)
		elif resource == 25 and chunk in [11, 12, 13, 14]:
			logical = _logical(160.0 if chunk == 11 else 159.0, 71.0)
		elif resource == 25 and chunk >= 49:
			logical = _logical(66.0, 72.0, 31.0, 38.0)
		elif resource == 76:
			logical = _logical(592.0, 432.0)
		return {"edition": edition, "archive": archive, "resource": resource, "chunk": chunk, "logical": logical}

	func texture(frame: Dictionary) -> Texture2D:
		var logical: Dictionary = frame["logical"]
		var image := Image.create(maxi(1, int(float(logical["width"]) * 2.0)), maxi(1, int(float(logical["height"]) * 2.0)), false, Image.FORMAT_RGBA8)
		if int(frame["resource"]) == 25 and int(frame["chunk"]) == 0:
			image.fill(source_color)
			# A logical pixel samples a 2x source texture at its center. Use a
			# bounded transparent area so the probe cannot sample a green neighbor.
			image.fill_rect(Rect2i(0, 0, 8, 8), Color(0, 0, 0, 0))
		else:
			image.fill(Color("#728fd7"))
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


func _detached(value: Dictionary) -> Dictionary:
	return value.duplicate(true)


func _interest_model() -> Dictionary:
	return _detached({"kind": "interest", "edition": "Game", "date": {"year": 1998, "month": 8, "day": 15}, "players": [
		{"id": 1, "name": "甲", "character_id": 0, "deposit_before": 0, "interest": 0, "loan_active": false},
		{"id": 2, "name": "乙", "character_id": 1, "deposit_before": 311141, "interest": 0, "loan_active": true},
		{"id": 3, "name": "丙", "character_id": 2, "deposit_before": 59233, "interest": 5923, "loan_active": false},
		{"id": 4, "name": "丁", "character_id": 3, "deposit_before": 39599, "interest": 3959, "loan_active": false},
	]})


func _dividend_model() -> Dictionary:
	return _detached({"kind": "dividend", "edition": "Game", "date": {"year": 1998, "month": 7, "day": 15}, "players": [{"id": 1, "name": "甲", "character_id": 0, "total": 0}], "companies": [{"company_id": 1, "name": "花旗銀行", "monthly_profit": 0, "payouts": [0]}]})


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var panel: Control = PanelScript.new()
	viewport.add_child(panel)
	await _settle()
	var visuals := FakeVisuals.new()
	panel.call("set_auto_advance_seconds", 0.0)
	panel.call("set_visuals", visuals)
	panel.call("set_view_model", _interest_model())
	await _settle()
	var frames: Dictionary = panel.call("source_frames")
	var logical: Dictionary = frames["Game.Panel25.49"]["logical"]
	_expect(typeof(logical["width"]) == TYPE_FLOAT and logical["width"] == 66.0, "JSON metadata keeps integral width as a finite float")
	_expect(typeof(logical["anchor_x"]) == TYPE_FLOAT and logical["anchor_x"] == 31.0, "JSON metadata keeps integral anchor as a finite float")
	for ordinal in range(4):
		var character := panel.find_child("InterestCharacter%d" % ordinal, true, false) as TextureRect
		_expect(character != null, "interest character %d is rendered" % ordinal)
		if character != null:
			_expect(character.position.x + character.size.x <= 640.0 and character.position.y + character.size.y <= 480.0, "interest character %d stays inside source canvas" % ordinal)
			_expect(character.size == Vector2(66, 72) and character.texture.get_size() == Vector2(132, 144), "interest character %d uses logical geometry independent of 2x texture" % ordinal)

	if DisplayServer.get_name() == "headless":
		skipped += 2
		print("SKIP: native pixel probes require a non-headless DisplayServer; metadata and geometry still ran")
	else:
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		_expect(pixels.get_pixel(20, 20).is_equal_approx(visuals.source_color), "source interest background is visible above fallback")
		print("MONTHLY_BACKGROUND_PROBE opaque=%s zero=%s" % [pixels.get_pixel(20, 20), pixels.get_pixel(2, 2)])
		_expect(pixels.get_pixel(2, 2).is_equal_approx(Color.BLACK), "transparent interest source pixels expose opaque black backing")

	panel.call("set_view_model", _dividend_model())
	await _settle()
	var header := panel.find_child("DividendHeaderCompany", true, false) as Label
	var company := panel.find_child("DividendCompany0", true, false) as Label
	var header_rect := header.get_global_rect() if header != null else Rect2()
	var company_rect := company.get_global_rect() if company != null else Rect2()
	_expect(header != null and header_rect.position.x == 42.0, "company header uses source left x18 plus panel origin x24")
	_expect(header != null and company != null and header_rect.position.x >= company_rect.position.x and header_rect.end.x <= company_rect.end.x, "company header stays within the source company cell")
	var backing := panel.find_child("MonthlyFallbackBackground", true, false) as ColorRect
	_expect(backing != null and backing.color == Color.BLACK, "dividend outer backing is opaque source black")

	viewport.queue_free()
	await _settle()
	print("Source monthly rendering checks: %d, failures: %d, skipped_pixel_probes: %d" % [checks, failures, skipped])
	quit(1 if failures else 0)
