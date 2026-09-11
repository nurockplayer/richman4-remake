extends "res://tests/stock_accounting.gd"
const Accounting = preload("res://game/core/stock_accounting.gd")

func _initialize() -> void:
	test_source_reachable_bounds()
	test_public_sale_low_cost()
	print("S21 fixed stock cost checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func test_source_reachable_bounds() -> void:
	var game := make_game()
	prepare_market(game,100.0,100.0)
	expect(game.choose_action("buy_stock",{"symbol":"s01","quantity":1}).get("ok",false), "boundary fixture originates in public market buy")
	var saved: Dictionary = game.to_dict()
	var minimum := source_float(1.0 / 1000000000.0)
	for value in [0.5, minimum]:
		var legal := saved.duplicate(true)
		legal.players[0].stocks.s01 = 1
		legal.players[0].stock_average_costs.s01 = value
		expect(Game.validate_save(legal).get("ok",false), "source reachable positive cost validates: " + str(value))
		var loaded: Object = Game.from_dict(JSON.parse_string(JSON.stringify(legal)))
		expect(loaded != null, "source reachable positive cost survives JSON: " + str(value))
		if loaded != null:
			expect(float(loaded.state.players[0].stock_average_costs.s01) == value, "source cost is canonical float32 after JSON")
	for value in [minimum / 2.0, 1e-50, -0.5, INF, NAN, 1e300, 0.0]:
		var invalid := saved.duplicate(true)
		invalid.players[0].stocks.s01 = 1
		invalid.players[0].stock_average_costs.s01 = value
		expect(not Game.validate_save(invalid).get("ok",false), "malformed positive holding cost rejects: " + str(value))
		expect(Game.from_dict(invalid) == null, "malformed cost cannot load: " + str(value))
	var empty_game := make_game()
	var empty: Dictionary = empty_game.to_dict()
	empty.players[0].stock_average_costs.s01 = 0.5
	expect(not Game.validate_save(empty).get("ok",false), "zero holdings reject nonzero subunit cost")
	var unknown := saved.duplicate(true)
	unknown.players[0].stocks.s01 = 1
	unknown.players[0].stock_average_costs.s01 = null
	expect(Game.from_dict(unknown) != null, "legacy unknown held cost remains honest")

func test_public_sale_low_cost() -> void:
	var game := make_game()
	prepare_market(game,100.0,100.0)
	game.set_player_ai(0,false)
	game.set_player_ai(1,false)
	expect(game.choose_action("buy_stock",{"symbol":"s01","quantity":2}).get("ok",false), "public seller market purchase succeeds")
	if not game.has_method("open_sale"):
		expect(false,"public SALE API absent on predecessor; public cost branch not yet qualified")
		return
	expect(game.call("open_sale").get("ok",false), "seller opens public SALE")
	var sid := int(game.call("sale_snapshot").get("session_id",0))
	var offer_result: Dictionary = game.call("sale_create_offer",{"session_id":sid,"category":"stock","source_id":0,"quantity":2,"asking":1})
	expect(offer_result.get("ok",false), "public SALE creates ask1 quantity2")
	var offer: Dictionary = offer_result.get("offer",{})
	if offer.is_empty(): return
	expect(game.call("close_sale",sid).get("ok",false), "seller closes SALE")
	# Actor staging only; all holdings and accounting originate in public actions.
	game.state.current_player = 1
	game.state.phase = "await_action"
	game._set_action_options(1)
	expect(game.call("open_sale").get("ok",false), "buyer opens public SALE")
	sid = int(game.call("sale_snapshot").get("session_id",0))
	expect(game.call("sale_accept_offer",{"session_id":sid,"offer_id":offer.offer_id,"revision":offer.revision}).get("ok",false), "public SALE accepts ask1 quantity2")
	expect(game.call("close_sale",sid).get("ok",false), "buyer closes SALE")
	expect(game.state.players[1].stocks.s01 == 2 and game.state.players[1].stock_average_costs.s01 == 0.5, "SALE records exact subunit float32 cost")
	valid_save(game,"public SALE subunit cost")
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null, "public SALE subunit cost survives JSON")
	expect(game.choose_action("sell_stock",{"symbol":"s01","quantity":1}).get("ok",false), "public partial sale succeeds")
	expect(game.state.players[1].stocks.s01 == 1 and game.state.players[1].stock_average_costs.s01 == 0.5, "partial sale keeps subunit cost with one share")
	valid_save(game,"partial subunit holding")
	expect(Game.from_dict(JSON.parse_string(game.to_json())) != null, "partial subunit holding survives JSON")
	var quote := Market.quote(float(game.state.market.prices.s01),1)
	expect(game.choose_action("buy_stock",{"symbol":"s01","quantity":1}).get("ok",false), "later public market purchase succeeds")
	var expected := source_float(float(int(0.5) + quote) / 2.0)
	expect(game.state.players[1].stock_average_costs.s01 == expected, "later purchase recognizes known subunit cost and truncates prior total")
	expect(game.choose_action("sell_stock",{"symbol":"s01","quantity":2}).get("ok",false), "public full sale succeeds")
	expect(game.state.players[1].stock_average_costs.s01 == 0.0, "full sale clears subunit-derived average")
