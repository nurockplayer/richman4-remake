class_name RichmanMissileRules
extends RefCounted

## Runtime rules for the original 飛彈 and 核子飛彈 tools.
##
## The game state owns the serialized board, player and inventory containers.
## This module owns the target geometry and the atomic validation boundary so
## the public action, AI picker and UI picker share one implementation.

const MISSILE_ID := "飛彈"
const NUCLEAR_MISSILE_ID := "核子飛彈"
const MISSILE_HALF_EXTENT: int = 100
const NUCLEAR_HALF_EXTENT: int = 220
const TOOL_IDS := [MISSILE_ID, NUCLEAR_MISSILE_ID]
const REQUEST_KEYS := ["tool_id", "tile_id", "cancel"]


static func is_missile(tool_id: String) -> bool:
	return TOOL_IDS.has(tool_id)


static func supports(game: Object) -> bool:
	if game == null or not game.has_method("_is_inventory") or not game.has_method("_is_graph"):
		return false
	if not game.has_method("_is_statuses") or not game.has_method("_status_node_index"):
		return false
	if not game._is_inventory() or not game._is_graph() or not game._is_statuses():
		return false
	var hospital_index: Variant = game._status_node_index("hospital")
	return typeof(hospital_index) == TYPE_INT and int(hospital_index) >= 0


static func half_extent(tool_id: String) -> int:
	return NUCLEAR_HALF_EXTENT if tool_id == NUCLEAR_MISSILE_ID else MISSILE_HALF_EXTENT


static func target_tiles(game: Object, player_id: int, tool_id: String) -> Array:
	var targets: Array = []
	if not is_missile(tool_id) or not supports(game):
		return targets
	var board: Variant = game.state.get("board", null)
	if typeof(board) != TYPE_ARRAY:
		return targets
	for tile_id in range(board.size()):
		if target_error(game, player_id, tool_id, tile_id).is_empty():
			targets.append(tile_id)
	return targets


static func target_error(game: Object, player_id: int, tool_id: String, tile_id: Variant) -> String:
	if not is_missile(tool_id):
		return "飛彈道具代號無效"
	if not supports(game):
		return "飛彈效果只適用於原版圖形背包地圖"
	var player: Dictionary = game._player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return "目前玩家無法行動"
	if str(game.state.get("phase", "")) != "await_roll":
		return "飛彈只能在擲骰前使用"
	if game._inventory_movement_blocked(player):
		return "目前移動狀態無法使用飛彈"
	var pending_remote: Variant = game.state.get("pending_remote_dice", {})
	if typeof(pending_remote) == TYPE_DICTIONARY and not pending_remote.is_empty():
		return "遙控骰子已經排程"
	var tools: Variant = player.get("tools", null)
	if typeof(tools) != TYPE_DICTIONARY or int(tools.get(tool_id, 0)) <= 0:
		return "玩家沒有這項道具"
	var board: Variant = game.state.get("board", null)
	if typeof(board) != TYPE_ARRAY or typeof(tile_id) != TYPE_INT or int(tile_id) < 0 or int(tile_id) >= board.size():
		return "目標格位無效"
	var tile_value: Variant = board[int(tile_id)]
	if typeof(tile_value) != TYPE_DICTIONARY:
		return "目標格位無效"
	if not _has_logical_coordinates(tile_value):
		return "目標格位沒有邏輯座標"
	return ""


static func affected_nodes(game: Object, tile_id: int, tool_id: String) -> Array:
	var affected: Array = []
	if not is_missile(tool_id) or not supports(game):
		return affected
	var board: Variant = game.state.get("board", null)
	if typeof(board) != TYPE_ARRAY or tile_id < 0 or tile_id >= board.size():
		return affected
	var target_value: Variant = board[tile_id]
	if typeof(target_value) != TYPE_DICTIONARY or not _has_logical_coordinates(target_value):
		return affected
	var target: Dictionary = target_value
	var target_x: int = int(target.get("x"))
	var target_y: int = int(target.get("y"))
	var extent: int = half_extent(tool_id)
	for node_id in range(board.size()):
		var node_value: Variant = board[node_id]
		if typeof(node_value) != TYPE_DICTIONARY or not _has_logical_coordinates(node_value):
			continue
		var node: Dictionary = node_value
		if abs(int(node.get("x")) - target_x) <= extent and abs(int(node.get("y")) - target_y) <= extent:
			affected.append(node_id)
	return affected


static func affected_players(game: Object, affected_node_ids: Array) -> Array:
	var affected: Array = []
	var players: Variant = game.state.get("players", null)
	if typeof(players) != TYPE_ARRAY:
		return affected
	for player_id in range(players.size()):
		var player_value: Variant = players[player_id]
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = player_value
		if not bool(player.get("alive", false)):
			continue
		var position: Variant = player.get("position", null)
		if typeof(position) == TYPE_INT and affected_node_ids.has(int(position)):
			affected.append(player_id)
	return affected


static func ai_target(game: Object, player_id: int, tool_id: String) -> int:
	var best_id: int = -1
	var best_opponents: int = -1
	var best_affected: int = -1
	var best_hits_caster: bool = true
	for candidate in target_tiles(game, player_id, tool_id):
		var candidate_tile: Dictionary = game._tile_at(int(candidate))
		# Status-only and other unsupported markers are valid blast victims, but
		# they are not useful AI aim points when an ordinary graph node is available.
		if str(candidate_tile.get("kind", "")) == "unsupported":
			continue
		var node_ids: Array = affected_nodes(game, int(candidate), tool_id)
		var hits_caster: bool = false
		var opponent_count: int = 0
		for target_player_id in affected_players(game, node_ids):
			if int(target_player_id) == player_id:
				hits_caster = true
			else:
				opponent_count += 1
		# A blast with no opponent in range has no useful deterministic target.
		if opponent_count <= 0:
			continue
		var better: bool = best_id < 0
		if not better and hits_caster != best_hits_caster:
			better = not hits_caster
		elif not better and opponent_count != best_opponents:
			better = opponent_count > best_opponents
		elif not better and node_ids.size() != best_affected:
			better = node_ids.size() > best_affected
		if not better:
			# Candidate iteration is canonical board order; retain the first tie.
			continue
		best_id = int(candidate)
		best_opponents = opponent_count
		best_affected = node_ids.size()
		best_hits_caster = hits_caster
	return best_id


static func use(game: Object, player_id: int, params: Dictionary) -> Dictionary:
	var parameter_error: String = _parameter_error(params)
	if not parameter_error.is_empty():
		return game._error(parameter_error)
	var tool_id: String = str(params.get("tool_id", ""))
	var player: Dictionary = game._player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return game._error("目前玩家無法行動")
	var tools: Variant = player.get("tools", null)
	if typeof(tools) != TYPE_DICTIONARY or int(tools.get(tool_id, 0)) <= 0:
		return game._error("玩家沒有這項道具")
	var context_error: String = _context_error(game, player)
	if not context_error.is_empty():
		return game._error(context_error)
	var cancel: bool = bool(params.get("cancel", false))
	if cancel:
		return game._result(true, "已取消%s" % tool_id, {"tool_id": tool_id, "cancelled": true})
	var tile_id: int = int(params.get("tile_id", -1))
	var error: String = target_error(game, player_id, tool_id, params.get("tile_id", null))
	if not error.is_empty():
		return game._error(error)
	var node_ids: Array = affected_nodes(game, tile_id, tool_id)
	if node_ids.is_empty():
		return game._error("目標格位沒有可作用的邏輯範圍")

	# Snapshot the complete affected entity list before any status admission or
	# facility update can move players or synchronize attached actors.
	var board_snapshot: Array = game.state.get("board", []).duplicate(true)
	var player_snapshots: Array = _snapshot_players(game, node_ids)
	var god_snapshots: Array = _snapshot_gods(game, node_ids)
	var property_ids: Array = []
	var facility_representatives: Dictionary = {}
	for node_id in node_ids:
		if node_id < 0 or node_id >= board_snapshot.size() or typeof(board_snapshot[node_id]) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = board_snapshot[node_id]
		var kind: String = str(node.get("kind", ""))
		if kind == "property":
			property_ids.append(node_id)
		elif kind == "facility":
			var source_id: int = int(node.get("source_object_id", -1))
			if source_id <= 0:
				return game._error("目標設施來源無效")
			if not facility_representatives.has(source_id):
				facility_representatives[source_id] = node_id
	property_ids.sort()
	var facility_source_ids: Array = facility_representatives.keys()
	facility_source_ids.sort()
	var preflight_error: String = _preflight(game, player_snapshots, facility_source_ids)
	if not preflight_error.is_empty():
		return game._error(preflight_error)

	# Keep the inventory operation in the owning game state's existing shared
	# helper.  This branch is reached only after all validation.
	var consumed: Dictionary = _consume_tool(game, player, tool_id)
	if not bool(consumed.get("ok", false)):
		return game._error(str(consumed.get("error", "道具無法使用")))

	var damage: Array = []
	var cleared: Array = []
	var nuclear: bool = tool_id == NUCLEAR_MISSILE_ID
	if nuclear:
		for property_id in property_ids:
			var property: Dictionary = game._tile_at(int(property_id))
			if property.is_empty():
				continue
			_clear_property(game, property_id, cleared)
		for source_id_value in facility_source_ids:
			_clear_facility(game, int(source_id_value), cleared)
	else:
		for property_id in property_ids:
			damage.append(game._hazard_damage_property(int(property_id)))
		for source_id_value in facility_source_ids:
			var representative: int = int(facility_representatives[int(source_id_value)])
			damage.append(game._hazard_damage_property(game._facility_canonical_index(representative)))

	var removed_gods: Array = []
	for node_id in node_ids:
		var removed: Array = game._hazard_clear_unbound_gods(int(node_id))
		if not removed.is_empty():
			removed_gods.append({"node": int(node_id), "god_ids": removed.duplicate(true)})

	var affected_player_ids: Array = []
	for snapshot_value in player_snapshots:
		if typeof(snapshot_value) != TYPE_DICTIONARY:
			continue
		var snapshot: Dictionary = snapshot_value
		var affected_player_id: int = int(snapshot.get("id", -1))
		if affected_player_id < 0:
			continue
		var vehicle: String = game._hazard_return_active_vehicle(game._player(affected_player_id))
		var admission: Dictionary = game._admit_player_status(affected_player_id, "hospital", 3)
		if not bool(admission.get("ok", false)):
			return game._error(str(admission.get("message", "玩家無法進入醫院")))
		affected_player_ids.append(affected_player_id)

	if nuclear:
		game._recalculate_property_values()
	var payload: Dictionary = {
		"player_id": player_id,
		"tool_id": tool_id,
		"tile_id": tile_id,
		"effect": "nuclear_missile" if nuclear else "missile",
		"half_extent": half_extent(tool_id),
		"affected_nodes": node_ids.duplicate(true),
		"affected_players": affected_player_ids,
		"damage": damage,
		"cleared": cleared,
		"removed_gods": removed_gods,
		"snapshotted_gods": god_snapshots.size(),
	}
	game._record_event("tool_used", payload)
	game._set_action_options(player_id)
	return game._result(true, "已使用%s" % tool_id, {"tool_id": tool_id, "tile_id": tile_id, "effect": payload["effect"]})


static func _parameter_error(params: Dictionary) -> String:
	if typeof(params) != TYPE_DICTIONARY:
		return "飛彈操作格式無效"
	for key in params.keys():
		if typeof(key) != TYPE_STRING or not REQUEST_KEYS.has(str(key)):
			return "飛彈操作格式無效"
	if not params.has("tool_id") or typeof(params.get("tool_id")) != TYPE_STRING or not is_missile(str(params.get("tool_id"))):
		return "飛彈道具代號格式無效"
	if params.has("cancel") and typeof(params.get("cancel")) != TYPE_BOOL:
		return "飛彈取消參數格式無效"
	if params.has("tile_id") and typeof(params.get("tile_id")) != TYPE_INT:
		return "目標格位格式無效"
	if not bool(params.get("cancel", false)) and not params.has("tile_id"):
		return "缺少飛彈目標格位"
	return ""


static func _snapshot_players(game: Object, node_ids: Array) -> Array:
	var snapshots: Array = []
	for player_id in range(game._players().size()):
		var player_value: Variant = game._players()[player_id]
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = player_value
		if not bool(player.get("alive", false)) or typeof(player.get("position", null)) != TYPE_INT or not node_ids.has(int(player.get("position"))):
			continue
		snapshots.append({"id": player_id, "position": int(player.get("position")), "vehicle": str(player.get("vehicle", "walking"))})
	return snapshots


static func _snapshot_gods(game: Object, node_ids: Array) -> Array:
	var snapshots: Array = []
	var objects: Variant = game.state.get("god_objects", [])
	if typeof(objects) != TYPE_ARRAY:
		return snapshots
	for actor_value in objects:
		if typeof(actor_value) != TYPE_DICTIONARY:
			continue
		var actor: Dictionary = actor_value
		if typeof(actor.get("node", null)) == TYPE_INT and node_ids.has(int(actor.get("node"))):
			snapshots.append(actor.duplicate(true))
	return snapshots


static func _preflight(game: Object, player_snapshots: Array, facility_source_ids: Array) -> String:
	if not player_snapshots.is_empty():
		if not game._is_statuses() or game._status_node_index("hospital") < 0:
			return "飛彈需要醫院狀態地圖"
		for snapshot_value in player_snapshots:
			var snapshot: Dictionary = snapshot_value
			var player: Dictionary = game._player(int(snapshot.get("id", -1)))
			if not game._valid_int(player.get("hospital_days", null), 0, game.MAX_STATUS_ADMISSION_DAYS) or not game._valid_int(player.get("prison_days", null), 0, game.MAX_STATUS_ADMISSION_DAYS):
				return "玩家狀態資料無效"
	if not facility_source_ids.is_empty() and not game._is_facilities():
		return "目標設施資料尚未開放"
	for source_id_value in facility_source_ids:
		if game._facility_indices(int(source_id_value)).is_empty():
			return "目標設施來源無效"
	return ""


static func _context_error(game: Object, player: Dictionary) -> String:
	if not supports(game):
		return "飛彈效果只適用於原版圖形背包地圖"
	if str(game.state.get("phase", "")) != "await_roll":
		return "飛彈只能在擲骰前使用"
	if game._inventory_movement_blocked(player):
		return "目前移動狀態無法使用飛彈"
	var pending_remote: Variant = game.state.get("pending_remote_dice", {})
	if typeof(pending_remote) == TYPE_DICTIONARY and not pending_remote.is_empty():
		return "遙控骰子已經排程"
	return ""


static func _consume_tool(game: Object, player: Dictionary, tool_id: String) -> Dictionary:
	var inventory_script: Variant = load("res://game/core/inventory_rules.gd")
	if inventory_script == null:
		return {"ok": false, "error": "道具供給規則無法載入"}
	return inventory_script.consume_tool(game.state.get("inventory_supply", {}), player.get("tools", {}), tool_id, 1)


static func _clear_property(game: Object, property_id: int, cleared: Array) -> void:
	var tile: Dictionary = game._tile_at(property_id)
	if tile.is_empty():
		return
	var old_owner: int = int(tile.get("owner", -1))
	tile["owner"] = -1
	tile["building_level"] = 0
	tile["is_chain_store"] = false
	game._update_tile_rent(tile)
	for player_id in range(game._players().size()):
		game._remove_property_reference(player_id, property_id)
	cleared.append({"tile_id": property_id, "kind": "property", "owner": old_owner})


static func _clear_facility(game: Object, source_id: int, cleared: Array) -> void:
	var indices: Array = game._facility_indices(int(source_id))
	if indices.is_empty():
		return
	indices.sort()
	var canonical_index: int = game._facility_canonical_index(int(indices[0]))
	var facility: Dictionary = game._facility_record(canonical_index)
	if facility.is_empty():
		return
	var old_owner: int = int(facility.get("owner", -1))
	game._update_facility_records(int(source_id), {"owner": -1, "building_level": 0, "facility_type": 0})
	for player_id in range(game._players().size()):
		for index_value in indices:
			game._remove_property_reference(player_id, int(index_value))
	cleared.append({"source_object_id": source_id, "tile_id": canonical_index, "owner": old_owner})


static func _has_logical_coordinates(tile: Dictionary) -> bool:
	return typeof(tile.get("x", null)) == TYPE_INT and typeof(tile.get("y", null)) == TYPE_INT
