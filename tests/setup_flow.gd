extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_defaults_and_player_funds()
	_test_setup_option_validation()
	_test_calendar_and_month_boundary()
	_test_calendar_terminal_boundary()
	_test_deadline_and_wealth_settlement()
	_test_zero_wealth_does_not_force_setup_winner()
	_test_setup_save_round_trip()
	_test_graph_setup_constructor()
	_test_setup_ai_completion()
	_test_legacy_versions_remain_unchanged()
	print("Setup flow checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures else 0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _base_options(start_date: Dictionary = {"year": 1998, "month": 1, "day": 1}) -> Dictionary:
	return {"start_date": start_date}


func _new_setup(seed_value: int = 42, player_count: int = 2, options: Dictionary = {}) -> Object:
	var candidate: Variant = GameState.new_game(seed_value, player_count, options)
	return candidate if candidate is Object else null


func _end_setup_round(game: Object) -> void:
	var player_count: int = int(game.state.get("players", []).size())
	for _index in range(player_count):
		if game.state.get("phase", "") == "game_over":
			return
		game.state["phase"] = "await_action"
		var result: Dictionary = game.end_turn()
		_expect(bool(result.get("ok", false)), "setup end_turn advances")


func _test_defaults_and_player_funds() -> void:
	var game: Object = _new_setup(100, 3, _base_options())
	_expect(game != null, "start date creates setup game")
	if game == null:
		return
	_expect_equal(game.state["version"], 3, "setup save uses version three")
	_expect_equal(game.state["initial_fund"], 200000, "initial fund defaults to source default")
	_expect_equal(game.state["day_limit"], 0, "day limit defaults to unlimited")
	_expect_equal(game.state["wealth_multiplier"], 0, "wealth target defaults to disabled")
	_expect_equal(game.state["start_date"], {"year": 1998, "month": 1, "day": 1}, "start date is persisted")
	_expect_equal(game.state["date"], game.state["start_date"], "current date starts at selected date")
	_expect_equal(game.state["elapsed"], 0, "elapsed days start at zero")
	_expect_equal(game.state["character_ids"], [0, 1, 2], "character ids default to first players")
	var players: Array = game.state["players"]
	_expect_equal(players[0]["character_id"], 0, "human receives first character")
	_expect_equal(players[0]["name"], "約翰喬", "human name follows selected character")
	_expect_equal(players[0]["init_cash_ratio"], 50, "human source cash ratio is fifty percent")
	_expect_equal(players[0]["cash"], 100000, "human starts with half cash")
	_expect_equal(players[0]["deposit"], 100000, "human starts with half deposit")
	_expect_equal(players[1]["init_cash_ratio"], 40, "character one source cash ratio is preserved")
	_expect_equal(players[1]["cash"], 80000, "AI cash follows character ratio")
	_expect_equal(players[1]["deposit"], 120000, "AI deposit is the unspent opening fund")
	_expect_equal(players[2]["init_cash_ratio"], 70, "character two source cash ratio is preserved")
	_expect_equal(players[2]["cash"], 140000, "second AI cash follows character ratio")
	_expect_equal(players[2]["deposit"], 60000, "second AI deposit follows character ratio")
	_expect_equal(game.state["bank"]["deposits"], 280000, "bank deposit liability sums all opening deposits")
	_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "new setup save validates")


func _test_setup_option_validation() -> void:
	_expect(_new_setup(1, 2, {"initial_fund": 200000}) == null, "nonempty setup requires start date")
	var valid: Dictionary = _base_options()
	valid["initial_fund"] = 300000
	valid["day_limit"] = 730
	valid["wealth_multiplier"] = 100
	valid["character_ids"] = [11, 0]
	var game: Object = _new_setup(1, 2, valid)
	_expect(game != null, "all source setup choices are accepted")
	if game != null:
		_expect_equal(game.state["initial_fund"], 300000, "selected opening fund is persisted")
		_expect_equal(game.state["players"][0]["cash"], 150000, "selected human opening cash is half")
		_expect_equal(game.state["players"][1]["cash"], 150000, "selected AI opening ratio is applied")
	var json_number_game: Object = _new_setup(3, 2, {"start_date": {"year": 2000.0, "month": 2.0, "day": 29.0}})
	_expect(json_number_game != null, "integral JSON date numbers are accepted")
	if json_number_game != null:
		_expect_equal(json_number_game.state["start_date"], {"year": 2000, "month": 2, "day": 29}, "setup date numbers are canonicalized")
	for invalid in [
		{"start_date": {"year": 1998, "month": 1, "day": 1}, "unknown": true},
		{"start_date": {"year": 1998, "month": 1, "day": 1}, "initial_fund": 1},
		{"start_date": {"year": 1998, "month": 1, "day": 1}, "day_limit": 1},
		{"start_date": {"year": 1998, "month": 1, "day": 1, "extra": 1}},
		{"start_date": {"year": 1998, "month": 2, "day": 29}},
		{"start_date": {"year": "2063", "month": 1, "day": 1}},
		{"start_date": {"year": 2063, "month": 1, "day": "1"}},
		{"start_date": {"year": 2063, "month": 1, "day": true}},
		{"start_date": {"year": 1998, "month": 1, "day": 1}, "character_ids": [0, 0]},
		{"start_date": {"year": 1998, "month": 1, "day": 1}, "character_ids": [0, 12]},
		{"start_date": {"year": 1998, "month": 1, "day": 1}, "character_ids": [0]},
	]:
		_expect(_new_setup(2, 2, invalid) == null, "invalid setup options are rejected: " + str(invalid))


func _test_calendar_and_month_boundary() -> void:
	var options: Dictionary = {
		"start_date": {"year": 1998, "month": 1, "day": 31},
		"character_ids": [0, 1],
	}
	var game: Object = _new_setup(5, 2, options)
	_expect(game != null, "month boundary fixture starts")
	if game == null:
		return
	_expect_equal(game.state["weekday"], 6, "January 31 1998 is Saturday")
	_expect(bool(game.state["market"]["open"]), "market is open on Saturday")
	_expect(game.state["action_options"].has("buy_stock"), "stock actions are available while market is open")
	_end_setup_round(game)
	_expect_equal(game.state["day"], 2, "one full player round advances one day")
	_expect_equal(game.state["elapsed"], 1, "elapsed tracks days after setup")
	_expect_equal(game.state["date"], {"year": 1998, "month": 2, "day": 1}, "calendar crosses January boundary")
	_expect_equal(game.state["weekday"], 7, "calendar identifies Sunday")
	_expect(not bool(game.state["market"]["open"]), "market closes on Sunday")
	_expect(not game.state["action_options"].has("buy_stock"), "Sunday hides stock actions")
	_expect_equal(game.state["players"][0]["deposit"], 110000, "month end pays ten percent human interest")
	_expect_equal(game.state["players"][1]["deposit"], 132000, "month end pays ten percent AI interest")
	_expect_equal(game.state["bank"]["deposits"], 242000, "bank deposit liability includes monthly interest")
	var interest_events: int = 0
	for event in game.state["event_log"]:
		if event.get("type", "") == "monthly_interest":
			interest_events += 1
	_expect_equal(interest_events, 2, "one interest event is recorded per eligible player")
	var deposits_after: Array = [game.state["players"][0]["deposit"], game.state["players"][1]["deposit"]]
	game._apply_month_boundary()
	_expect_equal([game.state["players"][0]["deposit"], game.state["players"][1]["deposit"]], deposits_after, "repeating month settlement is idempotent")


func _test_calendar_terminal_boundary() -> void:
	var boundary: Object = _new_setup(9, 2, {"start_date": {"year": 9999, "month": 12, "day": 31}})
	_expect(boundary != null, "maximum supported date starts")
	if boundary == null:
		return
	_end_setup_round(boundary)
	_expect_equal(boundary.state["phase"], "game_over", "calendar boundary settles the setup game")
	_expect_equal(boundary.state["day"], 1, "calendar boundary does not advance to an unrepresentable day")
	_expect_equal(boundary.state["elapsed"], 0, "calendar boundary keeps elapsed invariant")
	_expect_equal(boundary.state["date"], {"year": 9999, "month": 12, "day": 31}, "calendar boundary preserves last date")
	_expect_equal(boundary.state["last_event"].get("reason", ""), "calendar_limit", "calendar boundary records implementation limit")
	_expect(bool(GameState.validate_save(boundary.to_dict()).get("ok", false)), "calendar boundary save remains valid")


func _test_deadline_and_wealth_settlement() -> void:
	var deadline_options: Dictionary = {"start_date": {"year": 1998, "month": 1, "day": 1}, "day_limit": 30}
	var deadline: Object = _new_setup(7, 2, deadline_options)
	_expect(deadline != null, "deadline fixture starts")
	if deadline != null:
		deadline.state["day"] = 30
		deadline._sync_state()
		_end_setup_round(deadline)
		_expect_equal(deadline.state["phase"], "game_over", "deadline ends setup game")
		_expect_equal(deadline.state["elapsed"], 30, "deadline uses elapsed days")
		_expect_equal(deadline.state["winner"], 0, "deadline tie keeps first player")
		_expect_equal(deadline.state["last_event"]["reason"], "day_limit", "deadline reason is recorded")

	var target_options: Dictionary = {"start_date": {"year": 1998, "month": 1, "day": 1}, "wealth_multiplier": 3}
	var target: Object = _new_setup(8, 2, target_options)
	_expect(target != null, "wealth target fixture starts")
	if target != null:
		var before: int = int(target.state["players"][0]["deposit"])
		target.state["players"][0]["cash"] = 600000
		target.state["players"][0]["deposit"] = 0
		target.state["bank"]["deposits"] -= before
		_end_setup_round(target)
		_expect_equal(target.state["phase"], "game_over", "wealth target ends setup game")
		_expect_equal(target.state["winner"], 0, "wealth target chooses qualifying player")
		_expect_equal(target.state["last_event"]["reason"], "wealth_target", "wealth target reason is recorded")
		_expect_equal(target.state["last_event"]["wealth_target"], 600000, "wealth target is initial fund times multiplier")
		_expect_equal(target.get_player_wealth(0), 600000, "wealth helper includes cash")


func _test_zero_wealth_does_not_force_setup_winner() -> void:
	var game: Object = _new_setup(10, 2, {"start_date": {"year": 1998, "month": 1, "day": 1}, "day_limit": 30})
	_expect(game != null, "zero wealth settlement fixture starts")
	if game == null:
		return
	for player in game.state["players"]:
		player["cash"] = 0
		player["deposit"] = 0
		player["loan"] = 0
		player["properties"] = []
		player["property_values"] = 0
		player["stocks"] = {"tech": 0, "transport": 0, "energy": 0}
	game.state["bank"]["deposits"] = 0
	game.state["day"] = 31
	game._sync_state()
	_expect(not game._check_setup_end_conditions(), "zero wealth deadline keeps the setup game running")
	_expect_equal(game.state["phase"], "await_roll", "zero wealth deadline does not enter game over")
	_expect_equal(game.state["winner"], -1, "zero wealth setup settlement has no winner")
	_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "zero wealth setup state remains saveable")


func _test_setup_save_round_trip() -> void:
	var game: Object = _new_setup(99, 2, {"start_date": {"year": 1999, "month": 12, "day": 31}, "initial_fund": 100000, "character_ids": [10, 11]})
	_expect(game != null, "save fixture starts")
	if game == null:
		return
	_end_setup_round(game)
	var saved: Dictionary = game.to_dict()
	_expect(bool(GameState.validate_save(saved).get("ok", false)), "setup save after date advance validates")
	var restored: Object = GameState.from_dict(saved)
	_expect(restored != null, "setup save restores")
	if restored != null:
		_expect_equal(restored.to_json(), game.to_json(), "setup save round trip is exact")
		_expect_equal(restored.state["date"], {"year": 2000, "month": 1, "day": 1}, "restored date crosses year boundary")
		_expect_equal(restored.state["last_settled_month"], {"year": 1999, "month": 12}, "restored month settlement marker persists")
	var bad_date: Dictionary = saved.duplicate(true)
	bad_date["date"]["day"] = 2
	_expect(not bool(GameState.validate_save(bad_date).get("ok", false)), "tampered setup date is rejected")
	var bad_character: Dictionary = saved.duplicate(true)
	bad_character["players"][1]["character_id"] = 0
	_expect(not bool(GameState.validate_save(bad_character).get("ok", false)), "tampered setup character is rejected")
	var bad_name: Dictionary = saved.duplicate(true)
	bad_name["players"][0]["name"] = "玩家 1"
	_expect(not bool(GameState.validate_save(bad_name).get("ok", false)), "tampered setup character name is rejected")
	var bad_deposits: Dictionary = saved.duplicate(true)
	bad_deposits["bank"]["deposits"] += 1
	_expect(not bool(GameState.validate_save(bad_deposits).get("ok", false)), "tampered setup bank deposits are rejected")

	var json_payload: Variant = JSON.parse_string(game.to_json())
	_expect(json_payload is Dictionary, "setup save parses through the JSON API")
	var json_restored: Object = GameState.from_dict(json_payload) if json_payload is Dictionary else null
	_expect(json_restored != null, "setup save reloads after JSON parsing")
	if json_restored != null:
		_expect_equal(json_restored.to_json(), game.to_json(), "JSON save reload preserves setup state")

	var numeric_game: Object = _new_setup(100, 2, {"start_date": {"year": 2063, "month": 12, "day": 31}})
	_expect(numeric_game != null, "numeric date fixture starts")
	if numeric_game != null:
		_end_setup_round(numeric_game)
		var numeric_payload: Variant = JSON.parse_string(numeric_game.to_json())
		_expect(numeric_payload is Dictionary, "numeric date save parses through JSON")
		if numeric_payload is Dictionary:
			var float_payload: Dictionary = numeric_payload.duplicate(true)
			for date_key in ["start_date", "date"]:
				var date_value: Dictionary = float_payload[date_key]
				for field in ["year", "month", "day"]:
					date_value[field] = float(date_value[field])
			var float_restored: Object = GameState.from_dict(float_payload)
			_expect(float_restored != null, "integral float dates reload after JSON parsing")
			if float_restored != null:
				_expect_equal(float_restored.state["date"], {"year": 2064, "month": 1, "day": 1}, "numeric date reload canonicalizes date fields")
		var ui_path := "user://richman4_save.json"
		_expect(numeric_game.save_to_path(ui_path), "UI save path accepts setup JSON")
		var ui_path_restored: Object = GameState.load_from_path(ui_path)
		_expect(ui_path_restored != null, "UI save path reloads setup JSON")


func _test_graph_setup_constructor() -> void:
	var normalized: Dictionary = Maps.normalize_map(Fixture.make())
	_expect(bool(normalized.get("ok", false)), "graph setup fixture normalizes")
	if not bool(normalized.get("ok", false)):
		return
	var game: Object = GameState.new_game_on_board(123, 2, normalized["definition"], {"start_date": {"year": 1998, "month": 1, "day": 1}, "day_limit": 30})
	_expect(game != null, "graph setup constructor accepts setup options")
	if game != null:
		_expect_equal(game.state["version"], 3, "graph setup uses version three")
		_expect_equal(game.state["board_mode"], "graph", "graph setup preserves graph mode")
		_expect_equal(game.state["players"][0]["position"], normalized["definition"]["start_position"], "graph setup preserves map start")
		_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "graph setup save validates")


func _test_setup_ai_completion() -> void:
	var game: Object = _new_setup(314159, 2, {"start_date": {"year": 1998, "month": 1, "day": 1}, "day_limit": 30})
	_expect(game != null, "AI setup fixture starts")
	if game == null:
		return
	var result: Dictionary = game.run_ai_match(100)
	_expect(bool(result.get("ok", false)), "AI setup match reaches a settlement")
	_expect_equal(game.state["phase"], "game_over", "AI setup match ends in game over")
	_expect(int(game.state["winner"]) >= 0 and int(game.state["winner"]) < 2, "AI setup settlement has a valid winner")
	_expect(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "AI setup final save validates")

	var long_game: Object = _new_setup(2, 4, {"start_date": {"year": 1998, "month": 1, "day": 1}, "initial_fund": 300000, "day_limit": 730})
	_expect(long_game != null, "730-day AI setup fixture starts")
	if long_game == null:
		return
	var long_result: Dictionary = long_game.run_ai_match(5000)
	_expect(bool(long_result.get("ok", false)), "730-day AI setup match reaches its deadline")
	_expect_equal(long_game.state["elapsed"], 730, "730-day AI setup match advances through all elapsed days")
	_expect(int(long_game.state["bank"].get("cash", -1)) >= 0, "730-day AI setup bank cash remains non-negative")
	_expect(bool(GameState.validate_save(long_game.to_dict()).get("ok", false)), "730-day AI setup final save validates")
	var long_json_payload: Variant = JSON.parse_string(long_game.to_json())
	var long_restored: Object = GameState.from_dict(long_json_payload) if long_json_payload is Dictionary else null
	_expect(long_restored != null, "730-day AI setup JSON reloads")
	if long_restored != null:
		_expect_equal(long_restored.to_json(), long_game.to_json(), "730-day AI setup JSON reload preserves final state")


func _test_legacy_versions_remain_unchanged() -> void:
	var legacy: Object = GameState.new_game(42, 2)
	_expect(legacy != null, "legacy constructor remains available")
	if legacy != null:
		_expect_equal(legacy.state["version"], 1, "legacy constructor keeps version one")
		_expect(not legacy.state.has("start_date"), "legacy state has no setup fields")
		_expect(bool(GameState.validate_save(legacy.to_dict()).get("ok", false)), "legacy v1 save validates")
		legacy.state["players"][0]["cash"] = 0
		legacy.state["players"][1]["cash"] = 0
		legacy._set_action_options(0)
		_expect_equal(legacy._richest_alive_player(), 0, "legacy richest-player behavior keeps zero-wealth fallback")
		var legacy_copy: Object = GameState.from_dict(legacy.to_dict())
		_expect(legacy_copy != null, "legacy v1 save restores")
		if legacy_copy != null:
			_expect_equal(legacy_copy.to_json(), legacy.to_json(), "legacy v1 round trip stays exact")
