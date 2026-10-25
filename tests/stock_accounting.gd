extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Market = preload("res://game/core/original_stock_market.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")

var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func source_float(value: float) -> float:
	return float(PackedFloat32Array([value])[0])

func make_game() -> Object:
	var game = Game.new_game_on_board(42, 4, Fixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	expect(game != null, "valid source company fixture creates a game")
	if game == null:
		return null
	game.state.phase = "await_action"
	game.state.current_player = 0
	game.state.day = 1
	game.state.weekday = 1
	# The stock tests do not exercise god placement. Clear the random source
	# objects so fixture validation is independent of their spawn locations.
	game.state.god_objects = []
	game._sync_state()
	game._set_action_options(0)
	return game

func stock_cost(game: Object, player_id: int = 0) -> Variant:
	var player: Dictionary = game.state.players[player_id]
	var costs: Variant = player.get("stock_average_costs", null)
	if typeof(costs) != TYPE_DICTIONARY:
		return null
	return costs.get("s01", null)

func cost_equals(game: Object, expected: float) -> bool:
	var value: Variant = stock_cost(game)
	return value != null and is_equal_approx(float(value), expected)

func cost_is_zero(game: Object) -> bool:
	return cost_equals(game, 0.0)

func populated_costs(value: Variant = 0.0) -> Dictionary:
	var costs: Dictionary = {}
	for stock_symbol in Market.symbols():
		costs[stock_symbol] = value
	return costs

func set_bank_deposits(game: Object) -> void:
	var total := 0
	for player in game.state.players:
		total += int(player.get("deposit", 0))
	game.state.bank.deposits = total

func recompute_market_index(game: Object) -> void:
	var total_cents := 0
	for price in game.state.market.prices.values():
		total_cents += roundi(float(price) * 100.0)
	game.state.market.index = floori(float(total_cents) / 10.0)

func set_quote(game: Object, previous: float, current: float) -> void:
	var row: Dictionary = game.state.market.rows.s01
	row.previous_price = previous
	row.price = current
	game.state.market.prices.s01 = current
	var history: Array = game.state.market.history.s01
	history[history.size() - 1] = current
	recompute_market_index(game)
	game._sync_state()
	game._set_action_options(0)

func prepare_market(game: Object, previous: float, current: float, deposit: int = 100000, turn_supply: int = 1000) -> void:
	var player: Dictionary = game.state.players[0]
	player.deposit = deposit
	var row: Dictionary = game.state.market.rows.s01
	row.turn_supply = turn_supply
	set_quote(game, previous, current)
	set_bank_deposits(game)
	game._set_action_options(0)

func valid_save(game: Object, label: String) -> void:
	var result: Dictionary = Game.validate_save(game.to_dict())
	expect(bool(result.get("ok", false)), label + " valid save " + str(result.get("errors", [])))

func expect_reject_atomic(game: Object, action: String, params: Dictionary, label: String) -> void:
	game._sync_state()
	game._set_action_options(0)
	var before: String = game.to_json()
	var rng_before: int = int(game.state.rng_state)
	var result: Dictionary = game.choose_action(action, params)
	expect(not bool(result.get("ok", false)), label + " rejects")
	expect(game.to_json() == before, label + " leaves state and events unchanged")
	expect(int(game.state.rng_state) == rng_before, label + " leaves RNG unchanged")

func test_market_average_and_roundtrip() -> void:
	var game = make_game()
	if game == null:
		return
	expect(typeof(stock_cost(game)) == TYPE_FLOAT and cost_is_zero(game), "new game zero holdings have known zero average")
	valid_save(game, "new game")
	prepare_market(game, 100.0, 100.0)
	var first: Dictionary = game.choose_action("buy_stock", {"symbol": "s01", "quantity": 3})
	expect(bool(first.get("ok", false)), "market first buy succeeds")
	expect(cost_equals(game, source_float(100.0)), "first market buy records source float32 average")
	set_quote(game, 100.0, 101.23)
	var second: Dictionary = game.choose_action("buy_stock", {"symbol": "s01", "quantity": 2})
	expect(bool(second.get("ok", false)), "market repeated buy succeeds")
	var expected_average := source_float(float(300 + Market.quote(101.23, 2)) / 5.0)
	expect(cost_equals(game, expected_average), "market repeated buy uses truncated old total plus integer amount")
	valid_save(game, "weighted market buys")
	var restored = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null, "weighted market save loads")
	if restored != null:
		expect(stock_cost(restored) != null and cost_equals(restored, float(stock_cost(game))), "weighted market average survives JSON continuation")
	set_quote(game, 101.23, 103.0)
	var partial: Dictionary = game.choose_action("sell_stock", {"symbol": "s01", "quantity": 2})
	expect(bool(partial.get("ok", false)), "partial market sale succeeds")
	expect(cost_equals(game, expected_average), "partial sale preserves average cost")
	set_quote(game, 103.0, 97.0)
	var full: Dictionary = game.choose_action("sell_stock", {"symbol": "s01", "quantity": 3})
	expect(bool(full.get("ok", false)), "full market sale succeeds")
	expect(cost_is_zero(game), "full sale clears average cost")
	prepare_market(game, 97.0, 97.0)
	var rebuy: Dictionary = game.choose_action("buy_stock", {"symbol": "s01", "quantity": 1})
	expect(bool(rebuy.get("ok", false)), "rebuy after closure succeeds")
	expect(cost_equals(game, source_float(97.0)), "rebuy records a new known average")
	valid_save(game, "market close and rebuy")

func test_company_issue_uses_same_accounting() -> void:
	var game = make_game()
	if game == null:
		return
	var player: Dictionary = game.state.players[0]
	player.position = 5
	player.cash = 100000
	player.deposit = 0
	set_bank_deposits(game)
	game._set_action_options(0)
	var first: Dictionary = game.choose_action("buy_company", {"quantity": 3})
	expect(bool(first.get("ok", false)), "company face-price purchase succeeds")
	expect(cost_equals(game, source_float(40.0)), "company face-price purchase records average")
	var second: Dictionary = game.choose_action("buy_company", {"quantity": 2})
	expect(bool(second.get("ok", false)), "repeated company face-price purchase succeeds")
	expect(cost_equals(game, source_float(40.0)), "company purchase joins weighted accounting path")
	valid_save(game, "company face-price purchases")

func test_legacy_unknown_and_bankruptcy_clear() -> void:
	var game = make_game()
	if game == null:
		return
	prepare_market(game, 100.0, 100.0)
	expect(game.choose_action("buy_stock", {"symbol": "s01", "quantity": 2}).get("ok", false), "legacy setup market buy succeeds")
	var saved: Dictionary = game.to_dict()
	saved.players[0].erase("stock_average_costs")
	expect(bool(Game.validate_save(saved).get("ok", false)), "legacy save without historical cost remains structurally valid")
	var legacy = Game.from_dict(saved)
	expect(legacy != null, "legacy save without historical cost loads")
	if legacy != null:
		expect(stock_cost(legacy) == null, "legacy held position stays explicitly unknown")
		prepare_market(legacy, 100.0, 100.0, 100000, 1000)
		expect(legacy.choose_action("buy_stock", {"symbol": "s01", "quantity": 1}).get("ok", false), "legacy unknown position can buy without fabricated history")
		expect(stock_cost(legacy) == null, "buying onto unknown history remains unknown")
		set_quote(legacy, 100.0, 100.0)
		expect(legacy.choose_action("sell_stock", {"symbol": "s01", "quantity": 3}).get("ok", false), "legacy unknown position can close")
		expect(cost_is_zero(legacy), "closing legacy unknown position restores known zero")
		prepare_market(legacy, 100.0, 97.0, 100000, 1000)
		expect(legacy.choose_action("buy_stock", {"symbol": "s01", "quantity": 1}).get("ok", false), "legacy closed position can reopen")
		expect(cost_equals(legacy, source_float(97.0)), "reopened legacy position has known current cost")
	valid_save(legacy, "legacy migration after closure")
	var bankrupt = make_game()
	if bankrupt == null:
		return
	prepare_market(bankrupt, 100.0, 100.0)
	expect(bankrupt.choose_action("buy_stock", {"symbol": "s01", "quantity": 2}).get("ok", false), "bankruptcy setup market buy succeeds")
	bankrupt._declare_bankruptcy(0, -1, 1, "stock_accounting_test")
	expect(not bankrupt.state.players[0].alive and bankrupt.state.players[0].stocks.s01 == 0, "bankruptcy clears stock holdings")
	expect(cost_is_zero(bankrupt), "bankruptcy clears average cost")
	bankrupt.state.current_player = 1
	bankrupt.state.phase = "await_roll"
	set_bank_deposits(bankrupt)
	bankrupt._sync_state()
	bankrupt._set_action_options(1)
	valid_save(bankrupt, "bankruptcy stock liquidation")

func test_metadata_validation() -> void:
	var game = make_game()
	if game == null:
		return
	var saved: Dictionary = game.to_dict()
	var cases: Array = [
		{"name": "negative", "value": -1.0},
		{"name": "infinite", "value": INF},
		{"name": "nan", "value": NAN},
		{"name": "string", "value": "100"},
		{"name": "dictionary", "value": {}},
		{"name": "array", "value": []},
	]
	for item in cases:
		var broken: Dictionary = saved.duplicate(true)
		broken.players[0]["stock_average_costs"] = populated_costs()
		broken.players[0].stock_average_costs.s01 = item.value
		expect(not bool(Game.validate_save(broken).get("ok", false)), "malformed stock average cost rejects: " + str(item.name))
	var nonzero_empty: Dictionary = saved.duplicate(true)
	nonzero_empty.players[0]["stock_average_costs"] = populated_costs()
	nonzero_empty.players[0].stock_average_costs.s01 = 1.0
	expect(not bool(Game.validate_save(nonzero_empty).get("ok", false)), "zero holding cannot retain nonzero stock average")
	var positive_zero: Dictionary = saved.duplicate(true)
	positive_zero.players[0].stocks.s01 = 1
	positive_zero.players[0]["stock_average_costs"] = populated_costs()
	positive_zero.players[0].stock_average_costs.s01 = 0.0
	expect(not bool(Game.validate_save(positive_zero).get("ok", false)), "positive holding cannot use zero average")
	var subunit_positive: Dictionary = saved.duplicate(true)
	subunit_positive.players[0].stocks.s01 = 1
	subunit_positive.players[0]["stock_average_costs"] = populated_costs()
	subunit_positive.players[0].stock_average_costs.s01 = 0.5
	expect(preload("res://game/core/stock_accounting.gd").validate_player(subunit_positive.players[0], Market.symbols()).is_empty(), "source SALE can leave one share with a valid subunit average")
	var huge_positive: Dictionary = saved.duplicate(true)
	huge_positive.players[0].stocks.s01 = 1
	huge_positive.players[0]["stock_average_costs"] = populated_costs()
	huge_positive.players[0].stock_average_costs.s01 = 1e300
	expect(not bool(Game.validate_save(huge_positive).get("ok", false)), "positive holding cannot use an arithmetic-unsafe average")
	expect(Game.from_dict(huge_positive) == null, "arithmetic-unsafe average cannot be adopted by loading")
	var missing_symbol: Dictionary = saved.duplicate(true)
	missing_symbol.players[0]["stock_average_costs"] = populated_costs()
	missing_symbol.players[0].stock_average_costs.erase("s01")
	expect(not bool(Game.validate_save(missing_symbol).get("ok", false)), "new save must include each stock average")
	var malformed_stocks: Dictionary = saved.duplicate(true)
	malformed_stocks.players[0]["stocks"] = []
	malformed_stocks.players[0]["stock_average_costs"] = populated_costs()
	expect(not bool(Game.validate_save(malformed_stocks).get("ok", false)), "malformed stocks reject without cost-validation crash")

func test_price_limits_and_affordability() -> void:
	var upper_buy = make_game()
	if upper_buy == null:
		return
	prepare_market(upper_buy, 100.0, Market.next_price(100.0, 10.0), 1000, 1000)
	# current is the row quote; previous is the source classifier anchor.
	set_quote(upper_buy, 100.0, Market.next_price(100.0, 10.0))
	expect_reject_atomic(upper_buy, "buy_stock", {"symbol": "s01", "quantity": 1}, "upper-limit buy")
	var lower_sell = make_game()
	if lower_sell == null:
		return
	prepare_market(lower_sell, 100.0, 100.0)
	expect(lower_sell.choose_action("buy_stock", {"symbol": "s01", "quantity": 1}).get("ok", false), "lower-limit sell setup buy succeeds")
	set_quote(lower_sell, 100.0, Market.next_price(100.0, -10.0))
	expect_reject_atomic(lower_sell, "sell_stock", {"symbol": "s01", "quantity": 1}, "lower-limit sell")
	var upper_sell = make_game()
	if upper_sell == null:
		return
	prepare_market(upper_sell, 100.0, 100.0)
	expect(upper_sell.choose_action("buy_stock", {"symbol": "s01", "quantity": 1}).get("ok", false), "upper-limit sell setup buy succeeds")
	set_quote(upper_sell, 100.0, Market.next_price(100.0, 10.0))
	expect(upper_sell.choose_action("sell_stock", {"symbol": "s01", "quantity": 1}).get("ok", false), "upper-limit sell remains valid")
	var lower_buy = make_game()
	if lower_buy == null:
		return
	prepare_market(lower_buy, 100.0, Market.next_price(100.0, -10.0), 1000, 1000)
	expect(lower_buy.choose_action("buy_stock", {"symbol": "s01", "quantity": 1}).get("ok", false), "lower-limit buy remains valid")
	var near_upper = make_game()
	if near_upper == null:
		return
	prepare_market(near_upper, 100.0, 109.0, 1000, 1000)
	expect(near_upper.choose_action("buy_stock", {"symbol": "s01", "quantity": 1}).get("ok", false), "below-upper-limit buy remains valid")
	var near_lower = make_game()
	if near_lower == null:
		return
	prepare_market(near_lower, 100.0, 100.0)
	expect(near_lower.choose_action("buy_stock", {"symbol": "s01", "quantity": 1}).get("ok", false), "above-lower-limit sell setup buy succeeds")
	set_quote(near_lower, 100.0, 91.0)
	expect(near_lower.choose_action("sell_stock", {"symbol": "s01", "quantity": 1}).get("ok", false), "above-lower-limit sell remains valid")
	var boundary_upper = make_game()
	if boundary_upper == null:
		return
	var source_upper := Market.next_price(4.96, 10.0)
	expect(not is_equal_approx(source_upper, snappedf(4.96 * 1.1, 0.01)), "upper tick boundary differs from naive percentage")
	prepare_market(boundary_upper, 4.96, source_upper, 1000, 1000)
	expect_reject_atomic(boundary_upper, "buy_stock", {"symbol": "s01", "quantity": 1}, "source upper tick boundary buy")
	var boundary_lower = make_game()
	if boundary_lower == null:
		return
	var source_lower := Market.next_price(4.99, -10.0)
	expect(not is_equal_approx(source_lower, snappedf(4.99 * 0.9, 0.01)), "lower tick boundary differs from naive percentage")
	prepare_market(boundary_lower, 4.99, source_lower, 1000, 1000)
	expect(boundary_lower.choose_action("buy_stock", {"symbol": "s01", "quantity": 1}).get("ok", false), "source lower tick boundary sell setup buy succeeds")
	expect_reject_atomic(boundary_lower, "sell_stock", {"symbol": "s01", "quantity": 1}, "source lower tick boundary sell")
	var affordability = make_game()
	if affordability == null:
		return
	prepare_market(affordability, 33.4, 33.4, 100, 5)
	expect_reject_atomic(affordability, "buy_stock", {"symbol": "s01", "quantity": 3}, "quantity affordability upper bound")
	expect(affordability.choose_action("buy_stock", {"symbol": "s01", "quantity": 2}).get("ok", false), "quantity within floor deposit over price succeeds")
	expect(affordability.state.players[0].deposit == 100 - Market.quote(33.4, 2), "affordable purchase charges actual integer amount")

func test_limit_state_boundaries() -> void:
	var upper := Market.next_price(1000.0, 10.0)
	var lower := Market.next_price(1000.0, -10.0)
	expect(Market.limit_state(1000.0, 1099.99) == 0, "near-upper quote remains ordinary")
	expect(Market.limit_state(1000.0, upper) == 1, "upper tick quote is upper-limit")
	expect(Market.limit_state(1000.0, 1101.0) == 1, "beyond-upper quote remains upper-limit")
	expect(Market.limit_state(1000.0, lower) == 3, "lower tick quote is lower-limit")
	expect(Market.limit_state(1000.0, 89.99) == 3, "beyond-lower quote remains lower-limit")
	expect(Market.limit_state(1000.0, 1000.0) == 4, "unchanged quote is flat state")
	expect(Market.limit_state(1.0, 1.0) == 4, "lower clamp does not turn flat quote into lower-limit")
	expect(Market.limit_state(9999.0, 9999.0) == 4, "upper clamp does not turn flat quote into upper-limit")
	expect(Market.limit_state(1000.0, 950.0) == 0, "ordinary downward quote remains ordinary")
	expect(Market.limit_state(1000.0, 1005.0) == 0, "ordinary upward quote remains ordinary")

	var beyond_upper := make_game()
	if beyond_upper == null:
		return
	prepare_market(beyond_upper, 1000.0, 1101.0, 100000, 1000)
	expect_reject_atomic(beyond_upper, "buy_stock", {"symbol": "s01", "quantity": 1}, "beyond-upper public buy")
	var near_upper := make_game()
	if near_upper == null:
		return
	prepare_market(near_upper, 1000.0, 1099.99, 100000, 1000)
	expect(near_upper.choose_action("buy_stock", {"symbol": "s01", "quantity": 1}).get("ok", false), "near-upper public buy remains valid")

func _initialize() -> void:
	test_market_average_and_roundtrip()
	test_company_issue_uses_same_accounting()
	test_legacy_unknown_and_bankruptcy_clear()
	test_metadata_validation()
	test_price_limits_and_affordability()
	test_limit_state_boundaries()
	print("Stock accounting checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
