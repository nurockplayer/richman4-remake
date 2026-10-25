extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")
const Loans = preload("res://game/core/source_loans.gd")
const Statements = preload("res://game/core/monthly_statements.gd")
const Maps = preload("res://game/content/original_maps.gd")
const MapFixture = preload("res://tests/fixtures/original_map_fixture.gd")
var checks := 0
var failures := 0
var setup_failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)

func make_game(day: int, count: int = 4) -> Object:
	var game: Object = Game.new_game_on_board(42, count, Fixture.definition(), {
		"original_facilities": true, "original_gods": true, "original_companies": true,
		"start_date": {"year": 1998, "month": 1, "day": 1}})
	game.state.god_objects = []
	game.state.day = day
	game.state.current_player = count - 1
	game.state.phase = "await_action"
	game._sync_state()
	game._set_action_options(count - 1)
	return game

func qualify(game: Object, label: String) -> bool:
	game._sync_state()
	game._set_action_options(int(game.state.current_player))
	var validation: Dictionary = Game.validate_save(game.to_dict())
	var ok := bool(validation.get("ok", false))
	expect(ok, label + " valid before action: " + str(validation.get("errors", [])))
	if not ok: setup_failures += 1
	return ok

func reports(game: Object) -> Array:
	var result: Array = []
	for event in game.state.event_log:
		if event.get("type", "") == "monthly_statement": result.append(event.get("report", {}))
	return result

func hold(game: Object, player_id: int, quantity: int) -> void:
	game.state.players[player_id].stocks.s01 += quantity
	game.state.companies[0].treasury -= quantity
	game._update_company_owners()

func balances(game: Object, values: Array) -> void:
	game.state.bank.deposits = 0
	for index in range(values.size()):
		game.state.players[index].deposit = values[index]
		game.state.bank.deposits += int(values[index])

func roundtrip(game: Object, label: String) -> void:
	var text: String = game.to_json()
	var copy: Object = Game.from_dict(JSON.parse_string(text))
	expect(copy != null, label + " JSON restores")
	if copy == null: return
	expect(copy.to_json() == text, label + " entire ledger/RNG/report JSON preserved")
	expect(reports(copy) == reports(game), label + " report payload survives JSON")
	var n := reports(copy).size()
	copy.get_snapshot()
	copy.get_snapshot()
	expect(reports(copy).size() == n and copy.to_json() == text, label + " reading does not settle again")

func dividends() -> void:
	var game := make_game(14)
	hold(game, 0, 1)
	hold(game, 1, 2)
	game.state.companies[0].monthly_profit = 101
	game.state.companies[0].cumulative_profit = 500
	if not qualify(game, "day14 positive dividend"): return
	var old0: int = game.state.players[0].deposit
	var old1: int = game.state.players[1].deposit
	expect(game.end_turn().get("ok", false), "public end_turn reaches day15")
	var found := reports(game)
	expect(found.size() == 1, "day15 emits one authoritative dividend report")
	expect(game.state.players[0].deposit == old0 + 33 and game.state.players[1].deposit == old1 + 67, "existing dividend ledger uses actual truncation")
	expect(game.state.companies[0].monthly_profit == 0 and game.state.companies[0].cumulative_profit == 500, "source monthly reset remains intact")
	if found.size() == 1:
		var report: Dictionary = found[0]
		expect(report.get("kind") == "dividend" and report.get("edition") == "Game", "dividend edition and kind come from source state")
		expect(report.get("date") == {"year": 1998, "month": 1, "day": 15}, "report binds actual settlement date")
		var players: Array = report.get("players", [])
		expect(players.size() == 4, "all four live players retained")
		if players.size() == 4:
			expect(players[0].get("total") == 33 and players[1].get("total") == 67 and players[2].get("total") == 0, "report totals are exact credited payouts")
			expect(players[0].get("name") == game.state.players[0].name and players[0].get("character_id") == 0, "report retains authoritative player identity")
		var companies: Array = report.get("companies", [])
		expect(companies.size() == 1, "only mapped company appears")
		if companies.size() == 1:
			expect(companies[0].get("monthly_profit") == 101 and companies[0].get("payouts") == [33, 67, 0, 0], "report retains pre-reset profit and each actual payment")
			var snapshot: Dictionary = game.get_snapshot()
			var original: String = game.to_json()
			for event in snapshot.event_log:
				if event.get("type", "") == "monthly_statement": event.report.companies[0].payouts[0] = 999
			expect(game.to_json() == original, "caller-owned read snapshot remains independent")
	roundtrip(game, "positive report")
	game = make_game(14, 2)
	game.state.companies[0].monthly_profit = 101
	if not qualify(game, "unheld company"): return
	game.end_turn()
	found = reports(game)
	expect(found.size() == 1, "unheld company still has a source table")
	if found.size() == 1:
		var companies: Array = found[0].get("companies", [])
		expect(companies.size() == 1 and companies[0].get("monthly_profit") == 101 and companies[0].get("payouts") == [0, 0], "unheld report has real profit and zero distributions")
	expect(game.state.companies[0].monthly_profit == 101, "displaying an unheld company does not clear its pool")
	game = make_game(14)
	hold(game, 0, 1)
	balances(game, [70, 100, 100, 100])
	game.state.players[0].cash = 100
	game.state.companies[0].monthly_profit = -120
	if not qualify(game, "negative dividend"): return
	game.end_turn()
	found = reports(game)
	expect(found.size() == 1, "negative dividend produces a report")
	if found.size() == 1: expect(found[0].players[0].get("total") == -120 and found[0].companies[0].get("payouts") == [-120, 0, 0, 0], "negative payouts keep their sign")
	expect(game.state.players[0].deposit == 0 and game.state.players[0].cash == 50, "report does not change source loss allocation")
	roundtrip(game, "negative report")
	game = make_game(14)
	hold(game, 0, 1)
	balances(game, [1000000000000, 0, 0, 0])
	game.state.companies[0].monthly_profit = 1
	if not qualify(game, "dividend overflow"): return
	game.end_turn()
	expect(reports(game).is_empty(), "rejected settlement must not publish a successful report")
	game = make_game(13)
	if not qualify(game, "non-settlement date"): return
	game.end_turn()
	expect(reports(game).is_empty(), "ordinary day has no monthly report")

func interest() -> void:
	var game := make_game(31)
	balances(game, [59333, 200, 0, 9])
	Loans.take(game.state.players[1], game.state.bank, 100, 31, int(game.state.weekday))
	if not qualify(game, "month-end mixed accounts"): return
	var before: Dictionary = game.to_dict()
	expect(game.end_turn().get("ok", false), "public end_turn crosses real January boundary")
	var found := reports(game)
	expect(found.size() == 1, "one bank-interest report includes eligible and excluded accounts")
	if found.size() == 1:
		var report: Dictionary = found[0]
		expect(report.get("kind") == "interest" and report.get("date") == {"year": 1998, "month": 2, "day": 1}, "interest report is bound to the actual month boundary")
		var players: Array = report.get("players", [])
		expect(players.size() == 4, "zero-deposit and loan accounts remain visible")
		if players.size() == 4:
			for id in range(4): expect(players[id].get("deposit_before") == before.players[id].deposit, "pre-interest deposit retained for player %d" % id)
			expect(players[0].get("interest") == 5933 and players[0].get("loan_active") == false, "report carries actual credited interest")
			expect(players[1].get("interest") == 0 and players[1].get("loan_active") == true, "loan exclusion is an explicit marker")
			expect(players[2].get("interest") == 0 and players[3].get("interest") == 0, "zero and sub-unit interest are explicit")
	expect(game.state.players[0].deposit == 65266 and game.state.players[1].deposit == 300, "existing deposit and loan interest rules unchanged")
	var old: String = game.to_json()
	game._apply_month_boundary()
	expect(game.to_json() == old, "repeat month boundary neither pays nor reports twice")
	roundtrip(game, "interest report")

func setup_less_game(day: int) -> Object:
	# new_game_on_board with empty options takes the plain _initialize_graph
	# path, so players come from _build_players() and carry no setup identity.
	var normalized: Dictionary = Maps.normalize_map(MapFixture.make())
	var definition: Dictionary = normalized.get("definition", {})
	if definition.is_empty(): return null
	var game: Object = Game.new_game_on_board(42, 4, definition)
	if game == null: return null
	game.state.day = day
	game.state.current_player = 3
	game.state.phase = "await_action"
	game._sync_state()
	game._set_action_options(3)
	return game


func setup_less_statements() -> void:
	# The report builder is presentation only: a game without the setup path
	# must settle exactly as before and still leave a report to show.
	var raw := {
		"map_source": {"edition": "Game"},
		"date": {"year": 1998, "month": 1, "day": 15},
		"players": [{"id": 0, "name": "玩家 1", "alive": true}, {"id": 1, "name": "玩家 2", "alive": true}],
	}
	var built: Dictionary = Statements.dividend(raw, [
		{"company_id": 1, "name": "測試企業", "monthly_profit": 50, "stock_index": 0, "payouts": [25, 0]},
	], {0: 25})
	expect(built.get("players", []).size() == 2, "identity-less dividend payload still builds")
	if built.get("players", []).size() == 2:
		expect(built.players[0].get("character_id") == -1 and built.players[0].get("name") == "玩家 1", "absent source identity becomes an explicit marker")
		expect(built.players[0].get("total") == 25, "identity-less report keeps the credited total")
	expect(Statements.begin(raw, "interest").get("players", []).size() == 2, "identity-less interest payload builds without ledger fields")

	var game := setup_less_game(14)
	expect(game != null, "plain original-map game constructs")
	if game == null: return
	expect(str(game.state.map_source.get("edition", "")) == "Game", "plain original-map game keeps its source edition")
	expect(not game.state.players[0].has("character_id"), "plain players really have no setup identity")
	if not qualify(game, "setup-less day14"): return
	expect(game.end_turn().get("ok", false), "setup-less game reaches day 15")
	expect(reports(game).is_empty(), "a game without the company layer has no dividend report")

	game = setup_less_game(29)
	if game == null: return
	# A migrated pre-setup save can carry a calendar date; month-end settlement
	# then asks the report builder for identities the players never had.
	game.state["date"] = {"year": 1998, "month": 1, "day": 30}
	balances(game, [59333, 200, 0, 9])
	if not qualify(game, "setup-less month end"): return
	expect(game.end_turn().get("ok", false), "setup-less game crosses the month boundary")
	var found := reports(game)
	expect(found.size() == 1, "setup-less settlement records its interest report")
	if found.size() == 1:
		var players: Array = found[0].get("players", [])
		expect(players.size() == 4, "setup-less report keeps every live player")
		if players.size() == 4:
			expect(players[0].get("name") == game.state.players[0].name and players[0].get("character_id") == -1, "setup-less identity is marked instead of aborting the report")
			expect(players[0].get("deposit_before") == 59333 and players[0].get("interest") == 5933, "setup-less report keeps the exact credited amounts")
	expect(game.state.players[0].deposit == 65266 and game.state.players[1].deposit == 220 and game.state.players[3].deposit == 9, "setup-less settlement amounts are unchanged")
	roundtrip(game, "setup-less report")


func _initialize() -> void:
	dividends()
	interest()
	setup_less_statements()
	print("Monthly statement checks: %d, failures: %d, setup_failures: %d" % [checks, failures, setup_failures])
	quit(1 if failures else 0)
