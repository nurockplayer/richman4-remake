extends Control
class_name RichmanSourceTrusteeDialog

## Pure source-shaped S04 trustee presenter.
##
## The source dialog receives player rows as a detached snapshot and keeps all
## edits in `_draft_rows`.  It emits accepted only from the OK release; every
## cancel path discards the draft.  No original art or platform state is
## embedded in this public script.

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const FRAME_ORIGIN := Vector2(102.0, 62.0)
const FRAME_SIZE := Vector2(435.0, 355.0)
const PANEL_ARCHIVE := "Panel"
const PANEL_RESOURCE := 77
const VALID_EDITIONS := ["Game", "MultiverseJourney"]
const MAX_ROWS := 4
const ROW_HEIGHT := 83.0
const PERSONALITIES := ["乖寶寶", "普通人", "大老奸"]
const DARK := Color("#101010")
const GREEN := Color("#2c8b3e")
const BLUE := Color("#152c4b")
const ART_FALLBACK := "來源託管面板素材未載入"

const ACCEPT_HITBOX := Rect2(377.0, 97.0, 40.0, 56.0)
const CANCEL_HITBOX := Rect2(377.0, 185.0, 40.0, 56.0)

signal accepted(rows: Array)
signal cancelled
signal changed(rows: Array)

const CONTROL_BOXES := {
	"use_cards": Rect2(185,44,96,18), "use_tools": Rect2(185,75,96,18),
	"personality_0": Rect2(185,132,96,18), "personality_1": Rect2(185,164,96,18), "personality_2": Rect2(185,197,96,18),
	"cash_minus": Rect2(196,266,11,22), "cash_plus": Rect2(290,266,11,22),
	"stock_minus": Rect2(196,299,11,22), "stock_plus": Rect2(290,299,11,22),
	"cash_ratio": Rect2(208,265,80,24), "stock_ratio": Rect2(208,298,80,24),
}
var _character_ids: Dictionary = {}
var row_controls: Array = []
var _model_rows: Array = []
var _draft_rows: Array = []
var _current_player_id := -1
var _edition := ""
var _selected_player_id := -1
var _pressed_row_id := -1
var _pressed_action := ""
var _open := false
var _visual_accessor: Variant = null
var _source_frames: Dictionary = {}
var _source_art_status: Dictionary = {}
var _surface: Control
var _panel_art: TextureRect
var _fallback: ColorRect
var _fallback_label: Label
var _built := false


func _init() -> void:
	name = "SourceTrusteeDialog"
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build()


func _ready() -> void:
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE


func configure(rows: Array, current_player_id: int, edition: String) -> bool:
	var copied := rows.duplicate(true)
	if not _validate_rows(copied, current_player_id, edition):
		_model_rows = []
		_draft_rows = []
		_open = false
		_render()
		return false
	_model_rows = copied
	_draft_rows = copied.duplicate(true)
	_current_player_id = current_player_id
	_edition = edition
	_selected_player_id = current_player_id
	_pressed_row_id = -1
	_pressed_action = ""
	_open = true
	_render()
	show()
	grab_focus()
	return true


func set_view_model(model: Dictionary) -> bool:
	var rows_value: Variant = model.get("rows", [])
	return rows_value is Array and configure(rows_value, int(model.get("current_player_id", -1)), str(model.get("edition", "")))


func set_visual_accessor(accessor: Variant) -> void:
	_visual_accessor = accessor.duplicate(true) if accessor is Dictionary else accessor
	_render()


func set_visuals(accessor: Variant) -> void:
	set_visual_accessor(accessor)


func is_open() -> bool:
	return _open and visible


func is_model_valid() -> bool:
	return not _model_rows.is_empty()


func view_model() -> Dictionary:
	return {"rows": _model_rows.duplicate(true), "current_player_id": _current_player_id, "edition": _edition}


func draft_rows() -> Array:
	return _draft_rows.duplicate(true)


func rows() -> Array:
	return draft_rows()


func committed_rows() -> Array:
	return _model_rows.duplicate(true)


func selected_player_id() -> int:
	return _selected_player_id


func source_geometry() -> Dictionary:
	return {
		"canvas": REFERENCE_SIZE,
		"panel_origin": FRAME_ORIGIN,
		"panel_size": FRAME_SIZE,
		"edition": _edition,
		"panel_archive": PANEL_ARCHIVE,
		"panel_resource": PANEL_RESOURCE,
		"row_height": ROW_HEIGHT,
		"row_hitboxes": _row_hitboxes(),
		"accept": FRAME_ORIGIN + ACCEPT_HITBOX.position,
		"cancel": FRAME_ORIGIN + CANCEL_HITBOX.position,
	}


func get_source_geometry() -> Dictionary:
	return source_geometry()


func source_hitboxes() -> Dictionary:
	return {
		"accept": FRAME_ORIGIN + ACCEPT_HITBOX.position,
		"cancel": FRAME_ORIGIN + CANCEL_HITBOX.position,
		"rows": _row_hitboxes(),
		"personality": _control_hitboxes("personality"),
		"use_cards": _control_hitboxes("use_cards"),
		"use_tools": _control_hitboxes("use_tools"),
		"cash_ratio": _control_hitboxes("cash_ratio"),
		"stock_ratio": _control_hitboxes("stock_ratio"),
	}


func get_source_hitboxes() -> Dictionary:
	return source_hitboxes()


func source_frames() -> Dictionary:
	return _source_frames.duplicate(true)


func get_source_frames() -> Dictionary:
	return source_frames()


func source_art_status() -> Dictionary:
	return _source_art_status.duplicate(true)


func source_art_available() -> bool:
	return bool(_source_art_status.get("panel", false))


func has_source_art() -> bool:
	return source_art_available()


## First click on another row selects it.  A second click on that selected row
## toggles the trustee bit, matching the source's two-step interaction.
func select_player(player_id: int) -> bool:
	if _find_row(player_id) < 0:
		return false
	if _selected_player_id != player_id:
		_selected_player_id = player_id
		_render_rows()
		return true
	return toggle_selected()


func toggle_selected() -> bool:
	var index := _find_row(_selected_player_id)
	if index < 0:
		return false
	_draft_rows[index]["trustee"] = not bool(_draft_rows[index].get("trustee", false))
	_render_rows()
	changed.emit(draft_rows())
	return true


func set_flag(player_id: int, flag: String, enabled: bool) -> bool:
	if flag not in ["use_cards", "use_tools"]:
		return false
	var index := _find_row(player_id)
	if index < 0:
		return false
	_draft_rows[index][flag] = enabled
	_render_rows()
	changed.emit(draft_rows())
	return true


func set_personality(player_id: int, personality: int) -> bool:
	if personality < 0 or personality >= PERSONALITIES.size():
		return false
	var index := _find_row(player_id)
	if index < 0:
		return false
	_draft_rows[index]["personality"] = personality
	_render_rows()
	changed.emit(draft_rows())
	return true


func adjust_ratio(player_id: int, ratio_name: String, delta: int) -> bool:
	if ratio_name not in ["cash_ratio", "stock_ratio"] or delta == 0:
		return false
	var index := _find_row(player_id)
	if index < 0:
		return false
	var old := int(_draft_rows[index].get(ratio_name, 50))
	var value := clampi(old + (10 if delta > 0 else -10), 0, 100)
	_draft_rows[index][ratio_name] = value
	_render_rows()
	changed.emit(draft_rows())
	return true


func set_ratio(player_id: int, ratio_name: String, value: int) -> bool:
	if ratio_name not in ["cash_ratio", "stock_ratio"]:
		return false
	var index := _find_row(player_id)
	if index < 0 or value < 0 or value > 100 or value % 10 != 0:
		return false
	_draft_rows[index][ratio_name] = value
	_render_rows()
	changed.emit(draft_rows())
	return true


func accept_dialog() -> bool:
	if not is_open():
		return false
	_open = false
	hide()
	accepted.emit(draft_rows())
	return true


func cancel_dialog() -> bool:
	if not is_open():
		return false
	_open = false
	_pressed_action = ""
	_pressed_row_id = -1
	hide()
	cancelled.emit()
	return true


func _gui_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and _pressed_action in ["cash_ratio", "stock_ratio"]:
			_set_ratio_from_point(event.position - FRAME_ORIGIN, _pressed_action)
			accept_event()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			cancel_dialog()
			accept_event()
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var local: Vector2 = event.position - FRAME_ORIGIN
		if event.pressed:
			_pressed_action = _interaction_at(local)
			_pressed_row_id = _row_at(local)
			if _pressed_row_id >= 0:
				select_player(_pressed_row_id)
			elif _pressed_action in ["cash_ratio", "stock_ratio"]:
				_set_ratio_from_point(local, _pressed_action)
			accept_event()
			return
		var action := _interaction_at(local)
		if action == _pressed_action:
			if action == "accept": accept_dialog()
			elif action == "cancel": cancel_dialog()
			elif action.begins_with("personality_"): set_personality(_selected_player_id, int(action.trim_prefix("personality_")))
			elif action in ["use_cards", "use_tools"]:
				var index := _find_row(_selected_player_id)
				if index >= 0: set_flag(_selected_player_id, action, not bool(_draft_rows[index][action]))
			elif action.ends_with("_minus") or action.ends_with("_plus"):
				adjust_ratio(_selected_player_id, "cash_ratio" if action.begins_with("cash") else "stock_ratio", 1 if action.ends_with("_plus") else -1)
			elif action in ["cash_ratio", "stock_ratio"]: _set_ratio_from_point(local, action)
		_pressed_action = ""
		_pressed_row_id = -1
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel_dialog()
		accept_event()

func _build() -> void:
	_surface = Control.new()
	_surface.name = "SourceTrusteeSurface"
	_surface.size = REFERENCE_SIZE
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)
	_fallback = ColorRect.new()
	_fallback.name = "SourceTrusteePanelFallback"
	_fallback.position = FRAME_ORIGIN
	_fallback.size = FRAME_SIZE
	_fallback.color = Color("#b8a276")
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(_fallback)
	_panel_art = TextureRect.new()
	_panel_art.name = "SourceTrusteePanel77"
	_panel_art.position = FRAME_ORIGIN
	_panel_art.size = FRAME_SIZE
	_panel_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_panel_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_panel_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_art.visible = false
	_surface.add_child(_panel_art)
	_fallback_label = Label.new()
	_fallback_label.name = "SourceTrusteeArtFallback"
	_fallback_label.position = FRAME_ORIGIN + Vector2(105.0, 174.0)
	_fallback_label.size = Vector2(225.0, 25.0)
	_fallback_label.text = ART_FALLBACK
	_fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback_label.add_theme_font_size_override("font_size", 14)
	_fallback_label.add_theme_color_override("font_color", Color("#553d25"))
	_fallback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(_fallback_label)
	_built = true


func _render() -> void:
	if not _built:
		return
	_source_frames.clear()
	_source_art_status.clear()
	var frame := _resolve_panel()
	_source_frames["panel"] = frame.get("frame", {}).duplicate(true)
	_source_art_status["panel"] = frame.get("texture") is Texture2D
	_panel_art.texture = frame.get("texture")
	_panel_art.visible = _panel_art.texture != null
	_fallback.visible = not _panel_art.visible
	_fallback_label.visible = not _panel_art.visible
	_render_rows()


func _render_rows() -> void:
	if not _built:
		return
	for child in row_controls:
		if is_instance_valid(child): child.free()
	row_controls.clear()
	for key in _source_frames.keys():
		if key != "panel": _source_frames.erase(key)
	for key in _source_art_status.keys():
		if key != "panel": _source_art_status.erase(key)
	if not is_model_valid():
		return
	for index in range(_draft_rows.size()):
		var row: Dictionary = _draft_rows[index]
		var y := 8.0 + ROW_HEIGHT * float(index)
		var row_name := "TrusteeRow%d" % int(row.player_id)
		_add_source_chunk(row_name, 1 if int(row.player_id) == _selected_player_id else 2, Vector2(8,y))
		var character := int(_character_ids.get(int(row.player_id), -1))
		var portrait := false
		if character >= 0 and character < 12:
			portrait = _add_source_chunk("TrusteePortrait%d" % int(row.player_id), character + 6, Vector2(80,y+40))
		if not portrait:
			_add_label("TrusteeName%d" % row.player_id, str(row.name), FRAME_ORIGIN + Vector2(35,y+25), Vector2(82,30), 14, Color.WHITE)
		if bool(row.trustee): _add_source_chunk("TrusteeDelegated%d" % int(row.player_id), 3, Vector2(19,y+36))
	var selected: Dictionary = _draft_rows[_find_row(_selected_player_id)]
	_add_label("TrusteeAIHeading", "託管AI", FRAME_ORIGIN + Vector2(136,15), Vector2(74,22), 18, Color.WHITE)
	_add_label("TrusteeCardsLabel", "使用卡片", FRAME_ORIGIN + Vector2(209,42), Vector2(78,22), 16, Color.WHITE)
	_add_label("TrusteeToolsLabel", "使用道具", FRAME_ORIGIN + Vector2(209,73), Vector2(78,22), 16, Color.WHITE)
	if bool(selected.use_cards): _add_source_chunk("TrusteeCardsMarker", 3, Vector2(186,45))
	if bool(selected.use_tools): _add_source_chunk("TrusteeToolsMarker", 3, Vector2(186,77))
	_add_label("TrusteePersonalityLabel", "個  性", FRAME_ORIGIN + Vector2(136,103), Vector2(74,22), 18, Color.WHITE)
	for index in range(3):
		_add_label("TrusteePersonalityText%d" % index, PERSONALITIES[index], FRAME_ORIGIN + Vector2(209,[130,162,195][index]), Vector2(78,22), 16, Color.WHITE)
	_add_source_chunk("TrusteePersonalityMarker", 3, Vector2(186,[133,165,197][int(selected.personality)]))
	_add_label("TrusteeRatioHeading", "資金運用比例", FRAME_ORIGIN + Vector2(190,234), Vector2(120,23), 18, Color.WHITE)
	_add_ratio("cash", selected, 266)
	_add_ratio("stock", selected, 299)
	_add_button_label("TrusteeAccept", "確定", FRAME_ORIGIN + Vector2(377,111), Vector2(40,28))
	_add_button_label("TrusteeCancel", "取消", FRAME_ORIGIN + Vector2(377,199), Vector2(40,28))

func _add_ratio(kind: String, row: Dictionary, y: float) -> void:
	var value := int(row[kind + "_ratio"])
	_add_label("Trustee%sLeft" % kind, "現金" if kind == "cash" else "股票", FRAME_ORIGIN + Vector2(154,y), Vector2(40,22), 16, Color.WHITE)
	_add_label("Trustee%sRight" % kind, "存款" if kind == "cash" else "資金", FRAME_ORIGIN + Vector2(304,y), Vector2(40,22), 16, Color.WHITE)
	for segment in range(value / 10):
		var marker := ColorRect.new()
		marker.name = "Trustee%sSegment%d" % [kind, segment]
		marker.position = FRAME_ORIGIN + Vector2(209 + 8 * segment,y)
		marker.size = Vector2(7,22)
		marker.color = Color.RED
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_surface.add_child(marker)
		row_controls.append(marker)

func _add_label(node_name: String, value: String, position: Vector2, box_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = position
	label.size = box_size
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(label)
	row_controls.append(label)
	return label


func _add_button_label(node_name: String, value: String, position: Vector2, box_size: Vector2) -> void:
	var label := _add_label(node_name, value, position, box_size, 15, DARK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func set_character_ids(value: Dictionary) -> void:
	_character_ids = value.duplicate()
	_render_rows()

func _add_source_chunk(node_name: String, chunk: int, point: Vector2) -> bool:
	var resolved := _resolve_chunk(chunk)
	_source_frames[node_name] = resolved.get("frame", {}).duplicate(true)
	_source_art_status[node_name] = resolved.get("texture") is Texture2D
	if not _source_art_status[node_name]: return false
	var frame: Dictionary = resolved.frame
	var logical: Dictionary = frame.get("logical", {})
	var texture := TextureRect.new()
	texture.name = node_name
	texture.position = FRAME_ORIGIN + point - Vector2(float(logical.get("anchor_x",0)),float(logical.get("anchor_y",0)))
	texture.size = Vector2(float(logical.get("width",1)),float(logical.get("height",1)))
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_SCALE
	texture.texture = resolved.texture
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(texture)
	row_controls.append(texture)
	return true

func _resolve_panel() -> Dictionary:
	return _resolve_chunk(0)

func _resolve_chunk(chunk: int) -> Dictionary:
	var frame: Dictionary = {}
	var texture: Texture2D = null
	if _visual_accessor is Object and _visual_accessor.has_method("ui"):
		var result: Variant = _visual_accessor.call("ui", _edition, PANEL_ARCHIVE, PANEL_RESOURCE, chunk)
		if result is Dictionary:
			frame = result.duplicate(true)
			if frame.get("texture") is Texture2D:
				texture = frame["texture"]
		elif result is Texture2D:
			texture = result
	elif _visual_accessor is Callable:
		var result: Variant = _visual_accessor.call("%s.%s.%d.%d" % [_edition, PANEL_ARCHIVE, PANEL_RESOURCE, chunk])
		if result is Dictionary:
			frame = result.duplicate(true)
			if frame.get("texture") is Texture2D:
				texture = frame["texture"]
		elif result is Texture2D:
			texture = result
	if texture == null and not frame.is_empty() and _visual_accessor is Object and _visual_accessor.has_method("texture"):
		var candidate: Variant = _visual_accessor.call("texture", frame)
		if candidate is Texture2D:
			texture = candidate
	return {"frame": frame, "texture": texture}


func _action_at(local: Vector2) -> String:
	if ACCEPT_HITBOX.has_point(local):
		return "accept"
	if CANCEL_HITBOX.has_point(local):
		return "cancel"
	return ""


func _interaction_at(local: Vector2) -> String:
	var action := _action_at(local)
	if not action.is_empty(): return action
	for key in CONTROL_BOXES:
		if CONTROL_BOXES[key].has_point(local): return key
	return ""

func _set_ratio_from_point(local: Vector2, ratio_name: String) -> void:
	if _find_row(_selected_player_id) < 0: return
	set_ratio(_selected_player_id, ratio_name, clampi(int(floor((local.x - 208.0) / 8.0)) * 10, 0, 100))

func _row_at(local: Vector2) -> int:
	if local.x < 8.0 or local.x >= 124.0 or local.y < 8.0:
		return -1
	var index := int(floor((local.y - 8.0) / ROW_HEIGHT))
	if index < 0 or index >= _draft_rows.size() or local.y >= 8.0 + ROW_HEIGHT * float(_draft_rows.size()):
		return -1
	return int(_draft_rows[index].get("player_id", -1))


func _row_hitboxes() -> Array:
	var result: Array = []
	for index in range(_draft_rows.size()):
		result.append(Rect2(FRAME_ORIGIN + Vector2(8.0, 8.0 + ROW_HEIGHT * float(index)), Vector2(116.0, 83.0)))
	return result


func _control_hitboxes(kind: String) -> Array:
	var keys: Array = ["personality_0","personality_1","personality_2"] if kind == "personality" else [kind]
	var result: Array = []
	for key in keys:
		var rect: Rect2 = CONTROL_BOXES[key]
		result.append(Rect2(FRAME_ORIGIN + rect.position,rect.size))
	return result

func _find_row(player_id: int) -> int:
	for index in range(_draft_rows.size()):
		if int(_draft_rows[index].get("player_id", -1)) == player_id:
			return index
	return -1


func _validate_rows(value: Array, current_player_id: int, edition: String) -> bool:
	if value.is_empty() or value.size() > MAX_ROWS or edition not in VALID_EDITIONS:
		return false
	var ids: Dictionary = {}
	var current_found := false
	for raw in value:
		if not raw is Dictionary:
			return false
		var row: Dictionary = raw
		var player_id: Variant = row.get("player_id", null)
		if not player_id is int or int(player_id) < 0 or int(player_id) > 3 or ids.has(int(player_id)):
			return false
		ids[int(player_id)] = true
		current_found = current_found or int(player_id) == current_player_id
		var personality := int(row.get("personality", 1))
		if personality < 0 or personality >= PERSONALITIES.size():
			return false
		for key in ["cash_ratio", "stock_ratio"]:
			var ratio: Variant = row.get(key, 50)
			if not (ratio is int or ratio is float) or not is_finite(float(ratio)) or float(ratio) < 0.0 or float(ratio) > 100.0:
				return false
	return current_found
