extends "res://tests/source_title_ui.gd"
const Core = preload("res://game/core/game_state.gd")
const CompanyFixture = preload("res://tests/fixtures/company_fixture.gd")

func monthly_game(day: int, humans: bool = true) -> Object:
	var flags := [true, true, true, true] if humans else [false, false, false, false]
	var game: Object = Core.new_game_on_board(42, 4, CompanyFixture.definition(), {
		"original_facilities": true, "original_gods": true, "original_companies": true,
		"start_date": {"year": 1998, "month": 1, "day": 1}, "human_flags": flags})
	game.state.god_objects = []
	game.state.day = day
	game.state.current_player = 3
	game.state.phase = "await_action"
	game._sync_state()
	game._set_action_options(3)
	return game

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	check(ui._map_catalog_complete and ui.game_state != null, "normal MainUI uses its source catalog factory")
	var game := monthly_game(14)
	check(Core.validate_save(game.to_dict()).get("ok", false), "day14 calendar fixture validates before action")
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state({"state": game.get_snapshot()})
	var controller := ui.find_child("SourceMonthlyController", true, false)
	check(controller != null, "MainUI builds the monthly statement controller")
	if controller != null:
		check(not controller.is_open(), "initial refresh never opens historical statements")
		ui._on_end_turn_pressed()
		await settle()
		check(controller.is_open() and controller.current_report().kind == "dividend", "ordinary end-turn admits the day15 report")
		check(controller.get_parent() == ui.source_shell.reference_canvas, "report uses the source logical canvas")
		check(ui._source_modal_open() and ui._load_blocked_by_presentation() and not ui._source_save_operation_allowed(), "report blocks board and persistence ingress")
		var before: String = game.to_json()
		ui._on_roll_pressed()
		ui._on_source_stocks_requested()
		ui._on_source_start_requested()
		check(game.to_json() == before and not ui.source_stock_panel.visible and not ui.source_shell.is_setup_visible(), "report guards leave the game/RNG unchanged")
		var panel: Control = controller.report_panel
		ui._refresh_from_state()
		check(controller.report_panel == panel, "snapshot refresh preserves the visible report")
		panel.continued.emit()
		await settle()
		check(not controller.is_open() and not ui._source_modal_open(), "acknowledgment returns to the original turn")
		check(game.to_json() == before, "acknowledgment never repeats settlement or alters RNG")
		ui._refresh_from_state()
		check(not controller.is_open(), "acknowledged report does not reopen on refresh")
		game = monthly_game(31, false)
		check(Core.validate_save(game.to_dict()).get("ok", false), "month-end AI calendar fixture validates")
		ui._cancel_presentation()
		ui.game_state = game
		ui._refresh_from_state({"state": game.get_snapshot()})
		var result: Dictionary = ui._invoke_game("run_ai_turn")
		ui._handle_result(result)
		for _frame in range(500):
			if not ui._presentation_busy: break
			await create_timer(0.01).timeout
		await settle()
		check(not ui._presentation_busy and controller.is_open() and controller.current_report().kind == "interest", "AI calendar advance retains its interest report after movement")
		before = game.to_json()
		ui._on_ai_timer_timeout()
		check(game.to_json() == before, "report stops the next AI turn")
		var serialized: String = game.to_json()
		ui._cancel_presentation()
		ui.game_state = Core.from_dict(JSON.parse_string(serialized))
		ui._refresh_from_state({"state": ui.game_state.get_snapshot()})
		check(not controller.is_open() and ui.game_state.to_json() == serialized, "load adopts settled state without historical replay")
	viewport.queue_free()
	await settle()
	print("Monthly MainUI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
