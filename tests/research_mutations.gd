extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/research_fixture.gd")

const RESEARCH_SAVE_VERSION := 12
const LAB_TYPE := 4
const RESEARCH_TOOLS := ["", "機器工人", "時光機", "傳送機", "工程車", "核子飛彈"]

var checks: int = 0
var failures: int = 0
var bootstrap_red: int = 0
var bootstrap_reported: bool = false


func _initialize() -> void:
	_test_v11_lab_guard()
	_test_lab_build_and_upgrade()
	_test_public_research_schedule()
	_test_rank_boundaries()
	_test_research_rejections()
	_test_incoming_owner_production()
	_test_nonlab_and_unowned_jobs()
	_test_lab_worker_upgrade()
	_test_job_address_stability()
	_test_bankruptcy_preserves_job()
	print("Original research mutation checks: %d, failures: %d, bootstrap_red: %d" % [checks, failures, bootstrap_red])
	quit(1 if failures or bootstrap_red > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_research_game(seed_value: int) -> Object:
	var definition: Dictionary = Fixture.definition()
	var game: Object = Game.new_game_on_board(seed_value, 4, definition, Fixture.new_game_options())
	if game != null:
		return game
	bootstrap_red += 1
	if not bootstrap_reported:
		bootstrap_reported = true
		print("BOOTSTRAP RED: v12 research factory is unavailable; mutation checks use a locally stamped v12 fallback")
	var legacy: Object = Game.new_game_on_board(seed_value, 4, definition, Fixture.v11_game_options())
	_expect(legacy != null, "v11 fixture bootstraps the v12 research harness")
	if legacy == null:
		return null
	legacy.state["version"] = RESEARCH_SAVE_VERSION
	legacy.state["original_property_cards"] = true
	legacy.state["original_remodel"] = true
	legacy.state["original_research"] = true
	legacy.state["research_action_used"] = false
	for tile_value in legacy.state.get("board", []):
		if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "facility":
			tile_value["research_tool"] = 0
			tile_value["research_turns"] = 0
	legacy._sync_state()
	return legacy


func _new_v11_game(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.v11_game_options())
	_expect(game != null, "v11 predecessor fixture starts")
	return game


func _prepare_action(game: Object, player_id: int, position: int, phase: String = "await_action") -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["company_service_pending"] = 0
	game.state["god_objects"] = []
	game.state["players"][player_id]["position"] = position
	game.state["players"][player_id]["previous_position"] = -1
	for candidate in game.state.get("players", []):
		candidate["hospital_days"] = 0
		candidate["prison_days"] = 0
		candidate["god_id"] = 0
	game._set_action_options(player_id)


func _facility_indices(game: Object, source_object_id: int) -> Array:
	var result: Array = []
	for index in range(game.state.get("board", []).size()):
		var tile: Dictionary = game.state["board"][index]
		if tile.get("kind", "") == "facility" and int(tile.get("source_object_id", -1)) == source_object_id:
			result.append(index)
	return result


func _set_facility_state(
	game: Object,
	source_object_id: int,
	owner_id: int,
	level: int,
	facility_type: int,
	research_tool: int = 0,
	research_turns: int = 0,
	facility_state: int = 0,
) -> void:
	var indices: Array = _facility_indices(game, source_object_id)
	var canonical_id: int = -1
	for tile_id in indices:
		var tile: Dictionary = game.state["board"][int(tile_id)]
		if canonical_id < 0:
			canonical_id = int(tile.get("facility_node_index", tile_id))
		tile["owner"] = owner_id
		tile["building_level"] = level
		tile["facility_type"] = facility_type
		tile["facility_state"] = facility_state
		tile["research_tool"] = research_tool
		tile["research_turns"] = research_turns
	for player in game.state.get("players", []):
		var properties: Array = player.get("properties", []).duplicate(true)
		while canonical_id >= 0 and properties.has(canonical_id):
			properties.erase(canonical_id)
		if int(player.get("id", -1)) == owner_id and canonical_id >= 0:
			properties.append(canonical_id)
		player["properties"] = properties
	game._recalculate_property_values()


func _set_research_job(game: Object, source_object_id: int, research_tool: int, research_turns: int) -> void:
	var indices: Array = _facility_indices(game, source_object_id)
	if indices.is_empty():
		return
	var first: Dictionary = game.state["board"][int(indices[0])]
	_set_facility_state(
		game,
		source_object_id,
		int(first.get("owner", -1)),
		int(first.get("building_level", 0)),
		int(first.get("facility_type", 0)),
		research_tool,
		research_turns,
		int(first.get("facility_state", 0)),
	)


func _stage_card(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	_expect(bool(result.get("ok", false)), "fixture stages %s" % card_id)
	return bool(result.get("ok", false))


func _cash_snapshot(game: Object) -> Array:
	var result: Array = []
	for player in game.state.get("players", []):
		result.append(int(player.get("cash", 0)))
	return result


func _research_snapshot(game: Object, source_object_id: int) -> Dictionary:
	var result: Dictionary = {"aliases": []}
	for tile_id in _facility_indices(game, source_object_id):
		var tile: Dictionary = game.state["board"][int(tile_id)]
		result["aliases"].append({
			"owner": tile.get("owner", null),
			"building_level": tile.get("building_level", null),
			"facility_type": tile.get("facility_type", null),
			"facility_state": tile.get("facility_state", null),
			"research_tool": tile.get("research_tool", null),
			"research_turns": tile.get("research_turns", null),
		})
	return result


func _end_one_turn(game: Object, player_id: int) -> Dictionary:
	game.state["current_player"] = player_id
	game.state["phase"] = "await_action"
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game._set_action_options(player_id)
	return game.end_turn()


func _advance_to_owner(game: Object, owner_id: int) -> void:
	var guard := 0
	while int(game.state.get("current_player", -1)) != owner_id and guard < 4:
		var current_id := int(game.state.get("current_player", -1))
		var result: Dictionary = _end_one_turn(game, current_id)
		_expect(bool(result.get("ok", false)), "turn advances toward incoming research owner")
		guard += 1
	_expect_equal(int(game.state.get("current_player", -1)), owner_id, "turn advances to incoming research owner")


func _expect_rejected_atomic(game: Object, params: Dictionary, label: String) -> void:
	var before: String = game.to_json()
	var result: Dictionary = game.choose_action("choose_research", params)
	_expect(not bool(result.get("ok", false)), label + " is rejected")
	_expect_equal(game.to_json(), before, label + " leaves the whole game unchanged")


func _test_v11_lab_guard() -> void:
	var game: Object = _new_v11_game(9301)
	if game == null:
		return
	_set_facility_state(game, 1, 0, 0, 0)
	_prepare_action(game, 0, 1)
	var before_build: String = game.to_json()
	var build: Dictionary = game.choose_action("build_facility", {"facility_type": LAB_TYPE})
	_expect(not bool(build.get("ok", false)), "v11 rejects research facility construction")
	_expect_equal(game.to_json(), before_build, "v11 rejected research construction is atomic")

	_set_facility_state(game, 1, 0, 1, LAB_TYPE)
	_prepare_action(game, 0, 1)
	var before_upgrade: String = game.to_json()
	var upgrade: Dictionary = game.choose_action("upgrade")
	_expect(not bool(upgrade.get("ok", false)), "v11 keeps the research facility upgrade guard")
	_expect_equal(game.to_json(), before_upgrade, "v11 rejected research upgrade is atomic")


func _test_lab_build_and_upgrade() -> void:
	var game: Object = _new_research_game(9302)
	if game == null:
		return
	_prepare_action(game, 0, 1)
	var cash_before: int = int(game.state["players"][0].get("cash", 0))
	var bank_before: int = int(game.state["bank"].get("cash", 0))
	var buy: Dictionary = game.choose_action("buy")
	_expect(bool(buy.get("ok", false)), "research facility land can be bought")
	_expect_equal(int(game.state["players"][0].get("cash", 0)), cash_before - 1000, "research facility land price follows ordinary facility price")
	_expect_equal(int(game.state["bank"].get("cash", 0)), bank_before + 1000, "research facility land payment reaches the bank")

	game.state["property_action_used"] = false
	game._set_action_options(0)
	var build: Dictionary = game.choose_action("build_facility", {"facility_type": LAB_TYPE})
	_expect(bool(build.get("ok", false)), "v12 can build a research facility")
	_expect_equal(int(build.get("event", {}).get("price", -1)), 1000, "research facility build uses ordinary land price")
	var indices: Array = _facility_indices(game, 1)
	for tile_id in indices:
		var tile: Dictionary = game.state["board"][int(tile_id)]
		_expect_equal(int(tile.get("facility_type", -1)), LAB_TYPE, "research facility build synchronizes facility type aliases")
		_expect_equal(int(tile.get("building_level", -1)), 1, "research facility build reaches level one")

	for expected_level in range(2, 6):
		game.state["property_action_used"] = false
		game._set_action_options(0)
		var upgrade: Dictionary = game.choose_action("upgrade")
		_expect(bool(upgrade.get("ok", false)), "research facility upgrades to level %d" % expected_level)
		_expect_equal(int(upgrade.get("event", {}).get("price", -1)), 300, "research facility upgrade keeps ordinary price at level %d" % expected_level)
		for tile_id in indices:
			_expect_equal(int(game.state["board"][int(tile_id)].get("building_level", -1)), expected_level, "research facility level %d synchronizes aliases" % expected_level)


func _test_public_research_schedule() -> void:
	var game: Object = _new_research_game(9303)
	if game == null:
		return
	_set_facility_state(game, 1, 0, 3, LAB_TYPE)
	_prepare_action(game, 0, 1)
	var cash_before: Array = _cash_snapshot(game)
	var bank_before: Dictionary = game.state["bank"].duplicate(true)
	var supply_before: Dictionary = game.state["inventory_supply"].duplicate(true)
	var result: Dictionary = game.choose_action("choose_research", {"tool_id": RESEARCH_TOOLS[1]})
	_expect(bool(result.get("ok", false)), "owner can schedule a level-one research product")
	_expect(bool(game.state.get("research_action_used", false)), "successful research records the action-used marker")
	for tile_id in _facility_indices(game, 1):
		var tile: Dictionary = game.state["board"][int(tile_id)]
		_expect_equal(int(tile.get("research_tool", -1)), 1, "research rank one synchronizes aliases")
		_expect_equal(int(tile.get("research_turns", -1)), 5, "research starts with five owner turns")
	_expect_equal(_cash_snapshot(game), cash_before, "research selection does not charge player cash")
	_expect_equal(game.state["bank"], bank_before, "research selection does not charge the bank")
	_expect_equal(game.state["inventory_supply"], supply_before, "research selection does not consume shared tool supply")

	var before_repeat: String = game.to_json()
	var repeat: Dictionary = game.choose_action("choose_research", {"tool_id": RESEARCH_TOOLS[2]})
	_expect(not bool(repeat.get("ok", false)), "same visit cannot schedule research twice")
	_expect_equal(game.to_json(), before_repeat, "repeat research selection is atomic")

	var after_turn: Dictionary = _end_one_turn(game, 0)
	_expect(bool(after_turn.get("ok", false)), "owner can end a research scheduling turn")
	_expect(not bool(game.state.get("research_action_used", true)), "ending the turn clears the research action-used marker")
	_expect_equal(int(game.state["board"][1].get("research_turns", -1)), 5, "outgoing research turn does not decrement its new job")

	_set_research_job(game, 1, 2, 2)
	_prepare_action(game, 0, 1)
	var reschedule: Dictionary = game.choose_action("choose_research", {"tool_id": RESEARCH_TOOLS[2]})
	_expect(bool(reschedule.get("ok", false)), "owner can reschedule an existing research job on a later visit")
	_expect_equal(int(game.state["board"][1].get("research_tool", -1)), 2, "rescheduling replaces the selected product")
	_expect_equal(int(game.state["board"][1].get("research_turns", -1)), 5, "rescheduling resets the countdown to five owner turns")


func _test_rank_boundaries() -> void:
	for level in range(1, 6):
		var game: Object = _new_research_game(9319 + level)
		if game == null:
			continue
		_set_facility_state(game, 1, 0, level, LAB_TYPE)
		_prepare_action(game, 0, 1)
		var result: Dictionary = game.choose_action("choose_research", {"tool_id": RESEARCH_TOOLS[level]})
		_expect(bool(result.get("ok", false)), "level %d can select its matching research rank" % level)
		_expect_equal(int(game.state["board"][1].get("research_tool", -1)), level, "level %d stores matching research rank" % level)
		_expect_equal(int(game.state["board"][1].get("research_turns", -1)), 5, "level %d matching research starts at five turns" % level)


func _test_research_rejections() -> void:
	var game: Object = _new_research_game(9304)
	if game == null:
		return
	_set_facility_state(game, 1, 0, 1, LAB_TYPE)
	_prepare_action(game, 0, 1)
	for params in [
		{"tool_id": RESEARCH_TOOLS[2]},
		{"tool_id": ""},
	]:
		_expect_rejected_atomic(game, params, "invalid level-one research selection %s" % str(params))
	var cancelled_before: String = game.to_json()
	var cancelled: Dictionary = game.choose_action("choose_research", {"cancel": true})
	_expect(bool(cancelled.get("ok", false)), "cancelled research selection is accepted")
	_expect_equal(game.to_json(), cancelled_before, "cancelled research selection is atomic")

	_set_facility_state(game, 1, 1, 3, LAB_TYPE)
	_prepare_action(game, 0, 1)
	_expect_rejected_atomic(game, {"tool_id": RESEARCH_TOOLS[1]}, "non-owner research selection")

	_set_facility_state(game, 1, 0, 3, 1)
	_prepare_action(game, 0, 1)
	_expect_rejected_atomic(game, {"tool_id": RESEARCH_TOOLS[1]}, "non-lab research selection")

	_set_facility_state(game, 1, 0, 3, LAB_TYPE)
	_prepare_action(game, 0, 9)
	_expect_rejected_atomic(game, {"tool_id": RESEARCH_TOOLS[1]}, "road research selection")

	_prepare_action(game, 0, 1, "await_roll")
	_expect_rejected_atomic(game, {"tool_id": RESEARCH_TOOLS[1]}, "await-roll research selection")

	_prepare_action(game, 0, 1, "await_action")
	game.state["players"][0]["hospital_days"] = 1
	game._set_action_options(0)
	_expect_rejected_atomic(game, {"tool_id": RESEARCH_TOOLS[1]}, "detained research selection")

	_prepare_action(game, 0, 1, "await_route")
	game.state["route_options"] = [2]
	game.state["remaining_steps"] = 1
	game.state["pending_movement"] = {"player_id": 0, "current_node": 1, "previous_node": 0}
	_expect_rejected_atomic(game, {"tool_id": RESEARCH_TOOLS[1]}, "route-pending research selection")


func _test_incoming_owner_production() -> void:
	var game: Object = _new_research_game(9305)
	if game == null:
		return
	_set_facility_state(game, 1, 1, 1, LAB_TYPE)
	_prepare_action(game, 1, 1)
	var schedule: Dictionary = game.choose_action("choose_research", {"tool_id": RESEARCH_TOOLS[1]})
	_expect(bool(schedule.get("ok", false)), "owner schedules a five-turn research job")
	_expect_equal(int(game.state["board"][1].get("research_turns", -1)), 5, "scheduled job starts at five turns")
	var outgoing: Dictionary = _end_one_turn(game, 1)
	_expect(bool(outgoing.get("ok", false)), "owner outgoing turn completes")
	_expect_equal(int(game.state["board"][1].get("research_turns", -1)), 5, "outgoing owner turn does not tick production")

	for expected_turns in [4, 3, 2, 1, 0]:
		_advance_to_owner(game, 1)
		_expect_equal(int(game.state["board"][1].get("research_turns", -1)), expected_turns, "incoming owner admission decrements exactly once to %d" % expected_turns)
		if expected_turns > 0:
			var next_outgoing: Dictionary = _end_one_turn(game, 1)
			_expect(bool(next_outgoing.get("ok", false)), "owner continues after production admission %d" % expected_turns)

	var owner_tools: Dictionary = game.state["players"][1].get("tools", {})
	_expect_equal(int(owner_tools.get(RESEARCH_TOOLS[1], 0)), 2, "completed research grants one tool without changing the opening tool")
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(RESEARCH_TOOLS[1], -1)), 0, "research delivery does not debit shared tool supply")

	# A second alias of the same canonical facility must not produce a second
	# decrement or delivery during one owner admission.
	var alias_game: Object = _new_research_game(9306)
	if alias_game == null:
		return
	_set_facility_state(alias_game, 1, 1, 1, LAB_TYPE, 1, 1)
	alias_game.state["current_player"] = 0
	alias_game.state["phase"] = "await_roll"
	_advance_to_owner(alias_game, 1)
	_expect_equal(int(alias_game.state["board"][1].get("research_turns", -1)), 0, "multi-entry facility ticks once per canonical facility")
	_expect_equal(int(alias_game.state["board"][6].get("research_turns", -1)), 0, "multi-entry research countdown stays synchronized")
	_expect_equal(int(alias_game.state["players"][1]["tools"].get(RESEARCH_TOOLS[1], 0)), 2, "multi-entry facility delivers one tool")

	# A full player tool stack completes and clears the job without retrying or
	# creating an eleventh unit on a later owner admission.
	var full_game: Object = _new_research_game(9307)
	if full_game == null:
		return
	_set_facility_state(full_game, 1, 1, 1, LAB_TYPE, 1, 1)
	full_game.state["players"][1]["tools"][RESEARCH_TOOLS[1]] = 9
	full_game.state["current_player"] = 0
	full_game.state["phase"] = "await_roll"
	_advance_to_owner(full_game, 1)
	_expect_equal(int(full_game.state["board"][1].get("research_turns", -1)), 0, "full research tool stack clears the completed job")
	_expect_equal(int(full_game.state["players"][1]["tools"].get(RESEARCH_TOOLS[1], 0)), 9, "full research tool stack does not exceed nine")
	full_game.state["current_player"] = 0
	full_game.state["phase"] = "await_roll"
	_advance_to_owner(full_game, 1)
	_expect_equal(int(full_game.state["players"][1]["tools"].get(RESEARCH_TOOLS[1], 0)), 9, "full research tool stack is not retried")


func _test_nonlab_and_unowned_jobs() -> void:
	var game: Object = _new_research_game(9308)
	if game == null:
		return
	_set_facility_state(game, 1, 1, 3, 1, 1, 3)
	game.state["current_player"] = 0
	game.state["phase"] = "await_roll"
	_advance_to_owner(game, 1)
	_expect_equal(int(game.state["board"][1].get("research_tool", -1)), 1, "non-lab job retains its selected product")
	_expect_equal(int(game.state["board"][1].get("research_turns", -1)), 3, "non-lab facility pauses research countdown")

	_set_facility_state(game, 1, -1, 3, LAB_TYPE, 1, 3)
	game.state["current_player"] = 0
	game.state["phase"] = "await_roll"
	_advance_to_owner(game, 1)
	_expect_equal(int(game.state["board"][1].get("research_turns", -1)), 3, "unowned lab does not tick production")

	var before_invalid_rank: int = int(game.state["players"][1]["tools"].get(RESEARCH_TOOLS[2], 0))
	_set_facility_state(game, 1, 1, 1, LAB_TYPE, 2, 3)
	game.state["current_player"] = 0
	game.state["phase"] = "await_roll"
	_advance_to_owner(game, 1)
	_expect_equal(int(game.state["board"][1].get("research_turns", -1)), 0, "rank above current lab level cancels countdown")
	_expect_equal(int(game.state["players"][1]["tools"].get(RESEARCH_TOOLS[2], 0)), before_invalid_rank, "rank above current lab level produces no tool")


func _test_lab_worker_upgrade() -> void:
	var game: Object = _new_research_game(9325)
	if game == null:
		return
	_set_facility_state(game, 1, 0, 1, LAB_TYPE)
	_prepare_action(game, 0, 1, "await_roll")
	var tool_before: int = int(game.state["players"][0]["tools"].get(RESEARCH_TOOLS[1], 0))
	var result: Dictionary = game.choose_action("use_tool", {"tool_id": RESEARCH_TOOLS[1], "tile_id": 1})
	_expect(bool(result.get("ok", false)), "machine worker can upgrade a research facility")
	_expect_equal(int(game.state["board"][1].get("building_level", -1)), 2, "machine worker raises a research facility by one level")
	_expect_equal(int(game.state["board"][6].get("building_level", -1)), 2, "machine worker synchronizes the research facility alias")
	_expect_equal(int(game.state["players"][0]["tools"].get(RESEARCH_TOOLS[1], 0)), tool_before - 1, "machine worker is consumed by a research facility upgrade")


func _test_job_address_stability() -> void:
	var exchange: Object = _new_research_game(9309)
	if exchange == null:
		return
	_set_facility_state(exchange, 1, 1, 3, LAB_TYPE, 1, 3)
	_set_facility_state(exchange, 2, 0, 2, 1, 2, 4)
	_prepare_action(exchange, 0, 1)
	if _stage_card(exchange, 0, "換屋"):
		var result: Dictionary = exchange.choose_action("use_card", {"card_id": "換屋", "tile_id": 7})
		_expect(bool(result.get("ok", false)), "換屋 remains available for v12 facilities")
		_expect_equal(int(exchange.state["board"][1].get("facility_type", -1)), 1, "換屋 moves target facility type to source address")
		_expect_equal(int(exchange.state["board"][1].get("building_level", -1)), 2, "換屋 moves target facility level to source address")
		_expect_equal(int(exchange.state["board"][1].get("research_tool", -1)), 1, "換屋 keeps source research product at source address")
		_expect_equal(int(exchange.state["board"][1].get("research_turns", -1)), 3, "換屋 keeps source research countdown at source address")
		_expect_equal(int(exchange.state["board"][7].get("facility_type", -1)), LAB_TYPE, "換屋 moves source lab type to target address")
		_expect_equal(int(exchange.state["board"][7].get("building_level", -1)), 3, "換屋 moves source lab level to target address")
		_expect_equal(int(exchange.state["board"][7].get("research_tool", -1)), 2, "換屋 keeps target research product at target address")
		_expect_equal(int(exchange.state["board"][7].get("research_turns", -1)), 4, "換屋 keeps target research countdown at target address")

	var remodel: Object = _new_research_game(9310)
	if remodel == null:
		return
	_set_facility_state(remodel, 2, 1, 2, 1, 2, 4)
	_prepare_action(remodel, 0, 7)
	if _stage_card(remodel, 0, "改建"):
		var result: Dictionary = remodel.choose_action("use_card", {"card_id": "改建", "facility_type": LAB_TYPE})
		_expect(bool(result.get("ok", false)), "改建 can convert a facility into a research lab in v12")
		_expect_equal(int(remodel.state["board"][7].get("facility_type", -1)), LAB_TYPE, "改建 sets research facility type")
		_expect_equal(int(remodel.state["board"][7].get("building_level", -1)), 2, "改建 preserves legal research facility level")
		_expect_equal(int(remodel.state["board"][7].get("research_tool", -1)), 2, "改建 keeps the job product at the source address")
		_expect_equal(int(remodel.state["board"][7].get("research_turns", -1)), 4, "改建 keeps the countdown at the source address")

	var ownership: Object = _new_research_game(9311)
	if ownership == null:
		return
	_set_facility_state(ownership, 1, 1, 1, LAB_TYPE, 1, 1)
	_set_facility_state(ownership, 2, 0, 1, 1)
	_prepare_action(ownership, 0, 1)
	if _stage_card(ownership, 0, "換地"):
		var result: Dictionary = ownership.choose_action("use_card", {"card_id": "換地", "tile_id": 7})
		_expect(bool(result.get("ok", false)), "換地 transfers a research facility ownership")
		_expect_equal(int(ownership.state["board"][1].get("owner", -1)), 0, "換地 transfers source lab ownership")
		_expect_equal(int(ownership.state["board"][1].get("research_turns", -1)), 1, "換地 preserves source lab countdown")
		ownership.state["current_player"] = 3
		ownership.state["phase"] = "await_roll"
		_advance_to_owner(ownership, 0)
		_expect_equal(int(ownership.state["board"][1].get("research_turns", -1)), 0, "incoming new owner receives the transferred lab tick")
		_expect_equal(int(ownership.state["players"][0]["tools"].get(RESEARCH_TOOLS[1], 0)), 2, "incoming new owner receives the completed product")


func _test_bankruptcy_preserves_job() -> void:
	var game: Object = _new_research_game(9312)
	if game == null:
		return
	_set_facility_state(game, 1, 0, 3, LAB_TYPE, 1, 3)
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["players"][0]["cash"] = 0
	game.state["players"][0]["deposit"] = 0
	game.state["bank"]["deposits"] = 0
	var before: Dictionary = _research_snapshot(game, 1)
	game._declare_bankruptcy(0, -1, 1, "research_test")
	_expect(bool(game.state["players"][0].get("bankrupt", false)), "research owner bankruptcy is recorded")
	for tile_id in _facility_indices(game, 1):
		var tile: Dictionary = game.state["board"][int(tile_id)]
		_expect_equal(int(tile.get("owner", -1)), -1, "bankruptcy clears research facility owner")
		_expect_equal(int(tile.get("building_level", -1)), 0, "bankruptcy clears research facility level")
		_expect_equal(int(tile.get("research_tool", -1)), int(before["aliases"][0].get("research_tool", -2)), "bankruptcy preserves research product at source address")
		_expect_equal(int(tile.get("research_turns", -1)), int(before["aliases"][0].get("research_turns", -2)), "bankruptcy preserves research countdown at source address")
