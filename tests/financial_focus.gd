extends SceneTree
const FinancePanel = preload("res://game/ui/financial_presentation.gd")
var checks := 0
var failures := 0
var answers: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var panel := FinancePanel.new()
	root.add_child(panel)
	panel.answered.connect(func(params: Dictionary): answers.append(params))
	var snapshot := {
		"players": [{"name": "施卡者", "alive": true, "is_human": false}, {"name": "付款者", "alive": true, "is_human": true}],
		"pending_finance": {"kind": "tax", "stage": "free", "payer_id": 1, "creditor_id": 0, "amount": 3001, "node_id": 0, "caster_id": 0}
	}
	await process_frame
	panel.sync(snapshot, [])
	await create_timer(0.1).timeout
	check(panel.visible and panel.exclusive and not panel.popup_window, "financial response is a persistent exclusive window")
	check(panel.prompt.text.contains("3,001") and panel.prompt.text.contains("查稅"), "pending amount and cause are visible")
	root.grab_focus()
	panel.notification(Window.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await create_timer(0.1).timeout
	check(panel.visible and answers.is_empty(), "focus loss cannot implicitly answer")
	panel.sync(snapshot, [])
	check(answers.is_empty() and panel.visible, "unchanged refresh cannot answer or close")
	panel.accept.pressed.emit()
	check(answers == [{"cancel": false}], "explicit accept sends only the selected free decision")
	answers.clear()
	snapshot.pending_finance.stage = "redirect"
	panel.sync(snapshot, [0])
	check(panel.target.visible and panel.target.get_selected_id() == 0, "redirect can select the caster")
	panel.accept.pressed.emit()
	check(answers == [{"cancel": false, "target_id": 0}], "redirect emits explicit target identity")
	answers.clear()
	panel.decline.pressed.emit()
	check(answers == [{"cancel": true}], "explicit decline remains distinct from focus changes")
	answers.clear()
	panel.sync({}, [])
	await process_frame
	check(not panel.visible and answers.is_empty(), "new or loaded inactive snapshot closes without response")
	panel.queue_free()
	print("Financial focus checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
