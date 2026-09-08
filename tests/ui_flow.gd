extends SceneTree
## Exercise the actual UI scheduler, not only the all-AI simulation helper.
const GameState = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	if ui.audio_controller != null:
		ui.audio_controller.call("stop")
	var game = GameState.new_game(42, 3)
	# Seed 42 rolls six. A human cannot cover the rent at that destination.
	game.state.players[0].cash = 1
	game.state.board[6].owner = 1
	game.state.players[1].properties = [6]
	game._sync_state()
	ui.game_state = game
	ui._refresh_from_state()
	_expect(not ui.roll_button.disabled, "Human roll is available before bankruptcy")
	ui._on_roll_pressed()
	_expect(game.state.players[0].bankrupt, "Fixture reaches non-final human bankruptcy")
	_expect(game.state.phase != "game_over", "Two opponents remain after bankruptcy")
	_expect(game.state.current_player == 1, "Normal UI roll hands control to next survivor")
	var turn_after_death := int(game.state.turn)
	await create_timer(1.2).timeout
	_expect(int(game.state.turn) > turn_after_death, "Actual UI timer runs the next AI turn")
	_expect(not game.state.players[game.state.current_player].bankrupt, "UI never rests on a bankrupt actor")
	ui.queue_free()
	await create_timer(0.15).timeout
	if failures == 0:
		print("UI bankruptcy and AI scheduling checks passed")
	quit(1 if failures else 0)
