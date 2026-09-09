extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/news_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func scenario(count: int) -> void:
	var game: Object = Fixture.new_game(541212, count)
	check(game != null, "public tax fixture constructs")
	if game == null: return
	for id in range(count):
		game.state.players[id].deposit = 0
		game.state.players[id].cash = 100000
	game.state.bank.deposits = 0
	game.state.players[0].cash = 1
	for entry in [[2, 0, 5], [3, 1, 1]]:
		var tile: Dictionary = game.state.board[entry[0]]
		tile.owner = entry[1]
		tile.building_level = entry[2]
		game.state.players[entry[1]].properties.append(entry[0])
		game._update_tile_rent(tile)
	game._recalculate_property_values()
	var target: int = int(game.state.board.back().index)
	game.state.players[0].position = int(game.state.board[target].adjacent[0])
	game.state.players[0].previous_position = -1
	var order: Array = [12]
	for id in range(36):
		if id != 12: order.append(id)
	game.state.news = {"order": order, "cursor": 0, "draw_count": 0, "last": {}}
	check(Inventory.grant_tool(game.state.inventory_supply, game.state.players[0].tools, "遙控骰子").get("ok", false), "public tax fixture grants remote die")
	game._set_action_options(0)
	check(Game.validate_save(game.to_dict()).get("ok", false), "public tax fixture validates before movement")
	check(Game.from_dict(JSON.parse_string(game.to_json())) != null, "public tax fixture reloads before movement")
	check(game.choose_action("use_tool", {"tool_id": "遙控骰子", "value": 1}).get("ok", false), "public tax remote die arms")
	var mirror: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	check(mirror != null, "armed movement reloads")
	if mirror == null: return
	var turn_before: int = int(game.state.turn)
	for candidate in [game, mirror]:
		check(candidate.roll().get("ok", false), "public tax roll succeeds")
		if candidate.state.phase == "await_route":
			check(candidate.choose_route(target).get("ok", false), "public tax route lands on news")
	check(not bool(game.state.players[0].alive), "public news tax bankrupts the moving actor")
	check(int(game.state.news.draw_count) == 1 and int(game.state.news.last.get("id", -1)) == 12, "public movement applies one land-tax news")
	if count == 2:
		check(game.state.phase == "game_over", "terminal news is not overwritten by movement completion")
		check(int(game.state.players[1].cash) == 100000, "terminal news stops before taxing winner's property")
	else:
		check(int(game.state.players[1].cash) == 99885, "news taxes later owner before admitting them")
		check(int(game.state.current_player) == 1 and game.state.phase == "await_roll", "movement hands off to next actor ready to roll")
		check(int(game.state.turn) == turn_before + 1, "news bankruptcy admits only once")
	check(Game.validate_save(game.to_dict()).get("ok", false), "public tax final state validates")
	check(game.to_json() == mirror.to_json(), "public tax JSON continuation is exact")
	check(Game.from_dict(JSON.parse_string(game.to_json())) != null, "public tax result reloads")

func _initialize() -> void:
	scenario(4)
	scenario(2)
	print("News public tax checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
