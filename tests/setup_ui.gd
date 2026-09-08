extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")

class ClocklessUI extends "res://game/ui/main_ui.gd":
	func _system_start_date() -> Dictionary:
		return {}

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	_test_missing_system_date()
	_test_default_setup_and_four_players(ui)
	await _test_actual_setup(ui)
	_test_duplicate_character_rejection(ui)
	_test_invalid_date_preserves_game(ui)
	_test_legacy_save_display(ui)
	ui.queue_free()
	await create_timer(0.15).timeout
	print("setup UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func _select(option: OptionButton, id: int) -> void:
	for index in range(option.item_count):
		if option.get_item_id(index) == id:
			option.select(index)
			return

func _set_date(ui: Control, year: int, month: int, day: int) -> void:
	ui.start_year_input.value = year
	ui.start_month_input.value = month
	ui.start_day_input.value = day

func _test_default_setup_and_four_players(ui: Control) -> void:
	_expect(int(ui.state.get("version", 0)) == (8 if bool(ui._selected_map_definition.get("supports_original_statuses", false)) else 7 if bool(ui._selected_map_definition.get("supports_original_companies", false)) else 6 if bool(ui._selected_map_definition.get("original_facilities", false)) else 4), "startup save version matches selected map capability")
	_expect(int(ui.state.get("initial_fund", 0)) == 200000, "startup uses the default initial fund")
	_expect(int(ui.state.get("day_limit", -1)) == 0, "startup has no day limit")
	_expect(int(ui.state.get("wealth_multiplier", -1)) == 0, "startup has no wealth target")
	_expect(ui.state.get("start_date", {}) is Dictionary and not ui.state.get("start_date", {}).is_empty(), "startup records the system date")
	_expect(str(ui.setup_summary_label.text).contains("期限不限") and str(ui.setup_summary_label.text).contains("目標不限"), "HUD displays unconstrained setup")
	ui._on_new_game_pressed()
	ui._select_option_id(ui.player_count_option, 4)
	ui._on_player_count_selected(2)
	_expect(ui.character_options.size() == 4, "four-player setup renders four character controls")
	for index in range(4):
		_expect(ui.character_options[index].item_count == 12, "character control %d exposes all twelve characters" % index)
		_expect(ui.character_options[index].get_selected_id() == index, "four-player default character %d is unique" % index)
	ui.new_game_popup.hide()

func _set_standard_setup(ui: Control) -> void:
	ui._on_new_game_pressed()
	ui._select_option_id(ui.player_count_option, 4)
	ui._on_player_count_selected(2)
	ui._select_option_id(ui.initial_fund_option, 100000)
	ui._select_option_id(ui.day_limit_option, 365)
	ui._select_option_id(ui.wealth_multiplier_option, 3)
	_set_date(ui, 2024, 2, 29)
	for index in range(4):
		ui.character_options[index].select([0, 4, 7, 11][index])
	ui.seed_input.text = "101"

func _test_actual_setup(ui: Control) -> void:
	_set_standard_setup(ui)
	ui._on_new_game_confirm()
	await process_frame
	var snapshot: Dictionary = ui.state
	_expect(int(snapshot.get("seed", 0)) == 101, "setup keeps the requested seed")
	_expect(int(snapshot.get("version", 0)) == (8 if bool(ui._selected_map_definition.get("supports_original_statuses", false)) else 7 if bool(ui._selected_map_definition.get("supports_original_companies", false)) else 6 if bool(ui._selected_map_definition.get("original_facilities", false)) else 4), "confirmed setup preserves selected map capability")
	_expect(int(snapshot.get("initial_fund", 0)) == 100000, "confirmed setup stores initial fund")
	_expect(int(snapshot.get("day_limit", 0)) == 365, "confirmed setup stores day limit")
	_expect(int(snapshot.get("wealth_multiplier", 0)) == 3, "confirmed setup stores wealth multiplier")
	_expect(snapshot.get("start_date", {}) == {"year": 2024, "month": 2, "day": 29}, "confirmed setup stores leap-day start date")
	_expect(snapshot.get("character_ids", []) == [0, 4, 7, 11], "confirmed setup stores unique character ids")
	var players: Array = snapshot.get("players", [])
	_expect(players.size() == 4, "confirmed setup keeps four players")
	if players.size() == 4:
		_expect(int(players[0].get("cash", 0)) == 50000 and int(players[0].get("deposit", 0)) == 50000, "human starts with equal cash and deposit")
		_expect(int(players[1].get("character_id", -1)) == 4 and int(players[1].get("cash", 0)) == 40000, "AI uses selected character cash ratio")
	_expect(not ui.new_game_popup.visible, "successful setup closes the popup")
	_expect(str(ui.setup_summary_label.text).contains("2024/02/29") and str(ui.setup_summary_label.text).contains("限365天") and str(ui.setup_summary_label.text).contains("$300,000"), "HUD displays date, limit and wealth target")

func _test_duplicate_character_rejection(ui: Control) -> void:
	var before: Dictionary = ui.state.duplicate(true)
	ui._on_new_game_pressed()
	ui._select_option_id(ui.player_count_option, 4)
	ui._on_player_count_selected(2)
	ui.character_options[0].select(2)
	ui.character_options[1].select(2)
	ui._on_new_game_confirm()
	_expect(ui.state == before, "duplicate characters preserve the current game")
	_expect(ui.new_game_popup.visible, "duplicate character rejection keeps popup open")
	_expect(str(ui.setup_error_label.text).contains("不同角色"), "duplicate character rejection explains the error")
	ui.new_game_popup.hide()

func _test_invalid_date_preserves_game(ui: Control) -> void:
	var before: Dictionary = ui.state.duplicate(true)
	ui._on_new_game_pressed()
	_set_date(ui, 2023, 2, 31)
	ui._on_new_game_confirm()
	_expect(ui.state == before, "invalid calendar date preserves the current game")
	_expect(ui.new_game_popup.visible, "invalid calendar date keeps popup open")
	_expect(str(ui.setup_error_label.text).contains("日期"), "invalid calendar date explains the error")
	ui.new_game_popup.hide()

func _test_legacy_save_display(ui: Control) -> void:
	var legacy = GameState.new_game(77, 2)
	ui.game_state = legacy
	ui._refresh_from_state()
	_expect(int(ui.state.get("version", -1)) == 1, "legacy fixture remains version one")
	_expect(str(ui.setup_summary_label.text).contains("舊版日期"), "legacy save has an explicit legacy date label")
	_expect(not str(ui.setup_summary_label.text).contains("期限不限"), "legacy save does not invent setup constraints")

func _test_missing_system_date() -> void:
	var ui := ClocklessUI.new()
	var options: Dictionary = ui._default_setup_options(4)
	_expect(options.get("start_date", {}) == {"year": 1998, "month": 1, "day": 1}, "missing system date uses supported fallback")
	var game: Object = GameState.new_game(42, 4, options)
	_expect(game != null and int(game.state.get("version", 0)) == 4, "missing clock retains classic inventory setup mode")
	ui.free()
