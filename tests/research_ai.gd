extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/research_fixture.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var options: Dictionary = Fixture.new_game_options()
	options.day_limit = 30
	var game: Object = Game.new_game_on_board(8522, 4, Fixture.definition(), options)
	expect(game != null, "research AI fixture starts v12")
	if game == null:
		print("Research AI checks: %d, failures: %d" % [checks, failures]); quit(1); return
	game.state.god_objects = []
	for id in range(4): game.set_player_ai(id, true)
	game.state.players[0].position = 1
	game.state.players[0].previous_position = 0
	game.state.players[0].properties = [1]
	game.state.phase = "await_action"
	game.state.last_roll = [1]
	game.state.last_total = 1
	game.state.last_roll_total = 1
	game.state.property_action_used = true
	game._update_facility_records(1, {"owner": 0, "facility_type": 4, "building_level": 3})
	game._recalculate_property_values()
	game._set_action_options(0)
	expect(Game.validate_save(game.to_dict()).get("ok", false), "AI research fixture is valid")
	var mirror: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(mirror != null, "AI research fixture reloads")
	if mirror != null:
		var result: Dictionary = game.run_ai_turn()
		var other: Dictionary = mirror.run_ai_turn()
		expect(result.get("ok", false) and result.get("completed", false), "AI selects research and ends its turn")
		expect(other.get("ok", false) and game.to_json() == mirror.to_json(), "research AI decisions replay exactly")
		expect(game.state.board[1].research_tool == 3, "AI picks highest product allowed by current level")
		expect(game.state.board[1].research_turns == 5, "AI does not decrement its new job on outgoing turn")
		var match_result: Dictionary = game.run_ai_match(200)
		expect(match_result.get("ok", false) and game.state.phase == "game_over" and game.state.elapsed == 30, "research AI finishes thirty days")
		expect(Game.validate_save(game.to_dict()).get("ok", false), "completed research match remains loadable")
	print("Research AI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
