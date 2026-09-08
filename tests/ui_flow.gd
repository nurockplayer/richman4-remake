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
	ui.set_process(false)
	ui._new_game(-2, 2)
	_expect(int(ui.state.get("seed", 0)) == -2, "Explicit negative seed is preserved by UI")
	game = GameState.new_game(42, 3)
	game.state.current_player = 1
	game._set_action_options(1)
	ui.game_state = game
	ui._refresh_from_state()
	_expect(ui.bank_shortcut.disabled and ui.cards_shortcut.disabled and ui.stocks_shortcut.disabled, "All AI sidebar shortcuts are disabled")
	ui._on_stocks_pressed()
	_expect(not ui.stocks_popup.visible, "AI sidebar cannot open trading popup")
	var ai_cash := int(game.state.players[1].cash)
	var result: Dictionary = ui._invoke_game("choose_action", ["buy_stock", {"symbol": "tech", "quantity": 1}])
	_expect(not result.get("ok", false), "UI action boundary rejects human action for AI")
	_expect(int(game.state.players[1].cash) == ai_cash, "AI cash remains unchanged by human input")
	var deposit_game := GameState.new_game(42, 2)
	deposit_game.state.players[0].cash = 250
	deposit_game.state.phase = "await_action"
	deposit_game.state.bank_access = true
	deposit_game._set_action_options(0)
	ui.game_state = deposit_game
	ui._refresh_from_state()
	ui._on_bank_pressed()
	_expect(ui.bank_deposit_button.text == "存入 $250", "UI shows the actual remaining deposit amount")
	ui._on_deposit_pressed()
	_expect(int(deposit_game.state.players[0].cash) == 0, "UI deposits sub-500 remaining cash")
	_expect(int(deposit_game.state.players[0].deposit) == 250, "UI records exact sub-500 deposit")
	game = GameState.new_game(42, 2)
	game.state.players[0].deposit = 250
	game.state.bank.deposits = 250
	game.state.phase = "await_action"
	game.state.bank_access = true
	game._set_action_options(0)
	ui.game_state = game
	ui._refresh_from_state()
	ui._on_bank_pressed()
	_expect(ui.bank_withdraw_button.text == "提取 $250", "UI shows the actual remaining withdrawal amount")
	ui._on_withdraw_pressed()
	_expect(int(game.state.players[0].deposit) == 0, "UI withdraws sub-500 remaining deposit")
	_expect(int(game.state.players[0].cash) == 15250, "UI returns exact remaining deposit to cash")
	_expect(ui.bank_withdraw_button.disabled, "UI refreshes withdrawal availability after exhausting deposit")
	ui.queue_free()
	await create_timer(0.15).timeout
	if failures == 0:
		print("UI bankruptcy and AI scheduling checks passed")
	quit(1 if failures else 0)
