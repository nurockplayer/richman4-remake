class_name RichmanTheftRules
extends RefCounted

## Pure inventory transfer rules for the original 搶奪 card.
##
## Every operation is staged on deep copies and committed only after all
## public inputs have been validated.  Rejected requests therefore leave the
## caller's save containers byte-stable.

const Inventory = preload("res://game/core/inventory_rules.gd")
const Catalogue = preload("res://game/content/original_inventory.gd")

const CARD_KIND := "card"
const TOOL_KIND := "tool"
const ROBBERY_CARD_ID := "搶奪"
const VEHICLE_TOOL_IDS: Array = ["機車", "汽車"]


## Return one legal choice for each distinct item held by each living target.
## Card duplicates are represented by `quantity`; tools use their sparse
## inventory quantity.  Catalogue and player order are deterministic.
static func choices(players: Array, actor_id: int) -> Array:
	if typeof(players) != TYPE_ARRAY or not _valid_player_id(players, actor_id):
		return []
	var actor_value: Variant = players[actor_id]
	if typeof(actor_value) != TYPE_DICTIONARY:
		return []
	var actor: Dictionary = actor_value
	var actor_cards_value: Variant = actor.get("cards", null)
	if not _valid_player(actor) or not _valid_cards(actor_cards_value):
		return []
	var actor_cards: Array = actor_cards_value
	if not actor_cards.has(ROBBERY_CARD_ID):
		return []

	var result: Array = []
	for target_id in range(players.size()):
		if target_id == actor_id:
			continue
		var target_value: Variant = players[target_id]
		if typeof(target_value) != TYPE_DICTIONARY:
			continue
		var target: Dictionary = target_value
		if not _valid_player(target) or not bool(target.get("alive", false)):
			continue
		var target_cards_value: Variant = target.get("cards", null)
		if target_cards_value is Array:
			var card_order: Array = []
			var card_counts: Dictionary = {}
			for card_value in target_cards_value:
				if typeof(card_value) != TYPE_STRING:
					continue
				var card_id: String = str(card_value)
				if _record_for(CARD_KIND, card_id).is_empty():
					continue
				if not card_counts.has(card_id):
					card_order.append(card_id)
					card_counts[card_id] = 0
				card_counts[card_id] = int(card_counts[card_id]) + 1
			for card_id in card_order:
				result.append(_choice(target_id, CARD_KIND, str(card_id), int(card_counts[card_id]), _card_capacity_full(actor)))
		var target_tools_value: Variant = target.get("tools", null)
		if target_tools_value is Dictionary:
			# Catalogue order is explicit and stable across Dictionary serialization.
			for record_value in Catalogue.tools():
				var record: Dictionary = record_value
				var tool_id: String = str(record.get("id", ""))
				var quantity: int = int(target_tools_value.get(tool_id, 0))
				if quantity <= 0:
					continue
				result.append(_choice(target_id, TOOL_KIND, tool_id, quantity, _tool_capacity_full(actor, tool_id)))
	return result


## Execute one unit transfer. A full card hand evicts its lowest-price card;
## a full tool type remains legal but receives no unit.
static func resolve(
	supply: Dictionary,
	players: Array,
	actor_id: int,
	target_id: Variant,
	item_kind: Variant,
	item_id: Variant,
	cancel: Variant = false,
) -> Dictionary:
	if typeof(players) != TYPE_ARRAY or not _valid_player_id(players, actor_id):
		return _failure("玩家目標無效。")
	if typeof(target_id) != TYPE_INT or not _valid_player_id(players, int(target_id)):
		return _failure("玩家目標無效。")
	var target_index: int = int(target_id)
	if target_index == actor_id:
		return _failure("搶奪卡不能指定自己。")
	if typeof(cancel) != TYPE_BOOL:
		return _failure("搶奪取消格式無效。")
	if bool(cancel):
		return _failure("已取消搶奪選擇。", {"cancelled": true})
	if typeof(item_kind) != TYPE_STRING:
		return _failure("物品類型無效。")
	var normalized_kind: String = str(item_kind).to_lower().strip_edges()
	if not [CARD_KIND, TOOL_KIND].has(normalized_kind):
		return _failure("物品類型無效。")
	if typeof(item_id) != TYPE_STRING or str(item_id).is_empty():
		return _failure("物品代號無效。")
	var identifier: String = str(item_id)
	if _record_for(normalized_kind, identifier).is_empty():
		return _failure("物品代號無效。")
	if not _valid_supply(supply):
		return _failure("共享供給格式無效。")

	var actor_value: Variant = players[actor_id]
	var target_value: Variant = players[target_index]
	if typeof(actor_value) != TYPE_DICTIONARY or typeof(target_value) != TYPE_DICTIONARY:
		return _failure("玩家資料格式無效。")
	var actor: Dictionary = actor_value
	var target: Dictionary = target_value
	if not _valid_player(actor) or not _valid_player(target):
		return _failure("玩家資料格式無效。")
	if not bool(actor.get("alive", false)) or not bool(target.get("alive", false)):
		return _failure("搶奪目標目前無法選取。")
	var actor_cards_value: Variant = actor.get("cards", null)
	var target_cards_value: Variant = target.get("cards", null)
	var actor_tools_value: Variant = actor.get("tools", null)
	var target_tools_value: Variant = target.get("tools", null)
	if not _valid_cards(actor_cards_value) or not _valid_cards(target_cards_value):
		return _failure("卡片背包格式無效。")
	if not _valid_tools(actor_tools_value) or not _valid_tools(target_tools_value):
		return _failure("道具背包格式無效。")
	var actor_cards: Array = actor_cards_value
	var target_cards: Array = target_cards_value
	var actor_tools: Dictionary = actor_tools_value
	var target_tools: Dictionary = target_tools_value
	if not actor_cards.has(ROBBERY_CARD_ID):
		return _failure("沒有搶奪卡。")

	var capacity_full: bool = false
	var target_quantity: int = 0
	if normalized_kind == CARD_KIND:
		target_quantity = target_cards.count(identifier)
		capacity_full = actor_cards.size() >= Inventory.CARD_CAPACITY
	else:
		target_quantity = int(target_tools.get(identifier, 0))
		capacity_full = int(actor_tools.get(identifier, 0)) >= Inventory.TOOL_CAPACITY_PER_TYPE
	if target_quantity <= 0:
		return _failure("目標沒有這項物品。")

	var staged_supply: Dictionary = supply.duplicate(true)
	var staged_actor_cards: Array = actor_cards.duplicate(true)
	var staged_target_cards: Array = target_cards.duplicate(true)
	var staged_actor_tools: Dictionary = actor_tools.duplicate(true)
	var staged_target_tools: Dictionary = target_tools.duplicate(true)
	var received: bool = false
	var evicted_card_id := ""
	if normalized_kind == CARD_KIND:
		var consume_target_card: Dictionary = Inventory.consume_card(staged_supply, staged_target_cards, identifier)
		if not bool(consume_target_card.get("ok", false)):
			return _failure(str(consume_target_card.get("error", "目標卡片無法移除。")))
		var receive_card: Dictionary = Inventory.grant_card(staged_supply, staged_actor_cards, identifier)
		if not bool(receive_card.get("ok", false)):
			return _failure(str(receive_card.get("error", "卡片無法加入背包。")))
		received = true
		evicted_card_id = str(receive_card.get("evicted_card_id", ""))
	else:
		var consume_target_tool: Dictionary = Inventory.consume_tool(staged_supply, staged_target_tools, identifier, 1)
		if not bool(consume_target_tool.get("ok", false)):
			return _failure(str(consume_target_tool.get("error", "目標道具無法移除。")))
		if not capacity_full:
			var receive_tool: Dictionary = Inventory.grant_tool(staged_supply, staged_actor_tools, identifier, 1)
			if not bool(receive_tool.get("ok", false)):
				return _failure(str(receive_tool.get("error", "道具無法加入背包。")))
			received = true

	# Card eviction can remove the action card itself. Consume the first
	# remaining occurrence only when it survived the receive step.
	var robbery_consumed: bool = false
	if staged_actor_cards.has(ROBBERY_CARD_ID):
		var consume_action_card: Dictionary = Inventory.consume_card(staged_supply, staged_actor_cards, ROBBERY_CARD_ID)
		if bool(consume_action_card.get("ok", false)):
			robbery_consumed = true

	_commit_supply(supply, staged_supply)
	_replace_array(actor_cards, staged_actor_cards)
	_replace_array(target_cards, staged_target_cards)
	_replace_dictionary(actor_tools, staged_actor_tools)
	_replace_dictionary(target_tools, staged_target_tools)
	return _success({
		"target_id": target_index,
		"item_kind": normalized_kind,
		"item_id": identifier,
		"quantity": 1,
		"received": received,
		"capacity_full": capacity_full,
		"evicted_card_id": evicted_card_id,
		"robbery_consumed": robbery_consumed,
	})


static func legal_choices(players: Array, actor_id: int) -> Array:
	return choices(players, actor_id)


static func _choice(target_id: int, item_kind: String, item_id: String, quantity: int, capacity_full: bool) -> Dictionary:
	return {"target_id": target_id, "item_kind": item_kind, "item_id": item_id, "quantity": quantity, "capacity_full": capacity_full}


static func _record_for(item_kind: String, identifier: String) -> Dictionary:
	if item_kind == CARD_KIND:
		return Catalogue.card(identifier)
	if item_kind == TOOL_KIND:
		return Catalogue.tool(identifier)
	return {}


static func _valid_supply(supply: Dictionary) -> bool:
	if typeof(supply) != TYPE_DICTIONARY:
		return false
	var cards_value: Variant = supply.get("cards", null)
	var tools_value: Variant = supply.get("tools", null)
	if not cards_value is Dictionary or not tools_value is Dictionary:
		return false
	var card_supply: Dictionary = cards_value
	var tool_supply: Dictionary = tools_value
	for record_value in Catalogue.cards():
		var record: Dictionary = record_value
		var item_id: String = str(record.get("id", ""))
		if not card_supply.has(item_id) or not _valid_nonnegative_int(card_supply[item_id]):
			return false
	for record_value in Catalogue.tools():
		var record: Dictionary = record_value
		var item_id: String = str(record.get("id", ""))
		if not tool_supply.has(item_id) or not _valid_nonnegative_int(tool_supply[item_id]):
			return false
	return true


static func _valid_player_id(players: Array, player_id: Variant) -> bool:
	return typeof(player_id) == TYPE_INT and int(player_id) >= 0 and int(player_id) < players.size()


static func _valid_player(player: Dictionary) -> bool:
	if typeof(player) != TYPE_DICTIONARY:
		return false
	var player_id: Variant = player.get("id", null)
	return typeof(player_id) == TYPE_INT and int(player_id) >= 0


static func _valid_cards(cards: Variant) -> bool:
	if not cards is Array or cards.size() > Inventory.CARD_CAPACITY:
		return false
	for value in cards:
		if typeof(value) != TYPE_STRING or _record_for(CARD_KIND, str(value)).is_empty():
			return false
	return true


static func _valid_tools(tools: Variant) -> bool:
	if not tools is Dictionary:
		return false
	for key in tools.keys():
		if typeof(key) != TYPE_STRING:
			return false
		var record: Dictionary = _record_for(TOOL_KIND, str(key))
		if record.is_empty() or not _valid_nonnegative_int(tools[key]):
			return false
		var capacity: int = Inventory.VEHICLE_STORAGE_CAPACITY if VEHICLE_TOOL_IDS.has(str(key)) else Inventory.TOOL_CAPACITY_PER_TYPE
		if int(tools[key]) > capacity:
			return false
	return true


static func _card_capacity_full(player: Dictionary) -> bool:
	var cards: Variant = player.get("cards", null)
	return cards is Array and cards.size() >= Inventory.CARD_CAPACITY


static func _tool_capacity_full(player: Dictionary, tool_id: String) -> bool:
	var tools: Variant = player.get("tools", null)
	return tools is Dictionary and int(tools.get(tool_id, 0)) >= Inventory.TOOL_CAPACITY_PER_TYPE


static func _valid_nonnegative_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0


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


static func _success(extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": true, "error": ""}
	for key in extra.keys():
		result[key] = extra[key]
	return result


static func _failure(message: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": false, "error": message}
	for key in extra.keys():
		result[key] = extra[key]
	return result
