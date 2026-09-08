extends SceneTree

## Synthetic facility runtime contract. This fixture contains no original data.
const GameState = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	var game: Object = _new_game(1801)
	_expect(game != null, "facility graph starts with explicit facility mode")
	if game == null:
		_finish()
		return
	_expect_equal(game.state.get("version", -1), 5, "facility setup uses v5 save")
	_expect_equal(game.state.get("original_facilities", false), true, "facility mode is persisted")
	_expect_equal(game.state["players"][0]["properties"], [], "new facility game starts without owned assets")
	_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "new facility save validates")

	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["players"][0]["position"] = 1
	game.state["property_action_used"] = false
	game._set_action_options(0)
	_expect(game.state["action_options"].has("buy"), "unowned facility offers buy")
	var buy: Dictionary = game.choose_action("buy")
	_expect(bool(buy.get("ok", false)), "facility land can be bought")
	_expect_equal(game.state["players"][0]["cash"], 14000, "facility land purchase charges land price")
	_expect_equal(game.state["board"][1]["owner"], 0, "facility owner is shared by first node")
	_expect_equal(game.state["board"][2]["owner"], 0, "facility owner is shared by duplicate node")
	_expect_equal(game.state["players"][0]["properties"], [1], "duplicate facility is one owned asset")

	game.state["property_action_used"] = false
	game._set_action_options(0)
	_expect(game.state["action_options"].has("build_facility"), "owned level zero facility offers build")
	var build: Dictionary = game.choose_action("build_facility", {"facility_type": 1})
	_expect(bool(build.get("ok", false)), "hotel facility can be built")
	_expect_equal(game.state["players"][0]["cash"], 13000, "facility build charges land price again")
	_expect_equal(game.state["board"][1]["building_level"], 1, "facility build reaches level one")
	_expect_equal(game.state["board"][2]["building_level"], 1, "facility build syncs duplicate level")
	_expect_equal(game.state["board"][1]["facility_type"], 1, "facility build records selected type")

	game.state["property_action_used"] = false
	game._set_action_options(0)
	var upgrade: Dictionary = game.choose_action("upgrade")
	_expect(bool(upgrade.get("ok", false)), "facility upgrade uses existing action")
	_expect_equal(game.state["board"][1]["building_level"], 2, "facility upgrade increments level")
	_expect_equal(upgrade.get("event", {}).get("price", -1), 300, "facility upgrade uses fixed source cost")

	_test_facility_service(game)
	_test_inventory_targets(game)
	_test_save_rejection(game)
	_test_gas_remote_and_roadblock()
	_test_facility_roulette()
	_test_facility_finance()
	_test_packed_facility_expiry()
	_test_shared_facility_inventory_effects()
	_test_legacy_compatibility()
	var malformed_options := _options()
	malformed_options["original_inventory"] = "true"
	_expect(GameState.new_game_on_board(1821, 2, _definition(), malformed_options) == null, "facility mode rejects malformed inventory option before implication")
	_finish()


func _finish() -> void:
	print("Facility flow checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures else 0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _definition() -> Dictionary:
	var nodes: Array = []
	var edges: Array = [[1], [0, 2], [1, 3], [2, 4], [3, 5], [4, 6], [5]]
	var source_ids: Array = [0, 1, 1, 2, 3, 4, 5]
	var types: Array = [0, 4001, 4001, 4002, 4003, 4004, 4005]
	var facility_types: Array = [0, 0, 0, 1, 2, 3, 4]
	for index in range(edges.size()):
		var tile: Dictionary = {
			"index": index,
			"source_node_id": index + 1,
			"x": index * 80,
			"y": 100,
			"adjacent": edges[index].duplicate(),
			"type_and_idx": types[index],
			"visual_index": 0,
			"event_code": 0,
			"source_object_id": source_ids[index],
			"kind": "rest" if index == 0 else "facility",
			"name": "起點" if index == 0 else "設施 %d" % source_ids[index],
			"owner": -1,
			"building_level": 0,
			"cost": 1000,
			"land_price": 1000,
			"upgrade_cost": 300,
			"base_rent": 0,
			"rent": 0,
			"group": "facility:%d" % source_ids[index],
			"tax_amount": 0,
			"facility_type": facility_types[index],
			"facility_state": 0,
			"fee_by_level": [300, 100, 200, 300, 400, 500],
			"facility_node_index": 1 if source_ids[index] == 1 else index,
		}
		if index == 0:
			tile["cost"] = 0
			tile["land_price"] = 0
			tile["upgrade_cost"] = 0
		nodes.append(tile)
	var retained_facilities: Array = []
	for source_id in range(1, 6):
		retained_facilities.append({"id": source_id, "land_price": 1000, "upgrade_cost": 300, "reserved_hex": "6400c8002c019001f401"})
	return {
		"schema": "richman4.runtime-map/v1",
		"version": 1,
		"id": "Game:1",
		"name": "Synthetic facilities",
		"source": {
			"facilities": retained_facilities,
			"edition": "Game",
			"map_number": 1,
			"archive": "Game/map.mkf",
			"entry_index": 1,
			"payload_sha256": "a".repeat(64),
			"source_file_sha256": "b".repeat(64),
		},
		"supports_new_game": true,
		"original_facilities": true,
		"board": nodes,
		"start_position": 0,
	}


func _options() -> Dictionary:
	return {
		"start_date": {"year": 1998, "month": 1, "day": 1},
		"initial_fund": 30000,
		"original_facilities": true,
	}


func _new_game(seed_value: int) -> Object:
	return GameState.new_game_on_board(seed_value, 2, _definition(), _options())


func _set_facility(game: Object, source_object_id: int, owner_id: int, level: int, facility_type: int, facility_state: int = 0) -> void:
	var canonical_id: int = -1
	for index in range(game.state["board"].size()):
		var tile: Dictionary = game.state["board"][index]
		if tile.get("kind", "") == "facility" and int(tile.get("source_object_id", -1)) == source_object_id:
			if canonical_id < 0:
				canonical_id = int(tile.get("facility_node_index", index))
			tile["owner"] = owner_id
			tile["building_level"] = level
			tile["facility_type"] = facility_type
			tile["facility_state"] = facility_state
	for candidate in game.state["players"]:
		var properties: Array = []
		if int(candidate.get("id", -1)) == owner_id and canonical_id >= 0:
			properties.append(canonical_id)
		candidate["properties"] = properties
	game._recalculate_property_values()


func _prepare_graph_action(game: Object, player_id: int, position: int, phase: String = "await_action") -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["players"][player_id]["position"] = position
	game.state["property_action_used"] = false
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["remaining_steps"] = 0
	game.state["route_options"] = []
	game.state["pending_movement"] = {}
	game._set_action_options(player_id)


func _test_facility_service(game: Object) -> void:
	game.state["current_player"] = 1
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = false
	game.state["players"][1]["position"] = 2
	game.state["players"][1]["cash"] = 10000
	game.state["last_roll_total"] = 6
	game.state["last_total"] = 6
	game._graph_visit_tile(1, game.state["board"][1], true)
	var service: Dictionary = _last_event_of_type(game, "facility_service")
	_expect(not service.is_empty(), "hotel landing records facility service")
	_expect(service.has("resolved_roll"), "hotel event records roulette roll")
	_expect(int(service.get("fee", 0)) > 0, "hotel event records resolved fee")

	var before_sealed: int = int(game.state["players"][1]["cash"])
	game.state["board"][1]["facility_state"] = 0x51
	game.state["board"][2]["facility_state"] = 0x51
	game._graph_visit_tile(1, game.state["board"][2], true)
	_expect_equal(game.state["players"][1]["cash"], before_sealed, "sealed facility does not charge")
	game.state["board"][1]["facility_state"] = 0x50
	game.state["board"][2]["facility_state"] = 0x50
	game._graph_visit_tile(1, game.state["board"][2], true)
	_expect(int(game.state["players"][1]["cash"]) < before_sealed, "raised facility still charges with doubled service")


func _test_inventory_targets(game: Object) -> void:
	var player: Dictionary = game.state["players"][0]
	player["current_player"] = 0
	game.state["current_player"] = 0
	game.state["phase"] = "await_roll"
	game.state["property_action_used"] = false
	_expect(bool(Inventory.grant_card(game.state["inventory_supply"], player["cards"], "漲價").get("ok", false)), "stage facility raise card")
	var raise_targets: Array = game.inventory_target_tiles("漲價")
	_expect(raise_targets.has(1) and raise_targets.has(2), "raise target API exposes duplicate facility nodes")


func _test_save_rejection(game: Object) -> void:
	var invalid: Dictionary = game.to_dict()
	invalid["board"][2]["owner"] = 1
	_expect(not bool(GameState.validate_save(invalid).get("ok", false)), "save rejects split duplicate facility ownership")
	var invalid_state: Dictionary = game.to_dict()
	invalid_state["board"][1]["facility_state"] = 0x52
	_expect(not bool(GameState.validate_save(invalid_state).get("ok", false)), "save rejects malformed packed facility state")
	var invalid_research: Dictionary = game.to_dict()
	invalid_research["board"][1]["facility_type"] = 4
	invalid_research["board"][2]["facility_type"] = 4
	invalid_research["board"][1]["building_level"] = 1
	invalid_research["board"][2]["building_level"] = 1
	_expect(not bool(GameState.validate_save(invalid_research).get("ok", false)), "save rejects built research facility runtime")


func _test_gas_remote_and_roadblock() -> void:
	var game: Object = _new_game(1811)
	_expect(game != null, "gas remote and roadblock fixture creates")
	if game == null:
		return
	_set_facility(game, 4, 1, 1, 3)
	var gas_owner: Dictionary = game.state["players"][1]
	var mover: Dictionary = game.state["players"][0]
	mover["position"] = 4
	mover["previous_position"] = 3
	gas_owner["position"] = 0
	_prepare_graph_action(game, 1, 0, "await_roll")
	var roadblock: Dictionary = game.choose_action("use_tool", {"tool_id": "路障", "tile_id": 5})
	_expect(bool(roadblock.get("ok", false)), "opponent can place roadblock before gas station")
	_expect_equal(game.state["roadblocks"].get("5", -1), 1, "gas route records roadblock placer")

	_prepare_graph_action(game, 0, 4, "await_roll")
	_expect(bool(Inventory.grant_tool(game.state["inventory_supply"], mover["tools"], "汽車").get("ok", false)), "gas route can stage a car tool")
	var vehicle: Dictionary = game.choose_action("use_tool", {"tool_id": "汽車"})
	_expect(bool(vehicle.get("ok", false)), "gas route selects car for deterministic multiplier")
	var remote_supply_before: int = int(game.state["inventory_supply"]["tools"]["遙控骰子"])
	var remote: Dictionary = game.choose_action("use_tool", {"tool_id": "遙控骰子", "value": 4})
	_expect(bool(remote.get("ok", false)), "remote die can be queued before movement")
	_expect_equal(int(game.state["inventory_supply"]["tools"]["遙控骰子"]), remote_supply_before + 1, "remote die returns to shared supply on use")
	var roll_result: Dictionary = game.roll()
	_expect(bool(roll_result.get("ok", false)), "remote die roll completes through graph movement")
	_expect_equal(roll_result.get("dice", []), [4], "remote die supplies the exact gas route roll")
	_expect_equal(game.state["pending_remote_dice"], {}, "remote die pending state clears after roll")
	_expect_equal(game.state["last_roll_total"], 4, "complete roll total survives early roadblock stop")
	_expect_equal(mover["position"], 5, "roadblock stops movement at gas station")
	_expect_equal(game.state["remaining_steps"], 0, "roadblock consumes all remaining movement")
	_expect(not game.state["roadblocks"].has("5"), "roadblock is consumed on gas route collision")
	var service: Dictionary = _last_event_of_type(game, "facility_service")
	_expect(bool(service.get("admitted", false)), "gas station service is admitted after roadblock landing")
	_expect_equal(service.get("facility_type", -1), 3, "gas landing resolves as gas station")
	_expect_equal(service.get("last_roll_total", -1), 4, "gas fee uses complete remote roll total")
	_expect_equal(service.get("fee", -1), 4000, "car gas fee uses source multiplier formula")
	_expect_equal(mover["cash"], 11000, "gas fee charges mover cash")
	_expect_equal(gas_owner["cash"], 16000, "gas fee pays facility owner")


func _test_facility_roulette() -> void:
	var game: Object = _new_game(1812)
	_expect(game != null, "facility roulette fixture creates")
	if game == null:
		return
	_set_facility(game, 2, 1, 1, 1)
	_set_facility(game, 3, 1, 1, 2)
	var visitor: Dictionary = game.state["players"][0]
	var owner: Dictionary = game.state["players"][1]
	visitor["cash"] = 100000
	owner["cash"] = 0
	game.state["last_roll_total"] = 6
	game.state["last_total"] = 6
	game._graph_visit_tile(0, game.state["board"][3], true)
	var hotel_service: Dictionary = _last_event_of_type(game, "facility_service")
	_expect(int(hotel_service.get("resolved_roll", 0)) >= 1 and int(hotel_service.get("resolved_roll", 0)) <= 4, "hotel roulette resolves one of four source outcomes")
	_expect_equal(hotel_service.get("base_fee", -1), 100, "hotel roulette keeps level fee as base")
	_expect_equal(hotel_service.get("fee", -1), int(hotel_service.get("base_fee", 0)) * int(hotel_service.get("resolved_roll", 0)), "hotel roulette multiplies fee by resolved outcome")
	game._graph_visit_tile(0, game.state["board"][4], true)
	var shopping_service: Dictionary = _last_event_of_type(game, "facility_service")
	_expect(int(shopping_service.get("resolved_roll", 0)) >= 1 and int(shopping_service.get("resolved_roll", 0)) <= 6, "shopping center roulette resolves one of six source outcomes")
	_expect_equal(shopping_service.get("base_fee", -1), 100, "shopping roulette keeps level fee as base")
	_expect_equal(shopping_service.get("fee", -1), int(shopping_service.get("base_fee", 0)) * int(shopping_service.get("resolved_roll", 0)), "shopping roulette multiplies fee by resolved outcome")


func _test_facility_finance() -> void:
	var game: Object = _new_game(1813)
	_expect(game != null, "facility finance fixture creates")
	if game == null:
		return
	var player: Dictionary = game.state["players"][0]
	_prepare_graph_action(game, 0, 2)
	var bank_before_buy: int = int(game.state["bank"]["cash"])
	_expect(bool(game.choose_action("buy").get("ok", false)), "facility purchase enters financial ledger")
	_expect_equal(int(game.state["bank"]["cash"]), bank_before_buy + 1000, "facility land price is credited to bank")
	game.state["property_action_used"] = false
	game._set_action_options(0)
	var bank_before_build: int = int(game.state["bank"]["cash"])
	_expect(bool(game.choose_action("build_facility", {"facility_type": 1}).get("ok", false)), "facility construction enters financial ledger")
	_expect_equal(int(game.state["bank"]["cash"]), bank_before_build + 1000, "facility construction uses land price source amount")
	game.state["property_action_used"] = false
	game._set_action_options(0)
	var bank_before_upgrade: int = int(game.state["bank"]["cash"])
	_expect(bool(game.choose_action("upgrade").get("ok", false)), "facility upgrade enters financial ledger")
	_expect_equal(int(game.state["bank"]["cash"]), bank_before_upgrade + 300, "facility upgrade uses source upgrade price")
	_expect_equal(player["property_values"], 1600, "facility asset valuation counts land and built levels once")
	_expect_equal(game.get_player_wealth(0), int(player["cash"]) + int(player["deposit"]) + 1600, "facility wealth valuation includes one shared asset")
	_expect_equal(game.state["price_index"], 1, "facility price index starts at one")

	var payment_game: Object = _new_game(1814)
	_expect(payment_game != null, "facility payment fixture creates")
	if payment_game != null:
		_set_facility(payment_game, 4, 1, 1, 3)
		var payer: Dictionary = payment_game.state["players"][0]
		var payee: Dictionary = payment_game.state["players"][1]
		payer["cash"] = 100
		payer["deposit"] = 600
		payer["vehicle"] = "motorcycle"
		payer["vehicles"]["motorcycle"] = true
		payer["dice_count"] = 2
		payee["cash"] = 0
		payee["deposit"] = 0
		payment_game.state["bank"]["cash"] = 1000000
		payment_game.state["bank"]["deposits"] = 600
		payment_game.state["last_roll_total"] = 1
		payment_game.state["last_total"] = 1
		var bank_cash_before: int = int(payment_game.state["bank"]["cash"])
		payment_game._graph_visit_tile(0, payment_game.state["board"][5], true)
		_expect_equal(payer["cash"], 0, "facility payment consumes cash before deposit")
		_expect_equal(payer["deposit"], 200, "facility payment consumes only required deposit")
		_expect_equal(payee["cash"], 500, "facility payment reaches facility owner exactly")
		_expect_equal(int(payment_game.state["bank"]["cash"]), bank_cash_before - 400, "deposit sourced facility payment leaves bank cash once")
		payer["cash"] = 1000
		payer["deposit"] = 0
		payer["rent_shield"] = 1
		payment_game.state["bank"]["cash"] = bank_cash_before
		var shielded: int = int(payer["cash"])
		payment_game._graph_visit_tile(0, payment_game.state["board"][5], true)
		_expect_equal(payer["cash"], shielded, "rent shield blocks facility charge")
		_expect_equal(payer["rent_shield"], 0, "facility charge consumes one rent shield")
		_expect(not _last_event_of_type(payment_game, "facility_blocked").is_empty(), "blocked facility charge is recorded")

	var bankruptcy_game: Object = _new_game(1815)
	_expect(bankruptcy_game != null, "facility bankruptcy fixture creates")
	if bankruptcy_game != null:
		_set_facility(bankruptcy_game, 4, 1, 1, 3)
		var bankrupt_player: Dictionary = bankruptcy_game.state["players"][0]
		bankrupt_player["cash"] = 0
		bankrupt_player["deposit"] = 0
		bankrupt_player["vehicle"] = "motorcycle"
		bankrupt_player["vehicles"]["motorcycle"] = true
		bankrupt_player["dice_count"] = 2
		bankruptcy_game.state["last_roll_total"] = 1
		bankruptcy_game.state["last_total"] = 1
		bankruptcy_game._graph_visit_tile(0, bankruptcy_game.state["board"][5], true)
		_expect(bool(bankrupt_player["bankrupt"]), "unpaid facility fee declares bankruptcy")
		_expect_equal(bankruptcy_game.state["board"][5]["owner"], 1, "facility bankruptcy transfers shared asset to creditor")
		_expect_equal(bankruptcy_game.state["bankruptcy_auctions"][0]["property_ids"], [], "fee bankruptcy does not auction the creditor facility")
		_expect_equal(bankruptcy_game.state["board"][5]["owner"], 1, "fee bankruptcy leaves creditor facility ownership intact")
		_expect_equal(bankruptcy_game.state["phase"], "game_over", "facility bankruptcy ends a two-player game")


func _advance_full_round(game: Object) -> void:
	for _index in range(game.state["players"].size()):
		game.state["phase"] = "await_action"
		var result: Dictionary = game.end_turn()
		_expect(bool(result.get("ok", false)), "facility expiry turn advances")


func _test_packed_facility_expiry() -> void:
	var game: Object = _new_game(1816)
	_expect(game != null, "packed facility expiry fixture creates")
	if game == null:
		return
	_set_facility(game, 1, 0, 1, 1, 0x51)
	_expect_equal(game.state["board"][1]["facility_state"], 0x51, "sealed facility starts with packed low status")
	_advance_full_round(game)
	_expect_equal(game.state["board"][1]["facility_state"], 0x41, "one round expiry decrements packed high duration")
	_expect_equal(game.state["board"][2]["facility_state"], 0x41, "packed expiry synchronizes duplicate facility node")
	var expiry: Dictionary = _last_event_of_type(game, "facility_state_expired")
	_expect_equal(expiry.get("from_state", -1), 0x51, "expiry event records packed source state")
	_expect_equal(expiry.get("to_state", -1), 0x41, "expiry event records packed next state")
	for expected_state in [0x31, 0x21, 0x11, 0x00]:
		_advance_full_round(game)
		_expect_equal(game.state["board"][1]["facility_state"], expected_state, "packed facility status expires one round at a time")
	_expect_equal(game.state["board"][2]["facility_state"], 0, "packed expiry clears all duplicate node status")
	_expect_equal(game.state["price_index"], 1, "facility rounds do not invent a price increase schedule")


func _test_shared_facility_inventory_effects() -> void:
	var worker_game: Object = _new_game(1817)
	_expect(worker_game != null, "shared facility worker fixture creates")
	if worker_game != null:
		_set_facility(worker_game, 1, 0, 1, 1)
		_prepare_graph_action(worker_game, 0, 2, "await_roll")
		var worker: Dictionary = worker_game.choose_action("use_tool", {"tool_id": "機器工人", "tile_id": 2})
		_expect(bool(worker.get("ok", false)), "machine worker targets a shared facility from duplicate node")
		_expect_equal(worker_game.state["board"][1]["building_level"], 2, "facility worker upgrades canonical node")
		_expect_equal(worker_game.state["board"][2]["building_level"], 2, "facility worker upgrades duplicate node")
		_prepare_graph_action(worker_game, 0, 2)
		_expect(bool(Inventory.grant_card(worker_game.state["inventory_supply"], worker_game.state["players"][0]["cards"], "拆除").get("ok", false)), "facility demolition card can be staged")
		var demolition: Dictionary = worker_game.choose_action("use_card", {"card_id": "拆除", "tile_id": 2})
		_expect(bool(demolition.get("ok", false)), "demolition card targets a shared facility")
		_expect_equal(worker_game.state["board"][1]["building_level"], 1, "facility demolition downgrades canonical node")
		_expect_equal(worker_game.state["board"][2]["building_level"], 1, "facility demolition downgrades duplicate node")
		_expect(bool(Inventory.grant_card(worker_game.state["inventory_supply"], worker_game.state["players"][0]["cards"], "漲價").get("ok", false)), "facility raise card can be staged")
		var raise: Dictionary = worker_game.choose_action("use_card", {"card_id": "漲價", "tile_id": 2})
		_expect(bool(raise.get("ok", false)), "raise card targets a shared facility")
		_expect_equal(worker_game.state["board"][1]["facility_state"], 0x50, "raise card updates canonical status")
		_expect_equal(worker_game.state["board"][2]["facility_state"], 0x50, "raise card updates duplicate status")

	var seal_game: Object = _new_game(1818)
	_expect(seal_game != null, "shared facility seal fixture creates")
	if seal_game != null:
		_set_facility(seal_game, 1, 1, 1, 1)
		_prepare_graph_action(seal_game, 0, 2)
		_expect(bool(Inventory.grant_card(seal_game.state["inventory_supply"], seal_game.state["players"][0]["cards"], "查封").get("ok", false)), "facility seal card can be staged")
		var seal: Dictionary = seal_game.choose_action("use_card", {"card_id": "查封", "tile_id": 2})
		_expect(bool(seal.get("ok", false)), "seal card targets an opponent shared facility")
		_expect_equal(seal_game.state["board"][1]["facility_state"], 0x51, "seal card updates canonical status")
		_expect_equal(seal_game.state["board"][2]["facility_state"], 0x51, "seal card updates duplicate status")
		var cash_before: int = int(seal_game.state["players"][0]["cash"])
		seal_game._graph_visit_tile(0, seal_game.state["board"][2], true)
		var sealed_service: Dictionary = _last_event_of_type(seal_game, "facility_service")
		_expect_equal(seal_game.state["players"][0]["cash"], cash_before, "sealed shared facility does not charge visitor")
		_expect_equal(sealed_service.get("reason", ""), "sealed", "sealed shared facility records sealed reason")

	var transfer_game: Object = _new_game(1819)
	_expect(transfer_game != null, "shared facility purchase-card fixture creates")
	if transfer_game != null:
		_set_facility(transfer_game, 1, 1, 2, 1)
		_prepare_graph_action(transfer_game, 0, 2)
		_expect(bool(Inventory.grant_card(transfer_game.state["inventory_supply"], transfer_game.state["players"][0]["cards"], "購地").get("ok", false)), "facility purchase card can be staged")
		var transfer: Dictionary = transfer_game.choose_action("use_card", {"card_id": "購地", "tile_id": 2})
		_expect(bool(transfer.get("ok", false)), "purchase card transfers a shared facility")
		_expect_equal(transfer_game.state["board"][1]["owner"], 0, "facility transfer updates canonical owner")
		_expect_equal(transfer_game.state["board"][2]["owner"], 0, "facility transfer updates duplicate owner")
		_expect_equal(transfer_game.state["board"][1]["building_level"], 2, "facility transfer preserves built level")
		_expect_equal(transfer_game.state["players"][0]["properties"], [1], "facility transfer keeps one canonical buyer asset")
		_expect_equal(transfer_game.state["players"][1]["properties"], [], "facility transfer removes seller asset")
		_expect_equal(transfer_game.state["players"][0]["property_values"], 1600, "facility transfer recalculates buyer asset value")
		_expect(bool(GameState.validate_save(transfer_game.to_dict()).get("ok", false)), "shared facility inventory transfer save validates")


func _test_legacy_compatibility() -> void:
	var legacy: Object = GameState.new_game(1820, 2)
	_expect(legacy != null, "legacy game fixture creates")
	if legacy == null:
		return
	_expect_equal(legacy.state.get("version", -1), 1, "legacy game keeps v1 save")
	_expect(not legacy.state.has("original_facilities"), "legacy game has no facility capability flag")
	_expect(not legacy.state.has("price_index"), "legacy game has no facility price index")
	_expect(bool(GameState.validate_save(legacy.to_dict()).get("ok", false)), "legacy game save remains valid")
	legacy.state["players"][0]["cards"] = ["漲價"]
	legacy.state["phase"] = "await_action"
	legacy._set_action_options(0)
	var legacy_card: Dictionary = legacy.choose_action("use_card", {"card_id": "漲價", "tile_id": 1})
	_expect(not bool(legacy_card.get("ok", false)), "legacy game rejects facility status card")
	_expect_equal(legacy.state["players"][0]["cards"], ["漲價"], "legacy rejection preserves facility status card")
	_expect(GameState.from_dict(legacy.to_dict()) != null, "legacy save reloads without facility fields")

	var inventory_options: Dictionary = {"start_date": {"year": 1998, "month": 1, "day": 1}, "original_inventory": true}
	var inventory: Object = GameState.new_game(1821, 2, inventory_options)
	_expect(inventory != null, "v4 inventory fixture creates")
	if inventory != null:
		_expect_equal(inventory.state.get("version", -1), 4, "inventory mode keeps v4 save")
		_expect_equal(inventory.state.get("original_facilities", true), false, "inventory mode does not implicitly enable facilities")
		_expect(bool(GameState.validate_save(inventory.to_dict()).get("ok", false)), "v4 inventory save remains valid")


func _last_event_of_type(game: Object, event_type: String) -> Dictionary:
	var events: Array = game.state.get("event_log", [])
	for index in range(events.size() - 1, -1, -1):
		if typeof(events[index]) == TYPE_DICTIONARY and str(events[index].get("type", "")) == event_type:
			return events[index]
	return {}
