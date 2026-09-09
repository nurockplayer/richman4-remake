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
func make_game(owner: int, level: int, turns: int) -> Object:
	var game: Object = Game.new_game_on_board(39712, 4, Fixture.definition(), Fixture.new_game_options())
	expect(game != null, "admission fixture starts v12")
	if game == null: return null
	game.state.god_objects = []
	game.state.players[owner].properties = [1]
	game._update_facility_records(1, {"owner": owner, "facility_type": 4, "building_level": level, "research_tool": 1, "research_turns": turns})
	game.state.phase = "await_action"
	game.state.last_roll = [1]
	game.state.last_total = 1
	game.state.last_roll_total = 1
	game._recalculate_property_values()
	game._set_action_options(0)
	return game
func _initialize() -> void:
	var ai: Object = make_game(0, 3, 0)
	if ai != null:
		ai.state.players[0].position = 1
		ai.set_player_ai(0, true)
		ai._set_action_options(0)
		expect(ai.run_ai_turn().get("completed", false), "AI completes normal laboratory visit")
		for index in [1, 6]:
			expect(ai.state.board[index].building_level == 4, "AI performs available normal lab upgrade")
			expect(ai.state.board[index].research_tool == 4 and ai.state.board[index].research_turns == 5, "AI chooses highest product after construction")
		expect(Game.from_dict(JSON.parse_string(ai.to_json())) != null, "AI research visit reloads")
	var zero: Object = make_game(1, 0, 3)
	if zero != null:
		expect(Game.validate_save(zero.to_dict()).get("ok", false), "owned zero-level pending lab is valid before admission")
		expect(zero.end_turn().get("ok", false), "incoming owner with zero-level lab is admitted")
		expect(zero.state.board[1].research_turns == 0 and zero.state.board[6].research_turns == 0, "zero-level lab cancels invalid product on owner admission")
	var complete: Object = make_game(1, 1, 1)
	if complete != null:
		var supply: Dictionary = complete.state.inventory_supply.duplicate(true)
		var before: int = int(complete.state.players[1].tools.get("機器工人", 0))
		expect(complete.end_turn().get("ok", false), "incoming owner completes research")
		expect(complete.state.players[1].tools.get("機器工人", 0) == before + 1, "admission grants exactly one product")
		expect(complete.state.inventory_supply == supply, "production preserves shared supply")
		var found := false
		for event in complete.state.event_log:
			if event.get("type", "") == "research_produced" and event.get("granted", false): found = true
		expect(found, "completed production emits the agreed observable event")
	for options in [Fixture.v11_game_options(), Fixture.new_game_options()]:
		var game: Object = Game.new_game_on_board(39713, 4, Fixture.definition(), options)
		expect(game != null, "numeric alias fixture starts")
		if game == null: continue
		var data: Dictionary = game.to_dict()
		data.board[6].building_level = float(data.board[6].building_level)
		expect(Game.validate_save(data).get("ok", false), "equivalent integer JSON numbers preserve alias compatibility")
		expect(Game.from_dict(data) != null, "equivalent numeric aliases reload")
	print("Research admission checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
