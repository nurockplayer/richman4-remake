extends Control

## Source Data440 YES/NO; Game Data399 is an audited byte-identical resource.
## Source uses hover selection followed by left release, or the Y/N bindings.
signal decided(accepted: bool)
const Hotkeys = preload("res://game/platform/system_hotkeys.gd")
const SOURCE_RECT := Rect2(272,216,96,48)
var _visuals: Variant
var _edition := "Game"
var _bindings: Array = Hotkeys.DEFAULTS.duplicate()
var _selection := 0
var _finished := false
var _texture: Texture2D
var _source_available := false

func _init() -> void:
	name = "SourceSaleConfirmation"
	size = Vector2(640,480)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func configure(visuals: Variant, edition: String, bindings: Array) -> void:
	_visuals = visuals
	_edition = edition
	var checked: Dictionary = Hotkeys.new().validate_bindings(bindings)
	_bindings = checked.bindings if checked.get("ok", false) else Hotkeys.DEFAULTS.duplicate()
	_selection = 0
	_finished = false
	_refresh()

func source_art_available() -> bool:
	return _source_available

func reset_hover() -> void:
	_selection = 0
	_refresh()

func _refresh() -> void:
	var resource := 399 if _edition == "Game" else 440
	var frame := {}
	_texture = null
	if _visuals is Object and _visuals.has_method("ui"):
		var result: Variant = _visuals.call("ui", _edition, "Data", resource, _selection)
		if result is Dictionary: frame = result
	elif _visuals is Dictionary:
		frame = _visuals.get("%s.Data.%d.%d" % [_edition,resource,_selection], {})
	if frame.get("ui_texture") is Texture2D: _texture = frame.ui_texture
	elif _visuals is Object and _visuals.has_method("texture") and not frame.is_empty(): _texture = _visuals.call("texture", frame)
	_source_available = _texture != null
	queue_redraw()

func _draw() -> void:
	if _texture != null: draw_texture_rect(_texture, SOURCE_RECT, false)
	else:
		draw_rect(SOURCE_RECT, Color("#405048"))
		draw_string(ThemeDB.fallback_font, Vector2(286,246), "YES   NO", HORIZONTAL_ALIGNMENT_LEFT, 80, 16)

func _gui_input(event: InputEvent) -> void:
	if _finished: return
	if event is InputEventMouseMotion:
		var next := int((event.position.x-SOURCE_RECT.position.x)/48)+1 if SOURCE_RECT.has_point(event.position) else 0
		if next != _selection:
			_selection = next
			_refresh()
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT: _decide(false)
		elif event.button_index == MOUSE_BUTTON_LEFT and _selection > 0: _decide(_selection == 1)
	accept_event()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _finished or not event is InputEventKey: return
	if not event.pressed or event.echo or event.alt_pressed or event.meta_pressed or event.shift_pressed: return
	var code: int = Hotkeys.new().event_key(event)
	var word: int = code | (0x1100 if event.ctrl_pressed else 0)
	if code > 0 and word in [int(_bindings[8]), int(_bindings[9])]:
		get_viewport().set_input_as_handled()
		_decide(word == int(_bindings[8]))

func _decide(accepted: bool) -> void:
	if _finished: return
	_finished = true
	decided.emit(accepted)
