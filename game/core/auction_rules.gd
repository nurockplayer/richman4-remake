class_name RichmanAuctionRules
extends RefCounted

## Deterministic rules for the original ID8 拍賣 card.
##
## The game state owns the board, player and inventory containers.  This module
## owns the pending-record contract and the bid/settlement transitions so the
## public action, AI loop and save validator share one implementation.

const CARD_ID := "拍賣"
const PENDING_KEYS := ["caster_id", "node_id", "opening_bid", "current_bid", "highest_bidder_id", "bidder_id", "participants", "withdrawn"]
const INCREMENTS := [100, 500, 1000, 5000, 10000]
const MAX_CASH: int = 1000000000000


static func is_auction_card(card_id: String) -> bool:
	return card_id == CARD_ID


static func response(game: Object) -> Dictionary:
	var value: Variant = game.state.get("pending_auction", {})
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


static func use_card(game: Object, player_id: int, cancel: Variant, params: Dictionary = {}) -> Dictionary:
	if not params.is_empty():
		for key in params.keys():
			if typeof(key) != TYPE_STRING or not ["card_id", "cancel"].has(str(key)):
				return game._error("拍賣卡參數無效")
		if params.has("card_id") and params.get("card_id") != CARD_ID:
			return game._error("拍賣卡代號無效")
	if typeof(cancel) != TYPE_BOOL:
		return game._error("拍賣卡取消參數無效")
	var player: Dictionary = game._player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return game._error("目前玩家無法使用拍賣卡")
	if not _has_card(player, CARD_ID):
		return game._error("沒有這張卡片")
	if not game._is_inventory() or not game._is_graph() or not game._is_gods():
		return game._error("拍賣卡只適用於原版神明圖形背包地圖")
	if bool(cancel):
		return game._result(true, "已取消拍賣卡", {"cancelled": true, "card_id": CARD_ID})
	var phase: String = str(game.state.get("phase", ""))
	if phase != "await_action":
		return game._error("拍賣卡只能在行動階段使用")
	if not response(game).is_empty():
		return game._error("目前已有待回應的拍賣")
	if not game._pending_finance().is_empty() or not game._pending_trap().is_empty():
		return game._error("目前有其他待回應事項")
	var pending_remote: Variant = game.state.get("pending_remote_dice", {})
	if typeof(pending_remote) != TYPE_DICTIONARY or not pending_remote.is_empty():
		return game._error("遙控骰子已經排程")
	if int(game.state.get("company_service_pending", 0)) > 0:
		return game._error("請先完成企業建設服務")
	var board: Variant = game.state.get("board", null)
	var position: Variant = player.get("position", null)
	if typeof(board) != TYPE_ARRAY or not game._valid_int(position, 0, board.size() - 1):
		return game._error("目前位置無效")
	var node_id: int = int(position)
	var target: Dictionary = game._tile_at(node_id)
	var target_error: String = _target_error(game, node_id, target)
	if not target_error.is_empty():
		return game._error(target_error)
	var opening_bid: int = _opening_bid(game, target)
	if opening_bid < 0 or opening_bid > MAX_CASH:
		return game._error("拍賣底價無效")
	var participants: Array = _participants(game, player_id, target, opening_bid)
	if participants.is_empty() or not participants.has(player_id):
		return game._error("沒有可參與拍賣的玩家")
	var pending: Dictionary = {
		"caster_id": player_id,
		"node_id": node_id,
		"opening_bid": opening_bid,
		"current_bid": opening_bid,
		"highest_bidder_id": -1,
		"bidder_id": int(participants[0]),
		"participants": participants,
		"withdrawn": [],
	}
	game.state["pending_auction"] = pending
	game._record_event("auction_started", {"caster_id": player_id, "node_id": node_id, "opening_bid": opening_bid, "participants": participants.duplicate(true)})
	game._set_action_options(player_id)
	return game._result(true, "拍賣開始", {"pending": pending.duplicate(true), "awaiting_response": true})


static func respond(game: Object, params: Dictionary, allow_ai: bool = false) -> Dictionary:
	var pending: Dictionary = response(game)
	if pending.is_empty():
		return game._error("目前沒有待回應的拍賣")
	var runtime_errors: Array = _validate_runtime(game, pending)
	if not runtime_errors.is_empty():
		return game._error("拍賣狀態無效")
	if typeof(params) != TYPE_DICTIONARY:
		return game._error("拍賣回應格式無效")
	if params.size() != 2 or not params.has("increment") or not params.has("cancel"):
		return game._error("拍賣回應格式無效")
	var increment_value: Variant = params.get("increment", null)
	var cancel_value: Variant = params.get("cancel", null)
	if typeof(increment_value) != TYPE_INT or typeof(cancel_value) != TYPE_BOOL:
		return game._error("拍賣回應格式無效")
	var increment: int = int(increment_value)
	var cancel: bool = bool(cancel_value)
	if increment < 0 or (increment > 0 and not INCREMENTS.has(increment)) or (cancel and increment != 0) or (not cancel and increment == 0):
		return game._error("拍賣加價幅度無效")
	var bidder_id: int = int(pending.get("bidder_id", -1))
	var bidder: Dictionary = game._player(bidder_id)
	if bidder.is_empty() or not bool(bidder.get("alive", false)):
		return game._error("目前拍賣玩家無法行動")
	if not allow_ai and (not bool(bidder.get("is_human", false)) or bool(bidder.get("is_ai", false))):
		return game._error("目前拍賣玩家不是人類玩家")
	if allow_ai and not bool(bidder.get("is_ai", false)):
		return game._error("目前拍賣玩家不是 AI")
	if cancel:
		var withdrawn: Array = pending.get("withdrawn", []).duplicate(true)
		if withdrawn.has(bidder_id):
			return game._error("玩家已退出拍賣")
		withdrawn.append(bidder_id)
		withdrawn.sort()
		pending["withdrawn"] = withdrawn
		var next_state: Dictionary = _advance_or_settle(game, pending, "withdraw")
		return next_state
	var prospective: int = int(pending.get("current_bid", 0)) + increment
	if prospective <= int(pending.get("current_bid", 0)) or prospective > MAX_CASH:
		return game._error("拍賣報價無效")
	var capacity_errors: Array = _capacity_errors(game, pending, prospective, bidder_id)
	if not capacity_errors.is_empty():
		return game._error(str(capacity_errors[0]))
	pending["current_bid"] = prospective
	pending["highest_bidder_id"] = bidder_id
	game.state["pending_auction"] = pending
	game._record_event("auction_bid", {"caster_id": int(pending["caster_id"]), "node_id": int(pending["node_id"]), "bidder_id": bidder_id, "increment": increment, "current_bid": prospective})
	return _advance_or_settle(game, pending, "bid")


static func ai_turn(game: Object, max_steps: int = 64) -> Dictionary:
	var steps := 0
	while steps < max_steps:
		var pending: Dictionary = response(game)
		if pending.is_empty():
			return game._result(true, "拍賣回合完成", {"completed": true, "auction": false})
		var bidder_id := int(pending.get("bidder_id", -1))
		var bidder: Dictionary = game._player(bidder_id)
		if bidder.is_empty() or not bool(bidder.get("is_ai", false)):
			return game._result(true, "等待人類玩家回應拍賣", {"player_id": bidder_id, "awaiting_response": true, "completed": false, "auction": true})
		var current_bid := int(pending.get("current_bid", 0))
		var opening := int(pending.get("opening_bid", 0))
		var max_bid := mini(int(bidder.get("cash", 0)), opening * 2)
		max_bid = mini(max_bid, _headroom(game, int(pending.get("caster_id", -1)), "deposit"))
		max_bid = mini(max_bid, _headroom(game, -1, "bank_deposits"))
		max_bid = mini(max_bid, _headroom(game, -1, "bank_cash"))
		var increment := 100 if current_bid + 100 <= max_bid else 0
		var result: Dictionary = respond(game, {"increment": increment, "cancel": increment == 0}, true)
		steps += 1
		if not bool(result.get("ok", false)):
			return game._result(false, str(result.get("message", "AI 拍賣回應失敗")), {"player_id": bidder_id, "iterations": steps, "completed": false, "auction": true})
		if not response(game).is_empty() and not bool(game._player(int(response(game).get("bidder_id", -1))).get("is_ai", false)):
			return game._result(true, "等待人類玩家回應拍賣", {"player_id": int(response(game).get("bidder_id", -1)), "awaiting_response": true, "iterations": steps, "completed": false, "auction": true})
	# A long but valid all-AI auction may need several bounded calls.  Yield to
	# the public turn loop as successful ongoing work so the caller can resume
	# from the still-pending record without treating the safety budget as a
	# gameplay failure.
	return game._result(true, "AI 拍賣仍在進行", {"iterations": steps, "completed": false, "auction": true, "awaiting_response": false})


static func validate_save(data: Dictionary, player_count: int, board: Variant, phase: String, action_options: Variant, inventory_save: bool) -> Array:
	var errors: Array = []
	if not data.has("pending_auction"):
		return errors
	var pending_value: Variant = data.get("pending_auction", null)
	if not inventory_save:
		errors.append("pending auction requires inventory save")
	if typeof(pending_value) != TYPE_DICTIONARY:
		errors.append("invalid pending auction")
		return errors
	var pending: Dictionary = pending_value
	if pending.size() != PENDING_KEYS.size():
		errors.append("pending auction keys are not canonical")
	for key in pending.keys():
		if typeof(key) != TYPE_STRING or not PENDING_KEYS.has(str(key)):
			errors.append("pending auction has unexpected field")
	for key in PENDING_KEYS:
		if not pending.has(key):
			errors.append("pending auction missing %s" % key)
	if typeof(board) != TYPE_ARRAY or typeof(data.get("players", null)) != TYPE_ARRAY:
		return errors
	var players: Array = data.get("players", [])
	var game := data_validator(data)
	if game == null or not game._is_inventory() or not game._is_graph() or not game._is_gods():
		errors.append("pending auction requires original gods graph inventory capability")
	errors.append_array(_validate_static_shape(game, data, pending, player_count, players, board, phase, action_options))
	return errors


static func data_validator(data: Dictionary) -> Object:
	# The static save path supplies a fully populated state object so target and
	# facility helpers use the same canonical board logic as runtime actions.
	var state_script: Variant = load("res://game/core/game_state.gd")
	if state_script == null:
		return null
	var game: Object = state_script.new()
	game.state = data
	return game


static func _validate_static_shape(game: Object, data: Dictionary, pending: Dictionary, player_count: int, players: Array, board: Array, phase: String, action_options: Variant) -> Array:
	var errors: Array = []
	if game == null:
		return ["auction validator unavailable"]
	if phase != "await_action":
		errors.append("pending auction outside action phase")
	if typeof(action_options) != TYPE_ARRAY or action_options != ["respond_auction"]:
		errors.append("pending auction action options mismatch")
	var caster_id := _int_field(pending, "caster_id", 0, player_count - 1, errors)
	var node_id := _int_field(pending, "node_id", 0, board.size() - 1, errors)
	var opening := _int_field(pending, "opening_bid", 0, MAX_CASH, errors)
	var current_bid := _int_field(pending, "current_bid", 0, MAX_CASH, errors)
	var highest_id := _int_field(pending, "highest_bidder_id", -1, player_count - 1, errors)
	var bidder_id := _int_field(pending, "bidder_id", 0, player_count - 1, errors)
	var participants := _int_array_field(pending.get("participants", null), player_count, "participants", errors)
	var withdrawn := _int_array_field(pending.get("withdrawn", null), player_count, "withdrawn", errors)
	if not _strict_sorted_unique(participants):
		errors.append("pending auction participants are not sorted unique")
	if not _strict_sorted_unique(withdrawn):
		errors.append("pending auction withdrawn is not sorted unique")
	for id in withdrawn:
		if not participants.has(id):
			errors.append("pending auction withdrawn is not a participant")
	if highest_id >= 0 and (not participants.has(highest_id) or withdrawn.has(highest_id)):
		errors.append("pending auction highest bidder is invalid")
	if not participants.has(bidder_id) or withdrawn.has(bidder_id) or bidder_id == highest_id:
		errors.append("pending auction bidder is invalid")
	if participants.is_empty():
		errors.append("pending auction has no participants")
	if not _valid_json_int(data.get("current_player", null), caster_id, caster_id):
		errors.append("pending auction caster mismatch")
	var caster: Dictionary = players[caster_id] if caster_id >= 0 and caster_id < players.size() and typeof(players[caster_id]) == TYPE_DICTIONARY else {}
	if caster.is_empty() or not bool(caster.get("alive", false)) or bool(caster.get("bankrupt", false)):
		errors.append("pending auction caster unavailable")
	var caster_position: Variant = caster.get("position", null)
	if not _valid_json_int(caster_position, 0, board.size() - 1) or int(caster_position) != node_id:
		errors.append("pending auction caster position mismatch")
	if typeof(caster.get("cards", null)) != TYPE_ARRAY or not caster.get("cards", []).has(CARD_ID):
		errors.append("pending auction missing reserved card")
	var target: Dictionary = game._tile_at(node_id)
	var target_error := _target_error(game, node_id, target)
	if not target_error.is_empty():
		errors.append("pending auction target invalid")
	else:
		var expected_opening := _opening_bid(game, target)
		if opening != expected_opening:
			errors.append("pending auction opening bid mismatch")
		var expected_participants := _participants(game, caster_id, target, opening)
		if participants != expected_participants:
			errors.append("pending auction participants mismatch")
	if current_bid < opening:
		errors.append("pending auction current bid below opening")
	if current_bid > opening and (current_bid - opening) % 100 != 0:
		errors.append("pending auction bid increment sequence invalid")
	if (current_bid == opening and highest_id != -1) or (current_bid > opening and highest_id < 0):
		errors.append("pending auction bid and highest bidder mismatch")
	var expected_bidder: int = _first_active_participant(participants, withdrawn) if highest_id < 0 else _next_active_participant(participants, highest_id, withdrawn)
	if bidder_id != expected_bidder:
		errors.append("pending auction bidder order mismatch")
	var active_count := 0
	for id in participants:
		if not withdrawn.has(id) and id != highest_id:
			active_count += 1
	if active_count <= 0:
		errors.append("pending auction has no response bidder")
	if typeof(data.get("pending_finance", {})) == TYPE_DICTIONARY and not data.get("pending_finance", {}).is_empty():
		errors.append("pending auction conflicts with pending finance")
	if typeof(data.get("pending_trap", {})) == TYPE_DICTIONARY and not data.get("pending_trap", {}).is_empty():
		errors.append("pending auction conflicts with pending trap")
	if typeof(data.get("pending_remote_dice", {})) != TYPE_DICTIONARY or not data.get("pending_remote_dice", {}).is_empty():
		errors.append("pending auction conflicts with remote dice")
	if int(data.get("company_service_pending", 0)) > 0:
		errors.append("pending auction conflicts with company service")
	if highest_id >= 0:
		var capacity_errors := _capacity_errors(game, pending, current_bid, highest_id)
		errors.append_array(capacity_errors)
	return errors


static func _int_field(value: Dictionary, key: String, low: int, high: int, errors: Array) -> int:
	var raw: Variant = value.get(key, null)
	if not _valid_json_int(raw, low, high):
		errors.append("pending auction %s invalid" % key)
		return low - 1
	return int(raw)


static func _int_array_field(value: Variant, player_count: int, label: String, errors: Array) -> Array:
	if typeof(value) != TYPE_ARRAY:
		errors.append("pending auction %s invalid" % label)
		return []
	var result: Array = []
	for item in value:
		if not _valid_json_int(item, 0, player_count - 1):
			errors.append("pending auction %s member invalid" % label)
			continue
		result.append(int(item))
	return result


static func _valid_json_int(value: Variant, low: int, high: int) -> bool:
	# JSON.parse_string represents numeric values as floats in Godot. Accept an
	# integral float at this boundary and let from_dict canonicalize it back to
	# an int after validation; reject fractional, non-finite, and other types.
	if typeof(value) == TYPE_INT:
		return int(value) >= low and int(value) <= high
	if typeof(value) == TYPE_FLOAT:
		var real := float(value)
		return is_finite(real) and floor(real) == real and real >= float(low) and real <= float(high)
	return false


static func _strict_sorted_unique(values: Array) -> bool:
	for index in range(1, values.size()):
		if int(values[index]) <= int(values[index - 1]):
			return false
	return true


static func _first_active_participant(participants: Array, withdrawn: Array) -> int:
	for value in participants:
		var participant_id := int(value)
		if not withdrawn.has(participant_id):
			return participant_id
	return -1


static func _next_active_participant(participants: Array, anchor_id: int, withdrawn: Array) -> int:
	var anchor_index := participants.find(anchor_id)
	if anchor_index < 0 or participants.is_empty():
		return -1
	for offset in range(1, participants.size() + 1):
		var index := (anchor_index + offset) % participants.size()
		var participant_id := int(participants[index])
		if participant_id != anchor_id and not withdrawn.has(participant_id):
			return participant_id
	return -1


static func _validate_runtime(game: Object, pending: Dictionary) -> Array:
	var data: Dictionary = game.state
	var players: Variant = data.get("players", null)
	var board: Variant = data.get("board", null)
	if typeof(players) != TYPE_ARRAY or typeof(board) != TYPE_ARRAY:
		return ["invalid state"]
	return _validate_static_shape(game, data, pending, players.size(), players, board, str(data.get("phase", "")), data.get("action_options", []))


static func _target_error(game: Object, node_id: int, tile: Dictionary) -> String:
	if tile.is_empty():
		return "拍賣目標不存在"
	var kind := str(tile.get("kind", ""))
	if kind not in ["property", "facility"]:
		return "拍賣目標必須是住宅或設施"
	var source_id: Variant = tile.get("source_object_id", null)
	if not _valid_json_int(source_id, 1, 1999):
		return "拍賣目標來源身分無效"
	var type_and_idx: Variant = tile.get("type_and_idx", null)
	var low := 2000 if kind == "property" else 4000
	var high := 3999 if kind == "property" else 5999
	if not _valid_json_int(type_and_idx, low + 1, high):
		return "拍賣目標來源類型無效"
	if kind == "facility":
		var record: Dictionary = game._facility_record(node_id)
		if record.is_empty() or int(record.get("source_object_id", -1)) != int(source_id):
			return "拍賣設施來源無效"
	return ""


static func _opening_bid(game: Object, tile: Dictionary) -> int:
	var base := int(tile.get("land_price", tile.get("cost", 0)))
	var level := int(tile.get("building_level", 0))
	if base < 0 or level < 0:
		return -1
	var truncated := int(float(base) * (1.0 + float(level) * 0.5))
	var price_index := int(game._facility_price_index()) if game.has_method("_facility_price_index") else 1
	return truncated * price_index


static func _participants(game: Object, caster_id: int, target: Dictionary, opening_bid: int) -> Array:
	var owner_id := int(target.get("owner", -1))
	if target.get("kind", "") == "facility":
		owner_id = int(game._facility_record(int(target.get("index", -1))).get("owner", owner_id))
	var result: Array = []
	for candidate_value in game._players():
		if typeof(candidate_value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = candidate_value
		var candidate_id: Variant = candidate.get("id", null)
		if not _valid_json_int(candidate_id, 0, game._players().size() - 1) or not bool(candidate.get("alive", false)) or bool(candidate.get("bankrupt", false)):
			continue
		var id := int(candidate_id)
		var is_caster_or_owner: bool = id == caster_id or id == owner_id
		if not is_caster_or_owner and (game._status_active(candidate) or game._sleep_active(candidate)):
			continue
		# The caster and current owner always receive a row; other players need
		# enough cash to reach at least the opening bid plus the minimum raise.
		if id not in [caster_id, owner_id] and int(candidate.get("cash", 0)) <= opening_bid:
			continue
		result.append(id)
	result.sort()
	return result


static func _capacity_errors(game: Object, pending: Dictionary, amount: int, bidder_id: int) -> Array:
	var errors: Array = []
	if amount < 0 or amount > MAX_CASH:
		return ["拍賣金額超出上限"]
	var bidder: Dictionary = game._player(bidder_id)
	if bidder.is_empty() or int(bidder.get("cash", 0)) < amount:
		errors.append("拍賣玩家現金不足")
	var caster_id := int(pending.get("caster_id", -1))
	var caster: Dictionary = game._player(caster_id)
	if caster.is_empty() or int(caster.get("deposit", 0)) > MAX_CASH - amount:
		errors.append("拍賣收款人的存款上限不足")
	var bank_value: Variant = game.state.get("bank", {})
	if typeof(bank_value) != TYPE_DICTIONARY:
		return errors + ["銀行資料無效"]
	var bank: Dictionary = bank_value
	if int(bank.get("deposits", 0)) > MAX_CASH - amount:
		errors.append("銀行存款總額上限不足")
	if int(bank.get("cash", 0)) > MAX_CASH - amount:
		errors.append("銀行現金上限不足")
	return errors


static func _headroom(game: Object, player_id: int, kind: String) -> int:
	var current := 0
	if kind == "deposit":
		current = int(game._player(player_id).get("deposit", 0))
	elif kind == "bank_deposits" or kind == "bank_cash":
		current = int(game.state.get("bank", {}).get("deposits" if kind == "bank_deposits" else "cash", 0))
	return max(0, MAX_CASH - current)


static func _advance_or_settle(game: Object, pending: Dictionary, cause: String) -> Dictionary:
	var highest := int(pending.get("highest_bidder_id", -1))
	var participants: Array = pending.get("participants", []).duplicate(true)
	var withdrawn: Array = pending.get("withdrawn", []).duplicate(true)
	var candidates: Array = []
	for id in participants:
		var candidate_id := int(id)
		if withdrawn.has(candidate_id) or candidate_id == highest:
			continue
		candidates.append(candidate_id)
	if candidates.is_empty():
		return _settle(game, pending, highest, cause)
	var current := int(pending.get("bidder_id", -1))
	var next_id := -1
	for offset in range(participants.size()):
		var index := (participants.find(current) + 1 + offset) % participants.size()
		var candidate_id := int(participants[index])
		if not withdrawn.has(candidate_id) and candidate_id != highest:
			next_id = candidate_id
			break
	if next_id < 0:
		next_id = int(candidates[0])
	pending["bidder_id"] = next_id
	game.state["pending_auction"] = pending
	game._set_action_options(int(pending.get("caster_id", -1)))
	return game._result(true, "拍賣等待下一位玩家", {"pending": pending.duplicate(true), "awaiting_response": true, "bidder_id": next_id})


static func _settle(game: Object, pending: Dictionary, winner_id: int, cause: String) -> Dictionary:
	var amount := int(pending.get("current_bid", 0)) if winner_id >= 0 else 0
	var capacity_errors := _capacity_errors(game, pending, amount, winner_id) if winner_id >= 0 else []
	if not capacity_errors.is_empty():
		return game._error(str(capacity_errors[0]))
	var caster_id := int(pending.get("caster_id", -1))
	var node_id := int(pending.get("node_id", -1))
	var target: Dictionary = game._tile_at(node_id)
	var card_player: Dictionary = game._player(caster_id)
	var consumed: Dictionary = {}
	# Calling through the preloaded inventory class keeps the operation atomic;
	# all fallible checks above have already passed.
	var inventory_script: Variant = load("res://game/core/inventory_rules.gd")
	if inventory_script == null:
		return game._error("卡片供給模組無法載入")
	consumed = inventory_script.consume_card(game.state["inventory_supply"], card_player["cards"], CARD_ID)
	if not bool(consumed.get("ok", false)):
		return game._error(str(consumed.get("error", "拍賣卡無法消耗")))
	var asset_id: int = game._facility_canonical_index(node_id) if target.get("kind", "") == "facility" else node_id
	for player_value in game._players():
		if typeof(player_value) == TYPE_DICTIONARY:
			game._remove_property_reference(int(player_value.get("id", -1)), asset_id)
	if winner_id >= 0:
		var bidder: Dictionary = game._player(winner_id)
		bidder["cash"] = int(bidder.get("cash", 0)) - amount
		var caster: Dictionary = game._player(caster_id)
		caster["deposit"] = int(caster.get("deposit", 0)) + amount
		var bank: Dictionary = game.state.get("bank", {})
		bank["deposits"] = int(bank.get("deposits", 0)) + amount
		bank["cash"] = int(bank.get("cash", 0)) + amount
		game.state["bank"] = bank
		if int(target.get("owner", -1)) < 0:
			game.LandTenure.acquire(game, target)
		if target.get("kind", "") == "facility":
			game._update_facility_records(int(target.get("source_object_id", -1)), {"owner": winner_id})
		else:
			target["owner"] = winner_id
		game._add_property_reference(winner_id, asset_id)
		game._record_event("auction_settled", {"caster_id": caster_id, "node_id": node_id, "winner_id": winner_id, "amount": amount, "cause": cause})
	else:
		if target.get("kind", "") == "facility":
			game._update_facility_records(int(target.get("source_object_id", -1)), {"owner": -1})
		else:
			target["owner"] = -1
		game._record_event("auction_no_sale", {"caster_id": caster_id, "node_id": node_id, "amount": 0, "cause": cause})
	game.state.erase("pending_auction")
	game._recalculate_property_values()
	game._set_action_options(int(game.state.get("current_player", caster_id)))
	return game._result(true, "拍賣成交" if winner_id >= 0 else "拍賣流標", {"settled": true, "winner_id": winner_id, "amount": amount, "no_sale": winner_id < 0})


static func _has_card(player: Dictionary, card_id: String) -> bool:
	var cards: Variant = player.get("cards", null)
	return typeof(cards) == TYPE_ARRAY and cards.has(card_id)
