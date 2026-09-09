extends SceneTree

## Issue #50 save-boundary seed for the optional player engineering_vehicle
## payload.  The payload is deliberately tested on the existing v13 graph
## schema.  No new version or top-level capability marker is permitted.
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/god_card_fixture.gd")

const BASE_SAVE_VERSION := 13
const ENGINEERING_VEHICLE := "engineering"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_legacy_v13_default_and_json_roundtrip()
	_test_valid_optional_metadata_and_json_continuation()
	_test_strict_optional_metadata_rejections()
	print("Engineering vehicle save checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_game(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 2, Fixture.definition(), Fixture.new_game_options())
	_expect(game != null, "v13 save fixture starts")
	if game == null:
		return null
	_expect_equal(int(game.state.get("version", -1)), BASE_SAVE_VERSION, "save fixture remains v13")
	var validation: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(validation.get("ok", false)), "save fixture baseline validates: %s" % str(validation.get("errors", [])))
	return game


func _active_data(seed_value: int, remaining: int = 3, previous_vehicle: String = "walking", previous_dice: int = 1) -> Dictionary:
	var game: Object = _new_game(seed_value)
	if game == null:
		return {}
	var data: Dictionary = game.to_dict()
	var player: Dictionary = data["players"][0]
	player["vehicle"] = ENGINEERING_VEHICLE
	player["dice_count"] = 1
	player["engineering_vehicle"] = {
		"remaining_admissions": remaining,
		"previous_vehicle": previous_vehicle,
		"previous_dice_count": previous_dice,
	}
	data["players"][0] = player
	return data


func _assert_valid(data: Dictionary, label: String) -> void:
	var validation: Dictionary = Game.validate_save(data)
	_expect(bool(validation.get("ok", false)), label + " validates: " + str(validation.get("errors", [])))


func _assert_rejected(data: Dictionary, label: String) -> void:
	var validation: Dictionary = Game.validate_save(data)
	_expect(not bool(validation.get("ok", false)), label + " is rejected")
	var encoded: String = JSON.stringify(data)
	var parsed: Variant = JSON.parse_string(encoded)
	_expect(parsed is Dictionary, label + " remains a JSON object")
	if parsed is Dictionary:
		_expect(Game.from_dict(parsed) == null, label + " cannot be loaded")


func _test_legacy_v13_default_and_json_roundtrip() -> void:
	var game: Object = _new_game(5101)
	if game == null:
		return
	var data: Dictionary = game.to_dict()
	_expect_equal(int(data.get("version", -1)), BASE_SAVE_VERSION, "legacy data keeps v13 version")
	for player_value in data.get("players", []):
		if typeof(player_value) == TYPE_DICTIONARY:
			_expect(not player_value.has("engineering_vehicle"), "legacy player omits inactive engineering metadata")
	_assert_valid(data, "legacy v13 save")
	var restored: Object = Game.from_dict(JSON.parse_string(JSON.stringify(data)))
	_expect(restored != null, "legacy v13 JSON reloads without engineering metadata")
	if restored != null:
		_expect_equal(restored.to_json(), game.to_json(), "legacy v13 JSON roundtrip is exact")


func _test_valid_optional_metadata_and_json_continuation() -> void:
	var data: Dictionary = _active_data(5102, 2, "car", 2)
	if data.is_empty():
		return
	var player: Dictionary = data["players"][0]
	# The ordinary vehicle is held while engineering is active and can be
	# re-equipped after the final owner admission.
	player["tools"]["汽車"] = 1
	data["inventory_supply"]["tools"]["汽車"] = int(data["inventory_supply"]["tools"].get("汽車", 0)) - 1
	data["players"][0] = player
	_assert_valid(data, "active engineering optional metadata")
	_expect_equal(int(data.get("version", -1)), BASE_SAVE_VERSION, "active engineering does not change save version")
	_expect(not data.has("engineering_save_version"), "active engineering does not add a save marker")
	var restored: Object = Game.from_dict(JSON.parse_string(JSON.stringify(data)))
	_expect(restored != null, "active engineering JSON continuation reloads")
	if restored == null:
		return
	var restored_player: Dictionary = restored.state["players"][0]
	_expect_equal(str(restored_player.get("vehicle", "")), ENGINEERING_VEHICLE, "JSON continuation keeps engineering vehicle")
	_expect_equal(restored_player.get("engineering_vehicle", {}), player.get("engineering_vehicle", {}), "JSON continuation keeps canonical metadata")
	_expect_equal(restored.to_json(), JSON.stringify(data), "JSON continuation preserves the canonical serialized state")
	_expect_equal(str(restored.state.get("rng_state_text", "")), str(data.get("rng_state_text", "")), "JSON continuation preserves RNG state")

	# Re-enter the same player twice through public end_turn.  The first owner
	# admission consumes the remaining count; the second expires before movement
	# and restores the held car/dice selection.
	restored.state["current_player"] = 0
	restored.state["phase"] = "await_action"
	restored.state["last_roll"] = []
	restored.state["last_total"] = 0
	restored.state["last_roll_total"] = 0
	restored.end_turn()
	restored.state["current_player"] = 1
	restored.state["phase"] = "await_action"
	restored.state["last_roll"] = []
	restored.state["last_total"] = 0
	restored.state["last_roll_total"] = 0
	restored.end_turn()
	restored_player = restored.state["players"][0]
	_expect_equal(int(restored_player.get("engineering_vehicle", {}).get("remaining_admissions", -1)), 1, "JSON-restored timer decrements on the owner admission")
	restored.state["current_player"] = 0
	restored.state["phase"] = "await_action"
	restored.state["last_roll"] = []
	restored.state["last_total"] = 0
	restored.state["last_roll_total"] = 0
	restored.end_turn()
	restored.state["current_player"] = 1
	restored.state["phase"] = "await_action"
	restored.state["last_roll"] = []
	restored.state["last_total"] = 0
	restored.state["last_roll_total"] = 0
	restored.end_turn()
	restored_player = restored.state["players"][0]
	_expect_equal(str(restored_player.get("vehicle", "")), "car", "JSON-restored timer expiry restores the previous vehicle")
	_expect_equal(int(restored_player.get("dice_count", -1)), 2, "JSON-restored expiry restores previous dice")
	_expect(not restored_player.has("engineering_vehicle"), "JSON-restored expiry removes optional metadata")
	_expect_equal(int(restored_player.get("tools", {}).get("汽車", 0)), 0, "JSON-restored expiry consumes the held car")


func _test_strict_optional_metadata_rejections() -> void:
	var missing_remaining: Dictionary = _active_data(5201)
	missing_remaining["players"][0]["engineering_vehicle"].erase("remaining_admissions")
	_assert_rejected(missing_remaining, "metadata missing remaining_admissions")

	var missing_previous_vehicle: Dictionary = _active_data(5202)
	missing_previous_vehicle["players"][0]["engineering_vehicle"].erase("previous_vehicle")
	_assert_rejected(missing_previous_vehicle, "metadata missing previous_vehicle")

	var missing_previous_dice: Dictionary = _active_data(5203)
	missing_previous_dice["players"][0]["engineering_vehicle"].erase("previous_dice_count")
	_assert_rejected(missing_previous_dice, "metadata missing previous_dice_count")

	var remaining_low: Dictionary = _active_data(5204, 0)
	_assert_rejected(remaining_low, "remaining_admissions below one")
	var remaining_high: Dictionary = _active_data(5205, 8)
	_assert_rejected(remaining_high, "remaining_admissions above seven")
	var remaining_type: Dictionary = _active_data(5206)
	remaining_type["players"][0]["engineering_vehicle"]["remaining_admissions"] = "3"
	_assert_rejected(remaining_type, "remaining_admissions wrong type")

	var vehicle_type: Dictionary = _active_data(5207)
	vehicle_type["players"][0]["engineering_vehicle"]["previous_vehicle"] = 1
	_assert_rejected(vehicle_type, "previous_vehicle wrong type")
	var vehicle_value: Dictionary = _active_data(5208)
	vehicle_value["players"][0]["engineering_vehicle"]["previous_vehicle"] = ENGINEERING_VEHICLE
	_assert_rejected(vehicle_value, "previous_vehicle cannot itself be engineering")
	var walking_dice: Dictionary = _active_data(5209, 3, "walking", 2)
	_assert_rejected(walking_dice, "walking previous dice above its limit")
	var motorcycle_dice: Dictionary = _active_data(5210, 3, "motorcycle", 3)
	_assert_rejected(motorcycle_dice, "motorcycle previous dice above its limit")
	var car_dice: Dictionary = _active_data(5211, 3, "car", 4)
	_assert_rejected(car_dice, "car previous dice above its limit")
	var dice_type: Dictionary = _active_data(5212)
	dice_type["players"][0]["engineering_vehicle"]["previous_dice_count"] = "1"
	_assert_rejected(dice_type, "previous_dice_count wrong type")

	var inactive_metadata: Dictionary = _active_data(5213)
	inactive_metadata["players"][0]["vehicle"] = "walking"
	inactive_metadata["players"][0]["dice_count"] = 1
	_assert_rejected(inactive_metadata, "metadata on an inactive ordinary vehicle")

	var active_without_metadata: Dictionary = _active_data(5214)
	active_without_metadata["players"][0].erase("engineering_vehicle")
	_assert_rejected(active_without_metadata, "engineering vehicle without metadata")

	var active_wrong_dice: Dictionary = _active_data(5215)
	active_wrong_dice["players"][0]["dice_count"] = 2
	_assert_rejected(active_wrong_dice, "engineering vehicle with more than one die")

	var dead_active: Dictionary = _active_data(5216)
	dead_active["players"][0]["alive"] = false
	_assert_rejected(dead_active, "dead player with active engineering metadata")

	var unknown_key: Dictionary = _active_data(5217)
	unknown_key["players"][0]["engineering_vehicle"]["unexpected"] = true
	_assert_rejected(unknown_key, "engineering metadata with an unknown key")

	var empty_metadata: Dictionary = _active_data(5218)
	empty_metadata["players"][0]["engineering_vehicle"] = {}
	_assert_rejected(empty_metadata, "empty engineering metadata")
