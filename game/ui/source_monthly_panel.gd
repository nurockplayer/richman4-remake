extends Control
class_name RichmanSourceMonthlyPanel

## Source-shaped S17/S18 report presenter.
##
## The host supplies a completed, copied report payload and an optional
## OriginalVisuals-like accessor.  This component never owns GameState, ledger,
## RNG, persistence, audio, or a filesystem path.  All positions below are
## source logical coordinates; texture pixel dimensions are never used for
## layout.

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const DIVIDEND_PANEL_ORIGIN := Vector2(24.0, 24.0)
const DIVIDEND_PANEL_SIZE := Vector2(592.0, 432.0)
const INTEREST_CLERK_POSITION := Vector2(28.0, 70.0)
const INTEREST_CLERK_SIZE := Vector2(233.0, 410.0)
const INTEREST_CARD_ORIGIN_X := 360.0
const INTEREST_CARD_SIZES := [
	Vector2(160.0, 71.0),
	Vector2(159.0, 71.0),
	Vector2(159.0, 71.0),
	Vector2(159.0, 71.0),
]
const INTEREST_ANCHORS := {
	1: [240],
	2: [120, 360],
	3: [100, 240, 380],
	4: [60, 180, 300, 420],
}
const VALID_EDITIONS := ["Game", "MultiverseJourney"]
const MAX_PLAYERS := 4
const MAX_COMPANIES := 12
const SOURCE_DARK := Color("#101010")
const SOURCE_WHITE := Color("#ffffff")
const SOURCE_SHADOW := Color("#101010")
const LOAN_RED := Color("#c21f28")

signal continued

## Dividend reports default to the source's three-second automatic advance.
## Set this to 0 (or use set_auto_advance_seconds(0)) for deterministic tests.
## Interest reports intentionally ignore this setting and never auto-close.
var auto_advance_seconds: float = 3.0

var _model: Dictionary = {}
var _visual_accessor: Variant = null
var _model_valid := false
var _kind := ""
var _edition := ""
var _is_open := false
var _continued_emitted := false
var _source_art_available := false
var _source_art_status: Dictionary = {}
var _source_frames: Dictionary = {}

var _surface: Control
var _fallback_background: ColorRect
var _unavailable: Label
var _timer: Timer
var _built := false


func _init() -> void:
	name = "SourceMonthlyPanel"
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build()


func _ready() -> void:
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE


## Replace the report snapshot.  The input is deeply copied before validation
## and rendering, so the host cannot be mutated by this presenter.
func set_view_model(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_kind = str(_model.get("kind", ""))
	_edition = _canonical_edition(_model.get("edition", null))
	_model_valid = _validate_model(_model)
	_is_open = _model_valid
	_continued_emitted = false
	_stop_timer()
	_render()
	if _model_valid:
		show()
		_configure_timer()
	else:
		show()


## Install a host-provided resolver.  Dictionaries are copied deeply; objects
## and callables are borrowed but never asked to perform IO by this component.
func set_visuals(accessor: Variant) -> void:
	if accessor is Dictionary:
		_visual_accessor = accessor.duplicate(true)
	else:
		_visual_accessor = accessor
	_render()
	if _model_valid:
		_configure_timer()


func view_model() -> Dictionary:
	return _model.duplicate(true)


func report_data() -> Dictionary:
	return view_model()


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


func source_geometry() -> Dictionary:
	return {
		"canvas": REFERENCE_SIZE,
		"kind": _kind,
		"edition": _edition,
		"panel_origin": DIVIDEND_PANEL_ORIGIN,
		"panel_size": DIVIDEND_PANEL_SIZE,
		"dividend": {
			"title_center": DIVIDEND_PANEL_ORIGIN + Vector2(296.0, 25.0),
			"header_company_origin": DIVIDEND_PANEL_ORIGIN + Vector2(18.0, 82.0),
			"header_player_center": DIVIDEND_PANEL_ORIGIN + Vector2(104.0, 82.0),
			"player_center": DIVIDEND_PANEL_ORIGIN + Vector2(160.0, 88.0),
			"profit_center": DIVIDEND_PANEL_ORIGIN + Vector2(542.0, 88.0),
			"data_origin": DIVIDEND_PANEL_ORIGIN + Vector2(62.0, 116.0),
			"total_center": DIVIDEND_PANEL_ORIGIN + Vector2(62.0, 404.0),
		},
		"interest": {
			"clerk_position": INTEREST_CLERK_POSITION,
			"clerk_size": INTEREST_CLERK_SIZE,
			"card_origin_x": INTEREST_CARD_ORIGIN_X,
			"anchors": _interest_anchors(_model.get("players", []).size() if _model.get("players", []) is Array else 0),
		},
	}


func get_source_geometry() -> Dictionary:
	return source_geometry()


func source_frames() -> Dictionary:
	return _source_frames.duplicate(true)


func get_source_frames() -> Dictionary:
	return source_frames()


func set_auto_advance_seconds(seconds: float) -> void:
	if not is_finite(seconds) or seconds < 0.0:
		auto_advance_seconds = 0.0
	else:
		auto_advance_seconds = seconds
	_configure_timer()


## Close the currently open valid report exactly once.  This is public so a
## controller can use the same idempotent boundary as a source mouse release.
func continue_report() -> bool:
	if not _model_valid or not _is_open or _continued_emitted:
		return false
	_continued_emitted = true
	_is_open = false
	_stop_timer()
	hide()
	emit_signal("continued")
	return true


func _gui_input(event: InputEvent) -> void:
	if not _model_valid or not _is_open or not visible:
		return
	if not event is InputEventMouseButton:
		return
	var button_event := event as InputEventMouseButton
	if button_event.pressed:
		return
	if button_event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	if continue_report():
		get_viewport().set_input_as_handled()


func _on_auto_advance_timeout() -> void:
	continue_report()


func _on_timer_timeout() -> void:
	_on_auto_advance_timeout()


func _build() -> void:
	if _built:
		return
	_built = true
	_surface = Control.new()
	_surface.name = "SourceMonthlySurface"
	_surface.position = Vector2.ZERO
	_surface.size = REFERENCE_SIZE
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)

	_fallback_background = ColorRect.new()
	_fallback_background.name = "MonthlyFallbackBackground"
	_fallback_background.position = Vector2.ZERO
	_fallback_background.size = REFERENCE_SIZE
	_fallback_background.color = Color("#0d1524")
	_fallback_background.z_index = -3
	_fallback_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(_fallback_background)

	_unavailable = _make_label(
		"MonthlyUnavailable",
		"資料格式無法顯示",
		Rect2(80.0, 214.0, 480.0, 42.0),
		20,
		Color("#ffb3a4"),
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_unavailable.hide()

	_timer = Timer.new()
	_timer.name = "MonthlyAutoAdvanceTimer"
	_timer.one_shot = true
	_timer.timeout.connect(_on_auto_advance_timeout)
	add_child(_timer)


func _render() -> void:
	if not _built:
		return
	_stop_timer()
	_clear_dynamic_children()
	_source_frames.clear()
	_source_art_status.clear()
	_source_art_available = false
	_fallback_background.show()
	_unavailable.hide()
	if not _model_valid:
		_fallback_background.color = Color("#0d1524")
		_unavailable.show()
		_is_open = false
		return

	_is_open = true
	if _kind == "dividend":
		_build_dividend()
	else:
		_build_interest()
	if not _source_art_available:
		_add_source_fallback_note()


func _clear_dynamic_children() -> void:
	for child in _surface.get_children():
		if child == _fallback_background or child == _unavailable:
			continue
		child.free()


func _build_dividend() -> void:
	_fallback_background.color = Color.BLACK
	var panel_source := _resolve_source(76, 0)
	var panel_texture: Texture2D = panel_source.get("texture") as Texture2D
	var panel_frame: Dictionary = panel_source.get("frame", {})
	_source_frames["Panel76.0"] = panel_frame.duplicate(true)
	_source_art_status["background"] = panel_texture != null
	_source_art_available = panel_texture != null
	if panel_texture != null:
		var panel_art := _add_texture(
			"DividendPanelArt",
			panel_texture,
			DIVIDEND_PANEL_ORIGIN,
			DIVIDEND_PANEL_SIZE,
			panel_frame,
		)
		panel_art.z_index = 0

	var title_center := DIVIDEND_PANEL_ORIGIN + Vector2(296.0, 25.0)
	_make_centered_label("DividendTitle", "上市公司分紅", title_center, Vector2(300.0, 36.0), 28, SOURCE_WHITE, SOURCE_SHADOW)
	_make_label("DividendHeaderCompany", "公司", Rect2(DIVIDEND_PANEL_ORIGIN + Vector2(18.0, 82.0), Vector2(42.0, 24.0)), 16, SOURCE_DARK, HORIZONTAL_ALIGNMENT_LEFT)
	_make_centered_label(
		"DividendHeaderPlayer",
		"人名",
		DIVIDEND_PANEL_ORIGIN + Vector2(104.0, 82.0),
		Vector2(56.0, 24.0),
		16,
		SOURCE_DARK,
	)
	_make_centered_label(
		"DividendHeaderProfit",
		"本月盈餘",
		DIVIDEND_PANEL_ORIGIN + Vector2(542.0, 88.0),
		Vector2(100.0, 24.0),
		16,
		SOURCE_DARK,
	)

	var players: Array = _model["players"]
	for ordinal in range(players.size()):
		var player: Dictionary = players[ordinal]
		var center := DIVIDEND_PANEL_ORIGIN + Vector2(160.0 + 98.0 * ordinal, 88.0)
		_make_centered_label(
			"DividendPlayerHeader%d" % ordinal,
			str(player["name"]),
			center,
			Vector2(92.0, 24.0),
			16,
			SOURCE_DARK,
		)

	var companies: Array = _model["companies"]
	for row_index in range(companies.size()):
		var company: Dictionary = companies[row_index]
		var row_y := DIVIDEND_PANEL_ORIGIN.y + 116.0 + 24.0 * row_index
		_make_centered_label(
			"DividendCompany%d" % row_index,
			str(company["name"]),
			Vector2(DIVIDEND_PANEL_ORIGIN.x + 62.0, row_y),
			Vector2(108.0, 24.0),
			16,
			SOURCE_DARK,
		)
		var payouts: Array = company["payouts"]
		for ordinal in range(players.size()):
			var right_edge := DIVIDEND_PANEL_ORIGIN.x + 198.0 + 98.0 * ordinal
			_make_right_label(
				"DividendPayout%d_%d" % [row_index, ordinal],
				_format_number(int(payouts[ordinal])),
				Rect2(right_edge - 92.0, row_y - 12.0, 92.0, 24.0),
				16,
				SOURCE_DARK,
			)
		var profit_right_edge := DIVIDEND_PANEL_ORIGIN.x + 572.0
		_make_right_label(
			"DividendProfit%d" % row_index,
			_format_number(int(company["monthly_profit"])),
			Rect2(profit_right_edge - 112.0, row_y - 12.0, 112.0, 24.0),
			16,
			SOURCE_DARK,
		)

	_make_centered_label(
		"DividendTotalLabel",
		"紅利",
		DIVIDEND_PANEL_ORIGIN + Vector2(62.0, 404.0),
		Vector2(108.0, 24.0),
		16,
		SOURCE_DARK,
	)
	for ordinal in range(players.size()):
		var right_edge := DIVIDEND_PANEL_ORIGIN.x + 198.0 + 98.0 * ordinal
		_make_right_label(
			"DividendPlayerTotal%d" % ordinal,
			_format_number(int(players[ordinal]["total"])),
			Rect2(right_edge - 92.0, DIVIDEND_PANEL_ORIGIN.y + 404.0 - 12.0, 92.0, 24.0),
			16,
			SOURCE_DARK,
		)


func _build_interest() -> void:
	_fallback_background.color = Color("#0a1018")
	var background_source := _resolve_source(25, 0)
	var background_texture: Texture2D = background_source.get("texture") as Texture2D
	var background_frame: Dictionary = background_source.get("frame", {})
	_source_frames["Panel25.0"] = background_frame.duplicate(true)
	_source_art_status["background"] = background_texture != null
	if background_texture != null:
		var opaque := ColorRect.new()
		opaque.name = "InterestOpaqueBacking"
		opaque.position = Vector2.ZERO
		opaque.size = REFERENCE_SIZE
		opaque.color = Color.BLACK
		opaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		opaque.z_index = -2
		_surface.add_child(opaque)
		var background_art := _add_texture("InterestBackground", background_texture, Vector2.ZERO, REFERENCE_SIZE, background_frame)
		background_art.z_index = -1

	var clerk_source := _resolve_source(25, 24)
	var clerk_texture: Texture2D = clerk_source.get("texture") as Texture2D
	var clerk_frame: Dictionary = clerk_source.get("frame", {})
	_source_frames["Panel25.24"] = clerk_frame.duplicate(true)
	_source_art_status["clerk"] = clerk_texture != null
	if clerk_texture != null:
		_add_texture("InterestClerk", clerk_texture, INTEREST_CLERK_POSITION, INTEREST_CLERK_SIZE, clerk_frame)

	var players: Array = _model["players"]
	var anchors: Array = _interest_anchors(players.size())
	for ordinal in range(players.size()):
		var player: Dictionary = players[ordinal]
		var anchor_y: float = anchors[ordinal]
		var card_size: Vector2 = INTEREST_CARD_SIZES[ordinal]
		var card_origin := Vector2(INTEREST_CARD_ORIGIN_X, anchor_y - 36.0)
		var card_source := _resolve_source(25, 11 + ordinal)
		var card_texture: Texture2D = card_source.get("texture") as Texture2D
		var card_frame: Dictionary = card_source.get("frame", {})
		_source_frames["Panel25.%d" % (11 + ordinal)] = card_frame.duplicate(true)
		_source_art_status["card_%d" % ordinal] = card_texture != null
		if card_texture != null:
			_add_texture("InterestPlayerCard%d" % ordinal, card_texture, card_origin, card_size, card_frame)
		else:
			var card_fallback := ColorRect.new()
			card_fallback.name = "InterestPlayerCardFallback%d" % ordinal
			card_fallback.position = card_origin
			card_fallback.size = card_size
			card_fallback.color = Color("#e7dfbd")
			card_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_surface.add_child(card_fallback)

		var deposit_rect := Rect2(card_origin + Vector2(4.0, 6.0), Vector2(150.0, 22.0))
		var interest_rect := Rect2(card_origin + Vector2(4.0, 46.0), Vector2(150.0, 22.0))
		_make_label("InterestDepositLabel%d" % ordinal, "存款：", deposit_rect, 18, SOURCE_DARK, HORIZONTAL_ALIGNMENT_LEFT)
		_make_right_label(
			"InterestDeposit%d" % ordinal,
			_currency(int(player["deposit_before"])),
			deposit_rect,
			18,
			SOURCE_DARK,
		)
		_make_label("InterestInterestLabel%d" % ordinal, "利息：", interest_rect, 18, SOURCE_DARK, HORIZONTAL_ALIGNMENT_LEFT)
		var result_text := "貸款中" if bool(player["loan_active"]) else _currency(int(player["interest"]))
		var result_color := LOAN_RED if bool(player["loan_active"]) else SOURCE_DARK
		_make_right_label("InterestInterest%d" % ordinal, result_text, interest_rect, 18, result_color)

		var character_id := int(player["character_id"])
		var character_source := _resolve_source(25, 49 + character_id * 3)
		var character_texture: Texture2D = character_source.get("texture") as Texture2D
		var character_frame: Dictionary = character_source.get("frame", {})
		_source_frames["Panel25.%d" % (49 + character_id * 3)] = character_frame.duplicate(true)
		_source_art_status["character_%d" % ordinal] = character_texture != null
		if character_texture != null:
			var logical := _logical_for(character_frame, Vector2(66.0, 72.0))
			var anchor := _anchor_for(character_frame)
			var position := Vector2(600.0, anchor_y) - anchor
			_add_texture("InterestCharacter%d" % ordinal, character_texture, position, logical, character_frame)

	_source_art_available = _all_source_art_available()


func _all_source_art_available() -> bool:
	if _source_art_status.is_empty():
		return false
	for value in _source_art_status.values():
		if value != true:
			return false
	return true


func _add_source_fallback_note() -> void:
	var note := _make_label(
		"MonthlySourceArtFallback",
		"來源畫面素材未載入",
		Rect2(190.0, 458.0, 260.0, 18.0),
		13,
		Color("#b6d5cf"),
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	note.z_index = 10


func _add_texture(
	node_name: String,
	texture: Texture2D,
	position: Vector2,
	logical_size: Vector2,
	frame: Dictionary,
) -> TextureRect:
	var art := TextureRect.new()
	art.name = node_name
	art.position = position
	art.size = logical_size
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_meta("source_frame", frame.duplicate(true))
	art.set_meta("source_logical_size", logical_size)
	_surface.add_child(art)
	return art


func _make_centered_label(
	node_name: String,
	text_value: String,
	center: Vector2,
	logical_size: Vector2,
	font_size: int,
	color: Color,
	shadow_color: Color = Color.TRANSPARENT,
) -> Label:
	var rect := Rect2(center - logical_size / 2.0, logical_size)
	var label := _make_label(node_name, text_value, rect, font_size, color, HORIZONTAL_ALIGNMENT_CENTER)
	# Godot's font minimum can be taller than a small source label rectangle.
	# Keep the source center stable even when the physical font metrics grow.
	var actual_height := maxf(logical_size.y, label.get_minimum_size().y)
	label.position = Vector2(center.x - logical_size.x / 2.0, center.y - actual_height / 2.0)
	label.size = Vector2(logical_size.x, actual_height)
	if shadow_color.a > 0.0:
		label.add_theme_color_override("font_shadow_color", shadow_color)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _make_right_label(node_name: String, text_value: String, rect: Rect2, font_size: int, color: Color) -> Label:
	return _make_label(node_name, text_value, rect, font_size, color, HORIZONTAL_ALIGNMENT_RIGHT)


func _make_label(
	node_name: String,
	text_value: String,
	rect: Rect2,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = rect.position
	label.size = rect.size
	label.text = text_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(label)
	return label


func _resolve_source(resource: int, chunk: int) -> Dictionary:
	var key := "%s.Panel%d.%d" % [_edition, resource, chunk]
	var frame: Dictionary = {}
	var direct_texture: Texture2D = null
	if _visual_accessor is Dictionary:
		var value: Variant = _dictionary_visual(_visual_accessor, key, resource, chunk)
		if value is Dictionary:
			frame = value.duplicate(true)
		elif value is Texture2D:
			direct_texture = value
	elif _visual_accessor is Callable:
		var value: Variant = _visual_accessor.call(key)
		if value is Dictionary:
			frame = value.duplicate(true)
		elif value is Texture2D:
			direct_texture = value
	elif _visual_accessor is Object:
		if _visual_accessor.has_method("ui"):
			var value: Variant = _visual_accessor.call("ui", _edition, "Panel", resource, chunk)
			if value is Dictionary:
				frame = value.duplicate(true)
			elif value is Texture2D:
				direct_texture = value
		elif _visual_accessor.has_method("visual"):
			var value: Variant = _visual_accessor.call("visual", _edition, "Panel", resource, chunk)
			if value is Dictionary:
				frame = value.duplicate(true)
			elif value is Texture2D:
				direct_texture = value
		elif _visual_accessor.has_method("resolve"):
			var value: Variant = _visual_accessor.call("resolve", key)
			if value is Dictionary:
				frame = value.duplicate(true)
			elif value is Texture2D:
				direct_texture = value

	if frame.is_empty() and direct_texture == null:
		_source_frames[key] = {}
		return {"frame": {}, "texture": null}
	if frame.is_empty():
		frame = _fallback_frame(resource, chunk)
	var texture: Texture2D = direct_texture
	if texture == null and _visual_accessor is Object and _visual_accessor.has_method("texture"):
		var texture_value: Variant = _visual_accessor.call("texture", frame)
		if texture_value is Texture2D:
			texture = texture_value
	_source_frames[key] = frame.duplicate(true)
	return {"frame": frame, "texture": texture}


func _dictionary_visual(visuals: Dictionary, key: String, resource: int, chunk: int) -> Variant:
	var aliases := [
		key,
		key.to_lower(),
		key.to_upper(),
		key.replace(".", "/"),
		key.replace(".", "_"),
		"%s.Panel%d.chunk%d" % [_edition, resource, chunk],
	]
	if chunk == 0:
		aliases.append("%s.Panel%d" % [_edition, resource])
	if _edition == "MultiverseJourney":
		aliases.append(key.replace("MultiverseJourney", "MJ"))
	for alias in aliases:
		if visuals.has(alias):
			return visuals[alias]
	return null


func _fallback_frame(resource: int, chunk: int) -> Dictionary:
	var logical := {"width": 1, "height": 1, "anchor_x": 0, "anchor_y": 0}
	if resource == 76:
		logical = {"width": 592, "height": 432, "anchor_x": 0, "anchor_y": 0}
	elif resource == 25 and chunk == 0:
		logical = {"width": 640, "height": 480, "anchor_x": 0, "anchor_y": 0}
	elif resource == 25 and chunk == 24:
		logical = {"width": 233, "height": 410, "anchor_x": 0, "anchor_y": 0}
	elif resource == 25 and chunk in [11, 12, 13, 14]:
		logical = {"width": 160 if chunk == 11 else 159, "height": 71, "anchor_x": 0, "anchor_y": 0}
	elif resource == 25 and chunk >= 49:
		logical = {"width": 66, "height": 72, "anchor_x": 31, "anchor_y": 38}
	return {
		"edition": _edition,
		"archive": "Panel",
		"resource": resource,
		"chunk": chunk,
		"logical": logical,
	}


func _logical_for(frame: Dictionary, fallback: Vector2) -> Vector2:
	var logical: Variant = frame.get("logical", {})
	if not logical is Dictionary:
		return fallback
	var width := _metadata_integer(logical.get("width", null), 0)
	var height := _metadata_integer(logical.get("height", null), 0)
	if width <= 0 or height <= 0:
		return fallback
	return Vector2(float(width), float(height))


func _anchor_for(frame: Dictionary) -> Vector2:
	var logical: Variant = frame.get("logical", {})
	if not logical is Dictionary:
		return Vector2.ZERO
	var x := _metadata_integer(logical.get("anchor_x", 0), 0)
	var y := _metadata_integer(logical.get("anchor_y", 0), 0)
	return Vector2(float(x), float(y))


func _metadata_integer(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) != TYPE_FLOAT:
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
	if _edition.is_empty() or _kind not in ["dividend", "interest"]:
		return false
	var date_value: Variant = value.get("date", null)
	if not _valid_date(date_value):
		return false
	var players_value: Variant = value.get("players", null)
	if not _valid_players(players_value, _kind):
		return false
	if _kind == "dividend":
		var companies_value: Variant = value.get("companies", null)
		if not companies_value is Array or companies_value.size() > MAX_COMPANIES:
			return false
		var company_ids: Array = []
		for company_value in companies_value:
			if not company_value is Dictionary:
				return false
			if not _is_integer(company_value.get("company_id", null)) or not _valid_name(company_value.get("name", null)):
				return false
			if not _is_integer(company_value.get("monthly_profit", null)):
				return false
			var payouts_value: Variant = company_value.get("payouts", null)
			if not payouts_value is Array or payouts_value.size() != players_value.size():
				return false
			for payout in payouts_value:
				if not _is_integer(payout):
					return false
			var company_id := int(company_value["company_id"])
			if company_id in company_ids:
				return false
			company_ids.append(company_id)
	return true


func _valid_players(value: Variant, kind: String) -> bool:
	if not value is Array or value.size() < 1 or value.size() > MAX_PLAYERS:
		return false
	var ids: Array = []
	var characters: Array = []
	for player_value in value:
		if not player_value is Dictionary or not _is_integer(player_value.get("id", null)) or not _valid_name(player_value.get("name", null)):
			return false
		if not _is_integer(player_value.get("character_id", null)):
			return false
		var player_id := int(player_value["id"])
		var character_id := int(player_value["character_id"])
		if player_id in ids or character_id in characters or character_id < 0 or character_id > 11:
			return false
		ids.append(player_id)
		characters.append(character_id)
		if kind == "dividend":
			if not _is_integer(player_value.get("total", null)):
				return false
		else:
			if not _is_integer(player_value.get("deposit_before", null)) or not _is_integer(player_value.get("interest", null)):
				return false
			if int(player_value["interest"]) < 0 or typeof(player_value.get("loan_active", null)) != TYPE_BOOL:
				return false
	return true


func _valid_date(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var year: Variant = value.get("year", null)
	var month: Variant = value.get("month", null)
	var day: Variant = value.get("day", null)
	return _is_integer(year) and _is_integer(month) and _is_integer(day) and int(year) > 0 and int(month) >= 1 and int(month) <= 12 and int(day) >= 1 and int(day) <= 31


func _valid_name(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not str(value).strip_edges().is_empty()


func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT


func _interest_anchors(player_count: int) -> Array:
	var anchors: Variant = INTEREST_ANCHORS.get(player_count, [])
	return anchors.duplicate() if anchors is Array else []


func _configure_timer() -> void:
	if _timer == null or not is_instance_valid(_timer):
		return
	_stop_timer()
	if not _model_valid or not _is_open or _kind != "dividend" or auto_advance_seconds <= 0.0:
		return
	_timer.wait_time = auto_advance_seconds
	_timer.start()


func _stop_timer() -> void:
	if _timer != null and is_instance_valid(_timer):
		_timer.stop()


func _currency(value: int) -> String:
	return "$" + _format_number(value)


func _format_number(value: int) -> String:
	var sign := "-" if value < 0 else ""
	var digits := str(absi(value))
	var groups: Array[String] = []
	while digits.length() > 3:
		groups.push_front(digits.substr(digits.length() - 3, 3))
		digits = digits.substr(0, digits.length() - 3)
	groups.push_front(digits)
	var result := ""
	for index in range(groups.size()):
		if index > 0:
			result += ","
		result += groups[index]
	return sign + result
