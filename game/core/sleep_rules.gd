class_name RichmanSleepRules
extends RefCounted

## Rules and forced-turn driver for the original 冬眠／夢遊 card lifecycle.
##
## GameState supplies the existing inventory, movement and event primitives.
## Sleep metadata and its restricted orchestration stay together here.

const OriginalInventory = preload("res://game/core/inventory_rules.gd")
const EngineeringVehicle = preload("res://game/core/engineering_vehicle.gd")

const WINTER_CARD := "冬眠"
const DREAM_CARD := "夢遊"
const MAX_DAYS: int = 128
const WINTER_DAYS: int = 5
const DREAM_SELF_DAYS: int = 4
const DREAM_OTHER_DAYS: int = 5
const BACKUP_KEYS := ["previous_vehicle", "previous_dice_count"]
const ENGINEERING_KEYS := ["remaining_admissions", "previous_vehicle", "previous_dice_count"]
const ORDINARY_VEHICLES := ["walking", "motorcycle", "car"]


static func is_sleep_card(card_id: String) -> bool:
	return card_id == WINTER_CARD or card_id == DREAM_CARD


static func is_counter(value: Variant) -> bool:
	return _valid_integer(value, 0, MAX_DAYS)


static func is_active(value: Variant) -> bool:
	return is_counter(value) and int(value) > 0


static func next_counter(value: Variant) -> int:
	if not is_counter(value):
		return -1
	var current: int = int(value)
	if current == 128:
		return 0
	if current == 0:
		return 0
	if current == 1:
		return 128
	return current - 1


static func valid_backup(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "error": "dream vehicle backup must be an object"}
	var backup: Dictionary = value
	if backup.size() < BACKUP_KEYS.size() or backup.size() > BACKUP_KEYS.size() + 1:
		return {"ok": false, "error": "dream vehicle backup keys are not canonical"}
	for key in BACKUP_KEYS:
		if not backup.has(key):
			return {"ok": false, "error": "dream vehicle backup missing %s" % key}
	var previous_vehicle: Variant = backup.get("previous_vehicle", null)
	if typeof(previous_vehicle) != TYPE_STRING or (not ORDINARY_VEHICLES.has(str(previous_vehicle)) and str(previous_vehicle) != "engineering"):
		return {"ok": false, "error": "dream previous vehicle invalid"}
	var previous_dice: Variant = backup.get("previous_dice_count", null)
	var maximum: int = 1 if str(previous_vehicle) in ["walking", "engineering"] else 2 if str(previous_vehicle) == "motorcycle" else 3
	if not _valid_integer(previous_dice, 1, maximum):
		return {"ok": false, "error": "dream previous dice invalid"}
	if str(previous_vehicle) == "engineering":
		if backup.size() != BACKUP_KEYS.size() + 1 or typeof(backup.get("engineering_vehicle", null)) != TYPE_DICTIONARY:
			return {"ok": false, "error": "engineering dream backup requires metadata"}
		var checked: Dictionary = EngineeringVehicle.validate_metadata(backup["engineering_vehicle"])
		if not bool(checked.get("ok", false)):
			return checked
	elif backup.size() != BACKUP_KEYS.size():
		return {"ok": false, "error": "ordinary dream backup has unexpected metadata"}
	return {"ok": true, "error": ""}


static func validate_player(player: Dictionary) -> Dictionary:
	var winter_value: Variant = player.get("winter_sleep_days", 0)
	var dream_value: Variant = player.get("dream_days", 0)
	if not is_counter(winter_value) or not is_counter(dream_value):
		return {"ok": false, "error": "sleep counter invalid"}
	if int(winter_value) > 0 and int(dream_value) > 0:
		return {"ok": false, "error": "winter and dream counters are mutually exclusive"}
	var has_backup: bool = player.has("dream_vehicle_backup")
	if int(dream_value) > 0:
		if not has_backup:
			return {"ok": false, "error": "active dream requires vehicle backup"}
		var backup_result: Dictionary = valid_backup(player.get("dream_vehicle_backup", null))
		if not bool(backup_result.get("ok", false)):
			return backup_result
		if str(player.get("vehicle", "")) != "walking" or not _valid_integer(player.get("dice_count", null), 1, 1):
			return {"ok": false, "error": "active dream requires walking"}
	else:
		if has_backup:
			return {"ok": false, "error": "inactive dream cannot keep vehicle backup"}
	if player.has("engineering_vehicle") and int(dream_value) > 0:
		return {"ok": false, "error": "active dream cannot keep top-level engineering metadata"}
	return {"ok": true, "error": ""}


static func _valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	if typeof(value) == TYPE_FLOAT:
		var real: float = float(value)
		return is_finite(real) and floor(real) == real and real >= float(minimum) and real <= float(maximum)
	return false


static func dream_target_players(game: Object, caster_id: int) -> Array:
	# Dream keeps the source target picker broad enough to include the caster,
	# while detained players remain ineligible for a new sleep admission.
	var targets: Array = []
	if not game._is_inventory() or not game._is_statuses() or not game._valid_player(caster_id, true):
		return targets
	for player in game._players():
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var target_id_value: Variant = player.get("id", null)
		if typeof(target_id_value) != TYPE_INT:
			continue
		if not bool(player.get("alive", false)) or game._status_active(player):
			continue
		targets.append(int(target_id_value))
	targets.sort()
	return targets


static func _sleep_clear_dream(game: Object, player: Dictionary) -> void:
	player["dream_days"] = 0
	player.erase("dream_vehicle_backup")


static func _sleep_capture_vehicle(game: Object, player: Dictionary) -> Dictionary:
	var vehicle: String = str(player.get("vehicle", "walking"))
	var dice_value: Variant = player.get("dice_count", null)
	if vehicle == EngineeringVehicle.VEHICLE_ID:
		var metadata: Variant = player.get("engineering_vehicle", null)
		var metadata_validation: Dictionary = EngineeringVehicle.validate_metadata(metadata)
		if not bool(metadata_validation.get("ok", false)):
			return game._error("工程車狀態無效")
		var engineering_backup: Dictionary = {
			"previous_vehicle": vehicle,
			"previous_dice_count": 1,
			"engineering_vehicle": metadata.duplicate(true),
		}
		return {"ok": true, "backup": engineering_backup}
	if not ORDINARY_VEHICLES.has(vehicle):
		return game._error("目前交通工具無效")
	var maximum: int = int(game.VEHICLE_DICE.get(vehicle, 1))
	if not game._valid_int(dice_value, 1, maximum):
		return game._error("目前骰子數量無效")
	var backup: Dictionary = {"previous_vehicle": vehicle, "previous_dice_count": int(dice_value)}
	if game._is_inventory() and vehicle in ["motorcycle", "car"]:
		var tools_value: Variant = player.get("tools", null)
		if typeof(tools_value) != TYPE_DICTIONARY:
			return game._error("玩家道具資料無效")
		var tool_id: String = game._inventory_vehicle_tool_id(vehicle)
		var stored: int = int(tools_value.get(tool_id, 0))
		if stored < 0 or stored >= OriginalInventory.VEHICLE_STORAGE_CAPACITY:
			return game._error("道具數量超出上限")
		var staged_tools: Dictionary = tools_value.duplicate(true)
		staged_tools[tool_id] = stored + 1
		player["tools"] = staged_tools
	return {"ok": true, "backup": backup}


static func _sleep_admit(game: Object, player_id: int, kind: String, days: int) -> Dictionary:
	if not game._is_inventory() or not game._is_statuses() or not ["winter", "dream"].has(kind):
		return game._error("目前地圖不支援此睡眠狀態")
	if not game._valid_int(days, 1, MAX_DAYS):
		return game._error("睡眠天數無效")
	var player: Dictionary = game._player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return game._error("睡眠目標無效")
	# Detention has priority over either sleep card. The card is still consumed by
	# the caller, but the detained target keeps its existing status untouched.
	if game._status_active(player):
		return game._result(true, "拘留中的玩家不受睡眠卡影響", {"applied": false, "sleep_kind": kind, "player_id": player_id})
	if kind == "winter":
		_sleep_clear_dream(game, player)
		player["winter_sleep_days"] = days
	else:
		var captured: Dictionary = _sleep_capture_vehicle(game, player)
		if not bool(captured.get("ok", false)):
			return captured
		var backup_value: Variant = captured.get("backup", null)
		var backup_validation: Dictionary = valid_backup(backup_value)
		if not bool(backup_validation.get("ok", false)):
			return game._error("夢遊交通工具備份無效")
		player["winter_sleep_days"] = 0
		player["dream_days"] = days
		player["vehicle"] = "walking"
		player["dice_count"] = 1
		player.erase("engineering_vehicle")
		player["dream_vehicle_backup"] = backup_value.duplicate(true)
	game._record_event("sleep_admitted", {"player_id": player_id, "sleep_kind": kind, "remaining": days})
	return game._result(true, "已進入%s狀態" % ("冬眠" if kind == "winter" else "夢遊"), {"applied": true, "sleep_kind": kind, "player_id": player_id, "remaining": days})


static func _resolve_sleep_direct(game: Object, target_id: int, days: int, trigger_revenge: bool = false, caster_id: int = -1) -> Dictionary:
	var target: Dictionary = game._player(target_id)
	if target.is_empty() or not bool(target.get("alive", false)):
		return game._error("睡眠卡目標無效")
	if game._sleep_winter_active(target):
		return game._result(true, "冬眠中的玩家不受夢遊影響", {"applied": false, "sleep_kind": "dream", "player_id": target_id})
	var admission: Dictionary = _sleep_admit(game, target_id, "dream", days)
	if not bool(admission.get("ok", false)) or not bool(admission.get("applied", false)):
		return admission
	if trigger_revenge and caster_id >= 0 and game._trap_has_card(target, "復仇"):
		if not game._trap_consume_card(target_id, "復仇"):
			return game._error("復仇卡無法使用")
		game._record_event("trap_revenge", {"caster_id": caster_id, "target_id": target_id, "card_id": "夢遊"})
		var revenge_admission: Dictionary = _sleep_admit(game, caster_id, "dream", DREAM_OTHER_DAYS)
		if not bool(revenge_admission.get("ok", false)):
			return revenge_admission
	return admission


static func _sleep_tick(game: Object, player_id: int) -> Dictionary:
	var player: Dictionary = game._player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return game._error("目前玩家無法推進睡眠回合")
	if game._status_active(player):
		return game._result(true, "拘留期間暫停睡眠倒數", {"paused": true, "player_id": player_id})
	var kind: String = game._sleep_kind(player)
	if kind.is_empty():
		return game._error("目前玩家不在睡眠狀態")
	var key: String = "winter_sleep_days" if kind == "winter" else "dream_days"
	var next: int = next_counter(player.get(key, 0))
	if next < 0:
		return game._error("睡眠倒數資料無效")
	player[key] = next
	game._record_event("sleep_ticked", {"player_id": player_id, "sleep_kind": kind, "remaining": next})
	return game._result(true, "睡眠倒數推進", {"player_id": player_id, "sleep_kind": kind, "remaining": next})


static func _sleep_restore_vehicle(game: Object, player_id: int) -> Dictionary:
	var player: Dictionary = game._player(player_id)
	if player.is_empty():
		return game._error("夢遊玩家無效")
	var backup_value: Variant = player.get("dream_vehicle_backup", null)
	var validation: Dictionary = valid_backup(backup_value)
	if not bool(validation.get("ok", false)):
		return game._error("夢遊交通工具備份無效")
	var backup: Dictionary = backup_value
	var previous_vehicle: String = str(backup.get("previous_vehicle", "walking"))
	var restored_vehicle: String = "walking"
	var restored_dice: int = 1
	if previous_vehicle == EngineeringVehicle.VEHICLE_ID:
		restored_vehicle = previous_vehicle
		restored_dice = 1
		player["engineering_vehicle"] = backup.get("engineering_vehicle", {}).duplicate(true)
	else:
		var tool_id: String = game._inventory_vehicle_tool_id(previous_vehicle)
		var tools: Dictionary = player.get("tools", {}).duplicate(true)
		var available: bool = previous_vehicle == "walking" or int(tools.get(tool_id, 0)) > 0
		if available:
			restored_vehicle = previous_vehicle
			restored_dice = int(backup.get("previous_dice_count", 1))
			if not tool_id.is_empty():
				var consumed: int = int(tools.get(tool_id, 0)) - 1
				if consumed <= 0:
					tools.erase(tool_id)
				else:
					tools[tool_id] = consumed
				player["tools"] = tools
				var vehicles: Dictionary = player.get("vehicles", {}).duplicate(true)
				vehicles[previous_vehicle] = true
				player["vehicles"] = vehicles
			else:
				player["tools"] = tools
		player.erase("engineering_vehicle")
	player["vehicle"] = restored_vehicle
	player["dice_count"] = restored_dice
	player["dream_days"] = 0
	player.erase("dream_vehicle_backup")
	game._record_event("sleep_released", {"player_id": player_id, "sleep_kind": "dream", "previous_vehicle": previous_vehicle, "restored_vehicle": restored_vehicle, "restored_dice_count": restored_dice})
	return game._result(true, "夢遊已醒來", {"player_id": player_id, "restored_vehicle": restored_vehicle, "restored_dice_count": restored_dice})


static func use_card(game: Object, player_id: int, card_id: String, target_id: Variant, cancel: Variant) -> Dictionary:
	if not game._is_statuses() or not game._is_inventory():
		return game._error("目前地圖不支援睡眠卡")
	if typeof(cancel) != TYPE_BOOL:
		return game._error("睡眠卡取消參數無效")
	if not game._trap_has_card(game._player(player_id), card_id):
		return game._error("沒有這張卡片")
	if cancel:
		return game._result(true, "已取消睡眠卡")
	if card_id == DREAM_CARD and (typeof(target_id) != TYPE_INT or not dream_target_players(game, player_id).has(target_id)):
		return game._error("夢遊卡目標無效")
	if not game._trap_consume_card(player_id, card_id):
		return game._error("睡眠卡無法使用")
	game._record_event("card_used", {"player_id": player_id, "card_id": card_id, "effect": "winter" if card_id == WINTER_CARD else "dream"})
	if card_id == WINTER_CARD:
		for player in game._players():
			var id: int = int(player.get("id", -1))
			if id != player_id and bool(player.get("alive", false)) and not game._status_active(player):
				_sleep_admit(game, id, "winter", WINTER_DAYS)
		game._set_action_options(player_id)
		return game._result(true, "其他未拘留玩家冬眠五回合")
	var target: Dictionary = game._player(int(target_id))
	if game._sleep_winter_active(target):
		game._set_action_options(player_id)
		return game._result(true, "目標冬眠中，夢遊卡未生效", {"applied": false})
	if game._trap_has_card(target, "免罪"):
		game._trap_consume_card(int(target_id), "免罪")
		game._record_event("trap_blocked", {"caster_id": player_id, "target_id": int(target_id), "card_id": DREAM_CARD})
		game._set_action_options(player_id)
		return game._result(true, "免罪卡抵銷夢遊", {"blocked": true})
	if game._trap_has_card(target, "嫁禍"):
		if bool(target.get("is_human", false)) and not bool(target.get("is_ai", false)):
			game.state["pending_trap"] = {"caster_id": player_id, "target_id": int(target_id)}
			game.state["pending_trap_card"] = DREAM_CARD
			game.state["action_options"] = ["respond_trap"]
			game._record_event("trap_response_requested", {"caster_id": player_id, "target_id": int(target_id), "card_id": DREAM_CARD})
			return game._result(true, "等待嫁禍卡回應夢遊", {"awaiting_response": true})
		for candidate in game._players():
			var redirect: int = int(candidate.get("id", -1))
			if redirect == int(target_id) or not bool(candidate.get("alive", false)):
				continue
			game._trap_consume_card(int(target_id), "嫁禍")
			var response: Dictionary = _resolve_sleep_direct(game, redirect, DREAM_SELF_DAYS if redirect == player_id else DREAM_OTHER_DAYS)
			game._record_event("trap_redirected", {"caster_id": player_id, "from_target_id": int(target_id), "target_id": redirect, "card_id": DREAM_CARD, "ai": true})
			game._set_action_options(player_id)
			response.merge(game._result(bool(response.get("ok", false)), str(response.get("message", "")), {"redirected": true, "target_id": redirect}), true)
			return response
	var result: Dictionary = _resolve_sleep_direct(game, int(target_id), DREAM_SELF_DAYS if int(target_id) == player_id else DREAM_OTHER_DAYS, true, player_id)
	game._set_action_options(player_id)
	result.merge(game._result(bool(result.get("ok", false)), str(result.get("message", ""))), true)
	return result


static func run_turn(game: Object) -> Dictionary:
	var player_id: int = int(game.state.get("current_player", -1))
	var player: Dictionary = game._player(player_id)
	if game.state.get("phase", "") == "game_over" or not bool(player.get("alive", false)) or not game._sleep_active(player):
		return game._error("目前玩家沒有睡眠回合")
	if game._trap_pending():
		return game._error("請先回應卡片")
	if game.state.get("phase", "") == "await_roll":
		# Source admission releases detention before testing either sleep counter.
		for kind in ["hospital", "prison"]:
			if int(player.get(kind + "_days", 0)) == 128:
				game._release_status_marker(player_id, kind)
	if not game._status_active(player):
		var kind: String = game._sleep_kind(player)
		var key: String = "winter_sleep_days" if kind == "winter" else "dream_days"
		if int(player.get(key, 0)) == 128:
			if kind == "dream":
				var restored: Dictionary = _sleep_restore_vehicle(game, player_id)
				if not bool(restored.get("ok", false)): return restored
			else:
				player[key] = 0
				game._record_event("sleep_released", {"player_id": player_id, "sleep_kind": kind})
			game.state["phase"] = "await_roll"
			game.state["last_roll"] = []
			game.state["last_total"] = 0
			game.state["last_roll_total"] = 0
			game.state["extra_roll"] = false
			game.state["doubles_count"] = 0
			game.state["property_action_used"] = false
			game.state["bank_access"] = false
			game.state["bank_landing"] = false
			game.state["route_options"] = []
			game.state["pending_movement"] = {}
			game.state["remaining_steps"] = 0
			game._set_action_options(player_id)
			return game._result(true, "已醒來，請擲骰", {"released": true, "completed": false})
		if kind == "winter" and game.state.get("phase", "") == "await_roll":
			game.state["phase"] = "await_action"
			game.state["last_roll"] = []
			game.state["last_total"] = 0
			game.state["last_roll_total"] = 0
			game.state["property_action_used"] = true
			game._set_action_options(player_id)
	var iterations := 0
	while int(game.state.get("current_player", -1)) == player_id and game.state.get("phase", "") != "game_over":
		iterations += 1
		if iterations > game.MAX_GRAPH_STEPS + 4:
			return game._error("睡眠回合未能完成")
		var result: Dictionary
		match str(game.state.get("phase", "")):
			"await_roll":
				result = game.roll()
			"await_route":
				var options: Array = game.state.get("route_options", [])
				if options.is_empty(): return game._error("夢遊沒有可用路線")
				result = game.choose_route(int(options[0]))
			"await_action":
				if int(game.state.get("company_service_pending", 0)) > 0:
					# A landed construction-company service must finish without a
					# manual prompt; it is not the player's buy/build action.
					var company: Dictionary = game.get_company_at(int(player.get("position", -1)))
					var targets: Array = game._company_payable_upgrade_targets(player_id, company)
					if targets.is_empty(): return game._error("企業服務沒有合法目標")
					result = game._company_upgrade(player_id, {"tile_id": int(targets[0]), "facility_type": 1})
				else:
					result = game.end_turn()
			_:
				return game._error("睡眠回合階段無效")
		if not bool(result.get("ok", false)): return result
	return game._result(true, "睡眠回合完成", {"completed": true})
