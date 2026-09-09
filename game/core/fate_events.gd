class_name Richman4FateEvents
extends RefCounted

## Bounded adapter for the source event_code == 3 (命運) dispatcher.
##
## The source has one common 0..32 table and four map-specific prison entries.
## This module keeps the deck and immutable result shape together while routing
## gameplay mutations through GameState's existing accounting primitives.

const COUNT := 37
const COMMON_COUNT := 33
const UNSUPPORTED_IDS := [2, 3, 5, 6, 7, 8, 9, 32]
const MAP_PRISON_DAYS := {33: 3, 34: 5, 35: 7, 36: 9}
const INCOME_AMOUNTS := {
	20: 1000, 21: 3000, 22: 2000, 25: 10000, 27: 4000, 28: 6000, 29: 8000, 31: 5000,
}
const EXPENSE_AMOUNTS := {
	14: 3000, 15: 3000, 16: 3000, 17: 6000, 18: 600, 19: 1500,
	23: 1000, 24: 2000, 26: 8000, 30: 5000,
}
const LAST_KEYS := [
	"candidate_id", "id", "map_slot", "player_id", "targets", "changes", "summary",
	"outcome", "raw_amount", "raw_days", "gate_result",
]

const _NAMES := [
	"拆除房屋", "出售土地", "取得貸款", "銀行拒絕貸款", "存款轉移",
	"失蹤", "失蹤", "失蹤", "股票小幅出售", "股票全部出售",
	"機車故障", "汽車故障", "住院", "住院", "交通罰款",
	"交通事故", "交通事故", "繳交費用", "支付費用", "支付費用",
	"獲得獎金", "獲得獎金", "獲得獎金", "支付費用", "支付費用",
	"獲得獎金", "支付費用", "獲得獎金", "獲得獎金", "獲得獎金",
	"支付費用", "獲得獎金", "出售所有物品", "酒後駕車入獄", "違規入獄",
	"違規入獄", "違規入獄",
]


static func catalog() -> Array:
	var result: Array = []
	for event_id in range(COUNT):
		result.append({
			"id": event_id,
			"name": name_for(event_id),
			"adapter_status": "unsupported" if not is_supported(event_id) else "supported",
		})
	return result


static func is_supported(event_id: Variant) -> bool:
	return _valid_int(event_id, 0, COUNT - 1) and not UNSUPPORTED_IDS.has(int(event_id))


static func name_for(event_id: Variant) -> String:
	if not _valid_int(event_id, 0, COUNT - 1):
		return "未知命運"
	return str(_NAMES[int(event_id)])


static func new_state(rng: RandomNumberGenerator) -> Dictionary:
	var order: Array = []
	for event_id in range(COUNT):
		order.append(event_id)
	if rng != null:
		for index in range(COUNT - 1, 0, -1):
			var swap_index: int = rng.randi_range(0, index)
			var value: Variant = order[index]
			order[index] = order[swap_index]
			order[swap_index] = value
	return {"order": order, "cursor": 0, "draw_count": 0, "last": {}}


static func validate_state(value: Variant) -> Dictionary:
	var errors: Array = []
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["fate must be a dictionary"]}
	var fate: Dictionary = value
	if fate.size() != 4:
		errors.append("fate keys are not canonical")
	for key in ["order", "cursor", "draw_count", "last"]:
		if not fate.has(key):
			errors.append("fate missing %s" % key)
	var order: Variant = fate.get("order", null)
	if typeof(order) != TYPE_ARRAY or order.size() != COUNT:
		errors.append("fate order must contain 37 candidates")
	else:
		var seen: Dictionary = {}
		for event_id in order:
			if not _valid_int(event_id, 0, COUNT - 1) or seen.has(int(event_id)):
				errors.append("fate order is not a permutation")
			else:
				seen[int(event_id)] = true
		if seen.size() != COUNT:
			errors.append("fate order is not a permutation")
	var cursor: Variant = fate.get("cursor", null)
	if not _valid_int(cursor, 0, COUNT - 1):
		errors.append("fate cursor is invalid")
	var draw_count: Variant = fate.get("draw_count", null)
	if not _valid_int(draw_count, 0, 1000000000):
		errors.append("fate draw count is invalid")
	var last: Variant = fate.get("last", null)
	if typeof(last) != TYPE_DICTIONARY:
		errors.append("fate last result is invalid")
	elif not last.is_empty():
		errors.append_array(_validate_last(last))
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": []}


static func _validate_last(last: Dictionary) -> Array:
	var errors: Array = []
	if last.size() != LAST_KEYS.size():
		errors.append("fate last keys are not canonical")
	for key in LAST_KEYS:
		if not last.has(key):
			errors.append("fate last missing %s" % key)
	if not _valid_int(last.get("candidate_id", null), 0, COUNT - 1):
		errors.append("fate last candidate is invalid")
	if not _valid_int(last.get("id", null), 0, COUNT - 1) or not is_supported(last.get("id", -1)):
		errors.append("fate last id is unsupported")
	if not _valid_int(last.get("map_slot", null), 0, 4095):
		errors.append("fate last map slot is invalid")
	if not _valid_int(last.get("player_id", null), 0, 3):
		errors.append("fate last player is invalid")
	if typeof(last.get("targets", null)) != TYPE_ARRAY:
		errors.append("fate last targets are invalid")
	if typeof(last.get("changes", null)) != TYPE_ARRAY:
		errors.append("fate last changes are invalid")
	else:
		for change in last.get("changes", []):
			if typeof(change) != TYPE_DICTIONARY:
				errors.append("fate last change is invalid")
	if typeof(last.get("summary", null)) != TYPE_STRING or str(last.get("summary", "")).is_empty():
		errors.append("fate last summary is invalid")
	if not ["applied", "blocked", "unsupported", "unresolved"].has(str(last.get("outcome", ""))):
		errors.append("fate last outcome is invalid")
	if not _valid_int(last.get("raw_amount", null), 0, 1000000000000):
		errors.append("fate last amount is invalid")
	if not _valid_int(last.get("raw_days", null), 0, 128):
		errors.append("fate last duration is invalid")
	if not _valid_int(last.get("gate_result", null), 0, 2):
		errors.append("fate last gate result is invalid")
	return errors


static func has_eligible_target(game: Object, event_id: int) -> bool:
	if game == null or not is_supported(event_id):
		return false
	var player_id: int = int(game.state.get("current_player", -1))
	if not _valid_player(game, player_id):
		return false
	var player: Dictionary = game.state.players[player_id]
	match event_id:
		0:
			return not _housing_targets(game, player_id, true).is_empty()
		1:
			return not _housing_targets(game, player_id, false).is_empty()
		4:
			# The source dispatcher treats this common candidate as eligible even
			# when every donor has a zero balance; the apply result then records an
			# empty transfer target list.
			return true
		10, 11:
			return str(player.get("vehicle", "walking")) in ["motorcycle", "car"]
		12, 13:
			return str(player.get("vehicle", "walking")) in ["walking", "motorcycle"]
		14, 15, 16:
			return str(player.get("vehicle", "walking")) in ["walking", "motorcycle", "car"]
		33, 34, 35, 36:
			return _map_prison_available(game)
		_:
			return true


static func apply_landing(game: Object, player_id: int) -> void:
	if game == null or not _valid_player(game, player_id):
		return
	var state: Dictionary = game.state
	var fate_value: Variant = state.get("fate", null)
	var fate: Dictionary
	if fate_value == null:
		fate = new_state(game._rng)
		state["fate"] = fate
	else:
		if typeof(fate_value) != TYPE_DICTIONARY or not bool(validate_state(fate_value).get("ok", false)):
			game._record_event("fate_skipped", {"player_id": player_id, "reason": "invalid_state"})
			return
		fate = fate_value
	var order: Array = fate.get("order", [])
	var cursor_before: int = int(fate.get("cursor", 0))
	var cursor: int = cursor_before
	var selected_id: int = -1
	var selected_cursor_before: int = cursor_before
	for attempt in range(COUNT):
		var candidate_cursor: int = cursor
		var candidate_id: int = int(order[candidate_cursor])
		cursor = (candidate_cursor + 1) % COUNT
		var preview: Dictionary = {
			"player_id": player_id,
			"candidate_id": candidate_id,
			"name": name_for(candidate_id),
			"attempt": attempt + 1,
			"cursor_before": candidate_cursor,
			"cursor_after": cursor,
		}
		game._record_event("fate_preview", preview)
		var skip_reason := ""
		if not is_supported(candidate_id):
			skip_reason = "unsupported"
		elif not has_eligible_target(game, candidate_id):
			skip_reason = "no_compatible_target"
		if not skip_reason.is_empty():
			preview["reason"] = skip_reason
			game._record_event("fate_skipped", preview)
			continue
		selected_id = candidate_id
		selected_cursor_before = candidate_cursor
		break
	fate["cursor"] = cursor
	state["fate"] = fate
	if selected_id < 0:
		game._record_event("fate_skipped", {"player_id": player_id, "reason": "no_eligible", "cursor_before": cursor_before, "cursor_after": cursor})
		return
	var result: Dictionary = resolve(game, player_id, selected_id)
	if not bool(result.get("ok", false)):
		game._record_event("fate_skipped", {"player_id": player_id, "candidate_id": selected_id, "reason": str(result.get("reason", "apply_failed")), "cursor_before": selected_cursor_before, "cursor_after": cursor})
		return
	var old_draw_count: int = int(fate.get("draw_count", 0))
	var draw_count: int = mini(1000000000, old_draw_count + 1)
	fate["draw_count"] = draw_count
	var last: Dictionary = _canonical_last(player_id, selected_id, result)
	fate["last"] = last
	state["fate"] = fate
	game._record_event("fate_resolved", {
		"player_id": player_id,
		"candidate_id": selected_id,
		"id": int(last.get("id", selected_id)),
		"map_slot": int(last.get("map_slot", selected_id)),
		"targets": last["targets"],
		"changes": last["changes"],
		"summary": last["summary"],
		"outcome": last["outcome"],
		"draw_count": draw_count,
		"cursor_before": selected_cursor_before,
		"cursor_after": cursor,
	})


static func _canonical_last(player_id: int, candidate_id: int, result: Dictionary) -> Dictionary:
	return {
		"candidate_id": candidate_id,
		"id": int(result.get("id", candidate_id)),
		"map_slot": int(result.get("map_slot", candidate_id)),
		"player_id": player_id,
		"targets": result.get("targets", []).duplicate(true),
		"changes": result.get("changes", []).duplicate(true),
		"summary": str(result.get("summary", "命運效果已套用")),
		"outcome": str(result.get("outcome", "applied")),
		"raw_amount": maxi(0, int(result.get("raw_amount", 0))),
		"raw_days": maxi(0, int(result.get("raw_days", 0))),
		"gate_result": clampi(int(result.get("gate_result", 0)), 0, 2),
	}


static func resolve(game: Object, player_id: int, candidate_id: int) -> Dictionary:
	if game == null or not _valid_player(game, player_id) or not is_supported(candidate_id):
		return {"ok": false, "reason": "unsupported"}
	var resolved_id: int = _remap_traffic(game, candidate_id, player_id)
	var map_slot: int = _map_slot(game, candidate_id)
	var result: Dictionary = {"ok": true, "id": resolved_id, "map_slot": map_slot, "targets": [], "changes": [], "summary": "", "outcome": "applied", "raw_amount": 0, "raw_days": 0, "gate_result": 0}
	match candidate_id:
		0:
			return _resolve_built_housing(game, player_id, result)
		1:
			return _resolve_unbuilt_housing(game, player_id, result)
		4:
			return _resolve_deposit_levy(game, player_id, result)
		10, 11:
			return _resolve_vehicle_release(game, player_id, result)
		12, 13:
			result["raw_days"] = 3
			return _resolve_status(game, player_id, result, "hospital", 3)
		14, 15, 16:
			return _resolve_traffic_charge(game, player_id, candidate_id, result)
		17, 18, 19, 23, 24, 26, 30:
			return _resolve_money(game, player_id, candidate_id, result, false)
		20, 21, 22, 25, 27, 28, 29, 31:
			return _resolve_money(game, player_id, candidate_id, result, true)
		33, 34, 35, 36:
			result["raw_days"] = int(MAP_PRISON_DAYS[candidate_id])
			return _resolve_status(game, player_id, result, "prison", int(MAP_PRISON_DAYS[candidate_id]))
	return {"ok": false, "reason": "unsupported"}


static func _resolve_built_housing(game: Object, player_id: int, result: Dictionary) -> Dictionary:
	var targets: Array = _housing_targets(game, player_id, true)
	var target_id: int = _pick_int(game, targets)
	if target_id < 0:
		return {"ok": false, "reason": "no_compatible_target"}
	var tile: Dictionary = game.state.board[target_id]
	var level: int = int(tile.get("building_level", 0))
	var house_price: int = int(tile.get("house_price", tile.get("upgrade_cost", 0)))
	var amount: int = max(0, level * house_price)
	result["raw_amount"] = amount
	# Source ID 0 has no god/defense gate. Its only random operation is the
	# housing target selection above; cash and the level reset are deterministic.
	result["gate_result"] = 0
	var before_rent: int = int(tile.get("rent", 0))
	var before_level: int = level
	var before_chain_store: bool = bool(tile.get("is_chain_store", false))
	tile["building_level"] = 0
	tile["is_chain_store"] = false
	game._update_tile_rent(tile)
	var player: Dictionary = game.state.players[player_id]
	player["cash"] = _bounded_cash(player, amount)
	game._recalculate_property_values()
	result["targets"] = [target_id]
	result["changes"] = [
		{"tile_id": target_id, "field": "building_level", "from": before_level, "to": 0},
		{"tile_id": target_id, "field": "is_chain_store", "from": before_chain_store, "to": false},
		{"tile_id": target_id, "field": "rent", "from": before_rent, "to": int(tile.get("rent", 0))},
		{"player_id": player_id, "field": "cash", "amount": amount},
	]
	result["summary"] = "%s拆除房屋並獲得%d元" % [_player_name(game, player_id), amount]
	return result


static func _resolve_unbuilt_housing(game: Object, player_id: int, result: Dictionary) -> Dictionary:
	var targets: Array = _housing_targets(game, player_id, false)
	var target_id: int = _pick_int(game, targets)
	if target_id < 0:
		return {"ok": false, "reason": "no_compatible_target"}
	var tile: Dictionary = game.state.board[target_id]
	var amount: int = max(0, int(tile.get("land_price", tile.get("cost", 0))))
	result["raw_amount"] = amount
	# Source ID 1 also has no god/defense gate. Keep the source amount intact.
	result["gate_result"] = 0
	var before_owner: int = int(tile.get("owner", -1))
	tile["owner"] = -1
	game._remove_property_reference(player_id, target_id)
	game._update_tile_rent(tile)
	var player: Dictionary = game.state.players[player_id]
	player["cash"] = _bounded_cash(player, amount)
	game._recalculate_property_values()
	result["targets"] = [target_id]
	result["changes"] = [
		{"tile_id": target_id, "field": "owner", "from": before_owner, "to": -1},
		{"player_id": player_id, "field": "cash", "amount": amount},
	]
	result["summary"] = "%s出售土地並獲得%d元" % [_player_name(game, player_id), amount]
	return result


static func _resolve_deposit_levy(game: Object, player_id: int, result: Dictionary) -> Dictionary:
	var recipient: Dictionary = game.state.players[player_id]
	var targets: Array = []
	var changes: Array = []
	var transferred := 0
	for donor_value in _players(game):
		if typeof(donor_value) != TYPE_DICTIONARY:
			continue
		var donor: Dictionary = donor_value
		var donor_id: int = int(donor.get("id", -1))
		if donor_id < 0 or donor_id == player_id or not bool(donor.get("alive", false)):
			continue
		var before: int = max(0, int(donor.get("deposit", 0)))
		var levy: int = before / 10
		if levy <= 0:
			continue
		donor["deposit"] = before - levy
		transferred += levy
		targets.append(donor_id)
		changes.append({"player_id": donor_id, "field": "deposit", "from": before, "to": before - levy, "amount": -levy})
	if transferred > 0:
		var recipient_before: int = int(recipient.get("deposit", 0))
		recipient["deposit"] = recipient_before + transferred
		changes.append({"player_id": player_id, "field": "deposit", "from": recipient_before, "to": recipient_before + transferred, "amount": transferred})
	result["targets"] = targets
	result["changes"] = changes
	result["raw_amount"] = transferred
	result["summary"] = "%s收取其他玩家存款的十分之一，共%d元" % [_player_name(game, player_id), transferred]
	return result


static func _resolve_vehicle_release(game: Object, player_id: int, result: Dictionary) -> Dictionary:
	var player: Dictionary = game.state.players[player_id]
	var vehicle: String = str(player.get("vehicle", "walking"))
	var gate_result: int = _gate(game, player_id, 1, 1)
	result["gate_result"] = gate_result
	if gate_result == 1:
		return _blocked_result(result, player_id, player_id, "交通工具故障被抵銷")
	var tool_id: String = "機車" if vehicle == "motorcycle" else "汽車" if vehicle == "car" else ""
	if tool_id.is_empty():
		return {"ok": false, "reason": "no_compatible_target"}
	var supply: Dictionary = game.state.get("inventory_supply", {}).get("tools", {})
	var before_supply: int = int(supply.get(tool_id, 0))
	supply[tool_id] = before_supply + 1
	var spare: int = int(player.get("tools", {}).get(tool_id, 0))
	var had_vehicle: bool = bool(player.get("vehicles", {}).get(vehicle, false))
	var before_dice: int = int(player.get("dice_count", 1))
	player["vehicle"] = "walking"
	player["dice_count"] = 1
	var vehicles: Dictionary = player.get("vehicles", {}).duplicate(true)
	vehicles["walking"] = true
	vehicles[vehicle] = spare > 0
	player["vehicles"] = vehicles
	result["targets"] = [player_id]
	result["changes"] = [
		{"player_id": player_id, "field": "vehicle", "from": vehicle, "to": "walking"},
		{"player_id": player_id, "field": "dice_count", "from": before_dice, "to": 1},
		{"tool_id": tool_id, "field": "supply", "from": before_supply, "to": before_supply + 1},
		{"player_id": player_id, "field": "vehicle_owned", "from": had_vehicle, "to": spare > 0},
	]
	result["summary"] = "%s的%s故障，恢復步行" % [_player_name(game, player_id), "機車" if vehicle == "motorcycle" else "汽車"]
	return result


static func _resolve_status(game: Object, player_id: int, result: Dictionary, kind: String, days: int) -> Dictionary:
	var gate_result: int = _gate(game, player_id, 1, 1)
	result["gate_result"] = gate_result
	if gate_result == 1:
		return _blocked_result(result, player_id, player_id, "%s處罰被抵銷" % ("住院" if kind == "hospital" else "入獄"))
	var applied_days: int = days * 2 if gate_result == 2 else days
	result["raw_days"] = applied_days
	var target_id: int = player_id
	var target: Dictionary = game.state.players[target_id]
	var redirected := false
	if _has_card(target, "免罪"):
		if _consume_card(game, target_id, "免罪"):
			return _blocked_result(result, player_id, target_id, "免罪卡抵銷%s" % ("住院" if kind == "hospital" else "入獄"))
	if _has_card(target, "嫁禍"):
		var fallback: int = _lowest_alive_other(game, player_id)
		if fallback >= 0 and _consume_card(game, target_id, "嫁禍"):
			target_id = fallback
			redirected = true
			target = game.state.players[target_id]
	if kind == "hospital" and int(result.get("id", -1)) in [12, 13]:
		_return_vehicle_for_status(game, target_id)
	if not _admit_status(game, target_id, kind, applied_days):
		return {"ok": false, "reason": "status_unavailable"}
	# A redirected status admission does not refresh the acting player's action
	# list inside GameState. Refresh it after consuming the defense card so the
	# saved state remains identical after JSON reload.
	if game.has_method("_set_action_options"):
		game._set_action_options(player_id)
	result["targets"] = [target_id]
	result["changes"] = [{"player_id": target_id, "field": "status", "kind": kind, "days": applied_days, "redirected": redirected}]
	result["summary"] = "%s%s%d天" % [_player_name(game, target_id), "住院" if kind == "hospital" else "入獄", applied_days]
	return result


static func _resolve_traffic_charge(game: Object, player_id: int, candidate_id: int, result: Dictionary) -> Dictionary:
	var player: Dictionary = game.state.players[player_id]
	var vehicle: String = str(player.get("vehicle", "walking"))
	if int(result.get("id", -1)) == 15 and vehicle == "walking":
		result["raw_days"] = 3
		return _resolve_status(game, player_id, result, "hospital", 3)
	return _resolve_money(game, player_id, candidate_id, result, false)


static func _resolve_money(game: Object, player_id: int, candidate_id: int, result: Dictionary, income: bool) -> Dictionary:
	var base: int = int(INCOME_AMOUNTS.get(candidate_id, 0) if income else EXPENSE_AMOUNTS.get(candidate_id, 0))
	if base <= 0:
		return {"ok": false, "reason": "unsupported"}
	var price_index: int = int(game.state.get("price_index", 1)) if game.has_method("_facility_price_index") else 1
	price_index = max(1, price_index)
	var amount: int = base * price_index
	var gate_result: int = _gate(game, player_id, 0, 0 if income else 1)
	result["gate_result"] = gate_result
	result["raw_amount"] = amount
	if (income and gate_result == 1) or ((not income) and gate_result == 1):
		return _blocked_result(result, player_id, player_id, "命運金錢效果被抵銷")
	if gate_result == 2:
		amount *= 2
		result["raw_amount"] = amount
	var player: Dictionary = game.state.players[player_id]
	if income:
		var before_cash: int = int(player.get("cash", 0))
		player["cash"] = _bounded_cash(player, amount)
		result["changes"] = [{"player_id": player_id, "field": "cash", "from": before_cash, "to": int(player.get("cash", 0)), "amount": amount}]
		result["summary"] = "%s獲得%d元" % [_player_name(game, player_id), amount]
	else:
		var before_cash: int = int(player.get("cash", 0))
		game._charge_amount(player_id, amount, -1, "fate", false)
		result["changes"] = [{"player_id": player_id, "field": "cash", "from": before_cash, "to": int(player.get("cash", 0)), "amount": -amount}]
		result["summary"] = "%s支付%d元" % [_player_name(game, player_id), amount]
	return result


static func _blocked_result(result: Dictionary, player_id: int, target_id: int, summary: String) -> Dictionary:
	result["outcome"] = "blocked"
	result["targets"] = [target_id]
	result["changes"] = []
	result["summary"] = summary
	return result


static func _admit_status(game: Object, player_id: int, kind: String, days: int) -> bool:
	if game.has_method("_admit_player_status") and bool(game._is_statuses()):
		return bool(game._admit_player_status(player_id, kind, days).get("ok", false))
	var player: Dictionary = game.state.players[player_id]
	var key := "hospital_days" if kind == "hospital" else "prison_days"
	player[key] = (int(player.get(key, 0)) + days) & 127
	var node: int = -1
	if game.has_method("_status_node_index"):
		node = int(game._status_node_index(kind))
	if node >= 0:
		player["position"] = node
		if player.has("previous_position"):
			player["previous_position"] = -1
	return true


static func _return_vehicle_for_status(game: Object, player_id: int) -> void:
	var player: Dictionary = game.state.players[player_id]
	var vehicle := str(player.get("vehicle", "walking"))
	if vehicle not in ["motorcycle", "car"]:
		return
	# Status source handlers return the active finite unit before teleporting.
	var tool_id := "機車" if vehicle == "motorcycle" else "汽車"
	var supply: Dictionary = game.state.get("inventory_supply", {}).get("tools", {})
	supply[tool_id] = int(supply.get(tool_id, 0)) + 1
	var spare := int(player.get("tools", {}).get(tool_id, 0))
	var vehicles: Dictionary = player.get("vehicles", {}).duplicate(true)
	vehicles[vehicle] = spare > 0
	vehicles["walking"] = true
	player["vehicles"] = vehicles
	player["vehicle"] = "walking"
	player["dice_count"] = 1


static func _housing_targets(game: Object, player_id: int, built: bool) -> Array:
	var result: Array = []
	for index in range(game.state.get("board", []).size()):
		var tile: Variant = game.state.board[index]
		if typeof(tile) != TYPE_DICTIONARY or tile.get("kind", "") != "property":
			continue
		if int(tile.get("owner", -1)) != player_id:
			continue
		var level := int(tile.get("building_level", 0))
		if (built and level > 0) or ((not built) and level == 0):
			result.append(index)
	return result


static func _pick_int(game: Object, values: Array) -> int:
	if values.is_empty():
		return -1
	return int(values[game._rng.randi_range(0, values.size() - 1)])


static func _remap_traffic(game: Object, candidate_id: int, player_id: int) -> int:
	var vehicle := str(game.state.players[player_id].get("vehicle", "walking"))
	if candidate_id in [10, 11]:
		return 10 if vehicle == "motorcycle" else 11 if vehicle == "car" else candidate_id
	if candidate_id in [12, 13]:
		return 12 if vehicle == "walking" else 13
	if candidate_id in [14, 15, 16]:
		return 14 if vehicle == "walking" and candidate_id in [14, 16] else 15 if vehicle == "motorcycle" else 16 if vehicle == "car" else 15
	return candidate_id


static func _map_slot(game: Object, candidate_id: int) -> int:
	if candidate_id < COMMON_COUNT:
		return _remap_traffic(game, candidate_id, int(game.state.get("current_player", -1))) if candidate_id in [10, 11, 12, 13, 14, 15, 16] else candidate_id
	var source: Variant = game.state.get("map_source", {})
	var map_number: int = int(source.get("map_number", 1)) if typeof(source) == TYPE_DICTIONARY else 1
	return 33 + (candidate_id - COMMON_COUNT) + clampi(map_number - 1, 0, 99) * 4


static func _map_prison_available(game: Object) -> bool:
	var source: Variant = game.state.get("map_source", {})
	if typeof(source) != TYPE_DICTIONARY or str(source.get("edition", "")) != "Game":
		return false
	if game.state.has("game_stage") and int(game.state.get("game_stage", 0)) != 0:
		return false
	return true


static func _god_gate_value(game: Object, player_id: int, first_arg: int) -> int:
	var god_id: int = int(game.state.players[player_id].get("god_id", 0))
	var f70 := [0, 100, 150, 0, 0, -60, -100, 0, 0, 60, -60, 0, 0, 0, 0, -200, 0, 0]
	var f72 := [0, 0, 0, 100, 150, 0, 0, -60, -100, 60, -60, 0, 0, 0, 0, -200, 0, 0]
	if god_id < 0 or god_id >= f70.size():
		return 0
	return int(f72[god_id] if first_arg != 0 else f70[god_id])


static func _gate(game: Object, player_id: int, first_arg: int, second_arg: int) -> int:
	var value: int = _god_gate_value(game, player_id, first_arg)
	if first_arg == 0 and second_arg == 0:
		if value < 0:
			return 1
		if value > 100:
			return 2
		if value > 50:
			return 2 if (int(game._rng.randi()) & 1) != 0 else 0
		return 0
	if value < 0:
		return 2
	if value > 100:
		return 1
	if value > 50:
		return 1 if (int(game._rng.randi()) & 1) != 0 else 0
	return 0


static func _has_card(player: Dictionary, card_id: String) -> bool:
	var cards: Variant = player.get("cards", [])
	return typeof(cards) == TYPE_ARRAY and cards.has(card_id)


static func _consume_card(game: Object, player_id: int, card_id: String) -> bool:
	var player: Dictionary = game.state.players[player_id]
	if not _has_card(player, card_id):
		return false
	if game.has_method("_is_inventory") and bool(game._is_inventory()):
		return _consume_inventory_card(game, player, card_id)
	var index: int = player.cards.find(card_id)
	if index < 0:
		return false
	player.cards.remove_at(index)
	return true


static func _consume_inventory_card(game: Object, player: Dictionary, card_id: String) -> bool:
	# Keep the inventory module private to GameState; this branch is replaced by
	# the public card-consume helper when present, preserving finite supply.
	if game.has_method("_trap_consume_card"):
		return bool(game._trap_consume_card(int(player.get("id", -1)), card_id))
	var index: int = player.cards.find(card_id)
	if index < 0:
		return false
	player.cards.remove_at(index)
	return true


static func _lowest_alive_other(game: Object, player_id: int) -> int:
	for index in range(game.state.get("players", []).size()):
		if index == player_id:
			continue
		var player: Variant = game.state.players[index]
		if typeof(player) == TYPE_DICTIONARY and bool(player.get("alive", false)):
			return index
	return -1


static func _players(game: Object) -> Array:
	return game.state.get("players", [])


static func _valid_player(game: Object, player_id: int) -> bool:
	return player_id >= 0 and player_id < game.state.get("players", []).size() and typeof(game.state.players[player_id]) == TYPE_DICTIONARY and bool(game.state.players[player_id].get("alive", false))


static func _player_name(game: Object, player_id: int) -> String:
	return str(game.state.players[player_id].get("name", "玩家 %d" % (player_id + 1)))


static func _bounded_cash(player: Dictionary, amount: int) -> int:
	return min(1000000000000, int(player.get("cash", 0)) + max(0, amount))


static func _valid_int(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	if typeof(value) == TYPE_FLOAT:
		var real: float = float(value)
		return is_finite(real) and floor(real) == real and real >= float(minimum) and real <= float(maximum)
	return false
