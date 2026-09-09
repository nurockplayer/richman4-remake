extends SceneTree

## Issue #74 save-boundary seed for optional pending_finance.
##
## pending_finance is optional when no financial response is waiting.  When it
## exists it is a strict seven-field record and must survive JSON reload with
## the same public response continuation.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")

const TAX_CARD := "查稅"
const FREE_CARD := "免費"
const SCAPEGOAT_CARD := "嫁禍"
const PENDING_KEYS := ["kind", "stage", "payer_id", "creditor_id", "amount", "node_id", "caster_id"]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_optional_clean_save()
	_test_generated_free_pending_roundtrip()
	_test_generated_redirect_pending_roundtrip()
	_test_strict_pending_shape_and_context()
	print("Financial save checks: %d, failures: %d" % [checks, failures])
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
	expect(game != null, "legal v13 financial save fixture starts")
	if game == null:
		return null
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
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "fresh financial save fixture validates")
	return game


func prepare(game: Object, player_id: int = 0, phase: String = "await_action") -> void:
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
	game.call("_set_action_options", player_id)


func stage_card(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	expect(bool(result.get("ok", false)), "fixture stages %s for player %d" % [card_id, player_id])
	if bool(result.get("ok", false)):
		game.call("_set_action_options", int(game.state.get("current_player", player_id)))
	return bool(result.get("ok", false))


func set_cash(game: Object, player_id: int, cash: int) -> void:
	game.state["players"][player_id]["cash"] = cash


func pending(game: Object) -> Dictionary:
	var value: Variant = game.state.get("pending_finance", {})
	return value if value is Dictionary else {}


func use_tax(game: Object, target_id: Variant, cancel: Variant = false) -> Dictionary:
	return game.choose_action("use_card", {"card_id": TAX_CARD, "target_id": target_id, "cancel": cancel})


func respond(game: Object, cancel: Variant, target_id: Variant = 1) -> Dictionary:
	return game.choose_action("respond_finance", {"cancel": cancel, "target_id": target_id})


func start_free_pending(seed_value: int, target_cash: int = 5000, phase: String = "await_action") -> Object:
	var game: Object = fresh(seed_value)
	if game == null:
		return null
	stage_card(game, 0, TAX_CARD)
	stage_card(game, 1, FREE_CARD)
	set_cash(game, 1, target_cash)
	prepare(game, 0, phase)
	if not game.item_is_implemented("card", TAX_CARD):
		expect(false, "RED: save fixture admits 查稅 before generating pending finance")
		return null
	var result: Dictionary = use_tax(game, 1)
	expect(bool(result.get("ok", false)), "public 查稅 creates a saveable 免費 pending state")
	var pending_value: Dictionary = pending(game)
	expect(not pending_value.is_empty(), "public 查稅 pending state is present")
	if pending_value.is_empty():
		return null
	return game


func start_redirect_pending(seed_value: int) -> Object:
	var game: Object = fresh(seed_value)
	if game == null:
		return null
	stage_card(game, 0, TAX_CARD)
	stage_card(game, 1, FREE_CARD)
	stage_card(game, 1, SCAPEGOAT_CARD)
	set_cash(game, 1, 10005)
	if not game.item_is_implemented("card", TAX_CARD):
		expect(false, "RED: save fixture admits 查稅 before generating redirect finance")
		return null
	expect(bool(use_tax(game, 1).get("ok", false)), "redirect fixture creates initial 免費 pending")
	var decline: Dictionary = respond(game, true)
	expect(bool(decline.get("ok", false)), "declining 免費 creates redirect pending")
	expect_equal(str(pending(game).get("stage", "")), "redirect", "redirect fixture reaches redirect stage")
	if pending(game).is_empty() or str(pending(game).get("stage", "")) != "redirect":
		return null
	return game


func assert_exact_pending(data: Dictionary, label: String) -> void:
	var value: Variant = data.get("pending_finance", null)
	expect(value is Dictionary, label + " stores a Dictionary")
	if not value is Dictionary:
		return
	var record: Dictionary = value
	expect_equal(record.keys().size(), PENDING_KEYS.size(), label + " has exactly seven fields")
	for key in PENDING_KEYS:
		expect(record.has(key), label + " includes " + key)


func assert_roundtrip(data: Dictionary, label: String) -> Object:
	var validation: Dictionary = Game.validate_save(data)
	expect(bool(validation.get("ok", false)), label + " validates: " + str(validation.get("errors", [])))
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	expect(parsed is Dictionary, label + " JSON parses as an object")
	if not parsed is Dictionary:
		return null
	var restored: Object = Game.from_dict(parsed)
	expect(restored != null, label + " JSON reloads")
	if restored != null:
		expect_equal(restored.to_dict(), data, label + " preserves every save field")
	return restored


func rejected(data: Dictionary, label: String) -> void:
	var validation: Dictionary = Game.validate_save(data)
	expect(not bool(validation.get("ok", false)), label + " validator rejects")
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	if parsed is Dictionary:
		expect(Game.from_dict(parsed) == null, label + " loader rejects")


func fallback_pending_data(seed_value: int) -> Dictionary:
	# This shape is only used to enumerate strict malformed cases while the
	# feature is absent.  Once production exposes pending finance, generated
	# state above becomes the authority for all valid continuation assertions.
	var game: Object = fresh(seed_value)
	if game == null:
		return {}
	stage_card(game, 0, TAX_CARD)
	Inventory.consume_card(game.state["inventory_supply"], game.state["players"][0]["cards"], TAX_CARD)
	stage_card(game, 1, FREE_CARD)
	var data: Dictionary = game.to_dict()
	data["current_player"] = 0
	data["phase"] = "await_action"
	data["action_options"] = ["respond_finance"]
	data["pending_finance"] = {
		"kind": "tax",
		"stage": "free",
		"payer_id": 1,
		"creditor_id": 0,
		"amount": 1000,
		"node_id": 0,
		"caster_id": 0,
	}
	return data


func _test_optional_clean_save() -> void:
	var game: Object = fresh(74201)
	if game == null:
		return
	var data: Dictionary = game.to_dict()
	expect(not data.has("pending_finance"), "clean save omits optional pending_finance")
	expect_equal(int(data.get("version", -1)), 13, "financial cards do not introduce a save version")
	expect(not data.has("original_financial_cards"), "financial cards do not introduce a gameplay marker")
	var restored: Object = assert_roundtrip(data, "clean v13 save")
	if restored != null:
		expect(not restored.to_dict().has("pending_finance"), "clean JSON reload remains without pending finance")


func _test_generated_free_pending_roundtrip() -> void:
	var game: Object = start_free_pending(74202)
	if game == null:
		return
	var data: Dictionary = game.to_dict()
	assert_exact_pending(data, "generated 免費 pending")
	var restored: Object = assert_roundtrip(data, "generated 免費 pending save")
	if restored == null:
		return
	var live_response: Dictionary = respond(game, false)
	var restored_response: Dictionary = respond(restored, false)
	expect(bool(live_response.get("ok", false)), "live 免費 response succeeds after save")
	expect(bool(restored_response.get("ok", false)), "reloaded 免費 response succeeds")
	expect_equal(restored.to_json(), game.to_json(), "free response continuation is exact after JSON reload")
	expect(pending(game).is_empty() and pending(restored).is_empty(), "free response clears pending finance in both copies")

	# 查稅 may be selected before rolling.  The pending record preserves that
	# caller phase, and a JSON reload resumes the same await_roll continuation.
	var roll_game: Object = start_free_pending(74205, 5000, "await_roll")
	if roll_game == null:
		return
	expect_equal(str(roll_game.state.get("phase", "")), "await_roll", "await_roll tax pending preserves its caller phase")
	var roll_data: Dictionary = roll_game.to_dict()
	assert_exact_pending(roll_data, "await_roll generated 免費 pending")
	var roll_restored: Object = assert_roundtrip(roll_data, "await_roll 免費 pending save")
	if roll_restored == null:
		return
	var roll_live_response: Dictionary = respond(roll_game, false)
	var roll_restored_response: Dictionary = respond(roll_restored, false)
	expect(bool(roll_live_response.get("ok", false)), "await_roll 免費 response succeeds after save")
	expect(bool(roll_restored_response.get("ok", false)), "reloaded await_roll 免費 response succeeds")
	expect_equal(str(roll_game.state.get("phase", "")), "await_roll", "live await_roll response restores caller phase")
	expect_equal(str(roll_restored.state.get("phase", "")), "await_roll", "reloaded await_roll response restores caller phase")
	expect_equal(roll_restored.to_json(), roll_game.to_json(), "await_roll response continuation is exact after JSON reload")


func _test_generated_redirect_pending_roundtrip() -> void:
	var game: Object = start_redirect_pending(74203)
	if game == null:
		return
	var data: Dictionary = game.to_dict()
	assert_exact_pending(data, "generated redirect pending")
	var restored: Object = assert_roundtrip(data, "generated redirect pending save")
	if restored == null:
		return
	var live_response: Dictionary = respond(game, false, 2)
	var restored_response: Dictionary = respond(restored, false, 2)
	expect(bool(live_response.get("ok", false)), "live redirect response succeeds after save")
	expect(bool(restored_response.get("ok", false)), "reloaded redirect response succeeds")
	expect_equal(restored.to_json(), game.to_json(), "redirect response continuation is exact after JSON reload")
	expect(pending(game).is_empty() and pending(restored).is_empty(), "redirect response clears pending finance in both copies")


func _test_strict_pending_shape_and_context() -> void:
	var base: Dictionary = fallback_pending_data(74204)
	if base.is_empty():
		return
	assert_exact_pending(base, "canonical malformed-fixture pending")
	expect(bool(Game.validate_save(base).get("ok", false)), "canonical pending fixture is valid under the intended contract")
	# Top-level type, empty records, missing fields, and unexpected fields are all
	# rejected.  A present pending_finance can never mean "no response".
	for value in [null, [], "pending", 0, {}]:
		var malformed: Dictionary = base.duplicate(true)
		malformed["pending_finance"] = value
		rejected(malformed, "pending_finance top-level type %s" % str(value))
	for key in PENDING_KEYS:
		var missing: Dictionary = base.duplicate(true)
		missing["pending_finance"].erase(key)
		rejected(missing, "pending_finance missing " + key)
	var extra: Dictionary = base.duplicate(true)
	extra["pending_finance"]["extra"] = true
	rejected(extra, "pending_finance extra field")

	var field_values: Dictionary = {
		"kind": ["unknown", 1, true, [], {}],
		"stage": ["payment", 1, true, [], {}],
		"payer_id": [-1, 4, "1", true, 1.5, [], {}],
		"creditor_id": [-2, 4, "0", true, 0.5, [], {}],
		"amount": [-1, -100, 2000000000000, "1000", true, 1000.5, [], {}],
		"node_id": [-1, 10, "0", true, 0.5, [], {}],
		"caster_id": [-2, 4, "0", true, 0.5, [], {}],
	}
	for key in field_values:
		for value in field_values[key]:
			var malformed: Dictionary = base.duplicate(true)
			malformed["pending_finance"][key] = value
			rejected(malformed, "pending_finance malformed " + key + "=" + str(value))

	# Field relationships and runtime context are part of the save contract.
	var relationships: Array = []
	var payer_is_caster: Dictionary = base.duplicate(true)
	payer_is_caster["pending_finance"]["payer_id"] = 0
	relationships.append([payer_is_caster, "pending payer cannot be caster"])
	var wrong_creditor: Dictionary = base.duplicate(true)
	wrong_creditor["pending_finance"]["creditor_id"] = 1
	relationships.append([wrong_creditor, "pending tax creditor must be caster"])
	var wrong_node: Dictionary = base.duplicate(true)
	wrong_node["pending_finance"]["node_id"] = 1
	relationships.append([wrong_node, "pending node must be the source node"])
	var wrong_caster: Dictionary = base.duplicate(true)
	wrong_caster["pending_finance"]["caster_id"] = 1
	relationships.append([wrong_caster, "pending caster identity mismatch"])
	var wrong_kind: Dictionary = base.duplicate(true)
	wrong_kind["pending_finance"]["kind"] = "rent"
	relationships.append([wrong_kind, "tax pending cannot change kind without its source context"])
	var bad_redirect: Dictionary = base.duplicate(true)
	bad_redirect["pending_finance"]["stage"] = "redirect"
	relationships.append([bad_redirect, "redirect stage requires a qualifying original tax and 嫁禍"])
	for entry in relationships:
		rejected(entry[0], entry[1])

	for phase in ["await_route", "game_over"]:
		var phase_data: Dictionary = base.duplicate(true)
		phase_data["phase"] = phase
		phase_data["action_options"] = [] if phase != "await_roll" else ["use_card"]
		rejected(phase_data, "pending finance outside await_action: " + phase)
	var wrong_options: Dictionary = base.duplicate(true)
	wrong_options["action_options"] = ["end_turn"]
	rejected(wrong_options, "pending finance requires respond_finance action options")
	var ai_payer: Dictionary = base.duplicate(true)
	ai_payer["players"][1]["is_ai"] = true
	ai_payer["players"][1]["is_human"] = false
	rejected(ai_payer, "pending finance payer must remain human while awaiting response")
	var detained_payer: Dictionary = base.duplicate(true)
	detained_payer["players"][1]["hospital_days"] = 2
	detained_payer["players"][1]["position"] = 0
	detained_payer["players"][1]["previous_position"] = -1
	rejected(detained_payer, "pending finance payer cannot be detained")
	var missing_free: Dictionary = base.duplicate(true)
	missing_free["players"][1]["cards"] = []
	missing_free["inventory_supply"]["cards"][FREE_CARD] = int(missing_free["inventory_supply"]["cards"].get(FREE_CARD, 0)) + 1
	rejected(missing_free, "free pending requires the response card")

	# Waiting finance cannot coexist with another resumable driver.
	var trap_conflict: Dictionary = base.duplicate(true)
	trap_conflict["pending_trap"] = {"caster_id": 0, "target_id": 1}
	Inventory.grant_card(trap_conflict["inventory_supply"], trap_conflict["players"][1]["cards"], SCAPEGOAT_CARD)
	rejected(trap_conflict, "pending finance conflicts with pending trap")
	var remote_conflict: Dictionary = base.duplicate(true)
	remote_conflict["pending_remote_dice"] = {"player_id": 0, "value": 1}
	rejected(remote_conflict, "pending finance conflicts with remote dice")
	var company_conflict: Dictionary = base.duplicate(true)
	company_conflict["company_service_pending"] = 1
	rejected(company_conflict, "pending finance conflicts with company service")
