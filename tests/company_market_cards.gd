extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)
func card(game: Object, name: String) -> void:
	expect(Inventory.grant_card(game.state.inventory_supply,game.state.players[0].cards,name).get("ok",false),"stage source card")
	game._set_action_options(0)
	expect(game.choose_action("use_card",{"card_id":name,"symbol":"s01"}).get("ok",false),"use stock card")
func _initialize() -> void:
	var game = Game.new_game_on_board(31415,4,Fixture.definition(),{"original_facilities":true,"original_gods":true,"original_companies":true,"start_date":{"year":1998,"month":1,"day":1}})
	game.state.god_objects=[]
	card(game,"紅")
	expect(game.state.market.rows.s01.event==0x20 and game.state.market.prices.s01==110.0,"red card immediately recalculates from daily baseline")
	card(game,"紅")
	expect(game.state.market.prices.s01==110.0,"repeated red resets duration without compounding")
	card(game,"黑")
	expect(game.state.market.rows.s01.event==2 and game.state.market.prices.s01==90.0,"opposite card overwrites event and recomputes from same baseline")
	expect(game.state.market.history.s01.back()==90.0 and game.state.market.history.s01.size()==1,"card replaces current history slot")
	game._decrement_market_trends()
	expect(game.state.market.rows.s01.event==1,"black countdown decrements before next market tick")
	game._tick_market()
	expect(game.state.market.prices.s01==81.0,"remaining black day forces next fall")
	game._decrement_market_trends()
	expect(game.state.market.rows.s01.event==0,"second daily sweep clears black effect")
	game.state.market.rows.s01.suspension=1
	game.state.market.rows.s02.event=0x21
	game.state.market.closed_days=1
	game._decrement_market_trends()
	expect(game.state.market.rows.s01.suspension==0,"one-day suspension clears before market tick")
	expect(game.state.market.rows.s02.event==0x10,"both event nibbles decay independently")
	expect(game.state.market.closed_days==128 and not game.state.market.open,"final closure day retains closed marker")
	var before: Dictionary = game.state.market.duplicate(true)
	game._tick_market()
	expect(game.state.market==before,"closure marker leaves prices and history unchanged")
	game._decrement_market_trends()
	expect(game.state.market.closed_days==0 and game.state.market.open,"following daily sweep opens market")
	# A Sunday still consumes a stock event day without adding price history.
	game.state.day=4
	game._sync_state()
	game.state.market.rows.s01.event=0x20
	game._decrement_market_trends()
	var history_size: int = game.state.market.history.s01.size()
	game._tick_market()
	expect(game.state.market.rows.s01.event==0x10 and game.state.market.history.s01.size()==history_size,"Sunday decrements event but does not update price")
	game._set_action_options(0)
	var validation: Dictionary = Game.validate_save(game.to_dict())
	expect(validation.get("ok",false),"stock card state validates: "+str(validation.get("errors",[])))
	var restored = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored!=null and restored.to_json()==game.to_json(),"stock card and closure state JSON roundtrip")
	print("Company market card checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
