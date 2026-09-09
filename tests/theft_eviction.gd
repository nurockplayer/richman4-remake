extends SceneTree

## Issue #71 executable RED seed for finite-hand 搶奪 action eviction.
##
## A full hand can evict the very 搶奪 card that opened the public action.  The
## received item must not be mistaken for a surviving action card, and a
## duplicate 搶奪 card that remains in the hand must not be consumed either.
## Every fixture is assembled through the finite inventory API.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Catalogue = preload("res://game/content/original_inventory.gd")
const Fixture = preload("res://tests/fixtures/theft_fixture.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_evicted_action_when_stolen_card_is_robbery()
	_test_evicted_action_with_duplicate_robbery_remaining()
	_test_action_not_evicted_is_consumed()
	print("Theft eviction checks: %d, failures: %d" % [checks, failures])
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
	expect(game != null, "legal v13 theft eviction fixture starts")
	if game != null:
		expect(Game.validate_save(game.to_dict()).get("ok", false), "fresh theft eviction fixture validates")
	return game


func grant_card(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	expect(bool(result.get("ok", false)), "fixture grants card %s to player %d" % [card_id, player_id])
	return bool(result.get("ok", false))


func prepare(game: Object) -> void:
	Fixture.prepare_action(game, 0, "await_action")


func theft(game: Object, target_id: int, item_id: String) -> Dictionary:
	return game.choose_action("use_card", {
		"card_id": "搶奪",
		"target_id": target_id,
		"item_kind": "card",
		"item_id": item_id,
	})


func card_supply(game: Object, card_id: String) -> int:
	return int(game.state["inventory_supply"]["cards"].get(card_id, -1))


func card_totals(game: Object) -> Dictionary:
	var totals: Dictionary = {}
	var supply: Dictionary = game.state["inventory_supply"]["cards"]
	for record_value in Catalogue.cards():
		var record: Dictionary = record_value
		var card_id: String = str(record["id"])
		var total: int = int(supply.get(card_id, 0))
		for player_value in game.state.get("players", []):
			if player_value is Dictionary:
				var player: Dictionary = player_value
				var cards: Variant = player.get("cards", [])
				if cards is Array:
					total += cards.count(card_id)
		totals[card_id] = total
	return totals


func assert_card_totals_unchanged(before: Dictionary, game: Object, label: String) -> void:
	expect_equal(card_totals(game), before, label + " preserves every finite card total")


func assert_save_roundtrip(game: Object, label: String) -> void:
	var validation: Dictionary = Game.validate_save(game.to_dict())
	expect(bool(validation.get("ok", false)), label + " remains save-valid")
	var encoded: String = game.to_json()
	var parsed: Variant = JSON.parse_string(encoded)
	expect(parsed is Dictionary, label + " emits a JSON object")
	if not parsed is Dictionary:
		return
	var restored: Object = Game.from_dict(parsed)
	expect(restored != null, label + " reloads from canonical JSON")
	if restored == null:
		return
	expect_equal(restored.to_json(), encoded, label + " JSON remains canonical after reload")
	expect(Game.validate_save(restored.to_dict()).get("ok", false), label + " reload remains save-valid")
	expect_equal(restored.state["players"][0]["cards"], game.state["players"][0]["cards"], label + " reload preserves actor hand order")
	expect_equal(restored.state["players"][1]["cards"], game.state["players"][1]["cards"], label + " reload preserves target loss")


func _test_evicted_action_when_stolen_card_is_robbery() -> void:
	var game: Object = new_game(67101)
	if game == null:
		return
	var actor_hand: Array = [
		"搶奪", "免費", "免罪", "紅", "紅", "黑", "查稅", "漲價", "查封", "同盟", "烏龜", "怪獸", "怪獸", "嫁禍", "嫁禍",
	]
	for card_id in actor_hand:
		grant_card(game, 0, str(card_id))
	grant_card(game, 1, "搶奪")
	prepare(game)
	var totals_before: Dictionary = card_totals(game)
	var robbery_supply_before: int = card_supply(game, "搶奪")
	expect_equal(game.state["players"][0]["cards"], actor_hand, "stolen-robbery fixture preserves exact fifteen-card hand order before action")
	expect_equal(game.state["players"][1]["cards"], ["搶奪"], "stolen-robbery target starts with the selected card")
	expect_equal(game.state["players"][0]["cards"].size(), Inventory.CARD_CAPACITY, "stolen-robbery actor starts at full hand capacity")
	var result: Dictionary = theft(game, 1, "搶奪")
	expect(bool(result.get("ok", false)), "stolen-robbery public choose_action succeeds")
	expect_equal(str(result.get("evicted_card_id", "")), "搶奪", "stolen-robbery action reports 搶奪 eviction")
	expect_equal(bool(result.get("robbery_consumed", true)), false, "stolen-robbery action does not consume the received card")
	expect_equal(game.state["players"][0]["cards"], [
		"免費", "免罪", "紅", "紅", "黑", "查稅", "漲價", "查封", "同盟", "烏龜", "怪獸", "怪獸", "嫁禍", "嫁禍", "搶奪",
	], "stolen-robbery action preserves exact hand order after evicting the used card")
	expect_equal(game.state["players"][1]["cards"], [], "stolen-robbery target loses exactly the selected card")
	expect_equal(game.state["players"][0]["cards"].size(), Inventory.CARD_CAPACITY, "stolen-robbery action keeps the received card in the full hand")
	expect_equal(card_supply(game, "搶奪"), robbery_supply_before + 1, "stolen-robbery recycles only the evicted action card")
	assert_card_totals_unchanged(totals_before, game, "stolen-robbery action")
	assert_save_roundtrip(game, "stolen-robbery action")


func _test_evicted_action_with_duplicate_robbery_remaining() -> void:
	var game: Object = new_game(67102)
	if game == null:
		return
	var actor_hand: Array = [
		"搶奪", "免費", "免罪", "紅", "紅", "黑", "查稅", "漲價", "查封", "同盟", "烏龜", "怪獸", "怪獸", "嫁禍", "搶奪",
	]
	for card_id in actor_hand:
		grant_card(game, 0, str(card_id))
	grant_card(game, 1, "均富")
	prepare(game)
	var totals_before: Dictionary = card_totals(game)
	var robbery_supply_before: int = card_supply(game, "搶奪")
	var target_supply_before: int = card_supply(game, "均富")
	expect_equal(game.state["players"][0]["cards"], actor_hand, "duplicate-robbery fixture preserves exact fifteen-card hand order before action")
	expect_equal(game.state["players"][1]["cards"], ["均富"], "duplicate-robbery target starts with the selected card")
	var result: Dictionary = theft(game, 1, "均富")
	expect(bool(result.get("ok", false)), "duplicate-robbery public choose_action succeeds")
	expect_equal(str(result.get("evicted_card_id", "")), "搶奪", "duplicate-robbery action reports first 搶奪 eviction")
	expect_equal(bool(result.get("robbery_consumed", true)), false, "duplicate-robbery action does not consume the surviving duplicate")
	expect_equal(game.state["players"][0]["cards"], [
		"免費", "免罪", "紅", "紅", "黑", "查稅", "漲價", "查封", "同盟", "烏龜", "怪獸", "怪獸", "嫁禍", "搶奪", "均富",
	], "duplicate-robbery action preserves exact hand order and the surviving duplicate")
	expect_equal(game.state["players"][1]["cards"], [], "duplicate-robbery target loses exactly the selected card")
	expect_equal(game.state["players"][0]["cards"].count("搶奪"), 1, "duplicate-robbery action retains the other 搶奪 card")
	expect_equal(game.state["players"][0]["cards"].size(), Inventory.CARD_CAPACITY, "duplicate-robbery action keeps fifteen cards after eviction")
	expect_equal(card_supply(game, "搶奪"), robbery_supply_before + 1, "duplicate-robbery recycles only the evicted action card")
	expect_equal(card_supply(game, "均富"), target_supply_before, "duplicate-robbery conserves the stolen card pool")
	assert_card_totals_unchanged(totals_before, game, "duplicate-robbery action")
	assert_save_roundtrip(game, "duplicate-robbery action")


func _test_action_not_evicted_is_consumed() -> void:
	var game: Object = new_game(67103)
	if game == null:
		return
	var actor_hand: Array = [
		"改建", "搶奪", "免費", "免罪", "紅", "紅", "黑", "查稅", "漲價", "查封", "同盟", "烏龜", "怪獸", "怪獸", "嫁禍",
	]
	for card_id in actor_hand:
		grant_card(game, 0, str(card_id))
	grant_card(game, 1, "均富")
	prepare(game)
	var totals_before: Dictionary = card_totals(game)
	var robbery_supply_before: int = card_supply(game, "搶奪")
	var evicted_supply_before: int = card_supply(game, "改建")
	var target_supply_before: int = card_supply(game, "均富")
	var result: Dictionary = theft(game, 1, "均富")
	expect(bool(result.get("ok", false)), "non-evicted action public choose_action succeeds")
	expect_equal(str(result.get("evicted_card_id", "")), "改建", "non-evicted action reports the non-action eviction")
	expect_equal(bool(result.get("robbery_consumed", false)), true, "non-evicted action consumes the surviving 搶奪 card")
	expect_equal(game.state["players"][0]["cards"], [
		"免費", "免罪", "紅", "紅", "黑", "查稅", "漲價", "查封", "同盟", "烏龜", "怪獸", "怪獸", "嫁禍", "均富",
	], "non-evicted action preserves exact hand order after consuming 搶奪")
	expect_equal(game.state["players"][1]["cards"], [], "non-evicted action target loses exactly the selected card")
	expect_equal(game.state["players"][0]["cards"].size(), Inventory.CARD_CAPACITY - 1, "non-evicted action leaves fourteen cards after eviction and consumption")
	expect_equal(game.state["players"][0]["cards"].has("搶奪"), false, "non-evicted action removes the used 搶奪 card")
	expect_equal(card_supply(game, "搶奪"), robbery_supply_before + 1, "non-evicted action recycles the consumed action card once")
	expect_equal(card_supply(game, "改建"), evicted_supply_before + 1, "non-evicted action recycles the evicted card")
	expect_equal(card_supply(game, "均富"), target_supply_before, "non-evicted action conserves the stolen card pool")
	assert_card_totals_unchanged(totals_before, game, "non-evicted action")
	assert_save_roundtrip(game, "non-evicted action")
