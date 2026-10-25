extends SceneTree

## End-of-match settlement through the real MainUI host: all-AI completion,
## day-limit, wealth-target and last-survivor endings, plus the restart/title/
## quit choices, the frozen autosave and the disabled surrender command.

const QuitTestUI = preload("res://tests/fixtures/main_ui_quit_harness.gd")

var checks := 0
var failures := 0


class CountingStorage extends RefCounted:
	var automatic_writes := 0

	func write_automatic(_payload: Variant, _fingerprint: Variant = null) -> Dictionary:
		automatic_writes += 1
		return {"ok": true, "status": "written", "slot": 1}


## Minimal monthly report so the terminal-state/modal ordering can be driven
## without a real dividend cycle.
class FakeMonthlyPanel extends Control:
	signal continued

	func set_visuals(_visuals: Variant) -> void:
		pass

	func set_view_model(_model: Dictionary) -> void:
		pass

	func is_model_valid() -> bool:
		return true


func _initialize() -> void:
	call_deferred("run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _settle() -> void:
	await process_frame
	await process_frame


func _start_classic(
		ui: Control,
		seed_value: int,
		humans: Array,
		day_limit := 0,
		wealth_multiplier := 0,
	) -> Object:
	ui._set_development_path(true)
	var options := {
		"initial_fund": 200000,
		"day_limit": day_limit,
		"wealth_multiplier": wealth_multiplier,
		"start_date": {"year": 1998, "month": 1, "day": 1},
		"character_ids": [0, 1],
		"human_flags": humans,
	}
	var started: bool = ui._new_game(seed_value, 2, ui._make_fallback_map_definition(), options)
	_expect(started, "settlement fixture starts through MainUI")
	return ui.game_state


func _expected_ranking(game: Object) -> Array:
	var ranking: Array = []
	for player in game.state.players:
		ranking.append({
			"id": int(player.id),
			"name": str(player.name),
			"wealth": int(game.get_player_wealth(int(player.id))),
		})
	ranking.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.wealth) != int(b.wealth):
			return int(a.wealth) > int(b.wealth)
		return int(a.id) < int(b.id)
	)
	return ranking


func _expect_ranking(ui: Control, game: Object, label: String) -> void:
	var expected := _expected_ranking(game)
	var lines: PackedStringArray = ui.end_detail.text.split("\n")
	var start := lines.find("資產排名")
	_expect(start >= 0, "%s settlement lists a total-asset ranking" % label)
	if start < 0:
		return
	for index in range(expected.size()):
		var line := str(lines[start + 1 + index])
		var entry: Dictionary = expected[index]
		_expect(
			line.begins_with("%d. " % (index + 1)) and line.contains(str(entry.name)) and line.contains(ui._format_money(int(entry.wealth))),
			"%s ranking row %d follows descending total assets" % [label, index + 1],
		)


func _expect_overlay(ui: Control, game: Object, winner: int, reason_text: String, label: String) -> void:
	_expect(ui.end_overlay.visible, "%s settlement overlay is visible" % label)
	_expect(ui.end_overlay.z_index >= 100, "%s settlement overlay stays above the game HUD" % label)
	var winner_name := str(game.state.players[winner].name)
	_expect(ui.end_detail.text.contains("勝者：%s" % winner_name), "%s settlement names the winner" % label)
	_expect(ui.end_detail.text.contains(reason_text), "%s settlement explains the end reason" % label)
	_expect_ranking(ui, game, label)
	var restart := ui.end_overlay.find_child("SettlementRestart", true, false) as Button
	var close := ui.end_overlay.find_child("SettlementClose", true, false) as Button
	var quit := ui.end_overlay.find_child("SettlementQuit", true, false) as Button
	_expect(restart != null and not restart.disabled, "%s settlement offers a working new game" % label)
	_expect(close != null and not close.disabled and close.text == "返回標題", "%s settlement returns to the title" % label)
	_expect(quit != null and not quit.disabled, "%s settlement offers a normal quit" % label)
	_expect(not ui._source_modal_open(), "%s settlement leaves no gameplay modal open" % label)
	_expect(ui.roll_button.disabled and ui.end_turn_button.disabled, "%s settlement disables board actions" % label)


func _test_all_ai_match(ui: Control) -> void:
	ui.set_process(false)
	var game := _start_classic(ui, 777, [false, false], 30)
	ui.set_process(false)
	var result: Dictionary = game.run_ai_match(10000)
	_expect(bool(result.get("ok", false)), "all-AI fixture match reaches a terminal state")
	_expect(str(game.state.phase) == "game_over", "all-AI fixture match ends in game_over")
	if str(game.state.phase) != "game_over":
		return
	ui._refresh_from_state()
	await _settle()
	var winner := int(game.state.winner)
	_expect(winner >= 0, "all-AI match produces a winner")
	_expect_overlay(ui, game, winner, "期限結束", "all-AI")

	# A checkpoint captured just before settlement must never write afterwards.
	var storage := CountingStorage.new()
	ui.source_save_menu.storage = storage
	var before: Dictionary = game.to_dict()
	var after: Dictionary = before.duplicate(true)
	after["day"] = int(before.get("day", 1)) + 1
	after["phase"] = "await_roll"
	ui._source_autosave.capture_transition(game, before, after, true)
	_expect(ui._source_autosave.pending(), "pre-settlement autosave checkpoint is pending")
	ui._flush_source_autosave()
	_expect(not ui._source_autosave.pending(), "settlement discards the pending autosave")
	_expect(storage.automatic_writes == 0, "settlement never writes an AUTO slot")

	# Options still open, but surrender is visibly and operationally disabled.
	ui._open_source_options("game")
	_expect(ui._source_options_modal_open(), "options open on the settlement screen")
	_expect(ui.source_options_panel.z_index > ui.end_overlay.z_index, "settlement options render above the settlement panel")
	var labels: Array = ui.source_options_panel.command_labels
	_expect(labels.size() == 3, "options expose three source commands")
	if labels.size() == 3:
		_expect(str(labels[1].get_meta("source_command", "")) == "surrender", "second game command is surrender")
		_expect(bool(labels[1].get_meta("source_command_disabled", false)), "settlement disables the surrender command")
		_expect(not bool(labels[0].get_meta("source_command_disabled", true)), "settlement keeps restart enabled in options")
		_expect(not bool(labels[2].get_meta("source_command_disabled", true)), "settlement keeps quit enabled in options")
	var centre: Vector2 = ui.source_options_panel.get_hitbox("modecmd1").get_center()
	ui.source_options_panel._handle_left_down(centre)
	ui.source_options_panel._handle_left_up(centre)
	_expect(not ui._source_options_confirmation.visible, "pressing the disabled surrender row emits no command")
	_expect(str(ui._source_options_command).is_empty(), "disabled surrender never queues a confirmation")
	ui._on_source_options_command("surrender")
	_expect(not ui._source_options_confirmation.visible, "host rejects surrender even if a command is forced")
	# The enabled neighbour still reaches the host, so the gate is specific.
	var quit_centre: Vector2 = ui.source_options_panel.get_hitbox("modecmd2").get_center()
	ui.source_options_panel._handle_left_down(quit_centre)
	ui.source_options_panel._handle_left_up(quit_centre)
	_expect(ui._source_options_confirmation.visible, "enabled quit still raises its confirmation")
	ui._source_options_confirmation.hide()
	ui._cancel_source_options_command()
	_expect(not ui._source_options_confirmation.visible, "cancelling the quit confirmation closes it")
	ui.source_options_panel._cancel()
	_expect(not ui._source_options_modal_open(), "options close again")
	_expect(ui.source_options_panel.z_index == 70, "options layer resets below the game HUD after closing")

	# Quit goes through the host seam rather than ending the test process.
	var before_quit: String = game.to_json()
	var quit := ui.end_overlay.find_child("SettlementQuit", true, false) as Button
	quit.pressed.emit()
	_expect(ui.quit_requests == 1, "settlement quit requests an ordinary process exit")
	_expect(game.to_json() == before_quit, "settlement quit does not mutate the final snapshot")

	# Restart builds a fresh match from the settled seed and options.
	var settled_seed := int(game.state.seed)
	var restart := ui.end_overlay.find_child("SettlementRestart", true, false) as Button
	restart.pressed.emit()
	await _settle()
	_expect(ui.game_state != game, "settlement restart replaces the finished match")
	_expect(int(ui.game_state.state.seed) == settled_seed, "settlement restart reuses the settled seed")
	_expect(int(ui.game_state.state.turn) == 1 and int(ui.game_state.state.elapsed) == 0, "settlement restart starts a fresh first day")
	_expect(str(ui.game_state.state.phase) == "await_roll", "settlement restart starts at the roll phase")
	_expect(not ui.end_overlay.visible, "settlement overlay closes after a restart")


func _test_day_limit_end(ui: Control) -> void:
	var game := _start_classic(ui, 901, [true, true], 30)
	game.state.day = 30
	game.state.current_player = 1
	game.state.phase = "await_action"
	game._set_action_options(1)
	game._sync_state()
	ui._refresh_from_state()
	_expect(not ui.end_turn_button.disabled, "last day exposes the end-turn control")
	ui._on_end_turn_pressed()
	await _settle()
	_expect(str(game.state.phase) == "game_over", "day limit ends the match")
	var winner := int(game.state.winner)
	_expect_overlay(ui, game, winner, "期限結束", "day-limit")

	# A terminal state reached while a monthly report is open must settle as
	# soon as that report is acknowledged, instead of staying hidden behind it.
	ui.source_monthly_controller.panel_factory = func() -> Control: return FakeMonthlyPanel.new()
	var before: Dictionary = game.to_dict()
	var after: Dictionary = before.duplicate(true)
	var events: Array = after.get("event_log", []).duplicate(true)
	events.append({"type": "monthly_statement", "report": {"kind": "dividend", "amount": 1000}})
	after["event_log"] = events
	ui.source_monthly_controller.capture_transition(game, before, after)
	ui.source_monthly_controller.sync(game, false)
	_expect(ui._source_monthly_modal_open(), "a monthly report opens over the settled match")
	ui._update_end_overlay("game_over")
	_expect(not ui.end_overlay.visible, "the settlement waits behind the open report")
	var panel: Control = ui.source_monthly_controller.report_panel
	panel.continued.emit()
	await _settle()
	await _settle()
	_expect(not ui._source_monthly_modal_open(), "acknowledging the report closes it")
	_expect(ui.end_overlay.visible, "the settlement appears once the report closes")

	# The return control goes to the title instead of leaving a dead board.
	var close := ui.end_overlay.find_child("SettlementClose", true, false) as Button
	close.pressed.emit()
	await _settle()
	_expect(not ui.end_overlay.visible, "return control hides the settlement")
	_expect(ui.source_shell.is_title_visible(), "return control shows the source title")
	_expect(str(game.state.phase) == "game_over", "returning to the title keeps the settled snapshot")
	ui.source_shell.call("show_game")
	ui._refresh_from_state()
	await _settle()
	_expect(ui.end_overlay.visible, "reopening a settled board shows the settlement again")

	# Loading a finished manual save from the title must settle, not soft-lock.
	ui.source_shell.call("show_title")
	ui._refresh_from_state()
	await _settle()
	_expect(not ui.end_overlay.visible, "the title hides the settled overlay")
	ui._apply_loaded_game(game, game.to_dict(), false)
	await _settle()
	_expect(ui.end_overlay.visible, "loading a finished save shows its settlement")


func _test_wealth_target_end(ui: Control) -> void:
	var game := _start_classic(ui, 902, [true, true], 0, 3)
	game.state.players[0].cash = 600000
	game.state.current_player = 1
	game.state.phase = "await_action"
	game._set_action_options(1)
	game._sync_state()
	ui._refresh_from_state()
	ui._on_end_turn_pressed()
	await _settle()
	_expect(str(game.state.phase) == "game_over", "wealth target ends the match")
	_expect(int(game.state.winner) == 0, "wealth target winner is the richest player")
	_expect_overlay(ui, game, 0, "達成財富目標", "wealth-target")


func _test_last_survivor_end(ui: Control) -> void:
	var game := _start_classic(ui, 903, [true, true], 0)
	game.state.current_player = 1
	game.state.phase = "await_action"
	game._set_action_options(1)
	game._sync_state()
	ui._refresh_from_state()
	var result: Dictionary = ui._invoke_game("surrender")
	_expect(bool(result.get("ok", false)), "the second player can concede")
	ui._handle_result(result)
	await _settle()
	_expect(str(game.state.phase) == "game_over", "last surviving player ends the match")
	_expect(int(game.state.winner) == 0, "last survivor wins the match")
	_expect_overlay(ui, game, 0, "最後一位存活", "last-survivor")
	_expect(ui.end_detail.text.contains("已破產"), "last-survivor ranking marks the conceded player")

	# Without a source shell there is no title to return to; the close control
	# must keep the settlement (and its quit choice) rather than strand the player.
	var shell: Control = ui.source_shell
	ui.source_shell = null
	var close := ui.end_overlay.find_child("SettlementClose", true, false) as Button
	close.pressed.emit()
	await _settle()
	_expect(ui.end_overlay.visible, "settlement stays up when no title screen exists")
	ui.source_shell = shell


func run() -> void:
	var ui := QuitTestUI.new()
	root.add_child(ui)
	await _settle()
	ui.set_process(false)
	ui._source_settings["autosave"] = false
	await _test_all_ai_match(ui)
	await _test_day_limit_end(ui)
	await _test_wealth_target_end(ui)
	await _test_last_survivor_end(ui)
	ui.queue_free()
	await _settle()
	print("Match settlement checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
