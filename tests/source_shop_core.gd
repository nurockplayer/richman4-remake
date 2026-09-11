extends "res://tests/source_title_ui.gd"
const Core = preload("res://game/core/game_state.gd")
const Shop = preload("res://game/core/source_shop_flow.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Catalogue = preload("res://game/content/original_inventory.gd")
var definition: Dictionary
var options: Dictionary
var node_id := -1

func run() -> void:
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("PRECONDITION_UNMET installed catalog required")
		quit(2)
		return
	var ui := TitleTestUI.new()
	root.add_child(ui)
	await settle()
	ui.set_process(false)
	definition = find_map(ui,"Game",1)
	options = ui._default_setup_options(4,definition)
	options.human_flags = [true,true,true,true]
	options.start_date = {"year":1998,"month":1,"day":1}
	for tile in definition.board:
		if int(tile.get("event_code",0)) == 15:
			node_id = int(tile.index)
			break
	if node_id < 0:
		print("PRECONDITION_UNMET actual shop missing")
		quit(2)
		return
	_test_sampling()
	_test_public_trades()
	_test_capacity_supply()
	_test_lifetime_persistence()
	_test_commercial_gift_ai()
	ui.queue_free()
	await settle()
	print("Source shop core checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)

func game_at_shop(seed_value: int = 162, human: bool = true, admit: bool = true) -> Object:
	var setup := options.duplicate(true)
	setup.human_flags = [human,true,true,true]
	var game: Object = Core.new_game_on_board(seed_value,4,definition,setup)
	game.state.god_objects = [] # Isolate shop fixtures from unrelated random god occupancy.
	game.state.players[0].position = node_id
	game.state.players[0].points = 10000
	game.state.phase = "await_action"
	game._set_action_options(0)
	if admit: game._resolve_landing(0,false) # Legal rare-state fixture on a real catalog venue.
	return game

func valid(game: Object, label: String) -> void:
	var result: Dictionary = Core.validate_save(game.to_dict())
	check(result.get("ok",false),label + " save valid " + str(result.get("errors",[])))
	var restored: Object = Core.from_dict(JSON.parse_string(game.to_json()))
	check(restored != null,label + " JSON restores")
	if restored != null: check(restored.to_json() == game.to_json(),label + " continuation preserves exact state")

func buy(game: Object, kind: String, index: int) -> Dictionary:
	var visit: Dictionary = game.shop_visit_snapshot()
	var row: Dictionary = visit[kind + "_offers"][index]
	return game.choose_action("buy_item",{"visit_id":visit.visit_id,"item_kind":kind,"source_id":row.source_id,"offer_index":index})

func sell(game: Object, kind: String, index: int) -> Dictionary:
	var visit: Dictionary = game.shop_visit_snapshot()
	var row: Dictionary = visit["cards" if kind == "card" else "tools"][index]
	return game.choose_action("sell_item",{"visit_id":visit.visit_id,"item_kind":kind,"source_id":row.source_id,"held_index":index})

func return_cards(game: Object) -> void:
	for item_id in game.state.players[0].cards.duplicate():
		check(Inventory.consume_card(game.state.inventory_supply,game.state.players[0].cards,item_id).ok,"legal held-card fixture returns supply")

func _test_sampling() -> void:
	var supply := Inventory.new_supply()
	var before := supply.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 162
	var found_duplicate := false
	for trial in range(20):
		var offers := Shop.sample_offers(supply,rng)
		check(offers.cards.size() >= 6 and offers.cards.size() <= 15,"sample source six-to-fifteen range")
		var counts: Dictionary = {}
		for source_id in offers.cards:
			counts[source_id] = int(counts.get(source_id,0))+1
			check(int(counts[source_id]) <= int(supply.cards[Shop.record("card",source_id).id]),"sampling without replacement of remaining copies")
			if int(counts[source_id]) > 1: found_duplicate = true
		check(offers.tools == [1,2,3,4,5,6,7,8],"tool offers each available source type exactly once in order")
	check(found_duplicate,"weighted card-copy samples can repeat a card type")
	check(supply == before,"offer creation reserves no shared supply")
	for item_id in supply.cards: supply.cards[item_id] = 0
	for item_id in supply.tools: supply.tools[item_id] = 0
	var empty := Shop.sample_offers(supply,rng)
	check(empty.cards.is_empty() and empty.tools.is_empty(),"empty pools safely yield empty offers")

func _test_public_trades() -> void:
	var game := game_at_shop()
	return_cards(game)
	var visit: Dictionary = game.shop_visit_snapshot()
	var duplicates: Array = []
	for a in range(visit.card_offers.size()):
		for b in range(a+1,visit.card_offers.size()):
			if visit.card_offers[a].source_id == visit.card_offers[b].source_id: duplicates = [a,b]
	check(not duplicates.is_empty(),"fixed public visit contains independent duplicate offer rows")
	var index := int(duplicates[0]) if not duplicates.is_empty() else 0
	var row: Dictionary = visit.card_offers[index]
	var stock_before := int(game.state.inventory_supply.cards[row.id])
	var points_before := int(game.state.players[0].points)
	check(buy(game,"card",index).ok,"public visit buys one offered card")
	var after: Dictionary = game.shop_visit_snapshot()
	check(after.card_offers.size() == visit.card_offers.size() and after.card_offers[index].is_empty(),"purchase clears exact row and retains its hole")
	if not duplicates.is_empty(): check(not after.card_offers[int(duplicates[1])].is_empty(),"buy preserves the other duplicate row")
	check(game.state.inventory_supply.cards[row.id] == stock_before-1 and game.state.players[0].points == points_before-int(row.price),"one purchase debits one supply and full point price")
	var before: Dictionary = game.to_dict()
	var old := {"visit_id":visit.visit_id,"item_kind":"card","source_id":row.source_id,"offer_index":index}
	check(not game.choose_action("buy_item",old).ok and game.to_dict() == before,"same offer cannot buy twice")
	old.offer_index = visit.card_offers.size()
	check(not game.choose_action("buy_item",old).ok and game.to_dict() == before,"one-past offer row rejected atomically")
	old.offer_index = 0
	old.visit_id = int(visit.visit_id)+1
	check(not game.choose_action("buy_item",old).ok and game.to_dict() == before,"stale visit rejected atomically")
	check(not game.choose_action("buy_item",{"item_kind":"tool","item_id":"機車","quantity":2}).ok and game.to_dict() == before,"public direct bulk bypass rejected")
	check(not game.choose_action("buy_stock",{"symbol":"s01","quantity":1}).ok and game.to_dict() == before,"pending shop excludes stock action")
	check(sell(game,"card",0).ok,"public held card sale commits")
	check(game.state.players[0].points == points_before-int(row.price)+Inventory.quote_sale("card",row.id),"one sale credits truncated ninety percent")
	# Preserve the exact selected duplicate position among other held types.
	for item_id in ["改建","轉向","改建"]: check(Inventory.grant_card(game.state.inventory_supply,game.state.players[0].cards,item_id).ok,"legal duplicate held fixture")
	check(sell(game,"card",2).ok and game.state.players[0].cards == ["改建","轉向"],"selling selected duplicate preserves other held order")
	var tools: Array = game.shop_visit_snapshot().tools
	var tool_row: Dictionary = tools[0]
	var held_before := int(game.state.players[0].tools[tool_row.id])
	check(sell(game,"tool",0).ok and int(game.state.players[0].tools.get(tool_row.id,0)) == held_before-1,"source held tool sale consumes exactly one")
	valid(game,"traded visit")

func _test_capacity_supply() -> void:
	var game := game_at_shop()
	var offer_index := -1
	var visit: Dictionary = game.shop_visit_snapshot()
	for index in range(visit.tool_offers.size()):
		if visit.tool_offers[index].id == "機車": offer_index = index
	check(offer_index >= 0,"source visit offers available motorcycle")
	check(Inventory.grant_tool(game.state.inventory_supply,game.state.players[0].tools,"機車",9).ok,"legal nine-copy held fixture")
	var before: Dictionary = game.to_dict()
	check(not buy(game,"tool",offer_index).ok and game.to_dict() == before,"held quantity nine rejects purchase unchanged")
	check(Inventory.consume_tool(game.state.inventory_supply,game.state.players[0].tools,"機車",9).ok,"return fixture supply")
	game.state.players[0].points = 0
	before = game.to_dict()
	check(not buy(game,"tool",offer_index).ok and game.to_dict() == before,"insufficient points leaves offer inventory RNG unchanged")
	game.state.players[0].points = 10000
	for player in game.state.players:
		if player.id == 0: continue
		var remaining := int(game.state.inventory_supply.tools["機車"])
		if remaining > 0: check(Inventory.grant_tool(game.state.inventory_supply,player.tools,"機車",mini(remaining,9)).ok,"legal other-holder depletes unreserved supply")
	before = game.to_dict()
	check(not buy(game,"tool",offer_index).ok and game.to_dict() == before,"depleted offer fails without clearing row")
	# Capacity admission keeps all old cards, even though non-shop gifts can evict.
	while game.state.players[0].cards.size() < 15:
		var granted := Inventory.receive_random_card(game.state.inventory_supply,game.state.players[0].cards,game._rng)
		if not granted.ok: break
	before = game.to_dict()
	check(game.state.players[0].cards.size() == 15 and not buy(game,"card",0).ok and game.to_dict() == before,"shop full hand rejects instead of evicting")
	var company: Dictionary = game.get_company_at(node_id)
	company.monthly_profit = Shop.LIMIT
	before = game.to_dict()
	check(not sell(game,"card",0).ok and game.to_dict() == before,"venue contribution headroom is checked before wallet/inventory mutation")

func _test_lifetime_persistence() -> void:
	var game := game_at_shop()
	valid(game,"pending visit")
	var visit: Dictionary = game.shop_visit_snapshot()
	var before: Dictionary = game.to_dict()
	for index in range(5): game.shop_visit_snapshot()
	check(game.to_dict() == before,"repaint snapshots consume no RNG and never reroll")
	check(not game.end_turn().ok and not game.roll().ok and game.to_dict() == before,"pending visit prevents turn actions")
	check(not game.set_player_ai(0,true) and game.to_dict() == before,"public AI switch cannot steal human visit")
	check(not game.run_ai_turn().ok and game.to_dict() == before,"public AI step cannot operate human pending visit")
	var runner: Dictionary = game.run_ai_match(1)
	check(runner.get("completed_turns",-1) == 0 and runner.get("awaiting_response",false) and game.to_dict() == before,"runner does not count pending human visit")
	for mutate in ["visit_id","node_id","player_id","tool_order","gift","phase"]:
		var bad := before.duplicate(true)
		match mutate:
			"visit_id": bad.shop_visit.visit_id = 0
			"node_id": bad.shop_visit.node_id = -1
			"player_id": bad.shop_visit.player_id = 99
			"tool_order": bad.shop_visit.tool_offers = [2,1]
			"gift": bad.shop_visit.gift = {"item_kind":"card","item_id":"missing"}
			"phase": bad.phase = "await_action"
		check(Core.from_dict(bad) == null,"malformed visit rejected: " + mutate)
	var company: Dictionary = game.get_company_at(node_id)
	var monthly := int(company.monthly_profit)
	var cumulative := int(company.cumulative_profit)
	check(buy(game,"tool",0).ok,"trade before close")
	var contribution := int(game.state.shop_visit.contribution)
	check(company.monthly_profit == monthly and company.cumulative_profit == cumulative,"venue accounting defers accumulated contribution until close")
	var points := int(game.state.players[0].points)
	check(game.leave_shop(int(visit.visit_id)).ok,"close completes pending shop")
	check(company.monthly_profit == monthly+contribution and company.cumulative_profit == cumulative+contribution,"close adds contribution to both accepted venue fields")
	check(game.state.players[0].points == points and game.shop_visit_snapshot().is_empty(),"close preserves completed trades and removes active view")
	before = game.to_dict()
	check(not game.leave_shop(int(visit.visit_id)).ok and game.to_dict() == before,"second close cannot duplicate venue contribution")
	Shop.admit(game,0)
	check(game.to_dict() == before,"same-visit reopen cannot replenish offers or gift")
	valid(game,"closed visit")
	check(game.end_turn().ok,"closed visit returns to ordinary turn continuation")
	valid(game,"after shop turn")

func _test_commercial_gift_ai() -> void:
	var game := game_at_shop(22,true,false)
	var company: Dictionary = game.get_company_at(node_id)
	var symbol: String = game.get_stock_symbols()[int(company.stock_index)]
	check(game.choose_action("buy_stock",{"symbol":symbol,"quantity":1}).ok,"public market grants legal venue ownership")
	check(company.owner == 0,"gift fixture is actual venue owner")
	game._resolve_landing(0,false)
	var visit: Dictionary = game.shop_visit_snapshot()
	check(not visit.is_empty() and not visit.gift.is_empty() and visit.gift_pending and not visit.ready,"owned shop gifts one item then still enters shop with message pending")
	var before: Dictionary = game.to_dict()
	check(not buy(game,"tool",0).ok and game.to_dict() == before,"gift message precedes ready transaction state")
	valid(game,"gift pending")
	check(game.acknowledge_shop_gift(int(visit.visit_id)).ok and game.shop_visit_snapshot().ready,"source gift acknowledgement enables same visit")
	check(game.shop_visit_snapshot().card_offers == visit.card_offers,"gift acknowledgement never rerolls offers")
	before = game.to_dict()
	check(not game.acknowledge_shop_gift(int(visit.visit_id)).ok and game.to_dict() == before,"gift is acknowledged once")
	var ai := game_at_shop(162,false,false)
	var rng_before: int = ai._rng.state
	ai._resolve_landing(0,false)
	check(ai.state.phase == "await_action" and ai.state.shop_visit.closed and not ai.state.shop_visit.human,"AI shop uses direct helpers and returns without human pending panel")
	check(ai.state.shop_visit.card_offers.is_empty() and ai.state.shop_visit.tool_offers.is_empty() and ai._rng.state == rng_before,"unowned AI shop never generates random human offers")
	check(ai.state.shop_visit.contribution > 0,"AI direct transaction contributes venue accounting")
	valid(ai,"AI completed shop")
	var turn_before := int(ai.state.turn)
	check(ai.run_ai_turn().get("completed",false) and ai.state.turn > turn_before,"public AI step actually advances after natural shop handler")
	var all_ai := game_at_shop(162,false,false)
	all_ai._resolve_landing(0,false)
	var match_result: Dictionary = all_ai.run_ai_match(1)
	check(int(match_result.get("completed_turns",0)) == 1 and int(all_ai.state.turn) > 1,"public AI runner counts actual completed turn after shop")
