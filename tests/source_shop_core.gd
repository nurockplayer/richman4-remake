extends "res://tests/source_inventory_test_helper.gd"
const Core = preload("res://game/core/game_state.gd")
const Shop = preload("res://game/core/source_shop_flow.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Catalogue = preload("res://game/content/original_inventory.gd")
const GodCardFixture = preload("res://tests/fixtures/god_card_fixture.gd")
var definition: Dictionary
var options: Dictionary
var node_id := -1

func run() -> void:
	if OS.get_environment("RICHMAN4_SHOP_COMPOSE_ONLY") == "1":
		_test_composed_poor_god_shop_closure()
		print("Source shop composed poor-god checks: %d, failures: %d" % [checks, failures])
		quit(1 if failures else 0)
		return
	_test_composed_poor_god_shop_closure()
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("PRECONDITION_UNMET installed catalog required")
		quit(2)
		return
	var ui := MainScene.instantiate()
	root.add_child(ui)
	await settle()
	ui.set_process(false)
	definition = find_map(ui,"Game",1)
	options = ui._default_setup_options(4,definition)
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
	_test_settlement_headroom()
	_test_public_trades()
	_test_capacity_supply()
	_test_lifetime_persistence()
	_test_commercial_gift_ai()
	_test_terminal_admission_guard()
	_test_terminal_movement_admission()
	ui.queue_free()
	await settle()
	print("Source shop core checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)

func _test_settlement_headroom() -> void:
	for field in ["monthly_profit", "cumulative_profit"]:
		var game := game_at_shop(19852, true, true)
		var company: Dictionary = game.get_company_at(node_id)
		company[field] = Shop.LIMIT
		game.state.shop_visit.contribution = 700
		var pending: Dictionary = game.to_dict()
		var admission := Core.validate_save(pending)
		check(not admission.get("ok", false), "open visit rejects pending contribution beyond " + field + " headroom")
		check(Core.from_dict(JSON.parse_string(JSON.stringify(pending))) == null, "JSON restore rejects pending contribution beyond " + field + " headroom")
	var boundary := game_at_shop(19853, true, true)
	var boundary_company: Dictionary = boundary.get_company_at(node_id)
	boundary_company.monthly_profit = Shop.LIMIT - 700
	boundary_company.cumulative_profit = Shop.LIMIT - 700
	boundary.state.shop_visit.contribution = 700
	var boundary_restored: Object = Core.from_dict(JSON.parse_string(boundary.to_json()))
	check(boundary_restored != null, "exact settlement headroom boundary restores")
	if boundary_restored != null:
		var visit_id := int(boundary_restored.state.shop_visit.visit_id)
		check(boundary_restored.leave_shop(visit_id).get("ok", false), "exact settlement headroom boundary leaves successfully")
		var posted: Dictionary = boundary_restored.get_company_at(node_id)
		check(int(posted.monthly_profit) == Shop.LIMIT and int(posted.cumulative_profit) == Shop.LIMIT, "boundary posts contribution exactly to LIMIT")
	var zero := game_at_shop(19854, true, true)
	var zero_company: Dictionary = zero.get_company_at(node_id)
	zero_company.monthly_profit = Shop.LIMIT
	zero_company.cumulative_profit = Shop.LIMIT
	var zero_restored: Object = Core.from_dict(JSON.parse_string(zero.to_json()))
	check(zero_restored != null, "zero contribution at LIMIT validates and restores")
	var negative := game_at_shop(19855, true, true)
	var negative_company: Dictionary = negative.get_company_at(node_id)
	negative_company.monthly_profit = -Shop.LIMIT
	negative_company.cumulative_profit = -Shop.LIMIT
	negative.state.shop_visit.contribution = 700
	check(Core.from_dict(JSON.parse_string(negative.to_json())) != null, "negative near-LIMIT profits permit positive pending contribution")
	var float_values := game_at_shop(19856, true, true)
	var float_company: Dictionary = float_values.get_company_at(node_id)
	float_company.monthly_profit = float(Shop.LIMIT - 700)
	float_company.cumulative_profit = float(Shop.LIMIT - 700)
	float_values.state.shop_visit.contribution = 700.0
	check(Core.from_dict(JSON.parse_string(float_values.to_json())) != null, "integer-valued JSON floats retain save contract at settlement boundary")
	var closed := game_at_shop(19857, true, true)
	closed.state.shop_visit.closed = true
	closed.state.phase = "await_action"
	closed._set_action_options(0)
	var closed_company: Dictionary = closed.get_company_at(node_id)
	closed_company.monthly_profit = Shop.LIMIT
	closed_company.cumulative_profit = Shop.LIMIT
	closed.state.shop_visit.contribution = 700
	var closed_restored: Object = Core.from_dict(JSON.parse_string(closed.to_json()))
	check(closed_restored != null and int(closed_restored.state.shop_visit.contribution) == 700, "closed positive-contribution history is not rechecked against later LIMIT profits")

func _test_composed_poor_god_shop_closure() -> void:
	var fixture_definition: Dictionary = GodCardFixture.definition()
	var company_node := -1
	for tile in fixture_definition.get("board", []):
		if tile is Dictionary and (tile.has("company_node_index") or int(tile.get("source_company_id", 0)) > 0):
			company_node = int(tile.get("index", -1))
			tile["event_code"] = 15
			tile["source_status_bits"] = (int(tile.get("source_status_bits", 0)) & ~0xff) | 15
			break
	check(company_node >= 0, "complete-company god-card fixture exposes a company shop tile")
	if company_node < 0: return
	for god_id in [5, 6]:
		for player_count in [2, 3]:
			var game: Object = Core.new_game_on_board(19800 + god_id * 10 + player_count, player_count, fixture_definition, GodCardFixture.new_game_options())
			check(game != null, "composed poor-god shop game starts")
			if game == null: continue
			var actor: Dictionary = game.state.players[0]
			actor.position = company_node
			actor.points = 10000
			actor.cash = 0
			game.state.bank.deposits -= int(actor.deposit)
			actor.deposit = 0
			game.state.phase = "await_action"
			game.state.god_objects = [{"id": god_id, "owner": -1, "node": 2, "days": 0}]
			check(Inventory.grant_card(game.state.inventory_supply, actor.cards, "請神符").get("ok", false), "composed fixture grants summon card")
			game._set_action_options(0)
			check(Shop.admit(game, 0), "public shop admission opens before public card command")
			var visit: Dictionary = game.shop_visit_snapshot()
			check(not visit.is_empty(), "public shop admission exposes a visit snapshot")
			var offer_id := int(visit.tool_offers[0].get("source_id", -1)) if not visit.is_empty() and not visit.tool_offers.is_empty() else -1
			var trade: Dictionary = game.choose_action("buy_item", {"visit_id": int(visit.get("visit_id", -1)), "item_kind": "tool", "source_id": offer_id, "offer_index": 0})
			check(trade.get("ok", false), "public shop trade completes before poor-god command")
			var contribution := int(game.state.shop_visit.contribution)
			var company: Dictionary = game.get_company_at(company_node)
			var posted_before := [int(company.get("monthly_profit", 0)), int(company.get("cumulative_profit", 0))]
			var leave: Dictionary = game.leave_shop(int(visit.get("visit_id", -1)))
			check(leave.get("ok", false) and contribution > 0, "public shop close posts the completed trade contribution")
			check(int(company.monthly_profit) == posted_before[0] + contribution and int(company.cumulative_profit) == posted_before[1] + contribution, "shop contribution posts once to monthly and cumulative venue totals")
			var after_close: Array = [int(company.monthly_profit), int(company.cumulative_profit)]
			check(not game.leave_shop(int(visit.get("visit_id", -1))).get("ok", false) and after_close == [int(company.monthly_profit), int(company.cumulative_profit)], "repeated public close cannot post shop contribution twice")
			game.state.players[0].position = 1
			game.state.players[0].previous_position = -1
			game.state.last_roll = [1]
			game.state.last_total = 1
			game.state.last_roll_total = 1
			var spell: Dictionary = game.choose_action("use_card", {"card_id": "請神符", "visible_tile_ids": [2]})
			check(spell.get("ok", false) and not bool(game.state.players[0].alive), "public summon card after shop close bankrupts its caster")
			var prefix := "god%d players%d: " % [god_id, player_count]
			check(Core.validate_save(game.to_dict()).get("ok", false), prefix + "public shop-close then poor-god state passes save validation")
			var restored: Object = Core.from_dict(JSON.parse_string(game.to_json()))
			check(restored != null, prefix + "composed terminal or handoff state restores from JSON")
			if player_count == 2:
				check(game.state.phase == "game_over" and int(game.state.winner) == 1, prefix + "public poor-god bankruptcy ends two-player game")
			else:
				check(int(game.state.current_player) == 1 and game.state.phase == "await_roll" and int(game.state.turn) == 2 and not game.state.action_options.is_empty(), prefix + "public poor-god bankruptcy hands three-player game to the deterministic next actor")
				if restored != null:
					var next_result: Dictionary = game.run_ai_turn()
					var replay_result: Dictionary = restored.run_ai_turn()
					check(next_result.get("ok", false) and replay_result.get("ok", false) and game.to_json() == restored.to_json(), prefix + "post-handoff continuation matches its JSON-restored replay")

func _test_terminal_movement_admission() -> void:
	var fixture_definition: Dictionary = definition.duplicate(true)
	var shop_node := -1
	for tile in fixture_definition.get("board", []):
		if tile is Dictionary and (tile.has("company_node_index") or int(tile.get("source_company_id", 0)) > 0):
			shop_node = int(tile.index)
			tile.event_code = 15
			tile.source_status_bits = (int(tile.get("source_status_bits", 0)) & ~0xff) | 15
			break
	check(shop_node >= 0, "v7 terminal recipe finds a company shop node")
	if shop_node < 0: return
	var v7: Dictionary = options.duplicate(true)
	for key in ["original_inventory","original_facilities","original_gods","original_companies"]: v7[key] = true
	for key in ["original_statuses","original_hazards","original_property_cards","original_remodel","original_research","original_building_cards"]: v7[key] = false
	if v7.get("character_ids", []) is Array: v7.character_ids = v7.character_ids.slice(0,2)
	var game: Object = Core.new_game_on_board(19833,2,fixture_definition,v7)
	check(game != null, "v7 terminal movement game starts without hazards")
	if game == null: return
	var shop_tile: Dictionary = game._tile_at(shop_node)
	var predecessor := int(shop_tile.adjacent[0]) if not shop_tile.get("adjacent", []).is_empty() else -1
	if predecessor < 0: return
	var prior := -1
	for neighbor in game._tile_at(predecessor).get("adjacent", []):
		if int(neighbor) != shop_node:
			prior = int(neighbor)
			break
	check(prior >= 0, "v7 terminal movement fixture has a previous node")
	if prior < 0: return
	# Reduce only the moving actor's outbound choices while keeping the two
	# traversed edges reciprocal and valid.
	for tile_index in range(game.state.board.size()):
		var tile_value: Dictionary = game.state.board[tile_index]
		var edges: Array = tile_value.get("adjacent", [])
		if tile_index == predecessor:
			tile_value.adjacent = [shop_node, prior]
		elif tile_index == shop_node:
			tile_value.adjacent = [predecessor]
		elif tile_index != prior:
			var kept: Array = []
			for edge in edges:
				if int(edge) != predecessor and int(edge) != shop_node: kept.append(edge)
			tile_value.adjacent = kept
	var actor: Dictionary = game.state.players[0]
	actor.position = predecessor
	actor.previous_position = prior
	actor.attached_god_id = 0
	var rival: Dictionary = game.state.players[1]
	game.state.bank.deposits -= int(rival.deposit)
	rival.deposit = 0
	rival.cash = 0
	rival.attached_god_id = 0
	game.state.god_objects = [{"id":1,"owner":-1,"node":shop_node,"days":0}]
	game.state.phase = "await_roll"
	check(Inventory.grant_tool(game.state.inventory_supply,actor.tools,"遙控骰子",1).ok, "v7 terminal fixture grants legal remote dice")
	game._set_action_options(0)
	var precheck: Dictionary = Core.validate_save(game.to_dict())
	check(precheck.get("ok",false), "v7 terminal remote-dice prestate is valid " + str(precheck.get("errors",[])))
	var scheduled: Dictionary = game.choose_action("use_tool",{"tool_id":"遙控骰子","value":1})
	check(scheduled.get("ok",false), "public remote-dice command schedules value one")
	var rolled: Dictionary = game.roll()
	check(rolled.get("ok",false), "public remote-dice roll reaches the final opponent's bankruptcy")
	var terminal: Dictionary = game.to_dict()
	check(terminal.phase == "game_over" and int(terminal.winner) == 0, "terminal roll preserves the moving human as winner")
	check(terminal.shop_visit.is_empty() and int(terminal.shop_sequence) == 0, "terminal landing does not open a visit or advance shop admission sequence")
	var terminal_check: Dictionary = Core.validate_save(terminal)
	check(terminal_check.get("ok",false), "terminal public state validates after shop admission guard " + str(terminal_check.get("errors",[])))
	var restored: Object = Core.from_dict(JSON.parse_string(game.to_json()))
	check(restored != null and restored.state.phase == "game_over" and int(restored.state.winner) == 0 and restored.shop_visit_snapshot().is_empty(), "terminal public JSON restore keeps winner and has no open shop visit")

func _test_terminal_admission_guard() -> void:
	var game: Object = game_at_shop(8821, true, false)
	game.state.phase = "game_over"
	game.state.winner = 0
	var before: Dictionary = game.to_dict()
	check(not Shop.admit(game, 0), "terminal source shop admission is rejected")
	check(game.to_dict() == before, "terminal admission rejection leaves RNG, sequence, gift, visit, events and accounting unchanged")

func game_at_shop(seed_value: int = 162, human: bool = true, admit: bool = true) -> Object:
	var setup := options.duplicate(true)
	var game: Object = Core.new_game_on_board(seed_value,4,definition,setup)
	if not human:
		check(game.set_player_ai(0,true), "rare AI shop fixture switches actor 0 before admission")
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
	var structural_source := game_at_shop(162,true,false)
	var old_source: Dictionary = structural_source.to_dict()
	old_source.erase("shop_visit")
	old_source.erase("shop_sequence")
	var migrated: Object = Core.from_dict(old_source)
	check(migrated != null and migrated.state.shop_visit.is_empty() and migrated.state.shop_sequence == 0,"complete graph inventory saves missing both shop fields receive structural empty initialization")
	var game := game_at_shop()
	valid(game,"pending visit")
	var missing_pending: Dictionary = game.to_dict()
	missing_pending.erase("shop_visit")
	missing_pending.erase("shop_sequence")
	check(Core.from_dict(missing_pending) == null,"legacy missing fields cannot erase an active pending visit")
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
	var missing_closed := before.duplicate(true)
	missing_closed.shop_visit.erase("closed")
	check(Core.from_dict(missing_closed) == null,"malformed visit missing closed flag is rejected")
	var mismatched_open_actor := before.duplicate(true)
	mismatched_open_actor.players[0].is_ai = true
	mismatched_open_actor.players[0].is_human = false
	check(Core.from_dict(mismatched_open_actor) == null,"open human visit rejects malformed actor mismatch")
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
	var historic: Dictionary = game.to_dict()
	historic.turn = int(historic.turn) + 1
	historic.current_player = 1
	historic.phase = "game_over"
	historic.action_options = []
	historic.winner = -1
	historic.last_event = {"type":"game_over", "reason":"company_dividend_no_survivors", "winner":-1}
	for historic_player in historic.players:
		historic_player.alive = false
		historic_player.bankrupt = true
	var historic_check: Dictionary = Core.validate_save(historic)
	check(historic_check.get("ok", false), "closed visit validates after owner death, turn handoff, and terminal phase: " + str(historic_check.get("errors", [])))
	var historic_restore: Object = Core.from_dict(JSON.parse_string(JSON.stringify(historic)))
	check(historic_restore != null and historic_restore.state.shop_visit == historic.shop_visit, "closed visit history survives terminal JSON round trip")
	var closed_await_shop: Dictionary = game.to_dict()
	closed_await_shop.phase = "await_shop"
	check(Core.from_dict(closed_await_shop) == null,"closed visit cannot restore into shop phase")
	_test_closed_visit_actor_history(game)
	_test_closed_visit_post_close_actions(game)
	_test_closed_visit_pending_card_response()
	check(game.end_turn().ok,"closed visit returns to ordinary turn continuation")
	valid(game,"after shop turn")

func _test_closed_visit_actor_history(game: Object) -> void:
	var visit: Dictionary = game.state.shop_visit.duplicate(true)
	var company: Dictionary = game.get_company_at(node_id)
	var completed_trades := int(visit.contribution)
	var contribution := [int(company.monthly_profit),int(company.cumulative_profit)]
	var inventory: Dictionary = game.state.inventory_supply.duplicate(true)
	var held: Dictionary = game.state.players[0].duplicate(true)
	var rng_state := int(game._rng.state)
	check(game.set_player_ai(0,true),"closed human visit permits public human-to-AI mode change")
	check(game.state.shop_visit == visit and int(company.monthly_profit) == contribution[0] and int(company.cumulative_profit) == contribution[1],"mode change retains closed visit offers, trades, and posted contribution")
	check(int(game.state.shop_visit.contribution) == completed_trades and game.state.inventory_supply == inventory and game.state.players[0].cards == held.cards and game.state.players[0].tools == held.tools and game.state.players[0].points == held.points and int(game._rng.state) == rng_state,"mode change preserves completed trade inventory and RNG")
	valid(game,"closed visit after AI toggle")
	var toggled_json: String = game.to_json()
	var toggled_restore: Object = Core.from_dict(JSON.parse_string(toggled_json))
	check(toggled_restore != null and toggled_restore.state.players[0].is_ai and toggled_restore.state.shop_visit.human,"JSON restore retains new actor mode and historical closed human actor")
	check(game.set_player_ai(0,false),"closed human visit permits public AI-to-human mode change")
	check(game.state.shop_visit == visit and int(game._rng.state) == rng_state and game.state.inventory_supply == inventory,"reverse toggle retains closed visit and does not reroll or transact")
	valid(game,"closed visit after reverse toggle")
	var ai_game := game_at_shop(163,false,false)
	ai_game._resolve_landing(0,false)
	var ai_visit: Dictionary = ai_game.state.shop_visit.duplicate(true)
	check(ai_visit.closed and not ai_visit.human and ai_game.set_player_ai(0,false),"closed AI visit permits public AI-to-human mode change")
	check(ai_game.state.shop_visit == ai_visit,"AI-origin visit retains its historical actor flag")
	valid(ai_game,"closed AI visit after human toggle")

func _test_closed_visit_post_close_actions(game: Object) -> void:
	var visit: Dictionary = game.state.shop_visit.duplicate(true)
	check(Inventory.grant_card(game.state.inventory_supply,game.state.players[0].cards,"陷害").ok,"legal caster fixture receives trap card")
	check(Inventory.grant_card(game.state.inventory_supply,game.state.players[1].cards,"復仇").ok,"legal living target fixture receives revenge card")
	check(game.trap_target_players(0).has(1),"public trap target list includes living non-detained revenge holder")
	var result: Dictionary = game.choose_action("use_card",{"card_id":"陷害","target_id":1})
	check(result.get("ok",false),"post-close public trap action resolves revenge")
	check(game.state.players[0].position != int(visit.node_id) and int(game.state.players[0].prison_days) > 0,"revenge moves closed-visit caster to prison")
	check(game.state.shop_visit == visit and game.state.phase == "await_action","post-close card continuation retains immutable visit and ordinary action phase")
	valid(game,"closed visit after revenge movement")
	var restored: Object = Core.from_dict(JSON.parse_string(game.to_json()))
	check(restored != null and restored.state.players[0].position == game.state.players[0].position and restored.state.shop_visit == visit,"JSON round trip preserves moved actor and closed visit history")

func _test_closed_visit_pending_card_response() -> void:
	var game := game_at_shop()
	var visit_id := int(game.state.shop_visit.visit_id)
	check(game.leave_shop(visit_id).ok,"response fixture closes source shop")
	var visit: Dictionary = game.state.shop_visit.duplicate(true)
	check(game.set_player_ai(1,false),"post-close response fixture enables human opponent")
	check(Inventory.grant_card(game.state.inventory_supply,game.state.players[0].cards,"夢遊").ok,"post-close response fixture grants dream card")
	check(Inventory.grant_card(game.state.inventory_supply,game.state.players[1].cards,"嫁禍").ok,"post-close response fixture grants opponent redirect card")
	var pending: Dictionary = game.choose_action("use_card",{"card_id":"夢遊","target_id":1})
	check(pending.get("ok",false) and pending.get("awaiting_response",false),"post-close card action reaches opponent response")
	check(game.state.shop_visit == visit and game.state.phase == "await_action" and game.state.action_options == ["respond_trap"],"closed visit permits ordinary pending card response phase")
	valid(game,"closed visit during pending card response")

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
