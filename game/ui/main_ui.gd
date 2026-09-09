extends Control

## Desktop game shell for the Richman 4 reconstruction.
##
## This script owns presentation and input only.  The simulation is loaded at
## runtime so the UI remains parseable while the core is developed in its own
## lane.  Once present, GameState is the authority for every displayed value.

const OriginalGods = preload("res://game/content/original_gods.gd")
const SAVE_PATH := "user://richman4_save.json"
const OriginalMaps = preload("res://game/content/original_maps.gd")
const GameCalendar = preload("res://game/core/game_calendar.gd")
const InventoryCatalogue = preload("res://game/content/original_inventory.gd")
const InventoryRules = preload("res://game/core/inventory_rules.gd")
const NewsPanel = preload("res://game/ui/news_panel.gd")
const MovementPresentation = preload("res://game/ui/movement_presentation.gd")
const FatePanel = preload("res://game/ui/fate_panel.gd")
const TheftPicker = preload("res://game/ui/theft_picker.gd")
const FinancialPresentation = preload("res://game/ui/financial_presentation.gd")
const SleepPresentation = preload("res://game/ui/sleep_presentation.gd")
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
const COMPANY_SAVE_VERSION := 7
const STATUS_SAVE_VERSION := 8
const HAZARD_SAVE_VERSION := 9
const PROPERTY_CARD_SAVE_VERSION := 10
const REMODEL_SAVE_VERSION := 11
const RESEARCH_SAVE_VERSION := 12
const BUILDING_CARD_SAVE_VERSION := 13
const RESEARCH_TOOLS := ["機器工人", "時光機", "傳送機", "工程車", "核子飛彈"]
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
var research_button: Button
var research_popup: PopupPanel
var research_popup_list: VBoxContainer
var end_turn_button: Button
var bank_button: Button
var cards_button: Button
var stocks_button: Button

var new_game_button: Button
var save_button: Button
var load_button: Button

var bank_popup: PopupPanel
var bank_loan_button: Button
var bank_loan_status: Label
var news_popup: PopupPanel
var fate_popup: PopupPanel
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
var facility_popup: PopupPanel
var facility_popup_list: VBoxContainer
var facility_popup_action := "build_facility"
var inventory_balance_label: Label
var shop_button: Button
var shop_popup: PopupPanel
var shop_balance_label: Label
var shop_popup_list: VBoxContainer
var shop_scroll: ScrollContainer
var stocks_popup: PopupPanel
var company_popup: PopupPanel
var trap_popup: PopupPanel
var trap_prompt_label: Label
var trap_target_option: OptionButton
var trap_redirect_button: Button
var trap_decline_button: Button
var _trap_response_busy := false
var financial_popup: PopupPanel
var _finance_response_busy := false
var audio_controller: Object
var audio_button: Button
var audio_config_button: Button
var audio_folder_dialog: FileDialog
var cards_popup_list: VBoxContainer
var stocks_popup_list: VBoxContainer
var company_popup_list: VBoxContainer
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
var _company_purchase_quantity: SpinBox
var _company_purchase_button: Button
var _company_service_target: OptionButton
var _company_service_type: OptionButton
var _company_service_button: Button
var _presentation_busy := false
var _presentation_generation := 0
var _presentation_result: Dictionary = {}
var _presentation_owner: Object

func _ready() -> void:
	_build_interface()
	_setup_audio()
	_load_map_catalog()
	_new_game(DEFAULT_SEED, PLAYER_COUNT, _selected_map_definition, _default_setup_options(PLAYER_COUNT))

func _process(_delta: float) -> void:
	_maybe_schedule_ai_turn()

func _unhandled_input(event: InputEvent) -> void:
	if _presentation_busy:
		return
	if (news_popup != null and news_popup.visible) or (fate_popup != null and fate_popup.visible):
		return
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
	news_popup = NewsPanel.new()
	add_child(news_popup)
	fate_popup = FatePanel.new()
	add_child(fate_popup)
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
	seed_label.hide()
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
	if board_view.has_signal("movement_finished"):
		board_view.movement_finished.connect(_on_movement_finished)

	var board_footer := _make_label("滾輪縮放 · 中／右鍵拖曳平移", 10, TEXT_MUTED)
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
	var players_scroll := ScrollContainer.new()
	players_scroll.custom_minimum_size = Vector2(0.0, 100.0)
	players_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	players_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_column.add_child(players_scroll)
	players_list = VBoxContainer.new()
	players_list.add_theme_constant_override("separation", 5)
	players_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_scroll.add_child(players_list)

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
	shop_button = _make_button("點券商店", _on_shop_pressed, true)
	shop_button.visible = false
	side_column.add_child(shop_button)
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
	research_button = _make_button("研究", _on_research_pressed)
	research_button.name = "ResearchButton"
	research_button.custom_minimum_size = Vector2(88.0, 52.0)
	row.add_child(research_button)
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
	financial_popup = FinancialPresentation.new()
	add_child(financial_popup)
	financial_popup.answered.connect(_respond_to_finance)
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
	bank_loan_status = _make_label("", 11, TEXT_GOLD)
	bank_loan_status.name = "LoanStatus"
	bank_box.add_child(bank_loan_status)
	bank_loan_button = _make_button("申請貸款 $10,000", _on_loan_pressed)
	bank_loan_button.name = "BankLoan"
	bank_box.add_child(bank_loan_button)
	var bank_close := _make_button("關閉", bank_popup.hide)
	bank_box.add_child(bank_close)

	cards_popup = _make_popup(Vector2i(640, 500))
	cards_popup.min_size = Vector2i(640, 500)
	var cards_box := _popup_box(cards_popup)
	cards_box.add_child(_make_label("背包", 19, TEXT_MAIN))
	inventory_balance_label = _make_label("", 13, TEXT_GOLD)
	cards_box.add_child(inventory_balance_label)
	var cards_description := _make_label("選擇物品與目標後使用；尚未還原的物品會保留在背包。", 11, TEXT_MUTED)
	cards_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cards_box.add_child(cards_description)
	var inventory_scroll := ScrollContainer.new()
	inventory_scroll.custom_minimum_size = Vector2(0, 330)
	inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cards_box.add_child(inventory_scroll)
	cards_popup_list = VBoxContainer.new()
	cards_popup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_popup_list.add_theme_constant_override("separation", 7)
	inventory_scroll.add_child(cards_popup_list)
	cards_box.add_child(_make_button("關閉", cards_popup.hide))

	facility_popup = _make_popup(Vector2i(590, 390))
	var facility_box := _popup_box(facility_popup)
	facility_box.add_child(_make_label("選擇商業設施", 19, TEXT_MAIN))
	facility_popup_list = VBoxContainer.new()
	facility_popup_list.add_theme_constant_override("separation", 8)
	facility_box.add_child(facility_popup_list)
	var cancel_facility := _make_button("取消", facility_popup.hide)
	cancel_facility.name = "CancelFacility"
	facility_box.add_child(cancel_facility)

	research_popup = _make_popup(Vector2i(590, 430))
	research_popup.name = "ResearchPopup"
	var research_box := _popup_box(research_popup)
	research_box.add_child(_make_label("研究所生產", 19, TEXT_MAIN))
	var research_help := _make_label("選定後於第 5 次輪到你時交付；再次造訪可改選。", 12, TEXT_MUTED)
	research_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	research_box.add_child(research_help)
	research_popup_list = VBoxContainer.new()
	research_popup_list.add_theme_constant_override("separation", 8)
	research_box.add_child(research_popup_list)
	var research_cancel := _make_button("取消", research_popup.hide)
	research_cancel.name = "CancelResearch"
	research_box.add_child(research_cancel)

	shop_popup = _make_popup(Vector2i(700, 530))
	shop_popup.min_size = Vector2i(700, 530)
	var shop_box := _popup_box(shop_popup)
	shop_box.add_child(_make_label("點券商店", 19, TEXT_MAIN))
	shop_balance_label = _make_label("", 13, TEXT_GOLD)
	shop_box.add_child(shop_balance_label)
	var shop_help := _make_label("購買使用點券；出售按總標價九折取整。選好數量再交易。", 11, TEXT_MUTED)
	shop_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_box.add_child(shop_help)
	shop_scroll = ScrollContainer.new()
	shop_scroll.custom_minimum_size = Vector2(0, 350)
	shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shop_box.add_child(shop_scroll)
	shop_popup_list = VBoxContainer.new()
	shop_popup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_popup_list.add_theme_constant_override("separation", 7)
	shop_scroll.add_child(shop_popup_list)
	shop_box.add_child(_make_button("關閉", shop_popup.hide))

	stocks_popup = _make_popup(Vector2i(760, 610))
	stocks_popup.min_size = Vector2i(760, 610)
	var stocks_box := _popup_box(stocks_popup)
	stocks_box.add_child(_make_label("股票市場", 19, TEXT_MAIN))
	var stocks_description := _make_label("選擇股數後交易；公司市場從銀行存款扣款，市場供給與暫停狀態會限制買入。", 11, TEXT_MUTED)
	stocks_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stocks_box.add_child(stocks_description)
	var stocks_scroll := ScrollContainer.new()
	stocks_scroll.name = "StocksScroll"
	stocks_scroll.custom_minimum_size = Vector2(0.0, 470.0)
	stocks_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stocks_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stocks_box.add_child(stocks_scroll)
	stocks_popup_list = VBoxContainer.new()
	stocks_popup_list.name = "StocksList"
	stocks_popup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stocks_popup_list.add_theme_constant_override("separation", 7)
	stocks_scroll.add_child(stocks_popup_list)
	var stocks_close := _make_button("關閉", stocks_popup.hide)
	stocks_box.add_child(stocks_close)

	company_popup = _make_popup(Vector2i(650, 590))
	company_popup.min_size = Vector2i(650, 590)
	var company_box := _popup_box(company_popup)
	company_box.add_child(_make_label("企業股份", 19, TEXT_MAIN))
	var company_scroll := ScrollContainer.new()
	company_scroll.name = "CompanyScroll"
	company_scroll.custom_minimum_size = Vector2(0.0, 445.0)
	company_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	company_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	company_box.add_child(company_scroll)
	company_popup_list = VBoxContainer.new()
	company_popup_list.name = "CompanyList"
	company_popup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	company_popup_list.add_theme_constant_override("separation", 8)
	company_scroll.add_child(company_popup_list)
	company_box.add_child(_make_button("關閉", company_popup.hide))

	trap_popup = _make_popup(Vector2i(570, 290))
	trap_popup.name = "TrapResponsePopup"
	trap_popup.exclusive = true
	# A defense choice must survive application/parent focus changes.
	trap_popup.popup_window = false
	var trap_box := _popup_box(trap_popup)
	trap_box.add_child(_make_label("使用嫁禍卡？", 19, TEXT_MAIN))
	trap_prompt_label = _make_label("", 13, TEXT_MAIN)
	trap_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trap_prompt_label.custom_minimum_size.x = 500
	trap_box.add_child(trap_prompt_label)
	trap_target_option = OptionButton.new()
	trap_target_option.name = "TrapRedirectTarget"
	trap_target_option.custom_minimum_size = Vector2(0, 38)
	trap_box.add_child(trap_target_option)
	trap_redirect_button = _make_button("使用嫁禍卡", func() -> void: _respond_to_trap(false))
	trap_redirect_button.name = "RedirectTrap"
	trap_box.add_child(trap_redirect_button)
	trap_decline_button = _make_button("不使用，接受入獄", func() -> void: _respond_to_trap(true))
	trap_decline_button.name = "DeclineTrap"
	trap_box.add_child(trap_decline_button)
	trap_popup.popup_hide.connect(func() -> void:
		if not _trap_response_busy and _human_trap_response_pending():
			call_deferred("_respond_to_trap", true)
	)

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

func _default_setup_options(player_count: int, map_definition: Dictionary = {}) -> Dictionary:
	var date := _system_start_date()
	if date.is_empty():
		date = {"year": 1998, "month": 1, "day": 1}
	var character_ids: Array = []
	for player_id in range(player_count):
		character_ids.append(player_id)
	var capability_definition: Dictionary = map_definition if not map_definition.is_empty() else _selected_map_definition
	var supports_companies := bool(capability_definition.get("supports_original_companies", false))
	var supports_facilities := bool(capability_definition.get("original_facilities", false)) or supports_companies
	return {
		"original_inventory": true,
		"original_facilities": supports_facilities,
		"original_gods": supports_facilities,
		"original_companies": supports_companies,
		"original_statuses": bool(capability_definition.get("supports_original_statuses", false)),
		"original_hazards": bool(capability_definition.get("supports_original_hazards", false)),
		"original_property_cards": bool(capability_definition.get("supports_original_property_cards", false)),
		"original_remodel": bool(capability_definition.get("supports_original_remodel", false)),
		"original_research": bool(capability_definition.get("supports_original_research", false)),
		"original_building_cards": bool(capability_definition.get("supports_original_building_cards", false)),
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
		"original_inventory": int(state.get("version", 0)) in [4, 5, 6, COMPANY_SAVE_VERSION, STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION],
		"original_facilities": int(state.get("version", 0)) in [5, 6, COMPANY_SAVE_VERSION, STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION],
		"original_gods": int(state.get("version", 0)) in [6, COMPANY_SAVE_VERSION, STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION],
		"original_companies": int(state.get("version", 0)) in [COMPANY_SAVE_VERSION, STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_companies", false)),
		"original_statuses": _has_original_statuses(),
		"original_hazards": _has_original_hazards(),
		"original_property_cards": _has_original_property_cards(),
		"original_remodel": _has_original_remodel(),
		"original_research": _has_original_research(),
		"original_building_cards": _has_original_building_cards(),
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
	var supports_companies := bool(_selected_map_definition.get("supports_original_companies", false))
	var supports_facilities := bool(_selected_map_definition.get("original_facilities", false)) or supports_companies
	return {"ok": true, "options": {
		"original_inventory": true,
		"original_facilities": supports_facilities,
		"original_gods": supports_facilities,
		"original_companies": supports_companies,
		"original_statuses": bool(_selected_map_definition.get("supports_original_statuses", false)),
		"original_hazards": bool(_selected_map_definition.get("supports_original_hazards", false)),
		"original_property_cards": bool(_selected_map_definition.get("supports_original_property_cards", false)),
		"original_remodel": bool(_selected_map_definition.get("supports_original_remodel", false)),
		"original_research": bool(_selected_map_definition.get("supports_original_research", false)),
		"original_building_cards": bool(_selected_map_definition.get("supports_original_building_cards", false)),
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
	var result: Dictionary = OriginalMaps.load_catalog(path, true)
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

func _map_source_matches(left: Variant, right: Variant, json_number_identity: bool = false) -> bool:
	if not left is Dictionary or not right is Dictionary:
		return false
	for key in ["edition", "map_number", "archive", "entry_index", "payload_sha256", "source_file_sha256"]:
		# Restart matches a JSON catalog against normalized save numbers. Keep
		# the existing preview-selection matching behavior for other callers.
		if json_number_identity and key in ["map_number", "entry_index"]:
			if not left.has(key) and not right.has(key):
				continue
			var left_value: Variant = left.get(key)
			var right_value: Variant = right.get(key)
			if typeof(left_value) not in [TYPE_INT, TYPE_FLOAT] or typeof(right_value) not in [TYPE_INT, TYPE_FLOAT]:
				return false
			if not is_finite(float(left_value)) or not is_finite(float(right_value)) or floor(float(left_value)) != float(left_value) or floor(float(right_value)) != float(right_value):
				return false
			if left_value != right_value:
				return false
			continue
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
	var effective_setup := setup_options.duplicate(true)
	if effective_setup.is_empty() and (bool(selected_definition.get("original_facilities", false)) or bool(selected_definition.get("supports_original_companies", false))):
		effective_setup = _default_setup_options(resolved_players, selected_definition)
	var state_script: Variant = load("res://game/core/game_state.gd")
	var candidate: Variant = null
	if state_script != null:
		if not _is_fallback_definition(selected_definition) and state_script.has_method("new_game_on_board"):
			candidate = state_script.new_game_on_board(resolved_seed, resolved_players, selected_definition, effective_setup) if not effective_setup.is_empty() else state_script.new_game_on_board(resolved_seed, resolved_players, selected_definition)
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
		_cancel_presentation()
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
	_cancel_presentation()
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
	var rest_status := _player_rest_status(_current_player())
	var resting := not rest_status.is_empty() and int(rest_status.count) != 128
	var result := _invoke_game("roll")
	_append_local_log(_result_text(result, "休養中。") if resting else "你擲出 %s。" % _roll_text(result))
	_handle_result(result)

func _on_buy_pressed() -> void:
	if buy_button.disabled:
		return
	if _has_action_option(_as_array(state.get("action_options", [])), "buy_company"):
		_open_company_popup()
		return
	var tile := _current_tile()
	if _has_original_gods() and int(_current_player().get("god_id", 0)) in [3, 4] and tile.get("kind", "") == "facility" and int(tile.get("building_level", 0)) == 0:
		_open_facility_builder("buy")
		return
	var result := _invoke_game("choose_action", ["buy", {}])
	_append_local_log("購買地產：%s" % _result_text(result, "已送出購買指令。"))
	_handle_result(result)

func _on_upgrade_pressed() -> void:
	if upgrade_button.disabled:
		return
	if _has_action_option(_as_array(state.get("action_options", [])), "company_upgrade"):
		_open_company_popup()
		return
	if _has_action_option(_as_array(state.get("action_options", [])), "build_facility"):
		_open_facility_builder()
		return
	var result := _invoke_game("choose_action", ["upgrade", {}])
	_append_local_log("升級建設：%s" % _result_text(result, "已送出升級指令。"))
	_handle_result(result)

func _facility_name(type_id: int) -> String:
	return ["公園", "旅館", "購物中心", "加油站", "研究所"][clampi(type_id, 0, 4)]

func _open_facility_builder(action: String = "build_facility") -> void:
	facility_popup_action = action
	for child in facility_popup_list.get_children():
		child.free()
	var tile := _current_tile()
	var tile_index := int(tile.get("index", -1))
	var player_id := int(state.get("current_player", -1))
	var price := int(tile.get("land_price", 0)) * int(state.get("price_index", 1))
	var price_text := "購地 %s · 福神免費建成第 1 級" if action == "buy" else "建造費 %s · 選擇後立即建成第 1 級"
	facility_popup_list.add_child(_make_label(price_text % _format_money(price), 13, TEXT_GOLD))
	var descriptions := ["不收設施費，最高 1 級", "依輪盤收費，最高 5 級", "依輪盤收費，最高 5 級", "向搭乘載具的訪客收費，最高 1 級", "生產研究工具，最高 5 級" if _has_original_research() else "道具生產尚未開放"]
	for type_id in range(5):
		var choice := type_id
		var button := _make_button("%s · %s" % [_facility_name(choice), descriptions[choice]], func() -> void:
			if int(_current_tile().get("index", -1)) != tile_index or int(state.get("current_player", -1)) != player_id:
				facility_popup.hide()
				return
			var result := _invoke_game("choose_action", [action, {"facility_type": choice}])
			_append_local_log("建造%s：%s" % [_facility_name(choice), _result_text(result, "已送出建造指令。")])
			_handle_result(result)
			facility_popup.hide()
		)
		button.name = "BuildFacility_%d" % choice
		button.disabled = (choice == 4 and not _has_original_research()) or price > int(_current_player().get("cash", 0)) or not _is_human_turn() or not _has_action_option(_as_array(state.get("action_options", [])), action)
		facility_popup_list.add_child(button)
	facility_popup.popup_centered(Vector2i(590, 390))
	_settle_inventory_popup(facility_popup, Vector2i(590, 390))

func _on_research_pressed() -> void:
	if research_button.disabled or not _has_action_option(_as_array(state.get("action_options", [])), "choose_research"):
		return
	for child in research_popup_list.get_children():
		child.free()
	var tile := _current_tile()
	var tile_index := int(tile.get("index", -1))
	var player_id := int(state.get("current_player", -1))
	var level := int(tile.get("building_level", 0))
	for index in range(RESEARCH_TOOLS.size()):
		var tool_id: String = RESEARCH_TOOLS[index]
		var button := _make_button("%s · 需 %d 級" % [tool_id, index + 1], func() -> void:
			if int(_current_tile().get("index", -1)) != tile_index or int(state.get("current_player", -1)) != player_id:
				research_popup.hide()
				return
			var result := _invoke_game("choose_action", ["choose_research", {"tool_id": tool_id}])
			_append_local_log("研究所：%s" % _result_text(result, "已送出生產選擇。"))
			_handle_result(result)
			research_popup.hide()
		)
		button.name = "ResearchTool_%d" % (index + 9)
		button.disabled = index >= level
		if index > 0:
			button.tooltip_text = "可生產並持有；此工具的使用效果尚未還原。"
		research_popup_list.add_child(button)
	research_popup.popup_centered(Vector2i(590, 430))
	_settle_inventory_popup(research_popup, Vector2i(590, 430))

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

func _on_loan_pressed() -> void:
	if bank_loan_button.disabled:
		return
	var result := _invoke_game("choose_action", ["take_loan", {"amount": 10000}])
	_append_local_log("申請貸款：%s" % _result_text(result, "已送出貸款申請。"))
	_handle_result(result)

func _on_cards_pressed() -> void:
	if not _is_human_turn():
		return
	_update_cards_popup()
	cards_popup.popup_centered(Vector2i(640, 540))
	_settle_inventory_popup(cards_popup, Vector2i(640, 540))


func _open_company_popup() -> void:
	if not _is_human_turn() or not _has_original_companies():
		return
	_update_company_popup()
	# Rebuild the rows before opening.  The popup starts hidden, so checking
	# `visible` here would make the first visit a no-op.
	if company_popup_list != null and company_popup_list.get_child_count() > 0:
		company_popup.popup_centered(Vector2i(650, 590))
		_settle_inventory_popup(company_popup, Vector2i(650, 590))

func _settle_inventory_popup(popup: PopupPanel, desired_size: Vector2i) -> void:
	# Newly rebuilt rows need a layout frame before their wrapped minimum height
	# is valid. Refit after that frame so the close button remains on screen.
	await get_tree().process_frame
	if is_instance_valid(popup) and popup.visible:
		popup.size = desired_size
		popup.move_to_center()

func _on_stocks_pressed() -> void:
	if not _is_human_turn():
		return
	_update_stocks_popup()
	stocks_popup.popup_centered(Vector2i(760, 610))
	_settle_inventory_popup(stocks_popup, Vector2i(760, 610))

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
	var loan_block_days := int(player.get("loan_block_days", 0))
	var loan_blocked := loan_block_days > 0 and loan_block_days < 128
	bank_loan_status.text = "暫停貸款 · 剩餘自己的回合 %d 次" % loan_block_days if loan_blocked else "目前貸款 %s" % _format_money(int(player.get("loan", 0)))
	bank_loan_button.disabled = loan_blocked or not _has_action_option(options, "take_loan") or int(state.get("bank", {}).get("cash", 0)) < 10000

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
	var restart_definition := _active_map_definition
	var matched_source := false
	# A loaded snapshot supplies current geometry for display, but a new match
	# needs the matching source's capabilities and initial company/stock data.
	for definition_value in _map_catalog:
		if definition_value is Dictionary and str(definition_value.get("id", "")) == str(_active_map_definition.get("id", "")) and _map_source_matches(definition_value.get("source", {}), _active_map_definition.get("source", {}), true):
			restart_definition = definition_value
			matched_source = true
			break
	if bool(options.get("original_companies", false)) and not matched_source:
		var message := "這份存檔對應的地圖資料尚未載入，無法重新開局。請恢復對應地圖資料後重新開啟遊戲，或從「新局」選擇其他可用地圖。現有棋局保持不變。"
		_append_local_log(message)
		_refresh_log_only()
		var notice := get_node_or_null("RestartUnavailableDialog") as AcceptDialog
		if notice == null:
			notice = AcceptDialog.new()
			notice.name = "RestartUnavailableDialog"
			notice.title = "無法重新開局"
			add_child(notice)
		notice.dialog_text = message
		notice.popup_centered(Vector2i(620, 160))
		return
	_new_game(seed_value, player_count, restart_definition, options)

func _on_end_restart_pressed() -> void:
	_restart_game()

func _close_end_overlay() -> void:
	end_overlay.hide()

func _is_human_turn() -> bool:
	var player := _current_player()
	return not _presentation_busy and not SleepPresentation.automatic(player) and game_state != null and bool(player.get("is_human", false)) and not bool(player.get("bankrupt", true)) and state.get("phase", "") != "game_over"

func _invoke_game(method: String, args: Array = []) -> Dictionary:
	if _presentation_busy:
		return {"ok": false, "message": "角色移動中。"}
	var is_trap_response := method == "choose_action" and not args.is_empty() and str(args[0]) == "respond_trap" and _human_trap_response_pending()
	var is_finance_response := method == "choose_action" and not args.is_empty() and str(args[0]) == "respond_finance" and FinancialPresentation.human_pending(state)
	if method not in ["run_ai_turn", "run_sleep_turn"] and not _is_human_turn() and not is_trap_response and not is_finance_response:
		return {"ok": false, "message": "目前不是你的回合。"}
	if game_state != null and game_state.has_method(method):
		var before := _read_snapshot().duplicate(true)
		var result: Variant = game_state.callv(method, args)
		if result is Dictionary:
			result["_presentation_before"] = before
			result["_presentation_generation"] = _presentation_generation
			result["_presentation_owner"] = game_state
			return result
		return {}
	return {"ok": false, "message": "模擬核心未載入；目前無法執行此操作。"}

func _handle_result(result: Dictionary) -> void:
	if _presentation_busy:
		return
	if result.has("_presentation_generation"):
		if int(result._presentation_generation) != _presentation_generation or result.get("_presentation_owner") != game_state:
			return
		var after: Dictionary = result.get("state", _read_snapshot())
		var moves := MovementPresentation.plan(result.get("_presentation_before", {}), after)
		if not moves.is_empty() and board_view != null and board_view.has_method("play_movement"):
			_presentation_busy = true
			_presentation_result = result
			_presentation_owner = game_state
			board_view.route_options = []
			_update_actions(str(state.get("phase", "")), int(state.get("current_player", 0)))
			_update_route_choices(str(state.get("phase", "")), int(state.get("current_player", 0)))
			board_view.play_movement(moves)
			return
	if result.is_empty():
		_append_local_log("模擬層未回傳事件；請查看目前回合狀態。")
	_refresh_from_state(result)

func _cancel_presentation() -> void:
	_presentation_generation += 1
	_presentation_busy = false
	_presentation_result = {}
	_presentation_owner = null
	_ai_pending = false
	if board_view != null and board_view.has_method("cancel_movement"):
		board_view.cancel_movement(true)
	if news_popup != null:
		news_popup.cancel_presentation()
	if fate_popup != null:
		fate_popup.cancel_presentation()

func _on_movement_finished() -> void:
	if not _presentation_busy:
		return
	var result := _presentation_result
	var same_game := _presentation_owner == game_state and int(result.get("_presentation_generation", -1)) == _presentation_generation
	_presentation_busy = false
	_presentation_result = {}
	_presentation_owner = null
	if same_game:
		_refresh_from_state(result)

func _refresh_from_state(result: Dictionary = {}) -> void:
	if _presentation_busy:
		return
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
		board_view.call("set_game_data", board, players, current_index, _active_map_definition, _as_array(state.get("route_options", [])), state.get("roadblocks", {}), (_as_array(state.get("god_objects", [])) if _has_original_gods() else []), (state.get("ground_hazards", {}) if _has_original_hazards() else {}))
	_update_header(phase, current_index)
	_update_players(players, current_index)
	_update_property_card(_current_tile())
	_update_actions(phase, current_index)
	_update_route_choices(phase, current_index)
	if bank_popup.visible:
		_update_bank_popup()
	if stocks_popup.visible:
		_update_stocks_popup()
	if company_popup.visible:
		_update_company_popup()
	_update_event_log()
	_update_end_overlay(phase)
	_update_trap_response_popup()
	_update_financial_popup()
	news_popup.sync_snapshot(state)
	fate_popup.sync_snapshot(state)
	_last_rendered_phase = phase

func _update_header(phase: String, current_index: int) -> void:
	seed_label.text = "SEED %s" % str(state.get("seed", "?"))
	turn_label.text = "第 %d 回合 · 第 %d 輪" % [int(state.get("turn", 1)), int(state.get("round", 1))]
	phase_label.text = _phase_text(phase)
	var remote: Dictionary = state.get("pending_remote_dice", {})
	if phase == "await_roll" and not remote.is_empty():
		phase_label.text += " · 遙控 %d 點" % int(remote.get("value", 0))
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
		if _has_original_inventory():
			name_column.add_child(_make_label("點券 %d · 卡片 %d/15" % [int(player.get("points", 0)), _as_array(player.get("cards", [])).size()], 10, TEXT_MUTED))
		var god_id := int(player.get("god_id", 0)) if _has_original_gods() else 0
		if god_id > 0:
			var days := 0
			for actor in _as_array(state.get("god_objects", [])):
				if actor is Dictionary and int(actor.get("owner", -1)) == index and int(actor.get("id", 0)) == god_id:
					days = int(actor.get("days", 0))
			name_column.add_child(_make_label("%s · %d 天" % [OriginalGods.name_for(god_id), days], 10, TEXT_GOLD))
		if _has_original_hazards() and int(player.get("bomb_steps", 0)) > 0:
			name_column.add_child(_make_label("定時炸彈 · 剩餘 %d 步" % int(player.bomb_steps), 10, TEXT_GOLD))
		var rest_status := _player_rest_status(player)
		if not rest_status.is_empty():
			name_column.add_child(_make_label(_rest_status_label(rest_status), 10, TEXT_GOLD))
		if _has_original_companies() and player.has("insurance_status"):
			var insurance_status := int(player.get("insurance_status", 0))
			if insurance_status == 128:
				name_column.add_child(_make_label("保險：128（到期當日仍有效）", 10, TEXT_GOLD))
			elif insurance_status > 0:
				name_column.add_child(_make_label("保險：%d 天" % insurance_status, 10, TEXT_GOLD))
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
	var company := _company_at_tile(tile)
	if not company.is_empty():
		var stock_symbol := _company_stock_symbol(company)
		var stock_name := _stock_name_for_ui(stock_symbol)
		var row := _stock_row_for_ui(stock_symbol)
		var stock_price := _stock_price_for_ui(stock_symbol)
		var owner_id := int(company.get("owner", -1))
		var owner_text := "無" if owner_id < 0 else _player_name(owner_id)
		var player_shares := _stock_holding(_current_player(), stock_symbol)
		var market_supply := int(row.get("market_supply", -1)) if not row.is_empty() else -1
		var suspension := int(row.get("suspension", 0)) if not row.is_empty() else 0
		current_property_label.text = str(company.get("display_name", tile.get("name", "企業")))
		details = "企業　·　格位 %02d" % (int(tile.get("index", 0)) + 1)
		details += "\n股票：%s（%s）　·　市價 %s" % [stock_name, stock_symbol, _format_price(stock_price)]
		details += "\n你的持股：%d 股　·　經營者：%s" % [player_shares, owner_text]
		details += "\n企業庫存：%d 股　·　本回合可購買：%d 股" % [int(company.get("treasury", 0)), int(state.get("company_purchase_remaining", 0))]
		details += "\n本月盈餘：%s　·　累計盈餘：%s　·　平均盈餘：%s" % [_format_money(int(company.get("monthly_profit", 0))), _format_money(int(company.get("cumulative_profit", 0))), _format_money(_company_average_earnings(company))]
		if market_supply >= 0:
			details += "\n市場供給：%d 股" % market_supply
		if suspension > 0:
			details += "　·　暫停交易 %d 天" % suspension
		current_property_detail.text = details
		return
	if kind == "property":
		var owner := int(tile.get("owner", -1))
		var displayed_rent := int(tile.get("rent", 0))
		if _has_original_remodel():
			var chain := bool(tile.get("is_chain_store", false))
			current_property_label.text += " · " + ("連鎖店" if chain else "普通住宅")
			details += " · 最高 %d 級" % (1 if chain else 5)
			displayed_rent = int(game_state.call("_calculate_rent", tile, owner)) if game_state != null and owner >= 0 else 0
		details += "\n地價 %s　·　租金 %s　·　等級 %d" % [_format_money(int(tile.get("cost", 0))), _format_money(displayed_rent), int(tile.get("building_level", 0))]
		details += "\n" + ("尚未有人持有" if owner < 0 else "持有者：玩家 %d" % (owner + 1))
		if owner < 0 and _has_original_gods():
			var purchase_price := (int(tile.get("land_price", tile.get("cost", 0))) + int(tile.get("building_level", 0)) * int(tile.get("house_price", tile.get("upgrade_cost", 0)))) * int(state.get("price_index", 1))
			details += " · 購買總價 %s" % _format_money(purchase_price)
	elif kind == "facility":
		var level := int(tile.get("building_level", 0))
		var price_index := int(state.get("price_index", 1))
		var land_price := int(tile.get("land_price", 0)) * price_index
		var owner := int(tile.get("owner", -1))
		current_property_label.text += " · " + ("設施用地" if level == 0 else _facility_name(int(tile.get("facility_type", 0))))
		details += "\n購地 %s · 建造 %s · 升級 %s" % [_format_money(land_price), _format_money(land_price), _format_money(int(tile.get("upgrade_cost", 0)) * price_index)]
		details += "\n等級 %d · %s" % [level, "尚未有人持有" if owner < 0 else "持有者：玩家 %d" % (owner + 1)]
		if level > 0:
			var type_id := clampi(int(tile.get("facility_type", 0)), 0, 4)
			details += " · 最高 %d 級" % [1, 5, 5, 1, 5][type_id]
		if _has_original_research() and int(tile.get("facility_type", 0)) == 4:
			var product := int(tile.get("research_tool", 0))
			var turns := int(tile.get("research_turns", 0))
			if product > 0 and product <= RESEARCH_TOOLS.size() and turns > 0:
				details += "\n%s · 剩餘自己的回合 %d 次" % [RESEARCH_TOOLS[product - 1], turns]
			else:
				details += "\n目前沒有生產排程"
		var status := int(tile.get("facility_state", 0))
		if status > 0:
			details += "\n%s · 剩餘 %d 天" % ["查封，暫停服務" if (status & 15) != 0 else "漲價，費用加倍", status >> 4]
	elif _has_original_inventory() and int(tile.get("event_code", 0)) == 15:
		current_property_label.text = "點券商店"
		details += "\n停在此格可購買或出售卡片與道具。"
	elif _has_original_statuses() and int(tile.get("type_and_idx", 0)) in [8001,8002]:
		details = "%s　·　格位 %02d\n休養或服刑結束後，從這個格位繼續行動。" % ["醫院" if int(tile.type_and_idx) == 8001 else "監獄", int(tile.get("index", 0))+1]
	elif kind == "unsupported":
		details += "\n此格尚未還原，暫不執行其效果。"
	elif kind == "fate":
		details += "\n停在此格會揭曉命運，影響財產或行動。"
	elif kind == "news":
		details += "\n停在此格會播報新聞，影響局勢。"
	else:
		details += "\n此格的效果由模擬層處理。"
	current_property_detail.text = details

func _update_actions(phase: String, current_index: int) -> void:
	var player := _current_player()
	var game_over := phase == "game_over"
	var human_turn := not _presentation_busy and not SleepPresentation.automatic(player) and bool(player.get("is_human", true)) and not bool(player.get("bankrupt", false)) and not game_over
	var action_options: Array = _as_array(state.get("action_options", []))
	var rest_status := _player_rest_status(player)
	var detained := _has_original_statuses() and not rest_status.is_empty()
	var reaction_pending := not _pending_trap_for_ui().is_empty() or state.has("pending_finance")
	roll_button.text = "擲骰"
	if not rest_status.is_empty():
		roll_button.text = ("出院擲骰" if rest_status.kind == "hospital" else "出獄擲骰") if int(rest_status.count) == 128 else ("休養" if rest_status.kind == "hospital" else "服刑")
	if SleepPresentation.automatic(player):
		roll_button.text = "醒來" if int(SleepPresentation.status(player).count) == 128 else "自動休息"
	roll_button.disabled = not (human_turn and phase == "await_roll") or reaction_pending
	var can_buy_company := _has_action_option(action_options, "buy_company")
	var can_buy_property := _has_action_option(action_options, "buy")
	buy_button.text = "購買企業股份" if can_buy_company else "購買地產"
	buy_button.disabled = not (human_turn and phase == "await_action" and (can_buy_property or can_buy_company))
	var can_build := _has_action_option(action_options, "build_facility")
	var can_company_upgrade := _has_action_option(action_options, "company_upgrade")
	upgrade_button.text = "企業建設" if can_company_upgrade else "建造設施" if can_build else "升級"
	upgrade_button.disabled = not (human_turn and phase == "await_action" and (_has_action_option(action_options, "upgrade") or can_build or can_company_upgrade))
	research_button.visible = _has_original_research() and _has_action_option(action_options, "choose_research")
	research_button.disabled = not (human_turn and phase == "await_action" and research_button.visible)
	if research_button.disabled:
		research_popup.hide()
	end_turn_button.disabled = not (human_turn and phase == "await_action" and _has_action_option(action_options, "end_turn"))
	bank_button.disabled = not human_turn or detained or reaction_pending
	cards_button.disabled = not human_turn or detained or reaction_pending
	stocks_button.disabled = not (human_turn and bool(state.get("market", {}).get("open", true))) or detained or reaction_pending
	bank_shortcut.disabled = bank_button.disabled
	cards_shortcut.disabled = cards_button.disabled
	stocks_shortcut.disabled = stocks_button.disabled
	cards_button.text = "背包" if _has_original_inventory() else "卡片"
	cards_shortcut.text = cards_button.text
	shop_button.visible = _shop_available()
	shop_button.disabled = not human_turn
	if not human_turn or not _shop_available():
		shop_popup.hide()
	if not human_turn or phase != "await_action" or not _has_action_option(action_options, facility_popup_action):
		facility_popup.hide()
	if not human_turn or phase != "await_action" or (not can_buy_company and not can_company_upgrade):
		company_popup.hide()
	if not human_turn or detained or reaction_pending:
		bank_popup.hide()
		cards_popup.hide()
		stocks_popup.hide()
	if game_over:
		action_hint_label.text = "本局已結束"
	elif state.has("pending_finance"):
		action_hint_label.text = "請回應付款選擇"
	elif reaction_pending:
		action_hint_label.text = "請決定是否使用嫁禍卡" if _human_trap_response_pending() else "等待嫁禍卡回應"
	elif SleepPresentation.automatic(player):
		action_hint_label.text = SleepPresentation.hint(player)
	elif not human_turn:
		action_hint_label.text = "%s 思考中…" % str(player.get("name", "AI"))
	elif phase == "await_route":
		action_hint_label.text = "請選擇行進方向"
	elif phase == "await_roll":
		action_hint_label.text = "輪到你了，請擲骰"
		if not rest_status.is_empty():
			if int(rest_status.count) == 128:
				action_hint_label.text = "按%s回到道路並開始行動" % roll_button.text
			else:
				action_hint_label.text = "%s，按%s推進回合" % [_rest_status_label(rest_status), roll_button.text]
	elif can_company_upgrade:
		action_hint_label.text = "請先完成企業建設服務"
	elif _has_original_gods() and phase == "await_action" and (not rest_status.is_empty() or _as_array(state.get("last_roll", [])).is_empty()):
		action_hint_label.text = "本回合休息，請結束回合"
	elif _has_original_gods() and int(player.get("god_id", 0)) in [9, 10, 12]:
		action_hint_label.text = "%s將在結束回合時影響停留地產" % OriginalGods.name_for(int(player.god_id))
	elif _has_original_gods() and int(player.get("god_id", 0)) in [7, 8, 15]:
		action_hint_label.text = "%s附身，暫停直接購地與建造" % OriginalGods.name_for(int(player.god_id))
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
	if _presentation_busy or phase != "await_route" or options.is_empty():
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

func _update_financial_popup() -> void:
	if financial_popup == null: return
	var targets: Array = []
	if FinancialPresentation.human_pending(state) and state.pending_finance.stage == "redirect" and game_state.has_method("tax_target_players"):
		targets = game_state.call("tax_target_players", int(state.pending_finance.payer_id))
	financial_popup.sync(state, targets)

func _respond_to_finance(params: Dictionary) -> void:
	if _finance_response_busy or not FinancialPresentation.human_pending(state): return
	_finance_response_busy = true
	var result := _invoke_game("choose_action", ["respond_finance", params])
	_append_local_log(_result_text(result, "已回應付款選擇。"))
	_handle_result(result)
	_finance_response_busy = false

func _pending_trap_for_ui() -> Dictionary:
	if not _has_original_statuses(): return {}
	var pending: Variant = state.get("pending_trap", {})
	return pending if pending is Dictionary else {}

func _human_trap_response_pending() -> bool:
	var pending := _pending_trap_for_ui()
	if pending.is_empty(): return false
	var target := int(pending.get("target_id", -1))
	var players := _as_array(state.get("players", []))
	return target >= 0 and target < players.size() and bool(players[target].get("is_human", false)) and bool(players[target].get("alive", false))

func _update_trap_response_popup() -> void:
	if trap_popup == null: return
	if not _human_trap_response_pending():
		trap_popup.hide()
		return
	var pending := _pending_trap_for_ui()
	trap_decline_button.text = "不使用，接受夢遊" if state.get("pending_trap_card", "") == "夢遊" else "不使用，接受入獄"
	trap_prompt_label.text = SleepPresentation.defense_prompt(_player_name(int(pending.get("caster_id", -1))), str(state.get("pending_trap_card", "陷害")))
	var prior_target := trap_target_option.get_selected_id() if trap_target_option.item_count > 0 else -1
	trap_target_option.clear()
	var targets: Array = _as_array(game_state.call("trap_response_targets")) if game_state != null and game_state.has_method("trap_response_targets") else []
	for target in targets:
		trap_target_option.add_item(_player_name(int(target)), int(target))
		if int(target) == prior_target: trap_target_option.select(trap_target_option.item_count-1)
	trap_redirect_button.disabled = trap_target_option.item_count == 0
	if not trap_popup.visible: trap_popup.popup_centered()

func _respond_to_trap(decline: bool) -> void:
	if _trap_response_busy or not _human_trap_response_pending(): return
	_trap_response_busy = true
	var params: Dictionary = {"cancel":true} if decline else {"target_id":trap_target_option.get_selected_id()}
	var result := _invoke_game("choose_action", ["respond_trap", params])
	_append_local_log(_result_text(result, "已回應陷害卡。"))
	_handle_result(result)
	_trap_response_busy = false


func _maybe_schedule_ai_turn() -> void:
	if _presentation_busy:
		return
	if (news_popup != null and news_popup.visible) or (fate_popup != null and fate_popup.visible):
		return
	if _ai_pending or state.is_empty() or String(state.get("phase", "")) == "game_over" or not _pending_trap_for_ui().is_empty() or state.has("pending_finance"):
		return
	var player := _current_player()
	if (bool(player.get("is_human", true)) and not SleepPresentation.automatic(player)) or bool(player.get("bankrupt", false)):
		return
	_ai_pending = true
	var timer := get_tree().create_timer(0.82)
	timer.timeout.connect(_on_ai_timer_timeout.bind(_presentation_generation))

func _on_ai_timer_timeout(generation := -1) -> void:
	if generation >= 0 and generation != _presentation_generation:
		return
	_ai_pending = false
	if _presentation_busy:
		return
	if (news_popup != null and news_popup.visible) or (fate_popup != null and fate_popup.visible):
		return
	if String(state.get("phase", "")) == "game_over" or not _pending_trap_for_ui().is_empty() or state.has("pending_finance"):
		return
	var player := _current_player()
	if bool(player.get("is_human", true)) and not SleepPresentation.automatic(player):
		return
	var sleeping := SleepPresentation.automatic(player)
	var result := _invoke_game("run_sleep_turn" if sleeping else "run_ai_turn")
	if sleeping:
		_append_local_log("%s：%s" % [str(player.get("name", "玩家")), _result_text(result, "自動推進回合。")])
	else:
		_append_local_log("%s 等待玩家回應。" % str(player.get("name", "AI")) if bool(result.get("awaiting_response", false)) else "%s 完成了自動回合。" % str(player.get("name", "AI")))
	_handle_result(result)

func _update_cards_popup() -> void:
	for child in cards_popup_list.get_children():
		child.free()
	var cards := _as_array(_current_player().get("cards", []))
	inventory_balance_label.text = "點券 %d · 卡片 %d/15" % [int(_current_player().get("points", 0)), cards.size()] if _has_original_inventory() else "卡片 %d/15" % cards.size()
	var options: Array = _as_array(state.get("action_options", []))
	var card_stock_symbols := _stock_symbols_for_ui()
	if cards.is_empty():
		var empty := _make_label("目前沒有可用卡片。", 12, TEXT_MUTED)
		cards_popup_list.add_child(empty)
	else:
		for card_index in range(cards.size()):
			var card_id := str(cards[card_index])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var record: Dictionary = InventoryCatalogue.card(card_id)
			var label := _make_label(str(record.get("name", "卡片 " + card_id)), 12, TEXT_MAIN)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var symbol_option: OptionButton = null
			if card_id == "紅" or card_id == "黑":
				symbol_option = OptionButton.new()
				symbol_option.name = "StockSymbol_" + card_id
				symbol_option.custom_minimum_size = Vector2(112.0, 34.0)
				symbol_option.add_theme_font_size_override("font_size", 11)
				for stock_index in range(card_stock_symbols.size()):
					var card_symbol := str(card_stock_symbols[stock_index])
					symbol_option.add_item("%s · %s" % [card_symbol, _stock_name_for_ui(card_symbol)], stock_index)
				row.add_child(symbol_option)
			var theft_picker: Node = null
			if card_id == "搶奪":
				theft_picker = TheftPicker.new()
				row.add_child(theft_picker)
				var choices: Array = game_state.call("theft_choices") if game_state != null and game_state.has_method("theft_choices") else []
				var visible: Array = board_view.visible_node_indices() if board_view != null else []
				theft_picker.configure(state, choices, visible)
			var target_option: OptionButton = null
			if ["停留", "烏龜", "轉向", "均貧", "陷害", "夢遊", "查稅"].has(card_id):
				target_option = OptionButton.new()
				target_option.name = "CardTarget_" + card_id
				target_option.custom_minimum_size = Vector2(120.0, 34.0)
				target_option.add_theme_font_size_override("font_size", 11)
				var target_players: Array = state.get("players", [])
				var target_method := "tax_target_players" if card_id == "查稅" else ("dream_target_players" if card_id == "夢遊" else "trap_target_players")
				var trap_targets: Array = _as_array(game_state.call(target_method, int(state.get("current_player", -1)))) if card_id in ["陷害", "夢遊", "查稅"] and game_state != null and game_state.has_method(target_method) else []
				var visible_targets: Array = _as_array(board_view.call("visible_node_indices")) if card_id in ["陷害", "夢遊", "查稅"] and board_view != null and board_view.has_method("visible_node_indices") else []
				for target_index in range(target_players.size()):
					var target_player: Dictionary = target_players[target_index] if target_players[target_index] is Dictionary else {}
					if bool(target_player.get("alive", false)) and (card_id != "均貧" or target_index != int(state.get("current_player", -1))) and (card_id not in ["陷害", "夢遊", "查稅"] or (trap_targets.has(target_index) and visible_targets.has(int(target_player.get("position", -1))))):
						target_option.add_item(str(target_player.get("name", "玩家 %d" % (target_index + 1))), target_index)
				if card_id in ["陷害", "夢遊", "查稅"] and target_option.item_count == 0:
					target_option.add_item("畫面內沒有可用目標", -1)
					target_option.disabled = true
					target_option.tooltip_text = "關閉背包後可平移或縮放地圖，再選擇目標。"
				row.add_child(target_option)
			var tile_option: OptionButton = null
			if card_id in ["拆除", "漲價", "查封", "換地", "換屋", "天使", "惡魔", "怪獸"]:
				tile_option = _make_inventory_tile_picker(card_id)
				row.add_child(tile_option)
			if card_id == "購地":
				var current_tile := _current_tile()
				row.add_child(_make_label("%s · %s" % [str(current_tile.get("name", "目前位置")), _format_money(_inventory_purchase_price(current_tile))], 11, TEXT_MUTED))
			var remodel_option: OptionButton = null
			if card_id == "改建":
				var current_tile := _current_tile()
				if current_tile.get("kind", "") == "facility":
					remodel_option = OptionButton.new()
					remodel_option.name = "RemodelType_改建"
					remodel_option.custom_minimum_size = Vector2(180.0, 34.0)
					for type_id in range(5):
						remodel_option.add_item(_facility_name(type_id) + ("（尚未開放）" if type_id == 4 and not _has_original_research() else ""), type_id)
					remodel_option.set_item_disabled(4, not _has_original_research())
					remodel_option.select(clampi(int(current_tile.get("facility_type", 0)), 0, 4 if _has_original_research() else 3))
					row.add_child(remodel_option)
				elif current_tile.get("kind", "") == "property":
					row.add_child(_make_label("改為普通住宅" if bool(current_tile.get("is_chain_store", false)) else "改為 1 級連鎖店", 11, TEXT_MUTED))
			var angel_option: OptionButton = null
			if card_id == "天使" and tile_option != null:
				angel_option = OptionButton.new()
				angel_option.name = "AngelFacilityType"
				angel_option.custom_minimum_size = Vector2(150.0, 34.0)
				for type_id in range(5):
					angel_option.add_item(_facility_name(type_id), type_id)
				angel_option.tooltip_text = "空設施的建造類型"
				row.add_child(angel_option)
				var refresh_angel_type := func(_index: int = 0) -> void:
					var target_id := tile_option.get_selected_id()
					var board: Array = state.get("board", [])
					var target: Dictionary = board[target_id] if target_id >= 0 and target_id < board.size() else {}
					angel_option.visible = target.get("kind", "") == "facility" and int(target.get("building_level", 0)) == 0
				tile_option.item_selected.connect(refresh_angel_type)
				refresh_angel_type.call()
			var summon_visible_nodes: Array = []
			var summon_target: Dictionary = {}
			if card_id == "請神符":
				if board_view != null and board_view.has_method("visible_node_indices"):
					summon_visible_nodes = _as_array(board_view.call("visible_node_indices"))
				if game_state != null and game_state.has_method("god_card_target"):
					summon_target = game_state.call("god_card_target", int(state.get("current_player", -1)), summon_visible_nodes)
				var preview := _make_label("畫面內沒有可請來的神明" if summon_target.is_empty() else "請來：" + OriginalGods.name_for(int(summon_target.get("id", 0))), 11, TEXT_MUTED)
				preview.name = "SummonGodTarget"
				row.add_child(preview)
			var use := _make_button("使用", func() -> void:
				var params: Dictionary = {"card_id": card_id}
				if theft_picker != null:
					var selected: Dictionary = theft_picker.selection()
					if selected.is_empty():
						return
					params.merge(selected)
				if card_id == "請神符":
					params["visible_tile_ids"] = summon_visible_nodes
				if angel_option != null and angel_option.visible:
					params["facility_type"] = angel_option.get_selected_id()
				if remodel_option != null:
					params["facility_type"] = remodel_option.get_selected_id()
				if symbol_option != null:
					var selected_stock_index := symbol_option.get_selected_id()
					if selected_stock_index >= 0 and selected_stock_index < card_stock_symbols.size():
						params["symbol"] = str(card_stock_symbols[selected_stock_index])
				if target_option != null:
					params["target_id"] = target_option.get_selected_id()
				if tile_option != null:
					params["tile_id"] = tile_option.get_selected_id()
				# Close inventory before a card can open its reaction window.
				cards_popup.hide()
				var result := _invoke_game("choose_action", ["use_card", params])
				_append_local_log("使用卡片 %s：%s" % [card_id, _result_text(result, "已送出卡片指令。")])
				_handle_result(result)
			)
			var implemented := _item_implemented("card", card_id)
			use.disabled = not implemented or not _has_action_option(options, "use_card")
			use.name = "UseCard_" + card_id
			if theft_picker != null:
				use.disabled = use.disabled or theft_picker.selection().is_empty()
				theft_picker.selection_changed.connect(func(available: bool):
					use.disabled = not implemented or not _has_action_option(options, "use_card") or not available
				)
			if (tile_option != null and tile_option.disabled) or (target_option != null and target_option.disabled):
				use.disabled = true
			if card_id == "請神符":
				use.disabled = use.disabled or summon_target.is_empty()
				use.tooltip_text = "自動請來畫面內最近的神明；可關閉背包後平移或縮放地圖。"
			if card_id == "送神符":
				use.disabled = use.disabled or (int(_current_player().get("bomb_steps", 0)) <= 0 and int(_current_player().get("god_id", 0)) not in [5, 6, 7, 8, 10])
				use.tooltip_text = "送走自己的壞神，並清除攜帶的定時炸彈。"
			if card_id in ["送神符", "請神符"]:
				use.disabled = use.disabled or not _player_rest_status(_current_player()).is_empty()
			if card_id == "購地":
				var current_tile := _current_tile()
				use.disabled = use.disabled or str(current_tile.get("kind", "")) not in ["property", "facility"] or int(current_tile.get("owner", -1)) == int(state.get("current_player", -1)) or _inventory_purchase_price(current_tile) > int(_current_player().get("cash", 0)) or bool(state.get("property_action_used", false))
				if _has_original_gods():
					use.disabled = use.disabled or int(current_tile.get("owner", -1)) < 0 or not _player_rest_status(_current_player()).is_empty()
			if card_id == "改建":
				var current_tile := _current_tile()
				use.disabled = use.disabled or str(current_tile.get("kind", "")) not in ["property", "facility"] or int(current_tile.get("building_level", 0)) <= 0 or not _player_rest_status(_current_player()).is_empty()
				use.tooltip_text = "改建腳下設施；選擇同類型也會消耗改建卡。" if current_tile.get("kind", "") == "facility" else "改建腳下已有建物的住宅；轉為連鎖店會降至 1 級。"
			if not implemented:
				use.text = "尚未還原"
			elif card_id == "免費":
				use.disabled = true
				use.text = "付款時選擇"
				use.tooltip_text = "符合條件的地租、設施、企業服務或查稅發生時，可選擇使用一次。"
			elif _has_original_statuses() and card_id in ["免罪", "復仇", "嫁禍"]:
				use.disabled = true
				use.text = "受影響時選擇" if card_id == "嫁禍" else "自動觸發"
			row.add_child(use)
			cards_popup_list.add_child(row)

	if _has_original_inventory():
		_append_tool_inventory()

func _stock_symbols_for_ui() -> Array:
	var symbols: Array = []
	if game_state != null and game_state.has_method("get_stock_symbols"):
		var source: Variant = game_state.call("get_stock_symbols")
		if source is Array:
			for value in source:
				var symbol := str(value).to_lower()
				if not symbol.is_empty() and not symbols.has(symbol):
					symbols.append(symbol)
	if not symbols.is_empty():
		return symbols
	var market: Dictionary = state.get("market", {})
	var rows: Variant = market.get("rows", {})
	if not rows is Dictionary or rows.is_empty():
		rows = market.get("prices", {})
	if rows is Dictionary:
		for key in rows.keys():
			var symbol := str(key).to_lower()
			if not symbol.is_empty() and not symbols.has(symbol):
				symbols.append(symbol)
	return symbols if not symbols.is_empty() else ["tech", "transport", "energy"]


func _stock_name_for_ui(symbol: String) -> String:
	if game_state != null and game_state.has_method("get_stock_name"):
		var value: Variant = game_state.call("get_stock_name", symbol)
		if value is String and not value.is_empty():
			return value
	return {"tech": "科技", "transport": "運輸", "energy": "能源"}.get(symbol, symbol)


func _stock_row_for_ui(symbol: String) -> Dictionary:
	var market: Dictionary = state.get("market", {})
	var rows: Variant = market.get("rows", {})
	if rows is Dictionary:
		var row: Variant = rows.get(symbol, rows.get(StringName(symbol), {}))
		if row is Dictionary:
			return row
	return {}


func _stock_price_for_ui(symbol: String) -> float:
	var row := _stock_row_for_ui(symbol)
	if not row.is_empty():
		return float(row.get("price", row.get("value", 0.0)))
	var market: Dictionary = state.get("market", {})
	var prices: Variant = market.get("prices", {})
	if prices is Dictionary:
		var quote: Variant = prices.get(symbol, prices.get(StringName(symbol), 0.0))
		if quote is Dictionary:
			return float(quote.get("price", quote.get("value", 0.0)))
		if quote is int or quote is float:
			return float(quote)
	return 0.0


func _stock_holding(player: Dictionary, symbol: String) -> int:
	var holdings: Variant = player.get("stocks", {})
	if holdings is Dictionary:
		return int(holdings.get(symbol, 0))
	return 0


func _format_price(price: float) -> String:
	return "$%.2f" % price


func _update_stocks_popup() -> void:
	for child in stocks_popup_list.get_children():
		child.free()
	var market: Dictionary = state.get("market", {})
	var options: Array = _as_array(state.get("action_options", []))
	var player := _current_player()
	var symbols := _stock_symbols_for_ui()
	var market_open := bool(market.get("open", true))
	var is_company_market := _has_original_companies()
	var account := int(player.get("deposit" if is_company_market else "cash", 0))
	var account_name := "存款" if is_company_market else "現金"
	var account_label := _make_label("%s：%s　·　持股為每檔獨立計算" % [account_name, _format_money(account)], 12, TEXT_GOLD)
	stocks_popup_list.add_child(account_label)
	for value in symbols:
		var symbol := str(value)
		var stock_row := _stock_row_for_ui(symbol)
		var price := _stock_price_for_ui(symbol)
		var holdings := _stock_holding(player, symbol)
		var market_supply := int(stock_row.get("market_supply", -1)) if not stock_row.is_empty() else -1
		var turn_supply := int(stock_row.get("turn_supply", market_supply)) if not stock_row.is_empty() else -1
		var available := mini(market_supply, turn_supply) if market_supply >= 0 and turn_supply >= 0 else -1
		var suspension := int(stock_row.get("suspension", 0)) if not stock_row.is_empty() else 0
		var row := HBoxContainer.new()
		row.name = "StockRow_" + symbol
		row.add_theme_constant_override("separation", 7)
		var detail := "%s（%s）　·　價格 %s" % [_stock_name_for_ui(symbol), symbol, _format_price(price)]
		if available >= 0:
			detail += "\n市場 %d 股　·　本回合 %d 股　·　持有 %d 股" % [market_supply, turn_supply, holdings]
		else:
			detail += "\n持有 %d 股" % holdings
		if suspension > 0:
			detail += "　·　暫停交易 %d 天" % suspension
		var label := _make_label(detail, 11, Color("#f28d83") if suspension > 0 else TEXT_MAIN)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size.x = 250.0
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var quantity := SpinBox.new()
		quantity.name = "StockQuantity_" + symbol
		quantity.min_value = 1
		quantity.max_value = max(1, max(available, holdings))
		quantity.step = 1
		quantity.value = 1
		quantity.custom_minimum_size.x = 72.0
		quantity.add_theme_font_size_override("font_size", 11)
		row.add_child(quantity)
		var buy := _make_button("買入", func() -> void:
			var result := _invoke_game("choose_action", ["buy_stock", {"symbol": symbol, "quantity": int(quantity.value)}])
			_append_local_log("買入 %s × %d：%s" % [symbol, int(quantity.value), _result_text(result, "已送出買股指令。")])
			call_deferred("_handle_result", result)
		)
		buy.name = "BuyStock_" + symbol
		buy.custom_minimum_size.x = 118.0
		row.add_child(buy)
		var sell := _make_button("賣出", func() -> void:
			var result := _invoke_game("choose_action", ["sell_stock", {"symbol": symbol, "quantity": int(quantity.value)}])
			_append_local_log("賣出 %s × %d：%s" % [symbol, int(quantity.value), _result_text(result, "已送出賣股指令。")])
			call_deferred("_handle_result", result)
		)
		sell.name = "SellStock_" + symbol
		sell.custom_minimum_size.x = 118.0
		row.add_child(sell)
		var update_quote := func(_value: float = 1.0) -> void:
			var count := int(quantity.value)
			var amount := int(price * count)
			buy.text = "買入 %s" % _format_money(amount)
			sell.text = "賣出 %s" % _format_money(amount)
			var valid_market := _is_human_turn() and market_open and suspension == 0
			var buy_supply_ok := available < 0 or count <= available
			var sell_holding_ok := count <= holdings
			buy.disabled = not (valid_market and _has_action_option(options, "buy_stock") and buy_supply_ok and account >= amount)
			sell.disabled = not (valid_market and _has_action_option(options, "sell_stock") and sell_holding_ok)
		quantity.tooltip_text = "每次交易股數；公司市場買入使用銀行存款。"
		quantity.value_changed.connect(update_quote)
		update_quote.call()
		stocks_popup_list.add_child(row)


func _company_at_tile(tile: Dictionary) -> Dictionary:
	if not _has_original_companies():
		return {}
	var tile_index := int(tile.get("index", -1))
	if game_state != null and game_state.has_method("get_company_at"):
		var company: Variant = game_state.call("get_company_at", tile_index)
		if company is Dictionary:
			return company
	var fallback: Variant = tile.get("company_state", {})
	return fallback if fallback is Dictionary else {}


func _company_stock_symbol(company: Dictionary) -> String:
	var stock_index := int(company.get("stock_index", -1))
	var symbols := _stock_symbols_for_ui()
	if stock_index >= 0 and stock_index < symbols.size():
		return str(symbols[stock_index])
	return "s%02d" % (stock_index + 1) if stock_index >= 0 else ""


func _player_name(player_id: int) -> String:
	var players: Array = _as_array(state.get("players", []))
	if player_id >= 0 and player_id < players.size() and players[player_id] is Dictionary:
		return str(players[player_id].get("name", "玩家 %d" % (player_id + 1)))
	return "玩家 %d" % (player_id + 1)


func _company_face_price(company: Dictionary) -> int:
	return int(int(company.get("stock_value", 0)) / 10000)


func _company_average_earnings(company: Dictionary) -> int:
	var cumulative := int(company.get("cumulative_profit", 0))
	var months := int(state.get("company_months", 0))
	return cumulative if months <= 0 else int(float(cumulative) / float(months))


func _company_purchase_cap(company: Dictionary, player: Dictionary) -> int:
	var face_price := _company_face_price(company)
	if face_price <= 0:
		return 0
	return mini(1000, mini(int(state.get("company_purchase_remaining", 0)), mini(int(company.get("treasury", 0)), int(player.get("cash", 0)) / face_price)))


func _company_upgrade_targets(player_id: int) -> Array:
	if game_state != null and game_state.has_method("get_company_upgrade_targets"):
		return _as_array(game_state.call("get_company_upgrade_targets", player_id))
	return []


func _company_upgrade_fee(tile: Dictionary, player_id: int, company_owner_id: int = -1) -> int:
	if game_state != null and game_state.has_method("get_company_upgrade_fee"):
		return int(game_state.call("get_company_upgrade_fee", player_id, int(tile.get("index", -1)), company_owner_id))
	if company_owner_id == player_id:
		return 0
	var land_price := int(tile.get("land_price", tile.get("cost", 0)))
	return land_price * int(state.get("price_index", 1))


func _ensure_company_facility_type_picker(tile: Dictionary) -> void:
	var needs_picker: bool = str(tile.get("kind", "")) == "facility" and int(tile.get("building_level", 0)) == 0
	if _company_service_type != null and not is_instance_valid(_company_service_type):
		_company_service_type = null
	if needs_picker:
		if _company_service_type != null:
			return
		_company_service_type = OptionButton.new()
		_company_service_type.name = "CompanyFacilityType"
		_company_service_type.custom_minimum_size = Vector2(0.0, 36.0)
		_company_service_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_company_service_type.add_theme_font_size_override("font_size", 11)
		for facility_type in range(5 if _has_original_research() else 4):
			_company_service_type.add_item(_facility_name(facility_type), facility_type)
		company_popup_list.add_child(_company_service_type)
		if _company_service_target != null:
			company_popup_list.move_child(_company_service_type, company_popup_list.get_children().find(_company_service_target) + 1)
		return
	if _company_service_type != null:
		_company_service_type.free()
		_company_service_type = null


func _update_company_popup() -> void:
	if company_popup_list == null:
		return
	for child in company_popup_list.get_children():
		child.free()
	_company_purchase_quantity = null
	_company_purchase_button = null
	_company_service_target = null
	_company_service_type = null
	_company_service_button = null
	var tile := _current_tile()
	var company := _company_at_tile(tile)
	if company.is_empty():
		company_popup.hide()
		return
	var player := _current_player()
	var player_id := int(state.get("current_player", -1))
	var stock_symbol := _company_stock_symbol(company)
	var stock_name := _stock_name_for_ui(stock_symbol)
	var owner_id := int(company.get("owner", -1))
	var owner_text := "無" if owner_id < 0 else _player_name(owner_id)
	var stock_row := _stock_row_for_ui(stock_symbol)
	var stock_price := _stock_price_for_ui(stock_symbol)
	company_popup_list.add_child(_make_label("%s　·　%s（%s）" % [str(company.get("display_name", "企業")), stock_name, stock_symbol], 15, TEXT_MAIN))
	company_popup_list.add_child(_make_label("市價 %s　·　面額 %s　·　經營者 %s" % [_format_price(stock_price), _format_price(float(_company_face_price(company))), owner_text], 11, TEXT_MUTED))
	company_popup_list.add_child(_make_label("你的持股 %d 股　·　企業庫存 %d 股　·　本回合可購買額度 %d 股" % [_stock_holding(player, stock_symbol), int(company.get("treasury", 0)), int(state.get("company_purchase_remaining", 0))], 11, TEXT_MAIN))
	company_popup_list.add_child(_make_label("本月盈餘 %s　·　累計盈餘 %s　·　平均盈餘 %s" % [_format_money(int(company.get("monthly_profit", 0))), _format_money(int(company.get("cumulative_profit", 0))), _format_money(_company_average_earnings(company))], 11, TEXT_GOLD))
	var suspension := int(stock_row.get("suspension", 0)) if not stock_row.is_empty() else 0
	if suspension > 0:
		company_popup_list.add_child(_make_label("關聯股票暫停交易 %d 天。" % suspension, 11, Color("#f28d83")))
	var pending_company := int(state.get("company_service_pending", 0))
	var options := _as_array(state.get("action_options", []))
	var can_buy_company := _has_action_option(options, "buy_company") and pending_company == 0
	var purchase_cap := _company_purchase_cap(company, player)
	var purchase_heading := _make_label("直接用現金購買企業股份", 13, TEXT_GOLD)
	company_popup_list.add_child(purchase_heading)
	var purchase_row := HBoxContainer.new()
	purchase_row.name = "CompanyPurchaseRow"
	purchase_row.add_theme_constant_override("separation", 7)
	_company_purchase_quantity = SpinBox.new()
	_company_purchase_quantity.name = "CompanyPurchaseQuantity"
	_company_purchase_quantity.min_value = 1
	_company_purchase_quantity.max_value = max(1, purchase_cap)
	_company_purchase_quantity.step = 1
	_company_purchase_quantity.value = 1
	_company_purchase_quantity.custom_minimum_size.x = 88.0
	_company_purchase_quantity.add_theme_font_size_override("font_size", 11)
	purchase_row.add_child(_company_purchase_quantity)
	_company_purchase_button = _make_button("購入", func() -> void:
		var current_company := _company_at_tile(_current_tile())
		if current_company.is_empty() or int(current_company.get("id", -1)) != int(company.get("id", -2)):
			company_popup.hide()
			return
		var result := _invoke_game("choose_action", ["buy_company", {"quantity": int(_company_purchase_quantity.value)}])
		_append_local_log("購入%s股份 × %d：%s" % [str(company.get("display_name", "企業")), int(_company_purchase_quantity.value), _result_text(result, "已送出企業股份指令。")])
		call_deferred("_handle_result", result)
		if bool(result.get("ok", false)):
			company_popup.hide()
	)
	_company_purchase_button.name = "BuyCompanyShares"
	_company_purchase_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	purchase_row.add_child(_company_purchase_button)
	company_popup_list.add_child(purchase_row)
	var purchase_quote := _make_label("", 11, TEXT_MUTED)
	purchase_quote.name = "CompanyPurchaseQuote"
	purchase_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	company_popup_list.add_child(purchase_quote)
	var update_purchase_quote := func(_value: float = 1.0) -> void:
		var count := int(_company_purchase_quantity.value)
		var amount := _company_face_price(company) * count
		_company_purchase_button.text = "購入 %d 股 · %s" % [count, _format_money(amount)]
		purchase_quote.text = "每股面額 %s · 可購買上限 %d 股" % [_format_price(float(_company_face_price(company))), purchase_cap]
		_company_purchase_button.disabled = not (_is_human_turn() and _phase_is_action() and can_buy_company and purchase_cap > 0 and count <= purchase_cap)
	_company_purchase_quantity.value_changed.connect(update_purchase_quote)
	update_purchase_quote.call()
	if not can_buy_company:
		purchase_quote.text += "\n" + ("請先完成企業建設服務。" if pending_company != 0 else "目前無法在此造訪購買股份。")

	if _has_action_option(options, "company_upgrade") or pending_company != 0:
		company_popup_list.add_child(HSeparator.new())
		company_popup_list.add_child(_make_label("企業建設服務", 13, TEXT_GOLD))
		if pending_company != 0:
			company_popup_list.add_child(_make_label("請先選擇一個自己的地產或設施完成本次建設服務。", 11, TEXT_MUTED))
		var targets := _company_upgrade_targets(player_id)
		if targets.is_empty():
			company_popup_list.add_child(_make_label("目前沒有可選的自有地產或設施。", 11, TEXT_MUTED))
		else:
			_company_service_target = OptionButton.new()
			_company_service_target.name = "CompanyUpgradeTarget"
			_company_service_target.custom_minimum_size = Vector2(0.0, 36.0)
			_company_service_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_company_service_target.add_theme_font_size_override("font_size", 11)
			for target_value in targets:
				var target_id := int(target_value)
				var target_tile := _tile_for_index(target_id)
				var target_level := int(target_tile.get("building_level", 0))
				var fee := _company_upgrade_fee(target_tile, player_id, owner_id)
				var target_text := "%s · 第 %d 級" % [str(target_tile.get("name", "格位 %02d" % (target_id + 1))), target_level]
				if owner_id == player_id:
					target_text += " · 免費（經營者服務，最多提升 2 級）"
				else:
					target_text += " · 費用 %s" % _format_money(fee)
				_company_service_target.add_item(target_text, target_id)
			company_popup_list.add_child(_company_service_target)
			var selected_tile := _tile_for_index(_company_service_target.get_selected_id())
			_ensure_company_facility_type_picker(selected_tile)
			var service_quote := _make_label("", 11, TEXT_MUTED)
			service_quote.name = "CompanyUpgradeQuote"
			company_popup_list.add_child(service_quote)
			_company_service_button = _make_button("建設服務", func() -> void:
				if _company_service_target == null or _company_service_target.item_count == 0:
					return
				var params: Dictionary = {"tile_id": _company_service_target.get_selected_id()}
				if _company_service_type != null:
					params["facility_type"] = _company_service_type.get_selected_id()
				var result := _invoke_game("choose_action", ["company_upgrade", params])
				_append_local_log("企業建設：%s" % _result_text(result, "已送出企業建設指令。"))
				call_deferred("_handle_result", result)
				if bool(result.get("ok", false)):
					company_popup.hide()
			)
			_company_service_button.name = "CompanyUpgrade"
			company_popup_list.add_child(_company_service_button)
			var update_service_quote := func(_index: int = 0) -> void:
				var selected_id := _company_service_target.get_selected_id()
				var selected := _tile_for_index(selected_id)
				_ensure_company_facility_type_picker(selected)
				var fee := _company_upgrade_fee(selected, player_id, owner_id)
				var owner_service := owner_id == player_id
				service_quote.text = "目標：%s　·　%s" % [str(selected.get("name", "格位")), "免費（經營者服務，最多提升 2 級）" if owner_service else "服務費 " + _format_money(fee)]
				_company_service_button.disabled = not (_is_human_turn() and _phase_is_action() and _has_action_option(_as_array(state.get("action_options", [])), "company_upgrade"))
				_company_service_button.text = "免費建設" if owner_service else "支付 %s 建設" % _format_money(fee)
			_company_service_target.item_selected.connect(update_service_quote)
			update_service_quote.call()

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


func _phase_is_action() -> bool:
	return str(state.get("phase", "")) == "await_action"

func _kind_label(kind: String) -> String:
	match kind:
		"fate":
			return "命運"
		"news":
			return "新聞"
		"facility":
			return "商業設施"
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
		"fate_resolved":
			return str(event.get("summary", "命運效果已結算。"))
		"fate_preview":
			return "命運來訪"
		"fate_skipped":
			return "本次沒有可套用的命運。"
		"news_applied":
			return str(event.get("summary", "新聞效果已結算。"))
		"news_preview":
			return "新聞報導"
		"news_skipped":
			return "本次沒有可套用的新聞。"
		"god_attached":
			return "%s附身 · %d 天" % [OriginalGods.name_for(int(event.get("god_id", 0))), int(event.get("days", 0))]
		"god_detached":
			return "%s離開" % OriginalGods.name_for(int(event.get("god_id", 0)))
		"god_spawned":
			return "%s出現在%s" % [OriginalGods.name_for(int(event.get("god_id", 0))), _tile_name(int(event.get("node", -1)))]
		"god_spawn_unavailable":
			return "%s暫無可出現的位置" % OriginalGods.name_for(int(event.get("god_id", 0)))
		"dog_encounter":
			return "遭惡犬咬傷，住院 3 天" if int(event.get("hospital_days", 0)) > 0 else "乘坐交通工具通過惡犬"
		"financial_response_requested":
			return "%s決定是否使用免費卡 · %s" % [_player_name(int(event.get("payer_id", -1))), _format_money(int(event.get("amount", 0)))]
		"financial_redirect_requested":
			return "%s決定是否使用嫁禍卡" % _player_name(int(event.get("payer_id", -1)))
		"financial_free_used":
			return "%s使用免費卡，免付 %s" % [_player_name(int(event.get("payer_id", -1))), _format_money(int(event.get("amount", 0)))]
		"financial_free_declined":
			return "%s不使用免費卡" % _player_name(int(event.get("payer_id", -1)))
		"financial_tax_redirected":
			return "嫁禍卡將查稅轉給%s · %s" % [_player_name(int(event.get("payer_id", -1))), _format_money(int(event.get("amount", 0)))]
		"financial_payment_waived":
			return "免除本次付款 %s" % _format_money(int(event.get("amount", 0)))
		"financial_response_error":
			return "付款選擇未能完成：%s" % str(event.get("error", "請重試"))
		"trap_response_requested":
			return "%s 決定是否使用嫁禍卡" % _player_name(int(event.get("target_id", -1)))
		"trap_blocked":
			return "免罪卡自動抵銷%s" % str(event.get("card_id", "陷害"))
		"trap_redirected":
			return "嫁禍卡將處罰轉給%s" % _player_name(int(event.get("target_id", -1)))
		"trap_revenge":
			return "復仇卡自動反擊，%s也%s" % [_player_name(int(event.get("caster_id", -1))), "進入夢遊" if event.get("card_id", "") == "夢遊" else "被送入監獄"]
		"trap_resolved":
			return "已接受%s" % ("夢遊狀態" if event.get("card_id", "") == "夢遊" else "入獄處罰")
		"sleep_admitted", "sleep_ticked":
			return SleepPresentation.label({"kind": event.get("sleep_kind", "dream"), "count": int(event.get("remaining", 0))})
		"sleep_released":
			return "已從%s醒來" % ("冬眠" if event.get("sleep_kind", "") == "winter" else "夢遊")
		"status_admitted":
			return "%s · %s" % ["送往醫院" if event.get("status_kind", "") == "hospital" else "送往監獄", _tile_name(int(event.get("node", -1)))]
		"status_skipped":
			return _rest_status_label({"kind":event.get("status_kind", "hospital"),"count":int(event.get("remaining",0))})
		"status_released":
			return "康復出院，從醫院格繼續行動" if event.get("status_kind", "") == "hospital" else "刑滿出獄，從監獄格繼續行動"
		"hospital_started":
			return "開始住院休養 · %d 天" % int(event.get("hospital_days", 0))
		"hospital_skipped":
			return "住院休養 · 剩餘 %d 天" % int(event.get("days", 0))
		"hospital_recovered":
			return "康復出院"
		"god_respawn_skipped":
			return "%s已在場上" % OriginalGods.name_for(int(event.get("god_id", 0)))
		"god_cash_effect":
			return "神明贈予 %s" % _format_money(int(event.get("amount", 0)))
		"god_cash_unavailable":
			return "銀行資金不足，本次未取得神明贈款"
		"god_card_drop":
			return "神明移除 %d 張卡片" % int(event.get("count", 0))
		"god_inventory_cleared":
			return "死神清空卡片、道具與裝備載具"
		"god_charge_modifier":
			return "%s將費用由 %s 調整為 %s" % [OriginalGods.name_for(int(event.get("god_id", 0))), _format_money(int(event.get("from_amount", 0))), _format_money(int(event.get("to_amount", 0)))]
		"god_charge_waived":
			return "%s免除費用 %s" % [OriginalGods.name_for(int(event.get("god_id", 0))), _format_money(int(event.get("amount", 0)))]
		"property_fee_waived":
			var fee_name := "設施費" if event.get("kind", "") == "facility" else "租金"
			var owner_status: String = {"hospital": "住院", "prison": "入獄", "winter": "冬眠", "dream": "夢遊"}.get(str(event.get("reason", "")), "死神附身")
			return "地主%s，本次免收%s" % [owner_status, fee_name]
		"god_fortune_construction":
			return "%s額外加蓋%s至第 %d 級" % [OriginalGods.name_for(int(event.get("god_id", 0))), _tile_name(int(event.get("tile_id", -1))), int(event.get("to_level", 0))]
		"god_property_effect":
			var god_name: String = OriginalGods.name_for(int(event.get("god_id", 0)))
			var property_name := _tile_name(int(event.get("tile_id", -1)))
			if event.get("effect", "") == "occupy":
				return "%s取得%s的所有權" % [god_name, property_name]
			return "%s將%s調整為第 %d 級" % [god_name, property_name, int(event.get("to_level", 0))]
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
		"facility_service":
			var facility_name := str(event.get("facility_name", "商業設施"))
			var reason := str(event.get("reason", ""))
			if reason == "sealed":
				return "%s查封中，暫停服務" % facility_name
			if reason == "walking_free":
				return "步行經過加油站，不收費"
			if reason == "gas_service":
				return "加油站 · 本次擲骰 %d 點 · 費用 %s" % [int(event.get("last_roll_total", 0)), _format_money(int(event.get("fee", 0)))]
			if int(event.get("resolved_roll", 0)) > 0:
				return "%s輪盤 %d 倍 · 費用 %s" % [facility_name, int(event.get("resolved_roll", 0)), _format_money(int(event.get("fee", 0)))]
			return "抵達%s，不收設施費" % facility_name
		"facility_blocked":
			return "免付設施費 %s" % _format_money(int(event.get("amount", 0)))
		"facility_state_expired":
			var remaining := int(event.get("to_state", 0)) >> 4
			return "設施臨時效果已到期" if remaining == 0 else "設施臨時效果剩餘 %d 天" % remaining
		"payment":
			return "支付 %s" % _format_money(int(event.get("amount", 0)))
		"deposit":
			return "存入銀行 %s" % _format_money(int(event.get("amount", 0)))
		"withdraw":
			return "從銀行提取 %s" % _format_money(int(event.get("amount", 0)))
		"stock_bought":
			return "買入 %s（%s）× %d · %s" % [str(event.get("stock_name", _stock_name_for_ui(str(event.get("symbol", ""))))), str(event.get("symbol", "")), int(event.get("quantity", 0)), _format_price(float(event.get("price", 0.0)))]
		"stock_sold":
			return "賣出 %s（%s）× %d · %s" % [str(event.get("stock_name", _stock_name_for_ui(str(event.get("symbol", ""))))), str(event.get("symbol", "")), int(event.get("quantity", 0)), _format_price(float(event.get("price", 0.0)))]
		"company_visited":
			var visited_name := str(event.get("company_name", "企業"))
			var visited_fee := int(event.get("base_fee", 0))
			return "到訪企業 %s · %s" % [visited_name, "服務費 %s" % _format_money(visited_fee) if visited_fee > 0 else "本次未收費"]
		"company_shares_bought":
			return "購入企業股份 %s × %d · 現金 %s" % [str(event.get("company_name", "企業")), int(event.get("quantity", 0)), _format_money(int(event.get("amount", 0)))]
		"company_owner_changed":
			var owner_value := int(event.get("owner_id", -1))
			return "企業 %s 經營者改為 %s" % [str(event.get("company_name", "企業")), "無" if owner_value < 0 else _player_name(owner_value)]
		"company_insurance_granted":
			var granted_status := int(event.get("insurance_status", 0))
			return "企業 %s 提供保險 %d 天 · 狀態 %d" % [str(event.get("company_name", "保險公司")), int(event.get("days", 0)), granted_status]
		"company_insurance_paid":
			return "保險公司理賠 %s · 增加住院 %d 天" % [_format_money(int(event.get("amount", 0))), int(event.get("days", 0))]
		"company_service_unavailable":
			return "企業服務暫不可用 · %s" % str(event.get("reason", "來源限制"))
		"company_dividend_unavailable":
			return "企業分紅暫不可用 · %s" % str(event.get("reason", "餘額上限"))
		"company_dividend":
			return "企業 %s 發放股利 %s · 實發 %s" % [str(event.get("company_name", "企業")), _format_money(int(event.get("pool", 0))), _format_money(int(event.get("distributed", 0)))]
		"company_dividend_paid":
			return "取得企業股利 %s" % _format_money(int(event.get("amount", 0)))
		"company_upgrade", "company_construction":
			return "企業建設 %s · %s" % [str(event.get("company_name", "企業")), _tile_name(int(event.get("tile_id", -1)))]
		"card_used":
			var card_name := _inventory_item_name("card", str(event.get("card_id", "")))
			if event.get("effect", "") in ["swap_ownership", "swap_buildings"]:
				var exchanged := "所有權" if event.effect == "swap_ownership" else "建物"
				return "使用%s：交換%s與%s的%s" % [card_name, _event_tile_name(event.get("source_tile_id")), _event_tile_name(event.get("target_tile_id")), exchanged]
			if event.has("tile_id") or event.has("property_id"):
				return "使用%s：%s" % [card_name, _tile_name(int(event.get("tile_id", event.get("property_id", -1))))]
			return "使用%s" % card_name
		"tool_used":
			var tool_name := _inventory_item_name("tool", str(event.get("tool_id", "")))
			if event.get("effect", "") == "remote_dice":
				return "使用%s：下次移動 %d 點" % [tool_name, int(event.get("value", 0))]
			if event.has("tile_id"):
				return "使用%s：%s" % [tool_name, _tile_name(int(event.get("tile_id", -1)))]
			return "使用%s" % tool_name
		"vehicle_selected":
			var names := {"walking": "步行", "motorcycle": "機車", "car": "汽車", "engineering": "工程車"}
			return "%s · %d 顆骰子" % [str(names.get(str(event.get("vehicle", "walking")), "交通工具")), int(event.get("dice_count", 1))]
		"engineering_demolition":
			return "工程車拆除了%s的建物" % _tile_name(int(event.get("tile_id", -1)))
		"engineering_expired":
			var names := {"walking": "步行", "motorcycle": "機車", "car": "汽車"}
			return "工程車期限結束，恢復%s" % str(names.get(str(event.get("restored_vehicle", "walking")), "步行"))
		"item_bought", "item_sold":
			var item_name := _inventory_item_name(str(event.get("item_kind", "")), str(event.get("item_id", "")))
			return "%s %s × %d · %d 點券" % ["買入" if event_type == "item_bought" else "出售", item_name, int(event.get("quantity", 1)), int(event.get("price", event.get("sale_price", 0)))]
		"points_landed", "points_passed":
			return "取得 %d 點券" % int(event.get("points", 0))
		"card_passed", "event_drawn", "god_fortune":
			if event.has("error"):
				return "本次未取得卡片"
			var card_id := str(event.get("card_id", ""))
			if InventoryCatalogue.card(card_id).is_empty():
				return "抽到事件：%s" % str(event.get("name", card_id))
			var detail := "取得%s" % _inventory_item_name("card", card_id)
			var evicted := str(event.get("evicted_card_id", ""))
			if not evicted.is_empty():
				detail += " · 背包已滿，退回%s" % _inventory_item_name("card", evicted)
			return detail
		"event_draw_failed":
			return "本次未取得卡片"
		"mine_triggered":
			var detail := "在%s踩到地雷 · 住院 %d 天" % [_tile_name(int(event.get("node", -1))), int(event.get("hospital_days", 3))]
			if str(event.get("vehicle", "walking")) in ["motorcycle", "car"]:
				detail += " · 載具損毀，改為步行"
			return detail
		"bomb_picked_up":
			return "拾取定時炸彈 · 剩餘 %d 步" % int(event.get("remaining", 38))
		"bomb_countdown":
			return "定時炸彈 · 剩餘 %d 步" % int(event.get("remaining", 0))
		"bomb_exploded":
			var detail := "定時炸彈爆炸 · 住院 %d 天" % int(event.get("hospital_days", 5))
			if str(event.get("vehicle", "walking")) in ["motorcycle", "car"]:
				detail += " · 載具損毀，改為步行"
			var damage_value: Variant = event.get("damage", {})
			var damage: Dictionary = damage_value if damage_value is Dictionary else {}
			if bool(damage.get("damaged", false)):
				detail += " · 建築降至 %d 級" % int(damage.get("to_level", 0))
			return detail
		"machine_doll_cleared":
			var count := _as_array(event.get("removed_hazards", [])).size() + _as_array(event.get("removed_roadblocks", [])).size() + _as_array(event.get("removed_gods", [])).size()
			return "機器娃娃前進 %d 步 · 清除 %d 個物件" % [int(event.get("steps", 0)), count]
		"bomb_transferred":
			return "定時炸彈轉移至%s · 剩餘 %d 步" % [_player_name(int(event.get("to_player_id", -1))), int(event.get("remaining", 0))]
		"roadblock_hit":
			return "遇到路障，停在%s並移除路障" % _tile_name(int(event.get("tile_id", -1)))
		"game_over":
			if str(event.get("reason", "")) == "company_dividend_no_survivors":
				return "企業分紅結算後已無存活股東，本局結束"
			return "本局結束"
		"turn_started":
			return "回合開始"
		_:
			return event_type

func _event_tile_name(value: Variant) -> String:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return "未知格位"
	var numeric := float(value)
	if not is_finite(numeric) or floor(numeric) != numeric or numeric < 0 or numeric >= _as_array(state.get("board", [])).size():
		return "未知格位"
	return _tile_name(int(value))

func _tile_name(index: int) -> String:
	return str(_tile_for_index(index).get("name", "格位 %02d" % (index + 1)))

func _inventory_item_name(kind: String, item_id: String) -> String:
	var record: Dictionary = InventoryCatalogue.card(item_id) if kind == "card" else InventoryCatalogue.tool(item_id)
	return str(record.get("name", item_id))

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

func _inventory_purchase_price(tile: Dictionary) -> int:
	if game_state != null and game_state.has_method("inventory_purchase_price"):
		return int(game_state.call("inventory_purchase_price", tile))
	if tile.get("kind", "") == "facility":
		return int(tile.get("land_price", 0)) * int(state.get("price_index", 1))
	return int(tile.get("cost", 0))

func _has_original_gods() -> bool:
	return int(state.get("version", 0)) in [6, COMPANY_SAVE_VERSION, STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_gods", false))

func _has_original_inventory() -> bool:
	return int(state.get("version", 0)) in [4, 5, 6, COMPANY_SAVE_VERSION, STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION]

func _has_original_companies() -> bool:
	return int(state.get("version", 0)) in [COMPANY_SAVE_VERSION, STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_companies", false))

func _has_original_hazards() -> bool:
	return int(state.get("version", 0)) in [HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_hazards", false))

func _has_original_property_cards() -> bool:
	return int(state.get("version", 0)) in [PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_property_cards", false))

func _has_original_building_cards() -> bool:
	return int(state.get("version", 0)) == BUILDING_CARD_SAVE_VERSION and bool(state.get("original_building_cards", false))

func _has_original_research() -> bool:
	return int(state.get("version", 0)) in [RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_research", false))

func _has_original_remodel() -> bool:
	return int(state.get("version", 0)) in [REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_remodel", false))

func _has_original_statuses() -> bool:
	return int(state.get("version", 0)) in [STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_statuses", false))

func _player_rest_status(player: Dictionary) -> Dictionary:
	if _has_original_gods() and int(player.get("hospital_days", 0)) > 0:
		return {"kind":"hospital", "count":int(player.hospital_days)}
	if _has_original_statuses() and int(player.get("prison_days", 0)) > 0:
		return {"kind":"prison", "count":int(player.prison_days)}
	return SleepPresentation.status(player) if _has_original_statuses() else {}

func _rest_status_label(rest_status: Dictionary) -> String:
	if rest_status.get("kind", "") in ["winter", "dream"]:
		return SleepPresentation.label(rest_status)
	var title := "住院" if rest_status.get("kind", "") == "hospital" else "服刑"
	var count := int(rest_status.get("count", 0))
	if _has_original_statuses():
		if count == 128: return "待出院" if rest_status.get("kind", "") == "hospital" else "待出獄"
		return "%s · 剩餘 %d 回合" % [title, count]
	return "%s · %d 天" % [title, count]


func _item_implemented(item_kind: String, item_id: String) -> bool:
	if not _has_original_inventory():
		return item_kind == "card"
	return game_state != null and game_state.has_method("item_is_implemented") and bool(game_state.call("item_is_implemented", item_kind, item_id))

func _shop_available() -> bool:
	return game_state != null and game_state.has_method("is_shop_available") and bool(game_state.call("is_shop_available"))

func _on_shop_pressed() -> void:
	if not _is_human_turn() or not _shop_available():
		return
	_update_shop_popup()
	shop_popup.popup_centered(Vector2i(700, 560))
	_settle_inventory_popup(shop_popup, Vector2i(700, 560))

func _update_shop_popup() -> void:
	for child in shop_popup_list.get_children():
		child.free()
	shop_balance_label.text = "持有點券：%d" % int(_current_player().get("points", 0))
	if not _shop_available():
		shop_popup.hide()
		return
	var items: Array = game_state.call("shop_items")
	var previous_kind := ""
	for value in items:
		if not value is Dictionary:
			continue
		var item: Dictionary = value
		var kind := str(item.get("item_kind", ""))
		var item_id := str(item.get("item_id", ""))
		if kind != previous_kind:
			shop_popup_list.add_child(_make_label("卡片" if kind == "card" else "道具", 15, TEXT_GOLD))
			previous_kind = kind
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		var description := str(item.get("name", item_id))
		if not bool(item.get("implemented", false)):
			description += " · 效果尚未還原"
		if int(item.get("equipped", 0)) > 0:
			description += " · 裝備中 %d" % int(item.get("equipped", 0))
		var label := _make_label(description + "\n持有 %d · 庫存 %d" % [int(item.get("owned", 0)), int(item.get("stock", 0))], 11, TEXT_MAIN)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 210
		row.add_child(label)
		var quantity := SpinBox.new()
		quantity.min_value = 1
		quantity.max_value = 9 if kind == "tool" else 1
		quantity.step = 1
		quantity.value = 1
		quantity.custom_minimum_size.x = 62
		quantity.add_theme_font_size_override("font_size", 11)
		row.add_child(quantity)
		var buy := _make_button("", func() -> void:
			_shop_transaction("buy_item", kind, item_id, int(quantity.value))
		)
		buy.name = "Buy_" + item_id
		buy.custom_minimum_size.x = 116
		row.add_child(buy)
		var sell := _make_button("", func() -> void:
			_shop_transaction("sell_item", kind, item_id, int(quantity.value))
		)
		sell.name = "Sell_" + item_id
		sell.custom_minimum_size.x = 116
		row.add_child(sell)
		var update_quote := func(_value: float = 1.0) -> void:
			var count := int(quantity.value)
			var price: int = InventoryRules.quote_buy(kind, item_id, count)
			buy.text = "買入 %d 點" % price
			sell.text = "出售 %d 點" % InventoryRules.quote_sale(kind, item_id, count)
			buy.disabled = not _is_human_turn() or int(_current_player().get("points", 0)) < price or int(item.get("stock", 0)) < count or (kind == "tool" and int(item.get("owned", 0)) + count > 9) or (kind == "card" and _as_array(_current_player().get("cards", [])).size() >= 15)
			sell.disabled = not _is_human_turn() or int(item.get("owned", 0)) < count
		quantity.value_changed.connect(update_quote)
		update_quote.call()
		shop_popup_list.add_child(row)

func _shop_transaction(action: String, item_kind: String, item_id: String, quantity: int) -> void:
	if not _is_human_turn() or not _shop_available():
		return
	var result := _invoke_game("choose_action", [action, {"item_kind": item_kind, "item_id": item_id, "quantity": quantity}])
	_append_local_log(_result_text(result, "已完成點券交易。"))
	_handle_result(result)
	call_deferred("_update_shop_popup")

func _append_tool_inventory() -> void:
	var player := _current_player()
	var vehicle := str(player.get("vehicle", "walking"))
	var vehicle_names := {"walking": "步行", "motorcycle": "機車", "car": "汽車", "engineering": "工程車"}
	var vehicle_dice := {"walking": 1, "motorcycle": 2, "car": 3, "engineering": 1}
	var vehicle_row := HBoxContainer.new()
	var vehicle_label := _make_label("目前交通：%s" % str(vehicle_names.get(vehicle, vehicle)), 12, TEXT_MAIN)
	vehicle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_row.add_child(vehicle_label)
	var dice_option := OptionButton.new()
	dice_option.name = "VehicleDice"
	for count in range(1, int(vehicle_dice.get(vehicle, 1)) + 1):
		dice_option.add_item("%d 顆骰子" % count, count)
	dice_option.select(clampi(int(player.get("dice_count", 1)) - 1, 0, dice_option.item_count - 1))
	dice_option.disabled = str(state.get("phase", "")) != "await_roll" or not state.get("pending_remote_dice", {}).is_empty()
	dice_option.item_selected.connect(func(index: int) -> void:
		var result := _invoke_game("choose_action", ["set_vehicle", {"vehicle": vehicle, "dice_count": dice_option.get_item_id(index)}])
		_handle_result(result)
		call_deferred("_update_cards_popup")
	)
	vehicle_row.add_child(dice_option)
	if vehicle != "walking":
		var walk := _make_button("改為步行", func() -> void:
			var result := _invoke_game("choose_action", ["set_vehicle", {"vehicle": "walking"}])
			_append_local_log(_result_text(result, "已送出交通指令。"))
			_handle_result(result)
			call_deferred("_update_cards_popup")
		)
		walk.name = "UnequipVehicle"
		walk.disabled = dice_option.disabled
		vehicle_row.add_child(walk)
	cards_popup_list.add_child(vehicle_row)
	if vehicle == "engineering":
		var engineering: Dictionary = player.get("engineering_vehicle", {})
		var status := _make_label("工程車：剩餘 %d 回合" % int(engineering.get("remaining_admissions", 0)), 12, TEXT_GOLD)
		status.name = "EngineeringVehicleStatus"
		cards_popup_list.add_child(status)
	cards_popup_list.add_child(_make_label("道具（取得上限每類 9 個）", 15, TEXT_GOLD))
	var tools: Dictionary = _current_player().get("tools", {})
	var has_tools := false
	for record in InventoryCatalogue.tools():
		var item_id := str(record.id)
		var count := int(tools.get(item_id, 0))
		if count <= 0:
			continue
		has_tools = true
		var row := HBoxContainer.new()
		var label := _make_label("%s × %d" % [record.name, count], 12, TEXT_MAIN)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var value_option: OptionButton = null
		if item_id == "遙控骰子":
			value_option = OptionButton.new()
			value_option.name = "RemoteValue"
			for value in range(1, 7):
				value_option.add_item("%d 點" % value, value)
			row.add_child(value_option)
		var tile_option: OptionButton = null
		if ["路障", "機器工人"].has(item_id) or (_has_original_hazards() and item_id in ["地雷", "定時炸彈"]):
			tile_option = _make_inventory_tile_picker(item_id)
			row.add_child(tile_option)
		var use := _make_button("使用", func() -> void:
			var params: Dictionary = {"tool_id": item_id}
			if value_option != null:
				params["value"] = value_option.get_selected_id()
			if tile_option != null:
				params["tile_id"] = tile_option.get_selected_id()
			var result := _invoke_game("choose_action", ["use_tool", params])
			_append_local_log("使用道具 %s：%s" % [item_id, _result_text(result, "已送出道具指令。")])
			_handle_result(result)
			cards_popup.hide()
		)
		use.name = "UseTool_" + item_id
		var implemented := _item_implemented("tool", item_id)
		var tool_phase_allowed := str(state.get("phase", "")) == "await_roll" or (item_id == "工程車" and str(state.get("phase", "")) == "await_action")
		use.disabled = not implemented or not tool_phase_allowed or not _has_action_option(_as_array(state.get("action_options", [])), "use_tool")
		if tile_option != null and tile_option.disabled:
			use.disabled = true
		if (item_id == "機車" and vehicle == "motorcycle") or (item_id == "汽車" and vehicle == "car") or (item_id == "工程車" and vehicle == "engineering"):
			use.disabled = true
			use.text = "使用中"
		if not implemented:
			use.text = "尚未還原"
		row.add_child(use)
		cards_popup_list.add_child(row)
	if not has_tools:
		cards_popup_list.add_child(_make_label("目前沒有道具。", 12, TEXT_MUTED))

func _make_inventory_tile_picker(item_id: String) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = "Target_" + item_id
	picker.custom_minimum_size = Vector2(220, 34)
	picker.add_theme_font_size_override("font_size", 11)
	if item_id in ["換地", "換屋"]:
		var exchanged := "所有權" if item_id == "換地" else "建物"
		picker.tooltip_text = "以腳下的%s與所選地產交換%s。" % [_tile_name(int(_current_player().get("position", -1))), exchanged]
	var candidates: Array = []
	if game_state != null and game_state.has_method("inventory_target_tiles"):
		candidates = _as_array(game_state.call("inventory_target_tiles", item_id))
	var visible: Array = _as_array(board_view.call("visible_node_indices")) if board_view != null and board_view.has_method("visible_node_indices") else []
	var board := _as_array(state.get("board", []))
	var barriers: Dictionary = state.get("roadblocks", {})
	for candidate in candidates:
		var index := int(candidate)
		if index < 0 or index >= board.size() or not visible.has(index):
			continue
		var tile: Dictionary = board[index]
		var label := "%s · 節點 %d" % [str(tile.get("name", "道路")), index + 1]
		if barriers.has(str(index)):
			label = "路障 · " + label
		elif str(tile.get("kind", "")) in ["property", "facility"]:
			label += " · %d 級" % int(tile.get("building_level", 0))
			if _has_original_remodel() and tile.get("kind", "") == "property":
				label += " · " + ("連鎖店" if bool(tile.get("is_chain_store", false)) else "普通住宅")
			if item_id in ["換地", "換屋"]:
				var owner_id := int(tile.get("owner", -1))
				label += " · " + (_player_name(owner_id) if owner_id >= 0 else "無主")
		picker.add_item(label, index)
	if picker.item_count == 0:
		picker.add_item("畫面內沒有可用目標", -1)
		picker.disabled = true
		picker.tooltip_text = "關閉背包後，可縮放或平移地圖，再重新選擇目標。"
	return picker
