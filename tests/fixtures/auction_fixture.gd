extends RefCounted

## Legal v13 synthetic fixture for Issue #78 auction tests.
## It reuses the finite-inventory building-card factory and contains no
## original assets or extracted source material.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Base = preload("res://tests/fixtures/building_card_fixture.gd")

const CARD_ID := "拍賣"
const MAX_CASH: int = 1000000000000


static func definition() -> Dictionary:
	return Base.definition()


static func new_game_options() -> Dictionary:
	return Base.new_game_options()


static func new_game(seed_value: int, player_count: int = 4) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, definition(), new_game_options())
	if game == null:
		return null
	for player_id in range(player_count):
		game.set_player_ai(player_id, false)
		var player: Dictionary = game.state["players"][player_id]
		player["alive"] = true
		player["bankrupt"] = false
		player["cash"] = 100000
		player["deposit"] = 0
		player["properties"] = []
		player["cards"] = []
		player["position"] = 2
		player["previous_position"] = -1
		player["hospital_days"] = 0
		player["prison_days"] = 0
		player["god_id"] = 0
	game.state["bank"]["deposits"] = 0
	game.state["god_objects"] = []
	reset_board(game)
	prepare(game, 0, 2)
	game.call("_sync_state")
	return game


static func reset_board(game: Object) -> void:
	for tile_value in game.state.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = tile_value
		if tile.get("kind", "") == "property":
			tile["owner"] = -1
			tile["building_level"] = 0
			tile["is_chain_store"] = false
			game.call("_update_tile_rent", tile)
		elif tile.get("kind", "") == "facility":
			tile["owner"] = -1
			tile["building_level"] = 0
			tile["facility_type"] = 0
			tile["facility_state"] = 0
			tile["research_tool"] = 0
			tile["research_turns"] = 0
	for player in game.state.get("players", []):
		if typeof(player) == TYPE_DICTIONARY:
			player["properties"] = []
	game.call("_recalculate_property_values")


static func prepare(game: Object, player_id: int, node_id: int, phase: String = "await_action") -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state.erase("pending_finance")
	game.state["pending_trap"] = {}
	game.state.erase("pending_trap_card")
	game.state.erase("pending_auction")
	for candidate in game.state.get("players", []):
		if typeof(candidate) != TYPE_DICTIONARY:
			continue
		candidate["hospital_days"] = 0
		candidate["prison_days"] = 0
		candidate["god_id"] = 0
	var caster: Dictionary = game.state["players"][player_id]
	caster["position"] = node_id
	caster["previous_position"] = -1
	game.state["god_objects"] = []
	game.call("_set_action_options", player_id)


static func stage_card(game: Object, player_id: int) -> Dictionary:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], CARD_ID)
	if bool(result.get("ok", false)):
		game.call("_set_action_options", player_id)
	return result


static func set_owner(game: Object, node_id: int, owner_id: int) -> void:
	var board: Array = game.state.get("board", [])
	if node_id < 0 or node_id >= board.size() or typeof(board[node_id]) != TYPE_DICTIONARY:
		return
	var tile: Dictionary = board[node_id]
	var asset_id: int = node_id
	if tile.get("kind", "") == "facility":
		var source_id: int = int(tile.get("source_object_id", -1))
		asset_id = int(tile.get("facility_node_index", node_id))
		for candidate_value in board:
			if typeof(candidate_value) == TYPE_DICTIONARY and candidate_value.get("kind", "") == "facility" and int(candidate_value.get("source_object_id", -1)) == source_id:
				candidate_value["owner"] = owner_id
	else:
		tile["owner"] = owner_id
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = player_value
		var properties: Array = player.get("properties", []).duplicate(true)
		while properties.has(asset_id):
			properties.erase(asset_id)
		player["properties"] = properties
	if owner_id >= 0 and owner_id < game.state.get("players", []).size():
		var owner_properties: Array = game.state["players"][owner_id].get("properties", []).duplicate(true)
		if not owner_properties.has(asset_id):
			owner_properties.append(asset_id)
		game.state["players"][owner_id]["properties"] = owner_properties
	game.call("_recalculate_property_values")


static func set_property_state(game: Object, node_id: int, owner_id: int, level: int) -> void:
	set_owner(game, node_id, owner_id)
	var tile: Dictionary = game.state["board"][node_id]
	tile["building_level"] = level
	tile["is_chain_store"] = false
	game.call("_update_tile_rent", tile)
	game.call("_recalculate_property_values")


static func facility_nodes(game: Object, source_id: int) -> Array:
	var result: Array = []
	for tile_value in game.state.get("board", []):
		if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "facility" and int(tile_value.get("source_object_id", -1)) == source_id:
			result.append(int(tile_value.get("index", -1)))
	result.sort()
	return result


static func set_facility_state(game: Object, source_id: int, owner_id: int, level: int, facility_type: int, facility_state: int = 0) -> void:
	for node_id in facility_nodes(game, source_id):
		var tile: Dictionary = game.state["board"][node_id]
		tile["building_level"] = level
		tile["facility_type"] = facility_type
		tile["facility_state"] = facility_state
	set_owner(game, facility_nodes(game, source_id)[0], owner_id)
	game.call("_recalculate_property_values")


static func set_funds(game: Object, player_id: int, cash: int, deposit: int = 0) -> void:
	var player: Dictionary = game.state["players"][player_id]
	player["cash"] = cash
	player["deposit"] = deposit
	var total_deposits: int = 0
	for candidate in game.state.get("players", []):
		total_deposits += int(candidate.get("deposit", 0))
	game.state["bank"]["deposits"] = total_deposits


static func target_snapshot(game: Object, node_id: int) -> Dictionary:
	var tile: Dictionary = game.state["board"][node_id]
	var snapshot: Dictionary = {}
	for key in ["owner", "building_level", "facility_type", "facility_state", "research_tool", "research_turns", "cost", "land_price", "house_price", "upgrade_cost", "type_and_idx", "source_object_id", "facility_node_index", "is_chain_store"]:
		if tile.has(key):
			snapshot[key] = tile[key]
	return snapshot


static func card_supply(game: Object) -> int:
	return int(game.state.get("inventory_supply", {}).get("cards", {}).get(CARD_ID, -1))


static func cash_deposit_snapshot(game: Object) -> Array:
	var result: Array = []
	for player in game.state.get("players", []):
		result.append([int(player.get("cash", 0)), int(player.get("deposit", 0))])
	return result


static func participant_ids(game: Object) -> Array:
	var ids: Array = []
	for player in game.state.get("players", []):
		if typeof(player) == TYPE_DICTIONARY and bool(player.get("alive", false)):
			ids.append(int(player.get("id", -1)))
	ids.sort()
	return ids


static func validate(game: Object) -> Dictionary:
	return Game.validate_save(game.to_dict())
