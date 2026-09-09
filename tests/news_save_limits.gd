extends SceneTree
const Fixture = preload("res://tests/fixtures/news_fixture.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func arm(game: Object, id: int) -> void:
	var order: Array = [id]
	for candidate in range(36):
		if candidate != id: order.append(candidate)
	game.state.news = {"order": order, "cursor": 0, "draw_count": 0, "last": {}}

func verify(game: Object, label: String) -> void:
	check(game.validate_save(game.to_dict()).get("ok", false), label + " validates")
	var restored: Object = game.from_dict(JSON.parse_string(game.to_json()))
	check(restored != null and restored.to_json() == game.to_json(), label + " JSON round-trip")

func _initialize() -> void:
	for monthly in [500000000000, 600000000000]:
		var game: Object = Fixture.new_game(580035)
		for company in game.state.companies:
			company.monthly_profit = 0
		game.state.companies[0].monthly_profit = monthly
		game.state.companies[0].cumulative_profit = -500000000000
		arm(game, 35)
		verify(game, "company input")
		var companies: Array = game.state.companies.duplicate(true)
		var market: Dictionary = game.state.market.duplicate(true)
		game._graph_visit_tile(0, game.state.board.back(), true)
		if monthly == 600000000000:
			check(game.state.companies == companies, "monthly overflow preserves every company")
			check(game.state.market == market, "monthly overflow preserves linked stock")
		else:
			check(int(game.state.companies[0].monthly_profit) == 1000000000000, "monthly exact limit succeeds")
			check(int(game.state.companies[0].cumulative_profit) == 500000000000, "monthly exact limit adds doubled earnings")
		verify(game, "company result")
	for room in [0, 10, 20]:
		var game: Object = Fixture.new_game(580023)
		for player in game.state.players:
			player.deposit = 0
			player.loan = 0
		game.state.players[0].deposit = 100
		game.state.players[1].deposit = 100
		game.state.players[2].deposit = 999999999800 - room
		game.state.players[2].loan = 1
		game.state.bank.deposits = 1000000000000 - room
		game.state.bank.loans = 1
		arm(game, 23)
		verify(game, "interest input")
		var bank_cash: int = int(game.state.bank.cash)
		game._graph_visit_tile(0, game.state.board.back(), true)
		check(int(game.state.players[0].deposit) == (110 if room >= 10 else 100), "first interest preflights aggregate capacity")
		check(int(game.state.players[1].deposit) == (110 if room >= 20 else 100), "second interest uses updated aggregate capacity")
		check(int(game.state.players[2].deposit) == 999999999800 - room, "loan holder receives no interest")
		check(int(game.state.bank.deposits) == 1000000000000, "aggregate liability never exceeds limit")
		check(int(game.state.bank.cash) == maxi(0, bank_cash - room), "bank pays only applied interest")
		verify(game, "interest result")
	print("News save limit checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
