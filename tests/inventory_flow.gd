extends SceneTree

const Inventory = preload("res://game/core/inventory_rules.gd")
const Catalogue = preload("res://game/content/original_inventory.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_finite_card_pool_and_weighted_draw()
	_test_card_capacity_evicts_first_cheapest()
	_test_tool_capacity_does_not_lose_pool()
	_test_invalid_quantities_are_atomic()
	_test_shop_quotes_round_after_total()
	_test_research_tools_have_no_shared_limit()
	_test_four_player_initial_inventory()
	print("Inventory flow checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures else 0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _card_total(supply: Dictionary) -> int:
	var total := 0
	for record in Catalogue.cards():
		total += int(supply["cards"][str(record["id"])])
	return total


func _tool_total(supply: Dictionary, source_ids: Array) -> int:
	var total := 0
	for source_id in source_ids:
		var record: Dictionary = Catalogue.tools()[int(source_id) - 1]
		total += int(supply["tools"][str(record["id"])])
	return total


func _test_finite_card_pool_and_weighted_draw() -> void:
	var first_supply: Dictionary = Inventory.new_supply()
	var second_supply: Dictionary = Inventory.new_supply()
	for record in Catalogue.cards():
		var card_id := str(record["id"])
		first_supply["cards"][card_id] = 0
		second_supply["cards"][card_id] = 0
	first_supply["cards"]["均富"] = 1
	first_supply["cards"]["均貧"] = 3
	second_supply["cards"]["均富"] = 1
	second_supply["cards"]["均貧"] = 3
	var probe := RandomNumberGenerator.new()
	probe.seed = 713
	var expected_roll := probe.randi_range(1, 4)
	var first_rng := RandomNumberGenerator.new()
	var second_rng := RandomNumberGenerator.new()
	first_rng.seed = 713
	second_rng.seed = 713
	var first_draw := Inventory.draw_card(first_supply, first_rng)
	var second_draw := Inventory.draw_card(second_supply, second_rng)
	var expected_card := "均富" if expected_roll == 1 else "均貧"
	_expect_equal(first_draw, expected_card, "draw follows remaining-supply weight")
	_expect_equal(first_draw, second_draw, "same shared RNG seed draws the same card")
	_expect_equal(_card_total(first_supply), 3, "drawing consumes exactly one finite card")
	_expect_equal(first_supply, second_supply, "equal seeds preserve equal supply state")

	var received_supply: Dictionary = Inventory.new_supply()
	for record in Catalogue.cards():
		received_supply["cards"][str(record["id"])] = 0
	received_supply["cards"]["均富"] = 1
	var received_cards: Array = []
	var receive_rng := RandomNumberGenerator.new()
	receive_rng.seed = 991
	var receive_before_total := _card_total(received_supply)
	var receive := Inventory.receive_random_card(received_supply, received_cards, receive_rng)
	_expect(bool(receive.get("ok", false)), "random card receive succeeds")
	_expect_equal(received_cards, ["均富"], "random card receive appends the selected card")
	_expect_equal(_card_total(received_supply) + received_cards.size(), receive_before_total, "atomic random receive debits the pool once")

	var grant_supply: Dictionary = Inventory.new_supply()
	var cards: Array = []
	var before_grant_total := _card_total(grant_supply)
	var grant := Inventory.grant_card(grant_supply, cards, "均富")
	_expect(bool(grant.get("ok", false)), "finite card grant succeeds")
	_expect_equal(_card_total(grant_supply) + cards.size(), before_grant_total, "grant preserves pool plus player conservation")
	var before_consume_total := _card_total(grant_supply)
	var consume := Inventory.consume_card(grant_supply, cards, "均富")
	_expect(bool(consume.get("ok", false)), "card consume succeeds")
	_expect_equal(_card_total(grant_supply), before_consume_total + 1, "consumed card returns to the finite pool")
	_expect(cards.is_empty(), "consumed card leaves the player array empty")


func _test_card_capacity_evicts_first_cheapest() -> void:
	var supply: Dictionary = Inventory.new_supply()
	var cards: Array = [
		"改建", "拆除", "均富", "均貧", "購地", "換地", "換屋", "轉向",
		"拍賣", "天使", "惡魔", "怪獸", "搶奪", "停留", "烏龜",
	]
	for card_id in cards:
		supply["cards"][card_id] = int(supply["cards"][card_id]) - 1
	var incoming_id := "免費"
	var incoming_before: int = int(supply["cards"][incoming_id])
	var evicted_before: int = int(supply["cards"]["改建"])
	var result := Inventory.grant_card(supply, cards, incoming_id)
	_expect(bool(result.get("ok", false)), "full card inventory accepts a card by eviction")
	_expect_equal(result.get("evicted_card_id", ""), "改建", "equal-price eviction keeps the first cheapest card")
	_expect_equal(cards.size(), Inventory.CARD_CAPACITY, "card inventory remains at capacity")
	_expect_equal(cards[0], "拆除", "evicted card is removed from its original slot")
	_expect_equal(cards[cards.size() - 1], incoming_id, "new card is appended after eviction")
	_expect_equal(int(supply["cards"][incoming_id]), incoming_before - 1, "incoming card leaves the finite pool")
	_expect_equal(int(supply["cards"]["改建"]), evicted_before + 1, "evicted card returns to the finite pool")
	_expect_equal(_card_total(supply) + cards.size(), _initial_card_total(), "full grant preserves finite card conservation")


func _initial_card_total() -> int:
	var total := 0
	for record in Catalogue.cards():
		total += int(record["initial_supply"])
	return total


func _test_tool_capacity_does_not_lose_pool() -> void:
	var supply: Dictionary = Inventory.new_supply()
	var tools: Dictionary = Inventory.empty_tools()
	var grant := Inventory.grant_tool(supply, tools, 1, 9)
	_expect(bool(grant.get("ok", false)), "finite tool grant reaches nine-unit capacity")
	var supply_before_failed_grant := supply.duplicate(true)
	var tools_before_failed_grant := tools.duplicate(true)
	var failed := Inventory.grant_tool(supply, tools, 1, 1)
	_expect(not bool(failed.get("ok", false)), "tenth finite tool is rejected")
	_expect_equal(supply, supply_before_failed_grant, "full tool inventory does not lose shared supply")
	_expect_equal(tools, tools_before_failed_grant, "full tool inventory does not mutate player tools")
	var consume := Inventory.consume_tool(supply, tools, 1, 9)
	_expect(bool(consume.get("ok", false)), "finite tool consume succeeds")
	_expect_equal(int(supply["tools"]["機器娃娃"]), 10, "finite tool consume restores the pool")
	_expect(tools.is_empty(), "consuming all finite tools removes the sparse entry")

	var vehicle_supply: Dictionary = Inventory.new_supply()
	vehicle_supply["tools"]["汽車"] = 0
	var vehicle_tools: Dictionary = {"汽車": 10}
	var other_vehicle_grant := Inventory.grant_tool(vehicle_supply, vehicle_tools, "機車", 1)
	_expect(bool(other_vehicle_grant.get("ok", false)), "a vehicle grant accepts a container with another vehicle stored at ten")
	_expect_equal(int(vehicle_tools["汽車"]), 10, "granting another vehicle preserves the ten-unit stored vehicle")
	_expect_equal(int(vehicle_tools.get("機車", 0)), 1, "granting another vehicle enters its backpack")

	var vehicle_consume := Inventory.consume_tool(vehicle_supply, vehicle_tools, "汽車", 9)
	_expect(bool(vehicle_consume.get("ok", false)), "vehicle consume works from a ten-unit stored backpack")
	_expect_equal(int(vehicle_tools["汽車"]), 1, "consuming nine stored vehicles leaves the last one")
	_expect_equal(int(vehicle_supply["tools"]["汽車"]), 9, "consuming stored vehicles returns them to finite supply")


func _test_invalid_quantities_are_atomic() -> void:
	var supply: Dictionary = Inventory.new_supply()
	var tools: Dictionary = {"路障": 2}
	for invalid_quantity in [0, -1, 1.5, 10, true]:
		var before_supply := supply.duplicate(true)
		var before_tools := tools.duplicate(true)
		var grant := Inventory.grant_tool(supply, tools, "路障", invalid_quantity)
		_expect(not bool(grant.get("ok", false)), "invalid grant quantity is rejected: %s" % str(invalid_quantity))
		_expect_equal(supply, before_supply, "invalid grant quantity leaves supply unchanged")
		_expect_equal(tools, before_tools, "invalid grant quantity leaves tools unchanged")
		var consume := Inventory.consume_tool(supply, tools, "路障", invalid_quantity)
		_expect(not bool(consume.get("ok", false)), "invalid consume quantity is rejected: %s" % str(invalid_quantity))
		_expect_equal(supply, before_supply, "invalid consume quantity leaves supply unchanged")
		_expect_equal(tools, before_tools, "invalid consume quantity leaves tools unchanged")

	var before_card_supply := supply.duplicate(true)
	var before_cards: Array = ["均富"]
	var cards_before := before_cards.duplicate(true)
	var invalid_card := Inventory.grant_card(supply, before_cards, "不存在的卡")
	_expect(not bool(invalid_card.get("ok", false)), "invalid card ID is rejected")
	_expect_equal(supply, before_card_supply, "invalid card ID leaves supply unchanged")
	_expect_equal(before_cards, cards_before, "invalid card ID leaves cards unchanged")


func _test_shop_quotes_round_after_total() -> void:
	_expect_equal(Inventory.quote_buy("card", "均富"), 200, "card purchase uses listed price")
	_expect_equal(Inventory.quote_sale("card", "均富"), 180, "card sale uses ninety percent")
	_expect_equal(Inventory.quote_sale("card", "購地"), 31, "card sale truncates a fractional value")
	_expect_equal(Inventory.quote_buy("tool", "地雷", 3), 75, "tool purchase multiplies listed price")
	_expect_equal(Inventory.quote_sale("tool", "地雷", 3), 67, "tool sale truncates after multiplying quantity")
	_expect_equal(Inventory.buy_price("tool", "地雷", 3), 75, "buy price alias follows purchase quote")
	_expect_equal(Inventory.sale_price("tool", "地雷", 3), 67, "sale price alias follows sale quote")
	_expect_equal(Inventory.quote_buy("card", "均富", 0), -1, "invalid quote quantity is rejected")
	_expect_equal(Inventory.quote_sale("missing", "均富"), -1, "invalid quote kind is rejected")


func _test_research_tools_have_no_shared_limit() -> void:
	var supply: Dictionary = Inventory.new_supply()
	var tools: Dictionary = Inventory.empty_tools()
	var before_supply := supply.duplicate(true)
	var grant := Inventory.grant_tool(supply, tools, 9, 9)
	_expect(bool(grant.get("ok", false)), "research tool can be granted without stock")
	_expect_equal(supply, before_supply, "research grant does not change shared supply")
	_expect_equal(int(tools["機器工人"]), 9, "research tool reaches the per-type cap")
	var full_before_supply := supply.duplicate(true)
	var full_before_tools := tools.duplicate(true)
	var full := Inventory.grant_tool(supply, tools, "機器工人", 1)
	_expect(not bool(full.get("ok", false)), "research tool still obeys the per-type cap")
	_expect_equal(supply, full_before_supply, "research cap failure leaves supply unchanged")
	_expect_equal(tools, full_before_tools, "research cap failure leaves tools unchanged")
	var consume := Inventory.consume_tool(supply, tools, 9, 9)
	_expect(bool(consume.get("ok", false)), "research tool consume succeeds")
	_expect_equal(supply, before_supply, "research consume does not create shared supply")
	_expect(tools.is_empty(), "consuming research tools clears the sparse entry")


func _test_four_player_initial_inventory() -> void:
	var supply: Dictionary = Inventory.new_supply()
	var players: Array = []
	for player_id in range(4):
		players.append({"id": player_id, "cards": ["均富"], "tools": {"路障": 2}, "points": 99})
	var result := Inventory.initialize_players(players, supply)
	_expect(bool(result.get("ok", false)), "four players receive the original opening inventory")
	for source_id in [1, 2, 3, 4, 8]:
		var record: Dictionary = Catalogue.tools()[source_id - 1]
		_expect_equal(int(supply["tools"][str(record["id"])]), 6, "finite opening tool %d leaves ten minus four" % source_id)
	for source_id in [5, 6, 7]:
		var record: Dictionary = Catalogue.tools()[source_id - 1]
		_expect_equal(int(supply["tools"][str(record["id"])]), 10, "unreceived finite opening tool %d remains at ten" % source_id)
	var expected_ids := ["機器娃娃", "路障", "地雷", "定時炸彈", "遙控骰子", "機器工人"]
	for player in players:
		_expect_equal(player["cards"], [], "new player cards start empty")
		_expect_equal(player["points"], 0, "new player points start at zero")
		for tool_id in expected_ids:
			_expect_equal(int(player["tools"].get(tool_id, 0)), 1, "new player receives opening tool %s" % tool_id)
		_expect_equal(player["tools"].size(), expected_ids.size(), "opening tools contain exactly six entries")
	_expect_equal(int(supply["tools"]["機器工人"]), 0, "research opening tool keeps its zero shared stock")

	var shortage_supply: Dictionary = Inventory.new_supply()
	shortage_supply["tools"]["機器娃娃"] = 0
	var existing_player: Dictionary = {"cards": ["均富"], "tools": {"路障": 2}, "points": 99}
	var before_shortage_supply := shortage_supply.duplicate(true)
	var before_existing_player := existing_player.duplicate(true)
	var shortage := Inventory.initialize_player(existing_player, shortage_supply)
	_expect(not bool(shortage.get("ok", false)), "opening initialization rejects insufficient finite stock")
	_expect_equal(shortage_supply, before_shortage_supply, "failed opening initialization leaves supply unchanged")
	_expect_equal(existing_player, before_existing_player, "failed opening initialization leaves player unchanged")
