extends RefCounted

## Synthetic v13 missile map built from the legal building-card fixture.
##
## The fixture has no original assets or extracted source data.  Coordinates
## are deliberately arranged as logical target-centered boundaries so the
## acceptance tests do not derive gameplay range from a texture or viewport.

const Base = preload("res://tests/fixtures/building_card_fixture.gd")
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")


static func definition() -> Dictionary:
	var result: Dictionary = Base.definition()
	var board: Array = result.get("board", [])
	var logical_positions: Array = [
		[-220, 0], # 0: hospital, nuclear boundary
		[0, 0], # 1: source-1 facility, blast centre
		[100, 0], # 2: ordinary housing, missile boundary
		[-100, 0], # 3: chain housing, missile boundary
		[221, 0], # 4: prison, outside nuclear boundary
		[500, 500], # 5: unrelated special node
		[0, 100], # 6: source-1 duplicate entrance, missile boundary
		[220, 0], # 7: source-2 facility, nuclear boundary
		[101, 0], # 8: source-2 duplicate entrance, outside missile boundary
		[0, -100], # 9: eligible road and god target, missile boundary
	]
	for index in range(min(board.size(), logical_positions.size())):
		var tile: Dictionary = board[index]
		tile["x"] = int(logical_positions[index][0])
		tile["y"] = int(logical_positions[index][1])
	result["board"] = board
	return result


static func new_game_options() -> Dictionary:
	return Base.new_game_options()


static func new_game(seed_value: int = 8101, player_count: int = 4) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, definition(), new_game_options())
	if game == null:
		return null
	# Keep every missile scenario independent of the map's deterministic god
	# spawn roulette. Tests add explicit in-range/out-of-range actors when the
	# blast contract needs them.
	game.state["god_objects"] = []
	for player_value in game.state.get("players", []):
		if typeof(player_value) == TYPE_DICTIONARY:
			player_value["god_id"] = 0
	game._set_action_options(int(game.state.get("current_player", 0)))
	return game


static func prepare_action(game: Object, player_id: int = 0, phase: String = "await_roll") -> void:
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
	game.state["pending_remote_dice"] = {}
	game._set_action_options(player_id)


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


static func facility_indices(game: Object, source_id: int) -> Array:
	var result: Array = []
	for index in range(game.state.get("board", []).size()):
		var tile: Variant = game.state["board"][index]
		if typeof(tile) == TYPE_DICTIONARY and tile.get("kind", "") == "facility" and int(tile.get("source_object_id", -1)) == source_id:
			result.append(index)
	return result


static func set_facility(
	game: Object,
	source_id: int,
	owner_id: int,
	level: int,
	facility_type: int,
	facility_state: int = 0,
	research_tool: int = 0,
	research_turns: int = 0,
) -> void:
	var indices: Array = facility_indices(game, source_id)
	if indices.is_empty():
		return
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


static func clear_tools_except(game: Object, player_id: int, keep: Array = []) -> void:
	if player_id < 0 or player_id >= game.state.get("players", []).size():
		return
	var player: Dictionary = game.state["players"][player_id]
	var tools: Dictionary = player.get("tools", {})
	for tool_id in tools.keys().duplicate():
		if keep.has(str(tool_id)):
			continue
		var quantity: int = int(tools.get(tool_id, 0))
		if quantity > 0:
			Inventory.consume_tool(game.state["inventory_supply"], tools, str(tool_id), quantity)
