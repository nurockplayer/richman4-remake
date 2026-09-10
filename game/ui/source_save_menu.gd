class_name SourceSaveMenu
extends Control

## Controller for the source save/load picker.
##
## SourceSavePanel owns source-shaped row presentation and selection.  This
## control owns the small amount of I/O and asynchronous presentation needed
## to connect that picker to MainUI.  It never adopts a snapshot into a live
## game; `load_ready` hands the validated candidate to the host instead.

const SaveSlots = preload("res://game/platform/save_slots.gd")
const SourceSavePanel = preload("res://game/ui/source_save_panel.gd")

const MODE_LOAD := "load"
const MODE_SAVE := "save"
const REFERENCE_SIZE := Vector2(640.0, 480.0)
const LOADING_RESOURCE := {
	"Game": 560,
	"MultiverseJourney": 601,
}
const DEFAULT_GUARD_MESSAGE := "目前有其他操作正在進行，暫時無法使用存檔。"
const SCAN_ERROR_MESSAGE := "讀取存檔清單失敗。"
const READ_ERROR_MESSAGE := "讀取失敗，檔位內容未套用。"
const WRITE_ERROR_MESSAGE := "儲存失敗，原有內容保持不變。"

signal load_ready(snapshot: Dictionary)
signal closed
signal saved(slot_id: int)

## These are intentionally public so MainUI and isolated tests can replace
## storage, inspect the picker, and provide the host's presentation guard.
var storage: Object = SaveSlots.new()
var picker: Control
var loading_overlay: Control
var message_label: Label
var operation_guard: Callable = Callable()

var _mode := MODE_LOAD
var _edition := "Game"
var _visuals: Object = null
var _frozen_save_payload: Dictionary = {}
var _generation := 0
var _busy := false
var _menu_open := false
var _pending_load := false
var _pending_snapshot: Dictionary = {}

var _loading_surface: Control
var _loading_image: TextureRect
var _loading_fallback: Label
var _message_surface: Control
var _message_backdrop: ColorRect
var _built := false


func _init() -> void:
	_build_surface()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 30
	_layout_surface()
	hide()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout_surface()


## Open the source picker and scan all six rows.  The payload is copied once
## at ingress so later host mutations cannot alter a pending SAVE operation.
func open(
		next_mode: String,
		next_edition: String,
		visuals: Object,
		payload: Dictionary = {},
) -> void:
	_build_surface()
	if _busy:
		return
	_mode = MODE_SAVE if next_mode.to_lower().strip_edges() == MODE_SAVE else MODE_LOAD
	_edition = next_edition if next_edition in LOADING_RESOURCE else "Game"
	_visuals = visuals
	_frozen_save_payload = payload.duplicate(true)
	_pending_load = false
	_pending_snapshot = {}
	_generation += 1
	_menu_open = true
	show()
	_picker_show()
	_clear_message()
	_layout_surface()

	var guard := _guard_result()
	if not bool(guard.get("ok", false)):
		_show_message(str(guard.get("message", DEFAULT_GUARD_MESSAGE)))
		return

	var scan_result: Variant = _scan_storage()
	_configure_picker(scan_result)
	if not _scan_ok(scan_result):
		_show_message(_scan_error(scan_result))


func is_busy() -> bool:
	return _busy


## Resolve the host's adoption/legacy decision after load_ready.  A rejected
## candidate leaves the exact picker rows and selection in place; it never
## performs a second disk read.
func resolve_load(accepted: bool) -> void:
	if not _pending_load:
		return
	if accepted:
		_close_menu(true)
		return
	_pending_load = false
	_pending_snapshot = {}
	_busy = false
	_hide_loading()
	_picker_show()
	_menu_open = true
	show()


## Cancel the picker or a queued read.  Incrementing the generation makes any
## continuation after process_frame a no-op before it can perform I/O.
func cancel() -> void:
	if not _menu_open and not _busy and not _pending_load:
		return
	_close_menu(true)


func _build_surface() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	picker = SourceSavePanel.new()
	picker.name = "SourceSavePicker"
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker.mouse_filter = Control.MOUSE_FILTER_STOP
	picker.z_index = 0
	add_child(picker)
	picker.connect("confirmed", Callable(self, "_on_picker_confirmed"))
	picker.connect("cancelled", Callable(self, "_on_picker_cancelled"))

	_message_surface = Control.new()
	_message_surface.name = "SourceSaveMessageSurface"
	_message_surface.size = REFERENCE_SIZE
	_message_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_surface.z_index = 100
	add_child(_message_surface)
	_message_backdrop = ColorRect.new()
	_message_backdrop.name = "SourceSaveMessageBackdrop"
	_message_backdrop.position = Rect2(5.0, 140.0, 116.0, 278.0).position
	_message_backdrop.size = Rect2(5.0, 140.0, 116.0, 278.0).size
	_message_backdrop.color = Color(0.04, 0.08, 0.11, 0.88)
	_message_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_backdrop.z_index = 0
	_message_surface.add_child(_message_backdrop)
	message_label = Label.new()
	message_label.name = "SourceSaveMessage"
	message_label.position = Rect2(8.0, 143.0, 110.0, 272.0).position
	message_label.size = Rect2(8.0, 143.0, 110.0, 272.0).size
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_size_override("font_size", 10)
	message_label.add_theme_color_override("font_color", Color("#ffe5b5"))
	message_label.add_theme_color_override("font_outline_color", Color("#131d26"))
	message_label.add_theme_constant_override("outline_size", 4)
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.z_index = 1
	_message_surface.add_child(message_label)

	loading_overlay = Control.new()
	loading_overlay.name = "SourceSaveLoadingOverlay"
	loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	loading_overlay.z_index = 1000
	add_child(loading_overlay)
	var shade := ColorRect.new()
	shade.name = "SourceSaveLoadingShade"
	shade.color = Color(0.02, 0.04, 0.06, 0.84)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_overlay.add_child(shade)
	_loading_surface = Control.new()
	_loading_surface.name = "SourceSaveLoadingSurface"
	_loading_surface.size = REFERENCE_SIZE
	_loading_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_overlay.add_child(_loading_surface)
	loading_overlay.hide()
	message_label.hide()
	_message_backdrop.hide()


func _layout_surface() -> void:
	if not _built:
		return
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	if picker != null:
		picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if loading_overlay != null:
		loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _message_surface != null:
		var scale_factor := minf(viewport_size.x / REFERENCE_SIZE.x, viewport_size.y / REFERENCE_SIZE.y)
		if scale_factor <= 0.0:
			scale_factor = 1.0
		_message_surface.scale = Vector2.ONE * scale_factor
		_message_surface.position = (viewport_size - REFERENCE_SIZE * scale_factor) * 0.5
		_message_surface.size = REFERENCE_SIZE
	if _loading_surface != null:
		var scale_factor := minf(viewport_size.x / REFERENCE_SIZE.x, viewport_size.y / REFERENCE_SIZE.y)
		if scale_factor <= 0.0:
			scale_factor = 1.0
		_loading_surface.scale = Vector2.ONE * scale_factor
		_loading_surface.position = (viewport_size - REFERENCE_SIZE * scale_factor) * 0.5
		_loading_surface.size = REFERENCE_SIZE
		_layout_loading_frame()


func _layout_loading_frame() -> void:
	if _loading_surface == null:
		return
	var frame_size := _loading_image.size if _loading_image != null else Vector2.ZERO
	if _loading_image != null:
		_loading_image.position = (REFERENCE_SIZE - frame_size) * 0.5
	if _loading_fallback != null:
		_loading_fallback.position = Vector2.ZERO
		_loading_fallback.size = REFERENCE_SIZE


func _picker_show() -> void:
	if picker != null:
		picker.show()


func _configure_picker(scan_result: Variant) -> void:
	if picker == null:
		return
	var frozen_payload := _frozen_save_payload.duplicate(true)
	picker.call("configure", _edition, _mode, scan_result, _visuals, frozen_payload)
	_picker_show()


func _scan_storage() -> Variant:
	if storage == null:
		return {"ok": false, "status": "error", "error": "storage_unavailable"}
	if storage.has_method("scan"):
		return storage.call("scan")
	if storage.has_method("scan_slots"):
		return storage.call("scan_slots")
	return {"ok": false, "status": "error", "error": "scan_unavailable"}


func _scan_ok(result: Variant) -> bool:
	if result is Array:
		return true
	if not result is Dictionary:
		return false
	return bool(result.get("ok", false)) and str(result.get("status", "scanned")) in ["scanned", "ok", ""]


func _scan_error(result: Variant) -> String:
	return SCAN_ERROR_MESSAGE


func _on_picker_cancelled(_slot_id: int, _fingerprint: String, _preview: Dictionary) -> void:
	cancel()


func _on_picker_confirmed(slot_id: int, fingerprint: String, preview: Dictionary) -> void:
	if _busy or not _menu_open or not visible:
		return
	var guard := _guard_result()
	if not bool(guard.get("ok", false)):
		_show_message(str(guard.get("message", DEFAULT_GUARD_MESSAGE)))
		return
	if _mode == MODE_SAVE:
		_save_slot(slot_id, fingerprint)
		return
	if str(preview.get("status", "")) != SaveSlots.STATUS_VALID:
		_show_message("這個檔位目前沒有可讀取的有效存檔。")
		return
	_begin_load(slot_id, fingerprint)


func _save_slot(slot_id: int, fingerprint: String) -> void:
	_busy = true
	var result := _storage_write(slot_id, _frozen_save_payload.duplicate(true), fingerprint)
	_busy = false
	if _write_ok(result):
		saved.emit(slot_id)
		_close_menu(true)
		return
	var error_text := _write_error(result)
	_show_message(error_text)
	_refresh_after_error(error_text)


func _begin_load(slot_id: int, fingerprint: String) -> void:
	_busy = true
	_pending_load = false
	_pending_snapshot = {}
	var generation := _generation
	_show_loading()
	if not is_inside_tree():
		_abort_load(generation, "讀取畫面尚未就緒。")
		return
	await get_tree().process_frame
	if not _continue_allowed(generation):
		_abort_load(generation, _guard_message())
		return
	await get_tree().process_frame
	if not _continue_allowed(generation):
		_abort_load(generation, _guard_message())
		return
	var result := _storage_read(slot_id, fingerprint)
	if generation != _generation or not visible:
		return
	_busy = false
	_hide_loading()
	if not _read_ok(result):
		var error_text := _read_error(result)
		_show_message(error_text)
		_refresh_after_error(error_text)
		return
	var snapshot: Variant = result.get("snapshot", null) if result is Dictionary else null
	if not snapshot is Dictionary:
		var error_text := READ_ERROR_MESSAGE
		_show_message(error_text)
		_refresh_after_error(error_text)
		return
	# Keep the validated candidate in memory while the host decides whether a
	# legacy/adoption modal should proceed.  The disk is never read again.
	_pending_snapshot = snapshot.duplicate(true)
	_pending_load = true
	_busy = true
	load_ready.emit(_pending_snapshot.duplicate(true))


func _abort_load(generation: int, reason: String) -> void:
	if generation != _generation or not visible:
		return
	_busy = false
	_pending_load = false
	_pending_snapshot = {}
	_hide_loading()
	_show_message(reason if not reason.is_empty() else DEFAULT_GUARD_MESSAGE)


func _continue_allowed(generation: int) -> bool:
	return generation == _generation and visible and _guard_result().get("ok", false)


func _storage_read(slot_id: int, fingerprint: String) -> Dictionary:
	if storage == null or not storage.has_method("read"):
		return {"ok": false, "status": "error", "error": "read_unavailable"}
	var result: Variant = storage.call("read", slot_id, fingerprint)
	return result if result is Dictionary else {"ok": false, "status": "error", "error": "invalid_read_result"}


func _storage_write(slot_id: int, payload: Dictionary, fingerprint: String) -> Dictionary:
	if storage == null or not storage.has_method("write"):
		return {"ok": false, "status": "error", "error": "write_unavailable"}
	var result: Variant = storage.call("write", slot_id, payload, fingerprint)
	return result if result is Dictionary else {"ok": false, "status": "error", "error": "invalid_write_result"}


func _read_ok(result: Variant) -> bool:
	return result is Dictionary and bool(result.get("ok", false)) and str(result.get("status", "")) == SaveSlots.STATUS_VALID


func _write_ok(result: Variant) -> bool:
	return result is Dictionary and bool(result.get("ok", false)) and str(result.get("status", "")) == SaveSlots.STATUS_WRITTEN


func _read_error(result: Variant) -> String:
	if result is Dictionary:
		match str(result.get("status", "")):
			SaveSlots.STATUS_STALE:
				return "檔位內容已變更，請重新選取。"
			SaveSlots.STATUS_UNREADABLE:
				return "檔位無法讀取，請重新選取。"
			SaveSlots.STATUS_CORRUPT:
				return "檔位存檔損毀，請重新選取。"
			SaveSlots.STATUS_INVALID:
				return "檔位存檔無效，請重新選取。"
			SaveSlots.STATUS_EMPTY:
				return "檔位目前是空白欄位。"
	return READ_ERROR_MESSAGE


func _write_error(result: Variant) -> String:
	if result is Dictionary:
		match str(result.get("status", "")):
			SaveSlots.STATUS_STALE:
				return "檔位內容已變更，請重新選取。"
			SaveSlots.STATUS_READONLY:
				return "原有存檔為唯讀，請選擇 1 至 5 號檔位。"
			SaveSlots.STATUS_INVALID:
				return "目前棋局未通過存檔驗證，原有內容保持不變。"
	return WRITE_ERROR_MESSAGE


func _refresh_after_error(previous_message: String) -> void:
	var guard := _guard_result()
	if not bool(guard.get("ok", false)):
		_show_message(previous_message + "\n" + str(guard.get("message", DEFAULT_GUARD_MESSAGE)))
		return
	var scan_result: Variant = _scan_storage()
	_configure_picker(scan_result)
	_picker_show()
	_menu_open = true
	show()
	if not _scan_ok(scan_result):
		_show_message(previous_message + "\n" + _scan_error(scan_result))
	else:
		_show_message(previous_message)


func _show_loading() -> void:
	_render_loading_visual()
	if loading_overlay != null:
		loading_overlay.show()
		loading_overlay.move_to_front()
	_layout_surface()


func _hide_loading() -> void:
	if loading_overlay != null:
		loading_overlay.hide()


func _render_loading_visual() -> void:
	if _loading_surface == null:
		return
	for child in _loading_surface.get_children():
		child.queue_free()
	_loading_image = null
	_loading_fallback = null
	var resource := int(LOADING_RESOURCE.get(_edition, LOADING_RESOURCE["Game"]))
	var frame: Dictionary = {}
	if _visuals != null and _visuals.has_method("ui"):
		var value: Variant = _visuals.call("ui", _edition, "Data", resource, 0)
		if value is Dictionary:
			frame = value
	var frame_size := _logical_frame_size(frame)
	if _visuals != null and not frame.is_empty() and frame_size.x > 0.0 and frame_size.y > 0.0 and _visuals.has_method("texture"):
		var texture_value: Variant = _visuals.call("texture", frame)
		if texture_value is Texture2D:
			_loading_image = TextureRect.new()
			_loading_image.name = "SourceLoadingImage"
			_loading_image.texture = texture_value
			_loading_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_loading_image.custom_minimum_size = Vector2.ZERO
			_loading_image.size = frame_size
			_loading_image.stretch_mode = TextureRect.STRETCH_KEEP
			_loading_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_loading_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_loading_surface.add_child(_loading_image)
	if _loading_image == null:
		_loading_fallback = Label.new()
		_loading_fallback.name = "SourceLoadingFallback"
		_loading_fallback.text = "讀取中"
		_loading_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loading_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_loading_fallback.add_theme_font_size_override("font_size", 24)
		_loading_fallback.add_theme_color_override("font_color", Color("#f1d28a"))
		_loading_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_loading_surface.add_child(_loading_fallback)
	_layout_loading_frame()


func _logical_frame_size(frame: Dictionary) -> Vector2:
	var logical: Variant = frame.get("logical", {})
	if not logical is Dictionary:
		return Vector2.ZERO
	var width := float(logical.get("width", 0))
	var height := float(logical.get("height", 0))
	if not is_finite(width) or not is_finite(height) or width <= 0.0 or height <= 0.0:
		return Vector2.ZERO
	return Vector2(width, height)


func _close_menu(emit_closed: bool) -> void:
	_generation += 1
	_busy = false
	_pending_load = false
	_pending_snapshot = {}
	_hide_loading()
	if picker != null:
		picker.hide()
	_menu_open = false
	message_label.hide()
	if _message_backdrop != null:
		_message_backdrop.hide()
	hide()
	if emit_closed:
		closed.emit()


func _show_message(text: String) -> void:
	if message_label == null:
		return
	message_label.text = text
	message_label.show()
	if _message_backdrop != null:
		_message_backdrop.show()
	_layout_surface()


func _clear_message() -> void:
	if message_label != null:
		message_label.text = ""
		message_label.hide()
	if _message_backdrop != null:
		_message_backdrop.hide()


func _guard_result() -> Dictionary:
	if not operation_guard.is_valid():
		return {"ok": true, "message": ""}
	var value: Variant = operation_guard.call()
	if value is Dictionary:
		return {
			"ok": bool(value.get("ok", false)),
			"message": str(value.get("message", DEFAULT_GUARD_MESSAGE)),
		}
	return {"ok": bool(value), "message": DEFAULT_GUARD_MESSAGE}


func _guard_message() -> String:
	var guard := _guard_result()
	return str(guard.get("message", DEFAULT_GUARD_MESSAGE)) if not bool(guard.get("ok", false)) else ""
