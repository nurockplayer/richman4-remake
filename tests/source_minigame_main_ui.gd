extends SceneTree

## MainUI gates save/load during a pending minigame and reopens them in the
## same refresh that returns the result.

const Core = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
const MainScene = preload("res://game/main.tscn")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _definition() -> Dictionary:
	var raw: Dictionary = Fixture.make()
	for entry in [[1, 6], [2, 7], [4, 8]]:
		var node: Dictionary = raw.nodes[int(entry[0])]
		node.merge({
			"kind": "unsupported",
			"type_and_idx": 0,
			"event_code": int(entry[1]),
			"source_status_bits": int(entry[1]),
		}, true)
	var normalized: Dictionary = Maps.normalize_map(raw, false)
	return normalized.definition if bool(normalized.get("ok", false)) else {}


func _run() -> void:
	var definition := _definition()
	if definition.is_empty():
		print("PRECONDITION_UNMET synthetic source minigame fixture")
		quit(2)
		return
	var ui = MainScene.instantiate()
	root.add_child(ui)
	ui.set_process(false)
	if ui.audio_controller != null:
		ui.audio_controller.call("stop")
	var game: Object = Core.new_game_on_board(3201, 2, definition, {})
	for player in game.state.players:
		game.set_player_ai(int(player.id), int(player.id) != 0)
	var node := -1
	for index in range(game.state.board.size()):
		if int(game.state.board[index].get("event_code", 0)) == 7 and int(game.state.board[index].get("type_and_idx", -1)) == 0:
			node = index
	game.state.current_player = 0
	game.state.players[0].position = node
	game.state.phase = "await_action"
	game.configure_minigames(true)
	game._resolve_landing(0)
	ui.game_state = game
	ui._refresh_from_state()
	var controller: Control = ui.source_minigame_controller
	_expect(controller != null and controller.is_open(), "pending human minigame opens the controller")
	_expect(ui.load_button.disabled, "load is gated while the minigame is pending")
	_expect(not ui._source_save_operation_allowed(), "save is gated while the minigame is pending")
	var encounter_id := int(game.minigame_snapshot().get("encounter_id", -1))
	for _tick in range(420):
		game.minigame_tick(encounter_id)
	var result: Dictionary = ui._invoke_game("finish_minigame", [encounter_id])
	_expect(bool(result.get("ok", false)), "finish_minigame passes the MainUI modal gate")
	ui._handle_result(result)
	_expect(str(game.state.phase) == "await_action", "core returns to ordinary actions")
	_expect(not controller.is_open(), "returned minigame releases the controller")
	_expect(not ui.load_button.disabled, "load reopens in the returning refresh")
	_expect(ui._source_save_operation_allowed(), "save reopens in the returning refresh")
	var shell_buttons: Dictionary = ui.source_shell.get("toolbar_buttons") if ui.source_shell != null else {}
	if shell_buttons.has("save"):
		_expect(not (shell_buttons["save"] as Button).disabled, "source save toolbar reopens in the returning refresh")
	if shell_buttons.has("load"):
		_expect(not (shell_buttons["load"] as Button).disabled, "source load toolbar reopens in the returning refresh")
	print("Source minigame MainUI checks: %d, failures: %d" % [checks, failures])
	ui.queue_free()
	quit(1 if failures else 0)
