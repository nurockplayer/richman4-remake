extends RefCounted

## Synthetic v11 remodel map built from the complete property-card fixture.
## The fixture contains no original assets or extracted source material.

const Base = preload("res://tests/fixtures/property_card_fixture.gd")

const REMODEL_SAVE_VERSION := 11


static func definition() -> Dictionary:
	var result: Dictionary = Base.definition()
	result["supports_original_remodel"] = true

	var board: Array = result.get("board", [])
	for tile_value in board:
		if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "property":
			tile_value["is_chain_store"] = false

	# Keep a reachable, ordinary road node for remodel rejection tests.  It is
	# appended after the source-derived fixture so no source asset is invented.
	var road_index := board.size()
	if board.size() > 0 and typeof(board[board.size() - 1]) == TYPE_DICTIONARY:
		var prior: Dictionary = board[board.size() - 1]
		var prior_edges: Array = prior.get("adjacent", []).duplicate()
		if not prior_edges.has(road_index):
			prior_edges.append(road_index)
		prior["adjacent"] = prior_edges
	board.append({
		"index": road_index,
		"source_node_id": road_index + 1,
		"x": 900,
		"y": 100,
		"adjacent": [road_index - 1],
		"type_and_idx": 0,
		"visual_index": 0,
		"event_code": 0,
		"source_status_bits": 0,
		"source_object_id": 0,
		"kind": "rest",
		"name": "測試道路",
		"owner": -1,
		"building_level": 0,
		"cost": 0,
		"upgrade_cost": 0,
		"base_rent": 0,
		"rent": 0,
		"group": "",
		"tax_amount": 0,
	})
	result["board"] = board
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
		"original_remodel": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	}


static func v10_game_options() -> Dictionary:
	# The predecessor fixture is intentionally the exact v10 option set.  A
	# v11 bootstrap may stamp this instance only when the v11 factory is absent.
	return Base.new_game_options()
