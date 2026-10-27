extends SceneTree
## MainUI presents a pending human magic house as a twelve-spell choice.
const MainScene = preload("res://game/main.tscn")
const Fixture = preload("res://tests/fixtures/status_fixture.gd")
const MAGIC_NODE := 1
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func run() -> void:
	if OS.get_environment("RICHMAN4_USER_ROOT").is_empty():
		push_error("RICHMAN4_USER_ROOT must point at a throwaway directory.")
		quit(2)
		return
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var definition: Dictionary = Fixture.definition()
	definition.board[MAGIC_NODE].merge({"kind": "unsupported", "event_code": 16, "source_status_bits": 16, "name": "魔法屋（待還原）"}, true)
	definition.board[MAGIC_NODE].erase("points")
	var options: Dictionary = ui._default_setup_options(4, definition)
	expect(ui._new_game(42, 4, definition, options), "status-capable UI new game starts")
	var game: Object = ui.game_state
	game.state.god_objects = []
	game.state.current_player = 0
	game.state.players[0].position = MAGIC_NODE
	game._graph_visit_tile(0, game.state.board[MAGIC_NODE], true)
	expect(game.state.phase == "await_magic_house", "human landing waits for a spell")
	ui._refresh_from_state()
	await process_frame
	expect(ui.magic_house_popup.visible, "the magic house choice is shown")
	expect(ui.magic_house_buttons.size() == 12 and ui.magic_house_buttons[11].disabled and not ui.magic_house_buttons[4].disabled, "twelve spells; unrestored ones are disabled")
	expect(str(ui.magic_house_prompt_label.text).contains("抽中"), "the prompt names the drawn group")
	ui.magic_house_popup.hide()
	await process_frame
	await process_frame
	expect(ui.magic_house_popup.visible, "hiding the choice re-opens it: the source has no decline")
	var before := JSON.stringify(game.state.players.map(func(p: Dictionary) -> int: return int(p.get("cash", 0)) + int(p.get("deposit", 0))))
	ui.magic_house_buttons[4].pressed.emit()
	await process_frame
	expect(game.state.phase == "await_action" and not ui.magic_house_popup.visible, "choosing a spell resolves the visit and closes the choice")
	expect(JSON.stringify(game.state.players.map(func(p: Dictionary) -> int: return int(p.get("cash", 0)) + int(p.get("deposit", 0)))) == before, "the deposit spell moves cash into deposits without creating money")
	ui.queue_free()
	await process_frame
	print("Magic house UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
