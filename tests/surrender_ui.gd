extends SceneTree

## SURRENDER through the real in-game options host.
##
## The options presenter must ask for confirmation before touching the match,
## cancelling must leave the game and its RNG untouched, confirming must route
## through the public game transition (bankruptcy path, no creditor) and close
## the options window, and a two-player concession must end the match.  Only a
## worktree-local settings path is injected, so the owner's files are never
## read or written.

const Core = preload("res://game/core/game_state.gd")
const CompanyFixture = preload("res://tests/fixtures/company_fixture.gd")
const TitleTestUI = preload("res://tests/fixtures/source_bank_ui_harness.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func settle() -> void:
	await process_frame
	await process_frame


func fixture(players: int = 4, actor: int = 3) -> Object:
	var flags: Array = []
	for index in range(players):
		flags.append(true)
	var game: Object = Core.new_game_on_board(42, players, CompanyFixture.definition(), {
		"original_facilities": true, "original_gods": true, "original_companies": true,
		"start_date": {"year": 1998, "month": 1, "day": 1}, "human_flags": flags})
	game.state.day = 14
	game.state.current_player = actor
	game.state.phase = "await_action"
	var total := 0
	for player in game.state.players:
		total += int(player.deposit)
	game.state.bank["deposits"] = total
	game._sync_state()
	game._set_action_options(actor)
	return game


func adopt(ui: Control, game: Object) -> void:
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state({"state": game.get_snapshot()})


## Press the options window's own row through the presenter's input path.
func press_row(panel: Control, row: String) -> void:
	var point: Vector2 = (panel.call("_hitbox", row) as Rect2).get_center()
	panel.call("_handle_left_down", point)
	panel.call("_handle_left_up", point)


func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var scratch := ProjectSettings.globalize_path("res://.local/surrender-ui-%d" % OS.get_process_id())
	var ui := TitleTestUI.new()
	ui.settings_path = scratch + "/settings.json"
	ui.hotkeys_path = scratch + "/hotkeys.json"
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	check(ui.source_options_panel != null and ui._source_options_confirmation != null, "MainUI builds the options and confirmation presenters")

	var game := fixture()
	adopt(ui, game)
	var actor := int(game.state.current_player)
	var before: String = game.to_json()
	ui._open_source_options("game")
	await settle()
	var panel: Control = ui.source_options_panel
	check(panel.call("is_open"), "in-game options open for the human")
	press_row(panel, "modecmd1")
	await settle()
	check(ui._source_options_confirmation.visible, "SURRENDER asks for confirmation first")
	check(str(ui._source_options_confirmation.dialog_text).contains("投降"), "the confirmation states what surrendering does")
	check(game.to_json() == before and bool(game.state.players[actor].get("alive", false)), "the prompt alone never concedes")
	ui._source_options_confirmation.canceled.emit()
	await settle()
	check(game.to_json() == before and bool(game.state.players[actor].get("alive", false)), "cancelling leaves the match untouched")
	check(panel.call("is_open"), "cancelling returns to the open options window")

	press_row(panel, "modecmd1")
	await settle()
	ui._source_options_confirmation.confirmed.emit()
	await settle()
	check(not bool(game.state.players[actor].get("alive", true)), "confirming concedes the human")
	check(not panel.call("is_open"), "conceding closes the options window")
	check(int(game.state.current_player) != actor, "the turn passes after the human concedes")
	check(game.state.phase != "game_over" and ui.state.get("phase", "") != "game_over", "a four-player match continues after one concession")
	check(ui._local_log.has("已投降"), "the log reports the concession")
	check(bool(Core.validate_save(game.to_dict()).get("ok", false)), "the post-concession UI state validates")

	var duel := fixture(2, 0)
	adopt(ui, duel)
	ui._open_source_options("game")
	await settle()
	press_row(ui.source_options_panel, "modecmd1")
	await settle()
	ui._source_options_confirmation.confirmed.emit()
	await settle()
	check(duel.state.phase == "game_over", "the two-player match ends when one player concedes")
	check(int(duel.state.get("winner", -1)) == 1 and int(ui.state.get("winner", -1)) == 1, "the last remaining player wins the concession")

	# A refused concession (the match is already over, so the actor cannot act)
	# must report the refusal, never a successful surrender.
	var frozen: String = duel.to_json()
	var log_size: int = ui._local_log.size()
	ui._open_source_options("game")
	await settle()
	press_row(ui.source_options_panel, "modecmd1")
	await settle()
	ui._source_options_confirmation.confirmed.emit()
	await settle()
	check(ui._local_log.size() == log_size + 1 and str(ui._local_log[-1]) != "已投降", "a refused concession never claims success")
	check(duel.to_json() == frozen, "a refused concession leaves the finished match alone")

	viewport.queue_free()
	await settle()
	print("Surrender MainUI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
