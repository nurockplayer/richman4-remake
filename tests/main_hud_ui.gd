extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const BaseMap = preload("res://tests/fixtures/original_map_fixture.gd")
const CompanyFixture = preload("res://tests/fixtures/company_fixture.gd")
const StatusFixture = preload("res://tests/fixtures/status_fixture.gd")
const OriginalGods = preload("res://game/content/original_gods.gd")

const SOURCE_HUD_DATA_LEFT := 46.0
const SOURCE_HUD_DATA_RIGHT := 174.0
const SOURCE_HUD_DATA_TOP := 76.0
const SOURCE_HUD_DATA_BOTTOM := 264.0

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _source_assets_available(shell: Control) -> bool:
	return shell.get("_source_title_texture") != null


## True when the control's rect in 640x480 reference-canvas coordinates stays
## inside the frame.  Source turn controls are children of the game screen.
func _inside_reference(control: Control) -> bool:
	if control == null:
		return false
	var origin := Vector2.ZERO
	var node: Node = control
	while node != null and node is Control and str(node.name) != "ReferenceCanvas":
		origin += (node as Control).position
		node = node.get_parent()
	var rect := Rect2(origin, control.size)
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= 640.0 and rect.end.y <= 480.0


func _dialog_fill(shell: Control) -> Color:
	var box: Panel = shell.turn_dialog.get_node_or_null("SourceTurnDialogBox") as Panel
	if box == null:
		return Color()
	var style: StyleBox = box.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		return (style as StyleBoxFlat).bg_color
	return Color()


func _set_human_graph_game(ui: Control) -> Object:
	var normalized: Dictionary = Maps.normalize_map(BaseMap.make())
	_expect(bool(normalized.get("ok", false)), "HUD fixture map normalizes")
	var definition: Dictionary = normalized.get("definition", {})
	ui._set_development_path(true)
	var started: bool = ui._new_game(2301, 2, definition)
	_expect(started, "HUD fixture starts through the existing new-game path")
	var game: Object = ui.game_state
	for player_id in range(2):
		game.set_player_ai(player_id, false)
		game.state.players[player_id].position = 0
		game.state.players[player_id].previous_position = -1
	game.state.current_player = 0
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	return game


func _test_title_and_layout(ui: Control, shell: Control) -> void:
	_expect(shell.is_title_visible(), "normal launch keeps the source title visible")
	_expect(shell.title_screen.visible and not shell.game_screen.visible, "title and board screens are mutually exclusive")
	_expect(shell.reference_canvas.size == Vector2(640.0, 480.0), "source shell owns a 640x480 reference canvas")
	_expect(is_equal_approx(shell.reference_canvas.scale.x, shell.reference_canvas.scale.y), "reference canvas uses uniform scaling")
	_expect(shell.board_host.position == Vector2(0.0, 40.0) and shell.board_host.size == Vector2(440.0, 440.0), "board host matches source crop")
	_expect(shell.hud_panel.position == Vector2(440.0, 0.0) and shell.hud_panel.size == Vector2(200.0, 280.0), "HUD panel matches source bounds")
	_expect(shell.calendar_panel.position == Vector2(440.0, 280.0) and shell.calendar_panel.size == Vector2(200.0, 200.0), "calendar panel matches source bounds")
	var source_keys := ["help", "options", "ai", "load", "save", "map", "inspect", "tools", "cards", "sale", "stocks"]
	for index in range(source_keys.size()):
		var key: String = source_keys[index]
		var button: Button = shell.toolbar_buttons.get(key)
		_expect(button != null and int(button.get_meta("source_chunk", -1)) == index + 1, "toolbar keeps source chunk order for %s" % key)
		_expect(button != null and button.position == Vector2(float(index) * 40.0, 0.0), "toolbar hit area is source aligned for %s" % key)
	if _source_assets_available(shell):
		_expect(shell._title_art.texture != null, "source title composite is loaded")
		_expect(shell._hud_art.texture != null, "source HUD frame is loaded")
		_expect(shell.calendar_panel.background_art != null and shell.calendar_panel.background_art.texture != null, "source calendar frame is loaded for a dated game")
		for key in source_keys:
			_expect(shell.toolbar_buttons[key].icon != null, "source toolbar icon is loaded for %s" % key)
		shell.title_start_button.mouse_entered.emit()
		_expect(shell.title_screen.hover_art.visible, "START hover uses the source hover frame")
		shell.title_start_button.mouse_exited.emit()
		_expect(not shell.title_screen.hover_art.visible, "START hover frame clears on exit")


func _test_title_ai_guard(ui: Control, game: Object, shell: Control) -> void:
	game.state.current_player = 1
	game.state.players[1].is_human = false
	game.state.players[1].is_ai = true
	game.state.phase = "await_roll"
	game._set_action_options(1)
	game._sync_state()
	ui._ai_pending = false
	ui._process(0.0)
	_expect(not ui._ai_pending, "title screen blocks AI scheduling")


func _test_hud_tabs_and_actions(ui: Control, shell: Control, game: Object) -> void:
	game.state.current_player = 0
	game.state.players[0].is_human = true
	game.state.players[0].is_ai = false
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	_expect(not shell.is_title_visible(), "new game enters the source board screen")
	for key in ["tools", "cards", "sale"]:
		var pending_control: Button = shell.toolbar_buttons.get(key) as Button
		_expect(pending_control != null and pending_control.visible and pending_control.disabled, "source %s command stays visibly pending" % key)
	# Issue #151 connects the ordinary AI command to the trustee draft.
	var trustee_control: Button = shell.toolbar_buttons.get("ai") as Button
	_expect(trustee_control != null and trustee_control.visible and not trustee_control.disabled, "source AI command is available on the active board")
	var trustee_before: String = game.to_json()
	trustee_control.pressed.emit()
	_expect(ui.source_trustee_controller.is_open(), "source AI control opens the real trustee host")
	ui.source_trustee_controller.cancel()
	_expect(not ui.source_trustee_controller.is_open() and game.to_json() == trustee_before, "trustee cancellation preserves the live match and RNG")
	var help_control: Button = shell.toolbar_buttons.get("help") as Button
	_expect(help_control != null and help_control.visible and not help_control.disabled, "source help command is available")
	var options_control: Button = shell.toolbar_buttons.get("options") as Button
	_expect(options_control != null and not options_control.disabled, "source options command is available")
	_expect(not shell.title_option_button.disabled, "source title options opens the presenter")
	_expect(shell.turn_dialog.get_parent() == shell.game_screen, "the source event box lives on the board screen")
	_expect(shell.roll_button.get_parent() == shell.game_screen and shell.roll_button.get_parent() != shell.hud_panel, "the GO advance command is a board-context control")
	_expect(shell.buy_button.get_parent() == shell.choice_selector and shell.upgrade_button.get_parent() == shell.choice_selector and shell.end_turn_button.get_parent() == shell.choice_selector, "landing choices share the source YES/NO picker")
	_expect(shell.choice_selector.get_parent() == shell.game_screen, "the YES/NO picker is a separate board control")
	_expect(shell.find_child("SourceActionStrip", true, false) == null, "the board mounts no permanent command strip")
	_expect(not shell.turn_dialog.visible and not shell.choice_selector.visible, "the event box and picker stay hidden on an ordinary await-roll turn")
	_expect(_inside_reference(shell.turn_dialog) and _inside_reference(shell.choice_selector) and _inside_reference(shell.roll_button), "source turn controls stay inside the 640x480 frame")
	for index in range(4):
		var key: String = ["cash", "property", "stock", "other"][index]
		var tab: Button = shell.tab_buttons[key]
		_expect(tab.position == Vector2(176.0, float(index) * 70.0), "HUD tab %s follows the source interval" % key)
		_expect(tab.size == Vector2(24.0, 70.0), "HUD tab %s keeps a distinct source hit area" % key)
		_expect(tab.text == ["資\n金", "地\n產", "股\n票", "其\n他"][index], "HUD tab %s renders both source label characters" % key)
	if _source_assets_available(shell):
		_expect(shell.cash_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "source cash is right aligned beside the source icon")
		_expect(shell.deposit_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and shell.wealth_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "source deposit and wealth are right aligned")
		_expect(shell.cash_label.position == Vector2(66.0, 96.0), "source cash value uses the source value row")
		_expect(shell.cash_label.get_theme_color("font_color").v < 0.35, "source cash value uses dark ink on the pale panel")
		_expect(str(shell.cash_label.text).begins_with("$"), "source cash value keeps visible dollar formatting")
	var before_tabs: String = game.to_json()
	for key in ["property", "stock", "other", "cash"]:
		shell.select_tab(key)
		_expect(shell.active_tab == key, "HUD tab selection updates presentation state for %s" % key)
		_expect(game.to_json() == before_tabs, "HUD tab selection does not mutate simulation for %s" % key)
	shell.set_view_mode(0)
	var before_calendar: String = game.to_json()
	shell.toggle_map_view()
	_expect(shell.minimap.visible and not shell.calendar_panel.visible, "view cycle exposes the minimap")
	_expect(game.to_json() == before_calendar, "view cycle does not mutate simulation")
	shell.toggle_map_view()
	_expect(shell.calendar_panel.visible and shell.minimap.visible, "second cycle exposes combined calendar and minimap")
	shell.toggle_map_view()
	_expect(shell.calendar_panel.visible and not shell.minimap.visible, "third cycle returns to the dated panel")
	_expect(not shell.buy_button.visible and not shell.upgrade_button.visible and not shell.end_turn_button.visible, "non-landing source turn hides unrelated actions")
	_expect(shell.roll_button.visible and shell.roll_button.text == "GO", "await-roll source turn exposes the bounded GO control")
	_expect(not shell.turn_dialog.visible and not shell.choice_selector.visible, "await-roll turn shows no decision dialog")
	game.state.phase = "await_action"
	game.state.action_options = ["buy", "end_turn"]
	game._sync_state()
	ui._refresh_from_state()
	_expect(not shell.roll_button.visible and shell.buy_button.visible and shell.buy_button.text == "YES", "landing source turn exposes only the purchase YES control")
	_expect(shell.end_turn_button.visible and shell.end_turn_button.text == "NO", "landing source turn exposes the decline NO control")
	_expect(not shell.upgrade_button.visible, "landing source turn hides the unrelated upgrade control")
	_expect(shell.turn_dialog.visible and shell.choice_selector.visible, "landing source turn opens the event box and picker")
	_expect(shell.turn_dialog.get_node_or_null("SourceTurnDialogBox") != null, "the event box keeps its framed dialog body")
	_expect(_dialog_fill(shell) == Color("#4a3524"), "the event box uses the source brown prompt framing")
	_expect(_inside_reference(shell.turn_dialog) and _inside_reference(shell.choice_selector) and _inside_reference(shell.buy_button) and _inside_reference(shell.end_turn_button), "landing controls stay inside the 640x480 frame")
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()


func _test_source_purchase_offer(ui: Control, shell: Control, game: Object) -> void:
	game.state.current_player = 0
	game.state.players[0].position = 2
	game.state.players[0].previous_position = 0
	game.state.players[0].cash = 2000
	game.state.property_action_used = false
	game.state.phase = "await_action"
	game._set_action_options(0)
	game._sync_state()
	var before_purchase_refresh: String = game.to_json()
	ui._refresh_from_state()
	var purchase_hint := str(shell.action_hint_label.text)
	_expect(purchase_hint.contains("測試路"), "source landing purchase offer names the current property")
	_expect(purchase_hint.contains("$1,000"), "source landing purchase offer uses the authoritative property price")
	_expect(purchase_hint.contains("YES") and purchase_hint.contains("NO"), "source landing purchase offer exposes confirm and decline controls")
	_expect(str(shell.dialog_text.text) == purchase_hint, "the source event box carries the landing offer text")
	_expect(game.to_json() == before_purchase_refresh, "source landing purchase refresh does not mutate simulation state")

	game.state.board[2].owner = 0
	game.state.players[0].properties = [2]
	game.state.players[0].cash = 500
	game.state.property_action_used = false
	game._set_action_options(0)
	game._sync_state()
	var before_upgrade_refresh: String = game.to_json()
	ui._refresh_from_state()
	var upgrade_hint := str(shell.action_hint_label.text)
	_expect(upgrade_hint.contains("升級"), "source owned-property offer names the upgrade action")
	_expect(upgrade_hint.contains("$300"), "source owned-property offer uses the authoritative upgrade price")
	_expect(upgrade_hint.contains("YES") and upgrade_hint.contains("NO"), "source owned-property offer exposes confirm and decline controls")
	_expect(game.to_json() == before_upgrade_refresh, "source owned-property refresh does not mutate simulation state")
	game.state.phase = "await_roll"
	game.state.players[0].position = 0
	game.state.players[0].previous_position = -1
	game.state.board[2].owner = -1
	game.state.players[0].properties = []
	game.state.players[0].cash = 100000
	game.state.property_action_used = false
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()


## Issue #101: the ordinary player view keeps no permanent hint/log scaffold,
## and every turn action stays reachable through the source GO command, event
## box and YES/NO picker.  Dev mode keeps the raw hint line.
func _test_source_turn_controls_normal_mode(ui: Control, shell: Control, game: Object) -> void:
	ui._set_development_path(false)
	game.state.current_player = 0
	game.state.players[0].is_human = true
	game.state.players[0].is_ai = false
	game.state.players[0].position = 0
	game.state.players[0].previous_position = -1
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	_expect(not shell.action_hint_label.visible, "normal mode hides the raw turn hint/log line")
	_expect(not shell.turn_dialog.visible and not shell.choice_selector.visible, "normal mode mounts no permanent command strip")
	_expect(shell.roll_button.visible and not shell.roll_button.disabled, "normal mode exposes the GO advance command")
	_expect(shell.roll_button.text == "GO", "the ordinary advance command keeps the source GO label")
	var go_style: StyleBox = shell.roll_button.get_theme_stylebox("normal")
	_expect(go_style is StyleBoxFlat and (go_style as StyleBoxFlat).bg_color == Color("#4a3524"), "the GO command uses the source brown/gold framing instead of navy")
	# The full-map view hides GO, so the keyboard must not roll from under it.
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	var before_map_enter: String = game.to_json()
	shell.toggle_full_map_view()
	_expect(not shell.roll_button.visible, "the full-map view hides the GO advance command")
	ui._unhandled_input(enter)
	_expect(ui.get("_presentation_busy") == false and game.to_json() == before_map_enter, "ENTER stays inert while the full-map view hides GO")
	shell.toggle_full_map_view()
	_expect(shell.roll_button.visible, "closing the full-map view restores the GO advance command")
	# Manual p.7: ENTER is the source confirm key, so it advances like SPACE.
	ui._unhandled_input(enter)
	_expect(ui.get("_presentation_busy") == true, "ENTER confirms the pending advance command")
	var board: Node = ui.board_view
	if board.has_method("_advance_movement"):
		board._advance_movement(100.0)
	_expect(ui.get("_presentation_busy") == false, "the source advance finishes its movement presentation")

	# A landing purchase is answered from the separate source YES/NO picker.
	game.state.current_player = 0
	game.state.players[0].position = 2
	game.state.players[0].previous_position = 0
	game.state.players[0].cash = 5000
	game.state.board[2].owner = -1
	game.state.players[0].properties = []
	game.state.property_action_used = false
	game.state.phase = "await_action"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	_expect(shell.turn_dialog.visible and shell.choice_selector.visible, "a landing purchase opens the event box and picker")
	_expect(str(shell.dialog_text.text).contains("測試路"), "the event box names the offered property")
	_expect(shell.buy_button.visible and shell.buy_button.text == "YES", "the picker offers the source YES tile")
	_expect(shell.end_turn_button.visible and shell.end_turn_button.text == "NO", "the picker offers the source NO tile")
	_expect(_inside_reference(shell.buy_button) and _inside_reference(shell.end_turn_button) and _inside_reference(shell.dialog_text), "the picker and event box stay inside the 640x480 frame")
	var cash_before := int(game.state.players[0].cash)
	shell.buy_button.pressed.emit()
	_expect(int(game.state.board[2].owner) == 0, "the picker YES tile completes the purchase")
	_expect(int(game.state.players[0].cash) == cash_before - 1000, "the picker YES tile charges the authoritative price")

	# The owned landing offers its upgrade through the same YES tile.
	game.state.players[0].cash = 5000
	game.state.property_action_used = false
	game.state.phase = "await_action"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	_expect(shell.upgrade_button.visible and shell.upgrade_button.text == "YES" and not shell.buy_button.visible, "an owned landing offers only the upgrade YES tile")
	var level_before := int(game.state.board[2].building_level)
	shell.upgrade_button.pressed.emit()
	_expect(int(game.state.board[2].building_level) > level_before, "the picker YES tile completes the upgrade")

	# The NO tile declines and hands the turn over.
	game.state.players[0].position = 2
	game.state.players[0].previous_position = 0
	game.state.players[0].cash = 5000
	game.state.board[2].owner = -1
	game.state.players[0].properties = []
	game.state.property_action_used = false
	game.state.phase = "await_action"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	_expect(shell.end_turn_button.visible and shell.end_turn_button.text == "NO", "the landing keeps the NO tile reachable")
	shell.end_turn_button.pressed.emit()
	_expect(int(game.state.current_player) == 1, "the picker NO tile declines and ends the turn")
	_expect(int(game.state.board[2].owner) == -1, "the declined landing leaves the property unowned")

	# The same GO command carries the jail continuation and its own wording.
	shell.sync_action_state("服刑", false, "", true, "", true, true, "服刑，按服刑推進回合", [], "await_roll", [])
	_expect(shell.roll_button.visible and shell.roll_button.text == "服刑", "the GO command carries the jail continuation")

	# A turn that only offers the decline action keeps the NO tile but shows no
	# permanent board message.
	shell.sync_action_state("擲骰", true, "購買地產", true, "升級", true, false, "請處理目前格位", [], "await_action", ["end_turn"])
	_expect(shell.choice_selector.visible and shell.end_turn_button.visible, "a decline-only turn keeps the NO tile reachable")
	_expect(not shell.turn_dialog.visible, "a decline-only turn shows no permanent board message")
	_expect(not shell.action_hint_label.visible, "the generic turn hint stays out of the normal player view")

	# Dev mode keeps the raw hint/log line for the developer.
	ui._set_development_path(true)
	game.state.current_player = 0
	game.state.players[0].position = 0
	game.state.players[0].previous_position = -1
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	_expect(shell.action_hint_label.visible, "dev mode keeps the raw turn hint line")
	_expect(str(shell.action_hint_label.text).contains("擲骰"), "dev mode keeps the raw hint copy")


## Release builds have no hint/log row, so a rejected action and a waiting turn
## answer on the board status line instead of being silent.
func _test_release_feedback_states(ui: Control, shell: Control) -> void:
	ui._set_development_path(false)
	ui._refresh_from_state()
	var game: Object = ui.game_state
	_expect(not shell.action_hint_label.visible, "the release lane keeps the dev hint row hidden")
	ui._presentation_busy = true
	var rejected: Dictionary = ui._invoke_game("roll")
	ui._presentation_busy = false
	_expect(str(rejected.get("message", "")) == "角色移動中。", "the movement gate rejects the action with its reason")
	_expect(shell.status_toast.visible and str(shell.status_toast_text.text) == "角色移動中。", "a rejected action shows its reason on the board")
	_expect(shell.status_toast.mouse_filter == Control.MOUSE_FILTER_IGNORE and _inside_reference(shell.status_toast), "the status toast is a passive overlay inside the 640x480 frame")
	shell.advance_status_toast(2.5)
	_expect(not shell.status_toast.visible, "the rejection toast hides after its short interval")

	# An AI turn explains the pause.
	game.state.current_player = 1
	game.state.players[1].is_human = false
	game.state.players[1].is_ai = true
	game.state.phase = "await_roll"
	game._set_action_options(1)
	game._sync_state()
	ui._refresh_from_state()
	_expect(shell.status_toast.visible and str(shell.status_toast_text.text).contains("思考中"), "an AI turn shows its waiting text in release builds")
	# A finance key that exists but holds nothing is not an active response and
	# must not mask the AI waiting text.
	ui.state["pending_finance"] = {}
	ui._sync_waiting_status()
	_expect(shell.status_toast.visible and str(shell.status_toast_text.text).contains("思考中"), "an empty pending finance entry does not mask the AI waiting text")
	ui.state.erase("pending_finance")
	ui._sync_waiting_status()
	_expect(shell.status_toast.visible and str(shell.status_toast_text.text).contains("思考中"), "clearing the finance entry restores the ordinary AI waiting text")

	# A turn with nothing but 結束 explains the lone control.
	game.state.current_player = 0
	game.state.players[0].is_human = true
	game.state.players[0].is_ai = false
	game.state.players[0].position = 0
	game.state.players[0].previous_position = -1
	game.state.phase = "await_action"
	game.state.action_options = ["end_turn"]
	game.state.last_roll = []
	game._sync_state()
	ui._refresh_from_state()
	_expect(shell.end_turn_button.visible and shell.end_turn_button.text == "結束", "the rest turn keeps its lone 結束 control")
	_expect(shell.status_toast.visible and str(shell.status_toast_text.text) == "本回合休息，請結束回合", "the board explains what the lone 結束 control is for")

	# A pending daily checkpoint is a short wait with its own text.
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	ui._source_autosave.capture_transition(game, {"day": 1}, {"day": 2, "phase": "await_roll"}, true)
	_expect(ui._source_autosave.pending(), "the daily checkpoint fixture is pending")
	ui._sync_waiting_status()
	_expect(shell.status_toast.visible and str(shell.status_toast_text.text) == "每日自動存檔中…", "a pending daily checkpoint explains the wait")
	ui._source_autosave.skip()
	ui._sync_waiting_status()
	_expect(not shell.status_toast.visible, "the checkpoint status clears with the pending checkpoint")

	# A rejection returned by the simulation core (not a UI gate) answers too.
	var core_rejection: Dictionary = ui._invoke_game("choose_route", [3])
	_expect(not bool(core_rejection.get("ok", true)) and not str(core_rejection.get("message", "")).is_empty(), "the simulation core rejects a route outside its phase")
	_expect(shell.status_toast.visible and str(shell.status_toast_text.text) == str(core_rejection.get("message", "")), "a simulation-level rejection shows the same board toast")
	shell.advance_status_toast(2.5)

	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	_expect(not shell.status_toast.visible, "an ordinary human turn keeps the board free of status text")

	# ENTER outside a route decision still confirms the GO advance command.
	var go_enter := InputEventKey.new()
	go_enter.keycode = KEY_ENTER
	go_enter.pressed = true
	var before_go: String = game.to_json()
	ui._unhandled_input(go_enter)
	_expect(game.to_json() != before_go, "ENTER keeps confirming GO when no route decision owns the turn")
	var board: Node = ui.board_view
	if board.has_method("_advance_movement"):
		board._advance_movement(100.0)
	_expect(ui.get("_presentation_busy") == false, "the ENTER advance finishes its movement presentation")
	ui._set_development_path(true)


## Keyboard route selection and the reaction gate around the source YES tiles.
func _test_route_keyboard_and_reaction_gate(ui: Control, shell: Control) -> void:
	var normalized: Dictionary = Maps.normalize_map(BaseMap.make())
	var definition: Dictionary = normalized.get("definition", {})
	_expect(ui._new_game(2302, 2, definition), "route keyboard fixture starts through the public new-game path")
	var game: Object = ui.game_state
	for player_id in range(2):
		game.set_player_ai(player_id, false)
		game.state.players[player_id].is_human = true
		game.state.players[player_id].is_ai = false
	game.state.current_player = 0
	game.state.players[0].position = 1
	game.state.players[0].previous_position = 0
	game.state.phase = "await_route"
	game.state.pending_movement = {"player_id": 0, "current_node": 1, "previous_node": 0}
	game.state.route_options = [2, 3]
	game.state.remaining_steps = 1
	game.state.last_total = 1
	game._sync_state()
	ui._refresh_from_state()
	await process_frame
	await process_frame
	_expect(shell.route_buttons.visible and shell.route_buttons.get_child_count() == 2, "the route decision exposes both destinations")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	# The old ENTER→GO habit must never commit an unseen destination at a fork.
	ui._input(enter)
	_expect(int(game.state.players[0].position) == 1 and str(game.state.phase) == "await_route", "ENTER without a selected destination never commits a route")
	# Route controls whose parent is hidden (a title or menu screen) stay inert.
	shell.game_screen.hide()
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	ui._input(right)
	ui._input(enter)
	_expect(int(game.state.players[0].position) == 1 and str(game.state.phase) == "await_route", "route controls under a hidden parent ignore keyboard input")
	shell.game_screen.show()
	_expect(shell.route_buttons.is_visible_in_tree(), "showing the board restores the route controls")
	ui._input(right)
	_expect(ui.get_viewport().gui_get_focus_owner() == shell.route_buttons.get_child(0), "RIGHT selects the first route destination")
	ui._input(right)
	_expect(ui.get_viewport().gui_get_focus_owner() == shell.route_buttons.get_child(1), "RIGHT moves the selection to the next destination")
	var number := InputEventKey.new()
	number.keycode = KEY_1
	number.pressed = true
	ui._input(number)
	_expect(ui.get_viewport().gui_get_focus_owner() == shell.route_buttons.get_child(0), "a number key selects the matching destination")
	ui._input(right)
	ui._input(enter)
	_expect(int(game.state.players[0].position) == 3, "ENTER confirms the keyboard-selected route")
	var board: Node = ui.board_view
	if board.has_method("_advance_movement"):
		board._advance_movement(100.0)
	_expect(ui.get("_presentation_busy") == false, "the keyboard route resolves through the ordinary presentation")

	# A pending response card owns the turn: the visible YES tiles stay inert.
	var status_definition: Dictionary = StatusFixture.definition()
	_expect(ui._new_game(2303, 4, status_definition, ui._default_setup_options(4, status_definition)), "reaction fixture starts through the public new-game path")
	game = ui.game_state
	for player_id in range(4):
		game.state.players[player_id].is_human = player_id == 0
		game.state.players[player_id].is_ai = player_id != 0
	game.state.current_player = 0
	game.state.phase = "await_action"
	game.state.action_options = ["buy", "end_turn"]
	game.state.pending_trap = {"caster_id": 1, "target_id": 0}
	game._sync_state()
	ui._set_development_path(false)
	ui._refresh_from_state()
	_expect(ui._human_trap_response_pending(), "the reaction fixture targets the human player")
	_expect(shell.status_toast.visible and str(shell.status_toast_text.text).contains("嫁禍卡"), "the release board shows the pending reaction text")
	_expect(shell.buy_button.visible and shell.buy_button.disabled, "the purchase YES tile stays disabled while a reaction is pending")
	_expect(shell.end_turn_button.visible, "the turn keeps another control reachable while the reaction is pending")

	# Leave an ordinary turn for the remaining HUD checks.
	game.state.pending_trap = {}
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	_expect(not shell.status_toast.visible, "the landing status clears once the response is resolved")


func _test_source_hud_detail_values(ui: Control, shell: Control, game: Object) -> void:
	var before: String = game.to_json()
	var snapshot: Dictionary = game.get_snapshot().duplicate(true)
	var player: Dictionary = snapshot.players[0]
	player.properties = [2, 3]
	player.stocks = {"s01": 3}
	player.god_id = 1
	player.hospital_days = 2
	player.insurance_status = 3
	player.alliance = {"partner_id": 1, "turns": 4}
	snapshot.board[2].name = "東區大街"
	snapshot.board[2].building_level = 2
	snapshot.board[3].name = "西區大街"
	snapshot.board[3].building_level = 1
	snapshot.god_objects = [{"id": 1, "owner": 0, "days": 5}]
	snapshot.market = {"rows": {"s01": {"name": "來源企業", "price": 123.45}}}
	shell.sync_snapshot(snapshot, {}, 9999)
	shell.select_tab("property")
	_expect(shell.property_label.text.contains("東區大街 Lv2"), "source property HUD lists the first property name and level")
	_expect(shell.property_label.text.contains("西區大街 Lv1"), "source property HUD lists the second property name and level")
	shell.select_tab("stock")
	_expect(shell.stock_label.text.contains("來源企業 × 3"), "source stock HUD lists the display name and holding")
	_expect(shell.stock_label.text.contains("$123.45"), "source stock HUD lists the authoritative current price")
	shell.select_tab("other")
	_expect(shell.other_label.text.contains(OriginalGods.name_for(1)), "source other HUD lists the attached god")
	_expect(shell.other_label.text.contains("5 天"), "source other HUD lists the attached god duration")
	_expect(shell.other_label.text.contains("住院 · 2 天"), "source other HUD lists the active status duration")
	_expect(shell.other_label.text.contains("保險 · 3 天"), "source other HUD lists an active insurance duration")
	_expect(shell.other_label.text.contains("同盟 · 剩餘 4 回合"), "source other HUD lists an active alliance duration")
	player.hospital_days = 0
	player.winter_sleep_days = 128
	player.insurance_status = 128
	player.alliance = {"partner_id": 1, "turns": 128}
	shell.sync_snapshot(snapshot, {}, 9999)
	shell.select_tab("other")
	_expect(shell.other_label.text.contains("待醒來"), "source other HUD uses sleep presentation copy for the 128 sentinel")
	_expect(shell.other_label.text.contains("保險 · 到期當日仍有效"), "source other HUD explains the insurance 128 sentinel")
	_expect(shell.other_label.text.contains("同盟 · 下回合到期"), "source other HUD explains the alliance 128 sentinel")
	var sentinel_inspector: String = str(shell._player_inspection_text(0))
	_expect(sentinel_inspector.contains("待醒來") and sentinel_inspector.contains("保險 · 到期當日仍有效") and sentinel_inspector.contains("同盟 · 下回合到期"), "player inspector shares the sentinel status presentation")
	_test_source_hud_data_geometry(shell)
	_expect(game.to_json() == before, "source HUD detail rendering leaves the live game object untouched")
	ui._refresh_from_state()


func _test_source_hud_data_geometry(shell: Control) -> void:
	var labels := {
		"property": shell.property_label,
		"stock": shell.stock_label,
		"other": shell.other_label,
	}
	for key in labels:
		shell.select_tab(str(key))
		var label: Label = labels[key]
		var rect := Rect2(label.position, label.size)
		var source_safe := rect.position.x >= SOURCE_HUD_DATA_LEFT and rect.position.x + rect.size.x <= SOURCE_HUD_DATA_RIGHT and rect.position.y >= SOURCE_HUD_DATA_TOP and rect.position.y + rect.size.y <= SOURCE_HUD_DATA_BOTTOM and not label.clip_text
		_expect(label.visible and source_safe and not str(label.text).is_empty(), "source %s data label stays inside the icon-free readable area without clipping" % key)


func _test_source_full_map_and_player_inspect(ui: Control, shell: Control, game: Object) -> void:
	var before_map: String = game.to_json()
	var map_button: Button = shell.toolbar_buttons.get("map") as Button
	var view_mode_before: int = shell.view_mode
	var calendar_visible: bool = shell.calendar_panel.visible
	var minimap_visible: bool = shell.minimap.visible
	map_button.pressed.emit()
	await process_frame
	_expect(shell.is_full_map_visible(), "source map command opens the full-map view")
	_expect(shell.full_map_view.visible and shell.full_map_view.size == Vector2(440.0, 440.0), "full-map view occupies the source board region")
	_expect(shell.view_mode == view_mode_before and shell.calendar_panel.visible == calendar_visible and shell.minimap.visible == minimap_visible, "full-map command does not reduce to the calendar view cycle")
	var full_map_points: Array = shell.full_map_view.call("_board_points")
	_expect(full_map_points.size() == game.state.board.size(), "full-map view projects every board node")
	_expect(game.to_json() == before_map, "full-map command does not mutate simulation state")
	map_button.pressed.emit()
	await process_frame
	_expect(not shell.is_full_map_visible() and not shell.full_map_view.visible, "source map command closes the full-map view")

	var before_inspect: String = game.to_json()
	var inspect_button: Button = shell.toolbar_buttons.get("inspect") as Button
	inspect_button.pressed.emit()
	await process_frame
	_expect(shell.is_player_inspector_visible(), "source inspect command opens the player inspector")
	_expect(shell.player_inspect_buttons.get_child_count() == game.state.players.size(), "player inspector exposes every player from the snapshot")
	_expect(shell.player_inspect_detail.text.contains(str(game.state.players[0].name)), "player inspector starts on the current player")
	var other_button: Button = shell.player_inspect_buttons.get_child(1) as Button if shell.player_inspect_buttons.get_child_count() > 1 else null
	if other_button != null:
		other_button.pressed.emit()
		_expect(shell.player_inspect_detail.text.contains(str(game.state.players[1].name)), "player inspector selects another player from the existing snapshot")
	_expect(game.to_json() == before_inspect, "player inspection and selection do not mutate simulation state")
	_expect(ui._source_modal_open(), "player inspector blocks simulation shortcuts while open")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	ui._unhandled_input(space)
	_expect(game.to_json() == before_inspect, "player inspector blocks a queued roll shortcut")
	shell.close_player_inspector()
	await process_frame
	_expect(not shell.is_player_inspector_visible(), "player inspector closes through its presentation API")


func _test_settlement_overlay_input(ui: Control, shell: Control) -> void:
	var game: Object = ui.game_state
	if game == null:
		_expect(false, "settlement overlay has a live game fixture")
		return
	game.state.phase = "game_over"
	game.state.winner = 0
	game._sync_state()
	var before: String = game.to_json()
	ui._refresh_from_state()
	await process_frame
	var close: Button = ui.end_overlay.find_child("SettlementClose", true, false) as Button
	var restart: Button = ui.end_overlay.find_child("SettlementRestart", true, false) as Button
	_expect(ui.end_overlay.visible and ui.end_overlay.z_index > shell.z_index and ui.end_overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "settlement overlay renders above and captures input over the source shell")
	_expect(close != null and close.visible and not close.disabled, "settlement overlay exposes a usable return control")
	_expect(restart != null and restart.visible and not restart.disabled, "settlement overlay exposes a usable restart control")
	if close != null:
		close.pressed.emit()
		await process_frame
	_expect(not ui.end_overlay.visible, "settlement return control receives input above the source shell")
	_expect(game.to_json() == before, "settlement return control does not mutate simulation state")


func _test_stock_names(shell: Control) -> void:
	var stock_snapshot := {
		"current_player": 0,
		"date": {"year": 1998, "month": 6, "day": 2},
		"players": [{"name": "玩家", "cash": 100, "deposit": 200, "stocks": {"s01": 3}, "properties": [], "property_values": 0, "cards": [], "tools": {}, "points": 0}],
		"market": {"rows": {"s01": {"name": "來源企業"}}},
	}
	shell.sync_snapshot(stock_snapshot, {}, 300)
	shell.select_tab("stock")
	_expect(str(shell.stock_label.text).contains("來源企業"), "stock HUD uses the source display name")


func _test_minimap_input(ui: Control, shell: Control, game: Object) -> void:
	var before_state: String = game.to_json()
	shell.set_view_mode(1)
	var view: Control = shell.board_host.get_child(0)
	var points: Array[Vector2] = shell.minimap.call("_board_points")
	var target_index: int = mini(2, points.size() - 1)
	var before_pan: Vector2 = view.map_pan if view.get("map_pan") is Vector2 else Vector2.ZERO
	var before_refresh := int(shell.minimap.get("_refresh_serial"))
	var before_polygon: Array = shell.minimap.call("_viewport_polygon")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = points[target_index] if target_index >= 0 else Vector2(100.0, 100.0)
	shell.minimap._gui_input(click)
	click.pressed = false
	shell.minimap._gui_input(click)
	_expect(game.to_json() == before_state, "minimap click does not mutate simulation")
	_expect(int(shell.minimap.get("_refresh_serial")) > before_refresh, "camera-only minimap selection requests a viewport redraw")
	var after_polygon: Array = shell.minimap.call("_viewport_polygon")
	_expect(after_polygon != before_polygon, "minimap viewport outline follows the changed board camera")
	if view.has_method("pan_by"):
		_expect(view.map_pan != before_pan, "minimap click pans the board view")
	if target_index >= 0 and view.has_method("get_screen_position_for_index"):
		var focused_position: Vector2 = view.call("get_screen_position_for_index", target_index)
		_expect(focused_position.distance_to(view.size * 0.5) < 1.5, "minimap node selection centers the board camera once")
	shell.set_view_mode(0)


func _test_calendar_minimap_viewport_input(viewport_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var ui: Control = MainScene.instantiate()
	viewport.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var game: Object = _set_human_graph_game(ui)
	await process_frame
	await process_frame
	var shell: Control = ui.source_shell
	shell.set_view_mode(0)
	var before_state: String = game.to_json()
	var board_view: Control = shell.board_host.get_child(0)
	var before_pan: Vector2 = board_view.map_pan if board_view.get("map_pan") is Vector2 else Vector2.ZERO
	var minimap_selections: Array[int] = []
	shell.minimap.node_selected.connect(func(index: int) -> void: minimap_selections.append(index))
	_expect(shell.calendar_panel.visible and not shell.minimap.visible, "calendar starts visible in %s viewport" % viewport_size)
	for round_trip in range(2):
		await _push_viewport_key(viewport, KEY_TAB)
		_expect(shell.minimap.visible and not shell.calendar_panel.visible, "view hotkey opens minimap on %s round %d" % [viewport_size, round_trip + 1])
		await _push_viewport_key(viewport, KEY_TAB)
		_expect(shell.calendar_panel.visible and shell.minimap.visible, "view hotkey opens the combined group on %s round %d" % [viewport_size, round_trip + 1])
		await _push_viewport_key(viewport, KEY_TAB)
		_expect(shell.calendar_panel.visible and not shell.minimap.visible, "view hotkey returns to the calendar on %s round %d" % [viewport_size, round_trip + 1])
	_expect(minimap_selections.is_empty(), "view hotkey does not reach minimap on %s" % viewport_size)
	_expect(board_view.get("map_pan") == before_pan, "view hotkey does not pan the board on %s" % viewport_size)
	_expect(game.to_json() == before_state, "calendar/minimap round trips preserve simulation on %s" % viewport_size)
	viewport.queue_free()
	await process_frame


func _push_viewport_key(viewport: SubViewport, keycode: int) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	viewport.push_input(key, true)
	await process_frame


func _push_viewport_click(viewport: SubViewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.position = point
		button.global_position = point
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		viewport.push_input(button, true)
		await process_frame


func _test_source_roll_presentation_gate(ui: Control, shell: Control) -> void:
	# Route buttons are built into an HBoxContainer whose sorting is deferred, so
	# the frame checks below wait for a layout pass before measuring bounds.
	var normalized: Dictionary = Maps.normalize_map(BaseMap.make())
	var definition: Dictionary = normalized.get("definition", {})
	var started: bool = ui._new_game(1, 2, definition)
	_expect(started, "source roll fixture starts through the public new-game path")
	ui.set_process(false)
	ui.board_view.set_process(false)
	var game: Object = ui.game_state
	for player_id in range(2):
		game.set_player_ai(player_id, false)
		game.state.players[player_id].position = 0
		game.state.players[player_id].previous_position = -1
	game.state.current_player = 0
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	var source_load: Button = shell.toolbar_buttons.get("load") as Button
	_expect(shell.roll_button.visible and not shell.roll_button.disabled, "visible source roll is enabled before the turn")
	_expect(source_load != null and not source_load.disabled, "visible source load is enabled before movement")
	_expect(not shell.title_load_button.disabled, "source title load follows the open load gate")
	shell.roll_button.pressed.emit()
	_expect(ui.get("_presentation_busy") == true, "source roll starts the movement presentation")
	_expect(shell.roll_button.visible and not shell.turn_dialog.visible, "source GO remains the active movement gate without a decision dialog")
	_expect(shell.roll_button.visible and shell.roll_button.disabled, "visible source roll is disabled during movement")
	_expect(source_load != null and source_load.disabled, "visible source load is disabled during movement")
	_expect(ui.load_button.disabled, "legacy load adapter shares the movement gate")
	_expect(shell.title_load_button.disabled, "source title load shares the movement gate")
	var board: Node = ui.board_view
	if board.has_method("_advance_movement"):
		board._advance_movement(100.0)
	_expect(ui.get("_presentation_busy") == false, "source movement finish clears the presentation lock")
	_expect(source_load != null and not source_load.disabled, "visible source load re-enables after movement")
	_expect(not shell.roll_button.visible, "source GO hides once the turn awaits a route")
	_expect(shell.route_buttons.visible and shell.route_buttons.get_child_count() > 0, "visible source route choices appear after movement")
	await process_frame
	await process_frame
	if shell.route_buttons.get_child_count() > 0:
		var route: Button = shell.route_buttons.get_child(0) as Button
		_expect(route.visible and not route.disabled, "visible source route choice is enabled after movement")
		_expect(route.size.x > 0.0, "the route fallback takes layout space before its bounds are checked")
		_expect(route != null and route.text.begins_with("前往 ") and not route.text.contains("→"), "visible source route choice uses a player-facing destination label")
		_expect(_inside_reference(route), "the source route fallback stays inside the 640x480 frame")
	_expect(shell.turn_dialog.visible, "the route phase explains itself in the source event box")
	var duplicate_route_labels: Array = shell.callv("_route_destination_labels", [[2, 3]])
	_expect(duplicate_route_labels.size() == 2 and duplicate_route_labels[0] != duplicate_route_labels[1], "concurrent same-name source route choices remain distinguishable")
	var ordinary_route_labels: Array = shell.callv("_route_destination_labels", [[2]])
	_expect(ordinary_route_labels == ["前往 測試路"], "ordinary source route labels keep their concise destination copy")
	for label_value in duplicate_route_labels:
		var label := str(label_value)
		_expect(label.begins_with("前往 ") and not label.contains("→") and not label.contains("%02d"), "same-name route distinction uses player-facing source cues")
	var near_axis_snapshot := {
		"current_player": 0,
		"players": [{"position": 0}],
		"board": [
			{"x": 1027, "y": 1115, "name": "分岔"},
			{"x": 1031, "y": 1209, "name": "點數 10"},
			{"x": 1102, "y": 1117, "name": "點數 10"},
		],
	}
	shell.sync_snapshot(near_axis_snapshot)
	var near_axis_labels: Array = shell.callv("_route_destination_labels", [[1, 2]])
	_expect(near_axis_labels == ["前往 點數 10（下方）", "前往 點數 10（右方）"], "source near-axis route vectors use their dominant cardinal direction")


func _test_source_stock_modal_gate(ui: Control, shell: Control) -> void:
	var definition: Dictionary = CompanyFixture.definition()
	var started: bool = ui._new_game(90101, 4, definition)
	_expect(started, "source stock fixture starts through the public new-game path")
	ui.set_process(false)
	ui.board_view.set_process(false)
	var game: Object = ui.game_state
	game.state.current_player = 0
	game.state.phase = "await_action"
	game.state.players[0].is_human = true
	game.state.players[0].is_ai = false
	game.state.players[0].deposit = 1000
	game.state.players[0].stocks["s01"] = 0
	# The stock interaction contract requires a normal market day.  New-game
	# setup follows the host calendar, which can be Sunday when this test runs.
	# Keep the save-derived calendar coherent so _sync_state() preserves it.
	game.state["start_date"] = {"year": 1998, "month": 6, "day": 1}
	game._sync_state()
	var market: Dictionary = game.state.get("market", {}).duplicate(true)
	market["open"] = true
	market["closed_days"] = 0
	var rows: Dictionary = market.get("rows", {})
	var row: Dictionary = rows.get("s01", {})
	row.price = 100.0
	row.previous_price = 100.0
	row.turn_supply = 20
	row.market_supply = 5000
	rows["s01"] = row
	market["rows"] = rows
	game.state["market"] = market
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	var source_stocks: Button = shell.toolbar_buttons.get("stocks") as Button
	_expect(source_stocks != null and source_stocks.visible and not source_stocks.disabled, "visible source stocks control is enabled before opening")
	var before_open: String = game.to_json()
	source_stocks.pressed.emit()
	await process_frame
	var panel: Control = ui.source_stock_panel
	_expect(panel != null and panel.visible, "source stocks control opens the source stock panel")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	ui._unhandled_input(space)
	var new_game_key := InputEventKey.new()
	new_game_key.keycode = KEY_N
	new_game_key.pressed = true
	ui._unhandled_input(new_game_key)
	ui._ai_pending = true
	ui._on_ai_timer_timeout()
	_expect(game.to_json() == before_open, "source stock panel blocks Space/N and queued AI mutation")
	_expect(not ui.new_game_popup.visible, "source stock panel keeps the legacy new-game popup closed")
	_expect(ui._ai_pending == false, "source stock panel drains a queued AI callback without acting")
	panel.call("close_panel")
	await process_frame
	_expect(not panel.visible, "source stock panel closes through its own EXIT control")
	source_stocks.pressed.emit()
	await process_frame
	panel.call("open_for", game.get_snapshot(), definition)
	panel.call("select_symbol", "s01")
	var buy: Button = panel.find_child("StockBuy", true, false) as Button
	_expect(buy != null and buy.visible and not buy.disabled, "source stock buy control is enabled for a selected share")
	if buy != null and not buy.disabled:
		buy.pressed.emit()
		await process_frame
		var buy_pad: Control = panel.find_child("SourceQuantityPad", true, false) as Control
		var buy_input: LineEdit = buy_pad.find_child("QuantityInput", true, false) as LineEdit if buy_pad != null else null
		if buy_input != null:
			buy_input.text = "1"
			buy_pad.find_child("QuantitySubmit", true, false).pressed.emit()
		await process_frame
	_expect(int(game.state.players[0].stocks.get("s01", 0)) == 1, "source stock buy reaches the existing choose_action path")
	_expect(int(game.state.players[0].deposit) == 900, "source stock buy uses the existing deposit accounting")
	panel.call("clear_selection")
	panel.call("select_symbol", "s01")
	var sell: Button = panel.find_child("StockSell", true, false) as Button
	_expect(sell != null and sell.visible and not sell.disabled, "source stock sell control is enabled after buying")
	if sell != null and not sell.disabled:
		sell.pressed.emit()
		await process_frame
		var sell_pad: Control = panel.find_child("SourceQuantityPad", true, false) as Control
		var sell_input: LineEdit = sell_pad.find_child("QuantityInput", true, false) as LineEdit if sell_pad != null else null
		if sell_input != null:
			sell_input.text = "1"
			sell_pad.find_child("QuantitySubmit", true, false).pressed.emit()
		await process_frame
	_expect(int(game.state.players[0].stocks.get("s01", 0)) == 0, "source stock sell reaches the existing choose_action path")
	_expect(int(game.state.players[0].deposit) == 1000, "source stock sell returns the existing deposit accounting")
	panel.call("close_panel")
	await process_frame
	_expect(not panel.visible, "source stock panel closes after the completed trade flow")


func _test_legacy_stock_source_route(ui: Control, shell: Control) -> void:
	var legacy: Object = GameState.new_game(204, 2)
	legacy.state.current_player = 0
	legacy.state.phase = "await_action"
	legacy._set_action_options(0)
	ui.game_state = legacy
	ui._active_map_definition = {}
	ui._refresh_from_state()
	var source_stocks: Button = shell.toolbar_buttons.get("stocks") as Button
	_expect(source_stocks != null and not source_stocks.disabled, "legacy source stocks control remains available")
	source_stocks.pressed.emit()
	_expect(ui.stocks_popup.visible and not ui.source_stock_panel.visible, "legacy source stocks stays on the legacy three-stock popup")
	ui.stocks_popup.hide()


func _run() -> void:
	var ui: Control = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	if ui.audio_controller != null:
		ui.audio_controller.call("stop")
	var shell: Control = ui.source_shell
	_test_title_and_layout(ui, shell)
	var game: Object = ui.game_state
	_test_title_ai_guard(ui, game, shell)
	game = _set_human_graph_game(ui)
	_test_hud_tabs_and_actions(ui, shell, game)
	_test_source_purchase_offer(ui, shell, game)
	_test_source_turn_controls_normal_mode(ui, shell, game)
	_test_source_hud_detail_values(ui, shell, game)
	await _test_source_full_map_and_player_inspect(ui, shell, game)
	_test_minimap_input(ui, shell, game)
	await _test_source_roll_presentation_gate(ui, shell)
	await _test_source_stock_modal_gate(ui, shell)
	_test_legacy_stock_source_route(ui, shell)
	_test_stock_names(shell)
	await _test_settlement_overlay_input(ui, shell)
	_test_release_feedback_states(ui, shell)
	await _test_route_keyboard_and_reaction_gate(ui, shell)
	await _test_calendar_minimap_viewport_input(Vector2i(640, 480))
	await _test_calendar_minimap_viewport_input(Vector2i(1280, 800))
	ui.queue_free()
	await create_timer(0.15).timeout
	print("Main HUD checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
