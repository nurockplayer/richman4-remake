extends RefCounted
const Base = preload("res://tests/fixtures/original_map_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")
static func stock_rows() -> Array:
	var rows: Array = []
	for i in range(12):
		rows.append({"index":i,"name":"股票 %d"%(i+1),"company_id":1 if i==0 else 0,"market_supply":5000 if i==0 else 10000,"turn_supply":0,"base_price":100.0,"previous_price":100.0,"price":100.0,"volatility":1.0,"momentum":0.0,"shock":0.0,"suspension":0,"event":0})
	return rows
static func definition() -> Dictionary:
	var raw: Dictionary = Base.make()
	raw.nodes[5].type_and_idx=6001
	raw.nodes[5].event_code=0
	var loaded: Dictionary = Maps.normalize_map(raw,true)
	if not loaded.get("ok",false): return {}
	var result: Dictionary = loaded.definition
	result.supports_original_companies=true
	result.stock_rows=stock_rows()
	result.companies=[{"id":1,"display_name":"測試企業","company_type":3,"stock_index":0,"stock_value":400000,"toll_fee":150,"monthly_profit":0,"cumulative_profit":0,"treasury":5000,"source_owner":0}]
	result.board[5].source_company_id=1
	result.board[5].company_node_index=5
	return result

static func construction_definition() -> Dictionary:
	var result := definition()
	result.companies[0].company_type=11
	for index in [1,4]:
		var tile: Dictionary = result.board[index]
		tile.erase("points")
		tile.source_status_bits=0
		tile.merge({"kind":"facility","name":"測試設施","type_and_idx":4001,"source_object_id":1,"event_code":0,"cost":1000,"land_price":1000,"upgrade_cost":300,"base_rent":0,"rent":0,"group":"facility:1","facility_type":0,"facility_state":0,"fee_by_level":[300,100,200,300,400,500],"facility_node_index":1},true)
	result.source.facilities=[{"id":1,"land_price":1000,"upgrade_cost":300,"reserved_hex":"6400c8002c019001f401"}]
	return result
