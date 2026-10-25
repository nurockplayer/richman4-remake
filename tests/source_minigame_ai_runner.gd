extends SceneTree

const Core = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	var definition := _definition()
	if definition.is_empty():
		print("PRECONDITION_UNMET synthetic source minigame fixture")
		quit(2)
		return
	_test_public_api(definition)
	_test_public_ai_runner(definition)
	_test_ai_and_trustee_shortcuts(definition)
	_test_human_pending_gate(definition)
	_test_finished_human_pending_gate(definition)
	_test_public_new_game_roll_route(definition)
	print("Source minigame AI runner checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _definition() -> Dictionary:
	var raw: Dictionary = Fixture.make()
	# Keep the fixture asset-free while exercising the same source event codes
	# used by the installed catalog. Existing housing nodes keep the graph
	# playable and make this safe for public CI.
	for entry in [[1, 6], [2, 7], [4, 8]]:
		var node: Dictionary = raw.nodes[int(entry[0])]
		node.merge({
			"kind": "unsupported",
			"type_and_idx": 0,
			"event_code": int(entry[1]),
			"source_status_bits": int(entry[1]),
		}, true)
	var normalized: Dictionary = Maps.normalize_map(raw, false)
	return normalized.definition if bool(normalized.get("ok", false)) else {}


func _new_game(definition: Dictionary, seed_value: int = 1701, player_count: int = 4) -> Object:
	var game: Object = Core.new_game_on_board(seed_value, player_count, definition, {})
	# Isolate settlement cash from the unrelated legacy AI stock heuristic,
	# which legitimately invests when cash >= 3000 during turn continuation.
	if game != null:
		game.state.players[0].cash = 2000
	return game


func _event_node(game: Object, event_code: int) -> int:
	for index in range(game.state.board.size()):
		var tile: Dictionary = game.state.board[index]
		if int(tile.get("event_code", 0)) == event_code and int(tile.get("type_and_idx", -1)) == 0:
			return index
	return -1


func _admit_event(game: Object, event_code: int, player_id: int, animation: bool) -> Dictionary:
	var node := _event_node(game, event_code)
	_expect(node >= 0, "synthetic source event %d exists" % event_code)
	if node < 0:
		return {}
	var player: Dictionary = game.state.players[player_id]
	player.position = node
	game.state.current_player = player_id
	game.state.phase = "await_action"
	game.configure_minigames(animation)
	game._resolve_landing(player_id)
	var snapshot: Dictionary = game.minigame_snapshot()
	_expect(game.state.phase == "await_minigame", "source event %d enters pending minigame phase" % event_code)
	return snapshot


func _set_ai(game: Object, player_id: int = 0) -> void:
	for player in game.state.players:
		game.set_player_ai(int(player.id), int(player.id) != player_id)
	game.set_player_ai(player_id, true)


func _set_trustee(game: Object, player_id: int = 0) -> void:
	var rows: Array = game.trustee_rows()
	for row in rows:
		row.trustee = int(row.player_id) == player_id
	_expect(game.apply_trustee_settings(rows), "public trustee settings commit")


func _event_count(game: Object, event_kind: String) -> int:
	var count := 0
	for event in game.state.event_log:
		if str(event.get("type", "")) == event_kind:
			count += 1
	return count


func _test_public_api(definition: Dictionary) -> void:
	var game := _new_game(definition, 1701, 2)
	_expect(game != null and game.has_method("run_ai_match") and game.has_method("run_ai_turn"), "public AI runner APIs exist")
	if game == null:
		return
	_set_ai(game)
	var snapshot := _admit_event(game, 6, 0, true)
	_expect(bool(snapshot.get("shortcut", false)) and bool(snapshot.get("finished", false)), "AI shortcut is admitted already finished")
	game.state.players[1].alive = false
	game.state.players[1].bankrupt = true
	var reward := int(snapshot.get("reward", -1))
	_expect(reward >= 50 and reward <= 69, "AI shortcut reward uses source 50-69 range")
	var cash := int(game.state.players[0].cash)
	var points := int(game.state.players[0].points)
	var result: Dictionary = game.run_ai_match(1)
	_expect(bool(result.get("ok", false)), "run_ai_match completes a finished shortcut")
	_expect(result.get("awaiting_response", false) == false and int(result.get("completed_turns", -1)) == 1, "completed shortcut counts one real AI turn")
	_expect(game.state.phase == "game_over" and int(game.state.winner) == 0, "AI runner advances actor and phase after minigame return")
	_expect(int(game.state.players[0].points) == points + reward, "shortcut awards points exactly once")
	_expect(int(game.state.players[0].cash) == cash, "shortcut does not change cash")
	_expect(_event_count(game, "minigame_completed") == 1, "shortcut emits one completion event")
	var completion: Dictionary = {}
	for event in game.state.event_log:
		if str(event.get("type", "")) == "minigame_completed":
			completion = event
	_expect(int(completion.get("source_points", -1)) == reward, "shortcut completion keeps admitted RNG reward")
	var after: String = game.to_json()
	var duplicate: Dictionary = game.finish_minigame(int(snapshot.get("encounter_id", -1)))
	_expect(not bool(duplicate.get("ok", false)) and game.to_json() == after, "duplicate completion is inert")


func _test_public_ai_runner(definition: Dictionary) -> void:
	for event_code in [6, 7, 8]:
		for mode in ["ai", "trustee"]:
			var seed_value: int = 2100 + int(event_code)
			var game := _new_game(definition, seed_value)
			_set_ai(game)
			if mode == "trustee":
				_set_trustee(game)
			var snapshot := _admit_event(game, event_code, 0, true)
			var reward := int(snapshot.get("reward", -1))
			var points := int(game.state.players[0].points)
			var cash := int(game.state.players[0].cash)
			var encounter_id := int(snapshot.get("encounter_id", -1))
			# A second identical admission is an oracle for legitimate end-turn RNG
			# consumption. The public runner remains the behavior under test.
			var expected := _new_game(definition, seed_value)
			_set_ai(expected)
			if mode == "trustee":
				_set_trustee(expected)
			var expected_snapshot := _admit_event(expected, event_code, 0, true)
			expected.finish_minigame(int(expected_snapshot.get("encounter_id", -1)))
			expected.run_ai_turn()
			var result: Dictionary = game.run_ai_match(1)
			_expect(not bool(result.get("ok", true)) and int(result.get("completed_turns", -1)) == 1, "%s %d public runner completes one real turn" % [mode, event_code])
			_expect(not bool(result.get("awaiting_response", false)), "%s %d public runner does not wait after shortcut" % [mode, event_code])
			_expect(game.state.phase == "await_roll" and int(game.state.current_player) == 1, "%s %d public runner advances to actor1 await_roll" % [mode, event_code])
			_expect(int(game.state.players[0].points) == points + reward, "%s %d public runner awards points once" % [mode, event_code])
			_expect(int(game.state.players[0].cash) == cash, "%s %d public runner leaves cash unchanged" % [mode, event_code])
			_expect(_event_count(game, "minigame_completed") == 1, "%s %d public runner emits one completion" % [mode, event_code])
			var completion: Dictionary = {}
			for event in game.state.event_log:
				if str(event.get("type", "")) == "minigame_completed":
					completion = event
			_expect(int(completion.get("source_points", -1)) == reward, "%s %d keeps admitted RNG reward" % [mode, event_code])
			_expect(int(game.state.get("rng_state", 0)) == int(expected.state.get("rng_state", 0)) and str(game.state.get("rng_state_text", "")) == str(expected.state.get("rng_state_text", "")), "%s %d consumes only legitimate end-turn RNG" % [mode, event_code])
			var after: String = game.to_json()
			var duplicate: Dictionary = game.finish_minigame(encounter_id)
			_expect(not bool(duplicate.get("ok", false)) and game.to_json() == after, "%s %d duplicate public completion is inert" % [mode, event_code])


func _test_ai_and_trustee_shortcuts(definition: Dictionary) -> void:
	for event_code in [6, 7, 8]:
		for mode in ["ai", "trustee"]:
			var game := _new_game(definition, 1800 + event_code)
			_set_ai(game)
			if mode == "trustee":
				_set_trustee(game)
			var snapshot := _admit_event(game, event_code, 0, true)
			var turn_result: Dictionary = game.run_ai_turn()
			_expect(bool(turn_result.get("ok", false)) and bool(turn_result.get("awaiting_response", false)), "%s %d run_ai_turn waits for shortcut result" % [mode, event_code])
			_expect(int(turn_result.get("completed", 1)) == 0, "%s %d shortcut is not counted before finish" % [mode, event_code])
			_expect(game.state.phase == "await_minigame" and int(game.state.current_player) == 0, "%s %d preserves pending actor" % [mode, event_code])
			_expect(game.minigame_snapshot() == snapshot, "%s %d run_ai_turn does not recalculate shortcut" % [mode, event_code])
			_expect(bool(game.finish_minigame(int(snapshot.get("encounter_id", -1))).get("ok", false)), "%s %d delayed finish accepts admitted result" % [mode, event_code])
			var next_turn: Dictionary = game.run_ai_turn()
			_expect(bool(next_turn.get("ok", false)) and bool(next_turn.get("completed", false)), "%s %d run_ai_turn completes after delayed finish" % [mode, event_code])
			_expect(game.state.phase == "await_roll" and int(game.state.current_player) != 0, "%s %d delayed finish advances actor and phase" % [mode, event_code])


func _test_human_pending_gate(definition: Dictionary) -> void:
	var game := _new_game(definition, 1908)
	# Player zero is the original interactive human; other actors remain AI.
	for player in game.state.players:
		var player_id := int(player.id)
		game.set_player_ai(player_id, player_id != 0)
	var snapshot := _admit_event(game, 8, 0, true)
	_expect(not bool(snapshot.get("shortcut", true)) and not bool(snapshot.get("finished", true)), "human event remains interactive")
	var before: String = game.to_json()
	var result: Dictionary = game.run_ai_match(20)
	_expect(not bool(result.get("ok", true)) and bool(result.get("awaiting_response", false)), "run_ai_match reports human minigame wait")
	_expect(int(result.get("completed_turns", -1)) == 0, "human wait does not count a completed turn")
	_expect(game.to_json() == before, "human pending gate preserves controls and state")
	_expect(game.minigame_snapshot() == snapshot, "human pending gate preserves interactive snapshot")


func _test_finished_human_pending_gate(definition: Dictionary) -> void:
	var game := _new_game(definition, 1910)
	for player in game.state.players:
		var player_id := int(player.id)
		game.set_player_ai(player_id, player_id != 0)
	var snapshot := _admit_event(game, 7, 0, true)
	var encounter_id := int(snapshot.get("encounter_id", -1))
	for _tick in range(420):
		game.minigame_tick(encounter_id)
	snapshot = game.minigame_snapshot()
	_expect(not bool(snapshot.get("shortcut", true)) and bool(snapshot.get("finished", false)), "finished human minigame remains interactive")
	var before: String = game.to_json()
	var result: Dictionary = game.run_ai_match(20)
	_expect(not bool(result.get("ok", true)) and bool(result.get("awaiting_response", false)) and int(result.get("completed_turns", -1)) == 0, "finished human minigame still waits without counting a turn")
	_expect(game.to_json() == before and game.minigame_snapshot() == snapshot, "finished human minigame is not auto-finished or rerolled")


func _drive_public_route(game: Object) -> bool:
	for _step in range(20):
		if game.state.get("phase", "") != "await_route":
			return true
		var options: Array = game.state.get("route_options", [])
		if options.is_empty():
			return false
		var result: Dictionary = game.choose_route(int(options[0]))
		if not bool(result.get("ok", false)):
			return false
	return game.state.get("phase", "") != "await_route"


func _test_public_new_game_roll_route(definition: Dictionary) -> void:
	var found_seed := -1
	for seed_value in range(1, 21):
		var game := _new_game(definition, seed_value)
		if game == null or game.state.get("phase", "") != "await_roll":
			continue
		var result: Dictionary = game.roll()
		if not bool(result.get("ok", false)) or not _drive_public_route(game):
			continue
		if game.state.get("phase", "") == "await_minigame":
			found_seed = seed_value
			_expect(int(game.state.current_player) == 0, "normal NEWGAME public roll keeps actor zero")
			_expect(not game.minigame_snapshot().is_empty(), "normal NEWGAME public roll admits source encounter")
			break
	_expect(found_seed >= 0, "bounded seed search finds a normal NEWGAME to public roll source route")
