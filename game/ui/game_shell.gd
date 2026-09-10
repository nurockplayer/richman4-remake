extends Control
class_name RichmanGameShell

## Source-shaped 640x480 presentation shell.
##
## This node owns layout, hit areas and presentation state only.  MainUI keeps
## ownership of GameState and connects these signals to the existing actions.

const OriginalVisuals = preload("res://game/platform/original_visuals.gd")
const SourceMinimap = preload("res://game/ui/source_minimap.gd")
const GameCalendar = preload("res://game/core/game_calendar.gd")
const REFERENCE_SIZE := Vector2(640.0, 480.0)
const TOOLBAR_WIDTH := 440.0
const BOARD_RECT := Rect2(0.0, 40.0, 440.0, 440.0)
const HUD_RECT := Rect2(440.0, 0.0, 200.0, 280.0)
const CALENDAR_RECT := Rect2(440.0, 280.0, 200.0, 200.0)
const TEXT_MAIN := Color("#edf3f0")
const TEXT_MUTED := Color("#a2bbc0")
const TEXT_GOLD := Color("#f1d28a")
const PANEL := Color("#172f3e")
const PANEL_DARK := Color("#0d1d2b")
const PANEL_BORDER := Color("#c8a356")

signal start_requested
signal load_requested
signal save_requested
signal option_requested
signal help_requested
signal ai_requested
signal map_requested
signal inspect_requested
signal tools_requested
signal cards_requested
signal sale_requested
signal stocks_requested
signal roll_requested
signal buy_requested
signal upgrade_requested
signal end_turn_requested
signal route_requested(next_index: int)
signal vehicle_requested(vehicle: String, dice_count: int)
signal tab_requested(tab_id: String)
signal minimap_pan_requested(delta: Vector2)
signal minimap_node_requested(index: int)

var reference_canvas: Control
var title_screen: Control
var game_screen: Control
var toolbar: Control
var board_host: Control
var hud_panel: Control
var calendar_panel: Control
var minimap: Control

var title_start_button: Button
var title_load_button: Button
var title_option_button: Button
var toolbar_buttons: Dictionary = {}
var tab_buttons: Dictionary = {}
var route_buttons: HBoxContainer
var roll_button: Button
var buy_button: Button
var upgrade_button: Button
var end_turn_button: Button
var action_strip: Control
var action_hint_label: Label
var calendar_toggle_button: Button
var portrait: TextureRect
var player_name_label: Label
var cash_caption: Label
var deposit_caption: Label
var wealth_caption: Label
var cash_label: Label
var deposit_label: Label
var wealth_label: Label
var property_label: Label
var stock_label: Label
var other_label: Label
var date_label: Label
var calendar_mode_label: Label

var title_visible := true
var active_tab := "cash"
var calendar_mode := "day"
var snapshot: Dictionary = {}
var map_definition: Dictionary = {}
var _player_wealth := -1
var _visuals = OriginalVisuals.new()
var _source_edition := "Game"
var _source_title_texture: Texture2D
var _source_panel_texture: Texture2D
var _source_hud_texture: Texture2D
var _source_calendar_texture: Texture2D
var _title_art: TextureRect
var _hud_art: TextureRect
var _calendar_art: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_reference_canvas()
	call_deferred("_layout_reference_canvas")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and reference_canvas != null:
		_layout_reference_canvas()


func _build_reference_canvas() -> void:
	reference_canvas = Control.new()
	reference_canvas.name = "ReferenceCanvas"
	reference_canvas.position = Vector2.ZERO
	reference_canvas.size = REFERENCE_SIZE
	reference_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(reference_canvas)
	_build_title_screen()
	_build_game_screen()


func _layout_reference_canvas() -> void:
	if reference_canvas == null:
		return
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	var scale_factor := minf(viewport_size.x / REFERENCE_SIZE.x, viewport_size.y / REFERENCE_SIZE.y)
	if scale_factor <= 0.0:
		return
	reference_canvas.scale = Vector2.ONE * scale_factor
	reference_canvas.position = (viewport_size - REFERENCE_SIZE * scale_factor) * 0.5


func _build_title_screen() -> void:
	title_screen = Control.new()
	title_screen.name = "SourceTitleScreen"
	title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reference_canvas.add_child(title_screen)
	_source_title_texture = _source_texture(_visuals.ui(_source_edition, "Data", 1, 0))
	if _source_title_texture != null:
		_title_art = TextureRect.new()
		_title_art.name = "SourceTitleArt"
		_title_art.texture = _source_title_texture
		_title_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_title_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_title_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_title_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_screen.add_child(_title_art)
	else:
		var background := ColorRect.new()
		background.color = Color("#0d2630")
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_screen.add_child(background)
		var glow := ColorRect.new()
		glow.color = Color("#1a5360")
		glow.position = Vector2(80.0, 95.0)
		glow.size = Vector2(480.0, 210.0)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_screen.add_child(glow)
		var title := _label("大富翁 4", 44, Color("#f5d98d"))
		title.position = Vector2(0.0, 130.0)
		title.size = Vector2(640.0, 56.0)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_screen.add_child(title)
		var subtitle := _label("城市棋局", 18, Color("#c1e0d6"))
		subtitle.position = Vector2(0.0, 190.0)
		subtitle.size = Vector2(640.0, 28.0)
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_screen.add_child(subtitle)
	var menu := Control.new()
	menu.name = "TitleMenu"
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _source_title_texture != null:
		menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		menu.position = Vector2(248.0, 300.0)
		menu.size = Vector2(144.0, 132.0)
	title_screen.add_child(menu)
	title_start_button = _title_button("START", "開始新局")
	_configure_title_hit_area(title_start_button, "start", Rect2(129.0, 322.0, 118.0, 112.0))
	title_start_button.pressed.connect(func() -> void: start_requested.emit())
	menu.add_child(title_start_button)
	title_load_button = _title_button("LOAD", "讀取存檔")
	_configure_title_hit_area(title_load_button, "load", Rect2(269.0, 322.0, 118.0, 112.0))
	title_load_button.pressed.connect(func() -> void: load_requested.emit())
	menu.add_child(title_load_button)
	title_option_button = _title_button("OPTION", "選項")
	_configure_title_hit_area(title_option_button, "option", Rect2(408.0, 322.0, 118.0, 112.0))
	title_option_button.pressed.connect(func() -> void: option_requested.emit())
	menu.add_child(title_option_button)


func _build_game_screen() -> void:
	game_screen = Control.new()
	game_screen.name = "SourceGameScreen"
	game_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_screen.hide()
	reference_canvas.add_child(game_screen)
	var background := ColorRect.new()
	background.color = PANEL_DARK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_screen.add_child(background)
	_build_toolbar()
	_build_board_host()
	_build_hud()
	_build_calendar_and_minimap()


func _build_toolbar() -> void:
	toolbar = Control.new()
	toolbar.name = "SourceToolbar"
	toolbar.position = Vector2.ZERO
	toolbar.size = Vector2(TOOLBAR_WIDTH, 40.0)
	game_screen.add_child(toolbar)
	_source_panel_texture = _source_texture(_visuals.ui(_source_edition, "Panel", 1, 0))
	if _source_panel_texture != null:
		var panel_art := TextureRect.new()
		panel_art.texture = _source_panel_texture
		panel_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		panel_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		panel_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toolbar.add_child(panel_art)
	var entries := [
		["help", "說", 1], ["options", "系", 2], ["ai", "託", 3],
		["load", "載", 4], ["save", "存", 5], ["map", "圖", 6],
		["inspect", "查", 7], ["tools", "具", 8], ["cards", "卡", 9],
		["sale", "售", 10], ["stocks", "股", 11],
	]
	for index in range(entries.size()):
		var entry: Array = entries[index]
		var key := str(entry[0])
		var button := _toolbar_button(str(entry[1]), key)
		button.position = Vector2(float(index) * 40.0, 0.0)
		button.size = Vector2(40.0, 40.0)
		button.set_meta("source_chunk", int(entry[2]))
		var icon := _source_texture(_visuals.ui(_source_edition, "Panel", 1, int(entry[2])))
		if icon != null:
			button.icon = icon
			button.text = ""
			button.set_meta("source_icon", icon)
		button.pressed.connect(_emit_toolbar.bind(key))
		toolbar.add_child(button)
		toolbar_buttons[key] = button


func _build_board_host() -> void:
	board_host = Control.new()
	board_host.name = "SourceBoardHost"
	board_host.position = BOARD_RECT.position
	board_host.size = BOARD_RECT.size
	board_host.clip_contents = true
	board_host.mouse_filter = Control.MOUSE_FILTER_STOP
	game_screen.add_child(board_host)


func _build_hud() -> void:
	hud_panel = Control.new()
	hud_panel.name = "SourceHud"
	hud_panel.position = HUD_RECT.position
	hud_panel.size = HUD_RECT.size
	hud_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	game_screen.add_child(hud_panel)
	var panel := ColorRect.new()
	panel.name = "SourceHudFallback"
	panel.color = PANEL
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_panel.add_child(panel)
	_hud_art = TextureRect.new()
	_hud_art.name = "SourceHudArt"
	_hud_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hud_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_hud_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hud_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_panel.add_child(_hud_art)
	_source_hud_texture = _source_texture(_visuals.ui(_source_edition, "Panel", 0, 0))
	_hud_art.texture = _source_hud_texture
	_hud_art.visible = _source_hud_texture != null
	if _source_hud_texture == null:
		var border := ColorRect.new()
		border.color = PANEL_BORDER
		border.position = Vector2(0.0, 0.0)
		border.size = Vector2(2.0, HUD_RECT.size.y)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_panel.add_child(border)
	portrait = TextureRect.new()
	portrait.name = "SourcePortrait"
	portrait.position = Vector2(4.0, 4.0)
	portrait.size = Vector2(72.0, 72.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_panel.add_child(portrait)
	player_name_label = _hud_label("玩家", 15, Vector2(80.0, 8.0), Vector2(88.0, 24.0), TEXT_MAIN)
	cash_caption = _hud_label("現金", 10, Vector2(28.0, 80.0), Vector2(140.0, 18.0), TEXT_MUTED)
	cash_label = _hud_label("$0", 16, Vector2(28.0, 96.0), Vector2(140.0, 30.0), TEXT_GOLD)
	deposit_caption = _hud_label("存款", 10, Vector2(28.0, 143.0), Vector2(140.0, 18.0), TEXT_MUTED)
	deposit_label = _hud_label("$0", 16, Vector2(28.0, 159.0), Vector2(140.0, 30.0), TEXT_GOLD)
	wealth_caption = _hud_label("總資產", 10, Vector2(28.0, 206.0), Vector2(140.0, 18.0), TEXT_MUTED)
	wealth_label = _hud_label("$0", 16, Vector2(28.0, 222.0), Vector2(140.0, 30.0), TEXT_GOLD)
	property_label = _hud_label("地產\n0 筆 · $0", 11, Vector2(28.0, 80.0), Vector2(140.0, 164.0), TEXT_MAIN)
	property_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stock_label = _hud_label("股票\n0 股", 11, Vector2(28.0, 80.0), Vector2(140.0, 164.0), TEXT_MAIN)
	stock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stock_label.hide()
	other_label = _hud_label("其他\n點券 0 · 卡片 0\n道具 0 種", 11, Vector2(28.0, 80.0), Vector2(140.0, 164.0), TEXT_MAIN)
	other_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	other_label.hide()
	var tab_names := {"cash": "資", "property": "產", "stock": "股", "other": "他"}
	for index in range(tab_names.size()):
		var key := str(tab_names.keys()[index])
		var tab := _tab_button(str(tab_names[key]), key)
		tab.position = Vector2(176.0, float(index) * 42.0)
		tab.size = Vector2(24.0, 40.0)
		tab.pressed.connect(_select_tab.bind(key))
		hud_panel.add_child(tab)
		tab_buttons[key] = tab
	action_strip = Control.new()
	action_strip.name = "SourceActionStrip"
	action_strip.position = Vector2(8.0, 398.0)
	action_strip.size = Vector2(424.0, 76.0)
	action_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	action_strip.hide()
	game_screen.add_child(action_strip)
	var action_background := ColorRect.new()
	action_background.name = "ActionBackground"
	action_background.color = Color(0.04, 0.12, 0.16, 0.88)
	action_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	action_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_strip.add_child(action_background)
	roll_button = _action_button("擲骰", "roll")
	roll_button.position = Vector2(8.0, 7.0)
	roll_button.size = Vector2(94.0, 29.0)
	roll_button.pressed.connect(func() -> void: roll_requested.emit())
	action_strip.add_child(roll_button)
	buy_button = _action_button("購買", "buy")
	buy_button.position = Vector2(108.0, 7.0)
	buy_button.size = Vector2(120.0, 29.0)
	buy_button.pressed.connect(func() -> void: buy_requested.emit())
	action_strip.add_child(buy_button)
	upgrade_button = _action_button("升級", "upgrade")
	upgrade_button.position = Vector2(234.0, 7.0)
	upgrade_button.size = Vector2(86.0, 29.0)
	upgrade_button.pressed.connect(func() -> void: upgrade_requested.emit())
	action_strip.add_child(upgrade_button)
	end_turn_button = _action_button("結束", "end_turn")
	end_turn_button.position = Vector2(326.0, 7.0)
	end_turn_button.size = Vector2(90.0, 29.0)
	end_turn_button.pressed.connect(func() -> void: end_turn_requested.emit())
	action_strip.add_child(end_turn_button)
	action_hint_label = _label("等待棋局", 10, TEXT_MUTED)
	action_hint_label.name = "SourceActionHint"
	action_hint_label.position = Vector2(8.0, 41.0)
	action_hint_label.size = Vector2(408.0, 26.0)
	action_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_strip.add_child(action_hint_label)
	route_buttons = HBoxContainer.new()
	route_buttons.name = "SourceRouteChoices"
	route_buttons.position = Vector2(8.0, 7.0)
	route_buttons.size = Vector2(408.0, 29.0)
	route_buttons.add_theme_constant_override("separation", 3)
	route_buttons.hide()
	action_strip.add_child(route_buttons)


func _build_calendar_and_minimap() -> void:
	calendar_panel = Control.new()
	calendar_panel.name = "SourceCalendar"
	calendar_panel.position = CALENDAR_RECT.position
	calendar_panel.size = CALENDAR_RECT.size
	calendar_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	game_screen.add_child(calendar_panel)
	var panel := ColorRect.new()
	panel.name = "SourceCalendarFallback"
	panel.color = Color("#d8e6d3")
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	calendar_panel.add_child(panel)
	_calendar_art = TextureRect.new()
	_calendar_art.name = "SourceCalendarArt"
	_calendar_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_calendar_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_calendar_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_calendar_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_calendar_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	calendar_panel.add_child(_calendar_art)
	date_label = _label("日期未記錄", 18, Color("#193047"))
	date_label.position = Vector2(12.0, 11.0)
	date_label.size = Vector2(176.0, 28.0)
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	calendar_panel.add_child(date_label)
	calendar_mode_label = _label("日曆", 10, Color("#416b68"))
	calendar_mode_label.position = Vector2(12.0, 42.0)
	calendar_mode_label.size = Vector2(176.0, 20.0)
	calendar_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	calendar_panel.add_child(calendar_mode_label)
	calendar_toggle_button = Button.new()
	calendar_toggle_button.name = "CalendarToggle"
	calendar_toggle_button.text = "月曆／地圖"
	calendar_toggle_button.position = Vector2(47.0, 166.0)
	calendar_toggle_button.size = Vector2(106.0, 26.0)
	calendar_toggle_button.add_theme_font_size_override("font_size", 10)
	calendar_toggle_button.pressed.connect(_toggle_calendar_mode)
	calendar_panel.add_child(calendar_toggle_button)
	minimap = SourceMinimap.new()
	minimap.name = "SourceMinimap"
	minimap.position = CALENDAR_RECT.position
	minimap.size = CALENDAR_RECT.size
	minimap.hide()
	minimap.pan_requested.connect(func(delta: Vector2) -> void: minimap_pan_requested.emit(delta))
	minimap.node_selected.connect(func(index: int) -> void: minimap_node_requested.emit(index))
	game_screen.add_child(minimap)


func _emit_toolbar(key: String) -> void:
	match key:
		"help": help_requested.emit()
		"options": option_requested.emit()
		"ai": ai_requested.emit()
		"load": load_requested.emit()
		"save": save_requested.emit()
		"map": map_requested.emit()
		"inspect": inspect_requested.emit()
		"tools": tools_requested.emit()
		"cards": cards_requested.emit()
		"sale": sale_requested.emit()
		"stocks": stocks_requested.emit()


func _select_tab(tab_id: String) -> void:
	active_tab = tab_id
	_render_hud()
	tab_requested.emit(tab_id)


func _toggle_calendar_mode() -> void:
	calendar_mode = "map" if calendar_mode == "day" else "day"
	calendar_panel.visible = calendar_mode != "map"
	minimap.visible = calendar_mode == "map"
	calendar_mode_label.text = "日曆" if calendar_mode == "day" else "地圖"


func toggle_map_view() -> void:
	_toggle_calendar_mode()


func select_tab(tab_id: String) -> void:
	if tab_buttons.has(tab_id):
		_select_tab(tab_id)


func show_title() -> void:
	title_visible = true
	title_screen.show()
	game_screen.hide()


func show_game() -> void:
	title_visible = false
	title_screen.hide()
	game_screen.show()


func is_title_visible() -> bool:
	return title_visible


func get_board_host() -> Control:
	return board_host


func set_board_view(view: Control) -> void:
	if view == null or board_host == null:
		return
	var old_parent := view.get_parent()
	if old_parent != null:
		old_parent.remove_child(view)
	board_host.add_child(view)
	view.position = Vector2.ZERO
	view.size = BOARD_RECT.size
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if minimap != null and minimap.has_method("set_board_view"):
		minimap.call("set_board_view", view)


func sync_snapshot(next_snapshot: Dictionary, next_definition: Dictionary = {}, player_wealth: int = -1) -> void:
	snapshot = next_snapshot.duplicate(true)
	map_definition = next_definition.duplicate(true)
	_player_wealth = player_wealth
	_render_hud()
	_render_calendar()
	if minimap != null and minimap.has_method("set_snapshot"):
		minimap.call("set_snapshot", snapshot, map_definition)


func sync_action_state(roll_text: String, roll_disabled: bool, buy_text: String, buy_disabled: bool, upgrade_text: String, upgrade_disabled: bool, end_disabled: bool, hint: String, routes: Array = []) -> void:
	if roll_button == null:
		return
	roll_button.text = roll_text
	roll_button.disabled = roll_disabled
	buy_button.text = buy_text
	buy_button.disabled = buy_disabled
	upgrade_button.text = upgrade_text
	upgrade_button.disabled = upgrade_disabled
	end_turn_button.disabled = end_disabled
	action_hint_label.text = hint
	roll_button.visible = true
	buy_button.visible = true
	upgrade_button.visible = true
	end_turn_button.visible = true
	for child in route_buttons.get_children():
		route_buttons.remove_child(child)
		child.queue_free()
	for next_index_value in routes:
		var next_index := int(next_index_value)
		var route := _action_button("→ %02d" % (next_index + 1), "route")
		route.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		route.pressed.connect(route_requested.emit.bind(next_index))
		route_buttons.add_child(route)
	route_buttons.visible = not routes.is_empty()
	# Keep the board-context controls mounted while a movement or event
	# presentation is running.  Their disabled state is the visible gate, so
	# the source surface cannot appear to lose the active turn controls while
	# the legacy adapter is temporarily blocked.
	action_strip.visible = true


func set_toolbar_enabled(key: String, enabled: bool) -> void:
	if toolbar_buttons.has(key):
		(toolbar_buttons[key] as Button).disabled = not enabled
	if key == "load" and title_load_button != null:
		title_load_button.disabled = not enabled


func _render_hud() -> void:
	if player_name_label == null:
		return
	var players: Array = snapshot.get("players", [])
	var current_index := int(snapshot.get("current_player", 0))
	var player: Dictionary = players[current_index] if current_index >= 0 and current_index < players.size() and players[current_index] is Dictionary else {}
	var character_id := int(player.get("character_id", current_index))
	player_name_label.text = str(player.get("name", "玩家"))
	cash_label.text = _money(int(player.get("cash", 0)))
	deposit_label.text = _money(int(player.get("deposit", 0)))
	wealth_label.text = _money(_player_wealth) if _player_wealth >= 0 else "未知"
	var properties: Array = player.get("properties", [])
	property_label.text = "地產\n%d 筆\n估值 %s" % [properties.size(), _money(int(player.get("property_values", 0)))]
	var holdings: Dictionary = player.get("stocks", {})
	var total_shares := 0
	var stock_lines: Array[String] = []
	for symbol in holdings:
		var amount := int(holdings[symbol])
		if amount <= 0:
			continue
		total_shares += amount
		stock_lines.append("%s × %d" % [_stock_display_name(str(symbol)), amount])
	stock_label.text = "股票\n%d 股\n%s" % [total_shares, "、".join(stock_lines)]
	if stock_lines.is_empty():
		stock_label.text = "股票\n0 股"
	var tools: Dictionary = player.get("tools", {})
	other_label.text = "其他\n點券 %d · 卡片 %d\n道具 %d 種" % [int(player.get("points", 0)), (player.get("cards", []) as Array).size(), tools.size()]
	if not _source_edition.is_empty():
		var frame := _visuals.ui(_source_edition, "Data", 2, clampi(character_id, 0, 11))
		portrait.texture = _source_texture(frame)
	portrait.visible = portrait.texture != null
	_set_hud_art(active_tab)
	cash_caption.visible = active_tab == "cash"
	deposit_caption.visible = active_tab == "cash"
	wealth_caption.visible = active_tab == "cash"
	cash_label.visible = active_tab == "cash"
	deposit_label.visible = active_tab == "cash"
	wealth_label.visible = active_tab == "cash"
	if active_tab == "cash":
		property_label.hide()
		stock_label.hide()
		other_label.hide()
	elif active_tab == "property":
		property_label.show()
		stock_label.hide()
		other_label.hide()
	elif active_tab == "stock":
		property_label.hide()
		stock_label.show()
		other_label.hide()
	else:
		property_label.hide()
		stock_label.hide()
		other_label.show()
	for key in tab_buttons:
		var tab: Button = tab_buttons[key]
		tab.modulate = Color.WHITE if key == active_tab else Color(0.72, 0.82, 0.82, 1.0)


func _render_calendar() -> void:
	if date_label == null:
		return
	var raw_date: Variant = snapshot.get("date", snapshot.get("start_date", null))
	if raw_date is Dictionary and GameCalendar.is_valid(raw_date):
		var weekday := int(snapshot.get("weekday", GameCalendar.weekday(raw_date)))
		date_label.text = "%04d / %02d / %02d 週%s" % [int(raw_date.year), int(raw_date.month), int(raw_date.day), _weekday_text(weekday)]
	else:
		date_label.text = "日期未記錄"
	calendar_mode_label.text = "日曆" if calendar_mode == "day" else "地圖"
	_set_calendar_art(raw_date)


func _set_hud_art(tab_id: String) -> void:
	if _hud_art == null:
		return
	var chunk: int = int({"cash": 0, "property": 1, "stock": 2, "other": 3}.get(tab_id, 0))
	_source_hud_texture = _source_texture(_visuals.ui(_source_edition, "Panel", 0, chunk))
	_hud_art.texture = _source_hud_texture
	_hud_art.visible = _source_hud_texture != null


func _set_calendar_art(raw_date: Variant) -> void:
	if _calendar_art == null:
		return
	_source_calendar_texture = null
	if raw_date is Dictionary and GameCalendar.is_valid(raw_date):
		var month := int(raw_date.get("month", 1))
		var season := 0 if month in [3, 4, 5] else 1 if month in [6, 7, 8] else 2 if month in [9, 10, 11] else 3
		_source_calendar_texture = _source_texture(_visuals.ui(_source_edition, "Panel", 2, 4 + season))
	_calendar_art.texture = _source_calendar_texture
	_calendar_art.visible = _source_calendar_texture != null


func _stock_display_name(symbol: String) -> String:
	var normalized := symbol.to_lower().strip_edges()
	var market: Variant = snapshot.get("market", {})
	if market is Dictionary:
		var rows: Variant = market.get("rows", {})
		if rows is Dictionary:
			var row: Variant = rows.get(normalized, rows.get(StringName(normalized), {}))
			if row is Dictionary:
				var market_name: Variant = row.get("display_name", row.get("name", ""))
				if market_name is String and not str(market_name).is_empty():
					return str(market_name)
	var stock_rows: Variant = map_definition.get("stock_rows", [])
	if stock_rows is Array and normalized.begins_with("s") and normalized.substr(1).is_valid_int():
		var index := int(normalized.substr(1)) - 1
		if index >= 0 and index < stock_rows.size() and stock_rows[index] is Dictionary:
			var definition_name: Variant = stock_rows[index].get("display_name", stock_rows[index].get("name", ""))
			if definition_name is String and not str(definition_name).is_empty():
				return str(definition_name)
	return normalized.to_upper()


func _weekday_text(weekday: int) -> String:
	return ["未知", "一", "二", "三", "四", "五", "六", "日"][weekday] if weekday >= 1 and weekday <= 7 else "未知"


func _source_texture(frame: Dictionary) -> Texture2D:
	return _visuals.texture(frame) if not frame.is_empty() else null


func _money(value: int) -> String:
	var digits := str(abs(value))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	grouped = digits + grouped
	return ("-" if value < 0 else "") + "$" + grouped


func _label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


func _hud_label(text: String, font_size: int, position: Vector2, label_size: Vector2, color: Color) -> Label:
	var result := _label(text, font_size, color)
	result.position = position
	result.size = label_size
	result.clip_text = true
	hud_panel.add_child(result)
	return result


func _title_button(text: String, tooltip: String) -> Button:
	var result := Button.new()
	result.text = text
	result.tooltip_text = tooltip
	result.custom_minimum_size = Vector2(144.0, 38.0)
	result.add_theme_font_size_override("font_size", 16)
	result.add_theme_color_override("font_color", Color("#fff2bd"))
	result.add_theme_stylebox_override("normal", _style(Color(0.06, 0.16, 0.2, 0.82), Color("#d8b45f"), 5, 1))
	result.add_theme_stylebox_override("hover", _style(Color(0.17, 0.34, 0.37, 0.92), Color("#fff0a5"), 5, 2))
	return result


func _configure_title_hit_area(button: Button, key: String, rect: Rect2) -> void:
	button.set_meta("source_key", key)
	if _source_title_texture == null:
		var index := ["start", "load", "option"].find(key)
		button.position = Vector2(0.0, float(maxi(0, index)) * 46.0)
		button.size = Vector2(144.0, 38.0)
		return
	button.position = rect.position
	button.size = rect.size
	button.text = ""
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var hover_chunk: int = int({"start": 2, "load": 4, "option": 6}.get(key, -1))
	if hover_chunk >= 0:
		var hover_texture := _source_texture(_visuals.ui(_source_edition, "Data", 1, hover_chunk))
		if hover_texture != null:
			button.mouse_entered.connect(func() -> void: button.icon = hover_texture)
			button.mouse_exited.connect(func() -> void: button.icon = null)


func _toolbar_button(text: String, key: String) -> Button:
	var result := Button.new()
	result.name = "Toolbar_%s" % key
	result.text = text
	result.tooltip_text = key
	result.flat = true
	result.focus_mode = Control.FOCUS_ALL
	result.add_theme_font_size_override("font_size", 12)
	result.add_theme_color_override("font_color", Color("#263540"))
	result.add_theme_color_override("font_hover_color", Color("#ffffff"))
	result.add_theme_color_override("font_disabled_color", Color("#76827c"))
	result.add_theme_stylebox_override("hover", _style(Color(0.95, 0.84, 0.45, 0.45), Color("#fff0a5"), 3, 1))
	return result


func _tab_button(text: String, key: String) -> Button:
	var result := _toolbar_button(text, "tab_" + key)
	result.name = "Tab_%s" % key
	result.add_theme_font_size_override("font_size", 13)
	return result


func _action_button(text: String, key: String) -> Button:
	var result := Button.new()
	result.name = "Action_%s" % key
	result.text = text
	result.tooltip_text = key
	result.focus_mode = Control.FOCUS_ALL
	result.add_theme_font_size_override("font_size", 10)
	result.add_theme_color_override("font_color", TEXT_MAIN)
	result.add_theme_color_override("font_disabled_color", Color("#62777b"))
	result.add_theme_stylebox_override("normal", _style(Color("#315469"), Color("#8aa99b"), 3, 1))
	result.add_theme_stylebox_override("hover", _style(Color("#527a7b"), TEXT_GOLD, 3, 1))
	result.add_theme_stylebox_override("disabled", _style(Color("#203743"), Color("#3c555d"), 3, 1))
	return result


func _style(background: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = background
	result.border_color = border
	result.set_border_width_all(width)
	result.set_corner_radius_all(radius)
	return result
