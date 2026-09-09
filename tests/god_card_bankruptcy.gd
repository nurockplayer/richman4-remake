extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/god_card_fixture.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	for god_id in [5, 6]:
		for phase in ["await_roll", "await_action"]:
			for player_count in [2, 3]:
				probe(god_id, phase, player_count)
	print("God card bankruptcy checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func probe(god_id: int, phase: String, player_count: int) -> void:
	var game: Object = Game.new_game_on_board(49001, player_count, Fixture.definition(), Fixture.new_game_options())
	check(game != null, "bankruptcy fixture starts")
	if game == null:
		return
	game.state.players[0].position = 1
	game.state.players[0].previous_position = -1
	game.state.players[0].cash = 0
	game.state.bank.deposits -= int(game.state.players[0].deposit)
	game.state.players[0].deposit = 0
	game.state.phase = phase
	if phase == "await_action":
		game.state.last_roll = [1]
		game.state.last_total = 1
		game.state.last_roll_total = 1
	game.state.god_objects = [{"id":god_id,"owner":-1,"node":2,"days":0}]
	check(Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, "請神符").get("ok", false), "grant summon card")
	game.call("_set_action_options", 0)
	var prefix := "god%d %s players%d: " % [god_id, phase, player_count]
	var fixture_validation: Dictionary = Game.validate_save(game.to_dict())
	check(fixture_validation.get("ok", false), prefix + "pre-action fixture validates: " + str(fixture_validation))
	var before_turn: int = int(game.state.turn)
	var result: Dictionary = game.choose_action("use_card", {"card_id":"請神符", "visible_tile_ids":[2]})
	check(result.get("ok", false), prefix + "summon succeeds")
	check(not game.state.players[0].alive, prefix + "immediate poor-god charge bankrupts caster")
	check(Game.validate_save(game.to_dict()).get("ok", false), prefix + "result remains saveable")
	var loaded: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	check(loaded != null, prefix + "JSON reload succeeds")
	if player_count == 2:
		check(game.state.phase == "game_over", prefix + "last survivor ends match")
		check(int(game.state.winner) == 1, prefix + "survivor wins")
	else:
		check(int(game.state.current_player) == 1, prefix + "next alive player owns turn")
		check(game.state.phase == "await_roll", prefix + "next turn is playable")
		check(int(game.state.turn) == before_turn + 1, prefix + "turn advances exactly once")
		check(not game.state.action_options.is_empty(), prefix + "next player retains controls")
		if loaded != null:
			var next_result: Dictionary = game.run_ai_turn()
			var replay_result: Dictionary = loaded.run_ai_turn()
			check(next_result.get("ok", false) and replay_result.get("ok", false), prefix + "next actor completes a turn")
			check(game.to_json() == loaded.to_json(), prefix + "continuation is deterministic")
