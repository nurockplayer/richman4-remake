extends Control
class_name RichmanSourceHotkeysPanel

## Pure source-shaped presenter for the independent 28-key options child.
## The host supplies a detached {edition, bindings} snapshot and an optional
## OriginalVisuals-like resolver.  This presenter owns no settings I/O,
## GameState, InputMap, native input, audio, or command consumer.

const SYSTEM_HOTKEYS := preload("res://game/platform/system_hotkeys.gd")
const REFERENCE_SIZE := Vector2(640.0, 480.0)
const FRAME_ORIGIN := Vector2(156.0, 72.0)
const FRAME_SIZE := Vector2(328.0, 336.0)
const ARCHIVE := "Data"
const SOURCE_RESOURCE := 3
const SOURCE_CHUNK := 1
const VALID_EDITIONS := ["Game", "MultiverseJourney"]
const SLOT_COUNT := 28
const FIXED_SLOT_COUNT := 8
const BLINK_SECONDS := 0.25

const SOURCE_LABELS := [
	"游標上移", "游標右移", "游標下移", "游標左移", "確定執行", "取消指令",
	"切換選項", "切換視窗組", "是<YES>", "否<NO>", "前進指令", "選擇骰子數",
	"股市", "交易", "卡片", "道具", "查詢", "地圖", "地圖向左旋轉", "地圖向右旋轉",
	"託管", "系統", "SAVE GAME", "LOAD GAME", "輔助說明", "向上換頁", "向下換頁", "結束程式",
]
const FIRST_COLUMN := Rect2(105.0, 25.0, 56.0, 240.0)
const SECOND_COLUMN := Rect2(257.0, 25.0, 56.0, 208.0)
const RESET := Rect2(17.0, 281.0, 71.0, 31.0)
const CANCEL := Rect2(130.0, 281.0, 71.0, 31.0)
const ACCEPT := Rect2(242.0, 281.0, 71.0, 31.0)

const SOURCE_CYAN := Color("#00f0f0")
const SOURCE_YELLOW := Color("#f0f000")
const SOURCE_WHITE := Color("#f0f0f0")
const SOURCE_EDGE := Color("#101010")
const UNAVAILABLE_TEXT := "熱鍵資料無法顯示"
const ART_FALLBACK_TEXT := "來源畫面素材未載入"
var _system := SYSTEM_HOTKEYS.new()

signal accepted(bindings: Array)
signal cancelled

var key_labels: Array = []
var title_labels: Array = []
var _model: Dictionary = {}
var _committed_bindings: Array = []
var _draft_bindings: Array = []
var _visual_accessor: Variant = null
var _model_valid := false
var _edition := ""
var _is_open := false
var _closed := false
var _suspended := false
var _pressed_action := ""
var _editing_slot := -1
var _editing_previous := 0
var _blink_on := true
var _source_art_available := false
var _source_art_status: Dictionary = {}
var _source_frames: Dictionary = {}
var _application_active := true
var _timer: Timer
var _surface: Control
var _frame_backdrop: ColorRect
var _unavailable_backdrop: ColorRect
var _unavailable: Label
var _built := false


func _init() -> void:
	name = "SourceHotkeysPanel"
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build()


func _ready() -> void:
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	_application_active = _application_is_focused()
	_timer = Timer.new()
	_timer.name = "SourceHotkeysBlinkTimer"
	_timer.wait_time = BLINK_SECONDS
	_timer.one_shot = false
	_timer.timeout.connect(_on_blink_timeout)
	add_child(_timer)
	_timer.start()
	_timer.paused = not _application_active


func _application_is_focused() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	for window_id in DisplayServer.get_window_list():
		if DisplayServer.window_is_focused(window_id):
			return true
	return false


func _notification(what: int) -> void:
	if what not in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		return
	_application_active = what == NOTIFICATION_APPLICATION_FOCUS_IN
	if _timer != null and is_instance_valid(_timer):
		_timer.paused = not _application_active or _suspended
	if not _application_active:
		_blink_on = false
		_render()


func set_view_model(model: Dictionary) -> bool:
	var incoming := model.duplicate(true)
	var same_model := _model_valid and _deep_equal(_model, incoming)
	var was_open := _is_open and not _closed
	_model = incoming
	_edition = _canonical_edition(_model.get("edition", null))
	_model_valid = _validate_model(_model)
	_pressed_action = ""
	_editing_slot = -1
	_editing_previous = 0
	if not _model_valid:
		_committed_bindings = []
		_draft_bindings = []
		_is_open = false
		_closed = false
		_render()
		show()
		return false
	if not same_model or not was_open:
		_committed_bindings = (_model["bindings"] as Array).duplicate(true)
		_draft_bindings = _committed_bindings.duplicate(true)
	_is_open = true
	_closed = false
	_suspended = false
	_blink_on = true
	_render()
	show()
	return true


func set_visual_accessor(accessor: Variant) -> void:
	if accessor is Dictionary:
		_visual_accessor = (accessor as Dictionary).duplicate(true)
	else:
		_visual_accessor = accessor
	_render()


func set_visuals(accessor: Variant) -> void:
	set_visual_accessor(accessor)


func view_model() -> Dictionary:
	return _model.duplicate(true)


func is_model_valid() -> bool:
	return _model_valid


func is_open() -> bool:
	return _is_open and _model_valid and visible


func draft_bindings() -> Array:
	return _draft_bindings.duplicate(true)


func committed_bindings() -> Array:
	return _committed_bindings.duplicate(true)


func source_art_available() -> bool:
	return _source_art_available


func source_frames() -> Dictionary:
	return _source_frames.duplicate(true)


func source_art_status() -> Dictionary:
	return _source_art_status.duplicate(true)


func source_geometry() -> Dictionary:
	return {
		"canvas": REFERENCE_SIZE,
		"frame_origin": FRAME_ORIGIN,
		"frame_size": FRAME_SIZE,
		"edition": _edition,
		"hitboxes": source_hitboxes(),
		"labels": SOURCE_LABELS.duplicate(),
		"fixed_slots": FIXED_SLOT_COUNT,
		"editable_slots": SLOT_COUNT - FIXED_SLOT_COUNT,
		"pressed_offset": Vector2(1.0, 1.0),
		"pressed_edge_darken": 16,
	}


func source_hitboxes() -> Dictionary:
	return {
		"first_column": FIRST_COLUMN,
		"second_column": SECOND_COLUMN,
		"reset": RESET,
		"cancel": CANCEL,
		"accept": ACCEPT,
	}


func suspend_input(suspended: bool) -> void:
	_suspended = suspended
	if suspended:
		_pressed_action = ""
		_blink_on = false
	if _timer != null and is_instance_valid(_timer):
		_timer.paused = suspended or not _application_active
	_render()


func is_input_suspended() -> bool:
	return _suspended


func pending_blink_visible() -> bool:
	return _editing_slot >= 0 and _application_active and not _suspended and _blink_on


func close_hotkeys() -> bool:
	return _cancel()


func close() -> bool:
	return close_hotkeys()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	accept_event()
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		if not mouse.pressed and not _suspended and _is_open:
			_handle_right_release()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT or _suspended or not _is_open or not _model_valid:
		return
	if mouse.pressed:
		_handle_left_down(mouse.position - FRAME_ORIGIN, mouse.double_click)
	else:
		_handle_left_up()


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree() or not _is_open or not _model_valid:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT and not mouse.pressed:
			var viewport := get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
			if _suspended:
				return
			_handle_right_release()
		return
	if not event is InputEventKey or _suspended or _editing_slot < 0:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed:
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	_handle_key(key_event)


func _handle_left_down(local: Vector2, double_click: bool) -> void:
	if double_click or not _pressed_action.is_empty():
		return
	# The source keeps the current row while an edit is pending; footer actions
	# remain available so reset/cancel/accept can still be chosen.
	if _editing_slot >= 0:
		if _contains_inclusive(RESET, local):
			_pressed_action = "reset"
		elif _contains_inclusive(CANCEL, local):
			_pressed_action = "cancel"
		elif _contains_inclusive(ACCEPT, local):
			_pressed_action = "accept"
		if not _pressed_action.is_empty():
			_render()
		return
	var slot := _slot_at(local)
	if slot >= 0:
		_pressed_action = "slot:%d" % slot
		_render()
		return
	if _contains_inclusive(RESET, local):
		_pressed_action = "reset"
		_render()
		return
	if _contains_inclusive(CANCEL, local):
		_pressed_action = "cancel"
		_render()
		return
	if _contains_inclusive(ACCEPT, local):
		_pressed_action = "accept"
		_render()


func _handle_left_up() -> void:
	if _pressed_action.is_empty():
		return
	var action := _pressed_action
	_pressed_action = ""
	if action.begins_with("slot:"):
		var slot := int(action.trim_prefix("slot:"))
		if slot >= FIXED_SLOT_COUNT and slot < SLOT_COUNT:
			_start_edit(slot)
		else:
			_render()
		return
	match action:
		"reset":
			_reset()
		"cancel":
			_cancel()
		"accept":
			_accept()


func _handle_right_release() -> void:
	if _editing_slot >= 0:
		_draft_bindings[_editing_slot] = _editing_previous
		_editing_slot = -1
		_editing_previous = 0
		_blink_on = false
		_render()
		return
	_cancel()


func _start_edit(slot: int) -> void:
	if slot < FIXED_SLOT_COUNT or slot >= _draft_bindings.size():
		_render()
		return
	_editing_slot = slot
	_editing_previous = int(_draft_bindings[slot])
	_draft_bindings[slot] = 0
	_blink_on = true
	_render()


func _handle_key(event: InputEventKey) -> void:
	var source_key := _system.event_key(event)
	if source_key == 0:
		return
	if source_key == 0x11:
		_draft_bindings[_editing_slot] = 0x1100
		_blink_on = true
		_render()
		return
	var prefix := 0x1100 if int(_draft_bindings[_editing_slot]) >> 8 == 0x11 else 0
	var candidate := prefix | source_key
	var checked := _draft_bindings.duplicate(true)
	checked[_editing_slot] = candidate
	var result: Dictionary = _system.validate_bindings(checked)
	if not bool(result.get("ok", false)) or _duplicate_elsewhere(candidate, _editing_slot):
		_blink_on = true
		_render()
		return
	_draft_bindings[_editing_slot] = candidate
	_editing_slot = -1
	_editing_previous = 0
	_blink_on = false
	_render()


func _duplicate_elsewhere(candidate: int, self_slot: int) -> bool:
	for index in range(_draft_bindings.size()):
		if index != self_slot and int(_draft_bindings[index]) == candidate:
			return true
	return false


func _accept() -> bool:
	if _closed or not _model_valid:
		return false
	var result := _draft_bindings.duplicate(true)
	var checked: Dictionary = _system.validate_bindings(result)
	if not bool(checked.get("ok", false)):
		return false
	_committed_bindings = result.duplicate(true)
	_draft_bindings = result.duplicate(true)
	_model["bindings"] = result.duplicate(true)
	_closed = true
	_is_open = false
	_suspended = false
	_pressed_action = ""
	_editing_slot = -1
	_timer_paused(false)
	hide()
	accepted.emit(result)
	return true


func _reset() -> bool:
	if _closed:
		return false
	_draft_bindings = _system.defaults()
	_editing_slot = -1
	_editing_previous = 0
	_blink_on = false
	_render()
	return true


func _cancel() -> bool:
	if _closed:
		return false
	_closed = true
	_is_open = false
	_pressed_action = ""
	_editing_slot = -1
	_editing_previous = 0
	_draft_bindings = _committed_bindings.duplicate(true)
	_suspended = false
	_timer_paused(false)
	hide()
	cancelled.emit()
	return true


func _timer_paused(value: bool) -> void:
	if _timer != null and is_instance_valid(_timer):
		_timer.paused = value or not _application_active


func _on_blink_timeout() -> void:
	if _application_active and not _suspended and _editing_slot >= 0:
		_blink_on = not _blink_on
		_render()


func _slot_at(local: Vector2) -> int:
	var column := -1
	var row := -1
	if _contains_inclusive(FIRST_COLUMN, local):
		column = 0
		row = clampi(floori((local.y - FIRST_COLUMN.position.y) / 16.0), 0, 14)
	elif _contains_inclusive(SECOND_COLUMN, local):
		column = 1
		row = clampi(floori((local.y - SECOND_COLUMN.position.y) / 16.0), 0, 12)
	if column < 0:
		return -1
	var slot := row if column == 0 else 15 + row
	return slot if slot >= 0 and slot < SLOT_COUNT else -1


func _contains_inclusive(rect: Rect2, point: Vector2) -> bool:
	return point.x >= rect.position.x and point.x <= rect.end.x - 1.0 and point.y >= rect.position.y and point.y <= rect.end.y - 1.0


func _build() -> void:
	if _built:
		return
	_built = true
	_surface = Control.new()
	_surface.name = "SourceHotkeysSurface"
	_surface.size = REFERENCE_SIZE
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)
	_frame_backdrop = ColorRect.new()
	_frame_backdrop.name = "SourceHotkeysFrameBackdrop"
	_frame_backdrop.position = FRAME_ORIGIN
	_frame_backdrop.size = FRAME_SIZE
	_frame_backdrop.color = Color("#0d1524")
	_frame_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_backdrop.visible = false
	_surface.add_child(_frame_backdrop)
	_unavailable_backdrop = ColorRect.new()
	_unavailable_backdrop.name = "SourceHotkeysUnavailableBackdrop"
	_unavailable_backdrop.position = FRAME_ORIGIN
	_unavailable_backdrop.size = FRAME_SIZE
	_unavailable_backdrop.color = Color("#0d1524")
	_unavailable_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unavailable_backdrop.visible = false
	_surface.add_child(_unavailable_backdrop)
	_unavailable = Label.new()
	_unavailable.name = "SourceHotkeysUnavailable"
	_unavailable.position = FRAME_ORIGIN + FRAME_SIZE / 2.0 - Vector2(150.0, 16.0)
	_unavailable.size = Vector2(300.0, 32.0)
	_unavailable.text = UNAVAILABLE_TEXT
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
	key_labels.clear()
	title_labels.clear()
	if not _model_valid:
		_unavailable_backdrop.visible = true
		_unavailable.visible = true
		return
	var source := _resolve_chunk(SOURCE_CHUNK)
	var frame: Dictionary = source.get("frame", {})
	_source_frames["hotkeys"] = frame.duplicate(true)
	var texture: Texture2D = source.get("texture")
	_source_art_status["hotkeys"] = texture != null
	_source_art_available = texture != null
	_frame_backdrop.visible = true
	if texture != null:
		_add_art(source, "SourceHotkeysFrame", FRAME_ORIGIN, FRAME_SIZE)
	_draw_labels()
	_draw_footer_labels()
	if _pressed_action.begins_with("slot:"):
		var pressed_slot := int(_pressed_action.trim_prefix("slot:"))
		if pressed_slot >= 0 and pressed_slot < SLOT_COUNT:
			_draw_pressed_effect(pressed_slot)
	elif _pressed_action == "reset":
		_draw_pressed_effect_rect(RESET, "reset")
	elif _pressed_action == "cancel":
		_draw_pressed_effect_rect(CANCEL, "cancel")
	elif _pressed_action == "accept":
		_draw_pressed_effect_rect(ACCEPT, "accept")
	if _editing_slot >= 0 and pending_blink_visible():
		var key_center := _key_center(_editing_slot)
		var pending := ColorRect.new()
		pending.name = "SourceHotkeysPendingEdit"
		pending.position = FRAME_ORIGIN + key_center - Vector2(26.0, 7.0)
		pending.size = Vector2(53.0, 13.0)
		pending.color = SOURCE_WHITE
		pending.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_surface.add_child(pending)
	if not _source_art_available:
		var fallback := _make_label("SourceHotkeysArtFallback", ART_FALLBACK_TEXT, 13, Color("#b6d5cf"))
		fallback.position = FRAME_ORIGIN + Vector2(34.0, 314.0)
		fallback.size = Vector2(260.0, 18.0)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _draw_labels() -> void:
	for index in range(SLOT_COUNT):
		var center := _key_center(index)
		var pressed_offset := Vector2(1.0, 1.0) if _pressed_action == "slot:%d" % index else Vector2.ZERO
		var label := _make_label("SourceHotkeysKeyLabel%d" % index, _system.key_name(int(_draft_bindings[index])), 12, SOURCE_CYAN if index < FIXED_SLOT_COUNT else SOURCE_YELLOW)
		label.position = FRAME_ORIGIN + center - Vector2(26.5, 7.0) + pressed_offset
		if _editing_slot == index:
			label.visible = false
		label.size = Vector2(53.0, 14.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_meta("source_slot", index)
		label.set_meta("source_center", center)
		label.set_meta("source_press_offset", pressed_offset)
		label.set_meta("source_column", 0 if index < 15 else 1)
		key_labels.append(label)
		var title_center := _title_center(index)
		var title := _make_label("SourceHotkeysTitleLabel%d" % index, SOURCE_LABELS[index], 12, SOURCE_WHITE)
		title.position = FRAME_ORIGIN + title_center - Vector2(36.0, 7.0)
		title.size = Vector2(72.0, 14.0)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.set_meta("source_slot", index)
		title_labels.append(title)


func _draw_footer_labels() -> void:
	var entries := [
		["SourceHotkeysResetLabel", "原始設定", Vector2(52.0, 296.0)],
		["SourceHotkeysCancelLabel", "取 消", Vector2(165.0, 296.0)],
		["SourceHotkeysAcceptLabel", "確 定", Vector2(278.0, 296.0)],
	]
	for entry in entries:
		var label := _make_label(str(entry[0]), str(entry[1]), 15, SOURCE_EDGE)
		var center: Vector2 = entry[2]
		var action := str(entry[0]).trim_suffix("Label").trim_prefix("SourceHotkeys").to_lower()
		var pressed_offset := Vector2.ONE if _pressed_action == action else Vector2.ZERO
		label.size = Vector2(72.0, 16.0)
		# Label enforces its font minimum height (15px source text is 23px in
		# Godot's default font), so center after assigning size to preserve the
		# source logical anchor and its one-pixel pressed displacement.
		label.position = FRAME_ORIGIN + center + pressed_offset - label.size / 2.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _draw_pressed_effect(slot: int) -> void:
	_draw_pressed_effect_rect(_cell_rect(slot), "slot:%d" % slot)


func _draw_pressed_effect_rect(rect: Rect2, action: String) -> void:
	var effect := Control.new()
	effect.name = "SourceHotkeysPressed"
	effect.position = FRAME_ORIGIN + rect.position
	effect.size = rect.size
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect.set_meta("source_action", action)
	if action.begins_with("slot:"):
		effect.set_meta("source_slot", int(action.trim_prefix("slot:")))
	effect.set_meta("source_press_offset", Vector2(1.0, 1.0))
	effect.set_meta("source_edge_darken", 16)
	effect.draw.connect(func() -> void:
		effect.draw_rect(Rect2(0, 0, effect.size.x, 1), SOURCE_EDGE)
		effect.draw_rect(Rect2(0, 0, 1, effect.size.y), SOURCE_EDGE)
	)
	_surface.add_child(effect)


func _cell_rect(slot: int) -> Rect2:
	if slot < 15:
		return Rect2(105.0, 25.0 + 16.0 * slot, 56.0, 16.0)
	return Rect2(257.0, 25.0 + 16.0 * (slot - 15), 56.0, 16.0)


func _title_center(slot: int) -> Vector2:
	return Vector2(62.0, 33.0 + 16.0 * slot) if slot < 15 else Vector2(208.0, 33.0 + 16.0 * (slot - 15))


func _key_center(slot: int) -> Vector2:
	return Vector2(132.0, 33.0 + 16.0 * slot) if slot < 15 else Vector2(284.0, 33.0 + 16.0 * (slot - 15))


func _add_art(result: Dictionary, node_name: String, origin: Vector2, logical_size: Vector2) -> TextureRect:
	var texture: Texture2D = result.get("texture")
	if texture == null:
		return null
	var art := TextureRect.new()
	art.name = node_name
	art.position = origin
	art.size = logical_size
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_meta("source_chunk", SOURCE_CHUNK)
	art.set_meta("source_logical_size", logical_size)
	art.set_meta("source_frame", (result.get("frame", {}) as Dictionary).duplicate(true))
	_surface.add_child(art)
	return art


func _make_label(node_name: String, text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(label)
	return label


func _resolve_chunk(chunk: int) -> Dictionary:
	var key := "%s.%s.%d.%d" % [_edition, ARCHIVE, SOURCE_RESOURCE, chunk]
	var frame: Dictionary = {}
	var direct_texture: Texture2D = null
	if _visual_accessor is Dictionary:
		var value: Variant = _dictionary_visual(_visual_accessor as Dictionary, key, chunk)
		if value is Dictionary:
			frame = (value as Dictionary).duplicate(true)
			direct_texture = frame.get("texture")
		elif value is Texture2D:
			direct_texture = value
	elif _visual_accessor is Callable:
		var value: Variant = (_visual_accessor as Callable).call(key)
		if value is Dictionary:
			frame = (value as Dictionary).duplicate(true)
			direct_texture = frame.get("texture")
		elif value is Texture2D:
			direct_texture = value
	elif _visual_accessor is Object:
		var accessor := _visual_accessor as Object
		if accessor.has_method("ui"):
			var value: Variant = accessor.call("ui", _edition, ARCHIVE, SOURCE_RESOURCE, chunk)
			if value is Dictionary:
				frame = (value as Dictionary).duplicate(true)
				direct_texture = frame.get("texture")
			elif value is Texture2D:
				direct_texture = value
		elif accessor.has_method("visual"):
			var value: Variant = accessor.call("visual", _edition, ARCHIVE, SOURCE_RESOURCE, chunk)
			if value is Dictionary:
				frame = (value as Dictionary).duplicate(true)
				direct_texture = frame.get("texture")
			elif value is Texture2D:
				direct_texture = value
		elif accessor.has_method("resolve"):
			var value: Variant = accessor.call("resolve", key)
			if value is Dictionary:
				frame = (value as Dictionary).duplicate(true)
				direct_texture = frame.get("texture")
			elif value is Texture2D:
				direct_texture = value
	if frame.is_empty() and direct_texture == null:
		return {"frame": {}, "texture": null}
	if frame.is_empty():
		frame = _fallback_frame(chunk)
	var texture: Texture2D = direct_texture
	if texture == null and _visual_accessor is Object and (_visual_accessor as Object).has_method("texture"):
		var texture_value: Variant = (_visual_accessor as Object).call("texture", frame)
		if texture_value is Texture2D:
			texture = texture_value
	return {"frame": frame, "texture": texture}


func _dictionary_visual(visuals: Dictionary, key: String, chunk: int) -> Variant:
	var aliases := [key, key.to_lower(), key.to_upper(), key.replace(".", "/"), key.replace(".", "_")]
	if _edition == "MultiverseJourney":
		aliases.append(key.replace("MultiverseJourney", "MJ"))
	for alias in aliases:
		if visuals.has(alias):
			return visuals[alias]
	return null


func _fallback_frame(chunk: int) -> Dictionary:
	return {
		"edition": _edition,
		"archive": ARCHIVE,
		"resource": SOURCE_RESOURCE,
		"chunk": chunk,
		"logical": {"width": FRAME_SIZE.x, "height": FRAME_SIZE.y, "anchor_x": 0.0, "anchor_y": 0.0},
	}


func _canonical_edition(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var normalized := str(value).strip_edges()
	return normalized if normalized in VALID_EDITIONS else ""


func _validate_model(value: Dictionary) -> bool:
	if value.size() != 2 or not value.has("edition") or not value.has("bindings"):
		return false
	if _edition.is_empty() or typeof(value.get("edition")) != TYPE_STRING:
		return false
	var bindings: Variant = value.get("bindings")
	if not bindings is Array or (bindings as Array).size() != SLOT_COUNT:
		return false
	var result: Dictionary = _system.validate_bindings(bindings)
	return bool(result.get("ok", false))


func _deep_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	match typeof(left):
		TYPE_DICTIONARY:
			var ld: Dictionary = left
			var rd: Dictionary = right
			if ld.size() != rd.size():
				return false
			for key in ld:
				if not rd.has(key) or not _deep_equal(ld[key], rd[key]):
					return false
			return true
		TYPE_ARRAY:
			var la: Array = left
			var ra: Array = right
			if la.size() != ra.size():
				return false
			for index in range(la.size()):
				if not _deep_equal(la[index], ra[index]):
					return false
			return true
		_:
			return left == right


func _clear_dynamic_children() -> void:
	for child in _surface.get_children():
		if child == _frame_backdrop or child == _unavailable_backdrop or child == _unavailable:
			continue
		child.free()
