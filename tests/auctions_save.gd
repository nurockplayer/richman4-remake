extends SceneTree

## Issue #78 save/restore acceptance for the optional pending_auction record.
##
## This is intentionally independent of the flow script: malformed records
## must fail closed and must never be partially loaded.

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/auction_fixture.gd")

const CARD_ID := "拍賣"
const MAX_CASH: int = 1000000000000
const PENDING_KEYS := ["caster_id", "node_id", "opening_bid", "current_bid", "highest_bidder_id", "bidder_id", "participants", "withdrawn"]

var checks := 0
var failures := 0
var behavior_reds := 0
var capability_available := false
var capability_reported := false


func _initialize() -> void:
	_test_clean_optional_state()
	_test_capability()
	_test_pending_roundtrip_and_schema()
	_test_malformed_records_fail_closed()
	print("Original auction save checks: %d, failures: %d, behavior_reds: %d" % [checks, failures, behavior_reds])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _expect_json_equal(actual: String, expected: String, message: String) -> void:
	checks += 1
	if actual == expected:
		return
	failures += 1
	print("FAIL: %s (json lengths actual=%d expected=%d)" % [message, actual.length(), expected.length()])


func _behavior_red(message: String) -> void:
	behavior_reds += 1
	failures += 1
	print("BEHAVIOR RED: " + message)


func _test_clean_optional_state() -> void:
	var game: Object = Fixture.new_game(7900)
	_expect(game != null, "fresh fixture starts for optional pending test")
	if game == null:
		return
	var data: Dictionary = game.to_dict()
	_expect(not data.has("pending_auction"), "clean save omits optional pending_auction")
	var validation: Dictionary = Game.validate_save(data)
	_expect(bool(validation.get("ok", false)), "clean save validates without auction pending")
	var restored: Object = Game.from_dict(data)
	_expect(restored != null, "clean save restores without auction pending")


func _test_capability() -> void:
	var game: Object = Fixture.new_game(7901)
	if game == null:
		return
	var missing: Array = []
	if not game.has_method("auction_response"):
		missing.append("auction_response()")
	if not game.item_is_implemented("card", CARD_ID):
		missing.append("item_is_implemented(card,拍賣)")
	capability_available = missing.is_empty()
	if not capability_available and not capability_reported:
		capability_reported = true
		_behavior_red("missing Issue #78 save capability: " + ", ".join(missing))


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


func _start_or_red(game: Object, label: String) -> bool:
	var result := _public_choose(game, "use_card", {"card_id": CARD_ID, "cancel": false}, label)
	if bool(result.get("ok", false)):
		return true
	if capability_available:
		_expect(false, "%s starts auction" % label)
	elif not bool(result.get("fixture_invalid", false)):
		_behavior_red("qualified %s start unavailable" % label)
	return false


func _new_pending(seed_value: int) -> Object:
	var game: Object = Fixture.new_game(seed_value)
	if game == null:
		_expect(false, "pending fixture starts")
		return null
	Fixture.prepare(game, 0, 2)
	var staged := Fixture.stage_card(game, 0)
	_expect(bool(staged.get("ok", false)), "pending fixture stages 拍賣 card")
	_start_or_red(game, "pending fixture")
	return game


func _test_pending_roundtrip_and_schema() -> void:
	var game: Object = _new_pending(7910)
	if game == null:
		return
	var pending_value: Variant = game.to_dict().get("pending_auction", null)
	if typeof(pending_value) != TYPE_DICTIONARY and not capability_available:
		return
	_expect(typeof(pending_value) == TYPE_DICTIONARY, "pending save stores a dictionary")
	if typeof(pending_value) != TYPE_DICTIONARY:
		return
	var pending: Dictionary = pending_value
	_expect_equal(pending.size(), PENDING_KEYS.size(), "pending save has exactly eight keys")
	for key in PENDING_KEYS:
		_expect(pending.has(key), "pending save contains " + key)
	_expect(typeof(pending.get("participants", null)) == TYPE_ARRAY, "participants is an array")
	_expect(typeof(pending.get("withdrawn", null)) == TYPE_ARRAY, "withdrawn is an array")
	var participants: Array = pending.get("participants", [])
	var sorted_participants := participants.duplicate()
	sorted_participants.sort()
	_expect_equal(participants, sorted_participants, "participants are sorted in save")
	var withdrawn: Array = pending.get("withdrawn", [])
	var sorted_withdrawn := withdrawn.duplicate()
	sorted_withdrawn.sort()
	_expect_equal(withdrawn, sorted_withdrawn, "withdrawn is sorted in save")
	_expect_equal(int(pending.get("current_bid", -1)), int(pending.get("opening_bid", -2)), "pending starts at opening bid")
	_expect_equal(int(pending.get("highest_bidder_id", 0)), -1, "pending starts without a highest bidder")
	_expect_equal(game.state.get("current_player", -1), pending.get("caster_id", -2), "state current player remains caster")
	_expect(game.state["players"][0]["cards"].has(CARD_ID), "reserved card remains present in pending save")

	var original_json: String = game.to_json()
	var data: Dictionary = game.to_dict()
	var restored: Object = Game.from_dict(data)
	_expect(restored != null, "valid pending save restores")
	if restored == null:
		return
	_expect_json_equal(restored.to_json(), original_json, "pending save JSON roundtrip is exact")
	_expect_equal(restored.to_dict().get("pending_auction", {}), pending, "restored pending record is identical")
	var restored_pending: Variant = restored.to_dict().get("pending_auction", {})
	if typeof(restored_pending) == TYPE_DICTIONARY and not restored_pending.is_empty():
		var response := _public_respond(restored, {"increment": 0, "cancel": true}, "save-resume-response")
		_expect(bool(response.get("ok", false)), "restored pending auction accepts the current bidder response")

	# Save dictionaries are semantically ordered by field name, not by the
	# insertion order chosen by a JSON producer.
	var reordered_data: Dictionary = data.duplicate(true)
	var reordered: Dictionary = {}
	var keys: Array = PENDING_KEYS.duplicate()
	keys.reverse()
	for key in keys:
		reordered[key] = pending[key]
	reordered_data["pending_auction"] = reordered
	var reordered_validation: Dictionary = Game.validate_save(reordered_data)
	_expect(bool(reordered_validation.get("ok", false)), "pending key insertion order does not change validity")


func _invalid_record(base: Dictionary, label: String) -> void:
	var before: String = JSON.stringify(base)
	var validation: Dictionary = Game.validate_save(base)
	_expect(not bool(validation.get("ok", false)), label + " is rejected by validate_save")
	_expect_json_equal(JSON.stringify(base), before, label + " validation does not mutate input")
	var restored: Object = Game.from_dict(base)
	_expect(restored == null, label + " is rejected without partial load")


func _test_malformed_records_fail_closed() -> void:
	var game: Object = _new_pending(7920)
	if game == null:
		return
	var clean: Dictionary = game.to_dict()
	var pending: Dictionary = clean.get("pending_auction", {}).duplicate(true)
	if pending.is_empty():
		return

	var missing := clean.duplicate(true)
	missing["pending_auction"].erase("bidder_id")
	_invalid_record(missing, "pending missing field")

	var extra := clean.duplicate(true)
	extra["pending_auction"]["unexpected"] = 1
	_invalid_record(extra, "pending extra field")

	var wrong_type := clean.duplicate(true)
	wrong_type["pending_auction"]["opening_bid"] = "1000"
	_invalid_record(wrong_type, "pending wrong scalar type")

	var wrong_array := clean.duplicate(true)
	wrong_array["pending_auction"]["participants"] = "0,1"
	_invalid_record(wrong_array, "pending wrong participants type")

	var wrong_bidder := clean.duplicate(true)
	wrong_bidder["pending_auction"]["bidder_id"] = 99
	_invalid_record(wrong_bidder, "pending unknown bidder")

	var wrong_target := clean.duplicate(true)
	wrong_target["pending_auction"]["node_id"] = game.state["board"].size() - 1
	_invalid_record(wrong_target, "pending wrong target kind")

	var wrong_opening := clean.duplicate(true)
	wrong_opening["pending_auction"]["opening_bid"] = int(pending.get("opening_bid", 0)) + 1
	_invalid_record(wrong_opening, "pending opening bid mismatch")

	var wrong_increment := clean.duplicate(true)
	var increment_participants: Array = pending.get("participants", [])
	if increment_participants.size() >= 2:
		wrong_increment["pending_auction"]["current_bid"] = int(pending.get("opening_bid", 0)) + 1
		wrong_increment["pending_auction"]["highest_bidder_id"] = int(increment_participants[0])
		wrong_increment["pending_auction"]["bidder_id"] = int(increment_participants[1])
		_invalid_record(wrong_increment, "pending non-increment bid")

	var ineligible_participant := clean.duplicate(true)
	var participant_ids: Array = pending.get("participants", [])
	if participant_ids.size() >= 3:
		var removed_cash_id := int(participant_ids[2])
		ineligible_participant["players"][removed_cash_id]["cash"] = int(pending.get("opening_bid", 0))
		_invalid_record(ineligible_participant, "pending ineligible participant")

	var wrong_phase := clean.duplicate(true)
	wrong_phase["phase"] = "await_roll"
	_invalid_record(wrong_phase, "pending phase mismatch")

	var no_card := clean.duplicate(true)
	no_card["players"][0]["cards"] = []
	_invalid_record(no_card, "pending missing reserved card")

	var wrong_options := clean.duplicate(true)
	wrong_options["action_options"] = ["end_turn"]
	_invalid_record(wrong_options, "pending action options mismatch")

	var conflict := clean.duplicate(true)
	conflict["pending_finance"] = {"payer_id": 0}
	_invalid_record(conflict, "pending finance conflict")

	var accepted_result := _public_respond(game, {"increment": 100, "cancel": false}, "accepted-capacity-raise")
	_expect(bool(accepted_result.get("ok", false)), "accepted capacity raise creates a pending high bid")
	if bool(accepted_result.get("ok", false)):
		var accepted_data: Dictionary = game.to_dict()
		var accepted_pending_value: Variant = accepted_data.get("pending_auction", null)
		var accepted_pending_present: bool = typeof(accepted_pending_value) == TYPE_DICTIONARY and not accepted_pending_value.is_empty()
		_expect(accepted_pending_present, "accepted capacity raise retains a pending high bid")
		if accepted_pending_present:
			var accepted_pending: Dictionary = accepted_pending_value
			var accepted_opening := int(accepted_pending.get("opening_bid", -1))
			var accepted_current := int(accepted_pending.get("current_bid", -1))
			var accepted_winner := int(accepted_pending.get("highest_bidder_id", -1))
			_expect_equal(accepted_current, accepted_opening + 100, "accepted capacity raise advances current bid")
			_expect(accepted_winner >= 0, "accepted capacity raise selects a highest bidder")
			var accepted_validation: Dictionary = Game.validate_save(accepted_data)
			_expect(bool(accepted_validation.get("ok", false)), "accepted high-bid pending save validates before capacity mutation")
			if bool(accepted_validation.get("ok", false)) and accepted_current == accepted_opening + 100 and accepted_winner >= 0:
				var capacity := accepted_data.duplicate(true)
				var caster_id := int(accepted_pending.get("caster_id", -1))
				capacity["players"][caster_id]["deposit"] = MAX_CASH
				capacity["bank"]["deposits"] = MAX_CASH
				_invalid_record(capacity, "pending settlement capacity overflow")

	var participants: Array = pending.get("participants", [])
	if participants.size() >= 2:
		var unsorted := clean.duplicate(true)
		var reversed: Array = participants.duplicate()
		reversed.reverse()
		unsorted["pending_auction"]["participants"] = reversed
		_invalid_record(unsorted, "pending participants out of order")
		var duplicate := clean.duplicate(true)
		var duplicate_list: Array = participants.duplicate()
		duplicate_list.append(participants[0])
		duplicate["pending_auction"]["participants"] = duplicate_list
		_invalid_record(duplicate, "pending duplicate participant")

	var withdrawn := clean.duplicate(true)
	withdrawn["pending_auction"]["withdrawn"] = [99]
	_invalid_record(withdrawn, "pending withdrawn non-member")
