extends SceneTree

## Issue #78 acceptance contract for the ID8 拍賣 card.
##
## The fixture is synthetic and uses only the finite v13 inventory catalog.  A
## missing auction API is reported as a semantic BEHAVIOR RED so this script
## remains executable while the production lane is still unimplemented.

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/auction_fixture.gd")

const CARD_ID := "拍賣"
const MAX_CASH: int = 1000000000000
const INCREMENTS := [100, 500, 1000, 5000, 10000]

var checks := 0
var failures := 0
var behavior_reds := 0
var capability_available := false
var capability_reported := false


func _initialize() -> void:
	_test_fixture_and_capability()
	_test_invalid_and_cancel_boundaries()
	_test_entry_and_opening()
	_test_increment_and_cash_limit()
	_test_owner_participation_and_no_sale()
	_test_sale_accounting_and_self_owner()
	_test_capacity_no_deadlock()
	_test_ai_initiated_bounded_auction()
	_test_pending_blockers()
	_test_mixed_human_ai_wait()
	print("Original auction flow checks: %d, failures: %d, behavior_reds: %d" % [checks, failures, behavior_reds])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _expect_json_equal(actual: String, expected: String, message: String) -> void:
	if actual == expected:
		checks += 1
		return
	checks += 1
	failures += 1
	print("FAIL: %s (json lengths actual=%d expected=%d)" % [message, actual.length(), expected.length()])


func _behavior_red(message: String) -> void:
	behavior_reds += 1
	failures += 1
	print("BEHAVIOR RED: " + message)


func _test_fixture_and_capability() -> void:
	var game: Object = Fixture.new_game(7800)
	_expect(game != null, "auction fixture starts from legal v13 definition")
	if game == null:
		return
	var validation: Dictionary = Fixture.validate(game)
	_expect(bool(validation.get("ok", false)), "fresh auction fixture validates before public actions")
	var missing: Array = []
	if not game.has_method("auction_response"):
		missing.append("auction_response()")
	if not game.item_is_implemented("card", CARD_ID):
		missing.append("item_is_implemented(card,拍賣)")
	capability_available = missing.is_empty()
	if not capability_available and not capability_reported:
		capability_reported = true
		_behavior_red("missing Issue #78 capability: " + ", ".join(missing))


func _validate_before_public(game: Object, label: String) -> bool:
	var validation: Dictionary = Fixture.validate(game)
	if bool(validation.get("ok", false)):
		return true
	_behavior_red("fixture save invalid before %s: %s" % [label, str(validation.get("errors", []))])
	return false


func _public_choose(game: Object, action: String, params: Dictionary, label: String) -> Dictionary:
	if not _validate_before_public(game, label):
		return {"ok": false, "fixture_invalid": true}
	return game.choose_action(action, params)


func _public_respond(game: Object, params: Dictionary, label: String) -> Dictionary:
	if not _validate_before_public(game, label):
		return {"ok": false, "fixture_invalid": true}
	return game.choose_action("respond_auction", params)


func _public_roll(game: Object, label: String) -> Dictionary:
	if not _validate_before_public(game, label):
		return {"ok": false, "fixture_invalid": true}
	return game.roll()


func _public_route(game: Object, label: String) -> Dictionary:
	if not _validate_before_public(game, label):
		return {"ok": false, "fixture_invalid": true}
	return game.choose_route(0)


func _public_end_turn(game: Object, label: String) -> Dictionary:
	if not _validate_before_public(game, label):
		return {"ok": false, "fixture_invalid": true}
	return game.end_turn()


func _public_ai(game: Object, label: String) -> Dictionary:
	if not _validate_before_public(game, label):
		return {"ok": false, "fixture_invalid": true}
	return game.run_ai_turn()


func _stage_and_prepare(game: Object, node_id: int, owner_id: int = -1, level: int = 0) -> bool:
	if owner_id != -1:
		Fixture.set_owner(game, node_id, owner_id)
		var tile: Dictionary = game.state["board"][node_id]
		tile["building_level"] = level
		if tile.get("kind", "") == "property":
			game.call("_update_tile_rent", tile)
		game.call("_recalculate_property_values")
	Fixture.prepare(game, 0, node_id)
	var staged: Dictionary = Fixture.stage_card(game, 0)
	_expect(bool(staged.get("ok", false)), "fixture stages 拍賣 card")
	return bool(staged.get("ok", false))


func _start(game: Object, label: String) -> Dictionary:
	return _public_choose(game, "use_card", {"card_id": CARD_ID, "cancel": false}, label)


func _start_or_red(game: Object, label: String) -> bool:
	var result := _start(game, label)
	if bool(result.get("ok", false)):
		return true
	if capability_available:
		_expect(false, "%s starts auction" % label)
	elif not bool(result.get("fixture_invalid", false)):
		_behavior_red("qualified %s start unavailable" % label)
	return false


func _pending(game: Object) -> Dictionary:
	if not game.has_method("auction_response"):
		return {}
	var value: Variant = game.auction_response()
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _drain_passes(game: Object, label: String, max_steps: int = 32) -> Dictionary:
	var last: Dictionary = {}
	for step in range(max_steps):
		last = _pending(game)
		if last.is_empty():
			return last
		var result := _public_respond(game, {"increment": 0, "cancel": true}, "%s-%d" % [label, step])
		_expect(bool(result.get("ok", false)), "pass/withdraw response succeeds while auction is pending")
		if not bool(result.get("ok", false)):
			return last
	_behavior_red("auction did not terminate after %d deterministic passes (%s)" % [max_steps, label])
	return last


func _property_node(game: Object) -> int:
	return 2


func _facility_node(game: Object) -> int:
	return 7


func _road_node(game: Object) -> int:
	return game.state.get("board", []).size() - 1


func _test_invalid_and_cancel_boundaries() -> void:
	var invalid: Object = Fixture.new_game(7801)
	if invalid == null:
		return
	_stage_and_prepare(invalid, _road_node(invalid))
	var invalid_before: String = invalid.to_json()
	var invalid_supply := Fixture.card_supply(invalid)
	var invalid_result := _public_choose(invalid, "use_card", {"card_id": CARD_ID, "cancel": false}, "invalid-road-target")
	_expect(not bool(invalid_result.get("ok", false)), "road target is rejected")
	_expect_json_equal(invalid.to_json(), invalid_before, "invalid target rejection is byte-atomic")
	_expect_equal(Fixture.card_supply(invalid), invalid_supply, "invalid target does not alter finite card supply")

	var malformed: Object = Fixture.new_game(7802)
	if malformed == null:
		return
	_stage_and_prepare(malformed, _property_node(malformed))
	if capability_available:
		var malformed_before: String = malformed.to_json()
		var malformed_result := _public_choose(malformed, "use_card", {"card_id": CARD_ID, "cancel": "true"}, "malformed-cancel-type")
		_expect(not bool(malformed_result.get("ok", false)), "cancel must be a bool")
		_expect_json_equal(malformed.to_json(), malformed_before, "malformed cancel is byte-atomic")

	var extra: Object = Fixture.new_game(7803)
	if extra == null:
		return
	_stage_and_prepare(extra, _property_node(extra))
	var extra_before: String = extra.to_json()
	var extra_result := _public_choose(extra, "use_card", {"card_id": CARD_ID, "cancel": false, "tile_id": 999}, "unexpected-target-param")
	_expect(not bool(extra_result.get("ok", false)), "auction entry rejects an unexpected target parameter")
	_expect_json_equal(extra.to_json(), extra_before, "unexpected target parameter is byte-atomic")

	var cancel: Object = Fixture.new_game(7804)
	if cancel == null:
		return
	_stage_and_prepare(cancel, _property_node(cancel))
	var cancel_before: String = cancel.to_json()
	var cancel_supply := Fixture.card_supply(cancel)
	var cancel_result := _public_choose(cancel, "use_card", {"card_id": CARD_ID, "cancel": true}, "pre-start-cancel")
	if capability_available:
		_expect(bool(cancel_result.get("ok", false)), "valid pre-start cancel succeeds")
		_expect_json_equal(cancel.to_json(), cancel_before, "pre-start cancel leaves state unchanged")
		_expect_equal(Fixture.card_supply(cancel), cancel_supply, "pre-start cancel keeps card reserved in hand")


func _check_opening_pending(game: Object, pending: Dictionary, phase_before: String, current_before: int) -> void:
	var expected_keys := ["caster_id", "node_id", "opening_bid", "current_bid", "highest_bidder_id", "bidder_id", "participants", "withdrawn"]
	_expect_equal(pending.size(), expected_keys.size(), "pending record has exactly eight fields")
	for key in expected_keys:
		_expect(pending.has(key), "pending record contains " + key)
	_expect_equal(int(pending.get("caster_id", -1)), current_before, "pending caster is original current player")
	_expect_equal(int(pending.get("node_id", -1)), _property_node(game), "pending node is current target")
	_expect_equal(int(pending.get("opening_bid", -1)), 4500, "opening bid truncates base*1.5 before price index")
	_expect_equal(int(pending.get("current_bid", -1)), int(pending.get("opening_bid", -2)), "current bid starts at opening")
	_expect_equal(int(pending.get("highest_bidder_id", 0)), -1, "no bidder is selected at opening")
	_expect_equal(game.state.get("phase", ""), phase_before, "auction keeps original phase")
	_expect_equal(int(game.state.get("current_player", -1)), current_before, "auction keeps original current player")
	_expect_equal(game.state["players"][0]["cards"].has(CARD_ID), true, "card remains reserved during pending auction")
	var participants: Array = pending.get("participants", [])
	var sorted := participants.duplicate()
	sorted.sort()
	_expect_equal(participants, sorted, "participants are ascending")
	_expect(participants.has(0), "caster is an eligible bidder row")
	_expect_equal(int(pending.get("bidder_id", -1)), int(participants[0]) if not participants.is_empty() else -1, "first bidder is the lowest participant")
	_drain_passes(game, "opening-cleanup")


func _test_entry_and_opening() -> void:
	var game: Object = Fixture.new_game(7810)
	if game == null:
		return
	Fixture.set_property_state(game, _property_node(game), -1, 1)
	game.state["price_index"] = 3
	Fixture.prepare(game, 0, _property_node(game))
	var staged := Fixture.stage_card(game, 0)
	_expect(bool(staged.get("ok", false)), "opening test stages card")
	var phase_before: String = str(game.state.get("phase", ""))
	var current_before: int = int(game.state.get("current_player", -1))
	var started := _start_or_red(game, "valid residential target")
	if started:
		var pending := _pending(game)
		_expect(not pending.is_empty(), "valid auction exposes pending record")
		if not pending.is_empty():
			_check_opening_pending(game, pending, phase_before, current_before)

	var target_cases := [{"owner": -1, "label": "unowned"}, {"owner": 1, "label": "other-owned"}, {"owner": 0, "label": "self-owned"}]
	for target_case in target_cases:
		var target_game: Object = Fixture.new_game(7811 + int(target_case.owner) + 1)
		if target_game == null:
			continue
		Fixture.set_owner(target_game, _property_node(target_game), int(target_case.owner))
		Fixture.prepare(target_game, 0, _property_node(target_game))
		var target_staged := Fixture.stage_card(target_game, 0)
		_expect(bool(target_staged.get("ok", false)), "%s target stages card" % str(target_case.label))
		var target_started := _start_or_red(target_game, "%s target" % str(target_case.label))
		if not target_started:
			continue
		var target_pending := _pending(target_game)
		_expect(not target_pending.is_empty(), "%s target exposes pending" % str(target_case.label))
		if target_pending.is_empty():
			continue
		_expect_equal(int(target_pending.get("node_id", -1)), _property_node(target_game), "%s target pending node" % str(target_case.label))

	var facility: Object = Fixture.new_game(7815)
	if facility == null:
		return
	Fixture.set_facility_state(facility, 2, 1, 1, 1, 0x51)
	Fixture.prepare(facility, 0, _facility_node(facility))
	var facility_staged := Fixture.stage_card(facility, 0)
	_expect(bool(facility_staged.get("ok", false)), "facility target stages card")
	var facility_started := _start_or_red(facility, "facility target")
	if not facility_started:
		return
	var facility_pending := _pending(facility)
	_expect(not facility_pending.is_empty(), "facility target exposes pending")
	if facility_pending.is_empty():
		return
	_expect_equal(int(facility_pending.get("node_id", -1)), _facility_node(facility), "facility pending keeps entrance node")


func _test_increment_and_cash_limit() -> void:
	var game: Object = Fixture.new_game(7820)
	if game == null:
		return
	game.state["price_index"] = 1
	Fixture.set_funds(game, 0, 1100)
	Fixture.prepare(game, 0, _property_node(game))
	var staged := Fixture.stage_card(game, 0)
	_expect(bool(staged.get("ok", false)), "increment test stages card")
	var started := _start_or_red(game, "increment test")
	if not started:
		return
	var pending := _pending(game)
	_expect(not pending.is_empty(), "increment test exposes pending")
	if pending.is_empty():
		return
	var bidder_id := int(pending.get("bidder_id", -1))
	_expect_equal(bidder_id, 0, "cash-limit fixture starts with player zero")
	var before_cash_json: String = game.to_json()
	var too_large := _public_respond(game, {"increment": 500, "cancel": false}, "cash-limit-reject")
	_expect(not bool(too_large.get("ok", false)), "bid over bidder cash is rejected")
	_expect_json_equal(game.to_json(), before_cash_json, "cash-limit rejection is byte-atomic")
	var last_bid := int(pending.get("current_bid", -1))
	for increment in INCREMENTS:
		var current := _pending(game)
		if current.is_empty():
			break
		var current_bidder := int(current.get("bidder_id", -1))
		Fixture.set_funds(game, current_bidder, max(100000, int(current.get("current_bid", 0)) + int(increment) + 1))
		var bid_result := _public_respond(game, {"increment": int(increment), "cancel": false}, "increment-%d" % int(increment))
		_expect(bool(bid_result.get("ok", false)), "accepted increment %d" % int(increment))
		if not bool(bid_result.get("ok", false)):
			break
		last_bid += int(increment)
		_expect_equal(int(_pending(game).get("current_bid", -1)), last_bid, "increment %d changes current bid exactly" % int(increment))
	_drain_passes(game, "increment-cleanup")


func _test_owner_participation_and_no_sale() -> void:
	var owner_game: Object = Fixture.new_game(7830)
	if owner_game == null:
		return
	Fixture.set_owner(owner_game, _property_node(owner_game), 1)
	Fixture.prepare(owner_game, 0, _property_node(owner_game))
	var owner_staged := Fixture.stage_card(owner_game, 0)
	_expect(bool(owner_staged.get("ok", false)), "owner participation stages card")
	var owner_started := _start_or_red(owner_game, "owner participation")
	if owner_started:
		var owner_pending := _pending(owner_game)
		_expect(not owner_pending.is_empty(), "owner participation exposes pending")
		if not owner_pending.is_empty():
			_expect(owner_pending.get("participants", []).has(1), "current owner remains an eligible bidder")
			_drain_passes(owner_game, "owner-cleanup")

	var no_sale: Object = Fixture.new_game(7831)
	if no_sale == null:
		return
	var property_id := _property_node(no_sale)
	Fixture.set_property_state(no_sale, property_id, 1, 2)
	var before_target := Fixture.target_snapshot(no_sale, property_id)
	var before_money := Fixture.cash_deposit_snapshot(no_sale)
	var before_supply := Fixture.card_supply(no_sale)
	Fixture.prepare(no_sale, 0, property_id)
	var no_sale_staged := Fixture.stage_card(no_sale, 0)
	_expect(bool(no_sale_staged.get("ok", false)), "property no-sale stages card")
	var no_sale_started := _start_or_red(no_sale, "property no-sale")
	if no_sale_started:
		var no_sale_pending := _pending(no_sale)
		_expect(not no_sale_pending.is_empty(), "property no-sale exposes pending")
		if not no_sale_pending.is_empty():
			_drain_passes(no_sale, "property-no-sale-passes")
			var after_target := Fixture.target_snapshot(no_sale, property_id)
			_expect_equal(after_target.get("owner", null), -1, "property no-sale clears owner")
			_expect_equal(after_target.get("building_level", null), before_target.get("building_level", null), "property no-sale preserves level")
			for key in ["is_chain_store", "cost", "land_price", "house_price", "upgrade_cost", "type_and_idx"]:
				if before_target.has(key):
					_expect_equal(after_target.get(key, null), before_target[key], "property no-sale preserves " + key)
			_expect_equal(Fixture.cash_deposit_snapshot(no_sale), before_money, "property no-sale does not move cash or deposits")
			_expect_equal(Fixture.card_supply(no_sale), before_supply, "property no-sale restores pre-grant card supply")
			_expect(not no_sale.state["players"][0]["cards"].has(CARD_ID), "property no-sale removes reserved card")

	var facility: Object = Fixture.new_game(7832)
	if facility == null:
		return
	var source_id := 2
	Fixture.set_facility_state(facility, source_id, 1, 2, 1, 0x51)
	var facility_before: Array = []
	for node_id in Fixture.facility_nodes(facility, source_id):
		facility_before.append(Fixture.target_snapshot(facility, int(node_id)))
	Fixture.prepare(facility, 0, _facility_node(facility))
	var facility_staged := Fixture.stage_card(facility, 0)
	_expect(bool(facility_staged.get("ok", false)), "facility no-sale stages card")
	var facility_started := _start_or_red(facility, "facility no-sale")
	if facility_started:
		var facility_pending := _pending(facility)
		_expect(not facility_pending.is_empty(), "facility no-sale exposes pending")
		if not facility_pending.is_empty():
			_drain_passes(facility, "facility-no-sale-passes")
			var facility_nodes := Fixture.facility_nodes(facility, source_id)
			for index in range(facility_nodes.size()):
				var after := Fixture.target_snapshot(facility, int(facility_nodes[index]))
				_expect_equal(after.get("owner", null), -1, "facility no-sale clears entrance owner")
				for key in ["building_level", "facility_type", "facility_state", "research_tool", "research_turns", "land_price", "type_and_idx"]:
					if facility_before[index].has(key):
						_expect_equal(after.get(key, null), facility_before[index][key], "facility no-sale preserves " + key)


func _first_bid_and_finish(game: Object, label: String) -> Dictionary:
	var pending := _pending(game)
	if pending.is_empty():
		return {}
	var bidder := int(pending.get("bidder_id", -1))
	var amount := int(pending.get("current_bid", 0)) + 100
	Fixture.set_funds(game, bidder, max(100000, amount + 1))
	var bid_result := _public_respond(game, {"increment": 100, "cancel": false}, label + "-bid")
	_expect(bool(bid_result.get("ok", false)), label + " first bid succeeds")
	var after_bid := _pending(game)
	var winner := int(after_bid.get("highest_bidder_id", bidder))
	var current_bid := int(after_bid.get("current_bid", amount))
	_drain_passes(game, label + "-passes")
	return {"winner": winner, "bid": current_bid}


func _test_sale_accounting_and_self_owner() -> void:
	var sale: Object = Fixture.new_game(7840)
	if sale == null:
		return
	var target := _property_node(sale)
	Fixture.set_owner(sale, target, 1)
	Fixture.prepare(sale, 0, target)
	var staged := Fixture.stage_card(sale, 0)
	_expect(bool(staged.get("ok", false)), "sale stages card")
	var cash_before := Fixture.cash_deposit_snapshot(sale)
	var bank_before := int(sale.state["bank"].get("deposits", 0))
	var sale_started := _start_or_red(sale, "sale")
	if sale_started:
		var sale_pending := _pending(sale)
		_expect(not sale_pending.is_empty(), "sale exposes pending")
		if not sale_pending.is_empty():
			var outcome := _first_bid_and_finish(sale, "sale")
			if not outcome.is_empty():
				var winner := int(outcome["winner"])
				var amount := int(outcome["bid"])
				var cash_after := Fixture.cash_deposit_snapshot(sale)
				_expect_equal(cash_after[winner][0], cash_before[winner][0] - amount, "winner pays current bid from cash")
				_expect_equal(cash_after[0][1], cash_before[0][1] + amount, "caster receives proceeds in deposit")
				_expect_equal(int(sale.state["bank"].get("deposits", 0)), bank_before + amount, "bank deposit aggregate increases by bid")
				_expect_equal(int(sale.state["board"][target].get("owner", -1)), winner, "sale assigns property to winner")
				_expect_equal(cash_after[1], cash_before[1], "previous owner receives no direct payout")

	var self_sale: Object = Fixture.new_game(7841)
	if self_sale == null:
		return
	var self_target := _property_node(self_sale)
	Fixture.set_owner(self_sale, self_target, 0)
	Fixture.prepare(self_sale, 0, self_target)
	var self_staged := Fixture.stage_card(self_sale, 0)
	_expect(bool(self_staged.get("ok", false)), "self-owner sale stages card")
	var self_cash_before := Fixture.cash_deposit_snapshot(self_sale)
	var self_started := _start_or_red(self_sale, "self-owner sale")
	if self_started:
		var self_pending := _pending(self_sale)
		_expect(not self_pending.is_empty(), "self-owner sale exposes pending")
		if not self_pending.is_empty():
			var self_outcome := _first_bid_and_finish(self_sale, "self-owner-sale")
			if not self_outcome.is_empty():
				var self_amount := int(self_outcome["bid"])
				_expect_equal(int(self_sale.state["board"][self_target].get("owner", -1)), 0, "self-owner sale keeps owner")
				_expect_equal(int(self_sale.state["players"][0].get("cash", 0)), self_cash_before[0][0] - self_amount, "self-owner still pays bid")
				_expect_equal(int(self_sale.state["players"][0].get("deposit", 0)), self_cash_before[0][1] + self_amount, "self-owner still receives caster deposit")


func _test_capacity_no_deadlock() -> void:
	var game: Object = Fixture.new_game(7850)
	if game == null:
		return
	Fixture.set_funds(game, 0, 100000, MAX_CASH - 50)
	Fixture.prepare(game, 0, _property_node(game))
	var staged := Fixture.stage_card(game, 0)
	_expect(bool(staged.get("ok", false)), "capacity test stages card")
	var started := _start_or_red(game, "capacity")
	if started:
		var pending := _pending(game)
		_expect(not pending.is_empty(), "capacity test exposes pending")
		if not pending.is_empty():
			var before: String = game.to_json()
			var bid := _public_respond(game, {"increment": 100, "cancel": false}, "capacity-reject")
			_expect(not bool(bid.get("ok", false)), "caster deposit headroom rejects prospective bid")
			_expect_json_equal(game.to_json(), before, "capacity rejection is byte-atomic")
			var terminal := _drain_passes(game, "capacity-passes")
			_expect(terminal.is_empty(), "capacity rejection can pass to a no-sale terminal")

	var bank_cash_game: Object = Fixture.new_game(7852)
	if bank_cash_game == null:
		return
	bank_cash_game.state["bank"]["cash"] = MAX_CASH - 50
	Fixture.prepare(bank_cash_game, 0, _property_node(bank_cash_game))
	var bank_cash_staged := Fixture.stage_card(bank_cash_game, 0)
	_expect(bool(bank_cash_staged.get("ok", false)), "bank cash capacity test stages card")
	var bank_cash_started := _start_or_red(bank_cash_game, "bank cash capacity")
	if bank_cash_started:
		var bank_cash_pending := _pending(bank_cash_game)
		_expect(not bank_cash_pending.is_empty(), "bank cash capacity test exposes pending")
		if not bank_cash_pending.is_empty():
			var bank_cash_before: String = bank_cash_game.to_json()
			var bank_cash_bid := _public_respond(bank_cash_game, {"increment": 100, "cancel": false}, "bank-cash-capacity-reject")
			_expect(not bool(bank_cash_bid.get("ok", false)), "bank cash headroom rejects prospective bid")
			_expect_json_equal(bank_cash_game.to_json(), bank_cash_before, "bank cash capacity rejection is byte-atomic")
			var bank_cash_terminal := _drain_passes(bank_cash_game, "bank-cash-capacity-passes")
			_expect(bank_cash_terminal.is_empty(), "bank cash capacity rejection can pass to a no-sale terminal")

	var ai_game: Object = Fixture.new_game(7851)
	if ai_game == null:
		return
	Fixture.set_funds(ai_game, 0, 100000, MAX_CASH - 50)
	for player_id in range(4):
		ai_game.set_player_ai(player_id, true)
	Fixture.prepare(ai_game, 0, _property_node(ai_game))
	var ai_staged := Fixture.stage_card(ai_game, 0)
	_expect(bool(ai_staged.get("ok", false)), "AI capacity test stages card")
	var ai_started := _start_or_red(ai_game, "AI capacity")
	if ai_started:
		var ai_pending := _pending(ai_game)
		_expect(not ai_pending.is_empty(), "AI capacity test exposes pending")
		if not ai_pending.is_empty():
			for step in range(32):
				if _pending(ai_game).is_empty():
					break
				var ai_result := _public_ai(ai_game, "ai-capacity-%d" % step)
				_expect(bool(ai_result.get("ok", false)), "AI capacity step returns without deadlock")
			_expect(_pending(ai_game).is_empty(), "all-AI capacity case terminates")


func _test_pending_blockers() -> void:
	var game: Object = Fixture.new_game(7860)
	if game == null:
		return
	Fixture.prepare(game, 0, _property_node(game))
	var staged := Fixture.stage_card(game, 0)
	_expect(bool(staged.get("ok", false)), "pending blocker test stages card")
	var started := _start_or_red(game, "pending blocker")
	if not started:
		return
	var pending := _pending(game)
	_expect(not pending.is_empty(), "pending blocker exposes pending")
	if pending.is_empty():
		return
	for action in ["roll", "route", "end_turn", "deposit", "withdraw", "use_tool", "other_card"]:
		var before: String = game.to_json()
		var result: Dictionary
		match action:
			"roll": result = _public_roll(game, "pending-roll")
			"route": result = _public_route(game, "pending-route")
			"end_turn": result = _public_end_turn(game, "pending-end-turn")
			"deposit": result = _public_choose(game, "deposit", {"amount": 100}, "pending-deposit")
			"withdraw": result = _public_choose(game, "withdraw", {"amount": 100}, "pending-withdraw")
			"use_tool": result = _public_choose(game, "use_tool", {"tool_id": "遙控骰子", "value": 4}, "pending-use-tool")
			_: result = _public_choose(game, "use_card", {"card_id": "停留"}, "pending-other-card")
		_expect(not bool(result.get("ok", false)), "pending rejects unrelated %s" % action)
		_expect_json_equal(game.to_json(), before, "pending unrelated %s is byte-atomic" % action)
	var malformed_before: String = game.to_json()
	var malformed := _public_respond(game, {"increment": "100", "cancel": false}, "pending-malformed-response")
	_expect(not bool(malformed.get("ok", false)), "pending rejects string increment")
	_expect_json_equal(game.to_json(), malformed_before, "malformed auction response is byte-atomic")


func _test_ai_initiated_bounded_auction() -> void:
	# Start through the public AI turn with no pre-existing pending record.  The
	# high opening bid forces more than one 64-step auction slice while every
	# intermediate snapshot remains save-valid.
	var game: Object = Fixture.new_game(7865)
	if game == null:
		return
	for player_id in range(4):
		game.set_player_ai(player_id, true)
	var target := _property_node(game)
	Fixture.set_property_state(game, target, -1, 5)
	game.state["price_index"] = 3
	Fixture.prepare(game, 0, target)
	# Reserve the landing property action so the AI reaches its card fallback.
	game.state["property_action_used"] = true
	game.call("_set_action_options", 0)
	var staged := Fixture.stage_card(game, 0)
	_expect(bool(staged.get("ok", false)), "AI initiation stages auction card")
	_expect(_pending(game).is_empty(), "AI initiation begins without a pre-existing pending auction")
	var first_result := _public_ai(game, "AI initiated auction")
	_expect(bool(first_result.get("ok", false)), "public AI turn starts and services auction")
	var pending := _pending(game)
	_expect(not pending.is_empty(), "AI card action creates a pending auction")
	if pending.is_empty():
		return
	_expect(bool(first_result.get("auction", false)), "AI result identifies auction work")

	var calls := 1
	while not pending.is_empty() and calls < 16:
		var validation := Fixture.validate(game)
		_expect(bool(validation.get("ok", false)), "long AI auction intermediate save remains valid")
		var result := _public_ai(game, "long-AI-auction-%d" % calls)
		_expect(bool(result.get("ok", false)), "bounded AI auction slice succeeds")
		calls += 1
		pending = _pending(game)
	_expect(pending.is_empty(), "long all-AI auction eventually settles")
	var final_validation := Fixture.validate(game)
	_expect(bool(final_validation.get("ok", false)), "settled AI auction save remains valid")
	var bid_events := 0
	for event_value in game.state.get("event_log", []):
		if typeof(event_value) == TYPE_DICTIONARY and event_value.get("type", "") == "auction_bid":
			bid_events += 1
	_expect(bid_events > 64, "long AI auction exceeds one 64-step slice")


func _run_mixed_human_ai_case(seed_value: int, caster_id: int, label: String) -> void:
	var game: Object = Fixture.new_game(seed_value)
	if game == null:
		return
	game.set_player_ai(0, true)
	game.set_player_ai(1, false)
	game.set_player_ai(2, true)
	game.set_player_ai(3, true)
	Fixture.prepare(game, caster_id, _property_node(game))
	var staged := Fixture.stage_card(game, caster_id)
	_expect(bool(staged.get("ok", false)), "%s stages card" % label)
	var started := _start_or_red(game, label)
	if not started:
		return
	var pending := _pending(game)
	_expect(not pending.is_empty(), "%s exposes pending" % label)
	if pending.is_empty():
		return
	_expect_equal(int(pending.get("caster_id", -1)), caster_id, "%s preserves caster identity" % label)
	_expect_equal(int(pending.get("bidder_id", -1)), 0, "%s starts at lowest AI bidder" % label)
	var ai_step := _public_ai(game, "%s-first-ai" % label)
	_expect(bool(ai_step.get("ok", false)), "%s AI bidder advances without a human response" % label)
	pending = _pending(game)
	if pending.is_empty():
		return
	var human_id := int(pending.get("bidder_id", -1))
	_expect_equal(human_id, 1, "%s waits at ascending human bidder" % label)
	_expect(bool(ai_step.get("awaiting_response", false)), "%s AI loop reports human wait" % label)
	var human_pass := _public_respond(game, {"increment": 0, "cancel": true}, "%s-human-pass" % label)
	_expect(bool(human_pass.get("ok", false)), "%s human pass resumes mixed auction" % label)
	for step in range(32):
		if _pending(game).is_empty():
			break
		var current := _pending(game)
		var current_id := int(current.get("bidder_id", -1))
		if current_id == 1:
			var pass_result := _public_respond(game, {"increment": 0, "cancel": true}, "%s-human-pass-%d" % [label, step])
			_expect(bool(pass_result.get("ok", false)), "%s human response remains available after AI rounds" % label)
		else:
			var ai := _public_ai(game, "%s-ai-%d" % [label, step])
			_expect(bool(ai.get("ok", false)), "%s AI round remains deterministic" % label)
	_expect(_pending(game).is_empty(), "%s mixed human/AI auction terminates" % label)


func _test_mixed_human_ai_wait() -> void:
	# Cover both control identities: the original caster may be AI, or a human
	# caster may leave the first (ascending) bidder to the AI turn loop.
	_run_mixed_human_ai_case(7870, 0, "AI-caster mixed")
	_run_mixed_human_ai_case(7871, 1, "human-caster mixed")
