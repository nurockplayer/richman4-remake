extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const StatusFixture = preload("res://tests/fixtures/status_fixture.gd")
const CompanyFixture = preload("res://tests/fixtures/company_fixture.gd")

var checks := 0
var failures := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func make_status_game(seed_value: int = 42, player_count: int = 4) -> Object:
	return Game.new_game_on_board(seed_value, player_count, StatusFixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"original_statuses": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})


func last_event_of_type(game: Object, event_type: String) -> Dictionary:
	var events: Array = game.state.get("event_log", [])
	for index in range(events.size() - 1, -1, -1):
		var event: Variant = events[index]
		if typeof(event) == TYPE_DICTIONARY and str(event.get("type", "")) == event_type:
			return event
	return {}


func set_direct_turn(game: Object, player_id: int, phase_name: String = "await_action") -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase_name
	game.state["property_action_used"] = false
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}


func _initialize() -> void:
	_test_status_admission_and_lifecycle()
	_test_status_actions_and_fees()
	_test_dog_and_legacy_hospital()
	_test_insurance_for_every_admission()
	_test_status_public_action_gates()
	print("Status flow checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _test_status_admission_and_lifecycle() -> void:
	var game := make_status_game()
	expect(game != null, "status source starts an executable game")
	if game == null:
		return
	expect(int(game.state.version) == Game.STATUS_SAVE_VERSION, "status mode uses v8 save")
	expect(bool(game.state.get("original_statuses", false)), "status marker is persisted")
	expect(bool(game.state.get("original_companies", false)) and bool(game.state.get("original_gods", false)) and bool(game.state.get("original_facilities", false)), "status mode retains all parent capability markers")

	var player: Dictionary = game.state.players[0]
	var duplicate_hospital: Dictionary = game.state.board[0].duplicate(true)
	duplicate_hospital["index"] = game.state.board.size()
	duplicate_hospital["source_node_id"] = game.state.board.size() + 1
	duplicate_hospital["adjacent"] = [4]
	game.state.board.append(duplicate_hospital)
	var destination := int(duplicate_hospital.index)
	player["position"] = 2
	player["previous_position"] = 1
	player["hospital_days"] = 5
	player["prison_days"] = 0
	player["stay_next"] = 56
	player["turtle_days"] = 57
	player["skip_turns"] = 0
	player["vehicle"] = "walking"
	player["god_id"] = 1
	var attached: Dictionary = game._god_object(1)
	attached["owner"] = 0
	attached["node"] = 2
	attached["days"] = 7
	set_direct_turn(game, 0, "await_route")
	game.state["route_options"] = [1, 3]
	game.state["remaining_steps"] = 2
	game.state["pending_movement"] = {"player_id": 0, "current_node": 2, "previous_node": 1}
	var before_invalid: String = game.to_json()
	var invalid: Dictionary = game._admit_player_status(0, "hospital", 0)
	expect(not bool(invalid.get("ok", false)), "zero-day status admission is rejected")
	expect(game.to_json() == before_invalid, "rejected status admission is atomic")
	invalid = game._admit_player_status(0, "unknown", 3)
	expect(not bool(invalid.get("ok", false)), "unknown status kind is rejected")
	expect(game.to_json() == before_invalid, "unknown status admission is atomic")

	var admitted: Dictionary = game._admit_player_status(0, "hospital", 3)
	expect(bool(admitted.get("ok", false)), "hospital admission succeeds")
	expect(int(player.hospital_days) == 8, "same status adds days")
	expect(int(player.prison_days) == 0, "same admission keeps opposite status clear")
	expect(int(player.position) == destination, "admission uses the last matching hospital node")
	expect(int(player.previous_position) == -1, "admission clears graph previous position")
	expect(game.state.route_options.is_empty() and int(game.state.remaining_steps) == 0 and game.state.pending_movement.is_empty(), "admission clears pending route state")
	expect(int(player.stay_next) == 56 and int(player.turtle_days) == 57 and int(player.skip_turns) == 0, "admission preserves unrelated movement counters")
	expect(int(attached.owner) == 0 and int(attached.node) == destination and int(player.god_id) == 1, "admission preserves and synchronizes attached god")
	expect(str(player.vehicle) == "walking" and bool(player.vehicles.walking), "admission preserves vehicle state")
	var event: Dictionary = last_event_of_type(game, "status_admitted")
	expect(str(event.get("status_kind", "")) == "hospital" and int(event.get("added_days", 0)) == 3 and int(event.get("remaining", -1)) == 8, "hospital admission event records source and duration")

	var noncurrent := make_status_game(43)
	noncurrent.state["god_objects"] = []
	var noncurrent_target: Dictionary = noncurrent.state.players[0]
	noncurrent_target["position"] = 2
	noncurrent_target["previous_position"] = 1
	noncurrent.state.players[1]["position"] = 1
	noncurrent.state.players[1]["previous_position"] = 0
	set_direct_turn(noncurrent, 1, "await_route")
	noncurrent.state["route_options"] = [2, 3]
	noncurrent.state["remaining_steps"] = 2
	noncurrent.state["pending_movement"] = {"player_id": 1, "current_node": 1, "previous_node": 0}
	noncurrent._set_action_options(1)
	var route_before: Array = noncurrent.state.route_options.duplicate(true)
	var pending_before: Dictionary = noncurrent.state.pending_movement.duplicate(true)
	var options_before: Array = noncurrent.state.action_options.duplicate(true)
	var noncurrent_admission: Dictionary = noncurrent._admit_player_status(0, "prison", 4)
	expect(bool(noncurrent_admission.get("ok", false)), "non-current player status admission succeeds")
	expect(noncurrent.state.route_options == route_before and int(noncurrent.state.remaining_steps) == 2 and noncurrent.state.pending_movement == pending_before, "non-current admission preserves current route state")
	expect(noncurrent.state.phase == "await_route" and noncurrent.state.action_options == options_before, "non-current admission preserves current phase and action options")

	player["hospital_days"] = 127
	player["prison_days"] = 4
	player["position"] = 2
	player["previous_position"] = 1
	set_direct_turn(game, 0)
	admitted = game._admit_player_status(0, "hospital", 1)
	expect(bool(admitted.get("ok", false)) and int(player.hospital_days) == 0, "seven-bit status addition permits a valid zero result")
	expect(int(player.prison_days) == 0, "hospital admission clears prison status")
	expect(int(player.position) == destination and int(player.previous_position) == -1, "wrapped admission still teleports and clears direction")

	player["hospital_days"] = 2
	player["prison_days"] = 0
	player["position"] = destination
	player["previous_position"] = -1
	set_direct_turn(game, 0, "await_roll")
	var skipped: Dictionary = game.roll()
	expect(bool(skipped.get("ok", false)) and bool(skipped.get("skipped", false)), "active hospital status skips the own roll")
	expect(int(player.hospital_days) == 1 and int(player.position) == destination, "status skip decrements without movement")
	expect(str(last_event_of_type(game, "status_skipped").get("status_kind", "")) == "hospital", "status skip event identifies hospital")
	game.state["phase"] = "await_roll"
	skipped = game.roll()
	expect(bool(skipped.get("skipped", false)) and int(player.hospital_days) == 128, "one remaining status day enters the terminal marker")
	game.state["phase"] = "await_roll"
	var released: Dictionary = game.roll()
	expect(bool(released.get("ok", false)) and int(player.hospital_days) == 0, "terminal status releases before normal movement")
	expect(not last_event_of_type(game, "status_released").is_empty(), "release is recorded before the resumed roll")

	var landed_before := int(player.hospital_days)
	game.state["phase"] = "await_action"
	game._graph_visit_tile(0, game.state.board[4], true)
	expect(int(player.hospital_days) == landed_before, "ordinary status facility landing is harmless")
	expect(str(game.state.last_event.get("type", "")) == "status_facility_landed" and str(game.state.last_event.get("name", "")) == "測試監獄", "status facility landing is named and observable")


func _test_status_actions_and_fees() -> void:
	var game := make_status_game(99)
	expect(game != null, "status action fixture starts")
	if game == null:
		return
	var player: Dictionary = game.state.players[0]
	player["position"] = 2
	player["previous_position"] = -1
	player["prison_days"] = 3
	player["hospital_days"] = 0
	player["cards"] = ["停留", "購地"]
	set_direct_turn(game, 0)
	game._set_action_options(0)
	expect(game.state.action_options.has("end_turn"), "detained player may end the turn")
	expect(not game.state.action_options.has("buy") and not game.state.action_options.has("upgrade") and not game.state.action_options.has("buy_vehicle"), "prison blocks property and vehicle actions")
	expect(not game.state.action_options.has("buy_stock") and not game.state.action_options.has("sell_stock"), "v8 prison hides active stock actions")
	expect(game.state.action_options == ["end_turn"], "v8 prison action phase only permits ending turn")
	player["position"] = 5
	game._set_action_options(0)
	expect(not game.state.action_options.has("buy_company"), "prison blocks direct company share purchase")

	# A detained owner waives property and facility service fees, while company
	# tolls remain payable through the separate company path.
	var debtor: Dictionary = game.state.players[1]
	debtor["cash"] = 1000
	var owner: Dictionary = game.state.players[0]
	owner["prison_days"] = 3
	owner["hospital_days"] = 0
	owner["alive"] = true
	game.state.board[2]["owner"] = 0
	owner["properties"] = [2]
	game.state["players"][1]["position"] = 2
	var cash_before: int = int(debtor.cash)
	game._charge_rent(1, 0, 100)
	expect(int(debtor.cash) == cash_before and str(game.state.last_event.get("type", "")) == "property_fee_waived", "prison owner waives property rent")

	var facility_tile: Dictionary = game.state.board[3].duplicate(true)
	facility_tile.merge({
		"kind": "facility",
		"owner": 0,
		"source_object_id": 1,
		"facility_node_index": 3,
		"facility_type": 1,
		"building_level": 1,
		"facility_state": 0,
		"land_price": 1000,
		"fee_by_level": [0, 100, 200, 300, 400, 500],
	}, true)
	game.state.board[3] = facility_tile
	game.state["players"][1]["position"] = 3
	game.state["last_roll_total"] = 1
	cash_before = int(debtor.cash)
	game._resolve_facility_visit(1, facility_tile)
	expect(int(debtor.cash) == cash_before and str(last_event_of_type(game, "property_fee_waived").get("kind", "")) == "facility", "prison owner waives facility service fee")

	var company_game := make_status_game(101)
	var company_owner: Dictionary = company_game.state.players[1]
	company_owner["prison_days"] = 3
	company_owner["hospital_days"] = 0
	company_game.state.companies[0]["owner"] = 1
	company_game.state["elapsed"] = 1
	var company_debtor: Dictionary = company_game.state.players[0]
	company_debtor["position"] = 5
	var company_cash_before: int = int(company_debtor.cash)
	company_game._resolve_company_visit(0, company_game.state.board[5])
	expect(int(company_debtor.cash) < company_cash_before, "company toll remains payable when owner is detained")


func _test_dog_and_legacy_hospital() -> void:
	var game := make_status_game(109)
	expect(game != null, "status dog fixture starts")
	if game == null:
		return
	game.state.god_objects = [{"id": 11, "node": 2, "owner": -1, "days": 0}]
	var player: Dictionary = game.state.players[0]
	player["position"] = 2
	player["previous_position"] = 1
	player["vehicle"] = "motorcycle"
	player["vehicles"]["motorcycle"] = true
	var immune: bool = game._encounter_dog(0, 2)
	expect(not immune and int(player.hospital_days) == 0 and int(player.prison_days) == 0, "vehicle protects the player from dog admission")
	expect(str(last_event_of_type(game, "dog_encounter").get("vehicle", "")) == "motorcycle", "vehicle dog encounter records immunity")

	game.state.god_objects = [{"id": 11, "node": 2, "owner": -1, "days": 0}]
	player["vehicle"] = "walking"
	player["position"] = 2
	player["previous_position"] = 1
	set_direct_turn(game, 0, "await_action")
	var collided: bool = game._encounter_dog(0, 2)
	expect(collided and int(player.hospital_days) == 3 and int(player.position) == game._status_node_index("hospital"), "walking dog admission lasts three turns and teleports")

	# v6 retains the existing hospital-only dog behavior and has no prison field.
	var legacy := Game.new_game_on_board(109, 2, StatusFixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	expect(legacy != null and int(legacy.state.version) == Game.GODS_SAVE_VERSION, "status-capable source still starts unchanged v6 without status option")
	if legacy != null:
		legacy.state.god_objects = [{"id": 11, "node": 2, "owner": -1, "days": 0}]
		var legacy_player: Dictionary = legacy.state.players[0]
		legacy_player["position"] = 2
		legacy_player["previous_position"] = 1
		legacy_player["vehicle"] = "walking"
		legacy._encounter_dog(0, 2)
		expect(int(legacy_player.hospital_days) == 3 and not legacy_player.has("prison_days"), "v6 hospital field and dog behavior remain unchanged")
		legacy.state["phase"] = "await_roll"
		var legacy_roll: Dictionary = legacy.roll()
		expect(bool(legacy_roll.get("skipped", false)) and int(legacy_player.hospital_days) == 2, "v6 hospital still skips and decrements one own turn")


func _test_insurance_for_every_admission() -> void:
	var game := make_status_game(123)
	expect(game != null, "insurance fixture starts")
	if game == null:
		return
	var player: Dictionary = game.state.players[0]
	var insurer: Dictionary = game.state.companies[0]
	insurer["company_type"] = 4
	insurer["owner"] = 0
	player["insurance_status"] = 1
	player["cash"] = 100000
	var initial_cash: int = int(player.cash)
	var initial_profit: int = int(insurer.monthly_profit)
	for admission in [3, 2]:
		var result: Dictionary = game._admit_player_status(0, "hospital", admission)
		expect(bool(result.get("ok", false)), "insurance admission succeeds for %d days" % admission)
	player["hospital_days"] = 127
	var wrapped: Dictionary = game._admit_player_status(0, "hospital", 1)
	expect(bool(wrapped.get("ok", false)) and int(player.hospital_days) == 0, "insurance covers a seven-bit wrap admission")
	var full_wrap: Dictionary = game._admit_player_status(0, "hospital", 128)
	expect(bool(full_wrap.get("ok", false)) and int(player.hospital_days) == 0, "insurance covers a 128-day admission")
	expect(int(player.cash) == initial_cash + 2000 * (3 + 2 + 1 + 128), "every admission input receives insurance payout")
	expect(int(insurer.monthly_profit) == initial_profit - 2000 * (3 + 2 + 1 + 128), "insurance company is charged for every admission input")
	expect(last_event_of_type(game, "company_insurance_paid").get("days", 0) == 128, "128-day insurance payment is observable")


func _test_status_public_action_gates() -> void:
	for kind in ["hospital", "prison"]:
		var game := make_status_game(110)
		game.state.god_objects=[]
		expect(game.choose_action("buy_stock", {"symbol":"s02", "quantity":1}).get("ok",false), kind+" market baseline buys an available share")
		expect(game.choose_action("set_vehicle", {"vehicle":"walking"}).get("ok",false), kind+" vehicle baseline is available")
		expect(game._admit_player_status(0,kind,3).get("ok",false),kind+" action gate fixture admits current player")
		for phase_name in ["await_roll", "await_action"]:
			if phase_name=="await_action": game.roll()
			for action in ["buy_stock", "sell_stock", "set_vehicle"]:
				var before: String=game.to_json()
				var result: Dictionary=game.choose_action(action,{"symbol":"s02","quantity":1,"vehicle":"walking"})
				expect(not result.get("ok",false) and game.to_json()==before,kind+" "+phase_name+" rejects "+action+" without mutation")
			var direct_before: String=game.to_json()
			expect(not game.set_vehicle("walking").get("ok",false) and game.to_json()==direct_before,kind+" direct vehicle selection rejected")
			expect(Game.validate_save(game.to_dict()).get("ok",false),kind+" "+phase_name+" still has valid save")
	var legacy := Game.new_game_on_board(110,4,CompanyFixture.definition(),{"original_facilities":true,"original_gods":true,"original_companies":true,"start_date":{"year":1998,"month":1,"day":1}})
	legacy.state.players[0].hospital_days=3
	expect(legacy.choose_action("buy_stock",{"symbol":"s02","quantity":1}).get("ok",false),"v7 retains prior hospital stock permission")
