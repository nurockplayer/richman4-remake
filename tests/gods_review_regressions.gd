extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func new_game(gods: bool = true, player_count: int = 4, shop: bool = false) -> Object:
	var raw := Fixture.make()
	if shop: raw.nodes[5].event_code=15
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
func purchase_card_game(gods: bool, facility: bool, owner: int, level: int, price_index: int, god_id: int = 0) -> Object:
	var game = new_game(gods)
	var target := 2 if facility else 4
	at_node(game,target,1 if facility else 2)
	game.state.price_index=price_index
	if facility:
		game._update_facility_records(1,{"owner":owner,"facility_type":1 if level>0 else 0,"building_level":level})
	else:
		game.state.board[target].owner=owner
		game.state.board[target].building_level=level
		game._update_tile_rent(game.state.board[target])
	if owner>=0: game.state.players[owner].properties=[target]
	if god_id>0: attached(game,0,god_id)
	var grant: Dictionary = Inventory.grant_card(game.state.inventory_supply,game.state.players[0].cards,"購地")
	expect(grant.get("ok",false),"stage finite-supply purchase card")
	game._recalculate_property_values()
	game._set_action_options(0)
	return game

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
	for days in [3,1]:
		for shop in [false,true]:
			var service_rest = new_game(true,4,shop)
			at_node(service_rest,5,4)
			service_rest.state.players[0].hospital_days=days
			service_rest.state.players[0].points=300
			service_rest._set_action_options(0)
			valid(service_rest,"hospital service prestate")
			expect(service_rest.roll().get("skipped",false),"hospital service turn skips movement")
			for action in ["take_loan","buy_item","sell_item"]:
				expect(not service_rest.state.action_options.has(action),"hospital rest disables location service even on final day: "+action)
			expect(not service_rest.is_shop_available(),"hospital rest hides shop availability even on final day")
			expect(service_rest.state.action_options.has("buy_stock") and service_rest.state.action_options.has("sell_stock"),"hospital rest preserves existing stock access while source permission remains unknown")
			var before: Dictionary = service_rest.to_dict()
			expect(not service_rest.choose_action("buy_item",{"item_kind":"tool","item_id":"路障","quantity":1}).get("ok",false),"resting shop trade rejects publicly")
			expect(service_rest.to_dict()==before,"resting shop rejection preserves supply and finances")
			valid(service_rest,"hospital service completion")
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
	for target_case in [{"node":1,"start":0,"previous":-1,"owned":false}, {"node":5,"start":4,"previous":3,"owned":false}, {"node":4,"start":2,"previous":1,"owned":false}, {"node":4,"start":2,"previous":1,"owned":true}, {"node":2,"start":1,"previous":0,"owned":false}, {"node":2,"start":1,"previous":0,"owned":true}]:
		var dog_game = new_game()
		var target: int = target_case.node
		at_node(dog_game,target_case.start,target_case.previous)
		dog_game.state.players[0].turtle_days=1
		for i in range(1,4):
			dog_game.state.players[i].position=0
			dog_game.state.players[i].previous_position=1
		if target_case.owned:
			if target==2:
				dog_game._update_facility_records(1,{"owner":1,"facility_type":1,"building_level":2})
				dog_game.state.players[1].properties=[2]
			else:
				dog_game.state.board[target].owner=1
				dog_game.state.board[target].building_level=1
				dog_game.state.players[1].properties=[target]
				dog_game._update_tile_rent(dog_game.state.board[target])
		attached(dog_game,0,9)
		dog_game.state.god_objects.append({"id":11,"node":target,"owner":-1,"days":0})
		dog_game._recalculate_property_values()
		dog_game._set_action_options(0)
		valid(dog_game,"dog public movement prestate")
		var cash_before: int = dog_game.state.players[0].cash
		var points_before: int = dog_game.state.players[0].points
		var level_before: int = dog_game.state.board[target].building_level
		var event_start: int = dog_game.state.event_log.size()
		expect(dog_game.roll().get("ok",false),"dog roll accepted")
		if dog_game.state.phase=="await_route":
			expect(dog_game.choose_route(target).get("ok",false),"dog chosen route accepted")
		expect(dog_game.state.players[0].hospital_days==3 and dog_game.state.phase=="await_action","dog bite establishes hospitalized action boundary")
		expect(dog_game.state.players[0].cash==cash_before,"dog collision does not collect final housing or facility fees")
		expect(dog_game.state.players[0].points==points_before,"dog collision does not award final points")
		for action in ["buy","build","upgrade","take_loan","buy_item","sell_item"]:
			expect(not dog_game.state.action_options.has(action),"hospitalized dog collision exposes no location action "+action)
		expect(not dog_game.choose_action("buy").get("ok",false),"dog collision purchase rejects at public action boundary")
		expect(dog_game.state.players[0].cash==cash_before,"dog collision purchase rejection leaves cash unchanged")
		if target==5:
			var pass_index := -1
			var dog_index := -1
			var landed_count := 0
			for index in range(event_start,dog_game.state.event_log.size()):
				var event: Dictionary = dog_game.state.event_log[index]
				if event.type=="bank_passed": pass_index=index
				if event.type=="dog_encounter": dog_index=index
				if event.type=="bank_landed": landed_count+=1
			expect(pass_index>=event_start and pass_index<dog_index,"source bank pass happens before dog collision")
			expect(dog_game.state.bank_access and not dog_game.state.bank_landing and landed_count==0,"dog retains completed bank pass without final bank landing")
			expect(dog_game.state.action_options.has("deposit") and dog_game.state.action_options.has("withdraw"),"dog collision preserves the completed bank-pass service")
		valid(dog_game,"dog collision completion")
		expect(dog_game.choose_action("end_turn").get("ok",false),"dog turn ends normally")
		expect(dog_game.state.board[target].building_level==level_before,"dog-stopped turn does not settle attached angel on collision land")
		valid(dog_game,"dog turn ended")
	for facility in [false,true]:
		for price_index in [1,2]:
			for god_id in [0,7,8,15]:
				var purchase = purchase_card_game(true,facility,1,2,price_index,god_id)
				valid(purchase,"source purchase card prestate")
				var before: Dictionary = purchase.to_dict()
				var price: int = 1600*price_index
				var result: Dictionary = purchase.choose_action("use_card",{"card_id":"購地"})
				expect(result.get("ok",false),"purchase card bypasses ordinary god investment restriction")
				expect(purchase.state.players[0].cash==before.players[0].cash-price,"purchase card charges land and existing building value at price index")
				expect(purchase.state.players[1].deposit==before.players[1].deposit+price,"purchase card pays full value into former owner's deposit")
				var target := 2 if facility else 4
				expect(purchase.state.board[target].owner==0 and purchase.state.board[target].building_level==2,"purchase card preserves acquired improvements")
				if facility: expect(purchase.state.board[3].owner==0,"purchase card synchronizes the second facility entrance")
				valid(purchase,"source purchase card completed")
			var short_cash = purchase_card_game(true,facility,1,2,price_index)
			short_cash.state.players[0].cash=1600*price_index-1
			short_cash._set_action_options(0)
			valid(short_cash,"purchase card insufficient funds prestate")
			var before: Dictionary = short_cash.to_dict()
			expect(not short_cash.choose_action("use_card",{"card_id":"購地"}).get("ok",false),"purchase card rejects one unit below complete price")
			expect(short_cash.to_dict()==before,"rejected complete-price purchase preserves state and finite card supply")
		for level in [0,2]:
			var unowned = purchase_card_game(true,facility,-1,level,1)
			valid(unowned,"v6 unowned purchase-card prestate")
			var before: Dictionary = unowned.to_dict()
			expect(not unowned.choose_action("use_card",{"card_id":"購地"}).get("ok",false),"v6 source purchase card excludes unowned land")
			expect(unowned.to_dict()==before,"unowned purchase-card rejection is atomic")
		var old_purchase = purchase_card_game(false,facility,1,2,2)
		valid(old_purchase,"legacy purchase price prestate")
		var old_cash: int = old_purchase.state.players[0].cash
		expect(old_purchase.choose_action("use_card",{"card_id":"購地"}).get("ok",false),"legacy purchase card still works")
		expect(old_purchase.state.players[0].cash==old_cash-(2000 if facility else 1000),"legacy purchase card retains historical price")
		var old_unowned = purchase_card_game(false,facility,-1,0,1)
		valid(old_unowned,"legacy unowned purchase prestate")
		expect(old_unowned.choose_action("use_card",{"card_id":"購地"}).get("ok",false),"legacy purchase card retains unowned target compatibility")
	for level in [0,2]:
		for cash in [1000+level*300, (1000+level*300)*2]:
			var direct = purchase_card_game(true,false,-1,level,2)
			direct.state.phase="await_action"
			direct.state.players[0].cash=cash
			direct._set_action_options(0)
			valid(direct,"indexed direct purchase prestate")
			var before: Dictionary = direct.to_dict()
			var result: Dictionary = direct.choose_action("buy")
			var expected_price: int = (1000+level*300)*2
			expect(result.get("ok",false)==(cash>=expected_price),"direct purchase affordability includes index")
			if cash>=expected_price:
				expect(direct.state.players[0].cash==cash-expected_price,"direct purchase charges indexed land and improvements")
			else:
				expect(direct.to_dict()==before,"insufficient indexed purchase is atomic")
			valid(direct,"indexed direct purchase result")
	for god_id in [7,8,15,12]:
		for owner in [-1,0]:
			if god_id==12 and owner==0: continue
			var ai = purchase_card_game(true,false,owner,0,1,god_id)
			ai.set_player_ai(0,true)
			ai.state.phase="await_action"
			ai._set_action_options(0)
			valid(ai,"blocked investment AI prestate")
			var shares_before: Dictionary = ai.state.players[0].stocks.duplicate(true)
			var result: Dictionary = ai.run_ai_turn()
			expect(result.get("ok",false) and result.get("completed",false),"blocked investment AI completes")
			expect(ai.state.players[0].stocks!=shares_before,"blocked investment AI continues to legal stock purchase")
			valid(ai,"blocked investment AI result")
	print("God review regression checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
