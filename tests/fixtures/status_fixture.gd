extends RefCounted

const Base = preload("res://tests/fixtures/company_fixture.gd")


static func definition() -> Dictionary:
	var result: Dictionary = Base.definition()
	for entry in [
		{"index": 0, "type_and_idx": 8001, "name": "測試醫院"},
		{"index": 4, "type_and_idx": 8002, "name": "測試監獄"},
	]:
		var tile: Dictionary = result.board[int(entry.index)]
		tile.merge({
			"kind": "unsupported",
			"type_and_idx": int(entry.type_and_idx),
			"event_code": 0,
			"source_status_bits": 0,
			"name": str(entry.name),
		}, true)
	result["supports_original_statuses"] = true
	return result
