extends SceneTree

## Old saves classify source event6/7/8 nodes and keep loading. A pending
## minigame session is never a save file, so load always restores a playable
## state instead of a session without its model.

const Core = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const UserPaths = preload("res://game/platform/user_paths.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	var definition := _definition()
	if definition.is_empty():
		print("PRECONDITION_UNMET synthetic source minigame fixture")
		quit(2)
		return
	_test_old_save_loading(definition)
	_test_pending_session_is_not_saveable(definition)
	print("Source minigame save checks: %d, failures: %d" % [checks, failures])
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


func _test_old_save_loading(definition: Dictionary) -> void:
	var game: Object = Core.new_game_on_board(3101, 2, definition, {})
	_expect(game != null, "synthetic source board constructs")
	if game == null:
		return
	# Pre-minigame saves classified these event roads as unsupported.
	var data: Dictionary = game.to_dict()
	var migrated_nodes := 0
	for tile in data.board:
		if int(tile.get("event_code", -1)) in [6, 7, 8] and int(tile.get("type_and_idx", -1)) == 0:
			tile["kind"] = "unsupported"
			migrated_nodes += 1
	_expect(migrated_nodes == 3, "old save contains three unsupported source events")
	var loaded: Object = Core.from_dict(data)
	_expect(loaded != null, "old save loads")
	if loaded == null:
		return
	for event_code in [6, 7, 8]:
		var node := _event_node(loaded, event_code)
		_expect(node >= 0 and str(loaded.state.board[node].get("kind", "")) == "minigame", "event %d migrates to minigame without reward" % event_code)


func _test_pending_session_is_not_saveable(definition: Dictionary) -> void:
	var game: Object = Core.new_game_on_board(3102, 2, definition, {})
	_expect(game != null, "pending-session board constructs")
	if game == null:
		return
	var node := _event_node(game, 7)
	_expect(node >= 0, "source balloon node exists")
	game.state.current_player = 0
	game.state.players[0].position = node
	game.state.phase = "await_action"
	game.configure_minigames(true)
	game._resolve_landing(0)
	_expect(str(game.state.phase) == "await_minigame", "landing admits the pending session")
	_expect(not game.save_to_path(UserPaths.resolve("user://source_minigame_pending.json")), "pending session refuses a direct save")
	_expect(Core.from_dict(game.to_dict()) == null, "pending session is not a loadable save")
	var before: String = game.to_json()
	_expect(not game.choose_action("end_turn").get("ok", false) and game.to_json() == before, "pending session excludes ordinary turn actions")
	var encounter_id := int(game.minigame_snapshot().get("encounter_id", -1))
	for _tick in range(420):
		game.minigame_tick(encounter_id)
	_expect(bool(game.minigame_snapshot().get("finished", false)), "interactive model reaches its deadline without a host tick loop")
	_expect(bool(game.finish_minigame(encounter_id).get("ok", false)), "finished session returns through the validated boundary")
	_expect(str(game.state.phase) == "await_action", "return restores ordinary actions")
	var returned: Dictionary = game.to_dict()
	_expect(bool(Core.validate_save(returned).get("ok", false)) and Core.from_dict(returned) != null, "returned state is saveable and loadable again")
