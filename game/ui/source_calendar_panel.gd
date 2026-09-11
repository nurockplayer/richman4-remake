extends Control
class_name RichmanSourceCalendarPanel

## Reusable source calendar child presenter.
##
## The host supplies a detached snapshot and an already-loaded source-art
## catalog.  This control owns presentation only: it does not read the clock,
## mutate GameState, or persist the selected calendar style.

const GameCalendar = preload("res://game/core/game_calendar.gd")

const LOGICAL_SIZE := Vector2(200.0, 200.0)
const SOURCE_ORIGIN := Vector2(440.0, 280.0)
const VALID_EDITIONS := ["Game", "MultiverseJourney"]
const ARCHIVE := "Panel"
const SOURCE_RESOURCE := 2
const MONTH_LABELS := [
	"一月", "二月", "三月", "四月", "五月", "六月",
	"七月", "八月", "九月", "十月", "十一月", "十二月",
]
const WEEKDAY_LABELS := ["日", "一", "二", "三", "四", "五", "六"]
# Source ref_00475218: Jan winter, Feb-Apr spring, May-Jul summer,
# Aug-Oct autumn, Nov-Dec winter.
const SOURCE_SEASONS := [3, 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3]
const SUN_CHUNK := 8
const MOON_CHUNK := 11
const MONTH_BASE_CHUNK := 4
const DAY_BASE_CHUNK := 0
const STYLE_DAY := "day"
const STYLE_MONTH := "month"
const DAY_CENTERS_ORIGIN := Vector2(30.0, 98.0)
const DAY_COLUMN_STEP := 23.0
const DAY_ROW_STEP := 14.0
const DAY_BOX_SIZE := Vector2(20.0, 14.0)
const HITBOXES := {
	"sun": Rect2(8.0, 8.0, 27.0, 27.0),
	"moon": Rect2(38.0, 8.0, 27.0, 27.0),
}

signal style_changed(style_name: String)

var _catalog: Variant = null
var _edition := "Game"
var _snapshot: Dictionary = {}
var _snapshot_valid := false
var _style := STYLE_DAY
var _input_guard: Callable = Callable()
var _surface: Control
var background_art: TextureRect
var _fallback: ColorRect
var _unavailable: Label
var _built := false
var _source_frames: Dictionary = {}
var _source_art_status: Dictionary = {}
var _source_art_available := false


func _init() -> void:
	name = "SourceCalendarPanel"
	size = LOGICAL_SIZE
	custom_minimum_size = LOGICAL_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Calendar controls are source mouse regions; keyboard focus belongs to the
	# host shell so hidden view-1 children cannot capture Tab traversal.
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build()


func _ready() -> void:
	size = LOGICAL_SIZE
	custom_minimum_size = LOGICAL_SIZE


## Install an already-loaded source visual catalog.  A dictionary is copied;
## resolver objects and callables are borrowed without performing IO here.
func configure_assets(catalog: Variant, edition: String = "") -> void:
	if catalog is Dictionary:
		_catalog = (catalog as Dictionary).duplicate(true)
	else:
		_catalog = catalog
	if edition in VALID_EDITIONS:
		_edition = edition
	_render()


## Compatibility spelling used by other source presenters.
func set_visuals(catalog: Variant, edition: String = "") -> void:
	configure_assets(catalog, edition)


func set_visual_accessor(catalog: Variant) -> void:
	configure_assets(catalog)


## Present a detached snapshot.  Only snapshot.date is required; a snapshot
## edition overrides the configured edition when it is valid.
func present(snapshot: Dictionary) -> bool:
	_snapshot = snapshot.duplicate(true)
	var requested_edition := str(_snapshot.get("edition", _edition)).strip_edges()
	if requested_edition in VALID_EDITIONS:
		_edition = requested_edition
	_snapshot_valid = _validate_snapshot(_snapshot)
	_render()
	show()
	return _snapshot_valid


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func view_model() -> Dictionary:
	return snapshot()


func is_snapshot_valid() -> bool:
	return _snapshot_valid


func is_model_valid() -> bool:
	return is_snapshot_valid()


func source_art_available() -> bool:
	return _source_art_available


func has_source_art() -> bool:
	return source_art_available()


func source_art_status() -> Dictionary:
	return _source_art_status.duplicate(true)


func source_frames() -> Dictionary:
	return _source_frames.duplicate(true)


func get_source_frames() -> Dictionary:
	return source_frames()


func set_style(style_name: String) -> bool:
	var normalized := style_name.strip_edges().to_lower()
	if normalized not in [STYLE_DAY, STYLE_MONTH] or not _input_allowed("style"):
		return false
	return _apply_style(normalized)


func _apply_style(normalized: String) -> bool:
	if _style == normalized:
		_render()
		return true
	_style = normalized
	_render()
	style_changed.emit(_style)
	return true


func style() -> String:
	return _style


func set_input_guard(guard: Callable) -> void:
	_input_guard = guard


func source_hitboxes() -> Dictionary:
	return HITBOXES.duplicate(true)


func get_source_hitboxes() -> Dictionary:
	return source_hitboxes()


func source_global_hitboxes() -> Dictionary:
	var result: Dictionary = {}
	for key in HITBOXES:
		result[key] = Rect2(SOURCE_ORIGIN + HITBOXES[key].position, HITBOXES[key].size)
	return result


func season_index(month: int = -1) -> int:
	var selected := month
	if selected < 1 or selected > 12:
		selected = int(_snapshot.get("date", {}).get("month", 0))
	return SOURCE_SEASONS[selected - 1] if selected >= 1 and selected <= 12 else -1


func day_centers(year: int = -1, month: int = -1) -> Dictionary:
	var date_value: Variant = _snapshot.get("date", {})
	var selected_year := year if year >= GameCalendar.MIN_YEAR and year <= GameCalendar.MAX_YEAR else int(date_value.get("year", 0)) if date_value is Dictionary else 0
	var selected_month := month if month >= 1 and month <= 12 else int(date_value.get("month", 0)) if date_value is Dictionary else 0
	if selected_year < GameCalendar.MIN_YEAR or selected_year > GameCalendar.MAX_YEAR or selected_month < 1 or selected_month > 12:
		return {}
	var first_sunday_index := GameCalendar.weekday({"year": selected_year, "month": selected_month, "day": 1}) % 7
	var result: Dictionary = {}
	for day in range(1, GameCalendar.days_in_month(selected_year, selected_month) + 1):
		var index := first_sunday_index + day - 1
		result[day] = DAY_CENTERS_ORIGIN + Vector2(DAY_COLUMN_STEP * float(index % 7), DAY_ROW_STEP * float(int(index / 7)))
	return result


func day_center(day: int) -> Vector2:
	return day_centers().get(day, Vector2(-1.0, -1.0))


func source_geometry() -> Dictionary:
	return {
		"logical_size": LOGICAL_SIZE,
		"canvas": LOGICAL_SIZE,
		"style": _style,
		"edition": _edition,
		"hitboxes": source_hitboxes(),
		"global_hitboxes": source_global_hitboxes(),
		"month_grid": {
			"month_center": Vector2(60.0, 48.0),
			"year_origin": Vector2(140.0, 8.0),
			"year_size": Vector2(60.0, 28.0),
			"weekday_origin": Vector2(30.0, 80.0),
			"weekday_step": Vector2(DAY_COLUMN_STEP, 0.0),
			"day_center_origin": DAY_CENTERS_ORIGIN,
			"column_step": DAY_COLUMN_STEP,
			"row_step": DAY_ROW_STEP,
			"current_day_box": {"offset": Vector2(-10.0, -6.0), "size": DAY_BOX_SIZE},
		},
	}


func current_day_box_rect(day: int = -1) -> Rect2:
	var selected := day
	if selected < 1:
		var date_value: Variant = _snapshot.get("date", {})
		selected = int(date_value.get("day", 0)) if date_value is Dictionary else 0
	var centers := day_centers()
	if not centers.has(selected):
		return Rect2()
	return Rect2(centers[selected] + Vector2(-10.0, -6.0), DAY_BOX_SIZE)


func get_source_geometry() -> Dictionary:
	return source_geometry()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if not visible or not is_visible_in_tree() or not _snapshot_valid:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _input_allowed("style"):
		return
	get_viewport().set_input_as_handled()
	accept_event()
	if mouse.pressed:
		return
	var local := mouse.position
	if HITBOXES["sun"].has_point(local):
		_apply_style(STYLE_DAY)
	elif HITBOXES["moon"].has_point(local):
		_apply_style(STYLE_MONTH)


func _build() -> void:
	if _built:
		return
	_built = true
	_surface = Control.new()
	_surface.name = "SourceCalendarSurface"
	_surface.size = LOGICAL_SIZE
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)
	_fallback = ColorRect.new()
	_fallback.name = "SourceCalendarFallback"
	_fallback.size = LOGICAL_SIZE
	_fallback.color = Color("#193a4a")
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(_fallback)
	_unavailable = Label.new()
	_unavailable.name = "SourceCalendarUnavailable"
	_unavailable.position = Vector2(10.0, 82.0)
	_unavailable.size = Vector2(180.0, 36.0)
	_unavailable.text = "日期資料無法顯示"
	_unavailable.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unavailable.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_unavailable.add_theme_font_size_override("font_size", 15)
	_unavailable.add_theme_color_override("font_color", Color("#ffb3a4"))
	_unavailable.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unavailable.hide()
	_surface.add_child(_unavailable)


func _render() -> void:
	if not _built:
		return
	for child in _surface.get_children():
		if child != _fallback and child != _unavailable:
			child.free()
	_source_frames.clear()
	_source_art_status.clear()
	_source_art_available = false
	background_art = null
	_fallback.show()
	_unavailable.visible = not _snapshot_valid
	if not _snapshot_valid:
		return
	var date_value: Dictionary = _snapshot["date"]
	var season := season_index(int(date_value.month))
	var base_chunk := MONTH_BASE_CHUNK + season if _style == STYLE_MONTH else DAY_BASE_CHUNK + season
	var base := _resolve_chunk(base_chunk)
	_source_frames["Panel2.%d" % base_chunk] = (base.get("frame", {}) as Dictionary).duplicate(true)
	_source_art_status["background"] = base.get("texture") is Texture2D
	var base_texture: Texture2D = base.get("texture") as Texture2D
	if base_texture != null:
		_fallback.hide()
		background_art = _add_texture("SourceCalendarArt", base_texture)
	if _style == STYLE_DAY:
		# The source day panel carries both selector glyphs.  Their native logical
		# bounds are 24x23 (sun) and 20x20 (moon); they are never stretched with
		# the 200x200 background.
		var sun := _resolve_chunk(SUN_CHUNK)
		var moon := _resolve_chunk(MOON_CHUNK)
		_source_frames["Panel2.%d" % SUN_CHUNK] = (sun.get("frame", {}) as Dictionary).duplicate(true)
		_source_frames["Panel2.%d" % MOON_CHUNK] = (moon.get("frame", {}) as Dictionary).duplicate(true)
		_source_art_status["sun"] = sun.get("texture") is Texture2D
		_source_art_status["moon"] = moon.get("texture") is Texture2D
		var sun_texture: Texture2D = sun.get("texture") as Texture2D
		var moon_texture: Texture2D = moon.get("texture") as Texture2D
		if sun_texture != null:
			_add_texture("SourceCalendarSun", sun_texture, Vector2(10, 9), Vector2(24, 23))
		if moon_texture != null:
			_add_texture("SourceCalendarMoon", moon_texture, Vector2(42, 11), Vector2(20, 20))
		_draw_day(date_value)
	else:
		_draw_month(date_value)
	_source_art_available = not _source_art_status.is_empty()
	for available in _source_art_status.values():
		_source_art_available = _source_art_available and bool(available)


func _draw_day(date_value: Dictionary) -> void:
	_make_label("SourceCalendarDay", str(int(date_value.day)), Rect2(18, 66, 84, 60), 60, Color("#101010"), HORIZONTAL_ALIGNMENT_CENTER)
	_make_label("SourceCalendarMonth", _month_text(int(date_value.month)), Rect2(20, 32, 80, 32), 28, Color("#101010"), HORIZONTAL_ALIGNMENT_CENTER)
	var underline := ColorRect.new()
	underline.name = "SourceCalendarMonthUnderline"
	underline.position = Vector2(20, 63)
	underline.size = Vector2(80, 1)
	underline.color = Color("#101010")
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(underline)
	_make_label("SourceCalendarYear", str(int(date_value.year)), Rect2(140, 8, 60, 28), 24, Color("#101010"), HORIZONTAL_ALIGNMENT_LEFT)
	var weekday := GameCalendar.weekday(date_value) % 7
	_make_label("SourceCalendarWeekday", "星期%s" % WEEKDAY_LABELS[weekday], Rect2(18, 138, 84, 22), 16, Color("#101010"), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_month(date_value: Dictionary) -> void:
	_make_label("SourceCalendarMonth", _month_text(int(date_value.month)), Rect2(20, 32, 80, 32), 28, Color("#101010"), HORIZONTAL_ALIGNMENT_CENTER)
	_make_label("SourceCalendarYear", str(int(date_value.year)), Rect2(140, 8, 60, 28), 24, Color("#101010"), HORIZONTAL_ALIGNMENT_LEFT)
	var centers := day_centers()
	var selected_day := int(date_value.day)
	for day in centers:
		var center: Vector2 = centers[day]
		if int(day) == selected_day:
			var current := Panel.new()
			current.name = "SourceCalendarCurrentDayBox"
			current.position = center + Vector2(-10, -6)
			current.size = DAY_BOX_SIZE
			current.mouse_filter = Control.MOUSE_FILTER_IGNORE
			current.z_index = 1
			var outline := StyleBoxFlat.new()
			outline.bg_color = Color(0, 0, 0, 0)
			outline.border_color = Color("#c21f28")
			outline.set_border_width_all(1)
			current.add_theme_stylebox_override("panel", outline)
			_surface.add_child(current)
		var weekday := (int(center.x - DAY_CENTERS_ORIGIN.x) / int(DAY_COLUMN_STEP))
		var day_color := Color("#c21f28") if weekday == 0 else Color("#101010")
		_make_label("SourceCalendarDay%d" % int(day), str(int(day)), Rect2(center - Vector2(10, 7), DAY_BOX_SIZE), 12, day_color, HORIZONTAL_ALIGNMENT_CENTER)


func _add_texture(node_name: String, texture: Texture2D, origin := Vector2.ZERO, logical_size := LOGICAL_SIZE) -> TextureRect:
	var art := TextureRect.new()
	art.name = node_name
	art.position = origin
	art.size = logical_size
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_meta("source_logical_size", logical_size)
	_surface.add_child(art)
	return art


func _make_label(node_name: String, text_value: String, rect: Rect2, font_size: int, color: Color, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 2
	_surface.add_child(label)
	return label


func _validate_snapshot(value: Dictionary) -> bool:
	if not value.has("date") or not GameCalendar.is_valid(value.get("date")):
		return false
	if value.has("edition") and str(value.get("edition", "")) not in VALID_EDITIONS:
		return false
	return true


func _month_text(month: int) -> String:
	return "%d月" % month if month >= 1 and month <= 12 else ""


func _input_allowed(action: String) -> bool:
	if not _input_guard.is_valid():
		return true
	if _input_guard.get_argument_count() == 0:
		return bool(_input_guard.call())
	return bool(_input_guard.call(action))


func _resolve_chunk(chunk: int) -> Dictionary:
	var key := "%s.%s.%d.%d" % [_edition, ARCHIVE, SOURCE_RESOURCE, chunk]
	var frame: Dictionary = {}
	var texture: Texture2D = null
	if _catalog is Dictionary:
		var value: Variant = _dictionary_visual(_catalog as Dictionary, key, chunk)
		if value is Dictionary:
			frame = (value as Dictionary).duplicate(true)
			texture = frame.get("texture") as Texture2D
		elif value is Texture2D:
			texture = value
	elif _catalog is Callable:
		var value: Variant = (_catalog as Callable).call(key)
		if value is Dictionary:
			frame = (value as Dictionary).duplicate(true)
			texture = frame.get("texture") as Texture2D
		elif value is Texture2D:
			texture = value
	elif _catalog is Object:
		var accessor := _catalog as Object
		if accessor.has_method("ui"):
			var value: Variant = accessor.call("ui", _edition, ARCHIVE, SOURCE_RESOURCE, chunk)
			if value is Dictionary:
				frame = (value as Dictionary).duplicate(true)
				texture = frame.get("texture") as Texture2D
			elif value is Texture2D:
				texture = value
		if texture == null and not frame.is_empty() and accessor.has_method("texture"):
			var resolved: Variant = accessor.call("texture", frame)
			if resolved is Texture2D:
				texture = resolved
	if frame.is_empty() and texture == null:
		return {"frame": {}, "texture": null}
	if frame.is_empty():
		frame = _fallback_frame(chunk)
	return {"frame": frame, "texture": texture}


func _dictionary_visual(visuals: Dictionary, key: String, chunk: int) -> Variant:
	for alias in [key, key.to_lower(), key.replace(".", "/"), "%s.Panel2.%d" % [_edition, chunk], "%s.Panel2.chunk%d" % [_edition, chunk], "%s:Panel:%d:%d" % [_edition, SOURCE_RESOURCE, chunk]]:
		if visuals.has(alias):
			return visuals[alias]
	return null


func _fallback_frame(chunk: int) -> Dictionary:
	return {"edition": _edition, "archive": ARCHIVE, "resource": SOURCE_RESOURCE, "chunk": chunk, "logical": {"width": 200.0, "height": 200.0, "anchor_x": 0.0, "anchor_y": 0.0}}
