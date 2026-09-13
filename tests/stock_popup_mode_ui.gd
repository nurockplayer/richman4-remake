extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	_expect(ui._stock_popup_description(true).contains("公司市場從銀行存款扣款"), "company market copy names the deposit account")
	_expect(ui._stock_popup_description(false).contains("舊版三股市使用現金"), "legacy market copy names cash trading")
	_expect(not ui._stock_popup_description(false).contains("公司市場從銀行存款扣款"), "legacy market copy does not claim company deposit trading")
	var game := GameState.new_game(61007, 2)
	game.state.phase = "await_action"
	game.state.current_player = 0
	game._set_action_options(0)
	game._sync_state()
	ui.game_state = game
	ui._refresh_from_state()
	ui._on_stocks_pressed()
	_expect(ui.stocks_description_label != null and ui.stocks_description_label.text.contains("舊版三股市使用現金"), "legacy stock popup visibly explains cash trading")
	ui.stocks_popup.hide()
	ui.queue_free()
	await create_timer(0.15).timeout
	print("Stock popup mode copy checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
