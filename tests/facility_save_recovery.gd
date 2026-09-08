extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	ui._load_map_catalog("user://facility-recovery-missing-catalog.json")
	var options: Dictionary = ui._default_setup_options(4)
	expect(ui._new_game(42, 4, ui._selected_map_definition, options), "asset-free fallback starts")
	expect(int(ui.state.version) == 4, "asset-free fallback retains nongraph inventory save")
	expect(Game.from_dict(JSON.parse_string(ui.game_state.to_json())) != null, "asset-free UI game survives JSON save and load")
	var forbidden := options.duplicate(true)
	forbidden.original_facilities = true
	expect(Game.new_game(42, 4, forbidden) == null, "classic constructor rejects graph-only facility mode")
	ui.queue_free()
	await process_frame
	var definition: Dictionary = Maps.normalize_map(Fixture.make(), true).definition
	var game = Game.new_game_on_board(42, 2, definition, {"original_facilities": true, "start_date": {"year": 1998, "month": 1, "day": 1}})
	game.roll()
	expect(game.state.phase == "await_route", "roll fixture pauses at route selection")
	var snapshot: Dictionary = JSON.parse_string(game.to_json())
	expect(bool(Game.validate_save(snapshot).ok), "unaltered pending roll snapshot validates")
	var resumed = Game.from_dict(snapshot)
	if resumed != null:
		game.run_ai_match(500)
		resumed.run_ai_match(500)
		expect(game.to_json() == resumed.to_json(), "unaltered route snapshot resumes identically")
	for changed_total in range(19):
		if changed_total == int(snapshot.last_total):
			continue
		var malformed := snapshot.duplicate(true)
		malformed.last_roll_total = changed_total
		expect(not bool(Game.validate_save(malformed).ok), "reject inconsistent preserved total %d" % changed_total)
	_test_source_prices()
	print("Facility save recovery checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func _test_source_prices() -> void:
	var raw := Fixture.make()
	raw.nodes[2].type_and_idx = 4001
	raw.nodes[3].type_and_idx = 4001
	raw.lands = []
	raw.facilities = [{"id": 1, "display_name": "Synthetic facility", "name_bytes_hex": "74657374000000000000000000000000", "facility_type": 0, "owner": 0, "level": 0, "tmp_state": 0, "land_price": 1000, "price_per_level": 300, "reserved_hex": "6400c8002c019001f401"}]
	var definition: Dictionary = Maps.normalize_map(raw, true).definition
	var game = Game.new_game_on_board(13, 2, definition, {"original_facilities": true, "start_date": {"year": 1998, "month": 1, "day": 1}})
	var snapshot: Dictionary = JSON.parse_string(game.to_json())
	expect(bool(Game.validate_save(snapshot).ok), "source-backed facility snapshot validates")
	for field in ["upgrade_cost", "land_price", "fee_by_level"]:
		var malformed := snapshot.duplicate(true)
		var bad_definition := definition.duplicate(true)
		for tile in [malformed.board[2], malformed.board[3], bad_definition.board[2], bad_definition.board[3]]:
			if field == "fee_by_level":
				tile.fee_by_level[1] += 1
			else:
				tile[field] += 1
				if field == "land_price":
					tile.cost = tile.land_price
		expect(not bool(Game.validate_save(malformed).ok), "reject shared runtime price mutation: " + field)
		expect(not bool(Game.validate_board_definition(bad_definition, true).ok), "reject source mismatch before new game: " + field)
	for mutation in ["missing", "unknown_id", "duplicate", "bad_bytes"]:
		var malformed := snapshot.duplicate(true)
		match mutation:
			"missing": malformed.map_source.erase("facilities")
			"unknown_id": malformed.map_source.facilities[0].id = 2
			"duplicate": malformed.map_source.facilities.append(malformed.map_source.facilities[0].duplicate(true))
			"bad_bytes": malformed.map_source.facilities[0].reserved_hex = "zz".repeat(10)
		expect(not bool(Game.validate_save(malformed).ok), "reject malformed retained facility source: " + mutation)
