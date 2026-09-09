extends SceneTree

## Issue #80 TEST-ONLY seed for the two remaining blast tools.
##
## The map is synthetic and asset-free.  Its graph coordinates deliberately
## put objects on the inclusive half-extent boundaries so the future runtime
## must resolve a target-centred logical square rather than a texture or
## viewport size.  This seed runs against the public use_tool boundary while
## the tools are still unimplemented and therefore records qualified RED.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/missile_fixture.gd")

const V13 := 13
const MISSILE := "飛彈"
const NUCLEAR := "核子飛彈"
const CENTRE := 1
const ORDINARY_HOUSE := 2
const CHAIN_HOUSE := 3
const PRISON := 4
const FAR_NODE := 5

var checks: int = 0
var failures: int = 0
var qualified_red: int = 0
var reported_red: Dictionary = {}


func _initialize() -> void:
	_test_v13_fixture_and_catalogue()
	_test_missile_damage_and_boundaries()
	_test_missile_facility_zero_transition()
	_test_nuclear_research_damage_and_non_global_boundary()
	_test_cancel_invalid_and_type_atomicity()
	_test_ai_missile_determinism()
	print("Missile flow checks: %d, failures: %d, qualified_red: %d" % [checks, failures, qualified_red])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_game(seed_value: int, player_count: int = 4) -> Object:
	var game: Object = Fixture.new_game(seed_value, player_count)
	_expect(game != null, "v13 missile fixture starts")
	if game == null:
		return null
	_expect_equal(int(game.state.get("version", -1)), V13, "missile fixture uses the legal v13 save")
	_expect(bool(game.state.get("original_building_cards", false)), "missile fixture retains the v13 marker")
	_expect(bool(game.state.get("original_research", false)), "missile fixture retains research production")
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), "fresh missile fixture validates: " + str(validation.get("errors", [])))
	return game


func _reset_players(game: Object) -> void:
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = player_value
		player["alive"] = true
		player["bankrupt"] = false
		player["hospital_days"] = 0
		player["prison_days"] = 0
		player["god_id"] = 0
		player["vehicle"] = "walking"
		player["dice_count"] = 1
		player["previous_position"] = -1
		player["bomb_steps"] = 0
	game.state["god_objects"] = []


func _prepare_action(game: Object, player_id: int, position: int, phase: String = "await_roll") -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state["players"][player_id]["position"] = position
	game.state["players"][player_id]["previous_position"] = -1
	game._set_action_options(player_id)


func _prepare_landed_action(game: Object, player_id: int, position: int) -> void:
	_prepare_action(game, player_id, position, "await_action")
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game._set_action_options(player_id)


func _stage_tool(game: Object, player_id: int, tool_id: String) -> bool:
	var result: Dictionary = Inventory.grant_tool(game.state["inventory_supply"], game.state["players"][player_id]["tools"], tool_id, 1)
	_expect(bool(result.get("ok", false)), "fixture stages " + tool_id + " through finite inventory rules")
	return bool(result.get("ok", false))


func _public_use(game: Object, params: Dictionary, label: String) -> Dictionary:
	# Keep this validation directly adjacent to the public action.  It proves the
	# scenario reached a legal v13 state instead of hiding a capability failure.
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), label + " has a valid save immediately before public use_tool: " + str(validation.get("errors", [])))
	_expect(game.state.get("action_options", []).has("use_tool"), label + " starts with a legal use_tool action")
	return game.choose_action("use_tool", params)


func _mark_qualified_red(result: Dictionary, label: String) -> void:
	var message := str(result.get("message", ""))
	if not bool(result.get("ok", false)) and message.contains("尚未還原"):
		qualified_red += 1
		if not reported_red.has(label):
			reported_red[label] = true
			print("QUALIFIED RED: %s -> %s" % [label, message])


func _expect_success(result: Dictionary, label: String) -> bool:
	_mark_qualified_red(result, label)
	var ok := bool(result.get("ok", false))
	_expect(ok, label + " succeeds: " + str(result.get("message", "")))
	return ok


func _assert_tool_event(game: Object, tool_id: String, target_id: int, label: String) -> void:
	var event: Dictionary = game.state.get("last_event", {})
	_expect_equal(str(event.get("type", "")), "tool_used", label + " records a tool_used event")
	_expect_equal(str(event.get("tool_id", "")), tool_id, label + " event identifies the tool")
	_expect_equal(int(event.get("player_id", -1)), int(game.state.get("current_player", -1)), label + " event identifies the actor")
	_expect_equal(int(event.get("tile_id", -1)), target_id, label + " event identifies the target")
	_expect(not str(event.get("effect", "")).is_empty(), label + " event identifies an effect")


func _facility_snapshot(game: Object, source_id: int) -> Array:
	var snapshots: Array = []
	for index_value in Fixture.facility_indices(game, source_id):
		var tile: Dictionary = game.state["board"][int(index_value)]
		snapshots.append(tile.duplicate(true))
	return snapshots


func _assert_static_property_fields(tile: Dictionary, before: Dictionary, label: String) -> void:
	for key in ["index", "source_node_id", "x", "y", "adjacent", "type_and_idx", "visual_index", "event_code", "source_status_bits", "source_object_id", "kind", "name", "cost", "upgrade_cost", "base_rent", "land_price", "house_price", "rent_by_level", "group", "tax_amount"]:
		_expect_equal(tile.get(key, null), before.get(key, null), label + " preserves " + key)


func _assert_static_facility_fields(tile: Dictionary, before: Dictionary, label: String) -> void:
	for key in ["index", "source_node_id", "x", "y", "adjacent", "type_and_idx", "visual_index", "event_code", "source_status_bits", "source_object_id", "kind", "name", "cost", "land_price", "upgrade_cost", "base_rent", "group", "tax_amount", "fee_by_level", "facility_node_index"]:
		_expect_equal(tile.get(key, null), before.get(key, null), label + " preserves " + key)


func _set_missile_world(game: Object, with_car: bool = false) -> Dictionary:
	_reset_players(game)
	Fixture.set_property(game, ORDINARY_HOUSE, 1, 3, false)
	Fixture.set_property(game, CHAIN_HOUSE, 1, 1, true)
	Fixture.set_facility(game, 1, 1, 3, 4, 0x50, 2, 3)
	Fixture.set_facility(game, 2, 2, 2, 2, 0x50, 0, 0)
	for player_id in range(game.state["players"].size()):
		game.state["players"][player_id]["position"] = CENTRE
	if game.state["players"].size() > 1:
		game.state["players"][1]["position"] = ORDINARY_HOUSE
	if game.state["players"].size() > 2:
		game.state["players"][2]["position"] = CHAIN_HOUSE
	if game.state["players"].size() > 3:
		game.state["players"][3]["position"] = PRISON
	game.state["god_objects"] = [
		{"id": 1, "node": 9, "owner": -1, "days": 0},
		{"id": 3, "node": PRISON, "owner": -1, "days": 0},
	]
	var info: Dictionary = {"car_supply_before": int(game.state["inventory_supply"]["tools"]["汽車"])}
	if with_car and game.state["players"].size() > 2:
		var car_grant: Dictionary = Inventory.grant_tool(game.state["inventory_supply"], game.state["players"][2]["tools"], "汽車", 1)
		_expect(bool(car_grant.get("ok", false)), "fixture stages an active car")
		_prepare_action(game, 2, CHAIN_HOUSE)
		var validation: Dictionary = Game.validate_save(game.to_dict())
		_expect(bool(validation.get("ok", false)), "active-car fixture validates before vehicle selection: " + str(validation.get("errors", [])))
		var car_result: Dictionary = game.set_vehicle("car")
		_expect(bool(car_result.get("ok", false)), "fixture equips the active car through the public entry")
		info["car_supply_after_equip"] = int(game.state["inventory_supply"]["tools"]["汽車"])
	_prepare_action(game, 0, CENTRE)
	return info


func _test_v13_fixture_and_catalogue() -> void:
	var definition: Dictionary = Fixture.definition()
	_expect(bool(definition.get("supports_original_research", false)), "fixture advertises v12 research capability")
	_expect(bool(definition.get("supports_original_building_cards", false)), "fixture advertises v13 capability")
	_expect_equal(int(definition.get("board", []).size()), 10, "fixture keeps the compact ten-node graph")
	var game: Object = _new_game(8101, 4)
	if game == null:
		return
	var tools: Dictionary = game.state["inventory_supply"]["tools"]
	_expect_equal(int(tools.get(MISSILE, -1)), 10, "missile keeps its finite shared opening supply")
	_expect_equal(int(tools.get(NUCLEAR, -1)), 0, "nuclear missile has no invented shared supply")
	for player_value in game.state["players"]:
		var player: Dictionary = player_value
		_expect_equal(int(player.get("tools", {}).get(MISSILE, 0)), 0, "missile is not pre-granted")
		_expect_equal(int(player.get("tools", {}).get(NUCLEAR, 0)), 0, "nuclear missile is research-produced")
		_expect_equal(int(player.get("god_id", -1)), 0, "fresh fixture has no live attached god")
	_expect(game.state.get("god_objects", []).is_empty(), "fresh fixture has no live spawned gods")


func _test_missile_damage_and_boundaries() -> void:
	var game: Object = _new_game(8110, 4)
	if game == null:
		return
	var info: Dictionary = _set_missile_world(game, true)
	var source_one_before: Array = _facility_snapshot(game, 1)
	var source_two_before: Array = _facility_snapshot(game, 2)
	var ordinary_before: Dictionary = game.state["board"][ORDINARY_HOUSE].duplicate(true)
	var chain_before: Dictionary = game.state["board"][CHAIN_HOUSE].duplicate(true)
	var prison_before: Dictionary = game.state["board"][PRISON].duplicate(true)
	var far_before: Dictionary = game.state["board"][FAR_NODE].duplicate(true)
	var missile_supply_before: int = int(game.state["inventory_supply"]["tools"][MISSILE])
	var car_supply_before_blast: int = int(info.get("car_supply_after_equip", -1))
	_expect(_stage_tool(game, 0, MISSILE), "missile effect has a held finite tool")
	_prepare_action(game, 0, CENTRE)
	var result: Dictionary = _public_use(game, {"tool_id": MISSILE, "tile_id": CENTRE}, "missile valid target")
	if not _expect_success(result, "missile valid target"):
		return
	_expect_equal(int(game.state["inventory_supply"]["tools"][MISSILE]), missile_supply_before + 1, "missile success recycles exactly one finite supply unit")
	_expect_equal(int(game.state["players"][0]["tools"].get(MISSILE, 0)), 0, "missile success removes the held tool")
	_expect_equal(int(game.state["players"][0].get("hospital_days", -1)), 3, "missile includes the caster in hospital admission")
	_expect_equal(int(game.state["players"][1].get("hospital_days", -1)), 3, "missile admits the ordinary-house player")
	_expect_equal(int(game.state["players"][2].get("hospital_days", -1)), 3, "missile admits the chain-house player")
	_expect_equal(int(game.state["players"][3].get("hospital_days", -1)), 0, "missile excludes the node outside its half-extent")
	_expect_equal(int(game.state["players"][2].get("position", -1)), 0, "missile sends the vehicle holder to the canonical hospital")
	_expect_equal(str(game.state["players"][2].get("vehicle", "")), "walking", "missile removes the active vehicle")
	_expect_equal(int(game.state["inventory_supply"]["tools"]["汽車"]), car_supply_before_blast + 1, "missile returns the active car exactly once")

	var ordinary: Dictionary = game.state["board"][ORDINARY_HOUSE]
	_expect_equal(int(ordinary.get("owner", -1)), 1, "missile preserves ordinary-house ownership")
	_expect_equal(int(ordinary.get("building_level", -1)), 2, "missile lowers ordinary housing one level")
	_expect_equal(bool(ordinary.get("is_chain_store", true)), false, "missile keeps ordinary housing non-chain")
	_expect_equal(ordinary.get("rent"), ordinary.get("rent_by_level", [])[2], "missile refreshes ordinary housing rent")
	_assert_static_property_fields(ordinary, ordinary_before, "ordinary housing")

	var chain: Dictionary = game.state["board"][CHAIN_HOUSE]
	_expect_equal(int(chain.get("owner", -1)), 1, "missile preserves chain-house ownership")
	_expect_equal(int(chain.get("building_level", -1)), 0, "missile clears chain-house construction")
	_expect_equal(bool(chain.get("is_chain_store", true)), false, "missile clears the chain-house type")
	_expect_equal(chain.get("rent"), chain.get("rent_by_level", [])[0], "missile refreshes cleared chain rent")
	_assert_static_property_fields(chain, chain_before, "chain housing")

	for index_value in Fixture.facility_indices(game, 1):
		var facility: Dictionary = game.state["board"][int(index_value)]
		var before: Dictionary = source_one_before[Fixture.facility_indices(game, 1).find(int(index_value))]
		_assert_static_facility_fields(facility, before, "missile source-1 facility")
		_expect_equal(int(facility.get("owner", -1)), 1, "missile preserves facility ownership")
		_expect_equal(int(facility.get("building_level", -1)), 2, "missile damages a shared facility once")
		_expect_equal(int(facility.get("facility_type", -1)), 4, "missile preserves nonzero facility type")
		_expect_equal(int(facility.get("facility_state", -1)), 0x50, "missile preserves facility status")
		_expect_equal(int(facility.get("research_tool", -1)), 2, "missile preserves facility research rank")
		_expect_equal(int(facility.get("research_turns", -1)), 3, "missile preserves facility research countdown")
	_expect_equal(_facility_snapshot(game, 2), source_two_before, "missile does not touch source-2 entrances outside its range")
	_expect_equal(game.state["board"][PRISON], prison_before, "missile leaves the exclusive outer board boundary unchanged")
	_expect_equal(game.state["board"][FAR_NODE], far_before, "missile leaves distant logical nodes unchanged")
	_expect_equal(game.state["god_objects"].size(), 1, "missile removes only the in-range unbound god")
	if game.state["god_objects"].size() == 1:
		_expect_equal(int(game.state["god_objects"][0].get("node", -1)), PRISON, "missile preserves the out-of-range unbound god")
	_assert_tool_event(game, MISSILE, CENTRE, "missile valid target")
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), "missile damage leaves a valid save: " + str(validation.get("errors", [])))


func _test_missile_facility_zero_transition() -> void:
	var game: Object = _new_game(8111, 2)
	if game == null:
		return
	_reset_players(game)
	Fixture.set_facility(game, 1, 1, 1, 4, 0x50, 1, 3)
	Fixture.set_property(game, ORDINARY_HOUSE, 1, 1, false)
	Fixture.set_property(game, CHAIN_HOUSE, 1, 1, false)
	var before: Array = _facility_snapshot(game, 1)
	_expect(_stage_tool(game, 0, MISSILE), "zero-transition missile has a held finite tool")
	_prepare_action(game, 0, CENTRE)
	var result: Dictionary = _public_use(game, {"tool_id": MISSILE, "tile_id": CENTRE}, "missile facility zero transition")
	if not _expect_success(result, "missile facility zero transition"):
		return
	for index_value in Fixture.facility_indices(game, 1):
		var facility: Dictionary = game.state["board"][int(index_value)]
		var snapshot: Dictionary = before[Fixture.facility_indices(game, 1).find(int(index_value))]
		_assert_static_facility_fields(facility, snapshot, "zero-transition facility")
		_expect_equal(int(facility.get("owner", -1)), 1, "zero-transition preserves facility owner")
		_expect_equal(int(facility.get("building_level", -1)), 0, "zero-transition reaches level zero")
		_expect_equal(int(facility.get("facility_type", -1)), 0, "zero-transition clears facility type")
		_expect_equal(int(facility.get("facility_state", -1)), 0, "zero-transition clears facility state")
		_expect_equal(int(facility.get("research_tool", -1)), 1, "zero-transition preserves research auxiliary rank")
		_expect_equal(int(facility.get("research_turns", -1)), 3, "zero-transition preserves research auxiliary countdown")
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), "zero-transition damage leaves a valid save: " + str(validation.get("errors", [])))


func _prepare_nuclear_game(seed_value: int) -> Object:
	var game: Object = _new_game(seed_value, 2)
	if game == null:
		return null
	_reset_players(game)
	Fixture.set_property(game, ORDINARY_HOUSE, 1, 3, false)
	Fixture.set_property(game, CHAIN_HOUSE, 1, 1, true)
	Fixture.set_facility(game, 1, 0, 5, 4, 0, 0, 0)
	Fixture.set_facility(game, 2, 1, 2, 2, 0, 0, 0)
	game.state["players"][0]["position"] = CENTRE
	game.state["players"][1]["position"] = ORDINARY_HOUSE
	return game


func _stage_nuclear_by_research(game: Object) -> bool:
	_prepare_landed_action(game, 0, CENTRE)
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), "research selection has a valid v13 save immediately before public choose_research: " + str(validation.get("errors", [])))
	var selection: Dictionary = game.choose_action("choose_research", {"tool_id": NUCLEAR})
	_expect(bool(selection.get("ok", false)), "research facility selects nuclear missile")
	if not bool(selection.get("ok", false)):
		return false
	for index_value in Fixture.facility_indices(game, 1):
		_expect_equal(int(game.state["board"][int(index_value)].get("research_tool", -1)), 5, "research selection stamps rank five on each alias")
		_expect_equal(int(game.state["board"][int(index_value)].get("research_turns", -1)), 5, "research selection starts a five-turn countdown")
	# Remove the landing evidence before synthetic end_turn calls.  This keeps
	# research ticking without replaying an unrelated landing settlement.
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game._set_action_options(0)
	for cycle in range(5):
		_prepare_action(game, 0, CENTRE, "await_action")
		validation = Game.validate_save(game.to_dict())
		_expect(bool(validation.get("ok", false)), "research cycle %d validates before player zero end_turn" % cycle)
		var first_end: Dictionary = game.end_turn()
		_expect(bool(first_end.get("ok", false)), "research cycle %d advances player zero" % cycle)
		_prepare_action(game, 1, ORDINARY_HOUSE, "await_action")
		validation = Game.validate_save(game.to_dict())
		_expect(bool(validation.get("ok", false)), "research cycle %d validates before player one end_turn" % cycle)
		var second_end: Dictionary = game.end_turn()
		_expect(bool(second_end.get("ok", false)), "research cycle %d advances player one and ticks the lab" % cycle)
	_expect_equal(int(game.state["players"][0]["tools"].get(NUCLEAR, 0)), 1, "research produces one nuclear missile")
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(NUCLEAR, -1)), 0, "research does not consume or create nuclear shared supply")
	_expect_equal(int(game.state["board"][CENTRE].get("research_tool", -1)), 5, "completed research retains rank auxiliary")
	_expect_equal(int(game.state["board"][CENTRE].get("research_turns", -1)), 0, "completed research clears countdown auxiliary")
	return true


func _test_nuclear_research_damage_and_non_global_boundary() -> void:
	var game: Object = _prepare_nuclear_game(8120)
	if game == null or not _stage_nuclear_by_research(game):
		return
	# Apply status after the research cycles so facility status is not changed by
	# the existing round-decay rule before the blast action.
	Fixture.set_facility(game, 1, 0, 5, 4, 0x50, 5, 0)
	Fixture.set_facility(game, 2, 1, 2, 2, 0x50, 0, 0)
	game.state["god_objects"] = [
		{"id": 1, "node": 9, "owner": -1, "days": 0},
		{"id": 3, "node": PRISON, "owner": -1, "days": 0},
	]
	var ordinary_before: Dictionary = game.state["board"][ORDINARY_HOUSE].duplicate(true)
	var chain_before: Dictionary = game.state["board"][CHAIN_HOUSE].duplicate(true)
	var source_one_before: Array = _facility_snapshot(game, 1)
	var source_two_before: Array = _facility_snapshot(game, 2)
	var prison_before: Dictionary = game.state["board"][PRISON].duplicate(true)
	var far_before: Dictionary = game.state["board"][FAR_NODE].duplicate(true)
	var nuclear_supply_before: int = int(game.state["inventory_supply"]["tools"].get(NUCLEAR, -1))
	_prepare_action(game, 0, CENTRE)
	var result: Dictionary = _public_use(game, {"tool_id": NUCLEAR, "tile_id": CENTRE}, "nuclear valid target")
	if not _expect_success(result, "nuclear valid target"):
		return
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(NUCLEAR, -1)), nuclear_supply_before, "nuclear consumes no invented shared supply")
	_expect_equal(int(game.state["players"][0]["tools"].get(NUCLEAR, 0)), 0, "nuclear removes the research-produced held tool")
	_expect_equal(int(game.state["players"][0].get("hospital_days", -1)), 3, "nuclear includes the caster in hospital admission")
	_expect_equal(int(game.state["players"][1].get("hospital_days", -1)), 3, "nuclear admits the other player")

	for property_id in [ORDINARY_HOUSE, CHAIN_HOUSE]:
		var property: Dictionary = game.state["board"][property_id]
		var before: Dictionary = ordinary_before if property_id == ORDINARY_HOUSE else chain_before
		_assert_static_property_fields(property, before, "nuclear property %d" % property_id)
		_expect_equal(int(property.get("owner", -1)), -1, "nuclear clears property %d ownership" % property_id)
		_expect_equal(int(property.get("building_level", -1)), 0, "nuclear clears property %d construction" % property_id)
		_expect_equal(bool(property.get("is_chain_store", true)), false, "nuclear clears property %d chain type" % property_id)
		_expect_equal(property.get("rent"), property.get("rent_by_level", [])[0], "nuclear refreshes property %d value" % property_id)
	_expect_equal(game.state["players"][1].get("properties", []), [], "nuclear clears the owner's property list")
	_expect_equal(int(game.state["players"][1].get("property_values", -1)), 0, "nuclear clears the owner's property value")

	for index_value in Fixture.facility_indices(game, 1):
		var facility: Dictionary = game.state["board"][int(index_value)]
		var before: Dictionary = source_one_before[Fixture.facility_indices(game, 1).find(int(index_value))]
		_assert_static_facility_fields(facility, before, "nuclear source-1 facility")
		_expect_equal(int(facility.get("owner", -1)), -1, "nuclear clears source-1 owner")
		_expect_equal(int(facility.get("building_level", -1)), 0, "nuclear clears source-1 level")
		_expect_equal(int(facility.get("facility_type", -1)), 0, "nuclear clears source-1 type")
		_expect_equal(int(facility.get("facility_state", -1)), 0x50, "nuclear preserves source-1 facility status")
		_expect_equal(int(facility.get("research_tool", -1)), 5, "nuclear preserves source-1 research rank")
		_expect_equal(int(facility.get("research_turns", -1)), 0, "nuclear preserves source-1 research countdown")
	for index_value in Fixture.facility_indices(game, 2):
		var facility: Dictionary = game.state["board"][int(index_value)]
		var before: Dictionary = source_two_before[Fixture.facility_indices(game, 2).find(int(index_value))]
		_assert_static_facility_fields(facility, before, "nuclear source-2 facility")
		_expect_equal(int(facility.get("owner", -1)), -1, "nuclear clears source-2 owner")
		_expect_equal(int(facility.get("building_level", -1)), 0, "nuclear clears source-2 level")
		_expect_equal(int(facility.get("facility_type", -1)), 0, "nuclear clears source-2 type")
		_expect_equal(int(facility.get("facility_state", -1)), 0x50, "nuclear preserves source-2 facility status")
	_expect_equal(game.state["players"][0].get("properties", []), [], "nuclear clears the former source-1 property list")
	_expect_equal(game.state["players"][1].get("properties", []), [], "nuclear clears the former source-2 property list")
	_expect_equal(game.state["board"][PRISON], prison_before, "nuclear excludes the first node outside half-extent 220")
	_expect_equal(game.state["board"][FAR_NODE], far_before, "nuclear excludes a distant logical node")
	_expect_equal(game.state["god_objects"].size(), 1, "nuclear removes only the in-range unbound god")
	if game.state["god_objects"].size() == 1:
		_expect_equal(int(game.state["god_objects"][0].get("node", -1)), PRISON, "nuclear preserves the out-of-range unbound god")
	_assert_tool_event(game, NUCLEAR, CENTRE, "nuclear valid target")
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), "nuclear damage leaves a valid save: " + str(validation.get("errors", [])))


func _prepare_staged_missile(seed_value: int) -> Object:
	var game: Object = _new_game(seed_value, 4)
	if game == null:
		return null
	_prepare_action(game, 0, CENTRE)
	if not _stage_tool(game, 0, MISSILE):
		return null
	_prepare_action(game, 0, CENTRE)
	return game


func _assert_rejected_atomic(game: Object, params: Dictionary, label: String) -> void:
	var before_json: String = game.to_json()
	var before_rng: String = str(game.state.get("rng_state_text", ""))
	var before_event: Dictionary = game.state.get("last_event", {}).duplicate(true)
	var before_supply: int = int(game.state["inventory_supply"]["tools"].get(MISSILE, -1))
	var before_held: int = int(game.state["players"][0]["tools"].get(MISSILE, 0))
	var result: Dictionary = _public_use(game, params, label)
	_mark_qualified_red(result, label)
	_expect(not bool(result.get("ok", false)), label + " is rejected")
	_expect(not str(result.get("message", "")).contains("尚未還原"), label + " reaches strict argument/target validation")
	_expect_equal(game.to_json(), before_json, label + " leaves the entire game unchanged")
	_expect_equal(str(game.state.get("rng_state_text", "")), before_rng, label + " does not consume RNG")
	_expect_equal(game.state.get("last_event", {}), before_event, label + " does not append an event")
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(MISSILE, -1)), before_supply, label + " does not recycle or consume the missile")
	_expect_equal(int(game.state["players"][0]["tools"].get(MISSILE, 0)), before_held, label + " keeps the held missile")


func _test_cancel_invalid_and_type_atomicity() -> void:
	var cancelled: Object = _prepare_staged_missile(8130)
	if cancelled != null:
		var before_json: String = cancelled.to_json()
		var before_rng: String = str(cancelled.state.get("rng_state_text", ""))
		var before_event: Dictionary = cancelled.state.get("last_event", {}).duplicate(true)
		var before_supply: int = int(cancelled.state["inventory_supply"]["tools"].get(MISSILE, -1))
		var before_held: int = int(cancelled.state["players"][0]["tools"].get(MISSILE, 0))
		var result: Dictionary = _public_use(cancelled, {"tool_id": MISSILE, "cancel": true}, "missile cancellation")
		_mark_qualified_red(result, "missile cancellation")
		_expect(bool(result.get("ok", false)), "missile cancellation succeeds")
		_expect_equal(cancelled.to_json(), before_json, "missile cancellation leaves the entire game unchanged")
		_expect_equal(str(cancelled.state.get("rng_state_text", "")), before_rng, "missile cancellation does not consume RNG")
		_expect_equal(cancelled.state.get("last_event", {}), before_event, "missile cancellation does not append an event")
		_expect_equal(int(cancelled.state["inventory_supply"]["tools"].get(MISSILE, -1)), before_supply, "missile cancellation preserves finite supply")
		_expect_equal(int(cancelled.state["players"][0]["tools"].get(MISSILE, 0)), before_held, "missile cancellation preserves held tool")

	var cases: Array = [
		{"label": "missile missing tile", "params": {"tool_id": MISSILE}},
		{"label": "missile negative tile", "params": {"tool_id": MISSILE, "tile_id": -1}},
		{"label": "missile off-map tile", "params": {"tool_id": MISSILE, "tile_id": 10}},
		{"label": "missile fractional tile", "params": {"tool_id": MISSILE, "tile_id": 1.5}},
		{"label": "missile string tile", "params": {"tool_id": MISSILE, "tile_id": "1"}},
		{"label": "missile boolean tile", "params": {"tool_id": MISSILE, "tile_id": true}},
		{"label": "missile malformed cancel", "params": {"tool_id": MISSILE, "tile_id": ORDINARY_HOUSE, "cancel": "yes"}},
		{"label": "missile malformed tool id", "params": {"tool_id": 7, "tile_id": ORDINARY_HOUSE}},
	]
	for offset in range(cases.size()):
		var game: Object = _prepare_staged_missile(8131 + offset)
		if game == null:
			continue
		var case_value: Dictionary = cases[offset]
		_assert_rejected_atomic(game, case_value["params"], str(case_value["label"]))


func _ai_game(seed_value: int) -> Object:
	var game: Object = _new_game(seed_value, 4)
	if game == null:
		return null
	_reset_players(game)
	Fixture.set_property(game, ORDINARY_HOUSE, 0, 1, false)
	Fixture.set_facility(game, 1, 0, 1, 1, 0, 0, 0)
	for player_id in range(game.state["players"].size()):
		game.state["players"][player_id]["position"] = FAR_NODE
	game.state["players"][0]["position"] = ORDINARY_HOUSE
	game.state["players"][1]["position"] = CENTRE
	game.state["players"][1]["cash"] = 1000
	game.state["players"][1]["deposit"] = 0
	Fixture.clear_tools_except(game, 1, [MISSILE])
	_expect(_stage_tool(game, 1, MISSILE), "AI fixture stages one missile")
	var deposit_total: int = 0
	for player_value in game.state["players"]:
		deposit_total += int(player_value.get("deposit", 0))
	game.state["bank"]["deposits"] = deposit_total
	game.state["day"] = 7
	game.state["current_player"] = 1
	game.state["phase"] = "await_roll"
	game._sync_state()
	game._set_action_options(1)
	return game


func _last_tool_event(game: Object, tool_id: String) -> Dictionary:
	var events: Array = game.state.get("event_log", [])
	for index in range(events.size() - 1, -1, -1):
		if typeof(events[index]) == TYPE_DICTIONARY:
			var event: Dictionary = events[index]
			if str(event.get("type", "")) == "tool_used" and str(event.get("tool_id", "")) == tool_id:
				return event
	return {}


func _test_ai_missile_determinism() -> void:
	var first: Object = _ai_game(8140)
	var second: Object = _ai_game(8140)
	if first == null or second == null:
		return
	var first_validation: Dictionary = Game.validate_save(first.to_dict())
	_expect(bool(first_validation.get("ok", false)), "AI missile fixture validates immediately before public run_ai_turn: " + str(first_validation.get("errors", [])))
	var second_validation: Dictionary = Game.validate_save(second.to_dict())
	_expect(bool(second_validation.get("ok", false)), "second AI missile fixture validates immediately before public run_ai_turn: " + str(second_validation.get("errors", [])))
	var first_result: Dictionary = first.run_ai_turn()
	var second_result: Dictionary = second.run_ai_turn()
	_expect(bool(first_result.get("ok", false)), "AI missile turn completes")
	_expect(bool(second_result.get("ok", false)), "repeat AI missile turn completes")
	var first_event: Dictionary = _last_tool_event(first, MISSILE)
	var second_event: Dictionary = _last_tool_event(second, MISSILE)
	_expect(not first_event.is_empty(), "AI missile turn records a missile event")
	_expect(not second_event.is_empty(), "repeat AI missile turn records a missile event")
	if first_event.is_empty():
		qualified_red += 1
		print("QUALIFIED RED: AI missile turn produced no missile event")
	else:
		_expect_equal(int(first_event.get("player_id", -1)), 1, "AI missile event identifies the AI caster")
		_expect_equal(int(first_event.get("tile_id", -1)), ORDINARY_HOUSE, "AI chooses the first useful other-player target")
	if second_event.is_empty():
		qualified_red += 1
	else:
		_expect_equal(second_event, first_event, "AI chooses the same legal missile target")
	_expect_equal(first.to_json(), second.to_json(), "identical AI missile seeds produce identical JSON")
