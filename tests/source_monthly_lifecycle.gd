extends "res://tests/source_monthly_controller.gd"

const Controller = preload("res://game/ui/source_monthly_controller.gd")
const ReportPanel = preload("res://game/ui/source_monthly_panel.gd")

func run() -> void:
	var controller := Controller.new()
	controller.panel_factory = func() -> Control:
		var panel := ReportPanel.new()
		panel.auto_advance_seconds = 0.5
		return panel
	root.add_child(controller)
	await settle()
	var owner := RefCounted.new()
	var before := {"event_log": [{"type": "turn_started", "day": 14, "turn": 1}]}
	var after := {"event_log": before.event_log + [event("dividend")]}
	controller.capture_transition(owner, before, after)
	controller.sync(owner, false)
	expect(controller.is_open() and controller.report_panel.is_model_valid(), "real presenter accepts the source-shaped report")
	expect(controller.report_panel.is_inside_tree(), "host attaches the report to its scene")
	var panel: Control = controller.report_panel
	await create_timer(0.02).timeout
	controller.sync(owner, false)
	expect(controller.report_panel == panel, "refresh keeps the existing timed report")
	await create_timer(0.8).timeout
	await settle()
	expect(not controller.is_open(), "real dividend presenter automatically advances through the host lifecycle")
	controller.capture_transition(owner, before, after)
	expect(not controller.is_open(), "timer acknowledgment retains duplicate-delivery protection")
	controller.queue_free()
	await settle()
	print("Monthly lifecycle checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
