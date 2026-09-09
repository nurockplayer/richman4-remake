extends SceneTree

## Issue #74 executable RED seed for 查稅 and human 免費 responses.
##
## This file intentionally reaches the game through public card, response,
## AI, and sleep-turn entry points.  It does not construct pending state for
## behavioural assertions; a pending save-shaped copy belongs to
## financial_save.gd.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")

const TAX_CARD := "查稅"
const FREE_CARD := "免費"
const SCAPEGOAT_CARD := "嫁禍"
const IMMUNITY_CARD := "免罪"
const REVENGE_CARD := "復仇"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_public_catalogue_and_targets()
	_test_tax_direct_payment_and_selection_atomicity()
	_test_human_free_accept_decline_and_waiting_guards()
	_test_tax_threshold_redirect_recompute_and_non_recursive_defenses()
	_test_ai_tax_fallback_and_dream_wait()
	print("Financial tax checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	expect(actual == expected, "%s (got %s, expected %s)" % [label, str(actual), str(expected)])


func fresh(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.new_game_options())
	expect(game != null, "legal v13 financial fixture starts")
	if game == null:
		return null
	# The complete fixture starts with source-derived god objects.  Remove those
	# unrelated occupants so target selection remains deterministic.
	game.state["god_objects"] = []
	for player_id in range(4):
		game.set_player_ai(player_id, false)
		var player: Dictionary = game.state["players"][player_id]
		player["position"] = player_id
		player["previous_position"] = -1
		player["hospital_days"] = 0
		player["prison_days"] = 0
		player["god_id"] = 0
		player["cash"] = 10000
		player["deposit"] = 0
		player["alive"] = true
	game.state["bank"]["deposits"] = 0
	prepare(game, 0)
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "fresh financial fixture validates")
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


func player(game: Object, player_id: int) -> Dictionary:
	return game.state["players"][player_id]


func set_cash(game: Object, player_id: int, cash: int, deposit: int = 0) -> void:
	player(game, player_id)["cash"] = cash
	player(game, player_id)["deposit"] = deposit
	var deposits: int = 0
	for record in game.state["players"]:
		deposits += int(record.get("deposit", 0))
	game.state["bank"]["deposits"] = deposits


func tax_targets(game: Object, caster_id: int) -> Array:
	if not game.has_method("tax_target_players"):
		expect(false, "tax_target_players public API exists")
		return []
	var value: Variant = game.call("tax_target_players", caster_id)
	expect(value is Array, "tax_target_players returns an Array")
	return value if value is Array else []


func finance_response(game: Object) -> Dictionary:
	if not game.has_method("financial_response"):
		expect(false, "financial_response public API exists")
		return {}
	var value: Variant = game.call("financial_response")
	expect(value is Dictionary, "financial_response returns a Dictionary")
	return value if value is Dictionary else {}


func pending(game: Object) -> Dictionary:
	var value: Variant = game.state.get("pending_finance", {})
	return value if value is Dictionary else {}


func respond(game: Object, cancel: Variant, target_id: Variant = 1) -> Dictionary:
	var params: Dictionary = {"cancel": cancel, "target_id": target_id}
	return game.choose_action("respond_finance", params)


func use_tax(game: Object, target_id: Variant, cancel: Variant = false) -> Dictionary:
	return game.choose_action("use_card", {"card_id": TAX_CARD, "target_id": target_id, "cancel": cancel})


func expect_rejected_atomic(game: Object, action: String, params: Dictionary, label: String) -> void:
	var before: String = game.to_json()
	var result: Dictionary = game.choose_action(action, params)
	expect(not bool(result.get("ok", false)), label + " is rejected")
	expect_equal(game.to_json(), before, label + " leaves state, RNG and supply unchanged")


func expect_rejected_tax_atomic(game: Object, params: Dictionary, label: String) -> void:
	# The pre-feature game coerces 查稅 parameters before reporting that the card
	# is unimplemented.  Avoid that known baseline crash while keeping one clear
	# RED assertion; the typed boundary is exercised once 查稅 is admitted.
	if not game.item_is_implemented("card", TAX_CARD):
		expect(false, label + " awaits the admitted 查稅 boundary")
		return
	expect_rejected_atomic(game, "use_card", params, label)


func _test_public_catalogue_and_targets() -> void:
	var game: Object = fresh(74101)
	if game == null:
		return
	stage_card(game, 0, TAX_CARD)
	expect(game.item_is_implemented("card", TAX_CARD), "查稅 is admitted by the public catalogue")
	expect(game.item_is_implemented("card", FREE_CARD), "免費 is admitted by the public catalogue")
	expect_equal(tax_targets(game, 0), [1, 2, 3], "tax target list includes every living non-caster player")
	# Existing status target policy excludes detained players and keeps the other
	# targets stable.  The public tax picker must apply the same boundary.
	game.call("_admit_player_status", 2, "hospital", 3)
	expect_equal(tax_targets(game, 0), [1, 3], "tax target list excludes a hospitalized player")
	expect_equal(tax_targets(game, 99), [], "tax target list rejects an invalid caster")
	expect_equal(tax_targets(game, 1), [0, 3], "tax target list is relative to the caster")


func _test_tax_direct_payment_and_selection_atomicity() -> void:
	var game: Object = fresh(74102)
	if game == null:
		return
	set_cash(game, 1, 12345, 6789)
	var caster_before: int = int(player(game, 0).cash)
	var target_before: int = int(player(game, 1).cash)
	var deposit_before: int = int(player(game, 1).deposit)
	var supply_after_stage: int = card_supply(game, TAX_CARD)
	stage_card(game, 0, TAX_CARD)
	supply_after_stage = card_supply(game, TAX_CARD)
	var invalid_before: String = game.to_json()
	var invalid_type: Dictionary = use_tax(game, "1")
	expect(not bool(invalid_type.get("ok", false)), "tax rejects a string target id")
	expect_equal(game.to_json(), invalid_before, "string target rejection is atomic")
	expect_rejected_atomic(game, "use_card", {"card_id": TAX_CARD, "target_id": 99}, "tax target outside public list")
	expect_rejected_tax_atomic(game, {"card_id": TAX_CARD, "target_id": 1, "cancel": "yes"}, "tax cancellation with wrong type")
	var cancel_before: String = game.to_json()
	var cancelled: Dictionary = use_tax(game, 1, true)
	expect(bool(cancelled.get("ok", false)), "tax target selection cancellation succeeds")
	expect_equal(game.to_json(), cancel_before, "tax selection cancellation does not consume or charge")
	var result: Dictionary = use_tax(game, 1)
	expect(bool(result.get("ok", false)), "tax without defenses resolves")
	if not bool(result.get("ok", false)):
		return
	var expected: int = int(floor(float(target_before) * 0.2))
	expect_equal(int(player(game, 1).cash), target_before - expected, "tax is twenty percent of target cash rounded toward zero")
	expect_equal(int(player(game, 0).cash), caster_before + expected, "tax credits the caster")
	expect_equal(int(player(game, 1).deposit), deposit_before, "tax never withdraws target deposit")
	expect_equal(card_supply(game, TAX_CARD), supply_after_stage + 1, "successful tax returns the consumed card to finite supply")
	expect(not player(game, 0).cards.has(TAX_CARD), "successful tax consumes 查稅")
	expect(pending(game).is_empty(), "tax without 免費 has no pending response")

	# Crediting the caster must preserve the save cash ceiling.  Reject the
	# selection atomically before consuming 查稅 when the immediate transfer
	# would exceed the representable 1e12 player-cash limit.
	var cap: Object = fresh(74114)
	if cap == null:
		return
	set_cash(cap, 0, 1000000000000 - 1999)
	stage_card(cap, 0, TAX_CARD)
	expect(bool(Game.validate_save(cap.to_dict()).get("ok", false)), "tax cash-cap fixture validates before public tax")
	var cap_before: String = cap.to_json()
	var cap_result: Dictionary = use_tax(cap, 1)
	expect(not bool(cap_result.get("ok", false)), "tax rejects caster credit overflow at the cash cap")
	expect_equal(cap.to_json(), cap_before, "tax cash-cap rejection preserves state, RNG and supply")

	# A zero-cash target still receives the initial 免費 choice.  This keeps the
	# source's card-consumption and response semantics visible at amount zero.
	var zero: Object = fresh(74103)
	if zero == null:
		return
	set_cash(zero, 1, 0, 9000)
	stage_card(zero, 0, TAX_CARD)
	stage_card(zero, 1, FREE_CARD)
	var zero_result: Dictionary = use_tax(zero, 1)
	expect(bool(zero_result.get("ok", false)), "zero-value tax still enters 免費 response")
	var zero_pending: Dictionary = pending(zero)
	expect_equal(int(zero_pending.get("amount", -1)), 0, "zero-value tax preserves an amount-zero pending choice")
	if not zero_pending.is_empty():
		var zero_accept: Dictionary = respond(zero, false, 1)
		expect(bool(zero_accept.get("ok", false)), "amount-zero 免費 response succeeds")
		expect_equal(int(player(zero, 1).cash), 0, "amount-zero 免費 leaves target cash unchanged")


func _test_human_free_accept_decline_and_waiting_guards() -> void:
	var accept_game: Object = fresh(74104)
	if accept_game == null:
		return
	stage_card(accept_game, 0, TAX_CARD)
	stage_card(accept_game, 1, FREE_CARD)
	set_cash(accept_game, 1, 5000)
	var target_cash: int = int(player(accept_game, 1).cash)
	var caster_cash: int = int(player(accept_game, 0).cash)
	var free_supply: int = card_supply(accept_game, FREE_CARD)
	var tax_result: Dictionary = use_tax(accept_game, 1)
	expect(bool(tax_result.get("ok", false)), "查稅 offers 免費 to a human target")
	var accepted_pending: Dictionary = pending(accept_game)
	expect_equal(accepted_pending.keys().size(), 7, "financial pending uses exactly seven canonical fields")
	for key in ["kind", "stage", "payer_id", "creditor_id", "amount", "node_id", "caster_id"]:
		expect(accepted_pending.has(key), "financial pending includes " + key)
	var response: Dictionary = finance_response(accept_game)
	expect_equal(response, accepted_pending, "financial_response exposes the canonical pending record")
	var waiting_before: String = accept_game.to_json()
	for action in ["roll", "end_turn", "set_vehicle", "use_card"]:
		if action == "roll":
			expect_rejected_atomic(accept_game, action, {}, "financial response blocks " + action)
		elif action == "end_turn":
			expect_rejected_atomic(accept_game, action, {}, "financial response blocks " + action)
		elif action == "set_vehicle":
			expect_rejected_atomic(accept_game, action, {"vehicle": "walking"}, "financial response blocks " + action)
		else:
			expect_rejected_atomic(accept_game, action, {"card_id": FREE_CARD, "target_id": 1}, "financial response blocks " + action)
	expect_equal(accept_game.to_json(), waiting_before, "blocked operations preserve the pending response")
	for bad_cancel in ["false", 0, 1, [], {}]:
		expect_rejected_atomic(accept_game, "respond_finance", {"cancel": bad_cancel, "target_id": 1}, "financial response rejects cancel type " + str(bad_cancel))
	# The free response has no redirect picker; the UI therefore sends only the
	# boolean decision.  target_id is validated when the redirect stage is active.
	var accepted: Dictionary = respond(accept_game, false)
	expect(bool(accepted.get("ok", false)), "human accepts 免費")
	if bool(accepted.get("ok", false)):
		expect_equal(int(player(accept_game, 1).cash), target_cash, "accepted 免費 leaves target cash unchanged")
		expect_equal(int(player(accept_game, 0).cash), caster_cash, "accepted 免費 transfers no cash")
		expect(not player(accept_game, 1).cards.has(FREE_CARD), "accepted 免費 consumes the defense card")
		expect_equal(card_supply(accept_game, FREE_CARD), free_supply + 1, "accepted 免費 returns its card to finite supply")
		expect(pending(accept_game).is_empty(), "accepted 免費 clears the pending response")
		expect(bool(Game.validate_save(accept_game.to_dict()).get("ok", false)), "accepted 免費 state remains save-valid")

	var decline_game: Object = fresh(74105)
	if decline_game == null:
		return
	stage_card(decline_game, 0, TAX_CARD)
	stage_card(decline_game, 1, FREE_CARD)
	set_cash(decline_game, 1, 5000)
	var decline_target_before: int = int(player(decline_game, 1).cash)
	var decline_caster_before: int = int(player(decline_game, 0).cash)
	var decline_supply: int = card_supply(decline_game, FREE_CARD)
	expect(bool(use_tax(decline_game, 1).get("ok", false)), "decline fixture enters 免費 response")
	var declined: Dictionary = respond(decline_game, true)
	expect(bool(declined.get("ok", false)), "human declines 免費")
	if bool(declined.get("ok", false)):
		var amount: int = int(floor(float(decline_target_before) * 0.2))
		expect_equal(int(player(decline_game, 1).cash), decline_target_before - amount, "declined 免費 pays the original tax")
		expect_equal(int(player(decline_game, 0).cash), decline_caster_before + amount, "declined 免費 credits the caster")
		expect(player(decline_game, 1).cards.has(FREE_CARD), "declined 免費 keeps the defense card")
		expect_equal(card_supply(decline_game, FREE_CARD), decline_supply, "declined 免費 leaves supply unchanged")
		expect(pending(decline_game).is_empty(), "declined 免費 clears the pending response")


func _test_tax_threshold_redirect_recompute_and_non_recursive_defenses() -> void:
	# Initial amount exactly 2,000 does not unlock 嫁禍 redirect.
	var boundary: Object = fresh(74106)
	if boundary == null:
		return
	set_cash(boundary, 1, 10000)
	stage_card(boundary, 0, TAX_CARD)
	stage_card(boundary, 1, FREE_CARD)
	stage_card(boundary, 1, SCAPEGOAT_CARD)
	expect(bool(use_tax(boundary, 1).get("ok", false)), "amount-2000 fixture enters 免費 response")
	var boundary_decline: Dictionary = respond(boundary, true)
	expect(bool(boundary_decline.get("ok", false)), "amount-2000 decline resolves directly")
	if bool(boundary_decline.get("ok", false)):
		expect(pending(boundary).is_empty(), "amount exactly 2000 cannot redirect")
		expect(player(boundary, 1).cards.has(SCAPEGOAT_CARD), "amount exactly 2000 preserves 嫁禍")
		expect_equal(int(player(boundary, 1).cash), 8000, "amount exactly 2000 pays original target")

	# A target whose initial amount is 2,001 may redirect only after declining
	# 免費.  The redirected player is charged directly even when that player
	# owns both defense cards.
	var redirect: Object = fresh(74107)
	if redirect == null:
		return
	set_cash(redirect, 1, 10005)
	set_cash(redirect, 2, 5001)
	stage_card(redirect, 0, TAX_CARD)
	stage_card(redirect, 1, FREE_CARD)
	stage_card(redirect, 1, SCAPEGOAT_CARD)
	stage_card(redirect, 2, FREE_CARD)
	stage_card(redirect, 2, SCAPEGOAT_CARD)
	var original_target_cash: int = int(player(redirect, 1).cash)
	var redirected_target_cash: int = int(player(redirect, 2).cash)
	var caster_cash: int = int(player(redirect, 0).cash)
	expect(bool(use_tax(redirect, 1).get("ok", false)), "amount-2001 fixture enters 免費 response")
	var redirect_prompt: Dictionary = respond(redirect, true, 1)
	expect(bool(redirect_prompt.get("ok", false)), "declining 免費 exposes 嫁禍 redirect")
	var redirect_pending: Dictionary = pending(redirect)
	expect_equal(str(redirect_pending.get("stage", "")), "redirect", "tax redirect uses the redirect stage")
	expect_equal(int(redirect_pending.get("amount", -1)), 2001, "redirect keeps the initial amount for its threshold")
	if not redirect_pending.is_empty():
		expect_rejected_atomic(redirect, "respond_finance", {"cancel": false}, "redirect response requires a target id")
		expect_rejected_atomic(redirect, "respond_finance", {"cancel": false, "target_id": "2"}, "redirect response rejects string target")
		expect_rejected_atomic(redirect, "respond_finance", {"cancel": false, "target_id": 99}, "redirect response rejects unavailable target")
		var target_response: Dictionary = respond(redirect, false, 2)
		expect(bool(target_response.get("ok", false)), "嫁禍 can select a second legal target")
		if bool(target_response.get("ok", false)):
			var recomputed: int = int(floor(float(redirected_target_cash) * 0.2))
			expect_equal(int(player(redirect, 1).cash), original_target_cash, "redirected original target pays nothing")
			expect_equal(int(player(redirect, 2).cash), redirected_target_cash - recomputed, "redirect recomputes tax from the new target cash")
			expect_equal(int(player(redirect, 0).cash), caster_cash + recomputed, "redirect credits the recomputed amount")
			expect(player(redirect, 2).cards.has(FREE_CARD) and player(redirect, 2).cards.has(SCAPEGOAT_CARD), "redirect bypasses recursive 免費 and 嫁禍")
			expect(not player(redirect, 1).cards.has(SCAPEGOAT_CARD), "redirect consumes only the original target 嫁禍")
			expect(pending(redirect).is_empty(), "redirect response clears pending finance")

	# Selecting the caster is legal, but a tax redirected to its caster transfers
	# zero and must not recurse through the caster's defenses.
	var self_redirect: Object = fresh(74108)
	if self_redirect == null:
		return
	set_cash(self_redirect, 1, 10005)
	stage_card(self_redirect, 0, TAX_CARD)
	stage_card(self_redirect, 1, FREE_CARD)
	stage_card(self_redirect, 1, SCAPEGOAT_CARD)
	stage_card(self_redirect, 0, IMMUNITY_CARD)
	stage_card(self_redirect, 0, REVENGE_CARD)
	var self_caster_cash: int = int(player(self_redirect, 0).cash)
	expect(bool(use_tax(self_redirect, 1).get("ok", false)), "self-redirect fixture enters 免費 response")
	expect(bool(respond(self_redirect, true).get("ok", false)), "self-redirect fixture reaches 嫁禍 response")
	if not pending(self_redirect).is_empty():
		var self_result: Dictionary = respond(self_redirect, false, 0)
		expect(bool(self_result.get("ok", false)), "嫁禍 can select the tax caster")
		if bool(self_result.get("ok", false)):
			expect_equal(int(player(self_redirect, 0).cash), self_caster_cash, "redirect to caster transfers zero")
			expect(player(self_redirect, 0).cards.has(IMMUNITY_CARD) and player(self_redirect, 0).cards.has(REVENGE_CARD), "tax redirect never invokes caster defenses")
			expect(pending(self_redirect).is_empty(), "self redirect clears pending finance")

	# 查稅 ignores 免罪 and 復仇 on the original target.
	var irrelevant: Object = fresh(74109)
	if irrelevant == null:
		return
	set_cash(irrelevant, 1, 5000)
	stage_card(irrelevant, 0, TAX_CARD)
	stage_card(irrelevant, 1, IMMUNITY_CARD)
	stage_card(irrelevant, 1, REVENGE_CARD)
	var irrelevant_result: Dictionary = use_tax(irrelevant, 1)
	expect(bool(irrelevant_result.get("ok", false)), "tax ignores immunity and revenge cards")
	if bool(irrelevant_result.get("ok", false)):
		var irrelevant_amount: int = int(floor(5000.0 * 0.2))
		expect_equal(int(player(irrelevant, 1).cash), 5000 - irrelevant_amount, "tax charges a target holding 免罪")
		expect(player(irrelevant, 1).cards.has(IMMUNITY_CARD) and player(irrelevant, 1).cards.has(REVENGE_CARD), "tax leaves irrelevant defense cards untouched")


func _test_ai_tax_fallback_and_dream_wait() -> void:
	# Only player one is an eligible tax target.  The AI must use its card and
	# leave the human target's 免費 choice waiting instead of silently consuming
	# it or selecting a detained/dead fallback.
	var game: Object = fresh(74110)
	if game == null:
		return
	stage_card(game, 0, TAX_CARD)
	stage_card(game, 1, FREE_CARD)
	game.call("_admit_player_status", 2, "hospital", 3)
	game.call("_admit_player_status", 3, "hospital", 3)
	game.set_player_ai(0, true)
	prepare(game, 0, "await_action", 0)
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "AI tax fixture validates before public AI turn")
	var ai_before: String = game.to_json()
	var ai_result: Dictionary = game.run_ai_turn()
	expect(bool(ai_result.get("ok", false)), "AI tax turn completes to a pending human response")
	expect(bool(ai_result.get("awaiting_response", false)), "AI tax reports awaiting human response")
	expect_equal(int(game.state.get("current_player", -1)), 0, "AI tax preserves the caster turn identity while waiting")
	expect_equal(tax_targets(game, 0), [1], "AI tax uses the sole eligible target")
	var ai_pending: Dictionary = pending(game)
	expect_equal(int(ai_pending.get("payer_id", -1)), 1, "AI pending payer is the human target")
	expect_equal(int(ai_pending.get("caster_id", -1)), 0, "AI pending caster remains the AI")
	expect(game.to_json() != ai_before, "AI tax changes state only by using the card and waiting")
	if not ai_pending.is_empty():
		var ai_accept: Dictionary = respond(game, false, 1)
		expect(bool(ai_accept.get("ok", false)), "human resolves the AI tax 免費 response")

	# Passive AI 免費 decisions use the original random threshold policy.  Tax
	# provides deterministic boundary amounts without depending on a random
	# trace: 20% of 40,000 is 8,000 and always exceeds the 3,000..5,999
	# threshold, while 20% of 10,000 is 2,000 and never reaches it.  A JSON
	# mirror must make the same public choice and preserve the same RNG state.
	var consume_game: Object = fresh(74112)
	if consume_game == null:
		return
	stage_card(consume_game, 0, TAX_CARD)
	stage_card(consume_game, 1, FREE_CARD)
	set_cash(consume_game, 1, 40000)
	consume_game.set_player_ai(1, true)
	prepare(consume_game, 0, "await_action", 0)
	expect(bool(Game.validate_save(consume_game.to_dict()).get("ok", false)), "AI high-tax fixture validates before public tax")
	var consume_mirror: Object = Game.from_dict(JSON.parse_string(consume_game.to_json()))
	expect(consume_mirror != null, "AI high-tax fixture reloads before public tax")
	var consume_result: Dictionary = use_tax(consume_game, 1)
	var consume_mirror_result: Dictionary = {}
	if consume_mirror != null:
		consume_mirror_result = use_tax(consume_mirror, 1)
	expect(bool(consume_result.get("ok", false)), "AI consumes 免費 when tax exceeds its threshold")
	if consume_mirror != null:
		expect(bool(consume_mirror_result.get("ok", false)), "reloaded AI high-tax choice succeeds")
	if bool(consume_result.get("ok", false)):
		expect_equal(int(player(consume_game, 1).cash), 40000, "AI 免費 prevents the high tax payment")
		expect(not player(consume_game, 1).cards.has(FREE_CARD), "AI high-tax choice consumes 免費")
		expect(pending(consume_game).is_empty(), "AI high-tax choice does not wait for a human")
	if consume_mirror != null:
		expect_equal(consume_mirror.to_json(), consume_game.to_json(), "AI high-tax choice has exact JSON replay")

	var decline_game: Object = fresh(74113)
	if decline_game == null:
		return
	stage_card(decline_game, 0, TAX_CARD)
	stage_card(decline_game, 1, FREE_CARD)
	set_cash(decline_game, 1, 10000)
	decline_game.set_player_ai(1, true)
	prepare(decline_game, 0, "await_action", 0)
	expect(bool(Game.validate_save(decline_game.to_dict()).get("ok", false)), "AI low-tax fixture validates before public tax")
	var decline_mirror: Object = Game.from_dict(JSON.parse_string(decline_game.to_json()))
	expect(decline_mirror != null, "AI low-tax fixture reloads before public tax")
	var decline_result: Dictionary = use_tax(decline_game, 1)
	var decline_mirror_result: Dictionary = {}
	if decline_mirror != null:
		decline_mirror_result = use_tax(decline_mirror, 1)
	expect(bool(decline_result.get("ok", false)), "AI declines 免費 when tax is below its threshold")
	if decline_mirror != null:
		expect(bool(decline_mirror_result.get("ok", false)), "reloaded AI low-tax choice succeeds")
	if bool(decline_result.get("ok", false)):
		expect_equal(int(player(decline_game, 1).cash), 8000, "AI low-tax choice pays the 2,000 tax")
		expect(player(decline_game, 1).cards.has(FREE_CARD), "AI low-tax choice preserves 免費")
		expect(pending(decline_game).is_empty(), "AI low-tax choice does not wait for a human")
	if decline_mirror != null:
		expect_equal(decline_mirror.to_json(), decline_game.to_json(), "AI low-tax choice has exact JSON replay")

	# A human dream target must also pause its restricted turn when the passive
	# 免費 response is requested.  The sleep counter/control identity survives
	# the response and can continue through the public sleep driver.
	var dream: Object = fresh(74111)
	if dream == null:
		return
	stage_card(dream, 0, TAX_CARD)
	stage_card(dream, 1, FREE_CARD)
	var dream_player: Dictionary = player(dream, 1)
	dream_player["dream_days"] = 4
	dream_player["winter_sleep_days"] = 0
	dream_player["vehicle"] = "walking"
	dream_player["dice_count"] = 1
	dream_player["dream_vehicle_backup"] = {"previous_vehicle": "walking", "previous_dice_count": 1}
	dream.call("_set_action_options", 0)
	expect(bool(Game.validate_save(dream.to_dict()).get("ok", false)), "dream tax fixture validates before public tax")
	var dream_tax: Dictionary = use_tax(dream, 1)
	expect(bool(dream_tax.get("ok", false)), "tax against a dreaming human reaches passive 免費")
	var dream_pending: Dictionary = pending(dream)
	expect(not dream_pending.is_empty(), "dreaming human 免費 pauses for a response")
	expect_equal(int(dream_player.get("dream_days", 0)), 4, "dream counter is unchanged while passive payment waits")
	if not dream_pending.is_empty():
		var dream_response: Dictionary = respond(dream, false, 1)
		expect(bool(dream_response.get("ok", false)), "dreaming human can accept passive 免費")
		expect_equal(int(dream_player.get("dream_days", 0)), 4, "accepting passive 免費 preserves the restricted turn")
		expect(dream_player.get("dream_vehicle_backup", {}).has("previous_vehicle"), "passive response preserves dream vehicle backup")
