extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Base = preload("res://tests/fixtures/news_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func scenario(count: int) -> void:
	var definition: Dictionary = Base.definition()
	definition.board.back().event_code = 3
	definition.board.back().source_status_bits = 3
	definition.board.back().kind = Maps.classify_source_node(0, 3).kind
	var game: Object = Game.new_game_on_board(561212, count, definition, Base.new_game_options())
	game.state.god_objects = []
	for id in range(count): game.set_player_ai(id, false)
	check(game != null, "public fate fixture constructs")
	if game == null: return
	for id in range(count):
		game.state.players[id].deposit = 0
		game.state.players[id].cash = 100000
	game.state.bank.deposits = 0
	game.state.players[0].cash = 1
	var target: int = int(game.state.board.back().index)
	game.state.players[0].position = int(game.state.board[target].adjacent[0])
	game.state.players[0].previous_position = -1
	var order: Array = [30]
	for id in range(37):
		if id != 30: order.append(id)
	game.state.fate = {"order": order, "cursor": 0, "draw_count": 0, "last": {}}
	check(Inventory.grant_tool(game.state.inventory_supply, game.state.players[0].tools, "遙控骰子").get("ok", false), "public fate fixture grants remote die")
	game._set_action_options(0)
	check(Game.validate_save(game.to_dict()).get("ok", false), "public fate fixture validates before movement")
	check(Game.from_dict(JSON.parse_string(game.to_json())) != null, "public fate fixture reloads before movement")
	check(game.choose_action("use_tool", {"tool_id": "遙控骰子", "value": 1}).get("ok", false), "public fate remote die arms")
	var mirror: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	check(mirror != null, "armed movement reloads")
	if mirror == null: return
	var turn_before: int = int(game.state.turn)
	for candidate in [game, mirror]:
		check(candidate.roll().get("ok", false), "public fate roll succeeds")
		if candidate.state.phase == "await_route":
			check(candidate.choose_route(target).get("ok", false), "public fate route lands on fate")
	check(not bool(game.state.players[0].alive), "public fate charge bankrupts the moving actor")
	check(int(game.state.fate.draw_count) == 1 and int(game.state.fate.last.get("id", -1)) == 30, "public movement applies one 5000 cash expense")
	if count == 2:
		check(game.state.phase == "game_over", "terminal fate is not overwritten by movement completion")
		check(int(game.state.players[1].cash) == 100000, "fate does not charge winner")
	else:
		check(int(game.state.players[1].cash) == 100000, "fate leaves next actor cash unchanged")
		check(int(game.state.current_player) == 1 and game.state.phase == "await_roll", "movement hands off to next actor ready to roll")
		check(int(game.state.turn) == turn_before + 1, "fate bankruptcy admits only once")
	check(Game.validate_save(game.to_dict()).get("ok", false), "public fate final state validates")
	check(game.to_json() == mirror.to_json(), "public fate JSON continuation is exact")
	check(Game.from_dict(JSON.parse_string(game.to_json())) != null, "public fate result reloads")

func _initialize() -> void:
	scenario(4)
	scenario(2)
	print("Fate public charge checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
