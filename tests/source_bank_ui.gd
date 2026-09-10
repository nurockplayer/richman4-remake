extends "res://tests/source_title_ui.gd"
const Core = preload("res://game/core/game_state.gd")
const BankFixture = preload("res://tests/fixtures/source_bank_visit_fixture.gd")

func bank_game(seed_value: int) -> Object:
	var game: Object = Core.new_game_on_board(seed_value, 2, BankFixture.definition(), {
		"original_facilities": true, "original_gods": true, "original_companies": true,
		"start_date": {"year": 1998, "month": 1, "day": 1}})
	game.state.players[0].position = 0
	game.state.players[0].previous_position = -1
	game.state.players[1].position = 8
	game.state.god_objects = []
	game._set_action_options(0)
	return game

func game_with_roll(total: int) -> Object:
	for seed_value in range(1, 100):
		var game := bank_game(seed_value)
		if int(game.roll(1).get("total", -1)) == total:
			return bank_game(seed_value)
	return null

func finish_movement(ui: Control) -> void:
	for _frame in range(500):
		if not ui.get("_presentation_busy"):
			break
		await create_timer(0.01).timeout
	await settle()
	check(not ui.get("_presentation_busy"), "movement presentation finishes within the bounded wait")

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
	check(ui._map_catalog_complete and ui.game_state != null, "source-capable MainUI starts through the catalog factory")
	var game := game_with_roll(2)
	check(game != null and Core.validate_save(game.to_dict()).get("ok", false), "bank encounter fixture is valid before the roll")
	var controller := ui.find_child("SourceBankController", true, false)
	check(controller != null, "MainUI builds the source bank encounter controller")
	if controller != null and game != null:
		ui.game_state = game
		ui._refresh_from_state({"state": game.get_snapshot()})
		ui._on_roll_pressed()
		check(ui._presentation_busy and not controller.is_open(), "bank waits for the approach animation before opening")
		await finish_movement(ui)
		check(controller.is_open() and ui.state.phase == "await_bank", "ordinary roll opens ATM at the core bank pause")
		check(controller.get_parent() == ui.source_shell.reference_canvas, "bank shares the source reference canvas")
		check(controller.bank_panel.position == Vector2(60, 71), "ATM uses the source board origin")
		check(ui._source_modal_open() and ui._load_blocked_by_presentation() and not ui._source_save_operation_allowed(), "bank decision blocks board controls and save/load")
		var before: String = game.to_json()
		ui._on_source_stocks_requested()
		ui._on_source_start_requested()
		check(not ui.source_stock_panel.visible and not ui.source_shell.is_setup_visible(), "bank blocks stock and new-game entry")
		check(game.to_json() == before, "blocked toolbar requests preserve game and RNG")
		var panel: Control = controller.bank_panel
		press(viewport, panel.find_child("ATMWithdraw", true, false))
		panel.set_amount_text("25")
		ui._update_all()
		check(panel.current_amount() == 25, "MainUI refresh preserves active ATM input")
		panel.action_requested.emit("withdraw", game.bank_transfer_limit("withdraw") + 1)
		await settle()
		check(game.to_json() == before and controller.error_label.visible, "host refresh preserves an authoritative atomic rejection")
		panel.cancel_amount()
		press(viewport, panel.find_child("ATMExit", true, false))
		await settle()
		check(ui._presentation_busy, "bank close resumes movement through the presentation adapter")
		await finish_movement(ui)
		check(not controller.is_open() and game.state.players[0].position == 2 and game.state.phase == "await_action", "bank close completes the exact remaining route")
		check(not ui._source_modal_open() and not ui._load_blocked_by_presentation(), "finished bank encounter releases modal guards")
		# A terminal bank first offers ATM, then the front, with the same token.
		game = game_with_roll(1)
		ui._cancel_presentation()
		ui.game_state = game
		ui._refresh_from_state({"state": game.get_snapshot()})
		ui._on_roll_pressed()
		await finish_movement(ui)
		check(controller.is_open() and controller.bank_panel.view_model().entry_mode == "atm", "landing first opens ATM")
		press(viewport, controller.bank_panel.find_child("ATMExit", true, false))
		await settle()
		check(controller.is_open() and controller.bank_panel.view_model().entry_mode == "loan", "landing ATM exit opens the bank front")
		check(game.state.pending_bank_visit.kind == "landing", "front preserves the core landing token")
		ui._cancel_presentation()
		check(not controller.is_open(), "game replacement cancels the active source bank presenter")
	viewport.queue_free()
	await settle()
	print("Source bank MainUI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
