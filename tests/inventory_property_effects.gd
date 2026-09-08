extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_legacy_and_initial_state()
	_test_roadblock_lifecycle_and_save()
	_test_special_node_roadblocks()
	_test_property_purchase_and_worker()
	_test_demolition_lifecycle()
	_test_ai_stage2_targets()
	_test_ai_replay()
	print("Inventory property effect checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures else 0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _options() -> Dictionary:
	return {"start_date": {"year": 1998, "month": 1, "day": 1}, "original_inventory": true}


func _new_graph_inventory(seed_value: int = 700) -> Object:
	var raw: Dictionary = Fixture.make()
	# Turn the synthetic non-property nodes into source roads while retaining the
	# branch at node 1 and the two ordinary housing nodes.
	for node_index in [0, 1, 4]:
		raw["nodes"][node_index]["type_and_idx"] = 0
		raw["nodes"][node_index]["event_code"] = 0
	var normalized: Dictionary = Maps.normalize_map(raw)
	if not bool(normalized.get("ok", false)):
		return null
	return GameState.new_game_on_board(seed_value, 2, normalized["definition"], _options())


func _prepare_roll(game: Object, player_id: int = 0) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = "await_roll"
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["route_options"] = []
	game._set_action_options(player_id)


func _prepare_action(game: Object, player_id: int = 0) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = false
	game._set_action_options(player_id)


func _stage_card(game: Object, player_id: int, card_id: String) -> bool:
	return bool(Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id).get("ok", false))


func _set_property_owner(game: Object, tile_id: int, owner_id: int, level: int = 0) -> void:
	var tile: Dictionary = game.state["board"][tile_id]
	tile["owner"] = owner_id
	tile["building_level"] = level
	game._update_tile_rent(tile)
	for candidate in game.state["players"]:
		var properties: Array = []
		if int(candidate.get("id", -1)) == owner_id:
			properties.append(tile_id)
		candidate["properties"] = properties
	game._recalculate_property_values()


func _test_legacy_and_initial_state() -> void:
	var fallback: Object = GameState.new_game(701, 2, _options())
	_expect(fallback != null, "v4 fallback game creates")
	if fallback == null:
		return
	_expect(fallback.state.has("roadblocks"), "v4 fallback has roadblocks state")
	_expect_equal(fallback.state["roadblocks"], {}, "v4 fallback starts with empty roadblocks")
	_expect(bool(GameState.validate_save(fallback.to_dict()).get("ok", false)), "v4 fallback empty roadblocks validates")
	var fallback_bad: Dictionary = fallback.to_dict()
	fallback_bad["roadblocks"] = {"0": 0}
	_expect(not bool(GameState.validate_save(fallback_bad).get("ok", false)), "v4 fallback rejects nonempty roadblocks")

	var legacy: Object = GameState.new_game(702, 2)
	_expect(legacy != null, "legacy game creates")
	if legacy == null:
		return
	_expect(not legacy.state.has("roadblocks"), "legacy save has no roadblocks field")
	legacy.state["players"][0]["cards"] = ["購地"]
	legacy.state["phase"] = "await_action"
	legacy._set_action_options(0)
	var legacy_use: Dictionary = legacy.choose_action("use_card", {"card_id": "購地"})
	_expect(not bool(legacy_use.get("ok", false)), "legacy rejects stage2 card effect")
	_expect_equal(legacy.state["players"][0]["cards"], ["購地"], "legacy stage2 card remains held")
	_expect(bool(GameState.validate_save(legacy.to_dict()).get("ok", false)), "legacy save remains valid")


func _test_roadblock_lifecycle_and_save() -> void:
	var game: Object = _new_graph_inventory()
	_expect(game != null, "roadblock fixture creates")
	if game == null:
		return
	var player: Dictionary = game.state["players"][0]
	player["position"] = 1
	_prepare_roll(game)
	var legal_targets: Array = game.inventory_target_tiles("路障")
	_expect(legal_targets.has(0), "roadblock exposes reachable adjacent road")
	_expect(not legal_targets.has(1), "roadblock excludes occupied nodes")
	_expect(legal_targets.has(2) and legal_targets.has(4) and legal_targets.has(5), "roadblock accepts reachable graph nodes with edges")
	var tool_before: int = int(player["tools"].get("路障", 0))
	var supply_before: int = int(game.state["inventory_supply"]["tools"]["路障"])
	var place: Dictionary = game.choose_action("use_tool", {"tool_id": "路障", "tile_id": 0})
	_expect(bool(place.get("ok", false)), "roadblock places on a legal road")
	_expect_equal(player["tools"].get("路障", 0), tool_before - 1, "roadblock consumes one held tool")
	_expect_equal(int(game.state["inventory_supply"]["tools"]["路障"]), supply_before + 1, "roadblock returns finite tool to supply")
	_expect_equal(game.state["roadblocks"].get("0", -1), 0, "roadblock records placer by canonical node key")

	var saved: Dictionary = game.to_dict()
	_expect(bool(GameState.validate_save(saved).get("ok", false)), "roadblock save validates")
	var restored: Object = GameState.from_dict(JSON.parse_string(game.to_json()))
	_expect(restored != null, "roadblock save reloads")
	if restored != null:
		_expect_equal(restored.to_json(), game.to_json(), "roadblock round trip is deterministic")
	var bad_key: Dictionary = saved.duplicate(true)
	bad_key["roadblocks"] = {0: 0}
	_expect(not bool(GameState.validate_save(bad_key).get("ok", false)), "roadblock integer key is rejected")
	var bad_target: Dictionary = saved.duplicate(true)
	bad_target["roadblocks"] = {"6": 0}
	_expect(not bool(GameState.validate_save(bad_target).get("ok", false)), "roadblock out-of-range target is rejected")
	var bad_placer: Dictionary = saved.duplicate(true)
	bad_placer["roadblocks"] = {"0": {"player_id": 0}}
	var bad_placer_result: Variant = GameState.validate_save(bad_placer)
	_expect(bad_placer_result is Dictionary and not bool(bad_placer_result.get("ok", true)), "malformed roadblock placer is rejected without runtime error")
	var bad_position: Dictionary = saved.duplicate(true)
	bad_position["players"][0]["position"] = {"node": 0}
	var bad_position_result: Variant = GameState.validate_save(bad_position)
	_expect(bad_position_result is Dictionary and not bool(bad_position_result.get("ok", true)), "malformed roadblock occupant position is rejected without runtime error")
	var too_many: Dictionary = saved.duplicate(true)
	for roadblock_id in range(11):
		too_many["roadblocks"][str(roadblock_id)] = 0
	var too_many_result: Variant = GameState.validate_save(too_many)
	_expect(too_many_result is Dictionary and not bool(too_many_result.get("ok", true)), "save with more than ten roadblocks is rejected")
	var occupied: Dictionary = saved.duplicate(true)
	occupied["roadblocks"] = {"1": 0}
	_expect(not bool(GameState.validate_save(occupied).get("ok", false)), "roadblock occupied target is rejected")

	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["phase"] = "await_roll"
	game._graph_begin_movement(0, 1)
	_expect_equal(game.state["route_options"], [0, 2, 3], "roadblock fixture retains branch choices")
	var collision: Dictionary = game.choose_route(0)
	_expect(bool(collision.get("ok", false)), "choosing a roadblock route succeeds")
	_expect_equal(player["position"], 0, "roadblock moves player onto destination")
	_expect_equal(game.state["remaining_steps"], 0, "roadblock stops remaining movement")
	_expect(not game.state["roadblocks"].has("0"), "roadblock is removed on collision")
	_expect_equal(game.state["phase"], "await_action", "roadblock collision proceeds to normal landing phase")

	var occupied_game: Object = _new_graph_inventory(703)
	if occupied_game != null:
		occupied_game.state["players"][0]["position"] = 1
		_prepare_roll(occupied_game)
		var occupied_tool_before: int = int(occupied_game.state["players"][0]["tools"].get("路障", 0))
		var occupied_place: Dictionary = occupied_game.choose_action("use_tool", {"tool_id": "路障", "tile_id": 1})
		_expect(not bool(occupied_place.get("ok", false)), "roadblock rejects occupied current node")
		_expect_equal(int(occupied_game.state["players"][0]["tools"].get("路障", 0)), occupied_tool_before, "invalid roadblock leaves tool held")
		occupied_game.state["roadblocks"] = {}
		for roadblock_id in range(10):
			occupied_game.state["roadblocks"][str(roadblock_id)] = 0
		var full_tool_before: int = int(occupied_game.state["players"][0]["tools"].get("路障", 0))
		var full_place: Dictionary = occupied_game.choose_action("use_tool", {"tool_id": "路障", "tile_id": 1})
		_expect(not bool(full_place.get("ok", false)), "roadblock placement rejects a full barrier set")
		_expect_equal(int(occupied_game.state["players"][0]["tools"].get("路障", 0)), full_tool_before, "full barrier set leaves tool held")


func _test_special_node_roadblocks() -> void:
	var normalized: Dictionary = Maps.normalize_map(Fixture.make())
	var point_game: Object = GameState.new_game_on_board(711, 2, normalized.get("definition", {}), _options()) if bool(normalized.get("ok", false)) else null
	_expect(point_game != null, "point-node roadblock fixture creates")
	if point_game != null:
		point_game.state["players"][0]["position"] = 2
		point_game.state["players"][0]["previous_position"] = -1
		point_game.state["players"][1]["position"] = 5
		_prepare_roll(point_game)
		_expect(bool(point_game.choose_action("use_tool", {"tool_id": "路障", "tile_id": 1}).get("ok", false)), "roadblock can target point node")
		point_game.state["last_roll"] = [1]
		point_game.state["last_total"] = 1
		point_game._graph_begin_movement(0, 1)
		_expect(point_game.state["route_options"].has(1), "point-node roadblock remains a route option")
		var point_before: int = int(point_game.state["players"][0]["points"])
		var point_collision: Dictionary = point_game.choose_route(1)
		_expect(bool(point_collision.get("ok", false)), "point-node roadblock collision succeeds")
		_expect_equal(int(point_game.state["players"][0]["points"]), point_before + 50, "point-node collision still resolves normal landing")
		_expect_equal(point_game.state["last_event"].get("type", ""), "points_landed", "point-node collision records landing")

	var card_game: Object = GameState.new_game_on_board(712, 2, normalized.get("definition", {}), _options()) if bool(normalized.get("ok", false)) else null
	_expect(card_game != null, "card-node roadblock fixture creates")
	if card_game != null:
		card_game.state["players"][0]["position"] = 2
		card_game.state["players"][0]["previous_position"] = -1
		card_game.state["players"][1]["position"] = 5
		_prepare_roll(card_game)
		_expect(bool(card_game.choose_action("use_tool", {"tool_id": "路障", "tile_id": 4}).get("ok", false)), "roadblock can target card node")
		card_game.state["last_roll"] = [1]
		card_game.state["last_total"] = 1
		card_game._graph_begin_movement(0, 1)
		var card_collision: Dictionary = card_game.choose_route(4)
		_expect(bool(card_collision.get("ok", false)), "card-node roadblock collision succeeds")
		_expect_equal(card_game.state["last_event"].get("type", ""), "event_drawn", "card-node collision still resolves normal landing")

	var bank_game: Object = GameState.new_game_on_board(713, 2, normalized.get("definition", {}), _options()) if bool(normalized.get("ok", false)) else null
	_expect(bank_game != null, "bank-node roadblock fixture creates")
	if bank_game != null:
		bank_game.state["players"][0]["position"] = 4
		bank_game.state["players"][0]["previous_position"] = -1
		bank_game.state["players"][1]["position"] = 0
		_prepare_roll(bank_game)
		_expect(bool(bank_game.choose_action("use_tool", {"tool_id": "路障", "tile_id": 5}).get("ok", false)), "roadblock can target bank node")
		bank_game.state["last_roll"] = [1]
		bank_game.state["last_total"] = 1
		bank_game._graph_begin_movement(0, 1)
		var bank_collision: Dictionary = bank_game.choose_route(5)
		_expect(bool(bank_collision.get("ok", false)), "bank-node roadblock collision succeeds")
		_expect(bool(bank_game.state["bank_landing"]), "bank-node collision still resolves normal landing")
		_expect_equal(bank_game.state["last_event"].get("type", ""), "bank_landed", "bank-node collision records landing")


func _test_property_purchase_and_worker() -> void:
	var game: Object = _new_graph_inventory(704)
	_expect(game != null, "purchase fixture creates")
	if game == null:
		return
	var buyer: Dictionary = game.state["players"][0]
	var tile: Dictionary = game.state["board"][2]
	buyer["position"] = 2
	buyer["cash"] = 5000
	_prepare_action(game)
	var purchase_supply_before: int = int(game.state["inventory_supply"]["cards"]["購地"])
	_expect(_stage_card(game, 0, "購地"), "purchase card can be staged")
	var cash_before: int = int(buyer["cash"])
	var bank_before: int = int(game.state["bank"]["cash"])
	var price: int = int(tile["cost"])
	var purchase: Dictionary = game.choose_action("use_card", {"card_id": "購地"})
	_expect(bool(purchase.get("ok", false)), "purchase card buys current ordinary housing")
	_expect_equal(int(buyer["cash"]), cash_before - price, "purchase card debits buyer cash")
	_expect_equal(int(game.state["bank"]["cash"]), bank_before + price, "unowned purchase pays the bank")
	_expect_equal(int(tile["owner"]), 0, "purchase card assigns ownership")
	_expect(buyer["properties"].has(2), "purchase card adds property to buyer")
	_expect_equal(int(buyer["property_values"]), int(tile["cost"]), "purchase updates buyer property value")
	_expect(bool(game.state["property_action_used"]), "purchase consumes this visit property action")
	_expect_equal(int(game.state["inventory_supply"]["cards"]["購地"]), purchase_supply_before, "successful purchase returns card to pool")
	var repeat: Dictionary = game.choose_action("use_card", {"card_id": "購地"})
	_expect(not bool(repeat.get("ok", false)), "purchase cannot repeat on owned property")

	var transfer_game: Object = _new_graph_inventory(705)
	if transfer_game != null:
		var transfer_tile: Dictionary = transfer_game.state["board"][2]
		var old_owner: Dictionary = transfer_game.state["players"][1]
		var transfer_buyer: Dictionary = transfer_game.state["players"][0]
		_set_property_owner(transfer_game, 2, 1)
		transfer_buyer["position"] = 2
		transfer_buyer["cash"] = 5000
		_prepare_action(transfer_game)
		_expect(_stage_card(transfer_game, 0, "購地"), "transfer purchase card can be staged")
		var old_deposit: int = int(old_owner["deposit"])
		var bank_deposits: int = int(transfer_game.state["bank"]["deposits"])
		var transfer_price: int = int(transfer_tile["cost"])
		var transfer: Dictionary = transfer_game.choose_action("use_card", {"card_id": "購地"})
		_expect(bool(transfer.get("ok", false)), "purchase card transfers owned housing")
		_expect_equal(int(old_owner["deposit"]), old_deposit + transfer_price, "transfer pays old owner deposit")
		_expect_equal(int(transfer_game.state["bank"]["deposits"]), bank_deposits + transfer_price, "transfer updates bank deposits")
		_expect(not old_owner["properties"].has(2) and transfer_buyer["properties"].has(2), "transfer synchronizes both property lists")
		_expect_equal(int(transfer_buyer["property_values"]), int(transfer_tile["cost"]), "transfer synchronizes buyer property value")
		_expect_equal(int(old_owner["property_values"]), 0, "transfer clears old owner property value")
		_expect(bool(GameState.validate_save(transfer_game.to_dict()).get("ok", false)), "transfer save remains valid")

	var worker_game: Object = _new_graph_inventory(706)
	if worker_game != null:
		var worker_tile: Dictionary = worker_game.state["board"][2]
		var worker_owner: Dictionary = worker_game.state["players"][1]
		_set_property_owner(worker_game, 2, 1, 0)
		var worker_player: Dictionary = worker_game.state["players"][0]
		worker_player["position"] = 1
		_prepare_roll(worker_game)
		_expect(worker_game.inventory_target_tiles("機器工人").has(2), "human worker retains opponent housing target")
		var worker_cash: int = int(worker_player["cash"])
		var worker: Dictionary = worker_game.choose_action("use_tool", {"tool_id": "機器工人", "tile_id": 2})
		_expect(bool(worker.get("ok", false)), "machine worker upgrades ordinary housing")
		_expect_equal(int(worker_tile["building_level"]), 1, "machine worker raises housing one level")
		_expect_equal(int(worker_tile["rent"]), int(worker_tile["rent_by_level"][1]), "machine worker updates rent")
		_expect_equal(int(worker_player["cash"]), worker_cash, "machine worker does not charge cash")
		_expect_equal(int(worker_owner["property_values"]), int(worker_tile["cost"]) + int(worker_tile["upgrade_cost"]), "machine worker updates owner property value")
		_expect(not worker_player["tools"].has("機器工人"), "machine worker is consumed")


func _test_demolition_lifecycle() -> void:
	var game: Object = _new_graph_inventory(707)
	_expect(game != null, "demolition fixture creates")
	if game == null:
		return
	var tile: Dictionary = game.state["board"][2]
	_set_property_owner(game, 2, 1, 2)
	var player: Dictionary = game.state["players"][0]
	player["position"] = 1
	_prepare_action(game)
	_expect(_stage_card(game, 0, "拆除"), "demolition card can be staged")
	var rent_before: int = int(tile["rent"])
	var demolish: Dictionary = game.choose_action("use_card", {"card_id": "拆除", "tile_id": 2})
	_expect(bool(demolish.get("ok", false)), "demolition card downgrades any ordinary housing")
	_expect_equal(int(tile["building_level"]), 1, "demolition lowers housing one level")
	_expect(int(tile["rent"]) < rent_before, "demolition lowers rent")
	_expect_equal(int(game.state["players"][1]["property_values"]), int(tile["cost"]) + int(tile["upgrade_cost"]), "demolition updates owner property value")

	var invalid_game: Object = _new_graph_inventory(708)
	if invalid_game != null:
		var invalid_player: Dictionary = invalid_game.state["players"][0]
		_prepare_action(invalid_game)
		_expect(_stage_card(invalid_game, 0, "拆除"), "invalid demolition card can be staged")
		var cards_before: Array = invalid_player["cards"].duplicate(true)
		var invalid: Dictionary = invalid_game.choose_action("use_card", {"card_id": "拆除", "tile_id": 2})
		_expect(not bool(invalid.get("ok", false)), "demolition rejects housing without an improvement")
		_expect_equal(invalid_player["cards"], cards_before, "invalid demolition leaves card held")

	var road_game: Object = _new_graph_inventory(709)
	if road_game != null:
		road_game.state["players"][0]["position"] = 1
		_prepare_roll(road_game)
		_expect(bool(road_game.choose_action("use_tool", {"tool_id": "路障", "tile_id": 0}).get("ok", false)), "roadblock fixture places barrier for demolition")
		_expect(_stage_card(road_game, 0, "拆除"), "roadblock demolition card can be staged")
		var clear: Dictionary = road_game.choose_action("use_card", {"card_id": "拆除", "tile_id": 0})
		_expect(bool(clear.get("ok", false)), "demolition card clears roadblock")
		_expect(not road_game.state["roadblocks"].has("0"), "demolition removes roadblock")


func _test_ai_stage2_targets() -> void:
	var worker_game: Object = _new_graph_inventory(714)
	_expect(worker_game != null, "AI worker fixture creates")
	if worker_game != null:
		_set_property_owner(worker_game, 2, 0, 0)
		worker_game.state["players"][0]["position"] = 1
		worker_game.state["players"][0]["previous_position"] = 0
		_prepare_roll(worker_game)
		var worker_level: int = int(worker_game.state["board"][2]["building_level"])
		worker_game._ai_roll_action(0)
		_expect_equal(int(worker_game.state["board"][2]["building_level"]), worker_level + 1, "AI worker targets its own housing")
		_expect_equal(int(worker_game.state["players"][0]["tools"].get("機器工人", 0)), 0, "AI worker consumes its own tool")

	var owner_priority_game: Object = _new_graph_inventory(718)
	_expect(owner_priority_game != null, "AI worker ownership-priority fixture creates")
	if owner_priority_game != null:
		_set_property_owner(owner_priority_game, 2, 1, 0)
		_set_property_owner(owner_priority_game, 3, 0, 0)
		var owner_priority_player: Dictionary = owner_priority_game.state["players"][0]
		owner_priority_player["position"] = 2
		owner_priority_player["previous_position"] = 1
		_prepare_roll(owner_priority_game)
		_expect_equal(owner_priority_game._inventory_ai_worker_target(0), 3, "AI worker skips opponent property at current position")
		var opponent_level: int = int(owner_priority_game.state["board"][2]["building_level"])
		var owned_level: int = int(owner_priority_game.state["board"][3]["building_level"])
		owner_priority_game._ai_roll_action(0)
		_expect_equal(int(owner_priority_game.state["board"][2]["building_level"]), opponent_level, "AI worker leaves opponent housing unchanged")
		_expect_equal(int(owner_priority_game.state["board"][3]["building_level"]), owned_level + 1, "AI worker upgrades owned housing when it appears later")

	var no_own_worker_game: Object = _new_graph_inventory(719)
	_expect(no_own_worker_game != null, "AI worker no-owned-property fixture creates")
	if no_own_worker_game != null:
		_set_property_owner(no_own_worker_game, 2, 1, 0)
		_set_property_owner(no_own_worker_game, 3, 1, 0)
		_prepare_roll(no_own_worker_game)
		_expect_equal(no_own_worker_game._inventory_ai_worker_target(0), -1, "AI worker has no target without owned housing")

	var roadblock_game: Object = _new_graph_inventory(715)
	_expect(roadblock_game != null, "AI roadblock fixture creates")
	if roadblock_game != null:
		var roadblock_player: Dictionary = roadblock_game.state["players"][0]
		Inventory.consume_tool(roadblock_game.state["inventory_supply"], roadblock_player["tools"], "機器工人", 1)
		roadblock_player["position"] = 1
		roadblock_player["previous_position"] = 0
		roadblock_game.state["players"][1]["position"] = 5
		_prepare_roll(roadblock_game)
		roadblock_game._ai_roll_action(0)
		_expect(roadblock_game.state["roadblocks"].has("0"), "AI roadblock chooses a safe adjacent node")
		_expect_equal(int(roadblock_player["tools"].get("路障", 0)), 0, "AI roadblock consumes its own tool")

	var purchase_game: Object = _new_graph_inventory(716)
	_expect(purchase_game != null, "AI purchase fixture creates")
	if purchase_game != null:
		_set_property_owner(purchase_game, 2, 1, 0)
		var purchase_player: Dictionary = purchase_game.state["players"][0]
		purchase_player["position"] = 2
		purchase_player["cash"] = 1200
		_prepare_action(purchase_game)
		_expect(_stage_card(purchase_game, 0, "購地"), "AI purchase card can be staged")
		purchase_game._ai_action(0)
		_expect_equal(int(purchase_game.state["board"][2]["owner"]), 0, "AI purchase targets the current opponent property")
		_expect(not purchase_player["cards"].has("購地"), "AI purchase consumes the card after a valid transfer")

	var demolition_game: Object = _new_graph_inventory(717)
	_expect(demolition_game != null, "AI demolition fixture creates")
	if demolition_game != null:
		_set_property_owner(demolition_game, 2, 1, 2)
		var demolition_player: Dictionary = demolition_game.state["players"][0]
		demolition_player["position"] = 1
		demolition_player["cash"] = 0
		_prepare_action(demolition_game)
		_expect(_stage_card(demolition_game, 0, "拆除"), "AI demolition card can be staged")
		demolition_game._ai_action(0)
		_expect_equal(int(demolition_game.state["board"][2]["building_level"]), 1, "AI demolition targets an opponent building")
		_expect(not demolition_player["cards"].has("拆除"), "AI demolition consumes the card after a valid target")

	var pending_target_game: Object = _new_graph_inventory(720)
	_expect(pending_target_game != null, "pending remote target fixture creates")
	if pending_target_game != null:
		_set_property_owner(pending_target_game, 2, 0, 1)
		pending_target_game.state["players"][0]["position"] = 1
		_prepare_roll(pending_target_game)
		_expect(_stage_card(pending_target_game, 0, "拆除"), "pending remote fixture stages demolition card")
		_expect(not pending_target_game.inventory_target_tiles("路障").is_empty(), "roadblock targets are exposed before remote scheduling")
		_expect(not pending_target_game.inventory_target_tiles("機器工人").is_empty(), "worker targets are exposed before remote scheduling")
		_expect(not pending_target_game.inventory_target_tiles("拆除").is_empty(), "demolition targets are exposed before remote scheduling")
		pending_target_game.state["pending_remote_dice"] = {"player_id": 0, "value": 4}
		_expect(pending_target_game.inventory_target_tiles("路障").is_empty(), "roadblock targets hide during remote scheduling")
		_expect(pending_target_game.inventory_target_tiles("機器工人").is_empty(), "worker targets hide during remote scheduling")
		_expect(pending_target_game.inventory_target_tiles("拆除").is_empty(), "demolition targets hide during remote scheduling")


func _test_ai_replay() -> void:
	var first: Object = _new_graph_inventory(710)
	var second: Object = _new_graph_inventory(710)
	_expect(first != null and second != null, "AI replay fixtures create")
	if first == null or second == null:
		return
	for game in [first, second]:
		var player: Dictionary = game.state["players"][0]
		player["position"] = 1
		for tool_id in ["機器娃娃", "地雷", "定時炸彈", "遙控骰子", "機器工人"]:
			Inventory.consume_tool(game.state["inventory_supply"], player["tools"], tool_id, 1)
		game.set_player_ai(0, true)
		_prepare_roll(game)
	var first_result: Dictionary = first.run_ai_turn()
	var second_result: Dictionary = second.run_ai_turn()
	_expect(bool(first_result.get("ok", false)) and bool(second_result.get("ok", false)), "AI completes roadblock continuation")
	_expect_equal(first.to_json(), second.to_json(), "AI roadblock replay is deterministic")
