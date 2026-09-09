class_name RichmanAllianceRules
extends RefCounted

## Runtime rules for the original 同盟 card.
##
## Alliance state is deliberately kept as an optional player field.  The
## game-state object remains the owner of movement, payment, and serialization
## primitives; this module supplies the card boundary, pair lifecycle, and
## ordinary-property contribution plan shared by those entry points.

const CARD_ID := "同盟"
const ALLIANCE_TURNS := 7
const RELEASE_MARKER := 128
const RECORD_KEYS := ["partner_id", "turns"]


static func is_alliance_card(card_id: String) -> bool:
	return card_id == CARD_ID


static func target_players(game: Object, caster_id: int) -> Array:
	var targets: Array = []
	if not game._is_inventory() or not game._valid_player(caster_id, true):
		return targets
	for value in game._players():
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = value
		var candidate_id: Variant = candidate.get("id", null)
		if typeof(candidate_id) != TYPE_INT or int(candidate_id) == caster_id:
			continue
		if not bool(candidate.get("alive", false)) or game._status_active(candidate):
			continue
		targets.append(int(candidate_id))
	targets.sort()
	return targets


static func use_card(game: Object, player_id: int, target_id: Variant, cancel: Variant) -> Dictionary:
	if not game._is_inventory():
		return game._error("同盟卡效果尚未還原")
	if typeof(cancel) != TYPE_BOOL:
		return game._error("同盟卡取消參數無效")
	if typeof(target_id) != TYPE_INT:
		return game._error("同盟卡目標格式無效")
	var caster: Dictionary = game._player(player_id)
	if caster.is_empty() or not bool(caster.get("alive", false)):
		return game._error("目前玩家無法使用同盟卡")
	if not _has_card(caster, CARD_ID):
		return game._error("沒有這張卡片")
	var target_id_int: int = int(target_id)
	if not target_players(game, player_id).has(target_id_int):
		return game._error("同盟卡目標無效")
	if cancel:
		return game._result(true, "已取消同盟卡")

	# Inventory consumption is the only fallible mutation in the confirmed
	# branch.  Validate every target and card condition first so a malformed
	# request cannot partially clear an existing pair.
	var consumed: Dictionary = _consume_card(game, player_id)
	if not bool(consumed.get("ok", false)):
		return game._error(str(consumed.get("error", "同盟卡無法使用")))
	_clear_for_player(game, player_id)
	_clear_for_player(game, target_id_int)
	game._player(player_id)["alliance"] = {"partner_id": target_id_int, "turns": ALLIANCE_TURNS}
	game._player(target_id_int)["alliance"] = {"partner_id": player_id, "turns": ALLIANCE_TURNS}
	game._record_event("card_used", {"player_id": player_id, "card_id": CARD_ID, "target_id": target_id_int, "effect": "alliance"})
	game._record_event("alliance_formed", {"player_id": player_id, "partner_id": target_id_int, "turns": ALLIANCE_TURNS})
	game._set_action_options(player_id)
	return game._result(true, "已建立同盟", {"target_id": target_id_int, "turns": ALLIANCE_TURNS})


static func are_allied(game: Object, first_id: int, second_id: int) -> bool:
	if first_id < 0 or second_id < 0 or first_id == second_id:
		return false
	if not game._valid_player(first_id, true) or not game._valid_player(second_id, true):
		return false
	var first: Dictionary = _record(game, first_id)
	var second: Dictionary = _record(game, second_id)
	return not first.is_empty() and not second.is_empty() and int(first.get("partner_id", -1)) == second_id and int(second.get("partner_id", -1)) == first_id


static func partner_id(game: Object, player_id: int) -> int:
	if not game._valid_player(player_id, true):
		return -1
	var record: Dictionary = _record(game, player_id)
	if record.is_empty():
		return -1
	var partner: int = int(record.get("partner_id", -1))
	return partner if are_allied(game, player_id, partner) else -1


static func clear_for_player(game: Object, player_id: int) -> void:
	_clear_for_player(game, player_id)


static func admit_player(game: Object, player_id: int) -> void:
	var player: Dictionary = game._player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return
	var record: Dictionary = _record(game, player_id)
	if record.is_empty():
		return
	var partner_id_int: int = int(record.get("partner_id", -1))
	if not are_allied(game, player_id, partner_id_int):
		_clear_for_player(game, player_id)
		return
	var turns: int = int(record.get("turns", 0))
	if turns == RELEASE_MARKER:
		_clear_for_player(game, player_id)
		game._record_event("alliance_expired", {"player_id": player_id, "partner_id": partner_id_int})
		return
	if turns == 1:
		record["turns"] = RELEASE_MARKER
		game._record_event("alliance_timer_marker", {"player_id": player_id, "partner_id": partner_id_int, "turns": RELEASE_MARKER})
		return
	if turns >= 2 and turns <= ALLIANCE_TURNS:
		record["turns"] = turns - 1
		game._record_event("alliance_timer_tick", {"player_id": player_id, "partner_id": partner_id_int, "turns": turns - 1})


static func rent_contributions(game: Object, tile: Dictionary, owner_id: int, owner_amount: int = -1) -> Array:
	var contributions: Array = []
	if tile.is_empty() or str(tile.get("kind", "")) != "property" or owner_id < 0:
		return contributions
	var primary_amount: int = owner_amount
	if primary_amount < 0 and game.has_method("_calculate_rent"):
		primary_amount = int(game._calculate_rent(tile, owner_id))
	if primary_amount > 0:
		contributions.append({"creditor_id": owner_id, "amount": primary_amount})
	var partner: int = partner_id(game, owner_id)
	if partner < 0 or not game.has_method("_calculate_rent") or not _qualifies_for_rent(game, tile, partner):
		return contributions
	var partner_amount: int = int(game._calculate_rent(tile, partner))
	if partner_amount > 0:
		contributions.append({"creditor_id": partner, "amount": partner_amount})
	return contributions


static func _qualifies_for_rent(game: Object, tile: Dictionary, owner_id: int) -> bool:
	if owner_id < 0 or tile.is_empty() or str(tile.get("kind", "")) != "property":
		return false
	var board: Variant = game.state.get("board", [])
	if typeof(board) != TYPE_ARRAY:
		return false
	if game._is_remodel():
		if bool(tile.get("is_chain_store", false)):
			for candidate_value in board:
				if typeof(candidate_value) != TYPE_DICTIONARY:
					continue
				var candidate: Dictionary = candidate_value
				if candidate.get("kind", "") == "property" and int(candidate.get("owner", -1)) == owner_id and bool(candidate.get("is_chain_store", false)) and int(candidate.get("building_level", 0)) > 0:
					return true
			return false
		var target_name: String = str(tile.get("name", ""))
		var target_group: String = str(tile.get("group", ""))
		for candidate_value in board:
			if typeof(candidate_value) != TYPE_DICTIONARY:
				continue
			var candidate: Dictionary = candidate_value
			if candidate.get("kind", "") != "property" or int(candidate.get("owner", -1)) != owner_id or bool(candidate.get("is_chain_store", false)):
				continue
			var candidate_name: String = str(candidate.get("name", ""))
			var same_road: bool = candidate_name == target_name and not target_name.is_empty()
			if target_name.is_empty():
				same_road = candidate_name.is_empty() and str(candidate.get("group", "")) == target_group
			if same_road:
				return true
		return false
	var target_group: String = str(tile.get("group", ""))
	for candidate_value in board:
		if typeof(candidate_value) == TYPE_DICTIONARY:
			var candidate: Dictionary = candidate_value
			if candidate.get("kind", "") == "property" and int(candidate.get("owner", -1)) == owner_id and str(candidate.get("group", "")) == target_group:
				return true
	return false


static func recipient_shares(game: Object, debtor_id: int, owner_id: int, amount: int, node_id: int) -> Array:
	if amount < 0:
		return []
	var tile: Dictionary = game._tile_at(node_id) if game.has_method("_tile_at") else {}
	var contributions: Array = rent_contributions(game, tile, owner_id)
	if contributions.size() < 2:
		return [{"creditor_id": owner_id, "amount": amount}]
	var total_nominal: int = 0
	for contribution_value in contributions:
		if typeof(contribution_value) == TYPE_DICTIONARY:
			total_nominal += max(0, int(contribution_value.get("amount", 0)))
	if total_nominal <= 0:
		return [{"creditor_id": owner_id, "amount": amount}]
	var result: Array = []
	var non_owner_total: int = 0
	for contribution_value in contributions:
		if typeof(contribution_value) != TYPE_DICTIONARY:
			continue
		var creditor_id: int = int(contribution_value.get("creditor_id", -1))
		var nominal: int = max(0, int(contribution_value.get("amount", 0)))
		if creditor_id == owner_id:
			continue
		var share: int = int(floor(float(amount) * float(nominal) / float(total_nominal)))
		share = max(0, share)
		result.append({"creditor_id": creditor_id, "amount": share})
		non_owner_total += share
	# The source owner receives the remainder, which keeps every actual payment
	# unit accounted for after proportional flooring.
	result.append({"creditor_id": owner_id, "amount": max(0, amount - non_owner_total)})
	return result


static func validate_save(data: Dictionary, player_count: int, inventory_save: bool) -> Array:
	var errors: Array = []
	var players: Variant = data.get("players", null)
	if typeof(players) != TYPE_ARRAY:
		return errors
	for index in range(players.size()):
		if typeof(players[index]) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = players[index]
		if not player.has("alliance"):
			continue
		if not inventory_save:
			errors.append("player %d alliance requires inventory save" % index)
		var value: Variant = player.get("alliance", null)
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("player %d alliance record invalid" % index)
			continue
		var record: Dictionary = value
		if record.size() != RECORD_KEYS.size():
			errors.append("player %d alliance keys are not canonical" % index)
		for key in record.keys():
			if not RECORD_KEYS.has(key):
				errors.append("player %d alliance has unexpected field" % index)
		for key in RECORD_KEYS:
			if not record.has(key):
				errors.append("player %d alliance missing %s" % [index, key])
		var partner_value: Variant = record.get("partner_id", null)
		var turns_value: Variant = record.get("turns", null)
		if not _valid_integer(partner_value) or int(partner_value) < 0 or int(partner_value) >= player_count or int(partner_value) == index:
			errors.append("player %d alliance partner invalid" % index)
		if not _valid_integer(turns_value) or not (int(turns_value) >= 1 and int(turns_value) <= ALLIANCE_TURNS or int(turns_value) == RELEASE_MARKER):
			errors.append("player %d alliance turns invalid" % index)
		if not bool(player.get("alive", false)):
			errors.append("player %d dead player cannot retain alliance" % index)
		if _valid_integer(partner_value) and int(partner_value) >= 0 and int(partner_value) < players.size() and typeof(players[int(partner_value)]) == TYPE_DICTIONARY:
			var partner: Dictionary = players[int(partner_value)]
			if not bool(partner.get("alive", false)):
				errors.append("player %d alliance partner unavailable" % index)
			var reciprocal_value: Variant = partner.get("alliance", null)
			if typeof(reciprocal_value) != TYPE_DICTIONARY or reciprocal_value.size() != RECORD_KEYS.size() or not _valid_integer(reciprocal_value.get("partner_id", null)) or int(reciprocal_value.get("partner_id", -1)) != index:
				errors.append("player %d alliance is not reciprocal" % index)
	return errors


static func _record(game: Object, player_id: int) -> Dictionary:
	var player: Dictionary = game._player(player_id)
	if player.is_empty():
		return {}
	var value: Variant = player.get("alliance", null)
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var record: Dictionary = value
	if record.size() != RECORD_KEYS.size():
		return {}
	for key in RECORD_KEYS:
		if not record.has(key) or not _valid_integer(record.get(key)):
			return {}
	var partner: int = int(record.get("partner_id", -1))
	var turns: int = int(record.get("turns", 0))
	if partner < 0 or partner == player_id or not (turns >= 1 and turns <= ALLIANCE_TURNS or turns == RELEASE_MARKER):
		return {}
	return record


static func _clear_for_player(game: Object, player_id: int) -> void:
	var player: Dictionary = game._player(player_id)
	if player.is_empty():
		return
	player.erase("alliance")
	for value in game._players():
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = value
		var record_value: Variant = candidate.get("alliance", null)
		if typeof(record_value) == TYPE_DICTIONARY and _valid_integer(record_value.get("partner_id", null)) and int(record_value.get("partner_id")) == player_id:
			candidate.erase("alliance")


static func _has_card(player: Dictionary, card_id: String) -> bool:
	var cards: Variant = player.get("cards", [])
	return typeof(cards) == TYPE_ARRAY and cards.has(card_id)


static func _consume_card(game: Object, player_id: int) -> Dictionary:
	var player: Dictionary = game._player(player_id)
	if player.is_empty() or not _has_card(player, CARD_ID):
		return {"ok": false, "error": "玩家沒有這張卡片"}
	var inventory = preload("res://game/core/inventory_rules.gd")
	return inventory.consume_card(game.state.get("inventory_supply", {}), player["cards"], CARD_ID)


static func _valid_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		return is_finite(value) and floor(value) == value
	return false
