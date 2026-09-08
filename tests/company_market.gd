extends SceneTree
const Market = preload("res://game/core/original_stock_market.gd")
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func rows() -> Array:
	var values: Array = []
	for i in range(12):
		values.append({"index":i,"name":"測試股票 %d" % i,"company_id":0,"market_supply":5000,"turn_supply":0,"base_price":100.0,"previous_price":100.0,"price":100.0,"volatility":1.0,"momentum":0.0,"shock":0.0,"suspension":0,"event":0})
	return values
func _initialize() -> void:
	expect(Market.symbols().size()==12 and Market.symbol(11)=="s12","twelve stable stock identities")
	expect(Market.quote(10.25,3)==30,"stock quotes truncate full fractional-price total")
	expect(is_equal_approx(Market.next_price(100.0,10.0),110.0),"ten percent rise uses half-unit tier")
	expect(is_equal_approx(Market.next_price(4.96,1.0),4.96),"candidate tier applies to price-change tick")
	expect(is_equal_approx(Market.next_price(5.02,-1.0),4.97),"fall truncates negative change toward zero")
	expect(Market.next_price(1.0,-10.0)==1.0 and Market.next_price(9999.0,10.0)==9999.0,"source price limits")
	expect(Market.adjusted_rate(301.0,100.0,100.0,8.0)==4.0,"expensive linked company damps positive momentum")
	expect(Market.adjusted_rate(301.0,100.0,100.0,-8.0)==-10.0,"expensive linked company amplifies falls then caps")
	expect(Market.adjusted_rate(84.0,100.0,100.0,4.0)==8.0,"cheap linked company doubles rises")
	expect(Market.adjusted_rate(49.0,100.0,0.0,-4.0)==-2.0,"unlinked baseline uses separate lower threshold")
	expect(Market.adjusted_rate(800.0,100.0,0.0,4.0)==4.0,"exact upper threshold stays unchanged")
	var market: Dictionary = Market.create(rows())
	var rng := RandomNumberGenerator.new()
	rng.seed=42
	Market.reset_turn_supply(market,rng)
	for row in market.rows.values():
		expect(row.turn_supply>=500 and row.turn_supply<=1499,"source turn supply stays within10–29.99percent")
	market.rows.s01.market_supply=750
	Market.reset_turn_supply(market,rng)
	expect(market.rows.s01.turn_supply==750,"small supply is wholly available")
	market.rows.s01.suspension=1
	market.rows.s02.event=0x20
	market.rows.s03.event=2
	var original: Dictionary = market.duplicate(true)
	var saved_rng := rng.state
	Market.tick(market,{},rng)
	expect(market.prices.s01==100.0,"suspended stock does not move")
	expect(market.prices.s02==110.0 and market.prices.s03==90.0,"event byte forces plus or minus ten percent")
	var replay: Dictionary = JSON.parse_string(JSON.stringify(original,"",true,true))
	rng.state=saved_rng
	Market.tick(replay,{},rng)
	# JSON parses integer fields as floats; compare numerical state here.
	expect(JSON.parse_string(JSON.stringify(market,"",true,true))==JSON.parse_string(JSON.stringify(replay,"",true,true)),"market tick replays identical values after JSON")
	market.open=false
	var before := JSON.stringify(market)
	var before_rng := rng.state
	Market.tick(market,{},rng)
	expect(JSON.stringify(market)==before and rng.state==before_rng,"closed market leaves prices history and RNG unchanged")
	market.open=true
	for day in range(150): Market.tick(market,{},rng)
	expect(market.history.s01.size()==144 and market.history_index==7,"history remains bounded with source144-slot index")
	print("Company market checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
