extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")
const RawFixture = preload("res://tests/fixtures/original_map_fixture.gd")
const Companies = preload("res://tests/fixtures/company_fixture.gd")

const BUILDING_CARD_SAVE_VERSION := 13

var checks := 0
var failures := 0
var bootstrap_red := 0
var bootstrap_reported := false


func _initialize() -> void:
	_test_raw_source_capability_contract()
	_test_fixture_capability_contract()
	_test_factory_and_legacy_contract()
	_test_capability_guards()
	print("Original building-card loader checks: %d, failures: %d, bootstrap_red: %d" % [checks, failures, bootstrap_red])
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
	# This is the same complete synthetic source chain used by the v12 loader
	# seed: one facility, both status anchors, companies and ordinary housing
	# chain bytes. No original asset or raw building-card marker is introduced.
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
	_expect(bool(loaded.get("ok", false)), "complete v12 source normalizes for building cards")
	if bool(loaded.get("ok", false)):
		var definition: Dictionary = loaded.get("definition", {})
		_expect(typeof(definition.get("supports_original_research", null)) == TYPE_BOOL, "source research capability is explicitly boolean")
		_expect(bool(definition.get("supports_original_research", false)), "complete v12 source advertises research")
		_expect(typeof(definition.get("supports_original_building_cards", null)) == TYPE_BOOL, "source building-card capability is explicitly boolean")
		_expect(bool(definition.get("supports_original_building_cards", false)), "complete research source derives building-card capability")
		_expect(not definition.has("original_building_cards"), "normalized source has no raw runtime building-card marker")

	var incomplete_raw: Dictionary = _research_raw()
	incomplete_raw.lands[0].erase("is_chain_store")
	var incomplete: Dictionary = Maps.normalize_map(incomplete_raw, true)
	_expect(bool(incomplete.get("ok", false)), "incomplete source remains loadable")
	if bool(incomplete.get("ok", false)):
		_expect(not bool(incomplete.definition.get("supports_original_research", false)), "incomplete source with no chain evidence withholds research")
		_expect(not bool(incomplete.definition.get("supports_original_building_cards", false)), "incomplete source with no research capability withholds building cards")

	var legacy: Dictionary = Maps.normalize_map(RawFixture.make(), true)
	_expect(bool(legacy.get("ok", false)), "legacy source remains loadable")
	if bool(legacy.get("ok", false)):
		_expect(not bool(legacy.definition.get("supports_original_research", false)), "legacy source does not advertise research")
		_expect(not bool(legacy.definition.get("supports_original_building_cards", false)), "legacy source does not advertise building cards")


func _test_fixture_capability_contract() -> void:
	var definition: Dictionary = Fixture.definition()
	_expect(typeof(definition.get("supports_original_building_cards", null)) == TYPE_BOOL, "building-card fixture capability is explicitly boolean")
	_expect(bool(definition.get("supports_original_building_cards", false)), "building-card fixture advertises capability")
	_expect(bool(definition.get("supports_original_research", false)), "building-card fixture retains v12 prerequisite")
	_expect(not definition.has("original_building_cards"), "fixture definition has no runtime activation marker")
	_expect(bool(Game.validate_board_definition(definition, true).get("ok", false)), "complete building-card definition validates")


func _test_factory_and_legacy_contract() -> void:
	var definition: Dictionary = Fixture.definition()
	var factory_game: Object = Game.new_game_on_board(13001, 4, definition, Fixture.new_game_options())
	if factory_game == null:
		bootstrap_red += 1
		if not bootstrap_reported:
			bootstrap_reported = true
			print("BOOTSTRAP RED: v13 building-card factory is unavailable; loader seed records the v12 fallback separately")
	else:
		_expect_equal(int(factory_game.state.get("version", -1)), BUILDING_CARD_SAVE_VERSION, "building-card factory uses v13 save")
		_expect(bool(factory_game.state.get("original_building_cards", false)), "v13 save carries building-card marker")
		_expect(Game.validate_save(factory_game.to_dict()).get("ok", false), "fresh v13 building-card save validates")

	var legacy_game: Object = Game.new_game_on_board(13002, 4, definition, Fixture.v12_game_options())
	_expect(legacy_game != null, "v12 predecessor remains loadable with building-card source")
	if legacy_game != null:
		_expect_equal(int(legacy_game.state.get("version", -1)), 12, "v12 predecessor keeps save version twelve")
		_expect(not bool(legacy_game.state.get("original_building_cards", false)), "v12 predecessor does not activate building cards")
		_expect(not legacy_game.state.has("building_card_action_used"), "v12 predecessor has no building-card action marker")
		_expect(Game.validate_save(legacy_game.to_dict()).get("ok", false), "v12 predecessor save remains valid")


func _test_capability_guards() -> void:
	var definition: Dictionary = Fixture.definition()
	var options: Dictionary = Fixture.new_game_options()
	for capability_value in ["yes", 1, {}, []]:
		var malformed: Dictionary = definition.duplicate(true)
		malformed["supports_original_building_cards"] = capability_value
		_expect(not bool(Game.validate_board_definition(malformed, true).get("ok", false)), "definition rejects malformed building-card capability: " + str(capability_value))
		_expect(Game.new_game_on_board(13003, 4, malformed, options) == null, "constructor rejects malformed building-card capability: " + str(capability_value))

	var disabled: Dictionary = definition.duplicate(true)
	disabled["supports_original_building_cards"] = false
	_expect(Game.new_game_on_board(13004, 4, disabled, options) == null, "constructor rejects disabled building-card capability when requested")

	var missing_research: Dictionary = definition.duplicate(true)
	missing_research["supports_original_research"] = false
	_expect(not bool(Game.validate_board_definition(missing_research, true).get("ok", false)), "definition rejects building cards without research capability")
	_expect(Game.new_game_on_board(13005, 4, missing_research, options) == null, "constructor rejects building cards without research capability")

