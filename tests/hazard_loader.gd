extends SceneTree
const Maps=preload("res://game/content/original_maps.gd")
const Base=preload("res://tests/fixtures/original_map_fixture.gd")
const Companies=preload("res://tests/fixtures/company_fixture.gd")
var checks:=0
var failures:=0
func expect(condition: bool,message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)
func _initialize() -> void:
	var raw:=Base.make()
	raw.nodes[1].type_and_idx=8001
	raw.nodes[1].event_code=0
	raw.nodes[5].type_and_idx=6001
	raw.nodes[5].event_code=0
	raw.companies=Companies.definition().companies.duplicate(true)
	raw.stock_rows=Companies.stock_rows()
	var loaded:=Maps.normalize_map(raw,true)
	expect(loaded.get("ok",false),"complete synthetic source normalizes")
	if not loaded.get("ok",false): quit(1);return
	expect(loaded.definition.get("supports_original_hazards",false),"complete status source enables v9 road hazards")
	expect(typeof(loaded.definition.get("supports_original_hazards"))==TYPE_BOOL,"hazard capability is explicitly boolean")
	for node in [0,1]:
		var incomplete:=raw.duplicate(true)
		incomplete.nodes[node].type_and_idx=8003
		loaded=Maps.normalize_map(incomplete,true)
		expect(loaded.get("ok",false) and not loaded.definition.get("supports_original_hazards",false),"missing status anchor cannot offer road hazards")
	var legacy:=raw.duplicate(true)
	legacy.erase("stock_rows")
	loaded=Maps.normalize_map(legacy,true)
	expect(loaded.get("ok",false) and not loaded.definition.get("supports_original_hazards",false),"legacy catalog stays compatible without hazard capability")
	loaded=Maps.normalize_map(raw,false)
	expect(loaded.get("ok",false) and not loaded.definition.get("supports_original_hazards",false),"legacy facility mode cannot advertise hazards")
	print("Hazard loader checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
