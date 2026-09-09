extends SceneTree

## Issue #81 TEST-ONLY seed for 時光機 (ID10) and 傳送機 (ID11).
##
## The fixture is a synthetic, asset-free v13 graph.  Positive public entries
## deliberately remain qualified RED until the two tools are implemented.  The
## strict target, save, RNG, and inventory assertions keep an implementation
## from hiding behind a top-level capability gate.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/time_transport_fixture.gd")

const V13 := 13
const TIME_MACHINE := "時光機"
const TRANSPORTER := "傳送機"
const REMOTE_DICE := "遙控骰子"
const CENTRE := 1
const PROPERTY_SOURCE := 2
const PROPERTY_DESTINATION := 3
const PRISON := 4
const FAR_NODE := 5
const ROAD := 9

var checks: int = 0
var failures: int = 0
var qualified_red: int = 0
var reported_red: Dictionary = {}


func _initialize() -> void:
	_test_v13_fixture_and_catalogue()
	_test_query_boundaries_are_read_only()
	_test_time_machine_anchor_lifetime_and_restore()
	_test_time_machine_ordering_and_missing_tools()
	_test_transport_property_and_auction_boundary()
	_test_transport_facility_and_research_location()
	_test_transport_players_gods_and_no_landing()
	_test_transport_cancel_invalid_and_type_atomicity()
	_test_ai_transport_and_time_determinism()
	print("Time/transport flow checks: %d, failures: %d, qualified_red: %d" % [checks, failures, qualified_red])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_game(seed_value: int, player_count: int = 2) -> Object:
	var game: Object = Fixture.new_game(seed_value, player_count)
	_expect(game != null, "v13 time/transport fixture starts")
	if game == null:
		return null
	_expect_equal(int(game.state.get("version", -1)), V13, "time/transport fixture remains v13")
	_expect(bool(game.state.get("original_building_cards", false)), "fixture retains the v13 marker")
	_expect(bool(game.state.get("original_research", false)), "fixture retains the research marker")
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), "fresh v13 fixture validates: %s" % str(validation.get("errors", [])))
	return game


func _valid_before(game: Object, label: String) -> bool:
	var validation: Dictionary = Game.validate_save(game.to_dict())
	var ok: bool = bool(validation.get("ok", false))
	_expect(ok, label + " has a valid save before the public entry: " + str(validation.get("errors", [])))
	return ok


func _stage_tool(game: Object, player_id: int, tool_id: String, label: String = "") -> bool:
	var supply_before: Dictionary = game.state["inventory_supply"]["tools"].duplicate(true)
	var result: Dictionary = Inventory.grant_tool(
		game.state["inventory_supply"],
		game.state["players"][player_id]["tools"],
		tool_id,
		1,
	)
	var name: String = label if not label.is_empty() else tool_id
	_expect(bool(result.get("ok", false)), name + " stages through inventory rules")
	if bool(result.get("ok", false)) and tool_id in [TIME_MACHINE, TRANSPORTER]:
		_expect_equal(game.state["inventory_supply"]["tools"], supply_before, name + " keeps research supply unchanged")
	return bool(result.get("ok", false))


func _public_use(game: Object, params: Dictionary, label: String) -> Dictionary:
	_valid_before(game, label)
	_expect(game.state.get("action_options", []).has("use_tool"), label + " exposes the public use_tool action")
	return game.choose_action("use_tool", params)


func _mark_qualified_red(result: Dictionary, label: String) -> void:
	var message: String = str(result.get("message", ""))
	if not bool(result.get("ok", false)) and message.contains("尚未還原"):
		qualified_red += 1
		if not reported_red.has(label):
			reported_red[label] = true
			print("QUALIFIED RED: %s -> %s" % [label, message])


func _expect_success(result: Dictionary, label: String) -> bool:
	_mark_qualified_red(result, label)
	var ok: bool = bool(result.get("ok", false))
	_expect(ok, label + " succeeds: " + str(result.get("message", "")))
	return ok


func _assert_tool_event(game: Object, tool_id: String, label: String) -> Dictionary:
	var event: Variant = game.state.get("last_event", {})
	_expect(typeof(event) == TYPE_DICTIONARY, label + " records a dictionary event")
	if typeof(event) != TYPE_DICTIONARY:
		return {}
	_expect_equal(str(event.get("type", "")), "tool_used", label + " records tool_used")
	_expect_equal(str(event.get("tool_id", "")), tool_id, label + " event identifies the tool")
	_expect_equal(int(event.get("player_id", -1)), int(game.state.get("current_player", -1)), label + " event identifies the actor")
	return event


func _prepare_action(game: Object, player_id: int, position: int = -1, phase: String = "await_roll") -> void:
	Fixture.prepare_action(game, player_id, position, phase)


func _end_non_landing_turn(game: Object, player_id: int, label: String) -> Dictionary:
	game.state["current_player"] = player_id
	game.state["phase"] = "await_action"
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["property_action_used"] = false
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game._set_action_options(player_id)
	var result: Dictionary = game.end_turn()
	_expect(bool(result.get("ok", false)), label + " ends through public end_turn")
	return result


func _cycle_to_human(game: Object, label: String) -> bool:
	var first: Dictionary = game.end_turn()
	_expect(bool(first.get("ok", false)), label + " completes the landed human turn")
	if not bool(first.get("ok", false)):
		return false
	_expect_equal(int(game.state.get("current_player", -1)), 1, label + " admits the second player")
	_end_non_landing_turn(game, 1, label + " advances the second player")
	_expect_equal(int(game.state.get("current_player", -1)), 0, label + " returns to human await_roll")
	_expect_equal(str(game.state.get("phase", "")), "await_roll", label + " returns to await_roll")
	return true


func _establish_human_anchor(game: Object, label: String, destination: int = PROPERTY_SOURCE, use_remote_dice: bool = true) -> bool:
	# This is the only anchor setup path: an actual human roll and route choice.
	# No private anchor setter or serialized field is introduced by the fixture.
	_prepare_action(game, 0, CENTRE, "await_roll")
	if use_remote_dice:
		# A public remote-dice value of one makes the actual graph traversal a single
		# edge while retaining the source ordering boundary around remote use.
		var remote_result: Dictionary = game.choose_action("use_tool", {"tool_id": REMOTE_DICE, "value": 1})
		_expect(bool(remote_result.get("ok", false)), label + " stages a public one-step remote roll")
		if not bool(remote_result.get("ok", false)):
			return false
	if not _valid_before(game, label + " pre-movement"):
		return false
	var roll_result: Dictionary = game.roll(1)
	_expect(bool(roll_result.get("ok", false)), label + " human roll succeeds")
	if not bool(roll_result.get("ok", false)):
		return false
	_expect_equal(str(game.state.get("phase", "")), "await_route", label + " exposes a route choice after the graph roll")
	_expect(game.state.get("route_options", []).has(destination), label + " route contains the selected destination")
	var route_result: Dictionary = game.choose_route(destination)
	_expect(bool(route_result.get("ok", false)), label + " human chooses a real route")
	_expect_equal(int(game.state["players"][0].get("position", -1)), destination, label + " reaches the selected node")
	var movement_event: Dictionary = _latest_event(game, "move")
	if movement_event.is_empty():
		# A one-edge public choice records route_chosen; automatic edges record move.
		movement_event = _latest_event(game, "route_chosen")
	_expect(not movement_event.is_empty(), label + " records an actual movement event")
	_expect_equal(str(game.state.get("phase", "")), "await_action", label + " resolves the real landing")
	return _cycle_to_human(game, label)


func _latest_event(game: Object, event_type: String) -> Dictionary:
	var events: Variant = game.state.get("event_log", [])
	if typeof(events) != TYPE_ARRAY:
		return {}
	for index in range(events.size() - 1, -1, -1):
		if typeof(events[index]) == TYPE_DICTIONARY and str(events[index].get("type", "")) == event_type:
			return events[index]
	return {}


func _event_types_since(game: Object, start_index: int) -> Array:
	var result: Array = []
	var events: Variant = game.state.get("event_log", [])
	if typeof(events) != TYPE_ARRAY:
		return result
	for index in range(max(0, start_index), events.size()):
		if typeof(events[index]) == TYPE_DICTIONARY:
			result.append(str(events[index].get("type", "")))
	return result


func _assert_cancelled_atomic(game: Object, tool_id: String, params: Dictionary, label: String) -> void:
	var before_json: String = game.to_json()
	var before_rng: String = str(game.to_dict().get("rng_state_text", ""))
	var before_event: Dictionary = game.state.get("last_event", {}).duplicate(true)
	var before_supply: Dictionary = game.state["inventory_supply"]["tools"].duplicate(true)
	var before_held: int = int(game.state["players"][0]["tools"].get(tool_id, 0))
	var result: Dictionary = _public_use(game, params, label)
	_mark_qualified_red(result, label)
	_expect(bool(result.get("ok", false)), label + " is accepted")
	_expect_equal(game.to_json(), before_json, label + " is byte-for-byte atomic")
	_expect_equal(str(game.to_dict().get("rng_state_text", "")), before_rng, label + " keeps RNG continuation")
	_expect_equal(game.state.get("last_event", {}), before_event, label + " appends no event")
	_expect_equal(game.state["inventory_supply"]["tools"], before_supply, label + " keeps all supply")
	_expect_equal(int(game.state["players"][0]["tools"].get(tool_id, 0)), before_held, label + " keeps the held tool")


func _assert_rejected_atomic(game: Object, tool_id: String, params: Dictionary, label: String) -> void:
	var before_json: String = game.to_json()
	var before_rng: String = str(game.to_dict().get("rng_state_text", ""))
	var before_event: Dictionary = game.state.get("last_event", {}).duplicate(true)
	var before_supply: Dictionary = game.state["inventory_supply"]["tools"].duplicate(true)
	var before_held: int = int(game.state["players"][0]["tools"].get(tool_id, 0))
	var result: Dictionary = _public_use(game, params, label)
	_mark_qualified_red(result, label)
	_expect(not bool(result.get("ok", false)), label + " is rejected")
	_expect(not str(result.get("message", "")).contains("尚未還原"), label + " reaches strict validation")
	_expect_equal(game.to_json(), before_json, label + " is byte-for-byte atomic")
	_expect_equal(str(game.to_dict().get("rng_state_text", "")), before_rng, label + " keeps RNG continuation")
	_expect_equal(game.state.get("last_event", {}), before_event, label + " appends no event")
	_expect_equal(game.state["inventory_supply"]["tools"], before_supply, label + " keeps all supply")
	_expect_equal(int(game.state["players"][0]["tools"].get(tool_id, 0)), before_held, label + " keeps the held tool")


func _static_property_snapshot(tile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["index", "source_node_id", "x", "y", "adjacent", "type_and_idx", "visual_index", "event_code", "source_status_bits", "source_object_id", "kind", "name", "cost", "upgrade_cost", "base_rent", "land_price", "house_price", "rent_by_level", "group", "tax_amount"]:
		result[key] = tile.get(key, null)
	return result


func _static_facility_snapshot(tile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["index", "source_node_id", "x", "y", "adjacent", "type_and_idx", "visual_index", "event_code", "source_status_bits", "source_object_id", "kind", "name", "cost", "land_price", "upgrade_cost", "base_rent", "group", "tax_amount", "fee_by_level", "facility_node_index"]:
		result[key] = tile.get(key, null)
	return result


func _assert_static_fields(actual: Dictionary, snapshot: Dictionary, label: String) -> void:
	for key in snapshot.keys():
		_expect_equal(actual.get(key, null), snapshot[key], label + " preserves " + str(key))


func _transport_result(game: Object, params: Dictionary, label: String) -> Dictionary:
	return _public_use(game, params, label)


func _query_array(game: Object, method_name: String, args: Array, label: String) -> Array:
	if not game.has_method(method_name):
		qualified_red += 1
		print("QUALIFIED RED: %s query is not available yet" % label)
		_expect(false, label + " query exists")
		return []
	var value: Variant = game.callv(method_name, args)
	_expect(typeof(value) == TYPE_ARRAY, label + " query returns an array")
	return value if typeof(value) == TYPE_ARRAY else []


func _status_query(game: Object, label: String) -> Dictionary:
	if not game.has_method("time_machine_status"):
		qualified_red += 1
		print("QUALIFIED RED: %s status query is not available yet" % label)
		_expect(false, label + " status query exists")
		return {}
	var value: Variant = game.call("time_machine_status")
	_expect(typeof(value) == TYPE_DICTIONARY, label + " status returns a dictionary")
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _test_v13_fixture_and_catalogue() -> void:
	var definition: Dictionary = Fixture.definition()
	_expect_equal(int(definition.get("board", []).size()), 10, "fixture keeps the existing ten-node graph")
	_expect(bool(definition.get("supports_original_research", false)), "fixture advertises research capability")
	_expect(bool(definition.get("supports_original_building_cards", false)), "fixture advertises v13 capability")
	var game: Object = _new_game(8201, 2)
	if game == null:
		return
	var supply: Dictionary = game.state["inventory_supply"]["tools"]
	_expect_equal(int(supply.get(TIME_MACHINE, -1)), 0, "time machine has no invented finite supply")
	_expect_equal(int(supply.get(TRANSPORTER, -1)), 0, "transporter has no invented finite supply")
	for player_value in game.state["players"]:
		var player: Dictionary = player_value
		_expect_equal(int(player.get("tools", {}).get(TIME_MACHINE, 0)), 0, "time machine is not pre-granted")
		_expect_equal(int(player.get("tools", {}).get(TRANSPORTER, 0)), 0, "transporter is not pre-granted")
	_expect(game.state.get("god_objects", []).is_empty(), "fixture clears spawned gods deterministically")
	_expect(game.state.get("action_options", []).has("use_tool"), "v13 fixture exposes use_tool without a top capability gate")


func _test_query_boundaries_are_read_only() -> void:
	var game: Object = _new_game(8202, 3)
	if game == null:
		return
	Fixture.set_property(game, PROPERTY_SOURCE, 0, 3, false)
	Fixture.set_property(game, PROPERTY_DESTINATION, -1, 0, false)
	Fixture.set_facility(game, 1, 0, 2, 4, 0x50, 2, 3)
	Fixture.set_facility(game, 2, -1, 0, 0, 0, 1, 4)
	game.state["players"][1]["position"] = PROPERTY_SOURCE
	game.state["players"][2]["hospital_days"] = 1
	game.state["players"][1]["god_id"] = 1
	game.state["god_objects"] = [
		{"id": 1, "node": PROPERTY_SOURCE, "owner": 1, "days": 7},
		{"id": 3, "node": PROPERTY_DESTINATION, "owner": -1, "days": 0},
	]
	var before: String = game.to_json()
	var property_targets: Array = _query_array(game, "transport_targets", ["property"], "property transport targets")
	if game.has_method("transport_targets"):
		_expect(property_targets.has(PROPERTY_SOURCE), "property query includes the built source")
	var property_destinations: Array = _query_array(game, "transport_destinations", ["property", PROPERTY_SOURCE], "property transport destinations")
	if game.has_method("transport_destinations"):
		_expect_equal(property_destinations, [PROPERTY_DESTINATION], "property query exposes only the empty destination")
	var facility_targets: Array = _query_array(game, "transport_targets", ["facility"], "facility transport targets")
	if game.has_method("transport_targets"):
		_expect(facility_targets.has(CENTRE), "facility query uses the canonical source node")
	var facility_destinations: Array = _query_array(game, "transport_destinations", ["facility", CENTRE], "facility transport destinations")
	if game.has_method("transport_destinations"):
		_expect_equal(facility_destinations, [7], "facility query exposes the empty canonical destination")
	var player_targets: Array = _query_array(game, "transport_targets", ["player"], "player transport targets")
	if game.has_method("transport_targets"):
		_expect(player_targets.has(1), "player query includes a living non-detained player")
		_expect(not player_targets.has(2), "player query excludes the detained player")
	var god_targets: Array = _query_array(game, "transport_targets", ["god"], "god transport targets")
	if game.has_method("transport_targets"):
		_expect(god_targets.has(1) and god_targets.has(3), "god query includes attached and unbound god IDs")
	var status: Dictionary = _status_query(game, "time status before anchor")
	if game.has_method("time_machine_status"):
		_expect_equal(bool(status.get("available", true)), false, "time status is unavailable before an anchor")
		_expect(not str(status.get("message", "")).is_empty(), "unavailable time status explains the missing anchor")
	_expect_equal(game.to_json(), before, "read-only target and status queries do not mutate state")


func _test_time_machine_anchor_lifetime_and_restore() -> void:
	var game: Object = _new_game(8210, 2)
	if game == null:
		return
	_stage_tool(game, 0, TIME_MACHINE)
	_stage_tool(game, 0, TRANSPORTER)
	if not _establish_human_anchor(game, "time anchor before self transport"):
		return
	var pre_transport_position: int = int(game.state["players"][0].get("position", -1))
	var current_rng: String = str(game.to_dict().get("rng_state_text", ""))
	var transport: Dictionary = _transport_result(game, {
		"tool_id": TRANSPORTER,
		"target_kind": "player",
		"target_id": 0,
		"destination_id": ROAD,
	}, "self transport captures a replacement anchor")
	var moved: bool = _expect_success(transport, "self transport")
	if moved:
		_expect_equal(int(game.state["players"][0].get("position", -1)), ROAD, "self transport moves the actor to the road")
		_expect_equal(str(game.state.get("phase", "")), "await_roll", "self transport keeps the current await_roll phase")
		_expect_equal(int(game.state["players"][0].get("hospital_days", -1)), 0, "self transport does not resolve a landing")
	var time_before: String = game.to_json()
	var restored: Dictionary = _public_use(game, {"tool_id": TIME_MACHINE}, "time restore after self transport")
	var restored_ok: bool = _expect_success(restored, "time restore after self transport")
	if restored_ok:
		_expect_equal(int(game.state["players"][0].get("position", -1)), pre_transport_position, "time restore returns to the pre-self-transport anchor")
		_expect_equal(int(game.state["players"][0]["tools"].get(TRANSPORTER, 0)), 1, "time restore recovers the pre-transport research tool")
		_expect_equal(int(game.state["players"][0]["tools"].get(TIME_MACHINE, 0)), 0, "time restore consumes exactly one time machine")
		_expect_equal(str(game.to_dict().get("rng_state_text", "")), current_rng, "time restore keeps the current RNG continuation")
		_expect_equal(str(game.state.get("phase", "")), "await_roll", "time restore returns to the anchor phase")
	var repeat_before: String = game.to_json()
	var repeated: Dictionary = _public_use(game, {"tool_id": TIME_MACHINE}, "repeated time restore after debit")
	_mark_qualified_red(repeated, "repeated time restore after debit")
	_expect(not bool(repeated.get("ok", false)), "repeated time restore is exhausted")
	_expect(not str(repeated.get("message", "")).contains("尚未還原"), "repeated time restore reaches the missing-tool guard")
	_expect_equal(game.to_json(), repeat_before if restored_ok else time_before, "repeated time restore is atomic")

	var loaded_game: Object = _new_game(8211, 2)
	if loaded_game == null:
		return
	_stage_tool(loaded_game, 0, TIME_MACHINE)
	if not _establish_human_anchor(loaded_game, "volatile anchor save"):
		return
	var encoded: String = loaded_game.to_json()
	var parsed: Variant = JSON.parse_string(encoded)
	_expect(parsed is Dictionary, "volatile anchor save remains JSON")
	if not parsed is Dictionary:
		return
	var reloaded: Object = Game.from_dict(parsed)
	_expect(reloaded != null, "JSON reload succeeds after an anchored movement")
	if reloaded == null:
		return
	_expect_equal(int(reloaded.state["players"][0]["tools"].get(TIME_MACHINE, 0)), 1, "JSON reload keeps the held time machine")
	var status: Dictionary = _status_query(reloaded, "time status after JSON reload")
	if reloaded.has_method("time_machine_status"):
		_expect_equal(bool(status.get("available", true)), false, "JSON reload loses the volatile anchor")
	var before_use: String = reloaded.to_json()
	var lost_anchor: Dictionary = _public_use(reloaded, {"tool_id": TIME_MACHINE}, "time restore after JSON reload")
	_mark_qualified_red(lost_anchor, "time restore after JSON reload")
	_expect(not bool(lost_anchor.get("ok", false)), "JSON reload cannot restore a private anchor")
	_expect(not str(lost_anchor.get("message", "")).contains("尚未還原"), "JSON reload reaches the no-anchor guard")
	_expect_equal(reloaded.to_json(), before_use, "no-anchor restore after JSON reload is atomic")


func _test_time_machine_ordering_and_missing_tools() -> void:
	# A tool acquired after capture cannot be injected into the restored past.
	var late_tool: Object = _new_game(8220, 2)
	if late_tool == null:
		return
	if not _establish_human_anchor(late_tool, "late time tool anchor"):
		return
	_stage_tool(late_tool, 0, TIME_MACHINE, "time tool acquired after anchor")
	var missing_in_anchor: Dictionary = _public_use(late_tool, {"tool_id": TIME_MACHINE}, "time restore with missing anchor tool")
	_mark_qualified_red(missing_in_anchor, "time restore with missing anchor tool")
	_expect(not bool(missing_in_anchor.get("ok", false)), "time restore rejects a tool absent from the anchor")
	_expect(not str(missing_in_anchor.get("message", "")).contains("尚未還原"), "missing anchor tool reaches strict validation")

	# Capture ordering retains the pending remote request and turtle state while
	# the roll consumes/clears them after the anchor is taken.
	var remote_game: Object = _new_game(8221, 2)
	if remote_game == null:
		return
	_stage_tool(remote_game, 0, TIME_MACHINE)
	_prepare_action(remote_game, 0, CENTRE)
	var remote_use: Dictionary = _public_use(remote_game, {"tool_id": REMOTE_DICE, "value": 4}, "remote dice before anchored movement")
	_expect(bool(remote_use.get("ok", false)), "remote dice schedules through the existing public entry")
	if bool(remote_use.get("ok", false)):
		var pending_before_roll: Dictionary = remote_game.state.get("pending_remote_dice", {}).duplicate(true)
		_expect_equal(pending_before_roll.get("value", -1), 4, "remote request is pending before movement")
		var roll_result: Dictionary = remote_game.roll(1)
		_expect(bool(roll_result.get("ok", false)), "remote roll succeeds after the pre-movement checks")
		var route_choices: int = 0
		while bool(roll_result.get("ok", false)) and remote_game.state.get("phase", "") == "await_route" and route_choices < 8:
			var options: Array = remote_game.state.get("route_options", [])
			_expect(not options.is_empty(), "remote movement exposes a legal route choice")
			if options.is_empty():
				break
			var route: int = PROPERTY_SOURCE if options.has(PROPERTY_SOURCE) else int(options[0])
			var route_result: Dictionary = remote_game.choose_route(route)
			_expect(bool(route_result.get("ok", false)), "remote movement accepts each selected route")
			if not bool(route_result.get("ok", false)):
				break
			route_choices += 1
		_expect_equal(str(remote_game.state.get("phase", "")), "await_action", "remote movement resolves the full rolled path")
		if remote_game.state.get("phase", "") == "await_action":
			_cycle_to_human(remote_game, "remote anchored movement")
		var remote_rng: String = str(remote_game.to_dict().get("rng_state_text", ""))
		var remote_restore: Dictionary = _public_use(remote_game, {"tool_id": TIME_MACHINE}, "remote ordered time restore")
		if _expect_success(remote_restore, "remote ordered time restore"):
			_expect_equal(remote_game.state.get("pending_remote_dice", {}), pending_before_roll, "time anchor retains pending remote consumption boundary")
			_expect_equal(str(remote_game.to_dict().get("rng_state_text", "")), remote_rng, "ordered restore keeps current RNG")

	var turtle_game: Object = _new_game(8222, 2)
	if turtle_game == null:
		return
	_stage_tool(turtle_game, 0, TIME_MACHINE)
	turtle_game.state["players"][0]["turtle_days"] = 1
	if _establish_human_anchor(turtle_game, "turtle ordered movement", PROPERTY_SOURCE, false):
		var turtle_restore: Dictionary = _public_use(turtle_game, {"tool_id": TIME_MACHINE}, "turtle ordered time restore")
		if _expect_success(turtle_restore, "turtle ordered time restore"):
			_expect_equal(int(turtle_game.state["players"][0].get("turtle_days", -1)), 1, "time anchor is captured before turtle decrement")


func _test_transport_property_and_auction_boundary() -> void:
	var game: Object = _new_game(8230, 2)
	if game == null:
		return
	Fixture.set_property(game, PROPERTY_SOURCE, 0, 3, false)
	Fixture.set_property(game, PROPERTY_DESTINATION, -1, 0, false)
	var source_before: Dictionary = game.state["board"][PROPERTY_SOURCE].duplicate(true)
	var destination_before: Dictionary = game.state["board"][PROPERTY_DESTINATION].duplicate(true)
	_stage_tool(game, 0, TRANSPORTER)
	_prepare_action(game, 0, CENTRE)
	var result: Dictionary = _transport_result(game, {
		"tool_id": TRANSPORTER,
		"target_kind": "property",
		"target_id": PROPERTY_SOURCE,
		"destination_id": PROPERTY_DESTINATION,
	}, "property transport")
	if _expect_success(result, "property transport"):
		var source: Dictionary = game.state["board"][PROPERTY_SOURCE]
		var destination: Dictionary = game.state["board"][PROPERTY_DESTINATION]
		_expect_equal(int(source.get("owner", -1)), -1, "property transport clears source ownership")
		_expect_equal(int(source.get("building_level", -1)), 0, "property transport clears source level")
		_expect_equal(bool(source.get("is_chain_store", true)), false, "property transport clears source chain flag")
		_expect_equal(int(destination.get("owner", -1)), 0, "property transport moves ownership to destination")
		_expect_equal(int(destination.get("building_level", -1)), 3, "property transport moves the source level")
		_expect_equal(bool(destination.get("is_chain_store", true)), false, "property transport moves the source chain flag")
		_expect_equal(int(destination.get("rent", -1)), int(destination.get("rent_by_level", [])[3]), "property transport recomputes destination rent")
		_expect(not game.state["players"][0].get("properties", []).has(PROPERTY_SOURCE), "property references remove the source")
		_expect(game.state["players"][0].get("properties", []).has(PROPERTY_DESTINATION), "property references add the destination")
		_expect_equal(int(game.state["players"][0].get("property_values", -1)), int(destination.get("cost", 0)) + int(destination.get("upgrade_cost", 0)) * 3, "property value uses destination pricing")
		_assert_static_fields(source, _static_property_snapshot(source_before), "property source")
		_assert_static_fields(destination, _static_property_snapshot(destination_before), "property destination")
		var event: Dictionary = _assert_tool_event(game, TRANSPORTER, "property transport")
		_expect_equal(str(event.get("target_kind", "")), "property", "property event identifies target kind")
		_expect_equal(int(event.get("target_id", -1)), PROPERTY_SOURCE, "property event identifies source")
		_expect_equal(int(event.get("destination_id", -1)), PROPERTY_DESTINATION, "property event identifies destination")
		_expect_equal(str(game.state.get("phase", "")), "await_roll", "property transport does not enter a landing phase")
		_expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "property transport leaves a valid save")

	var auction: Object = _new_game(8231, 2)
	if auction == null:
		return
	Fixture.set_property(auction, PROPERTY_SOURCE, 0, 2, false)
	Fixture.set_property(auction, PROPERTY_DESTINATION, -1, 1, false)
	_stage_tool(auction, 0, TRANSPORTER)
	_prepare_action(auction, 0, CENTRE)
	_assert_rejected_atomic(auction, TRANSPORTER, {
		"tool_id": TRANSPORTER,
		"target_kind": "property",
		"target_id": PROPERTY_SOURCE,
		"destination_id": PROPERTY_DESTINATION,
	}, "auction-unowned-built property destination")


func _test_transport_facility_and_research_location() -> void:
	var game: Object = _new_game(8240, 2)
	if game == null:
		return
	var source_aliases: Array = Fixture.set_facility(game, 1, 0, 2, 4, 0x50, 2, 3)
	var destination_aliases: Array = Fixture.set_facility(game, 2, -1, 0, 0, 0, 1, 4)
	_expect(not source_aliases.is_empty(), "facility transport has source entrances")
	_expect(not destination_aliases.is_empty(), "facility transport has destination entrances")
	var source_before: Array = []
	var destination_before: Array = []
	for index_value in source_aliases:
		source_before.append(game.state["board"][int(index_value)].duplicate(true))
	for index_value in destination_aliases:
		destination_before.append(game.state["board"][int(index_value)].duplicate(true))
	_stage_tool(game, 0, TRANSPORTER)
	_prepare_action(game, 0, CENTRE)
	var result: Dictionary = _transport_result(game, {
		"tool_id": TRANSPORTER,
		"target_kind": "facility",
		"target_id": CENTRE,
		"destination_id": 7,
	}, "facility transport")
	if _expect_success(result, "facility transport"):
		for offset in range(source_aliases.size()):
			var source: Dictionary = game.state["board"][int(source_aliases[offset])]
			_assert_static_fields(source, _static_facility_snapshot(source_before[offset]), "facility source entrance")
			_expect_equal(int(source.get("owner", -1)), -1, "facility source entrance clears ownership")
			_expect_equal(int(source.get("building_level", -1)), 0, "facility source entrance clears level")
			_expect_equal(int(source.get("facility_type", -1)), 0, "facility source entrance clears type")
			_expect_equal(int(source.get("facility_state", -1)), 0x50, "facility source keeps its original status")
			_expect_equal(int(source.get("research_tool", -1)), 2, "facility source keeps research rank at its original location")
			_expect_equal(int(source.get("research_turns", -1)), 3, "facility source keeps research countdown at its original location")
		for offset in range(destination_aliases.size()):
			var destination: Dictionary = game.state["board"][int(destination_aliases[offset])]
			_assert_static_fields(destination, _static_facility_snapshot(destination_before[offset]), "facility destination entrance")
			_expect_equal(int(destination.get("owner", -1)), 0, "facility destination entrance receives ownership")
			_expect_equal(int(destination.get("building_level", -1)), 2, "facility destination entrance receives level")
			_expect_equal(int(destination.get("facility_type", -1)), 4, "facility destination entrance receives type")
			_expect_equal(int(destination.get("facility_state", -1)), 0, "facility destination keeps its original status")
			_expect_equal(int(destination.get("research_tool", -1)), 1, "facility destination keeps its location-bound research rank")
			_expect_equal(int(destination.get("research_turns", -1)), 4, "facility destination keeps its location-bound research countdown")
		_expect_equal(game.state["players"][0].get("properties", []).has(CENTRE), false, "facility references remove the source canonical node")
		_expect_equal(game.state["players"][0].get("properties", []).has(7), true, "facility references add the destination canonical node")
		_expect_equal(str(game.state.get("phase", "")), "await_roll", "facility transport does not land")
		_expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "facility transport leaves a valid save")

	var invalid: Object = _new_game(8241, 2)
	if invalid == null:
		return
	Fixture.set_facility(invalid, 1, 0, 2, 4)
	Fixture.set_facility(invalid, 2, 1, 1, 2)
	_stage_tool(invalid, 0, TRANSPORTER)
	_prepare_action(invalid, 0, CENTRE)
	_assert_rejected_atomic(invalid, TRANSPORTER, {
		"tool_id": TRANSPORTER,
		"target_kind": "facility",
		"target_id": CENTRE,
		"destination_id": 7,
	}, "occupied facility destination")


func _test_transport_players_gods_and_no_landing() -> void:
	var player_game: Object = _new_game(8250, 3)
	if player_game == null:
		return
	player_game.state["players"][1]["position"] = PROPERTY_SOURCE
	player_game.state["players"][1]["previous_position"] = PRISON
	player_game.state["players"][2]["position"] = FAR_NODE
	var player_before: Dictionary = player_game.state["players"][1].duplicate(true)
	_stage_tool(player_game, 0, TRANSPORTER)
	_prepare_action(player_game, 0, CENTRE)
	var event_start: int = player_game.state.get("event_log", []).size()
	var player_result: Dictionary = _transport_result(player_game, {
		"tool_id": TRANSPORTER,
		"target_kind": "player",
		"target_id": 1,
		"destination_id": ROAD,
	}, "player transport")
	if _expect_success(player_result, "player transport"):
		var target: Dictionary = player_game.state["players"][1]
		_expect_equal(int(target.get("position", -1)), ROAD, "player transport moves the selected player")
		_expect_equal(int(target.get("previous_position", -1)), 8, "player transport uses the available behind-direction fallback")
		for key in ["cash", "deposit", "hospital_days", "prison_days", "skip_turns", "turtle_days", "stay_next", "turns_taken"]:
			_expect_equal(target.get(key, null), player_before.get(key, null), "player transport preserves " + key)
		_expect_equal(int(player_game.state.get("current_player", -1)), 0, "player transport preserves the acting player")
		_expect_equal(str(player_game.state.get("phase", "")), "await_roll", "player transport preserves the phase")
		var new_types: Array = _event_types_since(player_game, event_start)
		for forbidden in ["property_fee", "facility_service", "hospital_admitted", "prison_admitted", "research_progress", "research_produced", "bomb_exploded"]:
			_expect(not new_types.has(forbidden), "player transport does not resolve " + forbidden)
		var event: Dictionary = _assert_tool_event(player_game, TRANSPORTER, "player transport")
		_expect_equal(str(event.get("target_kind", "")), "player", "player event identifies target kind")
		_expect_equal(int(event.get("target_id", -1)), 1, "player event identifies target")
		_expect_equal(int(event.get("destination_id", -1)), ROAD, "player event identifies destination")
		_expect(bool(Game.validate_save(player_game.to_dict()).get("ok", false)), "player transport leaves a valid save")

	var attached: Object = _new_game(8251, 3)
	if attached == null:
		return
	attached.state["players"][1]["position"] = PROPERTY_SOURCE
	attached.state["players"][1]["previous_position"] = PRISON
	attached.state["players"][1]["god_id"] = 1
	attached.state["god_objects"] = [{"id": 1, "node": PROPERTY_SOURCE, "owner": 1, "days": 7}]
	_stage_tool(attached, 0, TRANSPORTER)
	_prepare_action(attached, 0, CENTRE)
	var attached_result: Dictionary = _transport_result(attached, {
		"tool_id": TRANSPORTER,
		"target_kind": "god",
		"target_id": 1,
		"destination_id": ROAD,
	}, "attached god transport")
	if _expect_success(attached_result, "attached god transport"):
		_expect_equal(int(attached.state["players"][1].get("position", -1)), ROAD, "attached god target resolves through its player")
		_expect_equal(int(attached.state["god_objects"][0].get("node", -1)), ROAD, "attached god follows its player")

	var unbound: Object = _new_game(8252, 3)
	if unbound == null:
		return
	unbound.state["god_objects"] = [{"id": 3, "node": PROPERTY_SOURCE, "owner": -1, "days": 0}]
	_stage_tool(unbound, 0, TRANSPORTER)
	_prepare_action(unbound, 0, CENTRE)
	var unbound_result: Dictionary = _transport_result(unbound, {
		"tool_id": TRANSPORTER,
		"target_kind": "god",
		"target_id": 3,
		"destination_id": ROAD,
	}, "unbound god transport")
	if _expect_success(unbound_result, "unbound god transport"):
		_expect_equal(int(unbound.state["god_objects"][0].get("node", -1)), ROAD, "unbound god transport moves only the god node")
		_expect_equal(int(unbound.state["players"][0].get("position", -1)), CENTRE, "unbound god transport leaves the actor position unchanged")
		_expect(bool(Game.validate_save(unbound.to_dict()).get("ok", false)), "unbound god transport leaves a valid save")


func _test_transport_cancel_invalid_and_type_atomicity() -> void:
	var cancelled: Object = _new_game(8260, 2)
	if cancelled != null:
		_stage_tool(cancelled, 0, TRANSPORTER)
		_prepare_action(cancelled, 0, CENTRE)
		_assert_cancelled_atomic(cancelled, TRANSPORTER, {
			"tool_id": TRANSPORTER,
			"target_kind": "property",
			"target_id": PROPERTY_SOURCE,
			"destination_id": PROPERTY_DESTINATION,
			"cancel": true,
		}, "transport cancellation")

	var time_cancel: Object = _new_game(8261, 2)
	if time_cancel != null:
		_stage_tool(time_cancel, 0, TIME_MACHINE)
		_prepare_action(time_cancel, 0, CENTRE)
		_assert_cancelled_atomic(time_cancel, TIME_MACHINE, {"tool_id": TIME_MACHINE, "cancel": true}, "time cancellation")

	var cases: Array = [
		{"label": "missing target kind", "params": {"tool_id": TRANSPORTER, "target_id": PROPERTY_SOURCE, "destination_id": PROPERTY_DESTINATION}},
		{"label": "unknown target kind", "params": {"tool_id": TRANSPORTER, "target_kind": "unknown", "target_id": PROPERTY_SOURCE, "destination_id": PROPERTY_DESTINATION}},
		{"label": "missing target id", "params": {"tool_id": TRANSPORTER, "target_kind": "property", "destination_id": PROPERTY_DESTINATION}},
		{"label": "fractional target id", "params": {"tool_id": TRANSPORTER, "target_kind": "property", "target_id": 2.5, "destination_id": PROPERTY_DESTINATION}},
		{"label": "string target id", "params": {"tool_id": TRANSPORTER, "target_kind": "property", "target_id": "2", "destination_id": PROPERTY_DESTINATION}},
		{"label": "boolean target id", "params": {"tool_id": TRANSPORTER, "target_kind": "property", "target_id": true, "destination_id": PROPERTY_DESTINATION}},
		{"label": "same property source and destination", "params": {"tool_id": TRANSPORTER, "target_kind": "property", "target_id": PROPERTY_SOURCE, "destination_id": PROPERTY_SOURCE}},
		{"label": "off-map destination", "params": {"tool_id": TRANSPORTER, "target_kind": "property", "target_id": PROPERTY_SOURCE, "destination_id": 10}},
		{"label": "fractional destination", "params": {"tool_id": TRANSPORTER, "target_kind": "property", "target_id": PROPERTY_SOURCE, "destination_id": 3.5}},
		{"label": "string destination", "params": {"tool_id": TRANSPORTER, "target_kind": "property", "target_id": PROPERTY_SOURCE, "destination_id": "3"}},
		{"label": "boolean destination", "params": {"tool_id": TRANSPORTER, "target_kind": "property", "target_id": PROPERTY_SOURCE, "destination_id": false}},
		{"label": "malformed cancellation", "params": {"tool_id": TRANSPORTER, "target_kind": "property", "target_id": PROPERTY_SOURCE, "destination_id": PROPERTY_DESTINATION, "cancel": "yes"}},
		{"label": "malformed tool id", "params": {"tool_id": 11, "target_kind": "property", "target_id": PROPERTY_SOURCE, "destination_id": PROPERTY_DESTINATION}},
	]
	for offset in range(cases.size()):
		var game: Object = _new_game(8262 + offset, 2)
		if game == null:
			continue
		Fixture.set_property(game, PROPERTY_SOURCE, 0, 2, false)
		Fixture.set_property(game, PROPERTY_DESTINATION, -1, 0, false)
		_stage_tool(game, 0, TRANSPORTER)
		_prepare_action(game, 0, CENTRE)
		var item: Dictionary = cases[offset]
		_assert_rejected_atomic(game, TRANSPORTER, item["params"], "transport " + str(item["label"]))

	var no_anchor: Object = _new_game(8280, 2)
	if no_anchor != null:
		_stage_tool(no_anchor, 0, TIME_MACHINE)
		_prepare_action(no_anchor, 0, CENTRE)
		_assert_rejected_atomic(no_anchor, TIME_MACHINE, {"tool_id": TIME_MACHINE}, "time machine without an anchor")

	var detained: Object = _new_game(8281, 2)
	if detained != null:
		detained.state["players"][1]["position"] = 0
		detained.state["players"][1]["previous_position"] = -1
		detained.state["players"][1]["hospital_days"] = 2
		_stage_tool(detained, 0, TRANSPORTER)
		_prepare_action(detained, 0, CENTRE)
		_assert_rejected_atomic(detained, TRANSPORTER, {"tool_id": TRANSPORTER, "target_kind": "player", "target_id": 1, "destination_id": ROAD}, "detained player target")


func _ai_transport_game(seed_value: int, tool_id: String) -> Object:
	var game: Object = _new_game(seed_value, 2)
	if game == null:
		return null
	Fixture.clear_tools_except(game, 1, [])
	game.state["players"][1]["cards"] = []
	game.state["players"][1]["cash"] = 0
	game.state["players"][1]["deposit"] = 0
	game.state["players"][1]["position"] = CENTRE
	game.state["players"][1]["previous_position"] = -1
	game.state["players"][0]["position"] = ROAD
	game.state["current_player"] = 1
	game.state["phase"] = "await_roll"
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	var deposit_total: int = 0
	for player_value in game.state.get("players", []):
		deposit_total += int(player_value.get("deposit", 0))
	game.state["bank"]["deposits"] = deposit_total
	_stage_tool(game, 1, tool_id, "AI " + tool_id)
	game._sync_state()
	game._set_action_options(1)
	return game


func _last_tool_event(game: Object, tool_id: String) -> Dictionary:
	var events: Variant = game.state.get("event_log", [])
	if typeof(events) != TYPE_ARRAY:
		return {}
	for index in range(events.size() - 1, -1, -1):
		if typeof(events[index]) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = events[index]
		if str(event.get("type", "")) == "tool_used" and str(event.get("tool_id", "")) == tool_id:
			return event
	return {}


func _test_ai_transport_and_time_determinism() -> void:
	var first: Object = _ai_transport_game(8290, TRANSPORTER)
	var second: Object = _ai_transport_game(8290, TRANSPORTER)
	if first == null or second == null:
		return
	_valid_before(first, "AI transporter fixture")
	_valid_before(second, "repeat AI transporter fixture")
	var first_result: Dictionary = first.run_ai_turn()
	var second_result: Dictionary = second.run_ai_turn()
	_expect(bool(first_result.get("ok", false)), "AI transporter turn completes")
	_expect(bool(second_result.get("ok", false)), "repeat AI transporter turn completes")
	var first_event: Dictionary = _last_tool_event(first, TRANSPORTER)
	var second_event: Dictionary = _last_tool_event(second, TRANSPORTER)
	if first_event.is_empty():
		qualified_red += 1
		print("QUALIFIED RED: AI transporter produced no transport event")
		_expect(false, "AI chooses self transport before its normal roll")
	else:
		_expect_equal(str(first_event.get("target_kind", "")), "player", "AI transport targets a player")
		_expect_equal(int(first_event.get("target_id", -1)), 1, "AI transport targets itself")
		_expect(int(first_event.get("destination_id", -1)) != CENTRE, "AI chooses a non-current destination")
	if second_event.is_empty():
		qualified_red += 1
		print("QUALIFIED RED: repeat AI transporter produced no transport event")
	_expect(not second_event.is_empty(), "repeat AI transporter records a transport event")
	if not first_event.is_empty() and not second_event.is_empty():
		_expect_equal(second_event, first_event, "AI chooses the same deterministic transport")
	_expect_equal(first.to_json(), second.to_json(), "identical AI transport seeds produce identical JSON")

	var ai_time: Object = _ai_transport_game(8291, TIME_MACHINE)
	if ai_time == null:
		return
	var time_before: int = int(ai_time.state["players"][1]["tools"].get(TIME_MACHINE, 0))
	var ai_time_result: Dictionary = ai_time.run_ai_turn()
	_expect(bool(ai_time_result.get("ok", false)), "AI time-machine turn completes")
	_expect_equal(int(ai_time.state["players"][1]["tools"].get(TIME_MACHINE, 0)), time_before, "AI never consumes the human-only time machine")
	_expect(_last_tool_event(ai_time, TIME_MACHINE).is_empty(), "AI never records a time-machine use")
