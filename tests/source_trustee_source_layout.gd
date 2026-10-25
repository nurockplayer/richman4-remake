extends SceneTree
const Dialog = preload("res://game/ui/source_trustee_dialog.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.configure([{"player_id":0,"name":"孫小美","trustee":false,"use_cards":true,"use_tools":true,"personality":1,"cash_ratio":50,"stock_ratio":30}],0,"Game")
	var boxes: Dictionary = dialog.source_hitboxes()
	check(boxes.use_cards[0] == Rect2(287,106,96,18), "card control uses original screen rectangle")
	check(boxes.use_tools[0] == Rect2(287,137,96,18), "tool control uses original screen rectangle")
	check(boxes.cash_ratio[0] == Rect2(310,327,80,24), "cash bar is original eighty logical pixels")
	check(boxes.stock_ratio[0] == Rect2(310,360,80,24), "stock bar uses independent original row")
	check(boxes.accept == Vector2(479,159) and boxes.cancel == Vector2(479,247), "OK and Cancel use original vertical right strip")
	check(boxes.personality.size() == 3, "three original personality hit areas are separate choices")
	click(dialog, Vector2(395,338))
	check(dialog.draft_rows()[0].cash_ratio == 60, "cash arrow release increases by ten")
	click(dialog, Vector2(301,338))
	check(dialog.draft_rows()[0].cash_ratio == 50, "cash arrow release decreases by ten")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(311,338)
	dialog._gui_input(press)
	check(dialog.draft_rows()[0].cash_ratio == 0, "cash bar left endpoint is zero")
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.position = Vector2(390,338)
	dialog._gui_input(drag)
	check(dialog.draft_rows()[0].cash_ratio == 100, "cash drag reaches one hundred at the right endpoint")
	drag.position = Vector2(345,338)
	dialog._gui_input(drag)
	check(dialog.draft_rows()[0].cash_ratio == 40, "cash drag quantizes to ten point steps")
	check(dialog.draft_rows()[0].stock_ratio == 30, "cash drag preserves independent stock ratio")
	dialog.queue_free()
	print("Trustee source layout checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func click(dialog: Control, position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		dialog._gui_input(event)
