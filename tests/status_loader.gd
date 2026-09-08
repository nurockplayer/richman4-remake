extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Status = preload("res://tests/fixtures/status_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Base = preload("res://tests/fixtures/original_map_fixture.gd")
const Companies = preload("res://tests/fixtures/company_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)
func _initialize() -> void:
	var raw: Dictionary = Base.make()
	raw.nodes[1].type_and_idx=8001
	raw.nodes[1].event_code=0
	raw.nodes[5].type_and_idx=6001
	raw.nodes[5].event_code=0
	raw.companies=Companies.definition().companies.duplicate(true)
	raw.stock_rows=Companies.stock_rows()
	var result: Dictionary = Maps.normalize_map(raw,true)
	expect(result.get("ok",false),"complete status source fixture loads")
	if not result.get("ok",false): quit(1);return
	expect(result.definition.get("supports_original_statuses",false),"company map with hospital and prison advertises status capability")
	expect(result.definition.board[0].name=="監獄" and result.definition.board[1].name=="醫院","source facility names retained")
	var missing_hospital: Dictionary = raw.duplicate(true)
	missing_hospital.nodes[1].type_and_idx=0
	result=Maps.normalize_map(missing_hospital,true)
	expect(result.get("ok",false) and not result.definition.get("supports_original_statuses",false),"missing hospital keeps company-only capability")
	var missing_prison: Dictionary = raw.duplicate(true)
	missing_prison.nodes[0].type_and_idx=0
	result=Maps.normalize_map(missing_prison,true)
	expect(result.get("ok",false) and not result.definition.get("supports_original_statuses",false),"missing prison keeps company-only capability")
	var legacy: Dictionary = raw.duplicate(true)
	legacy.erase("stock_rows")
	result=Maps.normalize_map(legacy,true)
	expect(result.get("ok",false) and not result.definition.get("supports_original_statuses",false),"legacy catalog cannot claim status capability")
	var options := {"original_facilities":true,"original_gods":true,"original_companies":true,"original_statuses":true,"start_date":{"year":1998,"month":1,"day":1}}
	expect(Game.new_game_on_board(42,4,Status.definition(),options)!=null,"complete direct status definition starts")
	for marker in ["yes",1,[],{}]:
		var invalid := Status.definition()
		invalid.supports_original_statuses=marker
		expect(not Game.validate_board_definition(invalid,true).get("ok",false),"definition rejects malformed status marker")
		expect(Game.new_game_on_board(42,4,invalid,options)==null,"constructor rejects non-boolean status capability")
	for node in [0,4]:
		var invalid := Status.definition()
		invalid.board[node].type_and_idx=8003
		expect(Game.new_game_on_board(42,4,invalid,options)==null,"constructor rejects claimed status capability missing anchor")
	print("Status loader checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
