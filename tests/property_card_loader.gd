extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Base = preload("res://tests/fixtures/original_map_fixture.gd")
const Companies = preload("res://tests/fixtures/company_fixture.gd")

var checks := 0
var failures := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _complete_raw() -> Dictionary:
	var raw: Dictionary = Base.make()
	raw.nodes[0].type_and_idx = 8002
	raw.nodes[1].type_and_idx = 8001
	raw.nodes[1].event_code = 0
	raw.nodes[5].type_and_idx = 6001
	raw.nodes[5].event_code = 0
	raw.companies = Companies.definition().companies.duplicate(true)
	raw.stock_rows = Companies.stock_rows()
	return raw


func _options() -> Dictionary:
	return {
		"original_inventory": true,
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"original_statuses": true,
		"original_hazards": true,
		"original_property_cards": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	}


func _initialize() -> void:
	var raw: Dictionary = _complete_raw()
	var loaded: Dictionary = Maps.normalize_map(raw, true)
	expect(bool(loaded.get("ok", false)), "complete property-card source normalizes")
	if not bool(loaded.get("ok", false)):
		print("Property card loader checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var definition: Dictionary = loaded.get("definition", {})
	expect(bool(definition.get("supports_original_property_cards", false)), "two referenced lands advertise property cards")
	expect(typeof(definition.get("supports_original_property_cards")) == TYPE_BOOL, "property-card capability is explicitly boolean")
	expect(Game.validate_board_definition(definition, true).get("ok", false), "complete property-card definition validates")
	expect(Game.new_game_on_board(4242, 4, definition, _options()) != null, "complete property-card definition starts")
	var duplicate_source_game: Object = Game.new_game_on_board(4243, 4, definition, _options())
	expect(duplicate_source_game != null, "runtime duplicate-source guard fixture starts")
	if duplicate_source_game != null:
		duplicate_source_game.state["phase"] = "await_action"
		duplicate_source_game.state["current_player"] = 0
		duplicate_source_game.state["players"][0]["position"] = 2
		duplicate_source_game.state["players"][0]["previous_position"] = -1
		duplicate_source_game.state["board"][3]["source_object_id"] = duplicate_source_game.state["board"][2]["source_object_id"]
		Inventory.grant_card(duplicate_source_game.state["inventory_supply"], duplicate_source_game.state["players"][0]["cards"], "換地")
		duplicate_source_game._set_action_options(0)
		expect(not duplicate_source_game.inventory_target_tiles("換地").has(3), "runtime selector rejects a duplicate housing source identity")
	var duplicate_source_raw: Dictionary = _complete_raw()
	duplicate_source_raw.nodes[3].type_and_idx = 2001
	var duplicate_source_loaded: Dictionary = Maps.normalize_map(duplicate_source_raw, true)
	expect(not bool(duplicate_source_loaded.get("ok", false)), "map normalizer rejects duplicate housing source identity")

	var one_land: Dictionary = _complete_raw()
	one_land.nodes[3].type_and_idx = 0
	var one_land_loaded: Dictionary = Maps.normalize_map(one_land, true)
	expect(bool(one_land_loaded.get("ok", false)), "single-land source remains loadable")
	if bool(one_land_loaded.get("ok", false)):
		expect(not bool(one_land_loaded.definition.get("supports_original_property_cards", false)), "single referenced land does not advertise property cards")

	var missing_status: Dictionary = _complete_raw()
	missing_status.nodes[1].type_and_idx = 0
	var missing_status_loaded: Dictionary = Maps.normalize_map(missing_status, true)
	expect(bool(missing_status_loaded.get("ok", false)), "source without hospital remains loadable")
	if bool(missing_status_loaded.get("ok", false)):
		expect(not bool(missing_status_loaded.definition.get("supports_original_property_cards", false)), "incomplete status chain does not advertise property cards")

	for capability_value in ["yes", 1, {}, []]:
		var malformed: Dictionary = definition.duplicate(true)
		malformed["supports_original_property_cards"] = capability_value
		expect(not bool(Game.validate_board_definition(malformed, true).get("ok", false)), "definition rejects malformed property-card capability: " + str(capability_value))
		expect(Game.new_game_on_board(4242, 4, malformed, _options()) == null, "constructor rejects malformed property-card capability: " + str(capability_value))

	var disabled: Dictionary = definition.duplicate(true)
	disabled["supports_original_property_cards"] = false
	expect(Game.new_game_on_board(4242, 4, disabled, _options()) == null, "constructor rejects disabled property-card capability when requested")

	print("Property card loader checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
