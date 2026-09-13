extends "res://tests/sleep_cards_ui.gd"

# Native acceptance found that opening the reaction while closing inventory
# could dismiss it before the human made a choice. Keep the reaction durable.
func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	var game := setup(ui, 69801)
	give(game, 0, "夢遊")
	give(game, 1, "嫁禍")
	await use_card(ui, "夢遊", 1)
	await create_timer(0.2).timeout
	check(ui._human_trap_response_pending() and ui.trap_popup.visible, "dream reaction survives inventory dismissal until human response")
	var decline: Node = ui.trap_popup.find_child("DeclineTrap", true, false)
	check(decline is Button and decline.text.contains("夢遊") and not decline.text.contains("入獄"), "decline button names the dream consequence")
	check(int(game.state.players[1].get("dream_days", 0)) == 0, "no dream is applied before human response")
	if ui._human_trap_response_pending() and decline is Button:
		decline.pressed.emit()
	check(int(game.state.players[1].get("dream_days", 0)) == 5, "actual decline button resolves dream")
	check(game.state.players[1].cards.has("嫁禍"), "decline retains the defense card")
	check(ui._event_detail("sleep_admitted", {"sleep_kind": "dream", "remaining": 5}).contains("夢遊"), "sleep admission has player-facing copy")
	check(ui._event_detail("trap_revenge", {"card_id": "夢遊", "caster_id": 0}).contains("夢遊"), "dream revenge copy does not claim imprisonment")
	check(Game.validate_save(game.to_dict()).get("ok", false), "modal result validates")
	ui.queue_free()
	print("Sleep modal checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
