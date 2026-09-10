extends SceneTree

## Focused, hermetic acceptance checks for the S17/S18 source presenter.
##
## The first tests-only commit intentionally loads the component dynamically.
## A missing implementation is a qualified behavioural RED; a missing script
## must not turn the result into a parser or setup error.  This suite never
## instantiates GameState, MainUI, audio, save/load, or an owner controller.

var checks := 0
var failures := 0
var _continued_count := 0


class FakeVisuals extends RefCounted:

	var calls: Array = []
	var texture_calls: Array = []
	var physical_scale := 2

	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		calls.append([edition, archive, resource, chunk])
		var logical := {"width": 1, "height": 1, "anchor_x": 0, "anchor_y": 0}
		if archive == "Panel" and resource == 25:
			if chunk == 0:
				logical = {"width": 640, "height": 480, "anchor_x": 0, "anchor_y": 0}
			elif chunk == 11:
				logical = {"width": 160, "height": 71, "anchor_x": 0, "anchor_y": 0}
			elif chunk in [12, 13, 14]:
				logical = {"width": 159, "height": 71, "anchor_x": 0, "anchor_y": 0}
			elif chunk == 24:
				logical = {"width": 233, "height": 410, "anchor_x": 0, "anchor_y": 0}
			elif chunk >= 49:
				logical = {"width": 66, "height": 72, "anchor_x": 31, "anchor_y": 38}
		elif archive == "Panel" and resource == 76:
			logical = {"width": 592, "height": 432, "anchor_x": 0, "anchor_y": 0}
		return {
			"edition": edition,
			"archive": archive,
			"resource": resource,
			"chunk": chunk,
			"logical": logical,
		}

	func texture(frame: Dictionary) -> Texture2D:
		texture_calls.append(frame.duplicate(true))
		var logical: Dictionary = frame.get("logical", {})
		var width := maxi(1, int(logical.get("width", 1)) * physical_scale)
		var height := maxi(1, int(logical.get("height", 1)) * physical_scale)
		var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
		var chunk := int(frame.get("chunk", 0))
		image.fill(Color(0.08 + float((chunk + 3) % 5) * 0.08, 0.32, 0.52, 1.0))
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


func _run() -> void:
	var source_path := "res://game/ui/source_monthly_panel.gd"
	if not FileAccess.file_exists(source_path):
		checks += 1
		failures += 1
		print("FAIL: Source monthly panel implementation is absent (qualified RED)")
		print("Source monthly panel RED: implementation absent; checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var source_script: Variant = load(source_path)
	if source_script == null:
		checks += 1
		failures += 1
		print("FAIL: Source monthly panel script could not load")
		quit(1)
		return
	var panel_value: Variant = source_script.new()
	if not panel_value is Node:
		checks += 1
		failures += 1
		print("FAIL: Source monthly panel did not instantiate as a Node")
		quit(1)
		return
	var panel: Node = panel_value
	root.add_child(panel)
	panel.continued.connect(_on_continued)
	await process_frame

	var api_ok := _check_public_api(panel)
	if api_ok:
		await _test_dividend_model_and_geometry(panel)
		await _test_interest_model_and_geometry(panel)
		await _test_invalid_models_and_fallback(panel)
		await _test_release_and_timer_race(panel, source_script)

	panel.queue_free()
	await process_frame
	print("Source monthly panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _check_public_api(panel: Node) -> bool:
	var methods := [
		"set_view_model",
		"set_visuals",
		"view_model",
		"report_data",
		"is_model_valid",
		"source_art_available",
		"source_geometry",
		"set_auto_advance_seconds",
		"continue_report",
		"is_open",
	]
	var ok := true
	for method in methods:
		var present := panel.has_method(method)
		expect(present, "monthly presenter exposes " + method)
		ok = ok and present
	var signal_present := panel.has_signal("continued")
	expect(signal_present, "monthly presenter exposes continued signal")
	return ok and signal_present


func _on_continued() -> void:
	_continued_count += 1


func _settle() -> void:
	await process_frame
	await process_frame


func _dividend_model() -> Dictionary:
	return {
		"kind": "dividend",
		"edition": "Game",
		"date": {"year": 1998, "month": 7, "day": 15},
		"players": [
			{"id": 11, "name": "宮本義雄", "character_id": 2, "total": 7641},
			{"id": 4, "name": "沙隆巴斯", "character_id": 5, "total": 5158},
			{"id": 8, "name": "錢夫人", "character_id": 8, "total": 35188},
		],
		"companies": [
			{"company_id": 2, "name": "花旗銀行", "monthly_profit": 0, "payouts": [0, 0, 0]},
			{"company_id": 4, "name": "松江百貨", "monthly_profit": 6975, "payouts": [6975, 0, 0]},
			{"company_id": 7, "name": "IBM", "monthly_profit": 31400, "payouts": [682, 0, 30717]},
			{"company_id": 9, "name": "未持有公司", "monthly_profit": 10000, "payouts": [0, 0, 0]},
		],
	}


func _interest_model() -> Dictionary:
	return {
		"kind": "interest",
		"edition": "MultiverseJourney",
		"date": {"year": 1998, "month": 8, "day": 15},
		"players": [
			{"id": 2, "name": "約翰喬", "character_id": 0, "deposit_before": 0, "interest": 0, "loan_active": false},
			{"id": 3, "name": "沙隆巴斯", "character_id": 1, "deposit_before": 311141, "interest": 0, "loan_active": true},
			{"id": 5, "name": "錢夫人", "character_id": 2, "deposit_before": 59233, "interest": 5923, "loan_active": false},
			{"id": 7, "name": "阿土仔", "character_id": 3, "deposit_before": 39599, "interest": 3959, "loan_active": false},
		],
	}


func _test_dividend_model_and_geometry(panel: Node) -> void:
	var model := _dividend_model()
	var before := model.duplicate(true)
	var visuals := FakeVisuals.new()
	panel.call("set_auto_advance_seconds", 0.0)
	panel.call("set_visuals", visuals)
	panel.call("set_view_model", model)
	await _settle()

	expect(model == before, "set_view_model does not mutate the dividend host model")
	expect(bool(panel.call("is_model_valid")), "valid dividend model is accepted")
	expect(bool(panel.call("source_art_available")), "complete dividend source art is reported available")
	expect(bool(panel.call("is_open")), "valid dividend model opens the modal")
	expect_equal(panel.call("report_data"), before, "public report data exposes the copied dividend payload")

	var exposed: Dictionary = panel.call("view_model")
	var exposed_players: Array = exposed["players"]
	var exposed_first: Dictionary = exposed_players[0]
	exposed_first["name"] = "外部修改"
	model["players"][0]["name"] = "主機修改"
	var retained: Dictionary = panel.call("view_model")
	expect(retained["players"][0]["name"] == "宮本義雄", "view_model returns an immutable deep copy")

	var geometry: Dictionary = panel.call("source_geometry")
	expect_equal(geometry.get("canvas"), Vector2(640, 480), "monthly backing canvas stays source logical size")
	expect_equal(geometry.get("panel_origin"), Vector2(24, 24), "dividend panel keeps the source backing origin")
	expect_equal(geometry.get("kind"), "dividend", "public geometry identifies the dividend report")

	var panel_art := panel.find_child("DividendPanelArt", true, false) as TextureRect
	expect(panel_art != null, "dividend uses a source Panel76 art node")
	if panel_art != null:
		expect_equal(panel_art.position, Vector2(24, 24), "Panel76 is placed at the source black-backing origin")
		expect_equal(panel_art.size, Vector2(592, 432), "Panel76 placement uses logical size, not the 2x texture size")
		expect(panel_art.texture != null and panel_art.texture.get_size() == Vector2(1184, 864), "2x Panel76 texture is accepted without changing geometry")

	var title := panel.find_child("DividendTitle", true, false) as Label
	var header_company := panel.find_child("DividendHeaderCompany", true, false) as Label
	var header_player := panel.find_child("DividendHeaderPlayer", true, false) as Label
	var header_profit := panel.find_child("DividendHeaderProfit", true, false) as Label
	var total := panel.find_child("DividendTotalLabel", true, false) as Label
	expect(title != null and title.text == "上市公司分紅", "dividend title keeps the source label")
	if title != null:
		expect_equal(title.get_rect().get_center(), Vector2(320, 49), "dividend title keeps source center plus panel origin")
		expect(title.get_theme_font_size("font_size") == 28, "dividend title keeps 28px source typography")
	expect(header_company != null and header_company.text == "公司", "diagonal company header is present")
	expect(header_player != null and header_player.text == "人名", "diagonal player header is present")
	expect(header_profit != null and header_profit.text == "本月盈餘", "monthly profit header is present")
	expect(total != null and total.text == "紅利", "dividend total label is present")
	if header_company != null:
		expect_equal(header_company.get_rect().get_center(), Vector2(42, 118), "company header keeps source relative center")
	if header_player != null:
		expect_equal(header_player.get_rect().get_center(), Vector2(128, 106), "player header keeps source diagonal center")
	if header_profit != null:
		expect_equal(header_profit.get_rect().get_center(), Vector2(566, 112), "profit header stays fixed at the final column")

	for ordinal in range(3):
		var player_header := panel.find_child("DividendPlayerHeader%d" % ordinal, true, false) as Label
		var player_total := panel.find_child("DividendPlayerTotal%d" % ordinal, true, false) as Label
		expect(player_header != null and player_header.text == ["宮本義雄", "沙隆巴斯", "錢夫人"][ordinal], "active player header %d is compacted" % ordinal)
		expect(player_total != null and player_total.text == ["7,641", "5,158", "35,188"][ordinal], "player total %d uses the authoritative signed-safe value" % ordinal)
		if player_header != null:
			expect_equal(player_header.get_rect().get_center(), Vector2(24 + 160 + 98 * ordinal, 24 + 88), "active player %d uses source compacted column center" % ordinal)
		if player_total != null:
			expect_equal(player_total.get_rect().end.x, 24 + 198 + 98 * ordinal, "player total %d keeps the source right edge" % ordinal)

	var negative := panel.find_child("DividendPayout1_1", true, false) as Label
	var monthly := panel.find_child("DividendProfit3", true, false) as Label
	var unheld := panel.find_child("DividendCompany3", true, false) as Label
	expect(negative != null and negative.text == "0", "zero payout remains visible instead of being omitted")
	var signed := panel.find_child("DividendPayout2_0", true, false) as Label
	expect(signed != null and signed.text == "682", "positive payout keeps source number formatting")
	expect(monthly != null and monthly.text == "10,000", "unheld company monthly profit remains in the report")
	expect(unheld != null and unheld.text == "未持有公司", "all linked companies remain in stock-index order")
	if monthly != null:
		expect_equal(monthly.get_rect().end.x, 24 + 572, "monthly profit keeps the fixed final-column right edge")
	if total != null:
		expect_equal(total.get_rect().get_center(), Vector2(24 + 62, 24 + 404), "dividend total keeps the source total center")

	expect(_has_visual_call(visuals.calls, "Game", "Panel", 76, 0), "Game resolves Panel76 chunk zero")
	expect(_has_visual_call(visuals.calls, "Game", "Panel", 25, 0), "Game resolves Panel25 full background")
	for chunk in [11, 12, 13, 14, 55, 64, 73]:
		expect(_has_visual_call(visuals.calls, "Game", "Panel", 25, chunk), "Game resolves monthly source chunk %d" % chunk)


func _test_interest_model_and_geometry(panel: Node) -> void:
	var model := _interest_model()
	var visuals := FakeVisuals.new()
	panel.call("set_auto_advance_seconds", 3.0)
	panel.call("set_visuals", visuals)
	panel.call("set_view_model", model)
	await _settle()

	expect(bool(panel.call("is_model_valid")), "valid interest model is accepted")
	expect(bool(panel.call("source_art_available")), "complete interest source art is reported available")
	var geometry: Dictionary = panel.call("source_geometry")
	expect_equal(geometry.get("kind"), "interest", "public geometry identifies the interest report")
	expect_equal(geometry.get("edition"), "MultiverseJourney", "public geometry retains the explicit edition")
	var background := panel.find_child("InterestBackground", true, false) as TextureRect
	var clerk := panel.find_child("InterestClerk", true, false) as TextureRect
	expect(background != null and background.texture != null, "interest uses the full Panel25 background")
	if background != null:
		expect_equal(background.position, Vector2.ZERO, "interest background starts at the source origin")
		expect_equal(background.size, Vector2(640, 480), "interest background keeps source logical bounds")
		expect(background.texture.get_size() == Vector2(1280, 960), "interest accepts a 2x background texture without geometry drift")
	expect(clerk != null and clerk.texture != null, "interest includes the stable source clerk pose")
	if clerk != null:
		expect_equal(clerk.position, Vector2(28, 70), "clerk keeps source placement")
		expect_equal(clerk.size, Vector2(233, 410), "clerk uses logical frame dimensions")

	var expected_anchors := [60, 180, 300, 420]
	for ordinal in range(4):
		var card := panel.find_child("InterestPlayerCard%d" % ordinal, true, false) as TextureRect
		var deposit := panel.find_child("InterestDeposit%d" % ordinal, true, false) as Label
		var interest := panel.find_child("InterestInterest%d" % ordinal, true, false) as Label
		var deposit_label := panel.find_child("InterestDepositLabel%d" % ordinal, true, false) as Label
		var interest_label := panel.find_child("InterestInterestLabel%d" % ordinal, true, false) as Label
		expect(card != null and card.texture != null, "interest card %d uses source card art" % ordinal)
		if card != null:
			expect_equal(card.position, Vector2(360, expected_anchors[ordinal] - 36), "interest card %d keeps source anchor placement" % ordinal)
			expect(card.size == Vector2(160 if ordinal == 0 else 159, 71), "interest card %d keeps source logical card size" % ordinal)
		expect(deposit_label != null and deposit_label.text == "存款：", "interest deposit label %d keeps source wording" % ordinal)
		expect(interest_label != null and interest_label.text == "利息：", "interest interest label %d keeps source wording" % ordinal)
		expect(deposit != null and deposit.text == ["$0", "$311,141", "$59,233", "$39,599"][ordinal], "interest deposit %d shows pre-interest balance" % ordinal)
		expect(interest != null, "interest result %d is present" % ordinal)
		if deposit != null:
			expect_equal(deposit.get_rect().end.x, 360 + 154, "interest deposit %d keeps source right edge" % ordinal)
		if interest != null:
			expect_equal(interest.get_rect().end.x, 360 + 154, "interest result %d keeps source right edge" % ordinal)
		if ordinal == 1:
			expect(interest.text == "貸款中" and interest.get_theme_color("font_color") == Color("#c21f28"), "loan-active interest replaces the numeric value in red")
		else:
			expect(interest.text == ["$0", "貸款中", "$5,923", "$3,959"][ordinal], "interest result %d preserves zero or settled interest" % ordinal)

	for chunk in [0, 11, 12, 13, 14, 24, 49, 52, 55, 58]:
		expect(_has_visual_call(visuals.calls, "MultiverseJourney", "Panel", 25, chunk), "MJ resolves Panel25 chunk %d" % chunk)
	for forbidden in [47, 50, 53, 56]:
		expect(not _has_visual_call(visuals.calls, "MultiverseJourney", "Panel", 25, forbidden), "interest slice does not claim initial character pose chunk %d" % forbidden)
	var timer := panel.find_child("MonthlyAutoAdvanceTimer", true, false) as Timer
	expect(timer == null or timer.is_stopped(), "interest report has no automatic close timer")


func _test_invalid_models_and_fallback(panel: Node) -> void:
	var visuals := FakeVisuals.new()
	var invalid_edition := _dividend_model()
	invalid_edition["edition"] = "UnknownEdition"
	panel.call("set_visuals", visuals)
	panel.call("set_view_model", invalid_edition)
	await _settle()
	expect(not bool(panel.call("is_model_valid")), "unknown edition is rejected")
	expect(not bool(panel.call("source_art_available")), "unknown edition cannot claim source art")
	expect(not bool(panel.call("continue_report")), "invalid model cannot emit continuation")
	var unavailable := panel.find_child("MonthlyUnavailable", true, false) as Label
	expect(unavailable != null and unavailable.text.contains("資料格式無法顯示"), "invalid model shows an explicit unavailable fallback")
	var game_calls := 0
	for call in visuals.calls:
		if call is Array and call.size() == 4 and call[0] == "Game":
			game_calls += 1
	expect(game_calls == 0, "unknown edition never silently borrows Game source art")

	var duplicate_ids := _dividend_model()
	duplicate_ids["players"][1]["id"] = duplicate_ids["players"][0]["id"]
	panel.call("set_view_model", duplicate_ids)
	expect(not bool(panel.call("is_model_valid")), "duplicate player IDs are invalid")
	var mismatched_payouts := _dividend_model()
	mismatched_payouts["companies"][0]["payouts"] = [1, 2]
	panel.call("set_view_model", mismatched_payouts)
	expect(not bool(panel.call("is_model_valid")), "payout alignment mismatch is invalid")
	var negative_interest := _interest_model()
	negative_interest["players"][0]["interest"] = -1
	panel.call("set_view_model", negative_interest)
	expect(not bool(panel.call("is_model_valid")), "negative settled interest is invalid")


func _test_release_and_timer_race(panel: Node, source_script: Script) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var modal_value: Variant = source_script.new()
	if not modal_value is Node:
		expect(false, "release test creates an isolated modal instance")
		viewport.queue_free()
		return
	var modal: Node = modal_value
	viewport.add_child(modal)
	var events: Array = []
	modal.continued.connect(func() -> void: events.append(true))
	var visuals := FakeVisuals.new()
	modal.call("set_auto_advance_seconds", 0.0)
	modal.call("set_visuals", visuals)
	modal.call("set_view_model", _dividend_model())
	await _settle()

	var down := InputEventMouseButton.new()
	down.position = Vector2(320, 240)
	down.global_position = down.position
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	viewport.push_input(down, true)
	await process_frame
	expect(events.is_empty(), "left button down does not close the source report")
	var up := InputEventMouseButton.new()
	up.position = Vector2(320, 240)
	up.global_position = up.position
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	viewport.push_input(up, true)
	await process_frame
	expect(events.size() == 1, "left button release closes the source report once")
	expect(not bool(modal.call("is_open")), "source release hides the report modal")
	modal.call("set_view_model", _dividend_model())
	await _settle()
	var timer := modal.find_child("MonthlyAutoAdvanceTimer", true, false) as Timer
	expect(timer != null and timer.one_shot, "dividend report owns a one-shot auto-close timer")
	if timer != null:
		timer.timeout.emit()
		expect(events.size() == 2, "timer close emits one continuation")
		var after_timer := events.size()
		var right_up := InputEventMouseButton.new()
		right_up.position = Vector2(320, 240)
		right_up.global_position = right_up.position
		right_up.button_index = MOUSE_BUTTON_RIGHT
		right_up.pressed = false
		viewport.push_input(right_up, true)
		await process_frame
		expect(events.size() == after_timer, "release/timer race cannot double-emit continuation")
		expect(not bool(modal.call("continue_report")), "closed report rejects a second continuation")
	viewport.queue_free()
	await process_frame


func _has_visual_call(calls: Array, edition: String, archive: String, resource: int, chunk: int) -> bool:
	for call in calls:
		if call is Array and call == [edition, archive, resource, chunk]:
			return true
	return false
