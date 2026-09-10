extends RefCounted

## Minimal source-shaped company map used by the Issue #135 encounter tests.
## It is intentionally synthetic and contains no extracted source assets.

const Base = preload("res://tests/fixtures/original_map_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")


static func stock_rows() -> Array:
	var rows: Array = []
	for index in range(12):
		rows.append({
			"index": index,
			"name": "股票 %d" % (index + 1),
			"company_id": 1 if index == 0 else 0,
			"market_supply": 5000 if index == 0 else 10000,
			"turn_supply": 0,
			"base_price": 100.0,
			"previous_price": 100.0,
			"price": 100.0,
			"volatility": 1.0,
			"momentum": 0.0,
			"shock": 0.0,
			"suspension": 0,
			"event": 0,
		})
	return rows


static func definition() -> Dictionary:
	var raw: Dictionary = Base.make()
	# 0 prison -> 1 bank -> 2 points.  Node 2 branches to a second bank
	# (node 3) or a property tile (node 4), then both paths meet at node 5.
	# Node 6 is a type-7 company bank; nodes 7/8 provide status coverage and a
	# second valid housing reference for the source-capable setup.
	raw["nodes"] = [
		{"id": 1, "x": 100, "y": 100, "adjacent": [2], "type_and_idx": 8002, "event_code": 0, "visual_index": 0},
		{"id": 2, "x": 180, "y": 100, "adjacent": [1, 3], "type_and_idx": 0, "event_code": 14, "visual_index": 0},
		{"id": 3, "x": 260, "y": 100, "adjacent": [2, 4, 5], "type_and_idx": 0, "event_code": 10, "visual_index": 0},
		{"id": 4, "x": 340, "y": 100, "adjacent": [3, 6], "type_and_idx": 0, "event_code": 14, "visual_index": 0},
		{"id": 5, "x": 340, "y": 180, "adjacent": [3, 6], "type_and_idx": 2001, "event_code": 0, "visual_index": 0},
		{"id": 6, "x": 420, "y": 140, "adjacent": [4, 5, 7], "type_and_idx": 0, "event_code": 13, "visual_index": 0},
		{"id": 7, "x": 500, "y": 140, "adjacent": [6, 8, 9], "type_and_idx": 6001, "event_code": 14, "visual_index": 0},
		{"id": 8, "x": 580, "y": 140, "adjacent": [7], "type_and_idx": 8001, "event_code": 0, "visual_index": 0},
		{"id": 9, "x": 500, "y": 220, "adjacent": [7], "type_and_idx": 2002, "event_code": 0, "visual_index": 0},
	]
	var loaded: Dictionary = Maps.normalize_map(raw, true)
	if not bool(loaded.get("ok", false)):
		return {}
	var result: Dictionary = loaded["definition"]
	# The base fixture deliberately omits complete source company records. Add
	# the smallest coherent company catalogue after map normalization, matching
	# the established company_fixture pattern.
	result["supports_original_companies"] = true
	result["supports_original_statuses"] = true
	result["supports_original_hazards"] = true
	result["stock_rows"] = stock_rows()
	result["companies"] = [{
		"id": 1,
		"display_name": "測試企業",
		"company_type": 7,
		"stock_index": 0,
		"stock_value": 400000,
		"toll_fee": 150,
		"monthly_profit": 0,
		"cumulative_profit": 0,
		"treasury": 5000,
		"source_owner": 0,
	}]
	result["board"][6]["source_company_id"] = 1
	result["board"][6]["company_node_index"] = 6
	return result
