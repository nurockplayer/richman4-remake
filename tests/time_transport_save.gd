extends SceneTree

## Issue #81 save contract for the v13 時光機／傳送機 batch.
##
## The transport and time effects are intentionally still qualified RED until
## their production implementation lands.  This file keeps the save boundary
## executable beforehand: every world snapshot is a legal v13 graph, private
## time anchors never become serialized state, and an unavailable post-load
## restore remains byte/RNG/inventory atomic.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/time_transport_fixture.gd")

const V13 := 13
const TIME_MACHINE := "時光機"
const TRANSPORTER := "傳送機"
const REMOTE_DICE := "遙控骰子"
const TIMED_BOMB := "定時炸彈"
const CENTRE := 1
const PROPERTY_SOURCE := 2
const ROAD := 9
const SECOND_ROAD := 8

var checks: int = 0
var failures: int = 0
var qualified_red: int = 0


func _initialize() -> void:
	_test_v13_world_round_trip_and_continuation()
	_test_private_anchor_loss_after_json_load_is_atomic()
	_test_repeated_restore_debits_and_exhausts()
	_test_discarded_future_anchor_is_unusable()
	_test_player_transport_skips_payable_landing()
	_test_stay_and_status_skip_keep_anchor()
	print("Time/transport save checks: %d, failures: %d, qualified_red: %d" % [checks, failures, qualified_red])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_game(seed_value: int, player_count: int = 3) -> Object:
	var game: Object = Fixture.new_game(seed_value, player_count)
	_expect(game != null, "v13 save fixture starts")
	if game == null:
		return null
	_expect_equal(int(game.state.get("version", -1)), V13, "save fixture remains v13")
	_expect(bool(game.state.get("original_building_cards", false)), "save fixture retains the v13 marker")
	_expect(bool(game.state.get("original_research", false)), "save fixture retains research capability")
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), "fresh v13 save fixture validates: %s" % str(validation.get("errors", [])))
	return game


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
		_expect_equal(game.state["inventory_supply"]["tools"], supply_before, name + " leaves research supply unchanged")
	return bool(result.get("ok", false))


func _public_use(game: Object, params: Dictionary, label: String) -> Dictionary:
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), label + " starts from a valid save: " + str(validation.get("errors", [])))
	return game.choose_action("use_tool", params)


func _expect_success(result: Dictionary, label: String) -> bool:
	var qualified: bool = _mark_qualified_red(result, label)
	var ok: bool = bool(result.get("ok", false))
	_expect(ok, label + " succeeds: " + str(result.get("message", "")))
	# Keep the qualified RED classification separate from the assertion.  The
	# implementation must still turn this into a passing assertion after the
	# production effect is restored.
	return ok and not qualified


func _prepare_action(game: Object, player_id: int = 0, position: int = CENTRE, phase: String = "await_roll") -> void:
	Fixture.prepare_action(game, player_id, position, phase)


func _mark_qualified_red(result: Dictionary, label: String) -> bool:
	var message: String = str(result.get("message", ""))
	if not bool(result.get("ok", false)) and message.contains("尚未還原"):
		qualified_red += 1
		print("QUALIFIED RED: %s -> %s" % [label, message])
		return true
	return false


func _status_query(game: Object, label: String) -> Dictionary:
	if not game.has_method("time_machine_status"):
		qualified_red += 1
		print("QUALIFIED RED: %s status query is not available yet" % label)
		_expect(false, label + " status query exists")
		return {}
	var value: Variant = game.call("time_machine_status")
	_expect(typeof(value) == TYPE_DICTIONARY, label + " status returns a dictionary")
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _assert_rejected_atomic(
	game: Object,
	result: Dictionary,
	label: String,
	before_json: String,
	before_rng: String,
	before_event: Dictionary,
	before_supply: Dictionary,
	before_tools: Dictionary,
	player_id: int = 0,
) -> void:
	var qualified: bool = _mark_qualified_red(result, label)
	_expect(not bool(result.get("ok", false)), label + " is rejected")
	if not qualified:
		_expect(not str(result.get("message", "")).is_empty(), label + " explains the rejection")
	_expect_equal(game.to_json(), before_json, label + " is byte-for-byte atomic")
	_expect_equal(str(game.to_dict().get("rng_state_text", "")), before_rng, label + " keeps RNG continuation")
	_expect_equal(game.state.get("last_event", {}), before_event, label + " appends no event")
	_expect_equal(game.state["inventory_supply"]["tools"], before_supply, label + " keeps tool supply")
	_expect_equal(game.state["players"][player_id].get("tools", {}), before_tools, label + " keeps held tools")


func _advance_non_landing_turn(game: Object, player_id: int, label: String) -> bool:
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
	_expect(bool(result.get("ok", false)), label + " advances through public end_turn")
	return bool(result.get("ok", false))


func _round_trip(game: Object, label: String) -> Object:
	var encoded: String = game.to_json()
	var parsed: Variant = JSON.parse_string(encoded)
	_expect(parsed is Dictionary, label + " JSON parses")
	if not parsed is Dictionary:
		return null
	var restored: Object = Game.from_dict(parsed)
	_expect(restored != null, label + " restores through from_dict")
	if restored == null:
		return null
	_expect_equal(restored.to_json(), encoded, label + " JSON round trip is exact")
	var validation: Dictionary = Game.validate_save(restored.to_dict())
	_expect(bool(validation.get("ok", false)), label + " restored world validates: " + str(validation.get("errors", [])))
	return restored


func _prepare_rich_world(game: Object) -> void:
	# Preserve ownership, aliased facility entrances, location-bound research,
	# and the legal v13 inventory shape through every save boundary.
	Fixture.set_property(game, PROPERTY_SOURCE, 0, 3, false)
	Fixture.set_facility(game, CENTRE, 0, 2, 4, 0x51, 2, 3)
	Fixture.set_facility(game, 2, -1, 0, 0, 0, 1, 4)
	_prepare_action(game, 0, CENTRE)
	game._sync_state()
	game._set_action_options(0)
	_expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "rich v13 world remains legal before save")


func _test_v13_world_round_trip_and_continuation() -> void:
	var game: Object = _new_game(8301, 3)
	if game == null:
		return
	_prepare_rich_world(game)
	var finite_before: int = int(game.state["inventory_supply"]["tools"].get(REMOTE_DICE, -1))
	var research_before: Dictionary = {
		TIME_MACHINE: int(game.state["inventory_supply"]["tools"].get(TIME_MACHINE, -1)),
		TRANSPORTER: int(game.state["inventory_supply"]["tools"].get(TRANSPORTER, -1)),
	}
	_stage_tool(game, 0, TIME_MACHINE)
	_stage_tool(game, 0, TRANSPORTER)
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(REMOTE_DICE, -1)), finite_before, "research-tool staging does not alter finite remote supply")
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(TIME_MACHINE, -1)), research_before[TIME_MACHINE], "time supply remains unbounded")
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(TRANSPORTER, -1)), research_before[TRANSPORTER], "transport supply remains unbounded")

	# Save while a public remote request is pending.  This exercises the legal
	# serialized world boundary before any movement consumes the request.
	var remote_result: Dictionary = game.choose_action("use_tool", {"tool_id": REMOTE_DICE, "value": 1})
	_expect(bool(remote_result.get("ok", false)), "public remote request reaches the save boundary")
	var pending_json: String = game.to_json()
	_expect(bool(Game.validate_save(JSON.parse_string(pending_json)).get("ok", false)), "pending remote v13 snapshot validates")
	_expect_equal(int(game.state["inventory_supply"]["tools"].get(REMOTE_DICE, -1)), finite_before + 1, "finite remote supply receives the consumed tool")
	var restored: Object = _round_trip(game, "pending remote v13 save")
	if restored == null:
		return
	_expect_equal(restored.state.get("pending_remote_dice", {}), game.state.get("pending_remote_dice", {}), "pending remote request survives JSON")
	_expect_equal(restored.state["inventory_supply"]["tools"], game.state["inventory_supply"]["tools"], "finite and research supplies survive JSON")
	_expect_equal(restored.state["players"][0].get("tools", {}), game.state["players"][0].get("tools", {}), "held time and transport tools survive JSON")
	_expect_equal(restored.state["board"][CENTRE].get("research_tool", -1), 2, "source research rank survives JSON")
	_expect_equal(restored.state["board"][CENTRE].get("research_turns", -1), 3, "source research countdown survives JSON")
	_expect_equal(restored.state["board"][7].get("research_tool", -1), 1, "destination research rank remains location-bound in JSON")
	_expect_equal(restored.state["board"][7].get("research_turns", -1), 4, "destination research countdown remains location-bound in JSON")

	# Continue the original and loaded worlds through the public roll and route
	# APIs, then compare the exact post-turn state.  No private state is used to
	# resume either branch.
	var original_roll: Dictionary = game.roll(1)
	var restored_roll: Dictionary = restored.roll(1)
	_expect(bool(original_roll.get("ok", false)) and bool(restored_roll.get("ok", false)), "original and loaded worlds continue through roll")
	_expect_equal(restored_roll.get("dice", []), original_roll.get("dice", []), "loaded world keeps the same remote die")
	_expect_equal(restored_roll.get("total", -1), original_roll.get("total", -1), "loaded world keeps the same roll total")
	_expect_equal(restored.to_json(), game.to_json(), "loaded world matches after consuming the remote request")
	_expect_equal(str(game.state.get("phase", "")), "await_route", "world continuation retains the route pause")
	var original_route: Dictionary = game.choose_route(PROPERTY_SOURCE)
	var restored_route: Dictionary = restored.choose_route(PROPERTY_SOURCE)
	_expect(bool(original_route.get("ok", false)) and bool(restored_route.get("ok", false)), "original and loaded worlds continue through route choice")
	_expect_equal(restored.to_json(), game.to_json(), "loaded world matches after route continuation")
	var original_end: Dictionary = game.end_turn()
	var restored_end: Dictionary = restored.end_turn()
	_expect(bool(original_end.get("ok", false)) and bool(restored_end.get("ok", false)), "original and loaded worlds continue through end_turn")
	_expect_equal(restored.to_json(), game.to_json(), "loaded world remains deterministic after end_turn")


func _establish_human_anchor(game: Object, label: String) -> bool:
	# This is the only anchor setup path: public remote dice, public roll, and a
	# real graph route.  The test never writes a private anchor or serialized
	# substitute directly.
	_prepare_action(game, 0, CENTRE)
	var remote_result: Dictionary = game.choose_action("use_tool", {"tool_id": REMOTE_DICE, "value": 1})
	_expect(bool(remote_result.get("ok", false)), label + " stages a public remote roll")
	if not bool(remote_result.get("ok", false)):
		return false
	var before_roll: String = game.to_json()
	var roll_result: Dictionary = game.roll(1)
	_expect(bool(roll_result.get("ok", false)), label + " rolls through the public API")
	if not bool(roll_result.get("ok", false)):
		return false
	_expect_equal(str(game.state.get("phase", "")), "await_route", label + " exposes a real route choice")
	_expect(game.state.get("route_options", []).has(PROPERTY_SOURCE), label + " route contains the selected property")
	var route_result: Dictionary = game.choose_route(PROPERTY_SOURCE)
	_expect(bool(route_result.get("ok", false)), label + " chooses a real route")
	_expect_equal(int(game.state["players"][0].get("position", -1)), PROPERTY_SOURCE, label + " reaches the selected property")
	_expect_equal(str(game.state.get("phase", "")), "await_action", label + " resolves the real landing")
	_expect(not game.to_json().is_empty() and before_roll != game.to_json(), label + " changes the world only through movement")
	return bool(route_result.get("ok", false))


func _test_private_anchor_loss_after_json_load_is_atomic() -> void:
	var fresh: Object = _new_game(8302, 2)
	if fresh == null:
		return
	_stage_tool(fresh, 0, TIME_MACHINE)
	_prepare_action(fresh, 0, CENTRE)
	var fresh_status: Dictionary = _status_query(fresh, "fresh time anchor status")
	if fresh.has_method("time_machine_status"):
		_expect_equal(bool(fresh_status.get("available", true)), false, "new game starts without a private anchor")
	var game: Object = fresh
	if not _establish_human_anchor(game, "volatile anchor"):
		return
	var saved_json: String = game.to_json()
	var saved_data: Variant = JSON.parse_string(saved_json)
	_expect(saved_data is Dictionary, "anchored v13 world JSON parses")
	if not saved_data is Dictionary:
		return
	_expect(bool(Game.validate_save(saved_data).get("ok", false)), "anchored v13 world remains a legal save")
	var loaded: Object = Game.from_dict(saved_data)
	_expect(loaded != null, "anchored world restores through JSON")
	if loaded == null:
		return
	_expect_equal(loaded.to_json(), saved_json, "loading loses no serialized world data")
	_expect_equal(int(loaded.state["players"][0]["tools"].get(TIME_MACHINE, -1)), 1, "loading keeps the held time machine")
	_expect_equal(int(loaded.state["inventory_supply"]["tools"].get(TIME_MACHINE, -1)), 0, "loading keeps the unbounded research supply")
	var loaded_status: Dictionary = _status_query(loaded, "post-load time anchor status")
	if loaded.has_method("time_machine_status"):
		_expect_equal(bool(loaded_status.get("available", true)), false, "JSON load starts without the private anchor")

	# A failed restore after volatile-anchor loss is a read-only public action.
	var before_json: String = loaded.to_json()
	var before_rng: String = str(loaded.to_dict().get("rng_state_text", ""))
	var before_event: Dictionary = loaded.state.get("last_event", {}).duplicate(true)
	var before_supply: Dictionary = loaded.state["inventory_supply"]["tools"].duplicate(true)
	var before_held: int = int(loaded.state["players"][0]["tools"].get(TIME_MACHINE, 0))
	var restore_result: Dictionary = loaded.choose_action("use_tool", {"tool_id": TIME_MACHINE})
	var qualified: bool = _mark_qualified_red(restore_result, "time restore after JSON load")
	_expect(not bool(restore_result.get("ok", false)), "time restore after JSON load is rejected")
	if not qualified:
		_expect(not str(restore_result.get("message", "")).is_empty(), "post-load rejection explains the unavailable anchor")
	_expect_equal(loaded.to_json(), before_json, "post-load rejection is byte-for-byte atomic")
	_expect_equal(str(loaded.to_dict().get("rng_state_text", "")), before_rng, "post-load rejection keeps RNG continuation")
	_expect_equal(loaded.state.get("last_event", {}), before_event, "post-load rejection appends no event")
	_expect_equal(loaded.state["inventory_supply"]["tools"], before_supply, "post-load rejection keeps research supply")
	_expect_equal(int(loaded.state["players"][0]["tools"].get(TIME_MACHINE, 0)), before_held, "post-load rejection keeps the held tool")
	_expect(bool(Game.validate_save(loaded.to_dict()).get("ok", false)), "post-load rejection leaves a valid v13 save")


func _test_repeated_restore_debits_and_exhausts() -> void:
	var game: Object = _new_game(8303, 2)
	if game == null:
		return
	_stage_tool(game, 0, TIME_MACHINE, "first time machine")
	_stage_tool(game, 0, TIME_MACHINE, "second time machine")
	_stage_tool(game, 0, TRANSPORTER)
	_prepare_action(game, 0, CENTRE)
	var transport_result: Dictionary = _public_use(game, {
		"tool_id": TRANSPORTER,
		"target_kind": "player",
		"target_id": 0,
		"destination_id": ROAD,
	}, "repeat restore self transport")
	if not _expect_success(transport_result, "repeat restore self transport"):
		return
	_expect_equal(int(game.state["players"][0].get("position", -1)), ROAD, "repeat restore transport reaches the road")
	_expect_equal(int(game.state["players"][0]["tools"].get(TIME_MACHINE, 0)), 2, "repeat restore starts with two time machines")

	var first_restore: Dictionary = _public_use(game, {"tool_id": TIME_MACHINE}, "first repeated time restore")
	if not _expect_success(first_restore, "first repeated time restore"):
		return
	_expect_equal(int(game.state["players"][0].get("position", -1)), CENTRE, "first restore returns to the self-transport anchor")
	_expect_equal(int(game.state["players"][0]["tools"].get(TIME_MACHINE, 0)), 1, "first restore debits one time machine")
	_expect_equal(int(game.state["players"][0]["tools"].get(TRANSPORTER, 0)), 1, "first restore recovers the staged transporter")

	var second_restore: Dictionary = _public_use(game, {"tool_id": TIME_MACHINE}, "second repeated time restore")
	if not _expect_success(second_restore, "second repeated time restore"):
		return
	_expect_equal(int(game.state["players"][0].get("position", -1)), CENTRE, "second restore uses the post-debit anchor")
	_expect_equal(int(game.state["players"][0]["tools"].get(TIME_MACHINE, 0)), 0, "second restore debits the last time machine")
	_expect_equal(int(game.state["players"][0]["tools"].get(TRANSPORTER, 0)), 1, "second restore does not replenish the transporter twice")

	# The exhausted third call must not consume, rewind RNG, append an event, or
	# otherwise mutate the legal v13 world.
	var before_json: String = game.to_json()
	var before_rng: String = str(game.to_dict().get("rng_state_text", ""))
	var before_event: Dictionary = game.state.get("last_event", {}).duplicate(true)
	var before_supply: Dictionary = game.state["inventory_supply"]["tools"].duplicate(true)
	var before_tools: Dictionary = game.state["players"][0].get("tools", {}).duplicate(true)
	var exhausted: Dictionary = _public_use(game, {"tool_id": TIME_MACHINE}, "third repeated time restore")
	var qualified: bool = _mark_qualified_red(exhausted, "third repeated time restore")
	_expect(not bool(exhausted.get("ok", false)), "third repeated time restore is rejected")
	if not qualified:
		_expect(not str(exhausted.get("message", "")).is_empty(), "third repeated time restore explains exhausted inventory")
	_expect_equal(game.to_json(), before_json, "third repeated time restore is byte-for-byte atomic")
	_expect_equal(str(game.to_dict().get("rng_state_text", "")), before_rng, "third repeated time restore keeps RNG continuation")
	_expect_equal(game.state.get("last_event", {}), before_event, "third repeated time restore appends no event")
	_expect_equal(game.state["inventory_supply"]["tools"], before_supply, "third repeated time restore keeps research supply")
	_expect_equal(game.state["players"][0].get("tools", {}), before_tools, "third repeated time restore keeps the exhausted inventory")


func _test_discarded_future_anchor_is_unusable() -> void:
	var game: Object = _new_game(8304, 2)
	if game == null:
		return
	# Both players are human so each can establish an independent private slot.
	game.set_player_ai(1, false)
	_stage_tool(game, 0, TIME_MACHINE, "first human time machine")
	_stage_tool(game, 0, TRANSPORTER, "first human transporter")
	_stage_tool(game, 1, TIME_MACHINE, "second human time machine")
	_stage_tool(game, 1, TRANSPORTER, "second human transporter")

	_prepare_action(game, 0, CENTRE)
	var first_transport: Dictionary = _public_use(game, {
		"tool_id": TRANSPORTER,
		"target_kind": "player",
		"target_id": 0,
		"destination_id": ROAD,
	}, "first human self transport")
	if not _expect_success(first_transport, "first human self transport"):
		return
	_expect_equal(int(game.state["players"][0].get("position", -1)), ROAD, "first human leaves a future position")
	if not _advance_non_landing_turn(game, 0, "first human self transport turn"):
		return

	_prepare_action(game, 1, CENTRE)
	var second_transport: Dictionary = _public_use(game, {
		"tool_id": TRANSPORTER,
		"target_kind": "player",
		"target_id": 1,
		"destination_id": SECOND_ROAD,
	}, "second human self transport")
	if not _expect_success(second_transport, "second human self transport"):
		return
	_expect_equal(int(game.state["players"][1].get("position", -1)), SECOND_ROAD, "second human leaves a later future position")
	if not _advance_non_landing_turn(game, 1, "second human self transport turn"):
		return

	# The first human rewinds to the pre-self-transport snapshot.  The second
	# human's later anchor belongs to the discarded future and must be cleared,
	# while that player's held tool remains part of the restored world.
	_prepare_action(game, 0, ROAD)
	var first_restore: Dictionary = _public_use(game, {"tool_id": TIME_MACHINE}, "discarded future rewind")
	if not _expect_success(first_restore, "discarded future rewind"):
		return
	_expect_equal(int(game.state["players"][0].get("position", -1)), CENTRE, "first human rewind returns to its anchor")
	_expect_equal(int(game.state["players"][1]["tools"].get(TIME_MACHINE, 0)), 1, "discarded future rewind keeps second human tool")

	_prepare_action(game, 1, CENTRE)
	var before_json: String = game.to_json()
	var before_rng: String = str(game.to_dict().get("rng_state_text", ""))
	var before_event: Dictionary = game.state.get("last_event", {}).duplicate(true)
	var before_supply: Dictionary = game.state["inventory_supply"]["tools"].duplicate(true)
	var before_tools: Dictionary = game.state["players"][1].get("tools", {}).duplicate(true)
	var discarded_restore: Dictionary = _public_use(game, {"tool_id": TIME_MACHINE}, "discarded second human anchor")
	var qualified: bool = _mark_qualified_red(discarded_restore, "discarded second human anchor")
	_expect(not bool(discarded_restore.get("ok", false)), "discarded second human anchor is unusable")
	if not qualified:
		_expect(not str(discarded_restore.get("message", "")).is_empty(), "discarded second human anchor explains its invalidation")
	_expect_equal(game.to_json(), before_json, "discarded second human restore is byte-for-byte atomic")
	_expect_equal(str(game.to_dict().get("rng_state_text", "")), before_rng, "discarded second human restore keeps RNG continuation")
	_expect_equal(game.state.get("last_event", {}), before_event, "discarded second human restore appends no event")
	_expect_equal(game.state["inventory_supply"]["tools"], before_supply, "discarded second human restore keeps research supply")
	_expect_equal(game.state["players"][1].get("tools", {}), before_tools, "discarded second human restore keeps the held tool")


func _test_player_transport_skips_payable_landing() -> void:
	var game: Object = _new_game(8305, 3)
	if game == null:
		return
	Fixture.set_property(game, PROPERTY_SOURCE, 0, 3, false)
	game.state["players"][1]["position"] = CENTRE
	game.state["players"][1]["previous_position"] = -1
	game.state["players"][1]["bomb_steps"] = 7
	# Reclassify player 1's opening timed bomb as the carried hazard.  The
	# opening finite supply already accounts for this unit, so the held copy is
	# removed without touching shared supply and the v13 conservation invariant
	# remains exact.
	game.state["players"][1]["tools"].erase(TIMED_BOMB)
	_prepare_action(game, 0, CENTRE)
	_expect(Game._is_graph_road_tile(game.state["board"][PROPERTY_SOURCE]), "payable transport target is a graph road tile")
	_stage_tool(game, 0, TRANSPORTER)
	var target_before: Dictionary = game.state["players"][1].duplicate(true)
	var bank_before: Dictionary = game.state["bank"].duplicate(true)
	var event_start: int = game.state.get("event_log", []).size()
	var result: Dictionary = _public_use(game, {
		"tool_id": TRANSPORTER,
		"target_kind": "player",
		"target_id": 1,
		"destination_id": PROPERTY_SOURCE,
	}, "payable-property player transport")
	if not _expect_success(result, "payable-property player transport"):
		return
	var target: Dictionary = game.state["players"][1]
	_expect_equal(int(target.get("position", -1)), PROPERTY_SOURCE, "player transport reaches the payable property without landing")
	for key in ["cash", "deposit", "bomb_steps", "hospital_days", "prison_days", "skip_turns", "turtle_days", "stay_next", "turns_taken"]:
		_expect_equal(target.get(key, null), target_before.get(key, null), "player transport preserves payable target " + key)
	_expect_equal(game.state["bank"], bank_before, "player transport leaves bank balances untouched")
	_expect_equal(int(game.state.get("current_player", -1)), 0, "payable-property transport preserves the actor")
	_expect_equal(str(game.state.get("phase", "")), "await_roll", "payable-property transport does not enter a landing phase")
	var event_types: Array = []
	for index in range(event_start, game.state.get("event_log", []).size()):
		event_types.append(str(game.state["event_log"][index].get("type", "")))
	for forbidden in ["property_fee", "facility_service", "hospital_admitted", "prison_admitted", "research_progress", "research_produced", "bomb_exploded"]:
		_expect(not event_types.has(forbidden), "payable-property transport does not resolve " + forbidden)
	_expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "payable-property transport leaves a valid save")


func _test_stay_and_status_skip_keep_anchor() -> void:
	var cases: Array = [
		{"label": "stay", "field": "stay_next", "value": 1, "seed": 8306},
		{"label": "status", "field": "hospital_days", "value": 1, "seed": 8307},
	]
	for case_value in cases:
		var entry: Dictionary = case_value
		var game: Object = _new_game(int(entry["seed"]), 2)
		if game == null:
			continue
		_stage_tool(game, 0, TIME_MACHINE, str(entry["label"]) + " skip time machine")
		_stage_tool(game, 0, TRANSPORTER, str(entry["label"]) + " skip transporter")
		_prepare_action(game, 0, CENTRE)
		var transport_result: Dictionary = _public_use(game, {
			"tool_id": TRANSPORTER,
			"target_kind": "player",
			"target_id": 0,
			"destination_id": ROAD,
		}, str(entry["label"]) + " skip self transport")
		if not _expect_success(transport_result, str(entry["label"]) + " skip self transport"):
			continue
		var anchor_position: int = int(game.state["players"][0].get("position", -1))
		game.state["players"][0][str(entry["field"])] = int(entry["value"])
		var skip_result: Dictionary = game.roll(1)
		_expect(bool(skip_result.get("ok", false)), str(entry["label"]) + " turn skips through public roll")
		_expect_equal(str(game.state.get("phase", "")), "await_action", str(entry["label"]) + " skip leaves an action phase")
		if not bool(skip_result.get("ok", false)):
			continue
		if not _advance_non_landing_turn(game, 0, str(entry["label"]) + " skip first turn"):
			continue
		_prepare_action(game, 1, CENTRE, "await_action")
		if not _advance_non_landing_turn(game, 1, str(entry["label"]) + " skip second turn"):
			continue
		var restore_result: Dictionary = _public_use(game, {"tool_id": TIME_MACHINE}, str(entry["label"]) + " skip restore")
		if _expect_success(restore_result, str(entry["label"]) + " skip restore"):
			_expect_equal(int(game.state["players"][0].get("position", -1)), CENTRE, str(entry["label"]) + " restore returns to the earlier anchor")
			_expect_equal(int(game.state["players"][0]["tools"].get(TRANSPORTER, 0)), 1, str(entry["label"]) + " restore recovers the transporter")
		else:
			# Keep this assertion visible once the production effect is present;
			# current generic RED is already classified above.
			_expect(anchor_position == ROAD, str(entry["label"]) + " established the pre-skip anchor")
