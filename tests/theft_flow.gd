extends SceneTree

## Issue #64 executable RED seed for the original 搶奪 card.
##
## The fixture is deliberately assembled through the existing finite inventory
## API.  The public action assertions are expected to be RED until the runtime
## lane implements the frozen theft contract.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/theft_fixture.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_legal_fixture_and_choices()
	_test_duplicate_card_transfer()
	_test_stealing_robbery_card_preserves_first_occurrence()
	_test_zero_pool_research_tool_transfer()
	_test_zero_pool_finite_tool_transfer()
	_test_equipped_vehicle_is_not_backpack_item()
	_test_full_tool_capacity_oddity()
	_test_full_card_eviction()
	_test_invalid_empty_and_cancel_are_atomic()
	_test_ai_choice_is_deterministic_and_bounded()
	print("Theft flow checks: %d, failures: %d" % [checks, failures])
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
	expect(game != null, "legal v13 theft fixture starts")
	if game != null:
		expect(Game.validate_save(game.to_dict()).get("ok", false), "fresh theft fixture validates")
	return game


func grant_card(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	expect(bool(result.get("ok", false)), "fixture grants card %s to player %d" % [card_id, player_id])
	return bool(result.get("ok", false))


func grant_tool(game: Object, player_id: int, tool_id: String, quantity: int = 1) -> bool:
	var result: Dictionary = Inventory.grant_tool(game.state["inventory_supply"], game.state["players"][player_id]["tools"], tool_id, quantity)
	expect(bool(result.get("ok", false)), "fixture grants %s x%d to player %d" % [tool_id, quantity, player_id])
	return bool(result.get("ok", false))


func prepare(game: Object, player_id: int = 0, phase: String = "await_action") -> void:
	Fixture.prepare_action(game, player_id, phase)


func theft(game: Object, target_id: int, item_kind: String, item_id: String, cancel: bool = false) -> Dictionary:
	return game.choose_action("use_card", {
		"card_id": "搶奪",
		"target_id": target_id,
		"item_kind": item_kind,
		"item_id": item_id,
		"cancel": cancel,
	})


func expect_rejected_atomic(game: Object, params: Dictionary, label: String) -> void:
	var before_json: String = game.to_json()
	var before_rng: int = int(game.state.get("rng_state", -1))
	var result: Dictionary = game.choose_action("use_card", params)
	expect(not bool(result.get("ok", false)), label + " is rejected")
	expect_equal(game.to_json(), before_json, label + " leaves state unchanged")
	expect_equal(int(game.state.get("rng_state", -1)), before_rng, label + " leaves RNG unchanged")


func _test_legal_fixture_and_choices() -> void:
	var game: Object = new_game(64011)
	if game == null:
		return
	grant_card(game, 0, "搶奪")
	grant_card(game, 1, "紅")
	grant_tool(game, 1, "路障")
	prepare(game)
	expect(Game.validate_save(game.to_dict()).get("ok", false), "legal theft choices fixture validates before action")
	var has_choices: bool = game.has_method("theft_choices")
	expect(has_choices, "theft_choices API exists")
	if not has_choices:
		return
	var choices: Variant = game.call("theft_choices")
	expect(choices is Array, "theft_choices returns an Array")
	if choices is Array:
		var found_card: bool = false
		var found_tool: bool = false
		for value in choices:
			if not value is Dictionary:
				continue
			var choice: Dictionary = value
			expect(int(choice.get("target_id", -1)) != 0, "theft choices never expose the actor")
			if int(choice.get("target_id", -1)) == 1 and str(choice.get("item_kind", "")) == "card" and str(choice.get("item_id", "")) == "紅":
				found_card = true
			if int(choice.get("target_id", -1)) == 1 and str(choice.get("item_kind", "")) == "tool" and str(choice.get("item_id", "")) == "路障":
				found_tool = true
		expect(found_card, "theft choices expose a held target card")
		expect(found_tool, "theft choices expose a held target tool")


func _test_duplicate_card_transfer() -> void:
	var game: Object = new_game(64012)
	if game == null:
		return
	grant_card(game, 0, "搶奪")
	grant_card(game, 0, "搶奪")
	grant_card(game, 1, "紅")
	grant_card(game, 1, "紅")
	prepare(game)
	var red_supply_before: int = int(game.state["inventory_supply"]["cards"]["紅"])
	var robbery_supply_before: int = int(game.state["inventory_supply"]["cards"]["搶奪"])
	expect(Game.validate_save(game.to_dict()).get("ok", false), "duplicate card fixture validates before transfer")
	var first: Dictionary = theft(game, 1, "card", "紅")
	var second: Dictionary = theft(game, 1, "card", "紅")
	expect(bool(first.get("ok", false)), "first duplicate card theft succeeds")
	expect(bool(second.get("ok", false)), "second duplicate card theft succeeds")
	expect_equal(game.state["players"][1]["cards"].count("紅"), 0, "duplicate target cards are both removed")
	expect_equal(game.state["players"][0]["cards"].count("紅"), 2, "duplicate target cards are both received")
	expect_equal(game.state["players"][0]["cards"].count("搶奪"), 0, "one robbery card is consumed for each duplicate theft")
	expect_equal(int(game.state["inventory_supply"]["cards"]["紅"]), red_supply_before, "duplicate card transfer conserves target card pool")
	expect_equal(int(game.state["inventory_supply"]["cards"]["搶奪"]), robbery_supply_before + 2, "duplicate card transfer recycles both robbery cards")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "duplicate card transfer remains save-valid")


func _test_stealing_robbery_card_preserves_first_occurrence() -> void:
	var game: Object = new_game(64015)
	if game == null:
		return
	grant_card(game, 0, "搶奪")
	grant_card(game, 0, "免費")
	grant_card(game, 0, "搶奪")
	grant_card(game, 1, "搶奪")
	grant_card(game, 1, "搶奪")
	prepare(game)
	var robbery_supply_before: int = int(game.state["inventory_supply"]["cards"]["搶奪"])
	expect_equal(robbery_supply_before, 0, "duplicate robbery-card fixture exhausts the finite pool")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "duplicate robbery-card fixture validates before transfer")
	var result: Dictionary = theft(game, 1, "card", "搶奪")
	expect(bool(result.get("ok", false)), "stealing a robbery card succeeds")
	expect_equal(game.state["players"][1]["cards"].count("搶奪"), 1, "stealing one of two target robbery cards removes one occurrence")
	expect_equal(game.state["players"][0]["cards"], ["免費", "搶奪", "搶奪"], "robbery-card use consumes the actor's first occurrence after receipt")
	expect_equal(int(game.state["inventory_supply"]["cards"]["搶奪"]), robbery_supply_before + 1, "duplicate robbery-card transfer returns only the used action card")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "duplicate robbery-card transfer remains save-valid")


func _test_zero_pool_research_tool_transfer() -> void:
	var game: Object = new_game(64013)
	if game == null:
		return
	grant_card(game, 0, "搶奪")
	grant_tool(game, 1, "機器工人")
	prepare(game)
	var supply_before: int = int(game.state["inventory_supply"]["tools"]["機器工人"])
	expect_equal(supply_before, 0, "research tool fixture starts with zero shared pool")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "zero-pool research fixture validates before transfer")
	var result: Dictionary = theft(game, 1, "tool", "機器工人")
	expect(bool(result.get("ok", false)), "held research tool transfers despite zero shared pool")
	expect_equal(int(game.state["players"][1]["tools"].get("機器工人", 0)), 0, "research tool leaves target")
	expect_equal(int(game.state["players"][0]["tools"].get("機器工人", 0)), 1, "research tool enters actor backpack")
	expect_equal(int(game.state["inventory_supply"]["tools"]["機器工人"]), supply_before, "research tool transfer keeps shared pool at zero")
	expect_equal(game.state["players"][0]["cards"].count("搶奪"), 0, "research tool theft consumes robbery card")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "zero-pool research transfer remains save-valid")


func _test_zero_pool_finite_tool_transfer() -> void:
	var game: Object = new_game(64016)
	if game == null:
		return
	grant_card(game, 0, "搶奪")
	grant_tool(game, 1, "路障")
	grant_tool(game, 2, "路障", Inventory.TOOL_CAPACITY_PER_TYPE)
	prepare(game)
	var supply_before: int = int(game.state["inventory_supply"]["tools"]["路障"])
	expect_equal(supply_before, 0, "finite tool fixture exhausts the shared pool while target retains one")
	expect_equal(int(game.state["players"][1]["tools"].get("路障", 0)), 1, "finite tool target retains a transferable unit at pool zero")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "zero-pool finite tool fixture validates before transfer")
	var result: Dictionary = theft(game, 1, "tool", "路障")
	expect(bool(result.get("ok", false)), "held finite tool transfers despite zero shared pool")
	expect_equal(int(game.state["players"][1]["tools"].get("路障", 0)), 0, "finite tool leaves target at pool zero")
	expect_equal(int(game.state["players"][0]["tools"].get("路障", 0)), 1, "finite tool enters actor backpack at pool zero")
	expect_equal(int(game.state["inventory_supply"]["tools"]["路障"]), supply_before, "finite tool transfer keeps the exhausted shared pool conserved")
	expect_equal(game.state["players"][0]["cards"].count("搶奪"), 0, "finite tool theft consumes robbery card")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "zero-pool finite tool transfer remains save-valid")


func _test_equipped_vehicle_is_not_backpack_item() -> void:
	var game: Object = new_game(64014)
	if game == null:
		return
	grant_card(game, 0, "搶奪")
	grant_tool(game, 1, "汽車")
	prepare(game, 1, "await_roll")
	var selected: Dictionary = game.choose_action("set_vehicle", {"vehicle": "car"})
	expect(bool(selected.get("ok", false)), "vehicle fixture equips a legally held car")
	prepare(game)
	expect_equal(str(game.state["players"][1].get("vehicle", "")), "car", "target vehicle is equipped")
	expect_equal(int(game.state["players"][1]["tools"].get("汽車", 0)), 0, "equipped car is absent from target backpack")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "equipped vehicle fixture validates before theft")
	if game.has_method("theft_choices"):
		var choices: Variant = game.call("theft_choices")
		if choices is Array:
			for value in choices:
				if value is Dictionary:
					expect(not (int(value.get("target_id", -1)) == 1 and str(value.get("item_id", "")) == "汽車"), "equipped car is absent from theft choices")
	expect_rejected_atomic(game, {
		"card_id": "搶奪",
		"target_id": 1,
		"item_kind": "tool",
		"item_id": "汽車",
	}, "equipped-only vehicle theft")
	expect_equal(game.state["players"][0]["cards"].count("搶奪"), 1, "equipped-only vehicle rejection keeps robbery card")


func _test_full_tool_capacity_oddity() -> void:
	_test_full_tool_capacity_case("路障", 1, "finite tool")
	_test_full_tool_capacity_case("機器工人", 0, "research tool")


func _test_full_tool_capacity_case(tool_id: String, expected_supply_delta: int, label: String) -> void:
	var game: Object = new_game(64020 + expected_supply_delta)
	if game == null:
		return
	grant_card(game, 0, "搶奪")
	grant_tool(game, 0, tool_id, Inventory.TOOL_CAPACITY_PER_TYPE)
	grant_tool(game, 1, tool_id)
	prepare(game)
	var target_before: int = int(game.state["players"][1]["tools"].get(tool_id, 0))
	var actor_before: int = int(game.state["players"][0]["tools"].get(tool_id, 0))
	var supply_before: int = int(game.state["inventory_supply"]["tools"][tool_id])
	expect_equal(actor_before, Inventory.TOOL_CAPACITY_PER_TYPE, label + " actor reaches nine-unit capacity")
	expect_equal(target_before, 1, label + " target holds one source unit")
	expect(Game.validate_save(game.to_dict()).get("ok", false), label + " full-capacity fixture validates before transfer")
	var result: Dictionary = theft(game, 1, "tool", tool_id)
	expect(bool(result.get("ok", false)), label + " theft remains selectable at full actor capacity")
	expect_equal(int(game.state["players"][1]["tools"].get(tool_id, 0)), 0, label + " target loses one tool")
	expect_equal(int(game.state["players"][0]["tools"].get(tool_id, 0)), actor_before, label + " actor gains zero at full capacity")
	expect_equal(int(game.state["inventory_supply"]["tools"][tool_id]), supply_before + expected_supply_delta, label + " preserves original finite/research supply oddity")
	expect_equal(game.state["players"][0]["cards"].count("搶奪"), 0, label + " failed receive still consumes robbery card")
	expect(Game.validate_save(game.to_dict()).get("ok", false), label + " full-capacity result remains save-valid")


func _test_full_card_eviction() -> void:
	_test_full_card_case([
		"搶奪", "免費", "免罪", "紅", "紅", "黑", "查稅", "漲價", "查封", "同盟", "烏龜", "怪獸", "怪獸", "嫁禍", "嫁禍",
	], "搶奪", 15, "robbery card is cheapest")
	_test_full_card_case([
		"改建", "搶奪", "免費", "免罪", "紅", "紅", "黑", "查稅", "漲價", "查封", "同盟", "烏龜", "怪獸", "怪獸", "嫁禍",
	], "改建", 14, "different card is cheapest")


func _test_full_card_case(card_ids: Array, expected_evicted: String, expected_size: int, label: String) -> void:
	var game: Object = new_game(64030 + expected_size)
	if game == null:
		return
	for card_id in card_ids:
		grant_card(game, 0, str(card_id))
	grant_card(game, 1, "均富")
	prepare(game)
	var robbery_supply_before: int = int(game.state["inventory_supply"]["cards"]["搶奪"])
	var evicted_supply_before: int = int(game.state["inventory_supply"]["cards"][expected_evicted])
	var target_supply_before: int = int(game.state["inventory_supply"]["cards"]["均富"])
	expect_equal(game.state["players"][0]["cards"].size(), Inventory.CARD_CAPACITY, label + " actor starts with fifteen cards")
	expect(Game.validate_save(game.to_dict()).get("ok", false), label + " full-card fixture validates before transfer")
	var result: Dictionary = theft(game, 1, "card", "均富")
	expect(bool(result.get("ok", false)), label + " full-card theft succeeds")
	expect_equal(game.state["players"][1]["cards"].count("均富"), 0, label + " target loses the selected card")
	expect_equal(game.state["players"][0]["cards"].has("均富"), true, label + " actor receives the selected card")
	expect_equal(game.state["players"][0]["cards"].size(), expected_size, label + " preserves the source card-capacity result")
	expect_equal(game.state["players"][0]["cards"].has("搶奪"), false, label + " robbery card is absent after the action")
	expect_equal(int(game.state["inventory_supply"]["cards"][expected_evicted]), evicted_supply_before + 1, label + " evicted card returns to the pool")
	expect_equal(int(game.state["inventory_supply"]["cards"]["均富"]), target_supply_before, label + " stolen card pool is conserved")
	expect_equal(int(game.state["inventory_supply"]["cards"]["搶奪"]), robbery_supply_before + 1, label + " robbery card is recycled exactly once")
	expect(Game.validate_save(game.to_dict()).get("ok", false), label + " full-card result remains save-valid")


func _test_invalid_empty_and_cancel_are_atomic() -> void:
	var game: Object = new_game(64040)
	if game == null:
		return
	grant_card(game, 0, "搶奪")
	grant_card(game, 1, "紅")
	prepare(game)
	expect_rejected_atomic(game, {"card_id": "搶奪", "target_id": 0, "item_kind": "card", "item_id": "紅"}, "self target")
	expect_rejected_atomic(game, {"card_id": "搶奪", "target_id": 99, "item_kind": "card", "item_id": "紅"}, "missing target")
	expect_rejected_atomic(game, {"card_id": "搶奪", "target_id": 1, "item_kind": "card", "item_id": "不存在"}, "missing item")
	expect_rejected_atomic(game, {"card_id": "搶奪", "target_id": 1, "item_kind": "invalid", "item_id": "紅"}, "invalid item kind")
	expect_rejected_atomic(game, {"card_id": "搶奪", "target_id": 1, "item_kind": "card", "item_id": "紅", "cancel": true}, "cancelled theft")
	game.state["players"][1]["alive"] = false
	game.state["players"][1]["bankrupt"] = true
	prepare(game)
	expect_rejected_atomic(game, {"card_id": "搶奪", "target_id": 1, "item_kind": "card", "item_id": "紅"}, "dead target")

	var empty: Object = new_game(64041)
	if empty == null:
		return
	grant_card(empty, 0, "搶奪")
	prepare(empty)
	expect_rejected_atomic(empty, {"card_id": "搶奪", "target_id": 1, "item_kind": "card", "item_id": "紅"}, "empty target item")

	var no_card: Object = new_game(64042)
	if no_card == null:
		return
	grant_card(no_card, 1, "紅")
	prepare(no_card)
	expect_rejected_atomic(no_card, {"card_id": "搶奪", "target_id": 1, "item_kind": "card", "item_id": "紅"}, "actor without robbery card")


func _test_ai_choice_is_deterministic_and_bounded() -> void:
	var game: Object = new_game(64050)
	if game == null:
		return
	grant_card(game, 0, "搶奪")
	grant_card(game, 1, "免費")
	grant_tool(game, 0, "路障", Inventory.TOOL_CAPACITY_PER_TYPE)
	grant_tool(game, 2, "路障")
	game.state["players"][1]["points"] = 500
	game.state["players"][2]["points"] = 100
	game.state["players"][0]["cash"] = 0
	game.state["players"][0]["deposit"] = 0
	var total_deposits: int = 0
	for player in game.state["players"]:
		total_deposits += int(player.get("deposit", 0))
	game.state["bank"]["deposits"] = total_deposits
	game.state["bank_access"] = false
	game.set_player_ai(0, true)
	prepare(game)
	game.state["property_action_used"] = true
	game._set_action_options(0)
	var ai_validation: Dictionary = Game.validate_save(game.to_dict())
	expect(bool(ai_validation.get("ok", false)), "AI theft fixture validates before JSON reload")
	var before: String = game.to_json()
	var mirror: Object = Game.from_dict(JSON.parse_string(before))
	expect(mirror != null, "AI theft fixture reloads before decision")
	if mirror == null:
		return
	var first: Dictionary = game.run_ai_turn()
	var second: Dictionary = mirror.run_ai_turn()
	expect(bool(first.get("ok", false)) and bool(first.get("completed", false)), "AI theft turn reaches a terminal action")
	expect(bool(second.get("ok", false)) and bool(second.get("completed", false)), "reloaded AI theft turn reaches a terminal action")
	expect(int(first.get("iterations", 999)) <= 16, "AI theft turn respects the action iteration bound")
	expect(int(second.get("iterations", 999)) <= 16, "reloaded AI theft turn respects the action iteration bound")
	expect_equal(game.to_json(), mirror.to_json(), "AI theft choice is deterministic across JSON reload")
	expect(game.state["players"][0]["cards"].has("免費"), "AI takes the highest-price eligible card")
	expect(not game.state["players"][1]["cards"].has("免費"), "AI removes the selected card from its target")
	expect_equal(int(game.state["players"][0]["tools"].get("路障", 0)), Inventory.TOOL_CAPACITY_PER_TYPE, "AI avoids a tool when actor capacity is full")
	expect_equal(int(game.state["players"][2]["tools"].get("路障", 0)), 1, "AI leaves the full-capacity tool target untouched")
	expect_equal(int(game.state["players"][0]["cards"].count("搶奪")), 0, "AI theft consumes the robbery card")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "AI theft result remains save-valid")
