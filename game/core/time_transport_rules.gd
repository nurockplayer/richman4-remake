class_name RichmanTimeTransportRules
extends RefCounted

const OriginalInventory = preload("res://game/core/inventory_rules.gd")
const OriginalGods = preload("res://game/content/original_gods.gd")

## Runtime rules for the original research tools 時光機 (ID10) and 傳送機
## (ID11).  GameState owns the save and private-anchor containers; this module
## keeps the public validation, read-only selectors and effect boundaries in
## one place.

const TIME_MACHINE := "時光機"
const TRANSPORTER := "傳送機"
const TARGET_KINDS := ["property", "facility", "player", "god"]
const REQUEST_KEYS := ["tool_id", "target_kind", "target_id", "destination_id", "cancel"]
const CATEGORY_IDS := {
	"property": 0,
	"facility": 1,
	"player": 2,
	"god": 3,
}


static func is_supported(game: Object) -> bool:
	return game != null and game.has_method("_is_inventory") and game.has_method("_is_graph") and game.has_method("_is_research") and game._is_inventory() and game._is_graph() and game._is_research()


static func is_tool(tool_id: String) -> bool:
	return tool_id == TIME_MACHINE or tool_id == TRANSPORTER


static func category_id(target_kind: String) -> int:
	return int(CATEGORY_IDS.get(target_kind, -1))


static func target_kind_for_category(category: int) -> String:
	for target_kind in CATEGORY_IDS.keys():
		if int(CATEGORY_IDS[target_kind]) == category:
			return str(target_kind)
	return ""


static func transport_targets(game: Object, target_kind: String) -> Array:
	var targets: Array = []
	if not _transport_context_available(game):
		return targets
	var normalized_kind := target_kind.to_lower().strip_edges()
	if not TARGET_KINDS.has(normalized_kind):
		return targets
	var player_id := int(game.state.get("current_player", -1))
	if _transport_target_context_error(game, player_id).is_empty():
		for candidate in _target_ids(game, player_id, normalized_kind):
			if _transport_target_error(game, player_id, normalized_kind, int(candidate)).is_empty():
				targets.append(int(candidate))
	targets.sort()
	return targets


static func transport_destinations(game: Object, target_kind: String, target_id: Variant) -> Array:
	var destinations: Array = []
	if not _transport_context_available(game):
		return destinations
	var normalized_kind := target_kind.to_lower().strip_edges()
	if not TARGET_KINDS.has(normalized_kind) or typeof(target_id) != TYPE_INT:
		return destinations
	var player_id := int(game.state.get("current_player", -1))
	var source_error := _transport_target_error(game, player_id, normalized_kind, int(target_id))
	if not source_error.is_empty():
		return destinations
	for node_id in range(game.state.get("board", []).size()):
		if _transport_destination_error(game, player_id, normalized_kind, int(target_id), node_id).is_empty():
			destinations.append(node_id)
	if normalized_kind == "facility":
		# A facility has multiple entrances but one selectable asset.  Return the
		# declared canonical node once, in board order.
		var canonical: Array = []
		for node_id in destinations:
			var canonical_id := int(game._facility_canonical_index(int(node_id)))
			if not canonical.has(canonical_id):
				canonical.append(canonical_id)
		destinations = canonical
	else:
		destinations.sort()
	return destinations


static func time_machine_status(game: Object) -> Dictionary:
	var status := {"available": false, "message": ""}
	if not is_supported(game):
		status["message"] = "時光機只適用於研究所圖形地圖。"
		return status
	var player_id := int(game.state.get("current_player", -1))
	var player: Dictionary = game._player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		status["message"] = "目前玩家無法使用時光機。"
		return status
	if not bool(player.get("is_human", false)) or bool(player.get("is_ai", false)):
		status["message"] = "時光機只能由人類玩家使用。"
		return status
	if int(player.get("tools", {}).get(TIME_MACHINE, 0)) <= 0:
		status["message"] = "目前沒有時光機。"
		return status
	if str(game.state.get("phase", "")) != "await_roll":
		status["message"] = "時光機只能在擲骰前使用。"
		return status
	var anchor: Dictionary = game._time_anchor_snapshot(player_id)
	if anchor.is_empty():
		status["message"] = "尚未有可用的回溯紀錄；讀檔後請先完成一次正常移動。"
		return status
	if not _anchor_matches_player(game, anchor, player_id):
		status["message"] = "回溯紀錄已失效；請先完成一次正常移動。"
		return status
	var anchor_players: Variant = anchor.get("players", null)
	if typeof(anchor_players) != TYPE_ARRAY or player_id < 0 or player_id >= anchor_players.size() or typeof(anchor_players[player_id]) != TYPE_DICTIONARY:
		status["message"] = "回溯紀錄缺少目前玩家資料。"
		return status
	var anchor_player: Dictionary = anchor_players[player_id]
	var anchor_tools: Variant = anchor_player.get("tools", null)
	if typeof(anchor_tools) != TYPE_DICTIONARY or int(anchor_tools.get(TIME_MACHINE, 0)) <= 0:
		status["message"] = "上次移動前沒有時光機，無法回到那個時間點。"
		return status
	status["available"] = true
	status["message"] = "可回到上次正常移動前。"
	return status


static func use_transport(game: Object, player_id: int, params: Dictionary) -> Dictionary:
	var parameter_error := _transport_parameter_error(params)
	if not parameter_error.is_empty():
		return game._error(parameter_error)
	if not is_supported(game):
		return game._error("傳送機只適用於研究所圖形地圖。")
	var actor: Dictionary = game._player(player_id)
	if actor.is_empty() or not bool(actor.get("alive", false)):
		return game._error("目前玩家無法使用傳送機。")
	var context_error := _transport_target_context_error(game, player_id)
	if not context_error.is_empty():
		return game._error(context_error)
	var tools: Variant = actor.get("tools", null)
	if typeof(tools) != TYPE_DICTIONARY or int(tools.get(TRANSPORTER, 0)) <= 0:
		return game._error("玩家沒有傳送機。")
	var cancel := bool(params.get("cancel", false))
	if cancel:
		return game._result(true, "已取消傳送機", {"tool_id": TRANSPORTER, "cancelled": true})
	var target_kind := str(params.get("target_kind", "")).to_lower().strip_edges()
	var target_id := int(params.get("target_id", -1))
	var destination_id := int(params.get("destination_id", -1))
	var target_error := _transport_target_error(game, player_id, target_kind, target_id)
	if not target_error.is_empty():
		return game._error(target_error)
	var destination_error := _transport_destination_error(game, player_id, target_kind, target_id, destination_id)
	if not destination_error.is_empty():
		return game._error(destination_error)

	# The anchor is private and is captured only after every public legality
	# check, immediately before the first transport mutation.
	var canonical_target_id := target_id
	if target_kind == "facility":
		canonical_target_id = int(game._facility_canonical_index(target_id))
	var captures_actor_anchor: bool = target_kind == "player" and target_id == player_id
	if target_kind == "god":
		var god_target: Dictionary = game._god_object(target_id)
		captures_actor_anchor = int(god_target.get("owner", -1)) == player_id
	if captures_actor_anchor:
		game._capture_time_anchor(player_id)

	var consume_result: Dictionary = OriginalInventory.consume_tool(game.state["inventory_supply"], actor["tools"], TRANSPORTER, 1)
	if not bool(consume_result.get("ok", false)):
		return game._error(str(consume_result.get("error", "傳送機無法使用")))
	var effect_error := _apply_transport(game, player_id, target_kind, canonical_target_id, destination_id)
	if not effect_error.is_empty():
		# All effect failures are preflighted above. Keep this defensive branch
		# explicit; no inventory is restored because it is unreachable for valid
		# state and would otherwise conceal a broken map contract.
		return game._error(effect_error)
	game._record_event("tool_used", {
		"player_id": player_id,
		"tool_id": TRANSPORTER,
		"target_kind": target_kind,
		"target_id": canonical_target_id,
		"destination_id": destination_id,
		"effect": "transport",
	})
	game._set_action_options(player_id)
	return game._result(true, "已使用傳送機", {"tool_id": TRANSPORTER, "target_kind": target_kind, "target_id": canonical_target_id, "destination_id": destination_id})


static func use_time_machine(game: Object, player_id: int, params: Dictionary) -> Dictionary:
	var parameter_error := _time_parameter_error(params)
	if not parameter_error.is_empty():
		return game._error(parameter_error)
	if not is_supported(game):
		return game._error("時光機只適用於研究所圖形地圖。")
	var player: Dictionary = game._player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return game._error("目前玩家無法使用時光機。")
	if not bool(player.get("is_human", false)) or bool(player.get("is_ai", false)):
		return game._error("時光機只能由人類玩家使用。")
	if str(game.state.get("phase", "")) != "await_roll":
		return game._error("時光機只能在擲骰前使用。")
	var current_tools: Variant = player.get("tools", null)
	if typeof(current_tools) != TYPE_DICTIONARY or int(current_tools.get(TIME_MACHINE, 0)) <= 0:
		return game._error("玩家沒有時光機。")
	if bool(params.get("cancel", false)):
		return game._result(true, "已取消時光機", {"tool_id": TIME_MACHINE, "cancelled": true})
	var anchor: Dictionary = game._time_anchor_snapshot(player_id)
	if anchor.is_empty() or not _anchor_matches_player(game, anchor, player_id):
		return game._error("沒有可用的回溯紀錄；請先完成一次正常移動。")
	var anchor_players: Variant = anchor.get("players", null)
	if typeof(anchor_players) != TYPE_ARRAY or player_id < 0 or player_id >= anchor_players.size() or typeof(anchor_players[player_id]) != TYPE_DICTIONARY:
		return game._error("回溯紀錄缺少目前玩家資料。")
	var anchor_player: Dictionary = anchor_players[player_id]
	var anchor_tools: Variant = anchor_player.get("tools", null)
	if typeof(anchor_tools) != TYPE_DICTIONARY or int(anchor_tools.get(TIME_MACHINE, 0)) <= 0:
		return game._error("上次移動前沒有時光機，無法回到那個時間點。")

	# Build and validate the complete restored world before touching the live
	# state. The live RNG is deliberately retained as the continuation point.
	var staged: Dictionary = anchor.duplicate(true)
	var current_rng: int = int(game._rng.state)
	staged["rng_state"] = current_rng
	staged["rng_state_text"] = str(current_rng)
	var staged_players: Variant = staged.get("players", null)
	if typeof(staged_players) != TYPE_ARRAY or player_id < 0 or player_id >= staged_players.size() or typeof(staged_players[player_id]) != TYPE_DICTIONARY:
		return game._error("回溯紀錄中的玩家資料無效。")
	var staged_player: Dictionary = staged_players[player_id]
	var staged_consume: Dictionary = OriginalInventory.consume_tool(staged["inventory_supply"], staged_player["tools"], TIME_MACHINE, 1)
	if not bool(staged_consume.get("ok", false)):
		return game._error("回溯紀錄中的時光機無法消耗。")
	var staged_validation: Dictionary = game.validate_save(staged)
	if not bool(staged_validation.get("ok", false)):
		return game._error("目前無法依回溯紀錄還原上次移動。")

	# Store the post-debit anchor before adding the live event. A later use can
	# restore the post-debit world but cannot replenish the consumed machine.
	game.state = staged
	game._rng.state = current_rng
	game._replace_time_anchor_after_restore(player_id, staged)
	game._set_action_options(player_id)
	game._record_event("tool_used", {"player_id": player_id, "tool_id": TIME_MACHINE, "effect": "time_restore"})
	return game._result(true, "已回到上次移動前", {"tool_id": TIME_MACHINE, "effect": "time_restore"})


static func _transport_context_available(game: Object) -> bool:
	if not is_supported(game):
		return false
	var player_id := int(game.state.get("current_player", -1))
	return _transport_target_context_error(game, player_id).is_empty()


static func _transport_target_context_error(game: Object, player_id: int) -> String:
	if str(game.state.get("phase", "")) != "await_roll":
		return "目前不是擲骰階段"
	var player: Dictionary = game._player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return "目前玩家無法行動"
	if game._status_active(player) or game._inventory_movement_blocked(player):
		return "目前狀態無法使用傳送機"
	return ""


static func _target_ids(game: Object, player_id: int, target_kind: String) -> Array:
	var ids: Array = []
	var board: Array = game.state.get("board", [])
	if target_kind == "property":
		for tile_value in board:
			if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "property":
				continue
			if int(tile_value.get("owner", -1)) >= 0 or int(tile_value.get("building_level", 0)) > 0:
				ids.append(int(tile_value.get("index", -1)))
	elif target_kind == "facility":
		var seen_sources: Dictionary = {}
		for tile_value in board:
			if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility":
				continue
			var source_id := int(tile_value.get("source_object_id", -1))
			if source_id <= 0 or seen_sources.has(source_id):
				continue
			seen_sources[source_id] = true
			var index := int(tile_value.get("index", -1))
			ids.append(int(game._facility_canonical_index(index)))
	elif target_kind == "player":
		for candidate in game._players():
			if typeof(candidate) == TYPE_DICTIONARY and bool(candidate.get("alive", false)) and not game._status_active(candidate):
				ids.append(int(candidate.get("id", -1)))
	elif target_kind == "god":
		var objects: Variant = game.state.get("god_objects", [])
		if typeof(objects) == TYPE_ARRAY:
			for actor_value in objects:
				if typeof(actor_value) != TYPE_DICTIONARY:
					continue
				var actor: Dictionary = actor_value
				var god_id: Variant = actor.get("id", null)
				if not game._valid_int(god_id, 1, 15) or not OriginalGods.valid_id(god_id):
					continue
				var owner_id := int(actor.get("owner", -1))
				if owner_id >= 0:
					var owner: Dictionary = game._player(owner_id)
					if owner.is_empty() or not bool(owner.get("alive", false)) or game._status_active(owner):
						continue
				ids.append(int(god_id))
	return ids


static func _transport_target_error(game: Object, player_id: int, target_kind: String, target_id: int) -> String:
	if not TARGET_KINDS.has(target_kind):
		return "傳送目標類型無效"
	var board: Array = game.state.get("board", [])
	if target_kind == "property":
		if target_id < 0 or target_id >= board.size() or typeof(board[target_id]) != TYPE_DICTIONARY or board[target_id].get("kind", "") != "property":
			return "住宅傳送來源無效"
		var tile: Dictionary = board[target_id]
		if int(tile.get("owner", -1)) < 0 and int(tile.get("building_level", 0)) <= 0:
			return "住宅沒有可傳送的建物或所有權"
		return ""
	if target_kind == "facility":
		if target_id < 0 or target_id >= board.size() or typeof(board[target_id]) != TYPE_DICTIONARY or board[target_id].get("kind", "") != "facility":
			return "設施傳送來源無效"
		var facility: Dictionary = game._facility_record(target_id)
		if facility.is_empty():
			return "設施傳送來源無效"
		if int(facility.get("owner", -1)) < 0 and int(facility.get("building_level", 0)) <= 0 and int(facility.get("facility_type", 0)) <= 0:
			return "設施沒有可傳送的建物或所有權"
		return ""
	if target_kind == "player":
		if target_id < 0 or target_id >= game._players().size():
			return "玩家傳送來源無效"
		var target_player: Dictionary = game._player(target_id)
		if target_player.is_empty() or not bool(target_player.get("alive", false)) or game._status_active(target_player):
			return "玩家必須存活且不在拘留狀態"
		var position: Variant = target_player.get("position", null)
		if typeof(position) != TYPE_INT or position < 0 or position >= board.size():
			return "玩家位置無效"
		return ""
	# God target IDs are unique source identities, not array indexes.
	var god: Dictionary = game._god_object(target_id)
	if god.is_empty():
		return "神明傳送來源無效"
	var owner_id := int(god.get("owner", -1))
	if owner_id >= 0:
		var owner: Dictionary = game._player(owner_id)
		if owner.is_empty() or not bool(owner.get("alive", false)) or game._status_active(owner):
			return "附身神明的玩家目前無法傳送"
	return ""


static func _transport_destination_error(game: Object, player_id: int, target_kind: String, target_id: int, destination_id: int) -> String:
	var board: Array = game.state.get("board", [])
	if destination_id < 0 or destination_id >= board.size() or typeof(board[destination_id]) != TYPE_DICTIONARY:
		return "傳送目的地無效"
	var source_node := _target_source_node(game, target_kind, target_id)
	if source_node < 0:
		return "傳送來源無效"
	if target_kind == "facility":
		if board[destination_id].get("kind", "") != "facility":
			return "設施傳送目的地必須是另一項設施"
		destination_id = int(game._facility_canonical_index(destination_id))
		if source_node == destination_id:
			return "傳送來源與目的地不可相同"
		var destination_facility: Dictionary = game._facility_record(destination_id)
		if destination_facility.is_empty() or int(destination_facility.get("source_object_id", -1)) == int(game._facility_record(source_node).get("source_object_id", -2)):
			return "設施傳送目的地必須是另一項設施"
		if int(destination_facility.get("owner", -1)) != -1 or int(destination_facility.get("building_level", 0)) != 0 or int(destination_facility.get("facility_type", 0)) != 0:
			return "設施目的地必須是空的"
		return ""
	if target_kind == "property":
		if source_node == destination_id:
			return "傳送來源與目的地不可相同"
		var destination_property: Dictionary = board[destination_id]
		if destination_property.get("kind", "") != "property":
			return "住宅傳送目的地必須是另一間住宅"
		if int(destination_property.get("owner", -1)) != -1 or int(destination_property.get("building_level", 0)) != 0 or bool(destination_property.get("is_chain_store", false)):
			return "住宅目的地必須是空的"
		return ""
	if target_kind == "player":
		var target_player: Dictionary = game._player(target_id)
		if source_node == destination_id:
			return "玩家傳送目的地必須不同"
		if not game._is_graph_road_tile(board[destination_id]):
			return "玩家目的地不是可通行道路"
		if _dynamic_destination_blocked(game, destination_id, -1):
			return "玩家目的地已有道路物件"
		if not _direction_previous_valid(game, target_player, destination_id):
			return "玩家目的地方向無效"
		return ""
	# Attached god targets resolve to their owner; unbound gods occupy their node.
	var god: Dictionary = game._god_object(target_id)
	var owner_id := int(god.get("owner", -1))
	if owner_id >= 0:
		if source_node == destination_id:
			return "神明傳送目的地必須不同"
		if not game._is_graph_road_tile(board[destination_id]):
			return "附身神明目的地不是可通行道路"
		if _dynamic_destination_blocked(game, destination_id, -1):
			return "附身神明目的地已有道路物件"
		return ""
	if source_node == destination_id:
		return "神明傳送目的地必須不同"
	var occupied: Dictionary = _god_destination_occupancy(game, target_id)
	if not OriginalGods.source_tile_eligible(board[destination_id], occupied):
		return "神明目的地不符合來源道路條件"
	if _dynamic_destination_blocked(game, destination_id, target_id):
		return "神明目的地已有道路物件"
	return ""


static func _target_source_node(game: Object, target_kind: String, target_id: int) -> int:
	if target_kind == "property":
		return target_id
	if target_kind == "facility":
		return int(game._facility_canonical_index(target_id))
	if target_kind == "player":
		var player: Dictionary = game._player(target_id)
		return int(player.get("position", -1))
	var god: Dictionary = game._god_object(target_id)
	if int(god.get("owner", -1)) >= 0:
		return int(game._player(int(god.get("owner", -1))).get("position", -1))
	return int(god.get("node", -1))


static func _dynamic_destination_blocked(game: Object, node_id: int, ignored_god_id: int) -> bool:
	var roadblocks: Variant = game.state.get("roadblocks", {})
	if typeof(roadblocks) == TYPE_DICTIONARY and roadblocks.has(str(node_id)):
		return true
	if not game._ground_hazard_at(node_id).is_empty():
		return true
	var objects: Variant = game.state.get("god_objects", [])
	if typeof(objects) == TYPE_ARRAY:
		for actor_value in objects:
			if typeof(actor_value) != TYPE_DICTIONARY:
				continue
			var actor: Dictionary = actor_value
			if int(actor.get("id", -1)) == ignored_god_id or int(actor.get("owner", -1)) >= 0:
				continue
			if int(actor.get("node", -1)) == node_id:
				return true
	return false


static func _god_destination_occupancy(game: Object, ignored_god_id: int) -> Dictionary:
	var occupied: Dictionary = {}
	for player in game._players():
		if typeof(player) != TYPE_DICTIONARY or not bool(player.get("alive", false)):
			continue
		var position: Variant = player.get("position", null)
		if typeof(position) == TYPE_INT:
			occupied[int(position)] = true
	var objects: Variant = game.state.get("god_objects", [])
	if typeof(objects) == TYPE_ARRAY:
		for actor_value in objects:
			if typeof(actor_value) != TYPE_DICTIONARY:
				continue
			var actor: Dictionary = actor_value
			if int(actor.get("id", -1)) == ignored_god_id:
				continue
			var node := int(actor.get("node", -1))
			var owner_id := int(actor.get("owner", -1))
			if owner_id >= 0:
				node = int(game._player(owner_id).get("position", node))
			if node >= 0:
				occupied[node] = true
	return occupied


static func _direction_previous_valid(game: Object, player: Dictionary, destination_id: int) -> bool:
	var board: Array = game.state.get("board", [])
	if destination_id < 0 or destination_id >= board.size() or typeof(board[destination_id]) != TYPE_DICTIONARY:
		return false
	var adjacent: Variant = board[destination_id].get("adjacent", null)
	return typeof(adjacent) == TYPE_ARRAY and not adjacent.is_empty()


static func _apply_transport(game: Object, player_id: int, target_kind: String, target_id: int, destination_id: int) -> String:
	if target_kind == "property":
		var source: Dictionary = game._tile_at(target_id)
		var destination: Dictionary = game._tile_at(destination_id)
		var owner := int(source.get("owner", -1))
		var level := int(source.get("building_level", 0))
		var chain := bool(source.get("is_chain_store", false))
		source["owner"] = -1
		source["building_level"] = 0
		source["is_chain_store"] = false
		game._update_tile_rent(source)
		destination["owner"] = owner
		destination["building_level"] = level
		destination["is_chain_store"] = chain
		game._update_tile_rent(destination)
		game._remove_property_reference(owner, target_id)
		game._add_property_reference(owner, destination_id)
		game._recalculate_property_values()
		return ""
	if target_kind == "facility":
		var source_record: Dictionary = game._facility_record(target_id)
		var destination_record: Dictionary = game._facility_record(destination_id)
		if source_record.is_empty() or destination_record.is_empty():
			return "設施傳送資料無效"
		var owner := int(source_record.get("owner", -1))
		var level := int(source_record.get("building_level", 0))
		var facility_type := int(source_record.get("facility_type", 0))
		game._update_facility_records(int(source_record.get("source_object_id", -1)), {"owner": -1, "building_level": 0, "facility_type": 0})
		game._update_facility_records(int(destination_record.get("source_object_id", -1)), {"owner": owner, "building_level": level, "facility_type": facility_type})
		var source_canonical := int(game._facility_canonical_index(target_id))
		var destination_canonical := int(game._facility_canonical_index(destination_id))
		game._remove_property_reference(owner, source_canonical)
		game._add_property_reference(owner, destination_canonical)
		game._recalculate_property_values()
		return ""
	if target_kind == "player":
		var target_player: Dictionary = game._player(target_id)
		var previous := _direction_previous_node(game, target_player, destination_id)
		target_player["previous_position"] = previous
		target_player["position"] = destination_id
		game._sync_attached_gods()
		return ""
	var god: Dictionary = game._god_object(target_id)
	if int(god.get("owner", -1)) >= 0:
		var target_player: Dictionary = game._player(int(god.get("owner", -1)))
		var previous := _direction_previous_node(game, target_player, destination_id)
		target_player["previous_position"] = previous
		target_player["position"] = destination_id
		game._sync_attached_gods()
	else:
		god["node"] = destination_id
	return ""


static func _direction_previous_node(game: Object, player: Dictionary, destination_id: int) -> int:
	var board: Array = game.state.get("board", [])
	if destination_id < 0 or destination_id >= board.size() or typeof(board[destination_id]) != TYPE_DICTIONARY:
		return -1
	var destination: Dictionary = board[destination_id]
	var adjacent: Array = destination.get("adjacent", []).duplicate()
	var valid: Array = []
	for candidate in adjacent:
		if typeof(candidate) == TYPE_INT and candidate >= 0 and candidate < board.size() and typeof(board[candidate]) == TYPE_DICTIONARY:
			valid.append(int(candidate))
	valid.sort()
	if valid.is_empty():
		return -1
	var current_id := int(player.get("position", -1))
	var previous_id := int(player.get("previous_position", -1))
	if current_id < 0 or current_id >= board.size() or previous_id < 0 or previous_id >= board.size() or typeof(board[current_id]) != TYPE_DICTIONARY or typeof(board[previous_id]) != TYPE_DICTIONARY:
		return valid[0]
	var current: Dictionary = board[current_id]
	var previous: Dictionary = board[previous_id]
	var travel_x := float(int(current.get("x", 0)) - int(previous.get("x", 0)))
	var travel_y := float(int(current.get("y", 0)) - int(previous.get("y", 0)))
	var travel_length := sqrt(travel_x * travel_x + travel_y * travel_y)
	if travel_length <= 0.0:
		return valid[0]
	var best_id: int = int(valid[0])
	var best_score := -INF
	for candidate_id in valid:
		var candidate: Dictionary = board[int(candidate_id)]
		var candidate_x := float(int(candidate.get("x", 0)) - int(destination.get("x", 0)))
		var candidate_y := float(int(candidate.get("y", 0)) - int(destination.get("y", 0)))
		var candidate_length := sqrt(candidate_x * candidate_x + candidate_y * candidate_y)
		if candidate_length <= 0.0:
			continue
		var score := ((-travel_x * candidate_x) + (-travel_y * candidate_y)) / (travel_length * candidate_length)
		if score > best_score + 0.000001:
			best_score = score
			best_id = int(candidate_id)
	return best_id


static func _anchor_matches_player(game: Object, anchor: Dictionary, player_id: int) -> bool:
	if anchor.is_empty() or str(anchor.get("phase", "")) != "await_roll" or int(anchor.get("current_player", -1)) != player_id:
		return false
	var validation: Dictionary = game.validate_save(anchor)
	if not bool(validation.get("ok", false)):
		return false
	var players: Variant = anchor.get("players", null)
	return typeof(players) == TYPE_ARRAY and player_id >= 0 and player_id < players.size() and typeof(players[player_id]) == TYPE_DICTIONARY and bool(players[player_id].get("is_human", false)) and not bool(players[player_id].get("is_ai", false))


static func _transport_parameter_error(params: Dictionary) -> String:
	if typeof(params) != TYPE_DICTIONARY:
		return "傳送機操作格式無效"
	for key in params.keys():
		if typeof(key) != TYPE_STRING or not REQUEST_KEYS.has(str(key)):
			return "傳送機操作格式無效"
	if not params.has("tool_id") or typeof(params.get("tool_id")) != TYPE_STRING or str(params.get("tool_id")) != TRANSPORTER:
		return "傳送機道具代號格式無效"
	if params.has("cancel") and typeof(params.get("cancel")) != TYPE_BOOL:
		return "傳送機取消參數格式無效"
	for key in ["target_kind"]:
		if params.has(key) and typeof(params.get(key)) != TYPE_STRING:
			return "傳送目標格式無效"
	for key in ["target_id", "destination_id"]:
		if params.has(key) and typeof(params.get(key)) != TYPE_INT:
			return "傳送節點格式無效"
	if bool(params.get("cancel", false)):
		return ""
	if not params.has("target_kind") or not params.has("target_id") or not params.has("destination_id"):
		return "傳送機缺少目標或目的地"
	return ""


static func _time_parameter_error(params: Dictionary) -> String:
	if typeof(params) != TYPE_DICTIONARY:
		return "時光機操作格式無效"
	for key in params.keys():
		if typeof(key) != TYPE_STRING or not REQUEST_KEYS.has(str(key)):
			return "時光機操作格式無效"
	if not params.has("tool_id") or typeof(params.get("tool_id")) != TYPE_STRING or str(params.get("tool_id")) != TIME_MACHINE:
		return "時光機道具代號格式無效"
	if params.has("cancel") and typeof(params.get("cancel")) != TYPE_BOOL:
		return "時光機取消參數格式無效"
	for key in ["target_kind", "target_id", "destination_id"]:
		if params.has(key):
			return "時光機不接受傳送目標"
	return ""
