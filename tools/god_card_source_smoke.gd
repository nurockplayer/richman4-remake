extends SceneTree
## Read two maps from the existing owner-authorized catalog; no asset imports.
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
		check(false, "Provide the existing owner-authorized catalog path")
		quit(1)
		return
	var catalog := Maps.load_catalog(args[0], true)
	if not catalog.get("ok", false):
		check(false, str(catalog.get("error", "Catalog load failed")))
		quit(1)
		return
	var map_count := 0
	for definition in catalog.maps.slice(0, 2):
		var map_id := str(definition.id)
		var game := Game.new_game_on_board(4813, 4, definition, {"original_inventory":true,"original_facilities":true,"original_gods":true,"original_companies":true,"original_statuses":true,"original_hazards":true,"original_property_cards":true,"original_remodel":true,"original_research":true,"original_building_cards":true,"start_date":{"year":1998,"month":1,"day":1}})
		check(game != null, map_id + " starts")
		if game == null: continue
		map_count += 1
		var player: Dictionary = game.state.players[0]
		for actor in game.state.god_objects:
			if int(actor.id) == 5:
				actor.owner = 0
				actor.node = player.position
				actor.days = 7
				player.god_id = 5
		var held := int(player.tools.get("定時炸彈", 0))
		check(held > 0, map_id + " has a bomb to stage")
		if held <= 0: continue
		if held == 1: player.tools.erase("定時炸彈")
		else: player.tools["定時炸彈"] = held - 1
		player.bomb_steps = 9
		check(Game.validate_save(game.to_dict()).get("ok", false), map_id + " staged god/bomb snapshot validates")
		for card in ["送神符", "請神符"]:
			check(Inventory.grant_card(game.state.inventory_supply, player.cards, card).get("ok", false), map_id + " stages " + card)
			game._set_action_options(0)
			check(game.choose_action("use_card", {"card_id":card}).get("ok", false), map_id + " uses " + card)
			check(Game.validate_save(game.to_dict()).get("ok", false), map_id + " validates after " + card)
			if card == "送神符":
				check(int(player.god_id) == 0 and int(player.bomb_steps) == 0, map_id + " clears both effects")
			else:
				check(int(player.god_id) > 0, map_id + " attaches a god")
		for player_id in range(4): game.set_player_ai(player_id, true)
		var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		check(restored != null, map_id + " reloads card effects")
		if restored == null: continue
		var turns := 0
		while turns < 16 and game.state.phase != "game_over":
			var result: Dictionary = game.run_ai_turn()
			var counterpart: Dictionary = restored.run_ai_turn()
			check(result.get("ok", false) and counterpart.get("ok", false) and result.get("completed", false), map_id + " completes AI turn")
			check(game.to_json() == restored.to_json(), map_id + " continues deterministically")
			check(Game.validate_save(game.to_dict()).get("ok", false), map_id + " continued snapshot validates")
			turns += 1
		print("God card source ", map_id, " version=", game.state.version, " turns=", turns)
	check(map_count == 2, "Expected two source maps")
	print("God card source acceptance: ", map_count, " maps, ", failures, " failures")
	quit(1 if failures else 0)
