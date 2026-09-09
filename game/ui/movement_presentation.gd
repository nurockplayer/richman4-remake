class_name RichmanMovementPresentation
extends RefCounted

## Pure, action-scoped movement extraction for graph saves.
##
## The simulation completes an action synchronously.  This helper compares the
## two complete snapshots returned around that action and emits only edges that
## are still provable from the event log.  An empty result means that the UI
## should adopt the latest snapshot immediately.

const GRAPH_MODE := "graph"
const MAX_EVENT_LOG_SIZE := 200
const OCTANT_VECTORS := [
	Vector2(0, 1),
	Vector2(1, 1),
	Vector2(1, 0),
	Vector2(1, -1),
	Vector2(0, -1),
	Vector2(-1, -1),
	Vector2(-1, 0),
	Vector2(-1, 1),
]
const UNSAFE_EVENT_PARTS := [
	"teleport", "warp", "summon", "status", "hospital", "prison",
	"terminal", "game_over", "gameover", "bankrupt", "death",
	"movement_blocked", "movement_invalid", "player_removed",
]


static func plan(before: Dictionary, after: Dictionary) -> Array:
	var before_board := _read_board(before)
	var after_board := _read_board(after)
	if not bool(before_board.get("ok", false)) or not bool(after_board.get("ok", false)):
		return []
	if not _valid_snapshot_shell(before) or not _valid_snapshot_shell(after):
		return []
	if str(before.get("board_mode", "")) != GRAPH_MODE or str(after.get("board_mode", "")) != GRAPH_MODE:
		return []
	if before_board.get("signature", []) != after_board.get("signature", []):
		return []
	if not _same_map_identity(before, after):
		return []
	if not _valid_start_position(before, before_board) or not _valid_start_position(after, after_board):
		return []

	var before_players := _read_players(before, before_board.get("nodes", {}))
	var after_players := _read_players(after, after_board.get("nodes", {}))
	if not bool(before_players.get("ok", false)) or not bool(after_players.get("ok", false)):
		return []
	var before_by_id: Dictionary = before_players.get("players", {})
	var after_by_id: Dictionary = after_players.get("players", {})
	if not _same_actor_set(before_by_id, after_by_id):
		return []

	var delta := _event_delta(before.get("event_log", []), after.get("event_log", []))
	if not bool(delta.get("ok", false)):
		return []
	var new_events: Array = delta.get("events", [])
	if new_events.is_empty():
		return []
	if str(after.get("phase", "")) == "game_over":
		return []

	var move_events: Array = []
	for event_index in range(new_events.size()):
		var event_value: Variant = new_events[event_index]
		if typeof(event_value) != TYPE_DICTIONARY:
			return []
		var event: Dictionary = event_value
		if _unsafe_event(event):
			return []
		var event_type: Variant = event.get("type", null)
		if typeof(event_type) != TYPE_STRING or str(event_type).is_empty():
			return []
		if str(event_type) == "route_chosen":
			# choose_route() traverses this edge itself and records no "move"
			# for it. A following identical move is the same presentation edge.
			var route_move: Dictionary = event.duplicate(true)
			route_move["steps"] = 1
			if not _valid_move_event(route_move, before_players.get("nodes", {})):
				return []
			var duplicate_move := false
			if event_index + 1 < new_events.size() and typeof(new_events[event_index + 1]) == TYPE_DICTIONARY:
				var following: Dictionary = new_events[event_index + 1]
				duplicate_move = following.get("type", "") == "move" and following.get("player_id") == event.get("player_id") and following.get("from") == event.get("from") and following.get("to") == event.get("to") and following.get("steps") == 1
			if not duplicate_move:
				move_events.append(route_move)
		elif str(event_type) == "move":
			if not _valid_move_event(event, before_players.get("nodes", {})):
				return []
			move_events.append(event)

	if move_events.is_empty():
		return []
	var actor_id := -1
	for event in move_events:
		var event_player_id: int = int(event["player_id"])
		if not before_by_id.has(event_player_id):
			return []
		if actor_id < 0:
			actor_id = event_player_id
		elif actor_id != event_player_id:
			return []
	if actor_id < 0:
		return []

	var changed_players: Array = []
	for player_id in before_by_id.keys():
		var old_player: Dictionary = before_by_id[player_id]
		var new_player: Dictionary = after_by_id[player_id]
		if int(old_player["position"]) != int(new_player["position"]):
			changed_players.append(int(player_id))
	if changed_players.size() > 1 or (changed_players.size() == 1 and int(changed_players[0]) != actor_id):
		return []

	var cursor := int(before_by_id[actor_id]["position"])
	var previous_direction := 0
	var result: Array = []
	for event in move_events:
		var from_node := int(event["from"])
		var to_node := int(event["to"])
		if from_node != cursor:
			return []
		var from_position: Vector2 = before_players["nodes"][from_node]["position"]
		var to_position: Vector2 = before_players["nodes"][to_node]["position"]
		previous_direction = direction(from_position, to_position, previous_direction)
		result.append({
			"player_id": actor_id,
			"from": from_node,
			"to": to_node,
			"direction": previous_direction,
		})
		cursor = to_node
	if cursor != int(after_by_id[actor_id]["position"]):
		return []
	return result


static func direction(from: Vector2, to: Vector2, previous: int = 0) -> int:
	var delta := to - from
	if delta.length_squared() <= 0.000001:
		return previous if previous >= 0 and previous < OCTANT_VECTORS.size() else 0
	var unit := delta.normalized()
	var best_direction := 0
	var best_dot := -INF
	for index in range(OCTANT_VECTORS.size()):
		var score := unit.dot(OCTANT_VECTORS[index].normalized())
		if score > best_dot:
			best_dot = score
			best_direction = index
	return best_direction


static func direction_for_edge(from: Vector2, to: Vector2, previous: int = 0) -> int:
	return direction(from, to, previous)


static func _valid_snapshot_shell(snapshot: Dictionary) -> bool:
	if typeof(snapshot.get("board_mode", null)) != TYPE_STRING or str(snapshot.get("board_mode")) != GRAPH_MODE:
		return false
	if typeof(snapshot.get("map_id", null)) != TYPE_STRING or str(snapshot.get("map_id", "")).is_empty():
		return false
	for key in ["board", "players", "event_log"]:
		if typeof(snapshot.get(key, null)) != TYPE_ARRAY:
			return false
	if snapshot["event_log"].size() > MAX_EVENT_LOG_SIZE:
		return false
	for key in ["map_name", "map_schema"]:
		if snapshot.has(key) and typeof(snapshot.get(key)) != TYPE_STRING:
			return false
	if snapshot.has("map_version") and not _is_int(snapshot.get("map_version")):
		return false
	if snapshot.has("map_source") and typeof(snapshot.get("map_source")) != TYPE_DICTIONARY:
		return false
	if snapshot.has("start_position") and not _is_int(snapshot.get("start_position")):
		return false
	for event_value in snapshot["event_log"]:
		if typeof(event_value) != TYPE_DICTIONARY:
			return false
		var event: Dictionary = event_value
		if typeof(event.get("type", null)) != TYPE_STRING or str(event.get("type", "")).is_empty():
			return false
	return true


static func _same_map_identity(before: Dictionary, after: Dictionary) -> bool:
	for key in ["map_id", "map_name", "map_schema", "map_version", "start_position"]:
		if before.has(key) != after.has(key):
			return false
		if before.has(key) and before.get(key) != after.get(key):
			return false
	var old_source: Dictionary = before.get("map_source", {}).duplicate(true)
	var new_source: Dictionary = after.get("map_source", {}).duplicate(true)
	# Facility aliases and company records retain mutable gameplay fields.
	# Node geometry is checked independently; these records are not map identity.
	for key in ["lands", "facilities", "companies"]:
		old_source.erase(key)
		new_source.erase(key)
	if old_source != new_source:
		return false
	return true


static func _valid_start_position(snapshot: Dictionary, board: Dictionary) -> bool:
	if not snapshot.has("start_position"):
		return true
	return board.get("nodes", {}).has(int(snapshot["start_position"]))


static func _read_board(snapshot: Dictionary) -> Dictionary:
	if typeof(snapshot.get("board", null)) != TYPE_ARRAY:
		return {}
	var board: Array = snapshot["board"]
	if board.is_empty():
		return {}
	var nodes: Dictionary = {}
	for tile_value in board:
		if typeof(tile_value) != TYPE_DICTIONARY:
			return {}
		var tile: Dictionary = tile_value
		var id_result := _node_id(tile)
		if not bool(id_result.get("ok", false)):
			return {}
		var node_id: int = int(id_result["id"])
		if nodes.has(node_id) or not tile.has("x") or not tile.has("y"):
			return {}
		if not _is_number(tile.get("x")) or not _is_number(tile.get("y")):
			return {}
		var neighbors_result := _neighbors(tile)
		if not bool(neighbors_result.get("ok", false)):
			return {}
		nodes[node_id] = {
			"position": Vector2(float(tile["x"]), float(tile["y"])),
			"x": float(tile["x"]),
			"y": float(tile["y"]),
			"neighbors": neighbors_result["neighbors"],
		}
	for node_id in nodes.keys():
		var neighbors: Array = nodes[node_id]["neighbors"]
		for neighbor in neighbors:
			if not nodes.has(neighbor) or not nodes[neighbor]["neighbors"].has(node_id):
				return {}
	var ids: Array = nodes.keys()
	ids.sort()
	var signature: Array = []
	for node_id in ids:
		var node: Dictionary = nodes[node_id]
		var canonical_neighbors: Array = node["neighbors"].duplicate()
		canonical_neighbors.sort()
		signature.append([node_id, node["x"], node["y"], canonical_neighbors])
	return {"ok": true, "nodes": nodes, "signature": signature}


static func _node_id(tile: Dictionary) -> Dictionary:
	var has_index := tile.has("index")
	var has_id := tile.has("id")
	if not has_index and not has_id:
		return {}
	if has_index and not _is_int(tile.get("index")):
		return {}
	if has_id and not _is_int(tile.get("id")):
		return {}
	if has_index and has_id and int(tile["index"]) != int(tile["id"]):
		return {}
	var value: int = int(tile["index"]) if has_index else int(tile["id"])
	if value < 0:
		return {}
	return {"ok": true, "id": value}


static func _neighbors(tile: Dictionary) -> Dictionary:
	var has_adjacent := tile.has("adjacent")
	var has_neighbors := tile.has("neighbors")
	if not has_adjacent and not has_neighbors:
		return {}
	var adjacent: Array = []
	if has_adjacent:
		if typeof(tile.get("adjacent")) != TYPE_ARRAY:
			return {}
		adjacent = _canonical_neighbors(tile["adjacent"])
		if adjacent.is_empty() and not tile["adjacent"].is_empty():
			return {}
	var neighbors: Array = adjacent
	if has_neighbors:
		if typeof(tile.get("neighbors")) != TYPE_ARRAY:
			return {}
		neighbors = _canonical_neighbors(tile["neighbors"])
		if neighbors.is_empty() and not tile["neighbors"].is_empty():
			return {}
	if has_adjacent and has_neighbors:
		var adjacent_sorted: Array = adjacent.duplicate()
		var neighbors_sorted: Array = neighbors.duplicate()
		adjacent_sorted.sort()
		neighbors_sorted.sort()
		if adjacent_sorted != neighbors_sorted:
			return {}
	var canonical: Array = neighbors.duplicate()
	canonical.sort()
	return {"ok": true, "neighbors": canonical}


static func _canonical_neighbors(value: Array) -> Array:
	var result: Array = []
	for neighbor_value in value:
		if not _is_int(neighbor_value) or int(neighbor_value) < 0 or result.has(int(neighbor_value)):
			return []
		result.append(int(neighbor_value))
	return result


static func _read_players(snapshot: Dictionary, nodes: Dictionary) -> Dictionary:
	var players: Array = snapshot.get("players", [])
	var by_id: Dictionary = {}
	for player_value in players:
		if typeof(player_value) != TYPE_DICTIONARY:
			return {}
		var player: Dictionary = player_value
		if not _is_int(player.get("id", null)) or int(player["id"]) < 0:
			return {}
		if not _is_int(player.get("position", null)) or not nodes.has(int(player["position"])):
			return {}
		var player_id: int = int(player["id"])
		if by_id.has(player_id):
			return {}
		by_id[player_id] = {"position": int(player["position"])}
	return {"ok": true, "players": by_id, "nodes": nodes}


static func _same_actor_set(before: Dictionary, after: Dictionary) -> bool:
	if before.size() != after.size():
		return false
	for player_id in before.keys():
		if not after.has(player_id):
			return false
	return true


static func _valid_move_event(event: Dictionary, nodes: Dictionary) -> bool:
	for key in ["player_id", "from", "to", "steps"]:
		if not event.has(key) or not _is_int(event.get(key)):
			return false
	if int(event["steps"]) != 1:
		return false
	var from_node := int(event["from"])
	var to_node := int(event["to"])
	if from_node == to_node or not nodes.has(from_node) or not nodes.has(to_node):
		return false
	return nodes[from_node]["neighbors"].has(to_node)


static func _unsafe_event(event: Dictionary) -> bool:
	var event_type := str(event.get("type", "")).to_lower()
	for unsafe_part in UNSAFE_EVENT_PARTS:
		if event_type.contains(unsafe_part):
			return true
	return false


static func _event_delta(before_value: Variant, after_value: Variant) -> Dictionary:
	if typeof(before_value) != TYPE_ARRAY or typeof(after_value) != TYPE_ARRAY:
		return {}
	var before: Array = before_value
	var after: Array = after_value
	if after.size() < before.size() or after.size() > MAX_EVENT_LOG_SIZE:
		return {}
	if _has_prefix(after, before):
		return {"ok": true, "events": after.slice(before.size())}
	if before.size() != MAX_EVENT_LOG_SIZE or after.size() != MAX_EVENT_LOG_SIZE:
		return {}
	var overlaps: Array = []
	for overlap in range(1, MAX_EVENT_LOG_SIZE):
		if _suffix_prefix_match(before, after, overlap):
			overlaps.append(overlap)
	if overlaps.size() != 1:
		return {}
	var retained: int = int(overlaps[0])
	var new_count := MAX_EVENT_LOG_SIZE - retained
	if retained <= 0 or new_count <= 0 or after.size() - retained != new_count:
		return {}
	return {"ok": true, "events": after.slice(retained)}


static func _has_prefix(sequence: Array, prefix: Array) -> bool:
	if prefix.size() > sequence.size():
		return false
	for index in range(prefix.size()):
		if sequence[index] != prefix[index]:
			return false
	return true


static func _suffix_prefix_match(before: Array, after: Array, length: int) -> bool:
	if length <= 0 or length > before.size() or length > after.size():
		return false
	var before_start := before.size() - length
	for index in range(length):
		if before[before_start + index] != after[index]:
			return false
	return true


static func _is_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT


static func _is_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return is_finite(float(value))
