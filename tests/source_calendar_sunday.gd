extends SceneTree

## Focused Sunday-red regression.  Dates are valid source-calendar fixtures;
## the test checks both day-style labels and snapshot immutability.

const PANEL_SCRIPT_PATH := "res://game/ui/source_calendar_panel.gd"
const NORMAL_INK := Color("#101010")
const SUNDAY_RED := Color("#ff0000")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _settle() -> void:
	await process_frame
	await process_frame


func _new_panel() -> Control:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var script: Variant = load(PANEL_SCRIPT_PATH)
	var panel: Control = script.new()
	viewport.add_child(panel)
	return panel


func _find(panel: Node, node_name: String) -> Label:
	return panel.find_child(node_name, true, false) as Label


func _run() -> void:
	if not FileAccess.file_exists(PANEL_SCRIPT_PATH):
		checks += 1
		failures += 1
		print("Source calendar Sunday RED: implementation absent; checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var script: Variant = load(PANEL_SCRIPT_PATH)
	if script == null:
		checks += 1
		failures += 1
		print("Source calendar Sunday RED: script could not load")
		quit(1)
		return
	var panel := _new_panel()
	await _settle()
	_expect(bool(panel.call("set_style", "day")), "day style accepts valid style")
	var cases := [
		{"date": {"year": 2024, "month": 3, "day": 2}, "sunday": false},
		{"date": {"year": 2024, "month": 3, "day": 3}, "sunday": true},
		{"date": {"year": 2024, "month": 3, "day": 4}, "sunday": false},
	]
	for case_value in cases:
		var date_value: Dictionary = case_value["date"].duplicate(true)
		var snapshot := {"edition": "Game", "date": date_value}
		var before := snapshot.duplicate(true)
		_expect(bool(panel.call("present", snapshot)), "valid source date presents %s" % date_value)
		await _settle()
		var day := _find(panel, "SourceCalendarDay")
		var weekday := _find(panel, "SourceCalendarWeekday")
		_expect(day != null and weekday != null, "day and weekday labels render for %s" % date_value)
		var expected := SUNDAY_RED if bool(case_value["sunday"]) else NORMAL_INK
		if day != null:
			_expect_equal(day.get_theme_color("font_color"), expected, "day label Sunday color for %s" % date_value)
		if weekday != null:
			_expect_equal(weekday.get_theme_color("font_color"), expected, "weekday Sunday color for %s" % date_value)
		_expect_equal(snapshot, before, "present does not mutate date snapshot for %s" % date_value)
	panel.queue_free()
	await _settle()
	print("Source calendar Sunday checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
