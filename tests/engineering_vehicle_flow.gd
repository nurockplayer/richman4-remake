extends SceneTree

## Issue #50 acceptance seed for research tool 12 (工程車).
##
## This is intentionally staged under .local while the production writer is
## being prepared.  It reuses the complete v13 research/building fixture and
## keeps all assertions on the public turn/action boundary or existing land
## mutation helpers.  The seed must stay source-independent: no new map node,
## save version, capability marker, or finite supply is introduced here.
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/god_card_fixture.gd")

const BASE_SAVE_VERSION := 13
const ENGINEERING_TOOL := "工程車"
const ENGINEERING_VEHICLE := "engineering"
const VEHICLE_DICE := {"walking": 1, "motorcycle": 2, "car": 3}
const MAX_ENGINEERING_ADMISSIONS := 7

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_fixture_and_capability_boundary()
	_test_activation_replacement_and_no_free_set()
	_test_cancel_and_escape_to_ordinary_vehicle()
	_test_seven_owner_admissions_and_restore()
	_test_missing_previous_vehicle_restores_walking()
	_test_hazard_death_and_inventory_reset()
	_test_landing_only_ownership_and_god_order()
	_test_facility_alias_clear_and_research_order()
	_test_gas_uses_engineering_multiplier_four()
	print("Engineering vehicle flow checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_game(seed_value: int, player_count: int = 3) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, Fixture.definition(), Fixture.new_game_options())
	_expect(game != null, "v13 research/building fixture starts")
	if game == null:
		return null
	_expect_equal(int(game.state.get("version", -1)), BASE_SAVE_VERSION, "engineering keeps the existing v13 save schema")
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), "fresh engineering fixture is save-valid: %s" % str(validation.get("errors", [])))
	return game


func _prepare_turn(game: Object, player_id: int, phase: String = "await_roll", position: int = -1) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	if position >= 0 and player_id >= 0 and player_id < game.state.get("players", []).size():
		game.state["players"][player_id]["position"] = position
		game.state["players"][player_id]["previous_position"] = -1
	game.call("_set_action_options", player_id)


func _stage_tool(game: Object, player_id: int, tool_id: String, label: String = "") -> bool:
	var before_supply: Dictionary = game.state["inventory_supply"]["tools"].duplicate(true)
	var result: Dictionary = Inventory.grant_tool(game.state["inventory_supply"], game.state["players"][player_id]["tools"], tool_id, 1)
	_expect(bool(result.get("ok", false)), "stage %s" % (label if not label.is_empty() else tool_id))
	if not bool(result.get("ok", false)):
		return false
	if tool_id == ENGINEERING_TOOL:
		_expect_equal(game.state["inventory_supply"]["tools"], before_supply, "research tool staging does not alter shared supply")
	return true


func _stage_engineering(game: Object, player_id: int, label: String = "engineering activation") -> bool:
	if not _stage_tool(game, player_id, ENGINEERING_TOOL, label + " stages tool"):
		return false
	_prepare_turn(game, player_id)
	var staged_validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(staged_validation.get("ok", false)), label + " staged fixture is save-valid: %s" % str(staged_validation.get("errors", [])))
	var before_supply: Dictionary = game.state["inventory_supply"]["tools"].duplicate(true)
	var result: Dictionary = game.choose_action("use_tool", {"tool_id": ENGINEERING_TOOL})
	_expect(bool(result.get("ok", false)), label + " uses 工程車 through use_tool")
	_expect_equal(game.state["inventory_supply"]["tools"], before_supply, label + " activation leaves research supply unchanged")
	if not bool(result.get("ok", false)):
		return false
	var player: Dictionary = game.state["players"][player_id]
	_expect_equal(str(player.get("vehicle", "")), ENGINEERING_VEHICLE, label + " selects engineering vehicle")
	_expect_equal(int(player.get("dice_count", -1)), 1, label + " fixes one die")
	_expect_equal(int(player.get("engineering_vehicle", {}).get("remaining_admissions", -1)), MAX_ENGINEERING_ADMISSIONS, label + " starts seven admissions")
	var active_validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(active_validation.get("ok", false)), label + " active state is save-valid: %s" % str(active_validation.get("errors", [])))
	return true


func _seed_active_engineering(game: Object, player_id: int, previous_vehicle: String = "walking", previous_dice: int = 1, remaining: int = MAX_ENGINEERING_ADMISSIONS) -> void:
	# This fallback lets the downstream landing/reset assertions remain useful
	# in the intentional RED run before the core action branch exists.  A green
	# implementation must reach exactly this shape through _stage_engineering.
	var player: Dictionary = game.state["players"][player_id]
	player["vehicle"] = ENGINEERING_VEHICLE
	player["dice_count"] = 1
	player["engineering_vehicle"] = {
		"remaining_admissions": remaining,
		"previous_vehicle": previous_vehicle,
		"previous_dice_count": previous_dice,
	}
	_prepare_turn(game, player_id)


func _activate_or_seed(game: Object, player_id: int, previous_vehicle: String = "walking", previous_dice: int = 1) -> void:
	if _stage_engineering(game, player_id):
		return
	# Mirror the one-unit research-tool consumption in the RED fallback.  The
	# production path performs this atomically before setting the active shape.
	var staged_tools: Dictionary = game.state["players"][player_id].get("tools", {})
	var staged_count: int = int(staged_tools.get(ENGINEERING_TOOL, 0))
	if staged_count <= 1:
		staged_tools.erase(ENGINEERING_TOOL)
	else:
		staged_tools[ENGINEERING_TOOL] = staged_count - 1
	var ordinary_tool: String = "汽車" if previous_vehicle == "car" else "機車" if previous_vehicle == "motorcycle" else ""
	if not ordinary_tool.is_empty():
		staged_tools[ordinary_tool] = int(staged_tools.get(ordinary_tool, 0)) + 1
	_seed_active_engineering(game, player_id, previous_vehicle, previous_dice)
	_validate_predecessor_projection(game, player_id, "engineering fallback")


func _activate_staged_or_seed(game: Object, player_id: int, previous_vehicle: String = "walking", previous_dice: int = 1) -> void:
	# Used after a cancellation check: the original staged research tool must
	# be consumed once, rather than being granted a second time by the harness.
	_prepare_turn(game, player_id)
	var staged_validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(staged_validation.get("ok", false)), "staged 工程車 fixture is save-valid: %s" % str(staged_validation.get("errors", [])))
	var result: Dictionary = game.choose_action("use_tool", {"tool_id": ENGINEERING_TOOL})
	_expect(bool(result.get("ok", false)), "staged 工程車 activates after cancellation")
	if bool(result.get("ok", false)):
		var active_validation: Dictionary = Game.validate_save(game.to_dict())
		_expect(bool(active_validation.get("ok", false)), "post-cancellation engineering state is save-valid: %s" % str(active_validation.get("errors", [])))
		return
	var tools: Dictionary = game.state["players"][player_id].get("tools", {})
	var quantity: int = int(tools.get(ENGINEERING_TOOL, 0))
	if quantity <= 1:
		tools.erase(ENGINEERING_TOOL)
	else:
		tools[ENGINEERING_TOOL] = quantity - 1
	_seed_active_engineering(game, player_id, previous_vehicle, previous_dice)
	_validate_predecessor_projection(game, player_id, "post-cancellation engineering fallback")


func _validate_predecessor_projection(game: Object, player_id: int, label: String) -> void:
	var projection: Dictionary = game.to_dict()
	var players: Array = projection.get("players", []).duplicate(true)
	if player_id < 0 or player_id >= players.size() or typeof(players[player_id]) != TYPE_DICTIONARY:
		_expect(false, label + " has a valid player projection")
		return
	var player: Dictionary = players[player_id]
	player.erase("engineering_vehicle")
	player["vehicle"] = "walking"
	player["dice_count"] = 1
	players[player_id] = player
	projection["players"] = players
	var validation: Dictionary = Game.validate_save(projection)
	_expect(bool(validation.get("ok", false)), label + " predecessor projection is save-valid: %s" % str(validation.get("errors", [])))


func _end_non_landing_turn(game: Object, player_id: int, label: String) -> Dictionary:
	_prepare_turn(game, player_id, "await_action")
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	var result: Dictionary = game.end_turn()
	_expect(bool(result.get("ok", false)), label + " ends through public end_turn")
	return result


func _set_successful_landing(game: Object, player_id: int, tile_id: int) -> void:
	_prepare_turn(game, player_id, "await_action", tile_id)
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.call("_set_action_options", player_id)


func _latest_event(game: Object, event_type: String) -> Dictionary:
	var log: Variant = game.state.get("event_log", [])
	if typeof(log) != TYPE_ARRAY:
		return {}
	for index in range(log.size() - 1, -1, -1):
		if typeof(log[index]) == TYPE_DICTIONARY and str(log[index].get("type", "")) == event_type:
			return log[index]
	return {}


func _event_index(game: Object, event_type: String) -> int:
	var log: Variant = game.state.get("event_log", [])
	if typeof(log) != TYPE_ARRAY:
		return -1
	for index in range(log.size()):
		if typeof(log[index]) == TYPE_DICTIONARY and str(log[index].get("type", "")) == event_type:
			return index
	return -1


func _property_indices(game: Object) -> Array:
	var result: Array = []
	for index in range(game.state.get("board", []).size()):
		var tile: Variant = game.state["board"][index]
		if typeof(tile) == TYPE_DICTIONARY and tile.get("kind", "") == "property":
			result.append(index)
	return result


func _facility_indices(game: Object, source_id: int) -> Array:
	var result: Array = []
	for index in range(game.state.get("board", []).size()):
		var tile: Variant = game.state["board"][index]
		if typeof(tile) == TYPE_DICTIONARY and tile.get("kind", "") == "facility" and int(tile.get("source_object_id", -1)) == source_id:
			result.append(index)
	return result


func _facility_source_with_aliases(game: Object) -> int:
	var counts: Dictionary = {}
	for tile_value in game.state.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility":
			continue
		var source_id: int = int(tile_value.get("source_object_id", -1))
		counts[source_id] = int(counts.get(source_id, 0)) + 1
	for source_id in counts.keys():
		if int(counts[source_id]) > 1:
			return int(source_id)
	return -1


func _set_property(game: Object, tile_id: int, owner_id: int, level: int, chain_store: bool = false) -> void:
	var tile: Dictionary = game.state["board"][tile_id]
	tile["owner"] = owner_id
	tile["building_level"] = level
	tile["is_chain_store"] = chain_store
	if tile.get("rent_by_level", []).is_empty() and tile.get("base_rent", 0) == 0:
		tile["base_rent"] = 100
		tile["rent"] = 100
	game.call("_update_tile_rent", tile)
	var canonical: int = int(tile.get("index", tile_id))
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var properties: Array = player_value.get("properties", []).duplicate(true)
		while properties.has(canonical):
			properties.erase(canonical)
		if int(player_value.get("id", -1)) == owner_id and owner_id >= 0:
			properties.append(canonical)
		player_value["properties"] = properties
	game.call("_recalculate_property_values")


func _set_facility(game: Object, source_id: int, owner_id: int, level: int, facility_type: int, research_tool: int = 0, research_turns: int = 0, facility_state: int = 0) -> Array:
	var indices: Array = _facility_indices(game, source_id)
	_expect(not indices.is_empty(), "fixture contains facility source %d" % source_id)
	if indices.is_empty():
		return []
	game.call("_update_facility_records", source_id, {
		"owner": owner_id,
		"building_level": level,
		"facility_type": facility_type,
		"research_tool": research_tool,
		"research_turns": research_turns,
		"facility_state": facility_state,
	})
	var canonical: int = int(game.state["board"][int(indices[0])].get("facility_node_index", int(indices[0])))
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var properties: Array = player_value.get("properties", []).duplicate(true)
		while properties.has(canonical):
			properties.erase(canonical)
		if int(player_value.get("id", -1)) == owner_id and owner_id >= 0:
			properties.append(canonical)
		player_value["properties"] = properties
	game.call("_recalculate_property_values")
	return indices


func _test_fixture_and_capability_boundary() -> void:
	var definition: Dictionary = Fixture.definition()
	_expect(bool(definition.get("supports_original_research", false)), "fixture exposes existing research capability")
	var game: Object = _new_game(5001)
	if game == null:
		return
	_expect(not game.state.has("engineering_vehicle"), "engineering does not add a top-level save marker")
	_expect(not game.state.has("engineering_save_version"), "engineering does not add a save version marker")
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(ENGINEERING_TOOL, -1)), 0, "research tool has no finite shared supply")
	_expect(game.item_is_implemented("tool", ENGINEERING_TOOL), "engineering tool is executable")
	var player: Dictionary = game.state["players"][0]
	var before_supply: Dictionary = game.state["inventory_supply"]["tools"].duplicate(true)
	var grant: Dictionary = Inventory.grant_tool(game.state["inventory_supply"], player["tools"], ENGINEERING_TOOL, 1)
	_expect(bool(grant.get("ok", false)), "engineering can be staged from research output")
	_expect_equal(game.state["inventory_supply"]["tools"], before_supply, "engineering staging does not debit a shared pool")
	_expect(not player.has("engineering_vehicle"), "staging the tool alone does not activate it")


func _test_activation_replacement_and_no_free_set() -> void:
	var game: Object = _new_game(5002)
	if game == null:
		return
	var player: Dictionary = game.state["players"][0]
	_expect(_stage_tool(game, 0, "汽車", "previous car"), "car is available for the replacement fixture")
	_prepare_turn(game, 0)
	var car_result: Dictionary = game.set_vehicle("car", 2)
	_expect(bool(car_result.get("ok", false)), "previous car equips with two dice")
	var car_supply_after_equip: int = int(game.state["inventory_supply"]["tools"].get("汽車", -1))
	_activate_or_seed(game, 0, "car", 2)
	player = game.state["players"][0]
	_expect_equal(str(player.get("vehicle", "")), ENGINEERING_VEHICLE, "activation replaces a held car")
	_expect_equal(int(player.get("dice_count", -1)), 1, "engineering activation always uses one die")
	_expect_equal(int(player.get("tools", {}).get("汽車", 0)), 1, "equipped car returns to held inventory")
	_expect_equal(int(player.get("tools", {}).get(ENGINEERING_TOOL, 0)), 0, "activation consumes one engineering tool")
	_expect_equal(int(game.state["inventory_supply"]["tools"].get("汽車", -1)), car_supply_after_equip, "ordinary vehicle finite supply is unchanged by replacement")
	_expect_equal(player.get("engineering_vehicle", {}).get("previous_vehicle", ""), "car", "previous vehicle metadata is retained")
	_expect_equal(int(player.get("engineering_vehicle", {}).get("previous_dice_count", -1)), 2, "previous dice metadata is retained")
	var repeated_before: String = game.to_json()
	_prepare_turn(game, 0)
	var repeated: Dictionary = game.choose_action("use_tool", {"tool_id": ENGINEERING_TOOL})
	_expect(not bool(repeated.get("ok", false)), "active engineering vehicle cannot be activated again")
	_expect_equal(game.to_json(), repeated_before, "repeated activation is atomic")

	var free_game: Object = _new_game(5003)
	if free_game == null:
		return
	_prepare_turn(free_game, 0)
	var free_before: String = free_game.to_json()
	var free_set: Dictionary = free_game.set_vehicle(ENGINEERING_VEHICLE, 1)
	_expect(not bool(free_set.get("ok", false)), "set_vehicle cannot acquire engineering for free")
	_expect_equal(free_game.to_json(), free_before, "free engineering selection is atomic")
	_activate_or_seed(free_game, 0)
	_prepare_turn(free_game, 0)
	var active_set: Dictionary = free_game.set_vehicle(ENGINEERING_VEHICLE, 1)
	_expect(bool(active_set.get("ok", false)), "active engineering can explicitly retain one die")
	_expect_equal(int(free_game.state["players"][0].get("engineering_vehicle", {}).get("remaining_admissions", -1)), 7, "same engineering selection keeps its timer")


func _test_cancel_and_escape_to_ordinary_vehicle() -> void:
	var game: Object = _new_game(5004)
	if game == null:
		return
	_stage_tool(game, 0, ENGINEERING_TOOL, "cancel")
	_prepare_turn(game, 0)
	var before_cancel: String = game.to_json()
	var cancelled: Dictionary = game.choose_action("use_tool", {"tool_id": ENGINEERING_TOOL, "cancel": true})
	_expect(not bool(cancelled.get("ok", false)) or bool(cancelled.get("cancelled", false)), "cancelling an unselected engineering use does not activate")
	_expect_equal(game.to_json(), before_cancel, "engineering cancellation does not consume or mutate")
	_activate_staged_or_seed(game, 0)
	var player: Dictionary = game.state["players"][0]
	var before_engineering_supply: int = int(game.state["inventory_supply"]["tools"].get(ENGINEERING_TOOL, -1))
	_expect(_stage_tool(game, 0, "機車", "escape motorcycle"), "motorcycle is available for early replacement")
	_prepare_turn(game, 0)
	var escape: Dictionary = game.set_vehicle("motorcycle", 2)
	_expect(bool(escape.get("ok", false)), "ordinary motorcycle can replace engineering early")
	player = game.state["players"][0]
	_expect_equal(str(player.get("vehicle", "")), "motorcycle", "early replacement selects motorcycle")
	_expect_equal(int(player.get("dice_count", -1)), 2, "early replacement restores ordinary dice selection")
	_expect(not player.has("engineering_vehicle"), "early replacement clears engineering metadata")
	_expect_equal(int(player.get("tools", {}).get(ENGINEERING_TOOL, 0)), 0, "early replacement does not return consumed engineering tool")
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(ENGINEERING_TOOL, -1)), before_engineering_supply, "early replacement leaves research supply unchanged")

	var remote_game: Object = _new_game(5005)
	if remote_game == null:
		return
	_activate_or_seed(remote_game, 0)
	_prepare_turn(remote_game, 0)
	remote_game.state["pending_remote_dice"] = {"player_id": 0, "value": 4}
	var remote_before: String = remote_game.to_json()
	var remote_attempt: Dictionary = remote_game.choose_action("use_tool", {"tool_id": ENGINEERING_TOOL})
	_expect(not bool(remote_attempt.get("ok", false)), "pending remote dice blocks engineering activation")
	_expect(remote_game.to_json() == remote_before, "remote-dice rejection is atomic")


func _test_seven_owner_admissions_and_restore() -> void:
	var game: Object = _new_game(5006, 2)
	if game == null:
		return
	var player: Dictionary = game.state["players"][0]
	_stage_tool(game, 0, "汽車", "expiry previous car")
	_prepare_turn(game, 0)
	game.set_vehicle("car", 2)
	_activate_or_seed(game, 0, "car", 2)
	player = game.state["players"][0]
	var initial_remaining: int = int(player.get("engineering_vehicle", {}).get("remaining_admissions", -1))
	_expect_equal(initial_remaining, 7, "activation begins with seven own admissions")
	# An opponent admission does not count.  Each pair then admits player 0
	# once, without relying on movement or a full round boundary.
	_end_non_landing_turn(game, 0, "expiry actor turn")
	_expect_equal(int(player.get("engineering_vehicle", {}).get("remaining_admissions", -1)), initial_remaining, "opponent admission does not decrement engineering")
	for admission in range(1, 7):
		_end_non_landing_turn(game, 1, "expiry opponent turn %d" % admission)
		_end_non_landing_turn(game, 0, "expiry owner turn %d" % admission)
		if admission < 7:
			_expect_equal(int(player.get("engineering_vehicle", {}).get("remaining_admissions", -1)), 7 - admission, "owner admission %d decrements only the timer" % admission)
		_expect_equal(int(game.state["players"][1].get("turns_taken", 0)), admission, "other player's turn still progresses normally")
	_expect_equal(str(player.get("vehicle", "")), ENGINEERING_VEHICLE, "six later owner admissions retain engineering")
	_expect_equal(int(player.get("dice_count", -1)), 1, "engineering remains one die before expiry")
	# Seventh subsequent owner admission expires before that actor can move.
	_end_non_landing_turn(game, 1, "expiry final opponent turn")
	_expect_equal(str(player.get("vehicle", "")), "car", "seventh owner admission restores the held car")
	_expect_equal(int(player.get("dice_count", -1)), 2, "expiry restores the previous dice count")
	_expect(not player.has("engineering_vehicle"), "expiry removes optional engineering metadata")
	_expect_equal(int(player.get("tools", {}).get("汽車", 0)), 0, "expiry re-equips one restored car")

	var rest_game: Object = _new_game(5007, 2)
	if rest_game == null:
		return
	_activate_or_seed(rest_game, 0)
	var rest_player: Dictionary = rest_game.state["players"][0]
	rest_player["hospital_days"] = 2
	var before_rest: int = int(rest_player.get("engineering_vehicle", {}).get("remaining_admissions", -1))
	_end_non_landing_turn(rest_game, 0, "rest admission actor turn")
	_end_non_landing_turn(rest_game, 1, "rest admission owner turn")
	_expect_equal(int(rest_player.get("engineering_vehicle", {}).get("remaining_admissions", -1)), before_rest - 1, "a rest admission counts as the owner's incoming admission")


func _test_missing_previous_vehicle_restores_walking() -> void:
	var game: Object = _new_game(5008, 2)
	if game == null:
		return
	_stage_tool(game, 0, "汽車", "missing restore car")
	_prepare_turn(game, 0)
	game.set_vehicle("car", 3)
	_activate_or_seed(game, 0, "car", 3)
	var player: Dictionary = game.state["players"][0]
	# The previous car was returned to held inventory by activation. Remove that
	# unit to exercise the fail-closed restore branch without minting one.
	var returned_car: Dictionary = Inventory.consume_tool(game.state["inventory_supply"], player["tools"], "汽車", 1)
	_expect(bool(returned_car.get("ok", false)), "missing restore fixture returns its held car to finite supply")
	for _admission in range(7):
		_end_non_landing_turn(game, 0, "missing restore actor turn")
		_end_non_landing_turn(game, 1, "missing restore opponent turn")
	_expect_equal(str(player.get("vehicle", "")), "walking", "missing previous vehicle restores walking")
	_expect_equal(int(player.get("dice_count", -1)), 1, "missing previous vehicle restores one die")
	_expect(not player.has("engineering_vehicle"), "missing restore clears timer")
	_expect_equal(int(player.get("tools", {}).get("汽車", 0)), 0, "missing restore does not mint an ordinary vehicle")


func _test_hazard_death_and_inventory_reset() -> void:
	var hazard_game: Object = _new_game(5009, 3)
	if hazard_game == null:
		return
	_expect(_stage_tool(hazard_game, 0, "汽車", "hazard previous car"), "hazard fixture stages a finite car")
	_prepare_turn(hazard_game, 0)
	var hazard_car_result: Dictionary = hazard_game.set_vehicle("car", 2)
	_expect(bool(hazard_car_result.get("ok", false)), "hazard fixture equips its previous car")
	_activate_or_seed(hazard_game, 0, "car", 2)
	var hazard_player: Dictionary = hazard_game.state["players"][0]
	var mine_node: int = -1
	for index in range(hazard_game.state["board"].size()):
		var tile: Dictionary = hazard_game.state["board"][index]
		if tile.get("kind", "") in ["property", "rest"] and tile.get("adjacent", []).size() > 0:
			mine_node = index
			break
	_expect(mine_node >= 0, "hazard fixture has a reachable road node")
	var mine_held_before: int = int(hazard_player.get("tools", {}).get("地雷", 0))
	var mine_consumed: bool = bool(hazard_game.call("_hazard_consume_tool_without_supply", hazard_player, "地雷"))
	_expect(mine_consumed, "hazard fixture consumes its held mine before placing it")
	_expect_equal(int(hazard_player.get("tools", {}).get("地雷", 0)), mine_held_before - 1, "ground mine placement removes one held mine")
	hazard_game.state["ground_hazards"][str(mine_node)] = {"kind": "mine", "placer_id": 1}
	var hazard_result: Variant = hazard_game.call("_hazard_process_ground", 0, mine_node)
	_expect(bool(hazard_result), "mine processes an active engineering vehicle")
	_expect_equal(int(hazard_player.get("hospital_days", 0)), 3, "mine keeps the existing hospital admission")
	_expect_equal(str(hazard_player.get("vehicle", "")), "walking", "mine clears active engineering vehicle")
	_expect(not hazard_player.has("engineering_vehicle"), "mine clears engineering timer")

	var clear_game: Object = _new_game(5010)
	if clear_game == null:
		return
	_expect(_stage_tool(clear_game, 0, "汽車", "inventory clear previous car"), "inventory clear fixture stages a finite car")
	_prepare_turn(clear_game, 0)
	var clear_car_result: Dictionary = clear_game.set_vehicle("car", 2)
	_expect(bool(clear_car_result.get("ok", false)), "inventory clear fixture equips its previous car")
	_activate_or_seed(clear_game, 0, "car", 2)
	var clear_player: Dictionary = clear_game.state["players"][0]
	clear_game.call("_clear_player_inventory", 0)
	_expect_equal(str(clear_player.get("vehicle", "")), "walking", "inventory clear resets vehicle")
	_expect_equal(int(clear_player.get("dice_count", -1)), 1, "inventory clear resets dice")
	_expect(not clear_player.has("engineering_vehicle"), "inventory clear removes engineering timer")

	var bankrupt_game: Object = _new_game(5011, 3)
	if bankrupt_game == null:
		return
	_activate_or_seed(bankrupt_game, 0)
	var bankrupt_player: Dictionary = bankrupt_game.state["players"][0]
	var bankruptcy_debt: int = int(bankrupt_player.get("cash", 0)) + int(bankrupt_player.get("deposit", 0)) + 1
	bankrupt_game.call("_charge_amount", 0, bankruptcy_debt, -1, "engineering_test", false)
	_expect(not bool(bankrupt_player.get("alive", true)), "bankruptcy marks the active player dead")
	_expect(not bankrupt_player.has("engineering_vehicle"), "bankruptcy clears engineering timer")
	_expect_equal(str(bankrupt_player.get("vehicle", "")), "walking", "bankruptcy fails closed to walking")
	_expect_equal(int(bankrupt_player.get("dice_count", -1)), 1, "bankruptcy fails closed to one die")
	_validate_predecessor_projection(bankrupt_game, 0, "bankruptcy fixture")


func _test_landing_only_ownership_and_god_order() -> void:
	var properties: Array
	var enemy: Object = _new_game(5012)
	if enemy == null:
		return
	properties = _property_indices(enemy)
	if properties.is_empty():
		_expect(false, "fixture has an ordinary property")
		return
	var target: int = int(properties[0])
	_set_property(enemy, target, 1, 2)
	_activate_or_seed(enemy, 0)
	_set_successful_landing(enemy, 0, target)
	var enemy_end: Dictionary = enemy.end_turn()
	_expect(bool(enemy_end.get("ok", false)), "enemy property landing ends")
	_expect_equal(int(enemy.state["board"][target].get("building_level", -1)), 1, "enemy built property loses one level on final landing")
	_expect_equal(int(enemy.state["board"][target].get("owner", -1)), 1, "enemy property ownership is preserved")
	_expect(_latest_event(enemy, "engineering_demolition").get("tile_id", -1) == target, "enemy landing records engineering demolition")

	var unowned: Object = _new_game(5013)
	if unowned == null:
		return
	var unowned_target: int = int(_property_indices(unowned)[0])
	_set_property(unowned, unowned_target, -1, 1)
	_activate_or_seed(unowned, 0)
	_set_successful_landing(unowned, 0, unowned_target)
	unowned.end_turn()
	_expect_equal(int(unowned.state["board"][unowned_target].get("building_level", -1)), 0, "unowned built property is demolished")
	_expect_equal(int(unowned.state["board"][unowned_target].get("owner", -1)), -1, "unowned property remains unowned")

	var self_owned: Object = _new_game(5014)
	if self_owned == null:
		return
	var self_target: int = int(_property_indices(self_owned)[0])
	_set_property(self_owned, self_target, 0, 2)
	_activate_or_seed(self_owned, 0)
	_set_successful_landing(self_owned, 0, self_target)
	self_owned.end_turn()
	_expect_equal(int(self_owned.state["board"][self_target].get("building_level", -1)), 2, "self-owned property is not demolished")

	var empty: Object = _new_game(5015)
	if empty == null:
		return
	var empty_target: int = int(_property_indices(empty)[0])
	_set_property(empty, empty_target, 1, 0)
	_activate_or_seed(empty, 0)
	_set_successful_landing(empty, 0, empty_target)
	empty.end_turn()
	_expect_equal(int(empty.state["board"][empty_target].get("building_level", -1)), 0, "empty property is not demolished")

	var passed: Object = _new_game(5016)
	if passed == null:
		return
	var passed_target: int = int(_property_indices(passed)[0])
	var rest_target: int = 0
	_set_property(passed, passed_target, 1, 2)
	_activate_or_seed(passed, 0)
	passed.call("_graph_visit_tile", 0, passed.state["board"][passed_target], false, false)
	_set_successful_landing(passed, 0, rest_target)
	passed.end_turn()
	_expect_equal(int(passed.state["board"][passed_target].get("building_level", -1)), 2, "passing a built property does not demolish it")

	var nonmovement: Object = _new_game(5017)
	if nonmovement == null:
		return
	var nonmovement_target: int = int(_property_indices(nonmovement)[0])
	_set_property(nonmovement, nonmovement_target, 1, 2)
	_activate_or_seed(nonmovement, 0)
	_prepare_turn(nonmovement, 0, "await_action", nonmovement_target)
	nonmovement.state["last_roll"] = []
	nonmovement.end_turn()
	_expect_equal(int(nonmovement.state["board"][nonmovement_target].get("building_level", -1)), 2, "a nonmovement turn does not demolish")

	var god_game: Object = _new_game(5018)
	if god_game == null:
		return
	var god_target: int = int(_property_indices(god_game)[0])
	_set_property(god_game, god_target, 1, 2)
	god_game.state["god_objects"] = [{"id": 10, "node": god_target, "owner": 0, "days": 7}]
	god_game.state["players"][0]["god_id"] = 10
	god_game.state["players"][0]["position"] = god_target
	god_game.state["players"][0]["previous_position"] = -1
	_activate_or_seed(god_game, 0)
	_set_successful_landing(god_game, 0, god_target)
	god_game.end_turn()
	_expect_equal(int(god_game.state["board"][god_target].get("building_level", -1)), 0, "god property effect runs before engineering demolition")
	_expect(_event_index(god_game, "god_property_effect") >= 0, "god effect is recorded")
	_expect(_event_index(god_game, "engineering_demolition") > _event_index(god_game, "god_property_effect"), "engineering demolition follows god effect in the landing tail")


func _test_facility_alias_clear_and_research_order() -> void:
	var game: Object = _new_game(5019, 2)
	if game == null:
		return
	var source_id: int = _facility_source_with_aliases(game)
	_expect(source_id > 0, "fixture has a duplicated facility source")
	if source_id <= 0:
		return
	var aliases: Array = _set_facility(game, source_id, 1, 1, 4, 1, 1, 0x50)
	var preserved_land_price: int = int(game.state["board"][int(aliases[0])].get("land_price", -1))
	var preserved_cost: int = int(game.state["board"][int(aliases[0])].get("cost", -1))
	_activate_or_seed(game, 0)
	var target: int = int(aliases[aliases.size() - 1])
	_set_successful_landing(game, 0, target)
	game.end_turn()
	for alias_value in aliases:
		var alias: Dictionary = game.state["board"][int(alias_value)]
		_expect_equal(int(alias.get("building_level", -1)), 0, "facility alias clears level")
		_expect_equal(int(alias.get("facility_type", -1)), 0, "facility alias clears type")
		_expect_equal(int(alias.get("owner", -1)), 1, "facility alias preserves owner")
		_expect_equal(int(alias.get("facility_state", -1)), 0x50, "facility alias preserves unrelated temporary state")
		_expect_equal(int(alias.get("land_price", -1)), preserved_land_price, "facility alias preserves land price")
		_expect_equal(int(alias.get("cost", -1)), preserved_cost, "facility alias preserves cost")
	_expect(_event_index(game, "research_produced") < 0, "research does not produce after the facility is cleared")

	var unowned: Object = _new_game(5020)
	if unowned == null:
		return
	var unowned_source: int = _facility_source_with_aliases(unowned)
	var unowned_aliases: Array = _set_facility(unowned, unowned_source, -1, 1, 2)
	_activate_or_seed(unowned, 0)
	_set_successful_landing(unowned, 0, int(unowned_aliases[0]))
	unowned.end_turn()
	for alias_value in unowned_aliases:
		_expect_equal(int(unowned.state["board"][int(alias_value)].get("building_level", -1)), 0, "unowned facility aliases are demolished")
		_expect_equal(int(unowned.state["board"][int(alias_value)].get("owner", -1)), -1, "unowned facility aliases remain unowned")


func _test_gas_uses_engineering_multiplier_four() -> void:
	var game: Object = _new_game(5021, 2)
	if game == null:
		return
	var source_id: int = _facility_source_with_aliases(game)
	if source_id <= 0:
		_expect(false, "gas fixture has a duplicated facility source")
		return
	var aliases: Array = _set_facility(game, source_id, 1, 1, 3)
	_activate_or_seed(game, 0)
	var gas_node: int = int(aliases[0])
	game.state["players"][0]["cash"] = 100000
	game.state["players"][1]["cash"] = 100000
	_set_successful_landing(game, 0, gas_node)
	game.state["last_roll"] = [4]
	game.state["last_total"] = 4
	game.state["last_roll_total"] = 4
	game.call("_resolve_landing", 0)
	_expect_equal(str(game.state.get("phase", "")), "await_action", "gas landing resolves through the existing landing helper")
	var service: Dictionary = _latest_event(game, "facility_service")
	_expect_equal(str(service.get("vehicle", "")), ENGINEERING_VEHICLE, "gas service records engineering vehicle")
	_expect_equal(int(service.get("last_roll_total", -1)), 4, "gas service uses the complete roll total")
	_expect_equal(int(service.get("fee", -1)), 8000, "engineering gas fee uses source multiplier four")
	var ending: Dictionary = game.end_turn()
	_expect(bool(ending.get("ok", false)), "gas landing can finish its turn")
	_expect_equal(int(game.state["board"][gas_node].get("building_level", -1)), 0, "engineering gas landing demolishes after service")
