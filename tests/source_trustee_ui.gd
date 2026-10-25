extends SceneTree

## Focused S04 MainUI host checks.  The synthetic map fixture keeps private
## assets out of the repository; the dialog must stay usable without art.

const Core = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const BaseMap = preload("res://tests/fixtures/original_map_fixture.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func settle() -> void:
	await process_frame
	await process_frame


func run() -> void:
	var ui: Control = MainScene.instantiate()
	root.add_child(ui)
	await settle()
	ui.set_process(false)
	if ui.audio_controller != null:
		ui.audio_controller.call("stop")
	var normalized: Dictionary = Maps.normalize_map(BaseMap.make())
	check(bool(normalized.get("ok", false)), "trustee fixture map normalizes")
	var definition: Dictionary = normalized.get("definition", {})
	ui._set_development_path(true)
	var options := {
		"start_date": {"year": 1998, "month": 1, "day": 1},
		"human_flags": [true, true, false],
		"character_ids": [0, 1, 2],
	}
	check(ui._new_game(811, 3, definition, options), "ordinary factory creates mixed-origin game")
	ui.source_shell.show_game()
	ui._refresh_from_state()
	await settle()
	var game: Object = ui.game_state
	check(Core.validate_save(game.to_dict()).get("ok", false), "host setup is a valid save")
	check(ui.has_method("_source_trustee_modal_open"), "ordinary toolbar trustee host is implemented")
	check(not ui.source_shell.toolbar_buttons.ai.disabled, "ordinary toolbar trustee button is enabled")
	if not ui.has_method("_source_trustee_modal_open"):
		ui.queue_free()
		await settle()
		quit(1)
		return
	var before: String = game.to_json()
	var original_quit := auto_accept_quit
	ui.source_shell.toolbar_buttons.ai.pressed.emit()
	await settle()
	var controller: Control = ui.source_trustee_controller
	check(controller.is_open() and controller.get_parent() == ui.source_shell.reference_canvas, "ordinary toolbar opens source canvas trustee")
	check(game.to_json() == before, "opening and inspecting leave full state/RNG unchanged")
	check(ui._source_modal_open() and ui._load_blocked_by_presentation() and not ui._is_human_turn(), "trustee joins all host action and persistence gates")
	check(not auto_accept_quit, "OS close cannot quit app while draft is pending")
	check(not controller.dialog.source_art_available(), "private Panel77 art is absent from the public checkout")
	var fallback: Variant = controller.dialog.find_child("SourceTrusteeArtFallback", true, false)
	check(fallback != null and bool(fallback.visible), "missing private art keeps the text fallback visible")
	controller.dialog.set_ratio(0, "cash_ratio", 80)
	controller.dialog.set_ratio(1, "stock_ratio", 0)
	controller.dialog.select_player(1)
	check(not controller.draft_rows()[1].trustee, "other human row selects without toggling")
	controller.dialog.select_player(1)
	check(controller.draft_rows()[1].trustee, "selected row toggles")
	ui._on_roll_pressed()
	ui._on_source_map_requested()
	ui._on_source_inspect_requested()
	ui._on_source_stocks_requested()
	ui._on_source_load_requested()
	ui._on_source_start_requested()
	ui._on_ai_timer_timeout(ui._presentation_generation - 1)
	check(game.to_json() == before and not ui.source_stock_panel.visible and not ui.source_shell.is_title_visible(), "open draft rejects board/new/load/stocks and stale AI callbacks")
	controller.cancel()
	await settle()
	check(game.to_json() == before and not ui._source_modal_open() and auto_accept_quit == original_quit, "Cancel preserves state and restores host window policy")
	ui._on_source_ai_requested()
	controller = ui.source_trustee_controller
	controller.dialog.set_ratio(0, "cash_ratio", 80)
	controller.dialog.set_ratio(1, "stock_ratio", 0)
	controller.dialog.select_player(1)
	controller.dialog.select_player(1)
	controller.dialog.accept_dialog()
	await settle()
	check(game.trustee_rows()[0].cash_ratio == 80 and not game.state.players[0].is_ai and game.state.players[1].is_ai and game.state.players[2].is_ai, "OK atomically commits preferences for human and trustee while preserving native AI")
	var committed: String = game.to_json()
	check(Core.validate_save(game.to_dict()).get("ok", false), "accepted settings are save-valid")
	ui._on_source_ai_requested()
	controller = ui.source_trustee_controller
	check(controller.draft_rows()[0].cash_ratio == 80 and controller.draft_rows()[1].stock_ratio == 0, "reopen loads both committed row preferences")
	controller.dialog.set_ratio(0, "cash_ratio", 0)
	ui.get_window().close_requested.emit()
	await settle()
	check(not controller.is_open() and game.to_json() == committed and auto_accept_quit == original_quit, "Window close signal cancels draft without ledger/RNG changes or app quit")
	ui._on_source_ai_requested()
	var old_controller: Control = ui.source_trustee_controller
	var stale: Array = old_controller.draft_rows()
	old_controller.cancel()
	ui._on_source_ai_requested()
	controller = ui.source_trustee_controller
	stale[0].trustee = true
	old_controller.accepted.emit(stale)
	old_controller.cancelled.emit()
	check(controller.is_open() and game.to_json() == committed, "stale prior modal signals cannot commit or cancel the new session")
	controller.cancel()
	await settle()
	ui._on_source_ai_requested()
	controller = ui.source_trustee_controller
	var replacement: Object = Core.from_dict(JSON.parse_string(committed))
	ui.game_state = replacement
	ui._refresh_from_state()
	check(not controller.is_open() and replacement.to_json() == committed, "owner replacement cancels old draft")
	controller.accepted.emit(stale)
	check(replacement.to_json() == committed and game.to_json() == committed, "old owner acceptance cannot write either game")
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state()
	ui._on_source_ai_requested()
	controller = ui.source_trustee_controller
	check(controller.is_open(), "trustee reopens after owner replacement")
	for row in controller.draft_rows():
		if int(row.player_id) != controller.selected_player_id():
			controller.dialog.select_player(int(row.player_id))
		if not controller.draft_rows()[int(row.player_id)].trustee:
			controller.dialog.toggle_selected()
	controller.dialog.accept_dialog()
	await settle()
	var release := InputEventKey.new()
	release.keycode = KEY_ESCAPE
	release.pressed = false
	ui._unhandled_input(release)
	check(bool(game.state.get("trustee_recovery_requested", false)) and game.state.players[0].is_ai, "all-trustee Escape release requests delayed recovery")
	var result: Dictionary = game.run_ai_turn()
	check(result.get("ok", false) and not game.state.players[0].is_ai and game.state.players[1].is_ai, "next real actor boundary recovers source player0 only")
	ui.queue_free()
	await settle()
	print("Trustee MainUI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
