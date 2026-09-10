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
	_expect(ui.bank_deposit_button.disabled, "UI refreshes deposit availability after exhausting cash")
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

	# Issue #98 acceptance: a bare N key is an input-path request for a new game,
	# not a destructive shortcut. The current match must stay exact until the
	# player explicitly confirms the replacement.
	var restart_game := GameState.new_game(701, 2)
	restart_game.state.players[0].cash = 12345
	restart_game._sync_state()
	ui.game_state = restart_game
	ui._refresh_from_state()
	ui.new_game_popup.hide()
	var restart_before: Dictionary = restart_game.to_dict()
	var restart_key := InputEventKey.new()
	restart_key.keycode = KEY_N
	restart_key.pressed = true
	restart_key.echo = false
	ui._unhandled_input(restart_key)
	_expect(ui.game_state == restart_game, "Bare N keeps the current game object until explicit confirmation")
	_expect(ui._read_snapshot() == restart_before, "Bare N preserves the exact live snapshot and RNG continuation")
	_expect(ui.new_game_popup.visible, "Bare N opens the explicit new-game flow instead of restarting immediately")
	ui.new_game_popup.hide()
	_expect(ui.game_state == restart_game and ui._read_snapshot() == restart_before, "Cancelling the N-key new-game flow preserves the current game exactly")

	# Issue #98 acceptance: ordinary transfers must not require hundreds of
	# fixed-$500 clicks. These node names are the stable UI contract for the
	# implementation lane; amount ranges prevent zero/out-of-range submission.
	var amount_game := GameState.new_game(702, 2)
	amount_game.state.players[0].cash = 20000
	amount_game.state.players[0].deposit = 3000
	amount_game.state.bank.deposits = 3000
	amount_game.state.phase = "await_action"
	amount_game.state.bank_access = true
	amount_game._set_action_options(0)
	ui.game_state = amount_game
	ui._refresh_from_state()
	ui._on_bank_pressed()
	var deposit_amount := ui.bank_popup.find_child("BankDepositAmount", true, false) as SpinBox
	var withdraw_amount := ui.bank_popup.find_child("BankWithdrawAmount", true, false) as SpinBox
	var deposit_all := ui.bank_popup.find_child("BankDepositAll", true, false) as Button
	var withdraw_all := ui.bank_popup.find_child("BankWithdrawAll", true, false) as Button
	_expect(deposit_amount != null, "Bank exposes a selectable deposit amount")
	_expect(withdraw_amount != null, "Bank exposes a selectable withdrawal amount")
	_expect(deposit_all != null, "Bank exposes an efficient deposit-all path")
	_expect(withdraw_all != null, "Bank exposes an efficient withdraw-all path")
	if deposit_amount != null:
		_expect(deposit_amount.min_value >= 1.0 and deposit_amount.max_value == 20000.0, "Deposit amount prevents zero/out-of-range entry and reflects available cash")
		deposit_amount.value = 7000
		ui.bank_deposit_button.pressed.emit()
		_expect(int(amount_game.state.players[0].cash) == 13000, "Selectable deposit transfers the requested amount in one action")
		_expect(int(amount_game.state.players[0].deposit) == 10000, "Selectable deposit credits the exact requested amount")
	if withdraw_amount != null:
		_expect(withdraw_amount.min_value >= 1.0 and withdraw_amount.max_value == 10000.0, "Withdrawal amount prevents zero/out-of-range entry and reflects available deposit")
		withdraw_amount.value = 2500
		ui.bank_withdraw_button.pressed.emit()
		_expect(int(amount_game.state.players[0].cash) == 15500, "Selectable withdrawal transfers the requested amount in one action")
		_expect(int(amount_game.state.players[0].deposit) == 7500, "Selectable withdrawal debits the exact requested amount")
	if deposit_all != null:
		deposit_all.pressed.emit()
		_expect(int(amount_game.state.players[0].cash) == 0, "Deposit-all transfers all currently available cash")
		_expect(int(amount_game.state.players[0].deposit) == 23000, "Deposit-all preserves the exact account total")
	if withdraw_all != null:
		withdraw_all.pressed.emit()
		_expect(int(amount_game.state.players[0].deposit) == 0, "Withdraw-all empties the deposit balance")
		_expect(int(amount_game.state.players[0].cash) == 23000, "Withdraw-all preserves the exact account total")

	ui.queue_free()
	await create_timer(0.15).timeout
	if failures == 0:
		print("UI bankruptcy, AI scheduling and Issue #98 acceptance checks passed")
	quit(1 if failures else 0)
