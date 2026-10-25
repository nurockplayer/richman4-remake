extends Control
class_name RichmanSourceMinigamePanel

## Source-shaped S31/S32/S33 presenter.
##
## The panel owns presentation timing and pointer routing only.  The supplied
## worker is an optional deterministic presenter model; simulation and rewards
## remain owned by the game core/controller.  A missing private source image is
## represented by a named fallback surface instead of an invented source
## frame.

signal pointer_requested(position: Vector2, pressed: bool)
signal finish_requested
signal completed

const Art = preload("res://game/ui/source_minigame_art.gd")
const REFERENCE_SIZE := Vector2(640.0, 480.0)
const SOURCE_RESOURCE := 78
const INTRO_FRAME_COUNT := 20
const INTRO_INTERVAL_SECONDS := 0.114
const RESULT_SECONDS := 2.0
const VALID_KINDS := ["balloon", "penguin", "catching"]

var _kind := ""
var _seed := 0
var _input_data: Variant = {}
var _snapshot: Dictionary = {}
var _worker: Variant = null
var _visual_accessor: Variant = null
var _scale_factor := 1.0
var _phase := "closed" # intro, gameplay, result, closed
var _intro_elapsed := 0.0
var _result_elapsed := 0.0
var _paused := false
var _finished_emitted := false
var _source_art_available := false
var _source_frames: Dictionary = {}
var _art: Control
var _ending_elapsed := 0.0
var _ending_duration := 0.0
var _intro_node: TextureRect
var _result_label: Label
var _status_label: Label


func _init() -> void:
	name = "SourceMinigamePanel"
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hide()


## Configure one source mini-game.  `input_data` is copied before it reaches a
## worker so the presentation layer cannot mutate a core-owned dictionary.
func configure(kind: String, seed: int = 0, input_data: Variant = {}, worker: Variant = null) -> bool:
	_kind = _canonical_kind(kind)
	_seed = seed
	_input_data = input_data.duplicate(true) if input_data is Array or input_data is Dictionary else input_data
	_worker = worker
	_snapshot = {}
	_phase = "closed"
	_intro_elapsed = 0.0
	_result_elapsed = 0.0
	_paused = false
	_finished_emitted = false
	_source_frames.clear()
	_source_art_available = false
	if _kind.is_empty():
		_render_fallback("小遊戲資料無法顯示")
		return false
	if _worker != null and _worker is Object and _worker.has_method("configure"):
		_worker.call("configure", _kind, _seed, _input_data)
	if _worker != null and _worker is Object and _worker.has_method("snapshot"):
		_set_snapshot(_worker.call("snapshot"))
	_phase = "intro"
	_render()
	show()
	grab_focus()
	_update_intro_frame(0)
	return true


## Accept a core/worker snapshot without changing the configured identity.
func set_view_model(value: Dictionary) -> void:
	_set_snapshot(value)
	_render_status()


func set_model(worker: Variant) -> void:
	_worker = worker


func model() -> Dictionary:
	return _snapshot.duplicate(true)


func view_model() -> Dictionary:
	return model()


func snapshot() -> Dictionary:
	return model()


func kind() -> String:
	return _kind


func phase() -> String:
	return _phase


func is_open() -> bool:
	return visible and _phase != "closed"


func is_playing() -> bool:
	return is_open() and _phase == "gameplay"


func is_result() -> bool:
	return is_open() and _phase == "result"


func finished() -> bool:
	if _phase == "result":
		return true
	if _worker != null and _worker is Object and _worker.has_method("finished"):
		return bool(_worker.call("finished"))
	var model_value := _snapshot_model()
	return bool(_snapshot.get("finished", false)) or bool(_snapshot.get("done", false)) or bool(model_value.get("finished", false)) or bool(model_value.get("done", false))


func reward() -> Variant:
	if _snapshot.has("reward"):
		return _snapshot.reward
	if _worker != null and _worker is Object and _worker.has_method("reward"):
		return _worker.call("reward")
	return _snapshot_model().get("reward", 0)


func set_scale_factor(value: float) -> bool:
	if not is_finite(value) or value not in [1.0, 2.0]:
		return false
	_scale_factor = value
	scale = Vector2.ONE * _scale_factor
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	return true


func scale_factor() -> float:
	return _scale_factor


func canvas_rect() -> Rect2:
	return Rect2(Vector2.ZERO, REFERENCE_SIZE)


func set_visuals(accessor: Variant) -> void:
	if _visual_accessor == accessor: return
	_visual_accessor = accessor.duplicate(true) if accessor is Dictionary else accessor
	if not _kind.is_empty():
		_render()


func set_visual_accessor(accessor: Variant) -> void:
	set_visuals(accessor)


func source_art_available() -> bool:
	return _source_art_available


func has_source_art() -> bool:
	return source_art_available()


func source_frames() -> Dictionary:
	return {"intro":_source_frames.get("intro",{}),"gameplay":_art.source_frames() if is_instance_valid(_art) else {}}


func source_art_status() -> Dictionary:
	return {"available": _source_art_available, "kind": _kind, "resource": SOURCE_RESOURCE, "frames": source_frames()}


func source_geometry() -> Dictionary:
	return {
		"canvas": REFERENCE_SIZE,
		"scale": _scale_factor,
		"kind": _kind,
		"intro": {"resource": SOURCE_RESOURCE, "frame_count": INTRO_FRAME_COUNT, "interval_ms": 114, "loop": false, "index_zero_transparent": true},
		"result_seconds": RESULT_SECONDS,
	}


func source_hitboxes() -> Dictionary:
	return {"canvas": canvas_rect(), "pointer": canvas_rect()}


## Advance only presentation time.  Controllers may set `drive_worker` to true
## for standalone presentation tests; the normal game path ticks through core.
func tick(delta: float = 0.0, drive_worker: bool = false) -> void:
	if not visible or _paused or _phase == "closed":
		return
	var elapsed := maxf(0.0, delta)
	if _phase == "intro":
		_intro_elapsed += elapsed
		_update_intro_frame(mini(INTRO_FRAME_COUNT - 1, int(floor(_intro_elapsed / INTRO_INTERVAL_SECONDS))))
		if _intro_elapsed + 0.000001 >= INTRO_FRAME_COUNT * INTRO_INTERVAL_SECONDS:
			_phase = "gameplay"
			_update_intro_frame(-1)
			_render_status()
	elif _phase == "gameplay":
		if drive_worker and _worker != null and _worker is Object and _worker.has_method("tick"):
			_worker.call("tick")
			_refresh_worker_snapshot()
		if finished():
			show_result(_snapshot)
	elif _phase == "ending":
		_ending_elapsed += elapsed
		if _ending_elapsed + 0.000001 >= _ending_duration:
			_phase = "result"
			_result_elapsed = 0.0
		_render_status()
	elif _phase == "result":
		_result_elapsed += elapsed
		if _result_elapsed >= RESULT_SECONDS and not _finished_emitted:
			_finished_emitted = true
			finish_requested.emit()


func advance(delta: float = 0.0) -> void:
	tick(delta)


func show_result(value: Dictionary = {}) -> bool:
	if _phase == "closed":
		return false
	if not value.is_empty():
		_set_snapshot(value)
	else:
		_refresh_worker_snapshot()
	_ending_elapsed = 0.0
	_ending_duration = _art.ending_duration() if is_instance_valid(_art) else 0.0
	_phase = "ending" if _ending_duration>0.0 else "result"
	_result_elapsed = 0.0
	_finished_emitted = false
	_update_intro_frame(-1)
	_render_result()
	_render_status()
	return true


func pointer(position: Vector2, pressed: bool) -> bool:
	if not is_playing() or _paused or not canvas_rect().has_point(position):
		return false
	if _worker != null and _worker is Object and _worker.has_method("pointer"):
		_worker.call("pointer", position, pressed)
		_refresh_worker_snapshot()
		if finished():
			show_result(_snapshot)
	pointer_requested.emit(position, pressed)
	return true


func close() -> bool:
	# Source mini-games have no right-click escape while active.  Only the
	# controller can cancel the pending encounter explicitly.
	if _phase in ["intro", "gameplay"]:
		return false
	if _phase == "result":
		_phase = "closed"
		hide()
		completed.emit()
		return true
	return false


func cancel() -> void:
	_phase = "closed"
	_paused = true
	_finished_emitted = true
	hide()


func set_paused(value: bool) -> void:
	_paused = value


func is_paused() -> bool:
	return _paused


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_paused = true
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_paused = false


func _process(delta: float) -> void:
	# The controller owns core ticks.  This process hook keeps intro/result
	# timers alive in a standalone panel scene without touching simulation.
	if not visible:
		return
	tick(delta)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _kind=="catching":
		if pointer(event.position,false): accept_event()
		return
	if not event is InputEventMouseButton: return
	if event.button_index==MOUSE_BUTTON_RIGHT:
		accept_event()
		return
	if event.button_index!=MOUSE_BUTTON_LEFT: return
	if _phase=="result" and _kind=="penguin" and event.pressed and not _finished_emitted and not _paused:
		_finished_emitted=true
		finish_requested.emit()
		accept_event()
		return
	# Godot has already transformed GUI coordinates through every canvas scale.
	if pointer(event.position,event.pressed): accept_event()


func _input(event: InputEvent) -> void:
	# A child overlay must not create an alternate pointer route.  Only events
	# delivered in this panel's canvas are accepted by _gui_input above.
	if not visible or not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()


func _set_snapshot(value: Variant) -> void:
	_snapshot = value.duplicate(true) if value is Dictionary else {}


func _snapshot_model() -> Dictionary:
	var nested: Variant = _snapshot.get("model", _snapshot)
	return nested.duplicate(true) if nested is Dictionary else {}


func _refresh_worker_snapshot() -> void:
	if _worker != null and _worker is Object and _worker.has_method("snapshot"):
		_set_snapshot(_worker.call("snapshot"))


func _render() -> void:
	_clear_children()
	if _kind.is_empty():
		_render_fallback("小遊戲資料無法顯示")
		return
	var surface := ColorRect.new()
	surface.size=REFERENCE_SIZE
	surface.color=Color("#233b57")
	surface.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	_art=Art.new()
	add_child(_art)
	_art.set_visuals(_visual_accessor)
	_art.set_view_model(_snapshot,_phase,_ending_elapsed)
	_source_art_available=_art.available()
	if not _source_art_available:
		_status_label=_add_label("SourceMinigameStatus",_title()+" · 原版影像尚未載入",Rect2(24,20,592,42),20,Color.WHITE)
		_result_label=_add_label("SourceMinigameResult","",Rect2(60,180,520,120),28,Color.WHITE)
		_result_label.hide()
	_intro_node=TextureRect.new()
	_intro_node.name="SourceMinigameIntro"
	_intro_node.size=REFERENCE_SIZE
	_intro_node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_intro_node.stretch_mode=TextureRect.STRETCH_SCALE
	_intro_node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_intro_node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_intro_node)
	_update_intro_frame(mini(19,int(_intro_elapsed/INTRO_INTERVAL_SECONDS)) if _phase=="intro" else -1)
	_render_status()


func _render_fallback(message: String) -> void:
	_clear_children()
	var surface := ColorRect.new()
	surface.name = "SourceMinigameFallback"
	surface.size = REFERENCE_SIZE
	surface.color = Color("#27363b")
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	_add_label("SourceMinigameFallbackMessage", message, Rect2(24, 210, 592, 50), 20, Color("#ffb9a6"))


func _render_status() -> void:
	if is_instance_valid(_art):
		_art.set_view_model(_snapshot,_phase,_ending_elapsed)
		_source_art_available=_art.available()
	if is_instance_valid(_status_label):
		_status_label.visible=not _source_art_available
		_status_label.text=_title()+" · 原版影像尚未載入"
	if is_instance_valid(_result_label): _result_label.visible=_phase=="result" and not _source_art_available


func _render_result() -> void:
	if is_instance_valid(_result_label):
		var value: Variant = reward()
		_result_label.text = "完成！\n獎勵：%s" % str(value)
		_result_label.show()
	if is_instance_valid(_status_label):
		_status_label.text = "結果顯示中…"


func _update_intro_frame(index: int) -> void:
	if not is_instance_valid(_intro_node):
		return
	if index < 0:
		_intro_node.hide()
		return
	_intro_node.show()
	var texture: Variant = _resolve_animation(index)
	if texture is Texture2D:
		_intro_node.texture = texture
		_source_frames["intro"] = {"resource": SOURCE_RESOURCE, "frame": index, "frame_count": INTRO_FRAME_COUNT, "interval_ms": 114, "loop": false, "index_zero_transparent": true, "available": true}
		_source_art_available = is_instance_valid(_art) and _art.available()
	else:
		# An absent texture keeps the transparent intro layer inert and leaves the
		# logical fallback canvas below visible.
		_intro_node.texture = null
		_source_frames["intro"] = {"resource": SOURCE_RESOURCE, "frame": index, "frame_count": INTRO_FRAME_COUNT, "interval_ms": 114, "loop": false, "index_zero_transparent": true, "available": false}


func _resolve_animation(index: int) -> Variant:
	var key := "%s.Panel%d.frame%d" % [_edition(), SOURCE_RESOURCE, index]
	if _visual_accessor is Dictionary:
		var visuals: Dictionary = _visual_accessor
		for candidate in [key, key.to_lower(), key.replace(".", "/"), key.replace(".", "_"), "%s.%d.%d" % [_edition(), SOURCE_RESOURCE, index]]:
			if visuals.has(candidate):
				return visuals[candidate]
		var edition_value: Variant = visuals.get(_edition(), visuals.get(_edition().to_lower(), null))
		if edition_value is Dictionary:
			var archive_value: Variant = edition_value.get("Panel", edition_value)
			var panel_value: Variant = archive_value.get("Panel78", archive_value.get("78", archive_value.get(SOURCE_RESOURCE, null))) if archive_value is Dictionary else null
			if panel_value is Dictionary:
				var frames_value: Variant = panel_value.get("frames", panel_value)
				var frame_value: Variant = frames_value.get("frame%d" % index, frames_value.get(str(index), null)) if frames_value is Dictionary else null
				if frame_value != null:
					return frame_value
	if _visual_accessor is Callable:
		return _visual_accessor.call(key)
	if _visual_accessor is Object:
		var accessor := _visual_accessor as Object
		# SourceVisuals exposes regular UI records for Panel78 frames.  Keep this
		# path first so the same manifest loader serves chunks and FLIC frames.
		if accessor.has_method("ui") and accessor.has_method("texture"):
			var record: Variant = accessor.call("ui", _edition(), "Panel", SOURCE_RESOURCE, index)
			if record is Texture2D:
				return record
			if record is Dictionary:
				var record_texture: Variant = accessor.call("texture", record)
				if record_texture is Texture2D:
					return record_texture
		if accessor.has_method("animation_frame"):
			var value: Variant = accessor.call("animation_frame", _edition(), "Panel", SOURCE_RESOURCE, index)
			if value is Texture2D:
				return value
			if value is Dictionary and accessor.has_method("texture"):
				var animation_texture: Variant = accessor.call("texture", value)
				if animation_texture is Texture2D:
					return animation_texture
		if accessor.has_method("frame"):
			return accessor.call("frame", key)
		if accessor.has_method("animation"):
			return accessor.call("animation", key)
		if accessor.has_method("texture"):
			return accessor.call("texture", {"edition": _edition(), "archive": "Panel", "resource": SOURCE_RESOURCE, "frame": index, "key": key})
	return null


func _edition() -> String:
	var value: Variant = _snapshot.get("edition", _input_data.get("edition", "Game") if _input_data is Dictionary else "Game")
	return "MultiverseJourney" if str(value).to_lower().replace("_", "") in ["multiversejourney", "mj", "journey"] else "Game"


func _canonical_kind(value: String) -> String:
	var normalized := value.to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	if normalized in ["balloon", "balloon_game", "s31", "31"]:
		return "balloon"
	if normalized in ["penguin", "penguin_game", "s32", "32"]:
		return "penguin"
	if normalized in ["catching", "catch", "catch_game", "s33", "33"]:
		return "catching"
	return ""


func _title() -> String:
	return {"balloon": "七彩氣球", "penguin": "企鵝挖寶", "catching": "喜從天降"}.get(_kind, "小遊戲")


func _clear_children() -> void:
	_art = null
	_intro_node = null
	_result_label = null
	_status_label = null
	for child in get_children():
		child.free()


func _add_label(node_name: String, value: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = rect.position
	label.size = rect.size
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
