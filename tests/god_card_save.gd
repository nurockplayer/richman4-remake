extends SceneTree

## Issue #48 pure acceptance seed for the existing 送神符／請神符 save path.
##
## The fixture is an existing v13 graph/inventory/god game. God-card effects
## must therefore use the current save schema directly, with no card-specific
## version, marker, or migration branch.
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/god_card_fixture.gd")

const BASE_SAVE_VERSION := 13
const DISMISS_CARD := "送神符"
const SUMMON_CARD := "請神符"
const SAVE_PREREQUISITES := [
	"original_building_cards",
	"original_facilities",
	"original_gods",
	"original_companies",
	"original_statuses",
	"original_hazards",
	"original_property_cards",
	"original_remodel",
	"original_research",
]
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	_test_effect_save_round_trip_and_continuation()
	_test_existing_schema_and_capability_boundary()
	_test_strict_existing_markers_and_prerequisites()
	print("Original god-card save checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_game(seed_value: int, player_count: int = 3) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, Fixture.definition(), Fixture.new_game_options())
	_expect(game != null, "existing v13 god fixture starts")
	if game != null:
		_expect_equal(int(game.state.get("version", -1)), BASE_SAVE_VERSION, "existing god fixture keeps the v13 save schema")
	return game


func _new_game_without_gods(seed_value: int, player_count: int = 3) -> Object:
	var options: Dictionary = Fixture.new_game_options()
	for prerequisite in ["original_gods", "original_companies", "original_statuses", "original_hazards", "original_property_cards", "original_remodel", "original_research", "original_building_cards"]:
		options.erase(prerequisite)
	var game: Object = Game.new_game_on_board(seed_value, player_count, Fixture.definition(), options)
	_expect(game != null, "fixture without the existing god capability starts")
	return game


func _prepare_action(game: Object, player_id: int, position: int) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	var players: Array = game.state.get("players", [])
	if player_id < 0 or player_id >= players.size():
		return
	var player: Dictionary = players[player_id]
	player["position"] = position
	player["previous_position"] = -1
	player["hospital_days"] = 0
	player["prison_days"] = 0
	game.call("_set_action_options", player_id)


func _prepare_non_action_turn(game: Object, player_id: int) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = "await_action"
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.call("_set_action_options", player_id)


func _stage_card(game: Object, player_id: int, card_id: String) -> bool:
	var players: Array = game.state.get("players", [])
	if player_id < 0 or player_id >= players.size():
		_expect(false, "save fixture has player for " + card_id)
		return false
	var player: Dictionary = players[player_id]
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], player["cards"], card_id)
	_expect(bool(result.get("ok", false)), "save fixture stages " + card_id)
	if bool(result.get("ok", false)):
		game.call("_set_action_options", player_id)
	return bool(result.get("ok", false))


func _clear_actor_ownership(game: Object) -> void:
	# Positive save fixtures must never carry the -1 node sentinel. Rebuild the
	# small set of actors needed by each case instead of leaving free actors in
	# an invalid source location.
	game.state["god_objects"] = []
	for player_value in game.state.get("players", []):
		if typeof(player_value) == TYPE_DICTIONARY:
			player_value["god_id"] = 0


func _ensure_actor(game: Object, god_id: int, node: int = -1) -> Dictionary:
	var actor: Dictionary = game.call("_god_object", god_id)
	if actor.is_empty():
		var objects: Array = game.state.get("god_objects", [])
		actor = {"id": god_id, "node": node, "owner": -1, "days": 0}
		objects.append(actor)
		game.state["god_objects"] = objects
	actor["id"] = god_id
	actor["node"] = node
	actor["owner"] = -1
	actor["days"] = 0
	return actor


func _remove_actor(game: Object, god_id: int) -> void:
	if game.has_method("_remove_god"):
		game.call("_remove_god", god_id)
		return
	var objects: Array = game.state.get("god_objects", [])
	for index in range(objects.size() - 1, -1, -1):
		if typeof(objects[index]) == TYPE_DICTIONARY and int(objects[index].get("id", -1)) == god_id:
			objects.remove_at(index)


func _set_owned_god(game: Object, player_id: int, god_id: int, node: int) -> void:
	var owner: Dictionary = game.state["players"][player_id]
	_expect_equal(int(owner.get("position", -1)), node, "owned god fixture node follows its player")
	var actor: Dictionary = _ensure_actor(game, god_id, node)
	actor["owner"] = player_id
	actor["node"] = node
	actor["days"] = 7
	game.state["players"][player_id]["god_id"] = god_id


func _set_carried_bomb(game: Object, player_id: int, steps: int) -> void:
	var player: Dictionary = game.state["players"][player_id]
	player["bomb_steps"] = steps
	player["tools"].erase("定時炸彈")


func _set_ground_bomb(game: Object, node_id: int, placer_id: int) -> void:
	var occupied: Dictionary = {}
	for player_value in game.state.get("players", []):
		if typeof(player_value) == TYPE_DICTIONARY:
			occupied[int(player_value.get("position", -1))] = true
	for actor_value in game.state.get("god_objects", []):
		if typeof(actor_value) == TYPE_DICTIONARY:
			occupied[int(actor_value.get("node", -1))] = true
	_expect(not occupied.has(node_id), "ground bomb node is free of players and gods")
	game.state["ground_hazards"] = {str(node_id): {"kind": "timed_bomb", "placer_id": placer_id}}
	var supply: Dictionary = game.state["inventory_supply"]["tools"]
	_expect(int(supply.get("定時炸彈", 0)) > 0, "ground bomb has a finite source slot")
	# The ground bomb is the extra finite object in this fixture; reserve it
	# from the shared pool while the carried bomb consumes player 0's held unit.
	supply["定時炸彈"] = int(supply.get("定時炸彈", 0)) - 1


func _expect_v13_snapshot_valid(game: Object, label: String) -> void:
	var snapshot: Dictionary = game.to_dict()
	var validation: Dictionary = Game.validate_save(snapshot)
	_expect(bool(validation.get("ok", false)), label + " positive fixture is valid at the v13 save boundary: " + str(validation.get("errors", [])))


func _card_supply(game: Object, card_id: String) -> int:
	var supply: Variant = game.state.get("inventory_supply", {})
	if typeof(supply) != TYPE_DICTIONARY or typeof(supply.get("cards", null)) != TYPE_DICTIONARY:
		return -1
	return int(supply["cards"].get(card_id, -1))


func _tool_supply(game: Object, tool_id: String) -> int:
	var supply: Variant = game.state.get("inventory_supply", {})
	if typeof(supply) != TYPE_DICTIONARY or typeof(supply.get("tools", null)) != TYPE_DICTIONARY:
		return -1
	return int(supply["tools"].get(tool_id, -1))


func _cash_deposit_snapshot(game: Object) -> Array:
	var result: Array = []
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = player_value
		result.append([int(player.get("cash", 0)), int(player.get("deposit", 0))])
	return result


func _last_card_event(game: Object, card_id: String) -> Dictionary:
	var event_log: Variant = game.state.get("event_log", [])
	if typeof(event_log) != TYPE_ARRAY:
		return {}
	for index in range(event_log.size() - 1, -1, -1):
		if typeof(event_log[index]) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_log[index]
		if str(event.get("type", "")) == "card_used" and str(event.get("card_id", "")) == card_id:
			return event
	return {}


func _test_effect_save_round_trip_and_continuation() -> void:
	var game: Object = _new_game(49001)
	_expect(game != null, "existing v13 god-card save fixture starts")
	if game == null:
		return
	for prerequisite in SAVE_PREREQUISITES:
		_expect(bool(game.state.get(prerequisite, false)), "v13 save carries prerequisite marker: " + prerequisite)

	_clear_actor_ownership(game)
	_prepare_action(game, 0, 1)
	_set_owned_god(game, 0, 5, 1)
	_remove_actor(game, 6)
	var player0: Dictionary = game.state["players"][0]
	var player1: Dictionary = game.state["players"][1]
	_set_carried_bomb(game, 0, 8)
	player1["bomb_steps"] = 0
	_set_ground_bomb(game, 2, 1)
	var ground_before: Dictionary = game.state["ground_hazards"].duplicate(true)
	var cash_before: Array = _cash_deposit_snapshot(game)
	_expect_v13_snapshot_valid(game, "送神符 save effect")
	var card_supply_before: int = _card_supply(game, DISMISS_CARD)
	var bomb_supply_before: int = _tool_supply(game, "定時炸彈")
	if not _stage_card(game, 0, DISMISS_CARD):
		return
	var result: Dictionary = game.choose_action("use_card", {"card_id": DISMISS_CARD})
	_expect(bool(result.get("ok", false)), "送神符 reaches the existing v13 save boundary")
	_expect_equal(int(player0.get("god_id", -1)), 0, "save state clears the dismissed god")
	_expect_equal(int(player0.get("bomb_steps", -1)), 0, "save state clears the carried bomb")
	_expect_equal(int(game.state["players"][1].get("bomb_steps", -1)), 0, "save state preserves another player's bomb state")
	_expect_equal(game.state.get("ground_hazards", {}), ground_before, "save state preserves ground bombs")
	_expect_equal(_cash_deposit_snapshot(game), cash_before, "god cards do not invent cash transfers")
	_expect_equal(_card_supply(game, DISMISS_CARD), card_supply_before, "save records one consumed and recycled card")
	_expect_equal(_tool_supply(game, "定時炸彈"), bomb_supply_before + 1, "save records the returned carried-bomb slot")

	var data: Dictionary = game.to_dict()
	var last_event: Dictionary = _last_card_event(game, DISMISS_CARD)
	_expect_equal(str(last_event.get("type", "")), "card_used", "save retains the card event")
	_expect_equal(str(last_event.get("card_id", "")), DISMISS_CARD, "save retains the card identifier")
	_expect_equal(int(data.get("version", -1)), BASE_SAVE_VERSION, "god-card effect keeps the v13 save version")
	var baseline_keys: Array = _new_game(49006).to_dict().keys()
	baseline_keys.sort()
	var effect_keys: Array = data.keys()
	effect_keys.sort()
	_expect_equal(effect_keys, baseline_keys, "god-card effect does not add save fields")
	var validation: Dictionary = Game.validate_save(data)
	_expect(bool(validation.get("ok", false)), "valid god-card save validates: " + str(validation.get("errors", [])))
	var parsed: Variant = JSON.parse_string(game.to_json())
	_expect(parsed is Dictionary, "god-card save JSON parses")
	var restored: Object = Game.from_dict(parsed if parsed is Dictionary else {})
	_expect(restored != null, "god-card save restores through from_dict")
	if restored == null:
		return
	_expect_equal(restored.to_json(), game.to_json(), "god-card JSON round trip is exact")
	_expect_equal(restored.to_dict().get("god_objects", []), data.get("god_objects", []), "restored god objects retain ownership and days")
	_expect_equal(restored.to_dict().get("ground_hazards", {}), data.get("ground_hazards", {}), "restored ground hazards retain their owner")
	_prepare_non_action_turn(game, 0)
	_prepare_non_action_turn(restored, 0)
	var original_turn: Dictionary = game.end_turn()
	var restored_turn: Dictionary = restored.end_turn()
	_expect(bool(original_turn.get("ok", false)) and bool(restored_turn.get("ok", false)), "restored save continues through public end_turn")
	_expect_equal(restored.to_json(), game.to_json(), "save continuation remains deterministic")


func _test_existing_schema_and_capability_boundary() -> void:
	var game: Object = _new_game(49002)
	_expect(game != null, "existing v13 schema fixture starts")
	if game == null:
		return
	_expect_equal(int(game.state.get("version", -1)), BASE_SAVE_VERSION, "existing save remains version thirteen")
	_expect(bool(game.state.get("original_gods", false)), "existing save exposes the god runtime")
	_expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "clean existing save remains valid")
	for card_id in [DISMISS_CARD, SUMMON_CARD]:
		_expect(game.item_is_implemented("card", card_id), "existing god runtime advertises " + card_id)

	var without_gods: Object = _new_game_without_gods(49003)
	if without_gods == null:
		return
	_expect(not bool(without_gods.state.get("original_gods", false)), "god-less save omits the existing god runtime")
	_expect(bool(Game.validate_save(without_gods.to_dict()).get("ok", false)), "god-less save remains valid")
	for card_id in [DISMISS_CARD, SUMMON_CARD]:
		_expect(not without_gods.item_is_implemented("card", card_id), "god-less save refuses " + card_id)
		_prepare_action(without_gods, 0, 1)
		if _stage_card(without_gods, 0, card_id):
			var before: String = without_gods.to_json()
			var result: Dictionary = without_gods.choose_action("use_card", {"card_id": card_id})
			_expect(not bool(result.get("ok", false)), "god-less save rejects " + card_id)
			_expect_equal(without_gods.to_json(), before, "god-less rejection is atomic for " + card_id)


func _test_strict_existing_markers_and_prerequisites() -> void:
	var game: Object = _new_game(49004)
	_expect(game != null, "strict existing save fixture starts")
	if game == null:
		return
	var valid: Dictionary = game.to_dict()
	_expect(bool(Game.validate_save(valid).get("ok", false)), "strict fixture starts valid")
	for prerequisite in SAVE_PREREQUISITES:
		var malformed: Dictionary = valid.duplicate(true)
		malformed[prerequisite] = false
		_expect(not bool(Game.validate_save(malformed).get("ok", false)), "strict save rejects false prerequisite marker: " + prerequisite)
		_expect(Game.from_dict(malformed) == null, "strict save rejects false prerequisite JSON: " + prerequisite)
		var missing: Dictionary = valid.duplicate(true)
		missing.erase(prerequisite)
		_expect(not bool(Game.validate_save(missing).get("ok", false)), "strict save rejects missing prerequisite marker: " + prerequisite)
		_expect(Game.from_dict(missing) == null, "strict save rejects missing prerequisite JSON: " + prerequisite)
	var wrong_version: Dictionary = valid.duplicate(true)
	wrong_version["version"] = BASE_SAVE_VERSION - 1
	_expect(not bool(Game.validate_save(wrong_version).get("ok", false)), "strict save rejects a stale version with current state fields")
	_expect(Game.from_dict(wrong_version) == null, "strict save rejects stale-version JSON")
