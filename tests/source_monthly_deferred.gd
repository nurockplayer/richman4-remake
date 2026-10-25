extends "res://tests/source_monthly_ui.gd"

const NewsFixture = preload("res://tests/fixtures/news_fixture.gd")

func run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(960, 720)
	root.add_child(view)
	var ui := TitleTestUI.new()
	view.add_child(ui)
	await settle()
	ui.set_process(false)
	var options := NewsFixture.new_game_options()
	options.start_date = {"year": 1998, "month": 1, "day": 1}
	options.human_flags = [true, true, true, true]
	var game: Object = Core.new_game_on_board(5411, 4, NewsFixture.definition(), options)
	check(game != null, "news/company source fixture creates a game")
	if game == null:
		quit(1)
		return
	game.state.god_objects = []
	game.state.day = 14
	game.state.current_player = 3
	game.state.phase = "await_action"
	game._sync_state()
	game._set_action_options(3)
	# A legal rare-state fixture: resolve a source news landing immediately
	# before the final player's public end-turn produces the day-15 report.
	game._graph_visit_tile(3, game.state.board.back(), true)
	check(Core.validate_save(game.to_dict()).get("ok", false), "resolved news and day14 fixture validate before the end-turn")
	check(not game.state.get("news", {}).get("last", {}).is_empty(), "the existing news core supplies a completed result")
	ui._cancel_presentation()
	ui.game_state = game
	ui.news_popup.display_seconds = 60.0
	ui._refresh_from_state({"state": game.get_snapshot()})
	ui._on_end_turn_pressed()
	await settle()
	var controller: Control = ui.source_monthly_controller
	check(controller.is_open() and controller.current_report().kind == "dividend", "public end-turn queues a real dividend report")
	check(ui.news_popup.visible and controller.report_panel == null, "existing news presentation delays the queued report")
	var before: String = game.to_json()
	var close: Button = ui.news_popup.find_child("CloseNews", true, false)
	check(close != null, "real news popup has a close control")
	if close != null:
		close.pressed.emit()
	await settle()
	check(not ui.news_popup.visible, "news close dismisses its presentation")
	check(controller.report_panel != null and controller.report_panel.visible, "news dismissal releases the waiting monthly report without a new game action")
	check(game.to_json() == before, "presentation handoff leaves settled ledger and RNG unchanged")
	if controller.report_panel != null:
		controller.report_panel.continue_report()
		await settle()
		check(not controller.is_open(), "acknowledgment returns to the next turn")
	view.queue_free()
	await settle()
	print("Monthly deferred checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
