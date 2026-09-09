extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
const Companies = preload("res://tests/fixtures/company_fixture.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_legacy_source_stays_disabled()
	_test_v11_remodel_source_contract()
	print("Original remodel loader checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _remodel_raw() -> Dictionary:
	var raw: Dictionary = Fixture.make()
	# Remodel is a runtime/save capability.  Source maps do not carry an
	# original_remodel marker, and their initial runtime state is rebuilt as an
	# empty normal house.  The raw bit is nevertheless explicit for every land.
	raw.nodes[0].type_and_idx = 8002
	raw.nodes[1].type_and_idx = 8001
	raw.nodes[1].event_code = 0
	raw.nodes[5].type_and_idx = 6001
	raw.nodes[5].event_code = 0
	raw.companies = Companies.definition().companies.duplicate(true)
	raw.stock_rows = Companies.stock_rows()
	for land_value in raw.get("lands", []):
		if typeof(land_value) != TYPE_DICTIONARY:
			continue
		var land: Dictionary = land_value
		land["is_chain_store"] = 0
	return raw


func _test_legacy_source_stays_disabled() -> void:
	var loaded: Dictionary = Maps.normalize_map(Fixture.make())
	_expect(bool(loaded.get("ok", false)), "legacy source map remains loadable")
	if not bool(loaded.get("ok", false)):
		return
	var definition: Dictionary = loaded.get("definition", {})
	_expect(not bool(definition.get("supports_original_remodel", false)), "legacy source does not advertise remodel")


func _test_v11_remodel_source_contract() -> void:
	var loaded: Dictionary = Maps.normalize_map(_remodel_raw(), true)
	_expect(bool(loaded.get("ok", false)), "complete remodel source map normalizes")
	if not bool(loaded.get("ok", false)):
		return
	var definition: Dictionary = loaded.get("definition", {})
	_expect(typeof(definition.get("supports_original_remodel", null)) == TYPE_BOOL, "remodel capability is explicitly boolean")
	_expect(bool(definition.get("supports_original_remodel", false)), "complete remodel source advertises remodel")
	var property_count: int = 0
	for tile_value in definition.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "property":
			continue
		property_count += 1
		_expect(typeof(tile_value.get("is_chain_store", null)) == TYPE_BOOL, "every normalized property has a boolean chain flag")
		_expect(not bool(tile_value.get("is_chain_store", true)), "new source properties start as normal houses")
	_expect_equal(property_count, 2, "remodel fixture keeps both housing source objects")
	_expect(bool(Game.validate_board_definition(definition, false).get("ok", false)), "remodel definition validates")

	var malformed: Dictionary = definition.duplicate(true)
	for tile_value in malformed.get("board", []):
		if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "property":
			tile_value["is_chain_store"] = "yes"
			break
	_expect(not bool(Game.validate_board_definition(malformed, false).get("ok", false)), "validator rejects a non-boolean chain flag")


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])
