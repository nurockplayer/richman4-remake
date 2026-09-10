extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const BaseMap = preload("res://tests/fixtures/original_map_fixture.gd")
const CompanyFixture = preload("res://tests/fixtures/company_fixture.gd")
const OriginalGods = preload("res://game/content/original_gods.gd")

const SOURCE_HUD_DATA_LEFT := 46.0
const SOURCE_HUD_DATA_RIGHT := 174.0
const SOURCE_HUD_DATA_TOP := 76.0
const SOURCE_HUD_DATA_BOTTOM := 264.0

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _source_assets_available(shell: Control) -> bool:
	return shell.get("_source_title_texture") != null


func _set_human_graph_game(ui: Control) -> Object:
	var normalized: Dictionary = Maps.normalize_map(BaseMap.make())
	_expect(bool(normalized.get("ok", false)), "HUD fixture map normalizes")
	var definition: Dictionary = normalized.get("definition", {})
	ui._set_development_path(true)
	var started: bool = ui._new_game(2301, 2, definition)
	_expect(started, "HUD fixture starts through the existing new-game path")
	var game: Object = ui.game_state
	for player_id in range(2):
		game.set_player_ai(player_id, false)
		game.state.players[player_id].position = 0
		game.state.players[player_id].previous_position = -1
	game.state.current_player = 0
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	return game


func _test_title_and_layout(ui: Control, shell: Control) -> void:
	_expect(shell.is_title_visible(), "normal launch keeps the source title visible")
	_expect(shell.title_screen.visible and not shell.game_screen.visible, "title and board screens are mutually exclusive")
	_expect(shell.reference_canvas.size == Vector2(640.0, 480.0), "source shell owns a 640x480 reference canvas")
	_expect(is_equal_approx(shell.reference_canvas.scale.x, shell.reference_canvas.scale.y), "reference canvas uses uniform scaling")
	_expect(shell.board_host.position == Vector2(0.0, 40.0) and shell.board_host.size == Vector2(440.0, 440.0), "board host matches source crop")
	_expect(shell.hud_panel.position == Vector2(440.0, 0.0) and shell.hud_panel.size == Vector2(200.0, 280.0), "HUD panel matches source bounds")
	_expect(shell.calendar_panel.position == Vector2(440.0, 280.0) and shell.calendar_panel.size == Vector2(200.0, 200.0), "calendar panel matches source bounds")
	var source_keys := ["help", "options", "ai", "load", "save", "map", "inspect", "tools", "cards", "sale", "stocks"]
	for index in range(source_keys.size()):
		var key: String = source_keys[index]
		var button: Button = shell.toolbar_buttons.get(key)
		_expect(button != null and int(button.get_meta("source_chunk", -1)) == index + 1, "toolbar keeps source chunk order for %s" % key)
		_expect(button != null and button.position == Vector2(float(index) * 40.0, 0.0), "toolbar hit area is source aligned for %s" % key)
	if _source_assets_available(shell):
		_expect(shell._title_art.texture != null, "source title composite is loaded")
		_expect(shell._hud_art.texture != null, "source HUD frame is loaded")
		_expect(shell._calendar_art.texture != null, "source calendar frame is loaded for a dated game")
		for key in source_keys:
			_expect(shell.toolbar_buttons[key].icon != null, "source toolbar icon is loaded for %s" % key)
		shell.title_start_button.mouse_entered.emit()
		_expect(shell.title_start_button.icon != null, "START hover uses the source hover frame")
		shell.title_start_button.mouse_exited.emit()
		_expect(shell.title_start_button.icon == null, "START hover frame clears on exit")


func _test_title_ai_guard(ui: Control, game: Object, shell: Control) -> void:
	game.state.current_player = 1
	game.state.players[1].is_human = false
	game.state.players[1].is_ai = true
	game.state.phase = "await_roll"
	game._set_action_options(1)
	game._sync_state()
	ui._ai_pending = false
	ui._process(0.0)
	_expect(not ui._ai_pending, "title screen blocks AI scheduling")


func _test_hud_tabs_and_actions(ui: Control, shell: Control, game: Object) -> void:
	game.state.current_player = 0
	game.state.players[0].is_human = true
	game.state.players[0].is_ai = false
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	_expect(not shell.is_title_visible(), "new game enters the source board screen")
	for key in ["help", "options", "ai", "tools", "cards", "sale"]:
		var pending_control: Button = shell.toolbar_buttons.get(key) as Button
		_expect(pending_control != null and pending_control.visible and pending_control.disabled, "source %s command stays visibly pending" % key)
	_expect(shell.title_option_button.disabled, "source title options stays visibly pending")
	_expect(shell.action_strip.get_parent() == shell.game_screen, "context actions live on the board screen")
	_expect(shell.roll_button.get_parent() == shell.action_strip and shell.roll_button.get_parent() != shell.hud_panel, "roll is a board-context action")
	_expect(shell.buy_button.get_parent() == shell.action_strip and shell.upgrade_button.get_parent() == shell.action_strip and shell.end_turn_button.get_parent() == shell.action_strip, "landing actions share the board context strip")
	_expect(shell.action_strip.find_child("ActionBackground", false, false) == null, "source actions do not mount a permanent navy scaffold")
	for index in range(4):
		var key: String = ["cash", "property", "stock", "other"][index]
		var tab: Button = shell.tab_buttons[key]
		_expect(tab.position == Vector2(176.0, float(index) * 70.0), "HUD tab %s follows the source interval" % key)
		_expect(tab.size == Vector2(24.0, 70.0), "HUD tab %s keeps a distinct source hit area" % key)
		_expect(tab.text == ["資\n金", "地\n產", "股\n票", "其\n他"][index], "HUD tab %s renders both source label characters" % key)
	if _source_assets_available(shell):
		_expect(shell.cash_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "source cash is right aligned beside the source icon")
		_expect(shell.deposit_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and shell.wealth_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "source deposit and wealth are right aligned")
		_expect(shell.cash_label.position == Vector2(66.0, 96.0), "source cash value uses the source value row")
		_expect(shell.cash_label.get_theme_color("font_color").v < 0.35, "source cash value uses dark ink on the pale panel")
		_expect(str(shell.cash_label.text).begins_with("$"), "source cash value keeps visible dollar formatting")
	var before_tabs: String = game.to_json()
	for key in ["property", "stock", "other", "cash"]:
		shell.select_tab(key)
		_expect(shell.active_tab == key, "HUD tab selection updates presentation state for %s" % key)
		_expect(game.to_json() == before_tabs, "HUD tab selection does not mutate simulation for %s" % key)
	var before_calendar: String = game.to_json()
	shell.toggle_map_view()
	_expect(shell.minimap.visible and not shell.calendar_panel.visible, "calendar toggle exposes the minimap")
	_expect(game.to_json() == before_calendar, "calendar toggle does not mutate simulation")
	shell.toggle_map_view()
	_expect(shell.calendar_panel.visible and not shell.minimap.visible, "calendar toggle returns to the dated panel")
	_expect(not shell.buy_button.visible and not shell.upgrade_button.visible and not shell.end_turn_button.visible, "non-landing source turn hides unrelated actions")
	_expect(shell.roll_button.visible and shell.roll_button.text == "GO", "await-roll source turn exposes the bounded GO control")
	game.state.phase = "await_action"
	game.state.action_options = ["buy", "end_turn"]
	game._sync_state()
	ui._refresh_from_state()
	_expect(not shell.roll_button.visible and shell.buy_button.visible and shell.buy_button.text == "YES", "landing source turn exposes only the purchase YES control")
	_expect(shell.end_turn_button.visible and shell.end_turn_button.text == "NO", "landing source turn exposes the decline NO control")
	_expect(not shell.upgrade_button.visible, "landing source turn hides the unrelated upgrade control")
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()


func _test_source_purchase_offer(ui: Control, shell: Control, game: Object) -> void:
	game.state.current_player = 0
	game.state.players[0].position = 2
	game.state.players[0].previous_position = 0
	game.state.players[0].cash = 2000
	game.state.property_action_used = false
	game.state.phase = "await_action"
	game._set_action_options(0)
	game._sync_state()
	var before_purchase_refresh: String = game.to_json()
	ui._refresh_from_state()
	var purchase_hint := str(shell.action_hint_label.text)
	_expect(purchase_hint.contains("測試路"), "source landing purchase offer names the current property")
	_expect(purchase_hint.contains("$1,000"), "source landing purchase offer uses the authoritative property price")
	_expect(purchase_hint.contains("YES") and purchase_hint.contains("NO"), "source landing purchase offer exposes confirm and decline controls")
	_expect(game.to_json() == before_purchase_refresh, "source landing purchase refresh does not mutate simulation state")

	game.state.board[2].owner = 0
	game.state.players[0].properties = [2]
	game.state.players[0].cash = 500
	game.state.property_action_used = false
	game._set_action_options(0)
	game._sync_state()
	var before_upgrade_refresh: String = game.to_json()
	ui._refresh_from_state()
	var upgrade_hint := str(shell.action_hint_label.text)
	_expect(upgrade_hint.contains("升級"), "source owned-property offer names the upgrade action")
	_expect(upgrade_hint.contains("$300"), "source owned-property offer uses the authoritative upgrade price")
	_expect(upgrade_hint.contains("YES") and upgrade_hint.contains("NO"), "source owned-property offer exposes confirm and decline controls")
	_expect(game.to_json() == before_upgrade_refresh, "source owned-property refresh does not mutate simulation state")
	game.state.phase = "await_roll"
	game.state.players[0].position = 0
	game.state.players[0].previous_position = -1
	game.state.board[2].owner = -1
	game.state.players[0].properties = []
	game.state.players[0].cash = 100000
	game.state.property_action_used = false
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()


func _test_source_hud_detail_values(ui: Control, shell: Control, game: Object) -> void:
	var before: String = game.to_json()
	var snapshot: Dictionary = game.get_snapshot().duplicate(true)
	var player: Dictionary = snapshot.players[0]
	player.properties = [2, 3]
	player.stocks = {"s01": 3}
	player.god_id = 1
	player.hospital_days = 2
	player.insurance_status = 3
	player.alliance = {"partner_id": 1, "turns": 4}
	snapshot.board[2].name = "東區大街"
	snapshot.board[2].building_level = 2
	snapshot.board[3].name = "西區大街"
	snapshot.board[3].building_level = 1
	snapshot.god_objects = [{"id": 1, "owner": 0, "days": 5}]
	snapshot.market = {"rows": {"s01": {"name": "來源企業", "price": 123.45}}}
	shell.sync_snapshot(snapshot, {}, 9999)
	shell.select_tab("property")
	_expect(shell.property_label.text.contains("東區大街 Lv2"), "source property HUD lists the first property name and level")
	_expect(shell.property_label.text.contains("西區大街 Lv1"), "source property HUD lists the second property name and level")
	shell.select_tab("stock")
	_expect(shell.stock_label.text.contains("來源企業 × 3"), "source stock HUD lists the display name and holding")
	_expect(shell.stock_label.text.contains("$123.45"), "source stock HUD lists the authoritative current price")
	shell.select_tab("other")
	_expect(shell.other_label.text.contains(OriginalGods.name_for(1)), "source other HUD lists the attached god")
	_expect(shell.other_label.text.contains("5 天"), "source other HUD lists the attached god duration")
	_expect(shell.other_label.text.contains("住院 · 2 天"), "source other HUD lists the active status duration")
	_expect(shell.other_label.text.contains("保險 · 3 天"), "source other HUD lists an active insurance duration")
	_expect(shell.other_label.text.contains("同盟 · 剩餘 4 回合"), "source other HUD lists an active alliance duration")
	player.hospital_days = 0
	player.winter_sleep_days = 128
	player.insurance_status = 128
	player.alliance = {"partner_id": 1, "turns": 128}
	shell.sync_snapshot(snapshot, {}, 9999)
	shell.select_tab("other")
	_expect(shell.other_label.text.contains("待醒來"), "source other HUD uses sleep presentation copy for the 128 sentinel")
	_expect(shell.other_label.text.contains("保險 · 到期當日仍有效"), "source other HUD explains the insurance 128 sentinel")
	_expect(shell.other_label.text.contains("同盟 · 下回合到期"), "source other HUD explains the alliance 128 sentinel")
	var sentinel_inspector: String = str(shell._player_inspection_text(0))
	_expect(sentinel_inspector.contains("待醒來") and sentinel_inspector.contains("保險 · 到期當日仍有效") and sentinel_inspector.contains("同盟 · 下回合到期"), "player inspector shares the sentinel status presentation")
	_test_source_hud_data_geometry(shell)
	_expect(game.to_json() == before, "source HUD detail rendering leaves the live game object untouched")
	ui._refresh_from_state()


func _test_source_hud_data_geometry(shell: Control) -> void:
	var labels := {
		"property": shell.property_label,
		"stock": shell.stock_label,
		"other": shell.other_label,
	}
	for key in labels:
		shell.select_tab(str(key))
		var label: Label = labels[key]
		var rect := Rect2(label.position, label.size)
		var source_safe := rect.position.x >= SOURCE_HUD_DATA_LEFT and rect.position.x + rect.size.x <= SOURCE_HUD_DATA_RIGHT and rect.position.y >= SOURCE_HUD_DATA_TOP and rect.position.y + rect.size.y <= SOURCE_HUD_DATA_BOTTOM and not label.clip_text
		_expect(label.visible and source_safe and not str(label.text).is_empty(), "source %s data label stays inside the icon-free readable area without clipping" % key)


func _test_source_full_map_and_player_inspect(ui: Control, shell: Control, game: Object) -> void:
	var before_map: String = game.to_json()
	var map_button: Button = shell.toolbar_buttons.get("map") as Button
	var calendar_visible: bool = shell.calendar_panel.visible
	map_button.pressed.emit()
	await process_frame
	_expect(shell.is_full_map_visible(), "source map command opens the full-map view")
	_expect(shell.full_map_view.visible and shell.full_map_view.size == Vector2(440.0, 440.0), "full-map view occupies the source board region")
	_expect(shell.calendar_panel.visible == calendar_visible and not shell.minimap.visible, "full-map command does not reduce to the calendar minimap toggle")
	var full_map_points: Array = shell.full_map_view.call("_board_points")
	_expect(full_map_points.size() == game.state.board.size(), "full-map view projects every board node")
	_expect(game.to_json() == before_map, "full-map command does not mutate simulation state")
	map_button.pressed.emit()
	await process_frame
	_expect(not shell.is_full_map_visible() and not shell.full_map_view.visible, "source map command closes the full-map view")

	var before_inspect: String = game.to_json()
	var inspect_button: Button = shell.toolbar_buttons.get("inspect") as Button
	inspect_button.pressed.emit()
	await process_frame
	_expect(shell.is_player_inspector_visible(), "source inspect command opens the player inspector")
	_expect(shell.player_inspect_buttons.get_child_count() == game.state.players.size(), "player inspector exposes every player from the snapshot")
	_expect(shell.player_inspect_detail.text.contains(str(game.state.players[0].name)), "player inspector starts on the current player")
	var other_button: Button = shell.player_inspect_buttons.get_child(1) as Button if shell.player_inspect_buttons.get_child_count() > 1 else null
	if other_button != null:
		other_button.pressed.emit()
		_expect(shell.player_inspect_detail.text.contains(str(game.state.players[1].name)), "player inspector selects another player from the existing snapshot")
	_expect(game.to_json() == before_inspect, "player inspection and selection do not mutate simulation state")
	_expect(ui._source_modal_open(), "player inspector blocks simulation shortcuts while open")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	ui._unhandled_input(space)
	_expect(game.to_json() == before_inspect, "player inspector blocks a queued roll shortcut")
	shell.close_player_inspector()
	await process_frame
	_expect(not shell.is_player_inspector_visible(), "player inspector closes through its presentation API")


func _test_settlement_overlay_input(ui: Control, shell: Control) -> void:
	var game: Object = ui.game_state
	if game == null:
		_expect(false, "settlement overlay has a live game fixture")
		return
	game.state.phase = "game_over"
	game.state.winner = 0
	game._sync_state()
	var before: String = game.to_json()
	ui._refresh_from_state()
	await process_frame
	var close: Button = ui.end_overlay.find_child("SettlementClose", true, false) as Button
	var restart: Button = ui.end_overlay.find_child("SettlementRestart", true, false) as Button
	_expect(ui.end_overlay.visible and ui.end_overlay.z_index > shell.z_index and ui.end_overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "settlement overlay renders above and captures input over the source shell")
	_expect(close != null and close.visible and not close.disabled, "settlement overlay exposes a usable return control")
	_expect(restart != null and restart.visible and not restart.disabled, "settlement overlay exposes a usable restart control")
	if close != null:
		close.pressed.emit()
		await process_frame
	_expect(not ui.end_overlay.visible, "settlement return control receives input above the source shell")
	_expect(game.to_json() == before, "settlement return control does not mutate simulation state")


func _test_stock_names(shell: Control) -> void:
	var stock_snapshot := {
		"current_player": 0,
		"date": {"year": 1998, "month": 6, "day": 2},
		"players": [{"name": "玩家", "cash": 100, "deposit": 200, "stocks": {"s01": 3}, "properties": [], "property_values": 0, "cards": [], "tools": {}, "points": 0}],
		"market": {"rows": {"s01": {"name": "來源企業"}}},
	}
	shell.sync_snapshot(stock_snapshot, {}, 300)
	shell.select_tab("stock")
	_expect(str(shell.stock_label.text).contains("來源企業"), "stock HUD uses the source display name")


func _test_minimap_input(ui: Control, shell: Control, game: Object) -> void:
	var before_state: String = game.to_json()
	shell.toggle_map_view()
	var view: Control = shell.board_host.get_child(0)
	var points: Array[Vector2] = shell.minimap.call("_board_points")
	var target_index: int = mini(2, points.size() - 1)
	var before_pan: Vector2 = view.map_pan if view.get("map_pan") is Vector2 else Vector2.ZERO
	var before_refresh := int(shell.minimap.get("_refresh_serial"))
	var before_polygon: Array = shell.minimap.call("_viewport_polygon")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = points[target_index] if target_index >= 0 else Vector2(100.0, 100.0)
	shell.minimap._gui_input(click)
	click.pressed = false
	shell.minimap._gui_input(click)
	_expect(game.to_json() == before_state, "minimap click does not mutate simulation")
	_expect(int(shell.minimap.get("_refresh_serial")) > before_refresh, "camera-only minimap selection requests a viewport redraw")
	var after_polygon: Array = shell.minimap.call("_viewport_polygon")
	_expect(after_polygon != before_polygon, "minimap viewport outline follows the changed board camera")
	if view.has_method("pan_by"):
		_expect(view.map_pan != before_pan, "minimap click pans the board view")
	if target_index >= 0 and view.has_method("get_screen_position_for_index"):
		var focused_position: Vector2 = view.call("get_screen_position_for_index", target_index)
		_expect(focused_position.distance_to(view.size * 0.5) < 1.5, "minimap node selection centers the board camera once")
	shell.toggle_map_view()


func _test_source_roll_presentation_gate(ui: Control, shell: Control) -> void:
	var normalized: Dictionary = Maps.normalize_map(BaseMap.make())
	var definition: Dictionary = normalized.get("definition", {})
	var started: bool = ui._new_game(1, 2, definition)
	_expect(started, "source roll fixture starts through the public new-game path")
	ui.set_process(false)
	ui.board_view.set_process(false)
	var game: Object = ui.game_state
	for player_id in range(2):
		game.set_player_ai(player_id, false)
		game.state.players[player_id].position = 0
		game.state.players[player_id].previous_position = -1
	game.state.current_player = 0
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	var source_load: Button = shell.toolbar_buttons.get("load") as Button
	_expect(shell.roll_button.visible and not shell.roll_button.disabled, "visible source roll is enabled before the turn")
	_expect(source_load != null and not source_load.disabled, "visible source load is enabled before movement")
	_expect(not shell.title_load_button.disabled, "source title load follows the open load gate")
	shell.roll_button.pressed.emit()
	_expect(ui.get("_presentation_busy") == true, "source roll starts the movement presentation")
	_expect(shell.action_strip.visible, "source GO remains visible as the active movement gate")
	_expect(shell.roll_button.visible and shell.roll_button.disabled, "visible source roll is disabled during movement")
	_expect(source_load != null and source_load.disabled, "visible source load is disabled during movement")
	_expect(ui.load_button.disabled, "legacy load adapter shares the movement gate")
	_expect(shell.title_load_button.disabled, "source title load shares the movement gate")
	var board: Node = ui.board_view
	if board.has_method("_advance_movement"):
		board._advance_movement(100.0)
	_expect(ui.get("_presentation_busy") == false, "source movement finish clears the presentation lock")
	_expect(source_load != null and not source_load.disabled, "visible source load re-enables after movement")
	_expect(not shell.roll_button.visible, "source GO hides once the turn awaits a route")
	_expect(shell.route_buttons.visible and shell.route_buttons.get_child_count() > 0, "visible source route choices appear after movement")
	if shell.route_buttons.get_child_count() > 0:
		var route: Button = shell.route_buttons.get_child(0) as Button
		_expect(route.visible and not route.disabled, "visible source route choice is enabled after movement")


func _test_source_stock_modal_gate(ui: Control, shell: Control) -> void:
	var definition: Dictionary = CompanyFixture.definition()
	var started: bool = ui._new_game(90101, 4, definition)
	_expect(started, "source stock fixture starts through the public new-game path")
	ui.set_process(false)
	ui.board_view.set_process(false)
	var game: Object = ui.game_state
	game.state.current_player = 0
	game.state.phase = "await_action"
	game.state.players[0].is_human = true
	game.state.players[0].is_ai = false
	game.state.players[0].deposit = 1000
	game.state.players[0].stocks["s01"] = 0
	game.state.market.open = true
	game.state.market.closed_days = 0
	var row: Dictionary = game.state.market.rows.s01
	row.price = 100.0
	row.previous_price = 100.0
	row.turn_supply = 20
	row.market_supply = 5000
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	var source_stocks: Button = shell.toolbar_buttons.get("stocks") as Button
	_expect(source_stocks != null and source_stocks.visible and not source_stocks.disabled, "visible source stocks control is enabled before opening")
	var before_open: String = game.to_json()
	source_stocks.pressed.emit()
	await process_frame
	var panel: Control = ui.source_stock_panel
	_expect(panel != null and panel.visible, "source stocks control opens the source stock panel")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	ui._unhandled_input(space)
	var new_game_key := InputEventKey.new()
	new_game_key.keycode = KEY_N
	new_game_key.pressed = true
	ui._unhandled_input(new_game_key)
	ui._ai_pending = true
	ui._on_ai_timer_timeout()
	_expect(game.to_json() == before_open, "source stock panel blocks Space/N and queued AI mutation")
	_expect(not ui.new_game_popup.visible, "source stock panel keeps the legacy new-game popup closed")
	_expect(ui._ai_pending == false, "source stock panel drains a queued AI callback without acting")
	panel.call("close_panel")
	await process_frame
	_expect(not panel.visible, "source stock panel closes through its own EXIT control")
	source_stocks.pressed.emit()
	await process_frame
	panel.call("open_for", game.get_snapshot(), definition)
	panel.call("select_symbol", "s01")
	var buy: Button = panel.find_child("StockBuy", true, false) as Button
	_expect(buy != null and buy.visible and not buy.disabled, "source stock buy control is enabled for a selected share")
	if buy != null and not buy.disabled:
		buy.pressed.emit()
		await process_frame
		var buy_pad: Control = panel.find_child("SourceQuantityPad", true, false) as Control
		var buy_input: LineEdit = buy_pad.find_child("QuantityInput", true, false) as LineEdit if buy_pad != null else null
		if buy_input != null:
			buy_input.text = "1"
			buy_pad.find_child("QuantitySubmit", true, false).pressed.emit()
		await process_frame
	_expect(int(game.state.players[0].stocks.get("s01", 0)) == 1, "source stock buy reaches the existing choose_action path")
	_expect(int(game.state.players[0].deposit) == 900, "source stock buy uses the existing deposit accounting")
	panel.call("clear_selection")
	panel.call("select_symbol", "s01")
	var sell: Button = panel.find_child("StockSell", true, false) as Button
	_expect(sell != null and sell.visible and not sell.disabled, "source stock sell control is enabled after buying")
	if sell != null and not sell.disabled:
		sell.pressed.emit()
		await process_frame
		var sell_pad: Control = panel.find_child("SourceQuantityPad", true, false) as Control
		var sell_input: LineEdit = sell_pad.find_child("QuantityInput", true, false) as LineEdit if sell_pad != null else null
		if sell_input != null:
			sell_input.text = "1"
			sell_pad.find_child("QuantitySubmit", true, false).pressed.emit()
		await process_frame
	_expect(int(game.state.players[0].stocks.get("s01", 0)) == 0, "source stock sell reaches the existing choose_action path")
	_expect(int(game.state.players[0].deposit) == 1000, "source stock sell returns the existing deposit accounting")
	panel.call("close_panel")
	await process_frame
	_expect(not panel.visible, "source stock panel closes after the completed trade flow")


func _test_legacy_stock_source_route(ui: Control, shell: Control) -> void:
	var legacy: Object = GameState.new_game(204, 2)
	legacy.state.current_player = 0
	legacy.state.phase = "await_action"
	legacy._set_action_options(0)
	ui.game_state = legacy
	ui._active_map_definition = {}
	ui._refresh_from_state()
	var source_stocks: Button = shell.toolbar_buttons.get("stocks") as Button
	_expect(source_stocks != null and not source_stocks.disabled, "legacy source stocks control remains available")
	source_stocks.pressed.emit()
	_expect(ui.stocks_popup.visible and not ui.source_stock_panel.visible, "legacy source stocks stays on the legacy three-stock popup")
	ui.stocks_popup.hide()


func _run() -> void:
	var ui: Control = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	if ui.audio_controller != null:
		ui.audio_controller.call("stop")
	var shell: Control = ui.source_shell
	_test_title_and_layout(ui, shell)
	var game: Object = ui.game_state
	_test_title_ai_guard(ui, game, shell)
	game = _set_human_graph_game(ui)
	_test_hud_tabs_and_actions(ui, shell, game)
	_test_source_purchase_offer(ui, shell, game)
	_test_source_hud_detail_values(ui, shell, game)
	await _test_source_full_map_and_player_inspect(ui, shell, game)
	_test_minimap_input(ui, shell, game)
	_test_source_roll_presentation_gate(ui, shell)
	await _test_source_stock_modal_gate(ui, shell)
	_test_legacy_stock_source_route(ui, shell)
	_test_stock_names(shell)
	await _test_settlement_overlay_input(ui, shell)
	ui.queue_free()
	await create_timer(0.15).timeout
	print("Main HUD checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
