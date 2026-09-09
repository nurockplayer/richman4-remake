extends SceneTree

## Issue #69 executable RED seed for the original 冬眠／夢遊 cards.
##
## The fixture is a complete v13 graph/inventory/status game.  Inventory
## changes are staged through the finite inventory API; the sleep fields are
## only asserted after the public card action or on a save-shaped copy.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")

const BASE_SAVE_VERSION := 13
const WINTER_CARD := "冬眠"
const DREAM_CARD := "夢遊"
const IMMUNITY_CARD := "免罪"
const SCAPEGOAT_CARD := "嫁禍"
const REVENGE_CARD := "復仇"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_legal_v13_fixture_and_public_entries()
	_test_winter_card_and_status_boundaries()
	_test_dream_targets_defenses_and_atomicity()
	_test_sleep_turn_identity_and_action_gates()
	_test_dream_vehicle_storage_boundary()
	_test_god_tail_survives_dream_but_manual_actions_do_not()
	print("Sleep cards flow checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect(actual == expected, message)


func new_game(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.new_game_options())
	expect(game != null, "legal v13 sleep fixture starts")
	if game == null:
		return null
	expect_equal(int(game.state.get("version", -1)), BASE_SAVE_VERSION, "sleep fixture keeps v13 save version")
	# The complete fixture initializes six unbound gods.  Clearing them keeps
	# the card seed focused and avoids an unrelated occupied-node choice.
	game.state["god_objects"] = []
	for player_id in range(4):
		game.set_player_ai(player_id, false)
		var player: Dictionary = game.state["players"][player_id]
		player["position"] = player_id
		player["previous_position"] = -1
		player["hospital_days"] = 0
		player["prison_days"] = 0
		player["god_id"] = 0
	prepare(game, 0)
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "fresh sleep fixture validates")
	return game


func prepare(game: Object, player_id: int = 0, phase: String = "await_action", position: int = -1) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	if position >= 0:
		game.state["players"][player_id]["position"] = position
		game.state["players"][player_id]["previous_position"] = -1
	game.call("_set_action_options", player_id)


func stage_card(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	expect(bool(result.get("ok", false)), "fixture stages %s for player %d" % [card_id, player_id])
	if bool(result.get("ok", false)):
		game.call("_set_action_options", int(game.state.get("current_player", player_id)))
	return bool(result.get("ok", false))


func card_supply(game: Object, card_id: String) -> int:
	return int(game.state.get("inventory_supply", {}).get("cards", {}).get(card_id, -1))


func status_node(game: Object, kind: String) -> int:
	return int(game.call("_status_node_index", kind))


func call_dictionary(game: Object, method: String, args: Array = []) -> Dictionary:
	if not game.has_method(method):
		expect(false, method + " public API exists")
		return {}
	var value: Variant = game.callv(method, args)
	expect(value is Dictionary, method + " returns a Dictionary")
	return value if value is Dictionary else {}


func expect_rejected_atomic(game: Object, params: Dictionary, label: String) -> void:
	var before: String = game.to_json()
	var result: Dictionary = game.choose_action("use_card", params)
	expect(not bool(result.get("ok", false)), label + " is rejected")
	expect_equal(game.to_json(), before, label + " leaves state unchanged")


func _test_legal_v13_fixture_and_public_entries() -> void:
	var game: Object = new_game(69011)
	if game == null:
		return
	stage_card(game, 0, DREAM_CARD)
	stage_card(game, 0, WINTER_CARD)
	prepare(game, 0, "await_action", 1)
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "staged sleep cards preserve finite inventory conservation")
	expect(game.state["action_options"].has("use_card"), "await_action exposes the public sleep card entry")
	expect(game.item_is_implemented("card", WINTER_CARD), "winter card is admitted by public catalogue")
	expect(game.item_is_implemented("card", DREAM_CARD), "dream card is admitted by public catalogue")
	if game.has_method("dream_target_players"):
		var targets: Variant = game.call("dream_target_players", 0)
		expect(targets is Array, "dream_target_players returns an Array")
		if targets is Array:
			expect_equal(targets, [0, 1, 2, 3], "dream target list includes self and living players")
	else:
		expect(false, "dream_target_players public API exists")
	var supply_before: int = card_supply(game, DREAM_CARD)
	var result: Dictionary = game.choose_action("use_card", {"card_id": DREAM_CARD, "target_id": 0})
	expect(bool(result.get("ok", false)), "public choose_action accepts a self dream card")
	if bool(result.get("ok", false)):
		var player: Dictionary = game.state["players"][0]
		expect(not player["cards"].has(DREAM_CARD), "successful self dream consumes the held card")
		expect_equal(card_supply(game, DREAM_CARD), supply_before + 1, "self dream recycles exactly one finite card")
		expect_equal(int(player.get("dream_days", 0)), 4, "self dream uses the four-turn duration")
		expect_equal(player.get("dream_vehicle_backup", {}), {"previous_vehicle": "walking", "previous_dice_count": 1}, "walking self dream records a canonical vehicle backup")
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "self dream result remains save-valid")


func _test_winter_card_and_status_boundaries() -> void:
	var game: Object = new_game(69012)
	if game == null:
		return
	var hospital: int = status_node(game, "hospital")
	var prison: int = status_node(game, "prison")
	expect(hospital >= 0 and prison >= 0, "status fixture exposes both hospital and prison nodes")
	var hospital_player: Dictionary = game.state["players"][2]
	hospital_player["hospital_days"] = 3
	hospital_player["position"] = hospital
	hospital_player["previous_position"] = -1
	var prison_player: Dictionary = game.state["players"][3]
	prison_player["prison_days"] = 3
	prison_player["position"] = prison
	prison_player["previous_position"] = -1
	stage_card(game, 0, WINTER_CARD)
	prepare(game, 0, "await_action", 1)
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "winter status exclusion fixture validates before action")
	var supply_before: int = card_supply(game, WINTER_CARD)
	var result: Dictionary = game.choose_action("use_card", {"card_id": WINTER_CARD})
	expect(bool(result.get("ok", false)), "public choose_action accepts winter without a target")
	if not bool(result.get("ok", false)):
		return
	var ordinary: Dictionary = game.state["players"][1]
	expect_equal(int(ordinary.get("winter_sleep_days", 0)), 5, "winter admits every eligible living player for five turns")
	expect_equal(int(ordinary.get("dream_days", 0)), 0, "winter clears any ordinary dream counter")
	expect_equal(int(hospital_player.get("winter_sleep_days", 0)), 0, "winter excludes hospitalized players")
	expect_equal(int(prison_player.get("winter_sleep_days", 0)), 0, "winter excludes imprisoned players")
	expect_equal(int(hospital_player.get("hospital_days", 0)), 3, "winter preserves hospital status")
	expect_equal(int(prison_player.get("prison_days", 0)), 3, "winter preserves prison status")
	expect(not game.state["players"][0].get("winter_sleep_days", 0) > 0, "winter does not put the caster to sleep")
	expect(not game.state["players"][0]["cards"].has(WINTER_CARD), "winter consumes the held card")
	expect_equal(card_supply(game, WINTER_CARD), supply_before + 1, "winter recycles exactly one finite card")
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "winter result remains save-valid")


func _test_dream_targets_defenses_and_atomicity() -> void:
	var game: Object = new_game(69013)
	if game == null:
		return
	var hospital: int = status_node(game, "hospital")
	var prison: int = status_node(game, "prison")
	prepare(game, 0, "await_action", 1)
	game.state["players"][2]["hospital_days"] = 3
	game.state["players"][2]["position"] = hospital
	game.state["players"][2]["previous_position"] = -1
	game.state["players"][3]["prison_days"] = 3
	game.state["players"][3]["position"] = prison
	game.state["players"][3]["previous_position"] = -1
	game.state["players"][3]["prison_days"] = 0
	game.call("_charge_amount", 3, 1000000000, -1, "sleep target fixture", false)
	var target_validation: Dictionary = Game.validate_save(game.to_dict())
	if not target_validation.get("ok", false): print("TARGET_FIXTURE_ERRORS ", target_validation.get("errors", []))
	expect(bool(target_validation.get("ok", false)), "detained and bankrupt targets preserve legal fixture")
	if game.has_method("dream_target_players"):
		var targets: Variant = game.call("dream_target_players", 0)
		if targets is Array:
			expect_equal(targets, [0, 1], "dream target list excludes dead or detained players")
	stage_card(game, 0, DREAM_CARD)
	expect_rejected_atomic(game, {"card_id": DREAM_CARD, "target_id": 99}, "dream missing target")
	var before_cancel: String = game.to_json()
	var cancel: Dictionary = game.choose_action("use_card", {"card_id": DREAM_CARD, "target_id": 0, "cancel": true})
	expect(bool(cancel.get("ok", false)), "dream target cancellation succeeds")
	expect_equal(game.to_json(), before_cancel, "dream cancellation is atomic and does not consume")

	var plain: Object = new_game(69014)
	if plain != null:
		stage_card(plain, 0, DREAM_CARD)
		prepare(plain, 0, "await_action", 1)
		var plain_result: Dictionary = plain.choose_action("use_card", {"card_id": DREAM_CARD, "target_id": 1})
		expect(bool(plain_result.get("ok", false)), "dream targets another living player")
		if bool(plain_result.get("ok", false)):
			expect_equal(int(plain.state["players"][1].get("dream_days", 0)), 5, "other-player dream lasts five turns")

	var immune: Object = new_game(69015)
	if immune != null:
		stage_card(immune, 0, DREAM_CARD)
		stage_card(immune, 1, IMMUNITY_CARD)
		prepare(immune, 0, "await_action", 1)
		var immune_result: Dictionary = immune.choose_action("use_card", {"card_id": DREAM_CARD, "target_id": 1})
		expect(bool(immune_result.get("ok", false)), "immunity is checked before dream admission")
		if bool(immune_result.get("ok", false)):
			expect_equal(int(immune.state["players"][1].get("dream_days", 0)), 0, "immunity prevents dream")
			expect(not immune.state["players"][1]["cards"].has(IMMUNITY_CARD), "immunity is consumed when it blocks dream")

	var revenge: Object = new_game(69016)
	if revenge != null:
		stage_card(revenge, 0, DREAM_CARD)
		stage_card(revenge, 1, REVENGE_CARD)
		prepare(revenge, 0, "await_action", 1)
		var revenge_result: Dictionary = revenge.choose_action("use_card", {"card_id": DREAM_CARD, "target_id": 1})
		expect(bool(revenge_result.get("ok", false)), "dream resolves direct revenge without recursive defense")
		if bool(revenge_result.get("ok", false)):
			expect_equal(int(revenge.state["players"][1].get("dream_days", 0)), 5, "revenge target still receives the other-player duration")
			expect_equal(int(revenge.state["players"][0].get("dream_days", 0)), 5, "revenge puts the dream caster to sleep")
			expect(not revenge.state["players"][1]["cards"].has(REVENGE_CARD), "revenge is consumed once")

	var scapegoat: Object = new_game(69017)
	if scapegoat != null:
		stage_card(scapegoat, 0, DREAM_CARD)
		stage_card(scapegoat, 1, SCAPEGOAT_CARD)
		prepare(scapegoat, 0, "await_action", 1)
		var pending: Dictionary = scapegoat.choose_action("use_card", {"card_id": DREAM_CARD, "target_id": 1})
		expect(bool(pending.get("ok", false)), "scapegoat opens a human dream response")
		if bool(pending.get("ok", false)):
			expect(bool(pending.get("awaiting_response", false)), "dream response is explicitly pending")
			expect_equal(scapegoat.state.get("pending_trap", {}), {"caster_id": 0, "target_id": 1}, "dream reuses the existing two-key pending trap shape")
			expect_equal(str(scapegoat.state.get("pending_trap_card", "")), DREAM_CARD, "dream pending identifies its card separately")
			expect_equal(scapegoat.state.get("action_options", []), ["respond_trap"], "dream pending gates the action surface")
		expect(bool(Game.validate_save(scapegoat.to_dict()).get("ok", false)), "dream pending response remains save-valid")


func _sleep_result(game: Object) -> Dictionary:
	return call_dictionary(game, "run_sleep_turn")


func _test_sleep_turn_identity_and_action_gates() -> void:
	var game: Object = new_game(69018)
	if game == null:
		return
	stage_card(game, 0, DREAM_CARD)
	stage_card(game, 0, "紅")
	prepare(game, 0, "await_action", 1)
	var dream: Dictionary = game.choose_action("use_card", {"card_id": DREAM_CARD, "target_id": 0})
	expect(bool(dream.get("ok", false)), "sleep-turn fixture admits a human dream")
	if not bool(dream.get("ok", false)):
		return
	expect_equal(game.state["action_options"], ["end_turn"], "active dream leaves only end_turn in the current action phase")
	var human_before: String = game.to_json()
	var blocked_buy: Dictionary = game.choose_action("buy")
	expect(not bool(blocked_buy.get("ok", false)), "dream blocks manual property buy")
	expect_equal(game.to_json(), human_before, "blocked dream buy is atomic")
	var blocked_card: Dictionary = game.choose_action("use_card", {"card_id": "紅", "symbol": "tech"})
	expect(not bool(blocked_card.get("ok", false)), "dream blocks manual card use")
	expect_equal(game.to_json(), human_before, "blocked dream card use is atomic")
	var human_flags: Array = [bool(game.state["players"][0].get("is_human", false)), bool(game.state["players"][0].get("is_ai", false))]
	var handoff: Dictionary = _sleep_result(game)
	expect(bool(handoff.get("ok", false)), "run_sleep_turn handles the post-card human handoff")
	expect(int(game.state.get("current_player", 0)) != 0, "human dream handoff advances without changing identity flags")
	expect_equal([bool(game.state["players"][0].get("is_human", false)), bool(game.state["players"][0].get("is_ai", false))], human_flags, "sleep handoff preserves human identity")

	var ai_game: Object = new_game(69019)
	if ai_game == null:
		return
	ai_game.set_player_ai(0, true)
	stage_card(ai_game, 0, DREAM_CARD)
	prepare(ai_game, 0, "await_action", 1)
	var ai_card: Dictionary = ai_game.choose_action("use_card", {"card_id": DREAM_CARD, "target_id": 0})
	expect(bool(ai_card.get("ok", false)), "sleep-turn fixture admits an AI dream")
	if bool(ai_card.get("ok", false)):
		prepare(ai_game, 0, "await_roll", 1)
		var ai_flags: Array = [bool(ai_game.state["players"][0].get("is_human", false)), bool(ai_game.state["players"][0].get("is_ai", false))]
		var ai_sleep: Dictionary = _sleep_result(ai_game)
		expect(bool(ai_sleep.get("ok", false)), "run_sleep_turn handles an AI dream")
		expect_equal([bool(ai_game.state["players"][0].get("is_human", false)), bool(ai_game.state["players"][0].get("is_ai", false))], ai_flags, "AI sleep preserves AI identity")

	var ordinary: Object = new_game(69020)
	if ordinary != null:
		prepare(ordinary, 0, "await_roll", 1)
		var before: String = ordinary.to_json()
		var rejected: Dictionary = _sleep_result(ordinary)
		expect(not bool(rejected.get("ok", false)), "run_sleep_turn rejects a non-sleep actor")
		expect_equal(ordinary.to_json(), before, "non-sleep run_sleep_turn is atomic")


func _test_dream_vehicle_storage_boundary() -> void:
	var game: Object = new_game(69022)
	if game == null:
		return
	var player: Dictionary = game.state["players"][0]
	var supply: Dictionary = game.state["inventory_supply"]
	var car_tool_supply_before: int = int(supply["tools"].get("汽車", -1))
	expect(bool(Inventory.grant_tool(supply, player["tools"], "汽車").get("ok", false)), "vehicle boundary stages one car")
	prepare(game, 0, "await_roll", 1)
	var equip: Dictionary = game.set_vehicle("car", 2)
	expect(bool(equip.get("ok", false)), "vehicle boundary equips the staged car")
	expect_equal(int(player["tools"].get("汽車", 0)), 0, "equipped car leaves an empty car backpack")
	expect(bool(Inventory.grant_tool(supply, player["tools"], "汽車", 9).get("ok", false)), "vehicle boundary stages nine stored cars")
	expect_equal(int(player["tools"].get("汽車", 0)), 9, "active car holds nine stored cars before dream")
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "active car plus nine stored cars is save-valid")
	var before_ninth_grant: String = game.to_json()
	var ninth_grant: Dictionary = Inventory.grant_tool(supply, player["tools"], "汽車")
	expect(not bool(ninth_grant.get("ok", false)), "ordinary vehicle acquisition keeps the nine-unit backpack cap")
	expect_equal(game.to_json(), before_ninth_grant, "ordinary vehicle acquisition at nine is atomic")
	stage_card(game, 0, DREAM_CARD)
	prepare(game, 0, "await_action", 1)
	var dream: Dictionary = game.choose_action("use_card", {"card_id": DREAM_CARD, "target_id": 0})
	expect(bool(dream.get("ok", false)), "dream accepts the full-car storage boundary")
	if not bool(dream.get("ok", false)):
		return
	expect_equal(str(player.get("vehicle", "")), "walking", "dream returns the active car to walking")
	expect_equal(int(player["tools"].get("汽車", 0)), 10, "dream preserves nine stored plus one equipped car")
	expect_equal(player.get("dream_vehicle_backup", {}), {"previous_vehicle": "car", "previous_dice_count": 2}, "dream stores the equipped car backup")
	expect_equal(int(supply["tools"].get("汽車", -1)), car_tool_supply_before - 10, "dream does not return the equipped car to shared supply")
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "walking dream with ten stored cars is save-valid")
	var before_grant: String = game.to_json()
	var tenth: Dictionary = Inventory.grant_tool(supply, player["tools"], "汽車")
	expect(not bool(tenth.get("ok", false)), "ordinary vehicle acquisition rejects an eleventh stored car")
	expect_equal(game.to_json(), before_grant, "ordinary vehicle acquisition at ten is atomic")


func _test_god_tail_survives_dream_but_manual_actions_do_not() -> void:
	var gated: Object = new_game(69021)
	if gated == null:
		return
	var gated_property: Dictionary = gated.state["board"][2]
	gated_property["owner"] = 0
	gated_property["building_level"] = 1
	gated.call("_update_tile_rent", gated_property)
	gated.state["players"][0]["properties"] = [2]
	gated.state["players"][0]["position"] = 2
	gated.state["players"][0]["previous_position"] = -1
	gated.call("_recalculate_property_values")
	var gated_actor: Dictionary = gated.call("_spawn_god", 9)
	expect(not gated_actor.is_empty(), "god9 manual-gate fixture actor exists")
	if gated_actor.is_empty():
		return
	expect(bool(gated.call("_attach_god", 0, 9)), "god9 attaches to the manual-gate actor")
	gated.state["players"][0]["dream_days"] = 2
	gated.state["players"][0]["dream_vehicle_backup"] = {"previous_vehicle": "walking", "previous_dice_count": 1}
	prepare(gated, 0, "await_action", 2)
	expect(bool(Game.validate_save(gated.to_dict()).get("ok", false)), "god9 manual-gate sleep fixture validates")
	var gated_before: String = gated.to_json()
	var blocked_upgrade: Dictionary = gated.choose_action("upgrade")
	expect(not bool(blocked_upgrade.get("ok", false)), "dream blocks manual property upgrade")
	expect_equal(gated.to_json(), gated_before, "blocked dream upgrade is atomic")

	var game: Object = new_game(69023)
	if game == null:
		return
	# Exercise the common public end_turn landing tail.  The automatic god
	# effect must still run for a sleeping player after a real positive roll.
	var property: Dictionary = game.state["board"][2]
	property["owner"] = -1
	property["building_level"] = 1
	game.call("_update_tile_rent", property)
	game.state["players"][0]["position"] = 2
	game.state["players"][0]["previous_position"] = -1
	var actor: Dictionary = game.call("_spawn_god", 9)
	expect(not actor.is_empty(), "god9 fixture actor exists")
	if actor.is_empty():
		return
	expect(bool(game.call("_attach_god", 0, 9)), "god9 attaches to the dream actor")
	game.state["players"][0]["dream_days"] = 2
	game.state["players"][0]["dream_vehicle_backup"] = {"previous_vehicle": "walking", "previous_dice_count": 1}
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["property_action_used"] = false
	game.call("_set_action_options", 0)
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "god9 public-tail sleep fixture validates")
	var before_level: int = int(property.get("building_level", 0))
	var ended: Dictionary = game.end_turn()
	expect(bool(ended.get("ok", false)), "public end_turn completes a sleeping landing")
	expect_equal(int(property.get("building_level", 0)), before_level + 1, "dream does not suppress god9 automatic property effect")
