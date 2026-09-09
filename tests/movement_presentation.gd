extends SceneTree

const MovementPresentation = preload("res://game/ui/movement_presentation.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _run() -> void:
	_test_direction_mapping()
	_test_action_scoped_graph_delta()
	_test_route_delta_and_input_immutability()
	_test_snap_guards()
	_test_capped_event_log_delta()
	print("Movement presentation checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_direction_mapping() -> void:
	var cases := [
		[Vector2(0, 1), 0],
		[Vector2(1, 1), 1],
		[Vector2(1, 0), 2],
		[Vector2(1, -1), 3],
		[Vector2(0, -1), 4],
		[Vector2(-1, -1), 5],
		[Vector2(-1, 0), 6],
		[Vector2(-1, 1), 7],
	]
	for entry in cases:
		_expect_equal(MovementPresentation.direction(Vector2.ZERO, entry[0]), entry[1], "direction maps octant %d" % int(entry[1]))
	_expect_equal(MovementPresentation.direction(Vector2(4, 4), Vector2(4, 4), 6), 6, "zero delta preserves prior direction")
	_expect_equal(MovementPresentation.direction(Vector2(4, 4), Vector2(4, 4), 12), 0, "invalid prior direction falls back to down")
	_expect_equal(MovementPresentation.direction(Vector2.ZERO, Vector2(4, 1)), 2, "nearest octant selects right for shallow diagonal")


func _test_action_scoped_graph_delta() -> void:
	var before := _snapshot(0, [{"id": 0, "position": 0}, {"id": 1, "position": 3}], [{"type": "new_game", "turn": 1}])
	var after := before.duplicate(true)
	after["players"][0]["position"] = 2
	after["event_log"] = [
		{"type": "new_game", "turn": 1},
		{"type": "move", "player_id": 0, "from": 0, "to": 1, "steps": 1},
		{"type": "move", "player_id": 0, "from": 1, "to": 2, "steps": 1},
		{"type": "points_landed", "player_id": 0, "points": 50},
	]
	var moves: Array = MovementPresentation.plan(before, after)
	_expect_equal(moves.size(), 2, "one action yields one queue entry per graph edge")
	if moves.size() == 2:
		_expect_equal(moves[0], {"player_id": 0, "from": 0, "to": 1, "direction": 2}, "first edge carries its direction")
		_expect_equal(moves[1], {"player_id": 0, "from": 1, "to": 2, "direction": 2}, "second edge remains ordered")
	var ordinary_refresh := before.duplicate(true)
	_expect(MovementPresentation.plan(before, ordinary_refresh).is_empty(), "repeated snapshot does not replay movement")
	var non_move_refresh := before.duplicate(true)
	non_move_refresh["event_log"] = [{"type": "new_game", "turn": 1}, {"type": "status_checked", "player_id": 0}]
	_expect(MovementPresentation.plan(before, non_move_refresh).is_empty(), "non-movement action has no presentation queue")


func _test_route_delta_and_input_immutability() -> void:
	var before := _snapshot(1, [{"id": 0, "position": 1}, {"id": 1, "position": 3}], [{"type": "new_game", "turn": 1}, {"type": "move", "player_id": 0, "from": 0, "to": 1, "steps": 1}])
	var after := before.duplicate(true)
	after["players"][0]["position"] = 2
	after["event_log"] = before["event_log"].duplicate(true)
	after["event_log"].append({"type": "route_chosen", "player_id": 0, "from": 1, "to": 2})
	after["event_log"].append({"type": "move", "player_id": 0, "from": 1, "to": 2, "steps": 1})
	var before_text := JSON.stringify(before)
	var after_text := JSON.stringify(after)
	var moves: Array = MovementPresentation.plan(before, after)
	_expect_equal(moves.size(), 1, "route action presents its newly chosen edge")
	_expect_equal(JSON.stringify(before), before_text, "plan leaves before snapshot untouched")
	_expect_equal(JSON.stringify(after), after_text, "plan leaves after snapshot untouched")


func _test_snap_guards() -> void:
	var before := _snapshot(0, [{"id": 0, "position": 0}, {"id": 1, "position": 3}], [{"type": "new_game", "turn": 1}])
	var valid_after := before.duplicate(true)
	valid_after["players"][0]["position"] = 1
	valid_after["event_log"].append({"type": "move", "player_id": 0, "from": 0, "to": 1, "steps": 1})
	_expect(not MovementPresentation.plan(before, valid_after).is_empty(), "valid graph edge is admitted")

	var legacy := valid_after.duplicate(true)
	legacy.erase("board_mode")
	_expect(MovementPresentation.plan(before, legacy).is_empty(), "legacy snapshot snaps instead of animating")

	var aggregate := valid_after.duplicate(true)
	aggregate["event_log"][1]["steps"] = 2
	_expect(MovementPresentation.plan(before, aggregate).is_empty(), "legacy aggregate move snaps")

	var teleport := before.duplicate(true)
	teleport["players"][0]["position"] = 2
	teleport["event_log"].append({"type": "teleport", "player_id": 0, "from": 0, "to": 2})
	_expect(MovementPresentation.plan(before, teleport).is_empty(), "teleport snaps")

	var status := valid_after.duplicate(true)
	status["event_log"].append({"type": "status_applied", "player_id": 0, "status": "hospital"})
	_expect(MovementPresentation.plan(before, status).is_empty(), "status interruption snaps")

	var terminal := valid_after.duplicate(true)
	terminal["phase"] = "game_over"
	terminal["event_log"].append({"type": "terminal", "winner": 1})
	_expect(MovementPresentation.plan(before, terminal).is_empty(), "terminal result snaps")

	var multi_actor := before.duplicate(true)
	multi_actor["players"][0]["position"] = 1
	multi_actor["players"][1]["position"] = 2
	multi_actor["event_log"] = [
		{"type": "new_game", "turn": 1},
		{"type": "move", "player_id": 0, "from": 0, "to": 1, "steps": 1},
		{"type": "move", "player_id": 1, "from": 3, "to": 2, "steps": 1},
	]
	_expect(MovementPresentation.plan(before, multi_actor).is_empty(), "multi-actor delta snaps")

	var map_changed := valid_after.duplicate(true)
	map_changed["map_id"] = "map-2"
	_expect(MovementPresentation.plan(before, map_changed).is_empty(), "map identity change snaps")

	var geometry_changed := valid_after.duplicate(true)
	geometry_changed["board"][1]["x"] = 999
	_expect(MovementPresentation.plan(before, geometry_changed).is_empty(), "map geometry change snaps")

	var broken_edge := valid_after.duplicate(true)
	broken_edge["board"][0]["adjacent"] = []
	_expect(MovementPresentation.plan(before, broken_edge).is_empty(), "edge absent from geometry snaps")


func _test_capped_event_log_delta() -> void:
	var history: Array = []
	for index in range(200):
		history.append({"type": "history", "seq": index})
	var before := _snapshot(0, [{"id": 0, "position": 0}], history)
	var after := before.duplicate(true)
	after["players"][0]["position"] = 1
	var capped: Array = history.slice(1)
	capped.append({"type": "move", "player_id": 0, "from": 0, "to": 1, "steps": 1})
	after["event_log"] = capped
	var moves: Array = MovementPresentation.plan(before, after)
	_expect_equal(moves.size(), 1, "capped log with one unambiguous new edge is admitted")

	var ambiguous := before.duplicate(true)
	ambiguous["players"][0]["position"] = 1
	var ambiguous_log: Array = []
	for index in range(199):
		ambiguous_log.append({"type": "history", "seq": 0})
	ambiguous_log.append({"type": "move", "player_id": 0, "from": 0, "to": 1, "steps": 1})
	ambiguous["event_log"] = ambiguous_log
	_expect(MovementPresentation.plan(before, ambiguous).is_empty(), "repeated capped overlap is ambiguous and snaps")


func _board() -> Array:
	return [
		{"index": 0, "x": 0, "y": 0, "adjacent": [1]},
		{"index": 1, "x": 10, "y": 0, "adjacent": [0, 2]},
		{"index": 2, "x": 20, "y": 0, "adjacent": [1, 3]},
		{"index": 3, "x": 20, "y": 10, "adjacent": [2]},
	]


func _snapshot(start_position: int, players: Array, event_log: Array) -> Dictionary:
	return {
		"board_mode": "graph",
		"map_id": "fixture:movement",
		"map_name": "Movement fixture",
		"map_schema": "richman4.runtime-map/v1",
		"map_version": 1,
		"map_source": {"payload_sha256": "a".repeat(64)},
		"start_position": start_position,
		"phase": "await_action",
		"board": _board(),
		"players": players.duplicate(true),
		"event_log": event_log.duplicate(true),
	}
