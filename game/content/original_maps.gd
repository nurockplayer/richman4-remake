class_name RichmanOriginalMaps
extends RefCounted

const SCHEMA := "richman4.runtime-map/v1"
const MAX_CATALOG_BYTES := 32 * 1024 * 1024
const FACILITY_MIN_SOURCE_TYPE := 4001
const FACILITY_MAX_SOURCE_TYPE := 5999
const FACILITY_MAX_SOURCE_ID := 1999
const FACILITY_PRICE_COUNT := 6
const STOCK_COUNT := 12
const COMPANY_MAX_ID := 1999
const COMPANY_MIN_SOURCE_TYPE := 6001
const COMPANY_MAX_SOURCE_TYPE := 7999
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

static func load_catalog(path: String = "", original_facilities: bool = false) -> Dictionary:
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
		var result := normalize_map(entry, original_facilities)
		if not result.ok:
			return {"ok": false, "error": result.error, "maps": []}
		var definition: Dictionary = result.definition
		if identities.has(definition.id):
			return {"ok": false, "error": "地圖身分重複。", "maps": []}
		identities[definition.id] = true
		maps.append(definition)
	return {"ok": true, "error": "", "maps": maps, "original_facilities": original_facilities}

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and floor(float(value)) == float(value) and value >= low and value <= high

static func _number(value: Variant, low: float, high: float) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _hash(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true

static func _hex(value: Variant, byte_count: int) -> bool:
	if not value is String or value.length() != byte_count * 2:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true

## Decode the facility price span at source +0x24.
##
## Schema-v1 importer output and older local caches expose the first u16 as
## price_per_level. The following five u16 values remain in reserved_hex;
## together they form the six-entry fee_by_level table. Entry zero is also the
## level-zero upgrade cost in the original source layout.
static func facility_price_table(record: Variant) -> Dictionary:
	if not record is Dictionary:
		return _failure("設施價目資料無效。")
	var has_upgrade_cost: bool = record.has("upgrade_cost")
	var has_legacy_price: bool = record.has("price_per_level")
	if not has_upgrade_cost and not has_legacy_price:
		return _failure("設施缺少升級價格。")
	var upgrade_cost: Variant = record.get("upgrade_cost", record.get("price_per_level", null))
	if not _integer(upgrade_cost, 0, 1000000):
		return _failure("設施升級價格無效。")
	if has_legacy_price:
		var legacy_price: Variant = record.get("price_per_level", null)
		if not _integer(legacy_price, 0, 1000000) or int(legacy_price) != int(upgrade_cost):
			return _failure("設施升級價格別名不一致。")
	var reserved: Variant = record.get("reserved_hex", null)
	if not _hex(reserved, (FACILITY_PRICE_COUNT - 1) * 2):
		return _failure("設施價目保留欄位無效。")
	var reserved_text := str(reserved)
	var digits := "0123456789abcdef"
	var prices: Array = [int(upgrade_cost)]
	for index in range(0, reserved_text.length(), 4):
		var low := digits.find(reserved_text.substr(index, 1))
		var high := digits.find(reserved_text.substr(index + 1, 1))
		var next_low := digits.find(reserved_text.substr(index + 2, 1)) if index + 2 < reserved_text.length() else -1
		var next_high := digits.find(reserved_text.substr(index + 3, 1)) if index + 3 < reserved_text.length() else -1
		if low < 0 or high < 0:
			return _failure("設施價目保留欄位無效。")
		# The retained bytes are five little-endian u16 values. Decode one
		# byte pair at a time; the first pair is the low/high nibble pair of
		# each byte, then combine the two bytes into the source price.
		var byte_low := low * 16 + high
		if next_low < 0 or next_high < 0:
			return _failure("設施價目保留欄位無效。")
		var byte_high := next_low * 16 + next_high
		prices.append(byte_low + byte_high * 256)
	if prices.size() != FACILITY_PRICE_COUNT:
		return _failure("設施價目數量無效。")
	if record.has("fee_by_level"):
		var explicit_fees: Variant = record.get("fee_by_level", null)
		if not explicit_fees is Array or explicit_fees.size() != FACILITY_PRICE_COUNT:
			return _failure("設施費用表必須有六級。")
		for index in range(FACILITY_PRICE_COUNT):
			if not _integer(explicit_fees[index], 0, 1000000) or int(explicit_fees[index]) != int(prices[index]):
				return _failure("設施費用表與來源價格不一致。")
	return {"ok": true, "error": "", "upgrade_cost": int(prices[0]), "fee_by_level": prices}

static func _normalize_facility_record(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("設施資料無效。")
	var facility: Dictionary = value
	if not _integer(facility.get("id", null), 1, FACILITY_MAX_SOURCE_ID):
		return _failure("設施身分無效。")
	if not _hex(facility.get("name_bytes_hex", null), 16):
		return _failure("設施名稱來源無效。")
	if facility.has("display_name") and (not facility.display_name is String or facility.display_name.length() > 128):
		return _failure("設施名稱無效。")
	if not _integer(facility.get("facility_type", null), 0, 4):
		return _failure("設施類型無效。")
	if not _integer(facility.get("owner", null), 0, 255) or not _integer(facility.get("level", null), 0, 5):
		return _failure("設施原始狀態無效。")
	if not _integer(facility.get("tmp_state", null), 0, 255):
		return _failure("設施臨時狀態無效。")
	if not _integer(facility.get("land_price", null), 0, 1000000):
		return _failure("設施地價無效。")
	if facility.has("field_0x1b") and not _integer(facility.get("field_0x1b", null), 0, 255):
		return _failure("設施欄位無效。")
	var prices := facility_price_table(facility)
	if not prices.ok:
		return prices
	var normalized := facility.duplicate(true)
	normalized["upgrade_cost"] = prices.upgrade_cost
	normalized["fee_by_level"] = prices.fee_by_level.duplicate()
	return {"ok": true, "error": "", "record": normalized}

static func _normalize_company_record(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("企業資料無效。")
	var company: Dictionary = value.duplicate(true)
	if not _integer(company.get("id", null), 1, COMPANY_MAX_ID):
		return _failure("企業身分無效。")
	# Caches created before the company capability only have the legacy fields.
	# Keep those records loadable; they cannot advertise the complete company
	# capability until the source financial fields are present.
	var has_source_state := company.has("stock_index") or company.has("stock_value") or company.has("monthly_profit") or company.has("cumulative_profit") or company.has("treasury") or company.has("company_type") or company.has("source_owner")
	if not has_source_state:
		if company.has("owner") and not _integer(company.get("owner"), 0, 255):
			return _failure("企業所有者無效。")
		if company.has("commerce_type") and not _integer(company.get("commerce_type"), 0, 255):
			return _failure("企業類型無效。")
		return {"ok": true, "error": "", "record": company, "complete": false}
	for key in ["stock_index", "company_type", "stock_value", "monthly_profit", "cumulative_profit", "treasury", "toll_fee"]:
		if not company.has(key):
			return _failure("企業缺少 %s。" % key)
	if not _integer(company.get("stock_index"), 0, STOCK_COUNT - 1):
		return _failure("企業股票索引無效。")
	if not _integer(company.get("company_type"), 0, 255):
		return _failure("企業類型無效。")
	if company.has("commerce_type") and (not _integer(company.get("commerce_type"), 0, 255) or int(company.commerce_type) != int(company.company_type)):
		return _failure("企業類型別名不一致。")
	company["commerce_type"] = int(company.company_type)
	for key in ["stock_value", "monthly_profit", "cumulative_profit", "treasury", "toll_fee"]:
		if not _integer(company.get(key), 0, 1000000000):
			return _failure("企業財務欄位無效。")
	var source_owner: Variant = company.get("source_owner", company.get("owner", null))
	if not _integer(source_owner, 0, 255):
		return _failure("企業所有者無效。")
	if company.has("owner") and (not _integer(company.get("owner"), 0, 255) or int(company.owner) != int(source_owner)):
		return _failure("企業所有者別名不一致。")
	company["source_owner"] = int(source_owner)
	company["owner"] = int(source_owner)
	if company.has("display_name") and (not company.display_name is String or company.display_name.length() > 128):
		return _failure("企業名稱無效。")
	if company.has("name_bytes_hex") and not _hex(company.get("name_bytes_hex"), 16):
		return _failure("企業名稱來源無效。")
	return {"ok": true, "error": "", "record": company, "complete": true}

static func _normalize_stock_row(value: Variant, expected_index: int) -> Dictionary:
	if not value is Dictionary:
		return _failure("股票資料無效。")
	var row: Dictionary = value.duplicate(true)
	if not _integer(row.get("index", null), expected_index, expected_index):
		return _failure("股票索引順序無效。")
	if not row.get("name") is String or row.name.is_empty() or row.name.length() > 128:
		return _failure("股票名稱無效。")
	if not _integer(row.get("company_id", null), 0, COMPANY_MAX_ID):
		return _failure("股票企業連結無效。")
	for key in ["market_supply", "turn_supply"]:
		if not _integer(row.get(key, null), 0, 10000):
			return _failure("股票供給數量無效。")
	if int(row.turn_supply) > int(row.market_supply):
		return _failure("股票本回合供給超出市場供給。")
	for key in ["base_price", "previous_price", "price"]:
		if not _number(row.get(key, null), 1.0, 9999.0):
			return _failure("股票價格無效。")
	if not _number(row.get("volatility", null), 0.0, 1000.0) or not _number(row.get("momentum", null), -10.0, 10.0) or not _number(row.get("shock", null), -100.0, 100.0):
		return _failure("股票波動欄位無效。")
	for key in ["suspension", "event"]:
		if not _integer(row.get(key, null), 0, 255):
			return _failure("股票狀態欄位無效。")
	if row.has("source_initial_link") and not _integer(row.get("source_initial_link"), 0, 65535):
		return _failure("股票來源連結欄位無效。")
	return {"ok": true, "error": "", "row": row}

static func _normalize_companies(raw_companies: Array, raw: Dictionary) -> Dictionary:
	var companies: Array = []
	var companies_by_id: Dictionary = {}
	var company_complete: Dictionary = {}
	for value in raw_companies:
		var company_result := _normalize_company_record(value)
		if not company_result.ok:
			return _failure(company_result.error)
		var company: Dictionary = company_result.record
		var company_id := int(company.id)
		if companies_by_id.has(company_id):
			return _failure("企業身分重複。")
		companies_by_id[company_id] = company
		company_complete[company_id] = bool(company_result.get("complete", false))
		companies.append(company)
	var stock_rows: Array = []
	var supports := false
	if raw.has("stock_rows"):
		if not raw.get("stock_rows") is Array or raw.stock_rows.size() != STOCK_COUNT:
			return _failure("股票資料必須有十二列。")
		for index in range(STOCK_COUNT):
			var row_result := _normalize_stock_row(raw.stock_rows[index], index)
			if not row_result.ok:
				return _failure(row_result.error)
			stock_rows.append(row_result.row)
		var consistent := not companies.is_empty()
		var seen_stock_indexes: Dictionary = {}
		for company in companies:
			var company_id := int(company.id)
			if not bool(company_complete.get(company_id, false)):
				consistent = false
				continue
			var stock_index := int(company.stock_index)
			if seen_stock_indexes.has(stock_index):
				consistent = false
			seen_stock_indexes[stock_index] = company_id
			if int(stock_rows[stock_index].company_id) != company_id:
				consistent = false
		for row in stock_rows:
			var linked_id := int(row.company_id)
			if linked_id == 0:
				continue
			if not companies_by_id.has(linked_id) or not bool(company_complete.get(linked_id, false)):
				consistent = false
				continue
			if int(companies_by_id[linked_id].stock_index) != int(row.index):
				consistent = false
		supports = consistent
	return {"ok": true, "error": "", "companies": companies, "stock_rows": stock_rows, "supports_original_companies": supports}

## Return the one canonical runtime classification for a source node.
##
## Keeping this mapping next to normalize_map means a graph save cannot change
## the observed event into a different runtime action by editing only `kind`.
static func classify_source_node(type_and_idx: Variant, event_code: Variant, original_facilities: bool = false) -> Dictionary:
	if not _integer(type_and_idx, 0, 65535) or not _integer(event_code, 0, 255):
		return {"ok": false, "kind": ""}
	var object_type := int(type_and_idx)
	var event := int(event_code)
	if object_type > 2000 and object_type < 4000:
		return {"ok": true, "kind": "property"}
	if original_facilities and object_type >= FACILITY_MIN_SOURCE_TYPE and object_type <= FACILITY_MAX_SOURCE_TYPE:
		return {"ok": true, "kind": "facility", "source_object_id": object_type - 4000}
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

static func normalize_map(raw: Variant, original_facilities: bool = false) -> Dictionary:
	if not raw is Dictionary or raw.get("schema", "") != "richman4.map/v1":
		return _failure("原版地圖格式無效。")
	if raw.get("edition") not in ["Game", "MultiverseJourney"] or not _integer(raw.get("map_number"), 1, 99):
		return _failure("原版地圖身分無效。")
	if raw.get("version") != 1 or not _hash(raw.get("payload_sha256")) or not _hash(raw.get("source_file_sha256")):
		return _failure("原版地圖來源資訊無效。")
	if not _integer(raw.get("entry_index"), 0, 999) or raw.get("archive") not in ["map.mkf", "%s/map.mkf" % raw.edition]:
		return _failure("原版地圖來源位置無效。")
	for key in ["nodes", "lands", "facilities", "companies"]:
		if not raw.get(key) is Array:
			return _failure("原版地圖缺少 %s。" % key)
	var nodes: Array = raw.nodes
	if nodes.size() < 2 or nodes.size() > 4096:
		return _failure("原版地圖節點數無效。")
	var company_result := _normalize_companies(raw.companies, raw)
	if not company_result.ok:
		return _failure(company_result.error)
	var companies: Array = company_result.companies
	var stock_rows: Array = company_result.stock_rows
	var supports_original_companies: bool = company_result.supports_original_companies
	var companies_by_id: Dictionary = {}
	for company in companies:
		companies_by_id[int(company.id)] = company
	var lands: Dictionary = {}
	var ordinary_source_housing := true
	for land in raw.lands:
		if not land is Dictionary or not _integer(land.get("id"), 1, 1999) or lands.has(int(land.id)):
			return _failure("住宅身分無效或重複。")
		if (land.has("display_name") and (not land.display_name is String or land.display_name.length() > 128)) or not land.get("name_bytes_hex") is String:
			return _failure("住宅名稱無效。")
		# The importer exposes the source +0x18 chain-store byte when it is
		# available.  Older caches predate that field and are intentionally
		# treated as ordinary housing so they remain loadable.
		if land.has("is_chain_store") and not _integer(land.get("is_chain_store"), 0, 1):
			return _failure("住宅連鎖店欄位無效。")
		if not land.has("is_chain_store") or int(land.get("is_chain_store", -1)) != 0:
			ordinary_source_housing = false
		for key in ["land_price", "house_price"]:
			if not _integer(land.get(key), 0, 1000000):
				return _failure("住宅價格無效。")
		if not land.get("rent_by_level") is Array or land.rent_by_level.size() != 6:
			return _failure("住宅租金表無效。")
		for rent in land.rent_by_level:
			if not _integer(rent, 0, 1000000):
				return _failure("住宅租金數值無效。")
		lands[int(land.id)] = land
	var facilities: Dictionary = {}
	var facility_sources: Array = []
	if original_facilities:
		for facility_value in raw.facilities:
			var facility_result := _normalize_facility_record(facility_value)
			if not facility_result.ok:
				return _failure(facility_result.error)
			var facility: Dictionary = facility_result.record
			var facility_id := int(facility.id)
			if facilities.has(facility_id):
				return _failure("設施身分無效或重複。")
			facilities[facility_id] = facility
			facility_sources.append(facility)
	var board: Array = []
	var referenced_lands: Dictionary = {}
	var referenced_facilities: Dictionary = {}
	var company_node_indexes: Dictionary = {}
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
		var status_bits: Variant = node.get("status_bits", event_code)
		if not _integer(status_bits, 0, 4294967295) or (int(status_bits) & 0xff) != event_code:
			return _failure("Invalid source node status bits.")
		var classification: Dictionary = classify_source_node(object_type, event_code, original_facilities)
		if original_facilities and object_type >= 4000 and object_type < 6000 and classification.kind != "facility":
			return _failure("設施來源參照無效。")
		var tile := {"index": index, "source_node_id": index + 1, "x": int(node.x), "y": int(node.y), "adjacent": adjacent,
			"type_and_idx": object_type, "visual_index": node.get("visual_index", 0), "event_code": event_code, "source_status_bits": int(status_bits), "source_object_id": 0,
			"kind": "rest", "name": EVENT_NAMES.get(event_code, "未知事件 %d" % event_code), "owner": -1, "building_level": 0,
			"cost": 0, "upgrade_cost": 0, "base_rent": 0, "rent": 0, "group": "", "tax_amount": 0}
		if object_type >= COMPANY_MIN_SOURCE_TYPE and object_type <= COMPANY_MAX_SOURCE_TYPE:
			var source_company_id := object_type - 6000
			tile["source_company_id"] = source_company_id
			if not company_node_indexes.has(source_company_id):
				company_node_indexes[source_company_id] = index
			tile["company_node_index"] = int(company_node_indexes[source_company_id])
			if companies_by_id.has(source_company_id):
				var company_state: Dictionary = companies_by_id[source_company_id]
				tile["company_name"] = str(company_state.get("display_name", ""))
				tile["company_state"] = company_state.duplicate(true)
		if classification.kind == "property":
			var land_id := object_type - 2000
			if not lands.has(land_id) or referenced_lands.has(land_id):
				return _failure("住宅參照缺失或重複。")
			referenced_lands[land_id] = true
			var land: Dictionary = lands[land_id]
			tile.merge({"kind": "property", "source_object_id": land_id, "name": str(land.get("display_name", "未命名住宅 %d" % land_id)),
				"cost": int(land.land_price), "land_price": int(land.land_price), "house_price": int(land.house_price),
				"upgrade_cost": int(land.house_price), "base_rent": int(land.rent_by_level[0]), "rent": int(land.rent_by_level[0]),
				"rent_by_level": land.rent_by_level.duplicate(), "group": str(land.get("name_bytes_hex", "land:%d" % land_id)),
				# A new game always starts with ordinary housing.  The source byte is
				# retained only as a capability prerequisite, never as active state.
				"is_chain_store": false}, true)
		elif classification.kind == "facility":
			var facility_id := int(classification.source_object_id)
			if not facilities.has(facility_id):
				return _failure("設施參照缺失。")
			var facility: Dictionary = facilities[facility_id]
			if not referenced_facilities.has(facility_id):
				referenced_facilities[facility_id] = index
			var facility_prices: Dictionary = facility_price_table(facility)
			if not facility_prices.ok:
				return _failure(facility_prices.error)
			var facility_name := str(facility.get("display_name", "未命名設施 %d" % facility_id))
			if facility_name.is_empty():
				facility_name = "未命名設施 %d" % facility_id
			tile.merge({"kind": "facility", "source_object_id": facility_id,
				"facility_node_index": int(referenced_facilities[facility_id]), "name": facility_name,
				"facility_type": int(facility.facility_type), "facility_state": 0,
				# Research state is runtime-owned.  Source maps only establish the
				# zeroed fields needed by a v12 save; the capability below is derived
				# from the complete v11 source chain.
				"research_tool": 0, "research_turns": 0,
				"cost": int(facility.land_price), "land_price": int(facility.land_price),
				"upgrade_cost": int(facility_prices.upgrade_cost), "fee_by_level": facility_prices.fee_by_level.duplicate(),
				"group": str(facility.get("name_bytes_hex", "facility:%d" % facility_id))}, true)
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
	if original_facilities:
		for facility_id in facilities.keys():
			if not referenced_facilities.has(facility_id):
				return _failure("設施資料未被地圖參照。")
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
	var has_hospital := false
	var has_prison := false
	for tile in board:
		has_hospital = has_hospital or int(tile.type_and_idx) == 8001
		has_prison = has_prison or int(tile.type_and_idx) == 8002
	var supports_original_statuses := original_facilities and supports_original_companies and has_hospital and has_prison
	# Property exchanges need at least two canonical source assets of one of the
	# supported categories.  Keep this capability explicit so a partial map can
	# remain loadable without advertising a selector that can never succeed.
	var supports_original_property_cards := original_facilities and supports_original_statuses and (referenced_lands.size() >= 2 or referenced_facilities.size() >= 2)
	# Remodel requires the complete v10 capability chain plus a source map whose
	# housing records passed the optional chain-byte validation above.  The
	# normalized runtime starts with every flag cleared; this capability only
	# authorizes the v11 ruleset and does not activate a source state.
	var supports_original_remodel := original_facilities and supports_original_property_cards and ordinary_source_housing
	# Research is a v12 extension of the complete v11 source contract.  Keep
	# partial and legacy caches loadable while withholding the capability marker
	# when any prerequisite source evidence is absent.
	var supports_original_research := supports_original_remodel
	# Building cards are a v13 extension of the complete v12 source contract.
	# Derive the capability from the existing research evidence so raw maps do
	# not need a second marker that could drift from the source prerequisites.
	var supports_original_building_cards := supports_original_research
	if supports_original_statuses:
		for tile in board:
			if int(tile.type_and_idx) in [8001,8002]:
				tile.name = "醫院" if int(tile.type_and_idx) == 8001 else "監獄"
	var supported := not referenced_lands.is_empty() or (original_facilities and not referenced_facilities.is_empty())
	var source := {"edition": raw.edition, "map_number": int(raw.map_number), "archive": "%s/map.mkf" % raw.edition,
		"entry_index": raw.get("entry_index", 0), "payload_sha256": raw.get("payload_sha256", ""), "source_file_sha256": raw.get("source_file_sha256", "")}
	if original_facilities:
		source["facilities"] = facility_sources.duplicate(true)
	var definition := {"schema": SCHEMA, "version": 1, "id": "%s:%d" % [raw.edition, raw.map_number],
		"name": "%s · 地圖 %d" % ["原版" if raw.edition == "Game" else "超時空之旅", raw.map_number],
		"source": source, "original_facilities": original_facilities,
		"board": board, "start_position": start_position, "supports_new_game": supported,
		"unsupported_reason": "" if supported else "此地圖沒有已支援的可購置地產，尚未開放對局。",
		"companies": companies, "stock_rows": stock_rows,
		"supports_original_companies": supports_original_companies, "supports_original_statuses": supports_original_statuses,
		"supports_original_hazards": supports_original_statuses, "supports_original_property_cards": supports_original_property_cards,
		"supports_original_remodel": supports_original_remodel, "supports_original_research": supports_original_research,
		"supports_original_building_cards": supports_original_building_cards}
	return {"ok": true, "error": "", "definition": definition}
