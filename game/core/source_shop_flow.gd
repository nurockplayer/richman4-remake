extends RefCounted

## Source shop visits use the complete original-company ruleset, as do source
## bank/lottery encounters. The accepted inventory-only v4 API stays a direct
## metadata/bulk test surface; complete catalog games use this public boundary.
const Inventory = preload("res://game/core/inventory_rules.gd")
const Catalogue = preload("res://game/content/original_inventory.gd")
const LIMIT := 1000000000000

static func enabled(game: Object) -> bool:
	return game._is_companies() and game._is_inventory() and game._is_graph()

static func initialize(state: Dictionary) -> void:
	state["shop_sequence"] = 0
	state["shop_visit"] = {}

static func current(game: Object, allow_closed: bool = false) -> Dictionary:
	if not enabled(game): return {}
	var visit: Variant = game.state.get("shop_visit", {})
	if not visit is Dictionary or visit.is_empty(): return {}
	var player: Dictionary = game._current_player()
	if int(visit.get("player_id", -1)) != int(game.state.current_player) or int(visit.get("node_id", -1)) != int(player.get("position", -1)) or int(visit.get("turn", -1)) != int(game.state.turn) or not bool(player.get("alive", false)):
		return {}
	if bool(visit.get("closed", true)):
		return visit if allow_closed and game.state.phase == "await_action" else {}
	if game.state.phase != "await_shop": return {}
	# A saved human visit cannot silently become an AI command session.
	if bool(visit.human) != (bool(player.get("is_human", false)) and not bool(player.get("is_ai", true))): return {}
	return visit

static func admit(game: Object, player_id: int) -> bool:
	if not enabled(game): return false
	var player: Dictionary = game._player(player_id)
	var tile: Dictionary = game._tile_at(int(player.get("position", -1)))
	if player_id != int(game.state.current_player) or not bool(player.get("alive", false)) or int(tile.get("event_code", -1)) != 15 or game._status_active(player) or game._sleep_active(player): return false
	var old: Dictionary = game.state.get("shop_visit", {})
	if not old.is_empty() and int(old.get("turn", -1)) == int(game.state.turn) and int(old.get("player_id", -1)) == player_id and int(old.get("node_id", -1)) == int(player.position):
		return true # Repaint/re-entry cannot replenish or award the venue gift twice.
	var sequence := int(game.state.get("shop_sequence", 0)) + 1
	if sequence > 1000000000: return false
	game.state.shop_sequence = sequence
	var human := bool(player.get("is_human", false)) and not bool(player.get("is_ai", true))
	var company: Dictionary = game.get_company_at(int(player.position))
	var gift := _gift(game, player) if not company.is_empty() and int(company.get("owner", -1)) == player_id else {}
	var offers := sample_offers(game.state.inventory_supply, game._rng) if human else {"cards": [], "tools": []}
	var visit := {"visit_id": sequence, "player_id": player_id, "node_id": int(player.position), "turn": int(game.state.turn), "human": human, "closed": false, "card_offers": offers.cards, "tool_offers": offers.tools, "contribution": 0, "gift": gift, "gift_pending": human and not gift.is_empty()}
	game.state.shop_visit = visit
	game.state.phase = "await_shop"
	game.state.action_options = []
	game._record_event("shop_entered", {"player_id": player_id, "visit_id": sequence, "node_id": int(player.position), "gift": gift.duplicate(true)})
	if not human: ai_turn(game)
	return true

static func sample_offers(supply: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var cards: Array = []
	var remaining: Dictionary = supply.get("cards", {}).duplicate(true)
	var wanted := rng.randi_range(6, 15)
	for _slot in range(wanted):
		var total := 0
		for record in Catalogue.cards(): total += maxi(0, int(remaining.get(record.id, 0)))
		if total <= 0: break
		var pick := rng.randi_range(0, total - 1)
		for record in Catalogue.cards():
			pick -= maxi(0, int(remaining.get(record.id, 0)))
			if pick < 0:
				cards.append(int(record.source_id))
				remaining[record.id] = int(remaining[record.id]) - 1
				break
	var tools: Array = []
	for record in Catalogue.tools():
		if int(record.source_id) <= 8 and int(supply.get("tools", {}).get(record.id, 0)) > 0: tools.append(int(record.source_id))
	return {"cards": cards, "tools": tools}

static func _gift(game: Object, player: Dictionary) -> Dictionary:
	# The source selects the gift category first. Exhausted/capacity-limited
	# tool gifts safely yield no item; no unverified category reroll is added.
	if game._rng.randi_range(0, 1) == 0:
		var result: Dictionary = Inventory.receive_random_card(game.state.inventory_supply, player.cards, game._rng)
		if result.get("ok", false): return {"item_kind": "card", "item_id": str(result.card_id)}
	else:
		var candidates: Array = []
		for record in Catalogue.tools():
			if int(record.source_id) <= 8 and int(game.state.inventory_supply.tools.get(record.id, 0)) > 0 and int(player.tools.get(record.id, 0)) < 9: candidates.append(record)
		if not candidates.is_empty():
			var record: Dictionary = candidates[game._rng.randi_range(0, candidates.size()-1)]
			if Inventory.grant_tool(game.state.inventory_supply, player.tools, record.id, 1).get("ok", false): return {"item_kind": "tool", "item_id": str(record.id)}
	return {}

static func record(kind: String, source_id: int) -> Dictionary:
	var rows: Array = Catalogue.cards() if kind == "card" else Catalogue.tools() if kind == "tool" else []
	return rows[source_id - 1] if source_id >= 1 and source_id <= rows.size() else {}

static func snapshot(game: Object) -> Dictionary:
	var visit := current(game)
	if visit.is_empty(): return {}
	var result := visit.duplicate(true)
	result["edition"] = str(game.state.get("map_source", {}).get("edition", ""))
	result["mode"] = "cards"
	result["ready"] = not bool(visit.gift_pending)
	var player: Dictionary = game._current_player()
	result["points"] = int(player.points)
	result["cards"] = []
	for item_id in player.cards: result.cards.append(Catalogue.card(str(item_id)))
	result["tools"] = []
	for item in Catalogue.tools():
		var quantity := int(player.tools.get(item.id, 0))
		if quantity > 0:
			item["count"] = quantity
			result.tools.append(item)
	for kind in ["card", "tool"]:
		var key: String = kind + "_offers"
		result[key] = []
		for source_id in visit[key]: result[key].append(record(kind, int(source_id)))
	result["gift_message"] = "贈送 %s" % str(visit.gift.item_id) if not visit.gift.is_empty() else ""
	return result

static func acknowledge_gift(game: Object, visit_id: int) -> Dictionary:
	var visit := current(game)
	if visit.is_empty() or int(visit.visit_id) != visit_id or not bool(visit.gift_pending): return game._error("商店贈禮已失效")
	visit.gift_pending = false
	return game._result(true, "歡迎選購")

static func trade(game: Object, action: String, params: Dictionary) -> Dictionary:
	var visit := current(game)
	if visit.is_empty() or not bool(visit.human) or bool(visit.gift_pending) or not _integer(params.get("visit_id"), 1, 1000000000) or int(params.visit_id) != int(visit.visit_id): return game._error("商店造訪已失效")
	if action not in ["buy_item", "sell_item"] or typeof(params.get("quantity", 1)) != TYPE_INT or int(params.get("quantity", 1)) != 1: return game._error("商店每次只交易一件")
	var kind: Variant = params.get("item_kind")
	if typeof(kind) != TYPE_STRING or kind not in ["card", "tool"] or not _integer(params.get("source_id"), 1, 30): return game._error("商店物品無效")
	var source_id := int(params.source_id)
	var item := record(kind, source_id)
	if item.is_empty(): return game._error("商店物品無效")
	var held_index := -1
	var offer_index := -1
	if action == "buy_item":
		var offers: Array = visit[kind + "_offers"]
		if not _integer(params.get("offer_index"), 0, offers.size()-1): return game._error("商店商品列無效")
		offer_index = int(params.offer_index)
		if int(offers[offer_index]) != source_id: return game._error("商店商品列已售出")
	else:
		var holdings: Array = snapshot(game).get("cards" if kind == "card" else "tools", [])
		if not _integer(params.get("held_index"), 0, holdings.size()-1): return game._error("商店持有物品列無效")
		held_index = int(params.held_index)
		if int(holdings[held_index].source_id) != source_id: return game._error("商店持有物品列已變更")
	var result := _direct_trade(game, action, kind, str(item.id), held_index)
	if not bool(result.get("ok", false)): return result
	if offer_index >= 0: visit[kind + "_offers"][offer_index] = 0
	return game._result(true, "商品交易完成", {"item_kind": kind, "source_id": source_id, "quantity": 1, "visit_id": int(visit.visit_id)})

static func _direct_trade(game: Object, action: String, kind: String, item_id: String, held_index: int = -1) -> Dictionary:
	var visit := current(game)
	if visit.is_empty(): return game._error("目前沒有商店造訪")
	var contribution := Inventory.quote_buy(kind, item_id, 1) * (10 if action == "buy_item" else 1)
	var company: Dictionary = game.get_company_at(int(visit.node_id))
	var total := int(visit.contribution) + contribution
	if contribution < 0 or total > LIMIT or (not company.is_empty() and (int(company.monthly_profit) > LIMIT-total or int(company.cumulative_profit) > LIMIT-total)): return game._error("商店帳務超出上限")
	var result: Dictionary = game._trade_item(int(visit.player_id), action, {"item_kind": kind, "item_id": item_id, "quantity": 1, "held_index": held_index})
	if bool(result.get("ok", false)): visit.contribution = total
	return result

static func leave(game: Object, visit_id: int) -> Dictionary:
	var visit := current(game)
	if visit.is_empty() or int(visit.visit_id) != visit_id: return game._error("商店造訪已失效")
	var company: Dictionary = game.get_company_at(int(visit.node_id))
	var contribution := int(visit.contribution)
	if not company.is_empty():
		if int(company.monthly_profit) > LIMIT-contribution or int(company.cumulative_profit) > LIMIT-contribution: return game._error("商店帳務超出上限")
		company.monthly_profit = int(company.monthly_profit) + contribution
		company.cumulative_profit = int(company.cumulative_profit) + contribution
	visit.closed = true
	visit.gift_pending = false
	game.state.phase = "await_action"
	game._set_action_options(int(visit.player_id))
	game._record_event("shop_closed", {"player_id": int(visit.player_id), "visit_id": visit_id, "contribution": contribution})
	return game._result(true, "已離開商店")

static func ai_turn(game: Object) -> void:
	var visit := current(game)
	if visit.is_empty() or bool(visit.human): return
	var player: Dictionary = game._current_player()
	# Bounded existing-item policy: source AI trades directly, never through
	# human randomized offers. Exact character preferences remain unverified.
	if int(player.points) < 100:
		var cheapest := ""
		var price := LIMIT
		for item_id in player.cards:
			var item_price := Inventory.quote_buy("card", item_id, 1)
			if item_price < price:
				cheapest = str(item_id)
				price = item_price
		if not cheapest.is_empty(): _direct_trade(game, "sell_item", "card", cheapest)
		for item in Catalogue.tools():
			if int(player.tools.get(item.id, 0)) > 1: _direct_trade(game, "sell_item", "tool", item.id)
	var budget := int(player.points) / 2
	var cards: Array = Catalogue.cards()
	cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.price) < int(b.price) if a.price != b.price else int(a.source_id) < int(b.source_id))
	for item in cards:
		if int(item.price) > budget or player.cards.size() >= 15: break
		if _direct_trade(game, "buy_item", "card", item.id).get("ok", false): budget -= int(item.price)
	for item in Catalogue.tools():
		if int(item.source_id) > 8: break
		if int(player.points) >= int(item.price) and int(player.tools.get(item.id, 0)) < 9: _direct_trade(game, "buy_item", "tool", item.id)
	leave(game, int(visit.visit_id))

static func _integer(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

static func validate(data: Dictionary, supported: bool) -> Array:
	if not supported:
		return ["source shop requires complete original-company rules"] if data.has("shop_visit") or data.has("shop_sequence") else []
	# Missing fields admit a low-cost structural migration, never old semantics.
	if not data.has("shop_visit") and not data.has("shop_sequence"):
		return ["pending shop has no visit"] if data.get("phase") == "await_shop" else []
	if not _integer(data.get("shop_sequence"), 0, 1000000000) or not data.get("shop_visit") is Dictionary: return ["invalid source shop state"]
	var visit: Dictionary = data.shop_visit
	if visit.is_empty(): return ["pending shop has no visit"] if data.get("phase") == "await_shop" else []
	var players: Variant = data.get("players")
	var board: Variant = data.get("board")
	if not players is Array or not board is Array or not _integer(visit.get("visit_id"), 1, int(data.shop_sequence)) or not _integer(visit.get("player_id"), 0, players.size()-1) or not _integer(visit.get("node_id"), 0, board.size()-1): return ["invalid source shop identity"]
	var player: Variant = players[int(visit.player_id)]
	var tile: Variant = board[int(visit.node_id)]
	if not player is Dictionary or not tile is Dictionary or not _integer(visit.get("turn"), 1, 1000000000) or not _integer(data.get("turn"), int(visit.turn), int(visit.turn)) or not _integer(data.get("current_player"), int(visit.player_id), int(visit.player_id)) or not _integer(player.get("position"), int(visit.node_id), int(visit.node_id)) or not bool(player.get("alive", false)) or not _integer(tile.get("event_code"), 15, 15): return ["stale source shop owner"]
	for key in ["human", "closed", "gift_pending"]:
		if typeof(visit.get(key)) != TYPE_BOOL: return ["invalid source shop flag"]
	if bool(visit.human) != (bool(player.get("is_human", false)) and not bool(player.get("is_ai", true))): return ["source shop actor mismatch"]
	if data.get("phase") != ("await_action" if visit.closed else "await_shop"): return ["source shop phase mismatch"]
	if not _integer(visit.get("contribution"), 0, LIMIT) or not visit.get("gift") is Dictionary: return ["invalid source shop contribution or gift"]
	if not visit.gift.is_empty():
		if visit.gift.get("item_kind") not in ["card", "tool"] or typeof(visit.gift.get("item_id")) != TYPE_STRING: return ["invalid source shop gift"]
		var gift_record: Dictionary = Catalogue.card(visit.gift.item_id) if visit.gift.item_kind == "card" else Catalogue.tool(visit.gift.item_id)
		if gift_record.is_empty(): return ["invalid source shop gift"]
	if visit.gift_pending and (visit.closed or visit.gift.is_empty() or not visit.human): return ["invalid source shop gift lifetime"]
	for kind in ["card", "tool"]:
		var rows: Variant = visit.get(kind + "_offers")
		if not rows is Array or rows.size() > (15 if kind == "card" else 8) or (not visit.human and not rows.is_empty()): return ["invalid source shop offer rows"]
		var previous := 0
		for source_id in rows:
			if not _integer(source_id, 0, 30 if kind == "card" else 8): return ["invalid source shop offer identity"]
			if kind == "tool" and int(source_id) > 0:
				if int(source_id) <= previous: return ["source shop tools must retain source order"]
				previous = int(source_id)
	if not visit.closed:
		if data.get("action_options") != []: return ["pending source shop has ordinary actions"]
		for key in ["pending_bank_visit", "pending_trap", "pending_finance", "pending_auction"]:
			var pending: Variant = data.get(key, {})
			if not pending is Dictionary or not pending.is_empty(): return ["source shop overlaps another decision"]
	return []
