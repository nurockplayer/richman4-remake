extends "res://tests/sleep_cards_lifecycle.gd"

# Public movement/payment boundaries for Issue #74. No source assets required.
func _initialize() -> void:
	for fee in [1999, 2000]:
		for accept in [false, true]:
			rent_fee(fee, accept, false)
	rent_fee(1999, true, true)
	facility_fee(1)
	facility_fee(2)
	company_fee(12)
	company_fee(4)
	company_construction()
	god_and_unrelated_debits()
	dream_payment()
	print("Financial fee checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func fee_game(seed_value: int, amount: int = 2000, company_type: int = 12) -> Object:
	var definition: Dictionary = Fixture.definition()
	definition.board[2].rent_by_level = [amount, amount, amount, amount, amount, amount]
	definition.board[2].base_rent = amount
	definition.board[2].rent = amount
	definition.companies[0].company_type = company_type
	definition.companies[0].toll_fee = 2500
	var g: Object = Game.new_game_on_board(seed_value, 4, definition, Fixture.new_game_options())
	expect(g != null, "legal complete financial fixture starts")
	if g == null: return null
	g.state.god_objects = []
	for id in range(4):
		g.set_player_ai(id, false)
		g.state.players[id].position = 1
		g.state.players[id].previous_position = -1
		for held in g.state.players[id].cards.duplicate():
			Inventory.consume_card(g.state.inventory_supply, g.state.players[id].cards, held)
	legal(g, "fresh financial fixture")
	return g

func own_property(g: Object, owner: int) -> void:
	g.state.board[2].owner = owner
	g.state.board[2].building_level = 1
	g.state.players[owner].properties = [2]
	g._update_tile_rent(g.state.board[2])
	g._recalculate_property_values()

func set_funds(g: Object, player_id: int, cash: int) -> void:
	g.state.bank.deposits -= int(g.state.players[player_id].deposit)
	g.state.players[player_id].deposit = 0
	g.state.players[player_id].cash = cash

func land(g: Object, destination: int, start: int, previous: int) -> void:
	turn(g, 0)
	g.state.players[0].position = start
	g.state.players[0].previous_position = previous
	g.state.players[0].turtle_days = 1
	g._set_action_options(0)
	legal(g, "before one-step public landing")
	var rolled: Dictionary = g.roll()
	expect(rolled.get("ok", false), "public one-step roll succeeds")
	if g.state.phase == "await_route":
		expect(g.choose_route(destination).get("ok", false), "public route reaches payment destination")
	expect(int(g.state.players[0].position) == destination, "movement reaches intended fee node")

func pending(g: Object, expected_kind: String) -> Dictionary:
	expect(g.has_method("financial_response"), "financial response API exists")
	if not g.has_method("financial_response"): return {}
	var result: Dictionary = g.call("financial_response")
	expect(result.get("kind", "") == expected_kind and result.get("stage", "") == "free", "expected passive free decision is pending")
	return result

func answer(g: Object, accept: bool) -> bool:
	var result: Dictionary = g.choose_action("respond_finance", {"cancel": not accept})
	expect(result.get("ok", false), "public free response accepted")
	return result.get("ok", false)

func rent_fee(amount: int, accept: bool, insolvent: bool) -> void:
	var g := fee_game(74101, amount)
	if g == null: return
	own_property(g, 1)
	card(g, 0, "免費")
	if insolvent: set_funds(g, 0, 1000)
	var before_cash: int = int(g.state.players[0].cash)
	var before_owner: int = int(g.state.players[1].cash)
	land(g, 2, 1, 0)
	if amount < 2000 and not insolvent:
		expect(not g.state.has("pending_finance"), "below threshold and solvent rent has no free prompt")
		expect(int(g.state.players[0].cash) == before_cash - amount, "below threshold rent pays normally")
		expect(g.state.players[0].cards.has("免費"), "below threshold rent preserves free card")
		legal(g, "normal below-threshold payment")
		return
	var decision := pending(g, "rent")
	expect(int(g.state.players[0].cash) == before_cash and int(g.state.players[1].cash) == before_owner, "eligible rent is unpaid while waiting")
	expect(g.state.players[0].alive, "free response precedes insolvency resolution")
	if decision.is_empty(): return
	expect(int(decision.amount) == amount, "pending rent preserves exact computed fee")
	legal(g, "pending rent")
	var frozen: String = g.to_json()
	for action in ["end_turn", "use_card", "buy_stock", "deposit"]:
		expect(not g.choose_action(action, {}).get("ok", false), "ordinary action blocked during payment decision")
		expect(g.to_json() == frozen, "blocked payment action is atomic")
	var mirror: Object = Game.from_dict(JSON.parse_string(frozen))
	if not answer(g, accept): return
	expect(not g.state.has("pending_finance"), "answer clears optional payment metadata")
	expect(int(g.state.players[0].cash) == before_cash - (0 if accept else amount), "rent response settles selected outcome")
	expect(int(g.state.players[1].cash) == before_owner + (0 if accept else amount), "rent owner receives only actual payment")
	expect(g.state.players[0].cards.has("免費") == not accept, "only accepting consumes free card")
	legal(g, "answered rent")
	if mirror != null:
		mirror.choose_action("respond_finance", {"cancel": not accept})
		expect(g.to_json() == mirror.to_json(), "pending rent replay has exact full JSON")

func facility_fee(facility_type: int) -> void:
	var g := fee_game(74102)
	if g == null: return
	g._update_facility_records(1, {"owner": 1, "building_level": 1, "facility_type": facility_type})
	g.state.players[1].properties = [1]
	g._recalculate_property_values()
	card(g, 0, "免費")
	set_funds(g, 0, 0)
	land(g, 1, 0, -1)
	if facility_type == 1:
		expect(not g.state.has("pending_finance"), "hotel skips free even above available funds")
		expect(not g.state.players[0].alive, "hotel exclusion still resolves unpaid fee bankruptcy")
		legal(g, "hotel excluded payment")
		return
	var decision := pending(g, "facility")
	expect(g.state.players[0].alive, "other facility offers free before bankruptcy")
	if decision.is_empty(): return
	legal(g, "facility pending")
	if not answer(g, true): return
	expect(g.state.players[0].alive and int(g.state.players[0].cash) == 0, "free preserves insolvent facility visitor")
	legal(g, "facility waived")

func own_company(g: Object) -> void:
	turn(g, 1)
	expect(g.choose_action("buy_stock", {"symbol": "s01", "quantity": 1}).get("ok", false), "company ownership uses public stock purchase")
	expect(int(g.state.companies[0].owner) == 1, "counterparty owns service company")
	turn(g, 0)

func company_fee(company_type: int) -> void:
	var g := fee_game(74103, 2000, company_type)
	if g == null: return
	own_company(g)
	card(g, 0, "免費")
	var before_cash: int = int(g.state.players[0].cash)
	land(g, 5, 4, 2)
	var decision := pending(g, "company")
	expect(int(g.state.companies[0].monthly_profit) == 0 and int(g.state.players[0].cash) == before_cash, "company payment waits without crediting earnings")
	if decision.is_empty(): return
	if company_type == 4:
		expect(int(g.state.players[0].insurance_status) > 0, "insurance service already granted while fee awaits")
	legal(g, "company pending")
	if not answer(g, true): return
	expect(int(g.state.companies[0].monthly_profit) == 0 and int(g.state.companies[0].cumulative_profit) == 0, "waived service never credits company profits")
	if company_type == 4:
		expect(int(g.state.players[0].insurance_status) > 0, "free does not undo granted insurance")
	legal(g, "company waived")

func company_construction() -> void:
	var g := fee_game(74104, 2000, 11)
	if g == null: return
	own_company(g)
	own_property(g, 0)
	card(g, 0, "免費")
	set_funds(g, 0, 999)
	land(g, 5, 4, 2)
	expect(int(g.state.company_service_pending) == 1, "construction service waits for target first")
	expect(g.choose_action("company_upgrade", {"tile_id": 2}).get("ok", false), "public construction resolves its target")
	var decision := pending(g, "company")
	expect(int(g.state.board[2].building_level) == 2, "construction applied before payment reaction")
	if decision.is_empty(): return
	legal(g, "construction fee pending")
	if not answer(g, true): return
	expect(int(g.state.board[2].building_level) == 2 and g.state.players[0].alive, "free retains construction and prevents insolvency")
	expect(int(g.state.companies[0].monthly_profit) == 0, "free construction adds no company profit")
	legal(g, "construction waived")

func god_and_unrelated_debits() -> void:
	var g := fee_game(74105, 3000)
	if g == null: return
	own_property(g, 1)
	card(g, 0, "免費")
	g._spawn_god(2)
	expect(g._attach_god(0, 2), "attach wealth god through existing status primitive")
	var cash_before: int = int(g.state.players[0].cash)
	land(g, 2, 1, 0)
	expect(not g.state.has("pending_finance") and g.state.players[0].cards.has("免費"), "god waiver precedes passive free choice")
	expect(int(g.state.players[0].cash) == cash_before, "god rent waiver still applies")
	g._charge_amount(0, 3000, -1, "event")
	expect(int(g.state.players[0].cash) == cash_before - 3000, "unrelated event charge cannot use free")
	g._charge_amount(0, 3000, -1, "god_poor")
	expect(int(g.state.players[0].cash) == cash_before - 6000, "god redistribution cannot use free")
	expect(not g.state.has("pending_finance") and g.state.players[0].cards.has("免費"), "unrelated charges preserve unused card")
	legal(g, "unrelated charge boundaries")

func dream_payment() -> void:
	var g := fee_game(74106)
	if g == null: return
	own_property(g, 1)
	card(g, 0, "免費")
	card(g, 0, "夢遊")
	turn(g, 0)
	if not cast(g, "夢遊", 0): return
	g.state.players[0].position = 1
	g.state.players[0].previous_position = 0
	g.state.players[0].turtle_days = 1
	legal(g, "human dream payer")
	var result := driver(g)
	expect(result.get("ok", false) and result.get("awaiting_response", false) and not result.get("completed", true), "dream driver pauses for passive human response")
	var decision := pending(g, "rent")
	if decision.is_empty(): return
	expect(int(g.state.current_player) == 0 and int(g.state.players[0].dream_days) == 4, "waiting dream has not ticked or handed off")
	expect(g.state.players[0].is_human and not g.state.players[0].is_ai, "waiting dream preserves human identity")
	legal(g, "dream pending free")
	if not answer(g, true): return
	result = driver(g)
	expect(result.get("ok", false) and result.get("completed", false), "answered dream resumes its restricted driver")
	expect(int(g.state.current_player) == 1 and int(g.state.players[0].dream_days) == 3, "answered dream ticks and hands off exactly once")
	legal(g, "dream payment continuation")
