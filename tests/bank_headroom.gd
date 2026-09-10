extends SceneTree

## Issue #104 focused core acceptance.
##
## Every fixture starts as a valid save.  The large-value cases then exercise
## the public deposit/withdraw boundary against each destination cap, exact
## limit success, and zero headroom.  Rejections must leave the complete JSON
## state, phase, RNG, and event history unchanged.

const Game = preload("res://game/core/game_state.gd")
const MAX_BALANCE: int = 1000000000000

var checks: int = 0
var failures: int = 0
var qualified_red: int = 0


func _initialize() -> void:
	_test_public_limit_query()
	_test_deposit_source_and_destination_caps()
	_test_withdraw_source_and_destination_caps()
	_test_zero_headroom_is_rejected_atomically()
	print("Bank headroom checks: %d, failures: %d, qualified_red: %d" % [checks, failures, qualified_red])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_game(seed_value: int) -> Object:
	var game: Object = Game.new_game(seed_value, 2)
	_expect(game != null, "standard bank fixture starts")
	return game


func _prepare_action(game: Object, cash: int, deposit: int, bank_cash: int, bank_deposits: int) -> void:
	var player: Dictionary = game.state["players"][0]
	player["cash"] = cash
	player["deposit"] = deposit
	var bank: Dictionary = game.state["bank"]
	bank["cash"] = bank_cash
	bank["deposits"] = bank_deposits
	game.state["bank"] = bank
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["bank_access"] = true
	game.state["bank_landing"] = false
	game.state["property_action_used"] = false
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game._sync_state()
	game._set_action_options(0)


func _valid_save(game: Object, label: String) -> bool:
	var serialized: Dictionary = game.to_dict()
	var validation: Dictionary = Game.validate_save(serialized)
	var ok := bool(validation.get("ok", false))
	_expect(ok, label + " starts from a valid save: " + str(validation.get("errors", [])))
	var restored: Object = Game.from_dict(serialized)
	_expect(restored != null, label + " loads through Game.from_dict")
	if restored != null:
		_expect_equal(restored.to_json(), game.to_json(), label + " survives JSON round-trip")
	return ok


func _expected_limit(action: String, cash: int, deposit: int, bank_cash: int, bank_deposits: int) -> int:
	if action == "deposit":
		return mini(cash, mini(MAX_BALANCE - deposit, mini(MAX_BALANCE - bank_cash, MAX_BALANCE - bank_deposits)))
	if action == "withdraw":
		return mini(deposit, mini(bank_cash, MAX_BALANCE - cash))
	return 0


func _assert_limit_query(game: Object, action: String, expected: int, label: String) -> void:
	if not game.has_method("bank_transfer_limit"):
		_expect(false, "public bank_transfer_limit query exists for " + label)
		return
	_expect_equal(int(game.call("bank_transfer_limit", action)), expected, label + " reports the shared legal limit")


func _assert_rejected_atomic(game: Object, action: String, amount: int, label: String) -> void:
	_expect(_valid_save(game, label + " before rejection"), label + " is a qualified valid-save fixture")
	var before_json: String = game.to_json()
	var before_snapshot: Dictionary = game.state.duplicate(true)
	var before_phase: String = str(game.state.get("phase", ""))
	var before_rng: String = str(game.to_dict().get("rng_state_text", ""))
	var before_events: Array = game.state.get("event_log", []).duplicate(true)
	var before_last_event: Dictionary = game.state.get("last_event", {}).duplicate(true)
	var result: Dictionary = game.choose_action(action, {"amount": amount})
	if bool(result.get("ok", false)):
		qualified_red += 1
		print("QUALIFIED RED: %s accepted over-limit amount %d" % [label, amount])
	_expect(not bool(result.get("ok", false)), label + " rejects the over-limit public request")
	_expect_equal(game.to_json(), before_json, label + " preserves byte-identical state")
	_expect_equal(game.state, before_snapshot, label + " preserves all state fields")
	_expect_equal(str(game.state.get("phase", "")), before_phase, label + " preserves phase")
	_expect_equal(str(game.to_dict().get("rng_state_text", "")), before_rng, label + " preserves RNG continuation")
	_expect_equal(game.state.get("event_log", []), before_events, label + " appends no event")
	_expect_equal(game.state.get("last_event", {}), before_last_event, label + " preserves last event")
	var after_validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(after_validation.get("ok", false)), label + " remains saveable after rejection: " + str(after_validation.get("errors", [])))


func _assert_exact_success(game: Object, action: String, amount: int, label: String) -> void:
	_expect(_valid_save(game, label + " before success"), label + " is a qualified valid-save fixture")
	var result: Dictionary = game.choose_action(action, {"amount": amount})
	_expect(bool(result.get("ok", false)), label + " accepts exact legal limit: " + str(result.get("message", "")))
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), label + " remains saveable after exact transfer: " + str(validation.get("errors", [])))


func _test_public_limit_query() -> void:
	var game := _new_game(10401)
	if game == null:
		return
	_prepare_action(game, 700, 200, 300, 200)
	_assert_limit_query(game, "deposit", 700, "deposit source-limited query")
	_prepare_action(game, 700, 200, 300, 200)
	_assert_limit_query(game, "withdraw", 200, "withdraw source-limited query")
	_assert_limit_query(game, "unknown", 0, "unknown transfer query")


func _test_deposit_source_and_destination_caps() -> void:
	var source := _new_game(10402)
	if source != null:
		_prepare_action(source, 25, 0, 100, 0)
		_assert_limit_query(source, "deposit", 25, "deposit cash source cap")
		_assert_exact_success(source, "deposit", 25, "deposit sub-500 exact source amount")

	var cases: Array = [
		{"label": "deposit player-account headroom", "cash": 100, "deposit": MAX_BALANCE - 40, "bank_cash": 0, "bank_deposits": 0, "limit": 40},
		{"label": "deposit bank-cash headroom", "cash": 100, "deposit": 0, "bank_cash": MAX_BALANCE - 30, "bank_deposits": 0, "limit": 30},
		{"label": "deposit aggregate headroom", "cash": 100, "deposit": 0, "bank_cash": 0, "bank_deposits": MAX_BALANCE - 20, "limit": 20},
	]
	var seed := 10410
	for specification in cases:
		var game := _new_game(seed)
		seed += 1
		if game == null:
			continue
		_prepare_action(game, specification.cash, specification.deposit, specification.bank_cash, specification.bank_deposits)
		var limit := int(specification.limit)
		_assert_limit_query(game, "deposit", limit, str(specification.label))
		_assert_rejected_atomic(game, "deposit", limit + 1, str(specification.label))
		var exact := _new_game(seed)
		seed += 1
		if exact == null:
			continue
		_prepare_action(exact, specification.cash, specification.deposit, specification.bank_cash, specification.bank_deposits)
		_assert_exact_success(exact, "deposit", limit, str(specification.label))


func _test_withdraw_source_and_destination_caps() -> void:
	var source_deposit := _new_game(10420)
	if source_deposit != null:
		_prepare_action(source_deposit, 0, 25, 100, 25)
		_assert_limit_query(source_deposit, "withdraw", 25, "withdraw deposit source cap")
		_assert_exact_success(source_deposit, "withdraw", 25, "withdraw sub-500 exact source amount")

	var source_bank := _new_game(10421)
	if source_bank != null:
		_prepare_action(source_bank, 0, 100, 30, 100)
		_assert_limit_query(source_bank, "withdraw", 30, "withdraw bank-cash source cap")
		_assert_exact_success(source_bank, "withdraw", 30, "withdraw exact bank-cash source amount")

	var game := _new_game(10422)
	if game != null:
		_prepare_action(game, MAX_BALANCE - 20, 100, 100, 100)
		_assert_limit_query(game, "withdraw", 20, "withdraw player-account headroom")
		_assert_rejected_atomic(game, "withdraw", 21, "withdraw player-account headroom")

	var exact := _new_game(10423)
	if exact != null:
		_prepare_action(exact, MAX_BALANCE - 20, 100, 100, 100)
		_assert_exact_success(exact, "withdraw", 20, "withdraw player-account headroom")


func _test_zero_headroom_is_rejected_atomically() -> void:
	var deposit := _new_game(10430)
	if deposit != null:
		_prepare_action(deposit, 50, MAX_BALANCE, 0, MAX_BALANCE)
		_assert_limit_query(deposit, "deposit", 0, "deposit zero destination headroom")
		_expect(not deposit.state.get("action_options", []).has("deposit"), "deposit zero destination headroom hides the unavailable action")
		_assert_rejected_atomic(deposit, "deposit", 1, "deposit zero destination headroom")

	var withdraw := _new_game(10431)
	if withdraw != null:
		_prepare_action(withdraw, MAX_BALANCE, 50, 50, 50)
		_assert_limit_query(withdraw, "withdraw", 0, "withdraw zero destination headroom")
		_expect(not withdraw.state.get("action_options", []).has("withdraw"), "withdraw zero destination headroom hides the unavailable action")
		_assert_rejected_atomic(withdraw, "withdraw", 1, "withdraw zero destination headroom")
