extends Control
class_name RichmanSourceSetupPanel

## The source game's 640x480 new-game setup surface.
##
## This control only collects choices.  MainUI remains the owner of the
## simulation and validates the selected map before creating a match.

const OriginalVisuals = preload("res://game/platform/original_visuals.gd")
const GameCalendar = preload("res://game/core/game_calendar.gd")
const REFERENCE_SIZE := Vector2(640.0, 480.0)
const CHARACTER_NAMES := [
	"約翰喬", "沙隆巴斯", "忍太郎", "錢夫人", "阿土伯", "莎拉公主",
	"宮本寶藏", "糖糖", "烏咪", "孫小美", "小丹尼", "金貝貝",
]
const MAP_NAMES := ["TAIWAN", "CHINA", "JAPAN", "USA"]
const MJ_MAP_NAMES := ["STAR", "ANCIENT", "DINOSAUR", "ISLAND"]
const FUNDS := [300000, 200000, 100000, 50000, 30000, 10000]
const DAYS := [0, 730, 365, 182, 91, 30]
const WEALTH := [0, 100, 50, 10, 5, 3]
const VEHICLES := ["walking", "motorcycle", "car"]
const LAND_TENURE := [0, 1, 3, 6, 12, 24]
const BG := Color("#152f3a")
const CARD := Color("#d7e4d2")
const INK := Color("#1c2b2b")
const GOLD := Color("#e6bf69")

signal confirmed(options: Dictionary, map_definition: Dictionary)
signal cancelled

var _visuals = OriginalVisuals.new()
var _catalog: Array = []
var _selected_map: Dictionary = {}
var _map_buttons: Array[Button] = []
var _edition_buttons: Array[Button] = []
var _portrait_buttons: Array[Button] = []
var _player_type_buttons: Array[Button] = []
var _character_ids: Array = [0, 1, 2, 3]
var _player_ai: Array = [false, true, true, true]
var _active_player := 0
var _player_count := 4
var _edition := "Game"
var _map_preview: TextureRect
var _map_caption: Label
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

func _ready() -> void:
	position = Vector2.ZERO
	size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	_build_surface()
	hide()

func set_catalog(catalog: Array, selected_definition: Dictionary = {}, defaults: Dictionary = {}) -> void:
	_catalog = catalog.duplicate(true)
	_selected_map = selected_definition.duplicate(true)
	var selected_source: Variant = _selected_map.get("source", {})
	if selected_source is Dictionary and str(selected_source.get("edition", "")) == "MultiverseJourney":
		_edition = "MultiverseJourney"
	if _selected_map.is_empty():
		for value in _catalog:
			if value is Dictionary:
				_selected_map = value.duplicate(true)
				break
	_apply_defaults(defaults)
	_rebuild_maps()
	_update_preview()
	_update_portraits()

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

func _build_surface() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var heading := _label("NEW GAME  ·  GAME SETUP", 18, GOLD)
	heading.position = Vector2(12, 8)
	heading.size = Vector2(616, 27)
	add_child(heading)
	var portraits := Control.new()
	portraits.name = "CharacterPortraits"
	portraits.position = Vector2(10, 40)
	portraits.size = Vector2(432, 142)
	add_child(portraits)
	for index in range(12):
		var button := Button.new()
		button.name = "CharacterPortrait_%d" % index
		button.position = Vector2(float(index % 6) * 72.0, float(index / 6) * 70.0)
		button.size = Vector2(68, 66)
		button.text = "%02d\n%s" % [index, CHARACTER_NAMES[index]]
		button.add_theme_font_size_override("font_size", 9)
		button.pressed.connect(_select_character.bind(index))
		portraits.add_child(button)
		_portrait_buttons.append(button)
	var players := Control.new()
	players.name = "PlayerSlots"
	players.position = Vector2(10, 190)
	players.size = Vector2(432, 96)
	add_child(players)
	for index in range(4):
		var slot := Button.new()
		slot.name = "PlayerSlot_%d" % index
		slot.position = Vector2(float(index % 2) * 216.0, float(index / 2) * 43.0)
		slot.size = Vector2(210, 38)
		slot.text = "P%d" % (index + 1)
		slot.add_theme_font_size_override("font_size", 11)
		slot.pressed.connect(_select_player.bind(index))
		players.add_child(slot)
		var type_button := Button.new()
		type_button.name = "PlayerType_%d" % index
		type_button.position = slot.position + Vector2(132, 4)
		type_button.size = Vector2(72, 30)
		type_button.add_theme_font_size_override("font_size", 9)
		type_button.pressed.connect(_toggle_player_type.bind(index))
		players.add_child(type_button)
		_player_type_buttons.append(type_button)
	var map_card := _panel("MapChoicePanel", Vector2(454, 40), Vector2(174, 246))
	add_child(map_card)
	var map_heading := _label("MAP", 12, INK)
	map_heading.position = Vector2(8, 7)
	map_heading.size = Vector2(158, 20)
	map_card.add_child(map_heading)
	for index in range(2):
		var edition_button := Button.new()
		edition_button.name = "MapEdition_Game" if index == 0 else "MapEdition_MJ"
		edition_button.text = "GAME" if index == 0 else "MJ"
		edition_button.position = Vector2(7.0 + float(index) * 80.0, 25.0)
		edition_button.size = Vector2(76, 22)
		edition_button.add_theme_font_size_override("font_size", 9)
		edition_button.pressed.connect(_select_edition.bind("Game" if index == 0 else "MultiverseJourney"))
		map_card.add_child(edition_button)
		_edition_buttons.append(edition_button)
	var map_list := VBoxContainer.new()
	map_list.name = "MapChoices"
	map_list.position = Vector2(7, 50)
	map_list.size = Vector2(160, 176)
	map_list.add_theme_constant_override("separation", 3)
	map_card.add_child(map_list)
	# Four stable choices are retained even when the private catalog is absent;
	# unavailable entries stay disabled and cannot be submitted.
	for index in range(4):
		var button := Button.new()
		button.name = "MapChoice_%d" % index
		button.custom_minimum_size = Vector2(0, 38)
		button.text = MAP_NAMES[index]
		button.add_theme_font_size_override("font_size", 10)
		button.pressed.connect(_select_map.bind(index))
		map_list.add_child(button)
		_map_buttons.append(button)
	_map_caption = _label("選擇地圖後顯示來源背景。", 9, INK)
	_map_caption.position = Vector2(7, 210)
	_map_caption.size = Vector2(160, 28)
	_map_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_card.add_child(_map_caption)
	_map_preview = TextureRect.new()
	_map_preview.name = "SourceMapPreview"
	_map_preview.position = Vector2(10, 292)
	_map_preview.size = Vector2(432, 138)
	_map_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_map_preview)
	var settings := _panel("Settings", Vector2(454, 292), Vector2(174, 174))
	add_child(settings)
	_count = _option(settings, "PlayerCount", "玩家", [2, 3, 4], 4, 0)
	_count.item_selected.connect(func(_i: int) -> void: _player_count = _count.get_selected_id(); _update_portraits())
	_funds = _option(settings, "InitialFund", "資金", FUNDS, 200000, 1)
	_days = _option(settings, "DayLimit", "時間", DAYS, 0, 2)
	_wealth = _option(settings, "WealthTarget", "目標", WEALTH, 0, 3)
	_vehicle = _option(settings, "InitialVehicle", "車輛", VEHICLES, "walking", 4)
	_vehicle.set_item_text(0, "步行")
	_vehicle.set_item_text(1, "機車")
	_vehicle.set_item_text(2, "汽車")
	_land_tenure = _option(settings, "LandTenure", "地權", LAND_TENURE, 0, 5)
	_land_tenure.set_item_text(0, "無限")
	for index in range(1, _land_tenure.item_count):
		_land_tenure.set_item_text(index, "%d月" % LAND_TENURE[index])
		_land_tenure.set_item_disabled(index, true)
	_land_tenure.tooltip_text = "土地期限：核心功能待接入，目前僅支援無限期。"
	_year = _spin(settings, "StartYear", 1998, 9999, 1998, Vector2(7, 126))
	_month = _spin(settings, "StartMonth", 1, 12, 1, Vector2(62, 126))
	_day = _spin(settings, "StartDay", 1, 31, 1, Vector2(117, 126))
	var pending := _label("土地期限：核心待接入（無限期）", 8, INK)
	pending.name = "LandTenurePending"
	pending.position = Vector2(7, 150)
	pending.size = Vector2(160, 18)
	settings.add_child(pending)
	_error = _label("", 9, Color("#b83d3d"))
	_error.position = Vector2(12, 436)
	_error.size = Vector2(420, 20)
	add_child(_error)
	var ok := Button.new()
	ok.name = "OK"
	ok.text = "OK"
	ok.position = Vector2(454, 436)
	ok.size = Vector2(80, 32)
	ok.pressed.connect(_confirm)
	add_child(ok)
	var exit := Button.new()
	exit.name = "EXIT"
	exit.text = "EXIT"
	exit.position = Vector2(546, 436)
	exit.size = Vector2(80, 32)
	exit.pressed.connect(cancel)
	add_child(exit)

func _panel(node_name: String, position: Vector2, panel_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = position
	panel.size = panel_size
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.border_color = GOLD
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _option(parent: Control, node_name: String, caption: String, values: Array, selected: Variant, row: int) -> OptionButton:
	var label := _label(caption, 9, INK)
	label.position = Vector2(7, 3 + row * 20)
	label.size = Vector2(38, 20)
	parent.add_child(label)
	var option := OptionButton.new()
	option.name = node_name
	option.position = Vector2(44, row * 20)
	option.size = Vector2(120, 23)
	option.add_theme_font_size_override("font_size", 9)
	for index in range(values.size()):
		var value = values[index]
		option.add_item(str(value), index)
		if value is int:
			option.set_item_id(index, int(value))
	if not _select_option(option, selected):
		option.select(0)
	parent.add_child(option)
	return option

func _spin(parent: Control, node_name: String, minimum: int, maximum: int, value: int, position: Vector2) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = node_name
	spin.position = position
	spin.size = Vector2(52, 22)
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = value
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.add_theme_font_size_override("font_size", 9)
	parent.add_child(spin)
	return spin

func _select_option(option: OptionButton, value: Variant) -> bool:
	for index in range(option.item_count):
		if (value is String and option.get_item_text(index) == str(value)) or (not value is String and option.get_item_id(index) == int(value)):
			option.select(index)
			return true
	return false

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
		_select_option(_vehicle, str(defaults.get("initial_vehicle", "walking")))
	if _land_tenure != null:
		_select_option(_land_tenure, int(defaults.get("land_tenure_months", 0)))
	var date: Variant = defaults.get("start_date", {})
	if date is Dictionary and GameCalendar.is_valid(date):
		_year.value = int(date.get("year", 1998)); _month.value = int(date.get("month", 1)); _day.value = int(date.get("day", 1))

func _rebuild_maps() -> void:
	var valid: Array = []
	for value in _catalog:
		if value is Dictionary and _definition_edition(value) == _edition:
			valid.append(value)
	for index in range(_map_buttons.size()):
		var button := _map_buttons[index]
		button.disabled = index >= valid.size()
		if index < valid.size():
			var definition: Dictionary = valid[index]
			button.text = _map_name(definition, index)
			if str(definition.get("id", "")) == str(_selected_map.get("id", "")):
				button.button_pressed = true
		else:
			button.text = MAP_NAMES[index]
	for index in range(_edition_buttons.size()):
		_edition_buttons[index].disabled = (_edition == "Game" and index == 0) or (_edition == "MultiverseJourney" and index == 1)

func _definition_edition(definition: Dictionary) -> String:
	var source: Variant = definition.get("source", {})
	return str(source.get("edition", "Game")) if source is Dictionary else "Game"

func _map_name(definition: Dictionary, index: int) -> String:
	var source: Variant = definition.get("source", {})
	var edition := str(source.get("edition", "Game")) if source is Dictionary else "Game"
	var number := int(source.get("map_number", index + 1)) - 1 if source is Dictionary else index
	var names := MJ_MAP_NAMES if edition == "MultiverseJourney" else MAP_NAMES
	return "%s · %s" % [edition, names[clampi(number, 0, names.size() - 1)]]

func _select_map(index: int) -> void:
	var valid: Array = []
	for value in _catalog:
		if value is Dictionary and _definition_edition(value) == _edition:
			valid.append(value)
	if index < valid.size():
		_selected_map = valid[index].duplicate(true)
		_update_preview()

func _select_edition(edition: String) -> void:
	_edition = edition
	_rebuild_maps()
	_update_portraits()
	_update_preview()

func _select_player(index: int) -> void:
	_active_player = clampi(index, 0, _player_count - 1)
	_update_portraits()

func _select_character(index: int) -> void:
	if _active_player >= _player_count:
		return
	if _character_ids.slice(0, _player_count).has(index):
		for player in range(_player_count):
			if _character_ids[player] == index:
				_character_ids[player] = _character_ids[_active_player]
	_character_ids[_active_player] = index
	_update_portraits()

func _toggle_player_type(index: int) -> void:
	if index >= _player_count:
		return
	_player_ai[index] = not _player_ai[index]
	_update_portraits()

func _human_flags() -> Array:
	var result: Array = []
	for index in range(_player_count):
		result.append(not _player_ai[index])
	return result

func _update_portraits() -> void:
	for index in range(_portrait_buttons.size()):
		var button := _portrait_buttons[index]
		var frame := _visuals.character(_edition, index)
		var texture := _visuals.texture(frame)
		button.icon = texture
		button.modulate = Color("#fff2c2") if index in _character_ids.slice(0, _player_count) else Color("#82949a")
	for index in range(_player_type_buttons.size()):
		var button := _player_type_buttons[index]
		button.disabled = index >= _player_count
		button.text = "AI" if _player_ai[index] else "真人"

func _update_preview() -> void:
	if _map_preview == null:
		return
	var scene := _visuals.scene_for(_selected_map)
	var texture := _visuals.texture(scene.get("image", {})) if not scene.is_empty() else null
	_map_preview.texture = texture
	_map_caption.text = _map_name(_selected_map, 0) if not _selected_map.is_empty() else "選擇可用地圖"

func _confirm() -> void:
	var result := collect_options()
	if not bool(result.get("ok", false)):
		_error.text = str(result.get("message", "開局設定無效。"))
		return
	_error.text = ""
	confirmed.emit(result["options"], _selected_map.duplicate(true))

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
