extends SceneTree

## Pure RED seed for the graph-news landing and its bounded 36-card resolver.
## The fixture is synthetic; all assertions go through GameState landing so a
## future NewsEvents adapter cannot pass by only exercising a mock module.

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/news_fixture.gd")
const EngineeringVehicle = preload("res://game/core/engineering_vehicle.gd")
const OriginalInventory = preload("res://game/core/inventory_rules.gd")
const OriginalStockMarket = preload("res://game/core/original_stock_market.gd")

const NEWS_COUNT := 36
const UNSUPPORTED_IDS := [4, 7, 20, 29]
const SUPPORTED_IDS := [0, 1, 2, 3, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 24, 25, 26, 27, 28, 30, 31, 32, 33, 34, 35]
const PROPERTY_IDS := [2, 3]
const FACILITY_SOURCE_IDS := [1, 2]
const FACILITY_GROUPS := [[1, 6], [7, 8]]
const STOCK_SYMBOLS := ["s01", "s02", "s03", "s04", "s05", "s06", "s07", "s08", "s09", "s10", "s11", "s12"]

var checks := 0
var failures := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	_test_fixture_and_shape()
	_test_pass_through_and_deck()
	_test_status_effects()
	_test_asset_effects()
	_test_money_effects()
	_test_vehicle_and_loan_effects()
	_test_stock_effects()
	_test_company_effects()
	print("news_flow checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _news_order(first_id: int) -> Array:
	var result: Array = [first_id]
	for event_id in range(NEWS_COUNT):
		if event_id != first_id:
			result.append(event_id)
	return result


func _set_news(game: Object, order: Array, cursor: int = 0) -> void:
	game.state["news"] = {
		"order": order.duplicate(true),
		"cursor": cursor,
		"draw_count": 0,
		"last": {},
	}


func _new_game(first_id: int = 16, seed_value: int = 5400, player_count: int = 4) -> Object:
	var game: Object = Fixture.new_game(seed_value, player_count)
	expect(game != null, "news fixture creates a game")
	if game == null:
		return null
	game.state["phase"] = "await_action"
	game.state["current_player"] = 0
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["property_action_used"] = false
	game._set_action_options(0)
	_set_news(game, _news_order(first_id))
	return game


func _valid_before_effect(game: Object, label: String) -> void:
	if game == null:
		return
	_assert_news_permutation(game, label + " pre-effect")
	var raw: Dictionary = game.to_dict()
	var validation: Dictionary = Game.validate_save(raw)
	expect(bool(validation.get("ok", false)), label + " fixture validates before effect: " + str(validation.get("errors", [])))
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null, label + " fixture survives JSON before effect")


func _assert_news_permutation(game: Object, label: String) -> void:
	var news: Variant = game.state.get("news", null)
	expect(typeof(news) == TYPE_DICTIONARY, label + " has a news dictionary")
	if typeof(news) != TYPE_DICTIONARY:
		return
	var order: Variant = news.get("order", null)
	expect(typeof(order) == TYPE_ARRAY and order.size() == NEWS_COUNT, label + " has exactly 36 news candidates")
	if typeof(order) != TYPE_ARRAY:
		return
	var sorted_order: Array = order.duplicate()
	sorted_order.sort()
	var expected_order: Array = []
	for event_id in range(NEWS_COUNT):
		expected_order.append(event_id)
	expect(sorted_order == expected_order, label + " news order is a permutation of IDs 0..35")
	expect(typeof(news.get("cursor", null)) == TYPE_INT and int(news.get("cursor", -1)) >= 0 and int(news.get("cursor", -1)) < NEWS_COUNT, label + " cursor is bounded")
	expect(typeof(news.get("draw_count", null)) == TYPE_INT and int(news.get("draw_count", -1)) >= 0, label + " draw count is nonnegative")
	expect(typeof(news.get("last", null)) == TYPE_DICTIONARY, label + " last result is a dictionary")


func _market_index(market: Dictionary) -> int:
	var cents := 0
	for symbol in STOCK_SYMBOLS:
		cents += roundi(float(market.prices.get(symbol, 0.0)) * 100.0)
	return floori(float(cents) / 10.0)


func _land_news(game: Object, label: String, final_landing: bool = true) -> void:
	if game == null:
		return
	var board: Array = game.state.get("board", [])
	expect(not board.is_empty(), label + " board exists")
	if board.is_empty():
		return
	var tile: Dictionary = board.back()
	var player: Dictionary = game.state.players[0]
	player["position"] = int(tile.get("index", board.size() - 1))
	player["previous_position"] = maxi(0, int(player["position"]) - 1)
	game._graph_visit_tile(0, tile, final_landing)
	var validation: Dictionary = Game.validate_save(game.to_dict())
	expect(bool(validation.get("ok", false)), label + " save validates after effect: " + str(validation.get("errors", [])))
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null, label + " JSON reloads after effect")


func _last(game: Object) -> Dictionary:
	var news: Variant = game.state.get("news", {})
	if typeof(news) != TYPE_DICTIONARY:
		return {}
	var last: Variant = news.get("last", {})
	return last if typeof(last) == TYPE_DICTIONARY else {}


func _expect_last(game: Object, event_id: int, label: String) -> Dictionary:
	var last := _last(game)
	expect(last.size() == 5, label + " result uses the fixed five-key last shape")
	expect(int(last.get("id", -1)) == event_id, label + " selects expected news ID")
	expect(int(last.get("player_id", -1)) == 0, label + " records the landing player")
	expect(typeof(last.get("targets", null)) == TYPE_ARRAY, label + " result has typed targets")
	expect(typeof(last.get("changes", null)) == TYPE_ARRAY, label + " result has typed changes")
	expect(typeof(last.get("summary", null)) == TYPE_STRING and not str(last.get("summary", "")).is_empty(), label + " result has a readable summary")
	return last


func _target_id(last: Dictionary) -> int:
	var targets: Array = last.get("targets", [])
	if targets.is_empty():
		return -1
	var target: Variant = targets[0]
	if typeof(target) == TYPE_INT:
		return int(target)
	if typeof(target) == TYPE_DICTIONARY:
		for key in ["tile_id", "node", "id", "source_object_id", "stock_index", "company_id"]:
			if typeof(target.get(key, null)) == TYPE_INT:
				return int(target[key])
	return -1


func _test_fixture_and_shape() -> void:
	var game := _new_game(16)
	_valid_before_effect(game, "baseline")
	if game == null:
		return
	var tile: Dictionary = game.state.board.back()
	expect(int(tile.get("event_code", -1)) == 2, "fixture board tail is source event_code 2")
	expect(int(tile.get("source_status_bits", -1)) == 2, "fixture board tail preserves source news status bits")
	expect(str(tile.get("name", "")) == "測試新聞", "fixture board tail has synthetic news name")
	var news: Dictionary = game.state.news
	expect(news.order.size() == NEWS_COUNT, "news state stores all 36 candidates")
	expect(news.cursor == 0 and news.draw_count == 0 and news.last.is_empty(), "news state starts at cursor zero with empty result")
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null and restored.state.get("news", {}).order == news.order, "news order survives JSON roundtrip")


func _test_pass_through_and_deck() -> void:
	var pass_game := _new_game(16)
	_valid_before_effect(pass_game, "pass-through")
	_land_news(pass_game, "pass-through", false)
	expect(int(pass_game.state.news.draw_count) == 0, "passing over news does not draw")
	expect(_last(pass_game).is_empty(), "passing over news does not write a result")

	var skip_game := _new_game(16)
	var order: Array = [4, 7, 20, 29, 16]
	for event_id in range(NEWS_COUNT):
		if not order.has(event_id):
			order.append(event_id)
	_set_news(skip_game, order)
	_valid_before_effect(skip_game, "unsupported-skip")
	_land_news(skip_game, "unsupported-skip")
	_expect_last(skip_game, 16, "unsupported-skip")
	expect(int(skip_game.state.news.cursor) == 5, "unsupported candidates advance cursor before selecting")
	expect(int(skip_game.state.news.draw_count) == 1, "one landing increments draw count once after candidate skips")

	var wrap_game := _new_game(16)
	var wrap_order: Array = [16]
	for event_id in range(NEWS_COUNT):
		if not wrap_order.has(event_id) and event_id not in [4, 7]:
			wrap_order.append(event_id)
	# Keep a real permutation while placing two unsupported cards at the end.
	# The wrapped scan therefore visits exactly [4, 7, 16].
	wrap_order.erase(4)
	wrap_order.erase(7)
	wrap_order.append(4)
	wrap_order.append(7)
	_set_news(wrap_game, wrap_order, 34)
	_valid_before_effect(wrap_game, "deck-wrap")
	_land_news(wrap_game, "deck-wrap")
	_expect_last(wrap_game, 16, "deck-wrap")
	expect(int(wrap_game.state.news.cursor) == 1, "deck cursor wraps modulo 36")
	expect(int(wrap_game.state.news.draw_count) == 1, "wrapped scan still counts one draw invocation")

	var continuation := _new_game(16)
	var continuation_order: Array = [16, 17]
	for event_id in range(NEWS_COUNT):
		if not continuation_order.has(event_id):
			continuation_order.append(event_id)
	_set_news(continuation, continuation_order)
	_valid_before_effect(continuation, "continuation-before-first")
	_land_news(continuation, "continuation-first")
	_expect_last(continuation, 16, "continuation-first")
	var after_first: String = continuation.to_json()
	var resumed: Object = Game.from_dict(JSON.parse_string(after_first))
	expect(resumed != null, "news continuation restores after first draw")
	if resumed == null:
		return
	# Continue through the ordinary finite inventory lifecycle: grant one car
	# from shared supply, equip it through the existing vehicle selector, then
	# persist that ownership/equipment state before the next news landing.
	var car_supply_before: int = int(resumed.state.inventory_supply.tools.get("汽車", -1))
	var car_grant: Dictionary = OriginalInventory.grant_tool(
		resumed.state.inventory_supply,
		resumed.state.players[0]["tools"],
		"汽車",
	)
	expect(bool(car_grant.get("ok", false)), "JSON continuation grants a finite-supply car")
	expect(int(resumed.state.players[0]["tools"].get("汽車", 0)) == 1, "JSON continuation records car ownership before equip")
	expect(int(resumed.state.inventory_supply.tools.get("汽車", -1)) == car_supply_before - 1, "car grant decrements shared finite supply")
	resumed.state["phase"] = "await_roll"
	resumed.state["current_player"] = 0
	var car_equip: Dictionary = resumed.set_vehicle("car", 3)
	expect(bool(car_equip.get("ok", false)), "JSON continuation equips car through existing API")
	expect(str(resumed.state.players[0].get("vehicle", "")) == "car", "JSON continuation keeps equipped car")
	expect(bool(resumed.state.players[0].get("vehicles", {}).get("car", false)), "JSON continuation keeps car ownership")
	expect(int(resumed.state.players[0].get("tools", {}).get("汽車", 0)) == 0, "equipping car consumes the owned inventory unit")
	var after_vehicle: String = resumed.to_json()
	var equipped: Object = Game.from_dict(JSON.parse_string(after_vehicle))
	expect(equipped != null, "JSON continuation reloads equipped car")
	if equipped == null:
		return
	equipped.state.players[0]["stay_next"] = 0
	equipped.state["phase"] = "await_action"
	equipped.state["current_player"] = 0
	equipped._set_action_options(0)
	_land_news(equipped, "continuation-second")
	_expect_last(equipped, 17, "continuation-second")
	expect(int(equipped.state.news.cursor) == 2 and int(equipped.state.news.draw_count) == 2, "JSON continuation keeps cursor and draw count")
	expect(equipped.to_json() != after_first, "second landing records a new deterministic result")


func _test_status_effects() -> void:
	for event_id in [0, 1, 2, 3]:
		var game := _new_game(event_id)
		# Keep the landing actor on the news node and place a separate active
		# status holder on its canonical facility, so post-effect save checks can
		# verify both movement and status invariants independently.
		var status_kind := "prison" if event_id in [0, 1] else "hospital"
		expect(game._admit_player_status(1, status_kind, 6).get("ok", false), "first news status target enters through existing admission")
		expect(game._admit_player_status(2, status_kind, 4).get("ok", false), "second news status target enters through existing admission")
		_valid_before_effect(game, "status-%d" % event_id)
		_land_news(game, "status-%d" % event_id)
		_expect_last(game, event_id, "status-%d" % event_id)
		var field := "prison_days" if event_id in [0, 1] else "hospital_days"
		var expected := 128 if event_id in [0, 2] else 9
		expect(int(game.state.players[1].get(field, -1)) == expected, "status-%d applies source counter mutation" % event_id)
		expect(int(game.state.players[2].get(field, -1)) == (128 if event_id in [0, 2] else 7), "status-%d affects every matching status holder" % event_id)
		expect(int(game.state.players[0].get(field, -1)) == 0 and int(game.state.players[3].get(field, -1)) == 0, "status-%d preserves players outside the facility" % event_id)


func _clear_assets(game: Object) -> void:
	for player in game.state.players:
		player["properties"] = []
	for property_id in PROPERTY_IDS:
		var property: Dictionary = game.state.board[property_id]
		property["owner"] = -1
		property["building_level"] = 0
		game._update_tile_rent(property)
	for source_id in FACILITY_SOURCE_IDS:
		game._update_facility_records(source_id, {"owner": -1, "building_level": 0, "facility_type": 0, "facility_state": 0})
	game._recalculate_property_values()


func _prepare_all_assets(game: Object, owner_id: int = 1) -> void:
	_clear_assets(game)
	var owner: Dictionary = game.state.players[owner_id]
	var owned: Array = []
	for property_id in PROPERTY_IDS:
		var property: Dictionary = game.state.board[property_id]
		property["owner"] = owner_id
		property["building_level"] = 2
		property["land_price"] = 1001 + property_id
		property["cost"] = int(property.land_price)
		property["house_price"] = 300
		game._update_tile_rent(property)
		owned.append(property_id)
	for source_id in FACILITY_SOURCE_IDS:
		game._update_facility_records(source_id, {"owner": owner_id, "building_level": 2, "facility_type": 1, "facility_state": 0})
		owned.append(1 if source_id == 1 else 7)
	owner["properties"] = owned
	game._recalculate_property_values()


func _assert_selected_asset_group(game: Object, before: Dictionary, direction: String, label: String) -> void:
	var last := _last(game)
	var target_id := _target_id(last)
	expect(target_id >= 0, label + " identifies a canonical target")
	var expected_groups: Array = []
	if PROPERTY_IDS.has(target_id):
		expected_groups.append(PROPERTY_IDS)
	else:
		for group in FACILITY_GROUPS:
			if group.has(target_id):
				expected_groups.append(group)
	expect(not expected_groups.is_empty(), label + " target is a housing or facility record")
	for group in expected_groups:
		for index in group:
			var old_price: int = int(before.get(str(index), -1))
			var current_price: int = int(game.state.board[index].get("land_price", -1))
			var expected_price: int = int(float(old_price) * (1.3 if direction == "up" else 0.7))
			expect(current_price == expected_price, label + " updates every same-name/facility-alias price")


func _test_asset_effects() -> void:
	# ID 5 has a source mode-1 clear and must work through a canonical property.
	var clear_game := _new_game(5)
	_clear_assets(clear_game)
	var clear_property: Dictionary = clear_game.state.board[2]
	clear_property["owner"] = 1
	clear_property["building_level"] = 2
	clear_game.state.players[1]["properties"] = [2]
	clear_game._update_tile_rent(clear_property)
	_valid_before_effect(clear_game, "asset-clear")
	_land_news(clear_game, "asset-clear")
	_expect_last(clear_game, 5, "asset-clear")
	expect(int(clear_property.get("owner", -1)) == -1 and int(clear_property.get("building_level", -1)) == 0, "ID5 clears selected housing owner and level")

	for event_id in [6, 14]:
		var price_game := _new_game(event_id)
		_prepare_all_assets(price_game)
		var before: Dictionary = {}
		for index in PROPERTY_IDS + [1, 6, 7, 8]:
			before[str(index)] = int(price_game.state.board[index].get("land_price", -1))
		_valid_before_effect(price_game, "asset-price-%d" % event_id)
		_land_news(price_game, "asset-price-%d" % event_id)
		_expect_last(price_game, event_id, "asset-price-%d" % event_id)
		_assert_selected_asset_group(price_game, before, "up" if event_id == 6 else "down", "asset-price-%d" % event_id)

	# IDs 15/18/19/21 all exercise built housing/facility damage paths. Every
	# candidate is built to keep the source random selection target-compatible.
	for event_id in [18, 19, 21]:
		var damage_game := _new_game(event_id)
		_prepare_all_assets(damage_game)
		var before_levels: Dictionary = {}
		for index in PROPERTY_IDS + [1, 6, 7, 8]:
			before_levels[str(index)] = int(damage_game.state.board[index].get("building_level", -1))
		_valid_before_effect(damage_game, "asset-damage-%d" % event_id)
		_land_news(damage_game, "asset-damage-%d" % event_id)
		_expect_last(damage_game, event_id, "asset-damage-%d" % event_id)
		var target_id := _target_id(_last(damage_game))
		if target_id < 0 or target_id >= damage_game.state.board.size():
			expect(false, "asset-damage-%d identifies a valid canonical target" % event_id)
			continue
		var group: Array = [target_id] if event_id in [19, 21] else PROPERTY_IDS
		if not PROPERTY_IDS.has(target_id):
			group = [target_id]
			for candidate in FACILITY_GROUPS:
				if candidate.has(target_id):
					group = candidate
		for index in group:
			var level: int = int(damage_game.state.board[index].get("building_level", -1))
			var expected_level := 0 if event_id == 19 else int(before_levels[str(index)]) - 1
			expect(level == expected_level, "asset-damage-%d applies canonical group damage" % event_id)

	var fallback_game := _new_game(15)
	_clear_assets(fallback_game)
	var fallback_property: Dictionary = fallback_game.state.board[2]
	fallback_property["owner"] = 1
	fallback_property["building_level"] = 2
	fallback_game.state.players[1]["properties"] = [2]
	fallback_game._update_tile_rent(fallback_property)
	_valid_before_effect(fallback_game, "asset-id15-housing-fallback")
	_land_news(fallback_game, "asset-id15-housing-fallback")
	_expect_last(fallback_game, 15, "asset-id15-housing-fallback")
	expect(int(fallback_property.get("building_level", -1)) == 1, "ID15 requires a built housing target and damages it once")


func _own_properties(game: Object, player_id: int, ids: Array) -> void:
	for candidate in game.state.players:
		candidate["properties"] = []
	_clear_assets(game)
	var player: Dictionary = game.state.players[player_id]
	player["properties"] = ids.duplicate()
	for property_id in PROPERTY_IDS:
		var property: Dictionary = game.state.board[property_id]
		property["owner"] = player_id if ids.has(property_id) else -1
		property["building_level"] = 0
		game._update_tile_rent(property)
	for source_id in FACILITY_SOURCE_IDS:
		var canonical := 1 if source_id == 1 else 7
		game._update_facility_records(source_id, {"owner": player_id if ids.has(canonical) else -1, "building_level": 0, "facility_type": 0})
	game._recalculate_property_values()


func _test_money_effects() -> void:
	var max_game := _new_game(8)
	max_game.state["price_index"] = 2
	_own_properties(max_game, 0, [2, 3])
	# Keep the maximum holder at two records and give the second player one
	# distinct facility record; reusing a housing ID would invalidate the
	# fixture's canonical owner references.
	max_game._update_facility_records(1, {"owner": 1, "building_level": 0, "facility_type": 0})
	max_game.state.players[1]["properties"] = [1]
	max_game._recalculate_property_values()
	_valid_before_effect(max_game, "money-max")
	var max_cash: int = int(max_game.state.players[0].cash)
	_land_news(max_game, "money-max")
	_expect_last(max_game, 8, "money-max")
	expect(int(max_game.state.players[0].cash) == max_cash + 20000, "ID8 credits max property holder by price index times 10000")

	var min_game := _new_game(9)
	min_game.state["price_index"] = 2
	_own_properties(min_game, 1, [2])
	for player_id in [0, 2, 3]:
		min_game.state.players[player_id]["cash"] = 100000
	var min_cash: int = int(min_game.state.players[0].cash)
	_valid_before_effect(min_game, "money-min")
	_land_news(min_game, "money-min")
	_expect_last(min_game, 9, "money-min")
	expect(int(min_game.state.players[0].cash) == min_cash + 10000, "ID9 credits the first tied minimum-property player")

	var stock_game := _new_game(10)
	stock_game.state["price_index"] = 2
	stock_game.state.players[0].stocks["s01"] = 3
	stock_game.state.players[1].stocks["s01"] = 2
	stock_game.state.market.rows["s01"]["market_supply"] = 4995
	stock_game._update_company_owners()
	var stock_cash: int = int(stock_game.state.players[0].cash)
	_valid_before_effect(stock_game, "money-stock-max")
	_land_news(stock_game, "money-stock-max")
	_expect_last(stock_game, 10, "money-stock-max")
	expect(int(stock_game.state.players[0].cash) == stock_cash + 20000, "ID10 credits max 12-stock holder by price index times 10000")

	var tax_game := _new_game(11)
	var tax_before := [10000, 20000, 30000, 40000]
	for player_id in range(4):
		tax_game.state.players[player_id]["cash"] = tax_before[player_id]
	_valid_before_effect(tax_game, "tax-nonterminal")
	_land_news(tax_game, "tax-nonterminal")
	_expect_last(tax_game, 11, "tax-nonterminal")
	for player_id in range(4):
		expect(int(tax_game.state.players[player_id].cash) == tax_before[player_id] - int(tax_before[player_id] * 0.05), "ID11 charges every active player five percent")
	expect(int(tax_game.state.current_player) == 0 and tax_game.state.phase != "game_over", "nonterminal global tax keeps the actor in place")

	var land_tax := _new_game(12)
	land_tax.state["price_index"] = 1
	_clear_assets(land_tax)
	for player in land_tax.state.players:
		player["properties"] = []
	land_tax.state.players[0]["properties"] = [2]
	land_tax.state.players[1]["properties"] = [3]
	land_tax.state.players[2]["properties"] = [1]
	land_tax.state.board[2]["owner"] = 0
	land_tax.state.board[2]["building_level"] = 5
	land_tax.state.board[3]["owner"] = 1
	land_tax.state.board[3]["building_level"] = 1
	land_tax._update_facility_records(1, {"owner": 2, "building_level": 1, "facility_type": 1, "facility_state": 0})
	land_tax._update_tile_rent(land_tax.state.board[2])
	land_tax._update_tile_rent(land_tax.state.board[3])
	land_tax._recalculate_property_values()
	# The v13 graph validator owns source prices; a level-5 synthetic house is
	# enough to make the current actor insolvent without changing source fields.
	land_tax.state.players[0]["cash"] = 1
	for player in land_tax.state.players:
		player["deposit"] = 0
	land_tax.state.players[1]["cash"] = 100000
	land_tax.state.players[2]["cash"] = 100000
	land_tax.state.players[3]["cash"] = 100000
	land_tax.state.bank["deposits"] = 0
	_valid_before_effect(land_tax, "tax-terminal")
	_land_news(land_tax, "tax-terminal")
	_expect_last(land_tax, 12, "tax-terminal")
	expect(not bool(land_tax.state.players[0].alive), "property tax can bankrupt the current actor")
	expect(int(land_tax.state.current_player) == 1, "terminal actor tax hands off once after all player charges")
	expect(int(land_tax.state.players[1].cash) < 100000 and int(land_tax.state.players[2].cash) < 100000, "nonterminal actor tax still applies later taxable players before handoff")

	var game_over_tax := _new_game(12, 5412, 2)
	_clear_assets(game_over_tax)
	for player in game_over_tax.state.players:
		player["properties"] = []
		player["deposit"] = 0
	game_over_tax.state.players[0]["properties"] = [2]
	game_over_tax.state.board[2]["owner"] = 0
	game_over_tax.state.board[2]["building_level"] = 5
	game_over_tax._update_tile_rent(game_over_tax.state.board[2])
	game_over_tax._recalculate_property_values()
	game_over_tax.state.players[0]["cash"] = 1
	game_over_tax.state.players[1]["cash"] = 100000
	game_over_tax.state.bank["deposits"] = 0
	_valid_before_effect(game_over_tax, "tax-game-over")
	_land_news(game_over_tax, "tax-game-over")
	_expect_last(game_over_tax, 12, "tax-game-over")
	expect(game_over_tax.state.phase == "game_over", "last opponent bankruptcy ends global tax in game over")
	expect(int(game_over_tax.state.players[1].cash) == 100000, "terminal tax stops before charging the remaining player")

	var stock_tax := _new_game(13)
	stock_tax.state["price_index"] = 2
	stock_tax.state.players[0].stocks["s01"] = 10
	stock_tax.state.market.rows["s01"]["market_supply"] = 4990
	stock_tax._update_company_owners()
	stock_tax.state.players[0].cash = 10000
	var stock_tax_cash: int = int(stock_tax.state.players[0].cash)
	_valid_before_effect(stock_tax, "tax-stock")
	_land_news(stock_tax, "tax-stock")
	_expect_last(stock_tax, 13, "tax-stock")
	expect(int(stock_tax.state.players[0].cash) == stock_tax_cash - 100, "ID13 charges five percent of stock holdings times current price index")


func _test_vehicle_and_loan_effects() -> void:
	var walking_game := _new_game(16)
	walking_game.state.players[0]["stay_next"] = 7
	walking_game.state.players[1]["stay_next"] = 4
	walking_game.state.players[2]["vehicle"] = "car"
	walking_game.state.players[2]["vehicles"]["car"] = true
	walking_game.state.inventory_supply.tools["汽車"] = int(walking_game.state.inventory_supply.tools["汽車"]) - 1
	_valid_before_effect(walking_game, "vehicle-walking")
	_land_news(walking_game, "vehicle-walking")
	_expect_last(walking_game, 16, "vehicle-walking")
	expect(int(walking_game.state.players[0].stay_next) == 1 and int(walking_game.state.players[1].stay_next) == 1, "ID16 overwrites walking stay counters")
	expect(int(walking_game.state.players[2].stay_next) == 0, "ID16 excludes nonwalking vehicles")

	var nonwalking_game := _new_game(17)
	nonwalking_game.state.players[0]["vehicle"] = "car"
	nonwalking_game.state.players[1]["vehicle"] = "motorcycle"
	nonwalking_game.state.players[0]["vehicles"]["car"] = true
	nonwalking_game.state.players[1]["vehicles"]["motorcycle"] = true
	nonwalking_game.state.inventory_supply.tools["汽車"] = int(nonwalking_game.state.inventory_supply.tools["汽車"]) - 1
	nonwalking_game.state.inventory_supply.tools["機車"] = int(nonwalking_game.state.inventory_supply.tools["機車"]) - 1
	nonwalking_game.state.players[2]["vehicle"] = EngineeringVehicle.VEHICLE_ID
	nonwalking_game.state.players[2]["engineering_vehicle"] = {"remaining_admissions": 7, "previous_vehicle": "car", "previous_dice_count": 3}
	nonwalking_game.state.players[2]["dice_count"] = 1
	nonwalking_game.state.players[3]["vehicle"] = "walking"
	_valid_before_effect(nonwalking_game, "vehicle-nonwalking")
	_land_news(nonwalking_game, "vehicle-nonwalking")
	_expect_last(nonwalking_game, 17, "vehicle-nonwalking")
	for player_id in [0, 1, 2]:
		expect(int(nonwalking_game.state.players[player_id].stay_next) == 1, "ID17 includes cars, motorcycles and engineering vehicles")
	expect(int(nonwalking_game.state.players[3].stay_next) == 0, "ID17 excludes walking vehicles")

	var loan_game := _new_game(22)
	for player in loan_game.state.players:
		player["loan_block_days"] = 0
	_valid_before_effect(loan_game, "loan-block")
	_land_news(loan_game, "loan-block")
	_expect_last(loan_game, 22, "loan-block")
	for player in loan_game.state.players:
		expect(int(player.get("loan_block_days", -1)) == 15, "ID22 sets every active player loan block marker")
	loan_game.state.current_player = 3
	loan_game.state.phase = "await_roll"
	loan_game._advance_to_next_alive(3)
	loan_game.state.current_player = 3
	loan_game.state.phase = "await_roll"
	loan_game.state.players[0]["loan_block_days"] = 1
	loan_game._advance_to_next_alive(3)
	expect(int(loan_game.state.players[0].loan_block_days) == 128, "loan marker releases as 1 to 128 on own admission")
	loan_game.state.current_player = 0
	loan_game.state.phase = "await_action"
	# Reclassify the fixture's source company node as a canonical bank node so
	# the loan action is tested through the real bank landing path.
	var bank_tile: Dictionary = loan_game.state.board[5]
	bank_tile["event_code"] = 14
	bank_tile["source_status_bits"] = 14
	bank_tile["kind"] = "bank"
	bank_tile["name"] = "測試銀行"
	loan_game.state.players[0]["position"] = 5
	loan_game.state.players[0]["previous_position"] = -1
	loan_game.state.bank_access = true
	loan_game.state.bank_landing = true
	loan_game._set_action_options(0)
	expect(loan_game.state.action_options.has("take_loan"), "released 128 loan marker no longer blocks loan action")

	var deposit_game := _new_game(23)
	for player in deposit_game.state.players:
		player["deposit"] = 0
	deposit_game.state.players[0]["deposit"] = 1000
	deposit_game.state.players[0]["loan"] = 0
	deposit_game.state.players[1]["deposit"] = 2000
	deposit_game.state.players[1]["loan"] = 5000
	deposit_game.state.bank["deposits"] = 3000
	_valid_before_effect(deposit_game, "deposit-interest")
	_land_news(deposit_game, "deposit-interest")
	_expect_last(deposit_game, 23, "deposit-interest")
	expect(int(deposit_game.state.players[0].deposit) == 1100 and int(deposit_game.state.players[1].deposit) == 2000, "ID23 credits ten percent only to players without loans")
	expect(int(deposit_game.state.bank.deposits) == 3100, "ID23 preserves bank deposit liability")


func _test_stock_effects() -> void:
	var all_down := _new_game(24)
	var down_prices_before: Dictionary = {}
	var down_history_tails_before: Dictionary = {}
	for symbol in STOCK_SYMBOLS:
		var row: Dictionary = all_down.state.market.rows[symbol]
		down_prices_before[symbol] = float(row.price)
		down_history_tails_before[symbol] = float(all_down.state.market.history[symbol].back())
	_valid_before_effect(all_down, "stock-all-down")
	_land_news(all_down, "stock-all-down")
	_expect_last(all_down, 24, "stock-all-down")
	for symbol in STOCK_SYMBOLS:
		var row: Dictionary = all_down.state.market.rows[symbol]
		var expected_price: float = OriginalStockMarket.next_price(float(row.previous_price), -10.0)
		expect(int(row.event) == 1, "ID24 sets low-nibble event on every stock")
		expect(not is_equal_approx(float(row.price), float(down_prices_before[symbol])), "ID24 refreshes every stock row price immediately")
		expect(is_equal_approx(float(row.price), expected_price), "ID24 recalculates each row price from its previous price")
		expect(is_equal_approx(float(all_down.state.market.prices[symbol]), float(row.price)), "ID24 mirrors refreshed row price into market prices")
		expect(is_equal_approx(float(all_down.state.market.history[symbol].back()), float(row.price)), "ID24 stores refreshed price as history tail")
		expect(not is_equal_approx(float(all_down.state.market.history[symbol].back()), float(down_history_tails_before[symbol])), "ID24 changes the history sample")
	expect(int(all_down.state.market.index) == _market_index(all_down.state.market), "ID24 refreshes aggregate market index")

	var all_up := _new_game(25)
	var up_prices_before: Dictionary = {}
	var up_history_tails_before: Dictionary = {}
	for symbol in STOCK_SYMBOLS:
		var row: Dictionary = all_up.state.market.rows[symbol]
		up_prices_before[symbol] = float(row.price)
		up_history_tails_before[symbol] = float(all_up.state.market.history[symbol].back())
	_valid_before_effect(all_up, "stock-all-up")
	_land_news(all_up, "stock-all-up")
	_expect_last(all_up, 25, "stock-all-up")
	for symbol in STOCK_SYMBOLS:
		var row: Dictionary = all_up.state.market.rows[symbol]
		var expected_price: float = OriginalStockMarket.next_price(float(row.previous_price), 10.0)
		expect(int(row.event) == 0x10, "ID25 sets high-nibble event on every stock")
		expect(not is_equal_approx(float(row.price), float(up_prices_before[symbol])), "ID25 refreshes every stock row price immediately")
		expect(is_equal_approx(float(row.price), expected_price), "ID25 recalculates each row price from its previous price")
		expect(is_equal_approx(float(all_up.state.market.prices[symbol]), float(row.price)), "ID25 mirrors refreshed row price into market prices")
		expect(is_equal_approx(float(all_up.state.market.history[symbol].back()), float(row.price)), "ID25 stores refreshed price as history tail")
		expect(not is_equal_approx(float(all_up.state.market.history[symbol].back()), float(up_history_tails_before[symbol])), "ID25 changes the history sample")
	expect(int(all_up.state.market.index) == _market_index(all_up.state.market), "ID25 refreshes aggregate market index")

	var market_close := _new_game(26)
	_valid_before_effect(market_close, "stock-market-close")
	_land_news(market_close, "stock-market-close")
	_expect_last(market_close, 26, "stock-market-close")
	expect(int(market_close.state.market.closed_days) == 10, "ID26 sets the global market closure counter to ten")

	var halt := _new_game(27)
	var prices_before: Dictionary = {}
	var previous_prices_before: Dictionary = {}
	var history_tails_before: Dictionary = {}
	for symbol in STOCK_SYMBOLS:
		var row: Dictionary = halt.state.market.rows[symbol]
		prices_before[symbol] = float(row.price)
		# Keep a distinct, valid source previous price so the halt copy is
		# observable and cannot pass while leaving price unchanged.
		row.previous_price = 90.0 + float(row.index)
		previous_prices_before[symbol] = float(row.previous_price)
		history_tails_before[symbol] = float(halt.state.market.history[symbol].back())
	_valid_before_effect(halt, "stock-halt")
	_land_news(halt, "stock-halt")
	_expect_last(halt, 27, "stock-halt")
	var halted: Array = []
	for symbol in STOCK_SYMBOLS:
		var row: Dictionary = halt.state.market.rows[symbol]
		if int(row.suspension) == 15:
			halted.append(symbol)
			expect(float(row.previous_price) != float(prices_before[symbol]), "ID27 starts from distinct previous/current prices")
			expect(float(row.price) == float(previous_prices_before[symbol]), "ID27 restores halted current price from previous price")
			expect(float(halt.state.market.prices[symbol]) == float(row.price), "ID27 mirrors restored halted price into market prices")
			expect(float(halt.state.market.history[symbol].back()) == float(row.price), "ID27 synchronizes halted stock history tail")
		else:
			expect(float(row.price) == float(prices_before[symbol]), "ID27 leaves non-selected stock price unchanged")
			expect(float(halt.state.market.history[symbol].back()) == float(history_tails_before[symbol]), "ID27 leaves non-selected history unchanged")
	expect(halted.size() == 1, "ID27 halts exactly one stock")
	expect(int(halt.state.market.index) == _market_index(halt.state.market), "ID27 refreshes aggregate market index")

	var clear_halt := _new_game(28)
	clear_halt.state.market.rows["s01"].suspension = 5
	_valid_before_effect(clear_halt, "stock-clear-halt")
	_land_news(clear_halt, "stock-clear-halt")
	_expect_last(clear_halt, 28, "stock-clear-halt")
	expect(int(clear_halt.state.market.rows["s01"].suspension) == 0, "ID28 clears a selected existing stock suspension")


func _test_company_effects() -> void:
	var expected: Dictionary = {
		30: {"profit": -10000, "event": 3},
		31: {"profit": 20000, "event": 0x30},
		32: {"profit": -20000, "event": 4},
		33: {"profit": -10000, "event": 3},
		34: {"profit": -5000, "event": 3},
	}
	for event_id in expected.keys():
		var game := _new_game(int(event_id))
		var company: Dictionary = game.state.companies[0]
		company["monthly_profit"] = 100000
		company["cumulative_profit"] = 200000
		var linked_symbol := "s%02d" % (int(company.get("stock_index", -1)) + 1)
		var row: Dictionary = game.state.market.rows[linked_symbol]
		row["event"] = 0
		row["previous_price"] = 90.0
		var linked_price_before: float = float(row.price)
		var linked_history_tail_before: float = float(game.state.market.history[linked_symbol].back())
		var prices_before: Dictionary = {}
		var history_tails_before: Dictionary = {}
		for symbol in STOCK_SYMBOLS:
			prices_before[symbol] = float(game.state.market.rows[symbol].price)
			history_tails_before[symbol] = float(game.state.market.history[symbol].back())
		var holdings_before: int = int(game.state.players[0].stocks.get("s01", 0))
		_valid_before_effect(game, "company-%d" % int(event_id))
		_land_news(game, "company-%d" % int(event_id))
		_expect_last(game, int(event_id), "company-%d" % int(event_id))
		expect(int(company.monthly_profit) == 100000 + int(expected[event_id].profit), "ID%d mutates linked company monthly profit" % int(event_id))
		expect(int(company.cumulative_profit) == 200000 + int(expected[event_id].profit), "ID%d mutates linked company cumulative profit" % int(event_id))
		expect(int(row.event) == int(expected[event_id].event), "ID%d writes linked stock event status" % int(event_id))
		expect(int(game.state.players[0].stocks.get("s01", 0)) == holdings_before, "ID%d does not confuse company stock_index with player holdings" % int(event_id))
		var expected_rate: float = 10.0 if (int(expected[event_id].event) & 0xf0) != 0 else -10.0
		var expected_price: float = OriginalStockMarket.next_price(float(row.previous_price), expected_rate)
		expect(not is_equal_approx(float(row.price), linked_price_before), "ID%d refreshes the linked stock row price" % int(event_id))
		expect(is_equal_approx(float(row.price), expected_price), "ID%d recalculates the linked stock row from its previous price" % int(event_id))
		expect(is_equal_approx(float(game.state.market.prices[linked_symbol]), float(row.price)), "ID%d mirrors linked row price into market prices" % int(event_id))
		expect(is_equal_approx(float(game.state.market.history[linked_symbol].back()), float(row.price)), "ID%d stores linked row price in history tail" % int(event_id))
		expect(not is_equal_approx(float(game.state.market.history[linked_symbol].back()), linked_history_tail_before), "ID%d changes linked history sample" % int(event_id))
		for symbol in STOCK_SYMBOLS:
			if symbol == linked_symbol:
				continue
			expect(is_equal_approx(float(game.state.market.rows[symbol].price), float(prices_before[symbol])), "ID%d leaves non-linked stock row price unchanged" % int(event_id))
			expect(is_equal_approx(float(game.state.market.prices[symbol]), float(prices_before[symbol])), "ID%d leaves non-linked market price unchanged" % int(event_id))
			expect(is_equal_approx(float(game.state.market.history[symbol].back()), float(history_tails_before[symbol])), "ID%d leaves non-linked history unchanged" % int(event_id))
		expect(int(game.state.market.index) == _market_index(game.state.market), "ID%d refreshes aggregate market index" % int(event_id))

	var double_game := _new_game(35)
	var double_company: Dictionary = double_game.state.companies[0]
	double_company["monthly_profit"] = 20000
	double_company["cumulative_profit"] = 50000
	var double_symbol := "s%02d" % (int(double_company.get("stock_index", -1)) + 1)
	var double_row: Dictionary = double_game.state.market.rows[double_symbol]
	double_row["event"] = 0
	double_row["previous_price"] = 90.0
	var double_price_before: float = float(double_row.price)
	var double_history_tail_before: float = float(double_game.state.market.history[double_symbol].back())
	var double_prices_before: Dictionary = {}
	var double_history_tails_before: Dictionary = {}
	for symbol in STOCK_SYMBOLS:
		double_prices_before[symbol] = float(double_game.state.market.rows[symbol].price)
		double_history_tails_before[symbol] = float(double_game.state.market.history[symbol].back())
	_valid_before_effect(double_game, "company-double")
	_land_news(double_game, "company-double")
	_expect_last(double_game, 35, "company-double")
	expect(int(double_company.monthly_profit) == 40000 and int(double_company.cumulative_profit) == 90000, "ID35 doubles monthly profit and adds the doubled amount to cumulative profit")
	expect(int(double_row.event) == 0x20, "ID35 maps source monthly-profit bucket to linked stock event")
	var double_expected_price: float = OriginalStockMarket.next_price(float(double_row.previous_price), 10.0)
	expect(not is_equal_approx(float(double_row.price), double_price_before), "ID35 refreshes the linked stock row price")
	expect(is_equal_approx(float(double_row.price), double_expected_price), "ID35 recalculates the linked stock row from its previous price")
	expect(is_equal_approx(float(double_game.state.market.prices[double_symbol]), float(double_row.price)), "ID35 mirrors linked row price into market prices")
	expect(is_equal_approx(float(double_game.state.market.history[double_symbol].back()), float(double_row.price)), "ID35 stores linked row price in history tail")
	expect(not is_equal_approx(float(double_game.state.market.history[double_symbol].back()), double_history_tail_before), "ID35 changes linked history sample")
	for symbol in STOCK_SYMBOLS:
		if symbol == double_symbol:
			continue
		expect(is_equal_approx(float(double_game.state.market.rows[symbol].price), float(double_prices_before[symbol])), "ID35 leaves non-linked stock row price unchanged")
		expect(is_equal_approx(float(double_game.state.market.prices[symbol]), float(double_prices_before[symbol])), "ID35 leaves non-linked market price unchanged")
		expect(is_equal_approx(float(double_game.state.market.history[symbol].back()), float(double_history_tails_before[symbol])), "ID35 leaves non-linked history unchanged")
	expect(int(double_game.state.market.index) == _market_index(double_game.state.market), "ID35 refreshes aggregate market index")
