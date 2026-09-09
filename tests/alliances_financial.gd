extends SceneTree

## Issue #75 financial integration seed for reciprocal 同盟 state.
##
## The scenarios enter through the public movement, finance-response, and card
## APIs.  Alliance records are staged as the accepted reciprocal save shape;
## the current pre-alliance core therefore remains a deliberate RED baseline.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")

const FREE_CARD := "免費"
const TAX_CARD := "查稅"
const ALLIANCE_DAYS := 7
const MAX_CASH := 1000000000000

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_combined_rent_uses_nominal_free_threshold_and_accepts_once()
	_test_combined_rent_decline_splits_actual_insolvent_payment_and_replays()
	_test_god_modified_combined_rent_offers_free_once()
	_test_allied_rent_recipient_caps_use_proportional_shares()
	_test_human_allied_payer_still_waits_for_free_response()
	_test_allied_tax_caster_and_target_pay_normally()
	print("Alliances financial checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	expect(actual == expected, "%s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func fresh(seed_value: int, player_count: int = 4) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, Fixture.definition(), Fixture.new_game_options())
	expect(game != null, "v13 financial alliance fixture starts")
	if game == null:
		return null
	# Remove source-derived occupants/cards so every scenario has a finite,
	# deterministic inventory and an ordinary human payer unless changed below.
	game.state["god_objects"] = []
	game.state["roadblocks"] = {}
	game.state["ground_hazards"] = {}
	for player_id in range(player_count):
		game.set_player_ai(player_id, false)
		var player: Dictionary = game.state["players"][player_id]
		for held_value in player.get("cards", []).duplicate():
			Inventory.consume_card(game.state["inventory_supply"], player["cards"], str(held_value))
		player.erase("alliance")
		player["position"] = 2
		player["previous_position"] = -1
		player["hospital_days"] = 0
		player["prison_days"] = 0
		player["winter_sleep_days"] = 0
		player["dream_days"] = 0
		player["god_id"] = 0
		player["cash"] = 100000
		player["deposit"] = 0
		player["alive"] = true
		player["bankrupt"] = false
	game.state["bank"]["deposits"] = 0
	prepare_action(game, 0)
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "clean v13 alliance financial fixture validates")
	return game


func prepare_action(game: Object, player_id: int, position: int = 2) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = "await_action"
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state["pending_trap"] = {}
	game.state.erase("pending_trap_card")
	game.state.erase("pending_finance")
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["bank_access"] = false
	game.state["bank_landing"] = false
	if player_id >= 0 and player_id < game.state["players"].size():
		game.state["players"][player_id]["position"] = position
		game.state["players"][player_id]["previous_position"] = -1
	game._set_action_options(player_id)


func pair(game: Object, first_id: int, second_id: int, first_turns: int = ALLIANCE_DAYS, second_turns: int = ALLIANCE_DAYS) -> void:
	game.state["players"][first_id]["alliance"] = {"partner_id": second_id, "turns": first_turns}
	game.state["players"][second_id]["alliance"] = {"partner_id": first_id, "turns": second_turns}


func stage_card(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	expect(bool(result.get("ok", false)), "finite inventory stages %s for player %d" % [card_id, player_id])
	if bool(result.get("ok", false)):
		game._set_action_options(int(game.state.get("current_player", player_id)))
	return bool(result.get("ok", false))


func card_count(game: Object, player_id: int, card_id: String) -> int:
	var count: int = 0
	for value in game.state["players"][player_id].get("cards", []):
		if str(value) == card_id:
			count += 1
	return count


func card_supply(game: Object, card_id: String) -> int:
	return int(game.state.get("inventory_supply", {}).get("cards", {}).get(card_id, -1))


func set_cash(game: Object, player_id: int, cash: int, deposit: int = 0) -> void:
	game.state["players"][player_id]["cash"] = cash
	game.state["players"][player_id]["deposit"] = deposit
	var total_deposits: int = 0
	for value in game.state.get("players", []):
		if typeof(value) == TYPE_DICTIONARY:
			total_deposits += int(value.get("deposit", 0))
	game.state["bank"]["deposits"] = total_deposits


func set_property(game: Object, tile_id: int, owner_id: int, level: int, chain: bool = false) -> void:
	var board: Array = game.state.get("board", [])
	expect(tile_id >= 0 and tile_id < board.size(), "property fixture tile %d exists" % tile_id)
	if tile_id < 0 or tile_id >= board.size():
		return
	var tile: Dictionary = board[tile_id]
	expect(str(tile.get("kind", "")) == "property", "property fixture tile %d is ordinary property" % tile_id)
	for value in game.state.get("players", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var properties: Array = value.get("properties", []).duplicate(true)
		while properties.has(tile_id):
			properties.erase(tile_id)
		value["properties"] = properties
	tile["owner"] = owner_id
	tile["building_level"] = level
	tile["is_chain_store"] = chain
	if owner_id >= 0 and owner_id < game.state["players"].size():
		var owner_properties: Array = game.state["players"][owner_id].get("properties", []).duplicate(true)
		if not owner_properties.has(tile_id):
			owner_properties.append(tile_id)
		game.state["players"][owner_id]["properties"] = owner_properties
	game._update_tile_rent(tile)
	game._recalculate_property_values()


func prepare_public_roll(game: Object, player_id: int, target_id: int) -> bool:
	var board: Array = game.state.get("board", [])
	var source_id: int = -1
	for index in range(board.size()):
		if typeof(board[index]) != TYPE_DICTIONARY:
			continue
		var adjacent: Variant = board[index].get("adjacent", [])
		if typeof(adjacent) == TYPE_ARRAY and adjacent.has(target_id):
			source_id = index
			break
	expect(source_id >= 0, "route fixture has an edge into tile %d" % target_id)
	if source_id < 0:
		return false
	var player: Dictionary = game.state["players"][player_id]
	player["position"] = source_id
	player["previous_position"] = -1
	for actor_value in game.state.get("god_objects", []):
		if typeof(actor_value) == TYPE_DICTIONARY and int(actor_value.get("owner", -1)) == player_id:
			actor_value["node"] = source_id
	player["vehicle"] = "walking"
	player["dice_count"] = 1
	player["turtle_days"] = 1
	game.state["current_player"] = player_id
	game.state["phase"] = "await_roll"
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state["pending_trap"] = {}
	game.state.erase("pending_trap_card")
	game.state.erase("pending_finance")
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game._set_action_options(player_id)
	legal(game, "actual public roll boundary")
	var rolled: Dictionary = game.roll()
	expect(bool(rolled.get("ok", false)), "public roll reaches one-step alliance financial route")
	if not bool(rolled.get("ok", false)):
		return false
	if game.state.get("phase", "") == "await_route":
		legal(game, "actual public choose_route boundary")
		var routed: Dictionary = game.choose_route(target_id)
		expect(bool(routed.get("ok", false)), "public choose_route reaches alliance financial destination")
		return bool(routed.get("ok", false))
	expect_equal(int(player.get("position", -1)), target_id, "public roll reaches alliance financial destination")
	return true


func financial_response(game: Object) -> Dictionary:
	expect(game.has_method("financial_response"), "financial_response public API exists")
	if not game.has_method("financial_response"):
		return {}
	var value: Variant = game.call("financial_response")
	expect(value is Dictionary, "financial_response returns a Dictionary")
	return value if value is Dictionary else {}


func event_list(game: Object, event_type: String) -> Array:
	var matches: Array = []
	for value in game.state.get("event_log", []):
		if typeof(value) == TYPE_DICTIONARY and str(value.get("type", "")) == event_type:
			matches.append(value)
	return matches


func legal(game: Object, label: String) -> bool:
	var data: Dictionary = game.to_dict()
	var validation: Dictionary = Game.validate_save(data)
	expect(bool(validation.get("ok", false)), label + " validates before action: " + str(validation.get("errors", [])))
	var encoded: String = game.to_json()
	var parsed: Variant = JSON.parse_string(encoded)
	var restored: Object = Game.from_dict(parsed) if parsed is Dictionary else null
	expect(restored != null, label + " has a JSON-continuable save")
	if restored != null:
		expect(restored.to_json() == encoded, label + " JSON continuation is exact")
	return bool(validation.get("ok", false))


func _test_combined_rent_uses_nominal_free_threshold_and_accepts_once() -> void:
	var game: Object = fresh(75201)
	if game == null:
		return
	# Each source is below the 2,000 threshold; the reciprocal same-name pair
	# makes their nominal total 2,400 and therefore eligible for 免費.
	pair(game, 0, 1)
	set_property(game, 2, 1, 3)
	set_property(game, 3, 0, 3)
	stage_card(game, 2, FREE_CARD)
	set_cash(game, 2, 10000)
	var payer_before: int = int(game.state["players"][2]["cash"])
	var owner_before: int = int(game.state["players"][1]["cash"])
	var ally_before: int = int(game.state["players"][0]["cash"])
	var supply_before: int = card_supply(game, FREE_CARD)
	legal(game, "combined nominal rent before public roll")
	if not prepare_public_roll(game, 2, 2):
		return
	var pending: Dictionary = financial_response(game)
	expect(str(pending.get("kind", "")) == "rent" and str(pending.get("stage", "")) == "free", "combined nominal rent prompts 免費")
	expect_equal(int(pending.get("amount", -1)), 2400, "免費 prompt stores the combined nominal rent")
	expect_equal(int(game.state["players"][2]["cash"]), payer_before, "combined rent remains unpaid while 免費 waits")
	expect_equal(int(game.state["players"][1]["cash"]), owner_before, "combined rent does not credit owner before response")
	expect_equal(int(game.state["players"][0]["cash"]), ally_before, "combined rent does not credit ally before response")
	if pending.is_empty():
		return
	legal(game, "combined nominal rent pending before 免費 acceptance")
	var accepted: Dictionary = game.choose_action("respond_finance", {"cancel": false})
	expect(bool(accepted.get("ok", false)), "accepting combined 免費 succeeds")
	expect(financial_response(game).is_empty(), "accepting combined 免費 clears pending response")
	expect_equal(int(game.state["players"][2]["cash"]), payer_before, "accepted combined 免費 leaves payer cash unchanged")
	expect_equal(int(game.state["players"][1]["cash"]), owner_before, "accepted combined 免費 waives owner share")
	expect_equal(int(game.state["players"][0]["cash"]), ally_before, "accepted combined 免費 waives ally share")
	expect_equal(card_count(game, 2, FREE_CARD), 0, "accepted combined 免費 consumes exactly one defense card")
	expect_equal(card_supply(game, FREE_CARD), supply_before + 1, "accepted combined 免費 returns exactly one card to finite supply")
	var waived: Array = event_list(game, "financial_payment_waived")
	expect(not waived.is_empty(), "accepted combined 免費 records a waiver event")
	if not waived.is_empty():
		expect_equal(int(waived[waived.size() - 1].get("amount", -1)), 2400, "waiver event retains the combined nominal amount")


func _test_combined_rent_decline_splits_actual_insolvent_payment_and_replays() -> void:
	var game: Object = fresh(75202)
	if game == null:
		return
	pair(game, 0, 1)
	set_property(game, 2, 1, 2)
	set_property(game, 3, 0, 1)
	stage_card(game, 2, FREE_CARD)
	set_cash(game, 2, 100)
	var owner_before: int = int(game.state["players"][1]["cash"])
	var ally_before: int = int(game.state["players"][0]["cash"])
	var supply_before: int = card_supply(game, FREE_CARD)
	legal(game, "insolvent combined rent before public roll")
	if not prepare_public_roll(game, 2, 2):
		return
	var pending: Dictionary = financial_response(game)
	expect(str(pending.get("kind", "")) == "rent" and str(pending.get("stage", "")) == "free", "insolvent combined rent prompts 免費")
	expect_equal(int(pending.get("amount", -1)), 850, "insolvent pending rent keeps the combined nominal amount")
	if pending.is_empty():
		return
	var pending_json: String = game.to_json()
	var parsed: Variant = JSON.parse_string(pending_json)
	var restored: Object = Game.from_dict(parsed) if parsed is Dictionary else null
	expect(restored != null, "insolvent pending rent reloads from exact JSON")
	legal(game, "insolvent combined rent pending before decline")
	var declined: Dictionary = game.choose_action("respond_finance", {"cancel": true})
	expect(bool(declined.get("ok", false)), "declining combined 免費 succeeds")
	expect(financial_response(game).is_empty(), "declining combined 免費 clears pending response")
	expect_equal(int(game.state["players"][2]["cash"]), 0, "insolvent combined payer pays all actual cash")
	expect(bool(game.state["players"][2].get("bankrupt", false)), "insolvent combined payer enters bankruptcy")
	# 600:250 contributions split the actual 100 payment as owner remainder 71
	# and ally floor share 29, with no transient full-credit to the owner.
	expect_equal(int(game.state["players"][1]["cash"]) - owner_before, 71, "combined insolvency credits owner proportional remainder")
	expect_equal(int(game.state["players"][0]["cash"]) - ally_before, 29, "combined insolvency credits ally proportional share")
	expect_equal((int(game.state["players"][1]["cash"]) - owner_before) + (int(game.state["players"][0]["cash"]) - ally_before), 100, "combined insolvency credits only actual payable funds")
	expect_equal(card_count(game, 2, FREE_CARD), 1, "declining combined 免費 preserves the defense card")
	expect_equal(card_supply(game, FREE_CARD), supply_before, "declining combined 免費 leaves finite supply unchanged")
	if restored != null:
		legal(restored, "reloaded insolvent pending rent before decline")
		var replay: Dictionary = restored.choose_action("respond_finance", {"cancel": true})
		expect(bool(replay.get("ok", false)), "reloaded insolvent pending rent declines publicly")
		expect_equal(restored.to_json(), game.to_json(), "declined combined rent has exact JSON replay")


func _test_god_modified_combined_rent_offers_free_once() -> void:
	var game: Object = fresh(75203)
	if game == null:
		return
	pair(game, 0, 1)
	set_property(game, 2, 1, 5)
	set_property(game, 3, 0, 5)
	stage_card(game, 2, FREE_CARD)
	set_cash(game, 2, 10000)
	# God 1 halves a rent charge.  It is staged at the current player node and
	# follows that player through the real public movement path.
	game.state["players"][2]["god_id"] = 1
	game.state["god_objects"] = [{"id": 1, "node": 2, "owner": 2, "days": 7}]
	legal(game, "god-modified combined rent before public roll")
	if not prepare_public_roll(game, 2, 2):
		return
	var pending: Dictionary = financial_response(game)
	expect(str(pending.get("kind", "")) == "rent" and str(pending.get("stage", "")) == "free", "god-modified combined rent still offers 免費")
	# Level-5 contributions are 4,800 each, so the nominal combined 9,600 is
	# modified once to 4,800 before the FREE threshold and pending record.
	expect_equal(int(pending.get("amount", -1)), 4800, "god modifier applies once before the combined 免費 amount")
	var modifiers: Array = []
	for value in event_list(game, "god_charge_modifier"):
		if str(value.get("reason", "")) == "rent":
			modifiers.append(value)
	expect_equal(modifiers.size(), 1, "combined rent emits one God rent modifier")
	if modifiers.size() == 1:
		expect_equal(int(modifiers[0].get("from_amount", -1)), 9600, "God modifier sees the combined nominal rent")
		expect_equal(int(modifiers[0].get("to_amount", -1)), 4800, "God modifier halves the combined rent once")
	if pending.is_empty():
		return
	var free_before: int = card_supply(game, FREE_CARD)
	legal(game, "god-modified combined rent pending before 免費 acceptance")
	var response: Dictionary = game.choose_action("respond_finance", {"cancel": false})
	expect(bool(response.get("ok", false)), "god-modified combined 免費 acceptance succeeds")
	expect(financial_response(game).is_empty(), "god-modified combined 免費 clears pending")
	expect_equal(card_supply(game, FREE_CARD), free_before + 1, "god-modified combined 免費 consumes exactly once")
	var post_modifiers: Array = []
	for value in event_list(game, "god_charge_modifier"):
		if str(value.get("reason", "")) == "rent":
			post_modifiers.append(value)
	expect_equal(post_modifiers.size(), 1, "FREE acceptance does not apply the God modifier a second time")


func _test_allied_rent_recipient_caps_use_proportional_shares() -> void:
	var game: Object = fresh(75204)
	if game == null:
		return
	pair(game, 0, 1)
	set_property(game, 2, 1, 2)
	set_property(game, 3, 0, 1)
	# Nominal rent is 850.  Each recipient's proportional share fits exactly at
	# the cash ceiling, while crediting the owner with all 850 would overflow.
	set_cash(game, 2, 850)
	set_cash(game, 1, MAX_CASH - 600)
	set_cash(game, 0, MAX_CASH - 250)
	prepare_action(game, 2)
	legal(game, "recipient cap combined rent before public roll")
	if not prepare_public_roll(game, 2, 2):
		return
	expect_equal(int(game.state["players"][2]["cash"]), 0, "recipient cap payer pays the combined rent")
	expect_equal(int(game.state["players"][1]["cash"]), MAX_CASH, "owner receives only its proportional share within cap")
	expect_equal(int(game.state["players"][0]["cash"]), MAX_CASH, "ally receives its proportional share within cap")
	expect(not bool(game.state["players"][2].get("bankrupt", false)), "recipient cap does not reject a payable split")
	expect(event_list(game, "payment_rejected").is_empty(), "recipient cap split emits no nominal full-credit rejection")


func _test_human_allied_payer_still_waits_for_free_response() -> void:
	var game: Object = fresh(75205)
	if game == null:
		return
	pair(game, 0, 1)
	set_property(game, 2, 2, 5)
	stage_card(game, 0, FREE_CARD)
	set_cash(game, 0, 10000)
	var payer_before: int = int(game.state["players"][0]["cash"])
	var creditor_before: int = int(game.state["players"][2]["cash"])
	legal(game, "allied human payer before public roll")
	if not prepare_public_roll(game, 0, 2):
		return
	var pending: Dictionary = financial_response(game)
	expect(str(pending.get("kind", "")) == "rent" and str(pending.get("stage", "")) == "free", "human allied payer waits for 免費 response")
	expect_equal(int(pending.get("payer_id", -1)), 0, "waiting response retains allied payer identity")
	expect_equal(int(pending.get("amount", -1)), 4800, "waiting response stores ordinary rent amount")
	expect_equal(int(game.state.get("current_player", -1)), 0, "waiting response keeps the allied human turn")
	expect_equal(int(game.state["players"][0]["cash"]), payer_before, "waiting response leaves allied payer cash unchanged")
	expect_equal(int(game.state["players"][2]["cash"]), creditor_before, "waiting response leaves creditor cash unchanged")
	if pending.is_empty():
		return
	var frozen: String = game.to_json()
	var blocked_roll: Dictionary = game.roll()
	expect(not bool(blocked_roll.get("ok", false)), "waiting allied response blocks another public roll")
	expect_equal(game.to_json(), frozen, "blocked allied roll is atomic")
	legal(game, "allied human rent pending before 免費 acceptance")
	var accepted: Dictionary = game.choose_action("respond_finance", {"cancel": false})
	expect(bool(accepted.get("ok", false)), "allied human payer can accept 免費")
	expect(financial_response(game).is_empty(), "allied human response clears pending")


func _test_allied_tax_caster_and_target_pay_normally() -> void:
	var target_allied: Object = fresh(75206)
	if target_allied == null:
		return
	pair(target_allied, 0, 1)
	stage_card(target_allied, 0, TAX_CARD)
	set_cash(target_allied, 1, 10000)
	set_cash(target_allied, 0, 10000)
	prepare_action(target_allied, 0, 2)
	legal(target_allied, "allied tax target before public card")
	var target_before: int = int(target_allied.state["players"][1]["cash"])
	var caster_before: int = int(target_allied.state["players"][0]["cash"])
	var target_result: Dictionary = target_allied.choose_action("use_card", {"card_id": TAX_CARD, "target_id": 1, "cancel": false})
	expect(bool(target_result.get("ok", false)), "allied tax target resolves through public card")
	expect_equal(int(target_allied.state["players"][1]["cash"]), target_before - 2000, "allied tax target pays tax normally")
	expect_equal(int(target_allied.state["players"][0]["cash"]), caster_before + 2000, "allied tax caster receives tax normally")
	expect(financial_response(target_allied).is_empty(), "allied tax target does not create a rent-style pending response")

	var caster_allied: Object = fresh(75207)
	if caster_allied == null:
		return
	pair(caster_allied, 0, 1)
	stage_card(caster_allied, 1, TAX_CARD)
	set_cash(caster_allied, 0, 10000)
	set_cash(caster_allied, 1, 10000)
	prepare_action(caster_allied, 1, 2)
	legal(caster_allied, "allied tax caster before public card")
	var reverse_target_before: int = int(caster_allied.state["players"][0]["cash"])
	var reverse_caster_before: int = int(caster_allied.state["players"][1]["cash"])
	var caster_result: Dictionary = caster_allied.choose_action("use_card", {"card_id": TAX_CARD, "target_id": 0, "cancel": false})
	expect(bool(caster_result.get("ok", false)), "allied tax caster resolves through public card")
	expect_equal(int(caster_allied.state["players"][0]["cash"]), reverse_target_before - 2000, "allied tax caster target pays tax normally")
	expect_equal(int(caster_allied.state["players"][1]["cash"]), reverse_caster_before + 2000, "allied tax caster receives tax normally")
	expect(financial_response(caster_allied).is_empty(), "reverse allied tax does not create a rent-style pending response")
