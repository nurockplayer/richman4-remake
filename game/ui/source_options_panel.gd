extends Control
class_name RichmanSourceOptionsPanel

## Pure source-shaped general-options presenter for Issue #141 / S35.
##
## The host supplies a detached six-field settings snapshot and an optional
## OriginalVisuals-like resolver.  This control owns no GameState, settings
## persistence, audio, RNG, child window or platform command.  It only mutates
## a local draft and emits explicit intents for the host to handle.

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const FRAME_ORIGIN := Vector2(147.0, 59.0)
const FRAME_SIZE := Vector2(347.0, 363.0)
const ARCHIVE := "Data"
const SOURCE_RESOURCE := 3
const VALID_EDITIONS := ["Game", "MultiverseJourney"]
const VALID_MODES := ["title", "game"]
const SETTINGS_KEYS := ["speed", "animation", "music_level", "sound_level", "autosave", "view"]

const FIELD_LABELS := [
	"遊戲速度", "動畫過程", "音 樂", "音 效", "自動存檔",
	"樂 曲", "視 窗", "日、月曆", "縮小地圖", "組合畫面",
]
const FIELD_POSITIONS := [
	{"name": "speed", "x": 14.0, "y": 25.0, "mode": 5},
	{"name": "animation", "x": 14.0, "y": 58.0, "mode": 5},
	{"name": "music_level", "x": 14.0, "y": 90.0, "mode": 5},
	{"name": "sound_level", "x": 14.0, "y": 122.0, "mode": 5},
	{"name": "autosave", "x": 14.0, "y": 155.0, "mode": 5},
	{"name": "music_track", "x": 49.0, "y": 202.0, "mode": 2},
	{"name": "view", "x": 209.0, "y": 202.0, "mode": 2},
	{"name": "view_calendar", "x": 286.0, "y": 226.0, "mode": 2},
	{"name": "view_small_map", "x": 286.0, "y": 258.0, "mode": 2},
	{"name": "view_combined", "x": 286.0, "y": 290.0, "mode": 2},
]
const TRACK_LABELS := [
	"1.星際總動員", "2.重回侏儸紀", "3.夢幻伊甸園", "4.打拼為將來",
	"5.椰林風情畫", "6.浪漫月世界", "7.熱情的夏夜", "8.漫步星空下",
]
const TITLE_COMMANDS := ["date", "hotkeys", "help"]
const TITLE_COMMAND_LABELS := ["日期更改", "熱鍵設定", "遊戲說明"]
const GAME_COMMANDS := ["restart", "surrender", "quit"]
const GAME_COMMAND_LABELS := ["重新遊戲", "認輸投降", "結束遊戲"]

# All rectangles are local to the 347x363 source frame.  Right and bottom
# edges are exclusive, matching the original integer comparisons.
const HITBOXES := {
	"speed": Rect2(81.0, 17.0, 47.0, 16.0),
	"music_level": Rect2(89.0, 81.0, 63.0, 16.0),
	"sound_level": Rect2(89.0, 113.0, 63.0, 16.0),
	"animation": Rect2(98.0, 50.0, 15.0, 15.0),
	"music_toggle": Rect2(66.0, 82.0, 15.0, 15.0),
	"sound_toggle": Rect2(66.0, 114.0, 15.0, 15.0),
	"autosave": Rect2(98.0, 146.0, 15.0, 15.0),
	"view_calendar": Rect2(217.0, 214.0, 107.0, 22.0),
	"view_map": Rect2(217.0, 246.0, 107.0, 22.0),
	"view_combined": Rect2(217.0, 278.0, 107.0, 22.0),
	"modecmd0": Rect2(227.0, 14.0, 100.0, 35.0),
	"modecmd1": Rect2(227.0, 68.0, 100.0, 35.0),
	"modecmd2": Rect2(227.0, 119.0, 100.0, 35.0),
	"track": Rect2(18.0, 226.0, 159.0, 119.0),
	"cancel": Rect2(194.0, 314.0, 62.0, 30.0),
	"accept": Rect2(266.0, 314.0, 62.0, 30.0),
}

const CHUNKS := {
	"frame": 0,
	"inner": 1,
	"selection": 2,
	"cancel": 3,
	"accept": 4,
	"level_marker": 5,
	"command_pressed": 6,
	"cancel_pressed": 7,
	"accept_pressed": 8,
	"radio": 9,
	"title_commands": 10,
	"game_commands": 11,
	"marker_on": 12,
	"marker_off": 13,
	"cancel_alt": 14,
	"accept_alt": 15,
}
const CHUNK_ROLES := [
	"frame", "inner", "selection", "cancel", "accept", "level_marker",
	"command_pressed", "cancel_pressed", "accept_pressed", "radio",
	"title_commands", "game_commands", "marker_on", "marker_off",
	"cancel_alt", "accept_alt",
]
const FALLBACK_LOGICAL := {
	0: Vector2(347.0, 363.0),
	1: Vector2(328.0, 336.0),
	2: Vector2(199.0, 220.0),
	3: Vector2(62.0, 30.0),
	4: Vector2(62.0, 30.0),
	5: Vector2(15.0, 16.0),
	6: Vector2(101.0, 36.0),
	7: Vector2(16.0, 16.0),
	8: Vector2(16.0, 16.0),
	9: Vector2(15.0, 15.0),
	10: Vector2(177.0, 174.0),
	11: Vector2(177.0, 174.0),
	12: Vector2(17.0, 11.0),
	13: Vector2(17.0, 11.0),
	14: Vector2(56.0, 31.0),
	15: Vector2(80.0, 41.0),
}

const SOURCE_TEXT := Color("#101010")
const UNAVAILABLE_TEXT := "選項資料無法顯示"
const ART_FALLBACK_TEXT := "來源畫面素材未載入"

signal accepted(settings: Dictionary)
signal cancelled
signal command_requested(command: String)
signal preview_requested(track: int)

# These arrays are public inspection handles for the host and isolated visual
# tests.  They contain only nodes owned by this presenter and are rebuilt on a
# valid model render.
var field_labels: Array = []
var track_labels: Array = []
var command_labels: Array = []

var _model: Dictionary = {}
var _committed_settings: Dictionary = {}
var _draft_settings: Dictionary = {}
var _visual_accessor: Variant = null
var _model_valid := false
var _edition := ""
var _mode := ""
var _is_open := false
var _closed := false
var _suspended := false
var _pressed_action := ""
var _source_art_available := false
var _source_art_status: Dictionary = {}
var _source_frames: Dictionary = {}
var _current_track := -1

var _surface: Control
var _frame_backdrop: ColorRect
var _unavailable_backdrop: ColorRect
var _unavailable: Label
var _built := false


func _init() -> void:
	name = "SourceOptionsPanel"
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build()


func _ready() -> void:
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE


## Replace the source snapshot.  Input and output are deeply detached.  A
## content-identical refresh while the session is open keeps its unsaved
## draft; after cancel/accept, the same model starts a fresh draft session.
func set_view_model(model: Dictionary) -> bool:
	var incoming := model.duplicate(true)
	var same_model := _model_valid and _deep_equal(_model, incoming)
	var was_open := _is_open and not _closed
	_model = incoming
	_edition = _canonical_edition(_model.get("edition", null))
	_mode = str(_model.get("mode", ""))
	_model_valid = _validate_model(_model)
	_pressed_action = ""
	if not _model_valid:
		_committed_settings = {}
		_draft_settings = {}
		_is_open = false
		_closed = false
		_render()
		show()
		return false

	if not same_model or not was_open:
		_committed_settings = _settings_copy(_model["settings"])
		_draft_settings = _committed_settings.duplicate(true)
	_is_open = true
	_closed = false
	_suspended = false
	_render()
	show()
	return true


## Install a host-provided resolver.  Dictionaries are copied; objects and
## callables are borrowed and are never asked to perform IO by this presenter.
func set_visual_accessor(accessor: Variant) -> void:
	if accessor is Dictionary:
		_visual_accessor = (accessor as Dictionary).duplicate(true)
	else:
		_visual_accessor = accessor
	_render()


## Compatibility alias used by the existing source presenters.
func set_visuals(accessor: Variant) -> void:
	set_visual_accessor(accessor)


## Report the track currently playing in the host audio layer.  The default
## stays unknown so the presenter never invents a selection from a preview.
## Restore an unpersisted host draft after a failed write without changing
## the opening snapshot that controls track-preview permission.
func restore_draft(settings_value: Dictionary) -> bool:
	var candidate := _model.duplicate(true)
	candidate["settings"] = settings_value.duplicate(true)
	if not _model_valid or not _validate_model(candidate):
		return false
	_draft_settings = _settings_copy(settings_value)
	_closed = false
	_is_open = true
	_suspended = false
	_pressed_action = ""
	_render()
	show()
	return true


func set_current_track(index: int) -> void:
	_current_track = index if index >= -1 and index < TRACK_LABELS.size() else -1
	_render()


func view_model() -> Dictionary:
	return _model.duplicate(true)


func model() -> Dictionary:
	return view_model()


func is_model_valid() -> bool:
	return _model_valid


func is_open() -> bool:
	return _is_open and _model_valid and visible


func draft_settings() -> Dictionary:
	return _draft_settings.duplicate(true)


func committed_settings() -> Dictionary:
	return _committed_settings.duplicate(true)


func settings() -> Dictionary:
	return draft_settings()


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
	if chunk < 0 or chunk >= CHUNK_ROLES.size():
		return {}
	var role: String = CHUNK_ROLES[chunk]
	var frame: Variant = _source_frames.get(role, {})
	return frame.duplicate(true) if frame is Dictionary else {}


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
		"mode": _mode,
		"hitboxes": source_hitboxes(),
		"fields": FIELD_POSITIONS.duplicate(true),
		"tracks": TRACK_LABELS.duplicate(),
		"commands": TITLE_COMMANDS.duplicate() if _mode == "title" else GAME_COMMANDS.duplicate(),
	}


func get_source_geometry() -> Dictionary:
	return source_geometry()


## Parent calls this while a child source window or confirmation owns input.
## The local draft remains intact while suspended.
func suspend_input(suspended: bool) -> void:
	_suspended = suspended
	if suspended:
		_pressed_action = ""
		_render()


func is_input_suspended() -> bool:
	return _suspended


## Source right-button release and this explicit method share one cancellation
## boundary.  There is intentionally no Escape/key-navigation path here.
func close_options() -> bool:
	return _cancel()


func close() -> bool:
	return close_options()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	# Handle the event before a signal can synchronously free this panel.
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	accept_event()
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		if not mouse.pressed and not _suspended:
			_cancel()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT or _suspended:
		return
	var local := mouse.position - FRAME_ORIGIN
	if mouse.pressed:
		_handle_left_down(local)
	else:
		_handle_left_up(local)


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_RIGHT or mouse.pressed:
		return
	# _input catches a source right release outside the panel bounds.  Mark the
	# viewport before cancellation because the signal receiver may free us.
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	if _suspended:
		return
	_cancel()


func _handle_left_down(local: Vector2) -> void:
	if not _model_valid or not _is_open:
		return
	# A second down before an up is not a second source action.
	if not _pressed_action.is_empty():
		return

	if _hitbox("speed").has_point(local):
		var speed := clampi(floori((local.x - 81.0) / 16.0), 0, 2)
		_draft_settings["speed"] = speed
		_pressed_action = "setting"
		_render()
		return
	if _hitbox("music_level").has_point(local):
		var music := clampi(floori((local.x - 89.0) / 16.0) + 1, 1, 4)
		_draft_settings["music_level"] = music
		_pressed_action = "setting"
		_render()
		return
	if _hitbox("sound_level").has_point(local):
		var sound := clampi(floori((local.x - 89.0) / 16.0) + 1, 1, 4)
		_draft_settings["sound_level"] = sound
		_pressed_action = "setting"
		_render()
		return
	if _hitbox("animation").has_point(local):
		_draft_settings["animation"] = not bool(_draft_settings.get("animation", false))
		_pressed_action = "setting"
		_render()
		return
	if _hitbox("music_toggle").has_point(local):
		_draft_settings["music_level"] = 4 if int(_draft_settings.get("music_level", 0)) == 0 else 0
		_pressed_action = "setting"
		_render()
		return
	if _hitbox("sound_toggle").has_point(local):
		_draft_settings["sound_level"] = 4 if int(_draft_settings.get("sound_level", 0)) == 0 else 0
		_pressed_action = "setting"
		_render()
		return
	if _hitbox("autosave").has_point(local):
		_draft_settings["autosave"] = not bool(_draft_settings.get("autosave", false))
		_pressed_action = "setting"
		_render()
		return

	for view_name in ["view_calendar", "view_map", "view_combined"]:
		if _hitbox(view_name).has_point(local):
			_draft_settings["view"] = ["view_calendar", "view_map", "view_combined"].find(view_name)
			_pressed_action = "setting"
			_render()
			return

	if _hitbox("track").has_point(local):
		var track := clampi(floori((local.y - 226.0) / 15.0), 0, 7)
		# The source checks the committed music byte, not the mutable scratch
		# value.  Mark the action handled before the callback can free the panel.
		if int(_committed_settings.get("music_level", 0)) > 0:
			_pressed_action = ""
			preview_requested.emit(track)
		return

	if _hitbox("cancel").has_point(local):
		_pressed_action = "cancel"
		_render()
		return
	if _hitbox("accept").has_point(local):
		_pressed_action = "accept"
		_render()
		return
	for command_index in range(3):
		if _hitbox("modecmd%d" % command_index).has_point(local):
			_pressed_action = "command:%d" % command_index
			_render()
			return


func _handle_left_up(_local: Vector2) -> void:
	if _pressed_action.is_empty():
		return
	var action := _pressed_action
	_pressed_action = ""
	# Release position is deliberately ignored.  The source dispatches the
	# remembered press row and never re-hits the release coordinate.
	match action:
		"setting":
			_render()
		"cancel":
			_cancel()
		"accept":
			_accept()
		_:
			if action.begins_with("command:"):
				var command_index := int(action.trim_prefix("command:"))
				var commands: Array = TITLE_COMMANDS if _mode == "title" else GAME_COMMANDS
				if command_index >= 0 and command_index < commands.size():
					_render()
					# No code after this signal may dereference the presenter.
					command_requested.emit(str(commands[command_index]))


func _accept() -> bool:
	if _closed:
		return false
	var result := _draft_settings.duplicate(true)
	_committed_settings = result.duplicate(true)
	_draft_settings = result.duplicate(true)
	if _model_valid and _model.get("settings") is Dictionary:
		_model["settings"] = result.duplicate(true)
	_closed = true
	_is_open = false
	_suspended = false
	_pressed_action = ""
	hide()
	# Emit only after every state/lifecycle flag is final.
	accepted.emit(result)
	return true


func _cancel() -> bool:
	if _closed:
		return false
	_closed = true
	_is_open = false
	_pressed_action = ""
	_draft_settings = _committed_settings.duplicate(true)
	_suspended = false
	hide()
	# Invalid models remain closable, but can never emit accepted.
	cancelled.emit()
	return true


func _hitbox(name_value: String) -> Rect2:
	return HITBOXES.get(name_value, Rect2())


func _build() -> void:
	if _built:
		return
	_built = true
	_surface = Control.new()
	_surface.name = "SourceOptionsSurface"
	_surface.position = Vector2.ZERO
	_surface.size = REFERENCE_SIZE
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)

	_frame_backdrop = ColorRect.new()
	_frame_backdrop.name = "SourceOptionsFrameBackdrop"
	_frame_backdrop.position = FRAME_ORIGIN
	_frame_backdrop.size = FRAME_SIZE
	_frame_backdrop.color = Color.BLACK
	_frame_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_backdrop.visible = false
	_surface.add_child(_frame_backdrop)

	_unavailable_backdrop = ColorRect.new()
	_unavailable_backdrop.name = "SourceOptionsUnavailableBackdrop"
	_unavailable_backdrop.position = FRAME_ORIGIN
	_unavailable_backdrop.size = FRAME_SIZE
	_unavailable_backdrop.color = Color("#0d1524")
	_unavailable_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unavailable_backdrop.visible = false
	_surface.add_child(_unavailable_backdrop)

	_unavailable = Label.new()
	_unavailable.name = "SourceOptionsUnavailable"
	_unavailable.text = UNAVAILABLE_TEXT
	_unavailable.position = FRAME_ORIGIN + FRAME_SIZE / 2.0 - Vector2(165.0, 16.0)
	_unavailable.size = Vector2(330.0, 32.0)
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
	field_labels.clear()
	track_labels.clear()
	command_labels.clear()
	if not _model_valid:
		_unavailable_backdrop.visible = true
		_unavailable.visible = true
		return
	_draw_options()


func _clear_dynamic_children() -> void:
	for child in _surface.get_children():
		if child == _frame_backdrop or child == _unavailable_backdrop or child == _unavailable:
			continue
		child.free()


func _draw_options() -> void:
	var resolved: Dictionary = {}
	var all_available := true
	for role in CHUNK_ROLES:
		var chunk: int = int(CHUNKS[role])
		var result := _resolve_chunk(chunk)
		resolved[role] = result
		var frame: Dictionary = result.get("frame", {})
		_source_frames[role] = frame.duplicate(true)
		var texture: Texture2D = result.get("texture")
		var available := texture != null
		_source_art_status[role] = available
		all_available = all_available and available
	_source_art_available = all_available
	_frame_backdrop.visible = true
	_add_art(resolved["frame"], "SourceOptionsFrame", Vector2.ZERO, FRAME_SIZE, 0)

	# Data3 chunks 10/11 are the source title/game command plates.  Their
	# logical metadata is used only for the size; command hitboxes remain the
	# contract geometry above.
	var command_role := "title_commands" if _mode == "title" else "game_commands"
	var command_frame: Dictionary = resolved[command_role]
	_add_art(command_frame, "SourceOptionsCommandPlate", Vector2(168.0, 2.0), _logical_for(command_frame, Vector2(177.0, 174.0)), int(CHUNKS[command_role]))

	_draw_field_labels()
	_draw_markers(resolved)
	_draw_commands(resolved)
	_draw_tracks_and_views()

	if not _source_art_available:
		_make_centered_label(
			"SourceOptionsArtFallback",
			ART_FALLBACK_TEXT,
			Vector2(173.0, 351.0),
			Vector2(260.0, 18.0),
			13,
			Color("#b6d5cf"),
		)


func _draw_field_labels() -> void:
	for index in range(FIELD_LABELS.size()):
		var record: Dictionary = FIELD_POSITIONS[index]
		var label_text: String = FIELD_LABELS[index]
		var label: Label
		if int(record["mode"]) == 5:
			label = _make_left_center_label(
				"SourceOptionsFieldLabel%d" % index,
				label_text,
				Vector2(float(record["x"]), float(record["y"])),
				Vector2(88.0, 22.0),
				15,
			)
		else:
			label = _make_centered_label(
				"SourceOptionsFieldLabel%d" % index,
				label_text,
				Vector2(float(record["x"]), float(record["y"])),
				Vector2(120.0, 22.0),
				15,
			)
		label.set_meta("source_index", index)
		label.set_meta("source_field", str(record["name"]))
		label.set_meta("source_mode", int(record["mode"]))
		label.set_meta("source_position", Vector2(float(record["x"]), float(record["y"])))
		field_labels.append(label)


func _draw_markers(resolved: Dictionary) -> void:
	var marker_frame: Dictionary = resolved["level_marker"]
	var radio_frame: Dictionary = resolved["radio"]
	var speed := clampi(int(_draft_settings.get("speed", 0)), 0, 2)
	for index in range(speed + 1):
		_add_art(marker_frame, "SourceOptionsSpeedMarker%d" % index, Vector2(81.0 + 16.0 * index, 17.0), Vector2(15.0, 16.0), int(CHUNKS["level_marker"]))
	for index in range(clampi(int(_draft_settings.get("music_level", 0)), 0, 4)):
		_add_art(marker_frame, "SourceOptionsMusicLevelMarker%d" % index, Vector2(89.0 + 16.0 * index, 81.0), Vector2(15.0, 16.0), int(CHUNKS["level_marker"]))
	for index in range(clampi(int(_draft_settings.get("sound_level", 0)), 0, 4)):
		_add_art(marker_frame, "SourceOptionsSoundLevelMarker%d" % index, Vector2(89.0 + 16.0 * index, 113.0), Vector2(15.0, 16.0), int(CHUNKS["level_marker"]))
	if bool(_draft_settings.get("animation", false)):
		_add_art(radio_frame, "SourceOptionsAnimationMarker", Vector2(98.0, 50.0), Vector2(15.0, 15.0), int(CHUNKS["radio"]))
	if int(_draft_settings.get("music_level", 0)) > 0:
		_add_art(radio_frame, "SourceOptionsMusicToggleMarker", Vector2(66.0, 82.0), Vector2(15.0, 15.0), int(CHUNKS["radio"]))
	if int(_draft_settings.get("sound_level", 0)) > 0:
		_add_art(radio_frame, "SourceOptionsSoundToggleMarker", Vector2(66.0, 114.0), Vector2(15.0, 15.0), int(CHUNKS["radio"]))
	if bool(_draft_settings.get("autosave", false)):
		_add_art(radio_frame, "SourceOptionsAutosaveMarker", Vector2(98.0, 146.0), Vector2(15.0, 15.0), int(CHUNKS["radio"]))
	var view := clampi(int(_draft_settings.get("view", 0)), 0, 2)
	_add_art(radio_frame, "SourceOptionsViewMarker%d" % view, Vector2(218.0, 215.0 + 32.0 * view), Vector2(15.0, 15.0), int(CHUNKS["radio"]))


func _draw_commands(resolved: Dictionary) -> void:
	var labels: Array = TITLE_COMMAND_LABELS if _mode == "title" else GAME_COMMAND_LABELS
	var label_centers := [Vector2(276.0, 33.0), Vector2(276.0, 87.0), Vector2(276.0, 138.0)]
	for index in range(3):
		var rect: Rect2 = _hitbox("modecmd%d" % index)
		if _pressed_action == "command:%d" % index:
			_add_art(
				resolved["command_pressed"],
				"SourceOptionsCommand%dPressed" % index,
				rect.position,
				_logical_for(resolved["command_pressed"], Vector2(101.0, 36.0)),
				int(CHUNKS["command_pressed"]),
			)
		var label := _make_centered_label(
			"SourceOptionsCommand%d" % index,
			str(labels[index]),
			label_centers[index],
			rect.size,
			20,
		)
		label.set_meta("source_command", (TITLE_COMMANDS if _mode == "title" else GAME_COMMANDS)[index])
		label.set_meta("source_hitbox", rect)
		command_labels.append(label)

	var cancel_rect: Rect2 = _hitbox("cancel")
	var accept_rect: Rect2 = _hitbox("accept")
	if _pressed_action == "cancel":
		_add_art(resolved["cancel"], "SourceOptionsCancelPressed", cancel_rect.position, cancel_rect.size, int(CHUNKS["cancel"]))
	if _pressed_action == "accept":
		_add_art(resolved["accept"], "SourceOptionsAcceptPressed", accept_rect.position, accept_rect.size, int(CHUNKS["accept"]))
	_make_centered_label("SourceOptionsCancelLabel", "取 消", Vector2(224.0, 328.0), Vector2(62.0, 22.0), 20)
	_make_centered_label("SourceOptionsAcceptLabel", "確 定", Vector2(296.0, 328.0), Vector2(62.0, 22.0), 20)


func _draw_tracks_and_views() -> void:
	var track_rect := _hitbox("track")
	if _current_track >= 0 and _current_track < TRACK_LABELS.size():
		var highlight := ColorRect.new()
		highlight.name = "SourceOptionsTrackHighlight"
		highlight.position = FRAME_ORIGIN + Vector2(18.0, 226.0 + 15.0 * _current_track)
		highlight.size = Vector2(159.0, 14.0)
		highlight.color = Color("#ff0000")
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_surface.add_child(highlight)
	for index in range(TRACK_LABELS.size()):
		var track_label := _make_left_center_label(
			"SourceOptionsTrackLabel%d" % index,
			TRACK_LABELS[index],
			Vector2(26.0, 233.0 + 15.0 * index),
			Vector2(151.0, 14.0),
			12,
		)
		track_label.add_theme_color_override("font_color", Color("#f0f0f0"))
		track_label.set_meta("source_track", index)
		track_label.set_meta("source_hitbox", track_rect)
		track_labels.append(track_label)


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


func _make_label(node_name: String, text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", SOURCE_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(label)
	return label


func _make_left_center_label(node_name: String, text_value: String, local_anchor: Vector2, logical_size: Vector2, font_size: int) -> Label:
	var label := _make_label(node_name, text_value, font_size)
	var actual_height := maxf(logical_size.y, label.get_minimum_size().y)
	label.position = FRAME_ORIGIN + Vector2(local_anchor.x, local_anchor.y - actual_height / 2.0)
	label.size = Vector2(logical_size.x, actual_height)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _make_centered_label(
		node_name: String,
		text_value: String,
		local_center: Vector2,
		logical_size: Vector2,
		font_size: int,
		font_color: Color = SOURCE_TEXT,
) -> Label:
	var label := _make_label(node_name, text_value, font_size)
	label.add_theme_color_override("font_color", font_color)
	var actual_height := maxf(logical_size.y, label.get_minimum_size().y)
	var center := FRAME_ORIGIN + local_center
	label.position = Vector2(center.x - logical_size.x / 2.0, center.y - actual_height / 2.0)
	label.size = Vector2(logical_size.x, actual_height)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


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
		"%s.%s.chunk%d" % [_edition, ARCHIVE, chunk],
		"%s.Data3.%d" % [_edition, chunk],
		"%s.Data3.chunk%d" % [_edition, chunk],
		"%s:Data:%d:%d" % [_edition, SOURCE_RESOURCE, chunk],
	]
	if chunk == 0:
		aliases.append("%s.%s.%d" % [_edition, ARCHIVE, SOURCE_RESOURCE])
	if _edition == "MultiverseJourney":
		aliases.append(key.replace("MultiverseJourney", "MJ"))
	for alias in aliases:
		if visuals.has(alias):
			return visuals[alias]
	return null


func _fallback_frame(chunk: int) -> Dictionary:
	var size: Vector2 = FALLBACK_LOGICAL.get(chunk, Vector2.ONE)
	return {
		"edition": _edition,
		"archive": ARCHIVE,
		"resource": SOURCE_RESOURCE,
		"chunk": chunk,
		"logical": {"width": size.x, "height": size.y, "anchor_x": 0.0, "anchor_y": 0.0},
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
	if width <= 0 or height <= 0:
		return fallback
	return Vector2(width, height)


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


func _validate_model(value: Dictionary) -> bool:
	if _edition.is_empty() or _mode not in VALID_MODES:
		return false
	if value.size() != 3 or not value.has("edition") or not value.has("mode") or not value.has("settings"):
		return false
	if typeof(value.get("edition")) != TYPE_STRING or typeof(value.get("mode")) != TYPE_STRING:
		return false
	var settings_value: Variant = value.get("settings", null)
	if not settings_value is Dictionary:
		return false
	var settings: Dictionary = settings_value as Dictionary
	if settings.size() != SETTINGS_KEYS.size():
		return false
	for key in SETTINGS_KEYS:
		if not settings.has(key):
			return false
	if not _valid_int(settings["speed"], 0, 2):
		return false
	if typeof(settings["animation"]) != TYPE_BOOL:
		return false
	if not _valid_int(settings["music_level"], 0, 4):
		return false
	if not _valid_int(settings["sound_level"], 0, 4):
		return false
	if typeof(settings["autosave"]) != TYPE_BOOL:
		return false
	if not _valid_int(settings["view"], 0, 2):
		return false
	return true


func _valid_int(value: Variant, low: int, high: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= low and int(value) <= high


func _settings_copy(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in SETTINGS_KEYS:
		result[key] = value[key]
	return result


func _deep_equal(left: Variant, right: Variant) -> bool:
	var left_type := typeof(left)
	var right_type := typeof(right)
	if left_type != right_type:
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
