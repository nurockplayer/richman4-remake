class_name RichmanOriginalInventory
extends RefCounted

## Deterministic card, tool and point-shop lifecycle rules.
##
## The caller owns the game state and passes its shared supply and player
## containers into these functions.  The supply shape is:
## {"cards": {card_id: remaining_count}, "tools": {tool_id: remaining_count}}
## where all IDs are the short Chinese strings from the original catalogue.
## Player cards are an Array of IDs; player tools are a sparse Dictionary of
## IDs to quantities.  Mutating operations preserve those container references.

const Catalogue = preload("res://game/content/original_inventory.gd")

const CARD_CAPACITY: int = Catalogue.CARD_CAPACITY
const TOOL_CAPACITY_PER_TYPE: int = Catalogue.TOOL_CAPACITY_PER_TYPE
const SHOP_SALE_RATE: float = 0.9
const FINITE_TOOL_SOURCE_ID_MAX: int = 8
const INITIAL_TOOL_SOURCE_IDS: Array = [1, 2, 3, 4, 8, 9]
const CARD_KIND := "card"
const TOOL_KIND := "tool"


static func new_supply() -> Dictionary:
	var card_supply: Dictionary = {}
	for record in Catalogue.cards():
		card_supply[str(record["id"])] = int(record["initial_supply"])
	var tool_supply: Dictionary = {}
	for record in Catalogue.tools():
		tool_supply[str(record["id"])] = int(record["initial_supply"])
	return {"cards": card_supply, "tools": tool_supply}


static func empty_tools() -> Dictionary:
	return {}


## Initialize one new player, consuming the finite opening tool supply.
## Existing unrelated player fields are retained.  The operation is atomic.
static func initialize_player(player: Dictionary, supply: Dictionary) -> Dictionary:
	if not player is Dictionary:
		return _failure("玩家資料格式無效。")
	return initialize_players([player], supply)


## Initialize every player in one atomic operation.  Each player receives one
## each of source tool IDs 1, 2, 3, 4, 8 and 9, empty cards, and zero points.
static func initialize_players(players: Array, supply: Dictionary) -> Dictionary:
	if not _valid_supply(supply):
		return _failure("共享供給格式無效。")
	for player in players:
		if not player is Dictionary:
			return _failure("玩家資料格式無效。")

	var player_count: int = players.size()
	var staged_supply: Dictionary = supply.duplicate(true)
	var staged_tools_by_player: Array = []
	var staged_tool_supply: Dictionary = staged_supply["tools"]
	for source_id in INITIAL_TOOL_SOURCE_IDS:
		var record: Dictionary = _record_for(TOOL_KIND, source_id)
		if record.is_empty():
			return _failure("開局道具目錄無效。")
		if int(record["source_id"]) > FINITE_TOOL_SOURCE_ID_MAX:
			continue
		var tool_id: String = str(record["id"])
		var available: int = int(staged_tool_supply[tool_id])
		if available < player_count:
			return _failure("開局道具供給不足。")
		staged_tool_supply[tool_id] = available - player_count

	for _player in players:
		var starting_tools: Dictionary = empty_tools()
		for source_id in INITIAL_TOOL_SOURCE_IDS:
			var record: Dictionary = _record_for(TOOL_KIND, source_id)
			starting_tools[str(record["id"])] = 1
		staged_tools_by_player.append(starting_tools)

	_commit_supply(supply, staged_supply)
	for index in range(players.size()):
		var player: Dictionary = players[index]
		_set_player_array(player, "cards", [])
		_set_player_dictionary(player, "tools", staged_tools_by_player[index])
		player["points"] = 0
	return _success({"players": players.size(), "tool_source_ids": INITIAL_TOOL_SOURCE_IDS.duplicate()})


## Draw one card using the caller's already-seeded shared RNG.  This low-level
## operation reserves the card by decrementing the shared pool and returns the
## canonical ID; it does not put the card in a player's hand.  Use
## receive_random_card when the draw is meant to reach a player.  Catalogue
## order is the tie/order authority, so the same RNG state produces the same
## result.  No RNG call or mutation occurs in either failure case.
static func draw_card(supply: Dictionary, rng: RandomNumberGenerator) -> String:
	if not _valid_supply(supply) or rng == null:
		return ""
	var selected_id: String = _weighted_card_id(supply, rng)
	if selected_id.is_empty():
		return ""

	var staged_supply: Dictionary = supply.duplicate(true)
	var staged_cards: Dictionary = staged_supply["cards"]
	staged_cards[selected_id] = int(staged_cards[selected_id]) - 1
	_commit_supply(supply, staged_supply)
	return selected_id


## Atomically draw one card into a player's hand.  The weighted selection,
## finite-pool debit, full-hand eviction and append are one lifecycle step;
## callers must not follow this with grant_card for the same draw.
static func receive_random_card(supply: Dictionary, player_cards: Array, rng: RandomNumberGenerator) -> Dictionary:
	if not _valid_supply(supply) or not _valid_cards(player_cards) or rng == null:
		return _failure("卡片供給、背包或亂數格式無效。")
	var selected_id: String = _weighted_card_id(supply, rng)
	if selected_id.is_empty():
		return _failure("沒有可抽取的卡片。")
	var selected_record: Dictionary = _record_for(CARD_KIND, selected_id)
	var result: Dictionary = _grant_card_record(supply, player_cards, selected_record)
	if not bool(result.get("ok", false)):
		return result
	result["drawn_card_id"] = selected_id
	return result


## Grant one card from the finite shared pool.  At capacity, the first card
## with the lowest catalogue price is returned to the pool before the new card
## is appended.  Equal prices retain the first card in the player's Array.
static func grant_card(supply: Dictionary, player_cards: Array, identifier: Variant) -> Dictionary:
	var record: Dictionary = _record_for(CARD_KIND, identifier)
	if record.is_empty():
		return _failure("卡片代號無效。")
	if not _valid_supply(supply) or not _valid_cards(player_cards):
		return _failure("卡片供給或背包格式無效。")
	if player_cards.size() > CARD_CAPACITY:
		return _failure("卡片背包超出上限。")
	return _grant_card_record(supply, player_cards, record)


static func _grant_card_record(supply: Dictionary, player_cards: Array, record: Dictionary) -> Dictionary:
	var card_id: String = str(record["id"])

	var card_supply: Dictionary = supply["cards"]
	var available: int = int(card_supply[card_id])
	if available <= 0:
		return _failure("卡片供給不足。")

	var staged_cards: Array = player_cards.duplicate(true)
	var evicted_id: String = ""
	if staged_cards.size() == CARD_CAPACITY:
		var evicted_index: int = _first_cheapest_card_index(staged_cards)
		if evicted_index < 0:
			return _failure("找不到可歸還的卡片。")
		evicted_id = str(staged_cards[evicted_index])
		staged_cards.remove_at(evicted_index)
	staged_cards.append(card_id)

	var staged_supply: Dictionary = supply.duplicate(true)
	var staged_card_supply: Dictionary = staged_supply["cards"]
	staged_card_supply[card_id] = available - 1
	if not evicted_id.is_empty():
		staged_card_supply[evicted_id] = int(staged_card_supply[evicted_id]) + 1
	_commit_supply(supply, staged_supply)
	_replace_array(player_cards, staged_cards)
	return _success({"card_id": card_id, "evicted_card_id": evicted_id})


## Consume one owned card and return it to the finite shared pool.
static func consume_card(supply: Dictionary, player_cards: Array, identifier: Variant) -> Dictionary:
	var record: Dictionary = _record_for(CARD_KIND, identifier)
	if record.is_empty():
		return _failure("卡片代號無效。")
	if not _valid_supply(supply) or not _valid_cards(player_cards):
		return _failure("卡片供給或背包格式無效。")
	var card_id: String = str(record["id"])
	var card_index: int = player_cards.find(card_id)
	if card_index < 0:
		return _failure("玩家沒有這張卡片。")

	var staged_cards: Array = player_cards.duplicate(true)
	staged_cards.remove_at(card_index)
	var staged_supply: Dictionary = supply.duplicate(true)
	var staged_card_supply: Dictionary = staged_supply["cards"]
	staged_card_supply[card_id] = int(staged_card_supply[card_id]) + 1
	_commit_supply(supply, staged_supply)
	_replace_array(player_cards, staged_cards)
	return _success({"card_id": card_id})


## Grant quantity units of a tool.  Source IDs 1..8 consume finite shared
## supply; research tools 9..13 have no shared stock limit.  Every player's
## tool type remains at or below nine units.
static func grant_tool(supply: Dictionary, player_tools: Dictionary, identifier: Variant, quantity: Variant = 1) -> Dictionary:
	var record: Dictionary = _record_for(TOOL_KIND, identifier)
	if record.is_empty():
		return _failure("道具代號無效。")
	if not _valid_quantity(quantity):
		return _failure("道具數量無效。")
	if not _valid_supply(supply) or not _valid_tools(player_tools):
		return _failure("道具供給或背包格式無效。")

	var tool_id: String = str(record["id"])
	var requested: int = int(quantity)
	var owned: int = int(player_tools.get(tool_id, 0))
	if owned + requested > TOOL_CAPACITY_PER_TYPE:
		return _failure("道具數量超出上限。")

	var source_id: int = int(record["source_id"])
	var staged_supply: Dictionary = supply.duplicate(true)
	if source_id <= FINITE_TOOL_SOURCE_ID_MAX:
		var staged_tool_supply: Dictionary = staged_supply["tools"]
		var available: int = int(staged_tool_supply[tool_id])
		if available < requested:
			return _failure("道具供給不足。")
		staged_tool_supply[tool_id] = available - requested

	var staged_tools: Dictionary = player_tools.duplicate(true)
	staged_tools[tool_id] = owned + requested
	_commit_supply(supply, staged_supply)
	_replace_dictionary(player_tools, staged_tools)
	return _success({"tool_id": tool_id, "quantity": requested})


## Consume quantity units of a tool.  Finite tools are returned to shared
## supply; research tools simply leave the player inventory.
static func consume_tool(supply: Dictionary, player_tools: Dictionary, identifier: Variant, quantity: Variant = 1) -> Dictionary:
	var record: Dictionary = _record_for(TOOL_KIND, identifier)
	if record.is_empty():
		return _failure("道具代號無效。")
	if not _valid_quantity(quantity):
		return _failure("道具數量無效。")
	if not _valid_supply(supply) or not _valid_tools(player_tools):
		return _failure("道具供給或背包格式無效。")

	var tool_id: String = str(record["id"])
	var requested: int = int(quantity)
	var owned: int = int(player_tools.get(tool_id, 0))
	if owned < requested:
		return _failure("玩家沒有足夠的道具。")

	var staged_supply: Dictionary = supply.duplicate(true)
	var source_id: int = int(record["source_id"])
	if source_id <= FINITE_TOOL_SOURCE_ID_MAX:
		var staged_tool_supply: Dictionary = staged_supply["tools"]
		staged_tool_supply[tool_id] = int(staged_tool_supply[tool_id]) + requested

	var staged_tools: Dictionary = player_tools.duplicate(true)
	var remaining: int = owned - requested
	if remaining == 0:
		staged_tools.erase(tool_id)
	else:
		staged_tools[tool_id] = remaining
	_commit_supply(supply, staged_supply)
	_replace_dictionary(player_tools, staged_tools)
	return _success({"tool_id": tool_id, "quantity": requested})


## Full listed price for a shop purchase.
## Returns -1 for an invalid item or quantity.
static func quote_buy(item_kind: String, identifier: Variant, quantity: Variant = 1) -> int:
	var record: Dictionary = _record_for(item_kind, identifier)
	if record.is_empty() or not _valid_quote_quantity(quantity):
		return -1
	return int(record["price"]) * int(quantity)


## Shop sale value: truncate(total listed price * 0.9), with the multiplication
## performed before truncation for quantities greater than one.
## Returns -1 for an invalid item or quantity.
static func quote_sale(item_kind: String, identifier: Variant, quantity: Variant = 1) -> int:
	var purchase_price: int = quote_buy(item_kind, identifier, quantity)
	if purchase_price < 0:
		return -1
	return int(floor(float(purchase_price) * SHOP_SALE_RATE))


## Short aliases keep callers readable at purchase/sale sites.
static func buy_price(item_kind: String, identifier: Variant, quantity: Variant = 1) -> int:
	return quote_buy(item_kind, identifier, quantity)


static func sale_price(item_kind: String, identifier: Variant, quantity: Variant = 1) -> int:
	return quote_sale(item_kind, identifier, quantity)


static func _weighted_card_id(supply: Dictionary, rng: RandomNumberGenerator) -> String:
	var card_supply: Dictionary = supply["cards"]
	var total: int = 0
	for record in Catalogue.cards():
		var card_id: String = str(record["id"])
		total += int(card_supply[card_id])
	if total <= 0:
		return ""

	var draw: int = rng.randi_range(1, total)
	for record in Catalogue.cards():
		var card_id: String = str(record["id"])
		var quantity: int = int(card_supply[card_id])
		if draw <= quantity:
			return card_id
		draw -= quantity
	return ""


static func _record_for(item_kind: String, identifier: Variant) -> Dictionary:
	var kind: String = item_kind.to_lower()
	if kind == "cards":
		kind = CARD_KIND
	elif kind == "tools":
		kind = TOOL_KIND
	if typeof(identifier) == TYPE_STRING:
		if kind == CARD_KIND:
			return Catalogue.card(str(identifier))
		if kind == TOOL_KIND:
			return Catalogue.tool(str(identifier))
		return {}
	if typeof(identifier) != TYPE_INT:
		return {}
	var source_id: int = int(identifier)
	if kind == CARD_KIND:
		var cards: Array = Catalogue.cards()
		return cards[source_id - 1] if source_id >= 1 and source_id <= cards.size() else {}
	if kind == TOOL_KIND:
		var tools: Array = Catalogue.tools()
		return tools[source_id - 1] if source_id >= 1 and source_id <= tools.size() else {}
	return {}


static func _valid_supply(supply: Dictionary) -> bool:
	var card_supply: Variant = supply.get("cards", null)
	var tool_supply: Variant = supply.get("tools", null)
	if not card_supply is Dictionary or not tool_supply is Dictionary:
		return false
	for record in Catalogue.cards():
		var card_id: String = str(record["id"])
		if not card_supply.has(card_id) or not _valid_nonnegative_int(card_supply[card_id]):
			return false
	for record in Catalogue.tools():
		var tool_id: String = str(record["id"])
		if not tool_supply.has(tool_id) or not _valid_nonnegative_int(tool_supply[tool_id]):
			return false
	return true


static func _valid_cards(cards: Array) -> bool:
	if cards.size() > CARD_CAPACITY:
		return false
	for identifier in cards:
		if typeof(identifier) != TYPE_STRING or _record_for(CARD_KIND, identifier).is_empty():
			return false
	return true


static func _valid_tools(tools: Dictionary) -> bool:
	for identifier in tools.keys():
		if typeof(identifier) != TYPE_STRING:
			return false
		var record: Dictionary = _record_for(TOOL_KIND, identifier)
		if record.is_empty() or not _valid_nonnegative_int(tools[identifier]):
			return false
		if int(tools[identifier]) > TOOL_CAPACITY_PER_TYPE:
			return false
	return true


static func _valid_quantity(quantity: Variant) -> bool:
	return typeof(quantity) == TYPE_INT and int(quantity) > 0 and int(quantity) <= TOOL_CAPACITY_PER_TYPE


static func _valid_quote_quantity(quantity: Variant) -> bool:
	return typeof(quantity) == TYPE_INT and int(quantity) > 0


static func _valid_nonnegative_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0


static func _first_cheapest_card_index(cards: Array) -> int:
	var best_index: int = -1
	var best_price: int = 2147483647
	for index in range(cards.size()):
		var record: Dictionary = _record_for(CARD_KIND, cards[index])
		if record.is_empty():
			return -1
		var price: int = int(record["price"])
		if price < best_price:
			best_price = price
			best_index = index
	return best_index


static func _commit_supply(target: Dictionary, staged: Dictionary) -> void:
	var target_cards: Dictionary = target["cards"]
	var staged_cards: Dictionary = staged["cards"]
	target_cards.clear()
	for key in staged_cards.keys():
		target_cards[key] = staged_cards[key]
	var target_tools: Dictionary = target["tools"]
	var staged_tools: Dictionary = staged["tools"]
	target_tools.clear()
	for key in staged_tools.keys():
		target_tools[key] = staged_tools[key]


static func _replace_array(target: Array, staged: Array) -> void:
	target.clear()
	target.append_array(staged)


static func _replace_dictionary(target: Dictionary, staged: Dictionary) -> void:
	target.clear()
	for key in staged.keys():
		target[key] = staged[key]


static func _set_player_array(player: Dictionary, key: String, value: Array) -> void:
	var current: Variant = player.get(key, null)
	if current is Array:
		_replace_array(current, value)
	else:
		player[key] = value


static func _set_player_dictionary(player: Dictionary, key: String, value: Dictionary) -> void:
	var current: Variant = player.get(key, null)
	if current is Dictionary:
		_replace_dictionary(current, value)
	else:
		player[key] = value.duplicate(true)


static func _success(extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": true, "error": ""}
	for key in extra.keys():
		result[key] = extra[key]
	return result


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
