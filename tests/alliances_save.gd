extends SceneTree

## Issue #75 save-boundary seed for the optional reciprocal alliance record.
##
## This is intentionally a RED seed.  The alliance card is already present in
## the v13 finite inventory catalogue, but the game state does not yet own the
## player-level alliance schema or its loader validation.
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")

const ALLIANCE_DAYS := 7
const ALLIANCE_RELEASE_MARKER := 128

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_optional_and_reciprocal_schema()
	_test_strict_schema_rejections()
	_test_status_and_lifecycle_boundaries()
	print("Alliances save checks: %d, failures: %d" % [checks, failures])
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
	expect(game != null, "v13 alliance save fixture starts")
	if game == null:
		return null
	game.state["god_objects"] = []
	game.state["roadblocks"] = {}
	game.state["ground_hazards"] = {}
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = player_value
		player["position"] = 2
		player["previous_position"] = -1
		player.erase("alliance")
	game.state["current_player"] = 0
	game.state["phase"] = "await_roll"
	game._set_action_options(0)
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "clean v13 alliance fixture validates")
	return game


func pair(data: Dictionary, first_id: int, second_id: int, first_turns: int = ALLIANCE_DAYS, second_turns: int = ALLIANCE_DAYS) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	result["players"][first_id]["alliance"] = {"partner_id": second_id, "turns": first_turns}
	result["players"][second_id]["alliance"] = {"partner_id": first_id, "turns": second_turns}
	return result


func valid(data: Dictionary, label: String) -> void:
	var validation: Dictionary = Game.validate_save(data)
	expect(bool(validation.get("ok", false)), label + " validates: " + str(validation.get("errors", [])))
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	expect(parsed is Dictionary, label + " JSON is an object")
	if parsed is Dictionary:
		var restored: Object = Game.from_dict(parsed)
		expect(restored != null, label + " JSON continuation loads")
		if restored != null:
			expect_equal(restored.to_dict(), data, label + " continuation preserves the alliance record")
		expect_equal(Game.from_dict(parsed) != null, bool(validation.get("ok", false)), label + " loader agrees with validator")


func rejected(data: Dictionary, label: String) -> void:
	var validation: Dictionary = Game.validate_save(data)
	expect(not bool(validation.get("ok", false)), label + " validator rejects")
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	if parsed is Dictionary:
		expect(Game.from_dict(parsed) == null, label + " loader rejects")


func _test_optional_and_reciprocal_schema() -> void:
	var base_game: Object = fresh(75101)
	if base_game == null:
		return
	var base: Dictionary = base_game.to_dict()
	valid(base, "v13 save without optional alliance")

	var active: Dictionary = pair(base, 0, 1)
	valid(active, "reciprocal seven-turn alliance")
	expect_equal(active["players"][0]["alliance"], {"partner_id": 1, "turns": ALLIANCE_DAYS}, "caster alliance record has canonical keys")
	expect_equal(active["players"][1]["alliance"], {"partner_id": 0, "turns": ALLIANCE_DAYS}, "partner alliance record has canonical keys")

	# A player is admitted independently.  The 128 marker is therefore valid
	# while the reciprocal side still has its ordinary countdown.
	var asymmetric_release: Dictionary = pair(base, 0, 1, ALLIANCE_RELEASE_MARKER, ALLIANCE_DAYS)
	valid(asymmetric_release, "asymmetric 128 release marker survives JSON")
	var symmetric_release: Dictionary = pair(base, 0, 1, ALLIANCE_RELEASE_MARKER, ALLIANCE_RELEASE_MARKER)
	valid(symmetric_release, "symmetric 128 release markers survive JSON")


func _test_strict_schema_rejections() -> void:
	var game: Object = fresh(75102)
	if game == null:
		return
	var base: Dictionary = pair(game.to_dict(), 0, 1)

	var invalid_records: Array = [null, [], "alliance", false, 0, {},
		{"partner_id": 1},
		{"turns": ALLIANCE_DAYS},
		{"partner_id": 1, "turns": ALLIANCE_DAYS, "extra": true},
	]
	for index in range(invalid_records.size()):
		var malformed: Dictionary = base.duplicate(true)
		malformed["players"][0]["alliance"] = invalid_records[index]
		rejected(malformed, "malformed alliance record %d" % index)

	var invalid_partners: Array = ["1", 1.5, true, null, {}, [], -1, 4, 0]
	for partner_value in invalid_partners:
		var malformed: Dictionary = base.duplicate(true)
		malformed["players"][0]["alliance"]["partner_id"] = partner_value
		rejected(malformed, "malformed alliance partner %s" % str(partner_value))

	var invalid_turns: Array = ["7", 1.5, true, null, {}, [], -1, 0, 8, 129]
	for turns_value in invalid_turns:
		var malformed: Dictionary = base.duplicate(true)
		malformed["players"][0]["alliance"]["turns"] = turns_value
		rejected(malformed, "malformed alliance turns %s" % str(turns_value))

	var missing_partner: Dictionary = base.duplicate(true)
	missing_partner["players"][1]["alliance"].erase("partner_id")
	rejected(missing_partner, "reciprocal record missing partner id")
	var missing_turns: Dictionary = base.duplicate(true)
	missing_turns["players"][1]["alliance"].erase("turns")
	rejected(missing_turns, "reciprocal record missing turns")
	var nonreciprocal: Dictionary = base.duplicate(true)
	nonreciprocal["players"][1].erase("alliance")
	rejected(nonreciprocal, "single-sided alliance record")
	var wrong_reciprocal: Dictionary = base.duplicate(true)
	wrong_reciprocal["players"][1]["alliance"]["partner_id"] = 2
	rejected(wrong_reciprocal, "nonreciprocal partner ids")
	var third_party: Dictionary = base.duplicate(true)
	third_party["players"][2]["alliance"] = {"partner_id": 1, "turns": ALLIANCE_DAYS}
	rejected(third_party, "one player cannot have two alliance partners")

	var dead_partner: Dictionary = base.duplicate(true)
	dead_partner["players"][1]["alive"] = false
	dead_partner["players"][1]["bankrupt"] = true
	rejected(dead_partner, "alliance partner must remain alive")
	var non_current_base: Dictionary = game.to_dict()
	non_current_base["current_player"] = 2
	valid(non_current_base, "non-current holder baseline validates before death mutation")
	var dead_holder: Dictionary = pair(non_current_base, 0, 1)
	dead_holder["players"][0]["alive"] = false
	dead_holder["players"][0]["bankrupt"] = true
	rejected(dead_holder, "alliance holder must remain alive")


func _test_status_and_lifecycle_boundaries() -> void:
	var game: Object = fresh(75103, 2)
	if game == null:
		return
	var base: Dictionary = pair(game.to_dict(), 0, 1, 1, 1)
	# Detention and sleep are temporary admission states; alliance records must
	# remain serializable while the public turn flow handles their timers.
	var prison_node: int = int(game.call("_status_node_index", "prison"))
	base["players"][1]["prison_days"] = 1
	base["players"][1]["position"] = prison_node
	base["players"][1]["previous_position"] = -1
	valid(base, "detained alliance remains loadable")
	var sleeping: Dictionary = pair(game.to_dict(), 0, 1, ALLIANCE_RELEASE_MARKER, ALLIANCE_DAYS)
	sleeping["players"][1]["winter_sleep_days"] = 3
	sleeping["players"][1]["vehicle"] = "walking"
	sleeping["players"][1]["dice_count"] = 1
	valid(sleeping, "sleeping alliance remains loadable")

	var bankruptcy: Dictionary = pair(game.to_dict(), 0, 1)
	bankruptcy["players"][1]["cash"] = 0
	bankruptcy["players"][1]["deposit"] = 0
	var deposits := 0
	for player_value in bankruptcy["players"]:
		if typeof(player_value) == TYPE_DICTIONARY:
			deposits += int(player_value.get("deposit", 0))
	bankruptcy["bank"]["deposits"] = deposits
	valid(bankruptcy, "alliance partner pre-bankruptcy snapshot remains loadable")
	bankruptcy["players"][1]["alive"] = false
	bankruptcy["players"][1]["bankrupt"] = true
	rejected(bankruptcy, "bankruptcy cannot retain an active alliance")
