extends SceneTree
## Reads the existing private catalog without materializing source assets.
const Maps = preload("res://game/content/original_maps.gd")
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		check(false, "Provide the existing owner-authorized map catalog")
		quit(1)
		return
	var catalog := Maps.load_catalog(args[0], true)
	check(catalog.get("ok", false), "existing catalog loads")
	if not catalog.get("ok", false):
		quit(1)
		return
	var map_count := 0
	for definition in catalog.maps.slice(0, 2):
		var game := Game.new_game_on_board(505013, 4, definition, {"original_inventory":true,"original_facilities":true,"original_gods":true,"original_companies":true,"original_statuses":true,"original_hazards":true,"original_property_cards":true,"original_remodel":true,"original_research":true,"original_building_cards":true,"start_date":{"year":1998,"month":1,"day":1}})
		check(game != null, "source game starts")
		if game == null:
			continue
		map_count += 1
		var target_id := -1
		for tile in game.state.board:
			if tile.get("kind", "") == "property":
				target_id = int(tile.index)
				break
		check(target_id >= 0, "source map has a housing landing")
		if target_id < 0:
			continue
		var player: Dictionary = game.state.players[0]
		check(Inventory.grant_tool(game.state.inventory_supply, player.tools, "汽車").get("ok", false), "stage source car")
		check(game.set_vehicle("car", 2).get("ok", false), "source actor equips car with two dice")
		check(Inventory.grant_tool(game.state.inventory_supply, player.tools, "工程車").get("ok", false), "stage source engineering tool")
		game.state.god_objects = []
		player.position = target_id
		player.previous_position = -1
		player.cash = 200000
		var target: Dictionary = game.state.board[target_id]
		target.owner = 1
		target.building_level = 2
		game.state.players[1].properties.append(target_id)
		game._update_tile_rent(target)
		game._recalculate_property_values()
		game.state.phase = "await_action"
		game.state.last_roll = [1]
		game.state.last_total = 1
		game.state.last_roll_total = 1
		game._set_action_options(0)
		var validation: Dictionary = Game.validate_save(game.to_dict())
		check(validation.get("ok", false), "source staged fixture validates: " + str(validation.get("errors", [])))
		check(game.choose_action("use_tool", {"tool_id":"工程車"}).get("ok", false), "source engineering action succeeds")
		check(player.vehicle == "engineering" and int(player.dice_count) == 1, "source engineering uses one die")
		check(game.end_turn().get("ok", false), "source engineering landing settles")
		check(int(target.building_level) == 0 and int(target.owner) == 1, "source landing clears building and preserves ownership")
		check(Game.validate_save(game.to_dict()).get("ok", false), "source post-landing state validates")
		for player_id in range(4):
			game.set_player_ai(player_id, true)
		var mirror: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		check(mirror != null, "source state reloads")
		if mirror == null:
			continue
		var turns := 0
		for _turn in range(32):
			if game.state.phase == "game_over":
				break
			var result: Dictionary = game.run_ai_turn()
			var replay: Dictionary = mirror.run_ai_turn()
			check(result.get("ok", false) and replay.get("ok", false), "source AI and replay complete a turn")
			check(game.to_json() == mirror.to_json(), "source continuation is deterministic")
			check(Game.validate_save(game.to_dict()).get("ok", false), "source continuation stays valid")
			turns += 1
		print("Engineering source %s version=%d turns=%d" % [definition.id, int(game.state.version), turns])
	check(map_count == 2, "two source maps exercised")
	print("Engineering source acceptance: %d maps, %d failures" % [map_count, failures])
	quit(1 if failures else 0)
