extends Control
class_name RichmanSourceSetupPanel

## The original game's 640x480 new-game setup surface.
##
## The jump archive owns the opaque map background and the two setup atlas
## frames. Controls are hit areas over those source frames, so the normal
## player flow does not invent a second card or a diagnostics header. A
## private scene manifest is optional while developing; when it is absent,
## the same source geometry remains available with a quiet fallback.

const OriginalVisuals = preload("res://game/platform/original_visuals.gd")
const GameCalendar = preload("res://game/core/game_calendar.gd")

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const SOURCE_TOP_RECT := Rect2(8.0, 8.0, 440.0, 155.0)
const SOURCE_SIDE_RECT := Rect2(448.0, 8.0, 192.0, 461.0)
const SOURCE_MAP_RECT := Rect2(14.0, 173.0, 436.0, 321.0)
const SOURCE_PORTRAIT_ORIGIN := Vector2(14.0, 20.0)
const SOURCE_MAP_BUTTON_RECT := Rect2(461.0, 35.0, 171.0, 33.0)
const SOURCE_OK_RECT := Rect2(462.0, 182.0, 76.0, 38.0)
const SOURCE_EXIT_RECT := Rect2(547.0, 182.0, 82.0, 38.0)
const SOURCE_SETTING_X := 534.0
const SOURCE_SETTING_WIDTH := 93.0
const SOURCE_SETTING_Y := [228.0, 263.0, 298.0, 333.0, 368.0, 403.0]
const SOURCE_PREVIEW_ANCHOR := Vector2(414.0, 464.0)

const CHARACTER_NAMES := [
	"約翰喬", "沙隆巴斯", "忍太郎", "錢夫人", "阿土伯", "莎拉公主",
	"宮本寶藏", "糖糖", "烏咪", "孫小美", "小丹尼", "金貝貝",
]
const MAP_NAMES := ["TAIWAN", "CHINA", "JAPAN", "U.S.A"]
const MJ_MAP_NAMES := ["STAR", "ANCIENT", "DINOSAUR", "ISLAND"]
const SOURCE_MAP_LABEL_RECT := Rect2(475.0, 34.0, 126.0, 30.0)
const SOURCE_MAP_CHECK_POSITION := Vector2(611.0, 43.0)
const SOURCE_SETTING_LABELS := ["遊戲人數", "總資金", "行進方式", "土地權限", "遊戲時間", "勝利條件"]
const FUNDS := [300000, 200000, 100000, 50000, 30000, 10000]
const DAYS := [0, 730, 365, 182, 91, 30]
const WEALTH := [0, 100, 50, 10, 5, 3]
const VEHICLES := ["walking", "motorcycle", "car"]
const LAND_TENURE := [0, 1, 3, 6, 12, 24]
const EDITIONS := ["Game", "MultiverseJourney"]
const SETUP_RESOURCE := {"Game": 4, "MultiverseJourney": 8}
const PREVIEW_RESOURCE_BASE := {"Game": 5, "MultiverseJourney": 9}

signal confirmed(options: Dictionary, map_definition: Dictionary)
signal cancelled

var _visuals = OriginalVisuals.new()
var _catalog: Array = []
var _selected_map: Dictionary = {}
var _map_buttons: Array[Button] = []
var _edition_buttons: Array[Button] = []
var _portrait_buttons: Array[Button] = []
var _player_slot_buttons: Array[Button] = []
var _player_type_buttons: Array[Button] = []
var _map_labels: Array[Label] = []
var _map_checks: Array[TextureRect] = []
var _setting_labels: Array[Label] = []
var _character_ids: Array = [0, 1, 2, 3]
var _player_ai: Array = [false, true, true, true]
var _active_player := 0
var _player_count := 4
var _edition := "Game"
var _stage := 0
var _setup_atlas_offset := 1

var _map_background: TextureRect
var _setup_top_art: TextureRect
var _setup_side_art: TextureRect
var _character_preview: TextureRect
var _map_preview: TextureRect
var _map_caption: Label
var _stage_option: OptionButton
var _error: Label
var _funds: OptionButton
var _days: OptionButton
var _wealth: OptionButton
var _vehicle: OptionButton
var _land_tenure: OptionButton
var _count: OptionButton
var _year: SpinBox
var _month: SpinBox
var _day: SpinBox
var _has_setup_atlas := false

func _ready() -> void:
	position = Vector2.ZERO
	size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_surface()
	hide()

func set_catalog(catalog: Array, selected_definition: Dictionary = {}, defaults: Dictionary = {}) -> void:
	_catalog = catalog.duplicate(true)
	_selected_map = selected_definition.duplicate(true)
	_set_edition_from_definition(_selected_map)
	_set_stage_from_definition(_selected_map)
	if _selected_map.is_empty():
		for value in _catalog:
			if value is Dictionary and _definition_edition(value) in EDITIONS:
				_selected_map = value.duplicate(true)
				_set_edition_from_definition(_selected_map)
				_set_stage_from_definition(_selected_map)
				break
	_apply_defaults(defaults)
	_rebuild_maps()
	_refresh_source_art()
	_update_portraits()
	_update_character_preview()

func collect_options() -> Dictionary:
	if _count == null:
		return {"ok": false, "message": "開局設定尚未載入。"}
	var ids: Array = _character_ids.slice(0, _player_count)
	var seen: Dictionary = {}
	for value in ids:
		if seen.has(int(value)):
			return {"ok": false, "message": "每位玩家必須選擇不同角色。"}
		seen[int(value)] = true
	var date := {"year": int(_year.value), "month": int(_month.value), "day": int(_day.value)}
	if not GameCalendar.is_valid(date):
		return {"ok": false, "message": "起始日期不存在，請檢查年月日。"}
	var humans := 0
	for index in range(_player_count):
		if not bool(_player_ai[index]):
			humans += 1
	if humans == 0:
		return {"ok": false, "message": "至少需要一位真人玩家。"}
	if _land_tenure != null and _land_tenure.get_selected_id() != 0:
		return {"ok": false, "message": "土地期限功能尚未由核心支援；請選擇無限期。"}
	if _selected_map.is_empty():
		return {"ok": false, "message": "尚未選擇可用地圖。"}
	return {"ok": true, "options": {
		"initial_fund": _funds.get_selected_id(),
		"day_limit": _days.get_selected_id(),
		"wealth_multiplier": _wealth.get_selected_id(),
		"start_date": date,
		"character_ids": ids,
		"human_flags": _human_flags(),
		"initial_vehicle": VEHICLES[_vehicle.selected] if _vehicle != null and _vehicle.selected >= 0 and _vehicle.selected < VEHICLES.size() else "walking",
		"land_tenure_months": _land_tenure.get_selected_id() if _land_tenure != null else 0,
	}}

func cancel() -> void:
	cancelled.emit()
	hide()

## The source-stage offset is retained for acceptance readback. Game uses
## chunk 1; MJ stage 1 uses chunk 21 in the setup atlas.
func get_setup_atlas_offset() -> int:
	return _setup_atlas_offset

func get_stage() -> int:
	return _stage

func get_map_background_resource() -> int:
	return _map_resource_index()

func _build_surface() -> void:
	# The source raw background is a complete 640x480 surface. It is drawn
	# first, followed by the two setup atlas frames and transparent hit areas.
	_map_background = TextureRect.new()
	_map_background.name = "SourceMapBackground"
	_map_background.position = Vector2.ZERO
	_map_background.size = REFERENCE_SIZE
	_map_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_background.stretch_mode = TextureRect.STRETCH_SCALE
	_map_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map_background)
	var fallback := ColorRect.new()
	fallback.name = "SourceMapFallback"
	fallback.position = SOURCE_MAP_RECT.position
	fallback.size = SOURCE_MAP_RECT.size
	fallback.color = Color("#1e3651")
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fallback)
	_map_preview = TextureRect.new()
	_map_preview.name = "SourceMapPreview"
	_map_preview.position = SOURCE_MAP_RECT.position
	_map_preview.size = SOURCE_MAP_RECT.size
	_map_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map_preview)
	_character_preview = TextureRect.new()
	_character_preview.name = "SourceCharacterVehiclePreview"
	_character_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_character_preview.stretch_mode = TextureRect.STRETCH_SCALE
	_character_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_character_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_character_preview)

	_setup_top_art = _art("SourcePortraitFrame", SOURCE_TOP_RECT)
	_setup_side_art = _art("SourceSettingsFrame", SOURCE_SIDE_RECT)
	add_child(_setup_top_art)
	add_child(_setup_side_art)

	var portraits := Control.new()
	portraits.name = "CharacterPortraits"
	portraits.position = Vector2.ZERO
	portraits.size = SOURCE_TOP_RECT.size
	portraits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portraits)
	for index in range(12):
		var button := _hit_button("CharacterPortrait_%d" % index)
		button.position = SOURCE_PORTRAIT_ORIGIN + Vector2(float(index % 6) * 72.0, float(index / 6) * 72.0)
		button.size = Vector2(72.0, 72.0)
		button.tooltip_text = CHARACTER_NAMES[index]
		button.pressed.connect(_select_character.bind(index))
		portraits.add_child(button)
		_portrait_buttons.append(button)

	# PlayerSlot is a source-compatible transparent hit area over each portrait.
	# The source frame has no extra row of labels; state remains available via
	# tooltips and the setup API instead of an invented panel.
	var players := Control.new()
	players.name = "PlayerSlots"
	players.position = Vector2.ZERO
	players.size = SOURCE_TOP_RECT.size
	players.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(players)
	for index in range(4):
		var slot := _hit_button("PlayerSlot_%d" % index)
		slot.position = Vector2(14.0 + float(index) * 106.0, 458.0)
		slot.size = Vector2(96.0, 17.0)
		slot.tooltip_text = "玩家 %d：點擊選取，PlayerType 可切換真人／AI" % (index + 1)
		slot.pressed.connect(_select_player.bind(index))
		players.add_child(slot)
		_player_slot_buttons.append(slot)
		var type_button := _hit_button("PlayerType_%d" % index)
		type_button.position = Vector2(14.0 + float(index) * 106.0, 477.0)
		type_button.size = Vector2(96.0, 10.0)
		type_button.tooltip_text = "玩家 %d：真人" % (index + 1)
		type_button.pressed.connect(_toggle_player_type.bind(index))
		players.add_child(type_button)
		_player_type_buttons.append(type_button)

	# Edition and map buttons sit on the baked right-side map list. Their text
	# is only visible when the private source frame is unavailable.
	for index in range(2):
		var edition_button := _hit_button("MapEdition_Game" if index == 0 else "MapEdition_MJ")
		edition_button.position = Vector2(458.0, 9.0 + float(index) * 18.0)
		edition_button.size = Vector2(86.0, 17.0)
		edition_button.tooltip_text = "Game" if index == 0 else "MultiverseJourney"
		edition_button.pressed.connect(_select_edition.bind("Game" if index == 0 else "MultiverseJourney"))
		add_child(edition_button)
		_edition_buttons.append(edition_button)

	# MJ has two four-map stages. This compact selector uses an otherwise quiet
	# edge of the side frame while the map list remains four source labels.
	_stage_option = _source_option("MapStage", Vector2(548.0, 9.0), Vector2(82.0, 17.0))
	_stage_option.add_item("STAGE 1", 0)
	_stage_option.add_item("STAGE 2", 1)
	_stage_option.item_selected.connect(func(_i: int) -> void:
		_select_stage(_stage_option.get_selected_id())
	)
	_stage_option.tooltip_text = "MultiverseJourney stage"

	for index in range(4):
		var button := _hit_button("MapChoice_%d" % index)
		button.position = Vector2(SOURCE_MAP_BUTTON_RECT.position.x, SOURCE_MAP_BUTTON_RECT.position.y + float(index) * 34.0)
		button.size = SOURCE_MAP_BUTTON_RECT.size
		button.pressed.connect(_select_map.bind(index))
		add_child(button)
		_map_buttons.append(button)
		var map_label := _label("", 17, Color("#d73550"))
		map_label.name = "MapChoiceLabel_%d" % index
		map_label.position = SOURCE_MAP_LABEL_RECT.position + Vector2(0.0, float(index) * 34.0)
		map_label.size = SOURCE_MAP_LABEL_RECT.size
		map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		map_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		map_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_label.add_theme_constant_override("outline_size", 1)
		map_label.add_theme_color_override("font_outline_color", Color("#6c2632"))
		add_child(map_label)
		_map_labels.append(map_label)
		var map_check := TextureRect.new()
		map_check.name = "MapChoiceCheck_%d" % index
		map_check.position = SOURCE_MAP_CHECK_POSITION + Vector2(0.0, float(index) * 34.0)
		map_check.size = Vector2(16.0, 16.0)
		map_check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		map_check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		map_check.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		map_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_check.visible = false
		add_child(map_check)
		_map_checks.append(map_check)
	for index in range(SOURCE_SETTING_LABELS.size()):
		var setting_label := _label(SOURCE_SETTING_LABELS[index], 14, Color("#f4f0dd"))
		setting_label.name = "SourceSettingLabel_%d" % index
		setting_label.position = Vector2(SOURCE_SIDE_RECT.position.x + 5.0, SOURCE_SETTING_Y[index] - 1.0)
		setting_label.size = Vector2(77.0, 30.0)
		setting_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		setting_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		setting_label.add_theme_constant_override("outline_size", 2)
		setting_label.add_theme_color_override("font_outline_color", Color("#1d3150"))
		_setting_labels.append(setting_label)
		add_child(setting_label)

	var ok := _hit_button("OK")
	ok.position = SOURCE_OK_RECT.position
	ok.size = SOURCE_OK_RECT.size
	ok.pressed.connect(_confirm)
	add_child(ok)
	var exit := _hit_button("EXIT")
	exit.position = SOURCE_EXIT_RECT.position
	exit.size = SOURCE_EXIT_RECT.size
	exit.pressed.connect(cancel)
	add_child(exit)

	_funds = _source_option("InitialFund", Vector2(SOURCE_SETTING_X, SOURCE_SETTING_Y[1]), Vector2(SOURCE_SETTING_WIDTH, 30.0))
	for value in FUNDS:
		_funds.add_item(str(value), value)
	_days = _source_option("DayLimit", Vector2(SOURCE_SETTING_X, SOURCE_SETTING_Y[4]), Vector2(SOURCE_SETTING_WIDTH, 30.0))
	for index in range(DAYS.size()):
		_days.add_item(["不限", "兩年", "一年", "半年", "三個月", "一個月"][index], DAYS[index])
	_wealth = _source_option("WealthTarget", Vector2(SOURCE_SETTING_X, SOURCE_SETTING_Y[5]), Vector2(SOURCE_SETTING_WIDTH, 30.0))
	for index in range(WEALTH.size()):
		_wealth.add_item("無限" if index == 0 else "%d倍" % WEALTH[index], WEALTH[index])
	_vehicle = _source_option("InitialVehicle", Vector2(SOURCE_SETTING_X, SOURCE_SETTING_Y[2]), Vector2(SOURCE_SETTING_WIDTH, 30.0))
	for index in range(VEHICLES.size()):
		_vehicle.add_item(["步行", "機車", "汽車"][index], index)
	_land_tenure = _source_option("LandTenure", Vector2(SOURCE_SETTING_X, SOURCE_SETTING_Y[3]), Vector2(SOURCE_SETTING_WIDTH, 30.0))
	_land_tenure.add_item("無限期", 0)
	for index in range(1, LAND_TENURE.size()):
		_land_tenure.add_item("%d月" % LAND_TENURE[index], LAND_TENURE[index])
		_land_tenure.set_item_disabled(index, true)
	_land_tenure.tooltip_text = "土地期限：核心功能待接入，目前僅支援無限期。"
	_count = _source_option("PlayerCount", Vector2(SOURCE_SETTING_X, SOURCE_SETTING_Y[0]), Vector2(SOURCE_SETTING_WIDTH, 30.0))
	for value in [2, 3, 4]:
		_count.add_item("%d人" % value, value)
	_count.item_selected.connect(func(_i: int) -> void:
		_player_count = _count.get_selected_id()
		_active_player = clampi(_active_player, 0, _player_count - 1)
		_update_portraits()
		_update_character_preview()
	)

	# Date is part of the existing setup contract, but the source frame does
	# not show separate date widgets. Keep these controls off-screen so restart
	# and default round trips preserve the selected date.
	_year = _spin("StartYear", 1998, 9999, 1998)
	_month = _spin("StartMonth", 1, 12, 1)
	_day = _spin("StartDay", 1, 31, 1)
	var hidden_settings := Control.new()
	hidden_settings.name = "SourceDateControls"
	hidden_settings.position = Vector2(-1000.0, -1000.0)
	hidden_settings.size = Vector2(1.0, 1.0)
	hidden_settings.visible = false
	add_child(hidden_settings)
	hidden_settings.add_child(_year)
	hidden_settings.add_child(_month)
	hidden_settings.add_child(_day)

	_map_caption = _label("", 8, Color.WHITE)
	_map_caption.name = "SourceMapCaption"
	_map_caption.visible = false
	add_child(_map_caption)
	_error = _label("", 10, Color("#ffcdc2"))
	_error.name = "SourceSetupError"
	_error.position = Vector2(456.0, 453.0)
	_error.size = Vector2(176.0, 16.0)
	_error.clip_text = true
	_error.visible = false
	add_child(_error)
	_update_fallback_text()

func _art(node_name: String, rect: Rect2) -> TextureRect:
	var art := TextureRect.new()
	art.name = node_name
	art.position = rect.position
	art.size = rect.size
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art

func _hit_button(node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 0.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 0.0))
	button.add_theme_stylebox_override("normal", _empty_style())
	button.add_theme_stylebox_override("hover", _empty_style())
	button.add_theme_stylebox_override("pressed", _empty_style())
	button.add_theme_stylebox_override("focus", _empty_style())
	button.add_theme_stylebox_override("disabled", _empty_style())
	return button

func _source_option(node_name: String, at: Vector2, control_size: Vector2) -> OptionButton:
	var option := OptionButton.new()
	option.name = node_name
	option.position = at
	option.size = control_size
	option.flat = true
	option.alignment = HORIZONTAL_ALIGNMENT_CENTER
	option.focus_mode = Control.FOCUS_NONE
	option.add_theme_font_size_override("font_size", 14)
	option.add_theme_color_override("font_color", Color("#172025"))
	option.add_theme_color_override("font_hover_color", Color("#172025"))
	option.add_theme_color_override("font_pressed_color", Color("#172025"))
	option.add_theme_color_override("font_disabled_color", Color("#172025"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		option.add_theme_stylebox_override(state, _empty_style())
	add_child(option)
	return option

func _empty_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_border_width_all(0)
	return style

func _spin(node_name: String, minimum: int, maximum: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = node_name
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = value
	spin.allow_greater = false
	spin.allow_lesser = false
	return spin

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _definition_edition(definition: Dictionary) -> String:
	var source: Variant = definition.get("source", {})
	if source is Dictionary:
		return str(source.get("edition", definition.get("edition", "Game")))
	return str(definition.get("edition", "Game"))

func _definition_map_number(definition: Dictionary) -> int:
	var source: Variant = definition.get("source", {})
	if source is Dictionary:
		return int(source.get("map_number", definition.get("map_number", 0)))
	return int(definition.get("map_number", 0))

func _set_edition_from_definition(definition: Dictionary) -> void:
	var edition := _definition_edition(definition)
	if edition in EDITIONS:
		_edition = edition

func _set_stage_from_definition(definition: Dictionary) -> void:
	var number := _definition_map_number(definition)
	if _edition == "MultiverseJourney" and number >= 5:
		_stage = 1
	else:
		_stage = 0
	_setup_atlas_offset = _stage * 20 + 1

func _apply_defaults(defaults: Dictionary) -> void:
	var count := int(defaults.get("player_count", defaults.get("character_ids", []).size()))
	if count >= 2 and count <= 4:
		_player_count = count
	var ids: Variant = defaults.get("character_ids", [])
	if ids is Array:
		for index in range(mini(ids.size(), 4)):
			_character_ids[index] = clampi(int(ids[index]), 0, 11)
	var types: Variant = defaults.get("human_flags", [])
	if types is Array:
		for index in range(mini(types.size(), 4)):
			_player_ai[index] = not bool(types[index])
	if _count != null:
		_select_option(_count, _player_count)
	if _funds != null:
		_select_option(_funds, int(defaults.get("initial_fund", 200000)))
	if _days != null:
		_select_option(_days, int(defaults.get("day_limit", 0)))
	if _wealth != null:
		_select_option(_wealth, int(defaults.get("wealth_multiplier", 0)))
	if _vehicle != null:
		_select_vehicle(str(defaults.get("initial_vehicle", "walking")))
	if _land_tenure != null:
		_select_option(_land_tenure, int(defaults.get("land_tenure_months", 0)))
	var date: Variant = defaults.get("start_date", {})
	if date is Dictionary and GameCalendar.is_valid(date):
		_year.value = int(date.get("year", 1998))
		_month.value = int(date.get("month", 1))
		_day.value = int(date.get("day", 1))

func _select_option(option: OptionButton, value: Variant) -> bool:
	for index in range(option.item_count):
		if value is String:
			if option.get_item_text(index) == str(value):
				option.select(index)
				return true
		elif option.get_item_id(index) == int(value):
			option.select(index)
			return true
	return false

func _select_vehicle(value: String) -> void:
	var index := VEHICLES.find(value)
	_vehicle.select(index if index >= 0 else 0)

func _edition_maps() -> Array:
	var result: Array = []
	var first := _stage * 4 + 1 if _edition == "MultiverseJourney" else 1
	var last := first + 3
	for value in _catalog:
		if not value is Dictionary or _definition_edition(value) != _edition:
			continue
		var number := _definition_map_number(value)
		if number >= first and number <= last:
			result.append(value)
	# Focused tests may supply a selected definition outside catalog storage.
	# Keep it usable only when its edition and stage are source-valid.
	if result.is_empty() and not _selected_map.is_empty() and _definition_edition(_selected_map) == _edition:
		var selected_number := _definition_map_number(_selected_map)
		if selected_number >= first and selected_number <= last:
			result.append(_selected_map.duplicate(true))
	return result

func _rebuild_maps() -> void:
	_setup_atlas_offset = _stage * 20 + 1
	var valid := _edition_maps()
	var selected_is_valid := false
	for definition in valid:
		if str(definition.get("id", "")) == str(_selected_map.get("id", "")):
			selected_is_valid = true
			break
	if not selected_is_valid and not valid.is_empty():
		_selected_map = valid[0].duplicate(true)
	for index in range(_map_buttons.size()):
		var button := _map_buttons[index]
		button.disabled = index >= valid.size()
		if index < valid.size():
			var definition: Dictionary = valid[index]
			button.tooltip_text = _map_name(definition, index)
			button.text = _map_name(definition, index) if not _has_setup_atlas else ""
			button.button_pressed = str(definition.get("id", "")) == str(_selected_map.get("id", ""))
		else:
			var names := MJ_MAP_NAMES if _edition == "MultiverseJourney" else MAP_NAMES
			button.text = names[index]
			button.tooltip_text = ""
	for index in range(_edition_buttons.size()):
		_edition_buttons[index].disabled = (_edition == "Game" and index == 0) or (_edition == "MultiverseJourney" and index == 1)
	if _stage_option != null:
		_stage_option.disabled = _edition != "MultiverseJourney"
		_stage_option.visible = _edition == "MultiverseJourney" or not _has_setup_atlas
		_stage_option.select(_stage)
	_update_fallback_text()

func _map_name(definition: Dictionary, index: int) -> String:
	var number := _definition_map_number(definition)
	var names := MJ_MAP_NAMES if _definition_edition(definition) == "MultiverseJourney" else MAP_NAMES
	var local_index := number - 1
	if _edition == "MultiverseJourney":
		local_index = posmod(number - 1, 4)
	return names[clampi(local_index if number > 0 else index, 0, names.size() - 1)]

func _select_map(index: int) -> void:
	var valid := _edition_maps()
	if index < 0 or index >= valid.size():
		return
	_selected_map = valid[index].duplicate(true)
	_set_stage_from_definition(_selected_map)
	_refresh_source_art()
	_update_character_preview()

func _select_edition(edition: String) -> void:
	if edition not in EDITIONS:
		return
	_edition = edition
	if edition == "Game":
		_stage = 0
	else:
		_set_stage_from_definition(_selected_map)
	_rebuild_maps()
	_refresh_source_art()
	_update_portraits()
	_update_character_preview()

func _select_stage(stage: int) -> void:
	_stage = clampi(stage, 0, 1)
	_setup_atlas_offset = _stage * 20 + 1
	_rebuild_maps()
	_refresh_source_art()

func _select_player(index: int) -> void:
	if index < 0 or index >= _player_count:
		return
	_active_player = index
	_update_portraits()
	_update_character_preview()

func _select_character(index: int) -> void:
	if _active_player >= _player_count or index < 0 or index >= CHARACTER_NAMES.size():
		return
	if _character_ids.slice(0, _player_count).has(index):
		for player in range(_player_count):
			if _character_ids[player] == index:
				_character_ids[player] = _character_ids[_active_player]
	_character_ids[_active_player] = index
	_update_portraits()
	_update_character_preview()

func _toggle_player_type(index: int) -> void:
	if index < 0 or index >= _player_count:
		return
	_player_ai[index] = not _player_ai[index]
	_update_portraits()

func _human_flags() -> Array:
	var result: Array = []
	for index in range(_player_count):
		result.append(not _player_ai[index])
	return result

func _ui_frame(resource: int, chunk: int) -> Dictionary:
	return _visuals.ui(_edition, "jump", resource, chunk)

func _find_setup_frame(top: bool) -> Dictionary:
	var resource := int(SETUP_RESOURCE.get(_edition, 4))
	var preferred := _stage * 20 + (0 if top else 1)
	var candidates := [preferred, 0 if top else 1]
	for chunk in candidates:
		var frame := _ui_frame(resource, chunk)
		if frame.is_empty():
			continue
		var logical: Dictionary = frame.get("logical", {})
		var width := int(logical.get("width", 0))
		var height := int(logical.get("height", 0))
		if top and width >= 400 and height <= 200:
			return frame
		if not top and width <= 220 and height >= 400:
			return frame
	return {}

func _map_resource_index() -> int:
	if _edition == "MultiverseJourney":
		var number := _definition_map_number(_selected_map)
		if number > 0:
			return clampi(number - 1, 0, 7)
		return _stage * 4
	var game_number := _definition_map_number(_selected_map)
	return clampi(game_number - 1, 0, 3) if game_number > 0 else 0

func _refresh_source_art() -> void:
	if _map_background == null:
		return
	var map_frame := _ui_frame(_map_resource_index(), 0)
	var map_texture := _visuals.texture(map_frame)
	_map_background.texture = map_texture
	_map_background.visible = map_texture != null
	if map_texture == null:
		var scene := _visuals.scene_for(_selected_map)
		_map_preview.texture = _visuals.texture(scene.get("image", {})) if not scene.is_empty() else null
		_map_preview.visible = _map_preview.texture != null
	else:
		_map_preview.texture = null
		_map_preview.visible = false
	var top_frame := _find_setup_frame(true)
	var side_frame := _find_setup_frame(false)
	_setup_top_art.texture = _visuals.texture(top_frame)
	_setup_side_art.texture = _visuals.texture(side_frame)
	_setup_top_art.visible = _setup_top_art.texture != null
	_setup_side_art.visible = _setup_side_art.texture != null
	_has_setup_atlas = _setup_top_art.visible and _setup_side_art.visible
	var map_check_frame := _ui_frame(int(SETUP_RESOURCE.get(_edition, 4)), 7)
	var map_check_texture := _visuals.texture(map_check_frame)
	for map_check in _map_checks:
		map_check.texture = map_check_texture
	_update_fallback_text()
	_rebuild_maps_text_only()

func _update_preview() -> void:
	# Preserve the focused panel API used by earlier setup tests and callers.
	_refresh_source_art()

func _rebuild_maps_text_only() -> void:
	var valid := _edition_maps()
	for index in range(_map_buttons.size()):
		if index < valid.size():
			_map_buttons[index].text = "" if _has_setup_atlas else _map_name(valid[index], index)
			_map_labels[index].text = _map_name(valid[index], index)
			_map_labels[index].visible = _has_setup_atlas
			_map_checks[index].visible = _has_setup_atlas and str(valid[index].get("id", "")) == str(_selected_map.get("id", ""))
		else:
			var names := MJ_MAP_NAMES if _edition == "MultiverseJourney" else MAP_NAMES
			_map_buttons[index].text = names[index]
			_map_labels[index].text = names[index]
			_map_labels[index].visible = false
			_map_checks[index].visible = false
	var ok := get_node_or_null("OK") as Button
	var exit := get_node_or_null("EXIT") as Button
	if ok != null:
		ok.text = "" if _setup_side_art.visible else "OK"
	if exit != null:
		exit.text = "" if _setup_side_art.visible else "EXIT"

func _update_fallback_text() -> void:
	if _stage_option != null:
		_stage_option.text = "STAGE %d" % (_stage + 1) if _edition == "MultiverseJourney" else ""
	if _map_caption != null:
		_map_caption.text = _map_name(_selected_map, 0) if not _selected_map.is_empty() else ""

func _update_portraits() -> void:
	for index in range(_portrait_buttons.size()):
		var button := _portrait_buttons[index]
		var frame := _visuals.ui(_edition, "Data", 2, index)
		var texture := _visuals.texture(frame)
		# The setup atlas supplies the coloured portrait slots; Data/2 supplies
		# the character sprite that sits inside each slot.
		button.icon = texture
		var player_number := _character_ids.find(index) + 1 if index in _character_ids.slice(0, _player_count) else 0
		button.tooltip_text = "%s · 玩家 %d%s" % [CHARACTER_NAMES[index], player_number, "（目前選取）" if index == _character_ids[_active_player] else ""]
		button.disabled = false
	for index in range(_player_slot_buttons.size()):
		_player_slot_buttons[index].disabled = index >= _player_count
	for index in range(_player_type_buttons.size()):
		var button := _player_type_buttons[index]
		button.disabled = index >= _player_count
		button.tooltip_text = "玩家 %d：%s" % [index + 1, "AI" if _player_ai[index] else "真人"]

func _update_character_preview() -> void:
	if _character_preview == null:
		return
	var character_id := clampi(int(_character_ids[_active_player]), 0, 11)
	var vehicle_index := _vehicle.selected if _vehicle != null else 0
	var base := int(PREVIEW_RESOURCE_BASE.get(_edition, 5))
	var resource := base + character_id * 3 + clampi(vehicle_index, 0, 2)
	var frame := _ui_frame(resource, 0)
	var texture := _visuals.texture(frame)
	if texture != null:
		var logical: Dictionary = frame.get("logical", {})
		_character_preview.texture = texture
		_character_preview.position = SOURCE_PREVIEW_ANCHOR - Vector2(float(logical.get("anchor_x", 0)), float(logical.get("anchor_y", 0)))
		_character_preview.size = Vector2(float(logical.get("width", texture.get_width())), float(logical.get("height", texture.get_height())))
		_character_preview.visible = true
		return
	var fallback_frame := _visuals.character(_edition, character_id, 0)
	var fallback_texture := _visuals.texture(fallback_frame)
	_character_preview.texture = fallback_texture
	if fallback_texture != null:
		var logical: Dictionary = fallback_frame.get("logical", {})
		_character_preview.position = SOURCE_PREVIEW_ANCHOR - Vector2(float(logical.get("anchor_x", 0)), float(logical.get("anchor_y", 0)))
		_character_preview.size = Vector2(float(logical.get("width", fallback_texture.get_width())), float(logical.get("height", fallback_texture.get_height())))
	_character_preview.visible = fallback_texture != null

func _confirm() -> void:
	var result := collect_options()
	if not bool(result.get("ok", false)):
		_error.text = str(result.get("message", "開局設定無效。"))
		_error.visible = true
		return
	_error.text = ""
	_error.visible = false
	confirmed.emit(result["options"], _selected_map.duplicate(true))
