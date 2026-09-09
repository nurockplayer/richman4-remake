extends SceneTree
const Panel = preload("res://game/ui/news_panel.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func snapshot(draw: int) -> Dictionary:
	return {"news": {"draw_count": draw, "last": {"summary": "測試新聞%d" % draw}}, "event_log": [{"type": "news_applied", "draw_count": draw}]}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var panel = Panel.new()
	root.add_child(panel)
	check(panel.get("display_seconds") == 2.4, "news defaults to a 2.4 second presentation")
	if panel.get("display_seconds") != null: panel.set("display_seconds", 0.08)
	var first := snapshot(1)
	var before := first.duplicate(true)
	panel.sync_snapshot(first)
	check(panel.visible, "new result is initially visible")
	await create_timer(0.14).timeout
	check(not panel.visible, "news closes automatically so AI can continue")
	check(first == before, "timing never mutates the source snapshot")
	panel.sync_snapshot(first)
	check(not panel.visible, "refresh does not restart a completed timer")
	panel.sync_snapshot(snapshot(2))
	await create_timer(0.04).timeout
	panel.sync_snapshot(snapshot(3))
	await create_timer(0.05).timeout
	check(panel.visible, "old result timer cannot dismiss a newer result")
	await create_timer(0.09).timeout
	check(not panel.visible, "new result closes on its own timer")
	panel.sync_snapshot(snapshot(4))
	check(panel.has_method("cancel_presentation"), "result presentation supports generation cancellation")
	if panel.has_method("cancel_presentation"): panel.cancel_presentation()
	check(not panel.visible, "new/load cancellation hides the old result")
	panel.sync_snapshot({})
	panel.sync_snapshot(snapshot(1))
	check(panel.visible, "fresh match can present draw one again")
	panel.get_node("MarginContainer/VBoxContainer/CloseNews").pressed.emit()
	check(not panel.visible, "manual early close remains available")
	await create_timer(0.14).timeout
	check(not panel.visible, "cancelled timers never reopen a result")
	panel.queue_free()
	print("News timing checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
