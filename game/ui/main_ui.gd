extends Control

## Desktop game shell for the Richman 4 reconstruction.
##
## This script owns presentation and input only.  The simulation is loaded at
## runtime so the UI remains parseable while the core is developed in its own
## lane.  Once present, GameState is the authority for every displayed value.

const SAVE_PATH := "user://richman4_save.json"
const OriginalMaps = preload("res://game/content/original_maps.gd")
const GameCalendar = preload("res://game/core/game_calendar.gd")
const FALLBACK_MAP_ID := "test:classic40"
const PLAYER_COUNT := 4
const DEFAULT_SEED := 136622
const MIN_SEED := -2147483648
const MAX_SEED := 2147483647
const SETUP_INITIAL_FUNDS := [300000, 200000, 100000, 50000, 30000, 10000]
const SETUP_DAY_LIMITS := [0, 730, 365, 182, 91, 30]
const SETUP_WEALTH_MULTIPLIERS := [0, 100, 50, 10, 5, 3]
const CHARACTER_NAMES := [
	"約翰喬", "沙隆巴斯", "忍太郎", "錢夫人", "阿土伯", "莎拉公主",
	"宮本寶藏", "糖糖", "烏咪", "孫小美", "小丹尼", "金貝貝",
]
const MIN_START_YEAR := 1998
const MAX_START_YEAR := 9999
const PANEL_BG := Color("#1c2d40")
const PANEL_RAISED := Color("#243b50")
const PANEL_BORDER := Color("#36546b")
const TEXT_MAIN := Color("#edf3f0")
const TEXT_MUTED := Color("#99b2bd")
const TEXT_GOLD := Color("#f1d28a")
const ACCENT := Color("#e0a958")
const ACCENT_DARK := Color("#a96d36")
const PLAYER_COLORS := [
	Color("#ef6a65"),
	Color("#4ba6e8"),
	Color("#e6b84f"),
	Color("#73c989"),
]

var game_state: Object
var state: Dictionary = {}
var board_view: Control

var seed_label: Label
var map_identity_label: Label
var phase_label: Label
var turn_label: Label
var setup_summary_label: Label
var current_player_label: Label
var current_property_label: Label
var current_property_detail: Label
var players_list: VBoxContainer
var event_log_view: RichTextLabel
var event_status_label: Label
var action_hint_label: Label

var bank_shortcut: Button
var cards_shortcut: Button
var stocks_shortcut: Button
var roll_button: Button
var buy_button: Button
var upgrade_button: Button
var end_turn_button: Button
var bank_button: Button
var cards_button: Button
var stocks_button: Button

var new_game_button: Button
var save_button: Button
var load_button: Button

var bank_popup: PopupPanel
var bank_deposit_button: Button
var bank_withdraw_button: Button
var new_game_popup: PopupPanel
var seed_input: LineEdit
var player_count_option: OptionButton
var initial_fund_option: OptionButton
var day_limit_option: OptionButton
var wealth_multiplier_option: OptionButton
var start_year_input: SpinBox
var start_month_input: SpinBox
var start_day_input: SpinBox
var character_options: Array[OptionButton] = []
var character_rows: VBoxContainer
var setup_scroll: ScrollContainer
var setup_error_label: Label
var map_selector: OptionButton
var map_catalog_status_label: Label
var map_preview_status_label: Label
var map_preview_view: Control
var map_catalog_file_dialog: FileDialog
var new_game_confirm_button: Button
var cards_popup: PopupPanel
var stocks_popup: PopupPanel
var audio_controller: Object
var audio_button: Button
var audio_config_button: Button
var audio_folder_dialog: FileDialog
var cards_popup_list: VBoxContainer
var stocks_popup_list: VBoxContainer
var end_overlay: ColorRect
var end_title: Label
var end_detail: Label
var route_options_box: HBoxContainer
var route_status_label: Label

var _local_log: Array[String] = []
var _ai_pending := false
var _last_rendered_phase := ""
var _selected_tile := -1
var _map_catalog: Array = []
var _map_catalog_path := ""
var _map_catalog_error := ""
var _map_catalog_ok := false
var _selected_map_definition: Dictionary = {}
var _active_map_definition: Dictionary = {}

func _ready() -> void:
	_build_interface()
	_setup_audio()
	_load_map_catalog()
	_new_game(DEFAULT_SEED, PLAYER_COUNT, _selected_map_definition, _default_setup_options(PLAYER_COUNT))

func _process(_delta: float) -> void:
	_maybe_schedule_ai_turn()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			if roll_button != null and not roll_button.disabled:
				_on_roll_pressed()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_N:
			_restart_game()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S and event.ctrl_pressed:
			_save_game()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_L and event.ctrl_pressed:
			_load_game()
			get_viewport().set_input_as_handled()

func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var background := ColorRect.new()
	background.color = Color("#0d1b2a")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var backdrop_glow := ColorRect.new()
	backdrop_glow.color = Color("#11283a")
	backdrop_glow.position = Vector2(0.0, 0.0)
	backdrop_glow.size = Vector2(520.0, 180.0)
	backdrop_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop_glow)

	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margins.add_theme_constant_override("margin_left", 22)
	margins.add_theme_constant_override("margin_top", 18)
	margins.add_theme_constant_override("margin_right", 22)
	margins.add_theme_constant_override("margin_bottom", 18)
	add_child(margins)

	var root_column := VBoxContainer.new()
	root_column.add_theme_constant_override("separation", 12)
	root_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margins.add_child(root_column)

	root_column.add_child(_build_header())
	root_column.add_child(_build_playfield())
	root_column.add_child(_build_action_bar())
	root_column.add_child(_build_event_log())

	_build_popups()
	_build_end_overlay()

func _build_header() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 76.0)
	_apply_panel_style(panel, Color("#17283a"), PANEL_BORDER, 16, 1)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 1)
	row.add_child(title_column)
	var title := _make_label("大富翁 4", 24, TEXT_MAIN)
	title_column.add_child(title)
	var subtitle := _make_label("城市棋局 · 桌面重製版", 11, TEXT_MUTED)
	title_column.add_child(subtitle)

	var meta_column := VBoxContainer.new()
	meta_column.custom_minimum_size = Vector2(300.0, 0.0)
	meta_column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(meta_column)
	phase_label = _make_label("等待擲骰", 13, TEXT_GOLD)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta_column.add_child(phase_label)
	map_identity_label = _make_label("地圖 · 測試棋盤", 10, TEXT_MUTED)
	map_identity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta_column.add_child(map_identity_label)
	setup_summary_label = _make_label("1998/01/01 星期四 · 期限不限 · 目標不限", 9, TEXT_MUTED)
	setup_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	setup_summary_label.clip_text = true
	meta_column.add_child(setup_summary_label)
	seed_label = _make_label("SEED 136622", 10, TEXT_MUTED)
	seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta_column.add_child(seed_label)

	new_game_button = _make_button("新局", _on_new_game_pressed, true)
	new_game_button.custom_minimum_size = Vector2(72.0, 42.0)
	row.add_child(new_game_button)
	save_button = _make_button("儲存", _save_game)
	save_button.custom_minimum_size = Vector2(72.0, 42.0)
	row.add_child(save_button)
	load_button = _make_button("讀取", _load_game)
	load_button.custom_minimum_size = Vector2(72.0, 42.0)
	row.add_child(load_button)
	audio_button = _make_button("音樂", _on_audio_pressed)
	audio_button.custom_minimum_size = Vector2(72.0, 42.0)
	row.add_child(audio_button)
	audio_config_button = _make_button("音樂設定", _on_audio_config_pressed)
	audio_config_button.custom_minimum_size = Vector2(86.0, 42.0)
	row.add_child(audio_config_button)
	return panel

func _build_playfield() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var board_panel := PanelContainer.new()
	board_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_panel_style(board_panel, PANEL_BG, PANEL_BORDER, 16, 1)
	row.add_child(board_panel)
	var board_margin := MarginContainer.new()
	board_margin.add_theme_constant_override("margin_left", 10)
	board_margin.add_theme_constant_override("margin_top", 10)
	board_margin.add_theme_constant_override("margin_right", 10)
	board_margin.add_theme_constant_override("margin_bottom", 10)
	board_panel.add_child(board_margin)
	var board_column := VBoxContainer.new()
	board_column.add_theme_constant_override("separation", 7)
	board_margin.add_child(board_column)
	var board_header := HBoxContainer.new()
	board_column.add_child(board_header)
	var board_title := _make_label("棋盤", 14, TEXT_MAIN)
	board_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_header.add_child(board_title)
	var board_hint := _make_label("點選格位查看 · 原版圖可縮放平移", 10, TEXT_MUTED)
	board_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	board_header.add_child(board_hint)

	var board_script: Variant = load("res://game/ui/board_view.gd")
	if board_script != null:
		board_view = board_script.new()
	else:
		board_view = _make_label("棋盤載入中…", 18, TEXT_MUTED)
	board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_column.add_child(board_view)
	if board_view.has_signal("tile_selected"):
		board_view.tile_selected.connect(_on_tile_selected)
	if board_view.has_signal("route_selected"):
		board_view.route_selected.connect(_on_route_selected)

	var board_footer := _make_label("原版圖像資產為本機研究來源；目前以向量繪製還原版面。", 10, TEXT_MUTED)
	board_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board_column.add_child(board_footer)

	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size = Vector2(334.0, 0.0)
	sidebar.size_flags_horizontal = Control.SIZE_SHRINK_END
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_panel_style(sidebar, PANEL_BG, PANEL_BORDER, 16, 1)
	row.add_child(sidebar)
	var side_margin := MarginContainer.new()
	side_margin.add_theme_constant_override("margin_left", 16)
	side_margin.add_theme_constant_override("margin_top", 14)
	side_margin.add_theme_constant_override("margin_right", 16)
	side_margin.add_theme_constant_override("margin_bottom", 14)
	sidebar.add_child(side_margin)
	var side_column := VBoxContainer.new()
	side_column.add_theme_constant_override("separation", 10)
	side_margin.add_child(side_column)

	var turn_header := HBoxContainer.new()
	side_column.add_child(turn_header)
	current_player_label = _make_label("你的回合", 18, TEXT_MAIN)
	current_player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_header.add_child(current_player_label)
	turn_label = _make_label("第 1 回合", 11, TEXT_GOLD)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	turn_header.add_child(turn_label)

	var players_heading := _make_label("玩家狀態", 11, TEXT_MUTED)
	side_column.add_child(players_heading)
	players_list = VBoxContainer.new()
	players_list.add_theme_constant_override("separation", 5)
	players_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_column.add_child(players_list)

	var property_panel := PanelContainer.new()
	_apply_panel_style(property_panel, PANEL_RAISED, Color("#47705f"), 12, 1)
	side_column.add_child(property_panel)
	var property_margin := MarginContainer.new()
	property_margin.add_theme_constant_override("margin_left", 12)
	property_margin.add_theme_constant_override("margin_top", 10)
	property_margin.add_theme_constant_override("margin_right", 12)
	property_margin.add_theme_constant_override("margin_bottom", 10)
	property_panel.add_child(property_margin)
	var property_column := VBoxContainer.new()
	property_column.add_theme_constant_override("separation", 3)
	property_margin.add_child(property_column)
	var property_caption := _make_label("目前所在格位", 10, TEXT_MUTED)
	property_column.add_child(property_caption)
	current_property_label = _make_label("街區 01", 15, TEXT_MAIN)
	property_column.add_child(current_property_label)
	current_property_detail = _make_label("尚未擲骰", 11, Color("#b6d3c5"))
	current_property_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	property_column.add_child(current_property_detail)

	route_status_label = _make_label("", 11, TEXT_GOLD)
	route_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_column.add_child(route_status_label)
	route_options_box = HBoxContainer.new()
	route_options_box.add_theme_constant_override("separation", 6)
	route_options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_column.add_child(route_options_box)

	var utility_row := HBoxContainer.new()
	utility_row.add_theme_constant_override("separation", 7)
	side_column.add_child(utility_row)
	bank_shortcut = _make_button("銀行", _on_bank_pressed)
	bank_shortcut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	utility_row.add_child(bank_shortcut)
	cards_shortcut = _make_button("卡片", _on_cards_pressed)
	cards_shortcut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	utility_row.add_child(cards_shortcut)
	stocks_shortcut = _make_button("股市", _on_stocks_pressed)
	stocks_shortcut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	utility_row.add_child(stocks_shortcut)
	return row

func _build_action_bar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 76.0)
	_apply_panel_style(panel, Color("#17283a"), PANEL_BORDER, 16, 1)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	var hint_column := VBoxContainer.new()
	hint_column.custom_minimum_size = Vector2(172.0, 0.0)
	hint_column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(hint_column)
	action_hint_label = _make_label("準備開始", 13, TEXT_MAIN)
	hint_column.add_child(action_hint_label)
	var hint := _make_label("SPACE 擲骰 · N 新局", 10, TEXT_MUTED)
	hint_column.add_child(hint)

	roll_button = _make_button("擲骰", _on_roll_pressed, true)
	roll_button.custom_minimum_size = Vector2(112.0, 52.0)
	row.add_child(roll_button)
	buy_button = _make_button("購買地產", _on_buy_pressed)
	buy_button.custom_minimum_size = Vector2(112.0, 52.0)
	row.add_child(buy_button)
	upgrade_button = _make_button("升級建設", _on_upgrade_pressed)
	upgrade_button.custom_minimum_size = Vector2(112.0, 52.0)
	row.add_child(upgrade_button)
	end_turn_button = _make_button("結束回合", _on_end_turn_pressed)
	end_turn_button.custom_minimum_size = Vector2(112.0, 52.0)
	row.add_child(end_turn_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	bank_button = _make_button("銀行", _on_bank_pressed)
	bank_button.custom_minimum_size = Vector2(92.0, 52.0)
	row.add_child(bank_button)
	cards_button = _make_button("卡片", _on_cards_pressed)
	cards_button.custom_minimum_size = Vector2(92.0, 52.0)
	row.add_child(cards_button)
	stocks_button = _make_button("股票", _on_stocks_pressed)
	stocks_button.custom_minimum_size = Vector2(92.0, 52.0)
	row.add_child(stocks_button)
	return panel

func _build_event_log() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 132.0)
	_apply_panel_style(panel, PANEL_BG, PANEL_BORDER, 16, 1)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _make_label("行動紀錄", 12, TEXT_MAIN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	event_status_label = _make_label("simulation log", 10, TEXT_MUTED)
	event_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(event_status_label)
	event_log_view = RichTextLabel.new()
	event_log_view.bbcode_enabled = false
	event_log_view.fit_content = false
	event_log_view.scroll_active = true
	event_log_view.scroll_following = true
	event_log_view.custom_minimum_size = Vector2(0.0, 80.0)
	event_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_log_view.add_theme_font_size_override("normal_font_size", 11)
	event_log_view.add_theme_color_override("default_color", TEXT_MUTED)
	column.add_child(event_log_view)
	return panel

func _build_popups() -> void:
	new_game_popup = _make_popup(Vector2i(760, 680))
	new_game_popup.wrap_controls = false
	var new_game_box := _popup_box(new_game_popup)
	new_game_box.add_child(_make_label("建立新局", 19, TEXT_MAIN))
	var new_game_description := _make_label("選擇地圖、玩家數與可重現的 seed；seed 留白會自動產生。", 11, TEXT_MUTED)
	new_game_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	new_game_box.add_child(new_game_description)
	setup_scroll = ScrollContainer.new()
	setup_scroll.name = "SetupScroll"
	setup_scroll.custom_minimum_size = Vector2(0.0, 148.0)
	setup_scroll.custom_maximum_size = Vector2(10000.0, 520.0)
	setup_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setup_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	new_game_box.add_child(setup_scroll)
	var setup_content := VBoxContainer.new()
	setup_content.name = "SetupContent"
	setup_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_content.add_theme_constant_override("separation", 7)
	setup_scroll.add_child(setup_content)
	var map_caption := _make_label("地圖", 11, TEXT_MUTED)
	setup_content.add_child(map_caption)
	var map_selector_row := HBoxContainer.new()
	map_selector_row.add_theme_constant_override("separation", 8)
	setup_content.add_child(map_selector_row)
	map_selector = OptionButton.new()
	map_selector.custom_minimum_size = Vector2(0.0, 38.0)
	map_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_selector.add_theme_font_size_override("font_size", 12)
	map_selector.item_selected.connect(_on_map_selected)
	map_selector_row.add_child(map_selector)
	var map_catalog_button := _make_button("讀取本機 catalog", _on_map_catalog_pressed)
	map_catalog_button.custom_minimum_size = Vector2(152.0, 38.0)
	map_selector_row.add_child(map_catalog_button)
	map_catalog_status_label = _make_label("尚未載入地圖目錄。", 10, TEXT_MUTED)
	map_catalog_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_content.add_child(map_catalog_status_label)
	var preview_script: Variant = load("res://game/ui/board_view.gd")
	if preview_script != null:
		map_preview_view = preview_script.new()
	else:
		map_preview_view = _make_label("地圖預覽載入中…", 14, TEXT_MUTED)
	map_preview_view.custom_minimum_size = Vector2(0.0, 248.0)
	map_preview_view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	map_preview_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_content.add_child(map_preview_view)
	map_preview_status_label = _make_label("", 11, TEXT_MUTED)
	map_preview_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_content.add_child(map_preview_status_label)
	var seed_caption := _make_label("Seed", 11, TEXT_MUTED)
	setup_content.add_child(seed_caption)
	seed_input = LineEdit.new()
	seed_input.placeholder_text = "留白以使用新 seed"
	seed_input.custom_minimum_size = Vector2(0.0, 38.0)
	seed_input.add_theme_font_size_override("font_size", 13)
	setup_content.add_child(seed_input)
	var players_caption := _make_label("玩家人數", 11, TEXT_MUTED)
	setup_content.add_child(players_caption)
	player_count_option = OptionButton.new()
	player_count_option.custom_minimum_size = Vector2(0.0, 38.0)
	player_count_option.add_theme_font_size_override("font_size", 12)
	player_count_option.add_item("2 位玩家", 2)
	player_count_option.add_item("3 位玩家", 3)
	player_count_option.add_item("4 位玩家", 4)
	player_count_option.select(2)
	player_count_option.item_selected.connect(_on_player_count_selected)
	setup_content.add_child(player_count_option)
	setup_content.add_child(_make_label("開局條件", 11, TEXT_MUTED))
	initial_fund_option = _make_setup_option(SETUP_INITIAL_FUNDS, "資金", " 元", 1)
	setup_content.add_child(initial_fund_option.get_meta("row"))
	day_limit_option = _make_setup_option(SETUP_DAY_LIMITS, "期限", " 天", 0)
	setup_content.add_child(day_limit_option.get_meta("row"))
	wealth_multiplier_option = _make_setup_option(SETUP_WEALTH_MULTIPLIERS, "財富目標", " 倍", 0)
	setup_content.add_child(wealth_multiplier_option.get_meta("row"))
	setup_content.add_child(_make_label("起始日期（預設取系統日期）", 11, TEXT_MUTED))
	var date_row := HBoxContainer.new()
	date_row.add_theme_constant_override("separation", 6)
	setup_content.add_child(date_row)
	start_year_input = _make_date_spinbox(MIN_START_YEAR, MAX_START_YEAR, 120.0)
	start_year_input.name = "StartYear"
	date_row.add_child(start_year_input)
	date_row.add_child(_make_label("年", 11, TEXT_MUTED))
	start_month_input = _make_date_spinbox(1, 12, 74.0)
	start_month_input.name = "StartMonth"
	date_row.add_child(start_month_input)
	date_row.add_child(_make_label("月", 11, TEXT_MUTED))
	start_day_input = _make_date_spinbox(1, 31, 74.0)
	start_day_input.name = "StartDay"
	date_row.add_child(start_day_input)
	date_row.add_child(_make_label("日", 11, TEXT_MUTED))
	start_year_input.value_changed.connect(_on_setup_date_component_changed)
	start_month_input.value_changed.connect(_on_setup_date_component_changed)
	start_day_input.value_changed.connect(_on_setup_date_component_changed)
	setup_content.add_child(_make_label("角色（每位玩家必須使用不同角色）", 11, TEXT_MUTED))
	character_rows = VBoxContainer.new()
	character_rows.name = "CharacterRows"
	character_rows.add_theme_constant_override("separation", 5)
	setup_content.add_child(character_rows)
	setup_error_label = _make_label("", 10, Color("#f28d83"))
	setup_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_content.add_child(setup_error_label)
	var new_game_actions := HBoxContainer.new()
	new_game_actions.add_theme_constant_override("separation", 8)
	new_game_box.add_child(new_game_actions)
	var new_game_cancel := _make_button("取消", new_game_popup.hide)
	new_game_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_game_actions.add_child(new_game_cancel)
	new_game_confirm_button = _make_button("開始新局", _on_new_game_confirm, true)
	new_game_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_game_actions.add_child(new_game_confirm_button)
	_rebuild_character_controls(4)

	bank_popup = _make_popup(Vector2i(430, 276))
	var bank_box := _popup_box(bank_popup)
	bank_box.add_child(_make_label("銀行帳戶", 19, TEXT_MAIN))
	var bank_description := _make_label("管理現金與存款。每次操作金額為 $500。", 11, TEXT_MUTED)
	bank_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bank_box.add_child(bank_description)
	var bank_balance := _make_label("", 14, TEXT_GOLD)
	bank_balance.name = "Balance"
	bank_box.add_child(bank_balance)
	var bank_actions := HBoxContainer.new()
	bank_actions.add_theme_constant_override("separation", 8)
	bank_box.add_child(bank_actions)
	bank_deposit_button = _make_button("存入 $500", _on_deposit_pressed, true)
	var deposit := bank_deposit_button
	deposit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bank_actions.add_child(deposit)
	bank_withdraw_button = _make_button("提取 $500", _on_withdraw_pressed)
	var withdraw := bank_withdraw_button
	withdraw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bank_actions.add_child(withdraw)
	var bank_close := _make_button("關閉", bank_popup.hide)
	bank_box.add_child(bank_close)

	cards_popup = _make_popup(Vector2i(560, 380))
	var cards_box := _popup_box(cards_popup)
	cards_box.add_child(_make_label("持有卡片", 19, TEXT_MAIN))
	var cards_description := _make_label("選擇一張卡片使用；效果由模擬層判定。", 11, TEXT_MUTED)
	cards_box.add_child(cards_description)
	cards_popup_list = VBoxContainer.new()
	cards_popup_list.add_theme_constant_override("separation", 7)
	cards_box.add_child(cards_popup_list)
	var cards_close := _make_button("關閉", cards_popup.hide)
	cards_box.add_child(cards_close)

	stocks_popup = _make_popup(Vector2i(500, 360))
	var stocks_box := _popup_box(stocks_popup)
	stocks_box.add_child(_make_label("股票市場", 19, TEXT_MAIN))
	var stocks_description := _make_label("每次買賣一股；報價由目前市場快照提供。", 11, TEXT_MUTED)
	stocks_box.add_child(stocks_description)
	stocks_popup_list = VBoxContainer.new()
	stocks_popup_list.add_theme_constant_override("separation", 7)
	stocks_box.add_child(stocks_popup_list)
	var stocks_close := _make_button("關閉", stocks_popup.hide)
	stocks_box.add_child(stocks_close)

	audio_folder_dialog = FileDialog.new()
	audio_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	audio_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	audio_folder_dialog.title = "選擇原版遊戲資料夾"
	audio_folder_dialog.ok_button_text = "使用此資料夾"
	audio_folder_dialog.dir_selected.connect(_on_audio_folder_selected)
	add_child(audio_folder_dialog)

	map_catalog_file_dialog = FileDialog.new()
	map_catalog_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	map_catalog_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	map_catalog_file_dialog.title = "選擇本機原版地圖 catalog.json"
	map_catalog_file_dialog.ok_button_text = "載入地圖目錄"
	map_catalog_file_dialog.filters = PackedStringArray(["*.json ; 地圖目錄 (catalog.json)"])
	map_catalog_file_dialog.file_selected.connect(_on_map_catalog_file_selected)
	add_child(map_catalog_file_dialog)

func _make_setup_option(values: Array, caption: String, suffix: String, default_index: int) -> OptionButton:
	var row := HBoxContainer.new()
	row.name = caption
	row.add_theme_constant_override("separation", 8)
	var label := _make_label(caption, 11, TEXT_MAIN)
	label.custom_minimum_size = Vector2(92.0, 0.0)
	row.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(0.0, 34.0)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override("font_size", 11)
	for value in values:
		var number := int(value)
		var text := "不限" if number == 0 and caption != "資金" else _format_money(number) if caption == "資金" else "%d%s" % [number, suffix]
		option.add_item(text, number)
	option.select(clampi(default_index, 0, max(0, option.item_count - 1)))
	row.add_child(option)
	option.set_meta("row", row)
	return option

func _make_date_spinbox(low: int, high: int, width: float) -> SpinBox:
	var field := SpinBox.new()
	field.min_value = low
	field.max_value = high
	field.step = 1
	field.allow_greater = false
	field.allow_lesser = false
	field.custom_minimum_size = Vector2(width, 34.0)
	field.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	field.add_theme_font_size_override("font_size", 11)
	return field

func _select_option_id(option: OptionButton, value: int) -> bool:
	if option == null:
		return false
	for index in range(option.item_count):
		if option.get_item_id(index) == value:
			option.select(index)
			return true
	return false

func _system_start_date() -> Dictionary:
	var system_date: Variant = Time.get_date_dict_from_system()
	if system_date is Dictionary and GameCalendar.is_valid(system_date):
		return {"year": int(system_date.get("year", 0)), "month": int(system_date.get("month", 0)), "day": int(system_date.get("day", 0))}
	return {}

func _default_setup_options(player_count: int) -> Dictionary:
	var date := _system_start_date()
	if date.is_empty():
		date = {"year": 1998, "month": 1, "day": 1}
	var character_ids: Array = []
	for player_id in range(player_count):
		character_ids.append(player_id)
	return {
		"initial_fund": 200000,
		"day_limit": 0,
		"wealth_multiplier": 0,
		"start_date": date,
		"character_ids": character_ids,
	}

func _character_ids_from_controls() -> Array:
	var ids: Array = []
	for option in character_options:
		if option != null:
			ids.append(option.get_selected_id())
	return ids

func _rebuild_character_controls(player_count: int, preferred_ids: Array = []) -> void:
	if character_rows == null:
		return
	var previous_ids := _character_ids_from_controls()
	for child in character_rows.get_children():
		child.free()
	character_options.clear()
	for player_id in range(player_count):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := _make_label("玩家 %d" % (player_id + 1), 11, TEXT_MAIN)
		label.custom_minimum_size = Vector2(92.0, 0.0)
		row.add_child(label)
		var option := OptionButton.new()
		option.name = "Character%d" % player_id
		option.custom_minimum_size = Vector2(0.0, 34.0)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_theme_font_size_override("font_size", 11)
		for character_id in range(CHARACTER_NAMES.size()):
			option.add_item("%02d · %s" % [character_id, CHARACTER_NAMES[character_id]], character_id)
		var selected_id := player_id
		if player_id < preferred_ids.size() and int(preferred_ids[player_id]) >= 0 and int(preferred_ids[player_id]) < CHARACTER_NAMES.size():
			selected_id = int(preferred_ids[player_id])
		elif player_id < previous_ids.size() and int(previous_ids[player_id]) >= 0 and int(previous_ids[player_id]) < CHARACTER_NAMES.size():
			selected_id = int(previous_ids[player_id])
		option.select(selected_id)
		option.item_selected.connect(_on_character_selected)
		row.add_child(option)
		character_rows.add_child(row)
		character_options.append(option)

func _on_character_selected(_index: int) -> void:
	_update_setup_validation(false)

func _on_player_count_selected(_index: int) -> void:
	var count := player_count_option.get_selected_id()
	_rebuild_character_controls(count)
	_update_setup_validation(false)

func _on_setup_date_component_changed(_value: float) -> void:
	_update_setup_validation(false)

func _setup_date_from_controls() -> Dictionary:
	if start_year_input == null or start_month_input == null or start_day_input == null:
		return {}
	return {"year": int(start_year_input.value), "month": int(start_month_input.value), "day": int(start_day_input.value)}

func _setup_options_from_state() -> Dictionary:
	var player_count := int(_as_array(state.get("players", [])).size())
	if player_count < 2 or player_count > 4:
		return {}
	var start_date: Variant = state.get("start_date", null)
	if not start_date is Dictionary or not GameCalendar.is_valid(start_date):
		return {}
	var character_ids: Array = []
	for player in state.get("players", []):
		if not player is Dictionary or not player.has("character_id"):
			return {}
		character_ids.append(int(player.get("character_id", -1)))
	return {
		"initial_fund": int(state.get("initial_fund", 200000)),
		"day_limit": int(state.get("day_limit", 0)),
		"wealth_multiplier": int(state.get("wealth_multiplier", 0)),
		"start_date": {"year": int(start_date.get("year", 0)), "month": int(start_date.get("month", 0)), "day": int(start_date.get("day", 0))},
		"character_ids": character_ids,
	}

func _populate_setup_controls() -> void:
	var player_count := int(_as_array(state.get("players", [])).size())
	if player_count < 2 or player_count > 4:
		player_count = PLAYER_COUNT
	_select_option_id(player_count_option, player_count)
	var initial_fund := int(state.get("initial_fund", 200000))
	if not SETUP_INITIAL_FUNDS.has(initial_fund):
		initial_fund = 200000
	_select_option_id(initial_fund_option, initial_fund)
	var day_limit := int(state.get("day_limit", 0))
	if not SETUP_DAY_LIMITS.has(day_limit):
		day_limit = 0
	_select_option_id(day_limit_option, day_limit)
	var wealth_multiplier := int(state.get("wealth_multiplier", 0))
	if not SETUP_WEALTH_MULTIPLIERS.has(wealth_multiplier):
		wealth_multiplier = 0
	_select_option_id(wealth_multiplier_option, wealth_multiplier)
	var date_value: Variant = state.get("start_date", null)
	var date: Dictionary = date_value.duplicate(true) if date_value is Dictionary and GameCalendar.is_valid(date_value) else _system_start_date()
	if date.is_empty():
		date = {"year": MIN_START_YEAR, "month": 1, "day": 1}
	start_year_input.value = int(date.get("year", MIN_START_YEAR))
	start_month_input.value = int(date.get("month", 1))
	start_day_input.value = int(date.get("day", 1))
	var preferred_ids: Array = []
	for player in state.get("players", []):
		if player is Dictionary and player.has("character_id"):
			preferred_ids.append(int(player.get("character_id", -1)))
	_rebuild_character_controls(player_count, preferred_ids)
	_update_setup_validation(false)

func _set_setup_error(message: String) -> void:
	if setup_error_label != null:
		setup_error_label.text = message

func _collect_setup_options() -> Dictionary:
	if initial_fund_option == null or day_limit_option == null or wealth_multiplier_option == null or player_count_option == null:
		return {"ok": false, "message": "開局設定尚未載入。"}
	var initial_fund := initial_fund_option.get_selected_id()
	if not SETUP_INITIAL_FUNDS.has(initial_fund):
		return {"ok": false, "message": "開局資金選項無效。"}
	var day_limit := day_limit_option.get_selected_id()
	if not SETUP_DAY_LIMITS.has(day_limit):
		return {"ok": false, "message": "期限選項無效。"}
	var wealth_multiplier := wealth_multiplier_option.get_selected_id()
	if not SETUP_WEALTH_MULTIPLIERS.has(wealth_multiplier):
		return {"ok": false, "message": "財富目標選項無效。"}
	var start_date := _setup_date_from_controls()
	if not GameCalendar.is_valid(start_date):
		return {"ok": false, "message": "起始日期不存在，請檢查年月日。"}
	var player_count := player_count_option.get_selected_id()
	if player_count < 2 or player_count > 4 or character_options.size() != player_count:
		return {"ok": false, "message": "玩家人數設定無效。"}
	var character_ids := _character_ids_from_controls()
	var seen: Dictionary = {}
	for character_id in character_ids:
		if character_id < 0 or character_id >= CHARACTER_NAMES.size():
			return {"ok": false, "message": "角色選擇無效。"}
		if seen.has(character_id):
			return {"ok": false, "message": "每位玩家必須選擇不同角色。"}
		seen[character_id] = true
	return {"ok": true, "options": {
		"initial_fund": initial_fund,
		"day_limit": day_limit,
		"wealth_multiplier": wealth_multiplier,
		"start_date": start_date,
		"character_ids": character_ids,
	}}

func _update_setup_validation(show_message: bool) -> void:
	if not show_message:
		_set_setup_error("")
		return
	var validation := _collect_setup_options()
	_set_setup_error("" if bool(validation.get("ok", false)) else str(validation.get("message", "開局設定無效。")))

func _build_end_overlay() -> void:
	end_overlay = ColorRect.new()
	end_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_overlay.color = Color(0.03, 0.08, 0.13, 0.84)
	end_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(end_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430.0, 250.0)
	_apply_panel_style(panel, Color("#20394b"), Color("#d9a958"), 18, 2)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	end_title = _make_label("本局結算", 28, TEXT_GOLD)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(end_title)
	end_detail = _make_label("", 13, TEXT_MAIN)
	end_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(end_detail)
	var restart := _make_button("開始新局", _on_end_restart_pressed, true)
	restart.custom_minimum_size = Vector2(0.0, 48.0)
	column.add_child(restart)
	var close := _make_button("返回棋盤", _close_end_overlay)
	close.custom_minimum_size = Vector2(0.0, 38.0)
	column.add_child(close)
	end_overlay.hide()

func _make_popup(size: Vector2i) -> PopupPanel:
	var popup := PopupPanel.new()
	popup.size = size
	popup.add_theme_stylebox_override("panel", _style_box(Color("#203447"), Color("#54748a"), 16, 1))
	add_child(popup)
	return popup

func _popup_box(popup: PopupPanel) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	popup.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)
	return box

func _load_map_catalog(path: String = "") -> void:
	var result: Dictionary = OriginalMaps.load_catalog(path)
	_map_catalog_path = path if not path.is_empty() else OriginalMaps.default_catalog_path()
	_map_catalog_ok = bool(result.get("ok", false)) and _as_array(result.get("maps", [])).size() > 0
	_map_catalog_error = str(result.get("error", ""))
	if _map_catalog_ok:
		_map_catalog = _as_array(result.get("maps", [])).duplicate(true)
		_selected_map_definition = {}
		for index in range(_map_catalog.size()):
			var definition: Dictionary = _map_catalog[index] if _map_catalog[index] is Dictionary else {}
			if _map_is_playable(definition):
				_selected_map_definition = definition.duplicate(true)
				break
		if _selected_map_definition.is_empty() and not _map_catalog.is_empty():
			_selected_map_definition = (_map_catalog[0] as Dictionary).duplicate(true)
	else:
		_map_catalog = [_make_fallback_map_definition()]
		_selected_map_definition = (_map_catalog[0] as Dictionary).duplicate(true)
	_update_map_selector()

func _make_fallback_map_definition() -> Dictionary:
	var state_script: Variant = load("res://game/core/game_state.gd")
	if state_script != null and state_script.has_method("new_game"):
		var candidate: Variant = state_script.new_game(DEFAULT_SEED, PLAYER_COUNT)
		if candidate != null and candidate.has_method("get_snapshot"):
			var snapshot: Variant = candidate.get_snapshot()
			if snapshot is Dictionary:
				var candidate_board: Variant = snapshot.get("board", [])
				if candidate_board is Array and not candidate_board.is_empty():
					return {"schema": "richman4.runtime-map/v1", "version": 1, "id": FALLBACK_MAP_ID,
						"name": "測試棋盤（%d 格）" % candidate_board.size(),
						"source": {"edition": "Test", "map_number": 0}, "board": candidate_board.duplicate(true),
						"start_position": 0, "supports_new_game": true, "unsupported_reason": ""}
	var side := 11
	var cells: Array[Vector2i] = []
	for x in range(side):
		cells.append(Vector2i(x, 0))
	for y in range(1, side):
		cells.append(Vector2i(side - 1, y))
	for x in range(side - 2, -1, -1):
		cells.append(Vector2i(x, side - 1))
	for y in range(side - 2, 0, -1):
		cells.append(Vector2i(0, y))
	var board: Array = []
	for index in range(cells.size()):
		var kind := "property" if index > 0 and index % 4 != 0 else "rest"
		var name := "測試道路 %02d" % (index + 1)
		if index == 0:
			kind = "start"
			name = "測試起點"
		elif kind == "rest":
			name = "測試休息 %02d" % (index + 1)
		board.append({"index": index, "source_node_id": index + 1, "kind": kind, "name": name,
			"owner": -1, "building_level": 0, "cost": 1000 + index * 100 if kind == "property" else 0,
			"upgrade_cost": 300 if kind == "property" else 0, "base_rent": 100 if kind == "property" else 0,
			"rent": 100 if kind == "property" else 0, "group": "test", "tax_amount": 0})
	return {"schema": "richman4.runtime-map/v1", "version": 1, "id": FALLBACK_MAP_ID,
		"name": "測試棋盤（%d 格）" % board.size(), "source": {"edition": "Test", "map_number": 0}, "board": board,
		"start_position": 0, "supports_new_game": true, "unsupported_reason": ""}

func _update_map_selector() -> void:
	if map_selector == null:
		return
	map_selector.clear()
	var selected_index := 0
	for index in range(_map_catalog.size()):
		var definition: Dictionary = _map_catalog[index] if _map_catalog[index] is Dictionary else {}
		var label := str(definition.get("name", "地圖 %d" % (index + 1)))
		if not _map_is_playable(definition):
			label += "（僅預覽）"
		map_selector.add_item(label, index)
		if not _selected_map_definition.is_empty() and str(definition.get("id", "")) == str(_selected_map_definition.get("id", "")):
			selected_index = index
	map_selector.select(selected_index)
	if selected_index >= 0 and selected_index < _map_catalog.size():
		_selected_map_definition = (_map_catalog[selected_index] as Dictionary).duplicate(true)
	if _map_catalog_ok:
		map_catalog_status_label.text = "已載入本機原版地圖 %d 張。" % _map_catalog.size()
	else:
		var reason := _map_catalog_error if not _map_catalog_error.is_empty() else "尚未匯入本機原版地圖。"
		map_catalog_status_label.text = "未找到本機原版地圖，使用明確測試棋盤。\n%s" % reason
	_update_map_preview()

func _on_map_selected(index: int) -> void:
	if index < 0 or index >= _map_catalog.size() or not _map_catalog[index] is Dictionary:
		return
	_selected_map_definition = (_map_catalog[index] as Dictionary).duplicate(true)
	_update_map_preview()

func _on_map_catalog_pressed() -> void:
	if map_catalog_file_dialog != null:
		map_catalog_file_dialog.popup_centered_ratio(0.78)

func _on_map_catalog_file_selected(path: String) -> void:
	_load_map_catalog(path)
	_append_local_log("已讀取本機地圖目錄。") if _map_catalog_ok else _append_local_log("地圖目錄讀取失敗，已回到測試棋盤。")
	_refresh_log_only()

func _extract_map_identity(snapshot: Dictionary) -> Variant:
	if snapshot.has("map_id"):
		return {"id": str(snapshot.get("map_id", "")), "name": str(snapshot.get("map_name", "")),
			"schema": str(snapshot.get("map_schema", "richman4.runtime-map/v1")),
			"version": int(snapshot.get("map_version", 1)), "source": snapshot.get("map_source", {})}
	for key in ["map_identity", "map_definition", "map"]:
		if snapshot.has(key) and snapshot[key] is Dictionary:
			var identity: Dictionary = snapshot[key].duplicate(true)
			identity.erase("board")
			return identity
	return null

func _snapshot_graph_definition(snapshot: Dictionary) -> Dictionary:
	if snapshot.get("board_mode", "") != "graph" or not snapshot.has("map_id") or not snapshot.has("board"):
		return {}
	var board: Variant = snapshot.get("board", [])
	var source: Variant = snapshot.get("map_source", {})
	if not board is Array or not source is Dictionary:
		return {}
	var map_id := str(snapshot.get("map_id", ""))
	if map_id.is_empty():
		return {}
	return {"schema": str(snapshot.get("map_schema", "richman4.runtime-map/v1")),
		"version": int(snapshot.get("map_version", 1)), "id": map_id,
		"name": str(snapshot.get("map_name", "")), "source": source.duplicate(true),
		"board": board.duplicate(true), "start_position": int(snapshot.get("start_position", 0)),
		"supports_new_game": true, "unsupported_reason": ""}

func _map_source_matches(left: Variant, right: Variant) -> bool:
	if not left is Dictionary or not right is Dictionary:
		return false
	for key in ["edition", "map_number", "archive", "entry_index", "payload_sha256", "source_file_sha256"]:
		if str(left.get(key, "")) != str(right.get(key, "")):
			return false
	return true

func _resolve_map_identity(identity: Variant) -> Dictionary:
	var identity_id := ""
	var identity_source: Variant = null
	if identity is Dictionary:
		identity_id = str(identity.get("id", ""))
		identity_source = identity.get("source", null)
	elif identity is String:
		identity_id = identity
	if not identity_id.is_empty():
		for definition_value in _map_catalog:
			if definition_value is Dictionary and str(definition_value.get("id", "")) == identity_id and (identity_source == null or _map_source_matches(identity_source, definition_value.get("source", {}))):
				return definition_value.duplicate(true)
	if identity is Dictionary:
		var resolved_identity: Dictionary = identity.duplicate(true)
		resolved_identity.erase("board")
		return resolved_identity
	return {}

func _adopt_map_from_snapshot(snapshot: Dictionary) -> void:
	var graph_definition := _snapshot_graph_definition(snapshot)
	if not graph_definition.is_empty():
		_active_map_definition = graph_definition
		var graph_id := str(graph_definition.get("id", ""))
		var graph_source: Variant = graph_definition.get("source", {})
		for index in range(_map_catalog.size()):
			var catalog_definition: Variant = _map_catalog[index]
			if catalog_definition is Dictionary and str(catalog_definition.get("id", "")) == graph_id and _map_source_matches(graph_source, catalog_definition.get("source", {})):
				_selected_map_definition = catalog_definition.duplicate(true)
				if map_selector != null:
					map_selector.select(index)
				break
		return
	if int(snapshot.get("version", -1)) == 1:
		_active_map_definition = _make_fallback_map_definition()
		return
	if snapshot.get("board_mode", "") != "graph":
		_active_map_definition = _make_fallback_map_definition()
		return
	var raw_identity: Variant = _extract_map_identity(snapshot)
	if raw_identity == null:
		return
	var resolved := _resolve_map_identity(raw_identity)
	if resolved.is_empty():
		return
	_active_map_definition = resolved
	var active_id := str(resolved.get("id", ""))
	if active_id.is_empty():
		return
	for index in range(_map_catalog.size()):
		if _map_catalog[index] is Dictionary and str(_map_catalog[index].get("id", "")) == active_id:
			_selected_map_definition = (_map_catalog[index] as Dictionary).duplicate(true)
			if map_selector != null:
				map_selector.select(index)
			break

func _update_map_preview() -> void:
	if map_preview_view != null and map_preview_view.has_method("set_preview_definition"):
		map_preview_view.call("set_preview_definition", _selected_map_definition)
	if map_preview_status_label == null:
		return
	if _selected_map_definition.is_empty():
		map_preview_status_label.text = "尚無可預覽的地圖。"
		return
	var board: Array = _as_array(_selected_map_definition.get("board", []))
	if _map_is_playable(_selected_map_definition):
		map_preview_status_label.text = "可開始新局 · %d 格路網。" % board.size()
	else:
		map_preview_status_label.text = "僅供預覽：%s" % str(_selected_map_definition.get("unsupported_reason", "此地圖尚未開放對局。"))
	if new_game_confirm_button != null:
		new_game_confirm_button.disabled = not _map_is_playable(_selected_map_definition)

func _map_is_playable(definition: Dictionary) -> bool:
	return not definition.is_empty() and bool(definition.get("supports_new_game", false))

func _is_fallback_definition(definition: Dictionary) -> bool:
	return str(definition.get("id", "")) == FALLBACK_MAP_ID

func _on_new_game_pressed() -> void:
	if new_game_popup == null:
		_restart_game()
		return
	if not _active_map_definition.is_empty():
		_selected_map_definition = _active_map_definition.duplicate(true)
	_update_map_selector()
	var current_seed: Variant = state.get("seed", null)
	seed_input.text = str(current_seed) if current_seed != null and int(current_seed) >= MIN_SEED and int(current_seed) <= MAX_SEED else ""
	_populate_setup_controls()
	_set_setup_error("")
	new_game_popup.popup_centered(Vector2i(760, 680))
	new_game_popup.set_size(Vector2i(760, 680))
	seed_input.grab_focus()

func _on_new_game_confirm() -> void:
	if not _map_is_playable(_selected_map_definition):
		_append_local_log("此地圖目前僅供預覽，無法開始新局。")
		_refresh_log_only()
		return
	var setup_validation := _collect_setup_options()
	if not bool(setup_validation.get("ok", false)):
		_set_setup_error(str(setup_validation.get("message", "開局設定無效。")))
		_append_local_log(str(setup_validation.get("message", "開局設定無效。")))
		_refresh_log_only()
		return
	var requested_seed: Variant = null
	if not seed_input.text.strip_edges().is_empty():
		if not seed_input.text.strip_edges().is_valid_int():
			_append_local_log("Seed 必須是整數，或留白自動產生。")
			_refresh_log_only()
			return
		requested_seed = int(seed_input.text.strip_edges())
		if requested_seed < MIN_SEED or requested_seed > MAX_SEED:
			_append_local_log("Seed 必須介於 -2147483648 與 2147483647。")
			_refresh_log_only()
			return
	var requested_players := player_count_option.get_selected_id()
	var before_game := game_state
	var before_seed := int(state.get("seed", MIN_SEED - 1))
	if _new_game(requested_seed, requested_players, _selected_map_definition, setup_validation["options"]):
		new_game_popup.hide()
	else:
		_set_setup_error("新局建立失敗，目前棋局保持不變。")
		if game_state == before_game and int(state.get("seed", MIN_SEED - 1)) == before_seed:
			_refresh_log_only()

func _new_game(seed_value: Variant = null, player_count: int = PLAYER_COUNT, map_definition: Dictionary = {}, setup_options: Dictionary = {}) -> bool:
	var resolved_seed: int
	if seed_value == null:
		resolved_seed = int(Time.get_unix_time_from_system()) % 2147483647
	else:
		resolved_seed = int(seed_value)
	if player_count < 2 or player_count > 4:
		_append_local_log("玩家人數必須介於 2 與 4。")
		_refresh_log_only()
		return false
	var resolved_players: int = player_count
	var selected_definition := map_definition.duplicate(true) if not map_definition.is_empty() else _selected_map_definition.duplicate(true)
	if not _map_is_playable(selected_definition):
		_append_local_log("此地圖目前僅供預覽，無法開始新局。")
		_refresh_log_only()
		return false
	var state_script: Variant = load("res://game/core/game_state.gd")
	var candidate: Variant = null
	if state_script != null:
		if not _is_fallback_definition(selected_definition) and state_script.has_method("new_game_on_board"):
			candidate = state_script.new_game_on_board(resolved_seed, resolved_players, selected_definition, setup_options) if not setup_options.is_empty() else state_script.new_game_on_board(resolved_seed, resolved_players, selected_definition)
		elif _is_fallback_definition(selected_definition) and state_script.has_method("new_game"):
			candidate = state_script.new_game(resolved_seed, resolved_players, setup_options) if not setup_options.is_empty() else state_script.new_game(resolved_seed, resolved_players)
	if candidate == null:
		if game_state == null and state.is_empty():
			state = _unavailable_state(resolved_seed)
			_append_local_log("模擬核心未載入；遊戲操作已停用。")
		else:
			_append_local_log("新局建立失敗；目前棋局保持不變。")
		_refresh_log_only()
		return false
	else:
		game_state = candidate
		_active_map_definition = selected_definition
		_local_log.clear()
		_append_local_log("已建立新局 · seed %d · %d 位玩家。" % [resolved_seed, resolved_players])
	_refresh_from_state()
	end_overlay.hide()
	_ai_pending = false
	return true

func _setup_audio() -> void:
	var audio_script: Variant = load("res://game/platform/original_audio.gd")
	if audio_script == null:
		audio_button.disabled = true
		audio_config_button.disabled = true
		return
	audio_controller = audio_script.new()
	add_child(audio_controller)
	if audio_controller.has_signal("playback_changed"):
		audio_controller.playback_changed.connect(_on_audio_playback_changed)
	_update_audio_button()

func _on_audio_pressed() -> void:
	if audio_controller == null:
		_append_local_log("音樂模組尚未載入。")
		_refresh_log_only()
		return
	var tracks: Variant = audio_controller.get("tracks")
	if tracks is PackedStringArray and tracks.is_empty():
		_on_audio_config_pressed()
		return
	var enabled := bool(audio_controller.get("enabled"))
	audio_controller.call("set_enabled", not enabled)
	_append_local_log("原版音樂已%s。" % ("開啟" if not enabled else "關閉"))
	_update_audio_button()
	_refresh_log_only()

func _on_audio_config_pressed() -> void:
	if audio_folder_dialog == null:
		_append_local_log("音樂設定暫時無法使用。")
		_refresh_log_only()
		return
	audio_folder_dialog.popup_centered_ratio(0.72)

func _on_audio_folder_selected(path: String) -> void:
	if audio_controller == null:
		return
	var configured: Variant = audio_controller.call("configure", path)
	if bool(configured):
		_append_local_log("已載入原版音樂資料夾，共 %d 首。" % int(audio_controller.get("tracks").size()))
	else:
		_append_local_log("選取的資料夾找不到 Media/Music/*.ogg。")
	_update_audio_button()
	_refresh_log_only()

func _on_audio_playback_changed(track_name: String) -> void:
	if event_status_label != null:
		event_status_label.text = "播放：%s" % track_name

func _update_audio_button() -> void:
	if audio_button == null or audio_controller == null:
		return
	var enabled := bool(audio_controller.get("enabled"))
	var tracks: Variant = audio_controller.get("tracks")
	if tracks is PackedStringArray and tracks.is_empty():
		audio_button.text = "音樂"
	else:
		audio_button.text = "音樂 開" if enabled else "音樂 關"

func _save_game() -> void:
	if game_state == null or not game_state.has_method("to_dict"):
		_append_local_log("儲存失敗：模擬核心未載入。")
		_refresh_log_only()
		return
	var serialized: Variant = game_state.call("to_dict")
	if not serialized is Dictionary:
		_append_local_log("儲存失敗：模擬核心未提供有效快照。")
		_refresh_log_only()
		return
	var payload: Dictionary = serialized
	var json_text := JSON.stringify(payload)
	var parsed: Variant = JSON.parse_string(json_text)
	var state_script: Variant = load("res://game/core/game_state.gd")
	if not parsed is Dictionary or state_script == null or not state_script.has_method("from_dict") or state_script.from_dict(parsed) == null:
		_append_local_log("儲存失敗：快照驗證未通過，原有存檔保持不變。")
		_refresh_log_only()
		return
	var temporary_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		_append_local_log("儲存失敗：無法建立暫存檔。")
		_refresh_log_only()
		return
	file.store_string(json_text)
	file.close()
	var verify_file := FileAccess.open(temporary_path, FileAccess.READ)
	var verify_text := verify_file.get_as_text() if verify_file != null else ""
	if verify_file != null:
		verify_file.close()
	var verify_payload: Variant = JSON.parse_string(verify_text)
	if not verify_payload is Dictionary or state_script.from_dict(verify_payload) == null:
		DirAccess.remove_absolute(temporary_path)
		_append_local_log("儲存失敗：暫存檔驗證未通過，原有存檔保持不變。")
		_refresh_log_only()
		return
	if DirAccess.rename_absolute(temporary_path, SAVE_PATH) != OK:
		DirAccess.remove_absolute(temporary_path)
		_append_local_log("儲存失敗：無法安全替換存檔，原有存檔保持不變。")
		_refresh_log_only()
		return
	_append_local_log("已安全儲存棋局 · seed %s。" % str(payload.get("seed", "?")))
	_refresh_log_only()

func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_append_local_log("找不到存檔；先建立一局再儲存即可。")
		_refresh_log_only()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_append_local_log("讀取失敗：無法開啟本機存檔。")
		_refresh_log_only()
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_append_local_log("讀取失敗：存檔格式無效。")
		_refresh_log_only()
		return
	var state_script: Variant = load("res://game/core/game_state.gd")
	if state_script == null:
		_append_local_log("讀取失敗：模擬核心未載入，目前棋局保持不變。")
		_refresh_log_only()
		return
	if not state_script.has_method("from_dict"):
		_append_local_log("讀取失敗：模擬核心缺少存檔介面，目前棋局保持不變。")
		_refresh_log_only()
		return
	var restored: Variant = state_script.from_dict(parsed)
	if restored == null:
		_append_local_log("讀取失敗：存檔驗證未通過，目前棋局保持不變。")
		_refresh_log_only()
		return
	game_state = restored
	_adopt_map_from_snapshot(parsed)
	_local_log.clear()
	_append_local_log("已讀取棋局 · seed %s。" % str(parsed.get("seed", "?")))
	_refresh_from_state()
	end_overlay.hide()
	_ai_pending = false

func _on_roll_pressed() -> void:
	if roll_button.disabled:
		return
	var result := _invoke_game("roll")
	_append_local_log("你擲出 %s。" % _roll_text(result))
	_handle_result(result)

func _on_buy_pressed() -> void:
	if buy_button.disabled:
		return
	var result := _invoke_game("choose_action", ["buy", {}])
	_append_local_log("購買地產：%s" % _result_text(result, "已送出購買指令。"))
	_handle_result(result)

func _on_upgrade_pressed() -> void:
	if upgrade_button.disabled:
		return
	var result := _invoke_game("choose_action", ["upgrade", {}])
	_append_local_log("升級建設：%s" % _result_text(result, "已送出升級指令。"))
	_handle_result(result)

func _on_end_turn_pressed() -> void:
	if end_turn_button.disabled:
		return
	var result := _invoke_game("end_turn")
	_append_local_log("你結束了回合。")
	_handle_result(result)

func _on_deposit_pressed() -> void:
	var amount := mini(500, maxi(0, int(_current_player().get("cash", 0))))
	if amount <= 0:
		return
	var result := _invoke_game("choose_action", ["deposit", {"amount": amount}])
	_append_local_log("銀行存入 %s：%s" % [_format_money(amount), _result_text(result, "已送出存款指令。")])
	_handle_result(result)

func _on_withdraw_pressed() -> void:
	var amount := mini(500, int(_current_player().get("deposit", 0)))
	var result := _invoke_game("choose_action", ["withdraw", {"amount": amount}])
	_append_local_log("銀行提取 %s：%s" % [_format_money(amount), _result_text(result, "已送出提款指令。")])
	_handle_result(result)

func _on_cards_pressed() -> void:
	if not _is_human_turn():
		return
	_update_cards_popup()
	cards_popup.popup_centered()

func _on_stocks_pressed() -> void:
	if not _is_human_turn():
		return
	_update_stocks_popup()
	stocks_popup.popup_centered()

func _on_bank_pressed() -> void:
	if not _is_human_turn():
		return
	_update_bank_popup()
	bank_popup.popup_centered()

func _update_bank_popup() -> void:
	var balance: Label = bank_popup.get_node_or_null("MarginContainer/VBoxContainer/Balance")
	var player := _current_player()
	if balance != null:
		balance.text = "現金 %s　·　存款 %s" % [_format_money(int(player.get("cash", 0))), _format_money(int(player.get("deposit", 0)))]
	var options: Array = _as_array(state.get("action_options", []))
	var deposit_amount := mini(500, maxi(0, int(player.get("cash", 0))))
	bank_deposit_button.text = "存入 %s" % _format_money(deposit_amount)
	bank_deposit_button.disabled = not _has_action_option(options, "deposit") or deposit_amount <= 0
	bank_withdraw_button.disabled = not _has_action_option(options, "withdraw")
	bank_withdraw_button.text = "提取 %s" % _format_money(mini(500, int(player.get("deposit", 0))))

func _on_tile_selected(index: int) -> void:
	_selected_tile = index
	var tile := _tile_for_index(index)
	if not tile.is_empty():
		_update_property_card(tile)

func _on_route_selected(next_index: int) -> void:
	if not _is_human_turn():
		return
	var options := _as_array(state.get("route_options", []))
	if not _has_int_option(options, next_index):
		return
	var result := _invoke_game("choose_route", [next_index])
	_append_local_log("選擇前往 %s：%s" % [_tile_name(next_index), _result_text(result, "已送出路線選擇。")])
	_handle_result(result)

func _restart_game() -> void:
	var player_count := int(_as_array(state.get("players", [])).size())
	if player_count < 2 or player_count > 4:
		player_count = PLAYER_COUNT
	var seed_value: Variant = state.get("seed", null)
	var options := _setup_options_from_state()
	_new_game(seed_value, player_count, _active_map_definition, options)

func _on_end_restart_pressed() -> void:
	_restart_game()

func _close_end_overlay() -> void:
	end_overlay.hide()

func _is_human_turn() -> bool:
	var player := _current_player()
	return game_state != null and bool(player.get("is_human", false)) and not bool(player.get("bankrupt", true)) and state.get("phase", "") != "game_over"

func _invoke_game(method: String, args: Array = []) -> Dictionary:
	if method != "run_ai_turn" and not _is_human_turn():
		return {"ok": false, "message": "目前不是你的回合。"}
	if game_state != null and game_state.has_method(method):
		var result: Variant = game_state.callv(method, args)
		return result if result is Dictionary else {}
	return {"ok": false, "message": "模擬核心未載入；目前無法執行此操作。"}

func _handle_result(result: Dictionary) -> void:
	if result.is_empty():
		_append_local_log("模擬層未回傳事件；請查看目前回合狀態。")
	_refresh_from_state(result)

func _refresh_from_state(result: Dictionary = {}) -> void:
	var snapshot := _read_snapshot()
	if result.has("snapshot") and result["snapshot"] is Dictionary:
		snapshot = result["snapshot"]
	elif result.has("state") and result["state"] is Dictionary:
		snapshot = result["state"]
	if not snapshot.is_empty():
		state = snapshot.duplicate(true)
	_adopt_map_from_snapshot(state)
	_update_all()

func _read_snapshot() -> Dictionary:
	if game_state == null:
		return state
	if game_state.has_method("get_snapshot"):
		var snapshot: Variant = game_state.call("get_snapshot")
		if snapshot is Dictionary:
			return snapshot
	var public_state: Variant = game_state.get("state")
	if public_state is Dictionary:
		return public_state
	return state

func _update_all() -> void:
	var phase := String(state.get("phase", "await_roll"))
	var current_index := int(state.get("current_player", 0))
	var players: Array = state.get("players", [])
	var board: Array = state.get("board", [])
	if board_view != null and board_view.has_method("set_game_data"):
		board_view.call("set_game_data", board, players, current_index, _active_map_definition, _as_array(state.get("route_options", [])))
	_update_header(phase, current_index)
	_update_players(players, current_index)
	_update_property_card(_current_tile())
	_update_actions(phase, current_index)
	_update_route_choices(phase, current_index)
	if bank_popup.visible:
		_update_bank_popup()
	_update_event_log()
	_update_end_overlay(phase)
	_last_rendered_phase = phase

func _update_header(phase: String, current_index: int) -> void:
	seed_label.text = "SEED %s" % str(state.get("seed", "?"))
	turn_label.text = "第 %d 回合 · 第 %d 輪" % [int(state.get("turn", 1)), int(state.get("round", 1))]
	phase_label.text = _phase_text(phase)
	if setup_summary_label != null:
		setup_summary_label.text = _setup_summary_text()
	var map_name := str(_active_map_definition.get("name", ""))
	if map_name.is_empty():
		var identity: Variant = _extract_map_identity(state)
		map_name = str(identity.get("name", identity.get("id", "測試棋盤"))) if identity is Dictionary else str(identity) if identity is String else "測試棋盤"
	map_identity_label.text = "地圖 · %s" % map_name
	var player := _current_player()
	var is_human := bool(player.get("is_human", true))
	current_player_label.text = "你的回合" if is_human else "%s 的回合" % str(player.get("name", "AI"))

func _weekday_text(weekday: int) -> String:
	return ["未知", "一", "二", "三", "四", "五", "六", "日"][weekday] if weekday >= 1 and weekday <= 7 else "未知"

func _setup_summary_text() -> String:
	var raw_date: Variant = state.get("date", state.get("start_date", null))
	if raw_date is Dictionary and GameCalendar.is_valid(raw_date):
		var date: Dictionary = raw_date
		var date_text := "%04d/%02d/%02d 週%s" % [int(date.get("year", 0)), int(date.get("month", 0)), int(date.get("day", 0)), _weekday_text(int(state.get("weekday", GameCalendar.weekday(date))))]
		var day_limit := int(state.get("day_limit", 0))
		var wealth_multiplier := int(state.get("wealth_multiplier", 0))
		var limit_text := "期限不限" if day_limit == 0 else "限%d天" % day_limit
		var target_text := "目標不限"
		if wealth_multiplier > 0:
			var initial_fund := int(state.get("initial_fund", 200000))
			target_text = "目標%s（%d倍）" % [_format_money(initial_fund * wealth_multiplier), wealth_multiplier]
		return "%s · %s · %s" % [date_text, limit_text, target_text]
	return "舊版日期 · 第%d天 · 期限/目標未記錄" % int(state.get("day", 1))

func _update_players(players: Array, current_index: int) -> void:
	for child in players_list.get_children():
		child.free()
	for index in range(players.size()):
		var player: Dictionary = players[index] if players[index] is Dictionary else {}
		var row := PanelContainer.new()
		var active := index == current_index
		_apply_panel_style(row, Color("#2a4355") if active else Color("#203447"), Color("#d9a958") if active else Color("#314e62"), 9, 1)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 9)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_right", 9)
		margin.add_theme_constant_override("margin_bottom", 6)
		row.add_child(margin)
		var content := HBoxContainer.new()
		content.add_theme_constant_override("separation", 8)
		margin.add_child(content)
		var dot := ColorRect.new()
		dot.color = PLAYER_COLORS[index % PLAYER_COLORS.size()]
		dot.custom_minimum_size = Vector2(9.0, 9.0)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		content.add_child(dot)
		var name_column := VBoxContainer.new()
		name_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(name_column)
		var player_name := _make_label(str(player.get("name", "玩家 %d" % (index + 1))), 12, TEXT_MAIN)
		name_column.add_child(player_name)
		var property_count := _make_label("%d 筆地產 · 位於 %02d" % [(_as_array(player.get("properties", []))).size(), int(player.get("position", 0)) + 1], 10, TEXT_MUTED)
		name_column.add_child(property_count)
		var money := _make_label(_format_money(int(player.get("cash", 0))), 12, TEXT_GOLD)
		money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		content.add_child(money)
		players_list.add_child(row)

func _update_property_card(tile: Dictionary) -> void:
	if tile.is_empty():
		current_property_label.text = "尚未定位"
		current_property_detail.text = "等待棋局資料。"
		return
	var kind := String(tile.get("kind", "property"))
	current_property_label.text = str(tile.get("name", "街區 %02d" % (int(tile.get("index", 0)) + 1)))
	var details := "%s　·　格位 %02d" % [_kind_label(kind), int(tile.get("index", 0)) + 1]
	if kind == "property":
		details += "\n地價 %s　·　租金 %s　·　等級 %d" % [_format_money(int(tile.get("cost", 0))), _format_money(int(tile.get("rent", 0))), int(tile.get("building_level", 0))]
		var owner := int(tile.get("owner", -1))
		details += "\n" + ("尚未有人持有" if owner < 0 else "持有者：玩家 %d" % (owner + 1))
	elif kind == "unsupported":
		details += "\n此格尚未還原，暫不執行其效果。"
	else:
		details += "\n此格的效果由模擬層處理。"
	current_property_detail.text = details

func _update_actions(phase: String, current_index: int) -> void:
	var player := _current_player()
	var game_over := phase == "game_over"
	var human_turn := bool(player.get("is_human", true)) and not bool(player.get("bankrupt", false)) and not game_over
	var action_options: Array = _as_array(state.get("action_options", []))
	roll_button.disabled = not (human_turn and phase == "await_roll")
	buy_button.disabled = not (human_turn and phase == "await_action" and _has_action_option(action_options, "buy"))
	upgrade_button.disabled = not (human_turn and phase == "await_action" and _has_action_option(action_options, "upgrade"))
	end_turn_button.disabled = not (human_turn and phase == "await_action" and _has_action_option(action_options, "end_turn"))
	bank_button.disabled = not human_turn
	cards_button.disabled = not human_turn
	stocks_button.disabled = not (human_turn and bool(state.get("market", {}).get("open", true)))
	bank_shortcut.disabled = bank_button.disabled
	cards_shortcut.disabled = cards_button.disabled
	stocks_shortcut.disabled = stocks_button.disabled
	if not human_turn:
		bank_popup.hide()
		cards_popup.hide()
		stocks_popup.hide()
	if game_over:
		action_hint_label.text = "本局已結束"
	elif not human_turn:
		action_hint_label.text = "%s 思考中…" % str(player.get("name", "AI"))
	elif phase == "await_route":
		action_hint_label.text = "請選擇行進方向"
	elif phase == "await_roll":
		action_hint_label.text = "輪到你了，請擲骰"
	else:
		action_hint_label.text = "請處理目前格位"

func _update_route_choices(phase: String, current_index: int) -> void:
	if route_options_box == null:
		return
	for child in route_options_box.get_children():
		child.free()
	var options := _as_array(state.get("route_options", []))
	var player: Dictionary = _current_player()
	var human_turn := bool(player.get("is_human", true)) and not bool(player.get("bankrupt", false)) and phase != "game_over"
	if phase != "await_route" or options.is_empty():
		route_status_label.text = ""
		return
	var remaining := int(state.get("remaining_steps", options.size()))
	route_status_label.text = "選擇下一格 · 剩餘步數 %d" % remaining
	for option in options:
		var next_index := int(option)
		var button := _make_button("前往 %s" % _tile_short_label(next_index), _on_route_selected.bind(next_index), human_turn)
		button.disabled = not human_turn
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		route_options_box.add_child(button)

func _update_event_log() -> void:
	var lines: Array[String] = []
	var entries: Array = _as_array(state.get("event_log", []))
	var start_index: int = max(0, entries.size() - 26)
	for index in range(start_index, entries.size()):
		lines.append(_format_event(entries[index]))
	for local_entry in _local_log:
		lines.append("· " + local_entry)
	if lines.is_empty():
		lines.append("· 等待第一個行動。")
	event_log_view.text = "\n".join(lines)
	event_status_label.text = "%d 筆事件" % entries.size()

func _refresh_log_only() -> void:
	_update_event_log()

func _update_end_overlay(phase: String) -> void:
	if phase != "game_over":
		end_overlay.hide()
		return
	var winner_index := int(state.get("winner", -1))
	var players: Array = state.get("players", [])
	var winner_name := "尚未公布"
	if winner_index >= 0 and winner_index < players.size() and players[winner_index] is Dictionary:
		winner_name = str(players[winner_index].get("name", "玩家 %d" % (winner_index + 1)))
	end_title.text = "本局結算"
	end_detail.text = "勝者：%s\n\n可以開始新局，或返回棋盤查看最後狀態。" % winner_name
	end_overlay.show()

func _maybe_schedule_ai_turn() -> void:
	if _ai_pending or state.is_empty() or String(state.get("phase", "")) == "game_over":
		return
	var player := _current_player()
	if bool(player.get("is_human", true)) or bool(player.get("bankrupt", false)):
		return
	_ai_pending = true
	var timer := get_tree().create_timer(0.82)
	timer.timeout.connect(_on_ai_timer_timeout)

func _on_ai_timer_timeout() -> void:
	_ai_pending = false
	if String(state.get("phase", "")) == "game_over":
		return
	var player := _current_player()
	if bool(player.get("is_human", true)):
		return
	var result := _invoke_game("run_ai_turn")
	_append_local_log("%s 完成了自動回合。" % str(player.get("name", "AI")))
	_handle_result(result)

func _update_cards_popup() -> void:
	for child in cards_popup_list.get_children():
		child.free()
	var cards := _as_array(_current_player().get("cards", []))
	var options: Array = _as_array(state.get("action_options", []))
	if cards.is_empty():
		var empty := _make_label("目前沒有可用卡片。", 12, TEXT_MUTED)
		cards_popup_list.add_child(empty)
	else:
		for card_index in range(cards.size()):
			var card_id := str(cards[card_index])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var label := _make_label("卡片 %s" % card_id, 12, TEXT_MAIN)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var symbol_option: OptionButton = null
			if card_id == "紅" or card_id == "黑":
				symbol_option = OptionButton.new()
				symbol_option.custom_minimum_size = Vector2(112.0, 34.0)
				symbol_option.add_theme_font_size_override("font_size", 11)
				symbol_option.add_item("科技股", 0)
				symbol_option.add_item("運輸股", 1)
				symbol_option.add_item("能源股", 2)
				row.add_child(symbol_option)
			var target_option: OptionButton = null
			if card_id == "停留" or card_id == "烏龜":
				target_option = OptionButton.new()
				target_option.custom_minimum_size = Vector2(120.0, 34.0)
				target_option.add_theme_font_size_override("font_size", 11)
				var target_players: Array = state.get("players", [])
				for target_index in range(target_players.size()):
					var target_player: Dictionary = target_players[target_index] if target_players[target_index] is Dictionary else {}
					if bool(target_player.get("alive", false)):
						target_option.add_item(str(target_player.get("name", "玩家 %d" % (target_index + 1))), target_index)
				row.add_child(target_option)
			var use := _make_button("使用", func() -> void:
				var params: Dictionary = {"card_id": card_id}
				if symbol_option != null:
					var symbol_names := ["tech", "transport", "energy"]
					params["symbol"] = symbol_names[symbol_option.get_selected_id()]
				if target_option != null:
					params["target_id"] = target_option.get_selected_id()
				var result := _invoke_game("choose_action", ["use_card", params])
				_append_local_log("使用卡片 %s：%s" % [card_id, _result_text(result, "已送出卡片指令。")])
				_handle_result(result)
				cards_popup.hide()
			)
			use.disabled = not _has_action_option(options, "use_card")
			row.add_child(use)
			cards_popup_list.add_child(row)

func _update_stocks_popup() -> void:
	for child in stocks_popup_list.get_children():
		child.free()
	var market: Dictionary = state.get("market", {})
	var prices: Dictionary = market.get("prices", market)
	var options: Array = _as_array(state.get("action_options", []))
	var symbols: Array[String] = []
	for key in prices.keys():
		symbols.append(str(key))
	if symbols.is_empty():
		symbols = ["RICH", "CITY", "TRVL"]
	for symbol in symbols:
		var quote: Variant = prices.get(symbol, prices.get(StringName(symbol), {}))
		var price := 100
		if quote is Dictionary:
			price = int(quote.get("price", quote.get("value", 100)))
		elif quote is int or quote is float:
			price = int(quote)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		var label := _make_label("%s　%s" % [symbol, _format_money(price)], 12, TEXT_MAIN)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var buy := _make_button("買入", func() -> void:
			var result := _invoke_game("choose_action", ["buy_stock", {"symbol": symbol, "quantity": 1}])
			_append_local_log("買入 %s：%s" % [symbol, _result_text(result, "已送出買股指令。")])
			_handle_result(result)
		)
		buy.disabled = not _has_action_option(options, "buy_stock") or not bool(market.get("open", true))
		row.add_child(buy)
		var sell := _make_button("賣出", func() -> void:
			var result := _invoke_game("choose_action", ["sell_stock", {"symbol": symbol, "quantity": 1}])
			_append_local_log("賣出 %s：%s" % [symbol, _result_text(result, "已送出賣股指令。")])
			_handle_result(result)
		)
		sell.disabled = not _has_action_option(options, "sell_stock") or not bool(market.get("open", true))
		row.add_child(sell)
		stocks_popup_list.add_child(row)

func _unavailable_state(seed_value: int) -> Dictionary:
	return {
		"version": 0,
		"seed": seed_value,
		"phase": "unavailable",
		"turn": 0,
		"round": 0,
		"current_player": 0,
		"winner": -1,
		"last_roll": [],
		"event_log": [],
		"board": [],
		"players": [],
		"bank": {},
		"market": {},
	}

func _current_player() -> Dictionary:
	var players: Array = state.get("players", [])
	var index := int(state.get("current_player", 0))
	if index >= 0 and index < players.size() and players[index] is Dictionary:
		return players[index]
	return {"name": "玩家", "is_human": true, "cash": 0, "position": 0, "properties": [], "cards": []}

func _current_tile() -> Dictionary:
	var position := int(_current_player().get("position", 0))
	return _tile_for_index(position)

func _tile_for_index(index: int) -> Dictionary:
	var board: Array = state.get("board", [])
	if index >= 0 and index < board.size() and board[index] is Dictionary:
		return board[index]
	var map_board: Array = _as_array(_active_map_definition.get("board", []))
	if index >= 0 and index < map_board.size() and map_board[index] is Dictionary:
		return map_board[index]
	return {}

func _tile_short_label(index: int) -> String:
	var tile := _tile_for_index(index)
	var name := str(tile.get("name", "格位 %02d" % (index + 1)))
	return "%02d · %s" % [index + 1, name]

func _phase_text(phase: String) -> String:
	match phase:
		"await_roll":
			return "等待擲骰"
		"await_action":
			return "等待行動"
		"await_route":
			return "選擇路線"
		"game_over":
			return "本局結束"
		_:
			return phase

func _kind_label(kind: String) -> String:
	match kind:
		"start":
			return "起點"
		"event":
			return "事件"
		"tax":
			return "稅務"
		"bank":
			return "銀行"
		"stock":
			return "股市"
		"card":
			return "卡片"
		"points":
			return "點數"
		"unsupported":
			return "待還原"
		"rest":
			return "休息"
		_:
			return "地產"

func _format_event(event: Variant) -> String:
	if event is Dictionary:
		var event_type := str(event.get("type", "event"))
		var message := str(event.get("message", event.get("text", event.get("description", ""))))
		if message.is_empty():
			message = _event_detail(event_type, event)
		var actor := _event_actor(event)
		return "· %s　%s" % [actor, message]
	return "· " + str(event)

func _event_actor(event: Dictionary) -> String:
	if event.has("actor") or event.has("player_name"):
		return str(event.get("actor", event.get("player_name", "系統")))
	if event.has("player_id"):
		var players: Array = state.get("players", [])
		var player_id := int(event.get("player_id", -1))
		if player_id >= 0 and player_id < players.size() and players[player_id] is Dictionary:
			return str(players[player_id].get("name", "玩家 %d" % (player_id + 1)))
	return "系統"

func _event_detail(event_type: String, event: Dictionary) -> String:
	match event_type:
		"new_game":
			return "新局開始 · %d 位玩家" % int(event.get("player_count", 0))
		"roll":
			return "擲骰：%s（合計 %d）" % [_roll_text(event), int(event.get("total", 0))]
		"move":
			return "移動至第 %02d 格" % (int(event.get("to", 0)) + 1)
		"property_bought":
			return "購買地產 · %s" % _tile_name(int(event.get("property_id", -1)))
		"property_upgraded":
			return "升級 %s 至第 %d 級" % [_tile_name(int(event.get("property_id", -1))), int(event.get("level", 0))]
		"payment":
			return "支付 %s" % _format_money(int(event.get("amount", 0)))
		"deposit":
			return "存入銀行 %s" % _format_money(int(event.get("amount", 0)))
		"withdraw":
			return "從銀行提取 %s" % _format_money(int(event.get("amount", 0)))
		"stock_bought":
			return "買入 %s × %d" % [str(event.get("symbol", "")), int(event.get("quantity", 0))]
		"stock_sold":
			return "賣出 %s × %d" % [str(event.get("symbol", "")), int(event.get("quantity", 0))]
		"card_used":
			return "使用卡片：%s" % str(event.get("card_id", ""))
		"game_over":
			return "本局結束"
		"turn_started":
			return "回合開始"
		_:
			return event_type

func _tile_name(index: int) -> String:
	return str(_tile_for_index(index).get("name", "格位 %02d" % (index + 1)))

func _roll_text(result: Dictionary) -> String:
	var dice: Array = _as_array(result.get("last_roll", result.get("dice", state.get("last_roll", []))))
	if dice.is_empty():
		return "完成"
	return "、".join(dice.map(func(value: Variant) -> String: return str(value)))

func _result_text(result: Dictionary, fallback: String) -> String:
	return str(result.get("message", fallback))

func _append_local_log(message: String) -> void:
	_local_log.append(message)
	if _local_log.size() > 8:
		_local_log.pop_front()

func _as_array(value: Variant) -> Array:
	return value if value is Array else []

func _has_action_option(options: Array, action: String) -> bool:
	for option in options:
		if str(option) == action:
			return true
	return false

func _has_int_option(options: Array, expected: int) -> bool:
	for option in options:
		if int(option) == expected:
			return true
	return false

func _format_money(amount: int) -> String:
	var negative := amount < 0
	var digits := str(abs(amount))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	grouped = digits + grouped
	return ("-" if negative else "") + "$" + grouped

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _make_button(text: String, action: Callable, accent := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 38.0)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", TEXT_MAIN)
	button.add_theme_color_override("font_hover_color", Color("#fff4d3"))
	button.add_theme_color_override("font_disabled_color", Color("#637b89"))
	button.add_theme_stylebox_override("normal", _style_box(ACCENT_DARK if accent else Color("#29475b"), Color("#d3a356") if accent else Color("#45687b"), 9, 1))
	button.add_theme_stylebox_override("hover", _style_box(Color("#bb7c3d") if accent else Color("#345b71"), Color("#f1d28a"), 9, 1))
	button.add_theme_stylebox_override("pressed", _style_box(Color("#8c572f") if accent else Color("#1d3547"), Color("#f1d28a"), 9, 1))
	button.add_theme_stylebox_override("disabled", _style_box(Color("#1b2d3c"), Color("#263f51"), 9, 1))
	button.pressed.connect(action)
	return button

func _apply_panel_style(panel: PanelContainer, background: Color, border: Color, radius: int, border_width: int) -> void:
	panel.add_theme_stylebox_override("panel", _style_box(background, border, radius, border_width))

func _style_box(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
