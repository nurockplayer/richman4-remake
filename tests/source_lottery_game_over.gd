extends "res://tests/source_lottery_core.gd"
const Flow = preload("res://game/core/lottery_flow.gd")


func _initialize() -> void:
	_test_no_draw_after_winner()
	_test_ai_switch_blocked_while_pending()
	print("Lottery game over checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _test_no_draw_after_winner() -> void:
	var game = fresh()
	game.state.day = 2
	game._sync_state()
	game.state.lottery_tickets[0] = 1
	game.state.jackpot = 7000
	game.state.phase = "game_over"
	game.state.action_options = []
	var before: Dictionary = game.to_dict()
	Flow.settle_day(game)
	expect(game.to_dict() == before, "no payout, ticket or RNG change after game over")
	expect(int(game.state.lottery_draw_day) == 0, "settled day identity is untouched")


func _test_ai_switch_blocked_while_pending() -> void:
	var game = fresh()
	enter(game)
	expect(game.state.phase == "await_lottery" and bool(game.state.players[0].is_human), "human actor holds the pending lottery")
	var before: Dictionary = game.to_dict()
	expect(not game.set_player_ai(0, true), "pending lottery rejects the public AI switch")
	expect(game.to_dict() == before, "rejected AI switch does not mutate")
	game.leave_lottery()
	expect(game.set_player_ai(0, true), "closed lottery permits the public AI switch")
