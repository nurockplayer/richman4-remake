extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/hazard_fixture.gd")

var checks := 0
var failures := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func make_game(seed_value: int = 3301) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"original_statuses": true,
		"original_hazards": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	expect(game != null, "hazard fixture starts")
	if game == null:
		return null
	for player_id in range(4):
		game.set_player_ai(player_id, false)
	# The fixture starts without live gods so every hazard case can place its
	# own deterministic actor without depending on spawn roulette.
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


func supply_count(game: Object, tool_id: String) -> int:
	return int(game.state.inventory_supply.tools.get(tool_id, -1))


func held_count(game: Object, player_id: int, tool_id: String) -> int:
	return int(game.state.players[player_id].tools.get(tool_id, 0))


func has_event(game: Object, event_type: String) -> bool:
	for event_value in game.state.event_log:
		if typeof(event_value) == TYPE_DICTIONARY and str(event_value.get("type", "")) == event_type:
			return true
	return false


func valid_save(game: Object, label: String) -> void:
	var validation: Dictionary = Game.validate_save(game.to_dict())
	expect(bool(validation.get("ok", false)), label + ": " + str(validation.get("errors", [])))


func remote_roll(game: Object, player_id: int, value: int) -> Dictionary:
	set_turn(game, player_id, "await_roll")
	game.state.pending_remote_dice = {"player_id": player_id, "value": value}
	game._set_action_options(player_id)
	return game.roll()


func _test_mode_and_target_contract() -> void:
	var game: Object = make_game(3301)
	if game == null:
		return
	expect(int(game.state.version) == Game.HAZARD_SAVE_VERSION, "hazard fixture uses v9")
	expect(bool(game.state.original_hazards), "v9 marker is retained")
	expect(game.state.ground_hazards == {}, "v9 starts with no ground hazards")
	for player in game.state.players:
		expect(int(player.get("bomb_steps", -1)) == 0, "v9 players start without carried bombs")
	for tool_id in ["地雷", "定時炸彈", "機器娃娃"]:
		expect(game.item_is_implemented("tool", tool_id), tool_id + " is executable only in v9")
	var legal_targets: Array = game.inventory_target_tiles("地雷")
	expect(legal_targets.has(2), "mine target exposes the first free road property")
	expect(not legal_targets.has(1), "mine target excludes occupied start node")
	var before: String = game.to_json()
	var rng_before: String = str(game.to_dict().get("rng_state_text", ""))
	var invalid: Dictionary = game.choose_action("use_tool", {"tool_id": "地雷", "tile_id": 1})
	expect(not invalid.get("ok", false) and game.to_json() == before, "occupied mine target is atomic")
	expect(str(game.to_dict().get("rng_state_text", "")) == rng_before, "invalid target does not consume RNG")
	var cancelled: Dictionary = game.choose_action("use_tool", {"tool_id": "地雷", "cancel": true})
	expect(not cancelled.get("ok", false) and game.to_json() == before, "cancelled mine target is unchanged")

	var mine_supply_before: int = supply_count(game, "地雷")
	var mine_held_before: int = held_count(game, 0, "地雷")
	var placed_mine: Dictionary = game.choose_action("use_tool", {"tool_id": "地雷", "tile_id": 2})
	expect(placed_mine.get("ok", false), "legal mine placement succeeds")
	expect(game.state.ground_hazards.get("2", {}).get("kind", "") == "mine", "mine moves to ground hazards")
	expect(supply_count(game, "地雷") == mine_supply_before, "mine placement leaves pool unchanged")
	expect(held_count(game, 0, "地雷") == mine_held_before - 1, "mine placement removes one held mine")
	expect(has_event(game, "tool_used"), "mine placement records tool event")

	set_turn(game, 0, "await_roll")
	var bomb_supply_before: int = supply_count(game, "定時炸彈")
	var bomb_held_before: int = held_count(game, 0, "定時炸彈")
	var placed_bomb: Dictionary = game.choose_action("use_tool", {"tool_id": "定時炸彈", "tile_id": 3})
	expect(placed_bomb.get("ok", false), "legal timed bomb placement succeeds")
	expect(game.state.ground_hazards.get("3", {}).get("kind", "") == "timed_bomb", "timed bomb moves to ground hazards")
	expect(supply_count(game, "定時炸彈") == bomb_supply_before, "timed bomb placement leaves pool unchanged")
	expect(held_count(game, 0, "定時炸彈") == bomb_held_before - 1, "timed bomb placement removes one held bomb")
	valid_save(game, "placed v9 hazards validate")


func _test_mine_vehicle_and_hospital() -> void:
	var game: Object = make_game(3302)
	if game == null:
		return
	set_turn(game, 1, "await_roll")
	expect(Inventory.grant_tool(game.state.inventory_supply, game.state.players[1].tools, "汽車", 1).get("ok", false), "fixture grants a car")
	var car_result: Dictionary = game.set_vehicle("car")
	expect(car_result.get("ok", false), "victim equips a car through production entry")
	set_turn(game, 0, "await_roll")
	var mine_supply_before: int = supply_count(game, "地雷")
	var car_supply_before: int = supply_count(game, "汽車")
	expect(game.choose_action("use_tool", {"tool_id": "地雷", "tile_id": 2}).get("ok", false), "mine is placed for vehicle case")
	var cash_before: int = int(game.state.players[1].cash)
	var roll_result: Dictionary = remote_roll(game, 1, 1)
	expect(roll_result.get("ok", false) and game.state.phase == "await_route", "vehicle victim reaches route choice")
	expect(game.state.route_options.has(2), "vehicle victim can choose mined branch")
	var route_result: Dictionary = game.choose_route(2)
	expect(route_result.get("ok", false), "vehicle victim can enter mined node")
	var victim: Dictionary = game.state.players[1]
	expect(int(victim.hospital_days) == 3, "mine sends victim to hospital for three days")
	expect(int(victim.position) == game._status_node_index("hospital"), "mine uses canonical hospital node")
	expect(str(victim.vehicle) == "walking" and int(victim.dice_count) == 1, "mine removes the active vehicle")
	expect(supply_count(game, "地雷") == mine_supply_before + 1, "mine hit returns mine to pool")
	expect(supply_count(game, "汽車") == car_supply_before + 1, "mine hit returns active car to pool")
	expect(int(victim.cash) == cash_before, "mine hit consumes landing without charging its tile")
	expect(has_event(game, "mine_triggered"), "mine hit records mine event")
	valid_save(game, "mine hospital snapshot validates")


func _test_ground_bomb_pickup_and_countdown() -> void:
	var game: Object = make_game(3303)
	if game == null:
		return
	var bomb_supply_before: int = supply_count(game, "定時炸彈")
	set_turn(game, 0, "await_roll")
	expect(game.choose_action("use_tool", {"tool_id": "定時炸彈", "tile_id": 2}).get("ok", false), "ground bomb is placed")
	expect(supply_count(game, "定時炸彈") == bomb_supply_before, "ground bomb placement does not return supply")
	# A one-step final landing picks the bomb up. The player starts at node 1;
	# the branch choice keeps the test independent of dice roulette.
	var pickup_roll: Dictionary = remote_roll(game, 1, 1)
	expect(pickup_roll.get("ok", false) and game.state.route_options.has(2), "bomb picker reaches route choice")
	var pickup_result: Dictionary = game.choose_route(2)
	var carrier: Dictionary = game.state.players[1]
	expect(pickup_result.get("ok", false), "ground bomb can be picked up on final landing")
	expect(game.state.ground_hazards.get("2", {}).is_empty(), "picked bomb leaves the ground")
	expect(int(carrier.bomb_steps) == Game.MAX_BOMB_STEPS, "pickup starts the 38-step countdown")
	expect(supply_count(game, "定時炸彈") == bomb_supply_before, "pickup keeps bomb slot occupied")
	expect(has_event(game, "bomb_picked_up"), "pickup records bomb event")
	valid_save(game, "carried bomb snapshot validates")


func _test_bomb_transfer_and_explosion() -> void:
	var transfer_game: Object = make_game(3304)
	if transfer_game == null:
		return
	# Put the carrier one edge from node 4 and a living recipient on its final
	# node. The bomb is already carried, represented by one removed held unit.
	set_position(transfer_game, 0, 2, 1)
	set_position(transfer_game, 1, 4, 2)
	transfer_game.state.players[0].tools.erase("定時炸彈")
	transfer_game.state.players[0].bomb_steps = 2
	var transfer_roll: Dictionary = remote_roll(transfer_game, 0, 1)
	expect(transfer_roll.get("ok", false), "carried bomb carrier rolls")
	expect(int(transfer_game.state.players[0].bomb_steps) == 0, "transfer clears the old carrier")
	expect(int(transfer_game.state.players[1].bomb_steps) == 1, "transfer gives remaining step to recipient")
	expect(has_event(transfer_game, "bomb_countdown"), "transfer decrements on the actual move")
	expect(has_event(transfer_game, "bomb_transferred"), "bomb transfer is event logged")
	valid_save(transfer_game, "transferred bomb snapshot validates")

	var explosion_game: Object = make_game(3305)
	if explosion_game == null:
		return
	set_position(explosion_game, 1, 4, 2)
	set_position(explosion_game, 0, 2, 1)
	explosion_game.state.players[1].tools.erase("定時炸彈")
	explosion_game.state.players[1].bomb_steps = 1
	var property: Dictionary = explosion_game.state.board[3]
	property.owner = 0
	property.building_level = 2
	property.rent_by_level = [100, 250, 600, 1200, 2400, 4800]
	property.rent = 600
	property.base_rent = 100
	explosion_game.state.players[0].properties = [3]
	explosion_game._recalculate_property_values()
	var level_before: int = int(property.building_level)
	var rent_before: int = int(property.rent)
	var bomb_supply_before: int = supply_count(explosion_game, "定時炸彈")
	var explosion_roll: Dictionary = remote_roll(explosion_game, 1, 1)
	expect(explosion_roll.get("ok", false) and explosion_game.state.route_options.has(3), "bomb carrier reaches property branch")
	var explosion_result: Dictionary = explosion_game.choose_route(3)
	var victim: Dictionary = explosion_game.state.players[1]
	expect(explosion_result.get("ok", false), "bomb carrier can choose explosion branch")
	expect(int(victim.bomb_steps) == 0, "explosion clears carried countdown")
	expect(int(victim.hospital_days) == 5, "explosion sends carrier to hospital five days")
	expect(supply_count(explosion_game, "定時炸彈") == bomb_supply_before + 1, "explosion returns bomb to pool")
	expect(int(property.building_level) == level_before - 1 and int(property.rent) != rent_before, "explosion lowers property and synchronizes rent")
	expect(int(property.owner) == 0, "explosion preserves property owner")
	expect(has_event(explosion_game, "bomb_exploded"), "explosion records bomb event")
	valid_save(explosion_game, "exploded bomb snapshot validates")


func god_at(game: Object, god_id: int, node_id: int, owner_id: int = -1, days: int = 0) -> void:
	game.state.god_objects = [{"id": god_id, "node": node_id, "owner": owner_id, "days": days}]
	for player in game.state.players:
		player.god_id = 0
	if owner_id >= 0:
		game.state.players[owner_id].god_id = god_id


func _test_final_only_gods_and_dog() -> void:
	var passing_god: Object = make_game(3306)
	if passing_god == null:
		return
	set_position(passing_god, 0, 2, 1)
	god_at(passing_god, 1, 4)
	var pass_roll: Dictionary = remote_roll(passing_god, 0, 2)
	expect(pass_roll.get("ok", false) and passing_god.state.phase == "await_route", "god passing case pauses only at branch")
	expect(not passing_god.state.god_objects.is_empty() and int(passing_god.state.god_objects[0].owner) == -1, "passing an unbound god does not attach in v9")
	expect(passing_god.state.god_objects[0].node == 4, "passing leaves god on its node")
	expect(passing_god.choose_route(3).get("ok", false), "passing god route completes")

	var final_god: Object = make_game(3307)
	if final_god == null:
		return
	set_position(final_god, 0, 2, 1)
	god_at(final_god, 1, 4)
	var final_roll: Dictionary = remote_roll(final_god, 0, 1)
	expect(final_roll.get("ok", false), "final god case rolls")
	expect(int(final_god.state.players[0].god_id) == 1, "final landing attaches ordinary god")
	expect(has_event(final_god, "god_attached"), "final god encounter records attachment")

	var passing_dog: Object = make_game(3308)
	if passing_dog == null:
		return
	set_position(passing_dog, 0, 2, 1)
	god_at(passing_dog, 11, 4)
	var dog_pass_roll: Dictionary = remote_roll(passing_dog, 0, 2)
	expect(dog_pass_roll.get("ok", false) and passing_dog.state.phase == "await_route", "dog passing case reaches branch")
	expect(int(passing_dog.state.god_objects[0].id) == 11, "passing dog remains untriggered in v9")
	expect(int(passing_dog.state.players[0].hospital_days) == 0, "passing dog does not hospitalize player")
	expect(passing_dog.choose_route(3).get("ok", false), "dog passing route completes")

	var final_dog: Object = make_game(3309)
	if final_dog == null:
		return
	set_position(final_dog, 0, 2, 1)
	god_at(final_dog, 11, 4)
	var dog_final_roll: Dictionary = remote_roll(final_dog, 0, 1)
	expect(dog_final_roll.get("ok", false), "final dog case rolls")
	expect(int(final_dog.state.players[0].hospital_days) == 3, "final dog hospitalizes walking player")
	expect(has_event(final_dog, "dog_encounter"), "final dog encounter records event")
	expect(not has_event(final_dog, "status_facility_landed"), "dog consumes final landing before tile settlement")


func take_held_tool(game: Object, player_id: int, tool_id: String) -> bool:
	var tools: Dictionary = game.state.players[player_id].tools
	var quantity: int = int(tools.get(tool_id, 0))
	if quantity <= 0:
		return false
	if quantity == 1:
		tools.erase(tool_id)
	else:
		tools[tool_id] = quantity - 1
	return true


func unique_non_current_nodes(path: Array, current_node: int) -> Array:
	var result: Array = []
	for node_value in path:
		var node_id: int = int(node_value)
		if node_id != current_node and not result.has(node_id):
			result.append(node_id)
	return result


func _test_machine_doll_cleanup_and_rng() -> void:
	var probe: Object = make_game(3310)
	if probe == null:
		return
	set_position(probe, 0, 1, -1)
	set_turn(probe, 0, "await_roll")
	var probe_result: Dictionary = probe.choose_action("use_tool", {"tool_id": "機器娃娃"})
	expect(probe_result.get("ok", false), "machine doll probe uses production entry")
	var path: Array = probe_result.get("path", [])
	expect(path.size() == 9, "machine doll walks exactly nine graph steps")
	var nodes: Array = unique_non_current_nodes(path, 1)
	expect(nodes.size() >= 4, "machine path offers four distinct cleanup anchors")
	if nodes.size() < 4:
		return

	var game: Object = make_game(3310)
	if game == null:
		return
	set_position(game, 0, 1, -1)
	# Reserve one finite slot in each object category by moving a held unit to
	# the ground/carrier fixture. The shared pool remains unchanged.
	expect(take_held_tool(game, 1, "地雷"), "fixture has mine for machine cleanup")
	expect(take_held_tool(game, 1, "定時炸彈"), "fixture has bomb for machine cleanup")
	expect(take_held_tool(game, 1, "路障"), "fixture has roadblock for machine cleanup")
	game.state.ground_hazards = {
		str(nodes[0]): {"kind": "mine", "placer_id": 1},
		str(nodes[1]): {"kind": "timed_bomb", "placer_id": 1},
	}
	game.state.roadblocks = {str(nodes[2]): 1}
	game.state.god_objects = [
		{"id": 3, "node": 1, "owner": 0, "days": 7},
		{"id": 1, "node": nodes[3], "owner": -1, "days": 0},
	]
	game.state.players[0].god_id = 3
	# An attached god at the carrier's node and a carried bomb are both outside
	# the machine doll cleanup set and must survive its nine-step path.
	game.state.players[0].bomb_steps = 7
	expect(take_held_tool(game, 0, "定時炸彈"), "fixture removes carried bomb slot from held tools")
	set_turn(game, 0, "await_roll")
	var machine_result: Dictionary = game.choose_action("use_tool", {"tool_id": "機器娃娃"})
	expect(machine_result.get("ok", false), "machine doll cleanup succeeds")
	expect(machine_result.get("path", []) == path, "machine doll uses deterministic saved RNG path")
	expect(int(game.state.last_event.get("steps", 0)) == 9, "machine event reports nine steps")
	expect(game.state.ground_hazards.is_empty(), "machine clears ground mine and bomb objects on path")
	expect(game.state.roadblocks.is_empty(), "machine clears roadblocks on path")
	expect(int(game.state.players[0].bomb_steps) == 7, "machine preserves carried bomb")
	expect(int(game.state.players[0].god_id) == 3 and game.state.god_objects.size() == 1 and int(game.state.god_objects[0].id) == 3, "machine preserves attached god")
	expect(has_event(game, "machine_doll_cleared"), "machine cleanup records event")
	valid_save(game, "machine cleanup snapshot validates")


func _initialize() -> void:
	_test_mode_and_target_contract()
	_test_mine_vehicle_and_hospital()
	_test_ground_bomb_pickup_and_countdown()
	_test_bomb_transfer_and_explosion()
	_test_final_only_gods_and_dog()
	_test_machine_doll_cleanup_and_rng()
	print("Hazard flow checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
