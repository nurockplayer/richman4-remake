extends SceneTree

const Model = preload("res://game/core/source_minigame_model.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_contract_and_deadlines()
	_test_balloon_scoring_and_effects()
	_test_penguin_source_dda_and_items()
	_test_catching_latched_motion_and_bomb()
	_test_snapshot_is_detached()
	print("Source minigame model checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new(kind: String, seed: int, data: Dictionary = {}) -> Model:
	return Model.new().configure(kind, seed, data)


func _test_contract_and_deadlines() -> void:
	var invalid := _new("unknown", 1)
	_expect(not bool(invalid.state.active), "unknown kind is inactive")
	_expect_equal(invalid.reward(), 0, "unknown kind has no reward")
	for spec in [["balloon", 150], ["penguin", 150], ["catching", 360]]:
		var model := _new(spec[0], 77)
		for _i in range(420 if spec[0]=="catching" else spec[1]):
			model.tick()
		_expect(model.finished(), "%s reaches source deadline" % spec[0])
		if spec[0]=="catching":
			_expect(int(model.state.tick)>=360 and int(model.state.tick)<=420 and bool(model.state.draining), "catching uses360 ordinary ticks then source drain")
		else:
			_expect_equal(int(model.state.tick), spec[1], "%s uses fixed tick deadline" % spec[0])


func _test_balloon_scoring_and_effects() -> void:
	var model := _new("balloon", 10)
	model.state["balloons"] = [{"id": 0, "x": 100, "y": 100, "phase": 1, "pop_frame": 0}]
	model.pointer(Vector2(100, 100), false)
	model.pointer(Vector2(100, 100), true)
	_expect_equal(model.reward(), 1, "ordinary balloon gives id plus one")
	_expect_equal(model.state.balloons[0].phase, 2, "hit balloon enters pop phase")
	model.state["balloons"] = [{"id": 9, "x": 100, "y": 100, "phase": 1, "pop_frame": 0}]
	model.state["score"] = 30
	model.pointer(Vector2(0, 0), false)
	model.pointer(Vector2(100, 100), true)
	_expect_equal(model.reward(), 60, "double balloon doubles score")
	model.state["balloons"] = [{"id": 10, "x": 100, "y": 100, "phase": 1, "pop_frame": 0}]
	model.pointer(Vector2(0, 0), false)
	model.pointer(Vector2(100, 100), true)
	_expect_equal(model.reward(), 30, "division balloon truncates score")
	model.state["score"] = 998
	model.state["balloons"] = [{"id": 8, "x": 100, "y": 100, "phase": 1, "pop_frame": 0}]
	model.pointer(Vector2(0, 0), false)
	model.pointer(Vector2(100, 100), true)
	_expect_equal(model.reward(), 999, "ordinary balloon clamps at 999")
	var special_counts := {9: 0, 10: 0, 11: 0}
	for id in Model.BALLOON_SPECIAL_TYPES:
		special_counts[id] = int(special_counts[id]) + 1
	_expect_equal(special_counts, {9: 2, 10: 5, 11: 3}, "question-mark spawn distribution keeps 2/5/3 source buckets")


func _test_penguin_source_dda_and_items() -> void:
	var model := _new("penguin", 22, {"current_cell": [3, 4], "cell_items": {"5,4": 2}})
	var before := model.snapshot()
	model.pointer(Vector2(80 + 5 * 48, 81 + 4 * 24), false)
	model.pointer(Vector2(80 + 5 * 48, 81 + 4 * 24), true)
	_expect_equal(model.state.movement_state, "walking", "penguin click starts movement")
	for _i in range(12):
		model.tick()
	_expect_equal(model.state.current_cell, Vector2i(5, 4), "penguin reaches target through central-hole detour")
	_expect_equal(model.reward(), 5, "penguin coin is worth five points")
	_expect_equal(model.state.dig_count, 1, "penguin digs once on target arrival")
	_expect(before.current_cell == Vector2i(3, 4), "snapshot before movement is detached")
	var bomb := _new("penguin", 23, {"current_cell": [3, 4], "cell_items": {"5,4": 1}})
	bomb.pointer(Vector2(80 + 5 * 48, 81 + 4 * 24), false)
	bomb.pointer(Vector2(80 + 5 * 48, 81 + 4 * 24), true)
	for _i in range(12):
		bomb.tick()
	_expect(bomb.finished() and bomb.state.finish_reason == "bomb", "penguin bomb ends game")


func _test_catching_latched_motion_and_bomb() -> void:
	var model := _new("catching", 30, {"items": [{"id": 0, "x": 320, "y": 320, "speed": 0}]})
	model.pointer(Vector2(400, 320), true)
	model.tick()
	_expect_equal(model.state.character_direction, 2, "catching follows pointer by ten source pixels")
	_expect_equal(model.state.counts[0], 0, "initial stationary direction cannot catch")
	model.tick()
	_expect_equal(model.state.counts[0], 1, "latched direction permits following-frame catch")
	_expect_equal(model.reward(), 10, "treasure chest is worth ten points")
	var bomb := _new("catching", 31, {"items": [{"id": 4, "x": 320, "y": 320, "speed": 0}]})
	bomb.pointer(Vector2(400, 320), true)
	bomb.tick()
	bomb.tick()
	_expect(bomb.finished() and bomb.state.bomb, "catching bomb ends game")
	_expect_equal(bomb.reward(), 0, "bomb does not award points")


func _test_snapshot_is_detached() -> void:
	var model := _new("balloon", 9)
	var copy := model.snapshot()
	copy["pointer"] = Vector2(639, 479)
	copy["effects"]["freeze_ticks"] = 99
	_expect_equal(model.state.pointer, Vector2.ZERO, "snapshot pointer is detached")
	_expect_equal(model.state.effects.freeze_ticks, 0, "snapshot nested state is detached")
	var source_grid: Array = []
	for i in range(81):
		source_grid.append(Vector2i(100 + i, 200 + i))
	var anchored := _new("penguin", 12, {"penguin_grid": source_grid})
	_expect_equal(anchored.state.penguin_position, Vector2(156, 256), "penguin_grid anchors are accepted without viewport scaling")
