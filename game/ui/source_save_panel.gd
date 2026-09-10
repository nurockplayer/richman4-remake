class_name SourceSavePanel
extends Control

## Source-shaped save/load slot picker.
##
## This control owns only presentation and selection.  It accepts the already
## validated rows returned by SaveSlots.scan() and never reads or writes a
## save, constructs a GameState, or changes a live game.  The caller remains
## responsible for calling SaveSlots.read()/write() after the signals below.
##
## The original frame is a 640x480 canvas.  Game Data479 and
## MultiverseJourney Data520 contain the corresponding load/save frame chunks;
## the visual accessor is injected so this panel does not perform filesystem
## work while it is being configured or rendered.

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const LOAD_IMAGE_SIZE := Vector2(555.0, 451.0)
const SAVE_IMAGE_SIZE := Vector2(555.0, 381.0)
const LOAD_IMAGE_POSITION := Vector2(40.0, 15.0)
const SAVE_IMAGE_POSITION := Vector2(40.0, 48.0)
const SOURCE_DATA_RESOURCE := {
	"Game": 479,
	"MultiverseJourney": 520,
}
const MODE_LOAD := "load"
const MODE_SAVE := "save"
const STATUS_EMPTY := "empty"
const STATUS_VALID := "valid"
const STATUS_CORRUPT := "corrupt"
const STATUS_INVALID := "invalid"
const STATUS_UNREADABLE := "unreadable"
const STATUS_ERROR := "error"
const SOURCE_PORTRAIT_RESOURCE := 2
const SOURCE_PORTRAIT_CHUNK_COUNT := 12

const SOURCE_PANEL := Color("#8daea7")
const SOURCE_PANEL_DARK := Color("#6f9791")
const SOURCE_PANEL_LIGHT := Color("#afc8bd")
const SOURCE_TEXT := Color("#1b2a2c")
const SOURCE_MUTED := Color("#30494a")
const SOURCE_GOLD := Color("#e5b85f")
const SOURCE_LOAD := Color("#f36b6c")
const SOURCE_SAVE := Color("#2584dd")
const SOURCE_SELECTION := Color(0.92, 0.83, 0.34, 0.32)
const SOURCE_SHADE := Color(0.03, 0.08, 0.10, 0.72)

## Canonical presentation signals.  The preview argument is a deep copy of
## the selected validated row, so receivers cannot mutate panel state.
signal slot_selected(slot_id: int, fingerprint: String, preview: Dictionary)
signal confirmed(slot_id: int, fingerprint: String, preview: Dictionary)
signal cancelled(slot_id: int, fingerprint: String, preview: Dictionary)
signal overwrite_confirmation_requested(slot_id: int, fingerprint: String, preview: Dictionary)

## Explicit aliases make the handoff readable to callers that use the longer
## selection terminology while preserving one event per user action.
signal selection_confirmed(slot_id: int, fingerprint: String, preview: Dictionary)
signal selection_cancelled(slot_id: int, fingerprint: String, preview: Dictionary)
signal overwrite_cancelled(slot_id: int, fingerprint: String, preview: Dictionary)

var edition := "Game"
var mode := MODE_LOAD
var previews: Array = []
var visuals: Object = null
var save_payload: Dictionary = {}

var reference_canvas: Control
var source_art: Control
var source_image: TextureRect
var source_fallback: ColorRect
var source_heading: Label
var source_frame: Dictionary = {}
var rows_root: Control
var action_bar: Control
var confirm_button: Button
var cancel_button: Button
var overwrite_overlay: Control
var overwrite_message: Label
var overwrite_confirm_button: Button
var overwrite_cancel_button: Button

## Public node maps are useful to a host that needs to attach focus styling or
## inspect the source hit regions.  They contain only nodes owned by this
## panel and are rebuilt whenever configure() changes the row shape.
var row_buttons: Dictionary = {}
var row_content: Dictionary = {}
var row_rects: Dictionary = {}

var _selected_slot := -1
var _overwrite_open := false
var _built := false


func _ready() -> void:
	_build()
	_layout_reference_canvas()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout_reference_canvas()


func _layout_reference_canvas() -> void:
	if reference_canvas == null:
		return
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var scale_factor := minf(viewport_size.x / REFERENCE_SIZE.x, viewport_size.y / REFERENCE_SIZE.y)
	if scale_factor <= 0.0:
		return
	reference_canvas.scale = Vector2.ONE * scale_factor
	reference_canvas.position = (viewport_size - REFERENCE_SIZE * scale_factor) * 0.5


## Configure the panel from SaveSlots.scan() output or its `slots` array.
## `visual_accessor` is expected to be the existing OriginalVisuals instance;
## passing null intentionally leaves a source-colour fallback in place.
func configure(
		next_edition: String,
		next_mode: String,
		next_previews: Variant,
		visual_accessor: Object = null,
		next_save_payload: Dictionary = {},
) -> void:
	edition = _normalized_edition(next_edition)
	mode = MODE_SAVE if next_mode.to_lower().strip_edges() == MODE_SAVE else MODE_LOAD
	visuals = visual_accessor
	save_payload = next_save_payload.duplicate(true)
	previews = _normalize_previews(next_previews)
	_selected_slot = -1
	_hide_overwrite()
	if _built:
		_render()


## Alias for callers that already have a scan result named `scan_result`.
func configure_from_scan(
		next_edition: String,
		next_mode: String,
		scan_result: Variant,
		visual_accessor: Object = null,
		next_save_payload: Dictionary = {},
) -> void:
	configure(next_edition, next_mode, scan_result, visual_accessor, next_save_payload)


func set_visuals(visual_accessor: Object) -> void:
	visuals = visual_accessor
	if _built:
		_render()


func set_edition(next_edition: String) -> void:
	edition = _normalized_edition(next_edition)
	if _built:
		_render()


func set_mode(next_mode: String) -> void:
	mode = MODE_SAVE if next_mode.to_lower().strip_edges() == MODE_SAVE else MODE_LOAD
	_selected_slot = -1
	_hide_overwrite()
	previews = _normalize_previews(previews)
	if _built:
		_render()


func set_previews(next_previews: Variant) -> void:
	previews = _normalize_previews(next_previews)
	_selected_slot = -1
	_hide_overwrite()
	if _built:
		_render()


func set_slot_previews(next_previews: Variant) -> void:
	set_previews(next_previews)


func set_save_payload(next_payload: Variant) -> void:
	save_payload = next_payload.duplicate(true) if next_payload is Dictionary else {}


func set_payload(next_payload: Variant) -> void:
	set_save_payload(next_payload)


func get_mode() -> String:
	return mode


func get_edition() -> String:
	return edition


func get_reference_size() -> Vector2:
	return REFERENCE_SIZE


func get_row_count() -> int:
	return previews.size()


func row_count() -> int:
	return get_row_count()


func get_previews() -> Array:
	return previews.duplicate(true)


func get_rows() -> Array:
	return get_previews()


func get_selected_slot() -> int:
	return _selected_slot


func selected_slot() -> int:
	return get_selected_slot()


func get_selected_preview() -> Dictionary:
	return _preview_for_slot(_selected_slot).duplicate(true)


func selected_preview() -> Dictionary:
	return get_selected_preview()


func get_selected_fingerprint() -> String:
	return str(get_selected_preview().get("fingerprint", ""))


func selected_fingerprint() -> String:
	return get_selected_fingerprint()


## Return hit geometry in the reference 640x480 canvas.  These rectangles
## mirror the source callback's strict bounds (x 0x81..0x241 and 72px rows).
func get_row_rect(slot_id: int) -> Rect2:
	return row_rects.get(slot_id, Rect2())


func row_rect(slot_id: int) -> Rect2:
	return get_row_rect(slot_id)


func get_source_geometry() -> Dictionary:
	return {
		"canvas": REFERENCE_SIZE,
		"image_position": SAVE_IMAGE_POSITION if mode == MODE_SAVE else LOAD_IMAGE_POSITION,
		"image_size": SAVE_IMAGE_SIZE if mode == MODE_SAVE else LOAD_IMAGE_SIZE,
		"rows": row_rects.duplicate(true),
	}


func is_overwrite_confirmation_visible() -> bool:
	return _overwrite_open


func has_selection() -> bool:
	return _selected_slot >= 0 and not _preview_for_slot(_selected_slot).is_empty()


## Select a row programmatically.  Invalid load rows are rejected just like
## their disabled buttons; save rows remain selectable so the caller can
## decide how to repair or replace an occupied path through its backend.
func select_slot(slot_id: int) -> bool:
	if not _valid_slot_for_mode(slot_id):
		return false
	var preview := _preview_for_slot(slot_id)
	if preview.is_empty():
		return false
	if mode == MODE_LOAD and str(preview.get("status", STATUS_ERROR)) != STATUS_VALID:
		return false
	_selected_slot = slot_id
	_update_selection_visuals()
	var fingerprint := str(preview.get("fingerprint", ""))
	var snapshot := preview.duplicate(true)
	slot_selected.emit(slot_id, fingerprint, snapshot)
	return true


func select_row(slot_id: int) -> bool:
	return select_slot(slot_id)


## Confirm the current selection.  An occupied save row first opens a custom
## source-styled confirmation overlay; no native Godot white dialog is used.
func confirm_selection() -> bool:
	if not has_selection():
		return false
	var preview := get_selected_preview()
	var fingerprint := str(preview.get("fingerprint", ""))
	if mode == MODE_SAVE and _occupied(preview):
		_show_overwrite()
		var requested := preview.duplicate(true)
		overwrite_confirmation_requested.emit(_selected_slot, fingerprint, requested)
		return false
	_emit_confirmed()
	return true


func confirm() -> bool:
	return confirm_selection()


func confirm_overwrite() -> bool:
	if not _overwrite_open or not has_selection():
		return false
	_hide_overwrite()
	_emit_confirmed()
	return true


func accept_overwrite() -> bool:
	return confirm_overwrite()


## Clear only the selection.  The deep-copied row previews are deliberately
## untouched, so a caller can cancel and reopen the picker without rescanning.
func cancel_selection() -> void:
	if _overwrite_open:
		cancel_overwrite()
		return
	var slot_id := _selected_slot
	var preview := get_selected_preview()
	var fingerprint := str(preview.get("fingerprint", ""))
	_selected_slot = -1
	_update_selection_visuals()
	cancelled.emit(slot_id, fingerprint, preview.duplicate(true))
	selection_cancelled.emit(slot_id, fingerprint, preview.duplicate(true))


func cancel() -> void:
	cancel_selection()


func cancel_overwrite() -> void:
	if not _overwrite_open:
		return
	var preview := get_selected_preview()
	var slot_id := _selected_slot
	var fingerprint := str(preview.get("fingerprint", ""))
	_hide_overwrite()
	overwrite_cancelled.emit(slot_id, fingerprint, preview.duplicate(true))


func reject_overwrite() -> void:
	cancel_overwrite()


func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	reference_canvas = Control.new()
	reference_canvas.name = "SourceSaveReferenceCanvas"
	reference_canvas.position = Vector2.ZERO
	reference_canvas.size = REFERENCE_SIZE
	reference_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(reference_canvas)
	source_art = Control.new()
	source_art.name = "SourceSaveArt"
	source_art.position = Vector2.ZERO
	source_art.size = REFERENCE_SIZE
	source_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reference_canvas.add_child(source_art)
	rows_root = Control.new()
	rows_root.name = "SourceSaveRows"
	rows_root.position = Vector2.ZERO
	rows_root.size = REFERENCE_SIZE
	rows_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reference_canvas.add_child(rows_root)
	_build_action_bar()
	_build_overwrite_overlay()
	_render()


func _build_action_bar() -> void:
	action_bar = Control.new()
	action_bar.name = "SourceSaveActions"
	action_bar.size = Vector2(640.0, 28.0)
	action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reference_canvas.add_child(action_bar)
	confirm_button = _source_button("確認", "ConfirmSelection")
	confirm_button.position = Vector2(222.0, 2.0)
	confirm_button.size = Vector2(94.0, 24.0)
	confirm_button.pressed.connect(confirm_selection)
	action_bar.add_child(confirm_button)
	cancel_button = _source_button("取消", "CancelSelection")
	cancel_button.position = Vector2(324.0, 2.0)
	cancel_button.size = Vector2(94.0, 24.0)
	cancel_button.pressed.connect(cancel_selection)
	action_bar.add_child(cancel_button)


func _build_overwrite_overlay() -> void:
	overwrite_overlay = Control.new()
	overwrite_overlay.name = "SourceOverwriteConfirmation"
	overwrite_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overwrite_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overwrite_overlay.z_index = 100
	reference_canvas.add_child(overwrite_overlay)
	var shade := ColorRect.new()
	shade.name = "SourceOverwriteShade"
	shade.color = SOURCE_SHADE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overwrite_overlay.add_child(shade)
	var card := PanelContainer.new()
	card.name = "SourceOverwriteCard"
	card.position = Vector2(142.0, 175.0)
	card.size = Vector2(356.0, 130.0)
	card.add_theme_stylebox_override("panel", _style(SOURCE_PANEL, SOURCE_GOLD, 0, 2))
	overwrite_overlay.add_child(card)
	var margin := MarginContainer.new()
	margin.name = "SourceOverwriteMargin"
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 11)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 11)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "SourceOverwriteColumn"
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	overwrite_message = _source_label("", 12, SOURCE_TEXT)
	overwrite_message.name = "SourceOverwriteMessage"
	overwrite_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overwrite_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overwrite_message.custom_minimum_size = Vector2(0.0, 46.0)
	column.add_child(overwrite_message)
	var buttons := HBoxContainer.new()
	buttons.name = "SourceOverwriteButtons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	overwrite_confirm_button = _source_button("覆寫", "ConfirmOverwrite")
	overwrite_confirm_button.custom_minimum_size = Vector2(100.0, 25.0)
	overwrite_confirm_button.pressed.connect(confirm_overwrite)
	buttons.add_child(overwrite_confirm_button)
	overwrite_cancel_button = _source_button("返回", "CancelOverwrite")
	overwrite_cancel_button.custom_minimum_size = Vector2(100.0, 25.0)
	overwrite_cancel_button.pressed.connect(cancel_overwrite)
	buttons.add_child(overwrite_cancel_button)
	overwrite_overlay.hide()


func _render() -> void:
	if not _built:
		return
	_render_source_art()
	_clear_rows()
	var image_position := SAVE_IMAGE_POSITION if mode == MODE_SAVE else LOAD_IMAGE_POSITION
	var image_size := SAVE_IMAGE_SIZE if mode == MODE_SAVE else LOAD_IMAGE_SIZE
	var row_ids := _slot_ids()
	for index in range(row_ids.size()):
		var slot_id := int(row_ids[index])
		var preview := _preview_for_slot(slot_id)
		var rect := _source_row_rect(slot_id)
		row_rects[slot_id] = rect
		_create_row(slot_id, preview, rect)
	# The art is intentionally not a parent of the buttons.  Rows therefore
	# remain clickable even when the source texture has transparent pixels.
	action_bar.position = Vector2(0.0, 458.0 if mode == MODE_LOAD else 436.0)
	action_bar.size = Vector2(640.0, 22.0 if mode == MODE_LOAD else 44.0)
	if source_art != null:
		source_art.position = Vector2.ZERO
		source_art.size = REFERENCE_SIZE
	if overwrite_overlay != null:
		overwrite_overlay.visible = _overwrite_open
	_update_selection_visuals()


func _render_source_art() -> void:
	if source_art == null:
		return
	for child in source_art.get_children():
		child.queue_free()
	source_image = null
	source_fallback = null
	source_heading = null
	source_frame = _source_ui_frame()
	var image_position := SAVE_IMAGE_POSITION if mode == MODE_SAVE else LOAD_IMAGE_POSITION
	var image_size := SAVE_IMAGE_SIZE if mode == MODE_SAVE else LOAD_IMAGE_SIZE
	var backdrop := ColorRect.new()
	backdrop.name = "SourceSaveBackdrop"
	backdrop.position = Vector2.ZERO
	backdrop.size = REFERENCE_SIZE
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_art.add_child(backdrop)
	if not source_frame.is_empty() and visuals != null and visuals.has_method("texture"):
		var texture_value: Variant = visuals.call("texture", source_frame)
		if texture_value is Texture2D:
			source_image = TextureRect.new()
			source_image.name = "SourceSaveImage"
			source_image.texture = texture_value
			source_image.position = image_position
			source_image.size = image_size
			source_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			source_image.stretch_mode = TextureRect.STRETCH_KEEP
			source_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			source_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			source_art.add_child(source_image)
		return
	_build_fallback_art(image_position, image_size)


func _build_fallback_art(image_position: Vector2, image_size: Vector2) -> void:
	source_fallback = ColorRect.new()
	source_fallback.name = "SourceSaveFallback"
	source_fallback.position = image_position
	source_fallback.size = image_size
	source_fallback.color = SOURCE_PANEL
	source_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_art.add_child(source_fallback)
	var border := PanelContainer.new()
	border.name = "SourceSaveFallbackBorder"
	border.position = image_position
	border.size = image_size
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0), SOURCE_PANEL_LIGHT, 0, 1))
	source_art.add_child(border)
	var title_back := ColorRect.new()
	title_back.name = "SourceSaveTitleBack"
	title_back.position = image_position + Vector2(0.0, 24.0)
	title_back.size = Vector2(72.0, 40.0)
	title_back.color = SOURCE_GOLD
	title_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_art.add_child(title_back)
	source_heading = _source_label("LOAD" if mode == MODE_LOAD else "SAVE", 18, SOURCE_LOAD if mode == MODE_LOAD else SOURCE_SAVE)
	source_heading.name = "SourceSaveHeading"
	source_heading.position = image_position + Vector2(0.0, 28.0)
	source_heading.size = Vector2(72.0, 30.0)
	source_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	source_art.add_child(source_heading)
	# The source frame's left column contains six/five translucent row cards.
	var row_ids := _slot_ids()
	for index in range(row_ids.size()):
		var card := ColorRect.new()
		card.name = "SourceSaveFallbackRow_%d" % int(row_ids[index])
		card.position = image_position + Vector2(72.0, 4.0 + float(index) * 72.0)
		card.size = Vector2(170.0, 66.0)
		card.color = Color(0.75, 0.86, 0.81, 0.16)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		source_art.add_child(card)


func _create_row(slot_id: int, preview: Dictionary, rect: Rect2) -> void:
	var row_button := Button.new()
	row_button.name = "SourceSaveRow_%d" % slot_id
	row_button.position = rect.position
	row_button.size = rect.size
	row_button.flat = true
	row_button.focus_mode = Control.FOCUS_ALL
	row_button.mouse_filter = Control.MOUSE_FILTER_STOP
	row_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	row_button.add_theme_stylebox_override("hover", _style(SOURCE_SELECTION, SOURCE_GOLD, 0, 1))
	row_button.add_theme_stylebox_override("pressed", _style(Color(0.92, 0.83, 0.34, 0.46), SOURCE_GOLD, 0, 1))
	row_button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), SOURCE_GOLD, 0, 1))
	row_button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	row_button.pressed.connect(select_slot.bind(slot_id))
	var is_valid := str(preview.get("status", STATUS_ERROR)) == STATUS_VALID
	row_button.disabled = mode == MODE_LOAD and not is_valid
	row_button.tooltip_text = _row_tooltip(slot_id, preview)
	rows_root.add_child(row_button)
	row_buttons[slot_id] = row_button
	var content := Control.new()
	content.name = "SourceSaveRowContent_%d" % slot_id
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_button.add_child(content)
	row_content[slot_id] = content
	var numeral := _source_label(str(slot_id), 10, SOURCE_TEXT)
	numeral.name = "SlotNumber"
	numeral.position = Vector2(-54.0, 25.0)
	numeral.size = Vector2(34.0, 20.0)
	numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(numeral)
	if mode == MODE_LOAD and slot_id == 0:
		var legacy := _source_label("原有存檔", 9, SOURCE_TEXT)
		legacy.name = "OriginalSaveLabel"
		legacy.position = Vector2(-20.0, 47.0)
		legacy.size = Vector2(92.0, 20.0)
		legacy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(legacy)
	_render_row_content(content, slot_id, preview)


func _render_row_content(content: Control, slot_id: int, preview: Dictionary) -> void:
	var status := str(preview.get("status", STATUS_ERROR)).to_lower()
	var metadata: Dictionary = preview.get("metadata", {}).duplicate(true) if preview.get("metadata", {}) is Dictionary else {}
	var date_text := str(metadata.get("date_text", ""))
	var map_text := str(metadata.get("map_name", metadata.get("map", metadata.get("map_id", ""))))
	var names := _metadata_names(metadata)
	var state_text := _status_text(status)
	var details := ""
	if status == STATUS_VALID:
		var first_line := " · ".join(_non_empty_strings([date_text, map_text]))
		var second_line := "、".join(names)
		details = first_line
		if not second_line.is_empty():
			details += "\n" if not details.is_empty() else ""
			details += second_line
		if details.is_empty():
			details = "存檔有效"
	else:
		details = state_text
		var error_text := str(preview.get("error", ""))
		if not error_text.is_empty() and status in [STATUS_CORRUPT, STATUS_INVALID, STATUS_UNREADABLE, STATUS_ERROR]:
			details += "\n" + error_text
	var details_label := _source_label(details, 9, SOURCE_TEXT if status == STATUS_VALID else SOURCE_MUTED)
	details_label.name = "SlotDetails"
	details_label.position = Vector2(4.0, 13.0)
	details_label.size = Vector2(300.0, 47.0)
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.clip_text = true
	content.add_child(details_label)
	_render_portraits(content, metadata, preview)


func _render_portraits(content: Control, metadata: Dictionary, preview: Dictionary) -> void:
	var portrait_chunks := _portrait_chunks(metadata, preview)
	if portrait_chunks.is_empty():
		return
	for index in range(mini(portrait_chunks.size(), 4)):
		var chunk := int(portrait_chunks[index])
		var frame := _source_portrait_frame(chunk)
		if frame.is_empty() or visuals == null or not visuals.has_method("texture"):
			continue
		var texture_value: Variant = visuals.call("texture", frame)
		if not texture_value is Texture2D:
			continue
		var image := TextureRect.new()
		image.name = "Portrait_%d" % index
		image.texture = texture_value
		image.position = Vector2(402.0 + float(index) * 31.0, 9.0)
		image.size = Vector2(28.0, 28.0)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(image)


func _build_overwrite_text() -> void:
	if overwrite_message == null:
		return
	overwrite_message.text = "檔位 %d 已有內容。\n確定要覆寫這個存檔嗎？" % _selected_slot


func _show_overwrite() -> void:
	_overwrite_open = true
	_build_overwrite_text()
	if overwrite_overlay != null:
		overwrite_overlay.show()


func _hide_overwrite() -> void:
	_overwrite_open = false
	if overwrite_overlay != null:
		overwrite_overlay.hide()


func _emit_confirmed() -> void:
	var preview := get_selected_preview()
	var slot_id := _selected_slot
	var fingerprint := str(preview.get("fingerprint", ""))
	var snapshot := preview.duplicate(true)
	confirmed.emit(slot_id, fingerprint, snapshot.duplicate(true))
	selection_confirmed.emit(slot_id, fingerprint, snapshot.duplicate(true))


func _update_selection_visuals() -> void:
	if confirm_button == null:
		return
	confirm_button.disabled = not has_selection()
	for slot_value in row_buttons.keys():
		var slot_id := int(slot_value)
		var button: Button = row_buttons[slot_id]
		button.set_meta("selected", slot_id == _selected_slot)
		button.modulate = Color.WHITE if slot_id == _selected_slot or _selected_slot < 0 else Color(0.9, 0.9, 0.9, 1.0)


func _clear_rows() -> void:
	row_buttons.clear()
	row_content.clear()
	row_rects.clear()
	if rows_root == null:
		return
	for child in rows_root.get_children():
		rows_root.remove_child(child)
		child.queue_free()


func _source_row_rect(slot_id: int) -> Rect2:
	var index := slot_id if mode == MODE_LOAD else slot_id - 1
	var image_position := SAVE_IMAGE_POSITION if mode == MODE_SAVE else LOAD_IMAGE_POSITION
	# Source callback bounds are x > 0x81 && x < 0x241 and y > 0x18
	# && y < 0x1c8 for load; save uses y > 0x39 && y < 0x1a1.
	var x := 129.0
	var y := 24.0 + float(index) * 72.0 if mode == MODE_LOAD else 57.0 + float(index) * 72.0
	var width := 448.0
	var height := 72.0
	# Keep image placement explicit in this method so a geometry test can catch
	# an accidental shift of the source frame independently of row selection.
	if image_position.x < 0.0 or image_position.y < 0.0:
		return Rect2()
	return Rect2(x, y, width, height)


func _slot_ids() -> Array:
	var result: Array = []
	if mode == MODE_LOAD:
		for slot_id in range(0, 6):
			result.append(slot_id)
	else:
		for slot_id in range(1, 6):
			result.append(slot_id)
	return result


func _normalize_previews(raw: Variant) -> Array:
	var source: Array = []
	if raw is Dictionary:
		var slots: Variant = raw.get("slots", raw.get("previews", []))
		if slots is Array:
			source = slots.duplicate(true)
	elif raw is Array:
		source = raw.duplicate(true)
	var expected := _slot_ids()
	var output: Array = []
	var has_explicit_slot := false
	for item in source:
		if item is Dictionary and typeof(item.get("slot", null)) == TYPE_INT:
			has_explicit_slot = true
			break
	for index in range(expected.size()):
		var slot_id := int(expected[index])
		var found: Dictionary = {}
		if has_explicit_slot:
			for item in source:
				if item is Dictionary and int(item.get("slot", -1)) == slot_id:
					found = item.duplicate(true)
					break
		else:
			var source_index := index
			if source_index < source.size() and source[source_index] is Dictionary:
				found = source[source_index].duplicate(true)
		if found.is_empty():
			found = _empty_preview(slot_id)
		else:
			found["slot"] = slot_id
			if not found.has("status"):
				found["status"] = STATUS_ERROR
			if not found.has("fingerprint"):
				found["fingerprint"] = ""
		output.append(found)
	return output


func _empty_preview(slot_id: int) -> Dictionary:
	return {
		"ok": true,
		"status": STATUS_EMPTY,
		"slot": slot_id,
		"fingerprint": "",
		"metadata": {},
	}


func _preview_for_slot(slot_id: int) -> Dictionary:
	for preview in previews:
		if preview is Dictionary and int(preview.get("slot", -1)) == slot_id:
			return preview
	return {}


func _valid_slot_for_mode(slot_id: int) -> bool:
	return slot_id in _slot_ids()


func _occupied(preview: Dictionary) -> bool:
	return str(preview.get("status", STATUS_EMPTY)).to_lower() != STATUS_EMPTY and not str(preview.get("path", "")).is_empty()


func _status_text(status: String) -> String:
	match status:
		STATUS_EMPTY: return "空白欄位"
		STATUS_VALID: return "存檔有效"
		STATUS_CORRUPT: return "存檔損毀"
		STATUS_INVALID: return "存檔無效"
		STATUS_UNREADABLE: return "存檔無法讀取"
		_: return "存檔狀態未知"


func _row_tooltip(slot_id: int, preview: Dictionary) -> String:
	var status := str(preview.get("status", STATUS_ERROR)).to_lower()
	if mode == MODE_LOAD and status != STATUS_VALID:
		return "檔位 %d：%s" % [slot_id, _status_text(status)]
	if mode == MODE_SAVE and _occupied(preview):
		return "檔位 %d：已有內容，確認後可覆寫" % slot_id
	return "檔位 %d：%s" % [slot_id, _status_text(status)]


func _metadata_names(metadata: Dictionary) -> Array:
	var names: Array = []
	var raw_names: Variant = metadata.get("player_names", metadata.get("players", []))
	if raw_names is Array:
		for player in raw_names:
			if player is Dictionary:
				var player_name := str(player.get("name", ""))
				if not player_name.is_empty():
					names.append(player_name)
			elif not str(player).is_empty():
				names.append(str(player))
	return names


func _portrait_chunks(metadata: Dictionary, preview: Dictionary) -> Array:
	var raw: Variant = metadata.get("portrait_chunks", null)
	if raw == null:
		raw = preview.get("portrait_chunks", null)
	if raw is Array:
		return _valid_portrait_chunks(raw)
	var player_ids: Variant = metadata.get("player_character_ids", null)
	if player_ids == null:
		player_ids = preview.get("player_character_ids", null)
	if player_ids is Array:
		return _valid_portrait_chunks(player_ids)
	var players: Variant = metadata.get("players", null)
	if players is Array:
		var result: Array = []
		for player in players:
			if not player is Dictionary:
				continue
			var chunk_value: Variant = player.get("portrait_chunk", player.get("character_id", null))
			if typeof(chunk_value) == TYPE_INT and int(chunk_value) >= 0 and int(chunk_value) < SOURCE_PORTRAIT_CHUNK_COUNT:
				result.append(int(chunk_value))
		return result
	return []


func _valid_portrait_chunks(raw: Array) -> Array:
	var result: Array = []
	for value in raw:
		if typeof(value) == TYPE_INT and int(value) >= 0 and int(value) < SOURCE_PORTRAIT_CHUNK_COUNT:
			result.append(int(value))
	return result


func _source_ui_frame() -> Dictionary:
	if visuals == null or not visuals.has_method("ui"):
		return {}
	var resource := int(SOURCE_DATA_RESOURCE.get(edition, SOURCE_DATA_RESOURCE["Game"]))
	var frame_value: Variant = visuals.call("ui", edition, "Data", resource, 0 if mode == MODE_LOAD else 1)
	return frame_value if frame_value is Dictionary else {}


func _source_portrait_frame(chunk: int) -> Dictionary:
	if visuals == null or not visuals.has_method("ui"):
		return {}
	if chunk < 0 or chunk >= SOURCE_PORTRAIT_CHUNK_COUNT:
		return {}
	var frame_value: Variant = visuals.call("ui", edition, "Data", SOURCE_PORTRAIT_RESOURCE, chunk)
	return frame_value if frame_value is Dictionary else {}


func _normalized_edition(value: String) -> String:
	return value if SOURCE_DATA_RESOURCE.has(value) else "Game"


func _non_empty_strings(values: Array) -> Array:
	var result: Array = []
	for value in values:
		var text := str(value)
		if not text.is_empty():
			result.append(text)
	return result


func _source_button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", SOURCE_TEXT)
	button.add_theme_color_override("font_hover_color", SOURCE_TEXT)
	button.add_theme_color_override("font_pressed_color", SOURCE_TEXT)
	button.add_theme_color_override("font_disabled_color", SOURCE_MUTED)
	button.add_theme_stylebox_override("normal", _style(SOURCE_PANEL_LIGHT, SOURCE_TEXT, 0, 1))
	button.add_theme_stylebox_override("hover", _style(SOURCE_GOLD, SOURCE_TEXT, 0, 1))
	button.add_theme_stylebox_override("pressed", _style(SOURCE_GOLD.darkened(0.12), SOURCE_TEXT, 0, 1))
	button.add_theme_stylebox_override("disabled", _style(SOURCE_PANEL_DARK, SOURCE_MUTED, 0, 1))
	return button


func _source_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _style(background: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = background
	result.border_color = border
	result.set_border_width_all(width)
	result.set_corner_radius_all(radius)
	return result
