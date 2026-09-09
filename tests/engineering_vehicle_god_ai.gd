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
	for scenario in [[12,2,false],[10,1,false],[10,2,true]]:
		var god_id: int = int(scenario[0])
		var level: int = int(scenario[1])
		var useful: bool = bool(scenario[2])
		var game: Object = stage(1,level)
		if game == null:continue
		game.state.god_objects = [{"id":god_id,"node":3,"owner":0,"days":7}]
		game.state.players[0].god_id = god_id
		game._set_action_options(0)
		check(Game.validate_save(game.to_dict()).get("ok",false),"god AI fixture validates before turn")
		var mirror: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		check(mirror != null,"god AI fixture reloads")
		var result: Dictionary = game.run_ai_turn()
		check(result.get("ok",false) and result.get("completed",false),"god AI action completes")
		check(int(game.state.players[0].tools.get("工程車",0)) == (1 if useful else 2),"god AI spends only when a building survives the prior god effect")
		check(game.state.players[0].vehicle == ("engineering" if useful else "walking"),"god AI avoids unnecessary engineering activation")
		check(int(game.state.board[3].owner) == (0 if god_id == 12 else 1),"prior god effect determines owner")
		check(int(game.state.board[3].building_level) == (level if god_id == 12 else 0),"god and engineering resolve the expected final building")
		check(Game.validate_save(game.to_dict()).get("ok",false),"god AI final state remains saveable")
		if mirror != null:
			check(mirror.run_ai_turn().get("ok",false),"god AI JSON replay completes")
			check(mirror.to_json() == game.to_json(),"god AI JSON replay is exact")
	print("Engineering god AI checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
