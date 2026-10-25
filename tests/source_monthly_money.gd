extends "res://tests/source_monthly_panel.gd"
const ReportPanel = preload("res://game/ui/source_monthly_panel.gd")
const Core = preload("res://game/core/game_state.gd")
const CompanyFixture = preload("res://tests/fixtures/company_fixture.gd")
const OriginalFixture = preload("res://tests/fixtures/original_map_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")
const LIMIT := 1000000000000

func _run() -> void:
	var panel := ReportPanel.new()
	root.add_child(panel)
	panel.set_auto_advance_seconds(0)
	panel.continued.connect(_on_continued)
	panel.set_view_model(_dividend_model())
	expect(panel.is_model_valid() and panel.is_open(), "baseline monetary fixture is a valid real dividend panel")
	for field in ["monthly_profit", "payout", "total", "deposit_before", "interest"]:
		var low := -LIMIT * 12 - 1 if field == "total" else -1 if field in ["deposit_before", "interest"] else -LIMIT - 1
		for value in [low, LIMIT + 1]:
			var model := _interest_model() if field in ["deposit_before", "interest"] else _dividend_model()
			if field == "monthly_profit": model.companies[0].monthly_profit = value
			elif field == "payout": model.companies[0].payouts[0] = value
			else: model.players[0][field] = value
			panel.set_view_model(model)
			expect(not panel.is_model_valid() and not panel.is_open(), "%s rejects out-of-contract amount %d" % [field,value])
			expect(not panel.continue_report(), "%s unavailable model cannot acknowledge as a valid report" % field)
	var upper := _interest_model()
	upper.players[0].deposit_before = LIMIT
	upper.players[0].interest = LIMIT
	panel.set_view_model(upper)
	expect(panel.is_model_valid(), "nonnegative account upper endpoints remain accepted")
	var signed := _dividend_model()
	signed.companies[0].monthly_profit = -LIMIT
	signed.companies[0].payouts[0] = -LIMIT
	signed.players[0].total = -LIMIT * 12
	panel.set_view_model(signed)
	expect(panel.is_model_valid(), "aggregate loss lower endpoint is not reduced to a single-company limit")
	signed.companies[0].monthly_profit = LIMIT
	signed.companies[0].payouts[0] = LIMIT
	signed.players[0].total = LIMIT
	panel.set_view_model(signed)
	expect(panel.is_model_valid(), "signed per-company and credited-total upper endpoints remain accepted")
	expect(_continued_count == 0, "all rejected models preserve once-only continuation boundary")
	producer_aggregate(panel)
	panel.queue_free()
	await _settle()
	print("Monthly money checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)

func producer_aggregate(panel: Control) -> void:
	# Two legal mapped companies can debit more than one account ceiling. The
	# report must retain that authoritative loss before bankruptcy consumes it.
	var raw: Dictionary = OriginalFixture.make()
	for node in [4,5]:
		raw.nodes[node].type_and_idx = 6000 + node - 3
		raw.nodes[node].event_code = 0
	var loaded: Dictionary = Maps.normalize_map(raw,true)
	expect(loaded.get("ok",false), "two-company producer map normalizes")
	if not loaded.get("ok",false): return
	var definition: Dictionary = loaded.definition
	definition.supports_original_companies = true
	definition.stock_rows = CompanyFixture.stock_rows()
	definition.stock_rows[1].company_id = 2
	definition.stock_rows[1].market_supply = 5000
	definition.companies = []
	for n in range(2):
		var company: Dictionary = CompanyFixture.definition().companies[0].duplicate(true)
		company.id = n+1
		company.stock_index = n
		definition.companies.append(company)
		definition.board[n+4].source_company_id = n+1
		definition.board[n+4].company_node_index = n+4
	var game: Object = Core.new_game_on_board(42,4,definition,{"original_facilities":true,"original_gods":true,"original_companies":true,"start_date":{"year":1998,"month":1,"day":1}})
	expect(game != null, "public factory accepts two-company definition")
	if game == null:return
	game.state.god_objects = []
	game.state.day = 14
	game.state.current_player = 3
	game.state.phase = "await_action"
	for n in range(2):
		game.state.players[0].stocks["s%02d" % (n+1)] = 1
		game.state.companies[n].treasury -= 1
		game.state.companies[n].monthly_profit = -LIMIT
	game._update_company_owners()
	game._sync_state()
	game._set_action_options(3)
	var validation: Dictionary = Core.validate_save(game.to_dict())
	expect(validation.get("ok",false), "aggregate-loss producer is valid before public end_turn: " + str(validation.get("errors",[])))
	if not validation.get("ok",false):return
	expect(game.end_turn().get("ok",false), "public end_turn produces the authoritative aggregate loss")
	var report: Dictionary = {}
	for event in game.state.event_log:
		if event.get("type") == "monthly_statement": report = event.report
	expect(not report.is_empty(), "legal aggregate loss emits the settlement report")
	if report.is_empty():return
	expect(report.players[0].total == -LIMIT*2, "report retains two-company loss exceeding one account ceiling")
	var ledger: String = game.to_json()
	panel.set_view_model(report)
	expect(panel.is_model_valid() and panel.is_open(), "strict presenter accepts the real aggregate-loss payload")
	expect(game.to_json() == ledger, "reading the aggregate report preserves settled ledger and RNG")
