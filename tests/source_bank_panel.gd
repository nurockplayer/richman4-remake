extends SceneTree

## Focused, hermetic acceptance checks for the source-shaped bank presenter.
##
## The first tests-only commit intentionally loads the component dynamically.
## A missing implementation is a qualified RED; a missing script must not turn
## the result into a parser error.  This suite never instantiates GameState or
## calls a domain action.

var checks := 0
var failures := 0
var _requests: Array = []
var _closed_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source_path := "res://game/ui/source_bank_panel.gd"
	if not FileAccess.file_exists(source_path):
		failures += 1
		checks += 1
		print("FAIL: Source bank panel implementation is absent (qualified RED)")
		print("Source bank panel RED: implementation absent; checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var source_script: Variant = load(source_path)
	if source_script == null:
		failures += 1
		checks += 1
		print("FAIL: Source bank panel script could not load")
		quit(1)
		return
	var panel: Node = source_script.new()
	root.add_child(panel)
	panel.connect("action_requested", Callable(self, "_on_action_requested"))
	panel.connect("closed", Callable(self, "_on_closed"))
	await process_frame

	_check_public_api(panel)
	_test_model_isolation(panel)
	_test_atm_selection_and_bounds(panel)
	_test_keypad_input_dispatch(panel)
	_test_loan_front_and_calculator(panel)
	_test_rear_special_gate(panel)
	_test_cancel_paths(panel)

	panel.queue_free()
	await process_frame
	print("Source bank panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _check_public_api(panel: Node) -> void:
	for method in ["set_view_model", "set_visuals", "select_action", "set_amount_text", "confirm_amount", "cancel_amount", "current_action", "current_amount"]:
		expect(panel.has_method(method), "bank presenter exposes " + method)
	expect(panel.has_signal("action_requested"), "bank presenter exposes action_requested")
	expect(panel.has_signal("closed"), "bank presenter exposes closed")


func _base_model() -> Dictionary:
	return {
		"edition": "game",
		"entry_mode": "atm",
		"allowed_actions": ["withdraw", "deposit", "exit"],
		"action_limits": {"withdraw": 250, "deposit": 600},
		"cash": 1250,
		"deposit": 900,
		"loan": 400,
		"due_date": 37,
		"special_principal": 80,
		"other_deposits": 1000,
		"can_special": false,
	}


func _test_model_isolation(panel: Node) -> void:
	var model := _base_model()
	var before: Dictionary = model.duplicate(true)
	panel.call("set_view_model", model)
	expect(model == before, "set_view_model does not mutate the host dictionary")
	panel.call("select_action", "withdraw")
	panel.call("set_amount_text", "125")
	panel.call("confirm_amount")
	expect(model == before, "selection and confirmation do not mutate host data")
	expect(_requests.size() == 1 and _requests[0] == ["withdraw", 125], "explicit confirmation emits the requested withdrawal")
	_requests.clear()


func _test_atm_selection_and_bounds(panel: Node) -> void:
	panel.call("set_view_model", _base_model())
	var withdraw_button: BaseButton = panel.find_child("ATMWithdraw", true, false) as BaseButton
	var deposit_button: BaseButton = panel.find_child("ATMDeposit", true, false) as BaseButton
	var maximum_button: BaseButton = panel.find_child("ATMMax", true, false) as BaseButton
	var enter_button: BaseButton = panel.find_child("ATMEnter", true, false) as BaseButton
	expect(withdraw_button != null and deposit_button != null, "ATM keeps source left/right direction controls")
	expect(maximum_button != null and enter_button != null, "ATM exposes source MAX and ENTER controls")
	if withdraw_button == null or deposit_button == null or maximum_button == null or enter_button == null:
		return

	_requests.clear()
	withdraw_button.pressed.emit()
	expect(str(panel.call("current_action")) == "withdraw", "ATM withdraw selects without emitting")
	expect(_requests.is_empty(), "selection alone never emits a domain action")
	panel.call("set_amount_text", "0")
	panel.call("confirm_amount")
	expect(_requests.is_empty(), "zero amount is rejected without an action")
	panel.call("set_amount_text", "251")
	panel.call("confirm_amount")
	expect(_requests.is_empty(), "over-limit amount is rejected without an action")
	panel.call("set_amount_text", "-1")
	panel.call("confirm_amount")
	expect(_requests.is_empty(), "negative amount is rejected without an action")
	panel.call("set_amount_text", "bad")
	panel.call("confirm_amount")
	expect(_requests.is_empty(), "non-numeric amount is rejected without an action")
	maximum_button.pressed.emit()
	expect(int(panel.call("current_amount")) == 250, "MAX fills the exact host withdrawal limit")
	enter_button.pressed.emit()
	expect(_requests.size() == 1 and _requests[0] == ["withdraw", 250], "exact MAX confirms through ENTER")
	_requests.clear()

	var gated_model := _base_model()
	gated_model.allowed_actions = ["withdraw", "exit"]
	panel.call("set_view_model", gated_model)
	deposit_button = panel.find_child("ATMDeposit", true, false) as BaseButton
	expect(deposit_button != null and deposit_button.disabled, "denied ATM action is visibly disabled")
	if deposit_button != null:
		deposit_button.pressed.emit()
	panel.call("set_amount_text", "1")
	panel.call("confirm_amount")
	expect(_requests.is_empty(), "denied ATM action cannot emit")


func _test_keypad_input_dispatch(panel: Node) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 338)
	viewport.disable_3d = true
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var input_panel: Node = panel.get_script().new()
	viewport.add_child(input_panel)
	input_panel.call("set_view_model", _base_model())
	input_panel.connect("action_requested", Callable(self, "_on_action_requested"))
	await process_frame
	input_panel.call("select_action", "withdraw")
	input_panel.call("set_amount_text", "")
	_requests.clear()
	viewport.push_input(_key_event(KEY_1, "1"))
	viewport.push_input(_key_event(KEY_2, "2"))
	viewport.push_input(_key_event(KEY_ENTER, "\n"))
	expect(_requests.size() == 1 and _requests[0] == ["withdraw", 12], "SubViewport key events dispatch through the amount pad")
	_requests.clear()
	input_panel.queue_free()
	viewport.queue_free()
	await process_frame


func _test_loan_front_and_calculator(panel: Node) -> void:
	var model := _base_model()
	model.entry_mode = "loan"
	model.edition = "front"
	model.allowed_actions = ["take_loan", "repay_loan", "exit"]
	model.action_limits = {"take_loan": 1200, "repay_loan": 400}
	panel.call("set_view_model", model)
	var borrow_button: BaseButton = panel.find_child("LoanBorrow", true, false) as BaseButton
	var repay_button: BaseButton = panel.find_child("LoanRepay", true, false) as BaseButton
	var exit_button: BaseButton = panel.find_child("BankExit", true, false) as BaseButton
	expect(borrow_button != null and repay_button != null and exit_button != null, "front bank exposes source loan controls and EXIT")
	if borrow_button == null or repay_button == null:
		return
	_requests.clear()
	borrow_button.pressed.emit()
	expect(str(panel.call("current_action")) == "take_loan", "loan borrow selects a source action")
	expect(panel.find_child("SourceAmountPad", true, false) != null, "loan opens the separate calculator pad")
	panel.call("set_amount_text", "1200")
	panel.call("confirm_amount")
	expect(_requests.size() == 1 and _requests[0] == ["take_loan", 1200], "loan confirmation emits exact host amount")
	_requests.clear()
	repay_button.pressed.emit()
	panel.call("set_amount_text", "400")
	panel.call("confirm_amount")
	expect(_requests.size() == 1 and _requests[0] == ["repay_loan", 400], "repayment confirmation emits exact host amount")
	_requests.clear()


func _test_rear_special_gate(panel: Node) -> void:
	var model := _base_model()
	model.entry_mode = "loan"
	model.edition = "rear"
	model.allowed_actions = ["take_special_finance", "repay_special_finance", "exit"]
	model.action_limits = {"take_special_finance": 700, "repay_special_finance": 80}
	model.can_special = false
	panel.call("set_view_model", model)
	var special_button: BaseButton = panel.find_child("SpecialBorrow", true, false) as BaseButton
	expect(special_button != null and special_button.disabled, "rear special financing is disabled for a non-owner")
	if special_button != null:
		special_button.pressed.emit()
	panel.call("set_amount_text", "1")
	panel.call("confirm_amount")
	expect(_requests.is_empty(), "non-owner cannot confirm special financing")

	model.can_special = true
	panel.call("set_view_model", model)
	special_button = panel.find_child("SpecialBorrow", true, false) as BaseButton
	expect(special_button != null and not special_button.disabled, "owner gate enables special financing")
	var summary: Label = panel.find_child("SpecialSummary", true, false) as Label
	expect(summary != null and summary.text.contains("80") and summary.text.contains("1000"), "rear scene displays supplied principal and other deposits")
	if special_button != null:
		_requests.clear()
		special_button.pressed.emit()
		panel.call("set_amount_text", "700")
		panel.call("confirm_amount")
		expect(_requests.size() == 1 and _requests[0] == ["take_special_finance", 700], "special action uses canonical core action name")
	_requests.clear()


func _test_cancel_paths(panel: Node) -> void:
	var model := _base_model()
	model.entry_mode = "atm"
	panel.call("set_view_model", model)
	_requests.clear()
	_closed_count = 0
	panel.call("select_action", "withdraw")
	panel.call("set_amount_text", "12")
	panel.call("cancel_amount")
	expect(str(panel.call("current_action")) == "", "amount-pad cancel returns to bank scene")
	expect(_closed_count == 0, "amount-pad cancel does not close the whole flow")
	var exit_button: BaseButton = panel.find_child("ATMExit", true, false) as BaseButton
	if exit_button != null:
		exit_button.pressed.emit()
	expect(_closed_count == 1, "bank EXIT emits closed as the explicit cancel")


func _key_event(keycode: Key, unicode_value: String) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.unicode = unicode_value.unicode_at(0)
	event.pressed = true
	return event


func _on_action_requested(action: String, amount: int) -> void:
	_requests.append([action, amount])


func _on_closed() -> void:
	_closed_count += 1
