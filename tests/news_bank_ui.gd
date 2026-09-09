extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/news_fixture.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	check(ui._new_game(5422, 4, Fixture.definition(), Fixture.new_game_options()), "loan UI fixture constructs")
	var game: Object = ui.game_state
	game.state.god_objects = []
	for id in range(4): game.set_player_ai(id, false)
	game.state.players[0].position = 5
	game.state.players[0].previous_position = -1
	game.state.phase = "await_action"
	game.state.bank_access = true
	game.state.bank_landing = true
	game._set_action_options(0)
	check(Game.validate_save(game.to_dict()).get("ok", false), "bank landing fixture validates")
	ui._refresh_from_state()
	ui._on_bank_pressed()
	var loan: Button = ui.find_child("BankLoan", true, false)
	check(loan != null and not loan.disabled, "eligible bank landing exposes loan button")
	game.state.players[0].loan_block_days = 15
	game._set_action_options(0)
	check(Game.validate_save(game.to_dict()).get("ok", false), "active news loan ban fixture validates")
	ui._refresh_from_state()
	ui._on_bank_pressed()
	loan = ui.find_child("BankLoan", true, false)
	check(loan != null and loan.disabled, "news ban disables loan button")
	var status: Label = ui.find_child("LoanStatus", true, false)
	check(status != null and status.text.contains("15"), "news ban duration is visible")
	check(not ui.bank_deposit_button.disabled and not ui.bank_withdraw_button.disabled, "news ban preserves deposit and withdrawal")
	var snapshot: String = game.to_json()
	ui.bank_popup.hide()
	check(game.to_json() == snapshot, "closing bank does not change loan ban")
	game.state.players[0].loan_block_days = 128
	game._set_action_options(0)
	ui._refresh_from_state()
	ui._on_bank_pressed()
	loan = ui.find_child("BankLoan", true, false)
	check(loan != null and not loan.disabled, "release marker restores loan button")
	var before_cash: int = int(game.state.players[0].cash)
	if loan != null and not loan.disabled: loan.pressed.emit()
	check(int(game.state.players[0].loan) == 10000 and int(game.state.players[0].cash) == before_cash + 10000, "actual loan button submits existing loan action")
	check(Game.validate_save(game.to_dict()).get("ok", false), "UI loan remains saveable")
	ui.queue_free()
	print("News bank UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
