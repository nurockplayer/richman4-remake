extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
const Movement = preload("res://game/ui/movement_presentation.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var game: Object = Game.new_game_on_board(1, 2, Maps.normalize_map(Fixture.make()).definition)
	game.state.players[0].position = 0
	game.state.players[0].previous_position = -1
	check(Game.validate_save(game.to_dict()).get("ok", false), "source-shaped input validates")
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	check(restored != null, "source-shaped input reloads")
	var before: Dictionary = game.to_dict()
	var restored_before: Dictionary = restored.to_dict()
	check(game.roll().get("ok", false) and restored.roll().get("ok", false), "fresh and loaded core both roll")
	var plan: Array = Movement.plan(before, game.to_dict())
	check(plan.size() == 1, "fresh graph roll provides its first edge")
	check(Movement.plan(restored_before, restored.to_dict()) == plan, "JSON-loaded game retains the same visible movement")
	check(restored.to_json() == game.to_json(), "presentation keeps JSON continuation exact")
	var source_before: Dictionary = before.duplicate(true)
	var source_after: Dictionary = game.to_dict()
	source_before.map_source["facilities"] = [{"id": 1, "owner": -1, "level": 0}]
	source_after.map_source["facilities"] = [{"id": 1, "owner": 0, "level": 1}]
	check(Movement.plan(source_before, source_after) == plan, "mutable facility records are not a map identity change")
	var loop_before := {
		"board_mode": "graph", "map_id": "loop", "event_log": [],
		"board": [{"index":0,"x":0,"y":0,"adjacent":[1,3]}, {"index":1,"x":1,"y":0,"adjacent":[0,2]}, {"index":2,"x":1,"y":1,"adjacent":[1,3]}, {"index":3,"x":0,"y":1,"adjacent":[0,2]}],
		"players": [{"id":0,"position":0}, {"id":1,"position":2}], "phase":"await_roll"
	}
	var loop_after := loop_before.duplicate(true)
	for i in range(4): loop_after.event_log.append({"type":"move","player_id":0,"from":i,"to":(i+1)%4,"steps":1})
	check(Movement.plan(loop_before, loop_after).size() == 4, "provable round trip animates despite unchanged final position")
	print("Movement continuation checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
