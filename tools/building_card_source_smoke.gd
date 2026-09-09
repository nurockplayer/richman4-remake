extends SceneTree
## Uses an existing owner-authorized catalog without materializing assets.
const Maps = preload("res://game/content/original_maps.gd")
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var failures := 0
func fail(label: String) -> void:
	failures += 1
	push_error(label)
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		fail("Provide an owner-authorized complete catalog path")
		quit(1); return
	var catalog := Maps.load_catalog(args[0], true)
	if not catalog.get("ok", false):
		fail(str(catalog.get("error", "Catalog load failed")))
		quit(1); return
	var map_count := 0
	for definition in catalog.maps:
		var id := str(definition.id)
		var game := Game.new_game_on_board(4413, 4, definition, {"original_inventory":true,"original_facilities":true,"original_gods":true,"original_companies":true,"original_statuses":true,"original_hazards":true,"original_property_cards":true,"original_remodel":true,"original_research":true,"original_building_cards":true,"day_limit":30,"start_date":{"year":1998,"month":1,"day":1}})
		if game == null:
			fail(id + " cannot start v13"); continue
		map_count += 1
		var site: Dictionary = {}
		for tile in game.state.board:
			if tile.get("kind", "") == "facility":
				site = tile; break
		if site.is_empty():
			fail(id + " has no facility"); continue
		var canonical: int = game._facility_canonical_index(int(site.index))
		var source_id: int = int(site.source_object_id)
		game.state.players[1].properties.append(canonical)
		game._update_facility_records(source_id, {"owner":1,"building_level":0,"facility_type":0})
		game._recalculate_property_values()
		for card in ["天使", "怪獸", "惡魔"]:
			Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, card)
			game._set_action_options(0)
			var params := {"card_id":card,"tile_id":canonical}
			if card == "天使": params["facility_type"] = 4
			if not game.choose_action("use_card", params).get("ok", false): fail(id + " failed public card " + card)
		if int(game.state.board[canonical].owner) != 1 or int(game.state.board[canonical].building_level) != 0:
			fail(id + " building destruction changed landlord or left building")
		for player_id in range(4):
			game.set_player_ai(player_id, true)
			for card in ["天使", "惡魔", "怪獸"]:
				Inventory.grant_card(game.state.inventory_supply, game.state.players[player_id].cards, card)
		game._set_action_options(0)
		var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		if restored == null:
			fail(id + " initial JSON snapshot rejected"); continue
		var turns := 0
		while game.state.phase != "game_over" and turns < 300:
			var result: Dictionary = game.run_ai_turn()
			var counterpart: Dictionary = restored.run_ai_turn()
			if not result.get("ok", false) or not counterpart.get("ok", false) or not result.get("completed", false):
				fail(id + " AI turn incomplete: " + str(result.get("message", ""))); break
			turns += 1
			var validation := Game.validate_save(game.to_dict())
			if not validation.get("ok", false):
				fail(id + " invalid save: " + str(validation.get("errors", []))); break
			if game.to_json() != restored.to_json():
				fail(id + " JSON continuation differs at turn " + str(turns)); break
			restored = Game.from_dict(JSON.parse_string(game.to_json()))
			if restored == null:
				fail(id + " snapshot cannot reload at turn " + str(turns)); break
		if game.state.phase != "game_over": fail(id + " did not finish 30-day match")
		print("Building card source ", id, " version=", game.state.version, " turns=", turns, " phase=", game.state.phase)
	if map_count != 12: fail("Expected twelve building-card-capable source maps")
	print("Building card source acceptance: ", map_count, " maps, ", failures, " failures")
	quit(1 if failures else 0)
