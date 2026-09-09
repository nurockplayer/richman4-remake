class_name Richman4NewsEvents
extends RefCounted

const OriginalStockMarket = preload("res://game/core/original_stock_market.gd")

## Bounded common-news domain.
##
## The source jump table contains 36 common-news handlers.  This module owns
## the stable catalogue, deck shape, bounded selection and effect plans.  The
## resolver receives GameState so each plan can call its existing canonical
## mutation helpers without creating a second property or money model.

const COUNT := 36
const UNSUPPORTED_IDS := [4, 7, 20, 29]

const _NAMES := [
	"監獄釋放", "監獄加刑", "醫院釋放", "醫院加護",
	"範圍災害", "土地查封", "房價上漲", "土地拍賣",
	"不動產獎勵", "不動產補助", "股票獎勵", "所得稅",
	"房產稅", "股票稅", "房價下跌", "住宅損壞",
	"行人停留", "交通停留", "建物降級", "土地查封",
	"多屋災害", "設施損壞", "銀行拒貸", "存款利息",
	"股市下跌", "股市上漲", "股市休市", "股票停牌",
	"解除停牌", "特殊事件", "企業虧損", "企業獲利",
	"企業大跌", "企業虧損", "企業小跌", "企業翻倍",
]

static func catalog() -> Array:
	var result: Array = []
	for event_id in range(COUNT):
		result.append({
			"id": event_id,
			"name": str(_NAMES[event_id]),
			"adapter_status": "unsupported" if UNSUPPORTED_IDS.has(event_id) else "supported",
		})
	return result


static func is_supported(event_id: Variant) -> bool:
	return _valid_int(event_id, 0, COUNT - 1) and not UNSUPPORTED_IDS.has(int(event_id))


static func name_for(event_id: Variant) -> String:
	if not _valid_int(event_id, 0, COUNT - 1):
		return "未知新聞"
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
		return {"ok": false, "errors": ["news must be a dictionary"]}
	var news: Dictionary = value
	if news.size() != 4:
		errors.append("news keys are not canonical")
	for key in ["order", "cursor", "draw_count", "last"]:
		if not news.has(key):
			errors.append("news missing %s" % key)
	var order: Variant = news.get("order", null)
	if typeof(order) != TYPE_ARRAY or order.size() != COUNT:
		errors.append("news order must contain 36 candidates")
	else:
		var seen: Dictionary = {}
		for event_id in order:
			if not _valid_int(event_id, 0, COUNT - 1) or seen.has(int(event_id)):
				errors.append("news order is not a permutation")
			else:
				seen[int(event_id)] = true
		if seen.size() != COUNT:
			errors.append("news order is not a permutation")
	var cursor: Variant = news.get("cursor", null)
	if not _valid_int(cursor, 0, COUNT - 1):
		errors.append("news cursor is invalid")
	var draw_count: Variant = news.get("draw_count", null)
	if not _valid_int(draw_count, 0, 1000000000):
		errors.append("news draw count is invalid")
	var last: Variant = news.get("last", null)
	if typeof(last) != TYPE_DICTIONARY:
		errors.append("news last result is invalid")
	elif not last.is_empty():
		if last.size() != 5:
			errors.append("news last keys are not canonical")
		for key in ["id", "player_id", "targets", "changes", "summary"]:
			if not last.has(key):
				errors.append("news last missing %s" % key)
		if not _valid_int(last.get("id", null), 0, COUNT - 1) or UNSUPPORTED_IDS.has(int(last.get("id", -1))):
			errors.append("news last id is unsupported")
		if not _valid_int(last.get("player_id", null), 0, 3):
			errors.append("news last player is invalid")
		if typeof(last.get("targets", null)) != TYPE_ARRAY:
			errors.append("news last targets are invalid")
		if typeof(last.get("changes", null)) != TYPE_ARRAY:
			errors.append("news last changes are invalid")
		else:
			for change in last.get("changes", []):
				if typeof(change) != TYPE_DICTIONARY:
					errors.append("news last change is invalid")
		if typeof(last.get("summary", null)) != TYPE_STRING or str(last.get("summary", "")).is_empty():
			errors.append("news last summary is invalid")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": []}


static func has_eligible_target(game: Object, event_id: int) -> bool:
	if game == null or not is_supported(event_id):
		return false
	match event_id:
		0, 1, 2, 3:
			return not _status_targets(game, event_id).is_empty()
		5:
			return not _asset_targets(game, true, false).is_empty()
		6, 14:
			return not _asset_targets(game, false, false).is_empty()
		18, 21:
			return not _asset_targets(game, true, false).is_empty()
		19:
			return not _asset_targets(game, false, false).is_empty()
		15:
			return not _asset_targets(game, true, true).is_empty()
		8, 9, 12:
			for player_id in _alive_player_ids(game):
				if _asset_count(game, player_id) > 0:
					return true
			return false
		10, 13:
			for player_id in _alive_player_ids(game):
				if _stock_count(game, player_id) > 0:
					return true
			return false
		11, 22:
			return not _alive_player_ids(game).is_empty()
		16:
			for player_id in _alive_player_ids(game):
				if str(game.state.players[player_id].get("vehicle", "walking")) == "walking":
					return true
			return false
		17:
			for player_id in _alive_player_ids(game):
				if str(game.state.players[player_id].get("vehicle", "walking")) != "walking":
					return true
			return false
		23:
			for player_id in _alive_player_ids(game):
				var player: Dictionary = game.state.players[player_id]
				if int(player.get("loan", 0)) == 0 and int(player.get("deposit", 0)) > 0:
					return true
			return false
		24, 25, 26, 27:
			return bool(game._is_companies()) and _stock_symbols(game).size() == 12
		28:
			if not bool(game._is_companies()):
				return false
			for symbol in _stock_symbols(game):
				if int(game.state.market.rows[symbol].get("suspension", 0)) > 0:
					return true
			return false
		30, 31, 32, 33, 34:
			return bool(game._is_companies()) and not game.state.get("companies", []).is_empty()
		35:
			if not bool(game._is_companies()):
				return false
			for company in game.state.get("companies", []):
				if typeof(company) == TYPE_DICTIONARY and int(company.get("monthly_profit", 0)) > 10000:
					return true
			return false
	return false


static func apply_landing(game: Object, player_id: int) -> void:
	var state: Dictionary = game.state
	var news_value: Variant = state.get("news", null)
	var news: Dictionary
	if news_value == null:
		news = new_state(game._rng)
		state["news"] = news
	else:
		if typeof(news_value) != TYPE_DICTIONARY:
			game._record_event("news_skipped", {"player_id": player_id, "reason": "invalid_state"})
			return
		var news_validation: Dictionary = validate_state(news_value)
		if not bool(news_validation.get("ok", false)):
			game._record_event("news_skipped", {"player_id": player_id, "reason": "invalid_state"})
			return
		news = news_value
	var order: Array = news.get("order", [])
	var cursor_before: int = int(news.get("cursor", 0))
	var cursor: int = cursor_before
	var selected_id := -1
	var selected_cursor_before := cursor_before
	for attempt in range(COUNT):
		var candidate_cursor: int = cursor
		var candidate_id: int = int(order[candidate_cursor])
		cursor = (candidate_cursor + 1) % COUNT
		var preview_payload: Dictionary = {
			"player_id": player_id,
			"news_id": candidate_id,
			"name": name_for(candidate_id),
			"attempt": attempt + 1,
			"cursor_before": candidate_cursor,
			"cursor_after": cursor,
		}
		game._record_event("news_preview", preview_payload)
		var skip_reason := ""
		if not is_supported(candidate_id):
			skip_reason = "unsupported"
		elif not has_eligible_target(game, candidate_id):
			skip_reason = "no_compatible_target"
		if not skip_reason.is_empty():
			preview_payload["reason"] = skip_reason
			game._record_event("news_skipped", preview_payload)
			continue
		selected_id = candidate_id
		selected_cursor_before = candidate_cursor
		break
	news["cursor"] = cursor
	var old_draw_count: int = int(news.get("draw_count", 0))
	news["draw_count"] = mini(1000000000, old_draw_count + 1)
	state["news"] = news
	if selected_id < 0:
		game._record_event("news_skipped", {"player_id": player_id, "reason": "no_eligible", "cursor_before": cursor_before, "cursor_after": cursor})
		return
	var result: Dictionary = resolve(game, player_id, selected_id)
	if not bool(result.get("ok", false)):
		game._record_event("news_skipped", {"player_id": player_id, "news_id": selected_id, "name": name_for(selected_id), "reason": str(result.get("reason", "apply_failed")), "cursor_before": selected_cursor_before, "cursor_after": cursor})
		return
	var last: Dictionary = {
		"id": selected_id,
		"player_id": player_id,
		"targets": result.get("targets", []).duplicate(true),
		"changes": result.get("changes", []).duplicate(true),
		"summary": str(result.get("summary", "新聞效果已套用")),
	}
	news["last"] = last
	state["news"] = news
	game._record_event("news_applied", {"player_id": player_id, "news_id": selected_id, "name": name_for(selected_id), "targets": last["targets"], "changes": last["changes"], "summary": last["summary"], "draw_count": int(news.get("draw_count", 0)), "cursor_before": selected_cursor_before, "cursor_after": cursor})


static func resolve(game: Object, player_id: int, event_id: int) -> Dictionary:
	## Apply one already-selected supported event through GameState's existing
	## helpers.  The result intentionally contains only presentation-neutral
	## target/change data; GameState stores the fixed five-key save result.
	if game == null or not is_supported(event_id):
		return {"ok": false, "reason": "unsupported"}
	var targets: Array = []
	var changes: Array = []
	var summary := ""
	match event_id:
		0, 1, 2, 3:
			var status_kind := "prison" if event_id in [0, 1] else "hospital"
			var status_key := "prison_days" if status_kind == "prison" else "hospital_days"
			for target_id in _status_targets(game, event_id):
				var target_player: Dictionary = game.state.players[target_id]
				var before: int = int(target_player.get(status_key, 0))
				var after: int = 128 if event_id in [0, 2] else (before + 3) & 127
				target_player[status_key] = after
				targets.append(target_id)
				changes.append({"player_id": target_id, "field": status_key, "from": before, "to": after})
			var place := "監獄" if status_kind == "prison" else "醫院"
			var verb := "已解除" if event_id in [0, 2] else "增加三天"
			summary = "%s的%s狀態%s" % [_player_list(game, targets), place, verb]
		5, 19:
			var clear_targets: Array = _asset_targets(game, event_id == 5, false)
			var target_id: int = _pick_int(game, clear_targets)
			if target_id < 0:
				return {"ok": false, "reason": "no_compatible_target"}
			_clear_asset(game, target_id)
			targets = [target_id]
			changes.append({"tile_id": target_id, "effect": "clear_asset"})
			var clear_tile: Dictionary = game.state.board[target_id]
			summary = "土地「%s」已清除所有權與建物" % str(clear_tile.get("name", "目標地產"))
		15, 18, 21:
			var damage_targets: Array = _asset_targets(game, event_id == 15, event_id == 15)
			var damage_target_id: int = _pick_int(game, damage_targets)
			if damage_target_id < 0:
				return {"ok": false, "reason": "no_compatible_target"}
			var damage_group: Array = _damage_target_group(game, damage_target_id, event_id == 15)
			if event_id == 21 and game.state.board[damage_target_id].get("kind", "") == "property":
				damage_group = [damage_target_id] if int(game.state.board[damage_target_id].get("building_level", 0)) > 0 else []
			if damage_group.is_empty():
				return {"ok": false, "reason": "no_compatible_target"}
			var damage_changes: Array = _damage_asset_group(game, damage_group)
			targets = [damage_target_id]
			changes.append_array(damage_changes)
			var damage_tile: Dictionary = game.state.board[damage_target_id]
			var damage_label := "住宅損壞" if event_id == 15 else "建物降級" if event_id == 18 else "設施損壞"
			summary = "%s「%s」%s" % ["設施" if damage_tile.get("kind", "") == "facility" else "住宅", str(damage_tile.get("name", "目標地產")), damage_label]
		6, 14:
			var price_targets: Array = _asset_targets(game, false, false)
			var price_target_id: int = _pick_int(game, price_targets)
			if price_target_id < 0:
				return {"ok": false, "reason": "no_compatible_target"}
			var price_up: bool = event_id == 6
			var price_changes: Array = _change_asset_price(game, price_target_id, price_up)
			targets = [price_target_id]
			changes.append_array(price_changes)
			var price_tile: Dictionary = game.state.board[price_target_id]
			var price_label := "上漲" if price_up else "下跌"
			summary = "%s「%s」的房價%s" % ["設施" if price_tile.get("kind", "") == "facility" else "土地", str(price_tile.get("name", "目標地產")), price_label]
		8, 9:
			var winner: int = _select_property_holder(game, event_id == 8)
			if winner < 0:
				return {"ok": false, "reason": "no_compatible_target"}
			var property_amount: int = int(game.state.get("price_index", 1)) * (10000 if event_id == 8 else 5000)
			_news_credit(game, winner, property_amount)
			targets = [winner]
			changes.append({"player_id": winner, "field": "cash", "amount": property_amount})
			summary = "%s獲得現金%d元" % [_player_name(game, winner), property_amount]
		10:
			var stock_winner: int = _select_stock_holder(game)
			if stock_winner < 0:
				return {"ok": false, "reason": "no_compatible_target"}
			var stock_amount: int = int(game.state.get("price_index", 1)) * 10000
			_news_credit(game, stock_winner, stock_amount)
			targets = [stock_winner]
			changes.append({"player_id": stock_winner, "field": "cash", "amount": stock_amount})
			summary = "%s獲得現金%d元" % [_player_name(game, stock_winner), stock_amount]
		11, 12, 13:
			var charged_ids: Array = []
			var tax_plan: Array = []
			for target_player_id in _alive_player_ids(game):
				var taxable: int = 0
				if event_id == 11:
					taxable = int(floor(float(game.state.players[target_player_id].get("cash", 0)) * 0.05))
				elif event_id == 12:
					taxable = int(floor(float(_asset_value(game, target_player_id)) * 0.05)) * int(game.state.get("price_index", 1))
				else:
					taxable = int(floor(_stock_value(game, target_player_id) * 0.05)) * int(game.state.get("price_index", 1))
				tax_plan.append({"player_id": target_player_id, "amount": taxable})
			for charge in tax_plan:
				if game.state.get("phase", "") == "game_over":
					break
				var target_player_id: int = int(charge.player_id)
				var taxable: int = int(charge.amount)
				if taxable > 0:
					game._charge_amount(target_player_id, taxable, -1, "news_tax")
					changes.append({"player_id": target_player_id, "field": "cash", "amount": -taxable})
					charged_ids.append(target_player_id)
				targets.append(target_player_id)
			var tax_name := "所得稅" if event_id == 11 else "房產稅" if event_id == 12 else "股票稅"
			summary = "%s完成%s結算" % [_player_list(game, charged_ids), tax_name]
		16, 17:
			var wanted_walking: bool = event_id == 16
			for target_id in _alive_player_ids(game):
				var target_player: Dictionary = game.state.players[target_id]
				var vehicle: String = str(target_player.get("vehicle", "walking"))
				if (vehicle == "walking") != wanted_walking:
					continue
				var before_stay: int = int(target_player.get("stay_next", 0))
				target_player["stay_next"] = 1
				targets.append(target_id)
				changes.append({"player_id": target_id, "field": "stay_next", "from": before_stay, "to": 1})
			summary = "%s下回合停留" % _player_list(game, targets)
		22:
			for target_id in _alive_player_ids(game):
				var target_player: Dictionary = game.state.players[target_id]
				var before_loan_block: int = int(target_player.get("loan_block_days", 0))
				target_player["loan_block_days"] = 15
				targets.append(target_id)
				changes.append({"player_id": target_id, "field": "loan_block_days", "from": before_loan_block, "to": 15})
			summary = "%s暫停申請貸款15天" % _player_list(game, targets)
		23:
			for target_id in _alive_player_ids(game):
				var target_player: Dictionary = game.state.players[target_id]
				var deposit: int = int(target_player.get("deposit", 0))
				if int(target_player.get("loan", 0)) != 0 or deposit <= 0:
					continue
				var interest: int = int(floor(float(deposit) * 0.1))
				var bank: Dictionary = game.state.get("bank", {})
				if interest <= 0 or deposit > 1000000000000 - interest or int(bank.get("deposits", 0)) > 1000000000000 - interest:
					continue
				target_player["deposit"] = deposit + interest
				bank["deposits"] = int(bank.get("deposits", 0)) + interest
				game.state["bank"] = bank
				game._bank_subtract_cash(interest)
				targets.append(target_id)
				changes.append({"player_id": target_id, "field": "deposit", "amount": interest})
			summary = "%s獲得存款利息" % _player_list(game, targets)
		24, 25:
			var rising: bool = event_id == 25
			var rate: float = 10.0 if rising else -10.0
			for symbol in _stock_symbols(game):
				var row: Dictionary = game.state.market.rows[symbol]
				row["event"] = 0x10 if rising else 1
				OriginalStockMarket.refresh_event_price(game.state.market, symbol, rate)
				targets.append(symbol)
				changes.append({"stock": symbol, "field": "event", "to": int(row.get("event", 0)), "price": float(row.get("price", 0.0))})
			summary = "12檔股票價格%s" % ("上漲" if rising else "下跌")
		26:
			var before_closed_days: int = int(game.state.market.get("closed_days", 0))
			game.state.market["closed_days"] = 10
			targets = ["stock_market"]
			changes.append({"field": "closed_days", "from": before_closed_days, "to": 10})
			summary = "證券市場休市10天"
		27:
			var halt_symbols: Array = _stock_symbols(game)
			var halted_symbol: String = str(halt_symbols[game._rng.randi_range(0, halt_symbols.size() - 1)])
			var halted_row: Dictionary = game.state.market.rows[halted_symbol]
			var before_suspension: int = int(halted_row.get("suspension", 0))
			halted_row["suspension"] = 15
			OriginalStockMarket.refresh_previous_price(game.state.market, halted_symbol)
			targets = [halted_symbol]
			changes.append({"stock": halted_symbol, "field": "suspension", "from": before_suspension, "to": 15, "price": float(halted_row.get("price", 0.0))})
			summary = "股票%s暫停交易15天" % halted_symbol
		28:
			var clear_halt_symbols: Array = []
			for symbol in _stock_symbols(game):
				if int(game.state.market.rows[symbol].get("suspension", 0)) > 0:
					clear_halt_symbols.append(symbol)
			if clear_halt_symbols.is_empty():
				return {"ok": false, "reason": "no_compatible_target"}
			var clear_halt_symbol: String = str(clear_halt_symbols[game._rng.randi_range(0, clear_halt_symbols.size() - 1)])
			var clear_halt_row: Dictionary = game.state.market.rows[clear_halt_symbol]
			var old_halt: int = int(clear_halt_row.get("suspension", 0))
			clear_halt_row["suspension"] = 0
			targets = [clear_halt_symbol]
			changes.append({"stock": clear_halt_symbol, "field": "suspension", "from": old_halt, "to": 0})
			summary = "股票%s解除停牌" % clear_halt_symbol
		30, 31, 32, 33, 34, 35:
			var company_targets: Array = []
			for company in game.state.get("companies", []):
				if typeof(company) != TYPE_DICTIONARY:
					continue
				if event_id == 35 and int(company.get("monthly_profit", 0)) <= 10000:
					continue
				company_targets.append(company)
			if company_targets.is_empty():
				return {"ok": false, "reason": "no_compatible_target"}
			var company_target: Dictionary = company_targets[game._rng.randi_range(0, company_targets.size() - 1)]
			var company_result: Dictionary = _apply_company(game, company_target, event_id)
			if not bool(company_result.get("ok", false)):
				return company_result
			targets = [int(company_target.get("id", -1))]
			changes.append(company_result.get("change", {}))
			summary = str(company_result.get("summary", "企業新聞已套用"))
		_:
			return {"ok": false, "reason": "unsupported"}
	return {"ok": true, "targets": targets, "changes": changes, "summary": summary}


static func _alive_player_ids(game: Object) -> Array:
	var result: Array = []
	for index in range(game.state.get("players", []).size()):
		var player: Variant = game.state.players[index]
		if typeof(player) == TYPE_DICTIONARY and bool(player.get("alive", false)):
			result.append(index)
	return result


static func _status_targets(game: Object, event_id: int) -> Array:
	var key := "prison_days" if event_id in [0, 1] else "hospital_days"
	var result: Array = []
	for player_id in _alive_player_ids(game):
		var value: int = int(game.state.players[player_id].get(key, 0))
		if value > 0 and value < 128:
			result.append(player_id)
	return result


static func _asset_targets(game: Object, require_built: bool, housing_only: bool) -> Array:
	var result: Array = []
	var seen_facilities: Dictionary = {}
	for index in range(game.state.get("board", []).size()):
		var tile: Variant = game.state.board[index]
		if typeof(tile) != TYPE_DICTIONARY:
			continue
		var kind := str(tile.get("kind", ""))
		var level := int(tile.get("building_level", 0))
		if kind == "property":
			if require_built and level <= 0:
				continue
			result.append(index)
		elif kind == "facility" and not housing_only:
			if require_built and level <= 0:
				continue
			var source_id := int(tile.get("source_object_id", -1))
			if source_id <= 0 or seen_facilities.has(source_id):
				continue
			seen_facilities[source_id] = true
			result.append(int(game._facility_canonical_index(index)))
	return result


static func _stock_symbols(game: Object) -> Array:
	return game.get_stock_symbols() if bool(game._is_companies()) else []


static func _pick_int(game: Object, values: Array) -> int:
	if values.is_empty():
		return -1
	return int(values[game._rng.randi_range(0, values.size() - 1)])


static func _clear_asset(game: Object, target_id: int) -> void:
	var tile: Dictionary = game.state.board[target_id]
	if tile.get("kind", "") == "facility":
		var source_id := int(tile.get("source_object_id", -1))
		var canonical := int(game._facility_canonical_index(target_id))
		var owner := int(game.state.board[canonical].get("owner", -1))
		game._update_facility_records(source_id, {"owner": -1, "building_level": 0, "facility_type": 0, "facility_state": 0, "research_tool": 0, "research_turns": 0})
		if owner >= 0:
			game._remove_property_reference(owner, canonical)
	else:
		var owner := int(tile.get("owner", -1))
		tile["owner"] = -1
		tile["building_level"] = 0
		if tile.has("is_chain_store"):
			tile["is_chain_store"] = false
		game._update_tile_rent(tile)
		if owner >= 0:
			game._remove_property_reference(owner, target_id)
	game._recalculate_property_values()


static func _damage_target_group(game: Object, target_id: int, housing_only: bool) -> Array:
	var tile: Dictionary = game.state.board[target_id]
	var kind := str(tile.get("kind", ""))
	if kind == "facility":
		if housing_only:
			return []
		var source_id := int(tile.get("source_object_id", -1))
		var aliases: Array = []
		for alias_id in game._facility_indices(source_id):
			var alias: Dictionary = game.state.board[int(alias_id)]
			if int(alias.get("building_level", 0)) > 0:
				aliases.append(int(alias_id))
		return aliases
	if kind != "property" or int(tile.get("building_level", 0)) <= 0:
		return []
	if housing_only:
		return [target_id]
	var target_name := str(tile.get("name", ""))
	var group: Array = []
	for candidate_id in range(game.state.board.size()):
		var candidate: Variant = game.state.board[candidate_id]
		if typeof(candidate) != TYPE_DICTIONARY or candidate.get("kind", "") != "property":
			continue
		if str(candidate.get("name", "")) == target_name and int(candidate.get("building_level", 0)) > 0:
			group.append(candidate_id)
	return group


static func _damage_asset_group(game: Object, group: Array) -> Array:
	var changes: Array = []
	var updated_facilities: Dictionary = {}
	for target_id_value in group:
		var target_id := int(target_id_value)
		if target_id < 0 or target_id >= game.state.board.size():
			continue
		var tile: Dictionary = game.state.board[target_id]
		if tile.get("kind", "") == "facility":
			var source_id := int(tile.get("source_object_id", -1))
			if updated_facilities.has(source_id):
				continue
			updated_facilities[source_id] = true
			var old_level := int(tile.get("building_level", 0))
			var next_level := maxi(0, old_level - 1)
			var updates: Dictionary = {"building_level": next_level}
			if next_level == 0:
				updates["facility_type"] = 0
				updates["facility_state"] = 0
				updates["research_tool"] = 0
				updates["research_turns"] = 0
			game._update_facility_records(source_id, updates)
			for alias_id in game._facility_indices(source_id):
				changes.append({"tile_id": int(alias_id), "field": "building_level", "from": old_level, "to": next_level})
		else:
			var old_level := int(tile.get("building_level", 0))
			var next_level := maxi(0, old_level - 1)
			tile["building_level"] = next_level
			if next_level == 0 and tile.has("is_chain_store"):
				tile["is_chain_store"] = false
			game._update_tile_rent(tile)
			changes.append({"tile_id": target_id, "field": "building_level", "from": old_level, "to": next_level})
	game._recalculate_property_values()
	return changes


static func adjusted_land_price(price: int, rising: bool) -> int:
	# Source handlers truncate the product, then write the low unsigned 16 bits.
	return int(floor(float(price) * (1.3 if rising else 0.7))) & 0xffff


static func _change_asset_price(game: Object, target_id: int, rising: bool) -> Array:
	var tile: Dictionary = game.state.board[target_id]
	var changes: Array = []
	if tile.get("kind", "") == "facility":
		var source_id := int(tile.get("source_object_id", -1))
		for alias_id in game._facility_indices(source_id):
			var alias: Dictionary = game.state.board[int(alias_id)]
			var old_price := int(alias.get("land_price", alias.get("cost", 0)))
			var next_price := adjusted_land_price(old_price, rising)
			alias["land_price"] = next_price
			alias["cost"] = next_price
			alias["news_price_override"] = true
			alias["news_price_source"] = int(old_price)
			changes.append({"tile_id": int(alias_id), "field": "land_price", "from": old_price, "to": next_price})
	else:
		var target_name := str(tile.get("name", ""))
		for candidate_id in range(game.state.board.size()):
			var candidate: Variant = game.state.board[candidate_id]
			if typeof(candidate) != TYPE_DICTIONARY or candidate.get("kind", "") != "property":
				continue
			if str(candidate.get("name", "")) != target_name:
				continue
			var old_price := int(candidate.get("land_price", candidate.get("cost", 0)))
			var next_price := adjusted_land_price(old_price, rising)
			candidate["land_price"] = next_price
			candidate["cost"] = next_price
			changes.append({"tile_id": candidate_id, "field": "land_price", "from": old_price, "to": next_price})
	game._recalculate_property_values()
	return changes


static func _select_property_holder(game: Object, greatest: bool) -> int:
	var selected := -1
	var selected_count := -1 if greatest else 1000000000
	for player_id in _alive_player_ids(game):
		var count := _asset_count(game, player_id)
		if (greatest and count > selected_count) or ((not greatest) and count < selected_count):
			selected = player_id
			selected_count = count
	return selected


static func _asset_count(game: Object, player_id: int) -> int:
	var player: Dictionary = game.state.players[player_id]
	var seen: Dictionary = {}
	for property_id in player.get("properties", []):
		var index := int(property_id)
		if index < 0 or index >= game.state.board.size():
			continue
		var tile: Dictionary = game.state.board[index]
		var key := "facility:%d" % int(tile.get("source_object_id", -1)) if tile.get("kind", "") == "facility" else "tile:%d" % index
		seen[key] = true
	return seen.size()


static func _stock_count(game: Object, player_id: int) -> int:
	var player: Dictionary = game.state.players[player_id]
	var stocks: Variant = player.get("stocks", {})
	if typeof(stocks) != TYPE_DICTIONARY:
		return 0
	var total := 0
	for symbol in _stock_symbols(game):
		total += maxi(0, int(stocks.get(symbol, 0)))
	return total


static func _select_stock_holder(game: Object) -> int:
	var selected := -1
	var selected_count := -1
	for player_id in _alive_player_ids(game):
		var count := _stock_count(game, player_id)
		if count > selected_count:
			selected = player_id
			selected_count = count
	return selected if selected_count > 0 else -1


static func _asset_value(game: Object, player_id: int) -> int:
	var player: Dictionary = game.state.players[player_id]
	var seen: Dictionary = {}
	var total := 0
	for property_id in player.get("properties", []):
		var index := int(property_id)
		if index < 0 or index >= game.state.board.size():
			continue
		var tile: Dictionary = game.state.board[index]
		var key := "facility:%d" % int(tile.get("source_object_id", -1)) if tile.get("kind", "") == "facility" else "tile:%d" % index
		if seen.has(key):
			continue
		seen[key] = true
		total += int(tile.get("land_price", tile.get("cost", 0))) + int(tile.get("building_level", 0)) * int(tile.get("upgrade_cost", tile.get("house_price", 0)))
	return total


static func _stock_value(game: Object, player_id: int) -> float:
	var player: Dictionary = game.state.players[player_id]
	var total := 0.0
	for symbol in _stock_symbols(game):
		total += float(player.get("stocks", {}).get(symbol, 0)) * float(game.state.market.rows[symbol].get("price", 0.0))
	return total


static func _news_credit(game: Object, player_id: int, amount: int) -> void:
	if amount <= 0:
		return
	var player: Dictionary = game.state.players[player_id]
	if int(player.get("cash", 0)) > 1000000000000 - amount:
		return
	player["cash"] = int(player.get("cash", 0)) + amount


static func _apply_company(game: Object, company: Dictionary, event_id: int) -> Dictionary:
	var old_monthly := int(company.get("monthly_profit", 0))
	var old_cumulative := int(company.get("cumulative_profit", 0))
	var delta := 0
	var event_code := 0
	var rate := -10.0
	if event_id == 35:
		var doubled: int = old_monthly * 2
		if doubled > 1000000000000 or doubled > 1000000000000 - old_cumulative:
			return {"ok": false, "reason": "earnings_limit"}
		company["monthly_profit"] = doubled
		company["cumulative_profit"] = old_cumulative + doubled
		event_code = (int(old_monthly / 10000) * 16) & 0xff
		rate = 10.0 if (event_code & 0xf0) != 0 else -10.0
	else:
		delta = -10000 if event_id in [30, 33] else 20000 if event_id == 31 else -20000 if event_id == 32 else -5000
		if old_monthly + delta < -1000000000000 or old_cumulative + delta < -1000000000000 or old_monthly + delta > 1000000000000 or old_cumulative + delta > 1000000000000:
			return {"ok": false, "reason": "earnings_limit"}
		company["monthly_profit"] = old_monthly + delta
		company["cumulative_profit"] = old_cumulative + delta
		event_code = 0x30 if event_id == 31 else 4 if event_id == 32 else 3
		rate = 10.0 if event_id == 31 else -10.0
	var stock_index := int(company.get("stock_index", -1))
	var symbol := OriginalStockMarket.symbol(stock_index)
	if stock_index < 0 or not game.state.market.get("rows", {}).has(symbol):
		return {"ok": false, "reason": "company_stock_missing"}
	var row: Dictionary = game.state.market.rows[symbol]
	row["event"] = event_code
	if event_code != 0:
		OriginalStockMarket.refresh_event_price(game.state.market, symbol, rate)
	var company_name := str(company.get("display_name", company.get("name", "企業")))
	var change := {"company_id": int(company.get("id", -1)), "monthly_profit": int(company.get("monthly_profit", 0)), "cumulative_profit": int(company.get("cumulative_profit", 0)), "stock": symbol, "event": event_code, "price": float(row.get("price", 0.0))}
	var summary := "企業「%s」收益變更為%d元，連動股票%s" % [company_name, int(company.get("monthly_profit", 0)), symbol]
	return {"ok": true, "change": change, "summary": summary}


static func _player_name(game: Object, player_id: int) -> String:
	if player_id < 0 or player_id >= game.state.get("players", []).size():
		return "玩家"
	return str(game.state.players[player_id].get("name", "玩家 %d" % (player_id + 1)))


static func _player_list(game: Object, player_ids: Array) -> String:
	var names: Array = []
	for player_id in player_ids:
		names.append(_player_name(game, int(player_id)))
	return "、".join(names) if not names.is_empty() else "目前玩家"


static func _valid_int(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	if typeof(value) == TYPE_FLOAT:
		var real: float = float(value)
		return is_finite(real) and floor(real) == real and real >= float(minimum) and real <= float(maximum)
	return false
