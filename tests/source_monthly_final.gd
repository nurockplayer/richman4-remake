extends "res://tests/source_monthly_ui.gd"

class ReportDouble extends Control:
	signal continued
	var model: Dictionary = {}
	func set_view_model(value: Dictionary) -> void: model = value.duplicate(true)
	func set_visuals(_value: Variant) -> void: pass

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	root.add_child(viewport)
	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	var game := monthly_game(14)
	for player in game.state.players:
		player.cash = 0
		player.deposit = 0
		player.stocks.s01 = 1
	game.state.bank.deposits = 0
	game.state.companies[0].treasury -= 4
	game.state.companies[0].monthly_profit = -4
	game._update_company_owners()
	game._set_action_options(3)
	check(Core.validate_save(game.to_dict()).get("ok", false), "final-loss fixture is valid before settlement")
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state({"state": game.get_snapshot()})
	var controller := ui.find_child("SourceMonthlyController", true, false)
	check(controller != null, "source monthly controller exists")
	if controller != null:
		controller.panel_factory = func() -> Control: return ReportDouble.new()
		ui._on_end_turn_pressed()
		await settle()
		check(game.state.phase == "game_over", "source dividend losses end the game")
		check(controller.is_open() and controller.current_report().players.size() == 4, "report retains the pre-bankruptcy participants")
		check(not ui.end_overlay.visible, "final settlement overlay waits until the source dividend report is acknowledged")
		var before: String = game.to_json()
		controller.report_panel.continued.emit()
		await settle()
		check(ui.end_overlay.visible and not controller.is_open(), "acknowledgment reveals final settlement")
		check(game.to_json() == before and Core.validate_save(game.to_dict()).get("ok", false), "report lifetime preserves settled ledger and valid final save")
	viewport.queue_free()
	await settle()
	print("Monthly final-report checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
