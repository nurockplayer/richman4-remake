extends SceneTree
## MainUI presents a pending human prison/hospital entrance as a bail choice.
const MainScene = preload("res://game/main.tscn")
const Fixture = preload("res://tests/fixtures/status_fixture.gd")
const SERVICE_NODE := 1
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
	definition.board[SERVICE_NODE].merge({"kind": "unsupported", "event_code": 4, "source_status_bits": 4, "name": "監獄入口（待還原）"}, true)
	definition.board[SERVICE_NODE].erase("points")
	var options: Dictionary = ui._default_setup_options(4, definition)
	expect(ui._new_game(42, 4, definition, options), "status-capable UI new game starts")
	var game: Object = ui.game_state
	game.state.god_objects = []
	game._admit_player_status(2, "prison", 3)
	game.state.current_player = 0
	game.state.players[0].position = SERVICE_NODE
	game.state.players[0].points = 100
	game._graph_visit_tile(0, game.state.board[SERVICE_NODE], true)
	expect(game.state.phase == "await_status_service", "human landing waits for the bail choice")
	ui._refresh_from_state()
	await process_frame
	expect(ui.status_service_popup.visible, "the bail service is shown")
	expect(ui.status_service_buttons.size() == 1 and not ui.status_service_buttons[0].disabled, "one enabled row per jailed player")
	expect(str(ui.status_service_buttons[0].text).contains("30"), "the row names the price")
	ui.status_service_popup.hide()
	await process_frame
	await process_frame
	expect(ui.status_service_popup.visible, "hiding re-opens the service")
	ui.status_service_buttons[0].pressed.emit()
	await process_frame
	expect(ui.status_service_confirm_row.visible and ui.status_service_popup.visible, "choosing a row asks for confirmation inside the service window")
	ui.status_service_confirm_ok.pressed.emit()
	await process_frame
	expect(game.state.phase == "await_action" and int(game.state.players[2].get("prison_days", 0)) == 128 and int(game.state.players[0].points) == 70 and not ui.status_service_popup.visible, "confirming bails the player and closes the service")
	ui.queue_free()
	await process_frame
	print("Status service UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
