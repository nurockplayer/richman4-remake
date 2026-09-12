extends SceneTree

# M4 reads only the frozen static GOD_ROWS constant. Never call spawn/effect/runtime helpers.
const GodSource = preload("res://game/content/original_gods.gd")
const PREFIX := "RICHMAN4_GODS_ORACLE="

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func _initialize() -> void:
	var ids: Array = GodSource.GOD_ROWS.keys()
	ids.sort()
	if ids.size() != 15:
		fail("M4 GOD_ROWS must contain exactly 15 rows")
		return
	var rows: Array = []
	for expected_id in range(1, 16):
		if ids[expected_id - 1] != expected_id:
			fail("M4 GOD_ROWS IDs must be exactly 1..15")
			return
		var source_row: Variant = GodSource.GOD_ROWS[expected_id]
		if typeof(source_row) != TYPE_DICTIONARY or source_row.size() != 4:
			fail("M4 GOD_ROWS row must be a four-field Dictionary")
			return
		for key in ["name", "pair", "days", "role"]:
			if not source_row.has(key):
				fail("M4 GOD_ROWS row missing field: " + key)
				return
		if typeof(source_row["name"]) != TYPE_STRING or source_row["name"].strip_edges().is_empty():
			fail("M4 god name must be non-empty Text")
			return
		if typeof(source_row["pair"]) != TYPE_INT or source_row["pair"] < 0 or source_row["pair"] > 15:
			fail("M4 pair must be integral 0..15")
			return
		if typeof(source_row["days"]) != TYPE_INT or source_row["days"] < 0:
			fail("M4 duration must be a non-negative integer")
			return
		if typeof(source_row["role"]) != TYPE_STRING or source_row["role"].strip_edges().is_empty():
			fail("M4 role must be non-empty Text")
			return
		rows.append({
			"legacy_id": expected_id,
			"display_name": source_row["name"],
			"pair_legacy_id": source_row["pair"],
			"duration_days": source_row["days"],
			"role_key": source_row["role"],
		})
	print(PREFIX + JSON.stringify({"gods": rows}))
	quit(0)
