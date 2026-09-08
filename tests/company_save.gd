extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)
func reject(data: Dictionary, message: String) -> void:
	expect(not Game.validate_save(data).get("ok",false),message+" validation")
	expect(Game.from_dict(data)==null,message+" loading")
func _initialize() -> void:
	var game = Game.new_game_on_board(42,4,Fixture.definition(),{"original_facilities":true,"original_gods":true,"original_companies":true,"start_date":{"year":1998,"month":1,"day":1}})
	var saved: Dictionary = game.to_dict()
	for key in ["original_companies","companies","company_purchase_remaining","company_months","jackpot"]:
		var broken: Dictionary = saved.duplicate(true)
		broken.erase(key)
		reject(broken,"missing "+key)
	for field in ["market_supply","turn_supply","index","company_id","suspension","event","price","momentum","volatility","shock","name"]:
		for value in [null,{},[],true]:
			var broken: Dictionary = saved.duplicate(true)
			broken.market.rows.s01[field]=value
			reject(broken,"wrong stock "+field+" type")
	for field in ["id","stock_index","company_type","stock_value","toll_fee","monthly_profit","cumulative_profit","treasury","owner","display_name"]:
		for value in [null,{},[],true]:
			var broken: Dictionary = saved.duplicate(true)
			broken.companies[0][field]=value
			reject(broken,"wrong company "+field+" type")
	for field in ["market_supply","turn_supply"]:
		var broken: Dictionary = saved.duplicate(true)
		broken.market.rows.s01[field]+=1
		if field=="turn_supply": broken.market.rows.s01[field]=5001
		reject(broken,"invalid supply "+field)
	var broken: Dictionary = saved.duplicate(true)
	broken.market.rows.s01.company_id=0
	broken.companies[0].treasury=0
	broken.market.rows.s01.market_supply=10000
	reject(broken,"company must have matching reverse stock link")
	broken=saved.duplicate(true)
	broken.board[0].source_company_id=1
	reject(broken,"company metadata cannot hijack other board node")
	broken=saved.duplicate(true)
	broken.companies[0].owner=0
	reject(broken,"owner must hold most shares")
	broken=saved.duplicate(true)
	broken.players[0].stocks.s01=1
	reject(broken,"shares cannot be fabricated")
	broken=saved.duplicate(true)
	broken.market.prices.s01=99.0
	reject(broken,"price mirrors agree")
	broken=saved.duplicate(true)
	broken.market.history.s01=[99.0]
	reject(broken,"history tail matches price")
	broken=saved.duplicate(true)
	broken.market.rows.s01.price=INF
	reject(broken,"infinite price rejected")
	broken=saved.duplicate(true)
	broken.market.rows.s01.shock=NAN
	reject(broken,"NaN shock rejected")
	broken=saved.duplicate(true)
	broken.market.rows.s01.price=100.096
	broken.market.prices.s01=100.096
	broken.market.history.s01[-1]=100.096
	var raw_total := 0.0
	for stock_row in broken.market.rows.values(): raw_total+=float(stock_row.price)
	broken.market.index=int(raw_total*10.0)
	reject(broken,"non-cent price must not load then normalize into invalid market index")
	print("Company save checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
