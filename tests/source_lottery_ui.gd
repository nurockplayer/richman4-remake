extends SceneTree

## Self-contained MainUI acceptance for the source lottery port. The fixture
## game is injected through the ordinary load path so the host wiring (gates,
## controller ownership, purchase/draw presentation) is exercised without the
## private source catalog.
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")
const MainScene = preload("res://game/main.tscn")

var checks := 0
var failures := 0
var ui: Control
var view: SubViewport


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func settle() -> void:
	await process_frame
	await process_frame


func waiting_game(start_day: int, human_flags: Array = [true, true, true, true]) -> Object:
	var definition := Fixture.definition()
	definition.board[3].merge({"kind": "lottery", "type_and_idx": 0, "event_code": 9, "source_status_bits": 9}, true)
	var game: Object = Game.new_game_on_board(42, 4, definition, {"original_facilities": true, "original_gods": true, "original_companies": true, "human_flags": human_flags, "start_date": {"year": 1998, "month": 1, "day": start_day}})
	game.state.god_objects = []
	return game


func load_game(game: Object) -> void:
	ui._cancel_presentation()
	ui._apply_loaded_game(game, game.to_dict(), false)


func right_release() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = false
	event.position = Vector2(10, 400)
	event.global_position = event.position
	view.push_input(event, true)
	await settle()


func _run() -> void:
	view = SubViewport.new()
	view.size = Vector2i(960, 720)
	view.gui_embed_subwindows = true
	view.handle_input_locally = true
	root.add_child(view)
	ui = MainScene.instantiate()
	view.add_child(ui)
	await settle()
	ui.set_process(false)
	await _test_purchase_cancel()
	await _test_pending_purchase()
	await _test_ai_encounter()
	await _test_draw_report()
	view.queue_free()
	await settle()
	print("Source lottery main UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _test_purchase_cancel() -> void:
	var game := waiting_game(14)
	game.state.players[0].position = 3
	game._resolve_landing(0, false)
	load_game(game)
	await settle()
	var controller: Control = ui.source_lottery_controller
	expect(controller.is_open(), "cancel fixture opens the purchase panel")
	var cash := int(game.state.players[0].cash)
	var before: Dictionary = game.to_dict()
	await right_release()
	expect(not controller.is_open() and not ui._source_modal_open(), "real right release closes the purchase panel")
	expect(game.state.phase == "await_action", "cancelling the purchase returns to the same actor")
	expect(int(game.state.players[0].cash) == cash and int(game.state.jackpot) == 0 and int(game.state.lottery_tickets.count(0)) == 36, "cancel has no financial effect")
	expect(ui._source_save_operation_allowed(), "cancel releases the save gate")
	var saved_after: Dictionary = game.to_dict()
	expect(saved_after != before and Game.validate_save(saved_after).ok, "cancelled encounter remains a valid save")


func _test_pending_purchase() -> void:
	var game := waiting_game(14)
	game.state.players[0].position = 3
	game._resolve_landing(0, false)
	expect(game.state.phase == "await_lottery", "fixture lands on source lottery")
	expect(Game.validate_save(game.to_dict()).ok, "pending purchase fixture validates")
	load_game(game)
	await settle()
	var controller: Control = ui.source_lottery_controller
	expect(controller != null and controller.is_open(), "pending lottery opens the source controller")
	var panel: Control = controller.report_panel
	expect(panel != null and panel.visible and panel.view_model().kind == "purchase", "pending encounter shows the purchase panel")
	expect(ui._source_modal_open() and ui._load_blocked_by_presentation() and not ui._source_save_operation_allowed(), "lottery owns the modal, load and save gates")
	var before: Dictionary = game.to_dict()
	var rejected: Dictionary = ui._invoke_game("roll")
	expect(not bool(rejected.get("ok", true)) and game.to_dict() == before, "ordinary actions are refused while the lottery panel is open")
	expect(str(rejected.get("message", "")).contains("彩券"), "refusal explains the pending lottery encounter")
	ui._on_source_stocks_requested()
	expect(ui.source_stock_panel == null or not ui.source_stock_panel.visible, "stocks stay closed behind the lottery panel")
	ui._on_bank_pressed()
	expect(not ui.bank_popup.visible, "bank stays closed behind the lottery panel")
	var cash := int(game.state.players[0].cash)
	panel.call("_select_ticket", 1)
	panel.call("_select_ticket", 1)
	await create_timer(0.7).timeout
	await settle()
	expect(game.state.players[0].cash == cash - 1000 and int(game.state.jackpot) == 1000 and int(game.state.lottery_tickets[0]) == 1, "purchase transfers exactly one ticket price into the shared pool")
	expect(game.state.phase == "await_action", "purchase returns to the same actor")
	expect(not controller.is_open() and not ui._source_modal_open(), "successful purchase releases the modal")
	expect(ui._source_save_operation_allowed(), "save gate reopens after the purchase")
	var saved: Dictionary = game.to_dict()
	var restored = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null and restored.to_dict() == saved, "purchased encounter round-trips through JSON")
	load_game(restored)
	await settle()
	expect(not controller.is_open(), "loading a purchased save does not replay the purchase")


func _test_ai_encounter() -> void:
	var game := waiting_game(5, [true, false, false, false])
	game.state.current_player = 1
	game.state.players[1].position = 3
	game._resolve_landing(1, false)
	expect(game.state.phase == "await_lottery" and int(game.state.lottery_pending) == 1, "AI fixture waits on the lottery encounter")
	expect(Game.validate_save(game.to_dict()).ok, "AI encounter fixture validates")
	load_game(game)
	await settle()
	var controller: Control = ui.source_lottery_controller
	expect(not controller.is_open() and not ui._source_modal_open(), "an AI encounter never opens the human purchase panel")
	expect(not ui._load_blocked_by_presentation(), "an AI encounter leaves the load gate open")
	var cash_before := int(game.state.players[1].cash)
	ui._maybe_schedule_ai_turn()
	await create_timer(1.0).timeout
	await settle()
	expect(int(game.state.lottery_pending) == -1 and game.state.phase != "await_lottery" and int(game.state.current_player) != 1, "the AI timer closes its encounter and finishes its turn")
	expect(not controller.is_open(), "the resolved AI encounter has no purchase report")
	var sold := 36 - int(game.state.lottery_tickets.count(0))
	var bought := int(game.state.jackpot) == 1000 and sold == 1 and int(game.state.lottery_tickets.count(2)) == 1 and int(game.state.players[1].cash) == cash_before - 1000
	var left := int(game.state.jackpot) == 0 and sold == 0 and int(game.state.players[1].cash) == cash_before
	expect(bought or left, "the AI buys at most one ticket with its own cash or leaves")


func _test_draw_report() -> void:
	var game := waiting_game(14)
	for i in range(11): game.state.lottery_tickets[i] = 1
	game.state.jackpot = 11000
	game.state.players[0].position = 3
	game.state.current_player = 3
	game.state.phase = "await_action"
	game._set_action_options(3)
	expect(Game.validate_save(game.to_dict()).ok, "day14 draw fixture validates")
	load_game(game)
	await settle()
	var controller: Control = ui.source_lottery_controller
	expect(not controller.is_open(), "no report before the draw")
	var before: String = game.to_json()
	ui._on_end_turn_pressed()
	await settle()
	expect(int(game.state.date.get("day", 0)) == 15 and int(game.state.lottery_draw_day) == 1, "public end turn settles the source draw on day 15")
	expect(int(game.state.jackpot) == 0, "concentrated tickets pay the whole shared pool")
	expect(controller.is_open(), "draw report is queued for presentation")
	var panel: Control = controller.report_panel
	expect(panel != null and panel.visible and panel.view_model().kind == "draw", "draw panel presents the settled result")
	var settled: String = game.to_json()
	var rejected: Dictionary = ui._invoke_game("roll")
	expect(not bool(rejected.get("ok", true)) and game.to_json() == settled, "draw report blocks the next action")
	expect(not ui._source_save_operation_allowed(), "draw report holds the save gate")
	panel.continued.emit()
	panel.continued.emit()
	await settle()
	expect(not controller.is_open() and not ui._source_modal_open(), "one acknowledgement clears the draw report")
	expect(game.to_json() == settled, "acknowledgement never repeats the award or consumes RNG")
	expect(ui._source_save_operation_allowed(), "draw acknowledgement releases the save gate")
	load_game(Game.from_dict(JSON.parse_string(settled)))
	await settle()
	expect(not controller.is_open(), "reloading a settled save does not replay its historical draw")
