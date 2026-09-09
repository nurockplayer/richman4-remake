extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/remodel_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func make_game() -> Object:
	var definition: Dictionary = Fixture.definition()
	definition.companies[0].company_type = 11
	var game: Object = Game.new_game_on_board(7511, 4, definition, Fixture.new_game_options())
	expect(game != null, "review v11 fixture starts")
	if game == null: return null
	game.state.god_objects = []
	game.state.players[0].stocks.s01 = 1
	game.state.companies[0].treasury -= 1
	game._update_company_owners()
	return game
func property(game: Object, tile_id: int, owner: int, level: int, chain: bool) -> void:
	var tile: Dictionary = game.state.board[tile_id]
	tile.owner = owner
	tile.building_level = level
	tile.is_chain_store = chain
	for player in game.state.players:
		player.properties.erase(tile_id)
	if owner >= 0: game.state.players[owner].properties.append(tile_id)
	game._update_tile_rent(tile)
	game._recalculate_property_values()
func valid(game: Object, label: String) -> void:
	game._set_action_options(int(game.state.current_player))
	var result: Dictionary = Game.validate_save(game.to_dict())
	expect(result.get("ok", false), label + " validates: " + str(result.get("errors", [])))
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null and restored.to_json() == game.to_json(), label + " reloads exactly")
func visit(game: Object, player_id: int) -> void:
	game.state.current_player = player_id
	game.state.players[player_id].position = 5
	game.state.players[player_id].previous_position = 4
	game.state.phase = "await_action"
	game._resolve_company_visit(player_id, game.state.board[5])
	game._set_action_options(player_id)
func _initialize() -> void:
	for player_id in [0, 1]:
		var game: Object = make_game()
		if game == null: continue
		property(game, 2, player_id, 1, true)
		property(game, 3, player_id, 1, false)
		visit(game, player_id)
		expect(game.get_company_upgrade_targets(player_id) == [3], "company excludes capped chain and retains normal house")
		var before: Dictionary = game.to_dict()
		expect(not game.choose_action("company_upgrade", {"tile_id": 2}).get("ok", false) and game.to_dict() == before, "company rejects chain without fee, state or RNG mutation")
		if game.state.company_service_pending == 0: visit(game, player_id)
		expect(game.choose_action("company_upgrade", {"tile_id": 3}).get("ok", false), "company can still improve normal house")
		expect(game.state.board[2].building_level == 1 and game.state.board[2].is_chain_store, "company leaves chain at one")
		valid(game, "company construction")
	var lone: Object = make_game()
	if lone != null:
		property(lone, 2, 0, 1, true)
		visit(lone, 0)
		expect(lone.state.company_service_pending == 0, "chain-only owner is not trapped in impossible company choice")
		var impossible: Dictionary = lone.to_dict()
		impossible.company_service_pending = 1
		impossible.action_options = ["company_upgrade"]
		expect(not Game.validate_save(impossible).get("ok", false) and Game.from_dict(impossible) == null, "save rejects pending company service with only capped chain")
		valid(lone, "chain-only company visit")
	var ai: Object = make_game()
	if ai != null:
		property(ai, 2, 0, 1, true)
		property(ai, 3, 0, 1, false)
		ai.set_player_ai(0, true)
		visit(ai, 0)
		expect(ai.run_ai_turn().get("completed", false), "AI completes pending construction with chain present")
		expect(ai.state.board[2].building_level == 1 and ai.state.board[3].building_level == 3, "AI chooses eligible normal house")
		valid(ai, "company AI")
	for creditor in [-1, -3, 1]:
		var game: Object = make_game()
		if game == null: continue
		property(game, 2, 0, 1, true)
		game.state.bank.deposits -= int(game.state.players[0].deposit)
		game.state.players[0].deposit = 0
		game.state.players[0].cash = 0
		game.state.phase = "await_roll"
		game._set_action_options(0)
		valid(game, "pre-bankruptcy")
		game._charge_amount(0, 1000000, creditor, "company" if creditor < -1 else "tax" if creditor == -1 else "rent")
		expect(not game.state.players[0].alive, "debt reaches actual bankruptcy")
		expect(game.state.board[2].is_chain_store == (creditor >= 0), "bank clears chain, player creditor preserves it")
		expect(game.state.board[2].building_level == (1 if creditor >= 0 else 0), "bank razes building, player creditor preserves it")
		valid(game, "bankruptcy")
	for god_id in [3, 4]:
		var game: Object = make_game()
		if game == null: continue
		property(game, 2, -1, 1, true)
		game.state.players[0].position = 2
		game.state.phase = "await_action"
		game.state.god_objects = [{"id": god_id, "node": 2, "owner": 0, "days": 3}]
		game.state.players[0].god_id = god_id
		game._set_action_options(0)
		valid(game, "pre-fortune acquisition")
		expect(game.choose_action("buy").get("ok", false), "fortune player buys unowned chain")
		expect(game.state.board[2].building_level == 1 and game.state.board[2].is_chain_store, "fortune bonus cannot exceed chain cap")
		valid(game, "fortune acquisition")
	print("Remodel review checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
