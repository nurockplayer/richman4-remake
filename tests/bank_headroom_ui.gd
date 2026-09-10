extends SceneTree

## Issue #104 focused UI acceptance for shared bank transfer limits.

const Game = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
const MAX_BALANCE: int = 1000000000000

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _prepare_action(game: Object, cash: int, deposit: int, bank_cash: int, bank_deposits: int) -> void:
	var player: Dictionary = game.state["players"][0]
	player["cash"] = cash
	player["deposit"] = deposit
	var bank: Dictionary = game.state["bank"]
	bank["cash"] = bank_cash
	bank["deposits"] = bank_deposits
	game.state["bank"] = bank
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["bank_access"] = true
	game.state["bank_landing"] = false
	game.state["property_action_used"] = false
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game._sync_state()
	game._set_action_options(0)


func _valid_save(game: Object, label: String) -> void:
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), label + " remains saveable: " + str(validation.get("errors", [])))


func _run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	if ui.audio_controller != null:
		ui.audio_controller.call("stop")

	var deposit_game: Object = Game.new_game(10440, 2)
	_prepare_action(deposit_game, 750, MAX_BALANCE - 250, 0, 0)
	ui.game_state = deposit_game
	ui._refresh_from_state()
	ui._on_bank_pressed()
	var deposit_amount := ui.bank_popup.find_child("BankDepositAmount", true, false) as SpinBox
	var deposit_all := ui.bank_popup.find_child("BankDepositAll", true, false) as Button
	_expect(deposit_amount != null, "bank UI exposes a deposit selector")
	_expect(deposit_all != null, "bank UI exposes deposit-all")
	if deposit_amount != null:
		_expect_equal(int(deposit_amount.max_value), 250, "deposit selector uses the player-account headroom")
		var deposit_editor := deposit_amount.get_line_edit()
		var before_focus_rejection: String = deposit_game.to_json()
		deposit_editor.grab_focus()
		deposit_editor.text = "251"
		deposit_editor.release_focus()
		await process_frame
		ui.bank_deposit_button.pressed.emit()
		_expect_equal(deposit_game.to_json(), before_focus_rejection, "focus-exit over-limit deposit remains atomic")
		_expect_equal(int(deposit_game.state["players"][0]["cash"]), 750, "focus-exit over-limit deposit preserves cash")
		_expect_equal(int(deposit_game.state["players"][0]["deposit"]), MAX_BALANCE - 250, "focus-exit over-limit deposit preserves account balance")
		_expect_equal(deposit_game.state["event_log"].size(), 1, "focus-exit over-limit deposit appends no event")
		deposit_editor.grab_focus()
		deposit_amount.value = 125
		deposit_editor.release_focus()
		await process_frame
		ui.bank_deposit_button.pressed.emit()
		_expect_equal(int(deposit_game.state["players"][0]["cash"]), 625, "selected deposit transfers the requested amount")
		_expect_equal(int(deposit_game.state["players"][0]["deposit"]), MAX_BALANCE - 125, "selected deposit preserves the exact account headroom")
	if deposit_all != null:
		_expect(not deposit_all.disabled, "deposit-all stays enabled while headroom remains")
		deposit_all.pressed.emit()
		_expect_equal(int(deposit_game.state["players"][0]["cash"]), 500, "deposit-all transfers only the remaining legal amount")
		_expect_equal(int(deposit_game.state["players"][0]["deposit"]), MAX_BALANCE, "deposit-all stops at the destination cap")
	_valid_save(deposit_game, "deposit UI exact and all actions")

	var withdraw_game: Object = Game.new_game(10441, 2)
	_prepare_action(withdraw_game, MAX_BALANCE - 125, 1000, 1000, 1000)
	ui.game_state = withdraw_game
	ui._refresh_from_state()
	ui._on_bank_pressed()
	var withdraw_amount := ui.bank_popup.find_child("BankWithdrawAmount", true, false) as SpinBox
	var withdraw_all := ui.bank_popup.find_child("BankWithdrawAll", true, false) as Button
	_expect(withdraw_amount != null, "bank UI exposes a withdrawal selector")
	_expect(withdraw_all != null, "bank UI exposes withdraw-all")
	if withdraw_amount != null:
		_expect_equal(int(withdraw_amount.max_value), 125, "withdrawal selector uses player cash headroom")
		withdraw_amount.value = 80
		ui.bank_withdraw_button.pressed.emit()
		_expect_equal(int(withdraw_game.state["players"][0]["cash"]), MAX_BALANCE - 45, "selected withdrawal transfers the requested amount")
		_expect_equal(int(withdraw_game.state["players"][0]["deposit"]), 920, "selected withdrawal debits the exact deposit")
	if withdraw_all != null:
		_expect(not withdraw_all.disabled, "withdraw-all stays enabled while headroom remains")
		withdraw_all.pressed.emit()
		_expect_equal(int(withdraw_game.state["players"][0]["cash"]), MAX_BALANCE, "withdraw-all stops at the destination cap")
		_expect_equal(int(withdraw_game.state["players"][0]["deposit"]), 875, "withdraw-all transfers only the remaining legal amount")
	_valid_save(withdraw_game, "withdraw UI exact and all actions")

	ui.queue_free()
	await create_timer(0.15).timeout
	print("Bank headroom UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
