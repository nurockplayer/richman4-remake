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
