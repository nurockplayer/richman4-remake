extends RefCounted

## Synthetic v13 time/transport fixture built from the existing legal graph.
##
## This wrapper does not add map nodes, source data, capabilities, or save
## fields.  It only keeps test setup on the already admitted building-card
## fixture and clears spawned gods so target selection stays deterministic.

const Base = preload("res://tests/fixtures/building_card_fixture.gd")
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")


static func definition() -> Dictionary:
	return Base.definition()


static func new_game(seed_value: int = 8201, player_count: int = 2) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, definition(), Base.new_game_options())
	if game == null:
		return null
	game.state["god_objects"] = []
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		player_value["god_id"] = 0
		player_value["hospital_days"] = 0
		player_value["prison_days"] = 0
	game._sync_state()
	game._set_action_options(int(game.state.get("current_player", 0)))
	return game


static func prepare_action(game: Object, player_id: int = 0, position: int = -1, phase: String = "await_roll") -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	if game.state.has("pending_remote_dice"):
		game.state["pending_remote_dice"] = {}
	if position >= 0 and player_id >= 0 and player_id < game.state.get("players", []).size():
		game.state["players"][player_id]["position"] = position
		game.state["players"][player_id]["previous_position"] = -1
	game._set_action_options(player_id)


static func stage_tool(game: Object, player_id: int, tool_id: String) -> bool:
	var result: Dictionary = Inventory.grant_tool(
		game.state["inventory_supply"],
		game.state["players"][player_id]["tools"],
		tool_id,
		1,
	)
	return bool(result.get("ok", false))


static func clear_tools_except(game: Object, player_id: int, keep: Array = []) -> void:
	if player_id < 0 or player_id >= game.state.get("players", []).size():
		return
	var tools: Dictionary = game.state["players"][player_id].get("tools", {})
	for tool_id in tools.keys().duplicate():
		if keep.has(str(tool_id)):
			continue
		var quantity: int = int(tools.get(tool_id, 0))
		if quantity > 0:
			Inventory.consume_tool(game.state["inventory_supply"], tools, str(tool_id), quantity)


static func property_indices(game: Object) -> Array:
	var result: Array = []
	for index in range(game.state.get("board", []).size()):
		var tile: Variant = game.state["board"][index]
		if typeof(tile) == TYPE_DICTIONARY and tile.get("kind", "") == "property":
			result.append(index)
	return result


static func facility_indices(game: Object, source_id: int) -> Array:
	var result: Array = []
	for index in range(game.state.get("board", []).size()):
		var tile: Variant = game.state["board"][index]
		if typeof(tile) == TYPE_DICTIONARY and tile.get("kind", "") == "facility" and int(tile.get("source_object_id", -1)) == source_id:
			result.append(index)
	return result


static func set_property(game: Object, tile_id: int, owner_id: int, level: int, chain_store: bool = false) -> void:
	var board: Array = game.state.get("board", [])
	if tile_id < 0 or tile_id >= board.size() or typeof(board[tile_id]) != TYPE_DICTIONARY:
		return
	var tile: Dictionary = board[tile_id]
	if tile.get("kind", "") != "property":
		return
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var properties: Array = player_value.get("properties", []).duplicate(true)
		while properties.has(tile_id):
			properties.erase(tile_id)
		player_value["properties"] = properties
	tile["owner"] = owner_id
	tile["building_level"] = level
	tile["is_chain_store"] = chain_store
	if owner_id >= 0 and owner_id < game.state.get("players", []).size():
		var owner_properties: Array = game.state["players"][owner_id].get("properties", []).duplicate(true)
		if not owner_properties.has(tile_id):
			owner_properties.append(tile_id)
		game.state["players"][owner_id]["properties"] = owner_properties
	game._update_tile_rent(tile)
	game._recalculate_property_values()


static func set_facility(
	game: Object,
	source_id: int,
	owner_id: int,
	level: int,
	facility_type: int,
	facility_state: int = 0,
	research_tool: int = 0,
	research_turns: int = 0,
) -> Array:
	var indices: Array = facility_indices(game, source_id)
	if indices.is_empty():
		return []
	var canonical: int = int(game.state["board"][int(indices[0])].get("facility_node_index", int(indices[0])))
	for index_value in indices:
		var tile: Dictionary = game.state["board"][int(index_value)]
		tile["owner"] = owner_id
		tile["building_level"] = level
		tile["facility_type"] = facility_type
		tile["facility_state"] = facility_state
		tile["research_tool"] = research_tool
		tile["research_turns"] = research_turns
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var properties: Array = player_value.get("properties", []).duplicate(true)
		while properties.has(canonical):
			properties.erase(canonical)
		player_value["properties"] = properties
	if owner_id >= 0 and owner_id < game.state.get("players", []).size():
		var owner_properties: Array = game.state["players"][owner_id].get("properties", []).duplicate(true)
		if not owner_properties.has(canonical):
			owner_properties.append(canonical)
		game.state["players"][owner_id]["properties"] = owner_properties
	game._recalculate_property_values()
	return indices
