extends SceneTree

var checks := 0
var failures := 0
class ReportDouble extends Control:
	signal continued
	var model: Dictionary = {}
	func set_view_model(value: Dictionary) -> void: model = value.duplicate(true)
	func set_visuals(_value: Variant) -> void: pass
	func view_model() -> Dictionary: return model.duplicate(true)

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)

func event(kind: String, turn: int = 1) -> Dictionary:
	return {"type": "monthly_statement", "day": 15, "turn": turn, "report": {"kind": kind, "edition": "Game", "date": {"year": 1998, "month": 1, "day": 15}, "players": [{"id": 0, "name": "測試", "character_id": 0, "total": 10}], "companies": []}}

func _initialize() -> void: call_deferred("run")
func settle() -> void:
	await process_frame
	await process_frame

func run() -> void:
	var exists := ResourceLoader.exists("res://game/ui/source_monthly_controller.gd")
	expect(exists, "source monthly controller exists")
	if not exists:
		print("Monthly controller checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var script: Script = load("res://game/ui/source_monthly_controller.gd")
	var controller: Control = script.new()
	controller.panel_factory = func() -> Control: return ReportDouble.new()
	root.add_child(controller)
	var owner := RefCounted.new()
	var replacement := RefCounted.new()
	var before := {"event_log": [{"type": "turn_started", "day": 14, "turn": 1}]}
	var after := {"event_log": before.event_log + [event("dividend")]}
	controller.sync(owner, false)
	expect(not controller.is_open(), "initial sync does not replay old history")
	controller.capture_transition(owner, before, after)
	expect(controller.is_open() and controller.pending_count() == 1, "fresh report queues immediately for modal guards")
	controller.sync(owner, true)
	expect(controller.report_panel == null or not controller.report_panel.visible, "movement or another presentation delays report visibility")
	controller.capture_transition(owner, before, after)
	expect(controller.pending_count() == 1, "duplicate delivery does not queue twice")
	controller.sync(owner, false)
	expect(controller.report_panel != null and controller.report_panel.visible, "unblocked queue presents report")
	var panel: Control = controller.report_panel
	controller.sync(owner, false)
	expect(controller.report_panel == panel, "repeated refresh preserves active report lifetime")
	var model: Dictionary = controller.current_report()
	model.players[0].total = 999
	expect(controller.current_report().players[0].total == 10, "public report is detached from queue state")
	after.event_log[-1].report.players[0].total = 999
	expect(controller.current_report().players[0].total == 10, "host input dictionaries are detached")
	var next := {"event_log": after.event_log + [event("interest", 2)]}
	controller.capture_transition(owner, after, next)
	expect(controller.pending_count() == 2 and controller.report_panel == panel, "next report queues behind the current one")
	panel.continued.emit()
	panel.continued.emit()
	expect(controller.is_open(), "deferred transition remains modal while next report is pending")
	await settle()
	expect(controller.pending_count() == 1 and controller.current_report().kind == "interest", "double close cannot skip the second report")
	controller.report_panel.continued.emit()
	await settle()
	expect(not controller.is_open(), "final close releases the queue")
	controller.capture_transition(owner, after, next)
	expect(not controller.is_open(), "late duplicate delivery cannot reopen an acknowledged report")
	controller.sync(replacement, false)
	expect(not controller.is_open(), "replacement does not adopt old reports")
	controller.capture_transition(replacement, before, {"event_log": before.event_log + [event("dividend")]})
	controller.sync(replacement, false)
	expect(controller.is_open(), "new game can produce the same financial report")
	controller.report_panel.continued.emit()
	controller.cancel()
	controller.sync(owner, false)
	await settle()
	expect(not controller.is_open(), "cancel invalidates queued deferred presentation")
	var full: Array = []
	for index in range(200): full.append({"type": "turn_started", "day": index + 1, "turn": index + 1})
	var slid: Array = full.slice(1) + [event("dividend", 201)]
	controller.capture_transition(owner, {"event_log": full}, {"event_log": slid})
	controller.sync(owner, false)
	expect(controller.is_open(), "bounded log rollover retains a provably fresh report")
	controller.cancel()
	controller.capture_transition(owner, {"event_log": full}, {"event_log": [event("dividend")]})
	expect(not controller.is_open(), "unrelated or rewound log does not replay a historical report")
	controller.queue_free()
	await settle()
	print("Monthly controller checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
