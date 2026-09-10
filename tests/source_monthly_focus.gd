extends "res://tests/source_monthly_controller.gd"

const ReportPanel = preload("res://game/ui/source_monthly_panel.gd")

class InitiallyInactivePanel extends "res://game/ui/source_monthly_panel.gd":
	func _application_is_focused() -> bool:
		return false

var focus_audit: Array = []
var audit_panel: Control
var audit_closed: Array = [0]

func _notification(what: int) -> void:
	if what in [Node.NOTIFICATION_APPLICATION_FOCUS_IN, Node.NOTIFICATION_APPLICATION_FOCUS_OUT]:
		record_focus("OS_IN" if what == Node.NOTIFICATION_APPLICATION_FOCUS_IN else "OS_OUT")

func record_focus(reason: String) -> void:
	var entry := {"event": reason, "ms": Time.get_ticks_msec(), "windows": [], "closed": audit_closed[0]}
	if DisplayServer.get_name() != "headless":
		for window_id in DisplayServer.get_window_list():
			entry.windows.append({"id": window_id, "focused": DisplayServer.window_is_focused(window_id)})
	if audit_panel != null and is_instance_valid(audit_panel):
		var timer: Timer = audit_panel.get("_timer")
		entry.merge({"active": audit_panel.get("_application_active"), "paused": timer.paused, "stopped": timer.is_stopped(), "time_left": timer.time_left, "open": audit_panel.is_open(), "visible": audit_panel.visible, "continued": audit_panel.get("_continued_emitted")})
	focus_audit.append(entry)
	if focus_audit.size() > 64: focus_audit.pop_front()

func inject_focus(panel: Control, what: int) -> void:
	audit_panel = panel
	var label := "INJECT_IN" if what == Node.NOTIFICATION_APPLICATION_FOCUS_IN else "INJECT_OUT"
	record_focus(label + "_BEFORE")
	panel.notification(what)
	record_focus(label + "_AFTER")

func wait_for_close(panel: Control) -> void:
	# Wait for the observable node timer outcome; native frame scheduling can
	# deliver a SceneTreeTimer before the presenter Timer in the same frame.
	record_focus("RESUME_WAIT_BEGIN")
	var deadline := Time.get_ticks_msec() + 2000
	while panel.is_open() and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	record_focus("RESUME_WAIT_DEADLINE" if panel.is_open() else "RESUME_WAIT_CLOSED")

func run() -> void:
	# Native launch focus arrives after initial scene frames on macOS. Wait for
	# that real startup event before deliberately simulating an inactive app.
	if DisplayServer.get_name() != "headless":
		for attempt in range(300):
			if DisplayServer.window_is_focused():
				break
			await create_timer(0.01).timeout
		await settle()
	expect(DisplayServer.get_name() == "headless" or DisplayServer.window_is_focused(), "native startup focus is established before injected transitions")
	# Focus notifications are injected into the real native/headless Node. This
	# proves the lifecycle boundary, not an ordinary OS application switch.
	var panel := ReportPanel.new()
	root.add_child(panel)
	await settle()
	inject_focus(panel, Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	panel.set_auto_advance_seconds(0.5)
	panel.set_view_model(event("dividend").report)
	var closed := [0]
	audit_closed = closed
	panel.continued.connect(func() -> void: closed[0] += 1)
	panel.continued.connect(func() -> void: record_focus("CONTINUED"))
	panel.get("_timer").timeout.connect(func() -> void: record_focus("TIMER_TIMEOUT"))
	expect(panel.is_model_valid() and panel.is_open(), "focus fixture is a valid visible real dividend report")
	var before: Dictionary = panel.view_model()
	inject_focus(panel, Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var remaining: float = panel.get("_timer").time_left
	await create_timer(0.8).timeout
	expect(panel.is_open(), "dividend stays visible while application is inactive")
	expect(closed[0] == 0, "inactive time cannot acknowledge the report")
	expect(is_equal_approx(panel.get("_timer").time_left, remaining), "inactive time preserves the remaining viewing interval")
	expect(panel.view_model() == before, "focus changes do not alter report payload")
	inject_focus(panel, Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await wait_for_close(panel)
	expect(not panel.is_open() and closed[0] == 1, "active viewing resumes the remaining interval and closes once")
	inject_focus(panel, Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	inject_focus(panel, Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await settle()
	expect(closed[0] == 1, "focus changes after close do not replay acknowledgment")
	panel.queue_free()
	await settle()

	var inactive := InitiallyInactivePanel.new()
	audit_panel = inactive
	root.add_child(inactive)
	await settle()
	inactive.get("_timer").timeout.connect(func() -> void: record_focus("INITIAL_INACTIVE_TIMEOUT"))
	inactive.set_auto_advance_seconds(0.5)
	inactive.set_view_model(event("dividend").report)
	expect(inactive.is_model_valid() and inactive.is_open(), "report created while inactive has a valid source model")
	await create_timer(0.8).timeout
	expect(inactive.is_open(), "new report does not start counting before its first application focus")
	inject_focus(inactive, Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await wait_for_close(inactive)
	expect(not inactive.is_open(), "initially inactive report advances after receiving focus")
	inactive.queue_free()
	await settle()
	if failures:
		print("FOCUS_AUDIT ", JSON.stringify(focus_audit))
	print("Monthly focus checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
