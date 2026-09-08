extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func new_game(gods: bool = true, player_count: int = 4) -> Object:
	var raw := Fixture.make()
	raw.nodes[2].type_and_idx = 4001
	raw.nodes[3].type_and_idx = 4001
	raw.nodes[4].type_and_idx = 2001
	raw.nodes[4].event_code = 0
	raw.lands.resize(1)
	raw.facilities = [{"id": 1, "display_name": "測試設施", "name_bytes_hex": "74657374000000000000000000000000", "facility_type": 0, "owner": 0, "level": 0, "tmp_state": 0, "land_price": 1000, "price_per_level": 300, "house_price": 300, "reserved_hex": "6400c8002c019001f401"}]
	var loaded: Dictionary = Maps.normalize_map(raw, true)
	var game = Game.new_game_on_board(42, player_count, loaded.definition, {"original_facilities": true, "original_gods": gods, "start_date": {"year": 1998, "month": 1, "day": 1}})
	if gods:
		game.state.god_objects = []
	return game

func attached(game: Object, player_id: int, god_id: int) -> void:
	game.state.players[player_id].god_id = god_id
	game.state.god_objects.append({"id":god_id,"node":game.state.players[player_id].position,"owner":player_id,"days":13 if god_id==15 else 7})
func insolvent(game: Object) -> void:
	game.state.players[0].cash = 0
	game.state.players[0].deposit = 0
	game.state.bank.deposits = 0
	for player in game.state.players:
		game.state.bank.deposits += player.deposit
func at_node(game: Object, node: int, previous: int) -> void:
	game.state.players[0].position = node
	game.state.players[0].previous_position = previous
func valid(game: Object, label: String) -> void:
	var validation: Dictionary = Game.validate_save(game.to_dict())
	if not validation.get("ok",false):
		print(label," validation: ",validation)
	expect(validation.get("ok",false), label+" save-valid")
	expect(Game.from_dict(JSON.parse_string(game.to_json())) != null, label+" JSON-restorable")
func _initialize() -> void:
	var bankrupt = new_game()
	attached(bankrupt,0,9)
	insolvent(bankrupt)
	valid(bankrupt,"attached pre-bankruptcy")
	bankrupt._charge_amount(0,1,-1,"tax")
	expect(not bankrupt.state.players[0].alive,"ordinary payment bankrupts the god holder")
	expect(bankrupt.state.players[0].god_id==0,"bankruptcy clears player attachment")
	for actor in bankrupt.state.god_objects:
		expect(actor.owner!=0,"bankruptcy clears god owner")
	valid(bankrupt,"immediate bankruptcy")
	bankrupt._sync_attached_gods()
	valid(bankrupt,"bankruptcy after synchronization")
	for scenario in [{"route": false, "players": 4}, {"route": true, "players": 4}, {"route": false, "players": 2}, {"route": true, "players": 2}]:
		var route_case: bool = scenario.route
		var moving = new_game(true, scenario.players)
		var target: int = 5 if route_case else 1
		at_node(moving,4 if route_case else 0,3 if route_case else -1)
		moving.state.players[0].turtle_days=1
		moving.state.god_objects=[{"id":5,"node":target,"owner":-1,"days":0}]
		insolvent(moving)
		for i in range(1,scenario.players):
			moving.state.players[i].position=0
			moving.state.players[i].previous_position=1
		moving._set_action_options(0)
		valid(moving,"poor encounter prestate")
		var points_before: int = moving.state.players[0].points
		var supply_before: Dictionary = moving.state.inventory_supply.duplicate(true)
		var result: Dictionary = moving.roll()
		if route_case:
			expect(moving.state.phase=="await_route","bank encounter uses chosen-route path")
			result=moving.choose_route(target)
		expect(result.get("ok",false),"poor encounter action resolves")
		expect(not moving.state.players[0].alive,"poor encounter bankrupts mover")
		if scenario.players == 2:
			expect(moving.state.phase=="game_over" and moving.state.winner==1,"old movement preserves final bankruptcy game-over state")
		else:
			expect(moving.state.current_player==1 and moving.state.phase=="await_roll","old movement leaves next alive player ready to roll")
		expect(moving.state.players[0].points==points_before,"bankrupt mover gains no landed points")
		expect(moving.state.inventory_supply==supply_before,"bankrupt mover consumes no landed card supply")
		expect(not moving.state.bank_access and not moving.state.bank_landing,"old bank landing grants no access to next player")
		expect(moving.state.pending_movement.is_empty() and moving.state.route_options.is_empty() and moving.state.remaining_steps==0,"aborted movement clears pending route state")
		valid(moving,"poor encounter completion")
	for days in [3,1]:
		var resting = new_game()
		at_node(resting,2,1)
		resting.state.players[0].hospital_days=days
		valid(resting,"hospital prestate")
		var before: Dictionary = resting.to_dict()
		expect(resting.roll().get("skipped",false),"hospital turn skips movement")
		expect(not resting.state.action_options.has("buy"),"hospital skips property actions even on final rest day")
		expect(not resting.choose_action("buy").get("ok",false),"hospital property action rejects directly")
		expect(resting.state.players[0].cash==before.players[0].cash and resting.to_dict().rng_state==before.rng_state,"hospital rejection leaves money and RNG unchanged")
		valid(resting,"hospital skipped turn")
	var legacy = new_game(false)
	legacy.state.players[0].hospital_days=3
	legacy.state.players[0].turtle_days=1
	at_node(legacy,0,-1)
	legacy._set_action_options(0)
	valid(legacy,"v5 foreign hospital field")
	expect(not legacy.roll().get("skipped",false),"v5 ignores foreign hospital field")
	expect(legacy.state.players[0].position==1 and legacy.state.last_roll==[1],"v5 movement continues unchanged")
	for god_id in [3,4]:
		for level in [1,4]:
			var fortune = new_game()
			at_node(fortune,2,1)
			fortune._update_facility_records(1,{"owner":0,"facility_type":1,"building_level":level})
			fortune.state.players[0].properties=[2]
			attached(fortune,0,god_id)
			fortune._recalculate_property_values()
			fortune.state.phase="await_action"
			fortune._set_action_options(0)
			valid(fortune,"fortune facility upgrade prestate")
			var cash_before: int = fortune.state.players[0].cash
			expect(fortune.choose_action("upgrade").get("ok",false),"fortune facility upgrade accepted")
			expect(fortune.state.players[0].cash==cash_before-300,"fortune facility upgrade charged once")
			for node in [2,3]:
				expect(fortune.state.board[node].building_level==mini(level+2,5),"fortune upgrade applies capped bonus to both entrances")
			valid(fortune,"fortune facility upgraded")
	for status in ["hospital","death"]:
		for facility in [false,true]:
			for shield in [0,1]:
				var fees = new_game()
				if facility:
					fees._update_facility_records(1,{"owner":1,"facility_type":1,"building_level":2})
					fees.state.players[1].properties=[2]
				else:
					fees.state.board[4].owner=1
					fees.state.board[4].building_level=1
					fees._update_tile_rent(fees.state.board[4])
					fees.state.players[1].properties=[4]
				if status=="hospital":
					fees.state.players[1].hospital_days=3
				else:
					attached(fees,1,15)
				fees.state.players[0].rent_shield=shield
				fees._recalculate_property_values()
				valid(fees,"unavailable creditor prestate")
				var before: Dictionary = fees.to_dict()
				if facility:
					fees._resolve_facility_visit(0,fees.state.board[2])
				else:
					fees._graph_visit_tile(0,fees.state.board[4],true)
				expect(fees.state.players[0].cash==before.players[0].cash and fees.state.players[1].cash==before.players[1].cash,"unavailable creditor collects no fee")
				expect(fees.state.players[0].rent_shield==shield,"unavailable creditor does not consume fee shield")
				expect(fees.to_dict().rng_state==before.rng_state,"unavailable creditor does not spin fee roulette")
				valid(fees,"unavailable creditor settled")
	print("God review regression checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
