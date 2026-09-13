extends "res://tests/sleep_cards_ui.gd"

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	var game := setup(ui, 69811)
	give(game, 0, "夢遊")
	give(game, 1, "嫁禍")
	await use_card(ui, "夢遊", 1)
	check(ui._human_trap_response_pending(), "valid dream awaits human response")
	var pending_json: String = game.to_json()
	ui.trap_popup.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.1).timeout
	check(game.to_json() == pending_json, "application focus loss must not choose a defense response")
	check(ui.trap_popup.visible and ui._human_trap_response_pending(), "defense decision remains visible after focus loss")
	if ui._human_trap_response_pending():
		ui.trap_decline_button.pressed.emit()
	check(int(game.state.players[1].get("dream_days", 0)) == 5, "explicit decline still resolves pending dream")
	ui.queue_free()
	print("Sleep focus checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
