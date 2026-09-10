extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const BaseMap = preload("res://tests/fixtures/original_map_fixture.gd")

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
	_expect(shell.action_strip.get_parent() == shell.game_screen, "context actions live on the board screen")
	_expect(shell.roll_button.get_parent() == shell.action_strip and shell.roll_button.get_parent() != shell.hud_panel, "roll is a board-context action")
	_expect(shell.buy_button.get_parent() == shell.action_strip and shell.upgrade_button.get_parent() == shell.action_strip and shell.end_turn_button.get_parent() == shell.action_strip, "landing actions share the board context strip")
	for index in range(4):
		var key: String = ["cash", "property", "stock", "other"][index]
		var tab: Button = shell.tab_buttons[key]
		_expect(tab.position == Vector2(176.0, float(index) * 42.0), "HUD tab %s follows the right edge" % key)
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
	var before_pan: Vector2 = shell.board_host.get_child(0).map_pan if shell.board_host.get_child_count() > 0 and shell.board_host.get_child(0).get("map_pan") is Vector2 else Vector2.ZERO
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(100.0, 100.0)
	shell.minimap._gui_input(click)
	click.pressed = false
	shell.minimap._gui_input(click)
	_expect(game.to_json() == before_state, "minimap click does not mutate simulation")
	var view: Control = shell.board_host.get_child(0)
	if view.has_method("pan_by"):
		_expect(view.map_pan != before_pan, "minimap click pans the board view")


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
	_test_minimap_input(ui, shell, game)
	_test_stock_names(shell)
	ui.queue_free()
	await create_timer(0.15).timeout
	print("Main HUD checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
