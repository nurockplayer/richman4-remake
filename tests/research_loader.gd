extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/research_fixture.gd")
const RawFixture = preload("res://tests/fixtures/original_map_fixture.gd")
const Companies = preload("res://tests/fixtures/company_fixture.gd")

const RESEARCH_SAVE_VERSION := 12

var checks: int = 0
var failures: int = 0
var bootstrap_red: int = 0
var bootstrap_reported: bool = false


func _initialize() -> void:
	_test_raw_source_capability_contract()
	_test_source_capability_contract()
	_test_v11_compatibility()
	_test_v12_initial_state_contract()
	_test_capability_guards()
	print("Original research loader checks: %d, failures: %d, bootstrap_red: %d" % [checks, failures, bootstrap_red])
	quit(1 if failures or bootstrap_red > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _research_raw() -> Dictionary:
	var raw: Dictionary = RawFixture.make()
	# Make the synthetic raw map complete enough to exercise the same
	# normalization path as the remodel loader: facilities, companies, status
	# anchors, and explicit ordinary-housing source bytes.
	raw.nodes[0].type_and_idx = 8002
	raw.nodes[1].type_and_idx = 4001
	raw.nodes[1].event_code = 0
	raw.nodes[4].type_and_idx = 8001
	raw.nodes[4].event_code = 0
	raw.nodes[5].type_and_idx = 6001
	raw.nodes[5].event_code = 0
	raw.companies = Companies.definition().companies.duplicate(true)
	raw.stock_rows = Companies.stock_rows()
	raw.facilities = [{
		"id": 1,
		"display_name": "測試研究所",
		"name_bytes_hex": "74657374000000000000000000000000",
		"facility_type": 0,
		"owner": 0,
		"level": 0,
		"tmp_state": 0,
		"land_price": 1000,
		"price_per_level": 300,
		"reserved_hex": "6400c8002c019001f401",
	}]
	for land_value in raw.get("lands", []):
		if typeof(land_value) == TYPE_DICTIONARY:
			land_value["is_chain_store"] = 0
	return raw


func _test_raw_source_capability_contract() -> void:
	var loaded: Dictionary = Maps.normalize_map(_research_raw(), true)
	_expect(bool(loaded.get("ok", false)), "complete raw research source normalizes")
	if bool(loaded.get("ok", false)):
		var definition: Dictionary = loaded.get("definition", {})
		_expect(typeof(definition.get("supports_original_research", null)) == TYPE_BOOL, "normalized research capability is explicitly boolean")
		_expect(bool(definition.get("supports_original_research", false)), "complete raw source advertises research")
		_expect(not definition.has("original_research"), "normalized source has no runtime research marker")
		var facility_count := 0
		for tile_value in definition.get("board", []):
			if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility":
				continue
			facility_count += 1
			_expect_equal(int(tile_value.get("research_tool", -1)), 0, "normalized facility starts with empty research product")
			_expect_equal(int(tile_value.get("research_turns", -1)), 0, "normalized facility starts with empty research countdown")
			_expect_equal(int(tile_value.get("facility_type", -1)), 0, "normalized facility retains source facility type")
		_expect(facility_count > 0, "normalized research source contains a facility")

	var legacy: Dictionary = Maps.normalize_map(RawFixture.make(), true)
	_expect(bool(legacy.get("ok", false)), "legacy raw source remains loadable")
	if bool(legacy.get("ok", false)):
		_expect(not bool(legacy.definition.get("supports_original_research", false)), "legacy raw source does not advertise research")

	var incomplete_raw: Dictionary = _research_raw()
	incomplete_raw.lands[0].erase("is_chain_store")
	var incomplete: Dictionary = Maps.normalize_map(incomplete_raw, true)
	_expect(bool(incomplete.get("ok", false)), "incomplete raw source remains loadable")
	if bool(incomplete.get("ok", false)):
		_expect(not bool(incomplete.definition.get("supports_original_research", false)), "incomplete raw source does not advertise research")


func _new_research_game(seed_value: int) -> Object:
	var definition: Dictionary = Fixture.definition()
	var game: Object = Game.new_game_on_board(seed_value, 4, definition, Fixture.new_game_options())
	if game != null:
		return game
	bootstrap_red += 1
	if not bootstrap_reported:
		bootstrap_reported = true
		print("BOOTSTRAP RED: v12 research factory is unavailable; loader checks use a locally stamped v12 fallback")
	var legacy: Object = Game.new_game_on_board(seed_value, 4, definition, Fixture.v11_game_options())
	_expect(legacy != null, "v11 fixture bootstraps the v12 loader harness")
	if legacy == null:
		return null
	legacy.state["version"] = RESEARCH_SAVE_VERSION
	legacy.state["original_research"] = true
	legacy.state["research_action_used"] = false
	for tile_value in legacy.state.get("board", []):
		if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "facility":
			tile_value["research_tool"] = 0
			tile_value["research_turns"] = 0
	return legacy


func _test_source_capability_contract() -> void:
	var definition: Dictionary = Fixture.definition()
	_expect(typeof(definition.get("supports_original_research", null)) == TYPE_BOOL, "research source capability is explicitly boolean")
	_expect(bool(definition.get("supports_original_research", false)), "complete v11 source capability advertises research")
	_expect(not definition.has("original_research"), "source definition does not carry a runtime research activation marker")
	_expect(bool(definition.get("supports_original_remodel", false)), "research capability inherits the complete remodel prerequisite")
	_expect(bool(definition.get("supports_original_property_cards", false)), "research capability inherits the complete property-card prerequisite")
	var facility_count := 0
	for tile_value in definition.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility":
			continue
		facility_count += 1
		_expect(typeof(tile_value.get("research_tool", null)) == TYPE_INT, "source facility carries an integer research rank")
		_expect(typeof(tile_value.get("research_turns", null)) == TYPE_INT, "source facility carries an integer research countdown")
		_expect_equal(int(tile_value.get("research_tool", -1)), 0, "source facility starts without a research product")
		_expect_equal(int(tile_value.get("research_turns", -1)), 0, "source facility starts without a research countdown")
	_expect(facility_count > 0, "research source fixture contains facilities")
	_expect(bool(Game.validate_board_definition(definition, true).get("ok", false)), "complete research definition validates")


func _test_v11_compatibility() -> void:
	var definition: Dictionary = Fixture.definition()
	var legacy: Object = Game.new_game_on_board(9101, 4, definition, Fixture.v11_game_options())
	_expect(legacy != null, "v11 predecessor fixture remains loadable")
	if legacy == null:
		return
	_expect_equal(int(legacy.state.get("version", -1)), 11, "v11 predecessor keeps save version eleven")
	_expect(not bool(legacy.state.get("original_research", false)), "v11 predecessor does not activate research")
	_expect(not legacy.state.has("research_action_used"), "v11 predecessor has no research action marker")


func _test_v12_initial_state_contract() -> void:
	var game: Object = _new_research_game(9102)
	_expect(game != null, "v12 research fixture starts")
	if game == null:
		return
	_expect_equal(int(game.state.get("version", -1)), RESEARCH_SAVE_VERSION, "research setup uses v12 save")
	_expect(bool(game.state.get("original_research", false)), "v12 save carries research marker")
	_expect(typeof(game.state.get("research_action_used", null)) == TYPE_BOOL, "v12 save carries research action boolean")
	_expect(not bool(game.state.get("research_action_used", true)), "fresh v12 save has no research action used")
	for prerequisite in ["original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards", "original_property_cards", "original_remodel"]:
		_expect(bool(game.state.get(prerequisite, false)), "v12 save carries prerequisite marker: " + prerequisite)
	for tile_value in game.state.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility":
			continue
		_expect(typeof(tile_value.get("research_tool", null)) == TYPE_INT, "fresh v12 facility research rank is serialized")
		_expect(typeof(tile_value.get("research_turns", null)) == TYPE_INT, "fresh v12 facility research countdown is serialized")
		_expect_equal(int(tile_value.get("research_tool", -1)), 0, "fresh v12 facility research rank starts at zero")
		_expect_equal(int(tile_value.get("research_turns", -1)), 0, "fresh v12 facility research countdown starts at zero")


func _test_capability_guards() -> void:
	var valid_definition: Dictionary = Fixture.definition()
	var valid_options: Dictionary = Fixture.new_game_options()
	for capability_value in ["yes", 1, {}, []]:
		var malformed: Dictionary = valid_definition.duplicate(true)
		malformed["supports_original_research"] = capability_value
		_expect(not bool(Game.validate_board_definition(malformed, true).get("ok", false)), "definition rejects malformed research capability: " + str(capability_value))
		_expect(Game.new_game_on_board(9103, 4, malformed, valid_options) == null, "constructor rejects malformed research capability: " + str(capability_value))

	var disabled: Dictionary = valid_definition.duplicate(true)
	disabled["supports_original_research"] = false
	_expect(Game.new_game_on_board(9104, 4, disabled, valid_options) == null, "constructor rejects disabled research capability when requested")

	var missing_remodel: Dictionary = valid_definition.duplicate(true)
	missing_remodel["supports_original_remodel"] = false
	_expect(not bool(Game.validate_board_definition(missing_remodel, true).get("ok", false)), "definition rejects research without remodel capability")
	_expect(Game.new_game_on_board(9105, 4, missing_remodel, valid_options) == null, "constructor rejects research without remodel capability")

	var missing_property_cards: Dictionary = valid_definition.duplicate(true)
	missing_property_cards["supports_original_property_cards"] = false
	_expect(not bool(Game.validate_board_definition(missing_property_cards, true).get("ok", false)), "definition rejects research without property-card capability")
	_expect(Game.new_game_on_board(9106, 4, missing_property_cards, valid_options) == null, "constructor rejects research without property-card capability")

	var missing_v11_flag: Dictionary = valid_options.duplicate(true)
	missing_v11_flag.erase("original_hazards")
	_expect(Game.new_game_on_board(9107, 4, valid_definition, missing_v11_flag) == null, "constructor rejects research without the complete v11 option chain")
