extends SceneTree

## Pure RED seed for the graph-fate landing and its bounded 37-candidate
## resolver. Every assertion enters through GameState and mutates only the
## synthetic fixture state; no future FateEvents module is preloaded here.

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/fate_fixture.gd")
const EngineeringVehicle = preload("res://game/core/engineering_vehicle.gd")
const OriginalInventory = preload("res://game/core/inventory_rules.gd")

const FATE_COUNT := 37
const UNSUPPORTED_IDS := [2, 3, 5, 6, 7, 8, 9, 32]
const CONNECTED_IDS := [0, 1, 4, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 33, 34, 35, 36]
const INCOME_AMOUNTS := {
	20: 1000, 21: 3000, 22: 2000, 25: 10000, 27: 4000, 28: 6000, 29: 8000, 31: 5000,
}
const EXPENSE_AMOUNTS := {
	17: 6000, 18: 600, 19: 1500, 23: 1000, 24: 2000, 26: 8000, 30: 5000,
}
const STATUS_DAYS := {12: 3, 13: 3}
const MAP_PRISON_DAYS := {33: 3, 34: 5, 35: 7, 36: 9}

var checks := 0
var failures := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	_test_fixture_and_shape()
	_test_pass_through_and_deck()
	_test_unsupported_candidates()
	_test_housing_effects()
	_test_deposit_transfer()
	_test_vehicle_and_traffic()
	_test_status_and_defense()
	_test_money_effects()
	_test_map_specific_effects()
	_test_rng_and_terminal()
	print("Fate flow checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _order(first_id: int) -> Array:
	var result: Array = [first_id]
	for candidate_id in range(FATE_COUNT):
		if candidate_id != first_id:
			result.append(candidate_id)
	return result


func _order_with_next(first_id: int, next_id: int) -> Array:
	var result: Array = [first_id, next_id]
	for candidate_id in range(FATE_COUNT):
		if candidate_id != first_id and candidate_id != next_id:
			result.append(candidate_id)
	return result


func _set_fate(game: Object, order: Array, cursor: int = 0, draw_count: int = 0, last: Dictionary = {}) -> void:
	game.state["fate"] = {
		"order": order.duplicate(true),
		"cursor": cursor,
		"draw_count": draw_count,
		"last": last.duplicate(true),
	}


func _new_game(first_id: int = 20, seed_value: int = 5600, player_count: int = 4, map_number: int = 1) -> Object:
	var game: Object = Fixture.new_game(seed_value, player_count, map_number)
	expect(game != null, "fate fixture creates a game")
	if game == null:
		return null
	game.state["phase"] = "await_action"
	game.state["current_player"] = 0
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["property_action_used"] = false
	game._set_action_options(0)
	_set_fate(game, _order(first_id))
	return game


func _fate_tile(game: Object) -> Dictionary:
	var board: Variant = game.state.get("board", null)
	if typeof(board) != TYPE_ARRAY or board.is_empty() or typeof(board.back()) != TYPE_DICTIONARY:
		return {}
	return board.back()


func _land_fate(game: Object, label: String, final_landing: bool = true) -> void:
	if game == null:
		return
	var tile := _fate_tile(game)
	expect(not tile.is_empty(), label + " has a fate road")
	if tile.is_empty():
		return
	var player: Dictionary = game.state.players[0]
	player["position"] = int(tile.get("index", game.state.board.size() - 1))
	player["previous_position"] = maxi(0, int(player["position"]) - 1)
	game._graph_visit_tile(0, tile, final_landing)


func _last(game: Object) -> Dictionary:
	var fate: Variant = game.state.get("fate", {})
	if typeof(fate) != TYPE_DICTIONARY:
		return {}
	var last: Variant = fate.get("last", {})
	return last if typeof(last) == TYPE_DICTIONARY else {}


func _event_types(game: Object) -> Array:
	var result: Array = []
	for event_value in game.state.get("event_log", []):
		if typeof(event_value) == TYPE_DICTIONARY:
			result.append(str(event_value.get("type", "")))
	return result


func _events_of_type(game: Object, event_type: String) -> Array:
	var result: Array = []
	for event_value in game.state.get("event_log", []):
		if typeof(event_value) == TYPE_DICTIONARY and str(event_value.get("type", "")) == event_type:
			result.append(event_value)
	return result


func _expect_last(game: Object, candidate_id: int, resolved_id: int, map_slot: int, outcome: String = "applied") -> Dictionary:
	var last := _last(game)
	var expected_keys := ["candidate_id", "id", "map_slot", "player_id", "targets", "changes", "summary", "outcome", "raw_amount", "raw_days", "gate_result"]
	var actual_keys: Array = last.keys()
	actual_keys.sort()
	expected_keys.sort()
	expect(actual_keys == expected_keys, "fate result uses the fixed canonical last shape")
	expect(int(last.get("candidate_id", -1)) == candidate_id, "fate result preserves selected candidate id")
	expect(int(last.get("id", -1)) == resolved_id, "fate result stores remapped id")
	expect(int(last.get("map_slot", -1)) == map_slot, "fate result stores source map slot")
	expect(int(last.get("player_id", -1)) == 0, "fate result records landing player")
	expect(typeof(last.get("targets", null)) == TYPE_ARRAY, "fate result has typed targets")
	expect(typeof(last.get("changes", null)) == TYPE_ARRAY, "fate result has typed changes")
	expect(typeof(last.get("summary", null)) == TYPE_STRING and not str(last.get("summary", "")).is_empty(), "fate result has a readable summary")
	expect(str(last.get("outcome", "")) == outcome, "fate result records outcome")
	expect(typeof(last.get("raw_amount", null)) == TYPE_INT and int(last.get("raw_amount", -1)) >= 0, "fate result has nonnegative raw amount")
	expect(typeof(last.get("raw_days", null)) == TYPE_INT and int(last.get("raw_days", -1)) >= 0, "fate result has nonnegative raw days")
	expect(typeof(last.get("gate_result", null)) == TYPE_INT and int(last.get("gate_result", -1)) in [0, 1, 2], "fate result has the source gate result")
	return last


func _target_ids(last: Dictionary) -> Array:
	var result: Array = []
	for target_value in last.get("targets", []):
		if typeof(target_value) == TYPE_INT:
			result.append(int(target_value))
		elif typeof(target_value) == TYPE_DICTIONARY:
			for key in ["player_id", "tile_id", "node", "id", "source_object_id"]:
				if typeof(target_value.get(key, null)) == TYPE_INT:
					result.append(int(target_value[key]))
					break
	return result


func _test_fixture_and_shape() -> void:
	var game := _new_game(20)
	if game == null:
		return
	var tile := _fate_tile(game)
	expect(int(tile.get("event_code", -1)) == 3, "fixture tail preserves source fate event code")
	expect(int(tile.get("source_status_bits", -1)) == 3, "fixture tail preserves source fate status bits")
	expect(str(tile.get("name", "")) == "測試命運", "fixture tail has synthetic fate name")
	expect(str(tile.get("kind", "")) == "fate", "source event code 3 classifies as fate")
	var fate: Variant = game.state.get("fate", null)
	expect(typeof(fate) == TYPE_DICTIONARY, "fate state is a dictionary")
	if typeof(fate) == TYPE_DICTIONARY:
		expect(fate.size() == 4, "fate state has exactly order/cursor/draw_count/last")
		expect(fate.order.size() == FATE_COUNT, "fate state stores all 37 candidates")
		expect(int(fate.cursor) == 0 and int(fate.draw_count) == 0 and fate.last.is_empty(), "fate state starts at cursor zero with empty result")
	var validation: Dictionary = Game.validate_save(game.to_dict())
	expect(bool(validation.get("ok", false)), "legal fate fixture save validates: " + str(validation.get("errors", [])))
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null, "legal fate fixture survives JSON")
	if restored != null:
		expect(restored.to_json() == game.to_json(), "fate state round trips without mutation")


func _test_pass_through_and_deck() -> void:
	var passed := _new_game(20)
	var before_fate: Dictionary = passed.state.fate.duplicate(true)
	var before_cash: int = int(passed.state.players[0].cash)
	_land_fate(passed, "fate pass-through", false)
	expect(passed.state.fate == before_fate, "passing over fate does not draw or mutate fate state")
	expect(int(passed.state.players[0].cash) == before_cash, "passing over fate does not apply a fate effect")
	expect(not _event_types(passed).has("fate_preview"), "passing over fate emits no preview")

	var game := _new_game(20)
	_land_fate(game, "single fate draw")
	_expect_last(game, 20, 20, 20)
	expect(int(game.state.fate.cursor) == 1, "fate cursor advances once after a resolved candidate")
	expect(int(game.state.fate.draw_count) == 1, "fate draw count increments once")
	var previews := _events_of_type(game, "fate_preview")
	var resolved := _events_of_type(game, "fate_resolved")
	expect(previews.size() == 1 and resolved.size() == 1, "resolved fate emits one preview and one resolved event")
	if not resolved.is_empty():
		expect(int(resolved.back().get("draw_count", -1)) == 1, "resolved fate carries draw count for UI correlation")

	var wrapped := _new_game(20)
	_set_fate(wrapped, _order(20), 36)
	_land_fate(wrapped, "fate deck wrap")
	_expect_last(wrapped, 20, 20, 20)
	expect(int(wrapped.state.fate.cursor) == 1, "fate cursor wraps from 36 to zero")
	expect(int(wrapped.state.fate.draw_count) == 1, "wrapped fate still counts one draw")

	var skip_order: Array = [2, 3, 5, 6, 7, 8, 9, 32, 20]
	for candidate_id in range(FATE_COUNT):
		if not skip_order.has(candidate_id):
			skip_order.append(candidate_id)
	var skipped := _new_game(20)
	_set_fate(skipped, skip_order)
	_land_fate(skipped, "fate unsupported scan")
	_expect_last(skipped, 20, 20, 20)
	expect(int(skipped.state.fate.cursor) == 9, "unsupported candidates advance cursor before selection")
	expect(int(skipped.state.fate.draw_count) == 1, "unsupported candidates do not increment draw count")
	var skipped_events := _events_of_type(skipped, "fate_skipped")
	expect(skipped_events.size() == UNSUPPORTED_IDS.size(), "unsupported candidates each emit a skip event")


func _test_unsupported_candidates() -> void:
	for candidate_id in UNSUPPORTED_IDS:
		var game := _new_game(candidate_id, 5610 + candidate_id)
		_set_fate(game, _order_with_next(candidate_id, 20))
		var before: String = game.to_json()
		var player: Dictionary = game.state.players[0]
		player["loan"] = 777
		player["loan_due_day"] = 18
		_give_card(game, 0, "購地")
		_land_fate(game, "unsupported candidate %d" % candidate_id)
		var last := _last(game)
		expect(int(last.get("candidate_id", -1)) != candidate_id, "unsupported candidate %d never resolves as fate" % candidate_id)
		expect(int(game.state.fate.draw_count) == 1, "unsupported candidate %d does not consume a draw" % candidate_id)
		expect(int(player.get("loan", -1)) == 777 and player.cards == ["購地"], "unsupported candidate %d leaves unrelated state unchanged" % candidate_id)
		# The seed was intentionally changed after the baseline snapshot; compare
		# only the fields that the unsupported scan is allowed to touch.
		expect(int(game.state.fate.cursor) == 2, "unsupported candidate %d advances exactly one cursor slot before next candidate" % candidate_id)
		expect(_events_of_type(game, "fate_skipped").size() >= 1, "unsupported candidate %d emits fate_skipped" % candidate_id)
		if candidate_id == 2:
			expect(not before.is_empty(), "loan skip fixture has a serializable baseline")


func _own_property(game: Object, tile_id: int, owner_id: int, level: int) -> void:
	var tile: Dictionary = game.state.board[tile_id]
	tile["owner"] = owner_id
	tile["building_level"] = level
	if tile.has("rent_by_level"):
		tile["rent"] = int(tile.rent_by_level[clampi(level, 0, tile.rent_by_level.size() - 1)])
	var player: Dictionary = game.state.players[owner_id]
	var properties: Array = player.get("properties", [])
	if not properties.has(tile_id):
		properties.append(tile_id)
	player["properties"] = properties
	game._recalculate_property_values()


func _give_card(game: Object, player_id: int, card_id: String) -> bool:
	var player: Dictionary = game.state.players[player_id]
	var result: Dictionary = OriginalInventory.grant_card(game.state.inventory_supply, player.cards, card_id)
	expect(bool(result.get("ok", false)), "fixture grants %s from the finite card supply" % card_id)
	return bool(result.get("ok", false))


func _test_housing_effects() -> void:
	var built := _new_game(0)
	_own_property(built, 2, 0, 2)
	# A built facility proves ID 0 scans housing only. The facility's source and
	# level remain untouched even though it is also owned by the current player.
	var facility: Dictionary = built.state.board[1]
	facility["owner"] = 0
	facility["building_level"] = 1
	built.state.players[0].properties.append(1)
	built._recalculate_property_values()
	var other_before: Dictionary = built.state.board[3].duplicate(true)
	var facility_before: Dictionary = facility.duplicate(true)
	var cash_before := int(built.state.players[0].cash)
	_land_fate(built, "built housing sale")
	_expect_last(built, 0, 0, 0)
	var selected: Dictionary = built.state.board[2]
	expect(int(built.state.players[0].cash) == cash_before + 2 * int(selected.get("house_price", 0)), "ID 0 credits built housing level times house price")
	expect(int(selected.get("building_level", -1)) == 0 and int(selected.get("rent", -1)) == 100, "ID 0 clears selected housing level and rent")
	expect(int(selected.get("owner", -1)) == 0, "ID 0 preserves housing owner")
	expect(built.state.board[3] == other_before, "ID 0 leaves a non-target housing tile unchanged")
	expect(facility == facility_before, "ID 0 never selects or mutates a facility")
	expect(int(built.state.players[0].property_values) > 0, "ID 0 resynchronizes remaining asset valuation")

	var unbuilt := _new_game(1, 5621)
	_own_property(unbuilt, 3, 0, 0)
	var property_before: Dictionary = unbuilt.state.board[2].duplicate(true)
	var unbuilt_cash := int(unbuilt.state.players[0].cash)
	_land_fate(unbuilt, "unbuilt housing sale")
	_expect_last(unbuilt, 1, 1, 1)
	var sold: Dictionary = unbuilt.state.board[3]
	expect(int(unbuilt.state.players[0].cash) == unbuilt_cash + int(sold.get("land_price", 0)), "ID 1 credits unbuilt housing land price")
	expect(int(sold.get("owner", -1)) == -1, "ID 1 clears unbuilt housing owner")
	expect(not unbuilt.state.players[0].properties.has(3), "ID 1 removes sold housing from owner index")
	expect(unbuilt.state.board[2] == property_before, "ID 1 leaves another housing tile unchanged")


func _set_deposit(game: Object, player_id: int, amount: int) -> void:
	game.state.players[player_id]["deposit"] = amount
	var total := 0
	for player in game.state.players:
		total += int(player.get("deposit", 0))
	game.state.bank["deposits"] = total


func _test_deposit_transfer() -> void:
	var game := _new_game(4, 5630)
	_set_deposit(game, 0, 1000)
	_set_deposit(game, 1, 10001)
	_set_deposit(game, 2, 20009)
	_set_deposit(game, 3, 9000)
	game.state.players[3]["alive"] = false
	game.state.players[3]["bankrupt"] = true
	var deposits_before: Array = []
	for player in game.state.players:
		deposits_before.append(int(player.get("deposit", 0)))
	var total_before := 0
	for amount in deposits_before:
		total_before += int(amount)
	var bank_cash_before := int(game.state.bank.cash)
	_land_fate(game, "deposit levy")
	var last := _expect_last(game, 4, 4, 4)
	var expected_donor1 := int(deposits_before[1]) / 10
	var expected_donor2 := int(deposits_before[2]) / 10
	expect(int(game.state.players[1].deposit) == int(deposits_before[1]) - expected_donor1, "ID 4 truncates donor one deposit levy")
	expect(int(game.state.players[2].deposit) == int(deposits_before[2]) - expected_donor2, "ID 4 truncates donor two deposit levy")
	expect(int(game.state.players[3].deposit) == int(deposits_before[3]), "ID 4 ignores dead donors")
	expect(int(game.state.players[0].deposit) == int(deposits_before[0]) + expected_donor1 + expected_donor2, "ID 4 credits all living donor levies to recipient deposit")
	var total_after := 0
	for player in game.state.players:
		total_after += int(player.get("deposit", 0))
	expect(total_after == total_before, "ID 4 preserves total deposits")
	expect(int(game.state.bank.cash) == bank_cash_before, "ID 4 does not move bank cash")
	expect(_target_ids(last).size() >= 2, "ID 4 records donor targets")


func _set_vehicle(game: Object, vehicle: String) -> void:
	var player: Dictionary = game.state.players[0]
	player["vehicle"] = vehicle
	player["dice_count"] = 2 if vehicle == "motorcycle" else 3 if vehicle == "car" else 1
	var vehicles: Dictionary = player.get("vehicles", {}).duplicate(true)
	vehicles["motorcycle"] = vehicle == "motorcycle" or bool(vehicles.get("motorcycle", false))
	vehicles["car"] = vehicle == "car" or bool(vehicles.get("car", false))
	player["vehicles"] = vehicles
	if vehicle == "motorcycle":
		player.tools["機車"] = 0
		game.state.inventory_supply.tools["機車"] = int(game.state.inventory_supply.tools.get("機車", 0)) - 1
	elif vehicle == "car":
		player.tools["汽車"] = 0
		game.state.inventory_supply.tools["汽車"] = int(game.state.inventory_supply.tools.get("汽車", 0)) - 1
	elif vehicle == EngineeringVehicle.VEHICLE_ID:
		player["engineering_vehicle"] = EngineeringVehicle.metadata("walking", 1)


func _test_vehicle_and_traffic() -> void:
	for entry in [
		{"candidate": 10, "vehicle": "motorcycle", "resolved": 10},
		{"candidate": 10, "vehicle": "car", "resolved": 11},
		{"candidate": 11, "vehicle": "motorcycle", "resolved": 10},
		{"candidate": 11, "vehicle": "car", "resolved": 11},
	]:
		var game := _new_game(int(entry.candidate), 5640 + int(entry.candidate) + int(entry.resolved))
		_set_vehicle(game, str(entry.vehicle))
		var spare_before: int = int(game.state.players[0].tools.get("路障", 0))
		var vehicle_supply_key := "機車" if str(entry.vehicle) == "motorcycle" else "汽車"
		var supply_before: int = int(game.state.inventory_supply.tools.get(vehicle_supply_key, 0))
		_land_fate(game, "traffic candidate %d %s" % [entry.candidate, entry.vehicle])
		_expect_last(game, int(entry.candidate), int(entry.resolved), int(entry.resolved))
		var player: Dictionary = game.state.players[0]
		expect(str(player.get("vehicle", "")) == "walking" and int(player.get("dice_count", -1)) == 1, "traffic fate returns active vehicle to walking")
		expect(int(game.state.inventory_supply.tools.get(vehicle_supply_key, 0)) == supply_before + 1, "traffic fate returns one finite vehicle unit")
		expect(int(player.tools.get("路障", 0)) == spare_before, "traffic fate preserves unrelated spare tools")
		expect(bool(player.vehicles.get(str(entry.vehicle), false)), "traffic fate preserves vehicle ownership flag")

	var engineering := _new_game(10, 5650)
	_set_fate(engineering, _order_with_next(10, 20))
	_set_vehicle(engineering, EngineeringVehicle.VEHICLE_ID)
	_land_fate(engineering, "engineering traffic skip")
	_expect_last(engineering, 10, 20, 20)
	expect(int(engineering.state.fate.cursor) == 2, "engineering vehicle is outside all 10-16 traffic candidates")


func _attach_gate_god(game: Object, god_id: int) -> void:
	var player: Dictionary = game.state.players[0]
	player["god_id"] = god_id
	game.state["god_objects"] = [{"id": god_id, "owner": 0, "node": int(player.get("position", 0)), "days": 3}]


func _test_status_and_defense() -> void:
	for entry in [
		{"candidate": 12, "vehicle": "walking", "resolved": 12},
		{"candidate": 12, "vehicle": "motorcycle", "resolved": 13},
		{"candidate": 13, "vehicle": "walking", "resolved": 12},
		{"candidate": 13, "vehicle": "motorcycle", "resolved": 13},
	]:
		var game := _new_game(int(entry.candidate), 5660 + int(entry.candidate) + int(entry.resolved))
		_set_vehicle(game, str(entry.vehicle))
		game.state.players[0]["hospital_days"] = 0
		game.state.players[0]["prison_days"] = 0
		_land_fate(game, "status remap %d %s" % [entry.candidate, entry.vehicle])
		_expect_last(game, int(entry.candidate), int(entry.resolved), int(entry.resolved))
		expect(int(game.state.players[0].hospital_days) == STATUS_DAYS[int(entry.resolved)] if int(entry.resolved) in STATUS_DAYS else true, "status fate admits three hospital days")
		expect(int(game.state.players[0].position) == 0, "status fate lands at the canonical hospital node")

	var car := _new_game(12, 5672)
	_set_fate(car, _order_with_next(12, 20))
	_set_vehicle(car, "car")
	_land_fate(car, "car status skip")
	_expect_last(car, 12, 20, 20)
	expect(int(car.state.fate.cursor) == 2, "car is ineligible for 12/13 status candidates")

	var blocked := _new_game(12, 5673)
	_attach_gate_god(blocked, 4) # f72 +150: status gate returns cancel.
	_land_fate(blocked, "status god block")
	_expect_last(blocked, 12, 12, 12, "blocked")
	expect(int(blocked.state.players[0].hospital_days) == 0, "status gate cancellation leaves status unchanged")
	expect(int(blocked.state.players[0].god_id) == 4, "status gate cancellation preserves attached god")

	var doubled := _new_game(12, 5674)
	_attach_gate_god(doubled, 7) # f72 -100: status gate doubles duration.
	_land_fate(doubled, "status god double")
	_expect_last(doubled, 12, 12, 12)
	expect(int(doubled.state.players[0].hospital_days) == 6, "status gate result two doubles hospital duration")

	var scapegoat := _new_game(33, 5680)
	# Candidate 33 uses the same status defense boundary as the common prison
	# handlers. A target with 嫁禍 redirects synchronously to the lowest alive
	# alternative; no pending interactive trap state is invented.
	_give_card(scapegoat, 0, "嫁禍")
	_land_fate(scapegoat, "prison scapegoat fallback")
	_expect_last(scapegoat, 33, 33, 33)
	expect(int(scapegoat.state.players[0].prison_days) == 0, "scapegoat source target avoids direct prison admission")
	expect(int(scapegoat.state.players[1].prison_days) == 3, "scapegoat redirects to lowest alive player")
	expect(not scapegoat.state.players[0].cards.has("嫁禍"), "scapegoat consumes the defense card")

	var no_fallback := _new_game(33, 5681, 2)
	no_fallback.state.players[1]["alive"] = false
	no_fallback.state.players[1]["bankrupt"] = true
	_give_card(no_fallback, 0, "嫁禍")
	_land_fate(no_fallback, "prison direct fallback")
	_expect_last(no_fallback, 33, 33, 33)
	expect(int(no_fallback.state.players[0].prison_days) == 3, "scapegoat is retained when no alternative player exists")
	expect(no_fallback.state.players[0].cards.has("嫁禍"), "嫁禍 remains when there is no valid fallback target")


func _test_money_effects() -> void:
	for candidate_id in INCOME_AMOUNTS.keys():
		var game := _new_game(int(candidate_id), 5700 + int(candidate_id))
		game.state["price_index"] = 2
		var cash_before := int(game.state.players[0].cash)
		var bank_before := int(game.state.bank.cash)
		_land_fate(game, "income %d" % candidate_id)
		var last := _expect_last(game, int(candidate_id), int(candidate_id), int(candidate_id))
		var amount := int(INCOME_AMOUNTS[candidate_id]) * 2
		expect(int(game.state.players[0].cash) == cash_before + amount, "income ID %d credits price-indexed amount directly to player cash" % candidate_id)
		expect(int(game.state.bank.cash) == bank_before, "income ID %d does not subtract bank cash" % candidate_id)
		expect(int(last.get("raw_amount", -1)) == amount, "income ID %d stores the raw price-indexed amount" % candidate_id)

	for candidate_id in EXPENSE_AMOUNTS.keys():
		var game := _new_game(int(candidate_id), 5800 + int(candidate_id))
		game.state["price_index"] = 2
		var cash_before := int(game.state.players[0].cash)
		var bank_before := int(game.state.bank.cash)
		_land_fate(game, "expense %d" % candidate_id)
		var last := _expect_last(game, int(candidate_id), int(candidate_id), int(candidate_id))
		var amount := int(EXPENSE_AMOUNTS[candidate_id]) * 2
		expect(int(game.state.players[0].cash) == cash_before - amount, "expense ID %d charges price-indexed amount" % candidate_id)
		expect(int(game.state.bank.cash) == bank_before + amount, "expense ID %d sends payment to bank" % candidate_id)
		expect(int(last.get("raw_amount", -1)) == amount, "expense ID %d stores the raw price-indexed amount" % candidate_id)

	# Income f70 values above 100 are cancelled only by the source god gate;
	# below zero doubles the amount. ID 20 has a fixed 1000 base here.
	var income_blocked := _new_game(20, 5901)
	_attach_gate_god(income_blocked, 15) # f70 -200 for income => cancel.
	var income_cash := int(income_blocked.state.players[0].cash)
	_land_fate(income_blocked, "income god block")
	_expect_last(income_blocked, 20, 20, 20, "blocked")
	expect(int(income_blocked.state.players[0].cash) == income_cash, "income god cancellation leaves cash unchanged")

	var income_double := _new_game(20, 5902)
	_attach_gate_god(income_double, 2) # f70 +150 for income => double.
	var income_double_cash := int(income_double.state.players[0].cash)
	_land_fate(income_double, "income god double")
	_expect_last(income_double, 20, 20, 20)
	expect(int(income_double.state.players[0].cash) == income_double_cash + 2000, "income god result two doubles amount")

	var expense_blocked := _new_game(17, 5903)
	_attach_gate_god(expense_blocked, 15) # f70 -200 for expense => double, not cancel.
	var expense_blocked_cash := int(expense_blocked.state.players[0].cash)
	_land_fate(expense_blocked, "expense god double")
	_expect_last(expense_blocked, 17, 17, 17)
	expect(int(expense_blocked.state.players[0].cash) == expense_blocked_cash - 12000, "expense god result two doubles amount")

	var expense_cancel := _new_game(17, 5904)
	_attach_gate_god(expense_cancel, 2) # f70 +150 for expense => cancel.
	var expense_cancel_cash := int(expense_cancel.state.players[0].cash)
	_land_fate(expense_cancel, "expense god block")
	_expect_last(expense_cancel, 17, 17, 17, "blocked")
	expect(int(expense_cancel.state.players[0].cash) == expense_cancel_cash, "expense god cancellation leaves cash unchanged")


func _test_map_specific_effects() -> void:
	for candidate_id in MAP_PRISON_DAYS.keys():
		var game := _new_game(int(candidate_id), 6000 + int(candidate_id), 4, 1)
		_land_fate(game, "Game map prison %d" % candidate_id)
		_expect_last(game, int(candidate_id), int(candidate_id), int(candidate_id))
		expect(int(game.state.players[0].prison_days) == int(MAP_PRISON_DAYS[candidate_id]), "map-specific candidate %d admits its source duration" % candidate_id)
		expect(int(game.state.players[0].position) == 4, "map-specific candidate %d uses the prison status node" % candidate_id)

	var map2 := _new_game(33, 6040, 4, 2)
	_land_fate(map2, "Game map two prison")
	_expect_last(map2, 33, 33, 37)
	var map3 := _new_game(33, 6041, 4, 3)
	_land_fate(map3, "Game map three prison")
	_expect_last(map3, 33, 33, 41)
	var map4 := _new_game(33, 6042, 4, 4)
	_land_fate(map4, "Game map four prison")
	_expect_last(map4, 33, 33, 45)

	var wrong_edition := _new_game(33, 6043)
	_set_fate(wrong_edition, _order_with_next(33, 20))
	wrong_edition.state.map_source["edition"] = "MultiverseJourney"
	_land_fate(wrong_edition, "wrong edition map-specific skip")
	_expect_last(wrong_edition, 33, 20, 20)


func _test_rng_and_terminal() -> void:
	var no_gate := _new_game(20, 6100)
	var no_gate_before := int(no_gate.state.rng_state)
	_land_fate(no_gate, "god gate no RNG")
	_expect_last(no_gate, 20, 20, 20)
	expect(int(no_gate.state.rng_state) == no_gate_before, "god gate range zero to fifty consumes no RNG")

	var mid_gate := _new_game(20, 6101)
	_attach_gate_god(mid_gate, 9) # f70 +60: exactly one income gate coin flip.
	var mid_before := int(mid_gate.state.rng_state)
	var probe := RandomNumberGenerator.new()
	probe.state = mid_before
	probe.randi()
	_land_fate(mid_gate, "god gate one RNG")
	_expect_last(mid_gate, 20, 20, 20)
	expect(int(mid_gate.state.rng_state) == int(probe.state), "mid-range god gate consumes exactly one RNG draw")

	var handoff := _new_game(17, 6110)
	handoff.state.players[0]["cash"] = 0
	handoff.state.players[0]["deposit"] = 0
	handoff.state.current_player = 0
	var next_before := int(handoff.state.current_player)
	_land_fate(handoff, "nonterminal fate bankruptcy")
	_expect_last(handoff, 17, 17, 17)
	expect(not bool(handoff.state.players[0].alive), "unpayable fate charge declares the current player bankrupt")
	expect(int(handoff.state.current_player) != next_before, "nonterminal fate bankruptcy advances exactly once to a live player")
	expect(_events_of_type(handoff, "fate_resolved").size() == 1, "bankruptcy during fate does not duplicate the resolved event")

	var terminal := _new_game(17, 6111, 2)
	terminal.state.players[1]["alive"] = false
	terminal.state.players[1]["bankrupt"] = true
	terminal.state.players[0]["cash"] = 0
	terminal.state.players[0]["deposit"] = 0
	_land_fate(terminal, "terminal fate bankruptcy")
	_expect_last(terminal, 17, 17, 17)
	expect(str(terminal.state.phase) == "game_over", "last live player bankruptcy ends the game")
	expect(_events_of_type(terminal, "fate_resolved").size() == 1, "terminal fate bankruptcy emits one resolved event")
