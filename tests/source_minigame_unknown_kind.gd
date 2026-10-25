extends SceneTree

## A minigame node whose source code has no model must not open an
## unanswerable pending phase: it resolves as a no-op landing.

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
	_test_unknown_kind_landing(definition, true)
	_test_unknown_kind_landing(definition, false)
	print("Source minigame unknown kind checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _definition() -> Dictionary:
	var raw: Dictionary = Fixture.make()
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


func _event_node(game: Object, event_code: int) -> int:
	for index in range(game.state.board.size()):
		var tile: Dictionary = game.state.board[index]
		if int(tile.get("event_code", 0)) == event_code and int(tile.get("type_and_idx", -1)) == 0:
			return index
	return -1


func _test_unknown_kind_landing(definition: Dictionary, animation: bool) -> void:
	var game: Object = Core.new_game_on_board(1801, 4, definition, {})
	_expect(game != null, "synthetic source board constructs")
	if game == null:
		return
	var setup := _event_node(game, 6)
	_expect(setup >= 0, "synthetic minigame node exists")
	if setup < 0:
		return
	# Keep the source kind but drop the recognised event code.
	game.state.board[setup].event_code = 0
	var player: Dictionary = game.state.players[0]
	player.position = setup
	game.state.current_player = 0
	game.state.phase = "await_action"
	game.configure_minigames(animation)
	var points_before: int = int(player.points)
	var rng_before: String = str(game._rng.state)
	game._resolve_landing(0)
	_expect(str(game.state.phase) != "await_minigame", "unknown kind never enters the pending minigame phase")
	_expect(game.state.current_player == 0 and bool(player.alive), "landing actor keeps the turn")
	_expect(int(player.points) == points_before and str(game._rng.state) == rng_before, "no-op landing awards no points and consumes no RNG")
	_expect(game.minigame_snapshot().is_empty(), "no pending snapshot exists for an unknown kind")
	_expect(not bool(game.finish_minigame(1).get("ok", false)), "no stale encounter can be finished")
	_expect(bool(game.end_turn().ok), "the turn can still end")
	_expect(str(game.state.phase) == "await_roll", "turn advances normally")
