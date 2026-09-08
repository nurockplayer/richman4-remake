extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const StatusFixture = preload("res://tests/fixtures/status_fixture.gd")

var checks := 0
var failures := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func make_game(seed_value: int = 31415) -> Object:
	var game := Game.new_game_on_board(seed_value, 4, StatusFixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"original_statuses": true,
		"day_limit": 30,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	if game == null:
		return null
	# The AI replay contract is about status state and graph progression; remove
	# unbound actors so the tiny fixture cannot start with an occupied node.
	game.state["god_objects"] = []
	for player_id in range(game.state.players.size()):
		game.set_player_ai(player_id, true)
	return game


func has_event(game: Object, event_type: String, status_kind: String = "") -> bool:
	for event in game.state.get("event_log", []):
		if typeof(event) != TYPE_DICTIONARY or str(event.get("type", "")) != event_type:
			continue
		if status_kind.is_empty() or str(event.get("status_kind", "")) == status_kind:
			return true
	return false


func valid(game: Object, label: String) -> void:
	var validation: Dictionary = Game.validate_save(game.to_dict())
	expect(bool(validation.get("ok", false)), label + ": " + str(validation.get("errors", [])))


func _initialize() -> void:
	var game := make_game()
	expect(game != null, "status AI fixture starts")
	if game == null:
		_finish()
		return
	var player: Dictionary = game.state.players[0]
	player["prison_days"] = 2
	player["hospital_days"] = 0
	player["position"] = game._status_node_index("prison")
	player["previous_position"] = -1
	game.state["current_player"] = 0
	game.state["phase"] = "await_roll"
	game._set_action_options(0)
	valid(game, "initial detained AI save")
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null, "detained AI save restores")
	if restored == null:
		_finish()
		return

	var prison_position := int(player.position)
	var first: Dictionary = game.run_ai_turn()
	var restored_first: Dictionary = restored.run_ai_turn()
	expect(bool(first.get("ok", false)) and bool(restored_first.get("ok", false)), "AI completes a prison skip turn")
	expect(int(player.prison_days) == 1 and int(player.position) == prison_position, "AI skip decrements prison without moving")
	expect(int(game.state.current_player) == 1 and int(restored.state.current_player) == 1, "AI advances to the next player after prison skip")
	expect(game.to_json() == restored.to_json(), "detained AI turn is deterministic after save restore")
	expect(has_event(game, "status_skipped", "prison"), "AI prison turn records status skip")
	valid(game, "first AI status turn")
	valid(restored, "restored first AI status turn")

	# Continue the paired games through status terminal/release and ordinary
	# graph turns, reloading one side after each turn to exercise JSON replay.
	var observed_release := false
	for turn_index in range(16):
		if game.state.get("phase", "") == "game_over":
			break
		var result: Dictionary = game.run_ai_turn()
		var restored_result: Dictionary = restored.run_ai_turn()
		expect(bool(result.get("ok", false)) and bool(restored_result.get("ok", false)), "paired AI turn %d completes" % turn_index)
		valid(game, "AI turn %d save" % turn_index)
		valid(restored, "restored AI turn %d save" % turn_index)
		expect(game.to_json() == restored.to_json(), "paired AI turn %d remains identical" % turn_index)
		if has_event(game, "status_released", "prison"):
			observed_release = true
		restored = Game.from_dict(JSON.parse_string(restored.to_json()))
		expect(restored != null, "AI state reloads after turn %d" % turn_index)
		if restored == null:
			break
	expect(observed_release, "AI reaches and releases the prison terminal marker")

	var release_game := make_game(31416)
	expect(release_game != null, "terminal release AI fixture starts")
	if release_game != null:
		var release_player: Dictionary = release_game.state.players[0]
		release_player["prison_days"] = 128
		release_player["position"] = release_game._status_node_index("prison")
		release_player["previous_position"] = -1
		release_game.state["current_player"] = 0
		release_game.state["phase"] = "await_roll"
		var release_result: Dictionary = release_game.run_ai_turn()
		expect(bool(release_result.get("ok", false)), "AI completes terminal release and resumed roll")
		expect(int(release_player.prison_days) == 0, "AI clears terminal prison marker before normal roll")
		expect(has_event(release_game, "status_released", "prison"), "AI terminal release is logged")
		valid(release_game, "terminal release AI save")

	_finish()


func _finish() -> void:
	print("Status AI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
