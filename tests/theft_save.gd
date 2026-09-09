extends SceneTree

## Issue #64 save and JSON-continuation RED seed.
##
## The save boundary stays on the existing v13 schema.  No theft-specific save
## marker or version is invented by this acceptance test.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/theft_fixture.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_empty_legal_fixture_roundtrip()
	_test_steal_roundtrip_and_continue()
	_test_rejected_request_does_not_change_save()
	print("Theft save checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func new_game(seed_value: int) -> Object:
	var game: Object = Fixture.new_game(seed_value)
	expect(game != null, "legal v13 theft save fixture starts")
	if game != null:
		expect(Game.validate_save(game.to_dict()).get("ok", false), "fresh theft save fixture validates")
	return game


func grant_card(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	expect(bool(result.get("ok", false)), "save fixture grants card %s" % card_id)
	return bool(result.get("ok", false))


func grant_tool(game: Object, player_id: int, tool_id: String, quantity: int = 1) -> bool:
	var result: Dictionary = Inventory.grant_tool(game.state["inventory_supply"], game.state["players"][player_id]["tools"], tool_id, quantity)
	expect(bool(result.get("ok", false)), "save fixture grants %s x%d" % [tool_id, quantity])
	return bool(result.get("ok", false))


func prepare(game: Object, player_id: int = 0, phase: String = "await_action") -> void:
	Fixture.prepare_action(game, player_id, phase)


func steal(game: Object, target_id: int, item_kind: String, item_id: String) -> Dictionary:
	return game.choose_action("use_card", {
		"card_id": "搶奪",
		"target_id": target_id,
		"item_kind": item_kind,
		"item_id": item_id,
	})


func _test_empty_legal_fixture_roundtrip() -> void:
	var game: Object = new_game(64101)
	if game == null:
		return
	grant_card(game, 0, "搶奪")
	grant_card(game, 1, "紅")
	prepare(game)
	var before: Dictionary = game.to_dict()
	var validation: Dictionary = Game.validate_save(before)
	expect(bool(validation.get("ok", false)), "legal theft save validates before JSON encoding")
	var encoded: String = game.to_json()
	var restored: Object = Game.from_dict(JSON.parse_string(encoded))
	expect(restored != null, "legal theft save reloads from canonical JSON")
	if restored == null:
		return
	expect_equal(restored.to_json(), encoded, "untouched theft save JSON is canonical after reload")
	expect(Game.validate_save(restored.to_dict()).get("ok", false), "untouched theft reload remains save-valid")
	expect_equal(int(restored.state.get("version", -1)), 13, "theft keeps the existing v13 save version")
	expect(not restored.state.has("theft"), "theft does not invent a save schema section")


func _test_steal_roundtrip_and_continue() -> void:
	var game: Object = new_game(64102)
	if game == null:
		return
	grant_card(game, 0, "搶奪")
	grant_card(game, 0, "搶奪")
	grant_card(game, 1, "紅")
	grant_card(game, 1, "紅")
	grant_tool(game, 1, "機器工人")
	prepare(game)
	expect(Game.validate_save(game.to_dict()).get("ok", false), "duplicate theft save validates before first action")
	var first: Dictionary = steal(game, 1, "card", "紅")
	expect(bool(first.get("ok", false)), "first theft is accepted before save")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "theft result validates before JSON reload")
	var encoded: String = game.to_json()
	var restored: Object = Game.from_dict(JSON.parse_string(encoded))
	expect(restored != null, "theft result reloads through canonical JSON")
	if restored == null:
		return
	expect_equal(restored.to_json(), encoded, "theft result JSON is canonical after reload")
	var second: Dictionary = steal(game, 1, "card", "紅")
	var restored_second: Dictionary = steal(restored, 1, "card", "紅")
	expect(bool(second.get("ok", false)) and bool(restored_second.get("ok", false)), "same duplicate theft continues on both instances")
	expect_equal(game.to_json(), restored.to_json(), "duplicate theft continuation stays deterministic after reload")
	expect_equal(game.state["players"][0]["cards"].count("紅"), 2, "continued reload action retains both stolen cards")
	expect_equal(game.state["players"][1]["cards"].count("紅"), 0, "continued reload action removes both target cards")
	expect_equal(game.state["players"][0]["cards"].count("搶奪"), 0, "continued reload action consumes both robbery cards")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "continued original theft state remains save-valid")
	expect(Game.validate_save(restored.to_dict()).get("ok", false), "continued reloaded theft state remains save-valid")
	expect(grant_card(restored, 0, "搶奪"), "reloaded actor can receive a legal robbery card for the next action")
	expect(Game.validate_save(restored.to_dict()).get("ok", false), "reloaded continuation fixture validates after restoring action card")
	var tool: Dictionary = steal(restored, 1, "tool", "機器工人")
	expect(bool(tool.get("ok", false)), "reloaded state can continue with the selected tool")
	expect_equal(int(restored.state["players"][1]["tools"].get("機器工人", 0)), 0, "continued reload tool action removes target tool")
	expect_equal(int(restored.state["players"][0]["tools"].get("機器工人", 0)), 1, "continued reload tool action grants actor tool")
	expect(Game.validate_save(restored.to_dict()).get("ok", false), "continued reload tool result remains save-valid")


func _test_rejected_request_does_not_change_save() -> void:
	var game: Object = new_game(64103)
	if game == null:
		return
	grant_card(game, 0, "搶奪")
	grant_card(game, 1, "紅")
	prepare(game)
	var before_json: String = game.to_json()
	var before_rng: int = int(game.state.get("rng_state", -1))
	var result: Dictionary = steal(game, 1, "card", "不存在")
	expect(not bool(result.get("ok", false)), "invalid selected item is rejected")
	expect_equal(game.to_json(), before_json, "invalid selected item leaves save state byte-stable")
	expect_equal(int(game.state.get("rng_state", -1)), before_rng, "invalid selected item leaves RNG unchanged")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "rejected theft state remains save-valid")
