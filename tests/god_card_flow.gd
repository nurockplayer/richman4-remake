extends SceneTree

## Issue #48 pure acceptance seed for the original 送神符／請神符 cards.
##
## The fixture is an existing v13 graph/inventory/god game.  The cards are
## deliberately exercised through that state directly: no card-specific save
## version or source capability is invented by this acceptance seed.
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/god_card_fixture.gd")

const BASE_SAVE_VERSION := 13
const DISMISS_CARD := "送神符"
const SUMMON_CARD := "請神符"
const BAD_GOD_IDS := [5, 6, 7, 8, 10]
const PRESERVED_GOD_IDS := [1, 2, 3, 4, 9, 12]
const GOD_DAYS := 7
const MAX_GOD_DISTANCE := 10000

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_fixture_and_capability_boundary()
	_test_dismiss_bad_gods_and_carried_bomb()
	_test_dismiss_preserves_good_gods_and_no_effect()
	_test_summon_nearest_tie_visibility_and_replacement()
	_test_phase_cancel_remote_and_invalid_atomicity()
	print("Original god-card flow checks: %d, failures: %d" % [checks, failures])
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


func _prepare_action(game: Object, player_id: int, position: int, phase: String = "await_action") -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
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


func _stage_card(game: Object, player_id: int, card_id: String) -> bool:
	var players: Array = game.state.get("players", [])
	if player_id < 0 or player_id >= players.size():
		_expect(false, "card staging player exists: " + card_id)
		return false
	var player: Dictionary = players[player_id]
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], player["cards"], card_id)
	_expect(bool(result.get("ok", false)), "fixture stages " + card_id)
	if bool(result.get("ok", false)):
		game.call("_set_action_options", player_id)
	return bool(result.get("ok", false))


func _use_card(game: Object, card_id: String, extras: Dictionary = {}) -> Dictionary:
	var params: Dictionary = {"card_id": card_id}
	params.merge(extras, true)
	return game.choose_action("use_card", params)


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


func _event_has_id(value: Variant, expected_id: int) -> bool:
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			if typeof(entry) in [TYPE_INT, TYPE_FLOAT] and int(entry) == expected_id:
				return true
			if typeof(entry) == TYPE_DICTIONARY and int(entry.get("id", entry.get("god_id", -1))) == expected_id:
				return true
	return false


func _event_has_god(event: Dictionary, god_id: int) -> bool:
	for key in ["god_id", "summoned_god_id", "dismissed_god_id"]:
		if typeof(event.get(key, null)) in [TYPE_INT, TYPE_FLOAT] and int(event.get(key, -1)) == god_id:
			return true
	for key in ["god_ids", "removed_god_ids", "dismissed_god_ids", "removed_gods", "dismissed_gods"]:
		if _event_has_id(event.get(key, null), god_id):
			return true
	return false


func _event_bomb_cleared(event: Dictionary) -> bool:
	for key in ["bomb_cleared", "carried_bomb_cleared"]:
		if typeof(event.get(key, null)) == TYPE_BOOL and bool(event.get(key, false)):
			return true
	var remaining_value: Variant = event.get("bomb_remaining", event.get("remaining_bomb_steps", null))
	if typeof(remaining_value) in [TYPE_INT, TYPE_FLOAT] and int(remaining_value) == 0:
		return true
	return str(event.get("effect", "")).contains("bomb")


func _last_card_event(game: Object, card_id: String) -> Dictionary:
	var last_event: Variant = game.state.get("last_event", {})
	if typeof(last_event) == TYPE_DICTIONARY and str(last_event.get("type", "")) == "card_used" and str(last_event.get("card_id", "")) == card_id:
		return last_event
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


func _assert_successful_card(game: Object, player_id: int, card_id: String, card_supply_before: int, label: String) -> void:
	_expect_equal(_card_supply(game, card_id), card_supply_before + 1, label + " recycles exactly one card")
	var player: Dictionary = game.state["players"][player_id]
	_expect(not player.get("cards", []).has(card_id), label + " removes the held card")


func _assert_card_event(game: Object, player_id: int, card_id: String, label: String) -> Dictionary:
	var event: Dictionary = _last_card_event(game, card_id)
	_expect(str(event.get("type", "")) == "card_used", label + " records a card_used event")
	_expect_equal(str(event.get("card_id", "")), card_id, label + " event identifies the card")
	_expect_equal(int(event.get("player_id", -1)), player_id, label + " event identifies the actor")
	return event


func _expect_rejected_atomic(game: Object, params: Dictionary, label: String) -> void:
	var before: String = game.to_json()
	var result: Dictionary = game.choose_action("use_card", params)
	_expect(not bool(result.get("ok", false)), label + " is rejected")
	_expect_equal(game.to_json(), before, label + " leaves the whole game unchanged")


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


func _set_owned_god(game: Object, player_id: int, god_id: int, node: int) -> Dictionary:
	var owner: Dictionary = game.state["players"][player_id]
	_expect_equal(int(owner.get("position", -1)), node, "owned god fixture node follows its player")
	var actor: Dictionary = _ensure_actor(game, god_id, node)
	actor["owner"] = player_id
	actor["node"] = node
	actor["days"] = GOD_DAYS
	game.state["players"][player_id]["god_id"] = god_id
	return actor


func _set_source_node(game: Object, node_id: int, x: int, y: int) -> void:
	var board: Array = game.state.get("board", [])
	if node_id < 0 or node_id >= board.size() or typeof(board[node_id]) != TYPE_DICTIONARY:
		_expect(false, "fixture source node exists: %d" % node_id)
		return
	var tile: Dictionary = board[node_id]
	tile["x"] = x
	tile["y"] = y


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


func _configure_summon_candidates(game: Object) -> void:
	_clear_actor_ownership(game)
	_expect(game.state.get("board", []).size() >= 7, "summon fixture has enough source-coordinate nodes")
	_set_source_node(game, 1, 0, 0)
	_set_source_node(game, 2, 3000, 4000)
	_set_source_node(game, 3, -3000, -4000)
	_set_source_node(game, 4, 0, MAX_GOD_DISTANCE)
	_set_source_node(game, 6, -100, -100)
	var player0: Dictionary = game.state["players"][0]
	player0["position"] = 1
	player0["previous_position"] = -1
	game.state["players"][1]["position"] = 0
	# IDs 5 and 6 tie at distance 5,000; stable god ID order selects 5.
	_set_owned_god(game, 1, 3, 0) # An attached god is never a summon target.
	var dog: Dictionary = _ensure_actor(game, 11, 6)
	dog["node"] = 6 # The dog is valid source data but cannot be attached.
	var candidate5: Dictionary = _ensure_actor(game, 5, 2)
	candidate5["node"] = 2
	var candidate6: Dictionary = _ensure_actor(game, 6, 3)
	candidate6["node"] = 3
	var boundary: Dictionary = _ensure_actor(game, 7, 4)
	boundary["node"] = 4
	game.state["players"][1]["god_id"] = 3
	game.state["players"][1]["position"] = 0
	game.state["players"][0]["god_id"] = 0


func _test_fixture_and_capability_boundary() -> void:
	var definition: Dictionary = Fixture.definition()
	_expect(bool(definition.get("supports_original_building_cards", false)), "fixture retains v13 building-card capability")
	var game: Object = _new_game(48001)
	_expect(game != null, "existing v13 god-card fixture starts")
	if game != null:
		_expect(bool(game.state.get("original_gods", false)), "existing god capability is retained")
		for card_id in [DISMISS_CARD, SUMMON_CARD]:
			_expect(game.item_is_implemented("card", card_id), "existing god capability advertises implemented card: " + card_id)
	var without_gods: Object = _new_game_without_gods(48002)
	if without_gods == null:
		return
	_expect(not bool(without_gods.state.get("original_gods", false)), "god-less game keeps the existing save schema without god state")
	for card_id in [DISMISS_CARD, SUMMON_CARD]:
		_expect(not without_gods.item_is_implemented("card", card_id), "god-less game refuses card capability: " + card_id)
		_prepare_action(without_gods, 0, 1)
		if _stage_card(without_gods, 0, card_id):
			_expect_rejected_atomic(without_gods, {"card_id": card_id}, "god-less game rejects " + card_id)


func _test_dismiss_bad_gods_and_carried_bomb() -> void:
	for god_id_value in BAD_GOD_IDS:
		var god_id: int = int(god_id_value)
		var game: Object = _new_game(48100 + god_id)
		_expect(game != null, "dismiss fixture starts for bad god %d" % god_id)
		if game == null:
			continue
		_clear_actor_ownership(game)
		_prepare_action(game, 0, 1)
		_set_owned_god(game, 0, god_id, 1)
		_remove_actor(game, 1 if god_id == 2 else 2 if god_id == 1 else 5 if god_id == 6 else 7 if god_id == 8 else 9)
		var player0: Dictionary = game.state["players"][0]
		var player1: Dictionary = game.state["players"][1]
		_set_carried_bomb(game, 0, 8)
		player1["bomb_steps"] = 0
		_set_ground_bomb(game, 2, 1)
		var ground_before: Dictionary = game.state["ground_hazards"].duplicate(true)
		var cash_before: Array = _cash_deposit_snapshot(game)
		_expect_v13_snapshot_valid(game, "送神符 bad god %d" % god_id)
		if not _stage_card(game, 0, DISMISS_CARD):
			continue
		var card_supply_before: int = _card_supply(game, DISMISS_CARD)
		var bomb_supply_before: int = _tool_supply(game, "定時炸彈")
		var result: Dictionary = _use_card(game, DISMISS_CARD)
		_expect(bool(result.get("ok", false)), "送神符 clears bad god %d and carried bomb" % god_id)
		_expect_equal(int(player0.get("god_id", -1)), 0, "送神符 clears bad god %d from player" % god_id)
		_expect_equal(int(player0.get("bomb_steps", -1)), 0, "送神符 clears carried bomb for bad god %d" % god_id)
		_expect_equal(int(player1.get("bomb_steps", -1)), 0, "送神符 does not change another player's bomb for bad god %d" % god_id)
		_expect_equal(game.state.get("ground_hazards", {}), ground_before, "送神符 does not touch ground bombs for bad god %d" % god_id)
		_expect_equal(_tool_supply(game, "定時炸彈"), bomb_supply_before + 1, "送神符 returns one carried bomb slot for bad god %d" % god_id)
		_expect_equal(_cash_deposit_snapshot(game), cash_before, "送神符 does not change money for bad god %d" % god_id)
		var pair_id: int = 6 if god_id == 5 else 5 if god_id == 6 else 8 if god_id == 7 else 7 if god_id == 8 else 9
		var pair: Dictionary = game.call("_god_object", pair_id)
		_expect(not pair.is_empty(), "送神符 respawns paired god %d after clearing %d" % [pair_id, god_id])
		if not pair.is_empty():
			_expect_equal(int(pair.get("owner", -2)), -1, "respawned pair %d is unattached" % pair_id)
		_assert_successful_card(game, 0, DISMISS_CARD, card_supply_before, "送神符 bad god %d" % god_id)
		var event: Dictionary = _assert_card_event(game, 0, DISMISS_CARD, "送神符 bad god %d" % god_id)
		_expect(_event_has_god(event, god_id), "送神符 event identifies cleared god %d" % god_id)
		_expect(_event_bomb_cleared(event), "送神符 event identifies carried-bomb clearing for god %d" % god_id)


func _test_dismiss_preserves_good_gods_and_no_effect() -> void:
	for god_id_value in PRESERVED_GOD_IDS:
		var god_id: int = int(god_id_value)
		var game: Object = _new_game(48200 + god_id)
		_expect(game != null, "preserved-god fixture starts for %d" % god_id)
		if game == null:
			continue
		_clear_actor_ownership(game)
		_prepare_action(game, 0, 1)
		_set_owned_god(game, 0, god_id, 1)
		var player0: Dictionary = game.state["players"][0]
		_set_carried_bomb(game, 0, 5)
		var card_supply_before: int = _card_supply(game, DISMISS_CARD)
		var bomb_supply_before: int = _tool_supply(game, "定時炸彈")
		_expect_v13_snapshot_valid(game, "送神符 good god %d" % god_id)
		if not _stage_card(game, 0, DISMISS_CARD):
			continue
		var result: Dictionary = _use_card(game, DISMISS_CARD)
		_expect(bool(result.get("ok", false)), "送神符 clears a carried bomb while preserving good god %d" % god_id)
		_expect_equal(int(player0.get("god_id", -1)), god_id, "送神符 preserves good god %d" % god_id)
		_expect_equal(int(player0.get("bomb_steps", -1)), 0, "送神符 clears the carried bomb beside good god %d" % god_id)
		_expect_equal(_tool_supply(game, "定時炸彈"), bomb_supply_before + 1, "送神符 returns the carried bomb slot beside good god %d" % god_id)
		_assert_successful_card(game, 0, DISMISS_CARD, card_supply_before, "送神符 good god %d" % god_id)
		var event: Dictionary = _assert_card_event(game, 0, DISMISS_CARD, "送神符 good god %d" % god_id)
		_expect(_event_bomb_cleared(event), "送神符 event records carried-bomb clearing beside good god %d" % god_id)
	var no_effect: Object = _new_game(48299)
	_expect(no_effect != null, "送神符 no-effect fixture starts")
	if no_effect == null:
		return
	_clear_actor_ownership(no_effect)
	_prepare_action(no_effect, 0, 1)
	if _stage_card(no_effect, 0, DISMISS_CARD):
		_expect_rejected_atomic(no_effect, {"card_id": DISMISS_CARD}, "送神符 with no bad god or carried bomb")


func _preview_target(game: Object, player_id: int, visible_tile_ids: Variant = null) -> Dictionary:
	if not game.has_method("god_card_target"):
		_expect(false, "god-card preview helper exists")
		return {}
	var result: Variant = game.call("god_card_target", player_id, visible_tile_ids)
	if typeof(result) != TYPE_DICTIONARY:
		_expect(false, "god-card preview helper returns a dictionary")
		return {}
	return result


func _test_summon_nearest_tie_visibility_and_replacement() -> void:
	var tie: Object = _new_game(48301)
	_expect(tie != null, "summon tie fixture starts")
	if tie != null:
		_configure_summon_candidates(tie)
		_prepare_action(tie, 0, 1)
		_expect_v13_snapshot_valid(tie, "請神符 nearest tie")
		var before_preview: String = tie.to_json()
		var preview: Dictionary = _preview_target(tie, 0)
		_expect_equal(int(preview.get("id", -1)), 5, "summon preview chooses nearest tied god by stable lower ID")
		_expect_equal(tie.to_json(), before_preview, "summon preview does not mutate or consume")
		if _stage_card(tie, 0, SUMMON_CARD):
			var card_supply_before: int = _card_supply(tie, SUMMON_CARD)
			var result: Dictionary = _use_card(tie, SUMMON_CARD)
			_expect(bool(result.get("ok", false)), "summon accepts the nearest tied bad god for a human")
			_expect_equal(int(tie.state["players"][0].get("god_id", -1)), 5, "summon attaches the selected bad god")
			var actor5: Dictionary = tie.call("_god_object", 5)
			_expect_equal(int(actor5.get("owner", -1)), 0, "summoned god follows the player")
			_expect_equal(int(actor5.get("days", 0)), GOD_DAYS, "summoned god receives its attachment duration")
			_assert_successful_card(tie, 0, SUMMON_CARD, card_supply_before, "summon nearest tied god")
			var summon_event: Dictionary = _assert_card_event(tie, 0, SUMMON_CARD, "summon nearest tied god")
			_expect(_event_has_god(summon_event, 5), "summon event identifies the attached bad god")

	var visible: Object = _new_game(48302)
	_expect(visible != null, "summon visibility fixture starts")
	if visible != null:
		_configure_summon_candidates(visible)
		_prepare_action(visible, 0, 1)
		_expect_v13_snapshot_valid(visible, "請神符 visible candidate")
		var visible_preview: Dictionary = _preview_target(visible, 0, [3])
		_expect_equal(int(visible_preview.get("id", -1)), 6, "visible node filter selects the visible tied god")
		if _stage_card(visible, 0, SUMMON_CARD):
			var visible_result: Dictionary = _use_card(visible, SUMMON_CARD, {"visible_tile_ids": [3]})
			_expect(bool(visible_result.get("ok", false)), "summon accepts a visible candidate")
			_expect_equal(int(visible.state["players"][0].get("god_id", -1)), 6, "visible summon attaches the selected god")

	var empty: Object = _new_game(48303)
	_expect(empty != null, "summon empty-visibility fixture starts")
	if empty != null:
		_configure_summon_candidates(empty)
		_prepare_action(empty, 0, 1)
		var empty_preview: Dictionary = _preview_target(empty, 0, [])
		_expect(empty_preview.is_empty(), "empty visible list means no summon candidate")
		if _stage_card(empty, 0, SUMMON_CARD):
			_expect_rejected_atomic(empty, {"card_id": SUMMON_CARD, "visible_tile_ids": []}, "summon with empty visible list")

	var boundary: Object = _new_game(48304)
	_expect(boundary != null, "summon strict-distance fixture starts")
	if boundary != null:
		_clear_actor_ownership(boundary)
		_prepare_action(boundary, 0, 1)
		_set_source_node(boundary, 1, 0, 0)
		_set_source_node(boundary, 2, MAX_GOD_DISTANCE, 0)
		var boundary_actor: Dictionary = _ensure_actor(boundary, 7, 2)
		boundary_actor["node"] = 2
		_expect_v13_snapshot_valid(boundary, "請神符 strict distance")
		if _stage_card(boundary, 0, SUMMON_CARD):
			_expect(_preview_target(boundary, 0).is_empty(), "summon rejects the exact 10,000 distance boundary")
			_expect_rejected_atomic(boundary, {"card_id": SUMMON_CARD}, "summon with no candidate inside strict distance")

	var invalid: Object = _new_game(48305)
	_expect(invalid != null, "summon invalid-visibility fixture starts")
	if invalid != null:
		_configure_summon_candidates(invalid)
		_prepare_action(invalid, 0, 1)
		if _stage_card(invalid, 0, SUMMON_CARD):
			_expect_rejected_atomic(invalid, {"card_id": SUMMON_CARD, "visible_tile_ids": "bad"}, "summon with malformed visible list")
			_expect_rejected_atomic(invalid, {"card_id": SUMMON_CARD, "visible_tile_ids": [-1]}, "summon with invalid visible node")

	var replacement: Object = _new_game(48306)
	_expect(replacement != null, "summon replacement fixture starts")
	if replacement != null:
		_clear_actor_ownership(replacement)
		_prepare_action(replacement, 0, 1)
		_set_source_node(replacement, 1, 0, 0)
		_set_source_node(replacement, 2, 1000, 0)
		var old_god: Dictionary = _set_owned_god(replacement, 0, 1, 1)
		old_god["days"] = 4
		_remove_actor(replacement, 2)
		var replacement_target: Dictionary = _ensure_actor(replacement, 9, 2)
		replacement_target["node"] = 2
		_expect_v13_snapshot_valid(replacement, "請神符 replacement")
		if _stage_card(replacement, 0, SUMMON_CARD):
			var replacement_result: Dictionary = _use_card(replacement, SUMMON_CARD)
			_expect(bool(replacement_result.get("ok", false)), "summon replaces an existing god")
			_expect_equal(int(replacement.state["players"][0].get("god_id", -1)), 9, "summon replacement installs the selected god")
			_expect(replacement.call("_god_object", 1).is_empty(), "summon replacement removes the old god object")
			var respawned_pair: Dictionary = replacement.call("_god_object", 2)
			_expect(not respawned_pair.is_empty() and int(respawned_pair.get("owner", -1)) == -1, "summon replacement respawns the old god pair")


func _test_phase_cancel_remote_and_invalid_atomicity() -> void:
	var cancel: Object = _new_game(48401)
	_expect(cancel != null, "god-card cancel fixture starts")
	if cancel != null:
		_clear_actor_ownership(cancel)
		_prepare_action(cancel, 0, 1)
		_set_owned_god(cancel, 0, 7, 1)
		if _stage_card(cancel, 0, DISMISS_CARD):
			_expect_rejected_atomic(cancel, {"card_id": DISMISS_CARD, "cancel": true}, "cancelled 送神符")

	var summon_cancel: Object = _new_game(48405)
	_expect(summon_cancel != null, "summon cancel fixture starts")
	if summon_cancel != null:
		_configure_summon_candidates(summon_cancel)
		_prepare_action(summon_cancel, 0, 1)
		if _stage_card(summon_cancel, 0, SUMMON_CARD):
			_expect_rejected_atomic(summon_cancel, {"card_id": SUMMON_CARD, "cancel": true}, "cancelled 請神符 with a valid candidate")

	var route: Object = _new_game(48402)
	_expect(route != null, "god-card route fixture starts")
	if route != null:
		_clear_actor_ownership(route)
		_prepare_action(route, 0, 1, "await_route")
		_set_owned_god(route, 0, 7, 1)
		route.state["route_options"] = [2]
		route.state["remaining_steps"] = 1
		route.state["pending_movement"] = {"player_id": 0, "current_node": 1, "previous_node": 0}
		if _stage_card(route, 0, DISMISS_CARD):
			_expect_rejected_atomic(route, {"card_id": DISMISS_CARD}, "送神符 during route selection")

	var detained: Object = _new_game(48403)
	_expect(detained != null, "god-card detained fixture starts")
	if detained != null:
		_clear_actor_ownership(detained)
		_prepare_action(detained, 0, 1)
		_set_owned_god(detained, 0, 7, 1)
		detained.state["players"][0]["hospital_days"] = 2
		if _stage_card(detained, 0, DISMISS_CARD):
			_expect_rejected_atomic(detained, {"card_id": DISMISS_CARD}, "送神符 during hospital stay")

	var remote: Object = _new_game(48404)
	_expect(remote != null, "god-card remote-dice fixture starts")
	if remote != null:
		_clear_actor_ownership(remote)
		_prepare_action(remote, 0, 1, "await_roll")
		_set_owned_god(remote, 0, 7, 1)
		remote.state["pending_remote_dice"] = {"player_id": 0, "value": 3}
		if _stage_card(remote, 0, DISMISS_CARD):
			_expect_rejected_atomic(remote, {"card_id": DISMISS_CARD}, "送神符 while remote dice is pending")
