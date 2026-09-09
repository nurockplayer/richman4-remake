extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/hazard_fixture.gd")

var checks := 0
var failures := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func make_game(seed_value: int = 3601, player_count: int = 4) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, Fixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"original_statuses": true,
		"original_hazards": true,
		"day_limit": 30,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	expect(game != null, "hazard AI fixture starts")
	if game == null:
		return null
	# The fixture's six-node graph has too few free anchors for the ordinary
	# god spawn set. Removing actors keeps these checks about AI/hazard paths.
	game.state.god_objects = []
	for player_id in range(player_count):
		game.set_player_ai(player_id, false)
	return game


func set_ai_turn(game: Object, player_id: int) -> void:
	game.set_player_ai(player_id, true)
	game.state.current_player = player_id
	game.state.phase = "await_roll"
	game.state.route_options = []
	game.state.remaining_steps = 0
	game.state.pending_movement = {}
	game.state.pending_remote_dice = {}
	game._set_action_options(player_id)


func remove_held_tool(game: Object, player_id: int, tool_id: String) -> bool:
	var player_tools: Dictionary = game.state.players[player_id].tools
	var quantity: int = int(player_tools.get(tool_id, 0))
	if quantity <= 0:
		return true
	var result: Dictionary = Inventory.consume_tool(game.state.inventory_supply, player_tools, tool_id, quantity)
	return bool(result.get("ok", false))


func has_event(game: Object, event_type: String, tool_id: String = "") -> bool:
	for event_value in game.state.event_log:
		if typeof(event_value) != TYPE_DICTIONARY or str(event_value.get("type", "")) != event_type:
			continue
		if tool_id.is_empty() or str(event_value.get("tool_id", "")) == tool_id:
			return true
	return false


func events_for_tool(game: Object, tool_id: String) -> Array:
	var result: Array = []
	for event_value in game.state.event_log:
		if typeof(event_value) == TYPE_DICTIONARY and str(event_value.get("type", "")) == "tool_used" and str(event_value.get("tool_id", "")) == tool_id:
			result.append(event_value)
	return result


func valid_save(game: Object, label: String) -> void:
	var validation: Dictionary = Game.validate_save(game.to_dict())
	expect(bool(validation.get("ok", false)), label + ": " + str(validation.get("errors", [])))


func unique_non_current_nodes(path: Array, current_node: int) -> Array:
	var result: Array = []
	for node_value in path:
		var node_id: int = int(node_value)
		if node_id != current_node and not result.has(node_id):
			result.append(node_id)
	return result


func _test_ai_places_mine_and_bomb() -> void:
	# The pre-roll AI lane must reach hazard actions even when the generic
	# worker/roadblock/vehicle heuristics have no usable item. Each production
	# run_ai_turn consumes one hazard opportunity before rolling.
	var mine_game: Object = make_game(3601)
	if mine_game == null:
		return
	for tool_id in ["機器娃娃", "路障", "定時炸彈", "遙控骰子", "機車", "汽車"]:
		expect(remove_held_tool(mine_game, 1, tool_id), "mine AI removes competing " + tool_id)
	set_ai_turn(mine_game, 1)
	var mine_supply_before: int = int(mine_game.state.inventory_supply.tools["地雷"])
	var mine_result: Dictionary = mine_game.run_ai_turn()
	var mine_events: Array = events_for_tool(mine_game, "地雷")
	expect(bool(mine_result.get("ok", false)), "AI mine turn completes")
	expect(not mine_events.is_empty(), "AI uses mine through pre-roll production path")
	if not mine_events.is_empty():
		var mine_tile: int = int(mine_events[0].get("tile_id", -1))
		expect(str(mine_game.state.ground_hazards.get(str(mine_tile), {}).get("kind", "")) == "mine" or has_event(mine_game, "mine_triggered"), "AI mine event leaves a mine or resolves its landing")
		expect(int(mine_events[0].get("player_id", -1)) == 1, "AI mine event belongs to current player")
	# Reset only the turn entry. The first turn may have moved the player, but
	# the next deterministic free-road target remains production-selected.
	var bomb_game: Object = make_game(3602)
	if bomb_game == null:
		return
	for tool_id in ["機器娃娃", "路障", "地雷", "遙控骰子", "機車", "汽車"]:
		expect(remove_held_tool(bomb_game, 1, tool_id), "bomb AI removes competing " + tool_id)
	set_ai_turn(bomb_game, 1)
	var bomb_supply_before: int = int(bomb_game.state.inventory_supply.tools["定時炸彈"])
	var bomb_result: Dictionary = bomb_game.run_ai_turn()
	var bomb_events: Array = events_for_tool(bomb_game, "定時炸彈")
	expect(bool(bomb_result.get("ok", false)), "AI bomb turn completes")
	expect(not bomb_events.is_empty(), "AI uses timed bomb through pre-roll production path")
	if not bomb_events.is_empty():
		var bomb_tile: int = int(bomb_events[0].get("tile_id", -1))
		expect(str(bomb_game.state.ground_hazards.get(str(bomb_tile), {}).get("kind", "")) == "timed_bomb" or has_event(bomb_game, "bomb_picked_up") or has_event(bomb_game, "bomb_exploded"), "AI bomb event leaves a bomb or resolves its landing")
		expect(int(bomb_events[0].get("player_id", -1)) == 1, "AI bomb event belongs to current player")
	expect(int(bomb_game.state.inventory_supply.tools["定時炸彈"]) == bomb_supply_before, "AI timed bomb placement does not return supply")
	valid_save(mine_game, "AI mine turn save")
	valid_save(bomb_game, "AI bomb turn save")


func _test_ai_machine_doll_cleanup() -> void:
	# Compute the machine route once from the same seed, then stage every dynamic
	# object category on that route. This keeps the expected path independent of
	# the AI's ordinary movement and checks the machine's v9 cleanup boundary.
	var probe: Object = make_game(3610)
	if probe == null:
		return
	probe.state.players[0].position = 1
	probe.state.players[0].previous_position = -1
	set_ai_turn(probe, 0)
	var probe_result: Dictionary = probe.choose_action("use_tool", {"tool_id": "機器娃娃"})
	expect(bool(probe_result.get("ok", false)), "machine route probe succeeds")
	var path: Array = probe_result.get("path", [])
	var nodes: Array = unique_non_current_nodes(path, 1)
	expect(path.size() == 9, "AI machine route has nine steps")
	expect(nodes.size() >= 4, "AI machine route has four cleanup anchors")
	if nodes.size() < 4:
		return

	var game: Object = make_game(3610)
	if game == null:
		return
	game.state.players[0].position = 1
	game.state.players[0].previous_position = -1
	# Keep one machine for the AI, while reserving the finite units represented
	# by staged road objects in player 1's inventory.
	for tool_id in ["路障", "地雷", "遙控骰子", "機車", "汽車"]:
		expect(remove_held_tool(game, 0, tool_id), "machine AI removes competing " + tool_id)
	for tool_id in ["地雷", "定時炸彈", "路障"]:
		var player_tools: Dictionary = game.state.players[1].tools
		expect(int(player_tools.get(tool_id, 0)) > 0, "fixture reserves " + tool_id + " for machine cleanup")
		player_tools.erase(tool_id)
	game.state.ground_hazards = {
		str(nodes[0]): {"kind": "mine", "placer_id": 1},
		str(nodes[1]): {"kind": "timed_bomb", "placer_id": 1},
	}
	game.state.roadblocks = {str(nodes[2]): 1}
	game.state.god_objects = [
		{"id": 3, "node": 1, "owner": 0, "days": 7},
		{"id": 1, "node": nodes[3], "owner": -1, "days": 0},
	]
	game.state.players[0].god_id = 3
	# Keep the other player detained so a normal movement edge cannot receive
	# the carried bomb while the AI's machine route is being exercised.
	for detained_id in range(1, game.state.players.size()):
		game.state.players[detained_id].hospital_days = 3
		game.state.players[detained_id].position = game._status_node_index("hospital")
		game.state.players[detained_id].previous_position = -1
	game.state.players[0].bomb_steps = 7
	game.state.players[0].tools.erase("定時炸彈")
	set_ai_turn(game, 0)
	var machine_supply_before: int = int(game.state.inventory_supply.tools["機器娃娃"])
	var result: Dictionary = game.run_ai_turn()
	var cleanup_event: Dictionary = {}
	for event_value in game.state.event_log:
		if typeof(event_value) == TYPE_DICTIONARY and str(event_value.get("type", "")) == "machine_doll_cleared":
			cleanup_event = event_value
			break
	expect(bool(result.get("ok", false)), "AI machine turn completes")
	expect(not cleanup_event.is_empty(), "AI uses machine doll before rolling")
	if not cleanup_event.is_empty():
		expect(cleanup_event.get("path", []) == path, "AI machine uses deterministic saved RNG path")
		expect(int(cleanup_event.get("steps", 0)) == 9, "AI machine event reports nine steps")
		expect(cleanup_event.get("removed_hazards", []).size() == 2, "AI machine clears mine and timed bomb")
		expect(cleanup_event.get("removed_roadblocks", []).size() == 1, "AI machine clears one roadblock")
		expect(cleanup_event.get("removed_gods", []).size() == 1, "AI machine clears one unbound god")
	expect(game.state.ground_hazards.is_empty(), "AI machine removes staged ground hazards")
	expect(game.state.roadblocks.is_empty(), "AI machine removes staged roadblock")
	expect(game.state.god_objects.size() == 1 and int(game.state.god_objects[0].get("id", -1)) == 3, "AI machine preserves attached god")
	expect(int(game.state.players[0].bomb_steps) > 0 and int(game.state.players[0].bomb_steps) <= 7, "AI machine preserves carried bomb countdown")
	expect(int(game.state.inventory_supply.tools["機器娃娃"]) == machine_supply_before, "AI machine consumption follows v9 supply semantics")
	valid_save(game, "AI machine cleanup save")


func _test_ai_match_replay() -> void:
	# A short paired replay exercises the public run_ai_turn API, then the full
	# run_ai_match loop. Reloading the second copy on each step catches hazards,
	# countdowns, route state and company/calendar mutations that are not visible
	# in a single placement assertion.
	var game: Object = make_game(3620, 2)
	if game == null:
		return
	for player_id in range(2):
		game.set_player_ai(player_id, true)
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null, "AI hazard match snapshot restores")
	if restored == null:
		return
	for turn_index in range(4):
		var first: Dictionary = game.run_ai_turn()
		var second: Dictionary = restored.run_ai_turn()
		expect(bool(first.get("ok", false)) and bool(second.get("ok", false)), "paired AI hazard turn %d completes" % turn_index)
		valid_save(game, "AI hazard turn %d save" % turn_index)
		expect(game.to_json() == restored.to_json(), "paired AI hazard turn %d is deterministic" % turn_index)
		restored = Game.from_dict(JSON.parse_string(restored.to_json()))
		expect(restored != null, "AI hazard state reloads after turn %d" % turn_index)
		if restored == null:
			return
	var first_match: Dictionary = game.run_ai_match(200)
	var second_match: Dictionary = restored.run_ai_match(200)
	expect(bool(first_match.get("ok", false)) and bool(second_match.get("ok", false)), "AI hazard match reaches game over")
	expect(game.state.phase == "game_over" and restored.state.phase == "game_over", "AI hazard match settles at game over")
	expect(int(game.state.elapsed) == 30 and int(restored.state.elapsed) == 30, "AI hazard match reaches configured day limit")
	expect(game.to_json() == restored.to_json(), "AI hazard full match remains deterministic after save replay")
	valid_save(game, "AI hazard final match save")


func _initialize() -> void:
	_test_ai_places_mine_and_bomb()
	_test_ai_machine_doll_cleanup()
	_test_ai_match_replay()
	print("Hazard AI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
