class_name RichmanOriginalGods
extends RefCounted

## Compact source-backed god definitions.  Artwork and executable data stay
## outside the repository; the runtime only needs stable identities and the
## verified lifecycle/effect groups.
const INITIAL_IDS: Array = [1, 3, 5, 7, 9, 11]
const GOD_ROWS: Dictionary = {
	1: {"name": "小財神", "pair": 2, "days": 7, "role": "wealth_small"},
	2: {"name": "大財神", "pair": 1, "days": 7, "role": "wealth_large"},
	3: {"name": "小福神", "pair": 4, "days": 7, "role": "fortune_small"},
	4: {"name": "大福神", "pair": 3, "days": 7, "role": "fortune_large"},
	5: {"name": "小窮神", "pair": 6, "days": 7, "role": "poor_small"},
	6: {"name": "大窮神", "pair": 5, "days": 7, "role": "poor_large"},
	7: {"name": "小衰神", "pair": 8, "days": 7, "role": "unlucky_small"},
	8: {"name": "大衰神", "pair": 7, "days": 7, "role": "unlucky_large"},
	9: {"name": "天使", "pair": 10, "days": 7, "role": "angel"},
	10: {"name": "惡魔", "pair": 9, "days": 7, "role": "demon"},
	11: {"name": "惡犬", "pair": 12, "days": 0, "role": "dog"},
	12: {"name": "土地公", "pair": 11, "days": 7, "role": "land_god"},
	13: {"name": "禮物", "pair": 0, "days": 0, "role": "gift"},
	14: {"name": "寶箱", "pair": 0, "days": 0, "role": "chest"},
	15: {"name": "死神", "pair": 0, "days": 13, "role": "death"},
}


static func valid_id(god_id: Variant) -> bool:
	return typeof(god_id) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(god_id)) and floor(float(god_id)) == float(god_id) and GOD_ROWS.has(int(god_id))


static func definition(god_id: int) -> Dictionary:
	if not GOD_ROWS.has(god_id):
		return {}
	return GOD_ROWS[god_id].duplicate(true)


static func name_for(god_id: int) -> String:
	if god_id == 0:
		return "無"
	return str(GOD_ROWS.get(god_id, {}).get("name", "未知神明"))


static func pair_for(god_id: int) -> int:
	return int(GOD_ROWS.get(god_id, {}).get("pair", 0))


static func days_for(god_id: int) -> int:
	return int(GOD_ROWS.get(god_id, {}).get("days", 0))


static func role_for(god_id: int) -> String:
	return str(GOD_ROWS.get(god_id, {}).get("role", "unknown"))


static func initial_ids() -> Array:
	return INITIAL_IDS.duplicate()


static func is_attachable(god_id: int) -> bool:
	return god_id >= 1 and god_id <= 10 or god_id == 12 or god_id == 15


static func is_spawnable(god_id: int) -> bool:
	# The bounded Issue #23 runtime guarantees the six initial objects.  The
	# unsupported gift/chest and death acquisition paths remain explicit gaps.
	return god_id >= 1 and god_id <= 12


static func source_tile_eligible(tile: Dictionary, occupied: Dictionary = {}, anchor: Dictionary = {}, require_distance: bool = false) -> bool:
	if tile.is_empty() or not typeof(tile.get("adjacent", null)) == TYPE_ARRAY or tile.get("adjacent", []).is_empty():
		return false
	var tile_index: int = int(tile.get("index", -1))
	if occupied.has(tile_index):
		return false
	var has_flags: bool = tile.has("source_status_bits") or tile.has("status_bits")
	if has_flags:
		var flags: Variant = tile.get("source_status_bits", tile.get("status_bits", null))
		if typeof(flags) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(flags)) or floor(float(flags)) != float(flags):
			return false
		if (int(flags) & 0x80ffff00) != 0:
			return false
	else:
		# Direct synthetic boards predate source_status_bits.  Keep this fallback
		# deliberately narrow so event and special nodes are never selected.
		var object_type: Variant = tile.get("type_and_idx", null)
		var event_code: Variant = tile.get("event_code", null)
		if typeof(object_type) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(object_type)) or floor(float(object_type)) != float(object_type) or int(object_type) >= 2000:
			return false
		if typeof(event_code) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(event_code)) or floor(float(event_code)) != float(event_code) or int(event_code) != 0:
			return false
	if require_distance and not anchor.is_empty():
		var x_delta: int = abs(int(tile.get("x", 0)) - int(anchor.get("x", 0)))
		var y_delta: int = abs(int(tile.get("y", 0)) - int(anchor.get("y", 0)))
		if x_delta < 300 and y_delta < 300:
			return false
	return true


static func spawn_candidates(board: Array, occupied: Dictionary = {}, anchor_node: int = -1, require_distance: bool = false) -> Array:
	var anchor: Dictionary = {}
	if anchor_node >= 0 and anchor_node < board.size() and typeof(board[anchor_node]) == TYPE_DICTIONARY:
		anchor = board[anchor_node]
	var candidates: Array = []
	for index in range(board.size()):
		if typeof(board[index]) != TYPE_DICTIONARY:
			continue
		if source_tile_eligible(board[index], occupied, anchor, require_distance):
			candidates.append(index)
	candidates.sort()
	return candidates
