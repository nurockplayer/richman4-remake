class_name RichmanOriginalMaps
extends RefCounted

const SCHEMA := "richman4.runtime-map/v1"
const MAX_CATALOG_BYTES := 32 * 1024 * 1024
const EVENT_NAMES := {
	0: "道路", 1: "道路", 2: "新聞", 3: "命運", 4: "監獄入口", 5: "醫院入口",
	6: "企鵝小遊戲", 7: "氣球小遊戲", 8: "接物小遊戲", 9: "彩券",
	10: "點數 50", 11: "點數 30", 12: "點數 10", 13: "卡片", 14: "銀行", 15: "商店", 16: "魔法屋",
}

static func default_catalog_path() -> String:
	var configured := OS.get_environment("RICHMAN4_MAP_CATALOG")
	if not configured.is_empty():
		return configured
	var packaged := OS.get_executable_path().get_base_dir().path_join("../Resources/Original/maps/catalog.json").simplify_path()
	for candidate in [packaged, "res://.local/runtime-original/maps/catalog.json", "res://.local/imported-original/maps/catalog.json"]:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""

static func load_catalog(path: String = "") -> Dictionary:
	var resolved := default_catalog_path() if path.is_empty() else path
	if resolved.is_empty():
		return {"ok": false, "error": "尚未匯入本機原版地圖。", "maps": []}
	var file := FileAccess.open(resolved, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "無法讀取地圖目錄。", "maps": []}
	if file.get_length() > MAX_CATALOG_BYTES:
		return {"ok": false, "error": "地圖目錄超出大小限制。", "maps": []}
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not raw is Dictionary or raw.get("schema", "") != "richman4.map-catalog/v1" or not raw.get("maps") is Array:
		return {"ok": false, "error": "地圖目錄格式無效。", "maps": []}
	if raw.get("version") != 1 or raw.maps.size() > 32 or raw.get("count") != raw.maps.size():
		return {"ok": false, "error": "地圖目錄版本或數量無效。", "maps": []}
	var maps: Array = []
	var identities: Dictionary = {}
	for entry in raw.maps:
		var result := normalize_map(entry)
		if not result.ok:
			return {"ok": false, "error": result.error, "maps": []}
		var definition: Dictionary = result.definition
		if identities.has(definition.id):
			return {"ok": false, "error": "地圖身分重複。", "maps": []}
		identities[definition.id] = true
		maps.append(definition)
	return {"ok": true, "error": "", "maps": maps}

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and floor(float(value)) == float(value) and value >= low and value <= high

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _hash(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true

## Return the one canonical runtime classification for a source node.
##
## Keeping this mapping next to normalize_map means a graph save cannot change
## the observed event into a different runtime action by editing only `kind`.
static func classify_source_node(type_and_idx: Variant, event_code: Variant) -> Dictionary:
	if not _integer(type_and_idx, 0, 65535) or not _integer(event_code, 0, 255):
		return {"ok": false, "kind": ""}
	var object_type := int(type_and_idx)
	var event := int(event_code)
	if object_type > 2000 and object_type < 4000:
		return {"ok": true, "kind": "property"}
	if event == 14:
		return {"ok": true, "kind": "bank"}
	if object_type >= 4000:
		return {"ok": true, "kind": "unsupported"}
	if event == 13:
		return {"ok": true, "kind": "card"}
	if event in [10, 11, 12]:
		return {"ok": true, "kind": "points", "points": {10: 50, 11: 30, 12: 10}[event]}
	if event > 1:
		return {"ok": true, "kind": "unsupported"}
	return {"ok": true, "kind": "rest"}

static func normalize_map(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.get("schema", "") != "richman4.map/v1":
		return _failure("原版地圖格式無效。")
	if raw.get("edition") not in ["Game", "MultiverseJourney"] or not _integer(raw.get("map_number"), 1, 99):
		return _failure("原版地圖身分無效。")
	if raw.get("version") != 1 or not _hash(raw.get("payload_sha256")) or not _hash(raw.get("source_file_sha256")):
		return _failure("原版地圖來源資訊無效。")
	if not _integer(raw.get("entry_index"), 0, 999) or raw.get("archive") != "%s/map.mkf" % raw.edition:
		return _failure("原版地圖來源位置無效。")
	for key in ["nodes", "lands", "facilities", "companies"]:
		if not raw.get(key) is Array:
			return _failure("原版地圖缺少 %s。" % key)
	var nodes: Array = raw.nodes
	if nodes.size() < 2 or nodes.size() > 4096:
		return _failure("原版地圖節點數無效。")
	var lands: Dictionary = {}
	for land in raw.lands:
		if not land is Dictionary or not _integer(land.get("id"), 1, 1999) or lands.has(int(land.id)):
			return _failure("住宅身分無效或重複。")
		if (land.has("display_name") and (not land.display_name is String or land.display_name.length() > 128)) or not land.get("name_bytes_hex") is String:
			return _failure("住宅名稱無效。")
		for key in ["land_price", "house_price"]:
			if not _integer(land.get(key), 0, 1000000):
				return _failure("住宅價格無效。")
		if not land.get("rent_by_level") is Array or land.rent_by_level.size() != 6:
			return _failure("住宅租金表無效。")
		for rent in land.rent_by_level:
			if not _integer(rent, 0, 1000000):
				return _failure("住宅租金數值無效。")
		lands[int(land.id)] = land
	var board: Array = []
	var referenced_lands: Dictionary = {}
	var start_position := -1
	for index in range(nodes.size()):
		var node: Variant = nodes[index]
		if not node is Dictionary or not _integer(node.get("id"), index + 1, index + 1):
			return _failure("原版地圖節點順序無效。")
		for key in ["x", "y"]:
			if not _integer(node.get(key), -1000000, 1000000):
				return _failure("原版地圖座標無效。")
		if not node.get("adjacent") is Array or node.adjacent.size() > 4:
			return _failure("原版地圖鄰接資料無效。")
		var adjacent: Array = []
		for neighbor in node.adjacent:
			if not _integer(neighbor, 1, nodes.size()) or int(neighbor) == index + 1 or adjacent.has(int(neighbor) - 1):
				return _failure("原版地圖包含無效連線。")
			adjacent.append(int(neighbor) - 1)
		if not _integer(node.get("type_and_idx"), 0, 65535) or not _integer(node.get("event_code"), 0, 255):
			return _failure("原版地圖格位類別無效。")
		var object_type := int(node.type_and_idx)
		var event_code := int(node.event_code)
		var classification: Dictionary = classify_source_node(object_type, event_code)
		var tile := {"index": index, "source_node_id": index + 1, "x": int(node.x), "y": int(node.y), "adjacent": adjacent,
			"type_and_idx": object_type, "visual_index": node.get("visual_index", 0), "event_code": event_code, "source_object_id": 0,
			"kind": "rest", "name": EVENT_NAMES.get(event_code, "未知事件 %d" % event_code), "owner": -1, "building_level": 0,
			"cost": 0, "upgrade_cost": 0, "base_rent": 0, "rent": 0, "group": "", "tax_amount": 0}
		if classification.kind == "property":
			var land_id := object_type - 2000
			if not lands.has(land_id) or referenced_lands.has(land_id):
				return _failure("住宅參照缺失或重複。")
			referenced_lands[land_id] = true
			var land: Dictionary = lands[land_id]
			tile.merge({"kind": "property", "source_object_id": land_id, "name": str(land.get("display_name", "未命名住宅 %d" % land_id)),
				"cost": int(land.land_price), "land_price": int(land.land_price), "house_price": int(land.house_price),
				"upgrade_cost": int(land.house_price), "base_rent": int(land.rent_by_level[0]), "rent": int(land.rent_by_level[0]),
				"rent_by_level": land.rent_by_level.duplicate(), "group": str(land.get("name_bytes_hex", "land:%d" % land_id))}, true)
		elif classification.kind == "bank":
			# Bank service is an event on company nodes in the original maps.
			# Company ownership remains separate from passing/landing service.
			tile.kind = "bank"
		elif classification.kind == "unsupported":
			tile.kind = "unsupported"
			if object_type >= 4000:
				tile.name = "醫院" if object_type == 8001 else ("監獄" if object_type == 8002 else "特殊設施")
				tile.name += "（待還原）"
			else:
				tile.name += "（待還原）"
		elif classification.kind == "card":
			tile.kind = "card"
		elif classification.kind == "points":
			tile.kind = "points"
			tile.points = int(classification.points)
		if start_position < 0 and adjacent.size() >= 2 and object_type < 4000:
			start_position = index
		board.append(tile)
	for tile in board:
		for neighbor in tile.adjacent:
			if not board[neighbor].adjacent.has(tile.index):
				return _failure("原版地圖連線不對稱。")
	if start_position < 0:
		return _failure("原版地圖沒有可用起點。")
	var reachable := {start_position: true}
	var frontier := [start_position]
	while not frontier.is_empty():
		var current: int = frontier.pop_back()
		for neighbor in board[current].adjacent:
			if not reachable.has(neighbor):
				reachable[neighbor] = true
				frontier.append(neighbor)
	for tile in board:
		if tile.kind == "property" and not reachable.has(tile.index):
			return _failure("原版地圖包含無法從起點到達的住宅。")
	var supported := not referenced_lands.is_empty()
	var definition := {"schema": SCHEMA, "version": 1, "id": "%s:%d" % [raw.edition, raw.map_number],
		"name": "%s · 地圖 %d" % ["原版" if raw.edition == "Game" else "超時空之旅", raw.map_number],
		"source": {"edition": raw.edition, "map_number": int(raw.map_number), "archive": raw.get("archive", ""),
			"entry_index": raw.get("entry_index", 0), "payload_sha256": raw.get("payload_sha256", ""), "source_file_sha256": raw.get("source_file_sha256", "")},
		"board": board, "start_position": start_position, "supports_new_game": supported,
		"unsupported_reason": "" if supported else "此地圖需要商業設施系統，尚未開放對局。"}
	return {"ok": true, "error": "", "definition": definition}
