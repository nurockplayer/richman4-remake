extends SceneTree

## Regression checks for the SourceBankController host boundary.
##
## This suite deliberately exercises the host adapters as MainUI does: the
## result handler refreshes the controller from the returned state.  The
## controller remains dynamically loaded so setup failures are kept separate
## from behavioural RED.

class FakeCore extends RefCounted:
	var token: Dictionary = {}
	var company: Dictionary = {}
	var calls: Array = []
	var summary: Dictionary = {}
	var resume_result: Dictionary = {"ok": true, "state": {}}
	var complete_result: Dictionary = {"ok": true, "state": {}}
	var transfer_limits: Dictionary = {"deposit": 100, "withdraw": 50}
	var loan_limits: Dictionary = {"take_loan": 800, "repay_loan": 300}
	var special_limits: Dictionary = {"take_special_finance": 700, "repay_special_finance": 200}

	func pending_bank_visit() -> Dictionary:
		calls.append(["pending_bank_visit", []])
		return token.duplicate(true)

	func bank_transfer_limit(action: String, player_id: int = -1) -> int:
		calls.append(["bank_transfer_limit", [action, player_id]])
		return int(transfer_limits.get(action, 0))

	func bank_loan_limit(action: String, player_id: int = -1) -> int:
		calls.append(["bank_loan_limit", [action, player_id]])
		return int(loan_limits.get(action, 0))

	func special_finance_limit(action: String, player_id: int = -1) -> int:
		calls.append(["special_finance_limit", [action, player_id]])
		return int(special_limits.get(action, 0))

	func get_company_at(node_id: int) -> Dictionary:
		calls.append(["get_company_at", [node_id]])
		return company.duplicate(true)

	func bank_account_summary(player_id: int = -1) -> Dictionary:
		calls.append(["bank_account_summary", [player_id]])
		return summary.duplicate(true)

	func resume_bank_visit() -> Dictionary:
		calls.append(["resume_bank_visit", []])
		return resume_result.duplicate(true)

	func complete_bank_visit() -> Dictionary:
		calls.append(["complete_bank_visit", []])
		return complete_result.duplicate(true)


## A separate fake intentionally has no bank_account_summary method.  This
## proves unknown summary data remains visibly unknown rather than falling
## back to player snapshot fields.
class FakeCoreNoSummary extends RefCounted:
	var token: Dictionary = {}
	var company: Dictionary = {}
	var calls: Array = []
	var transfer_limits: Dictionary = {"deposit": 100, "withdraw": 50}
	var loan_limits: Dictionary = {"take_loan": 800, "repay_loan": 300}
	var special_limits: Dictionary = {"take_special_finance": 700, "repay_special_finance": 200}

	func pending_bank_visit() -> Dictionary:
		calls.append(["pending_bank_visit", []])
		return token.duplicate(true)

	func bank_transfer_limit(action: String, player_id: int = -1) -> int:
		calls.append(["bank_transfer_limit", [action, player_id]])
		return int(transfer_limits.get(action, 0))

	func bank_loan_limit(action: String, player_id: int = -1) -> int:
		calls.append(["bank_loan_limit", [action, player_id]])
		return int(loan_limits.get(action, 0))

	func special_finance_limit(action: String, player_id: int = -1) -> int:
		calls.append(["special_finance_limit", [action, player_id]])
		return int(special_limits.get(action, 0))

	func get_company_at(node_id: int) -> Dictionary:
		calls.append(["get_company_at", [node_id]])
		return company.duplicate(true)

	func resume_bank_visit() -> Dictionary:
		calls.append(["resume_bank_visit", []])
		return {"ok": true, "state": {}}

	func complete_bank_visit() -> Dictionary:
		calls.append(["complete_bank_visit", []])
		return {"ok": true, "state": {}}


var _checks := 0
var _failures := 0
var _setup_failures := 0
var _controller: Node = null
var _host: Control = null
var _host_core: Object = null
var _invocations: Array = []
var _handled: Array = []
var _invoke_result: Dictionary = {"ok": true, "state": {}}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var controller_path := "res://game/ui/source_bank_controller.gd"
	if not FileAccess.file_exists(controller_path):
		_checks += 1
		_failures += 1
		print("FAIL: Source bank controller implementation is absent (qualified RED)")
		print("Source bank controller host RED: checks: %d, failures: %d, setup_failures: %d" % [_checks, _failures, _setup_failures])
		quit(1)
		return
	var controller_script: Variant = load(controller_path)
	if controller_script == null:
		_checks += 1
		_failures += 1
		_setup_failures += 1
		print("SETUP FAIL: Source bank controller script could not load")
		print("Source bank controller host checks: %d, failures: %d, setup_failures: %d" % [_checks, _failures, _setup_failures])
		quit(2)
		return
	_controller = controller_script.new()
	if _controller == null:
		_checks += 1
		_failures += 1
		_setup_failures += 1
		print("SETUP FAIL: Source bank controller could not instantiate")
		print("Source bank controller host checks: %d, failures: %d, setup_failures: %d" % [_checks, _failures, _setup_failures])
		quit(2)
		return
	_host = Control.new()
	_host.name = "SourceBankControllerHost"
	_host.size = Vector2(640, 480)
	_host.custom_minimum_size = _host.size
	root.add_child(_host)
	_host.add_child(_controller)
	_controller.set("invoke_game", Callable(self, "_invoke_game"))
	_controller.set("handle_result", Callable(self, "_handle_result"))
	await process_frame

	await _test_close_uses_invoke_adapter()
	await _test_rejection_survives_host_sync()
	await _test_core_replacement_clears_input_and_invalidates_callback()
	await _test_token_change_reopens_same_lifecycle()
	await _test_bank_summary_projection()

	_controller.queue_free()
	_host.queue_free()
	await process_frame
	print("Source bank controller host checks: %d, failures: %d, setup_failures: %d" % [_checks, _failures, _setup_failures])
	quit(2 if _setup_failures > 0 else (1 if _failures > 0 else 0))


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)


func _snapshot(
		actor: int = 0,
		phase: String = "await_bank",
		node_id: int = 1,
		actions: Array = ["deposit", "withdraw"],
) -> Dictionary:
	var players: Array = [
		{
			"id": 0,
			"name": "Human",
			"is_human": true,
			"alive": true,
			"bankrupt": false,
			"position": node_id if actor == 0 else 4,
			"cash": 400,
			"deposit": 100,
			"loan": 40,
			"due_date": 9090,
			"special_principal": 999,
			"other_deposits": 888,
			"properties": [],
		},
		{
			"id": 1,
			"name": "AI",
			"is_human": false,
			"alive": true,
			"bankrupt": false,
			"position": node_id if actor == 1 else 4,
			"cash": 400,
			"deposit": 100,
			"loan": 40,
			"due_date": 9090,
			"special_principal": 999,
			"other_deposits": 888,
			"properties": [],
		},
	]
	var is_pass := phase == "await_bank"
	return {
		"version": 1,
		"edition": "Game",
		"phase": phase,
		"current_player": actor,
		"players": players,
		"action_options": actions.duplicate(true),
		"bank_access": true,
		"bank_landing": phase == "await_action",
		"route_options": [],
		"pending_movement": {"player_id": actor, "current_node": node_id, "previous_node": 0} if is_pass else {},
		"remaining_steps": 1 if is_pass else 0,
		"bank": {"cash": 1000, "deposits": 200},
	}


func _set_token(core: Object, kind: String, actor: int = 0, node_id: int = 1) -> void:
	core.set("token", {"kind": kind, "player_id": actor, "node_id": node_id})


func _sync(core: Object, snapshot: Dictionary, blocked: bool = false, edition: String = "Game") -> void:
	_host_core = core
	_controller.call("sync", core, snapshot, edition, {}, blocked)


func _panel() -> Node:
	var panel: Variant = _controller.get("bank_panel")
	return panel as Node


func _calls_for(core: Object, method: String) -> Array:
	var result: Array = []
	var calls_value: Variant = core.get("calls")
	if typeof(calls_value) != TYPE_ARRAY:
		return result
	for item in calls_value:
		if typeof(item) == TYPE_ARRAY and item.size() == 2 and str(item[0]) == method:
			result.append(item)
	return result


func _test_close_uses_invoke_adapter() -> void:
	_controller.call("cancel")
	var core := FakeCore.new()
	_set_token(core, "pass", 0, 1)
	var before := _snapshot(0, "await_bank", 1)
	_sync(core, before)
	_invocations.clear()
	_handled.clear()
	var presentation_before := {"phase": "await_bank", "remaining_steps": 1, "marker": "host-metadata"}
	_invoke_result = {
		"ok": true,
		"message": "銀行操作已完成",
		"state": _snapshot(0, "await_roll", 1),
		"_presentation_before": presentation_before,
		"_presentation_generation": 17,
		"_presentation_owner": core,
	}
	var panel := _panel()
	var exit_button := panel.find_child("ATMExit", true, false) as BaseButton
	_expect(exit_button != null, "pass ATM exposes close for adapter test")
	if exit_button == null:
		return
	exit_button.pressed.emit()
	await process_frame
	await process_frame
	_expect(_invocations.size() == 1, "close invokes exactly one host adapter call")
	if _invocations.size() == 1:
		_expect(_invocations[0][0] == "resume_bank_visit" and _invocations[0][1].is_empty(), "close adapter receives resume method and empty args")
	_expect(_calls_for(core, "resume_bank_visit").is_empty(), "close never directly calls the core resume method")
	_expect(_handled.size() == 1, "close result reaches host result handler")
	if _handled.size() == 1:
		_expect(_handled[0].get("_presentation_before", {}) == presentation_before, "close preserves presentation-before metadata")
		_expect(int(_handled[0].get("_presentation_generation", -1)) == 17, "close preserves presentation generation metadata")
		_expect(_handled[0].get("_presentation_owner", null) == core, "close preserves presentation owner metadata")


func _test_rejection_survives_host_sync() -> void:
	_controller.call("cancel")
	var core := FakeCore.new()
	_set_token(core, "pass", 0, 1)
	var snapshot := _snapshot()
	_sync(core, snapshot)
	_invocations.clear()
	_handled.clear()
	_invoke_result = {"ok": false, "message": "拒絕：測試", "state": snapshot.duplicate(true)}
	var panel := _panel()
	_expect(bool(panel.call("select_action", "deposit")), "rejection test selects deposit")
	panel.call("set_amount_text", "12")
	_expect(bool(panel.call("confirm_amount")), "rejection test submits amount")
	await process_frame
	await process_frame
	var error_label := _controller.get("error_label") as Label
	_expect(_handled.size() == 1, "rejection reaches host handler before final assertion")
	_expect(bool(_controller.call("is_open")), "rejection keeps modal open after host refresh")
	_expect(error_label != null and error_label.visible and error_label.text.contains("拒絕"), "rejection error remains visible after host sync")
	_expect(int(panel.call("current_amount")) == 12, "rejection preserves amount after host refresh")


func _test_core_replacement_clears_input_and_invalidates_callback() -> void:
	_controller.call("cancel")
	var old_core := FakeCore.new()
	var new_core := FakeCore.new()
	_set_token(old_core, "pass", 0, 1)
	_set_token(new_core, "pass", 0, 1)
	var snapshot := _snapshot()
	_sync(old_core, snapshot)
	var panel := _panel()
	panel.call("select_action", "deposit")
	panel.call("set_amount_text", "12")
	_expect(int(panel.call("current_amount")) == 12, "replacement starts with old amount input")
	_invocations.clear()
	_handled.clear()
	_invoke_result = {"ok": true, "state": snapshot.duplicate(true)}
	_expect(bool(panel.call("confirm_amount")), "replacement queues old-core action")
	_sync(new_core, snapshot.duplicate(true))
	_expect(bool(_controller.call("is_open")), "same token on a replacement core reopens the modal")
	_expect(int(panel.call("current_amount")) == 0, "replacement clears old amount input")
	var replacement_summary_calls := _calls_for(new_core, "bank_account_summary").size()
	await process_frame
	await process_frame
	_expect(_handled.is_empty(), "old deferred callback does not reach the replacement host")
	_expect(_calls_for(new_core, "bank_account_summary").size() == replacement_summary_calls, "old deferred callback does not query replacement summary")


func _test_token_change_reopens_same_lifecycle() -> void:
	_controller.call("cancel")
	var core := FakeCore.new()
	_set_token(core, "pass", 0, 1)
	_sync(core, _snapshot(0, "await_bank", 1))
	var panel := _panel()
	panel.call("select_action", "deposit")
	panel.call("set_amount_text", "9")
	_set_token(core, "pass", 0, 2)
	_sync(core, _snapshot(0, "await_bank", 2))
	_expect(bool(_controller.call("is_open")), "a changed valid token reopens in the same controller lifecycle")
	_expect(int(panel.call("current_amount")) == 0, "changed token clears prior amount input")
	_expect(int(panel.call("view_model").get("node_id", -1)) == 2, "changed token installs the new node model")


func _test_bank_summary_projection() -> void:
	_controller.call("cancel")
	var core := FakeCore.new()
	core.summary = {
		"loan_due_date": {"year": 2026, "month": 9, "day": 7},
		"special_principal": 345,
		"other_deposits": 678,
	}
	core.company = {"company_type": 7, "owner": 0}
	_set_token(core, "landing", 0, 7)
	var landing := _snapshot(0, "await_action", 7, ["deposit", "withdraw", "take_loan", "repay_loan", "take_special_finance", "repay_special_finance"])
	_sync(core, landing)
	_expect(_calls_for(core, "bank_account_summary").size() == 1, "landing model queries the public bank summary once")
	var panel := _panel()
	var atm_exit := panel.find_child("ATMExit", true, false) as BaseButton
	_expect(atm_exit != null, "summary landing exposes ATM close")
	if atm_exit == null:
		return
	atm_exit.pressed.emit()
	await process_frame
	await process_frame
	var model: Dictionary = panel.call("view_model")
	_expect(str(model.get("due_date", "—")) == "2026-09-07", "front formats the public loan due date")
	_expect(int(model.get("special_principal", -1)) == 345, "front carries public special principal")
	_expect(int(model.get("other_deposits", -1)) == 678, "front carries public other deposits")
	var due_label := panel.find_child("LoanDueDate", true, false) as Label
	_expect(due_label != null and due_label.text.contains("2026-09-07"), "front renders formatted due date")
	var rear_entry := panel.find_child("BankRearEntry", true, false) as BaseButton
	_expect(rear_entry != null, "owner front exposes rear entry for summary projection")
	if rear_entry == null:
		return
	rear_entry.pressed.emit()
	await process_frame
	await process_frame
	var other_label := panel.find_child("SpecialOtherDeposits", true, false) as Label
	var principal_label := panel.find_child("SpecialPrincipal", true, false) as Label
	_expect(other_label != null and other_label.text.contains("678"), "rear renders public other deposits")
	_expect(principal_label != null and principal_label.text.contains("345"), "rear renders public special principal")

	_controller.call("cancel")
	var unknown_core := FakeCoreNoSummary.new()
	unknown_core.company = {"company_type": 7, "owner": 0}
	_set_token(unknown_core, "landing", 0, 7)
	_sync(unknown_core, landing.duplicate(true))
	var unknown_panel := _panel()
	var unknown_atm_exit := unknown_panel.find_child("ATMExit", true, false) as BaseButton
	_expect(unknown_atm_exit != null, "unknown summary landing exposes ATM close")
	if unknown_atm_exit == null:
		return
	unknown_atm_exit.pressed.emit()
	await process_frame
	await process_frame
	var unknown_due := unknown_panel.find_child("LoanDueDate", true, false) as Label
	_expect(unknown_due != null and unknown_due.text.contains("—"), "missing summary keeps front due date unknown")
	var unknown_rear := unknown_panel.find_child("BankRearEntry", true, false) as BaseButton
	_expect(unknown_rear != null, "unknown summary owner front exposes rear entry")
	if unknown_rear == null:
		return
	unknown_rear.pressed.emit()
	await process_frame
	await process_frame
	var unknown_other := unknown_panel.find_child("SpecialOtherDeposits", true, false) as Label
	var unknown_principal := unknown_panel.find_child("SpecialPrincipal", true, false) as Label
	_expect(unknown_other != null and unknown_other.text.contains("—"), "missing summary keeps rear other deposits unknown")
	_expect(unknown_principal != null and unknown_principal.text.contains("—"), "missing summary keeps rear principal unknown")


func _invoke_game(method: String, args: Array = []) -> Dictionary:
	_invocations.append([method, args.duplicate(true)])
	return _invoke_result.duplicate(true)


func _handle_result(result: Dictionary) -> void:
	_handled.append(result.duplicate(true))
	var latest: Variant = result.get("state", null)
	if _controller != null and _host_core != null and typeof(latest) == TYPE_DICTIONARY:
		# Mirror MainUI's authoritative refresh path.  This is intentionally a
		# real controller.sync call so feedback lifetime is tested at the host
		# boundary rather than with a recorder-only fake.
		_controller.call("sync", _host_core, latest, "Game", {}, false)
