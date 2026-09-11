extends "res://tests/source_lottery_core.gd"
const Flow = preload("res://game/core/lottery_flow.gd")
func _initialize() -> void:
	_test_day_order_and_identity()
	_test_empty_retention_and_bounds()
	_test_ai_and_bankruptcy()
	print("Lottery settlement checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
func next_day(game: Object) -> void:
	game.state.god_objects = []
	game.state.current_player = 3
	game.state.phase = "await_action"
	game._set_action_options(3)
	expect(game.end_turn().ok, "day14 public end-turn succeeds")
func _test_day_order_and_identity() -> void:
	var game = fresh()
	for i in range(11): game.state.lottery_tickets[i] = 1
	game.state.lottery_tickets[20] = 2
	game.state.jackpot = 12345
	var old_cash: Array = []
	for player in game.state.players: old_cash.append(int(player.cash))
	next_day(game)
	expect(game.state.date.day == 15 and game.state.lottery_draw_day == 1, "date14 advances to15 exactly once")
	var dividend_index := -1
	var draw_index := -1
	var turn_index := -1
	var report: Dictionary = {}
	for i in range(game.state.event_log.size()):
		var event: Dictionary = game.state.event_log[i]
		if event.type == "monthly_statement" and event.report.kind == "dividend": dividend_index = i
		if event.type == "lottery_draw":
			draw_index = i
			report = event.report
		if event.type == "turn_started": turn_index = i
	expect(dividend_index >= 0 and draw_index > dividend_index and turn_index > draw_index, "source dividend then lottery then actor ordering")
	expect(not report.is_empty() and report.winner_id >= 0, "concentrated tickets guarantee sold-number winner")
	if not report.is_empty():
		expect(game.state.players[int(report.winner_id)].cash == old_cash[int(report.winner_id)] + 12345, "whole shared pool paid as cash")
		expect(report.jackpot == 12345 and report.jackpot_after == 0 and report.tickets.count(0) == 24, "detached report retains pre-draw source display")
	expect(game.state.jackpot == 0 and game.state.lottery_tickets.count(0) == 36, "winner clears pool and every ticket")
	var saved: Dictionary = game.to_dict()
	Flow.settle_day(game)
	expect(game.to_dict() == saved, "same draw identity cannot pay or consume RNG again")
	var loaded = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(loaded != null, "settled save validates")
	if loaded != null:
		Flow.settle_day(loaded)
		expect(loaded.to_dict() == saved, "loaded identity cannot replay historical draw")
	var initial = Game.new_game_on_board(42, 4, Fixture.definition(), {"original_facilities":true,"original_gods":true,"original_companies":true,"start_date":{"year":1998,"month":1,"day":15}})
	initial.state.lottery_tickets[0] = 1
	initial.state.jackpot = 1000
	var start: Dictionary = initial.to_dict()
	Flow.settle_day(initial)
	expect(initial.to_dict() == start, "starting on15 never draws")
func _test_empty_retention_and_bounds() -> void:
	var empty = fresh()
	empty.state.day = 2
	empty._sync_state()
	var rng: String = empty.state.rng_state_text
	Flow.settle_day(empty)
	expect(empty.state.lottery_draw_day == 1 and str(empty._rng.state) == rng, "empty draw advances identity without RNG")
	expect(empty.state.event_log.filter(func(e: Dictionary) -> bool: return e.type == "lottery_draw").is_empty(), "empty draw has no presentation event")
	var retained := false
	for seed_value in range(1, 20):
		var game = fresh(seed_value)
		game.state.day = 2
		game._sync_state()
		game.state.lottery_tickets[0] = 1
		game.state.jackpot = 7000
		Flow.settle_day(game)
		if game.state.lottery_tickets[0] == 1:
			expect(game.state.jackpot == 7000 and game.state.lottery_tickets.count(0) == 35, "no winner retains all tickets and shared pool")
			retained = true
			break
	expect(retained, "bounded deterministic seed produces no-winner state")
	var capped = fresh()
	capped.state.day = 2
	capped._sync_state()
	capped.state.lottery_tickets[0] = 1
	capped.state.players[0].cash = 1000000000000
	capped.state.jackpot = 1
	rng = str(capped._rng.state)
	Flow.settle_day(capped)
	expect(capped.state.players[0].cash == 1000000000000 and capped.state.jackpot == 1 and str(capped._rng.state) == rng, "unrepresentable prize is retained without RNG")
	for value in [-1, 2, 0.5, true, {}, null]:
		var bad: Dictionary = capped.to_dict()
		bad.lottery_draw_day = value
		expect(not Game.validate_save(bad).ok, "invalid future/noninteger draw identity rejected")
func _test_ai_and_bankruptcy() -> void:
	for cash in [1000, 1001]:
		var game = fresh()
		game.state.players[0].cash = cash
		game.state.players[0].is_human = false
		game.state.players[0].is_ai = true
		enter(game)
		var rng := str(game._rng.state)
		Flow.ai_turn(game)
		expect(game.state.phase == "await_action", "AI closes lottery encounter")
		expect(game.state.jackpot == (1000 if cash == 1001 else 0), "AI uses strict cash threshold")
		if cash == 1000: expect(str(game._rng.state) == rng, "AI refusal consumes no RNG")
	var game = fresh()
	game.state.lottery_tickets[0] = 1
	game.state.lottery_tickets[1] = 2
	game._declare_bankruptcy(0, -1, 1000, "lottery_test")
	expect(game.state.lottery_tickets[0] == 0 and game.state.lottery_tickets[1] == 2, "bankruptcy clears only bankrupt owner tickets")
