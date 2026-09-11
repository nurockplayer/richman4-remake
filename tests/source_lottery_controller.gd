extends "res://tests/source_lottery_core.gd"
const Controller = preload("res://game/ui/source_lottery_controller.gd")
class PanelDouble extends Control:
	signal ticket_selected(number: int)
	signal cancelled
	signal continued
	var model: Dictionary
	func set_visuals(_value: Variant) -> void: pass
	func set_view_model(value: Dictionary) -> void: model = value.duplicate(true)
var intents := 0
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	await process_frame
	await process_frame
func run() -> void:
	var controller := Controller.new()
	controller.panel_factory = func() -> Control: return PanelDouble.new()
	root.add_child(controller)
	var game = fresh()
	controller.sync(game, false)
	expect(not controller.is_open(), "initial sync cannot replay events")
	enter(game)
	controller.sync(game, true)
	expect(controller.is_open() and controller.report_panel == null, "pending purchase guards immediately while movement blocks display")
	controller.sync(game, false)
	expect(controller.report_panel != null and controller.current_report().kind == "purchase", "purchase shows when unblocked")
	controller.action_requested.connect(func(_method: String, _args: Array) -> void: intents += 1)
	var old_panel: Control = controller.report_panel
	old_panel.ticket_selected.emit(1)
	old_panel.ticket_selected.emit(1)
	expect(intents == 1, "duplicate purchase callback dispatched once")
	controller.apply_action_result({"ok": false})
	old_panel.cancelled.emit()
	expect(intents == 2, "rejected action keeps cancellation available")
	game.leave_lottery()
	controller.apply_action_result({"ok": true})
	old_panel.cancelled.emit()
	await settle()
	expect(not controller.is_open() and intents == 2, "successful exit invalidates stale callback")
	var before := {"event_log": [{"type":"turn_started","day":14,"turn":1}]}
	var report := {"kind":"draw","edition":"Game","number":1,"winner_id":0,"amount":1000,"jackpot":1000,"tickets":game.state.lottery_tickets.duplicate(),"players":[{"id":0,"name":"測試","character_id":0,"alive":true}]}
	var after := {"event_log": before.event_log + [{"type":"lottery_draw","day":15,"turn":2,"report":report}]}
	controller.capture_transition(game, before, after)
	controller.capture_transition(game, before, after)
	expect(controller.pending_count() == 1, "duplicate draw event queues once")
	controller.sync(game, true)
	expect(controller.report_panel == null, "monthly report blocks lottery display")
	controller.sync(game, false)
	var draw_panel: Control = controller.report_panel
	var financial_before: Dictionary = game.to_dict()
	draw_panel.continued.emit()
	draw_panel.continued.emit()
	await settle()
	expect(not controller.is_open() and game.to_dict() == financial_before, "draw double-close neither pays nor consumes RNG")
	controller.capture_transition(game, before, after)
	expect(not controller.is_open(), "historical duplicate cannot reopen draw")
	controller.capture_transition(game, after, {"event_log":after.event_log + [{"type":"lottery_draw","day":45,"turn":3,"report":report}]})
	controller.sync(game, false)
	var stale_callback: Callable = controller.report_panel.continued.get_connections()[0].callable
	var replacement = fresh(43)
	controller.sync(replacement, false)
	stale_callback.call()
	await settle()
	expect(not controller.is_open(), "owner replacement invalidates old display callbacks")
	controller.queue_free()
	await settle()
	print("Lottery controller checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
