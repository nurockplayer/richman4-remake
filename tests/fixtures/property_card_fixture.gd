extends RefCounted

## Synthetic property-card map built from the complete v9 hazard fixture.
## The fixture contains no original assets or extracted source material.

const Base = preload("res://tests/fixtures/hazard_fixture.gd")

const PROPERTY_CARD_SAVE_VERSION := 10


static func definition() -> Dictionary:
	var result: Dictionary = Base.definition()
	result["original_facilities"] = true
	result["supports_original_property_cards"] = true

	var board: Array = result.get("board", [])
	# Keep two ordinary houses for the property branch. Turn the old points
	# node into one entrance of a shared facility, retain the company node as a
	# wrong-kind target, and append a second shared facility with two entrances.
	_set_facility_tile(board[1], 1, 1, "測試公園", 1000)
	board[1]["adjacent"].append(6)
	board.append(_new_facility_tile(6, 1, 1, "測試公園", 180, 100, [1], 1000))

	board[5]["adjacent"].append(7)
	board.append(_new_facility_tile(7, 2, 7, "測試旅館", 660, 180, [5, 8], 2000))
	board.append(_new_facility_tile(8, 2, 7, "測試旅館", 740, 260, [7], 2000))

	var source: Dictionary = result.get("source", {}).duplicate(true)
	source["facilities"] = [
		_facility_source(1, "測試公園"),
		_facility_source(2, "測試旅館"),
	]
	result["source"] = source
	return result


static func new_game_options() -> Dictionary:
	return {
		"original_inventory": true,
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"original_statuses": true,
		"original_hazards": true,
		"original_property_cards": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	}


static func v9_game_options() -> Dictionary:
	var options: Dictionary = new_game_options()
	options.erase("original_property_cards")
	return options


static func _facility_source(source_id: int, name: String) -> Dictionary:
	return {
		"id": source_id,
		"display_name": name,
		"name_bytes_hex": "74657374000000000000000000000000",
		"facility_type": 0,
		"owner": 0,
		"level": 0,
		"tmp_state": 0,
		"land_price": 1000 if source_id == 1 else 2000,
		"price_per_level": 300,
		"reserved_hex": "6400c8002c019001f401",
	}


static func _set_facility_tile(tile: Dictionary, source_id: int, canonical_index: int, name: String, land_price: int) -> void:
	for key in ["points", "source_company_id", "company_node_index", "company_name", "company_state"]:
		tile.erase(key)
	tile.merge({
		"kind": "facility",
		"type_and_idx": 4000 + source_id,
		"event_code": 0,
		"source_status_bits": 0,
		"source_object_id": source_id,
		"name": name,
		"owner": -1,
		"building_level": 0,
		"cost": land_price,
		"land_price": land_price,
		"upgrade_cost": 300,
		"base_rent": 0,
		"rent": 0,
		"group": "facility:%d" % source_id,
		"tax_amount": 0,
		"facility_type": 0,
		"facility_state": 0,
		"fee_by_level": [300, 100, 200, 300, 400, 500],
		"facility_node_index": canonical_index,
	}, true)


static func _new_facility_tile(
	index: int,
	source_id: int,
	canonical_index: int,
	name: String,
	x: int,
	y: int,
	adjacent: Array,
	land_price: int,
) -> Dictionary:
	return {
		"index": index,
		"source_node_id": index + 1,
		"x": x,
		"y": y,
		"adjacent": adjacent.duplicate(),
		"type_and_idx": 4000 + source_id,
		"visual_index": 0,
		"event_code": 0,
		"source_status_bits": 0,
		"source_object_id": source_id,
		"kind": "facility",
		"name": name,
		"owner": -1,
		"building_level": 0,
		"cost": land_price,
		"land_price": land_price,
		"upgrade_cost": 300,
		"base_rent": 0,
		"rent": 0,
		"group": "facility:%d" % source_id,
		"tax_amount": 0,
		"facility_type": 0,
		"facility_state": 0,
		"fee_by_level": [300, 100, 200, 300, 400, 500],
		"facility_node_index": canonical_index,
	}
