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

func stage(owner_id: int, level: int) -> Object:
	var game: Object = Game.new_game_on_board(5050, 4, Fixture.definition(), Fixture.new_game_options())
	check(game != null, "AI fixture starts")
	if game == null:
		return null
	game.state.god_objects = []
	for player_id in range(4):
		game.set_player_ai(player_id, player_id == 0)
	var player: Dictionary = game.state.players[0]
	for card in player.cards.duplicate():
		check(Inventory.consume_card(game.state.inventory_supply, player.cards, card).get("ok", false), "return unused AI fixture card")
	for tool in player.tools.keys():
		check(Inventory.consume_tool(game.state.inventory_supply, player.tools, tool, int(player.tools[tool])).get("ok", false), "return unused AI fixture tool")
	check(Inventory.grant_tool(game.state.inventory_supply, player.tools, "工程車", 2).get("ok", false), "AI receives two research tools")
	check(Inventory.grant_tool(game.state.inventory_supply, player.tools, "汽車").get("ok", false), "AI holds car to test active-vehicle fallback")
	check(Inventory.grant_tool(game.state.inventory_supply, player.tools, "機車").get("ok", false), "AI holds motorcycle to test active-vehicle fallback")
	player.position = 3
	player.previous_position = -1
	player.cash = 0
	var tile: Dictionary = game.state.board[3]
	tile.owner = owner_id
	tile.building_level = level
	tile.is_chain_store = false
	if owner_id >= 0:
		game.state.players[owner_id].properties.append(3)
	game._update_tile_rent(tile)
	game._recalculate_property_values()
	game.state.phase = "await_action"
	game.state.last_roll = [1]
	game.state.last_total = 1
	game.state.last_roll_total = 1
	game.state.property_action_used = true
	game._set_action_options(0)
	var validation: Dictionary = Game.validate_save(game.to_dict())
	check(validation.get("ok", false), "AI fixture validates: " + str(validation.get("errors", [])))
	return game

func _initialize() -> void:
	for scenario in [[1, 3, true], [0, 3, false], [-1, 3, false], [1, 0, false]]:
		var game: Object = stage(int(scenario[0]), int(scenario[1]))
		if game == null:
			continue
		var useful: bool = bool(scenario[2])
		var mirror: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		check(mirror != null, "AI initial state reloads")
		var result: Dictionary = game.run_ai_turn()
		check(result.get("ok", false) and result.get("completed", false), "AI action turn completes")
		check(int(game.state.players[0].tools.get("工程車", 0)) == (1 if useful else 2), "AI spends engineering tool only for a built enemy landing")
		check(game.state.players[0].vehicle == ("engineering" if useful else "walking"), "AI activates only for a useful landing")
		check(int(game.state.board[3].building_level) == (0 if useful else int(scenario[1])), "AI demolition changes only the useful enemy building")
		check(int(game.state.board[3].owner) == int(scenario[0]), "engineering AI preserves ownership")
		check(Game.validate_save(game.to_dict()).get("ok", false), "AI turn remains saveable")
		if mirror != null:
			var replay: Dictionary = mirror.run_ai_turn()
			check(replay.get("ok", false) and replay.get("completed", false), "loaded AI action turn completes")
			check(game.to_json() == mirror.to_json(), "AI activation and demolition replay exactly")
		if useful and game.state.players[0].vehicle == "engineering":
			# Isolate the normal pre-roll tool selection from random movement. The
			# inventory deliberately holds both ordinary vehicles as alternatives.
			game.state.current_player = 0
			game.state.phase = "await_roll"
			game.state.last_roll = []
			game.state.last_total = 0
			game.state.last_roll_total = 0
			game._set_action_options(0)
			check(Game.validate_save(game.to_dict()).get("ok", false), "active pre-roll fallback fixture validates")
			var car_before: int = int(game.state.players[0].tools.get("汽車", 0))
			var bike_before: int = int(game.state.players[0].tools.get("機車", 0))
			game._ai_roll_action(0)
			check(game.state.players[0].vehicle == "engineering", "ordinary AI fallback retains active engineering vehicle")
			check(int(game.state.players[0].tools.get("汽車", 0)) == car_before and int(game.state.players[0].tools.get("機車", 0)) == bike_before, "fallback does not consume replacement vehicles")
	print("Engineering vehicle AI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
