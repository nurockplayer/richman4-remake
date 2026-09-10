class_name RichmanSourceTitlePanel
extends Control

## Source-shaped title entry surface.
##
## The original title is a 640x480 Data1 frame.  This control keeps that
## logical surface fixed and leaves scaling to its host.  It accepts an
## already-created OriginalVisuals-like accessor; it never discovers a
## manifest, reads a file, or owns an edition/catalog decision.

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const EDITION_GAME := "Game"
const EDITION_MULTIVERSE := "MultiverseJourney"
const VALID_EDITIONS := [EDITION_GAME, EDITION_MULTIVERSE]

const BUTTON_ORDER := ["start", "load", "option", "exit", "new_stage"]
const SOURCE_ANCHORS := {
	"start": Vector2(190.0, 380.0),
	"load": Vector2(328.0, 380.0),
	"option": Vector2(468.0, 378.0),
	"exit": Vector2(328.0, 450.0),
	"new_stage": Vector2(62.0, 380.0),
}
const NORMAL_CHUNKS := {
	"start": 1,
	"load": 3,
	"option": 5,
	"exit": 7,
	"new_stage": 9,
}
const HOVER_CHUNKS := {
	"start": 2,
	"load": 4,
	"option": 6,
	"exit": 8,
	"new_stage": 10,
}
const BUTTON_NAMES := {
	"start": "SourceTitleStart",
	"load": "SourceTitleLoad",
	"option": "SourceTitleOption",
	"exit": "SourceTitleExit",
	"new_stage": "SourceTitleNewStage",
}
const BUTTON_LABELS := {
	"start": "開始新局",
	"load": "讀取存檔",
	"option": "選項",
	"exit": "離開遊戲",
	"new_stage": "新關卡",
}

# Safe source metadata is retained when an optional frame record or its
# texture is unavailable.  These dimensions describe hit regions in logical
# coordinates; they are never inferred from physical texture pixels.
const HOVER_LOGICAL := {
	"start": {"width": 116, "height": 113, "anchor_x": 59, "anchor_y": 57},
	"load": {"width": 114, "height": 99, "anchor_x": 55, "anchor_y": 54},
	"option": {"width": 103, "height": 98, "anchor_x": 53, "anchor_y": 46},
	"exit": {"width": 58, "height": 19, "anchor_x": 29, "anchor_y": 10},
	"new_stage": {"width": 90, "height": 107, "anchor_x": 45, "anchor_y": 52},
}
const NORMAL_EXIT_LOGICAL := {"width": 53, "height": 18, "anchor_x": 27, "anchor_y": 9}

signal start_requested(stage: int)
signal load_requested
signal option_requested
signal quit_requested

## The host may inspect these nodes to attach focus or capability policy.  The
## option button starts enabled; S35 can disable it without changing this
## component's source intent signal.
var buttons: Dictionary = {}
var background_art: TextureRect
var hover_art: TextureRect
var exit_normal_art: TextureRect

var edition := ""
var visuals: Object = null

var _surface: Control
var _fallback_background: ColorRect
var _fallback_title: Label
var _fallback_hint: Label
var _source_frames: Dictionary = {}
var _source_textures: Dictionary = {}
var _button_rects: Dictionary = {}
var _hover_key := ""
var _built := false
var _configured := false


func _init() -> void:
	_build()


func _ready() -> void:
	# This component is deliberately not a full-viewport control.  The parent
	# shell owns the one and only contain scale for this fixed logical surface.
	size = REFERENCE_SIZE
	_render()


func _exit_tree() -> void:
	# The MJ-only button is detached from the surface for Game titles so the
	# source tree has no NEW STAGE node.  Free that retained public object when
	# the component itself leaves the tree; otherwise it would remain orphaned.
	if buttons.has("new_stage"):
		var stage_button: Button = buttons["new_stage"]
		if is_instance_valid(stage_button):
			if stage_button.get_parent() != null:
				stage_button.get_parent().remove_child(stage_button)
			stage_button.free()


## Configure from an existing source visual accessor.  Passing null is a
## supported no-art mode and produces a readable, transparent-button fallback.
## Unknown editions are fail-closed: no artwork or entry signal is exposed.
func configure(next_edition: String, visual_accessor: Object = null) -> void:
	_build()
	var normalized := next_edition.strip_edges()
	_configured = true
	if normalized not in VALID_EDITIONS:
		edition = ""
		visuals = null
		hide()
		_render()
		return
	edition = normalized
	visuals = visual_accessor
	_render()


func get_reference_size() -> Vector2:
	return REFERENCE_SIZE


func get_edition() -> String:
	return edition


func is_valid_edition() -> bool:
	return edition in VALID_EDITIONS


func set_option_enabled(enabled: bool) -> void:
	if buttons.has("option"):
		(buttons["option"] as Button).disabled = not enabled


func get_button_rect(source_key: String) -> Rect2:
	return _button_rects.get(source_key, Rect2())


func button_rect(source_key: String) -> Rect2:
	return get_button_rect(source_key)


func get_button_rects() -> Dictionary:
	return _button_rects.duplicate(true)


func get_hover_key() -> String:
	return _hover_key


func active_hover_key() -> String:
	return get_hover_key()


func get_source_frame(source_key: String) -> Dictionary:
	var frame: Variant = _source_frames.get(source_key, {})
	return frame.duplicate(true) if frame is Dictionary else {}


func get_source_frames() -> Dictionary:
	return _source_frames.duplicate(true)


func get_source_geometry() -> Dictionary:
	return {
		"canvas": REFERENCE_SIZE,
		"edition": edition,
		"buttons": get_button_rects(),
	}


func _build() -> void:
	if _built:
		return
	_built = true
	set_size(REFERENCE_SIZE)
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_surface = Control.new()
	_surface.name = "SourceTitleSurface"
	_surface.position = Vector2.ZERO
	_surface.size = REFERENCE_SIZE
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)

	_fallback_background = ColorRect.new()
	_fallback_background.name = "SourceTitleFallbackBackground"
	_fallback_background.position = Vector2.ZERO
	_fallback_background.size = REFERENCE_SIZE
	_fallback_background.color = Color("#18343d")
	_fallback_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(_fallback_background)

	_fallback_title = Label.new()
	_fallback_title.name = "SourceTitleFallbackTitle"
	_fallback_title.position = Vector2(80.0, 166.0)
	_fallback_title.size = Vector2(480.0, 48.0)
	_fallback_title.text = "大富翁 4 · 城市棋局"
	_fallback_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fallback_title.add_theme_font_size_override("font_size", 28)
	_fallback_title.add_theme_color_override("font_color", Color("#f2d58f"))
	_fallback_title.add_theme_color_override("font_outline_color", Color("#09171c"))
	_fallback_title.add_theme_constant_override("outline_size", 4)
	_fallback_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(_fallback_title)

	_fallback_hint = Label.new()
	_fallback_hint.name = "SourceTitleFallbackHint"
	_fallback_hint.position = Vector2(120.0, 218.0)
	_fallback_hint.size = Vector2(400.0, 26.0)
	_fallback_hint.text = "來源畫面素材未載入"
	_fallback_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback_hint.add_theme_font_size_override("font_size", 13)
	_fallback_hint.add_theme_color_override("font_color", Color("#b6d5cf"))
	_fallback_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(_fallback_hint)

	background_art = _art("SourceTitleBackgroundArt")
	background_art.set_meta("source_key", "background")
	background_art.set_meta("source_chunk", 0)
	_surface.add_child(background_art)

	exit_normal_art = _art("SourceTitleExitNormalArt")
	exit_normal_art.set_meta("source_key", "exit_normal")
	exit_normal_art.set_meta("source_chunk", 7)
	exit_normal_art.z_index = 1
	_surface.add_child(exit_normal_art)

	hover_art = _art("SourceTitleHoverArt")
	hover_art.set_meta("source_key", "hover")
	hover_art.z_index = 2
	hover_art.hide()
	_surface.add_child(hover_art)

	for source_key in BUTTON_ORDER:
		var button := Button.new()
		button.name = str(BUTTON_NAMES[source_key])
		button.set_meta("source_key", source_key)
		button.set_meta("source_chunk", int(HOVER_CHUNKS[source_key]))
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.custom_minimum_size = Vector2.ZERO
		button.flat = true
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		button.tooltip_text = str(BUTTON_LABELS[source_key])
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_color_override("font_color", Color("#f7e7b2"))
		button.add_theme_color_override("font_hover_color", Color("#fff6d0"))
		button.add_theme_color_override("font_pressed_color", Color("#fff6d0"))
		button.add_theme_color_override("font_focus_color", Color("#fff6d0"))
		button.add_theme_color_override("font_disabled_color", Color("#9fb6b4"))
		for state in [
			"normal", "hover", "pressed", "focus", "disabled", "hover_pressed",
			"normal_mirrored", "hover_mirrored", "pressed_mirrored", "disabled_mirrored",
			"focus_mirrored", "focus_hover", "focus_hover_mirrored", "hover_pressed_mirrored",
		]:
			button.add_theme_stylebox_override(state, _transparent_style())
		button.mouse_entered.connect(_on_button_mouse_entered.bind(source_key))
		button.mouse_exited.connect(_on_button_mouse_exited.bind(source_key))
		button.pressed.connect(_on_button_pressed.bind(source_key))
		if source_key != "new_stage":
			_surface.add_child(button)
		buttons[source_key] = button

	# NEW STAGE is attached to the scene only for the expansion title.  Its
	# Button object remains in the public map so a host can keep stable access
	# while `find_child()` on an ordinary Game title stays source-accurate.
	(buttons["new_stage"] as Button).hide()


func _render() -> void:
	if not _built:
		return
	_hover_key = ""
	_source_frames.clear()
	_source_textures.clear()
	_button_rects.clear()
	hover_art.hide()
	hover_art.texture = null
	background_art.texture = null
	exit_normal_art.texture = null

	if not is_valid_edition():
		_surface.hide()
		_set_new_stage_tree(false)
		for source_key in BUTTON_ORDER:
			var invalid_button: Button = buttons[source_key]
			invalid_button.hide()
			invalid_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return

	_surface.show()
	_set_new_stage_tree(edition == EDITION_MULTIVERSE)
	var background_frame := _ui_frame(0)
	var background_texture := _texture_for(background_frame)
	_source_frames["background"] = background_frame
	_source_textures["background"] = background_texture
	background_art.position = Vector2.ZERO
	background_art.size = REFERENCE_SIZE
	background_art.texture = background_texture
	background_art.visible = background_texture != null
	_fallback_background.visible = background_texture == null
	_fallback_title.visible = background_texture == null
	_fallback_hint.visible = background_texture == null

	# Data1 chunk 0 already contains normal START/LOAD/OPTION and, for MJ,
	# normal NEW STAGE. EXIT is the one normal frame absent from that backdrop.
	var exit_frame := _ui_frame(7)
	var exit_texture := _texture_for(exit_frame)
	_source_frames["exit_normal"] = exit_frame
	_source_textures["exit_normal"] = exit_texture
	var exit_logical := _logical_for(exit_frame, "exit", true)
	exit_normal_art.position = _rect_for("exit", exit_logical).position
	exit_normal_art.size = _rect_for("exit", exit_logical).size
	exit_normal_art.texture = exit_texture
	exit_normal_art.visible = exit_texture != null

	for source_key in BUTTON_ORDER:
		var button: Button = buttons[source_key]
		var available: bool = source_key != "new_stage" or edition == EDITION_MULTIVERSE
		var hover_frame := _ui_frame(int(HOVER_CHUNKS[source_key])) if available else {}
		var hover_texture := _texture_for(hover_frame)
		if available:
			_source_frames[source_key + "_hover"] = hover_frame
			_source_textures[source_key + "_hover"] = hover_texture
		var logical := _logical_for(hover_frame, source_key)
		var button_rect := _rect_for(source_key, logical)
		_button_rects[source_key] = button_rect
		button.position = button_rect.position
		button.size = button_rect.size
		button.visible = available
		button.mouse_filter = Control.MOUSE_FILTER_STOP if available else Control.MOUSE_FILTER_IGNORE
		# Fallback labels are needed for the baked buttons only when their
		# backdrop is absent. EXIT has its own normal frame and needs a label only
		# when that frame is absent as well.
		var fallback_label: bool = background_texture == null and source_key != "exit"
		fallback_label = fallback_label or (source_key == "exit" and exit_texture == null)
		button.text = str(BUTTON_LABELS[source_key]) if fallback_label else ""
		if source_key == "new_stage" and not available:
			button.text = ""


func _set_new_stage_tree(available: bool) -> void:
	if not buttons.has("new_stage"):
		return
	var button: Button = buttons["new_stage"]
	if available:
		if button.get_parent() == null:
			_surface.add_child(button)
		button.show()
	else:
		if button.get_parent() != null:
			button.get_parent().remove_child(button)
		button.hide()


func _art(node_name: String) -> TextureRect:
	var art := TextureRect.new()
	art.name = node_name
	art.position = Vector2.ZERO
	art.size = REFERENCE_SIZE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


func _transparent_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_width_left = 0
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 0
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _ui_frame(chunk: int) -> Dictionary:
	if not is_valid_edition() or visuals == null or not visuals.has_method("ui"):
		return {}
	var value: Variant = visuals.call("ui", edition, "Data", 1, chunk)
	return value if value is Dictionary else {}


func _texture_for(frame: Dictionary) -> Texture2D:
	if frame.is_empty() or visuals == null or not visuals.has_method("texture"):
		return null
	var value: Variant = visuals.call("texture", frame)
	return value if value is Texture2D else null


func _logical_for(frame: Dictionary, source_key: String, normal := false) -> Dictionary:
	var fallback: Dictionary
	if normal and source_key == "exit":
		fallback = NORMAL_EXIT_LOGICAL.duplicate(true)
	else:
		fallback = HOVER_LOGICAL.get(source_key, {}).duplicate(true)
	var value: Variant = frame.get("logical", null)
	if not value is Dictionary:
		return fallback
	var logical: Dictionary = value
	for field in ["width", "height", "anchor_x", "anchor_y"]:
		var candidate: Variant = logical.get(field, null)
		var low := 1.0 if field in ["width", "height"] else -65535.0
		if _safe_number(candidate, low, 65535.0):
			fallback[field] = int(candidate)
	return fallback


func _safe_number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value) and float(value) >= low and float(value) <= high


func _rect_for(source_key: String, logical: Dictionary) -> Rect2:
	var anchor: Vector2 = SOURCE_ANCHORS.get(source_key, Vector2.ZERO)
	var anchor_offset := Vector2(float(logical.get("anchor_x", 0)), float(logical.get("anchor_y", 0)))
	var size_value := Vector2(float(logical.get("width", 1)), float(logical.get("height", 1)))
	return Rect2(anchor - anchor_offset, size_value)


func _can_interact(source_key: String) -> bool:
	if not _configured or not is_valid_edition() or not is_visible_in_tree() or not buttons.has(source_key):
		return false
	var button: Button = buttons[source_key]
	return button.visible and not button.disabled


func _on_button_mouse_entered(source_key: String) -> void:
	if not _can_interact(source_key):
		return
	_hover_key = source_key
	var frame: Dictionary = _source_frames.get(source_key + "_hover", {})
	var texture_value: Texture2D = _source_textures.get(source_key + "_hover", null)
	var button_rect: Rect2 = _button_rects.get(source_key, Rect2())
	hover_art.position = button_rect.position
	hover_art.size = button_rect.size
	hover_art.set_meta("source_key", source_key)
	hover_art.set_meta("source_chunk", int(HOVER_CHUNKS[source_key]))
	hover_art.texture = texture_value
	hover_art.visible = texture_value != null and not frame.is_empty()


func _on_button_mouse_exited(source_key: String) -> void:
	if _hover_key != source_key:
		return
	_hover_key = ""
	hover_art.hide()
	hover_art.texture = null


func _on_button_pressed(source_key: String) -> void:
	if not _can_interact(source_key):
		return
	match source_key:
		"start":
			start_requested.emit(0)
		"new_stage":
			start_requested.emit(1)
		"load":
			load_requested.emit()
		"option":
			option_requested.emit()
		"exit":
			quit_requested.emit()
