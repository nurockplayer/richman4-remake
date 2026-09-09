extends SceneTree

## Issue #75 acceptance seed for the original 同盟 card and allied rent path.
##
## This is intentionally a RED seed.  The v13 building-card fixture provides
## the complete finite inventory and status/company/facility graph.  Alliance
## state is staged only in legal save-shaped fixtures; production owns all
## effects once the public API is implemented.
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")

const ALLIANCE_CARD := "同盟"
const ALLIANCE_DAYS := 7
const ALLIANCE_RELEASE_MARKER := 128

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_fixture_and_public_card()
	_test_target_filter_and_typed_atomicity()
	_test_pair_replacement_and_refresh()
	_test_turn_expiry_sleep_detention_and_bankruptcy()
	_test_allied_property_facility_and_company_paths()
	print("Alliances flow checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func fresh(seed_value: int, player_count: int = 4) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, Fixture.definition(), Fixture.new_game_options())
	expect(game != null, "v13 building-card fixture starts")
	if game == null:
		return null
	expect_equal(int(game.state.get("version", -1)), 13, "alliance fixture uses the v13 save")
	expect(bool(game.state.get("original_building_cards", false)), "alliance fixture retains the v13 marker")
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
	expect(Game.validate_save(game.to_dict()).get("ok", false), "fresh v13 fixture is save-valid")
	return game


func prepare_action(game: Object, player_id: int = 0, position: int = 2) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = "await_action"
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_trap"] = {}
	game.state.erase("pending_trap_card")
	game.state["pending_remote_dice"] = {}
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["bank_access"] = false
	game.state["bank_landing"] = false
	game.state["players"][player_id]["position"] = position
	game.state["players"][player_id]["previous_position"] = -1
	game._set_action_options(player_id)


func stage_card(game: Object, player_id: int = 0) -> bool:
	var result: Dictionary = Inventory.grant_card(
		game.state["inventory_supply"],
		game.state["players"][player_id]["cards"],
		ALLIANCE_CARD,
	)
	expect(bool(result.get("ok", false)), "finite inventory stages 同盟")
	if bool(result.get("ok", false)):
		game._set_action_options(player_id)
	return bool(result.get("ok", false))


func legal(game: Object, label: String) -> bool:
	if game == null:
		expect(false, label + " has a game fixture")
		return false
	var snapshot: Dictionary = game.to_dict()
	var validation: Dictionary = Game.validate_save(snapshot)
	expect(bool(validation.get("ok", false)), label + " validates before action: " + str(validation.get("errors", [])))
	var encoded: String = game.to_json()
	var parsed: Variant = JSON.parse_string(encoded)
	var restored: Object = Game.from_dict(parsed) if typeof(parsed) == TYPE_DICTIONARY else null
	expect(restored != null, label + " has a JSON-continuable save")
	if restored != null:
		expect_equal(restored.to_json(), encoded, label + " JSON continuation is exact")
	return bool(validation.get("ok", false))


func alliance_record(game: Object, player_id: int) -> Dictionary:
	var player: Dictionary = game.state["players"][player_id]
	var value: Variant = player.get("alliance", null)
	return value if typeof(value) == TYPE_DICTIONARY else {}


func pair(game: Object, first_id: int, second_id: int, first_turns: int = ALLIANCE_DAYS, second_turns: int = ALLIANCE_DAYS) -> void:
	game.state["players"][first_id]["alliance"] = {"partner_id": second_id, "turns": first_turns}
	game.state["players"][second_id]["alliance"] = {"partner_id": first_id, "turns": second_turns}


func prepare_turn(game: Object, player_id: int) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = "await_action"
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_trap"] = {}
	game.state.erase("pending_trap_card")
	game.state["pending_remote_dice"] = {}
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["bank_access"] = false
	game.state["bank_landing"] = false
	game._set_action_options(player_id)


func target_players(game: Object, caster_id: int, label: String) -> Array:
	legal(game, label + " fixture")
	if not game.has_method("alliance_target_players"):
		expect(false, label + " exposes alliance_target_players")
		return []
	var value: Variant = game.call("alliance_target_players", caster_id)
	expect(value is Array, label + " target API returns an Array")
	return value if value is Array else []


func reject_atomic(game: Object, params: Dictionary, label: String) -> void:
	# Current main has no alliance target API yet.  Its legacy choose_action
	# coercion throws on malformed target/cancel values, so keep this RED seed
	# executable while still recording every typed-contract expectation.  Once
	# the public alliance API exists, the real atomic calls below are enabled.
	if not game.has_method("alliance_target_players"):
		expect(false, label + " awaits the alliance typed input boundary")
		return
	legal(game, "before " + label)
	var before_json: String = game.to_json()
	var before_rng: String = str(game.to_dict().get("rng_state_text", ""))
	var result: Variant = game.choose_action("use_card", params)
	expect(result is Dictionary, label + " returns a Dictionary")
	if result is Dictionary:
		expect(not bool(result.get("ok", false)), label + " is rejected")
	expect_equal(game.to_json(), before_json, label + " leaves state and supply unchanged")
	expect_equal(str(game.to_dict().get("rng_state_text", "")), before_rng, label + " leaves RNG unchanged")


func _test_fixture_and_public_card() -> void:
	var definition: Dictionary = Fixture.definition()
	expect(bool(definition.get("supports_original_building_cards", false)), "alliance fixture advertises v13 building-card support")
	var game: Object = fresh(75011)
	if game == null:
		return
	prepare_action(game, 0, 2)
	expect(stage_card(game), "同盟 card is available through finite inventory")
	expect(game.state["action_options"].has("use_card"), "await_action exposes the public card action")
	var supply_before: int = int(game.state["inventory_supply"]["cards"][ALLIANCE_CARD])
	legal(game, "alliance cancellation")
	var before_cancel: String = game.to_json()
	var cancelled: Dictionary = game.choose_action("use_card", {"card_id": ALLIANCE_CARD, "target_id": 1, "cancel": true})
	expect(bool(cancelled.get("ok", false)), "public 同盟 cancellation succeeds")
	expect_equal(game.to_json(), before_cancel, "cancellation is atomic and does not consume the card")
	expect(game.state["players"][0]["cards"].has(ALLIANCE_CARD), "cancelled 同盟 remains held")
	expect_equal(int(game.state["inventory_supply"]["cards"][ALLIANCE_CARD]), supply_before, "cancelled 同盟 leaves finite supply unchanged")

	var use_game: Object = fresh(75012)
	if use_game == null:
		return
	prepare_action(use_game, 0, 2)
	stage_card(use_game)
	legal(use_game, "alliance confirmation")
	var confirmed: Dictionary = use_game.choose_action("use_card", {"card_id": ALLIANCE_CARD, "target_id": 1, "cancel": false})
	expect(bool(confirmed.get("ok", false)), "public 同盟 confirmation succeeds")
	if bool(confirmed.get("ok", false)):
		expect_equal(alliance_record(use_game, 0), {"partner_id": 1, "turns": ALLIANCE_DAYS}, "confirmed 同盟 records caster side")
		expect_equal(alliance_record(use_game, 1), {"partner_id": 0, "turns": ALLIANCE_DAYS}, "confirmed 同盟 records reciprocal side")
		expect(not use_game.state["players"][0]["cards"].has(ALLIANCE_CARD), "confirmed 同盟 consumes exactly one card")
		expect_equal(int(use_game.state["inventory_supply"]["cards"][ALLIANCE_CARD]), 2, "confirmed 同盟 recycles exactly one finite card")
	expect(Game.validate_save(use_game.to_dict()).get("ok", false), "confirmed 同盟 remains save-valid")


func _test_target_filter_and_typed_atomicity() -> void:
	var game: Object = fresh(75021)
	if game == null:
		return
	prepare_action(game, 0, 2)
	var fresh_targets: Array = target_players(game, 0, "fresh alliance target list")
	expect_equal(fresh_targets, [1, 2, 3], "fresh target list contains living opponents and excludes caster")

	var prison_node: int = int(game.call("_status_node_index", "prison"))
	game.state["players"][2]["prison_days"] = 3
	game.state["players"][2]["hospital_days"] = 0
	game.state["players"][2]["position"] = prison_node
	game.state["players"][2]["previous_position"] = -1
	game.state["players"][3]["alive"] = false
	game.state["players"][3]["bankrupt"] = true
	game._set_action_options(0)
	var filtered_targets: Array = target_players(game, 0, "detained and dead alliance target list")
	expect_equal(filtered_targets, [1], "target list excludes detained and dead players")

	prepare_action(game, 0, 2)
	stage_card(game)
	var malformed_targets: Array = ["1", 1.5, true, null, {}, []]
	for malformed in malformed_targets:
		reject_atomic(game, {"card_id": ALLIANCE_CARD, "target_id": malformed}, "typed alliance target %s" % str(malformed))
	reject_atomic(game, {"card_id": ALLIANCE_CARD, "target_id": 99}, "out-of-range alliance target")
	reject_atomic(game, {"card_id": ALLIANCE_CARD, "target_id": 0}, "self alliance target")
	reject_atomic(game, {"card_id": ALLIANCE_CARD, "target_id": 2}, "detained alliance target")
	reject_atomic(game, {"card_id": ALLIANCE_CARD, "target_id": 3}, "dead alliance target")
	reject_atomic(game, {"card_id": ALLIANCE_CARD, "target_id": 1, "cancel": "true"}, "typed alliance cancellation")
	reject_atomic(game, {"card_id": ALLIANCE_CARD, "target_id": 1, "cancel": 1}, "numeric alliance cancellation")
	reject_atomic(game, {"card_id": ALLIANCE_CARD, "cancel": false}, "missing alliance target")


func _test_pair_replacement_and_refresh() -> void:
	var game: Object = fresh(75031)
	if game == null:
		return
	prepare_action(game, 0, 2)
	stage_card(game)
	legal(game, "first alliance pair")
	var first: Dictionary = game.choose_action("use_card", {"card_id": ALLIANCE_CARD, "target_id": 1, "cancel": false})
	expect(bool(first.get("ok", false)), "first alliance pair succeeds")
	if not bool(first.get("ok", false)):
		return
	prepare_action(game, 0, 2)
	stage_card(game)
	legal(game, "alliance pair replacement")
	var replacement: Dictionary = game.choose_action("use_card", {"card_id": ALLIANCE_CARD, "target_id": 2, "cancel": false})
	expect(bool(replacement.get("ok", false)), "alliance pair replacement succeeds")
	expect_equal(alliance_record(game, 0), {"partner_id": 2, "turns": ALLIANCE_DAYS}, "replacement keeps caster at seven turns")
	expect_equal(alliance_record(game, 2), {"partner_id": 0, "turns": ALLIANCE_DAYS}, "replacement creates reciprocal second pair")
	expect(alliance_record(game, 1).is_empty(), "replacement clears the caster's former partner")

	prepare_action(game, 0, 2)
	stage_card(game)
	legal(game, "repeated alliance pair")
	var repeated: Dictionary = game.choose_action("use_card", {"card_id": ALLIANCE_CARD, "target_id": 2, "cancel": false})
	expect(bool(repeated.get("ok", false)), "repeated alliance pairing succeeds")
	expect_equal(alliance_record(game, 0).get("turns", -1), ALLIANCE_DAYS, "repeated pairing resets caster duration to seven")
	expect_equal(alliance_record(game, 2).get("turns", -1), ALLIANCE_DAYS, "repeated pairing resets partner duration to seven")


func _test_turn_expiry_sleep_detention_and_bankruptcy() -> void:
	var timer_game: Object = fresh(75041, 2)
	if timer_game != null:
		pair(timer_game, 0, 1, ALLIANCE_DAYS, 1)
		prepare_turn(timer_game, 0)
		legal(timer_game, "alliance timer before partner admission")
		var first_end: Dictionary = timer_game.end_turn()
		expect(bool(first_end.get("ok", false)), "public turn enters the partner")
		expect_equal(alliance_record(timer_game, 0).get("turns", -1), ALLIANCE_DAYS, "caster timer does not tick on the other player's admission")
		expect_equal(alliance_record(timer_game, 1).get("turns", -1), ALLIANCE_RELEASE_MARKER, "one alliance turn becomes the 128 release marker")
		prepare_turn(timer_game, 1)
		legal(timer_game, "alliance timer before caster re-admission")
		var second_end: Dictionary = timer_game.end_turn()
		expect(bool(second_end.get("ok", false)), "public turn re-enters the caster")
		expect_equal(alliance_record(timer_game, 0).get("turns", -1), 6, "only the newly admitted caster timer decrements")
		expect_equal(alliance_record(timer_game, 1).get("turns", -1), ALLIANCE_RELEASE_MARKER, "128 remains until that player's next admission")
		prepare_turn(timer_game, 0)
		legal(timer_game, "alliance timer before symmetric release")
		var third_end: Dictionary = timer_game.end_turn()
		expect(bool(third_end.get("ok", false)), "public turn reaches the 128-day partner")
		expect(alliance_record(timer_game, 0).is_empty() and alliance_record(timer_game, 1).is_empty(), "128 release clears both alliance records symmetrically")

	var sleep_game: Object = fresh(75042, 2)
	if sleep_game != null:
		pair(sleep_game, 0, 1, 1, 1)
		sleep_game.state["players"][1]["winter_sleep_days"] = 1
		prepare_turn(sleep_game, 0)
		legal(sleep_game, "winter alliance admission")
		expect(bool(sleep_game.end_turn().get("ok", false)), "public turn admits sleeping alliance partner")
		expect_equal(alliance_record(sleep_game, 1).get("turns", -1), ALLIANCE_RELEASE_MARKER, "sleeping partner timer ticks at outer turn admission")
		legal(sleep_game, "before public winter sleep turn")
		var sleep_result: Dictionary = sleep_game.run_sleep_turn()
		expect(bool(sleep_result.get("ok", false)), "public run_sleep_turn completes winter admission")
		expect_equal(int(sleep_game.state["players"][1].get("winter_sleep_days", 0)), ALLIANCE_RELEASE_MARKER, "sleep outer flow preserves the 128 sleep marker")
		prepare_turn(sleep_game, 0)
		legal(sleep_game, "before sleeping partner release admission")
		expect(bool(sleep_game.end_turn().get("ok", false)), "public turn re-enters sleeping partner")
		expect(alliance_record(sleep_game, 0).is_empty() and alliance_record(sleep_game, 1).is_empty(), "sleeping partner's later admission clears the alliance pair")

	var detention_game: Object = fresh(75043, 2)
	if detention_game != null:
		pair(detention_game, 0, 1, 1, 1)
		var prison_node: int = int(detention_game.call("_status_node_index", "prison"))
		detention_game.state["players"][1]["prison_days"] = 1
		detention_game.state["players"][1]["hospital_days"] = 0
		detention_game.state["players"][1]["position"] = prison_node
		detention_game.state["players"][1]["previous_position"] = -1
		prepare_turn(detention_game, 0)
		legal(detention_game, "detention alliance admission")
		expect(bool(detention_game.end_turn().get("ok", false)), "public turn admits detained alliance partner")
		expect_equal(alliance_record(detention_game, 1).get("turns", -1), ALLIANCE_RELEASE_MARKER, "detained partner timer ticks at outer turn admission")
		legal(detention_game, "before public detention roll")
		var detained_roll: Dictionary = detention_game.roll()
		expect(bool(detained_roll.get("ok", false)) and bool(detained_roll.get("skipped", false)), "public roll resolves detained turn")
		expect_equal(alliance_record(detention_game, 1).get("turns", -1), ALLIANCE_RELEASE_MARKER, "detention does not freeze an already admitted alliance timer")
		prepare_turn(detention_game, 1)
		legal(detention_game, "before detained partner end turn")
		expect(bool(detention_game.end_turn().get("ok", false)), "detained player can end the public turn")
		prepare_turn(detention_game, 0)
		legal(detention_game, "before detained partner release admission")
		expect(bool(detention_game.end_turn().get("ok", false)), "public turn re-enters detained partner")
		expect(alliance_record(detention_game, 0).is_empty() and alliance_record(detention_game, 1).is_empty(), "detained partner's later admission clears the alliance pair")

	var bankruptcy_game: Object = fresh(75044)
	if bankruptcy_game != null:
		pair(bankruptcy_game, 0, 1)
		set_property(bankruptcy_game, 2, 2, 1, false)
		bankruptcy_game.state["players"][1]["cash"] = 0
		bankruptcy_game.state["players"][1]["deposit"] = 0
		sync_bank_deposits(bankruptcy_game)
		prepare_route(bankruptcy_game, 1, 2)
		legal(bankruptcy_game, "before alliance partner bankruptcy landing")
		var bankruptcy_result: Dictionary = bankruptcy_game.choose_route(2)
		expect(bool(bankruptcy_result.get("ok", false)), "public route reaches a bankruptcy landing")
		expect(bool(bankruptcy_game.state["players"][1].get("bankrupt", false)), "alliance partner bankruptcy is recorded")
		expect(alliance_record(bankruptcy_game, 0).is_empty() and alliance_record(bankruptcy_game, 1).is_empty(), "bankruptcy clears both alliance records")


func _test_allied_property_facility_and_company_paths() -> void:
	var mutual: Object = fresh(75051)
	if mutual != null:
		pair(mutual, 0, 1)
		set_property(mutual, 2, 1, 1, false)
		mutual.state["players"][0]["cash"] = 1000
		mutual.state["players"][1]["cash"] = 1000
		prepare_route(mutual, 0, 2)
		var before_cash: int = int(mutual.state["players"][0]["cash"])
		var before_rng: String = str(mutual.state["rng_state_text"])
		legal(mutual, "before mutual allied property landing")
		var mutual_result: Dictionary = mutual.choose_route(2)
		expect(bool(mutual_result.get("ok", false)), "public route reaches allied property")
		expect_equal(int(mutual.state["players"][0]["cash"]), before_cash, "allied landlord property charges no mutual rent")
		expect_equal(str(mutual.state["rng_state_text"]), before_rng, "mutual property waiver consumes no RNG")

	var ordinary: Object = fresh(75052)
	if ordinary != null:
		pair(ordinary, 0, 1)
		set_property(ordinary, 2, 1, 2, false)
		set_property(ordinary, 3, 0, 1, false)
		var payer_before: int = int(ordinary.state["players"][2]["cash"])
		var owner_before: int = int(ordinary.state["players"][1]["cash"])
		var ally_before: int = int(ordinary.state["players"][0]["cash"])
		prepare_route(ordinary, 2, 2)
		legal(ordinary, "before third-party same-name ordinary rent")
		var ordinary_result: Dictionary = ordinary.choose_route(2)
		expect(bool(ordinary_result.get("ok", false)), "public route reaches third-party same-name property")
		# Source rents are level 2 = 600 and level 1 = 250 in the v13 fixture.
		expect_equal(int(ordinary.state["players"][2]["cash"]), payer_before - 850, "third-party payer owes the combined same-name rent")
		expect_equal(int(ordinary.state["players"][1]["cash"]), owner_before + 600, "landlord receives its proportional same-name rent")
		expect_equal(int(ordinary.state["players"][0]["cash"]), ally_before + 250, "allied landlord receives its proportional same-name rent")

	var ordinary_short: Object = fresh(75053)
	if ordinary_short != null:
		pair(ordinary_short, 0, 1)
		set_property(ordinary_short, 2, 1, 2, false)
		set_property(ordinary_short, 3, 0, 1, false)
		ordinary_short.state["players"][2]["cash"] = 100
		ordinary_short.state["players"][2]["deposit"] = 0
		sync_bank_deposits(ordinary_short)
		var short_owner_before: int = int(ordinary_short.state["players"][1]["cash"])
		var short_ally_before: int = int(ordinary_short.state["players"][0]["cash"])
		prepare_route(ordinary_short, 2, 2)
		legal(ordinary_short, "before insufficient same-name rent")
		var short_result: Dictionary = ordinary_short.choose_route(2)
		expect(bool(short_result.get("ok", false)), "public route resolves insufficient same-name rent")
		expect(bool(ordinary_short.state["players"][2].get("bankrupt", false)), "insufficient combined rent follows bankruptcy")
		expect_equal(int(ordinary_short.state["players"][0]["cash"]) - short_ally_before, 29, "allied share truncates toward zero on partial payment")
		expect_equal(int(ordinary_short.state["players"][1]["cash"]) - short_owner_before, 71, "landlord receives the partial-payment remainder")
		expect_equal((int(ordinary_short.state["players"][0]["cash"]) - short_ally_before) + (int(ordinary_short.state["players"][1]["cash"]) - short_owner_before), 100, "partial rent credits only actually payable funds")

	var chain: Object = fresh(75054)
	if chain != null:
		pair(chain, 0, 1)
		set_property(chain, 2, 1, 1, true)
		set_property(chain, 3, 0, 1, true)
		var chain_payer_before: int = int(chain.state["players"][2]["cash"])
		var chain_owner_before: int = int(chain.state["players"][1]["cash"])
		var chain_ally_before: int = int(chain.state["players"][0]["cash"])
		prepare_route(chain, 2, 2)
		legal(chain, "before third-party chain rent")
		var chain_result: Dictionary = chain.choose_route(2)
		expect(bool(chain_result.get("ok", false)), "public route reaches third-party chain property")
		expect_equal(int(chain.state["players"][2]["cash"]), chain_payer_before - 4000, "third-party payer owes the combined chain rent")
		expect_equal(int(chain.state["players"][1]["cash"]), chain_owner_before + 2000, "chain landlord receives its proportional rent")
		expect_equal(int(chain.state["players"][0]["cash"]), chain_ally_before + 2000, "chain ally receives its proportional rent")

	var facility: Object = fresh(75055)
	if facility != null:
		pair(facility, 0, 1)
		set_facility(facility, 2, 1, 1, 1)
		facility.state["players"][0]["cash"] = 1000
		facility.state["players"][1]["cash"] = 1000
		prepare_route(facility, 0, 7)
		var facility_cash_before: int = int(facility.state["players"][0]["cash"])
		var facility_rng_before: String = str(facility.state["rng_state_text"])
		legal(facility, "before mutual allied facility landing")
		var facility_result: Dictionary = facility.choose_route(7)
		expect(bool(facility_result.get("ok", false)), "public route reaches allied facility")
		expect_equal(int(facility.state["players"][0]["cash"]), facility_cash_before, "allied facility service is waived")
		expect_equal(str(facility.state["rng_state_text"]), facility_rng_before, "mutual facility waiver consumes no RNG")

	var company: Object = fresh(75056)
	if company != null:
		pair(company, 0, 1)
		company.state["day"] = 2
		company._sync_state()
		var company_record: Dictionary = company.state["companies"][0]
		var company_symbol: String = str(company.state["market"]["rows"]["s01"].get("name", ""))
		company.state["players"][1]["stocks"]["s01"] = 1
		company_record["treasury"] = int(company_record.get("treasury", 0)) - 1
		company._update_company_owners()
		company_record["monthly_profit"] = -50
		var company_cash_before: int = int(company.state["players"][2]["cash"])
		var negative_profit_before: int = int(company_record["monthly_profit"])
		prepare_route(company, 2, 5)
		legal(company, "before allied company negative-profit landing")
		var company_result: Dictionary = company.choose_route(5)
		expect(bool(company_result.get("ok", false)), "public route reaches allied company")
		expect_equal(int(company.state["players"][2]["cash"]), company_cash_before - 150, "alliance does not waive company service fees")
		expect_equal(int(company_record["monthly_profit"]), negative_profit_before + 150, "company negative ledger still receives the actual toll")
		expect(company_symbol == "股票 1", "company fixture retains the source stock identity")


func set_property(game: Object, tile_id: int, owner_id: int, level: int, chain: bool) -> void:
	var tile: Dictionary = game.state["board"][tile_id]
	expect(tile.get("kind", "") == "property", "property fixture tile %d is ordinary property" % tile_id)
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var properties: Array = player_value.get("properties", []).duplicate(true)
		while properties.has(tile_id):
			properties.erase(tile_id)
		player_value["properties"] = properties
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


func sync_bank_deposits(game: Object) -> void:
	var deposits := 0
	for player_value in game.state.get("players", []):
		if typeof(player_value) == TYPE_DICTIONARY:
			deposits += int(player_value.get("deposit", 0))
	game.state["bank"]["deposits"] = deposits


func set_facility(game: Object, source_id: int, owner_id: int, level: int, facility_type: int) -> void:
	var canonical_id := -1
	for tile_value in game.state.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility" or int(tile_value.get("source_object_id", -1)) != source_id:
			continue
		if canonical_id < 0:
			canonical_id = int(tile_value.get("facility_node_index", tile_value.get("index", -1)))
		tile_value["owner"] = owner_id
		tile_value["building_level"] = level
		tile_value["facility_type"] = facility_type
		tile_value["facility_state"] = 0
	expect(canonical_id >= 0, "facility fixture contains source %d" % source_id)
	for player_value in game.state.get("players", []):
		if typeof(player_value) != TYPE_DICTIONARY:
			continue
		var properties: Array = player_value.get("properties", []).duplicate(true)
		while properties.has(canonical_id):
			properties.erase(canonical_id)
		player_value["properties"] = properties
	if owner_id >= 0 and owner_id < game.state["players"].size() and canonical_id >= 0:
		var owner_properties: Array = game.state["players"][owner_id].get("properties", []).duplicate(true)
		if not owner_properties.has(canonical_id):
			owner_properties.append(canonical_id)
		game.state["players"][owner_id]["properties"] = owner_properties
	game._recalculate_property_values()


func prepare_route(game: Object, player_id: int, target_id: int) -> bool:
	var board: Array = game.state.get("board", [])
	var source_id := -1
	for index in range(board.size()):
		if typeof(board[index]) != TYPE_DICTIONARY:
			continue
		var adjacent: Variant = board[index].get("adjacent", [])
		if typeof(adjacent) == TYPE_ARRAY and target_id in adjacent:
			source_id = index
			break
	if source_id < 0:
		expect(false, "route fixture has an edge into tile %d" % target_id)
		return false
	var options: Array = []
	var source_tile: Dictionary = board[source_id]
	var adjacent: Variant = source_tile.get("adjacent", [])
	if typeof(adjacent) == TYPE_ARRAY:
		for value in adjacent:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or floor(float(value)) != float(value):
				continue
			var next_id := int(value)
			if next_id != -1 and not options.has(next_id):
				options.append(next_id)
	if options.is_empty():
		options.append(source_id)
	options.sort()
	var player: Dictionary = game.state["players"][player_id]
	player["position"] = source_id
	player["previous_position"] = -1
	game.state["current_player"] = player_id
	game.state["phase"] = "await_route"
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["property_action_used"] = false
	game.state["route_options"] = options
	game.state["remaining_steps"] = 1
	game.state["pending_movement"] = {"player_id": player_id, "current_node": source_id, "previous_node": -1}
	game.state["pending_trap"] = {}
	game.state.erase("pending_trap_card")
	game.state["pending_remote_dice"] = {}
	game.state["bank_access"] = false
	game.state["bank_landing"] = false
	game._set_action_options(player_id)
	return options.has(target_id)
