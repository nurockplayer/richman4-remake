extends SceneTree

## Focused host-boundary checks for the source bank encounter controller.
##
## The controller is loaded dynamically so the tests-only RED remains a
## qualified behaviour failure while the implementation file is absent.  A
## parser or fixture failure is reported separately and never counted as a
## product RED.  FakeCore exposes only the public core seams accepted by the
## Issue #135 contract; no GameState or domain action is instantiated here.

class FakeCore extends RefCounted:
	var token: Dictionary = {}
	var company: Dictionary = {}
	var calls: Array = []
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

	func resume_bank_visit() -> Dictionary:
		calls.append(["resume_bank_visit", []])
		return resume_result.duplicate(true)

	func complete_bank_visit() -> Dictionary:
		calls.append(["complete_bank_visit", []])
		return complete_result.duplicate(true)


var _checks := 0
var _failures := 0
var _setup_failures := 0
var _controller: Node = null
var _host: Control = null
var _core := FakeCore.new()
var _invocations: Array = []
var _handled: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var controller_path := "res://game/ui/source_bank_controller.gd"
	if not FileAccess.file_exists(controller_path):
		_checks += 1
		_failures += 1
		print("FAIL: Source bank controller implementation is absent (qualified RED)")
		print("Source bank controller RED: implementation absent; checks: %d, failures: %d, setup_failures: %d" % [_checks, _failures, _setup_failures])
		quit(1)
		return
	var controller_script: Variant = load(controller_path)
	if controller_script == null:
		_checks += 1
		_failures += 1
		_setup_failures += 1
		print("SETUP FAIL: Source bank controller script could not load")
		print("Source bank controller checks: %d, failures: %d, setup_failures: %d" % [_checks, _failures, _setup_failures])
		quit(2)
		return
	_controller = controller_script.new()
	if _controller == null:
		_checks += 1
		_failures += 1
		_setup_failures += 1
		print("SETUP FAIL: Source bank controller could not instantiate")
		print("Source bank controller checks: %d, failures: %d, setup_failures: %d" % [_checks, _failures, _setup_failures])
		quit(2)
		return
	_host = Control.new()
	_host.name = "SourceReferenceCanvas"
	_host.size = Vector2(640, 480)
	_host.custom_minimum_size = _host.size
	root.add_child(_host)
	_host.add_child(_controller)
	_controller.set("invoke_game", Callable(self, "_invoke_game"))
	_controller.set("handle_result", Callable(self, "_handle_result"))
	await process_frame

	_test_public_surface()
	_test_pointer_and_geometry()
	_test_blocked_and_invalid_ingress()
	_test_snapshot_refresh_preserves_amount()
	_test_action_result_boundary()
	_test_landing_front_owner_limits_and_close()
	_test_pass_close_cancel_and_stale()
	_test_edition_alias()

	_controller.queue_free()
	_host.queue_free()
	await process_frame
	print("Source bank controller checks: %d, failures: %d, setup_failures: %d" % [_checks, _failures, _setup_failures])
	quit(2 if _setup_failures > 0 else (1 if _failures > 0 else 0))


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)


func _setup_expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		_setup_failures += 1
		push_error("SETUP FAIL: " + label)


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
			"special_principal": 20,
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
			"special_principal": 20,
			"properties": [],
		},
	]
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
		"pending_movement": {},
		"remaining_steps": 0,
		"bank": {"cash": 1000, "deposits": 200},
	}


func _set_token(kind: String, actor: int = 0, node_id: int = 1) -> void:
	_core.token = {"kind": kind, "player_id": actor, "node_id": node_id}


func _sync(snapshot: Dictionary, blocked: bool = false, edition: String = "Game") -> void:
	_controller.call("sync", _core, snapshot, edition, {}, blocked)


func _panel() -> Node:
	var panel: Variant = _controller.get("bank_panel")
	return panel as Node


func _public_calls(method: String) -> Array:
	var found: Array = []
	for item in _core.calls:
		if typeof(item) == TYPE_ARRAY and item.size() == 2 and str(item[0]) == method:
			found.append(item)
	return found


func _test_public_surface() -> void:
	for method in ["sync", "cancel", "is_open"]:
		_expect(_controller.has_method(method), "controller exposes " + method)
	_expect(_controller.get("bank_panel") is Node, "controller exposes bank_panel")
	_expect(_controller.get("invoke_game") is Callable, "controller exposes invoke_game adapter")
	_expect(_controller.get("handle_result") is Callable, "controller exposes handle_result adapter")
	var panel := _panel()
	_expect(panel != null and panel.has_method("set_view_model"), "controller owns the source bank panel")


func _test_pointer_and_geometry() -> void:
	_core.calls.clear()
	_set_token("pass", 0, 1)
	_sync(_snapshot())
	var panel := _panel()
	_expect(bool(_controller.call("is_open")), "valid human pass token opens controller")
	_expect(panel != null and panel.visible, "valid token shows bank panel")
	_expect(_controller.size == Vector2(640, 480), "controller keeps the 640x480 modal root")
	_expect(_controller.mouse_filter == Control.MOUSE_FILTER_STOP, "controller blocks pointer input behind modal")
	_expect(panel != null and panel.position == Vector2(60, 71), "pass ATM uses source position 60,71")
	_expect(panel != null and panel.size == Vector2(320, 338), "pass ATM uses source size 320x338")
	_expect(_public_calls("bank_transfer_limit").size() >= 2, "pass model reads both public transfer limits")
	for call in _public_calls("bank_transfer_limit"):
		_expect(call[1].size() == 2 and int(call[1][1]) == 0, "pass limits query the current human actor")
	_expect(panel != null and panel.get("_model").get("entry_mode", "") == "atm", "pass enters ATM mode")


func _test_blocked_and_invalid_ingress() -> void:
	_controller.call("cancel")
	_core.calls.clear()
	_set_token("pass", 0, 1)
	_sync(_snapshot(), true)
	_expect(not bool(_controller.call("is_open")), "blocked movement delays a new bank entry")
	_sync(_snapshot(), false)
	_expect(bool(_controller.call("is_open")), "unblocked sync admits the still-valid token")

	_controller.call("cancel")
	_set_token("pass", 1, 1)
	_sync(_snapshot(1, "await_bank", 1), false)
	_expect(not bool(_controller.call("is_open")), "AI actor cannot open a human bank modal")
	_controller.call("cancel")
	_set_token("landing", 0, 4)
	_sync(_snapshot(0, "await_action", 1), false)
	_expect(not bool(_controller.call("is_open")), "token node mismatch is rejected before opening")
	_controller.call("cancel")
	_set_token("unknown", 0, 1)
	_sync(_snapshot())
	_expect(not bool(_controller.call("is_open")), "unknown token kind is rejected")
	_controller.call("cancel")
	_set_token("pass", 0, 1)
	_sync(_snapshot(0, "game_over", 1))
	_expect(not bool(_controller.call("is_open")), "terminal phase never opens bank modal")


func _test_snapshot_refresh_preserves_amount() -> void:
	_controller.call("cancel")
	_set_token("pass", 0, 1)
	var model := _snapshot()
	_sync(model)
	var panel := _panel()
	_expect(bool(panel.call("select_action", "deposit")), "pass ATM accepts deposit selection")
	panel.call("set_amount_text", "12")
	_expect(int(panel.call("current_amount")) == 12, "pass ATM stores the selected amount")
	_sync(model.duplicate(true))
	_expect(int(panel.call("current_amount")) == 12, "unchanged token and snapshot preserve amount input")
	var changed := model.duplicate(true)
	changed["players"][0]["deposit"] = 112
	_sync(changed)
	_expect(int(panel.call("current_amount")) == 12, "latest model rebuild preserves amount input")
	_expect(int(panel.call("view_model").get("deposit", -1)) == 112, "latest snapshot reaches the panel model")


func _test_action_result_boundary() -> void:
	_controller.call("cancel")
	_set_token("pass", 0, 1)
	var model := _snapshot()
	_sync(model)
	var panel := _panel()
	_invocations.clear()
	_handled.clear()
	var denied := {"ok": false, "message": "拒絕：測試", "state": model.duplicate(true)}
	_controller.set("_test_invoke_result", denied)
	panel.call("select_action", "deposit")
	panel.call("set_amount_text", "12")
	panel.call("confirm_amount")
	await process_frame
	await process_frame
	_expect(_invocations.size() == 1 and _invocations[0] == ["choose_action", ["deposit", {"amount": 12}]], "ATM action uses the invoke_game adapter")
	_expect(_handled.size() == 1, "denied action still reaches the deferred result adapter")
	_expect(bool(_controller.call("is_open")), "denied action keeps the bank modal open")
	var error_label: Label = _controller.get("error_label") as Label
	_expect(error_label != null and error_label.visible and error_label.text.contains("拒絕"), "controller-owned error boundary keeps denial truthful")
	_expect(int(panel.call("current_amount")) == 12, "denial preserves the selected amount atomically")

	_invocations.clear()
	_handled.clear()
	var accepted_model := model.duplicate(true)
	accepted_model["players"][0]["deposit"] = 112
	var accepted := {"ok": true, "message": "已存款", "state": accepted_model}
	_controller.set("_test_invoke_result", accepted)
	panel.call("confirm_amount")
	await process_frame
	await process_frame
	_expect(_handled.size() == 1, "accepted action reaches the deferred result adapter")
	_expect(int(panel.call("view_model").get("deposit", -1)) == 112, "accepted action rebuilds from the latest result model")
	_expect(not error_label.visible or error_label.text.is_empty(), "accepted action clears the controller error boundary")


func _test_landing_front_owner_limits_and_close() -> void:
	_controller.call("cancel")
	_core.calls.clear()
	_core.company = {"company_type": 7, "owner": 0, "type_and_idx": 6001}
	_set_token("landing", 0, 7)
	var landing := _snapshot(0, "await_action", 7, ["deposit", "withdraw", "take_loan", "repay_loan", "take_special_finance", "repay_special_finance"])
	_sync(landing)
	var panel := _panel()
	_expect(panel != null and panel.position == Vector2(60, 71), "landing starts in the ATM at source position")
	var atm_exit: BaseButton = panel.find_child("ATMExit", true, false) as BaseButton
	_expect(atm_exit != null, "landing ATM exposes a close control")
	if atm_exit == null:
		return
	atm_exit.pressed.emit()
	await process_frame
	await process_frame
	_expect(bool(_controller.call("is_open")), "landing ATM close keeps the same encounter open")
	_expect(panel.position == Vector2.ZERO and panel.size == Vector2(640, 480), "landing ATM close switches to the source front bank")
	_expect(str(panel.call("view_model").get("entry_mode", "")) == "loan", "landing front uses loan bank presentation")
	_expect(int(panel.call("action_limit", "take_loan")) == 800, "front uses public bank loan limit")
	_expect(int(panel.call("action_limit", "take_special_finance")) == 700, "owner front uses public special finance limit")
	_expect(bool(panel.call("view_model").get("can_special", false)), "type-7 current owner receives the rear permission")
	_expect(_public_calls("get_company_at").size() >= 1, "landing owner gate reads the public company seam")

	var rear_entry: BaseButton = panel.find_child("BankRearEntry", true, false) as BaseButton
	_expect(rear_entry != null, "owner front exposes rear entry")
	if rear_entry != null:
		rear_entry.pressed.emit()
		await process_frame
		await process_frame
		_expect(panel.find_child("SpecialBorrow", true, false) != null, "rear entry reaches the owner special scene")
		var rear_exit: BaseButton = panel.find_child("BankExit", true, false) as BaseButton
		if rear_exit != null:
			rear_exit.pressed.emit()
			await process_frame
			await process_frame
			_expect(panel.find_child("LoanBorrow", true, false) != null, "rear exit returns to front without completing landing")

	var front_exit: BaseButton = panel.find_child("BankExit", true, false) as BaseButton
	_expect(front_exit != null, "landing front exposes a close control")
	if front_exit == null:
		return
	front_exit.pressed.emit()
	await process_frame
	await process_frame
	_expect(not bool(_controller.call("is_open")), "landing front close hides the controller")
	_expect(_public_calls("complete_bank_visit").size() == 1, "landing front close completes exactly once")
	front_exit.emit_signal("pressed")
	await process_frame
	_expect(_public_calls("complete_bank_visit").size() == 1, "duplicate landing close does not complete twice")


func _test_pass_close_cancel_and_stale() -> void:
	_controller.call("cancel")
	_core.calls.clear()
	_set_token("pass", 0, 1)
	_sync(_snapshot())
	var panel := _panel()
	var pass_exit: BaseButton = panel.find_child("ATMExit", true, false) as BaseButton
	_expect(pass_exit != null, "pass ATM exposes a close control")
	if pass_exit != null:
		pass_exit.pressed.emit()
		await process_frame
		await process_frame
		_expect(not bool(_controller.call("is_open")), "pass close hides the ATM before resume")
		_expect(_public_calls("resume_bank_visit").size() == 1, "pass close resumes exactly once through the core seam")
		pass_exit.emit_signal("pressed")
		await process_frame
		_expect(_public_calls("resume_bank_visit").size() == 1, "duplicate pass close does not resume twice")

	_set_token("pass", 0, 1)
	_sync(_snapshot())
	_expect(bool(_controller.call("is_open")), "fresh pass token opens after a completed pass close")
	_controller.call("cancel")
	_expect(not bool(_controller.call("is_open")), "cancel hides an active bank modal")
	_controller.call("cancel")
	_expect(not bool(_controller.call("is_open")), "repeated cancel remains idempotent")

	_set_token("pass", 0, 1)
	_sync(_snapshot())
	_expect(bool(_controller.call("is_open")), "stale test starts from a valid token")
	_core.token = {}
	_sync(_snapshot())
	_expect(not bool(_controller.call("is_open")), "token disappearance cancels a stale modal")


func _test_edition_alias() -> void:
	_controller.call("cancel")
	_set_token("pass", 0, 1)
	_sync(_snapshot(), false, "MJ")
	var panel := _panel()
	_expect(str(panel.call("view_model").get("edition", "")) == "MultiverseJourney", "MJ edition reaches the canonical source presenter")
	_controller.call("cancel")
	_set_token("pass", 0, 1)
	_sync(_snapshot(), false, "invalid-edition")
	_expect(bool(_controller.call("is_open")), "invalid edition falls back without blocking a valid token")


func _invoke_game(method: String, args: Array = []) -> Dictionary:
	_invocations.append([method, args.duplicate(true)])
	var result: Variant = _controller.get("_test_invoke_result")
	return result.duplicate(true) if result is Dictionary else {"ok": false, "message": "測試未設定結果"}


func _handle_result(result: Dictionary) -> void:
	_handled.append(result.duplicate(true))
