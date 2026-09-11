extends "res://tests/source_autosave_ui.gd"
const LotteryCoreTest = preload("res://tests/source_lottery_core.gd")
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.gui_embed_subwindows = true
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	var folder := "/tmp/richman4-lottery-ui-%d" % Time.get_ticks_usec()
	var storage := CountSlots.new(folder.path_join("slots"), folder.path_join("legacy.json"))
	ui.source_save_menu.storage = storage
	var game := monthly_game(14)
	for i in range(11): game.state.lottery_tickets[i] = 1
	game.state.jackpot = 11000
	check(Core.validate_save(game.to_dict()).ok, "rare sold-ticket day14 fixture is valid")
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state()
	ui._on_end_turn_pressed()
	await settle()
	check(ui.source_monthly_controller.is_open(), "public day15 action presents dividend first")
	check(ui.source_lottery_controller.is_open() and ui.source_lottery_controller.report_panel == null, "lottery queues behind monthly report")
	check(storage.attempts == 0 and ui._source_autosave.pending(), "daily checkpoint waits for both reports")
	var before: String = game.to_json()
	ui.source_monthly_controller.report_panel.continued.emit()
	await settle()
	check(not ui.source_monthly_controller.is_open() and ui.source_lottery_controller.report_panel != null, "monthly acknowledgement shows lottery next")
	check(storage.attempts == 0, "lottery acknowledgement still blocks autosave")
	var panel: Control = ui.source_lottery_controller.report_panel
	ui._on_roll_pressed()
	ui._on_ai_timer_timeout()
	ui._on_source_stocks_requested()
	ui._on_source_start_requested()
	check(game.to_json() == before and not ui.source_stock_panel.visible and not ui.source_shell.is_setup_visible(), "lottery stops board/setup/AI/stocks")
	ui._refresh_from_state()
	check(ui.source_lottery_controller.report_panel == panel, "refresh preserves lottery presentation lifetime")
	panel.continued.emit()
	panel.continued.emit()
	await settle()
	check(not ui.source_lottery_controller.is_open() and storage.attempts == 1, "one final acknowledgement releases exactly one autosave")
	check(game.to_json() == before, "UI close never repeats cash award or RNG")
	var automatic := folder.path_join("slots/auto.json")
	check(FileAccess.file_exists(automatic), "checkpoint is present after lottery")
	if FileAccess.file_exists(automatic):
		var restored = Core.from_dict(JSON.parse_string(FileAccess.get_file_as_string(automatic)))
		check(restored != null and restored.to_json() == before, "autosave retains lottery once-only identity and ledger")
	ui._cancel_presentation()
	ui.game_state = Core.from_dict(JSON.parse_string(before))
	ui._refresh_from_state()
	await settle()
	check(not ui.source_lottery_controller.is_open() and not ui.source_monthly_controller.is_open(), "load does not replay either historical report")
	# Valid source-shaped purchase fixture, separate from normal catalog test.
	var definition := CompanyFixture.definition()
	definition.board[3].kind = "lottery"
	definition.board[3].type_and_idx = 0
	definition.board[3].event_code = 9
	definition.board[3].source_status_bits = 9
	game = Core.new_game_on_board(42,4,definition,{"original_facilities":true,"original_gods":true,"original_companies":true,"human_flags":[true,true,true,true],"start_date":{"year":1998,"month":1,"day":1}})
	game.state.god_objects = []
	game.state.players[0].position = 3
	game._resolve_landing(0,false)
	check(Core.validate_save(game.to_dict()).ok, "purchase fixture validates")
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state()
	await settle()
	check(ui.source_lottery_controller.is_open(), "pending purchase adopts controller on refresh")
	panel = ui.source_lottery_controller.report_panel
	var cash := int(game.state.players[0].cash)
	panel.call("_select_ticket", 1)
	panel.call("_select_ticket", 1)
	await create_timer(0.55).timeout
	await settle()
	check(game.state.players[0].cash == cash-1000 and game.state.jackpot == 1000 and game.state.phase == "await_action", "purchase UI settles one ticket and returns to same actor")
	check(not ui.source_lottery_controller.is_open(), "successful purchase releases controller")
	viewport.queue_free()
	await settle()
	print("Lottery MainUI checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
