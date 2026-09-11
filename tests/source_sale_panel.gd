extends SceneTree

## Focused hermetic S21 SALE presenter checks.
##
## The host model is detached and the presenter emits intents only: no GameState,
## MainUI, persistence, inventory rules or money owner is instantiated here.
## Input is replayed programmatically through a SubViewport; nothing here claims
## native OS input.

const PANEL_PATH := "res://game/ui/source_sale_panel.gd"
const PANEL_SCRIPT = preload("res://game/ui/source_sale_panel.gd")
const OVERLAY_ENV := "RICHMAN4_SALE_PANEL_ASSETS"
const OVERLAY_DEFAULT := "/Users/tachikoma/Developer/richman4-validation-evidence/20260910-fidelity-recovery/sale/assets/images"

var checks := 0
var failures := 0
var actions: Array = []
var cancelled_count := 0


class FakeVisuals extends RefCounted:
	var calls: Array = []
	var missing: Array = []

	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		calls.append([edition, archive, resource, chunk])
		if missing.has("%d.%d" % [resource, chunk]):
			return {}
		var size := Vector2(4, 4)
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.1 + 0.01 * float(chunk), 0.4, 0.5, 1.0))
		return {
			"edition": edition,
			"archive": archive,
			"resource": resource,
			"chunk": chunk,
			"logical": {"width": size.x, "height": size.y, "anchor_x": 0.0, "anchor_y": 0.0},
			"texture": ImageTexture.create_from_image(image),
		}


class OverlayVisuals extends RefCounted:
	var root := ""
	var cache: Dictionary = {}

	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		var key := "%s|%s|%d|%d" % [root, edition, resource, chunk]
		if cache.has(key):
			return cache[key]
		var path := "%s/%s/ui/%s/%d/%d.png" % [root, edition, archive, resource, chunk]
		var result: Dictionary = {}
		if FileAccess.file_exists(path):
			var image := Image.load_from_file(path)
			if image != null and image.get_width() > 0:
				result = {
					"edition": edition,
					"archive": archive,
					"resource": resource,
					"chunk": chunk,
					"logical": {"width": image.get_width(), "height": image.get_height(), "anchor_x": 0.0, "anchor_y": 0.0},
					"texture": ImageTexture.create_from_image(image),
				}
		cache[key] = result
		return result


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	## A script error aborts _run without quitting; fail loudly instead of idling.
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("Source sale panel WATCHDOG timeout; checks: %d, failures: %d" % [checks, failures])
	quit(2)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _event(point: Vector2, button: int, pressed: bool, motion := false) -> InputEvent:
	if motion:
		var move := InputEventMouseMotion.new()
		move.position = point
		move.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		return move
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = pressed
	return event


func _new_pair() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var panel: Control = PANEL_SCRIPT.new()
	viewport.add_child(panel)
	panel.action_requested.connect(func(action: String, params: Dictionary) -> void: actions.append([action, params.duplicate(true)]))
	panel.cancelled.connect(func() -> void: cancelled_count += 1)
	return {"viewport": viewport, "panel": panel}


func _settle() -> void:
	await process_frame
	await process_frame


func _press(viewport: SubViewport, point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	viewport.push_input(_event(point, button, true), true)
	await _settle()


func _release(viewport: SubViewport, point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	viewport.push_input(_event(point, button, false), true)
	await _settle()


func _click(viewport: SubViewport, point: Vector2, release_point := Vector2.INF) -> void:
	await _press(viewport, point)
	await _release(viewport, point if release_point == Vector2.INF else release_point)


func _move(viewport: SubViewport, point: Vector2, held := true) -> void:
	viewport.push_input(_event(point, MOUSE_BUTTON_LEFT, held, true), true)
	await _settle()


func _empty_holdings() -> Dictionary:
	return {"stock": [], "property": [], "tool": [], "card": []}


func _offer(offer_id: int, category: String, source_id: int, seller_id: int, asking: int, reference_value: int, name := "") -> Dictionary:
	var record := {
		"offer_id": offer_id,
		"revision": 1,
		"seller_id": seller_id,
		"category": category,
		"source_id": source_id,
		"quantity": 2,
		"asking": asking,
		"name": name if not name.is_empty() else "品%d" % source_id,
		"reference_value": reference_value,
	}
	if category == "property":
		record["location"] = "地%d" % source_id
		record["development"] = "空地"
		record["rent"] = 10
		record["lease"] = 12
		record["building_level"] = 0
		record["building_type"] = 0
		record["property_kind"] = "land"
	return record


func _player(player_id: int, name: String, sex: int, offers: Array) -> Dictionary:
	return {"player_id": player_id, "name": name, "character_id": player_id, "sex": sex, "alive": true, "offers": offers}


func _full_board_players() -> Array:
	var categories := ["stock", "property", "tool", "card"]
	var first: Array = []
	var second: Array = []
	for index in range(7):
		var category: String = categories[index % 4]
		first.append(_offer(index + 1, category, index + 1, 0, 100 + index, 50 + index))
		second.append(_offer(100 + index, category, index + 1, 1, 200 + index, 80 + index))
	return [_player(0, "約 翰 喬", 1, first), _player(1, "錢 夫 人", 0, second)]


func _board_model(edition := "Game", players: Array = [], can_create := true, feedback := "", player_id := 0) -> Dictionary:
	return {
		"session_id": 7,
		"player_id": player_id,
		"edition": edition,
		"view": "board",
		"category": "stock",
		"players": players if not players.is_empty() else _full_board_players(),
		"holdings": _empty_holdings(),
		"can_create": can_create,
		"selected_offer": {},
		"selected_item": {},
		"feedback": feedback,
	}


func _picker_model(category: String, holdings: Dictionary, edition := "Game") -> Dictionary:
	return {
		"session_id": 7,
		"player_id": 0,
		"edition": edition,
		"view": "picker",
		"category": category,
		"players": [_player(0, "約 翰 喬", 1, [])],
		"holdings": holdings,
		"can_create": true,
		"selected_offer": {},
		"selected_item": {},
		"feedback": "",
	}


func _detail_model(offer: Dictionary, edition := "Game") -> Dictionary:
	return {
		"session_id": 7,
		"player_id": 0,
		"edition": edition,
		"view": "detail",
		"category": str(offer.get("category", "stock")),
		"players": [_player(0, "約 翰 喬", 1, []), _player(1, "錢 夫 人", 0, [])],
		"holdings": _empty_holdings(),
		"can_create": true,
		"selected_offer": offer,
		"selected_item": {},
		"feedback": "",
	}


func _stock_holdings() -> Array:
	return [
		{"source_id": 1, "name": "甲公司", "quantity": 0, "reference_value": 10},
		{"source_id": 2, "name": "乙公司", "quantity": 5, "reference_value": 22},
		{"source_id": 3, "name": "丙公司", "quantity": 3, "reference_value": 33},
		{"source_id": 4, "name": "丁公司", "quantity": 0, "reference_value": 44},
	]


func _tool_holdings() -> Array:
	return [
		{"source_id": 1, "name": "機車", "quantity": 0, "reference_value": 100},
		{"source_id": 5, "name": "汽車", "quantity": 2, "reference_value": 300},
		{"source_id": 9, "name": "炸彈", "quantity": 1, "reference_value": 500},
	]


func _card_holdings() -> Array:
	return [
		{"source_id": 3, "name": "購地卡", "quantity": 1, "reference_value": 200, "held_index": 0},
		{"source_id": 3, "name": "購地卡", "quantity": 1, "reference_value": 200, "held_index": 1},
		{"source_id": 7, "name": "換地卡", "quantity": 1, "reference_value": 400, "held_index": 2},
	]


func _property_holdings(count := 5) -> Array:
	var records: Array = [
		{"source_id": 1, "name": "空地甲", "quantity": 1, "reference_value": 100, "kind": "land", "building_level": 0, "building_type": 0, "location": "A1", "development": "空地", "rent": 5, "lease": 10},
		{"source_id": 2, "name": "房屋乙", "quantity": 1, "reference_value": 200, "kind": "land", "building_level": 2, "building_type": 0, "location": "B2", "development": "房屋", "rent": 15, "lease": 20},
		{"source_id": 3, "name": "商店丙", "quantity": 1, "reference_value": 300, "kind": "land", "building_level": 1, "building_type": 3, "location": "C3", "development": "連鎖店", "rent": 25, "lease": 30},
		{"source_id": 4, "name": "設施丁", "quantity": 1, "reference_value": 400, "kind": "facility", "building_level": 1, "building_type": 1, "location": "D4", "development": "設施", "rent": 35, "lease": 40},
		{"source_id": 5, "name": "設施戊", "quantity": 1, "reference_value": 500, "kind": "facility", "building_level": 0, "building_type": 0, "location": "E5", "development": "設施", "rent": 45, "lease": 50},
	]
	for index in range(6, count + 1):
		records.append({"source_id": index, "name": "額外%d" % index, "quantity": 1, "reference_value": 100 + index, "kind": "land", "building_level": 1, "building_type": 0, "location": "X%d" % index, "development": "房屋", "rent": 5, "lease": 6})
	return records


func _last_action() -> Array:
	return actions[actions.size() - 1] if not actions.is_empty() else []


func _count(panel: Control, prefix: String) -> int:
	var count := 0
	for child in panel.find_children(prefix + "*", "", true, false):
		count += 1
	return count


func _run() -> void:
	if not FileAccess.file_exists(PANEL_PATH):
		expect(false, "source sale presenter exists")
		print("Source sale panel RED: implementation absent; checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var pair := _new_pair()
	var viewport: SubViewport = pair.viewport
	var panel: Control = pair.panel
	var visuals := FakeVisuals.new()
	expect(not panel.visible and not panel.is_open(), "unconfigured panel starts hidden and inert")
	panel.set_visual_accessor(visuals)

	# Malformed model fails closed with explicit empty art status.
	var malformed := _board_model()
	malformed.erase("session_id")
	expect(not panel.configure(malformed), "malformed model is rejected")
	expect(not panel.is_open() and not panel.visible, "rejected model never opens")
	expect(panel.source_art_status().is_empty() and not panel.source_art_available(), "fail-closed art status is explicit")
	var bad_sex := _board_model()
	bad_sex.players[0].sex = 2
	expect(not panel.configure(bad_sex), "invalid sex is rejected")
	var bad_offer := _board_model()
	bad_offer.players[0].offers[1].erase("revision")
	expect(not panel.configure(bad_offer), "offer missing revision is rejected")
	var bad_holdings := _picker_model("stock", {"stock": [{"source_id": 1, "name": "甲"}]})
	expect(not panel.configure(bad_holdings), "holding missing quantity is rejected")

	# Board geometry, source frames and sex tiles for both editions.
	for edition in ["Game", "MultiverseJourney"]:
		var model := _board_model(edition)
		expect(panel.configure(model), "board model accepted: " + edition)
		expect(panel.is_open(), "configured board is open: " + edition)
		expect(not panel.source_art_available() and panel.source_art_status().get("board",false), "board art exists but source portrait remains pending: " + edition)
		var geometry: Dictionary = panel.source_geometry()
		expect_equal(geometry.edition, edition, "edition is reported: " + edition)
		expect_equal(geometry.board.rect, Rect2(22, 66, 596, 348), "board panel origin/size: " + edition)
		expect_equal(geometry.board.create, Rect2(464, 74, 72, 40), "create strict rect: " + edition)
		expect_equal(geometry.board.close, Rect2(536, 74, 72, 40), "close strict rect: " + edition)
		expect_equal(geometry.board.offer_origin, Vector2(104, 114), "offer origin: " + edition)
		expect_equal(geometry.board.offer_cell, Vector2(72, 72), "offer cell: " + edition)
		expect_equal(geometry.board.offer_columns, 7, "seven offers per player: " + edition)
		expect_equal(geometry.board.menu, Rect2(464, 116, 144, 96), "category menu rect: " + edition)
		expect_equal(geometry.board.sex_tiles, {"female": 9, "male": 13}, "sex tile chunks: " + edition)
		expect(visuals.calls.has([edition, "Panel", 73, 0]), "board chunk 73/0 requested: " + edition)
		var offer_nodes := _count(panel, "SourceSaleOffer")
		expect_equal(offer_nodes, 14, "seven offer rows for two players: " + edition)
		var male_offer := panel.find_child("SourceSaleOffer0_0", true, false)
		expect(male_offer != null and int(male_offer.get_meta("source_chunk")) == 13, "male stock seller uses tile 13: " + edition)
		var female_offer := panel.find_child("SourceSaleOffer1_0", true, false)
		expect(female_offer != null and int(female_offer.get_meta("source_chunk")) == 9, "female stock seller uses tile 9: " + edition)
		var property_offer := panel.find_child("SourceSaleOffer0_1", true, false)
		expect(property_offer != null and int(property_offer.get_meta("source_chunk")) == 14, "male property seller uses tile 14: " + edition)
		var female_card := panel.find_child("SourceSaleOffer1_3", true, false)
		expect(female_card != null and int(female_card.get_meta("source_chunk")) == 12, "female card seller uses tile 12: " + edition)
		var name_label := panel.find_child("SourceSalePlayerName1", true, false) as Label
		expect(name_label != null and name_label.text == "錢 夫 人", "board name is the live player name: " + edition)

	# Detached snapshot.
	var live := _board_model()
	panel.configure(live)
	live.players[0].name = "呼叫端改名"
	live.players[0].offers[0].asking = 99999
	expect_equal(panel.view_model().players[0].name, "約 翰 喬", "caller mutation cannot change the snapshot")
	expect_equal(panel.view_model().players[0].offers[0].asking, 100, "nested caller mutation cannot change the snapshot")

	# Strict create border: the open interval never latches the create button.
	panel.configure(_board_model("Game", [_player(0,"約 翰 喬",1,[])]))
	actions.clear()
	await _click(viewport, Vector2(464, 94))
	expect(actions.is_empty(), "create border pixel x=464 stays inert")
	expect(panel.find_child("SourceSaleMenu", true, false) == null, "create border never opens the menu")
	panel.configure(_board_model("Game", [_player(0,"約 翰 喬",1,[])]))

	# Menu boundary pixels stay inert while the local menu is held open.
	await _press(viewport, Vector2(500, 94))
	expect(panel.find_child("SourceSaleMenu", true, false) != null, "create press opens the local menu")
	await _move(viewport, Vector2(472, 125))
	await _release(viewport, Vector2(10, 10))
	expect(actions.is_empty(), "menu border pixel stays inert")
	expect(panel.find_child("SourceSaleMenu", true, false) != null, "menu stays open without a valid hover")

	# Column-major hover: begin a new held gesture after the prior release.
	await _press(viewport, Vector2(475, 126))
	await _move(viewport, Vector2(475, 126))
	await _release(viewport, Vector2(10, 10))
	expect_equal(_last_action(), ["category_selected", {"category": "stock"}], "left-top menu cell selects stock")
	actions.clear()
	await _press(viewport, Vector2(500, 94))
	await _move(viewport, Vector2(475, 165))
	await _release(viewport, Vector2(630, 470))
	expect_equal(_last_action(), ["category_selected", {"category": "property"}], "left-bottom cell selects property")
	actions.clear()
	await _press(viewport, Vector2(500, 94))
	await _move(viewport, Vector2(538, 126))
	await _release(viewport, Vector2(1, 1))
	expect_equal(_last_action(), ["category_selected", {"category": "tool"}], "right-top cell selects tool")
	actions.clear()
	await _press(viewport, Vector2(500, 94))
	await _move(viewport, Vector2(538, 165))
	await _release(viewport, Vector2(5, 5))
	expect_equal(_last_action(), ["category_selected", {"category": "card"}], "right-bottom cell selects card")
	actions.clear()

	# Create latch preserved across an equal host sync.
	await _press(viewport, Vector2(500, 94))
	expect(panel.find_child("SourceSaleMenu", true, false) != null, "menu is open before host sync")
	await _move(viewport, Vector2(538, 165))
	panel.configure(_board_model("Game", [_player(0,"約 翰 喬",1,[])]))
	expect(panel.find_child("SourceSaleMenu", true, false) != null, "equal model sync keeps the local menu gesture")
	await _release(viewport, Vector2(20, 20))
	expect_equal(_last_action(), ["category_selected", {"category": "card"}], "preserved latch still dispatches remembered hover")
	actions.clear()

	# Board full create refuses before the menu and only shows supplied feedback.
	var full := _board_model("Game", [], false, "")
	panel.configure(full)
	await _click(viewport, Vector2(500, 94))
	expect(panel.find_child("SourceSaleMenu", true, false) == null, "full board refuses create before the menu")
	expect(panel.find_child("SourceSaleFeedback", true, false) == null, "refusal is silent without host feedback")
	var full_feedback := _board_model("Game", [], false, "公佈欄已滿\n\n請先撤件！")
	panel.configure(full_feedback)
	await _click(viewport, Vector2(500, 94))
	expect(panel.find_child("SourceSaleFeedback", true, false) != null, "host feedback is visible when supplied")
	expect(panel.find_child("SourceSaleMenu", true, false) == null, "feedback refusal still never opens the menu")

	# Board offer latch + release outside opens the detail intent.
	panel.configure(_board_model())
	actions.clear()
	await _click(viewport, Vector2(110, 120), Vector2(640, 470))
	expect_equal(_last_action(), ["offer_selected", {"offer_id": 1, "revision": 1}], "offer latch releases outside into the detail intent")
	actions.clear()
	await _click(viewport, Vector2(100, 120))
	expect(actions.is_empty(), "offer border pixel x=100 stays inert")

	# Board close latch and right release.
	cancelled_count = 0
	await _press(viewport, Vector2(570, 94))
	expect(cancelled_count == 0, "close press alone does not cancel")
	await _release(viewport, Vector2(5, 470))
	expect_equal(cancelled_count, 1, "close latch releases outside as cancelled")
	expect(not panel.is_open(), "board close hides the panel")
	panel.configure(_board_model())
	cancelled_count = 0
	await _release(viewport, Vector2(40, 40), MOUSE_BUTTON_RIGHT)
	expect_equal(cancelled_count, 1, "board right release cancels")

	# Stock picker: compact positive rows only.
	var zero_stock := _picker_model("stock", {"stock":[{"source_id":0,"name":"第一公司","quantity":3,"reference_value":30}],"property":[],"tool":[],"card":[]})
	expect(panel.configure(zero_stock) and panel.find_child("SourceSaleStockName0",true,false) != null,"source stock id zero is a valid rendered holding")
	var stock_model := _picker_model("stock", {"stock": _stock_holdings(), "property": [], "tool": [], "card": []})
	panel.configure(stock_model)
	expect_equal(_count(panel, "SourceSaleStockName"), 2, "stock picker compacts zero holdings")
	expect(panel.find_child("SourceSaleStockName0", true, false) != null and (panel.find_child("SourceSaleStockName0", true, false) as Label).text == "乙公司", "first compact stock row is source order")
	expect_equal(panel.source_geometry().picker.stock.rows.position, Vector2(152, 64), "stock rows start at source y=64")
	expect_equal(panel.source_geometry().picker.stock.row_height, 32.0, "stock row stride is 32")
	actions.clear()
	await _click(viewport, Vector2(200, 80), Vector2(5, 5))
	expect_equal(_last_action(), ["item_selected", {"category": "stock", "source_id": 2, "held_index": -1}], "stock row commits remembered source id outside")
	actions.clear()
	await _click(viewport, Vector2(473, 48))
	expect_equal(_last_action(), ["back", {}], "stock close emits back")
	expect(panel.is_open(), "stock close does not cancel the whole panel")

	# Tool picker: compact positive rows and 74 icons.
	var tool_model := _picker_model("tool", {"stock": [], "property": [], "tool": _tool_holdings(), "card": []})
	panel.configure(tool_model)
	expect_equal(_count(panel, "SourceSaleToolIcon"), 2, "tool picker compacts zero rows")
	expect(visuals.calls.has(["Game", "Panel", 74, 4]), "tool 5 requests source icon 74/4")
	expect_equal(panel.source_geometry().picker.chunk, 3, "tool picker uses chunk 73/3")
	actions.clear()
	await _click(viewport, Vector2(176, 208), Vector2(600, 460))
	expect_equal(_last_action(), ["item_selected", {"category": "tool", "source_id": 5, "held_index": -1}], "tool slot commits remembered id outside")

	# Card picker: ordered duplicate slots with held_index.
	var card_model := _picker_model("card", {"stock": [], "property": [], "tool": [], "card": _card_holdings()})
	panel.configure(card_model)
	expect_equal(_count(panel, "SourceSaleCardLabel"), 3, "duplicate card slots are preserved")
	expect_equal((panel.find_child("SourceSaleCardLabel1", true, false) as Label).text, "購地卡", "duplicate card keeps source order")
	expect_equal(panel.source_geometry().picker.chunk, 4, "card picker uses chunk 73/4")
	actions.clear()
	await _click(viewport, Vector2(248, 208), Vector2(4, 4))
	expect_equal(_last_action(), ["item_selected", {"category": "card", "source_id": 3, "held_index": 1}], "card duplicate slot reports its held_index")

	# Property picker: five filters, eleven rows per page.
	var property_model := _picker_model("property", {"stock": [], "property": _property_holdings(), "tool": [], "card": []})
	panel.configure(property_model)
	expect_equal(panel.source_geometry().picker.property.tab_count, 5, "property picker has five filters")
	expect_equal(panel.source_geometry().picker.property.rows_per_page, 11, "property page shows eleven rows")
	expect_equal(_count(panel, "SourceSalePropertyCell"), 5 * 5, "all filter renders every property row")
	await _click(viewport, Vector2(232, 48))
	expect_equal(_count(panel, "SourceSalePropertyCell"), 3 * 5, "land filter keeps land rows")
	await _click(viewport, Vector2(312, 48))
	expect_equal(_count(panel, "SourceSalePropertyCell"), 2 * 5, "facility filter keeps facility rows")
	await _click(viewport, Vector2(392, 48))
	expect_equal(_count(panel, "SourceSalePropertyCell"), 1 * 5, "house filter keeps land with a building type zero")
	await _click(viewport, Vector2(472, 48))
	expect_equal(_count(panel, "SourceSalePropertyCell"), 1 * 5, "chain filter keeps land with a non-zero building type")
	actions.clear()
	await _click(viewport, Vector2(152, 48))
	await _click(viewport, Vector2(200, 112), Vector2(6, 6))
	expect_equal(_last_action(), ["item_selected", {"category": "property", "source_id": 1, "held_index": -1}], "property row commits remembered source id")
	actions.clear()
	var page_model := _picker_model("property", {"stock": [], "property": _property_holdings(13), "tool": [], "card": []})
	panel.configure(page_model)
	expect_equal(_count(panel, "SourceSalePropertyCell"), 11 * 5, "first property page is capped at eleven rows")
	await _click(viewport, Vector2(519, 112))
	expect_equal(_count(panel, "SourceSalePropertyCell"), 2 * 5, "page down shows the remaining property rows")
	await _click(viewport, Vector2(519, 71))
	expect_equal(_count(panel, "SourceSalePropertyCell"), 11 * 5, "page up returns to the eleven-row page")
	actions.clear()
	await _click(viewport, Vector2(519, 41))
	expect_equal(_last_action(), ["back", {}], "property close emits back")
	expect(panel.is_open(), "property close does not cancel the whole panel")

	# Detail: own primary label, other primary label, secondary and right release.
	var own := _offer(31, "stock", 2, 0, 700, 400)
	panel.configure(_detail_model(own))
	var own_label := panel.find_child("SourceSaleDetailPrimary", true, false) as Label
	expect(own_label != null and own_label.text == "撤 件", "own offer primary label is 撤 件")
	var own_geometry: Dictionary = panel.source_geometry()
	expect_equal(own_geometry.detail.origin, Vector2(224, 112), "stock detail origin")
	expect_equal(own_geometry.detail.primary, Rect2(240, 336, 72, 24), "stock detail primary strict rect")
	expect_equal(own_geometry.detail.secondary, Rect2(328, 336, 72, 24), "stock detail secondary strict rect")
	actions.clear()
	await _click(viewport, Vector2(240, 348))
	expect(actions.is_empty(), "detail primary border pixel stays inert")
	await _click(viewport, Vector2(276, 348), Vector2(600, 470))
	expect_equal(_last_action(), ["detail_primary", {"offer_id": 31, "revision": 1}], "detail primary releases outside as an intent")
	expect(panel.is_open(), "detail stays open for the host YES/NO resolution")
	actions.clear()
	await _click(viewport, Vector2(364, 348))
	expect_equal(_last_action(), ["back", {}], "detail secondary emits back")
	var other := _offer(32, "property", 3, 1, 900, 600)
	panel.configure(_detail_model(other))
	var other_label := panel.find_child("SourceSaleDetailPrimary", true, false) as Label
	expect(other_label != null and other_label.text == "購 買", "other offer primary label is 購 買")
	expect_equal(panel.source_geometry().detail.origin, Vector2(224, 96), "property detail origin")
	expect_equal(panel.source_geometry().detail.baseline, 265, "property detail button baseline")
	var tool_offer := _offer(33, "tool", 5, 1, 500, 300)
	panel.configure(_detail_model(tool_offer))
	expect_equal(panel.source_geometry().detail.origin, Vector2(224, 128), "tool detail origin")
	expect_equal(panel.source_geometry().detail.baseline, 203, "tool/card detail button baseline")
	actions.clear()
	await _release(viewport, Vector2(40, 40), MOUSE_BUTTON_RIGHT)
	expect_equal(_last_action(), ["back", {}], "detail right release emits back")

	# Reference: source panel, numeric reference and maximum ask; right release only.
	var reference_model := _detail_model(_offer(41, "property", 3, 1, 900, 600))
	reference_model["view"] = "reference"
	panel.configure(reference_model)
	expect_equal(panel.source_geometry().reference.rect, Rect2(227, 42, 184, 88), "reference panel default position")
	var message_label := panel.find_child("SourceSaleReferenceMessage", true, false) as Label
	expect(message_label != null and message_label.text == "請輸入欲拍賣的價格\n\n（市價：600元）", "reference follows source price instruction and market value")
	expect(panel.find_child("SourceSaleReferenceMax", true, false) == null, "source notice leaves MAX entry to the amount pad")
	actions.clear()
	await _click(viewport, Vector2(300, 180))
	expect(actions.is_empty(), "reference ignores left input")
	await _release(viewport, Vector2(40, 40), MOUSE_BUTTON_RIGHT)
	expect_equal(_last_action(), ["back", {}], "reference right release emits back")
	reference_model["reference_y"] = 200
	panel.configure(reference_model)
	expect_equal(panel.source_geometry().reference.rect.position.y, 200.0, "reference y follows the host model")

	# Release-only inertness for every view.
	panel.configure(_board_model())
	actions.clear()
	cancelled_count = 0
	await _release(viewport, Vector2(500, 94))
	expect(actions.is_empty() and cancelled_count == 0, "board release without press is inert")
	panel.configure(_picker_model("stock", {"stock": _stock_holdings(), "property": [], "tool": [], "card": []}))
	actions.clear()
	await _release(viewport, Vector2(200, 80))
	expect(actions.is_empty(), "picker release without press is inert")
	panel.configure(_detail_model(_offer(51, "stock", 2, 0, 700, 400)))
	actions.clear()
	await _release(viewport, Vector2(276, 348))
	expect(actions.is_empty(), "detail release without press is inert")

	# Missing art degrades to a descriptive fallback with explicit status.
	var blind := FakeVisuals.new()
	blind.missing = ["73.0", "73.13", "73.14", "73.15", "73.16", "73.9", "73.10", "73.11", "73.12"]
	panel.set_visual_accessor(blind)
	panel.configure(_board_model())
	expect(not panel.source_art_available(), "absent frames report unavailable art")
	expect(panel.source_art_status().get("board", true) == false, "absent board frame is explicit in art status")
	expect(panel.find_child("SourceSaleArtFallback", true, false) != null, "absent frames show the descriptive fallback")

	viewport.queue_free()
	await _settle()

	# Optional authorized-overlay integration (real PNG frames, never written).
	var overlay_root := OS.get_environment(OVERLAY_ENV)
	if overlay_root.is_empty() and DirAccess.dir_exists_absolute(OVERLAY_DEFAULT):
		overlay_root = OVERLAY_DEFAULT
	if not overlay_root.is_empty():
		var overlay_viewport := SubViewport.new()
		overlay_viewport.size = Vector2i(640, 480)
		overlay_viewport.handle_input_locally = true
		root.add_child(overlay_viewport)
		var overlay_panel: Control = PANEL_SCRIPT.new()
		overlay_viewport.add_child(overlay_panel)
		var overlay := OverlayVisuals.new()
		overlay.root = overlay_root
		overlay_panel.set_visual_accessor(overlay)
		var overlay_model := _board_model("MultiverseJourney")
		expect(overlay_panel.configure(overlay_model), "authorized overlay configures the board")
		expect(overlay_panel.source_art_status().get("board",false) and not overlay_panel.source_art_available(), "authorized overlay has source board while portrait remains pending")
		var board_art := overlay_panel.find_child("SourceSaleBoard", true, false) as TextureRect
		expect(board_art != null and board_art.texture.get_size() == Vector2(596, 348), "authorized board frame keeps source geometry")
		expect_equal(_count(overlay_panel, "SourceSaleOffer"), 14, "authorized overlay renders every source offer tile")
		expect(overlay_panel.source_art_status().get("board", false), "authorized overlay board frame resolves")
		overlay_viewport.queue_free()
		await _settle()
	else:
		print("NOTE: authorized sale overlay not present; real-frame checks skipped")

	print("Source sale panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
