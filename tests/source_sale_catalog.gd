extends "res://tests/source_title_ui.gd"

const Core = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Catalogue = preload("res://game/content/original_inventory.gd")
const CATALOG_SHA := "ac6a07666ceb9d8b4f1be8a6df3d486a3ffbb1f643cd383fd58daf81c5449565"

func run() -> void:
	var catalog := OS.get_environment("RICHMAN4_MAP_CATALOG")
	if catalog.is_empty() or FileAccess.get_sha256(catalog) != CATALOG_SHA:
		print("PRECONDITION_UNMET actual installed catalog identity required")
		quit(2)
		return
	var view := SubViewport.new()
	view.size = Vector2i(960,720)
	view.handle_input_locally = true
	root.add_child(view)
	view.notify_mouse_entered()
	var ui := TitleTestUI.new()
	view.add_child(ui)
	await settle()
	ui.set_process(false)
	if not ui._map_catalog_complete or ui._map_catalog.size() != 12:
		print("PRECONDITION_UNMET incomplete actual catalog")
		quit(2)
		return
	for edition in ["Game","MultiverseJourney"]:
		var definition := find_map(ui,edition,1 if edition == "Game" else 7)
		var options: Dictionary = ui._default_setup_options(4,definition)
		options.human_flags = [true,true,true,true]
		if not ui._new_game(164,4,definition,options):
			print("PRECONDITION_UNMET normal MainUI new game failed: " + edition)
			quit(2)
			return
		await settle()
		check(ui._has_original_companies() and ui._has_original_inventory(),"normal catalog has full SALE consumers: " + edition)
		var game: Object = ui.game_state
		var economic_before := economics(game)
		var button: Button = ui.source_shell.toolbar_buttons.sale
		check(not button.disabled,"ordinary SALE toolbar is enabled: " + edition)
		press(view,button)
		await settle()
		var panel: Node = ui.source_shell.find_child("SourceSalePanel",true,false)
		var opened := panel != null and panel.has_method("is_open") and bool(panel.call("is_open"))
		check(opened,"ordinary SALE toolbar opens original bulletin board: " + edition)
		check(economics(game) == economic_before,"ordinary entry changes no holdings wallets board market supply or RNG")
		if opened:
			check(game.state.phase == "await_sale","ordinary board has a durable public session")
			var before: String = game.to_json()
			check(not game.roll().get("ok",false) and not game.end_turn().get("ok",false) and game.to_json() == before,"human pending SALE blocks turn actions without mutation")
			var runner: Dictionary = game.run_ai_match(1)
			check(runner.get("completed_turns",-1) == 0 and runner.get("awaiting_response",false) and game.to_json() == before,"AI runner cannot count or take over human pending SALE")
			await right_release(view)
			check(game.state.phase == "await_roll" and economics(game) == economic_before,"right release closes board and preserves economic world")
		var key := InputEventKey.new()
		key.keycode = KEY_X
		key.pressed = true
		view.push_input(key,true)
		await settle()
		panel = ui.source_shell.find_child("SourceSalePanel",true,false)
		opened = panel != null and panel.has_method("is_open") and bool(panel.call("is_open"))
		check(opened,"ordinary source X hotkey opens SALE: " + edition)
		if opened: await right_release(view)
		var api_present := true
		for method in ["can_open_sale","open_sale","sale_snapshot","sale_create_offer","sale_cancel_offer","sale_accept_offer","close_sale"]:
			var found: bool = game.has_method(method)
			check(found,"public SALE method exists: " + method)
			api_present = api_present and found
		if api_present: await public_transactions(game)
	view.queue_free()
	await settle()
	print("Source SALE actual catalog checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)

func economics(game: Object) -> String:
	var data: Dictionary = game.to_dict()
	var selected := {}
	for key in ["players","board","market","bank","inventory_supply","companies","rng_state_text"]:
		selected[key] = data.get(key)
	return JSON.stringify(Core._canonicalize_json_numbers(selected),"",true,true)

func right_release(view: SubViewport) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = false
	event.position = Vector2(40,40)
	view.push_input(event,true)
	await settle()

func public_transactions(game: Object) -> void:
	# Legal holdings fixture starts only after independently checked ordinary entry.
	var seller := int(game.state.current_player)
	var tool: Dictionary = Catalogue.tools()[0]
	check(Inventory.grant_tool(game.state.inventory_supply,game.state.players[seller].tools,tool.id,1).get("ok",false),"legal finite tool fixture")
	check(game.choose_action("buy_stock",{"symbol":"s01","quantity":2}).get("ok",false),"ordinary public stock purchase provides seller holding")
	check(game.call("open_sale").get("ok",false),"public open admits human SALE session")
	var model: Dictionary = game.call("sale_snapshot")
	var session := int(model.get("session_id",0))
	check(session > 0,"public session has durable nonzero identity")
	var economic_before := economics(game)
	var created: Dictionary = game.call("sale_create_offer",{"session_id":session,"category":"tool","source_id":int(tool.source_id),"quantity":1,"asking":100})
	check(created.get("ok",false),"public create publishes one tool without escrow")
	check(economics(game) == economic_before,"listing creates no debit reservation or supply transfer")
	var offer: Dictionary = created.get("offer",{})
	if offer.is_empty(): return
	var saved: String = game.to_json()
	var restored: Object = Core.from_dict(JSON.parse_string(saved))
	check(restored != null and restored.to_json() == saved,"pending offer/session survives exact JSON continuation")
	var invalid := {"session_id":session,"offer_id":int(offer.offer_id),"revision":int(offer.revision)+1}
	check(not game.call("sale_cancel_offer",invalid).get("ok",false) and game.to_json() == saved,"stale cancellation rejects without mutation")
	invalid.revision = int(offer.revision)
	check(game.call("sale_cancel_offer",invalid).get("ok",false) and economics(game) == economic_before,"own cancellation removes only listing")
	var stock_created: Dictionary = game.call("sale_create_offer",{"session_id":session,"category":"stock","source_id":0,"quantity":2,"asking":1})
	check(stock_created.get("ok",false),"source permits total ask one for two shares")
	var stock_offer: Dictionary = stock_created.get("offer",{})
	if stock_offer.is_empty(): return
	check(game.call("close_sale",session).get("ok",false),"public close resumes original turn phase")
	check(advance_actor(game,seller),"public movement and end turn reach another living human")
	if int(game.state.current_player) == seller: return
	var buyer := int(game.state.current_player)
	check(game.call("open_sale").get("ok",false),"next player opens ordinary public board")
	model = game.call("sale_snapshot")
	session = int(model.get("session_id",0))
	var seller_deposit := int(game.state.players[seller].deposit)
	var seller_cash := int(game.state.players[seller].cash)
	var buyer_cash := int(game.state.players[buyer].cash)
	var bank_deposits := int(game.state.bank.deposits)
	var bank_cash := int(game.state.bank.cash)
	var market_before: Dictionary = game.state.market.duplicate(true)
	var request := {"session_id":session,"offer_id":int(stock_offer.offer_id),"revision":int(stock_offer.revision)}
	check(game.call("sale_accept_offer",request).get("ok",false),"different player accepts exact stock quantity and total asking amount")
	check(int(game.state.players[buyer].stocks.s01) == 2 and int(game.state.players[seller].stocks.s01) == 0,"SALE transfers two shares without creating stock")
	check(float(game.state.players[buyer].stock_average_costs.s01) == 0.5,"source SALE preserves valid float32 average below one")
	check(int(game.state.players[buyer].cash) == buyer_cash-1 and int(game.state.players[seller].cash) == seller_cash and int(game.state.players[seller].deposit) == seller_deposit+1,"buyer cash credits seller deposit rather than seller cash")
	check(int(game.state.bank.deposits) == bank_deposits+1 and int(game.state.bank.cash) == bank_cash+1 and game.state.market == market_before,"SALE preserves bank aggregates and market stock supply")
	saved = game.to_json()
	restored = Core.from_dict(JSON.parse_string(saved))
	check(restored != null and restored.to_json() == saved,"low average stock cost remains valid through save and JSON load")
	check(not game.call("sale_accept_offer",request).get("ok",false) and game.to_json() == saved,"already-sold offer cannot settle twice")
	check(game.call("close_sale",session).get("ok",false),"successful sale returns to play")

func advance_actor(game: Object, actor: int) -> bool:
	game.configure_minigames(false)
	for _step in range(400):
		if int(game.state.current_player) != actor: return true
		var result: Dictionary = {"ok":false}
		if not game.pending_bank_visit().is_empty():
			result = game.resume_bank_visit() if game.pending_bank_visit().kind == "pass" else game.complete_bank_visit()
		elif game.state.phase == "await_roll": result = game.roll()
		elif game.state.phase == "await_action": result = game.end_turn()
		elif game.state.phase == "await_route": result = game.choose_route(int(game.state.route_options[0]))
		elif game.state.phase == "await_lottery": result = game.leave_lottery()
		elif game.state.phase == "await_minigame": result = game.finish_minigame(int(game.minigame_snapshot().encounter_id))
		elif game.state.phase == "await_shop":
			var visit: Dictionary = game.shop_visit_snapshot()
			result = game.acknowledge_shop_gift(int(visit.visit_id)) if visit.get("gift_pending",false) else game.leave_shop(int(visit.visit_id))
		if not result.get("ok",false): return false
	return false
