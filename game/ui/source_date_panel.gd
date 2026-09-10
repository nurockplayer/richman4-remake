extends Control
class_name RichmanSourceDatePanel

## Pure source-shaped date child presenter for Issue #143.
##
## The host supplies a detached date snapshot and captured system date.  This
## control owns only the local draft, source-shaped drawing and mouse intents;
## it never reads the OS clock, GameState, persistence or the owner options
## panel.  The host decides what an accepted date means at runtime.

const GameCalendar = preload("res://game/core/game_calendar.gd")

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const FRAME_ORIGIN := Vector2(221.0, 130.0)
const FRAME_SIZE := Vector2(199.0, 220.0)
const ARCHIVE := "Data"
const SOURCE_RESOURCE := 3
const VALID_EDITIONS := ["Game", "MultiverseJourney"]
const MONTH_LABELS := [
	"一月", "二月", "三月", "四月", "五月", "六月",
	"七月", "八月", "九月", "十月", "十一月", "十二月",
]

# All rectangles are local to the 199x220 source frame.  Right and bottom
# edges are exclusive, matching the original integer comparisons.
const HITBOXES := {
	"month_down": Rect2(74.0, 21.0, 16.0, 10.0),
	"month_up": Rect2(74.0, 31.0, 16.0, 10.0),
	"year_down": Rect2(160.0, 21.0, 16.0, 10.0),
	"year_up": Rect2(160.0, 31.0, 16.0, 10.0),
	"system": Rect2(9.0, 180.0, 55.0, 30.0),
	"cancel": Rect2(72.0, 180.0, 55.0, 30.0),
	"accept": Rect2(134.0, 180.0, 55.0, 30.0),
	"daygrid": Rect2(15.0, 70.0, 166.0, 107.0),
}

# Data3 chunk 2 is the opaque idle date frame.  Chunk 12 is the pressed
# down-arrow overlay and chunk 13 is the pressed up-arrow overlay for both
# month and year controls; chunk 14 is shared by all three footer buttons.
const CHUNKS := {
	"frame": 2,
	"month_pressed": 12,
	"year_pressed": 13,
	"footer_pressed": 14,
}
const CHUNK_ROLES := ["frame", "month_pressed", "year_pressed", "footer_pressed"]
const FALLBACK_LOGICAL := {
	2: Vector2(199.0, 220.0),
	12: Vector2(17.0, 11.0),
	13: Vector2(17.0, 11.0),
	14: Vector2(56.0, 31.0),
}

const SOURCE_TEXT := Color("#101010")
const SOURCE_WHITE := Color("#ffffff")
const SELECTED_FILL := Color("#51916c")
const UNAVAILABLE_TEXT := "日期資料無法顯示"
const ART_FALLBACK_TEXT := "來源畫面素材未載入"
const INVALID_CONFIRM_TEXT := "日期無效，請重新選擇"
const DAY_SIZE := Vector2(20.0, 16.0)

signal accepted(date: Dictionary)
signal cancelled

# Public inspection handles.  They contain only nodes owned by this presenter
# and are rebuilt on each valid render.
var day_labels: Array = []
var month_labels: Array = []
var footer_labels: Array = []
var month_label: Label
var year_label: Label

var _model: Dictionary = {}
var _committed_date: Dictionary = {}
var _draft_date: Dictionary = {}
var _system_date: Dictionary = {}
var _visual_accessor: Variant = null
var _edition := ""
var _model_valid := false
var _is_open := false
var _closed := false
var _suspended := false
var _pressed_action := ""
var _invalid_confirm_text := ""
var _source_art_available := false
var _source_art_status: Dictionary = {}
var _source_frames: Dictionary = {}

var _surface: Control
var _frame_backdrop: ColorRect
var _unavailable_backdrop: ColorRect
var _unavailable: Label
var _invalid_confirm: Label
var _built := false


func _init() -> void:
	name = "SourceDatePanel"
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build()


func _ready() -> void:
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE


## Replace the detached date snapshot.  A content-identical refresh while the
## window is open keeps the unsaved draft; closing and reopening starts fresh.
func set_view_model(model: Dictionary) -> bool:
	var incoming := model.duplicate(true)
	var same_model := _model_valid and _deep_equal(_model, incoming)
	var was_open := _is_open and not _closed
	_model = incoming
	_edition = _canonical_edition(_model.get("edition", null))
	_model_valid = _validate_model(_model)
	_pressed_action = ""
	_invalid_confirm_text = ""
	if not _model_valid:
		_committed_date = {}
		_draft_date = {}
		_system_date = {}
		_is_open = false
		_closed = false
		_suspended = false
		_render()
		show()
		return false

	if not same_model or not was_open:
		_committed_date = _canonical_date(_model["date"])
		_draft_date = _committed_date.duplicate(true)
		_system_date = _canonical_date(_model["system_date"])
	_is_open = true
	_closed = false
	_suspended = false
	_render()
	show()
	return true


## Install a host-provided original-art resolver.  Dictionaries are copied;
## objects and callables are borrowed and never asked to perform IO here.
func set_visual_accessor(accessor: Variant) -> void:
	if accessor is Dictionary:
		_visual_accessor = (accessor as Dictionary).duplicate(true)
	else:
		_visual_accessor = accessor
	_render()


## Compatibility alias shared by existing source presenters.
func set_visuals(accessor: Variant) -> void:
	set_visual_accessor(accessor)


func view_model() -> Dictionary:
	return _model.duplicate(true)


func model() -> Dictionary:
	return view_model()


func is_model_valid() -> bool:
	return _model_valid


func is_open() -> bool:
	return _is_open and _model_valid and visible


func draft_date() -> Dictionary:
	return _draft_date.duplicate(true)


func date() -> Dictionary:
	return draft_date()


func committed_date() -> Dictionary:
	return _committed_date.duplicate(true)


func system_date() -> Dictionary:
	return _system_date.duplicate(true)


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


func source_frame(chunk: int) -> Dictionary:
	for role in CHUNK_ROLES:
		if int(CHUNKS[role]) != chunk:
			continue
		var frame: Variant = _source_frames.get(role, {})
		return frame.duplicate(true) if frame is Dictionary else {}
	return {}


func get_source_frame(chunk: int) -> Dictionary:
	return source_frame(chunk)


func source_hitboxes() -> Dictionary:
	return HITBOXES.duplicate(true)


func get_source_hitboxes() -> Dictionary:
	return source_hitboxes()


func get_hitbox(name_value: String) -> Rect2:
	return HITBOXES.get(name_value, Rect2())


func source_geometry() -> Dictionary:
	return {
		"canvas": REFERENCE_SIZE,
		"frame_origin": FRAME_ORIGIN,
		"frame_size": FRAME_SIZE,
		"edition": _edition,
		"hitboxes": source_hitboxes(),
		"month_center": Vector2(48.0, 32.0),
		"year_center": Vector2(133.0, 30.0),
		"day_grid": {
			"origin": Vector2(15.0, 70.0),
			"size": Vector2(166.0, 107.0),
			"center_origin": Vector2(28.0, 80.0),
			"column_step": 23.0,
			"row_step": 18.0,
			"box_size": DAY_SIZE,
			"highlight_offset": Vector2(-10.0, -6.0),
			"hit_offset": Vector2(-10.0, -8.0),
		},
		"footer": {
			"system_center": Vector2(38.0, 196.0),
			"cancel_center": Vector2(101.0, 196.0),
			"accept_center": Vector2(163.0, 196.0),
			"font_size": 15,
		},
	}


func get_source_geometry() -> Dictionary:
	return source_geometry()


## Return source-local centers for every real day in the current draft month.
## Optional arguments make geometry probing deterministic without mutating the
## presenter; the no-argument form is the host-facing current-month view.
func day_centers(year: int = -1, month: int = -1) -> Dictionary:
	var selected_year := year if year >= GameCalendar.MIN_YEAR and year <= GameCalendar.MAX_YEAR else int(_draft_date.get("year", 0))
	var selected_month := month if month >= 1 and month <= 12 else int(_draft_date.get("month", 0))
	if selected_year < GameCalendar.MIN_YEAR or selected_year > GameCalendar.MAX_YEAR or selected_month < 1 or selected_month > 12:
		return {}
	var first := GameCalendar.weekday({"year": selected_year, "month": selected_month, "day": 1}) % 7
	var result: Dictionary = {}
	for day in range(1, GameCalendar.days_in_month(selected_year, selected_month) + 1):
		var index := first + day - 1
		var column := index % 7
		var row := int(index / 7)
		result[day] = Vector2(28.0 + 23.0 * float(column), 80.0 + 18.0 * float(row))
	return result


func day_center(day: int) -> Vector2:
	var centers := day_centers()
	return centers.get(day, Vector2(-1.0, -1.0))


func source_day_centers() -> Dictionary:
	return day_centers()


func source_weekday(date_value: Variant = null) -> int:
	var selected: Variant = _draft_date if date_value == null else date_value
	if not GameCalendar.is_valid(selected):
		return -1
	return GameCalendar.weekday(selected) % 7


func weekday() -> int:
	return source_weekday()


func is_draft_date_valid() -> bool:
	return GameCalendar.is_valid(_draft_date)


func invalid_confirm_message() -> String:
	return _invalid_confirm_text


func get_invalid_confirm_message() -> String:
	return invalid_confirm_message()


func invalid_date_message() -> String:
	return invalid_confirm_message()


func validation_message() -> String:
	return invalid_confirm_message()


func invalid_confirm_visible() -> bool:
	return _invalid_confirm != null and _invalid_confirm.visible and not _invalid_confirm_text.is_empty()


## Parent calls this while another child or confirmation owns input.
func suspend_input(suspended: bool) -> void:
	_suspended = suspended
	if suspended:
		_pressed_action = ""
		_render()


func is_input_suspended() -> bool:
	return _suspended


## Source right-button release and this explicit method share one cancellation
## boundary.  Invalid/unavailable views can close, but can never accept.
func close_date() -> bool:
	return _close()


func close() -> bool:
	return close_date()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	# Mark the event before state changes or signals.  A receiver may free the
	# panel synchronously from accepted/cancelled.
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	accept_event()
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		if not mouse.pressed and not _suspended:
			_close()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT or _suspended:
		return
	if mouse.pressed:
		_handle_left_down(mouse.position - FRAME_ORIGIN)
	else:
		_handle_left_up()


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_RIGHT or mouse.pressed:
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	if not _suspended:
		_close()


func _handle_left_down(local: Vector2) -> void:
	if not _model_valid or not _is_open or _suspended:
		return
	# A second down before the matching up is one source action, even if the
	# pointer moved over another control.
	if not _pressed_action.is_empty():
		return
	for action in ["month_down", "month_up", "year_down", "year_up", "system", "cancel", "accept"]:
		if _hitbox(action).has_point(local):
			_pressed_action = action
			_invalid_confirm_text = ""
			_render()
			return
	if _hitbox("daygrid").has_point(local):
		var selected_day := _day_at(local)
		if selected_day > 0:
			_draft_date["day"] = selected_day
			_invalid_confirm_text = ""
			_pressed_action = "day"
			_render()


func _handle_left_up() -> void:
	if _pressed_action.is_empty():
		return
	var action := _pressed_action
	_pressed_action = ""
	match action:
		"month_down":
			_change_month(-1)
		"month_up":
			_change_month(1)
		"year_down":
			_change_year(-1)
		"year_up":
			_change_year(1)
		"system":
			_draft_date = _system_date.duplicate(true)
			_invalid_confirm_text = ""
			_render()
		"cancel":
			_close()
		"accept":
			_accept()
		"day":
			_render()


func _change_month(delta: int) -> void:
	if not _model_valid or not _is_open:
		return
	var month := int(_draft_date.get("month", 1))
	month += 1 if delta > 0 else -1
	if month < 1:
		month = 12
	elif month > 12:
		month = 1
	_draft_date["month"] = month
	_invalid_confirm_text = ""
	_render()


func _change_year(delta: int) -> void:
	if not _model_valid or not _is_open:
		return
	var year := int(_draft_date.get("year", GameCalendar.MIN_YEAR))
	year = clampi(year + (1 if delta > 0 else -1), GameCalendar.MIN_YEAR, GameCalendar.MAX_YEAR)
	_draft_date["year"] = year
	_invalid_confirm_text = ""
	_render()


func _accept() -> bool:
	if _closed or not _model_valid or not _is_open:
		return false
	if not GameCalendar.is_valid(_draft_date):
		_invalid_confirm_text = INVALID_CONFIRM_TEXT
		_render()
		return false
	var result := _canonical_date(_draft_date)
	_committed_date = result.duplicate(true)
	_draft_date = result.duplicate(true)
	_model["date"] = result.duplicate(true)
	_closed = true
	_is_open = false
	_suspended = false
	_pressed_action = ""
	_invalid_confirm_text = ""
	hide()
	# No code after this signal may dereference the presenter.
	accepted.emit(result)
	return true


func _close() -> bool:
	if _closed:
		return false
	_closed = true
	_is_open = false
	_pressed_action = ""
	_suspended = false
	_invalid_confirm_text = ""
	_draft_date = _committed_date.duplicate(true)
	hide()
	# No code after this signal may dereference the presenter.
	cancelled.emit()
	return true


func _hitbox(name_value: String) -> Rect2:
	return HITBOXES.get(name_value, Rect2())


func _build() -> void:
	if _built:
		return
	_built = true
	_surface = Control.new()
	_surface.name = "SourceDateSurface"
	_surface.position = Vector2.ZERO
	_surface.size = REFERENCE_SIZE
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)

	_frame_backdrop = ColorRect.new()
	_frame_backdrop.name = "SourceDateFrameBackdrop"
	_frame_backdrop.position = FRAME_ORIGIN
	_frame_backdrop.size = FRAME_SIZE
	_frame_backdrop.color = Color.BLACK
	_frame_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_backdrop.visible = false
	_surface.add_child(_frame_backdrop)

	_unavailable_backdrop = ColorRect.new()
	_unavailable_backdrop.name = "SourceDateUnavailableBackdrop"
	_unavailable_backdrop.position = FRAME_ORIGIN
	_unavailable_backdrop.size = FRAME_SIZE
	_unavailable_backdrop.color = Color("#0d1524")
	_unavailable_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unavailable_backdrop.visible = false
	_surface.add_child(_unavailable_backdrop)

	_unavailable = Label.new()
	_unavailable.name = "SourceDateUnavailable"
	_unavailable.text = UNAVAILABLE_TEXT
	_unavailable.position = FRAME_ORIGIN + FRAME_SIZE / 2.0 - Vector2(90.0, 15.0)
	_unavailable.size = Vector2(180.0, 30.0)
	_unavailable.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unavailable.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_unavailable.add_theme_font_size_override("font_size", 16)
	_unavailable.add_theme_color_override("font_color", Color("#ffb3a4"))
	_unavailable.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unavailable.visible = false
	_surface.add_child(_unavailable)

	_invalid_confirm = Label.new()
	_invalid_confirm.name = "SourceDateInvalidConfirm"
	_invalid_confirm.position = FRAME_ORIGIN + Vector2(10.0, 157.0)
	_invalid_confirm.size = Vector2(179.0, 18.0)
	_invalid_confirm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_invalid_confirm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_invalid_confirm.add_theme_font_size_override("font_size", 12)
	_invalid_confirm.add_theme_color_override("font_color", Color("#c21f28"))
	_invalid_confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_invalid_confirm.visible = false
	_surface.add_child(_invalid_confirm)


func _render() -> void:
	if not _built:
		return
	_clear_dynamic_children()
	_source_frames.clear()
	_source_art_status.clear()
	_source_art_available = false
	_frame_backdrop.visible = false
	_unavailable_backdrop.visible = false
	_unavailable.visible = false
	_invalid_confirm.visible = false
	_invalid_confirm.text = _invalid_confirm_text
	day_labels.clear()
	month_labels.clear()
	footer_labels.clear()
	month_label = null
	year_label = null
	if not _model_valid:
		_unavailable_backdrop.visible = true
		_unavailable.visible = true
		return
	_draw_date()


func _clear_dynamic_children() -> void:
	for child in _surface.get_children():
		if child == _frame_backdrop or child == _unavailable_backdrop or child == _unavailable or child == _invalid_confirm:
			continue
		child.free()


func _draw_date() -> void:
	var resolved: Dictionary = {}
	var all_available := true
	for role in CHUNK_ROLES:
		var chunk: int = int(CHUNKS[role])
		var result := _resolve_chunk(chunk)
		resolved[role] = result
		var frame: Dictionary = result.get("frame", {})
		_source_frames[role] = frame.duplicate(true)
		var available := result.get("texture") is Texture2D
		_source_art_status[role] = available
		all_available = all_available and available
	_source_art_available = all_available
	_frame_backdrop.visible = true
	_add_art(resolved["frame"], "SourceDateFrame", Vector2.ZERO, FRAME_SIZE, int(CHUNKS["frame"]))

	var year := int(_draft_date.get("year", GameCalendar.MIN_YEAR))
	var month := int(_draft_date.get("month", 1))
	month = clampi(month, 1, 12)
	month_label = _make_centered_label(
		"SourceDateMonth",
		MONTH_LABELS[month - 1],
		Vector2(48.0, 32.0),
		Vector2(68.0, 20.0),
		15,
	)
	month_label.set_meta("source_month", month)
	month_labels.append(month_label)
	year_label = _make_centered_label(
		"SourceDateYear",
		str(year),
		Vector2(133.0, 30.0),
		Vector2(62.0, 20.0),
		15,
	)
	year_label.set_meta("source_year", year)

	var centers := day_centers()
	var selected_day := int(_draft_date.get("day", 0))
	if centers.has(selected_day):
		var selected_center: Vector2 = centers[selected_day]
		var highlight := ColorRect.new()
		highlight.name = "SourceDateSelectedDay"
		highlight.position = FRAME_ORIGIN + selected_center + Vector2(-10.0, -6.0)
		highlight.size = Vector2(20.0, 16.0)
		highlight.color = SELECTED_FILL
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_surface.add_child(highlight)
	for day in centers:
		var center: Vector2 = centers[day]
		var label := _make_centered_label(
			"SourceDateDay%d" % int(day),
			str(day),
			center,
			DAY_SIZE,
			15,
			SOURCE_WHITE if int(day) == selected_day else SOURCE_TEXT,
		)
		label.set_meta("source_day", int(day))
		label.set_meta("source_center", center)
		day_labels.append(label)

	if _pressed_action in ["month_down", "year_down"]:
		_add_art(
			resolved["month_pressed"],
			"SourceDate%sPressed" % ("MonthDown" if _pressed_action == "month_down" else "YearDown"),
			_hitbox(_pressed_action).position,
			Vector2(17.0, 11.0),
			int(CHUNKS["month_pressed"]),
		)
	elif _pressed_action in ["month_up", "year_up"]:
		_add_art(
			resolved["year_pressed"],
			"SourceDate%sPressed" % ("MonthUp" if _pressed_action == "month_up" else "YearUp"),
			_hitbox(_pressed_action).position,
			Vector2(17.0, 11.0),
			int(CHUNKS["year_pressed"]),
		)
	if _pressed_action in ["system", "cancel", "accept"]:
		_add_art(
			resolved["footer_pressed"],
			"SourceDate%sPressed" % ("System" if _pressed_action == "system" else "Cancel" if _pressed_action == "cancel" else "Accept"),
			_hitbox(_pressed_action).position,
			Vector2(56.0, 31.0),
			int(CHUNKS["footer_pressed"]),
		)

	var footer_records := [
		{"name": "SourceDateSystemLabel", "text": "系 統", "center": Vector2(38.0, 196.0), "action": "system"},
		{"name": "SourceDateCancelLabel", "text": "取 消", "center": Vector2(101.0, 196.0), "action": "cancel"},
		{"name": "SourceDateAcceptLabel", "text": "確 定", "center": Vector2(163.0, 196.0), "action": "accept"},
	]
	for record in footer_records:
		var caption_offset := Vector2.ONE if _pressed_action == str(record["action"]) else Vector2.ZERO
		var footer := _make_centered_label(
			str(record["name"]),
			str(record["text"]),
			record["center"] + caption_offset,
			Vector2(55.0, 20.0),
			15,
		)
		footer.set_meta("source_action", str(record["action"]))
		footer_labels.append(footer)

	if not _invalid_confirm_text.is_empty():
		_invalid_confirm.visible = true
		_invalid_confirm.text = _invalid_confirm_text
	if not _source_art_available:
		_make_centered_label(
			"SourceDateArtFallback",
			ART_FALLBACK_TEXT,
			Vector2(99.0, 216.0),
			Vector2(180.0, 16.0),
			11,
			Color("#b6d5cf"),
		)


func _add_art(result: Dictionary, node_name: String, local_origin: Vector2, logical_size: Vector2, chunk: int) -> TextureRect:
	var texture: Texture2D = result.get("texture")
	if texture == null:
		return null
	var art := TextureRect.new()
	art.name = node_name
	art.position = FRAME_ORIGIN + local_origin
	art.size = logical_size
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_meta("source_chunk", chunk)
	art.set_meta("source_logical_size", logical_size)
	art.set_meta("source_frame", (result.get("frame", {}) as Dictionary).duplicate(true))
	_surface.add_child(art)
	return art


func _make_centered_label(
	node_name: String,
	text_value: String,
	center_local: Vector2,
	logical_size: Vector2,
	font_size: int,
	font_color: Color = SOURCE_TEXT,
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var actual_height := maxf(logical_size.y, label.get_minimum_size().y)
	var center := FRAME_ORIGIN + center_local
	label.position = Vector2(center.x - logical_size.x / 2.0, center.y - actual_height / 2.0)
	label.size = Vector2(logical_size.x, actual_height)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_surface.add_child(label)
	return label


func _day_at(local: Vector2) -> int:
	var centers := day_centers()
	for day in centers:
		var center: Vector2 = centers[day]
		if Rect2(center - Vector2(10.0, 8.0), DAY_SIZE).has_point(local):
			return int(day)
	return -1


func _resolve_chunk(chunk: int) -> Dictionary:
	var key := "%s.%s.%d.%d" % [_edition, ARCHIVE, SOURCE_RESOURCE, chunk]
	var frame: Dictionary = {}
	var direct_texture: Texture2D = null
	if _visual_accessor is Dictionary:
		var value: Variant = _dictionary_visual(_visual_accessor as Dictionary, key, chunk)
		if value is Dictionary:
			frame = (value as Dictionary).duplicate(true)
			if frame.get("texture") is Texture2D:
				direct_texture = frame["texture"]
		elif value is Texture2D:
			direct_texture = value
	elif _visual_accessor is Callable:
		var value: Variant = (_visual_accessor as Callable).call(key)
		if value is Dictionary:
			frame = (value as Dictionary).duplicate(true)
			if frame.get("texture") is Texture2D:
				direct_texture = frame["texture"]
		elif value is Texture2D:
			direct_texture = value
	elif _visual_accessor is Object:
		var accessor := _visual_accessor as Object
		if accessor.has_method("ui"):
			var value: Variant = accessor.call("ui", _edition, ARCHIVE, SOURCE_RESOURCE, chunk)
			if value is Dictionary:
				frame = (value as Dictionary).duplicate(true)
				if frame.get("texture") is Texture2D:
					direct_texture = frame["texture"]
			elif value is Texture2D:
				direct_texture = value
		elif accessor.has_method("visual"):
			var value: Variant = accessor.call("visual", _edition, ARCHIVE, SOURCE_RESOURCE, chunk)
			if value is Dictionary:
				frame = (value as Dictionary).duplicate(true)
				if frame.get("texture") is Texture2D:
					direct_texture = frame["texture"]
			elif value is Texture2D:
				direct_texture = value
		elif accessor.has_method("resolve"):
			var value: Variant = accessor.call("resolve", key)
			if value is Dictionary:
				frame = (value as Dictionary).duplicate(true)
				if frame.get("texture") is Texture2D:
					direct_texture = frame["texture"]
			elif value is Texture2D:
				direct_texture = value

	if frame.is_empty() and direct_texture == null:
		return {"frame": {}, "texture": null}
	if frame.is_empty():
		frame = _fallback_frame(chunk)
	var texture: Texture2D = direct_texture
	if texture == null and _visual_accessor is Object:
		var accessor := _visual_accessor as Object
		if accessor.has_method("texture"):
			var texture_value: Variant = accessor.call("texture", frame)
			if texture_value is Texture2D:
				texture = texture_value
	return {"frame": frame, "texture": texture}


func _dictionary_visual(visuals: Dictionary, key: String, chunk: int) -> Variant:
	var aliases := [
		key,
		key.to_lower(),
		key.to_upper(),
		key.replace(".", "/"),
		key.replace(".", "_"),
		"%s.Data3.%d" % [_edition, chunk],
		"%s.Data3.chunk%d" % [_edition, chunk],
		"%s:Data:%d:%d" % [_edition, SOURCE_RESOURCE, chunk],
	]
	if _edition == "MultiverseJourney":
		aliases.append(key.replace("MultiverseJourney", "MJ"))
	for alias in aliases:
		if visuals.has(alias):
			return visuals[alias]
	return null


func _fallback_frame(chunk: int) -> Dictionary:
	var logical_size: Vector2 = FALLBACK_LOGICAL.get(chunk, Vector2.ONE)
	return {
		"edition": _edition,
		"archive": ARCHIVE,
		"resource": SOURCE_RESOURCE,
		"chunk": chunk,
		"logical": {
			"width": logical_size.x,
			"height": logical_size.y,
			"anchor_x": 0.0,
			"anchor_y": 0.0,
		},
	}


func _logical_for(result: Dictionary, fallback: Vector2) -> Vector2:
	var frame: Variant = result.get("frame", {})
	if not frame is Dictionary:
		return fallback
	var logical: Variant = (frame as Dictionary).get("logical", {})
	if not logical is Dictionary:
		return fallback
	var width := _metadata_integer((logical as Dictionary).get("width", null), 0)
	var height := _metadata_integer((logical as Dictionary).get("height", null), 0)
	return Vector2(width, height) if width > 0 and height > 0 else fallback


func _metadata_integer(value: Variant, fallback: int) -> int:
	var type := typeof(value)
	if type == TYPE_INT:
		return int(value)
	if type != TYPE_FLOAT:
		return fallback
	var numeric := float(value)
	if not is_finite(numeric) or numeric != floor(numeric):
		return fallback
	return int(numeric)


func _canonical_edition(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var normalized := str(value).strip_edges()
	return normalized if normalized in VALID_EDITIONS else ""


func _canonical_date(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	return {
		"year": int((value as Dictionary).get("year", 0)),
		"month": int((value as Dictionary).get("month", 0)),
		"day": int((value as Dictionary).get("day", 0)),
	}


func _validate_model(value: Dictionary) -> bool:
	if _edition.is_empty() or value.size() != 3:
		return false
	if not value.has("edition") or not value.has("date") or not value.has("system_date"):
		return false
	if typeof(value.get("edition")) != TYPE_STRING:
		return false
	if not _valid_public_date(value.get("date", null)):
		return false
	if not _valid_public_date(value.get("system_date", null)):
		return false
	return true


func _valid_public_date(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var date_value: Dictionary = value
	if date_value.size() != 3:
		return false
	for key in ["year", "month", "day"]:
		if not date_value.has(key) or typeof(date_value[key]) != TYPE_INT:
			return false
	return GameCalendar.is_valid(date_value)


func _deep_equal(left: Variant, right: Variant) -> bool:
	var left_type := typeof(left)
	var right_type := typeof(right)
	if left_type != right_type:
		if _is_number(left) and _is_number(right):
			return float(left) == float(right)
		return false
	match left_type:
		TYPE_DICTIONARY:
			var left_dict: Dictionary = left
			var right_dict: Dictionary = right
			if left_dict.size() != right_dict.size():
				return false
			for key in left_dict:
				if not right_dict.has(key) or not _deep_equal(left_dict[key], right_dict[key]):
					return false
			return true
		TYPE_ARRAY:
			var left_array: Array = left
			var right_array: Array = right
			if left_array.size() != right_array.size():
				return false
			for index in range(left_array.size()):
				if not _deep_equal(left_array[index], right_array[index]):
					return false
			return true
		_:
			return left == right


func _is_number(value: Variant) -> bool:
	var type := typeof(value)
	return type == TYPE_INT or type == TYPE_FLOAT
