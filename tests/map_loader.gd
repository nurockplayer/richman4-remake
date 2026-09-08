extends SceneTree
const Maps = preload("res://game/content/original_maps.gd")
const GameState = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func make_facility_map() -> Dictionary:
	var raw := Fixture.make()
	raw.nodes[4].type_and_idx = 4001
	raw.nodes[4].event_code = 0
	raw.nodes[5].type_and_idx = 4001
	raw.nodes[5].event_code = 0
	raw.facilities = [{"id": 1, "x": 300, "y": 400, "display_name": "測試設施",
		"name_bytes_hex": "666163696c6974790000000000000000", "facility_type": 4,
		"owner": 1, "level": 2, "tmp_state": 0x51, "land_price": 800,
		"price_per_level": 100, "reserved_hex": "c8002c019001f4015802"}]
	return raw

func _initialize() -> void:
	var raw := Fixture.make()
	var normalized := Maps.normalize_map(raw)
	expect(normalized.ok, "Synthetic source map normalizes")
	var definition: Dictionary = normalized.definition
	expect(definition.board[1].adjacent == [0, 2, 3], "Source node IDs become zero-based runtime edges")
	expect(definition.start_position == 1, "Prison endpoint is excluded from initial placement")
	expect(definition.board[2].cost == 1000 and definition.board[2].upgrade_cost == 300, "Land and house prices remain distinct")
	expect(definition.board[2].rent_by_level == raw.lands[0].rent_by_level, "Source rent table is retained")
	expect(definition.board[1].points == 50, "Known point event maps to exact value")
	expect(definition.board[4].kind == "card" and definition.board[5].kind == "bank", "Cards and bank keep distinct event kinds")
	expect(definition.board[0].kind == "unsupported", "Unimplemented prison behavior stays explicit")
	expect(definition.board[2].group == definition.board[3].group, "Same source street name keeps group identity")
	expect(definition.source.payload_sha256 == raw.payload_sha256, "Map provenance is retained")
	var legacy_classification := Maps.classify_source_node(4001, 0)
	var facility_classification := Maps.classify_source_node(4001, 0, true)
	expect(legacy_classification.kind == "unsupported", "Facility source stays legacy-unsupported by default")
	expect(facility_classification.kind == "facility" and facility_classification.source_object_id == 1, "Facility source classification is opt-in")
	var facility_raw := make_facility_map()
	var facility_result := Maps.normalize_map(facility_raw, true)
	expect(facility_result.ok, "Facility source map normalizes in opt-in mode")
	if facility_result.ok:
		var facility_definition: Dictionary = facility_result.definition
		var first_facility: Dictionary = facility_definition.board[4]
		var second_facility: Dictionary = facility_definition.board[5]
		expect(facility_definition.original_facilities, "Facility capability is retained on definition")
		expect(facility_definition.supports_new_game, "Facility-only source additions support new games")
		expect(first_facility.kind == "facility" and second_facility.kind == "facility", "Both source nodes classify as facilities")
		expect(first_facility.source_object_id == 1 and second_facility.source_object_id == 1, "Facility nodes share source identity")
		expect(first_facility.facility_node_index == 4 and second_facility.facility_node_index == 4, "Facility nodes share canonical node index")
		expect(first_facility.cost == 800 and first_facility.land_price == 800 and first_facility.upgrade_cost == 100, "Facility land and upgrade costs are distinct")
		expect(first_facility.fee_by_level == [100, 200, 300, 400, 500, 600], "Facility fee table retains all six source prices")
		expect(first_facility.facility_type == 4 and first_facility.owner == -1 and first_facility.building_level == 0 and first_facility.facility_state == 0, "New facility runtime state resets source ownership and effects")
		expect(facility_definition.source.facilities[0].level == 2 and facility_definition.source.facilities[0].tmp_state == 0x51, "Facility source metadata retains original state")
	var malformed_facility := make_facility_map()
	malformed_facility.facilities[0].reserved_hex = "bad"
	expect(not Maps.normalize_map(malformed_facility, true).ok, "Malformed facility price bytes are rejected")
	malformed_facility = make_facility_map()
	malformed_facility.facilities.append(malformed_facility.facilities[0].duplicate(true))
	expect(not Maps.normalize_map(malformed_facility, true).ok, "Duplicate facility source records are rejected")
	var missing_facility := make_facility_map()
	missing_facility.facilities = []
	expect(not Maps.normalize_map(missing_facility, true).ok, "Missing facility source reference is rejected")
	var bad_explicit_prices := make_facility_map()
	bad_explicit_prices.facilities[0].fee_by_level = [100]
	expect(not Maps.normalize_map(bad_explicit_prices, true).ok, "Facility fee table must have six entries")
	var catalog_facility := {"schema": "richman4.map-catalog/v1", "version": 1, "count": 1, "maps": [facility_raw]}
	var facility_path := "user://facility-loader-test.json"
	var facility_file := FileAccess.open(facility_path, FileAccess.WRITE)
	facility_file.store_string(JSON.stringify(catalog_facility))
	facility_file.close()
	var facility_catalog_result := Maps.load_catalog(facility_path, true)
	expect(facility_catalog_result.ok and facility_catalog_result.original_facilities, "Catalog loader propagates facility mode")
	if facility_catalog_result.ok:
		expect(facility_catalog_result.maps[0].board[4].fee_by_level == [100, 200, 300, 400, 500, 600], "Legacy facility cache reconstructs six prices")
	DirAccess.remove_absolute(facility_path)
	var unnamed := Fixture.make()
	unnamed.lands[0].erase("display_name")
	unnamed.lands[0].name_bytes_hex = "0".repeat(32)
	var unnamed_result := Maps.normalize_map(unnamed)
	expect(unnamed_result.ok and unnamed_result.definition.board[2].name == "未命名住宅 1", "Unnamed source housing stays explicit without rejecting map")
	var no_lands := Fixture.make()
	no_lands.lands = []
	no_lands.nodes[2].type_and_idx = 4001
	no_lands.nodes[3].type_and_idx = 4001
	var browse_only := Maps.normalize_map(no_lands)
	expect(browse_only.ok and not browse_only.definition.supports_new_game, "Commercial-only map remains browseable without claiming playable economy")
	for edition in ["Game", "MultiverseJourney"]:
		var direct := Fixture.make()
		direct.edition = edition
		direct.archive = "map.mkf"
		var direct_result := Maps.normalize_map(direct)
		expect(direct_result.ok, "Direct edition catalog normalizes: " + edition)
		if direct_result.ok:
			expect(direct_result.definition.source.archive == edition + "/map.mkf", "Direct edition archive has canonical runtime identity")
			var direct_game = GameState.new_game_on_board(42, 2, direct_result.definition)
			expect(direct_game != null and GameState.from_dict(direct_game.to_dict()) != null, "Direct edition map can start and reload")
	var bads: Array = []
	var bad := Fixture.make()
	bad.nodes[1].adjacent = [99]
	bads.append(bad)
	bad = Fixture.make()
	bad.nodes[1].adjacent = [1, 3, 3]
	bads.append(bad)
	bad = Fixture.make()
	bad.nodes[1].adjacent = [1, 3]
	bads.append(bad)
	bad = Fixture.make()
	bad.nodes[1].id = 9
	bads.append(bad)
	bad = Fixture.make()
	bad.nodes[3].type_and_idx = 2001
	bads.append(bad)
	bad = Fixture.make()
	bad.lands[0].rent_by_level = [100]
	bads.append(bad)
	bad = Fixture.make()
	bad.lands[0].land_price = "invalid"
	bads.append(bad)
	bad = Fixture.make()
	bad.payload_sha256 = ""
	bads.append(bad)
	bad = Fixture.make()
	bad.nodes[1].x = [123]
	bads.append(bad)
	bad = Fixture.make()
	bad.nodes[1].adjacent = [1, 4]
	bad.nodes[2].adjacent = []
	bad.nodes[4].adjacent = [4, 6]
	bads.append(bad)
	for invalid in bads:
		expect(not Maps.normalize_map(invalid).ok, "Malformed source map is rejected")
	var catalog := {"schema": "richman4.map-catalog/v1", "version": 1, "count": 1, "maps": [raw]}
	var path := "user://loader-test.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(catalog))
	file.close()
	expect(Maps.load_catalog(path).ok, "Catalog disk round trip loads")
	catalog.maps.append(raw)
	catalog.count = 2
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(catalog))
	file.close()
	expect(not Maps.load_catalog(path).ok, "Duplicate catalog map identity is rejected")
	DirAccess.remove_absolute(path)
	print("Map loader checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
