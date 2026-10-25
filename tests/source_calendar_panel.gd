extends SceneTree

## Focused checks for the reusable source calendar child.
##
## The panel receives a detached snapshot and an injected source-art resolver;
## it never constructs GameState or consults the system clock.  Missing script
## is reported as availability RED before any behavioural assertion runs.

const PANEL_SCRIPT_PATH := "res://game/ui/source_calendar_panel.gd"
const LOGICAL_SIZE := Vector2(200, 200)
const MONTH_LABELS := [
	"一月", "二月", "三月", "四月", "五月", "六月",
	"七月", "八月", "九月", "十月", "十一月", "十二月",
]

var checks := 0
var failures := 0


class FakeVisuals extends RefCounted:
	var calls: Array = []
	var physical_scale := 2

	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		calls.append([edition, archive, resource, chunk])
		var image := Image.create(200 * physical_scale, 200 * physical_scale, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.1 + 0.02 * float(chunk), 0.35, 0.55, 1.0))
		return {
			"edition": edition,
			"archive": archive,
			"resource": resource,
			"chunk": chunk,
			"logical": {"width": 200.0, "height": 200.0, "anchor_x": 0.0, "anchor_y": 0.0},
			"texture": ImageTexture.create_from_image(image),
		}


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


func _snapshot(date: Dictionary, edition := "Game") -> Dictionary:
	return {"edition": edition, "date": date.duplicate(true)}


func _new_panel() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var script: Variant = load(PANEL_SCRIPT_PATH)
	var panel: Control = script.new()
	viewport.add_child(panel)
	return {"viewport": viewport, "panel": panel}


func _find(panel: Node, name_value: String) -> Node:
	return panel.find_child(name_value, true, false)


func _run() -> void:
	if not FileAccess.file_exists(PANEL_SCRIPT_PATH):
		checks += 1
		failures += 1
		print("Source calendar panel RED: implementation absent; checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var script: Variant = load(PANEL_SCRIPT_PATH)
	if script == null:
		checks += 1
		failures += 1
		print("Source calendar panel RED: script could not load")
		quit(1)
		return
	var pair := _new_panel()
	var viewport: SubViewport = pair["viewport"]
	var panel: Control = pair["panel"]
	await _settle()
	_test_api(panel)
	if failures == 0:
		await _test_calendar(panel)
		await _test_invalid_and_edition(panel)
		await _test_art_scale(panel)
	viewport.queue_free()
	await _settle()
	print("Source calendar panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _test_api(panel: Control) -> void:
	for method in ["configure_assets", "present", "set_style", "style", "source_geometry", "source_hitboxes", "day_centers", "source_frames", "source_art_status", "is_snapshot_valid", "season_index"]:
		_expect(panel.has_method(method), "calendar panel exposes %s" % method)
	_expect(panel.has_signal("style_changed"), "calendar panel exposes style_changed signal")
	_expect_equal(panel.size, LOGICAL_SIZE, "calendar panel keeps 200x200 logical size")
	_expect_equal(panel.mouse_filter, Control.MOUSE_FILTER_STOP, "calendar panel consumes pointer input")


func _test_calendar(panel: Control) -> void:
	var visuals := FakeVisuals.new()
	panel.call("configure_assets", visuals, "Game")
	_expect(bool(panel.call("present", _snapshot({"year": 2024, "month": 2, "day": 29}))), "2024 leap date presents")
	await _settle()
	_expect(bool(panel.call("is_snapshot_valid")), "valid snapshot is accepted")
	_expect_equal(panel.call("style"), "day", "day style is default")
	_expect_equal(panel.call("season_index"), 0, "February follows source spring season")
	_expect(_find(panel, "SourceCalendarDay") != null, "day presenter is rendered")
	_expect(_find(panel, "SourceCalendarCurrentDayBox") == null, "day presenter does not use month current-day box")
	_expect(_find(panel, "SourceCalendarWeekday") != null, "day presenter renders weekday text")
	_expect_equal((_find(panel, "SourceCalendarMonth") as Label).get_theme_font_size("font_size"), 28, "day month uses source font 28")
	_expect_equal((_find(panel, "SourceCalendarYear") as Label).get_theme_font_size("font_size"), 24, "day year uses source font 24")
	_expect_equal((_find(panel, "SourceCalendarDay") as Label).get_theme_font_size("font_size"), 60, "day number uses source font 60")
	_expect_equal((_find(panel, "SourceCalendarWeekday") as Label).get_theme_font_size("font_size"), 16, "weekday uses source font 16")
	var day_centers: Dictionary = panel.call("day_centers")
	_expect(day_centers.has(29), "leap day is present in February 2024")
	_expect_equal(day_centers.size(), 29, "February 2024 has 29 day centers")
	var geometry: Dictionary = panel.call("source_geometry")
	_expect_equal(geometry.get("logical_size"), LOGICAL_SIZE, "geometry reports source logical 200x200")
	_expect_equal(geometry.get("month_grid", {}).get("weekday_origin"), Vector2(30, 80), "month grid keeps source weekday origin")
	_expect_equal(geometry.get("month_grid", {}).get("year_origin"), Vector2(140, 8), "month grid keeps source year origin")
	var hitboxes: Dictionary = panel.call("source_hitboxes")
	_expect_equal(hitboxes.get("sun"), Rect2(8, 8, 27, 27), "sun hitbox preserves translated source bounds")
	_expect_equal(hitboxes.get("moon"), Rect2(38, 8, 27, 27), "moon hitbox preserves translated source bounds")
	_expect_equal(panel.call("source_global_hitboxes").get("sun"), Rect2(448, 288, 27, 27), "sun hitbox exposes source global bounds")
	_expect(bool(panel.call("set_style", "month")), "month style is selectable")
	await _settle()
	_expect_equal(panel.call("style"), "month", "month style is exposed")
	_expect(_find(panel, "SourceCalendarMonth") != null, "month presenter is rendered")
	_expect(_find(panel, "SourceCalendarWeekday0") == null, "month background owns its source weekday markers")
	_expect(_find(panel, "SourceCalendarDay29") != null, "month presenter renders leap day")
	_expect_equal((_find(panel, "SourceCalendarMonth") as Label).get_theme_font_size("font_size"), 28, "month title uses source font 28")
	_expect_equal((_find(panel, "SourceCalendarYear") as Label).get_theme_font_size("font_size"), 24, "month year uses source font 24")
	var month_box := _find(panel, "SourceCalendarCurrentDayBox") as Panel
	_expect(month_box != null, "month presenter renders current-day outline")
	if month_box != null:
		_expect_equal(month_box.size, Vector2(20, 14), "current-day outline keeps source size")
	_expect(bool(panel.call("set_style", "day")), "day style is selectable again")
	await _settle()
	# Source calendar preserves the deliberately divisible-by-four leap rule.
	_expect(bool(panel.call("present", _snapshot({"year": 2100, "month": 2, "day": 29}))), "2100 leap date follows source rule")
	_expect_equal(panel.call("day_centers").size(), 29, "2100 February has 29 source days")
	# August 1998 starts Saturday and requires a complete six-row grid.
	panel.call("present", _snapshot({"year": 1998, "month": 8, "day": 31}))
	await _settle()
	panel.call("set_style", "month")
	await _settle()
	var six_week_centers: Dictionary = panel.call("day_centers")
	_expect_equal(six_week_centers[31].y, 168.0, "six-week month keeps day 31 in row six")
	_expect(_find(panel, "SourceCalendarDay31") != null, "six-week month renders final day")


func _test_invalid_and_edition(panel: Control) -> void:
	for date in [{"year": 1997, "month": 1, "day": 1}, {"year": 2024, "month": 2, "day": 30}, {"year": 2024, "month": 13, "day": 1}]:
		_expect(not bool(panel.call("present", _snapshot(date))), "invalid date is rejected")
		_expect(not bool(panel.call("is_snapshot_valid")), "invalid date reports unavailable")
		_expect(_find(panel, "SourceCalendarUnavailable") != null, "invalid date renders explicit unavailable state")
	_expect(not bool(panel.call("present", _snapshot({"year": 2024, "month": 1, "day": 1}, "Unknown"))), "unknown edition fails closed")
	_expect(not bool(panel.call("set_style", "other")), "unknown style is rejected")


func _test_art_scale(panel: Control) -> void:
	var visuals := FakeVisuals.new()
	panel.call("configure_assets", visuals, "Game")
	panel.call("set_style", "day")
	panel.call("present", _snapshot({"year": 2024, "month": 1, "day": 1}))
	await _settle()
	var frames: Dictionary = panel.call("source_frames")
	_expect(frames.has("Panel2.3"), "day style resolves seasonal Panel2 chunk")
	_expect(frames.has("Panel2.8"), "day style resolves sun icon Panel2 chunk")
	var art := _find(panel, "SourceCalendarArt") as TextureRect
	_expect(art != null and art.texture != null, "calendar source art is rendered")
	var sun := _find(panel, "SourceCalendarSun") as TextureRect
	var moon := _find(panel, "SourceCalendarMoon") as TextureRect
	_expect(sun != null and sun.size == Vector2(24, 23), "sun overlay keeps native logical bounds")
	_expect(moon != null and moon.size == Vector2(20, 20), "moon overlay keeps native logical bounds")
	if art != null:
		_expect_equal(art.size, LOGICAL_SIZE, "2x texture is drawn at 200x200 logical size")
		_expect_equal(Vector2(art.texture.get_size()), Vector2(400, 400), "2x source texture remains physical 400x400")
	panel.call("set_style", "month")
	await _settle()
	frames = panel.call("source_frames")
	_expect(frames.has("Panel2.7"), "month style resolves complete Panel2 chunk")
	_expect(bool(panel.call("source_art_available")), "complete source resolver reports art available")
