extends "res://tests/source_date_panel.gd"

## Source date warning geometry regression.  The source frame is opaque, so an
## invalid-date hint must occupy the spare area without covering real controls
## or any day cell in the current month.

func _intersects(left: Rect2, right: Rect2) -> bool:
	return left.intersects(right)


func _run() -> void:
	var pair := _new_panel()
	var viewport: SubViewport = pair.viewport
	var panel: Control = pair.panel
	var visuals := FakeVisuals.new()
	await _present(
		panel,
		_model({"year": 2023, "month": 3, "day": 31}, {"year": 2026, "month": 9, "day": 11}),
		visuals,
	)
	_expect(bool(panel.call("is_model_valid")) and bool(panel.call("source_art_available")), "invalid-date layout fixture has source art")
	# March 31 -> April 31 preserves the source day byte while making the draft
	# invalid.  April 2023 has six rows; April 30 is on the bottom row at y=170.
	await _push_click(viewport, Vector2(74.0 + 8.0, 31.0 + 5.0))
	_expect_equal(panel.call("draft_date"), {"year": 2023, "month": 4, "day": 31}, "fixture retains invalid April 31 draft")
	await _push_click(viewport, HITBOXES.accept.get_center())
	_expect(not bool(panel.call("is_draft_date_valid")) and bool(panel.call("invalid_confirm_visible")), "invalid April draft shows a visible warning")
	var hint := _find(panel, "SourceDateInvalidConfirm") as Label
	var frame := _find(panel, "SourceDateFrame") as TextureRect
	_expect(hint != null and frame != null, "invalid warning and opaque source frame are present")
	if hint == null or frame == null:
		viewport.queue_free()
		await _settle()
		print("Source date hint layout checks: %d, failures: %d" % [checks, failures])
		quit(1 if failures else 0)
		return
	var hint_rect := hint.get_rect()
	_expect(hint.z_index > frame.z_index or hint.get_index() > frame.get_index(), "invalid warning draws above the opaque source frame")
	var centers: Dictionary = panel.call("day_centers")
	for day in centers:
		var center: Vector2 = centers[day]
		var day_rect := Rect2(FRAME_ORIGIN + center - Vector2(10.0, 8.0), Vector2(20.0, 16.0))
		_expect(not _intersects(hint_rect, day_rect), "invalid warning does not cover day %s" % str(day))
	for control_name in ["SourceDateMonth", "SourceDateYear", "SourceDateSystemLabel", "SourceDateCancelLabel", "SourceDateAcceptLabel"]:
		var control := _find(panel, control_name) as Control
		_expect(control != null and not _intersects(hint_rect, control.get_rect()), "invalid warning does not cover " + control_name)
	viewport.queue_free()
	await _settle()
	print("Source date hint layout checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
