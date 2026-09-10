extends Control
class_name RichmanSourceHelpPanel

## Source-shaped help presenter for Issue #139.
##
## The host supplies a detached, already validated help-edition dictionary and
## an optional OriginalVisuals-like resolver.  This component never owns
## GameState, persistence, RNG, audio, file paths or owner settings.  Every
## position below is a logical canvas coordinate; texture pixel dimensions are
## never used for layout.

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const FRAME_ORIGIN := Vector2(120.0, 40.0)
const FRAME_SIZE := Vector2(400.0, 400.0)
const SCHEMA := "richman4.help-edition/v1"
const ARCHIVE := "help"
const SOURCE_RESOURCE := 0
const VALID_EDITIONS := ["Game", "MultiverseJourney"]
const SECTION_COUNT := 8
const EXPECTED_TOPIC_COUNTS := [1, 6, 12, 3, 16, 18, 30, 13]
const EXPECTED_TOPIC_TOTAL := 99
const VISIBLE_TOPIC_ROWS := 8
const TOPIC_PAGE_STEP := 8
const MAX_BODY_LINES := 14

# Section list (frame-local coordinates).
const SECTION_ORIGIN := Vector2(26.0, 58.0)
const SECTION_STEP := 36.0
const SECTION_SIZE := Vector2(66.0, 33.0)
const SECTION_LABEL_CENTER := Vector2(59.0, 73.0)
const SECTION_LABEL_FONT := 12
const SECTION_TITLE_CENTER := Vector2(140.0, 57.0)
const SECTION_TITLE_FONT := 12

# Topic list.
const TOPIC_ORIGIN := Vector2(108.0, 78.0)
const TOPIC_STEP := 34.0
const TOPIC_UNSELECTED_SIZE := Vector2(85.0, 33.0)
const TOPIC_SELECTED_SIZE := Vector2(87.0, 33.0)
const TOPIC_LABEL_CENTER := Vector2(150.0, 94.0)
const TOPIC_LABEL_FONT := 15
const TOPIC_UP_ORIGIN := Vector2(170.0, 43.0)
const TOPIC_UP_SIZE := Vector2(22.0, 18.0)
const TOPIC_DOWN_ORIGIN := Vector2(170.0, 59.0)
const TOPIC_DOWN_SIZE := Vector2(22.0, 15.0)
const TOPIC_UP_HIT := Rect2(170.0, 43.0, 22.0, 15.0)
const TOPIC_DOWN_HIT := Rect2(170.0, 59.0, 22.0, 15.0)

# Body pages.
const BODY_HEADER_CENTER := Vector2(270.0, 63.0)
const BODY_HEADER_FONT := 15
const BODY_LINE_ORIGIN := Vector2(232.0, 90.0)
const BODY_LINE_STEP := 18.0
const BODY_LINE_FONT := 12
const BODY_AREA := Rect2(216.0, 80.0, 150.0, 274.0)
const BODY_PREV_ORIGIN := Vector2(322.0, 48.0)
const BODY_PREV_SIZE := Vector2(23.0, 32.0)
const BODY_NEXT_ORIGIN := Vector2(343.0, 48.0)
const BODY_NEXT_SIZE := Vector2(23.0, 35.0)
const BODY_PREV_HIT := Rect2(322.0, 48.0, 23.0, 32.0)
const BODY_NEXT_HIT := Rect2(343.0, 48.0, 23.0, 32.0)

const TEXT_COLOR := Color("#101010")
const UNAVAILABLE_MESSAGE := "說明資料無法顯示"
const ART_FALLBACK_NOTE := "來源畫面素材未載入"

const CHUNKS := {
	"frame": 0,
	"section": 1,
	"topic_unselected": 2,
	"topic_selected": 3,
	"topic_up": 4,
	"topic_down": 5,
	"topic_up_pressed": 6,
	"topic_down_pressed": 7,
	"body_prev": 8,
	"body_next": 9,
	"body_prev_pressed": 10,
	"body_next_pressed": 11,
}

const FALLBACK_LOGICAL := {
	0: Vector2(400.0, 400.0),
	1: Vector2(66.0, 33.0),
	2: Vector2(85.0, 33.0),
	3: Vector2(87.0, 33.0),
	4: Vector2(22.0, 18.0),
	5: Vector2(22.0, 15.0),
	6: Vector2(20.0, 18.0),
	7: Vector2(18.0, 14.0),
	8: Vector2(23.0, 32.0),
	9: Vector2(23.0, 35.0),
	10: Vector2(23.0, 32.0),
	11: Vector2(23.0, 30.0),
}

signal closed

var _model: Dictionary = {}
var _visual_accessor: Variant = null
var _model_valid := false
var _edition := ""
var _is_open := false
var _closed := false
var _section_index := 0
var _topic_index := 0
var _body_page := 0
var _topic_offsets: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var _pressed_topic_arrow := ""
var _pressed_body_arrow := ""
var _keys_down: Dictionary = {}
var _source_art_available := false
var _source_art_status: Dictionary = {}
var _source_frames: Dictionary = {}

var _surface: Control
var _frame_backdrop: ColorRect
var _unavailable_backdrop: ColorRect
var _unavailable: Label
var _built := false


func _init() -> void:
	name = "SourceHelpPanel"
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build()


func _ready() -> void:
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE


## Replace the help-edition snapshot.  The dictionary is deeply copied before
## validation, so the host can never be mutated by this presenter.  A content
## identical refresh keeps the current browsing state; a different model resets
## to section 0 / topic 0 / body page 0.
func set_view_model(model: Dictionary) -> void:
	var incoming := model.duplicate(true)
	var same := _model_valid and _deep_equal(_model, incoming)
	_model = incoming
	_edition = _canonical_edition(_model.get("edition", null))
	_model_valid = _validate_model(_model)
	_pressed_topic_arrow = ""
	_pressed_body_arrow = ""
	_keys_down.clear()
	if not _model_valid:
		_closed = false
		_is_open = false
		_render()
		show()
		return
	if not same:
		_section_index = 0
		_topic_index = 0
		_body_page = 0
		_topic_offsets.fill(0)
	_closed = false
	_is_open = true
	_render()
	show()


## Install a host-provided resolver.  Objects/callables are borrowed but never
## asked to perform IO by this component; dictionaries are copied deeply.
func set_visuals(accessor: Variant) -> void:
	if accessor is Dictionary:
		_visual_accessor = (accessor as Dictionary).duplicate(true)
	else:
		_visual_accessor = accessor
	_render()


func view_model() -> Dictionary:
	return _model.duplicate(true)


func is_model_valid() -> bool:
	return _model_valid


func is_open() -> bool:
	return _is_open and _model_valid and visible


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


func source_geometry() -> Dictionary:
	return {
		"canvas": REFERENCE_SIZE,
		"frame_origin": FRAME_ORIGIN,
		"frame_size": FRAME_SIZE,
		"edition": _edition,
		"section": {
			"origin": SECTION_ORIGIN,
			"step": SECTION_STEP,
			"size": SECTION_SIZE,
			"label_center": SECTION_LABEL_CENTER,
			"label_font_size": SECTION_LABEL_FONT,
			"title_center": SECTION_TITLE_CENTER,
			"title_font_size": SECTION_TITLE_FONT,
			"count": SECTION_COUNT,
		},
		"topic_list": {
			"title_center": SECTION_TITLE_CENTER,
			"title_font_size": SECTION_TITLE_FONT,
			"origin": TOPIC_ORIGIN,
			"step": TOPIC_STEP,
			"visible_rows": VISIBLE_TOPIC_ROWS,
			"unselected_size": TOPIC_UNSELECTED_SIZE,
			"selected_size": TOPIC_SELECTED_SIZE,
			"label_center": TOPIC_LABEL_CENTER,
			"label_font_size": TOPIC_LABEL_FONT,
			"up_origin": TOPIC_UP_ORIGIN,
			"up_size": TOPIC_UP_SIZE,
			"down_origin": TOPIC_DOWN_ORIGIN,
			"down_size": TOPIC_DOWN_SIZE,
			"up_hit": TOPIC_UP_HIT,
			"down_hit": TOPIC_DOWN_HIT,
			"page_step": TOPIC_PAGE_STEP,
		},
		"body": {
			"header_center": BODY_HEADER_CENTER,
			"header_font_size": BODY_HEADER_FONT,
			"line_origin": BODY_LINE_ORIGIN,
			"line_step": BODY_LINE_STEP,
			"line_font_size": BODY_LINE_FONT,
			"max_lines": MAX_BODY_LINES,
			"area": BODY_AREA,
			"prev_origin": BODY_PREV_ORIGIN,
			"prev_size": BODY_PREV_SIZE,
			"next_origin": BODY_NEXT_ORIGIN,
			"next_size": BODY_NEXT_SIZE,
			"prev_hit": BODY_PREV_HIT,
			"next_hit": BODY_NEXT_HIT,
		},
	}


func get_source_geometry() -> Dictionary:
	return source_geometry()


func selected_section() -> int:
	return _section_index


func selected_topic() -> int:
	return _topic_index


func selected_body_page() -> int:
	return _body_page


## First visible topic index of the current section.  The source keeps one such
## offset per section and only resets them when a fresh window is entered.
func topic_page_offset() -> int:
	if _section_index < 0 or _section_index >= _topic_offsets.size():
		return 0
	return _topic_offsets[_section_index]


## Select a section exactly like a source left press: the topic list offset for
## that section is deliberately retained (source table scroll persists), while
## the selected topic and body page reset to the first entry.
func select_section(index: int) -> bool:
	if not _model_valid or index < 0 or index >= SECTION_COUNT:
		return false
	_section_index = index
	_topic_index = 0
	_body_page = 0
	_render()
	return true


func select_topic(index: int) -> bool:
	if not _model_valid:
		return false
	var topics := _current_topics()
	if index < 0 or index >= topics.size():
		return false
	_topic_index = index
	_body_page = 0
	_render()
	return true


## Source arrow release semantics: shift the visible window by up to eight rows
## and move the selection by the same delta, preserving its visible slot.
func page_topics(direction: int) -> bool:
	if not _model_valid or direction == 0:
		return false
	var count := _current_topics().size()
	if count <= VISIBLE_TOPIC_ROWS:
		return false
	var old_offset: int = _topic_offsets[_section_index]
	var new_offset := clampi(old_offset + TOPIC_PAGE_STEP * signi(direction), 0, count - VISIBLE_TOPIC_ROWS)
	if new_offset == old_offset:
		return false
	_topic_offsets[_section_index] = new_offset
	_topic_index = clampi(_topic_index + (new_offset - old_offset), 0, count - 1)
	_render()
	return true


func page_body(direction: int) -> bool:
	if not _model_valid or direction == 0:
		return false
	var page_count := _current_pages().size()
	if page_count <= 1:
		return false
	var new_page := clampi(_body_page + signi(direction), 0, page_count - 1)
	if new_page == _body_page:
		return false
	_body_page = new_page
	_render()
	return true


## Close the modal help window exactly once.  A source right-button release
## closes anywhere without requiring a preceding right-button press.
func close_help() -> bool:
	return _close()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		if not mouse.pressed:
			_close()
		accept_event()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _model_valid or not _is_open:
		accept_event()
		return
	if mouse.pressed:
		_handle_left_press(mouse.position - FRAME_ORIGIN)
	elif not _pressed_topic_arrow.is_empty() or not _pressed_body_arrow.is_empty():
		_handle_left_release()
	accept_event()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not _built or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	if key.keycode != KEY_PAGEUP and key.keycode != KEY_PAGEDOWN:
		return
	if key.pressed:
		if key.echo or _keys_down.has(key.keycode):
			get_viewport().set_input_as_handled()
			return
		_keys_down[key.keycode] = true
		if _model_valid and _is_open:
			page_body(-1 if key.keycode == KEY_PAGEUP else 1)
	else:
		_keys_down.erase(key.keycode)
	get_viewport().set_input_as_handled()


func _close() -> bool:
	if _closed:
		return false
	_closed = true
	_is_open = false
	_pressed_topic_arrow = ""
	_pressed_body_arrow = ""
	_keys_down.clear()
	hide()
	closed.emit()
	return true


func _handle_left_press(local: Vector2) -> void:
	# A new press supersedes any arrow press that never received its release.
	_pressed_topic_arrow = ""
	_pressed_body_arrow = ""
	var topics := _current_topics()
	if topics.size() > VISIBLE_TOPIC_ROWS:
		if TOPIC_UP_HIT.has_point(local):
			_pressed_topic_arrow = "up"
			_render()
			return
		if TOPIC_DOWN_HIT.has_point(local):
			_pressed_topic_arrow = "down"
			_render()
			return
	if _current_pages().size() > 1:
		if BODY_PREV_HIT.has_point(local):
			_pressed_body_arrow = "prev"
			_render()
			return
		if BODY_NEXT_HIT.has_point(local):
			_pressed_body_arrow = "next"
			_render()
			return
	for index in range(SECTION_COUNT):
		if Rect2(SECTION_ORIGIN + Vector2(0.0, SECTION_STEP * float(index)), SECTION_SIZE).has_point(local):
			select_section(index)
			return
	var offset: int = _topic_offsets[_section_index]
	for row in range(VISIBLE_TOPIC_ROWS):
		var topic_index := offset + row
		if topic_index >= topics.size():
			break
		if Rect2(TOPIC_ORIGIN + Vector2(0.0, TOPIC_STEP * float(row)), Vector2(TOPIC_UNSELECTED_SIZE.x, TOPIC_STEP)).has_point(local):
			select_topic(topic_index)
			return


func _handle_left_release() -> void:
	if not _pressed_topic_arrow.is_empty():
		var arrow := _pressed_topic_arrow
		_pressed_topic_arrow = ""
		page_topics(-1 if arrow == "up" else 1)
		_render()
		return
	if not _pressed_body_arrow.is_empty():
		var arrow := _pressed_body_arrow
		_pressed_body_arrow = ""
		page_body(-1 if arrow == "prev" else 1)
		_render()


func _build() -> void:
	if _built:
		return
	_built = true
	_surface = Control.new()
	_surface.name = "SourceHelpSurface"
	_surface.position = Vector2.ZERO
	_surface.size = REFERENCE_SIZE
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)

	_frame_backdrop = ColorRect.new()
	_frame_backdrop.name = "SourceHelpFrameBackdrop"
	_frame_backdrop.position = FRAME_ORIGIN
	_frame_backdrop.size = FRAME_SIZE
	_frame_backdrop.color = Color.BLACK
	_frame_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_backdrop.visible = false
	_surface.add_child(_frame_backdrop)

	_unavailable_backdrop = ColorRect.new()
	_unavailable_backdrop.name = "SourceHelpUnavailableBackdrop"
	_unavailable_backdrop.position = FRAME_ORIGIN
	_unavailable_backdrop.size = FRAME_SIZE
	_unavailable_backdrop.color = Color("#0d1524")
	_unavailable_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unavailable_backdrop.visible = false
	_surface.add_child(_unavailable_backdrop)

	_unavailable = Label.new()
	_unavailable.name = "SourceHelpUnavailable"
	_unavailable.text = UNAVAILABLE_MESSAGE
	_unavailable.position = FRAME_ORIGIN + FRAME_SIZE / 2.0 - Vector2(200.0, 15.0)
	_unavailable.size = Vector2(400.0, 30.0)
	_unavailable.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unavailable.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_unavailable.add_theme_font_size_override("font_size", 20)
	_unavailable.add_theme_color_override("font_color", Color("#ffb3a4"))
	_unavailable.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unavailable.visible = false
	_surface.add_child(_unavailable)


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
	if not _model_valid:
		_unavailable_backdrop.visible = true
		_unavailable.visible = true
		return
	_draw_help()


func _clear_dynamic_children() -> void:
	for child in _surface.get_children():
		if child == _frame_backdrop or child == _unavailable_backdrop or child == _unavailable:
			continue
		child.free()


func _draw_help() -> void:
	_ensure_state()
	var resolved: Dictionary = {}
	var available := true
	for role in CHUNKS:
		var result := _resolve_chunk(int(CHUNKS[role]))
		resolved[role] = result
		var texture: Texture2D = result.get("texture")
		_source_frames[role] = (result.get("frame", {}) as Dictionary).duplicate(true)
		_source_art_status[role] = texture != null
		if texture == null:
			available = false
	_source_art_available = available

	var sections := _sections()
	var section := _current_section()
	var topics := _current_topics()
	var topic := _current_topic()
	var pages := _current_pages()
	var lines: Array = pages[_body_page] if _body_page >= 0 and _body_page < pages.size() else []
	_frame_backdrop.visible = true

	# The opaque source frame stays inside the 400x400 window; the board remains
	# visible everywhere else on the 640x480 canvas.
	_add_art(resolved["frame"], "SourceHelpFrame", Vector2.ZERO, FRAME_SIZE, int(CHUNKS["frame"]))

	# Section list, its selected-row overlay and the topic list title.
	_add_art(
		resolved["section"],
		"SourceHelpSectionArt",
		SECTION_ORIGIN + Vector2(0.0, SECTION_STEP * float(_section_index)),
		SECTION_SIZE,
		int(CHUNKS["section"]),
	)
	for index in range(SECTION_COUNT):
		var label_text := ""
		if index < sections.size() and sections[index] is Dictionary:
			label_text = str((sections[index] as Dictionary).get("label", ""))
		_make_centered_label(
			"SourceHelpSectionLabel%d" % index,
			label_text,
			SECTION_LABEL_CENTER + Vector2(0.0, SECTION_STEP * float(index)),
			Vector2(80.0, 20.0),
			SECTION_LABEL_FONT,
		)
	_make_centered_label(
		"SourceHelpSectionTitle",
		str(section.get("label", "")),
		SECTION_TITLE_CENTER,
		Vector2(110.0, 18.0),
		SECTION_TITLE_FONT,
	)

	# Eight visible topic rows; the selected row uses the source selected art.
	var offset: int = _topic_offsets[_section_index]
	for row in range(VISIBLE_TOPIC_ROWS):
		var topic_index := offset + row
		if topic_index >= topics.size():
			break
		var row_topic: Dictionary = topics[topic_index]
		var selected := topic_index == _topic_index
		var role := "topic_selected" if selected else "topic_unselected"
		_add_art(
			resolved[role],
			"SourceHelpTopicRow%d" % row,
			TOPIC_ORIGIN + Vector2(0.0, TOPIC_STEP * float(row)),
			TOPIC_SELECTED_SIZE if selected else TOPIC_UNSELECTED_SIZE,
			int(CHUNKS[role]),
		)
		_make_centered_label(
			"SourceHelpTopicLabel%d" % row,
			str(row_topic.get("title", "")),
			TOPIC_LABEL_CENTER + Vector2(0.0, TOPIC_STEP * float(row)),
			Vector2(84.0, 20.0),
			TOPIC_LABEL_FONT,
		)

	# Body header plus every source-preserved line of the current page.
	_make_centered_label(
		"SourceHelpBodyHeader",
		str(topic.get("title", "")),
		BODY_HEADER_CENTER,
		Vector2(140.0, 22.0),
		BODY_HEADER_FONT,
	)
	for line_index in range(lines.size()):
		_make_body_line(
			"SourceHelpBodyLine%d" % line_index,
			str(lines[line_index]),
			BODY_LINE_ORIGIN + Vector2(0.0, BODY_LINE_STEP * float(line_index)),
		)

	if topics.size() > VISIBLE_TOPIC_ROWS:
		var up_role := "topic_up_pressed" if _pressed_topic_arrow == "up" else "topic_up"
		var down_role := "topic_down_pressed" if _pressed_topic_arrow == "down" else "topic_down"
		_add_art(resolved[up_role], "SourceHelpTopicUpArt", TOPIC_UP_ORIGIN, TOPIC_UP_SIZE, int(CHUNKS[up_role]))
		_add_art(resolved[down_role], "SourceHelpTopicDownArt", TOPIC_DOWN_ORIGIN, TOPIC_DOWN_SIZE, int(CHUNKS[down_role]))

	if pages.size() > 1:
		var prev_role := "body_prev_pressed" if _pressed_body_arrow == "prev" else "body_prev"
		var next_role := "body_next_pressed" if _pressed_body_arrow == "next" else "body_next"
		_add_art(resolved[prev_role], "SourceHelpBodyPrevArt", BODY_PREV_ORIGIN, BODY_PREV_SIZE, int(CHUNKS[prev_role]))
		_add_art(resolved[next_role], "SourceHelpBodyNextArt", BODY_NEXT_ORIGIN, BODY_NEXT_SIZE, int(CHUNKS[next_role]))

	if not _source_art_available:
		_make_centered_label(
			"SourceHelpArtFallback",
			ART_FALLBACK_NOTE,
			Vector2(320.0, 458.0) - FRAME_ORIGIN,
			Vector2(260.0, 18.0),
			13,
			Color("#b6d5cf"),
		)


func _ensure_state() -> void:
	_section_index = clampi(_section_index, 0, SECTION_COUNT - 1)
	var count := _current_topics().size()
	_topic_index = clampi(_topic_index, 0, maxi(count - 1, 0))
	_topic_offsets[_section_index] = clampi(_topic_offsets[_section_index], 0, maxi(count - VISIBLE_TOPIC_ROWS, 0))
	_body_page = clampi(_body_page, 0, maxi(_current_pages().size() - 1, 0))


func _add_art(result: Dictionary, node_name: String, origin: Vector2, logical_size: Vector2, chunk: int) -> void:
	var texture: Texture2D = result.get("texture")
	if texture == null:
		return
	var art := TextureRect.new()
	art.name = node_name
	art.position = FRAME_ORIGIN + origin
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


func _make_label(node_name: String, text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(label)
	return label


func _make_centered_label(
	node_name: String,
	text_value: String,
	center_local: Vector2,
	logical_size: Vector2,
	font_size: int,
	font_color: Color = TEXT_COLOR,
) -> Label:
	var label := _make_label(node_name, text_value, font_size)
	label.add_theme_color_override("font_color", font_color)
	var center := FRAME_ORIGIN + center_local
	# Godot's font minimum can be taller than a small source label rectangle;
	# keep the source center stable even when the physical metrics grow.
	var actual_height := maxf(logical_size.y, label.get_minimum_size().y)
	label.position = Vector2(center.x - logical_size.x / 2.0, center.y - actual_height / 2.0)
	label.size = Vector2(logical_size.x, actual_height)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _make_body_line(node_name: String, text_value: String, origin_local: Vector2) -> Label:
	var label := _make_label(node_name, text_value, BODY_LINE_FONT)
	# Source draw mode 0 treats the body y as the text top.
	label.position = FRAME_ORIGIN + origin_local
	label.size = Vector2(BODY_AREA.size.x - 4.0, BODY_LINE_STEP)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return label


func _resolve_chunk(chunk: int) -> Dictionary:
	var key := "%s.%s.%d.%d" % [_edition, ARCHIVE, SOURCE_RESOURCE, chunk]
	var frame: Dictionary = {}
	var direct_texture: Texture2D = null
	if _visual_accessor is Dictionary:
		var value: Variant = _dictionary_visual(_visual_accessor, key, chunk)
		if value is Dictionary:
			frame = (value as Dictionary).duplicate(true)
		elif value is Texture2D:
			direct_texture = value
	elif _visual_accessor is Callable:
		var value: Variant = (_visual_accessor as Callable).call(key)
		if value is Dictionary:
			frame = (value as Dictionary).duplicate(true)
		elif value is Texture2D:
			direct_texture = value
	elif _visual_accessor is Object:
		if _visual_accessor.has_method("ui"):
			var value: Variant = _visual_accessor.call("ui", _edition, ARCHIVE, SOURCE_RESOURCE, chunk)
			if value is Dictionary:
				frame = (value as Dictionary).duplicate(true)
			elif value is Texture2D:
				direct_texture = value
		elif _visual_accessor.has_method("visual"):
			var value: Variant = _visual_accessor.call("visual", _edition, ARCHIVE, SOURCE_RESOURCE, chunk)
			if value is Dictionary:
				frame = (value as Dictionary).duplicate(true)
			elif value is Texture2D:
				direct_texture = value
		elif _visual_accessor.has_method("resolve"):
			var value: Variant = _visual_accessor.call("resolve", key)
			if value is Dictionary:
				frame = (value as Dictionary).duplicate(true)
			elif value is Texture2D:
				direct_texture = value

	if frame.is_empty() and direct_texture == null:
		return {"frame": {}, "texture": null}
	if frame.is_empty():
		frame = _fallback_frame(chunk)
	var texture: Texture2D = direct_texture
	if texture == null and _visual_accessor is Object and _visual_accessor.has_method("texture"):
		var texture_value: Variant = _visual_accessor.call("texture", frame)
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
		"%s.%s.chunk%d" % [_edition, ARCHIVE, chunk],
	]
	if chunk == 0:
		aliases.append("%s.%s" % [_edition, ARCHIVE])
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
			"anchor_x": 0,
			"anchor_y": 0,
		},
	}


func _sections() -> Array:
	var value: Variant = _model.get("sections", [])
	return value if value is Array else []


func _current_section() -> Dictionary:
	var sections := _sections()
	if _section_index < 0 or _section_index >= sections.size():
		return {}
	var value: Variant = sections[_section_index]
	return value if value is Dictionary else {}


func _current_topics() -> Array:
	var value: Variant = _current_section().get("topics", [])
	return value if value is Array else []


func _current_topic() -> Dictionary:
	var topics := _current_topics()
	if _topic_index < 0 or _topic_index >= topics.size():
		return {}
	var value: Variant = topics[_topic_index]
	return value if value is Dictionary else {}


func _current_pages() -> Array:
	var value: Variant = _current_topic().get("pages", [])
	return value if value is Array else []


func _canonical_edition(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var normalized := str(value).strip_edges()
	return normalized if normalized in VALID_EDITIONS else ""


func _validate_model(value: Dictionary) -> bool:
	if _edition.is_empty() or str(value.get("schema", "")) != SCHEMA:
		return false
	var sections_value: Variant = value.get("sections", null)
	if not sections_value is Array or (sections_value as Array).size() != SECTION_COUNT:
		return false
	var resource_index := 1
	for section_index in range(SECTION_COUNT):
		var section: Variant = (sections_value as Array)[section_index]
		if not section is Dictionary:
			return false
		if _metadata_integer((section as Dictionary).get("id", null), -1) != section_index:
			return false
		if typeof((section as Dictionary).get("label", null)) != TYPE_STRING:
			return false
		var topics_value: Variant = (section as Dictionary).get("topics", null)
		if not topics_value is Array or (topics_value as Array).size() != int(EXPECTED_TOPIC_COUNTS[section_index]):
			return false
		for topic in topics_value:
			if not topic is Dictionary:
				return false
			if _metadata_integer((topic as Dictionary).get("resource_index", null), -1) != resource_index:
				return false
			resource_index += 1
			if typeof((topic as Dictionary).get("title", null)) != TYPE_STRING:
				return false
			var pages_value: Variant = (topic as Dictionary).get("pages", null)
			if not pages_value is Array or (pages_value as Array).is_empty():
				return false
			for page in pages_value:
				if not page is Array or (page as Array).is_empty() or (page as Array).size() > MAX_BODY_LINES:
					return false
				for line in page:
					if typeof(line) != TYPE_STRING:
						return false
	return resource_index == EXPECTED_TOPIC_TOTAL + 1


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
