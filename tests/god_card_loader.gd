extends SceneTree

## Issue #48 loader seed.
##
## The two cards reuse the current graph, inventory and god runtime.  This seed
## deliberately keeps the current save schema: a v13 game has no extra card
## marker or source capability.  Until the card implementation lands, the
## positive card assertions report semantic RED while the fixture checks remain
## independently visible.
const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/god_card_fixture.gd")
const RawFixture = preload("res://tests/fixtures/original_map_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")

const CURRENT_SAVE_VERSION := 13
const DISMISS_CARD := "送神符"
const SUMMON_CARD := "請神符"

var checks := 0
var failures := 0
var fixture_validation_failures := 0


func _initialize() -> void:
	_test_raw_source_does_not_gain_card_capability()
	_test_existing_god_inventory_graph_capability()
	_test_current_schema_factory_and_cards()
	_test_no_god_runtime_rejects_cards()
	_test_json_loaded_current_save_keeps_cards()
	print("Original god-card loader checks: %d, failures: %d, fixture_validation_failures: %d" % [checks, failures, fixture_validation_failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _expect_fixture(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		fixture_validation_failures += 1
		push_error("FIXTURE FAIL: " + message)


func _existing_god_inventory_options() -> Dictionary:
	# Deliberately stop at the existing god + inventory graph capabilities.  The
	# card contract must not introduce a research or building-card prerequisite.
	return {
		"original_inventory": true,
		"original_facilities": true,
		"original_gods": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	}


func _inventory_without_gods_options() -> Dictionary:
	return {
		"original_inventory": true,
		"original_facilities": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	}


func _test_raw_source_does_not_gain_card_capability() -> void:
	var loaded: Dictionary = Maps.normalize_map(RawFixture.make(), true)
	_expect_fixture(bool(loaded.get("ok", false)), "raw source fixture remains loadable")
	if not bool(loaded.get("ok", false)):
		return
	var definition: Dictionary = loaded.get("definition", {})
	_expect(not definition.has("supports_original_god_cards"), "raw normalization does not add a new god-card capability")
	_expect(not definition.has("original_god_cards"), "raw normalization does not add a god-card runtime marker")
	_expect(not bool(definition.get("supports_original_gods", false)), "incomplete raw source does not claim an existing god capability")
	_expect(not bool(definition.get("supports_original_building_cards", false)), "incomplete raw source keeps existing v13 capability withheld")


func _test_existing_god_inventory_graph_capability() -> void:
	var definition: Dictionary = Fixture.definition()
	_expect(bool(definition.get("original_facilities", false)), "fixture retains existing original facilities capability")
	_expect(bool(definition.get("supports_original_hazards", false)), "fixture retains existing hazard capability for carried bombs")
	_expect(not definition.has("supports_original_god_cards"), "fixture does not declare a new god-card capability")
	_expect(not definition.has("original_god_cards"), "fixture definition does not declare a god-card marker")
	var validation: Dictionary = Game.validate_board_definition(definition, true)
	_expect_fixture(bool(validation.get("ok", false)), "existing god and inventory graph definition validates")

	var game: Object = Game.new_game_on_board(14901, 4, definition, _existing_god_inventory_options())
	_expect_fixture(game != null, "existing god and inventory graph starts without research")
	if game == null:
		return
	_expect_equal(int(game.state.get("version", -1)), 6, "existing god and inventory graph keeps the v6 save schema")
	_expect(bool(game.state.get("original_gods", false)), "existing god capability remains active")
	_expect(typeof(game.state.get("inventory_supply", null)) == TYPE_DICTIONARY, "existing inventory capability remains active")
	_expect(not game.state.has("original_research"), "god cards do not require a research save marker")
	_expect(not game.state.has("original_building_cards"), "god cards do not require a building-card save marker")
	_expect(game.item_is_implemented("card", DISMISS_CARD), "送神符 is implemented when existing god and inventory runtime is present")
	_expect(game.item_is_implemented("card", SUMMON_CARD), "請神符 is implemented when existing god and inventory runtime is present")
	_expect_fixture(bool(Game.validate_save(game.to_dict()).get("ok", false)), "existing god and inventory graph save validates")


func _test_current_schema_factory_and_cards() -> void:
	var definition: Dictionary = Fixture.definition()
	var game: Object = Game.new_game_on_board(14902, 4, definition, Fixture.new_game_options())
	_expect_fixture(game != null, "current v13 god-card fixture starts")
	if game == null:
		return
	_expect_equal(int(game.state.get("version", -1)), CURRENT_SAVE_VERSION, "god-card fixture keeps the current v13 save schema")
	_expect(bool(game.state.get("original_gods", false)), "v13 fixture keeps existing god capability")
	_expect(typeof(game.state.get("inventory_supply", null)) == TYPE_DICTIONARY, "v13 fixture keeps existing inventory capability")
	_expect(not game.state.has("original_god_cards"), "v13 save has no god-card marker")
	_expect(not game.state.has("supports_original_god_cards"), "v13 save has no god-card capability marker")
	_expect(game.item_is_implemented("card", DISMISS_CARD), "v13 god-enabled graph advertises 送神符")
	_expect(game.item_is_implemented("card", SUMMON_CARD), "v13 god-enabled graph advertises 請神符")
	_expect_fixture(bool(Game.validate_save(game.to_dict()).get("ok", false)), "current v13 god-card fixture save validates")

	var supply: Dictionary = game.state.get("inventory_supply", {})
	var cards: Array = game.state["players"][0].get("cards", [])
	_expect(bool(Inventory.grant_card(supply, cards, DISMISS_CARD).get("ok", false)), "current v13 fixture can stage 送神符 from finite supply")
	_expect(bool(Inventory.grant_card(supply, cards, SUMMON_CARD).get("ok", false)), "current v13 fixture can stage 請神符 from finite supply")


func _test_no_god_runtime_rejects_cards() -> void:
	var definition: Dictionary = Fixture.definition()
	var game: Object = Game.new_game_on_board(14903, 4, definition, _inventory_without_gods_options())
	_expect_fixture(game != null, "inventory graph without gods remains a valid predecessor")
	if game == null:
		return
	_expect(not game.item_is_implemented("card", DISMISS_CARD), "送神符 is withheld when the existing god runtime is absent")
	_expect(not game.item_is_implemented("card", SUMMON_CARD), "請神符 is withheld when the existing god runtime is absent")
	var player: Dictionary = game.state["players"][0]
	var supply: Dictionary = game.state["inventory_supply"]
	_expect(bool(Inventory.grant_card(supply, player["cards"], DISMISS_CARD).get("ok", false)), "no-god predecessor stages 送神符 for rejection")
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = true
	game._set_action_options(0)
	var before: String = game.to_json()
	var result: Dictionary = game.choose_action("use_card", {"card_id": DISMISS_CARD})
	_expect(not bool(result.get("ok", false)), "送神符 rejects when no existing god runtime is available")
	_expect_equal(game.to_json(), before, "no-god 送神符 rejection is atomic")

	var malformed_options: Dictionary = _existing_god_inventory_options()
	malformed_options["original_gods"] = "yes"
	_expect(Game.new_game_on_board(14904, 4, definition, malformed_options) == null, "malformed existing original_gods option is rejected")


func _test_json_loaded_current_save_keeps_cards() -> void:
	var game: Object = Game.new_game_on_board(14905, 4, Fixture.definition(), Fixture.new_game_options())
	_expect_fixture(game != null, "JSON fixture starts from the current v13 factory")
	if game == null:
		return
	var parsed: Variant = JSON.parse_string(game.to_json())
	_expect_fixture(parsed is Dictionary, "current v13 save JSON parses")
	if not parsed is Dictionary:
		return
	var restored: Object = Game.from_dict(parsed)
	_expect_fixture(restored != null, "current v13 save restores through from_dict")
	if restored == null:
		return
	_expect_equal(restored.to_json(), game.to_json(), "current v13 JSON round trip remains exact")
	_expect_fixture(bool(Game.validate_save(restored.to_dict()).get("ok", false)), "JSON-restored current v13 save validates")
	_expect(restored.item_is_implemented("card", DISMISS_CARD), "JSON-loaded god-enabled game can use 送神符")
	_expect(restored.item_is_implemented("card", SUMMON_CARD), "JSON-loaded god-enabled game can use 請神符")
