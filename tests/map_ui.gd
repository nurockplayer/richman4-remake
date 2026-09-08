extends SceneTree

const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
const MainScene = preload("res://game/main.tscn")
const BoardView = preload("res://game/ui/board_view.gd")

var checks := 0
var failures := 0

class RouteStub extends RefCounted:
	var state: Dictionary = {}
	var route_calls: Array = []

	func _init(initial_state: Dictionary) -> void:
		state = initial_state.duplicate(true)

	func get_snapshot() -> Dictionary:
		return state.duplicate(true)

	func choose_route(next_index: int) -> Dictionary:
		route_calls.append(next_index)
		state["phase"] = "await_roll"
		state["route_options"] = []
		state["remaining_steps"] = 0
		return {"ok": true, "message": "已選擇路線", "state": get_snapshot()}

class SelectionProbe extends RefCounted:
	var selected := -1
	var route := -1

	func on_tile(index: int) -> void:
		selected = index

	func on_route(index: int) -> void:
		route = index

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var normalized := Maps.normalize_map(Fixture.make())
	_expect(bool(normalized.get("ok", false)), "fixture map normalizes")
	var definition: Dictionary = normalized.get("definition", {})
	await _test_original_graph_view(definition)
	await _test_legacy_perimeter()

	var ui = MainScene.instantiate()
	root.add_child(ui)
	if ui.audio_controller != null:
		ui.audio_controller.call("stop")
	ui.set_process(false)
	await _test_new_game_popup_layout(ui)
	_test_catalog_fallback(ui)
	_test_catalog_selection_and_map8(ui, Fixture.make())
	_test_route_controls_and_ai_guard(ui, definition)
	_test_saved_map_identity(ui, definition)
	_test_invalid_seed_preserves_game(ui)
	ui.queue_free()
	await create_timer(0.15).timeout
	print("map UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func _rect_is_inside(outer: Rect2, inner: Rect2) -> bool:
	var inner_end := inner.position + inner.size
	var outer_end := outer.position + outer.size
	return inner.position.x >= outer.position.x and inner.position.y >= outer.position.y and inner_end.x <= outer_end.x and inner_end.y <= outer_end.y

func _popup_child_screen_rect(popup: PopupPanel, child: Control) -> Rect2:
	var child_rect: Rect2 = child.get_global_rect()
	return Rect2(Vector2(popup.position) + child_rect.position, child_rect.size)

func _test_new_game_popup_layout(ui: Control) -> void:
	ui._on_new_game_pressed()
	for _frame in range(8):
		await process_frame
	var popup: PopupPanel = ui.new_game_popup
	var viewport_rect := ui.get_viewport().get_visible_rect()
	var popup_rect := Rect2(Vector2(popup.position), Vector2(popup.size))
	var preview_rect := _popup_child_screen_rect(popup, ui.map_preview_view)
	var seed_rect := _popup_child_screen_rect(popup, ui.seed_input)
	var confirm_rect := _popup_child_screen_rect(popup, ui.new_game_confirm_button)
	_expect(popup.visible, "new game popup is visible after opening")
	_expect(_rect_is_inside(viewport_rect, popup_rect), "new game popup stays inside the 1280x800 viewport")
	_expect(_rect_is_inside(popup_rect, preview_rect), "map preview stays inside the popup")
	_expect(_rect_is_inside(popup_rect, seed_rect), "seed input stays inside the popup")
	_expect(_rect_is_inside(popup_rect, confirm_rect), "new game confirm stays inside the popup")
	_expect(_rect_is_inside(viewport_rect, seed_rect) and _rect_is_inside(viewport_rect, confirm_rect), "new game inputs stay inside the viewport")
	ui.new_game_popup.hide()

func _test_original_graph_view(definition: Dictionary) -> void:
	var view = BoardView.new()
	view.size = Vector2(720.0, 480.0)
	root.add_child(view)
	view.set_preview_definition(definition)
	await process_frame
	_expect(view.is_original_map(), "coordinate map uses original graph renderer")
	_expect(view.board_mode() == "original", "coordinate map reports original mode")
	var node_position: Vector2 = view.get_screen_position_for_index(2)
	var clicked := view.select_at_position(node_position)
	_expect(clicked == 2, "map node hit testing uses rendered coordinate")
	var probe := SelectionProbe.new()
	view.tile_selected.connect(probe.on_tile)
	view.route_selected.connect(probe.on_route)
	view.route_options = [2, 3]
	var route_click := view.select_at_position(node_position)
	_expect(route_click == 2 and probe.selected == 2 and probe.route == 2, "map click emits tile and route selection")
	var zoom_before := view.get_zoom()
	view.set_zoom(1.8, node_position)
	_expect(view.get_zoom() > zoom_before, "map zoom increases")
	var zoomed_position: Vector2 = view.get_screen_position_for_index(2)
	_expect(zoomed_position.distance_to(node_position) < 1.0, "zoom keeps focused node under pointer")
	view.pan_by(Vector2(32.0, 18.0))
	var panned_position: Vector2 = view.get_screen_position_for_index(2)
	_expect(panned_position.distance_to(zoomed_position + Vector2(32.0, 18.0)) < 1.0, "map pan moves node coordinates")
	var retained_pan: Vector2 = view.map_pan
	view.set_map_definition(definition)
	_expect(view.map_pan == retained_pan and view.map_zoom == 1.8, "ordinary preview refresh keeps viewport")
	var replacement := definition.duplicate(true)
	replacement.id = "replacement"
	view.set_map_definition(replacement)
	_expect(view.map_pan == Vector2.ZERO and view.map_zoom == 1.0, "preview map replacement resets viewport")
	view.set_game_data(replacement.board, [], 0, replacement)
	view.pan_by(Vector2(10000, -5000))
	view.set_zoom(2.0)
	view.set_game_data(replacement.board, [], 0, replacement)
	_expect(view.map_pan != Vector2.ZERO and view.map_zoom == 2.0, "ordinary active refresh keeps viewport")
	view.set_game_data(definition.board, [], 0, definition)
	_expect(view.map_pan == Vector2.ZERO and view.map_zoom == 1.0, "active map replacement resets viewport")
	view.pan_by(Vector2(10000, -5000))
	var changed_geometry := definition.duplicate(true)
	changed_geometry.board[0].x += 500
	view.set_game_data(changed_geometry.board, [], 0, changed_geometry)
	_expect(view.map_pan == Vector2.ZERO, "same identity with replaced coordinates resets viewport")
	view.queue_free()

func _test_legacy_perimeter() -> void:
	var board: Array = []
	for index in range(40):
		board.append({"index": index, "kind": "rest", "name": "測試 %02d" % (index + 1), "owner": -1})
	var view = BoardView.new()
	view.size = Vector2(520.0, 420.0)
	root.add_child(view)
	view.set_game_data(board, [], 0)
	await process_frame
	_expect(view.board_mode() == "legacy", "board without coordinates keeps legacy mode")
	_expect(view.get_screen_position_for_index(0) != Vector2.ZERO, "legacy perimeter remains selectable")
	view.queue_free()

func _test_catalog_fallback(ui: Control) -> void:
	ui._load_map_catalog("user://map-ui-catalog-does-not-exist.json")
	_expect(not bool(ui._map_catalog_ok), "missing catalog enters explicit fallback")
	_expect(ui._map_catalog.size() == 1, "missing catalog exposes one test board")
	_expect(str(ui.map_selector.get_item_text(0)).contains("測試棋盤"), "fallback selector names test board")
	_expect(str(ui.map_catalog_status_label.text).contains("測試棋盤"), "fallback status is visible")
	ui._new_game(19, 2, ui._selected_map_definition)
	var fallback_board: Array = ui._selected_map_definition.get("board", [])
	var state_board: Array = ui.state.get("board", [])
	_expect(fallback_board.size() == 40 and state_board.size() == 40, "missing catalog fallback starts the canonical 40 tile board")
	if fallback_board.size() > 25 and state_board.size() > 25:
		_expect(fallback_board[1].get("name", "") == state_board[1].get("name", "") and int(fallback_board[1].get("cost", 0)) == int(state_board[1].get("cost", 0)) and fallback_board[25].get("name", "") == state_board[25].get("name", "") and int(fallback_board[25].get("cost", 0)) == int(state_board[25].get("cost", 0)), "fallback names and prices match the legacy state board")

func _test_catalog_selection_and_map8(ui: Control, raw_fixture: Dictionary) -> void:
	var map_one := raw_fixture.duplicate(true)
	var map_eight_with_housing := raw_fixture.duplicate(true)
	map_eight_with_housing["map_number"] = 8
	var payload := {"schema": "richman4.map-catalog/v1", "version": 1, "count": 2, "maps": [map_one, map_eight_with_housing]}
	var path := "user://map-ui-catalog.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	ui._load_map_catalog(path)
	_expect(bool(ui._map_catalog_ok), "catalog file loads through UI")
	_expect(ui._map_catalog.size() == 2, "catalog exposes both map choices")
	ui._on_map_selected(1)
	_expect(str(ui._selected_map_definition.get("id", "")) == "Game:8", "map eight identity is preserved")
	_expect(bool(ui._selected_map_definition.get("supports_new_game", false)), "map eight with housing is playable")
	_expect(not ui.new_game_confirm_button.disabled, "map eight with housing enables new game")
	_expect(str(ui.map_preview_status_label.text).contains("可開始新局"), "playable map preview explains start availability")

	var map_eight_without_housing := raw_fixture.duplicate(true)
	map_eight_without_housing["map_number"] = 8
	map_eight_without_housing["lands"] = []
	var unsupported_nodes: Array = map_eight_without_housing["nodes"]
	for node_index in [2, 3]:
		unsupported_nodes[node_index]["type_and_idx"] = 4001
	map_eight_without_housing["nodes"] = unsupported_nodes
	payload = {"schema": "richman4.map-catalog/v1", "version": 1, "count": 2, "maps": [map_one, map_eight_without_housing]}
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	ui._load_map_catalog(path)
	_expect(bool(ui._map_catalog_ok), "catalog accepts map eight without housing")
	ui._on_map_selected(1)
	_expect(str(ui._selected_map_definition.get("id", "")) == "Game:8", "unsupported map eight identity is preserved")
	_expect(not bool(ui._selected_map_definition.get("supports_new_game", true)), "map eight without housing is preview only")
	_expect(ui.new_game_confirm_button.disabled, "map without housing disables new game")
	_expect(str(ui.map_preview_status_label.text).contains("僅供預覽"), "unsupported map preview explains restriction")
	ui._new_game(23, 2, ui._map_catalog[0])
	var before_state: Dictionary = ui.state.duplicate(true)
	var before_active: Dictionary = ui._active_map_definition.duplicate(true)
	ui._new_game()
	_expect(ui.state == before_state and ui._active_map_definition == before_active, "direct new game keeps the current game when the selected map is preview only")
	ui._on_end_restart_pressed()
	_expect(ui.state == before_state and ui._active_map_definition == before_active, "restart keeps the current game when the selected map is preview only")
	var broken_definition: Dictionary = ui._map_catalog[0].duplicate(true)
	broken_definition["id"] = "test:broken"
	broken_definition["board"] = []
	ui._new_game(29, 2, broken_definition)
	_expect(ui.state == before_state and ui._active_map_definition == before_active, "failed graph constructor does not fall back to a legacy game")
	ui._on_map_selected(0)
	_expect(not ui.new_game_confirm_button.disabled, "playable map enables new game")
	DirAccess.remove_absolute(path)

func _test_route_controls_and_ai_guard(ui: Control, definition: Dictionary) -> void:
	var human := {"id": 0, "name": "玩家 1", "is_human": true, "is_ai": false, "alive": true, "bankrupt": false, "position": 1, "properties": [], "cash": 15000, "deposit": 0, "cards": []}
	var ai := human.duplicate(true)
	ai["id"] = 1
	ai["name"] = "玩家 2"
	ai["is_human"] = false
	ai["is_ai"] = true
	var route_state := {"phase": "await_route", "current_player": 0, "route_options": [2, 3], "remaining_steps": 2,
		"board": definition.board, "players": [human, ai], "event_log": [], "turn": 1, "round": 1,
		"seed": 7, "market": {"open": true, "prices": {}}, "winner": -1}
	var human_stub := RouteStub.new(route_state)
	ui.game_state = human_stub
	ui._active_map_definition = definition
	ui._refresh_from_state()
	_expect(ui.action_hint_label.text == "請選擇行進方向", "route phase action hint is understandable")
	_expect(ui.route_options_box.get_child_count() == 2, "route phase renders text choices")
	ui._on_route_selected(2)
	_expect(human_stub.route_calls == [2], "legal text route choice reaches core")

	var ai_state: Dictionary = route_state.duplicate(true)
	ai_state["current_player"] = 1
	var ai_stub := RouteStub.new(ai_state)
	ui.game_state = ai_stub
	ui._refresh_from_state()
	_expect(ui.route_options_box.get_child_count() == 2, "AI route phase still renders guarded choices (actual=%d phase=%s options=%s)" % [ui.route_options_box.get_child_count(), str(ui.state.get("phase", "")), str(ui.state.get("route_options", []))])
	_expect(ui.route_options_box.get_child_count() > 0 and ui.route_options_box.get_child(0).disabled, "AI route choices are disabled")
	ui._on_route_selected(2)
	_expect(ai_stub.route_calls.is_empty(), "human route input cannot operate AI turn")

func _test_saved_map_identity(ui: Control, definition: Dictionary) -> void:
	ui._new_game(31, 2, definition)
	var validated_snapshot: Dictionary = ui.game_state.get_snapshot()
	var tampered_snapshot: Dictionary = validated_snapshot.duplicate(true)
	var tampered_identity: Dictionary = {"id": validated_snapshot.get("map_id", ""), "name": "偽造地圖", "source": validated_snapshot.get("map_source", {}), "board": [{"x": 999999, "y": 999999, "name": "偽造格位"}]}
	tampered_snapshot["map_identity"] = tampered_identity
	ui._active_map_definition = {}
	ui._adopt_map_from_snapshot(tampered_snapshot)
	var active_board: Array = ui._active_map_definition.get("board", [])
	var saved_board: Array = validated_snapshot.get("board", [])
	_expect(str(ui._active_map_definition.get("id", "")) == str(validated_snapshot.get("map_id", "")), "loaded map identity uses the validated core map id")
	_expect(str(ui._active_map_definition.get("name", "")) == str(validated_snapshot.get("map_name", "")), "tampered map identity cannot replace the validated core map name")
	_expect(active_board == saved_board, "tampered map identity cannot replace the validated core geometry")
	var other_source := definition.duplicate(true)
	other_source.source.payload_sha256 = "c".repeat(64)
	other_source.board[0].x = 999999
	ui._map_catalog = [other_source]
	ui._adopt_map_from_snapshot(validated_snapshot)
	_expect(ui._active_map_definition.board == saved_board, "same map id with changed catalog provenance cannot replace saved geometry")
	var core_script: Variant = load("res://game/core/game_state.gd")
	var legacy_snapshot: Dictionary = core_script.new_game(31, 2).get_snapshot()
	ui._adopt_map_from_snapshot(legacy_snapshot)
	_expect(ui._active_map_definition.id == "test:classic40", "identity-free v1 save clears original-map identity")
	_expect(ui._active_map_definition.board == legacy_snapshot.board, "identity-free v1 save restores actual legacy geometry")

func _test_invalid_seed_preserves_game(ui: Control) -> void:
	ui._new_game(17, 2, ui._selected_map_definition)
	var before_seed := int(ui.state.get("seed", 0))
	ui.seed_input.text = "-2147483649"
	ui._on_new_game_confirm()
	_expect(int(ui.state.get("seed", 0)) == before_seed, "out-of-range seed keeps current game")
	_expect(str(ui._local_log.back()).contains("Seed 必須"), "out-of-range seed shows input error")
