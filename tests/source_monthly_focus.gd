extends "res://tests/source_monthly_controller.gd"

const ReportPanel = preload("res://game/ui/source_monthly_panel.gd")

class InitiallyInactivePanel extends "res://game/ui/source_monthly_panel.gd":
	func _application_is_focused() -> bool:
		return false

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
	panel.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	panel.set_auto_advance_seconds(0.5)
	panel.set_view_model(event("dividend").report)
	var closed := [0]
	panel.continued.connect(func() -> void: closed[0] += 1)
	expect(panel.is_model_valid() and panel.is_open(), "focus fixture is a valid visible real dividend report")
	var before: Dictionary = panel.view_model()
	panel.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var remaining: float = panel.get("_timer").time_left
	await create_timer(0.8).timeout
	expect(panel.is_open(), "dividend stays visible while application is inactive")
	expect(closed[0] == 0, "inactive time cannot acknowledge the report")
	expect(is_equal_approx(panel.get("_timer").time_left, remaining), "inactive time preserves the remaining viewing interval")
	expect(panel.view_model() == before, "focus changes do not alter report payload")
	panel.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.7).timeout
	expect(not panel.is_open() and closed[0] == 1, "active viewing resumes the remaining interval and closes once")
	panel.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	panel.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await settle()
	expect(closed[0] == 1, "focus changes after close do not replay acknowledgment")
	panel.queue_free()
	await settle()

	var inactive := InitiallyInactivePanel.new()
	root.add_child(inactive)
	await settle()
	inactive.set_auto_advance_seconds(0.5)
	inactive.set_view_model(event("dividend").report)
	expect(inactive.is_model_valid() and inactive.is_open(), "report created while inactive has a valid source model")
	await create_timer(0.8).timeout
	expect(inactive.is_open(), "new report does not start counting before its first application focus")
	inactive.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.7).timeout
	expect(not inactive.is_open(), "initially inactive report advances after receiving focus")
	inactive.queue_free()
	await settle()
	print("Monthly focus checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
