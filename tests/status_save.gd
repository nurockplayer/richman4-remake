extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const StatusFixture = preload("res://tests/fixtures/status_fixture.gd")
const CompanyFixture = preload("res://tests/fixtures/company_fixture.gd")

var checks := 0
var failures := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func make_status_game(seed_value: int = 42) -> Object:
	return Game.new_game_on_board(seed_value, 4, StatusFixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"original_statuses": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})


func reject(data: Dictionary, message: String) -> void:
	var validation: Dictionary = Game.validate_save(data)
	expect(not bool(validation.get("ok", false)), message + " validation")
	expect(Game.from_dict(data) == null, message + " JSON restore")


func _initialize() -> void:
	var game := make_status_game()
	expect(game != null, "status save fixture starts")
	if game == null:
		_finish()
		return
	# Keep the save fixture free of source actor occupancy conflicts while the
	# status schema is exercised; actor synchronization is covered in flow.
	game.state["god_objects"] = []
	var player: Dictionary = game.state.players[0]
	player["hospital_days"] = 3
	player["prison_days"] = 0
	player["position"] = game._status_node_index("hospital")
	player["previous_position"] = -1
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game._set_action_options(0)
	var saved: Dictionary = game.to_dict()
	expect(bool(Game.validate_save(saved).get("ok", false)), "active status save validates")
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null, "active status save restores through JSON")
	if restored != null:
		expect(restored.to_json() == game.to_json(), "status save JSON round trip is exact")
	expect(saved.has("original_statuses") and saved.players[0].has("prison_days"), "status save persists marker and prison counter")

	var broken: Dictionary = saved.duplicate(true)
	broken.erase("original_statuses")
	reject(broken, "missing original_statuses marker")
	broken = saved.duplicate(true)
	broken.players[0].erase("prison_days")
	reject(broken, "missing prison_days")
	broken = saved.duplicate(true)
	broken.original_statuses = false
	reject(broken, "false original_statuses marker")
	for parent_marker in ["original_facilities", "original_gods", "original_companies"]:
		broken = saved.duplicate(true)
		broken[parent_marker] = false
		reject(broken, "status save missing parent marker " + parent_marker)

	broken = saved.duplicate(true)
	broken.version = Game.COMPANY_SAVE_VERSION
	reject(broken, "status marker on v7 save")
	for bad_value in [129, -1, 0.5, "3", null, {}, []]:
		broken = saved.duplicate(true)
		broken.players[0].hospital_days = bad_value
		reject(broken, "invalid hospital_days value " + str(bad_value))
	for bad_value in [129, -1, 0.5, "3", null, {}, []]:
		broken = saved.duplicate(true)
		broken.players[0].prison_days = bad_value
		reject(broken, "invalid prison_days value " + str(bad_value))

	broken = saved.duplicate(true)
	broken.players[0].prison_days = 2
	reject(broken, "mutually exclusive hospital and prison status")
	broken = saved.duplicate(true)
	broken.players[0].position = game._status_node_index("prison")
	reject(broken, "hospital status at prison node")
	broken = saved.duplicate(true)
	broken.players[0].previous_position = 1
	reject(broken, "active status retains previous graph node")
	broken = saved.duplicate(true)
	broken.board[0].type_and_idx = 0
	reject(broken, "status save without hospital node")
	broken = saved.duplicate(true)
	broken.board[4].type_and_idx = 0
	reject(broken, "status save without prison node")
	broken = saved.duplicate(true)
	broken.board[0].type_and_idx = "8001"
	reject(broken, "status node type must be numeric")

	var terminal: Dictionary = saved.duplicate(true)
	terminal.players[0].hospital_days = 128
	terminal.players[0].position = game._status_node_index("hospital")
	terminal.players[0].previous_position = -1
	expect(bool(Game.validate_save(terminal).get("ok", false)), "terminal status marker at hospital node validates")

	var legacy_v7 := Game.new_game_on_board(42, 4, CompanyFixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	expect(legacy_v7 != null and int(legacy_v7.state.version) == Game.COMPANY_SAVE_VERSION, "company-only source remains v7")
	if legacy_v7 != null:
		var legacy_v7_saved: Dictionary = legacy_v7.to_dict()
		expect(not legacy_v7_saved.has("original_statuses"), "v7 save has no status marker")
		expect(not legacy_v7_saved.players[0].has("prison_days"), "v7 player has no prison counter")
		expect(bool(Game.validate_save(legacy_v7_saved).get("ok", false)), "v7 save remains valid")
		expect(Game.from_dict(JSON.parse_string(legacy_v7.to_json())) != null, "v7 save remains loadable")

	var legacy_v6 := Game.new_game_on_board(43, 2, StatusFixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	expect(legacy_v6 != null and int(legacy_v6.state.version) == Game.GODS_SAVE_VERSION, "facility and god source remains v6")
	if legacy_v6 != null:
		legacy_v6.state.players[0].hospital_days = 3
		var legacy_v6_saved: Dictionary = legacy_v6.to_dict()
		expect(bool(Game.validate_save(legacy_v6_saved).get("ok", false)), "v6 hospital save remains valid")
		legacy_v6.state.players[0].hospital_days = 4
		reject(legacy_v6.to_dict(), "v6 hospital counter remains capped at three")

	_finish()


func _finish() -> void:
	print("Status save checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
