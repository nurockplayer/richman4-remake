extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
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

func _run() -> void:
	var ui: Control = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	if ui.audio_controller != null:
		ui.audio_controller.call("stop")

	var game: Object = GameState.new_game(192, 2)
	game.state.current_player = 0
	game.state.players[0].is_human = true
	game.state.players[0].is_ai = false
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui.game_state = game
	ui._refresh_from_state()
	await process_frame

	var before: String = game.to_json()
	var help_button: Button = ui.source_shell.toolbar_buttons.get("help")
	_expect(help_button != null and not help_button.disabled, "ordinary board Help command is enabled")
	ui._on_source_help_requested()
	await process_frame
	var controller: Control = ui.source_help_controller
	_expect(controller != null and controller.is_open(), "ordinary Help request opens the controller")
	_expect(controller.help_panel != null and controller.help_panel.visible, "Help presenter remains visible with unavailable content")
	_expect(not controller.help_panel.is_model_valid(), "missing private content renders the explicit unavailable view")
	_expect(ui._source_modal_open() and ui._load_blocked_by_presentation(), "Help participates in modal and load guards")
	_expect(game.to_json() == before, "opening unavailable Help preserves state and RNG")

	var blocked: Dictionary = ui._invoke_game("roll")
	_expect(not bool(blocked.get("ok", false)), "Help blocks simulation actions")
	ui._on_source_start_requested()
	ui._on_source_save_requested()
	ui._on_source_load_requested()
	ui._on_source_stocks_requested()
	ui._on_source_map_requested()
	ui._on_source_inspect_requested()
	await process_frame
	_expect(not ui.new_game_popup.visible and not ui.source_stock_panel.visible, "Help blocks competing source windows")
	_expect(not ui.source_shell.is_player_inspector_visible(), "Help blocks player inspection")
	_expect(game.to_json() == before, "blocked Help commands preserve state and RNG")

	controller.help_panel.close_help()
	await process_frame
	await process_frame
	_expect(not controller.is_open() and not ui._source_modal_open(), "Help closes cleanly and returns to the board")
	_expect(not help_button.disabled and not ui._load_blocked_by_presentation(), "board commands return after Help closes")
	_expect(game.to_json() == before, "closing Help preserves state and RNG")

	help_button.pressed.emit()
	await process_frame
	_expect(controller.is_open(), "the real toolbar Help button reopens the presenter")
	if controller.is_open():
		controller.cancel()
	ui.queue_free()
	await create_timer(0.15).timeout
	print("Source help UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
