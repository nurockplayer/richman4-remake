extends SceneTree
## Reads the sole existing catalog; does not materialize original assets.
const Maps = preload("res://game/content/original_maps.gd")
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/news_fixture.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): check(false, "existing catalog path required"); quit(1); return
	var catalog := Maps.load_catalog(args[0], true)
	check(catalog.get("ok", false), "existing source catalog loads")
	if not catalog.get("ok", false): quit(1); return
	var map_count := 0
	for definition in catalog.maps.slice(0, 2):
		var game := Game.new_game_on_board(561355, 4, definition, Fixture.new_game_options())
		check(game != null, "source fate game constructs")
		if game == null: continue
		map_count += 1
		game.state.god_objects = []
		for player_id in range(4): game.set_player_ai(player_id, false)
		var target := -1
		for tile in game.state.board:
			if int(tile.get("type_and_idx", -1)) == 0 and int(tile.get("event_code", -1)) == 3:
				target = int(tile.index)
				break
		check(target >= 0, "source map has fate node")
		if target < 0: continue
		var fate_tile: Dictionary = game.state.board[target]
		check(fate_tile.kind == "fate", "source fate classification is enabled")
		var player: Dictionary = game.state.players[0]
		player.position = int(fate_tile.adjacent[0])
		player.previous_position = -1
		player.cash = 200000
		var order: Array = [20]
		for id in range(37):
			if id != 20: order.append(id)
		game.state.fate = {"order": order, "cursor": 0, "draw_count": 0, "last": {}}
		check(Inventory.grant_tool(game.state.inventory_supply, player.tools, "遙控骰子").get("ok", false), "source fixture grants one remote die")
		game._set_action_options(0)
		check(Game.validate_save(game.to_dict()).get("ok", false), "source fixture validates before roll")
		check(game.choose_action("use_tool", {"tool_id": "遙控骰子", "value": 1}).get("ok", false), "source remote die uses public action")
		check(game.roll().get("ok", false), "source fate roll succeeds")
		if game.state.phase == "await_route":
			check(game.choose_route(target).get("ok", false), "source route selects adjacent fate")
		check(int(player.position) == target, "public movement actually lands on fate")
		check(int(player.cash) == 201000, "actual source landing credits 1000 cash")
		check(int(game.state.fate.draw_count) == 1 and int(game.state.fate.last.get("id", -1)) == 20, "source landing records exactly one applied fate")
		check(Game.validate_save(game.to_dict()).get("ok", false), "source post-fate state validates")
		for player_id in range(4): game.set_player_ai(player_id, true)
		var mirror: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		check(mirror != null, "source fate JSON loads")
		if mirror == null: continue
		var turns := 0
		for turn in range(32):
			if game.state.phase == "game_over": break
			var result: Dictionary = game.run_ai_turn()
			var replay: Dictionary = mirror.run_ai_turn()
			check(result.get("ok", false) and replay.get("ok", false), "source fate AI turn completes")
			check(game.to_json() == mirror.to_json(), "source fate JSON continuation matches")
			check(Game.validate_save(game.to_dict()).get("ok", false), "source fate AI save remains valid")
			turns += 1
		print("Fate source %s version=%d turns=%d" % [definition.id, int(game.state.version), turns])
	check(map_count == 2, "two source fate maps exercised")
	print("Fate source acceptance: %d maps, %d failures" % [map_count, failures])
	quit(1 if failures else 0)
