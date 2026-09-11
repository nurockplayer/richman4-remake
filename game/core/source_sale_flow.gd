extends RefCounted

## Source SALE bulletin board: offers describe holdings without escrow.
## Public human sessions and the once-per-turn AI path share settlement.
const Inventory = preload("res://game/core/inventory_rules.gd")
const Catalogue = preload("res://game/content/original_inventory.gd")
const Accounting = preload("res://game/core/stock_accounting.gd")
const Market = preload("res://game/core/original_stock_market.gd")
const TrusteePreferences = preload("res://game/core/trustee_preferences.gd")
const LIMIT := 1000000000000
const ID_LIMIT := 1000000000
const CATEGORIES := ["stock", "property", "tool", "card"]
# Source player profile table at MJ VA 0x47e80c, stride 104, sex byte +20.
const CHARACTER_SEX := [1,1,1,0,1,0,1,0,0,0,1,0]
const CHARACTER_PERSONALITY := [2,1,2,2,1,1,1,0,0,0,1,2]

static func enabled(game: Object) -> bool:
	return game._is_companies() and game._is_inventory() and game._is_graph()

static func initialize(state: Dictionary) -> void:
	var offers: Array = []
	for _player in state.get("players", []): offers.append([])
	state["sale_board"] = {"offers": offers, "sequence": 0, "session_sequence": 0, "session": {}, "ai_last_turn": {}}

static func _ordinary(game: Object, human: bool) -> bool:
	if not enabled(game) or game.state.get("phase", "") not in ["await_roll", "await_action"]: return false
	var player: Dictionary = game._current_player()
	if player.is_empty() or not bool(player.get("alive", false)) or game._status_active(player) or game._sleep_active(player): return false
	if human != (bool(player.get("is_human", false)) and not bool(player.get("is_ai", true))): return false
	if int(game.state.get("company_service_pending", 0)) != 0: return false
	for key in ["pending_bank_visit", "pending_trap", "pending_finance", "pending_auction", "pending_remote_dice"]:
		if not game.state.get(key, {}).is_empty(): return false
	return true

static func can_open(game: Object) -> bool:
	return _ordinary(game, true) and int(game.state.get("sale_board", {}).get("session_sequence", ID_LIMIT)) < ID_LIMIT

static func current(game: Object) -> Dictionary:
	if not enabled(game) or game.state.get("phase") != "await_sale": return {}
	var session: Dictionary = game.state.get("sale_board", {}).get("session", {})
	if session.is_empty() or int(session.player_id) != int(game.state.current_player) or int(session.turn) != int(game.state.turn): return {}
	var player: Dictionary = game._current_player()
	if not bool(player.get("alive", false)) or not bool(player.get("is_human", false)) or bool(player.get("is_ai", true)) or game._status_active(player) or game._sleep_active(player): return {}
	if int(game.state.get("company_service_pending", 0)) != 0: return {}
	for key in ["pending_bank_visit", "pending_trap", "pending_finance", "pending_auction", "pending_remote_dice"]:
		if not game.state.get(key, {}).is_empty(): return {}
	return session

static func open(game: Object) -> Dictionary:
	if not can_open(game): return game._error("目前無法開啟販賣欄")
	cleanup(game)
	var board: Dictionary = game.state.sale_board
	board.session_sequence = int(board.session_sequence) + 1
	board.session = {"session_id": int(board.session_sequence), "player_id": int(game.state.current_player), "turn": int(game.state.turn), "return_phase": str(game.state.phase)}
	game.state.phase = "await_sale"
	game.state.action_options = []
	return game._result(true, "販賣欄", {"session_id": int(board.session_sequence)})

static func close(game: Object, session_id: int) -> Dictionary:
	var session := current(game)
	if session.is_empty() or int(session.session_id) != session_id: return game._error("販賣操作已失效")
	game.state.phase = str(session.return_phase)
	game.state.sale_board.session = {}
	game._set_action_options(int(game.state.current_player))
	return game._result(true, "返回遊戲")

static func _session_request(game: Object, params: Dictionary) -> bool:
	var session := current(game)
	return not session.is_empty() and _input_integer(params.get("session_id"), 1, ID_LIMIT) and int(params.session_id) == int(session.session_id)

static func _item(category: String, source_id: int) -> Dictionary:
	var rows: Array = Catalogue.tools() if category == "tool" else Catalogue.cards() if category == "card" else []
	return rows[source_id - 1] if source_id > 0 and source_id <= rows.size() else {}

static func _property(game: Object, source_id: int) -> Dictionary:
	if not (source_id > 2000 and source_id < 4000 or source_id > 4000 and source_id < 6000): return {}
	for tile in game.state.board:
		if int(tile.get("type_and_idx", 0)) == source_id and tile.get("kind") in ["property", "facility"]:
			return game._facility_record(int(tile.index)) if tile.kind == "facility" else tile
	return {}

static func _building_type(tile: Dictionary) -> int:
	return int(tile.get("facility_type", 0)) if tile.get("kind") == "facility" else 1 if bool(tile.get("is_chain_store", false)) else 0

static func _property_identity(tile: Dictionary) -> Dictionary:
	return {"building_level": int(tile.get("building_level", 0)), "building_type": _building_type(tile)}

static func reference_value(game: Object, category: String, source_id: int, quantity: int = 1) -> int:
	if category == "stock":
		if source_id < 0 or source_id >= 12 or quantity <= 0: return 0
		return int(float(quantity) * float(game.state.market.prices.get(Market.symbol(source_id), 0.0)))
	if category == "property":
		var tile := _property(game, source_id)
		return game.inventory_purchase_price(tile) if not tile.is_empty() else 0
	var item := _item(category, source_id)
	return int(item.price) * 100 * game._facility_price_index() if not item.is_empty() else 0

static func maximum_asking(reference: int) -> int:
	return LIMIT if reference > LIMIT / 10 else maxi(0, reference * 10)

static func holdings(game: Object, player_id: int) -> Dictionary:
	var result := {"stock": [], "property": [], "tool": [], "card": []}
	var player: Dictionary = game._player(player_id)
	for source_id in range(12):
		var symbol := Market.symbol(source_id)
		var quantity := int(player.stocks.get(symbol, 0))
		if quantity > 0: result.stock.append({"source_id": source_id, "name": game.get_stock_name(symbol), "quantity": quantity, "reference_value": reference_value(game, "stock", source_id, quantity)})
	var seen := {}
	for tile_value in game.state.board:
		var source_id := int(tile_value.get("type_and_idx", 0))
		if seen.has(source_id): continue
		var tile := _property(game, source_id)
		if tile.is_empty() or int(tile.get("owner", -1)) != player_id: continue
		seen[source_id] = true
		var identity := _property_identity(tile)
		var kind := "facility" if tile.kind == "facility" else "land"
		var row := {"source_id": source_id, "name": str(tile.get("name", "")), "quantity": 1, "reference_value": reference_value(game, "property", source_id), "kind": kind, "property_kind": kind, "location": str(tile.get("name", "")), "development": str(identity.building_level) + " 級", "rent": int(tile.get("rent", 0)), "lease": int(tile.get("lease_months", 0))}
		row.merge(identity)
		result.property.append(row)
	result.property.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.source_id) < int(b.source_id))
	for item in Catalogue.tools():
		var quantity := int(player.tools.get(item.id, 0))
		if quantity > 0: result.tool.append({"source_id": int(item.source_id), "name": str(item.name), "quantity": quantity, "reference_value": reference_value(game, "tool", int(item.source_id))})
	for index in range(player.cards.size()):
		var item: Dictionary = Catalogue.card(str(player.cards[index]))
		result.card.append({"source_id": int(item.source_id), "name": str(item.name), "quantity": 1, "held_index": index, "reference_value": reference_value(game, "card", int(item.source_id))})
	return result

static func _decorated(game: Object, offer: Dictionary) -> Dictionary:
	var result := offer.duplicate(true)
	result["reference_value"] = reference_value(game, str(offer.category), int(offer.source_id), int(offer.quantity))
	result["name"] = game.get_stock_name(Market.symbol(int(offer.source_id))) if offer.category == "stock" else str(_item(str(offer.category), int(offer.source_id)).get("name", ""))
	if offer.category == "property":
		var tile := _property(game, int(offer.source_id))
		result.merge({"name": str(tile.get("name", "")), "location": str(tile.get("name", "")), "development": str(tile.get("building_level", 0)) + " 級", "rent": int(tile.get("rent", 0)), "lease": int(tile.get("lease_months", 0)), "kind": "facility" if tile.get("kind") == "facility" else "land", "property_kind": "facility" if tile.get("kind") == "facility" else "land"}, true)
	return result

static func snapshot(game: Object) -> Dictionary:
	var session := current(game)
	if session.is_empty(): return {}
	var result := session.duplicate(true)
	result["edition"] = str(game.state.get("map_source", {}).get("edition", ""))
	result["view"] = "board"
	result["players"] = []
	var board: Dictionary = game.state.sale_board
	for player in game.state.players:
		var character := clampi(int(player.get("character_id", 0)), 0, 11)
		var row := {"player_id": int(player.id), "name": str(player.name), "character_id": character, "sex": CHARACTER_SEX[character], "alive": bool(player.alive), "offers": []}
		for offer in board.offers[int(player.id)]: row.offers.append(_decorated(game, offer))
		result.players.append(row)
	result["holdings"] = holdings(game, int(session.player_id))
	result["can_create"] = board.offers[int(session.player_id)].size() < 7 and int(board.sequence) < ID_LIMIT
	result["cash"] = int(game._current_player().cash)
	result["deposit"] = int(game._current_player().deposit)
	result["price_index"] = game._facility_price_index()
	return result

static func _holding_valid(game: Object, offer: Dictionary) -> bool:
	var player: Dictionary = game._player(int(offer.seller_id))
	if player.is_empty() or not bool(player.get("alive", false)): return false
	var category := str(offer.category)
	var source_id := int(offer.source_id)
	if category == "stock": return int(player.stocks.get(Market.symbol(source_id), 0)) >= int(offer.quantity)
	if category == "property":
		var tile := _property(game, source_id)
		return not tile.is_empty() and int(tile.get("owner", -1)) == int(offer.seller_id) and _property_identity(tile) == offer.get("property_snapshot", {})
	var item := _item(category, source_id)
	if item.is_empty(): return false
	return player.cards.has(item.id) if category == "card" else int(player.tools.get(item.id, 0)) >= 1

static func cleanup(game: Object, age: bool = false) -> void:
	if not enabled(game): return
	for offers in game.state.sale_board.offers:
		for index in range(offers.size()-1, -1, -1):
			if not _holding_valid(game, offers[index]): offers.remove_at(index)
			elif age: offers[index].days = (int(offers[index].days) + 1) & 255

static func create_offer(game: Object, params: Dictionary) -> Dictionary:
	if not _session_request(game, params): return game._error("販賣操作已失效")
	return _create(game, int(game.state.current_player), params)

static func _create(game: Object, seller_id: int, params: Dictionary) -> Dictionary:
	if typeof(params.get("category")) != TYPE_STRING or params.category not in CATEGORIES or not _input_integer(params.get("source_id"), 0, 5999) or not _input_integer(params.get("quantity"), 1, ID_LIMIT) or not _input_integer(params.get("asking"), 1, LIMIT): return game._error("販賣數量或售價無效")
	var category := str(params.category)
	var source_id := int(params.source_id)
	var quantity := int(params.quantity)
	if category != "stock" and quantity != 1: return game._error("每筆道具、卡片或不動產只販賣一件")
	if category == "stock" and source_id >= 12 or category in ["tool", "card"] and _item(category, source_id).is_empty(): return game._error("販賣項目無效")
	var offer := {"offer_id": 0, "revision": 1, "seller_id": seller_id, "category": category, "source_id": source_id, "quantity": quantity, "asking": int(params.asking), "days": 0}
	if category == "property": offer["property_snapshot"] = _property_identity(_property(game, source_id))
	if not _holding_valid(game, offer): return game._error("持有項目已不足或變更")
	if int(params.asking) > maximum_asking(reference_value(game, category, source_id, quantity)): return game._error("售價不得超過參考價值的十倍")
	var board: Dictionary = game.state.sale_board
	var offers: Array = board.offers[seller_id]
	for index in range(offers.size()):
		var old: Dictionary = offers[index]
		if old.category == category and int(old.source_id) == source_id:
			if int(old.revision) >= ID_LIMIT: return game._error("販賣版本已達上限")
			offer.offer_id = int(old.offer_id)
			offer.revision = int(old.revision) + 1
			offers[index] = offer
			return game._result(true, "已更新販賣", {"offer": _decorated(game, offer)})
	if offers.size() >= 7 or int(board.sequence) >= ID_LIMIT: return game._error("販賣欄已滿")
	board.sequence = int(board.sequence) + 1
	offer.offer_id = int(board.sequence)
	offers.append(offer)
	return game._result(true, "已刊登販賣", {"offer": _decorated(game, offer)})

static func _find(game: Object, offer_id: int) -> Dictionary:
	for offers in game.state.sale_board.offers:
		for offer in offers:
			if int(offer.offer_id) == offer_id: return offer
	return {}

static func _requested_offer(game: Object, params: Dictionary) -> Dictionary:
	if not _input_integer(params.get("offer_id"), 1, ID_LIMIT) or not _input_integer(params.get("revision"), 1, ID_LIMIT): return {}
	var offer := _find(game, int(params.offer_id))
	return offer if not offer.is_empty() and int(offer.revision) == int(params.revision) else {}

static func cancel_offer(game: Object, params: Dictionary) -> Dictionary:
	if not _session_request(game, params): return game._error("販賣操作已失效")
	var offer := _requested_offer(game, params)
	if offer.is_empty() or int(offer.seller_id) != int(game.state.current_player): return game._error("只能取消目前自己的販賣")
	game.state.sale_board.offers[int(offer.seller_id)].erase(offer)
	return game._result(true, "已取消販賣")

static func accept_offer(game: Object, params: Dictionary) -> Dictionary:
	if not _session_request(game, params): return game._error("販賣操作已失效")
	var offer := _requested_offer(game, params)
	if offer.is_empty(): return game._error("販賣項目已失效")
	return _accept(game, int(game.state.current_player), offer)

static func _accept(game: Object, buyer_id: int, offer: Dictionary) -> Dictionary:
	var seller_id := int(offer.seller_id)
	if buyer_id == seller_id or not _holding_valid(game, offer): return game._error("販賣項目已失效")
	var buyer: Dictionary = game._player(buyer_id)
	var seller: Dictionary = game._player(seller_id)
	var amount := int(offer.asking)
	if not bool(buyer.get("alive", false)) or int(buyer.cash) < amount: return game._error("現金不足")
	var bank: Dictionary = game.state.bank
	if int(seller.deposit) > LIMIT - amount or int(bank.deposits) > LIMIT - amount or int(bank.cash) > LIMIT - amount: return game._error("銀行存款已達上限")
	var category := str(offer.category)
	var source_id := int(offer.source_id)
	var quantity := int(offer.quantity)
	var supply: Dictionary = {}
	var buyer_items: Variant = null
	var seller_items: Variant = null
	if category in ["tool", "card"]:
		var item := _item(category, source_id)
		if category == "card" and buyer.cards.size() >= 15 or category == "tool" and int(buyer.tools.get(item.id, 0)) >= 9: return game._error("背包已滿")
		# Stage the existing inventory transfer so every failure precedes money
		# and offer mutation. Consuming then granting preserves finite supply.
		supply = game.state.inventory_supply.duplicate(true)
		buyer_items = buyer.cards.duplicate() if category == "card" else buyer.tools.duplicate()
		seller_items = seller.cards.duplicate() if category == "card" else seller.tools.duplicate()
		var removed: Dictionary = Inventory.consume_card(supply, seller_items, item.id) if category == "card" else Inventory.consume_tool(supply, seller_items, item.id, 1)
		if not removed.get("ok", false): return game._error("販賣項目已不足")
		var granted: Dictionary = Inventory.grant_card(supply, buyer_items, item.id) if category == "card" else Inventory.grant_tool(supply, buyer_items, item.id, 1)
		if not granted.get("ok", false): return game._error("背包無法接收物品")
	elif category == "stock":
		if int(buyer.stocks.get(Market.symbol(source_id), 0)) > ID_LIMIT - quantity: return game._error("持股已達上限")
	buyer.cash = int(buyer.cash) - amount
	seller.deposit = int(seller.deposit) + amount
	bank.deposits = int(bank.deposits) + amount
	bank.cash = int(bank.cash) + amount
	game.state.sale_board.offers[seller_id].erase(offer)
	if category in ["tool", "card"]:
		game.state.inventory_supply = supply
		buyer["cards" if category == "card" else "tools"] = buyer_items
		seller["cards" if category == "card" else "tools"] = seller_items
	elif category == "stock":
		var symbol := Market.symbol(source_id)
		seller.stocks[symbol] = int(seller.stocks[symbol]) - quantity
		buyer.stocks[symbol] = int(buyer.stocks[symbol]) + quantity
		Accounting.record_sale(seller, symbol, quantity, game.get_stock_symbols())
		Accounting.record_purchase(buyer, symbol, quantity, amount, game.get_stock_symbols())
		game._update_company_owners()
		game._finish_company_trade(buyer_id)
	else:
		var tile := _property(game, source_id)
		var asset_id: int = game._facility_canonical_index(int(tile.index)) if tile.kind == "facility" else int(tile.index)
		for player in game.state.players: game._remove_property_reference(int(player.id), asset_id)
		if tile.kind == "facility": game._update_facility_records(int(tile.source_object_id), {"owner": buyer_id})
		else: tile.owner = buyer_id
		game._add_property_reference(buyer_id, asset_id)
		game._recalculate_property_values()
	cleanup(game)
	# A stock-company ownership hook may end or advance the buyer's turn.
	if game.state.phase != "await_sale" or int(game.state.current_player) != buyer_id or not bool(buyer.alive): game.state.sale_board.session = {}
	game._record_event("sale_accepted", {"seller_id": seller_id, "buyer_id": buyer_id, "category": category, "source_id": source_id, "quantity": quantity, "amount": amount, "offer_id": int(offer.offer_id)})
	return game._result(true, "交易完成", {"offer_id": int(offer.offer_id)})

static func ai_turn(game: Object) -> void:
	if not _ordinary(game, false) or game.state.phase != "await_roll": return
	var player_id := int(game.state.current_player)
	var board: Dictionary = game.state.sale_board
	var turn := int(game.state.turn)
	if int(board.ai_last_turn.get(str(player_id), -1)) == turn: return
	board.ai_last_turn[str(player_id)] = turn
	cleanup(game)
	var player: Dictionary = game._player(player_id)
	if game._rng.randi_range(0, 14) == 0:
		var candidates: Array = []
		var category := "card"
		if player.cards.size() > 12:
			# The source weights every ordered pair of equal card slots.
			for first in range(player.cards.size()):
				for second in range(player.cards.size()):
					if first != second and player.cards[first] == player.cards[second]: candidates.append(int(Catalogue.card(str(player.cards[first])).source_id))
		if candidates.is_empty():
			category = "tool"
			var preferences: Dictionary = TrusteePreferences.for_player(game.state, player_id)
			var personality := int(preferences.get("personality", CHARACTER_PERSONALITY[clampi(int(player.get("character_id", 0)),0,11)]))
			for item in Catalogue.tools():
				var quantity := int(player.tools.get(item.id, 0))
				if quantity >= 3 or quantity > 0 and int(item.source_flags[1]) - personality == 2: candidates.append(int(item.source_id))
		if not candidates.is_empty():
			var source_id := int(candidates[game._rng.randi_range(0, candidates.size()-1)])
			if board.offers[player_id].size() >= 7: board.offers[player_id].pop_front()
			_create(game, player_id, {"category": category, "source_id": source_id, "quantity": 1, "asking": reference_value(game, category, source_id)})
	if game._rng.randi_range(0, 2) == 0:
		for offer in board.offers[player_id]:
			if offer.category in ["tool", "card"] and int(offer.revision) < ID_LIMIT:
				var reference := reference_value(game, str(offer.category), int(offer.source_id))
				if reference > 0 and reference <= LIMIT and int(offer.asking) != reference:
					offer.asking = reference
					offer.revision = int(offer.revision) + 1
	if game._rng.randi_range(0, 3) == 0:
		for seller_offers in board.offers:
			for offer in seller_offers.duplicate():
				if int(offer.seller_id) == player_id: continue
				var reference := reference_value(game, str(offer.category), int(offer.source_id), int(offer.quantity))
				var affordable := int(player.cash) >= int(offer.asking)
				var desirable := false
				if offer.category == "stock": desirable = int(int(offer.asking) / int(offer.quantity)) < float(game.state.market.prices[Market.symbol(int(offer.source_id))])
				elif offer.category == "property": desirable = int(offer.asking) < reference * 3 and int(player.cash) > int(offer.asking) * 2
				# Source AI considers stocks and property only; tools/cards remain listings.
				if affordable and desirable and _accept(game, player_id, offer).get("ok", false):
					game._sync_state()
					return
	game._sync_state()

static func _input_integer(value: Variant, low: int, high: int) -> bool:
	return typeof(value) == TYPE_INT and value >= low and value <= high

static func _integer(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

static func validate(data: Dictionary, supported: bool) -> Array:
	if not supported: return ["source sale requires complete original-company rules"] if data.has("sale_board") else []
	if not data.has("sale_board"): return ["pending sale has no board"] if data.get("phase") == "await_sale" else []
	var board: Variant = data.sale_board
	var players: Variant = data.get("players")
	if not board is Dictionary or not players is Array or not board.get("offers") is Array or board.offers.size() != players.size() or not board.get("session") is Dictionary or not board.get("ai_last_turn") is Dictionary: return ["invalid source sale board"]
	for key in ["sequence", "session_sequence"]:
		if not _integer(board.get(key), 0, ID_LIMIT): return ["invalid source sale sequence"]
	var seen := {}
	for seller_id in range(players.size()):
		var offers: Variant = board.offers[seller_id]
		if not offers is Array or offers.size() > 7: return ["invalid source sale offer count"]
		var items := {}
		for offer in offers:
			if not offer is Dictionary or typeof(offer.get("category")) != TYPE_STRING or offer.category not in CATEGORIES: return ["invalid source sale category"]
			if not _integer(offer.get("offer_id"), 1, int(board.sequence)) or seen.has(int(offer.offer_id)) or not _integer(offer.get("revision"), 1, ID_LIMIT) or not _integer(offer.get("seller_id"), seller_id, seller_id) or not _integer(offer.get("source_id"), 0, 5999) or not _integer(offer.get("quantity"), 1, ID_LIMIT) or not _integer(offer.get("asking"), 1, LIMIT) or not _integer(offer.get("days"), 0, 255): return ["invalid source sale offer"]
			seen[int(offer.offer_id)] = true
			var item_key := str(offer.category) + ":" + str(int(offer.source_id))
			if items.has(item_key): return ["duplicate source sale item"]
			items[item_key] = true
			if offer.category != "stock" and int(offer.quantity) != 1: return ["invalid source sale quantity"]
			if offer.category == "stock" and int(offer.source_id) >= 12 or offer.category in ["tool", "card"] and _item(str(offer.category), int(offer.source_id)).is_empty(): return ["invalid source sale item identity"]
			if offer.category == "property":
				var source_id := int(offer.source_id)
				if not (source_id > 2000 and source_id < 4000 or source_id > 4000 and source_id < 6000): return ["invalid source sale property identity"]
				var identity: Variant = offer.get("property_snapshot")
				if not identity is Dictionary or not _integer(identity.get("building_level"), 0, 5) or not _integer(identity.get("building_type"), 0, 4): return ["invalid source sale building snapshot"]
	for key in board.ai_last_turn:
		if typeof(key) != TYPE_STRING or not key.is_valid_int() or str(int(key)) != key or not _integer(int(key), 0, players.size()-1) or not _integer(board.ai_last_turn[key], 1, ID_LIMIT): return ["invalid source sale AI guard"]
	var session: Dictionary = board.session
	if session.is_empty(): return ["pending sale has no session"] if data.get("phase") == "await_sale" else []
	if data.get("phase") != "await_sale" or not _integer(session.get("session_id"), 1, int(board.session_sequence)) or not _integer(session.get("player_id"), 0, players.size()-1) or not _integer(session.get("turn"), 1, ID_LIMIT) or session.get("return_phase") not in ["await_roll", "await_action"]: return ["invalid source sale session"]
	var player: Variant = players[int(session.player_id)]
	if not player is Dictionary or not bool(player.get("alive", false)) or not bool(player.get("is_human", false)) or bool(player.get("is_ai", true)) or not _integer(data.get("current_player"), int(session.player_id), int(session.player_id)) or not _integer(data.get("turn"), int(session.turn), int(session.turn)): return ["stale source sale actor"]
	if data.get("action_options") != [] or not _integer(data.get("company_service_pending", 0), 0, 0): return ["pending source sale has ordinary actions"]
	for key in ["pending_bank_visit", "pending_trap", "pending_finance", "pending_auction", "pending_remote_dice"]:
		if not data.get(key, {}) is Dictionary or not data.get(key, {}).is_empty(): return ["source sale overlaps another decision"]
	return []
