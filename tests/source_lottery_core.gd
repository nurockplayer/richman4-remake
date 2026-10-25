extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")
var checks := 0
var failures := 0
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fresh(seed_value: int = 42) -> Object:
	var definition := Fixture.definition()
	definition.board[3].kind = "lottery"
	definition.board[3].type_and_idx = 0
	definition.board[3].event_code = 9
	definition.board[3].source_status_bits = 9
	return Game.new_game_on_board(seed_value, 4, definition, {"original_facilities": true, "original_gods": true, "original_companies": true, "start_date": {"year": 1998, "month": 1, "day": 14}})
func enter(game: Object) -> void:
	game.state.god_objects = []
	game.state.players[0].position = 3
	game._resolve_landing(0, false)
func _initialize() -> void:
	for cash in [999, 1000, 1001]:
		var game = fresh()
		expect(game != null, "lottery fixture constructs")
		if game == null: continue
		game.state.players[0].cash = cash
		enter(game)
		expect(game.state.phase == "await_lottery", "lottery landing owns action phase")
		var before: Dictionary = game.to_dict()
		expect(not game.end_turn().ok, "lottery excludes end turn")
		expect(game.to_dict() == before, "rejected end turn does not mutate")
		var result: Dictionary = game.purchase_lottery(1)
		expect(result.ok == (cash >= 1000), "human exact cash threshold")
		if cash >= 1000:
			expect(game.state.players[0].cash == cash - 1000 and game.state.jackpot == 1000 and game.state.lottery_tickets[0] == 1, "purchase transfers exact cash to shared pool")
			var purchased: Dictionary = game.to_dict()
			expect(not game.purchase_lottery(2).ok and game.to_dict() == purchased, "one purchase per encounter")
		else:
			expect(game.to_dict() == before, "insufficient cash inert")
			game.leave_lottery()
		var saved: Dictionary = game.to_dict()
		var loaded = Game.from_dict(JSON.parse_string(JSON.stringify(saved)))
		expect(loaded != null, "lottery save JSON roundtrip valid: " + str(Game.validate_save(saved)))
		if loaded != null: expect(loaded.to_dict() == saved, "lottery continuation equality")
	var game = fresh()
	enter(game)
	var pending: Dictionary = game.to_dict()
	expect(Game.from_dict(pending) != null, "pending encounter can resume")
	for number in [0, 37, -1]:
		expect(not game.purchase_lottery(number).ok and game.to_dict() == pending, "out of range purchase inert")
	game.leave_lottery()
	expect(game.state.jackpot == 0 and game.state.lottery_tickets.count(0) == 36, "cancel has no financial effect")
	for bad in [[], [1], null, true]:
		var invalid: Dictionary = game.to_dict()
		invalid.lottery_tickets = bad
		expect(not Game.validate_save(invalid).ok and Game.from_dict(invalid) == null, "invalid ticket shape rejected")
	print("Lottery core checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
