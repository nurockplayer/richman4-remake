extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
const BaseMap = preload("res://tests/fixtures/original_map_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _human_game(ui: Control, seed_value: int) -> Object:
	var normalized: Dictionary = Maps.normalize_map(BaseMap.make())
	var definition: Dictionary = normalized.get("definition", {})
	var game := GameState.new_game_on_board(seed_value, 2, definition)
	game.state.phase = "await_roll"
	game.state.current_player = 0
	for player_id in range(2):
		game.set_player_ai(player_id, false)
		game.state.players[player_id].position = player_id
		game.state.players[player_id].previous_position = -1
	game._set_action_options(0)
	game._sync_state()
	ui.game_state = game
	ui._refresh_from_state()
	return game


func _write_snapshot(path: String, snapshot: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot))
	file.close()


func _remove_snapshot(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _start_movement(ui: Control, game: Object) -> void:
	var result: Dictionary = ui._invoke_game("roll")
	_expect(bool(result.get("ok", false)), "active presentation fixture rolls through the public UI path")
	ui._handle_result(result)
	_expect(ui._presentation_busy, "roll starts a real movement presentation")
	_expect(int(ui.state.players[0].position) == 0, "UI keeps the departure snapshot while movement is active")
	_expect(ui.load_button.disabled, "load control is disabled while movement is active")
	_expect(game != null and int(game.state.players[0].position) != 0, "core commits the post-action position before presentation")


func _test_movement_load_guard(ui: Control, load_path: String) -> void:
	var game := _human_game(ui, 1)
	_start_movement(ui, game)
	var before_core: String = game.to_json()
	var before_ui: Dictionary = ui.state.duplicate(true)
	ui._load_game_from_path(load_path)
	_expect(game.to_json() == before_core, "load during movement leaves the active core unchanged")
	_expect(ui.state == before_ui, "load during movement leaves the departure UI snapshot unchanged")
	_expect(ui._presentation_busy, "blocked load preserves the movement presentation lock")
	_expect(not ui.legacy_save_dialog.visible, "blocked load does not open a legacy choice modal")
	ui._cancel_presentation()
	ui._refresh_from_state()


func _test_news_and_fate_load_guards(ui: Control, load_path: String) -> void:
	var game := _human_game(ui, 61202)
	for presentation in [ui.news_popup, ui.fate_popup]:
		var before_core: String = game.to_json()
		var before_ui: Dictionary = ui.state.duplicate(true)
		presentation.show()
		ui._update_actions(str(ui.state.get("phase", "")), int(ui.state.get("current_player", 0)))
		_expect(ui.load_button.disabled, "%s disables load while visible" % presentation.name)
		ui._load_game_from_path(load_path)
		_expect(game.to_json() == before_core, "%s load leaves the current core unchanged" % presentation.name)
		_expect(ui.state == before_ui, "%s load leaves the current UI snapshot unchanged" % presentation.name)
		_expect(presentation.visible, "%s remains visible after blocked load" % presentation.name)
		presentation.hide()


func _run() -> void:
	var ui: Control = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var valid_game := GameState.new_game(61200, 2)
	var valid_snapshot: Dictionary = valid_game.to_dict()
	_expect(GameState.validate_save(valid_snapshot).get("ok", false), "active presentation load fixture is a valid public save")
	var load_path := "user://issue110-active-presentation.json"
	_write_snapshot(load_path, valid_snapshot)
	_test_movement_load_guard(ui, load_path)
	_test_news_and_fate_load_guards(ui, load_path)
	_remove_snapshot(load_path)
	ui.queue_free()
	await create_timer(0.15).timeout
	print("Active presentation load checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
