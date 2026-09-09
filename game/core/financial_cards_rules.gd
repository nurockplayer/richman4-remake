class_name RichmanFinancialCardsRules
extends RefCounted

## Rules for the passive 免費 response and active 查稅 card.
##
## The state object owns movement and payment primitives.  This module keeps
## the card decisions, pending record shape, and tax defence ordering together
## so every entry point uses the same atomic boundaries.

const OriginalInventory = preload("res://game/core/inventory_rules.gd")

const FREE_CARD := "免費"
const TAX_CARD := "查稅"
const SCAPEGOAT_CARD := "嫁禍"
const MAX_CASH: int = 1000000000000
const PENDING_KEYS := ["kind", "stage", "payer_id", "creditor_id", "amount", "node_id", "caster_id"]
const FEE_KINDS := ["rent", "facility", "company"]
const KINDS := ["rent", "facility", "company", "tax"]


static func is_financial_card(card_id: String) -> bool:
	return card_id == FREE_CARD or card_id == TAX_CARD


static func response(game: Object) -> Dictionary:
	var value: Variant = game.state.get("pending_finance", {})
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


static func tax_target_players(game: Object, caster_id: int) -> Array:
	var targets: Array = []
	if not game._is_inventory() or not game._valid_player(caster_id, true):
		return targets
	for candidate in game._players():
		if typeof(candidate) != TYPE_DICTIONARY:
			continue
		var candidate_id: Variant = candidate.get("id", null)
		if typeof(candidate_id) != TYPE_INT or int(candidate_id) == caster_id:
			continue
		if not bool(candidate.get("alive", false)) or game._status_active(candidate):
			continue
		targets.append(int(candidate_id))
	targets.sort()
	return targets


static func use_card(game: Object, player_id: int, card_id: String, target_id: Variant, cancel: Variant) -> Dictionary:
	if card_id == FREE_CARD:
		return game._error("免費卡只能在付款時回應")
	if card_id != TAX_CARD:
		return game._error("未知金融卡片")
	if typeof(cancel) != TYPE_BOOL:
		return game._error("查稅取消參數無效")
	var caster: Dictionary = game._player(player_id)
	if caster.is_empty() or not bool(caster.get("alive", false)):
		return game._error("目前玩家無法使用查稅卡")
	if not _has_card(caster, TAX_CARD):
		return game._error("沒有這張卡片")
	if bool(cancel):
		return game._result(true, "已取消查稅卡")
	if typeof(target_id) != TYPE_INT:
		return game._error("查稅目標格式無效")
	if not tax_target_players(game, player_id).has(int(target_id)):
		return game._error("查稅目標無效")
	var target: Dictionary = game._player(int(target_id))
	var amount: int = _tax_amount(target)
	# A direct tax transfers immediately. Validate the destination before card
	# consumption so a save-ceiling failure leaves the whole action unchanged.
	if not _can_tax_transfer(game, player_id, int(target_id), amount):
		return game._error("查稅轉帳超出現金上限")
	var consume: Dictionary = _consume_card(game, player_id, TAX_CARD)
	if not bool(consume.get("ok", false)):
		return game._error(str(consume.get("error", "查稅卡無法使用")))
	game._record_event("card_used", {"player_id": player_id, "card_id": TAX_CARD, "target_id": int(target_id), "amount": amount, "effect": "tax"})
	# 免費 is always offered first for a human payer, including amount zero.
	# AI decisions use the source threshold and never create a human prompt.
	if _has_card(target, FREE_CARD):
		if bool(target.get("is_human", false)) and not bool(target.get("is_ai", false)):
			_set_pending(game, "tax", "free", int(target_id), player_id, amount, player_id, player_id)
			game._record_event("financial_response_requested", {"kind": "tax", "stage": "free", "payer_id": int(target_id), "creditor_id": player_id, "amount": amount, "node_id": int(caster.get("position", -1)), "caster_id": player_id})
			return game._result(true, "等待免費卡回應", {"awaiting_response": true, "kind": "tax", "stage": "free", "amount": amount})
		var threshold: int = _ai_threshold(game)
		if amount > int(target.get("cash", 0)) or amount > threshold:
			if not _consume_card(game, int(target_id), FREE_CARD).get("ok", false):
				return game._error("免費卡無法使用")
			game._record_event("financial_free_used", {"kind": "tax", "payer_id": int(target_id), "amount": amount, "ai": true})
			return game._result(true, "AI 使用免費卡", {"waived": true, "amount": amount})
	# AI declines 免費.  A deterministic fallback may use 嫁禍 immediately;
	# redirected tax deliberately bypasses all recursive defences.
	if _has_card(target, SCAPEGOAT_CARD) and amount > 2000:
		var redirect_id: int = _first_redirect_target(game, int(target_id))
		if redirect_id >= 0:
			if not _consume_card(game, int(target_id), SCAPEGOAT_CARD).get("ok", false):
				return game._error("嫁禍卡無法使用")
			var redirected_amount: int = _tax_amount(game._player(redirect_id))
			if not _can_tax_transfer(game, player_id, redirect_id, redirected_amount):
				return game._error("嫁禍後查稅轉帳超出現金上限")
			_settle_tax(game, player_id, redirect_id, redirected_amount)
			game._record_event("financial_tax_redirected", {"caster_id": player_id, "from_payer_id": int(target_id), "payer_id": redirect_id, "amount": redirected_amount, "ai": true})
			return game._result(true, "AI 使用嫁禍卡", {"redirected": true, "target_id": redirect_id, "amount": redirected_amount})
	_settle_tax(game, player_id, int(target_id), amount)
	return game._result(true, "查稅完成", {"target_id": int(target_id), "amount": amount})


static func maybe_offer_free(game: Object, debtor_id: int, creditor_id: int, amount: int, node_id: int, kind: String, free_allowed: bool = true) -> Dictionary:
	if not free_allowed or not FEE_KINDS.has(kind) or amount <= 0 or game.state.has("pending_finance"):
		return {"offered": false}
	var debtor: Dictionary = game._player(debtor_id)
	if debtor.is_empty() or not bool(debtor.get("alive", false)) or not _has_card(debtor, FREE_CARD):
		return {"offered": false}
	var price_index: int = int(game._facility_price_index()) if game.has_method("_facility_price_index") else 1
	var threshold_amount: int = 2000 * max(1, price_index)
	var cash_plus_deposit: int = int(debtor.get("cash", 0)) + int(debtor.get("deposit", 0))
	if amount < threshold_amount and amount <= cash_plus_deposit:
		return {"offered": false}
	if bool(debtor.get("is_human", false)) and not bool(debtor.get("is_ai", false)):
		_set_pending(game, kind, "free", debtor_id, creditor_id, amount, node_id, -1)
		game._record_event("financial_response_requested", {"kind": kind, "stage": "free", "payer_id": debtor_id, "creditor_id": creditor_id, "amount": amount, "node_id": node_id, "caster_id": -1})
		return {"offered": true, "awaiting_response": true}
	var threshold: int = _ai_threshold(game)
	if amount > int(debtor.get("cash", 0)) or amount > threshold:
		var consumed: Dictionary = _consume_card(game, debtor_id, FREE_CARD)
		if not bool(consumed.get("ok", false)):
			return {"offered": true, "error": str(consumed.get("error", "免費卡無法使用"))}
		game._record_event("financial_free_used", {"kind": kind, "payer_id": debtor_id, "amount": amount, "ai": true})
		return {"offered": true, "waived": true}
	return {"offered": true, "declined": true}


static func respond(game: Object, params: Dictionary) -> Dictionary:
	var pending: Dictionary = response(game)
	if pending.is_empty() or pending.size() != PENDING_KEYS.size():
		return game._error("目前沒有待回應的金融付款")
	if not params.has("cancel") or typeof(params.get("cancel")) != TYPE_BOOL:
		return game._error("金融付款回應格式無效")
	var cancel: bool = bool(params.get("cancel"))
	var kind: String = str(pending.get("kind", ""))
	var stage: String = str(pending.get("stage", ""))
	var payer_id: int = int(pending.get("payer_id", -1))
	var creditor_id: int = int(pending.get("creditor_id", -1))
	var amount: int = int(pending.get("amount", -1))
	var node_id: int = int(pending.get("node_id", -1))
	var caster_id: int = int(pending.get("caster_id", -1))
	if not _pending_runtime_context(game, pending):
		return game._error("金融付款回應已失效")
	if kind == TAX_CARD or kind == "tax":
		return _respond_tax(game, pending, params)
	if stage != "free" or not FEE_KINDS.has(kind):
		return game._error("金融付款階段無效")
	if cancel:
		if not _settle_fee(game, payer_id, creditor_id, amount, kind):
			return game._error("金融付款無法結算")
		_clear_pending(game)
		game._record_event("financial_free_declined", {"kind": kind, "payer_id": payer_id, "amount": amount})
		_finish_payment_turn(game, payer_id)
		return game._result(true, "已拒絕免費卡", {"declined": true, "kind": kind, "amount": amount})
	if not _consume_card(game, payer_id, FREE_CARD).get("ok", false):
		return game._error("免費卡無法使用")
	_clear_pending(game)
	game._record_event("financial_free_used", {"kind": kind, "payer_id": payer_id, "amount": amount, "ai": false})
	game._record_event("financial_payment_waived", {"kind": kind, "payer_id": payer_id, "creditor_id": creditor_id, "amount": amount})
	game._set_action_options(int(game.state.get("current_player", -1)))
	return game._result(true, "已使用免費卡", {"waived": true, "kind": kind, "amount": amount})


static func _respond_tax(game: Object, pending: Dictionary, params: Dictionary) -> Dictionary:
	var cancel: bool = bool(params.get("cancel", false))
	var payer_id: int = int(pending.get("payer_id", -1))
	var caster_id: int = int(pending.get("caster_id", -1))
	var original_amount: int = int(pending.get("amount", -1))
	if str(pending.get("stage", "")) == "free":
		if not cancel:
			if not _consume_card(game, payer_id, FREE_CARD).get("ok", false):
				return game._error("免費卡無法使用")
			_clear_pending(game)
			game._record_event("financial_free_used", {"kind": "tax", "payer_id": payer_id, "amount": original_amount, "ai": false})
			game._set_action_options(int(game.state.get("current_player", -1)))
			return game._result(true, "已使用免費卡", {"waived": true, "kind": "tax", "amount": original_amount})
		# 嫁禍 is unlocked only by the original amount strictly above 2,000.
		var payer: Dictionary = game._player(payer_id)
		if original_amount > 2000 and _has_card(payer, SCAPEGOAT_CARD) and not _redirect_targets(game, payer_id).is_empty():
			pending["stage"] = "redirect"
			game.state["pending_finance"] = pending
			game.state["action_options"] = ["respond_finance"]
			game._record_event("financial_redirect_requested", {"caster_id": caster_id, "payer_id": payer_id, "amount": original_amount})
			return game._result(true, "等待嫁禍卡回應", {"awaiting_response": true, "stage": "redirect", "amount": original_amount})
		var direct_amount: int = _tax_amount(payer)
		if not _can_tax_transfer(game, caster_id, payer_id, direct_amount):
			return game._error("查稅轉帳超出現金上限")
		_clear_pending(game)
		_settle_tax(game, caster_id, payer_id, direct_amount)
		game._record_event("financial_free_declined", {"kind": "tax", "payer_id": payer_id, "amount": original_amount})
		_finish_payment_turn(game, payer_id)
		return game._result(true, "已拒絕免費卡", {"declined": true, "kind": "tax", "amount": direct_amount})
	if str(pending.get("stage", "")) != "redirect":
		return game._error("查稅回應階段無效")
	if cancel:
		var original_target: Dictionary = game._player(payer_id)
		var original_direct_amount: int = _tax_amount(original_target)
		if not _can_tax_transfer(game, caster_id, payer_id, original_direct_amount):
			return game._error("查稅轉帳超出現金上限")
		_clear_pending(game)
		_settle_tax(game, caster_id, payer_id, original_direct_amount)
		_finish_payment_turn(game, payer_id)
		return game._result(true, "已取消嫁禍", {"declined": true, "target_id": payer_id, "amount": original_direct_amount})
	# The caller adds target_id to the params; validate it before consuming
	# 嫁禍 so malformed responses remain atomic.
	if not params.has("target_id") or typeof(params.get("target_id")) != TYPE_INT:
		return game._error("嫁禍回應缺少目標")
	var target_id: int = int(params.get("target_id"))
	if not _redirect_targets(game, payer_id).has(target_id):
		return game._error("嫁禍目標無效")
	var target: Dictionary = game._player(target_id)
	var amount: int = _tax_amount(target)
	if not _can_tax_transfer(game, caster_id, target_id, amount):
		return game._error("嫁禍後查稅轉帳超出現金上限")
	if not bool(_consume_card(game, payer_id, SCAPEGOAT_CARD).get("ok", false)):
		return game._error("嫁禍卡無法使用")
	_clear_pending(game)
	_settle_tax(game, caster_id, target_id, amount)
	game._record_event("financial_tax_redirected", {"caster_id": caster_id, "from_payer_id": payer_id, "payer_id": target_id, "amount": amount})
	game._set_action_options(int(game.state.get("current_player", -1)))
	return game._result(true, "已使用嫁禍卡", {"redirected": true, "target_id": target_id, "amount": amount})


static func _pending_runtime_context(game: Object, pending: Dictionary) -> bool:
	var kind: String = str(pending.get("kind", ""))
	var stage: String = str(pending.get("stage", ""))
	if not KINDS.has(kind) or not ["free", "redirect"].has(stage):
		return false
	if stage == "redirect" and kind != "tax":
		return false
	var payer_id: int = int(pending.get("payer_id", -1))
	var caster_id: int = int(pending.get("caster_id", -1))
	var payer: Dictionary = game._player(payer_id)
	if payer.is_empty() or not bool(payer.get("alive", false)):
		return false
	if int(game.state.get("current_player", -1)) != (caster_id if kind == "tax" else payer_id):
		return false
	if not bool(payer.get("is_human", false)) or bool(payer.get("is_ai", false)):
		return false
	if game._status_active(payer):
		return false
	var phase: String = str(game.state.get("phase", ""))
	if not ["await_roll", "await_action"].has(phase) or game.state.get("action_options", []) != ["respond_finance"]:
		return false
	if typeof(game.state.get("pending_remote_dice", {})) != TYPE_DICTIONARY or not game.state.get("pending_remote_dice", {}).is_empty():
		return false
	if not game._pending_trap().is_empty():
		return false
	if int(game.state.get("company_service_pending", 0)) > 0:
		return false
	if not _has_card(payer, FREE_CARD):
		return false
	if stage == "redirect" and not _has_card(payer, SCAPEGOAT_CARD):
		return false
	var amount: Variant = pending.get("amount", null)
	var node_id: Variant = pending.get("node_id", null)
	var creditor_id: Variant = pending.get("creditor_id", null)
	if typeof(amount) != TYPE_INT or int(amount) < 0 or int(amount) > MAX_CASH or typeof(node_id) != TYPE_INT:
		return false
	if int(node_id) < 0 or int(node_id) >= game.state.get("board", []).size():
		return false
	if kind == "tax":
		if typeof(creditor_id) != TYPE_INT or int(creditor_id) != caster_id or payer_id == caster_id:
			return false
		var caster: Dictionary = game._player(caster_id)
		if caster.is_empty() or int(caster.get("position", -1)) != int(node_id):
			return false
		if int(amount) != _tax_amount(payer):
			return false
		if stage == "redirect" and (int(amount) <= 2000 or not _has_card(payer, SCAPEGOAT_CARD)):
			return false
		return true
	if typeof(creditor_id) != TYPE_INT or int(caster_id) != -1 or int(node_id) != int(payer.get("position", -2)):
		return false
	if kind == "rent" or kind == "facility":
		if not game._valid_player(int(creditor_id), true) or int(creditor_id) == payer_id:
			return false
		var owner: Dictionary = game._player(int(creditor_id))
		if not bool(owner.get("alive", false)):
			return false
	elif kind == "company":
		if int(creditor_id) > -2:
			return false
	else:
		return false
	return true


static func _settle_fee(game: Object, payer_id: int, creditor_id: int, amount: int, kind: String) -> bool:
	if amount < 0 or not FEE_KINDS.has(kind):
		return false
	if creditor_id >= 0 and not _can_credit_player(game, creditor_id, amount):
		return false
	game._charge_amount(payer_id, amount, creditor_id, kind, false)
	return true


static func _tax_amount(target: Dictionary) -> int:
	return int(floor(float(max(0, int(target.get("cash", 0)))) * 0.2))


static func _can_tax_transfer(game: Object, caster_id: int, target_id: int, amount: int) -> bool:
	if amount < 0 or amount > MAX_CASH:
		return false
	var target: Dictionary = game._player(target_id)
	var caster: Dictionary = game._player(caster_id)
	if target.is_empty() or caster.is_empty() or not bool(target.get("alive", false)) or not bool(caster.get("alive", false)):
		return false
	if target_id == caster_id:
		# 嫁禍 may select the tax caster. The source resolves that choice as a
		# no-op rather than taxing and crediting the same cash balance.
		return true
	if int(target.get("cash", 0)) < amount:
		return false
	return int(caster.get("cash", 0)) <= MAX_CASH - amount


static func _can_credit_player(game: Object, player_id: int, amount: int) -> bool:
	var player: Dictionary = game._player(player_id)
	return not player.is_empty() and amount >= 0 and int(player.get("cash", 0)) <= MAX_CASH - amount


static func _settle_tax(game: Object, caster_id: int, target_id: int, amount: int) -> void:
	if target_id == caster_id or amount <= 0:
		return
	var target: Dictionary = game._player(target_id)
	var caster: Dictionary = game._player(caster_id)
	target["cash"] = int(target.get("cash", 0)) - amount
	caster["cash"] = int(caster.get("cash", 0)) + amount
	game._record_event("payment", {"player_id": target_id, "creditor_id": caster_id, "amount": amount, "reason": "tax_card"})


static func _set_pending(game: Object, kind: String, stage: String, payer_id: int, creditor_id: int, amount: int, node_id: int, caster_id: int) -> void:
	game.state["pending_finance"] = {"kind": kind, "stage": stage, "payer_id": payer_id, "creditor_id": creditor_id, "amount": amount, "node_id": node_id, "caster_id": caster_id}
	game.state["action_options"] = ["respond_finance"]


static func _clear_pending(game: Object) -> void:
	game.state.erase("pending_finance")


static func _has_card(player: Dictionary, card_id: String) -> bool:
	var cards: Variant = player.get("cards", [])
	return typeof(cards) == TYPE_ARRAY and cards.has(card_id)


static func _consume_card(game: Object, player_id: int, card_id: String) -> Dictionary:
	var player: Dictionary = game._player(player_id)
	if player.is_empty() or not _has_card(player, card_id):
		return {"ok": false, "error": "玩家沒有這張卡片"}
	return OriginalInventory.consume_card(game.state.get("inventory_supply", {}), player["cards"], card_id)


static func _ai_threshold(game: Object) -> int:
	var price_index: int = int(game._facility_price_index()) if game.has_method("_facility_price_index") else 1
	return (3000 + int(game._rng.randi_range(0, 2999))) * max(1, price_index)


static func _first_redirect_target(game: Object, excluded_id: int) -> int:
	var targets: Array = _redirect_targets(game, excluded_id)
	return int(targets[0]) if not targets.is_empty() else -1


static func _redirect_targets(game: Object, excluded_id: int) -> Array:
	var result: Array = []
	for candidate in game._players():
		if typeof(candidate) != TYPE_DICTIONARY:
			continue
		var candidate_id: Variant = candidate.get("id", null)
		if typeof(candidate_id) != TYPE_INT or int(candidate_id) == excluded_id or not bool(candidate.get("alive", false)):
			continue
		result.append(int(candidate_id))
	result.sort()
	return result


static func _finish_payment_turn(game: Object, payer_id: int) -> void:
	if not bool(game._player(payer_id).get("alive", false)):
		if int(game.state.get("current_player", -1)) == payer_id and game.state.get("phase", "") != "game_over":
			game._advance_to_next_alive(payer_id)
		return
	game._set_action_options(int(game.state.get("current_player", -1)))


static func validate_pending(data: Dictionary, player_count: int, board: Variant, phase_name: String, action_options: Variant, inventory_save: bool, status_save: bool, companies_save: bool) -> Array:
	var errors: Array = []
	if not data.has("pending_finance"):
		return errors
	if not inventory_save:
		errors.append("pending finance requires inventory save")
	var value: Variant = data.get("pending_finance")
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("invalid pending finance")
		return errors
	var pending: Dictionary = value
	if pending.size() != PENDING_KEYS.size():
		errors.append("pending finance keys are not canonical")
	for key in PENDING_KEYS:
		if not pending.has(key):
			errors.append("pending finance missing " + key)
	for key in pending.keys():
		if not PENDING_KEYS.has(key):
			errors.append("pending finance unexpected field")
	if not errors.is_empty():
		return errors
	var kind_value: Variant = pending.get("kind")
	var stage_value: Variant = pending.get("stage")
	var kind: String = str(kind_value)
	var stage: String = str(stage_value)
	if typeof(kind_value) != TYPE_STRING or not KINDS.has(kind):
		errors.append("pending finance kind invalid")
	if typeof(stage_value) != TYPE_STRING or not ["free", "redirect"].has(stage):
		errors.append("pending finance stage invalid")
	if stage == "redirect" and kind != "tax":
		errors.append("pending finance redirect kind invalid")
	var numeric_fields_valid := true
	for key in ["payer_id", "creditor_id", "amount", "node_id", "caster_id"]:
		if not _valid_integer(pending.get(key)):
			errors.append("pending finance %s invalid" % key)
			numeric_fields_valid = false
	if not numeric_fields_valid:
		return errors
	var payer_id: int = int(pending.get("payer_id", -1))
	var creditor_id: int = int(pending.get("creditor_id", -1))
	var amount: int = int(pending.get("amount", -1))
	var node_id: int = int(pending.get("node_id", -1))
	var caster_id: int = int(pending.get("caster_id", -1))
	if payer_id < 0 or payer_id >= player_count:
		errors.append("pending finance payer invalid")
	if amount < 0 or amount > MAX_CASH:
		errors.append("pending finance amount invalid")
	if typeof(board) != TYPE_ARRAY or node_id < 0 or node_id >= board.size():
		errors.append("pending finance node invalid")
	if phase_name not in ["await_roll", "await_action"]:
		errors.append("pending finance outside action phase")
	if typeof(action_options) != TYPE_ARRAY or action_options != ["respond_finance"]:
		errors.append("pending finance action options mismatch")
	var players: Variant = data.get("players", null)
	if typeof(players) != TYPE_ARRAY or payer_id < 0 or payer_id >= players.size():
		return errors
	var payer: Variant = players[payer_id]
	if typeof(payer) != TYPE_DICTIONARY:
		return errors
	var payer_record: Dictionary = payer
	if not bool(payer_record.get("alive", false)) or bool(payer_record.get("bankrupt", false)):
		errors.append("pending finance payer unavailable")
	if not bool(payer_record.get("is_human", false)) or bool(payer_record.get("is_ai", false)):
		errors.append("pending finance payer must be human")
	if int(payer_record.get("hospital_days", 0)) > 0 or int(payer_record.get("prison_days", 0)) > 0:
		errors.append("pending finance payer detained")
	if stage == "free" and not _array_has_card(payer_record, FREE_CARD):
		errors.append("pending finance payer lacks free card")
	if stage == "redirect" and not _array_has_card(payer_record, SCAPEGOAT_CARD):
		errors.append("pending finance payer lacks scapegoat")
	if typeof(data.get("pending_trap", {})) == TYPE_DICTIONARY and not data.get("pending_trap", {}).is_empty():
		errors.append("pending finance conflicts with pending trap")
	if typeof(data.get("pending_remote_dice", {})) == TYPE_DICTIONARY and not data.get("pending_remote_dice", {}).is_empty():
		errors.append("pending finance conflicts with remote dice")
	if companies_save and int(data.get("company_service_pending", 0)) > 0:
		errors.append("pending finance conflicts with company service")
	if kind == "tax":
		if caster_id < 0 or caster_id >= player_count or payer_id == caster_id or creditor_id != caster_id:
			errors.append("pending tax identity invalid")
		elif typeof(players[caster_id]) == TYPE_DICTIONARY and int(players[caster_id].get("position", -1)) != node_id:
			errors.append("pending tax node mismatch")
		if stage == "redirect" and (amount <= 2000 or not _array_has_card(payer_record, SCAPEGOAT_CARD)):
			errors.append("pending redirect threshold invalid")
	else:
		if caster_id != -1 or payer_id != int(data.get("current_player", -2)) or node_id != int(payer_record.get("position", -3)):
			errors.append("pending fee context mismatch")
		if kind in ["rent", "facility"]:
			if creditor_id < 0 or creditor_id >= player_count or creditor_id == payer_id:
				errors.append("pending fee creditor invalid")
		elif kind == "company" and creditor_id > -2:
			errors.append("pending company creditor invalid")
	return errors


static func _array_has_card(player: Dictionary, card_id: String) -> bool:
	var cards: Variant = player.get("cards", null)
	return typeof(cards) == TYPE_ARRAY and cards.has(card_id)


static func _valid_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		return is_finite(value) and floor(value) == value
	return false
