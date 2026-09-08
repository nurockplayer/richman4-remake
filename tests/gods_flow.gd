extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")

var checks: int = 0
var failures: int = 0


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _definition() -> Dictionary:
	var raw: Dictionary = Fixture.make()
	raw["nodes"] = []
	for index in range(18):
		raw["nodes"].append({
			"id": index + 1,
			"x": index * 120,
			"y": (index % 3) * 120,
			"adjacent": [(index + 17) % 18 + 1, (index + 1) % 18 + 1],
			"type_and_idx": 0,
			"event_code": 0,
			"status_bits": 0,
			"visual_index": 0,
		})
	raw["nodes"][2]["type_and_idx"] = 2001
	raw["nodes"][5]["type_and_idx"] = 2002
	for index in [8, 9]:
		raw["nodes"][index]["type_and_idx"] = 4001
	raw["facilities"] = [{
		"id": 1,
		"display_name": "測試設施",
		"name_bytes_hex": "74657374000000000000000000000000",
		"facility_type": 0,
		"owner": 0,
		"level": 0,
		"tmp_state": 0,
		"land_price": 1000,
		"price_per_level": 300,
		"house_price": 300,
		"reserved_hex": "6400c8002c019001f401",
	}]
	var loaded: Dictionary = Maps.normalize_map(raw, true)
	_expect(bool(loaded.get("ok", false)), "god fixture normalizes")
	return loaded.get("definition", {})


func _new_gods_game(player_count: int = 2) -> Game:
	return Game.new_game_on_board(123, player_count, _definition(), {
		"original_facilities": true,
		"original_gods": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
		"day_limit": 0,
	})


func _reset_actors(game: Game) -> void:
	var index: int = 0
	for actor in game.state["god_objects"]:
		actor["owner"] = -1
		actor["days"] = 0
		actor["node"] = 10 + index
		index += 1
	for player in game.state["players"]:
		player["god_id"] = 0
		player["hospital_days"] = 0


func _attach(game: Game, player_id: int, god_id: int) -> void:
	if game._god_object(god_id).is_empty():
		game._spawn_god(god_id)
	var actor: Dictionary = game._god_object(god_id)
	actor["owner"] = -1
	actor["days"] = 0
	_expect(game._attach_god(player_id, god_id), "god %d attaches" % god_id)


func _test_spawn_and_step_pickup() -> void:
	var game: Game = _new_gods_game()
	_expect(game != null, "v6 game starts")
	if game == null:
		return
	_expect_equal(game.state["version"], 6, "god game uses v6 save")
	_expect_equal(game.state["god_objects"].size(), 6, "six initial god objects spawn")
	_reset_actors(game)
	var actor: Dictionary = game._god_object(3)
	actor["node"] = 1
	game.state["players"][0]["position"] = 0
	game._process_god_step(0, 1)
	_expect_equal(game.state["players"][0]["god_id"], 3, "each movement step can pick up a god")
	_expect_equal(int(actor["owner"]), 0, "picked up god follows owner")
	game.state["players"][0]["position"] = 2
	game._sync_attached_gods()
	_expect_equal(int(actor["node"]), 2, "attached god follows movement")


func _test_cash_and_cards() -> void:
	var game: Game = _new_gods_game()
	if game == null:
		return
	_reset_actors(game)
	var other_before: int = int(game.state["players"][1]["cash"])
	_attach(game, 0, 1)
	_expect(int(game.state["players"][1]["cash"]) < other_before, "small wealth god collects from each other player")
	var wealth_large_before: int = int(game.state["players"][0]["cash"])
	game._detach_god(1, "test", false)
	_attach(game, 0, 2)
	_expect(int(game.state["players"][0]["cash"]) > wealth_large_before, "large wealth god receives bank cash")

	var poor_before: int = int(game.state["players"][0]["cash"])
	game._detach_god(2, "test", false)
	_attach(game, 0, 5)
	_expect(int(game.state["players"][0]["cash"]) < poor_before, "small poor god pays each other player")
	var poor_large_before: int = int(game.state["players"][0]["cash"])
	game._detach_god(5, "test", false)
	_attach(game, 0, 6)
	_expect(int(game.state["players"][0]["cash"]) < poor_large_before, "large poor god pays the bank")

	game._detach_god(6, "test", false)
	var cards_before: int = game.state["players"][0]["cards"].size()
	_attach(game, 0, 3)
	_expect_equal(game.state["players"][0]["cards"].size(), cards_before + 1, "small fortune god grants one card")
	game._detach_god(3, "test", false)
	var cards_large_before: int = game.state["players"][0]["cards"].size()
	_attach(game, 0, 4)
	_expect_equal(game.state["players"][0]["cards"].size(), cards_large_before + 2, "large fortune god grants two cards")

	game._detach_god(4, "test", false)
	game.state["players"][0]["cards"] = ["均富", "均貧", "購地"]
	_attach(game, 0, 7)
	_expect_equal(game.state["players"][0]["cards"].size(), 2, "small unlucky god removes one card")
	game._detach_god(7, "test", false)
	game.state["players"][0]["cards"] = ["均富", "均貧", "購地", "停留"]
	_attach(game, 0, 8)
	_expect_equal(game.state["players"][0]["cards"].size(), 2, "large unlucky god removes half the cards")
	for card_count in [1, 3, 5]:
		var odd_game: Game = _new_gods_game()
		_reset_actors(odd_game)
		odd_game.state["players"][0]["cards"] = ["均富", "均貧", "購地", "停留", "烏龜"].slice(0, card_count)
		_attach(odd_game, 0, 8)
		_expect_equal(odd_game.state["players"][0]["cards"].size(), card_count - int(floor(float(card_count) / 2.0)), "large unlucky god floors half-card loss for %d cards" % card_count)


func _test_non_current_bankruptcy_preserves_movement() -> void:
	var game: Game = _new_gods_game(3)
	if game == null:
		return
	# The mover is player 0. Let small wealth god 1 bankrupt player 1 while the
	# mover is between graph steps, then verify that player 0's pending movement
	# and bank state survive the unrelated bankruptcy.
	_reset_actors(game)
	var wealth: Dictionary = game._god_object(1)
	wealth["node"] = 1
	var mover: Dictionary = game.state["players"][0]
	var debtor: Dictionary = game.state["players"][1]
	mover["position"] = 1
	mover["previous_position"] = 0
	debtor["cash"] = 0
	debtor["deposit"] = 0
	game.state["current_player"] = 0
	game.state["phase"] = "await_route"
	game.state["last_total"] = 2
	game.state["remaining_steps"] = 1
	game.state["pending_movement"] = {"player_id": 0, "current_node": 1, "previous_node": 0}
	game.state["route_options"] = [2]
	game.state["bank_access"] = true
	game.state["bank_landing"] = true
	game._process_god_step(0, 1)
	_expect(not bool(debtor["alive"]), "small wealth god can bankrupt a non-current player during movement")
	_expect_equal(game.state["remaining_steps"], 1, "unrelated bankruptcy preserves mover remaining steps")
	_expect_equal(game.state["pending_movement"], {"player_id": 0, "current_node": 1, "previous_node": 0}, "unrelated bankruptcy preserves mover pending movement")
	_expect_equal(game.state["route_options"], [2], "unrelated bankruptcy preserves mover route options")
	_expect(bool(game.state["bank_access"]) and bool(game.state["bank_landing"]), "unrelated bankruptcy preserves mover bank state")
	game._graph_continue_movement(0)
	_expect_equal(int(mover["position"]), 2, "mover continues after unrelated bankruptcy")
	_expect_equal(game.state["phase"], "await_roll", "completed movement returns to await_roll")


func _test_rent_and_build_effects() -> void:
	var game: Game = _new_gods_game()
	if game == null:
		return
	_reset_actors(game)
	var debtor: Dictionary = game.state["players"][0]
	var creditor: Dictionary = game.state["players"][1]
	debtor["cash"] = 1000
	debtor["deposit"] = 0
	creditor["cash"] = 0
	_attach(game, 0, 2)
	debtor["cash"] = 1000
	debtor["rent_shield"] = 1
	game._charge_rent(0, 1, 100)
	_expect_equal(int(debtor["cash"]), 1000, "large wealth waives rent")
	_expect_equal(int(debtor["rent_shield"]), 1, "waived rent does not consume rent shield")
	debtor["rent_shield"] = 0
	game._detach_god(2, "test", false)
	_attach(game, 0, 1)
	debtor["cash"] = 1000
	creditor["cash"] = 0
	game._charge_rent(0, 1, 100)
	_expect_equal(int(debtor["cash"]), 950, "small wealth halves rent")
	game._detach_god(1, "test", false)
	_attach(game, 0, 5)
	debtor["cash"] = 1000
	creditor["cash"] = 0
	game._charge_rent(0, 1, 100)
	_expect_equal(int(debtor["cash"]), 850, "small poor raises rent by half")
	game._detach_god(5, "test", false)
	debtor["cash"] = 1000000
	debtor["deposit"] = 0
	_attach(game, 0, 6)
	debtor["cash"] = 1000
	creditor["cash"] = 0
	game._charge_rent(0, 1, 100)
	_expect_equal(int(debtor["cash"]), 800, "large poor doubles rent")

	game._detach_god(6, "test", false)
	_attach(game, 0, 4)
	var property: Dictionary = game.state["board"][2]
	property["owner"] = 0
	debtor["properties"] = [2]
	debtor["cash"] = 100000
	debtor["position"] = 2
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = false
	var build_result: Dictionary = game.choose_action("upgrade")
	_expect(bool(build_result.get("ok", false)), "fortune allows a normal upgrade")
	_expect_equal(int(property["building_level"]), 2, "fortune adds a free legal construction level")

	game._detach_god(4, "test", false)
	_attach(game, 0, 9)
	property["owner"] = -1
	property["building_level"] = 1
	game._apply_god_property_effect(0, property, true)
	_expect_equal(int(property["building_level"]), 2, "angel can improve an unowned property")
	game._detach_god(9, "test", false)
	_attach(game, 0, 10)
	game._apply_god_property_effect(0, property, true)
	_expect_equal(int(property["building_level"]), 1, "demon can lower an unowned property")
	_expect_equal(int(property["owner"]), -1, "angel and demon preserve unowned ownership")

	var buy_game: Game = _new_gods_game()
	_reset_actors(buy_game)
	_attach(buy_game, 0, 4)
	var facility: Dictionary = buy_game.state["board"][8]
	var buy_player: Dictionary = buy_game.state["players"][0]
	buy_player["position"] = 8
	buy_player["cash"] = 100000
	buy_game.state["phase"] = "await_action"
	buy_game.state["current_player"] = 0
	buy_game.state["property_action_used"] = false
	var cancel_buy: Dictionary = buy_game.choose_action("buy")
	_expect(not bool(cancel_buy.get("ok", false)), "fortune facility buy requires a human type choice")
	_expect_equal(int(facility["owner"]), -1, "cancelled fortune facility buy keeps ownership unchanged")
	var facility_buy: Dictionary = buy_game.choose_action("buy", {"facility_type": 1})
	_expect(bool(facility_buy.get("ok", false)), "fortune facility buy accepts a supported type")
	_expect_equal(int(facility["owner"]), 0, "fortune facility buy records ownership")
	_expect_equal(int(facility["facility_type"]), 1, "fortune facility buy records selected type")
	_expect_equal(int(facility["building_level"]), 1, "fortune facility buy gets a free first level")
	_expect_equal(int(buy_player["cash"]), 99000, "fortune facility buy charges land price only")
	var housing: Dictionary = buy_game.state["board"][2]
	housing["owner"] = -1
	housing["building_level"] = 0
	buy_player["position"] = 2
	buy_player["properties"] = [8]
	buy_player["cash"] = 100000
	buy_game.state["property_action_used"] = false
	var housing_buy: Dictionary = buy_game.choose_action("buy")
	_expect(bool(housing_buy.get("ok", false)), "fortune housing buy succeeds")
	_expect_equal(int(housing["building_level"]), 1, "fortune housing buy gets a free extra level")
	_expect_equal(int(buy_player["cash"]), 99000, "fortune housing buy charges land price")


func _test_facility_charge_effects() -> void:
	var game: Game = _new_gods_game()
	if game == null:
		return
	_reset_actors(game)
	var facility: Dictionary = game.state["board"][8]
	var source_object_id: int = int(facility.get("source_object_id", -1))
	game._update_facility_records(source_object_id, {"owner": 1, "building_level": 1, "facility_type": 1, "facility_state": 0})
	var debtor: Dictionary = game.state["players"][0]
	var creditor: Dictionary = game.state["players"][1]
	debtor["position"] = 8
	debtor["cash"] = 1000
	debtor["rent_shield"] = 1
	creditor["cash"] = 0
	_attach(game, 0, 2)
	debtor["cash"] = 1000
	debtor["rent_shield"] = 1
	var god2_debtor_cash: int = int(debtor["cash"])
	var god2_creditor_cash: int = int(creditor["cash"])
	game.state["last_roll_total"] = 1
	game.state["last_total"] = 1
	game._resolve_facility_visit(0, facility)
	var service: Dictionary = game.state["last_event"]
	_expect(bool(service.get("type", "") == "god_charge_waived"), "god2 facility charge records a waiver after service")
	_expect(int(service.get("amount", 0)) > 0, "god2 waiver follows a fee-bearing facility service")
	_expect_equal(int(debtor["rent_shield"]), 1, "god2 waived facility fee preserves rent shield")
	_expect_equal(int(debtor["cash"]), god2_debtor_cash, "god2 waived facility fee leaves debtor cash unchanged")
	_expect_equal(int(creditor["cash"]), god2_creditor_cash, "god2 waived facility fee leaves creditor cash unchanged")

	game._detach_god(2, "test", false)
	debtor["cash"] = 1000
	debtor["rent_shield"] = 1
	creditor["cash"] = 0
	var ordinary_debtor_cash: int = int(debtor["cash"])
	var ordinary_creditor_cash: int = int(creditor["cash"])
	game._resolve_facility_visit(0, facility)
	_expect_equal(int(debtor["rent_shield"]), 0, "ordinary facility fee consumes rent shield")
	_expect_equal(int(debtor["cash"]), ordinary_debtor_cash, "ordinary rent shield absorbs facility fee")
	_expect_equal(int(creditor["cash"]), ordinary_creditor_cash, "ordinary rent shield leaves creditor cash unchanged")

	var legacy_game: Game = Game.new_game_on_board(124, 2, _definition(), {
		"original_facilities": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
		"day_limit": 0,
	})
	_expect(legacy_game != null, "legacy facility fixture creates")
	if legacy_game == null:
		return
	_expect_equal(int(legacy_game.state.get("version", -1)), 5, "legacy facility fixture remains v5")
	var legacy_debtor: Dictionary = legacy_game.state["players"][0]
	legacy_debtor["rent_shield"] = 1
	var legacy_cash_before: int = int(legacy_debtor["cash"])
	legacy_game._charge_rent(0, 1, 0)
	_expect_equal(int(legacy_debtor["rent_shield"]), 0, "legacy zero rent still consumes rent shield")
	_expect_equal(int(legacy_debtor["cash"]), legacy_cash_before, "legacy zero rent leaves cash unchanged")
	_expect_equal(str(legacy_game.state["last_event"].get("type", "")), "rent_blocked", "legacy zero rent keeps rent-blocked event")


func _test_land_god_and_dog() -> void:
	var game: Game = _new_gods_game()
	if game == null:
		return
	_reset_actors(game)
	var property: Dictionary = game.state["board"][2]
	property["owner"] = 1
	game.state["players"][1]["properties"] = [2]
	game.state["players"][0]["cash"] = 100000
	game.state["players"][0]["position"] = 2
	_attach(game, 0, 12)
	game._graph_visit_tile(0, property, true)
	game.state["phase"] = "await_action"
	game.state["current_player"] = 0
	game.state["last_roll"] = [1]
	game.end_turn()
	_expect_equal(int(property["owner"]), 0, "land god occupies the final landing")
	_expect(game.state["players"][0]["properties"].has(2), "land god synchronizes player ownership")
	_expect(not game.state["players"][1]["properties"].has(2), "land god removes the old ownership reference")

	game._detach_god(12, "test", false)
	var dog: Dictionary = game._god_object(11)
	dog["node"] = 0
	game.state["players"][0]["vehicle"] = "walking"
	game._process_god_step(0, 0)
	_expect_equal(int(game.state["players"][0]["hospital_days"]), 3, "walking encounter causes three hospital days")
	_expect(game._god_object(11).is_empty(), "encountered dog is removed before pair respawn")
	game.state["players"][0]["hospital_days"] = 0
	var replacement: Dictionary = game._god_object(12)
	_expect(not replacement.is_empty(), "dog encounter attempts paired land god respawn")
	game._remove_god(12)
	dog = {"id": 11, "node": 0, "owner": -1, "days": 0}
	game.state["god_objects"].append(dog)
	game.state["players"][0]["vehicle"] = "car"
	game._process_god_step(0, 0)
	_expect_equal(int(game.state["players"][0]["hospital_days"]), 0, "vehicle encounter removes dog without hospitalization")


func _test_lifecycle_and_gates() -> void:
	var game: Game = _new_gods_game()
	if game == null:
		return
	_reset_actors(game)
	_attach(game, 0, 1)
	var actor: Dictionary = game._god_object(1)
	game.state["phase"] = "await_action"
	game.state["current_player"] = 0
	game.end_turn()
	game.state["phase"] = "await_action"
	game.end_turn()
	_expect_equal(int(game.state["day"]), 2, "god day advances once per complete player cycle")
	_expect_equal(int(actor["days"]), 6, "attached god loses one day per cycle")

	game._detach_god(1, "test", false)
	_attach(game, 0, 7)
	var property: Dictionary = game.state["board"][2]
	property["owner"] = -1
	game.state["players"][0]["position"] = 2
	game.state["players"][0]["cash"] = 100000
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = false
	var before: Dictionary = property.duplicate(true)
	var blocked: Dictionary = game.choose_action("buy")
	_expect(not bool(blocked.get("ok", false)), "unlucky god blocks property investment")
	_expect_equal(property, before, "blocked investment does not mutate the property")


func _initialize() -> void:
	_test_spawn_and_step_pickup()
	_test_cash_and_cards()
	_test_non_current_bankruptcy_preserves_movement()
	_test_rent_and_build_effects()
	_test_facility_charge_effects()
	_test_land_god_and_dog()
	_test_lifecycle_and_gates()
	print("God flow checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
