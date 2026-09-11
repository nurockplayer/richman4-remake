extends "res://tests/stock_accounting.gd"
const Sale = preload("res://game/core/source_sale_flow.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Catalogue = preload("res://game/content/original_inventory.gd")
const LIMIT := 1000000000000

func _initialize() -> void:
	test_listing_lifetime()
	test_tools_and_cards()
	test_property_transfer()
	test_boundaries()
	test_save_validation()
	test_ai_continuation()
	print("Source SALE rules checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)

func sale_game(facility: bool = false) -> Object:
	var game: Object = Game.new_game_on_board(164,4,Fixture.construction_definition() if facility else Fixture.definition(),{"original_facilities":true,"original_gods":true,"original_companies":true,"human_flags":[true,true,true,true],"start_date":{"year":1998,"month":1,"day":1}})
	expect(game != null,"complete source rules fixture creates game")
	game.state.god_objects = []
	game.state.phase = "await_action"
	game._sync_state()
	game._set_action_options(0)
	return game

func open_for(game: Object, player_id: int) -> int:
	if game.state.phase == "await_sale": expect(game.close_sale(int(game.sale_snapshot().session_id)).ok,"previous actor closes public session")
	game.state.current_player = player_id
	game.state.phase = "await_action"
	game._set_action_options(player_id)
	expect(game.open_sale().ok,"actor opens public SALE")
	return int(game.sale_snapshot().session_id)

func create(game: Object, category: String, source_id: int, quantity: int = 1, asking: int = 1) -> Dictionary:
	return game.sale_create_offer({"session_id":int(game.sale_snapshot().session_id),"category":category,"source_id":source_id,"quantity":quantity,"asking":asking})

func request(game: Object, offer: Dictionary) -> Dictionary:
	return {"session_id":int(game.sale_snapshot().session_id),"offer_id":int(offer.offer_id),"revision":int(offer.revision)}

func valid_roundtrip(game: Object, label: String) -> void:
	valid_save(game,label)
	var saved: String = game.to_json()
	var restored: Object = Game.from_dict(JSON.parse_string(saved))
	expect(restored != null,label + " loads")
	if restored != null: expect(restored.to_json() == saved,label + " exact JSON continuation")

func economic(game: Object) -> Dictionary:
	var result := {}
	for key in ["players","bank","market","board","inventory_supply","rng_state_text"]: result[key] = game.to_dict().get(key)
	return result

func rejection(game: Object, method: String, params: Dictionary, label: String) -> void:
	var before: String = game.to_json()
	expect(not game.call(method,params).get("ok",false),label + " rejects")
	expect(game.to_json() == before,label + " is atomic")

func test_listing_lifetime() -> void:
	var game := sale_game()
	open_for(game,0)
	var before := economic(game)
	for source_id in [1,2,3,4,8,9]: expect(create(game,"tool",source_id).ok,"owned distinct source tool lists")
	expect(Inventory.grant_card(game.state.inventory_supply,game.state.players[0].cards,"改建").ok,"finite card fixture")
	before = economic(game)
	expect(create(game,"card",7).ok,"seventh offer lists")
	expect(game.sale_snapshot().players[0].offers.size() == 7 and not game.sale_snapshot().can_create,"seven slots hide UI create affordance")
	expect(economic(game) == before,"all offers remain without escrow")
	var old: Dictionary = game.sale_snapshot().players[0].offers[0]
	var updated: Dictionary = create(game,"tool",1,1,9)
	expect(updated.ok and updated.offer.offer_id == old.offer_id and int(updated.offer.revision) == int(old.revision)+1,"source helper replaces same item at full capacity")
	expect(game.sale_snapshot().players[0].offers.size() == 7,"same-item update does not create an eighth slot")
	rejection(game,"sale_cancel_offer",request(game,old),"old offer revision")
	var list_request := {"session_id":int(game.sale_snapshot().session_id),"category":"tool","source_id":5,"quantity":1,"asking":1}
	expect(Inventory.grant_tool(game.state.inventory_supply,game.state.players[0].tools,"機車",1).ok,"legal eighth tool holding")
	rejection(game,"sale_create_offer",list_request,"eighth distinct offer")
	valid_roundtrip(game,"full board with updated revision")
	for _day in range(8): Sale.cleanup(game,true)
	expect(game.sale_snapshot().players[0].offers.size() == 7 and int(game.sale_snapshot().players[0].offers[0].days) == 8,"daily source byte counter does not invent seven-day expiry")
	game.state.sale_board.offers[0][0].days = 255
	Sale.cleanup(game,true)
	expect(game.state.sale_board.offers[0][0].days == 0,"source daily byte wraps")
	expect(game.sale_cancel_offer(request(game,updated.offer)).ok,"owner cancels current revision")
	before = economic(game)
	expect(game.sale_snapshot().players[0].offers.size() == 6 and economic(game) == before,"cancel preserves wallets and holdings")
	game.close_sale(int(game.sale_snapshot().session_id))
	expect(Inventory.consume_tool(game.state.inventory_supply,game.state.players[0].tools,"路障",1).ok,"listed tool can legally leave backpack")
	game.open_sale()
	expect(game.sale_snapshot().players[0].offers.size() == 5,"entry removes unavailable tool offer")

func test_tools_and_cards() -> void:
	var game := sale_game()
	open_for(game,0)
	var offer: Dictionary = create(game,"tool",9,1,11).offer
	var supply: Dictionary = game.state.inventory_supply.duplicate(true)
	open_for(game,1)
	var seller_deposit := int(game.state.players[0].deposit)
	var buyer_cash := int(game.state.players[1].cash)
	expect(game.sale_accept_offer(request(game,offer)).ok,"research tool transfer uses shared safe settlement")
	expect(game.state.players[0].tools.get("機器工人",0) == 0 and game.state.players[1].tools["機器工人"] == 2,"one research tool transferred")
	expect(game.state.inventory_supply == supply,"research item has no finite pool mutation")
	expect(game.state.players[0].deposit == seller_deposit+11 and game.state.players[1].cash == buyer_cash-11,"full buyer cash credits seller bank deposit")
	rejection(game,"sale_accept_offer",request(game,offer),"already sold research offer")
	valid_roundtrip(game,"research transfer")
	game = sale_game()
	for player_id in [2,3]: expect(Inventory.consume_tool(game.state.inventory_supply,game.state.players[player_id].tools,"機器娃娃",1).ok,"return tools before capacity fixture")
	expect(Inventory.grant_tool(game.state.inventory_supply,game.state.players[1].tools,"機器娃娃",8).ok,"legal finite buyer capacity nine")
	open_for(game,0)
	offer = create(game,"tool",1,1,100).offer
	open_for(game,1)
	rejection(game,"sale_accept_offer",request(game,offer),"tool buyer at nine")
	expect(Inventory.consume_tool(game.state.inventory_supply,game.state.players[1].tools,"機器娃娃",1).ok,"one tool capacity becomes available")
	supply = game.state.inventory_supply.duplicate(true)
	expect(game.sale_accept_offer(request(game,offer)).ok,"tool with capacity accepts")
	expect(game.state.inventory_supply == supply and int(game.state.players[1].tools["機器娃娃"]) == 9,"finite transfer preserves pool and per-type cap")
	valid_roundtrip(game,"finite tool transfer")
	game = sale_game()
	for card_id in ["改建","轉向","改建"]: expect(Inventory.grant_card(game.state.inventory_supply,game.state.players[0].cards,card_id).ok,"legal duplicate card slots")
	open_for(game,0)
	var model: Dictionary = game.sale_snapshot()
	expect(model.holdings.card[0].source_id == 7 and model.holdings.card[2].source_id == 7 and model.holdings.card[2].held_index == 2,"picker preserves duplicate slot order")
	offer = create(game,"card",7,1,17).offer
	open_for(game,1)
	for item in Catalogue.cards():
		while int(game.state.inventory_supply.cards[item.id]) > 0 and game.state.players[1].cards.size() < 15:
			expect(Inventory.grant_card(game.state.inventory_supply,game.state.players[1].cards,item.id).ok,"fill buyer cards with finite copies")
	rejection(game,"sale_accept_offer",request(game,offer),"card buyer at fifteen without eviction")
	expect(Inventory.consume_card(game.state.inventory_supply,game.state.players[1].cards,game.state.players[1].cards[0]).ok,"one card capacity becomes available")
	supply = game.state.inventory_supply.duplicate(true)
	expect(game.sale_accept_offer(request(game,offer)).ok,"one duplicate card transfers")
	expect(game.state.players[0].cards == ["轉向","改建"] and game.state.players[1].cards.size() == 15,"source-ID offer removes first matching seller copy and appends buyer copy")
	expect(game.state.inventory_supply == supply,"card transfer preserves every finite pool")
	valid_roundtrip(game,"card transfer")

func test_property_transfer() -> void:
	for facility in [false,true]:
		var game := sale_game(facility)
		var node := 1 if facility else 2
		game.state.players[0].position = node
		game._set_action_options(0)
		expect(game.choose_action("buy").ok,"public property purchase supplies SALE holding")
		var source_id := int(game.state.board[node].type_and_idx)
		var reference: int = Sale.reference_value(game,"property",source_id)
		open_for(game,0)
		var offer: Dictionary = create(game,"property",source_id,1,reference).offer
		var board_before: Array = game.state.board.duplicate(true)
		open_for(game,1)
		expect(game.sale_accept_offer(request(game,offer)).ok,"property offer accepts")
		expect(int(game.state.board[node].owner) == 1 and not game.state.players[0].properties.has(node) and game.state.players[1].properties.has(node),"canonical property ownership and references transfer")
		if facility: expect(int(game.state.board[4].owner) == 1,"all aliases of the same facility transfer")
		expect(game.state.board[node].building_level == board_before[node].building_level,"property transfer preserves existing development")
		valid_roundtrip(game,"facility property" if facility else "land property")
		game.close_sale(int(game.sale_snapshot().session_id))
		expect(game.end_turn().ok,"public turn boundary clears completed property action")
		game.state.current_player = 1
		game.state.phase = "await_action"
		game.state.players[1].position = node
		game._set_action_options(1)
		open_for(game,1)
		offer = create(game,"property",source_id).offer
		game.close_sale(int(game.sale_snapshot().session_id))
		expect(game.choose_action("build_facility", {"facility_type":1}).ok if facility else game.choose_action("upgrade").ok,"listed property remains legally developable")
		game.open_sale()
		expect(game.sale_snapshot().players[1].offers.is_empty(),"building-level change invalidates source property snapshot")

func test_boundaries() -> void:
	var game := sale_game()
	prepare_market(game,100.0,100.0)
	expect(game.choose_action("buy_stock",{"symbol":"s01","quantity":3}).ok,"legal stock holding fixture")
	var sid := open_for(game,0)
	var params := {"session_id":sid,"category":"stock","source_id":0,"quantity":3,"asking":1}
	for key in ["session_id","source_id","quantity","asking"]:
		var malformed := params.duplicate()
		malformed[key] = float(malformed[key])
		rejection(game,"sale_create_offer",malformed,"direct numeric input must be integer type: "+key)
	for values in [[0,1],[4,1],[3,0],[3,3001]]:
		var malformed := params.duplicate()
		malformed.quantity = values[0]
		malformed.asking = values[1]
		rejection(game,"sale_create_offer",malformed,"quantity/asking source bounds "+str(values))
	var offer: Dictionary = create(game,"stock",0,3,3000).offer
	rejection(game,"sale_accept_offer",request(game,offer),"seller cannot buy own offer")
	game.close_sale(sid)
	expect(game.choose_action("sell_stock",{"symbol":"s01","quantity":1}).ok,"listed stock remains sellable on market")
	game.open_sale()
	expect(game.sale_snapshot().players[0].offers.is_empty(),"insufficient stock removes offer rather than lowering quantity")
	offer = create(game,"tool",1,1,10).offer
	open_for(game,1)
	rejection(game,"sale_cancel_offer",request(game,offer),"other actor cannot cancel seller offer")
	var cash := int(game.state.players[1].cash)
	game.state.players[1].cash = 9
	rejection(game,"sale_accept_offer",request(game,offer),"insufficient full cash")
	game.state.players[1].cash = cash
	for target in ["seller","deposits","cash"]:
		var before: Dictionary = game.to_dict()
		if target == "seller": game.state.players[0].deposit = LIMIT-9
		else: game.state.bank[target] = LIMIT-9
		rejection(game,"sale_accept_offer",request(game,offer),"bank aggregate capacity "+target)
		game.state = before
	game.close_sale(int(game.sale_snapshot().session_id))
	for key in ["pending_bank_visit","pending_trap","pending_finance","pending_auction","pending_remote_dice"]:
		game.state[key] = {"fixture":true}
		var before: String = game.to_json()
		expect(not game.can_open_sale() and not game.open_sale().ok and game.to_json() == before,"pending decision blocks SALE atomically: "+key)
		game.state.erase(key)
	for key in ["hospital_days","winter_sleep_days","dream_days"]:
		game.state.players[1][key] = 2
		expect(not game.can_open_sale(),"inactive status blocks SALE: "+key)
		game.state.players[1][key] = 0
	game.set_player_ai(1,true)
	expect(not game.can_open_sale(),"AI cannot open human SALE")

func test_save_validation() -> void:
	var game := sale_game()
	open_for(game,0)
	create(game,"tool",1)
	var saved: Dictionary = game.to_dict()
	for field in ["offers","session","ai_last_turn"]:
		var broken := saved.duplicate(true)
		broken.sale_board[field] = "invalid"
		expect(not Game.validate_save(broken).ok and Game.from_dict(broken) == null,"malformed board field fails closed: "+field)
	for field in ["offer_id","revision","seller_id","source_id","quantity","asking","days"]:
		var broken := saved.duplicate(true)
		broken.sale_board.offers[0][0][field] = -1
		expect(not Game.validate_save(broken).ok,"malformed offer integer rejects: "+field)
	var duplicate := saved.duplicate(true)
	duplicate.sale_board.offers[0].append(duplicate.sale_board.offers[0][0].duplicate(true))
	expect(not Game.validate_save(duplicate).ok,"duplicate durable identity cannot load")
	var moved := saved.duplicate(true)
	moved.current_player = 1
	expect(not Game.validate_save(moved).ok,"stale session owner cannot load")
	var ai := saved.duplicate(true)
	ai.players[0].is_ai = true
	ai.players[0].is_human = false
	expect(not Game.validate_save(ai).ok,"pending human save cannot change actor control")
	expect(not game.set_player_ai(0,true) and not game.request_trustee_recovery(),"public pending session blocks trustee takeover")
	var before: String = game.to_json()
	var runner: Dictionary = game.run_ai_match(2)
	expect(runner.completed_turns == 0 and runner.awaiting_response and game.to_json() == before,"public runner leaves pending human session unchanged")
	valid_roundtrip(game,"pending human offer board")
	game.close_sale(int(game.sale_snapshot().session_id))
	var legacy: Dictionary = game.to_dict()
	legacy.erase("sale_board")
	var migrated: Object = Game.from_dict(legacy)
	expect(migrated != null and migrated.state.sale_board.offers.size() == 4,"older structural save gains empty board")

func test_ai_continuation() -> void:
	var game := sale_game()
	game.set_player_ai(0,true)
	for tool_id in game.state.players[0].tools.keys():
		Inventory.consume_tool(game.state.inventory_supply, game.state.players[0].tools, tool_id, int(game.state.players[0].tools[tool_id]))
	for card_id in game.state.players[0].cards.duplicate():
		Inventory.consume_card(game.state.inventory_supply, game.state.players[0].cards, card_id)
	game.state.phase = "await_roll"
	game._set_action_options(0)
	var rng_before := str(game.to_dict().rng_state_text)
	Sale.ai_turn(game)
	expect(str(game.to_dict().rng_state_text) == rng_before,"idle SALE AI preserves the established gameplay RNG")
	var saved: String = game.to_json()
	Sale.ai_turn(game)
	expect(game.to_json() == saved,"AI listing/purchase policy runs once per turn")
	var restored: Object = Game.from_dict(JSON.parse_string(saved))
	expect(restored != null,"AI guard roundtrip loads")
	if restored != null:
		Sale.ai_turn(restored)
		expect(restored.to_json() == saved,"save continuation cannot reroll same AI SALE attempt")
	var result: Dictionary = game.run_ai_match(4)
	expect(result.get("completed_turns",0) == 4,"public AI runner progresses with SALE integration")
	valid_roundtrip(game,"AI progression")
