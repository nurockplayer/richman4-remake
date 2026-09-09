extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/god_card_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func stage(player_count: int) -> Object:
	var game: Object = Game.new_game_on_board(49002, player_count, Fixture.definition(), Fixture.new_game_options())
	check(game != null, "pre-roll wealth-god fixture starts")
	if game == null:
		return null
	game.state.players[0].position = 1
	game.state.players[0].previous_position = -1
	game.state.players[1].cash = 0
	game.state.bank.deposits -= int(game.state.players[1].deposit)
	game.state.players[1].deposit = 0
	game.state.god_objects = [{"id":1,"owner":-1,"node":2,"days":0}]
	for card in game.state.players[0].cards.duplicate():
		check(Inventory.consume_card(game.state.inventory_supply, game.state.players[0].cards, card).get("ok", false), "return competing fixture card")
	check(Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, "請神符").get("ok", false), "grant AI summon card")
	game.set_player_ai(0, true)
	game._set_action_options(0)
	var validation: Dictionary = Game.validate_save(game.to_dict())
	check(validation.get("ok", false), "pre-roll fixture validates: " + str(validation.get("errors", [])))
	return game

func _initialize() -> void:
	for use_match_api in [false, true]:
		var game: Object = stage(2)
		if game == null:
			continue
		var mirror: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		check(mirror != null, "terminal AI fixture reloads")
		var result: Dictionary = game.run_ai_match(1) if use_match_api else game.run_ai_turn()
		check(game.state.phase == "game_over" and int(game.state.winner) == 0, "pre-roll summon immediately wins the match")
		check(not game.state.players[1].alive, "wealth god bankrupts the final opponent")
		check(result.get("ok", false), "completed pre-roll terminal effect reports success")
		if use_match_api:
			check(int(result.get("completed_turns", -1)) == 1, "match API counts the completed terminal turn")
		else:
			check(result.get("completed", false), "turn API reports completion after terminal effect")
		check(game.state.last_roll.is_empty(), "terminal card effect does not roll dice")
		check(Game.validate_save(game.to_dict()).get("ok", false), "terminal AI state remains saveable")
		if mirror != null:
			var replay: Dictionary = mirror.run_ai_match(1) if use_match_api else mirror.run_ai_turn()
			check(replay.get("ok", false), "loaded terminal AI turn reports success")
			check(game.to_json() == mirror.to_json(), "terminal effect replays exactly")
	var continuation: Object = stage(3)
	if continuation != null:
		var result: Dictionary = continuation.run_ai_turn()
		check(result.get("ok", false) and result.get("completed", false), "nonterminal pre-roll summon still completes normal movement")
		check(not continuation.state.players[1].alive and continuation.state.players[2].alive, "nonterminal effect removes only insolvent opponent")
		check(continuation.state.phase != "game_over" and int(continuation.state.current_player) == 2, "nonterminal turn advances to surviving opponent once")
		check(Game.validate_save(continuation.to_dict()).get("ok", false), "nonterminal AI continuation remains saveable")
	print("God card AI terminal checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
