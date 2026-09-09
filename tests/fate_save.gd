extends SceneTree

## Save/reload RED seed for the optional fate state. The tests keep the state
## optional for predecessor saves, but reject malformed fate data before it can
## be interpreted as a fresh draw.

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/fate_fixture.gd")

const FATE_COUNT := 37
const LAST_KEYS := ["candidate_id", "id", "map_slot", "player_id", "targets", "changes", "summary", "outcome", "raw_amount", "raw_days", "gate_result"]

var checks := 0
var failures := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	_test_optional_state()
	_test_valid_last_and_roundtrip()
	_test_malformed_fate_rejected()
	_test_player_bounds()
	_test_legacy_kind_migration()
	print("Fate save checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _order() -> Array:
	var result: Array = []
	for candidate_id in range(FATE_COUNT):
		result.append(candidate_id)
	return result


func _last(candidate_id: int = 20, map_slot: int = 20, outcome: String = "applied") -> Dictionary:
	return {
		"candidate_id": candidate_id,
		"id": candidate_id,
		"map_slot": map_slot,
		"player_id": 0,
		"targets": [],
		"changes": [{"cash": 1000}],
		"summary": "增加 1000 元",
		"outcome": outcome,
		"raw_amount": 1000,
		"raw_days": 0,
		"gate_result": 0,
	}


func _new_game(seed_value: int = 6200) -> Object:
	var game: Object = Fixture.new_game(seed_value, 4)
	expect(game != null, "fate save fixture creates a game")
	if game == null:
		return null
	game.state["phase"] = "await_action"
	game.state["current_player"] = 0
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["property_action_used"] = false
	game._set_action_options(0)
	game.state["fate"] = {"order": _order(), "cursor": 0, "draw_count": 0, "last": {}}
	return game


func _valid_data() -> Dictionary:
	var game := _new_game()
	if game == null:
		return {}
	var data: Dictionary = game.to_dict()
	data["fate"] = {"order": _order(), "cursor": 1, "draw_count": 1, "last": _last()}
	return data


func _assert_rejected(data: Dictionary, label: String) -> void:
	var validation: Dictionary = Game.validate_save(data)
	expect(not bool(validation.get("ok", false)), label + " is rejected by save validation")
	expect(Game.from_dict(data) == null, label + " cannot be loaded")


func _test_optional_state() -> void:
	var game := _new_game(6201)
	if game == null:
		return
	var data: Dictionary = game.to_dict()
	var validation: Dictionary = Game.validate_save(data)
	expect(bool(validation.get("ok", false)), "empty optional fate state validates")
	data.erase("fate")
	validation = Game.validate_save(data)
	expect(bool(validation.get("ok", false)), "pre-fate saves without fate state remain valid")
	var restored: Object = Game.from_dict(data)
	expect(restored != null, "pre-fate save without fate state reloads")
	if restored != null:
		expect(not restored.state.has("fate"), "pre-fate reload does not invent a fate draw")
		expect(int(restored.state.get("version", -1)) == 13, "fate keeps the existing building-card save version")


func _test_valid_last_and_roundtrip() -> void:
	var data := _valid_data()
	if data.is_empty():
		return
	var validation: Dictionary = Game.validate_save(data)
	expect(bool(validation.get("ok", false)), "canonical fate last result validates: " + str(validation.get("errors", [])))
	var last: Dictionary = data.fate.last
	var actual_keys: Array = last.keys()
	actual_keys.sort()
	var expected_keys: Array = LAST_KEYS.duplicate()
	expected_keys.sort()
	expect(actual_keys == expected_keys, "canonical fate last result has exact keys")
	# Serialize through the canonical Game encoder so integer-valued arrays and
	# other typed fields retain the exact representation used by production
	# saves. JSON.stringify on a Dictionary widens some values to floats.
	var canonical: Object = Game.from_dict(data)
	expect(canonical != null, "canonical fate data can be encoded")
	if canonical == null:
		return
	var json_text: String = canonical.to_json()
	var restored: Object = Game.from_dict(JSON.parse_string(json_text))
	expect(restored != null, "canonical fate save reloads")
	if restored != null:
		expect(restored.to_json() == json_text, "fate save JSON continuation is exact")
		expect(restored.state.fate == data.fate, "fate cursor, draw count and last result survive reload")
		var before: String = restored.to_json()
		# Re-reading a completed result is observational; loading it must never
		# apply the cash change a second time.
		restored._set_action_options(0)
		expect(restored.to_json() == before, "reloading a completed fate result does not reapply it")

	var blocked_data := _valid_data()
	blocked_data.fate.last = _last(17, 17, "blocked")
	blocked_data.fate.last.changes = []
	blocked_data.fate.last.summary = "費用已抵銷"
	blocked_data.fate.last.raw_amount = 6000
	blocked_data.fate.last.gate_result = 1
	var blocked_validation: Dictionary = Game.validate_save(blocked_data)
	expect(bool(blocked_validation.get("ok", false)), "blocked fate result remains a valid canonical result")


func _test_malformed_fate_rejected() -> void:
	var malformed: Array = []
	var base := _valid_data()
	if base.is_empty():
		return

	var wrong_size: Dictionary = base.duplicate(true)
	wrong_size.fate.order = _order()
	wrong_size.fate.order.pop_back()
	malformed.append([wrong_size, "fate order with the wrong length"])

	var duplicate_order: Dictionary = base.duplicate(true)
	duplicate_order.fate.order[1] = duplicate_order.fate.order[0]
	malformed.append([duplicate_order, "fate order with duplicate candidates"])

	var out_of_range: Dictionary = base.duplicate(true)
	out_of_range.fate.order[0] = 37
	malformed.append([out_of_range, "fate order with an out-of-range candidate"])

	var wrong_order_type: Dictionary = base.duplicate(true)
	wrong_order_type.fate.order = "0,1,2"
	malformed.append([wrong_order_type, "fate order with the wrong type"])

	var cursor_high: Dictionary = base.duplicate(true)
	cursor_high.fate.cursor = 37
	malformed.append([cursor_high, "fate cursor above the wrap bound"])

	var cursor_negative: Dictionary = base.duplicate(true)
	cursor_negative.fate.cursor = -1
	malformed.append([cursor_negative, "fate cursor below zero"])

	var draw_negative: Dictionary = base.duplicate(true)
	draw_negative.fate.draw_count = -1
	malformed.append([draw_negative, "negative fate draw count"])

	var last_missing: Dictionary = base.duplicate(true)
	last_missing.fate.last.erase("summary")
	malformed.append([last_missing, "fate last missing summary"])

	var last_extra: Dictionary = base.duplicate(true)
	last_extra.fate.last["raw_payload"] = {}
	malformed.append([last_extra, "fate last with an extra payload key"])

	var targets_wrong: Dictionary = base.duplicate(true)
	targets_wrong.fate.last.targets = {"id": 0}
	malformed.append([targets_wrong, "fate last with non-array targets"])

	var changes_wrong: Dictionary = base.duplicate(true)
	changes_wrong.fate.last.changes = "cash +1000"
	malformed.append([changes_wrong, "fate last with non-array changes"])

	var summary_wrong: Dictionary = base.duplicate(true)
	summary_wrong.fate.last.summary = 1000
	malformed.append([summary_wrong, "fate last with non-string summary"])

	var outcome_wrong: Dictionary = base.duplicate(true)
	outcome_wrong.fate.last.outcome = "skipped"
	malformed.append([outcome_wrong, "fate last with an unknown outcome"])

	var amount_wrong: Dictionary = base.duplicate(true)
	amount_wrong.fate.last.raw_amount = -1
	malformed.append([amount_wrong, "fate last with a negative raw amount"])

	var days_wrong: Dictionary = base.duplicate(true)
	days_wrong.fate.last.raw_days = 1.5
	malformed.append([days_wrong, "fate last with a non-integer raw duration"])

	var gate_wrong: Dictionary = base.duplicate(true)
	gate_wrong.fate.last.gate_result = 3
	malformed.append([gate_wrong, "fate last with an unknown gate result"])

	var state_wrong: Dictionary = base.duplicate(true)
	state_wrong.fate = []
	malformed.append([state_wrong, "fate state with the wrong type"])

	for entry in malformed:
		_assert_rejected(entry[0], str(entry[1]))


func _test_player_bounds() -> void:
	var data := _valid_data()
	if data.is_empty():
		return
	data.fate.last.player_id = 4
	_assert_rejected(data, "fate last player outside the save player list")


func _test_legacy_kind_migration() -> void:
	var game := _new_game(6250)
	if game == null:
		return
	var data: Dictionary = game.to_dict()
	data.erase("fate")
	var tail: Dictionary = data.board.back()
	tail["kind"] = "unsupported"
	tail["type_and_idx"] = 0
	tail["event_code"] = 3
	tail["source_status_bits"] = 3
	var original_rng: String = str(data.get("rng_state_text", ""))
	var restored: Object = Game.from_dict(data)
	expect(restored != null, "legacy unsupported event_code 3 save reloads")
	if restored == null:
		return
	expect(str(restored.state.board.back().get("kind", "")) == "fate", "legacy event_code 3 kind migrates to fate")
	expect(str(restored.state.get("rng_state_text", "")) == original_rng, "fate kind migration preserves RNG continuation")
	expect(not restored.state.has("fate"), "legacy kind migration does not invent a result")
