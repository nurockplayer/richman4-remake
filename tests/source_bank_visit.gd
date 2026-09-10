extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/source_bank_visit_fixture.gd")

var _checks: int = 0
var _failures: int = 0
var _setup_failures: int = 0
var _definition: Dictionary = {}


func _initialize() -> void:
	_definition = Fixture.definition()
	_setup_expect(not _definition.is_empty(), "source bank fixture normalizes")
	var initial_game: Object = _new_game()
	if initial_game == null:
		_setup_expect(false, "source company game starts")
	else:
		# This is intentionally the first save assertion.  A RED from a malformed
		# fixture is a harness failure, not evidence for the encounter boundary.
		var initial_validation: Dictionary = Game.validate_save(initial_game.to_dict())
		_setup_expect(bool(initial_validation.get("ok", false)), "starting source company save validates: %s" % str(initial_validation.get("errors", [])))
	if _setup_failures > 0:
		_finish(2)
		return

	_test_public_surface()
	_test_straight_pass_pause_and_resume()
	_test_branch_pass_pause_and_resume()
	_test_bank_transaction_limits_and_atomicity()
	_test_consecutive_bank_pauses()
	_test_terminal_bank_landing_and_company_ownership()
	_test_sunday_ai_status_and_sleep_gates()
	_test_pending_save_roundtrip_and_malformed_tokens()
	_finish(1 if _failures > 0 else 0)


func _finish(exit_status: int) -> void:
	print("Source bank visit checks: %d, failures: %d, setup_failures: %d" % [_checks, _failures, _setup_failures])
	quit(exit_status)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _setup_expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		_setup_failures += 1
		push_error("SETUP FAIL: " + message)


func _new_game(with_statuses: bool = false, seed_value: int = 13501, player_count: int = 2) -> Object:
	var options: Dictionary = {
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	}
	if with_statuses:
		options["original_statuses"] = true
	var game: Object = Game.new_game_on_board(seed_value, player_count, _definition, options)
	if game == null:
		_setup_failures += 1
		push_error("SETUP FAIL: source company game returned null")
	return game


func _prepare_roll(game: Object, player_id: int, origin: int, previous: int = -1) -> void:
	var player: Dictionary = game.state["players"][player_id]
	game.state["current_player"] = player_id
	game.state["phase"] = "await_roll"
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	if game.state.has("pending_bank_visit"):
		game.state["pending_bank_visit"] = {}
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	if game.state.has("last_roll_total"):
		game.state["last_roll_total"] = 0
	game.state["bank_access"] = false
	game.state["bank_landing"] = false
	game.state["property_action_used"] = false
	player["position"] = origin
	player["previous_position"] = previous
	player["skip_turns"] = 0
	player["hospital_days"] = 0
	if player.has("prison_days"):
		player["prison_days"] = 0
	game._sync_state()
	game._set_action_options(player_id)


func _find_roll(total: int, origin: int, previous: int = -1, player_id: int = 0) -> Dictionary:
	for seed_value in range(1, 2000):
		var game: Object = _new_game(false, seed_value)
		if game == null:
			continue
		_prepare_roll(game, player_id, origin, previous)
		var result: Dictionary = game.roll(1)
		if bool(result.get("ok", false)) and int(result.get("total", -1)) == total:
			return {"game": game, "seed": seed_value, "result": result}
	return {}


func _method_argument_count(game: Object, method_name: String) -> int:
	for method_value in game.get_method_list():
		if typeof(method_value) != TYPE_DICTIONARY or str(method_value.get("name", "")) != method_name:
			continue
		var args: Variant = method_value.get("args", [])
		return args.size() if typeof(args) == TYPE_ARRAY else 0
	return -1


func _call_bank_method(game: Object, method_name: String, player_id: int = 0, node_id: int = -1) -> Dictionary:
	var argument_count: int = _method_argument_count(game, method_name)
	if argument_count < 0:
		return {"ok": false, "missing_method": true}
	if argument_count > 2:
		return {"ok": false, "unexpected_signature": true}
	var args: Array = []
	if argument_count >= 1:
		args.append(player_id)
	if argument_count >= 2:
		args.append(node_id)
	var value: Variant = Callable(game, method_name).callv(args)
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "invalid_result": true}
	return value


func _assert_method(game: Object, method_name: String) -> bool:
	var present: bool = _method_argument_count(game, method_name) >= 0
	_expect(present, "public %s method exists" % method_name)
	return present


func _event_count(game: Object, event_type: String) -> int:
	var count: int = 0
	for event_value in game.state.get("event_log", []):
		if typeof(event_value) == TYPE_DICTIONARY and str(event_value.get("type", "")) == event_type:
			count += 1
	return count


func _pending_token(game: Object) -> Variant:
	return game.state.get("pending_bank_visit", null)


func _assert_exact_token(token: Variant, kind: String, player_id: int, node_id: int, label: String) -> bool:
	var valid: bool = typeof(token) == TYPE_DICTIONARY
	if not valid:
		_expect(false, label + " has a dictionary token")
		return false
	var pending: Dictionary = token
	var keys: Array = pending.keys()
	keys.sort()
	_expect(keys == ["kind", "node_id", "player_id"], label + " token has exact keys")
	_expect(str(pending.get("kind", "")) == kind, label + " token kind")
	_expect(int(pending.get("player_id", -1)) == player_id, label + " token actor")
	_expect(int(pending.get("node_id", -1)) == node_id, label + " token node")
	return keys == ["kind", "node_id", "player_id"] and str(pending.get("kind", "")) == kind and int(pending.get("player_id", -1)) == player_id and int(pending.get("node_id", -1)) == node_id


func _assert_pass_pending(game: Object, node_id: int, previous_node: int, remaining: int, label: String) -> bool:
	var phase_valid: bool = _expect_phase(game, "await_bank", label + " pauses in await_bank")
	var token_valid: bool = _assert_exact_token(_pending_token(game), "pass", 0, node_id, label)
	# The remaining assertions describe a coherent pending token.  Returning on
	# the missing boundary keeps an ordinary-core RED qualified instead of
	# reporting cascading fixture-shape failures.
	if not phase_valid or not token_valid:
		return false
	var valid: bool = true
	valid = token_valid and valid
	valid = _expect_state_value(game.state.get("bank_access", false), true, label + " keeps bank access") and valid
	valid = _expect_state_value(game.state.get("bank_landing", false), false, label + " is a pass rather than landing") and valid
	valid = _expect_state_value(game.state.get("route_options", []), [], label + " clears route options") and valid
	var pending_movement: Variant = game.state.get("pending_movement", null)
	if typeof(pending_movement) != TYPE_DICTIONARY:
		_expect(false, label + " keeps a pending movement dictionary")
		valid = false
	else:
		var pending: Dictionary = pending_movement
		valid = _expect_state_value(int(pending.get("player_id", -1)), 0, label + " pending movement actor") and valid
		valid = _expect_state_value(int(pending.get("current_node", -1)), node_id, label + " pending movement node") and valid
		valid = _expect_state_value(int(pending.get("previous_node", -1)), previous_node, label + " pending movement previous node") and valid
	valid = _expect_state_value(int(game.state.get("remaining_steps", -1)), remaining, label + " preserves positive remaining steps") and valid
	valid = _expect_state_value(int(game.state.players[0].position), node_id, label + " actor is parked on bank") and valid
	var validation: Dictionary = Game.validate_save(game.to_dict())
	valid = _expect_state_value(bool(validation.get("ok", false)), true, label + " pending save validates") and valid
	return valid


func _assert_landing_pending(game: Object, owner_id: int, label: String) -> bool:
	var phase_valid: bool = _expect_phase(game, "await_action", label + " remains in await_action")
	var token_valid: bool = _assert_exact_token(_pending_token(game), "landing", 0, 6, label)
	if not phase_valid or not token_valid:
		return false
	var valid: bool = true
	valid = token_valid and valid
	valid = _expect_state_value(game.state.get("bank_access", false), true, label + " keeps bank access") and valid
	valid = _expect_state_value(game.state.get("bank_landing", false), true, label + " records a bank landing") and valid
	valid = _expect_state_value(game.state.get("route_options", []), [], label + " has no route options") and valid
	valid = _expect_state_value(game.state.get("remaining_steps", -1), 0, label + " landing has no remaining steps") and valid
	valid = _expect_state_value(game.state.get("pending_movement", {}), {}, label + " landing has no pending movement") and valid
	valid = _expect_state_value(int(game.state.players[0].position), 6, label + " actor is at company bank") and valid
	var allowed: Array = ["deposit", "withdraw", "take_loan", "repay_loan", "take_special_finance", "repay_special_finance"]
	for action_value in game.state.get("action_options", []):
		valid = _expect_state_value(allowed.has(str(action_value)), true, label + " exposes only bank action %s" % str(action_value)) and valid
	if owner_id == 0:
		valid = _expect_state_value(game.state.get("action_options", []).has("take_special_finance"), true, label + " owner sees chairman financing") and valid
	else:
		valid = _expect_state_value(game.state.get("action_options", []).has("take_special_finance"), false, label + " nonowner cannot take chairman financing") and valid
	return valid


func _expect_phase(game: Object, expected: String, message: String) -> bool:
	return _expect_state_value(str(game.state.get("phase", "")), expected, message)


func _expect_state_value(actual: Variant, expected: Variant, message: String) -> bool:
	var matched: bool = actual == expected
	_expect(matched, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])
	return matched


func _assert_no_later_effects(game: Object, points_before: int, cards_before: int, rng_before: String, label: String) -> void:
	_expect(_event_count(game, "points_passed") == points_before, label + " has no points effect before bank close")
	_expect(_event_count(game, "card_passed") == cards_before, label + " has no card/RNG effect before bank close")
	_expect(str(game.to_dict().get("rng_state_text", "")) == rng_before, label + " RNG is stable while bank is open")


func _expect_atomic_rejection(game: Object, action: String, params: Dictionary, label: String) -> void:
	var before: String = game.to_json()
	var result: Dictionary = game.choose_action(action, params)
	_expect(not bool(result.get("ok", false)), label + " rejects")
	_expect(game.to_json() == before, label + " is atomic")


func _test_public_surface() -> void:
	var game: Object = _new_game()
	if game == null:
		return
	_assert_method(game, "resume_bank_visit")
	_assert_method(game, "complete_bank_visit")
	_expect(game.has_method("bank_transfer_limit"), "public bank transfer limit remains available")


func _test_straight_pass_pause_and_resume() -> void:
	var found: Dictionary = _find_roll(2, 0, -1)
	_expect(not found.is_empty(), "straight bank fixture finds a deterministic two-step roll")
	if found.is_empty():
		return
	var game: Object = found["game"]
	var result: Dictionary = found["result"]
	_expect(bool(result.get("ok", false)), "straight roll succeeds through public API")
	var points_before: int = _event_count(game, "points_passed")
	var cards_before: int = _event_count(game, "card_passed")
	var rng_before: String = str(game.to_dict().get("rng_state_text", ""))
	var pending_ok: bool = _assert_pass_pending(game, 1, 0, 1, "straight pass")
	if not pending_ok:
		return
	_expect(_event_count(game, "bank_passed") == 1, "straight pass records one bank passage")
	_assert_no_later_effects(game, points_before, cards_before, rng_before, "straight pass")
	_expect_atomic_rejection(game, "end_turn", {}, "pass bank rejects ending the turn")
	var before_resume: String = game.to_json()
	var resumed: Dictionary = _call_bank_method(game, "resume_bank_visit", 0, 1)
	_expect(bool(resumed.get("ok", false)), "straight pass resumes through the public seam")
	_expect(game.state.get("pending_bank_visit", {}).is_empty(), "straight resume consumes the token")
	_expect(game.state.get("pending_movement", {}).is_empty() and game.state.get("route_options", []).is_empty(), "straight resume clears completed movement")
	_expect(int(game.state.get("remaining_steps", -1)) == 0, "straight resume consumes the remaining step")
	_expect(int(game.state.players[0].position) == 2, "straight resume reaches the points tile")
	_expect(_event_count(game, "points_landed") == 1, "straight resume applies the deferred landing effect once")
	_expect(_event_count(game, "bank_passed") == 1, "straight resume does not duplicate bank passage")
	var after_resume: String = game.to_json()
	_expect(after_resume != before_resume, "straight resume changes state after close")
	var repeated: Dictionary = _call_bank_method(game, "resume_bank_visit", 0, 1)
	_expect(not bool(repeated.get("ok", false)), "straight duplicate resume rejects")
	_expect(game.to_json() == after_resume, "straight duplicate resume is atomic")


func _test_branch_pass_pause_and_resume() -> void:
	var found: Dictionary = _find_roll(2, 2, 1)
	_expect(not found.is_empty(), "branch bank fixture finds a deterministic two-step roll")
	if found.is_empty():
		return
	var game: Object = found["game"]
	_expect(_expect_phase(game, "await_route", "branch roll waits for route choice"), "branch route phase is public")
	_expect_state_value(game.state.get("route_options", []), [3, 4], "branch route options are canonical")
	var points_before: int = _event_count(game, "points_passed")
	var cards_before: int = _event_count(game, "card_passed")
	var rng_before: String = str(game.to_dict().get("rng_state_text", ""))
	var choice: Dictionary = game.choose_route(3)
	_expect(bool(choice.get("ok", false)), "branch chooses the bank route through public API")
	var pending_ok: bool = _assert_pass_pending(game, 3, 2, 1, "branch chosen pass")
	if not pending_ok:
		return
	_expect(_event_count(game, "bank_passed") == 1, "branch chosen pass records one passage")
	_assert_no_later_effects(game, points_before, cards_before, rng_before, "branch chosen pass")
	var resumed: Dictionary = _call_bank_method(game, "resume_bank_visit", 0, 3)
	_expect(bool(resumed.get("ok", false)), "branch pass resumes after close")
	_expect(game.state.get("pending_bank_visit", {}).is_empty(), "branch resume consumes its token")
	_expect(int(game.state.players[0].position) == 5, "branch resume reaches the shared card tile")
	_expect(_event_count(game, "bank_passed") == 1, "branch resume does not duplicate the bank event")
	var after_resume: String = game.to_json()
	var repeated: Dictionary = _call_bank_method(game, "resume_bank_visit", 0, 3)
	_expect(not bool(repeated.get("ok", false)), "branch duplicate resume rejects")
	_expect(game.to_json() == after_resume, "branch duplicate resume is atomic")


func _set_bank_balances(game: Object, cash: int, deposit: int, bank_cash: int) -> void:
	var player: Dictionary = game.state.players[0]
	player["cash"] = cash
	player["deposit"] = deposit
	var deposits: int = 0
	for candidate in game.state.players:
		deposits += int(candidate.get("deposit", 0))
	game.state.bank["cash"] = bank_cash
	game.state.bank["deposits"] = deposits
	game._set_action_options(0)


func _test_bank_transaction_limits_and_atomicity() -> void:
	var found: Dictionary = _find_roll(2, 0, -1)
	_expect(not found.is_empty(), "transaction fixture finds a pending pass roll")
	if found.is_empty():
		return
	var game: Object = found["game"]
	if not _assert_pass_pending(game, 1, 0, 1, "transaction pending pass"):
		return
	_set_bank_balances(game, 90, 20, 100)
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), "transaction pending save remains valid after balance staging")
	_expect(game.bank_transfer_limit("deposit", 0) == 90, "deposit limit is the exact available amount")
	_expect(game.bank_transfer_limit("withdraw", 0) == 20, "withdraw limit starts at the existing deposit")
	_expect(game.bank_transfer_limit("deposit", 1) == 0, "noncurrent actor has no bank limit during a pending visit")
	var allowed: Array = ["deposit", "withdraw"]
	for action_value in game.state.get("action_options", []):
		_expect(allowed.has(str(action_value)), "pass exposes only transfer action %s" % str(action_value))
	for forbidden_action in ["end_turn", "buy_stock", "sell_stock", "take_loan", "repay_loan", "use_card", "choose_research"]:
		_expect_atomic_rejection(game, forbidden_action, {}, "pass rejects " + forbidden_action)
	for amount in [0, -1, 91, "1", true, 1.5, NAN, INF, {}, []]:
		_expect_atomic_rejection(game, "deposit", {"amount": amount}, "invalid deposit %s" % str(amount))
	var deposited: Dictionary = game.choose_action("deposit", {"amount": 90})
	_expect(bool(deposited.get("ok", false)), "deposit accepts the exact pending maximum")
	_expect(game.state.players[0].cash == 0 and game.state.players[0].deposit == 110, "deposit updates player balances exactly")
	_expect(game.state.bank.cash == 190, "deposit increases bank cash exactly")
	_expect(game.bank_transfer_limit("withdraw", 0) == 110, "withdraw limit follows the updated deposit")
	var withdrawn: Dictionary = game.choose_action("withdraw", {"amount": 110})
	_expect(bool(withdrawn.get("ok", false)), "withdraw accepts the exact pending maximum")
	_expect(game.state.players[0].cash == 110 and game.state.players[0].deposit == 0, "withdraw updates player balances exactly")
	_expect(game.state.bank.cash == 80, "withdraw decreases bank cash exactly")
	for amount in [0, -1, 1, "1", true, 1.5, NAN, INF, {}, []]:
		_expect_atomic_rejection(game, "withdraw", {"amount": amount}, "invalid withdraw %s" % str(amount))
	# The preceding withdrawal restored cash; explicitly prepare the zero-cash case.
	_set_bank_balances(game, 0, 0, 80)
	_expect_atomic_rejection(game, "deposit", {"amount": 1}, "empty-cash deposit rejects")


func _test_consecutive_bank_pauses() -> void:
	var found: Dictionary = _find_roll(4, 0, -1)
	_expect(not found.is_empty(), "consecutive bank fixture finds a deterministic four-step roll")
	if found.is_empty():
		return
	var game: Object = found["game"]
	if not _assert_pass_pending(game, 1, 0, 3, "first consecutive pass"):
		return
	var first_resume: Dictionary = _call_bank_method(game, "resume_bank_visit", 0, 1)
	_expect(bool(first_resume.get("ok", false)), "first consecutive pass resumes")
	_expect(_expect_phase(game, "await_route", "first resume exposes the next branch"), "first resume preserves route boundary")
	_expect_state_value(game.state.get("remaining_steps", -1), 2, "first resume preserves the two-step suffix")
	_expect_state_value(_event_count(game, "points_passed"), 1, "first resume applies the deferred points pass once")
	var second_choice: Dictionary = game.choose_route(3)
	_expect(bool(second_choice.get("ok", false)), "second bank route is chosen")
	if not _assert_pass_pending(game, 3, 2, 1, "second consecutive pass"):
		return
	_expect(_event_count(game, "bank_passed") == 2, "consecutive passes record two bank events")
	var second_resume: Dictionary = _call_bank_method(game, "resume_bank_visit", 0, 3)
	_expect(bool(second_resume.get("ok", false)), "second consecutive pass resumes")
	_expect(game.state.get("pending_bank_visit", {}).is_empty(), "second resume consumes only the second token")


func _buy_company_share(game: Object, buyer_id: int) -> bool:
	game.state["current_player"] = buyer_id
	game.state["phase"] = "await_roll"
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game._set_action_options(buyer_id)
	var bought: Dictionary = game.choose_action("buy_stock", {"symbol": "s01", "quantity": 1})
	_expect(bool(bought.get("ok", false)), "company owner fixture buys one source share")
	return bool(bought.get("ok", false))


func _make_landing_game(owner_id: int) -> Object:
	for seed_value in range(1, 2000):
		var game: Object = _new_game(false, seed_value)
		if game == null or not _buy_company_share(game, owner_id):
			continue
		_prepare_roll(game, 0, 5, 4)
		var rolled: Dictionary = game.roll(1)
		if not bool(rolled.get("ok", false)) or int(rolled.get("total", -1)) != 1:
			continue
		var route: Dictionary = game.choose_route(6)
		if bool(route.get("ok", false)) and int(game.state.players[0].position) == 6:
			return game
	return null


func _test_terminal_bank_landing_and_company_ownership() -> void:
	for owner_id in [0, 1]:
		var game: Object = _make_landing_game(owner_id)
		_expect(game != null, "type-7 %s landing fixture starts" % ("owner" if owner_id == 0 else "nonowner"))
		if game == null:
			continue
		var before_landing: String = game.to_json()
		var pending_ok: bool = _assert_landing_pending(game, owner_id, "type-7 %s landing" % ("owner" if owner_id == 0 else "nonowner"))
		if not pending_ok:
			continue
		_expect(_event_count(game, "bank_passed") == 0, "terminal type-7 bank has no pass event")
		for forbidden_action in ["end_turn", "buy_stock", "sell_stock", "use_card", "choose_research", "buy", "upgrade"]:
			_expect_atomic_rejection(game, forbidden_action, {}, "landing rejects " + forbidden_action)
		var before_close: Dictionary = game.to_dict()
		var completed: Dictionary = _call_bank_method(game, "complete_bank_visit", 0, 6)
		_expect(bool(completed.get("ok", false)), "type-7 landing completes through the public seam")
		_expect(game.state.get("pending_bank_visit", {}).is_empty(), "type-7 completion consumes the landing token")
		_expect(int(game.state.get("turn", -1)) == int(before_close.get("turn", -2)), "bank completion does not advance the turn")
		_expect(int(game.state.get("round", -1)) == int(before_close.get("round", -2)), "bank completion does not advance the round")
		_expect(str(game.to_dict().get("rng_state_text", "")) == str(before_close.get("rng_state_text", "")), "bank completion does not consume RNG")
		_expect(game.state.players[0].cash == before_close.players[0].cash and game.state.players[0].deposit == before_close.players[0].deposit, "bank completion does not change balances")
		var after_close: String = game.to_json()
		_expect(after_close != before_landing, "type-7 close consumes observable pending state")
		var repeated: Dictionary = _call_bank_method(game, "complete_bank_visit", 0, 6)
		_expect(not bool(repeated.get("ok", false)), "type-7 duplicate completion rejects")
		_expect(game.to_json() == after_close, "type-7 duplicate completion is atomic")


func _test_sunday_ai_status_and_sleep_gates() -> void:
	var sunday_seed: int = 1
	var sunday_roll: Dictionary = _find_roll(1, 0, -1)
	if not sunday_roll.is_empty():
		sunday_seed = int(sunday_roll.get("seed", 1))
	var sunday: Object = _new_game(false, sunday_seed)
	if sunday != null:
		_prepare_roll(sunday, 0, 0, -1)
		sunday.state["weekday"] = 7
		sunday._set_action_options(0)
		var result: Dictionary = sunday.roll(1)
		_expect(bool(result.get("ok", false)), "Sunday roll remains executable")
		_expect(not sunday.state.has("pending_bank_visit") or sunday.state.pending_bank_visit.is_empty(), "Sunday never opens a bank token")
		_expect(str(sunday.state.get("phase", "")) != "await_bank", "Sunday never enters await_bank")

	var ai: Object = _new_game(false, 13502)
	if ai != null:
		_prepare_roll(ai, 1, 0, -1)
		var ai_result: Dictionary = ai.roll(1)
		_expect(bool(ai_result.get("ok", false)), "AI roll remains executable")
		_expect(not ai.state.has("pending_bank_visit") or ai.state.pending_bank_visit.is_empty(), "AI never opens a human bank token")
		_expect(str(ai.state.get("phase", "")) != "await_bank", "AI never enters await_bank")

	var status: Object = _new_game(true, 13503)
	if status != null:
		_prepare_roll(status, 0, 0, -1)
		status.state.players[0]["prison_days"] = 2
		status._set_action_options(0)
		var status_result: Dictionary = status.roll(1)
		_expect(bool(status_result.get("ok", false)), "detained status roll remains executable")
		_expect(bool(status_result.get("skipped", false)), "detained status consumes the roll without movement")
		_expect(not status.state.has("pending_bank_visit") or status.state.pending_bank_visit.is_empty(), "detained status never opens a bank token")
		_expect(str(status.state.get("phase", "")) != "await_bank", "detained status never enters await_bank")

	var sleeping: Object = _new_game(false, 13504)
	if sleeping != null:
		_prepare_roll(sleeping, 0, 0, -1)
		sleeping.state.players[0]["winter_sleep_days"] = 2
		var sleeping_result: Dictionary = sleeping.roll(1)
		_expect(not bool(sleeping_result.get("ok", false)), "sleep gate rejects direct human roll")
		_expect(not sleeping.state.has("pending_bank_visit") or sleeping.state.pending_bank_visit.is_empty(), "sleep gate never opens a bank token")
		_expect(str(sleeping.state.get("phase", "")) != "await_bank", "sleep gate never enters await_bank")


func _reject_save(data: Dictionary, label: String) -> void:
	var validation: Dictionary = Game.validate_save(data)
	_expect(not bool(validation.get("ok", false)), label + " validator rejects")
	_expect(Game.from_dict(data) == null, label + " loader rejects")


func _test_pending_save_roundtrip_and_malformed_tokens() -> void:
	var pass_found: Dictionary = _find_roll(2, 0, -1)
	_expect(not pass_found.is_empty(), "save fixture finds a pass token")
	if pass_found.is_empty():
		return
	var pass_game: Object = pass_found["game"]
	if not _assert_pass_pending(pass_game, 1, 0, 1, "save pass"):
		return
	var saved_json: String = pass_game.to_json()
	var restored: Object = Game.from_dict(JSON.parse_string(saved_json))
	_expect(restored != null, "pending pass JSON reloads")
	if restored != null:
		_expect(restored.to_json() == saved_json, "pending pass JSON roundtrip is byte-identical")
		var first_resume: Dictionary = _call_bank_method(pass_game, "resume_bank_visit", 0, 1)
		var second_resume: Dictionary = _call_bank_method(restored, "resume_bank_visit", 0, 1)
		_expect(bool(first_resume.get("ok", false)) and bool(second_resume.get("ok", false)), "loaded and fresh pending passes resume")
		_expect(pass_game.to_json() == restored.to_json(), "loaded and fresh pending passes have identical continuation")

	var base: Dictionary = JSON.parse_string(saved_json)
	for value in [null, [], "pending", 0]:
		var wrong_top_level: Dictionary = base.duplicate(true)
		wrong_top_level["pending_bank_visit"] = value
		_reject_save(wrong_top_level, "pass token top-level type " + str(value))
	var missing_key: Dictionary = base.duplicate(true)
	missing_key.pending_bank_visit.erase("node_id")
	_reject_save(missing_key, "pass token missing node")
	var extra_key: Dictionary = base.duplicate(true)
	extra_key.pending_bank_visit["unexpected"] = true
	_reject_save(extra_key, "pass token extra key")
	var wrong_kind: Dictionary = base.duplicate(true)
	wrong_kind.pending_bank_visit["kind"] = "other"
	_reject_save(wrong_kind, "pass token invalid kind")
	var wrong_actor: Dictionary = base.duplicate(true)
	wrong_actor.pending_bank_visit["player_id"] = 1
	_reject_save(wrong_actor, "pass token wrong actor")
	var wrong_node: Dictionary = base.duplicate(true)
	wrong_node.pending_bank_visit["node_id"] = 2
	_reject_save(wrong_node, "pass token wrong node")
	var wrong_phase: Dictionary = base.duplicate(true)
	wrong_phase["phase"] = "await_action"
	_reject_save(wrong_phase, "pass token wrong phase")
	var orphan: Dictionary = base.duplicate(true)
	orphan["pending_bank_visit"] = {}
	_reject_save(orphan, "await_bank without token")
	var route_options: Dictionary = base.duplicate(true)
	route_options["route_options"] = [2]
	_reject_save(route_options, "pass token with route options")
	var zero_remaining: Dictionary = base.duplicate(true)
	zero_remaining["remaining_steps"] = 0
	_reject_save(zero_remaining, "pass token with zero remaining")
	var empty_movement: Dictionary = base.duplicate(true)
	empty_movement["pending_movement"] = {}
	_reject_save(empty_movement, "pass token without pending movement")
	var landing_flag: Dictionary = base.duplicate(true)
	landing_flag["bank_landing"] = true
	_reject_save(landing_flag, "pass token with landing flag")
	var position_mismatch: Dictionary = base.duplicate(true)
	position_mismatch.players[0]["position"] = 2
	_reject_save(position_mismatch, "pass token position mismatch")

	var invalid_action_game: Object = Game.from_dict(base)
	if _assert_pass_pending(invalid_action_game, 1, 0, 1, "resume validation"):
		invalid_action_game.state["current_player"] = 1
		var wrong_actor_before: String = invalid_action_game.to_json()
		var wrong_actor_result: Dictionary = _call_bank_method(invalid_action_game, "resume_bank_visit", 0, 1)
		_expect(not bool(wrong_actor_result.get("ok", false)), "resume rejects a wrong current actor")
		_expect(invalid_action_game.to_json() == wrong_actor_before, "wrong-actor resume is atomic")
		invalid_action_game.state["current_player"] = 0

		var wrong_node_game: Object = Game.from_dict(base)
		wrong_node_game.state.players[0]["position"] = 2
		var node_before: String = wrong_node_game.to_json()
		var wrong_node_result: Dictionary = _call_bank_method(wrong_node_game, "resume_bank_visit", 0, 1)
		_expect(not bool(wrong_node_result.get("ok", false)), "resume rejects a stale current node")
		_expect(wrong_node_game.to_json() == node_before, "stale-node resume is atomic")

		var wrong_phase_game: Object = Game.from_dict(base)
		wrong_phase_game.state["phase"] = "await_action"
		var phase_before: String = wrong_phase_game.to_json()
		var wrong_phase_result: Dictionary = _call_bank_method(wrong_phase_game, "resume_bank_visit", 0, 1)
		_expect(not bool(wrong_phase_result.get("ok", false)), "resume rejects a stale phase")
		_expect(wrong_phase_game.to_json() == phase_before, "wrong-phase resume is atomic")

	var landing_game: Object = _make_landing_game(0)
	_expect(landing_game != null, "malformed landing fixture starts")
	if landing_game == null:
		return
	if not _assert_landing_pending(landing_game, 0, "landing save"):
		return
	var landing_base: Dictionary = JSON.parse_string(landing_game.to_json())
	var landing_wrong_kind: Dictionary = landing_base.duplicate(true)
	landing_wrong_kind.pending_bank_visit["kind"] = "pass"
	_reject_save(landing_wrong_kind, "landing token wrong kind")
	var landing_wrong_actor: Dictionary = landing_base.duplicate(true)
	landing_wrong_actor.pending_bank_visit["player_id"] = 1
	_reject_save(landing_wrong_actor, "landing token wrong actor")
	var landing_wrong_node: Dictionary = landing_base.duplicate(true)
	landing_wrong_node.pending_bank_visit["node_id"] = 1
	_reject_save(landing_wrong_node, "landing token wrong node")
	var landing_extra_key: Dictionary = landing_base.duplicate(true)
	landing_extra_key.pending_bank_visit["unexpected"] = true
	_reject_save(landing_extra_key, "landing token extra key")
	var landing_not_bank: Dictionary = landing_base.duplicate(true)
	landing_not_bank["bank_landing"] = false
	_reject_save(landing_not_bank, "landing token without bank landing")
	var landing_remaining: Dictionary = landing_base.duplicate(true)
	landing_remaining["remaining_steps"] = 1
	_reject_save(landing_remaining, "landing token with remaining steps")
	var landing_movement: Dictionary = landing_base.duplicate(true)
	landing_movement["pending_movement"] = {"player_id": 0, "current_node": 6, "previous_node": 5}
	_reject_save(landing_movement, "landing token with pending movement")
