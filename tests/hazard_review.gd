extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/hazard_fixture.gd")

var checks := 0
var failures := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func make_game(seed_value: int, player_count: int = 4, hazards_mode: bool = true) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, Fixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"original_statuses": true,
		"original_hazards": hazards_mode,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	expect(game != null, "hazard review fixture starts")
	if game == null:
		return null
	for player_id in range(player_count):
		game.set_player_ai(player_id, false)
	game.state.god_objects = []
	game._set_action_options(int(game.state.current_player))
	return game


func set_turn(game: Object, player_id: int, phase: String = "await_roll") -> void:
	game.state.current_player = player_id
	game.state.phase = phase
	game.state.route_options = []
	game.state.remaining_steps = 0
	game.state.pending_movement = {}
	game.state.pending_remote_dice = {}
	game._set_action_options(player_id)


func set_position(game: Object, player_id: int, node_id: int, previous_id: int = -1) -> void:
	game.state.players[player_id].position = node_id
	game.state.players[player_id].previous_position = previous_id


func remote_roll(game: Object, player_id: int, value: int) -> Dictionary:
	set_turn(game, player_id, "await_roll")
	game.state.pending_remote_dice = {"player_id": player_id, "value": value}
	game._set_action_options(player_id)
	return game.roll()


func _test_final_mine_admission_ends_turn() -> void:
	var game: Object = make_game(4401)
	if game == null:
		return
	set_turn(game, 0, "await_roll")
	var placement: Dictionary = game.choose_action("use_tool", {"tool_id": "地雷", "tile_id": 2})
	expect(bool(placement.get("ok", false)), "review mine placement succeeds")
	var roll_result: Dictionary = remote_roll(game, 1, 1)
	expect(bool(roll_result.get("ok", false)) and game.state.phase == "await_route", "review mine victim reaches public route choice")
	var route_result: Dictionary = game.choose_route(2)
	expect(bool(route_result.get("ok", false)), "review mine victim chooses public route")
	var victim: Dictionary = game.state.players[1]
	expect(int(victim.get("hospital_days", 0)) == 3, "review mine admission sends victim to hospital")
	expect(game.state.phase == "await_action", "final mine admission transitions to action phase")
	expect(game.state.action_options == ["end_turn"], "final mine admission exposes only end-turn action")


func _test_final_dog_admission_ends_turn() -> void:
	var game: Object = make_game(4402)
	if game == null:
		return
	set_position(game, 0, 2, 1)
	game.state.god_objects = [{"id": 11, "node": 4, "owner": -1, "days": 0}]
	var roll_result: Dictionary = remote_roll(game, 0, 1)
	expect(bool(roll_result.get("ok", false)), "review dog encounter rolls through public entry")
	var victim: Dictionary = game.state.players[0]
	expect(int(victim.get("hospital_days", 0)) == 3, "review dog admission sends walking player to hospital")
	expect(game.state.phase == "await_action", "final dog admission transitions to action phase")
	expect(game.state.action_options == ["end_turn"], "final dog admission exposes only end-turn action")


func _configure_level_one_facility(game: Object, node_id: int) -> Dictionary:
	var facility: Dictionary = game.state.board[node_id]
	facility.merge({
		"kind": "facility",
		"name": "測試設施",
		"type_and_idx": 4001,
		"source_object_id": 1,
		"facility_node_index": node_id,
		"owner": 0,
		"building_level": 1,
		"facility_type": 1,
		"facility_state": 0,
		"cost": 1000,
		"land_price": 1000,
		"upgrade_cost": 300,
		"base_rent": 0,
		"rent": 0,
		"group": "facility:1",
		"fee_by_level": [300, 100, 200, 300, 400, 500],
	}, true)
	return facility


func _test_level_one_facility_bomb_clears_type() -> void:
	var game: Object = make_game(4403)
	if game == null:
		return
	var facility: Dictionary = _configure_level_one_facility(game, 3)
	game.state.players[1].tools.erase("定時炸彈")
	game.state.players[1].bomb_steps = 1
	var exploded: bool = game._hazard_explode_bomb(1, 3)
	expect(exploded, "review bomb explosion resolves on level-one facility")
	expect(int(facility.get("building_level", -1)) == 0, "facility bomb damage reaches level zero")
	expect(int(facility.get("facility_state", -1)) == 0, "facility bomb damage clears transient state")
	expect(int(facility.get("facility_type", -1)) == 0, "facility bomb damage clears facility type")
	expect(int(facility.get("owner", -1)) == 0, "facility bomb damage preserves owner")


func _test_v9_dynamic_object_overlap_validation() -> void:
	var game: Object = make_game(4404)
	if game == null:
		return
	set_turn(game, 0, "await_roll")
	var placement: Dictionary = game.choose_action("use_tool", {"tool_id": "路障", "tile_id": 2})
	expect(bool(placement.get("ok", false)), "review roadblock placement succeeds")
	for player in game.state.players:
		player.position = 1
		player.previous_position = -1
		player.god_id = 0
	game.state.god_objects = [{"id": 1, "node": 3, "owner": -1, "days": 0}]
	var valid_data: Dictionary = game.to_dict()
	var valid_result: Dictionary = Game.validate_save(valid_data)
	expect(bool(valid_result.get("ok", false)), "separate roadblock and unbound god preserve v9 save validity")
	var invalid_data: Dictionary = valid_data.duplicate(true)
	invalid_data["god_objects"][0]["node"] = 2
	var invalid_result: Dictionary = Game.validate_save(invalid_data)
	expect(not bool(invalid_result.get("ok", false)), "v9 save rejects roadblock and unbound god on one node")
	expect(invalid_result.get("errors", []).has("roadblock target overlaps dynamic road object"), "overlap rejection identifies the roadblock/god conflict")
	expect(not game._god_spawn_candidates().has(2), "god spawn candidates exclude an occupied roadblock node")
	for anchor in [0, 4]:
		var anchor_data: Dictionary = valid_data.duplicate(true)
		anchor_data.roadblocks = {str(anchor): 0}
		expect(Game.validate_save(anchor_data).get("ok", false), "separate objects at a status anchor remain valid")
		anchor_data.god_objects[0].node = anchor
		var anchor_result: Dictionary = Game.validate_save(anchor_data)
		expect(anchor_result.get("errors", []).has("roadblock target overlaps dynamic road object"), "status anchor does not exempt dynamic object overlap")


func _test_bankruptcy_releases_carried_bomb() -> void:
	var game: Object = make_game(4405, 3)
	if game == null:
		return
	var creditor_tile: Dictionary = game.state.board[2]
	creditor_tile["owner"] = 1
	game.state.players[1].properties = [2]
	game._recalculate_property_values()
	var debtor: Dictionary = game.state.players[0]
	debtor["cash"] = 0
	var debtor_deposit: int = int(debtor.get("deposit", 0))
	debtor["deposit"] = 0
	game.state.bank["deposits"] = int(game.state.bank.get("deposits", 0)) - debtor_deposit
	debtor.tools.erase("定時炸彈")
	debtor["bomb_steps"] = 2
	set_position(game, 0, 1, -1)
	var bomb_supply_before: int = int(game.state.inventory_supply.tools["定時炸彈"])
	var roll_result: Dictionary = remote_roll(game, 0, 1)
	expect(bool(roll_result.get("ok", false)) and game.state.phase == "await_route", "three-player charge reaches public route choice")
	var route_result: Dictionary = game.choose_route(2)
	expect(bool(route_result.get("ok", false)), "three-player charge reaches creditor property")
	expect(bool(debtor.get("bankrupt", false)) and not bool(debtor.get("alive", true)), "three-player charge declares the bomb carrier bankrupt")
	expect(int(debtor.get("bomb_steps", -1)) == 0, "bankruptcy clears the carried bomb countdown")
	expect(int(game.state.inventory_supply.tools["定時炸彈"]) == bomb_supply_before + 1, "bankruptcy returns the carried bomb to finite supply")
	expect(game.state.phase == "await_roll" and int(game.state.current_player) == 1 and int(game.state.winner) == -1, "non-final bankruptcy advances to a living player")
	var snapshot: Dictionary = game.to_dict()
	var validation: Dictionary = Game.validate_save(snapshot)
	expect(bool(validation.get("ok", false)), "bankruptcy snapshot with released bomb validates")
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null and restored.state.phase == "await_roll", "bankruptcy snapshot reloads without immediate game over")
	var invalid_dead_bomb: Dictionary = snapshot.duplicate(true)
	invalid_dead_bomb.players[0].bomb_steps = 1
	invalid_dead_bomb.inventory_supply.tools["定時炸彈"] = int(invalid_dead_bomb.inventory_supply.tools["定時炸彈"]) - 1
	var invalid_validation: Dictionary = Game.validate_save(invalid_dead_bomb)
	expect(not bool(invalid_validation.get("ok", false)), "v9 save rejects a dead player carrying a bomb")
	expect(invalid_validation.get("errors", []).has("dead player cannot carry bomb"), "dead bomb save rejection identifies the lifecycle conflict")


func _test_v8_admission_phase_compatibility() -> void:
	var game: Object = make_game(4406, 4, false)
	if game == null:
		return
	expect(int(game.state.version) == 8, "legacy admission fixture remains v8")
	var result: Dictionary = game._admit_player_status(0, "hospital", 3)
	expect(result.get("ok", false), "legacy admission still succeeds")
	expect(game.state.phase == "await_roll", "v8 direct admission retains its existing replay phase")


func _initialize() -> void:
	_test_v8_admission_phase_compatibility()
	_test_final_mine_admission_ends_turn()
	_test_final_dog_admission_ends_turn()
	_test_level_one_facility_bomb_clears_type()
	_test_v9_dynamic_object_overlap_validation()
	_test_bankruptcy_releases_carried_bomb()
	print("Hazard review checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
