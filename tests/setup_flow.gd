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
	_test_calendar_last_day_is_playable()
	_test_calendar_overflow_overrides_deadline_for_zero_wealth()
	_test_deadline_and_wealth_settlement()
	_test_zero_wealth_does_not_force_setup_winner()
	_test_setup_terminal_and_month_marker_validation()
	_test_setup_save_round_trip()
	_test_graph_setup_constructor()
	_test_setup_ai_completion()
	_test_deposit_backed_charges_keep_bank_cash_saveable()
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


func _test_calendar_last_day_is_playable() -> void:
	var boundary: Object = _new_setup(11, 2, {"start_date": {"year": 9999, "month": 12, "day": 30}})
	_expect(boundary != null, "day before maximum supported date starts")
	if boundary == null:
		return
	_end_setup_round(boundary)
	_expect_equal(boundary.state["phase"], "await_roll", "maximum supported date remains playable for one full day")
	_expect_equal(boundary.state["date"], {"year": 9999, "month": 12, "day": 31}, "last supported date is reached before terminal settlement")
	_expect_equal(boundary.state["elapsed"], 1, "last supported date advances elapsed exactly once")
	_expect(bool(GameState.validate_save(boundary.to_dict()).get("ok", false)), "last supported date save remains valid while playable")
	_end_setup_round(boundary)
	_expect_equal(boundary.state["phase"], "game_over", "calendar boundary settles only when the next date cannot be represented")
	_expect_equal(boundary.state["day"], 2, "calendar boundary keeps the last playable day")
	_expect_equal(boundary.state["elapsed"], 1, "calendar boundary does not add an unrepresentable day")
	_expect_equal(boundary.state["last_event"].get("reason", ""), "calendar_limit", "calendar boundary records implementation limit")


func _test_calendar_overflow_overrides_deadline_for_zero_wealth() -> void:
	var game: Object = _new_setup(19, 2, {"start_date": {"year": 9999, "month": 12, "day": 1}, "day_limit": 30})
	_expect(game != null, "calendar overflow deadline fixture starts")
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
	game.state["current_player"] = game.state["players"].size() - 1
	game.state["phase"] = "await_action"
	game._set_action_options(int(game.state["current_player"]))
	var pre_terminal: Dictionary = game.to_dict()
	_expect(bool(GameState.validate_save(pre_terminal).get("ok", false)), "max-date deadline state with zero wealth is valid before overflow")
	var result: Dictionary = game.end_turn()
	_expect(bool(result.get("ok", false)), "calendar overflow end_turn succeeds")
	_expect_equal(game.state["phase"], "game_over", "calendar overflow terminates despite elapsed deadline")
	_expect_equal(game.state["winner"], -1, "calendar overflow keeps winnerless zero-wealth result")
	_expect_equal(game.state["last_event"].get("reason", ""), "calendar_limit", "calendar overflow records calendar reason over deadline")
	_expect_equal(game.state["last_event"].get("calendar_boundary", false), true, "calendar overflow records boundary marker")
	var saved: Dictionary = game.to_dict()
	_expect(bool(GameState.validate_save(saved).get("ok", false)), "winnerless calendar terminal save validates")
	var restored: Object = GameState.from_dict(saved)
	_expect(restored != null, "winnerless calendar terminal save reloads")
	if restored != null:
		_expect_equal(restored.to_json(), game.to_json(), "winnerless calendar terminal save round trips exactly")


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


func _test_setup_terminal_and_month_marker_validation() -> void:
	var ordinary: Object = _new_setup(12, 2, {"start_date": {"year": 1998, "month": 1, "day": 1}})
	_expect(ordinary != null, "ordinary v3 validation fixture starts")
	if ordinary == null:
		return
	var ordinary_game_over: Dictionary = ordinary.to_dict()
	ordinary_game_over["phase"] = "game_over"
	ordinary_game_over["winner"] = -1
	ordinary_game_over["action_options"] = []
	ordinary_game_over["last_event"] = {"type": "game_over", "day": 1, "turn": 1, "winner": -1,
		"reason": "calendar_limit", "elapsed": 0, "wealth_target": 0, "winner_wealth": 0, "calendar_boundary": true}
	_expect(not bool(GameState.validate_save(ordinary_game_over).get("ok", false)), "v3 no-winner game over requires the actual calendar boundary")

	var calendar_terminal: Object = _new_setup(13, 2, {"start_date": {"year": 9999, "month": 12, "day": 31}})
	_expect(calendar_terminal != null, "calendar terminal validation fixture starts")
	if calendar_terminal != null:
		_end_setup_round(calendar_terminal)
		var valid_terminal: Dictionary = calendar_terminal.to_dict()
		_expect(bool(GameState.validate_save(valid_terminal).get("ok", false)), "actual calendar terminal save validates")
		var missing_marker: Dictionary = valid_terminal.duplicate(true)
		missing_marker["winner"] = -1
		missing_marker["last_event"].erase("calendar_boundary")
		_expect(not bool(GameState.validate_save(missing_marker).get("ok", false)), "calendar terminal save requires its boundary event marker")
		var ordinary_date: Dictionary = valid_terminal.duplicate(true)
		ordinary_date["winner"] = -1
		ordinary_date["date"] = {"year": 9999, "month": 12, "day": 30}
		_expect(not bool(GameState.validate_save(ordinary_date).get("ok", false)), "calendar marker on a non-final date is rejected")

	var deadline_boundary: Object = _new_setup(14, 2, {"start_date": {"year": 9999, "month": 12, "day": 1}, "day_limit": 30})
	_expect(deadline_boundary != null, "deadline boundary validation fixture starts")
	if deadline_boundary != null:
		deadline_boundary.state["day"] = 31
		deadline_boundary.state["phase"] = "game_over"
		deadline_boundary.state["winner"] = -1
		deadline_boundary.state["action_options"] = []
		deadline_boundary._sync_state()
		deadline_boundary.state["last_event"] = {"type": "game_over", "day": 31, "turn": 31, "winner": -1,
			"reason": "calendar_limit", "elapsed": 30, "wealth_target": 0, "winner_wealth": 0, "calendar_boundary": true}
		_expect(bool(GameState.validate_save(deadline_boundary.to_dict()).get("ok", false)), "calendar marker remains valid when deadline has also elapsed")

	var future_marker: Object = _new_setup(15, 2, {"start_date": {"year": 1998, "month": 1, "day": 31}})
	_expect(future_marker != null, "month marker validation fixture starts")
	if future_marker != null:
		_end_setup_round(future_marker)
		var crossed: Dictionary = future_marker.to_dict()
		_expect_equal(crossed["date"], {"year": 1998, "month": 2, "day": 1}, "month marker fixture crosses into a new month")
		_expect_equal(crossed["last_settled_month"], {"year": 1998, "month": 1}, "ordinary month crossing records the previous month")
		var current_marker: Dictionary = crossed.duplicate(true)
		current_marker["last_settled_month"] = {"year": 1998, "month": 2}
		_expect(not bool(GameState.validate_save(current_marker).get("ok", false)), "current-month settlement marker is rejected")
		var future_marker_save: Dictionary = crossed.duplicate(true)
		future_marker_save["last_settled_month"] = {"year": 1999, "month": 1}
		_expect(not bool(GameState.validate_save(future_marker_save).get("ok", false)), "future settlement marker is rejected")

	var deadline_day_one: Object = _new_setup(16, 2, {"start_date": {"year": 1998, "month": 12, "day": 2}, "day_limit": 30})
	_expect(deadline_day_one != null, "day-one deadline fixture starts")
	if deadline_day_one != null:
		var deadline_deposits: Array = [deadline_day_one.state["players"][0]["deposit"], deadline_day_one.state["players"][1]["deposit"]]
		deadline_day_one.state["day"] = 30
		deadline_day_one._sync_state()
		_end_setup_round(deadline_day_one)
		_expect_equal(deadline_day_one.state["phase"], "game_over", "deadline settles before month interest on day one")
		_expect_equal(deadline_day_one.state["date"], {"year": 1999, "month": 1, "day": 1}, "deadline fixture reaches the first day of the next month")
		_expect_equal(deadline_day_one.state["last_settled_month"], {}, "deadline ending on day one does not settle the previous month")
		_expect_equal([deadline_day_one.state["players"][0]["deposit"], deadline_day_one.state["players"][1]["deposit"]], deadline_deposits, "deadline ending on day one does not pay month interest")
		_expect(bool(GameState.validate_save(deadline_day_one.to_dict()).get("ok", false)), "day-one deadline save validates with unsettled marker")

	var target_day_one: Object = _new_setup(17, 2, {"start_date": {"year": 1998, "month": 12, "day": 2}, "wealth_multiplier": 3})
	_expect(target_day_one != null, "day-one wealth target fixture starts")
	if target_day_one != null:
		var target_deposit_before: int = int(target_day_one.state["players"][0]["deposit"])
		target_day_one.state["players"][0]["cash"] = 600000
		target_day_one.state["players"][0]["deposit"] = 0
		target_day_one.state["bank"]["deposits"] -= target_deposit_before
		target_day_one.state["day"] = 30
		target_day_one._sync_state()
		_end_setup_round(target_day_one)
		_expect_equal(target_day_one.state["phase"], "game_over", "wealth target settles before month interest on day one")
		_expect_equal(target_day_one.state["date"], {"year": 1999, "month": 1, "day": 1}, "wealth target fixture reaches the first day of the next month")
		_expect_equal(target_day_one.state["last_settled_month"], {}, "wealth target ending on day one does not settle the previous month")
		_expect_equal(target_day_one.state["players"][1]["deposit"], 120000, "wealth target ending on day one leaves the other deposit unsettled")
		_expect(bool(GameState.validate_save(target_day_one.to_dict()).get("ok", false)), "day-one wealth target save validates with unsettled marker")

	var bankruptcy_day_one: Object = _new_setup(18, 3, {"start_date": {"year": 1998, "month": 12, "day": 2}})
	_expect(bankruptcy_day_one != null, "ordinary bankruptcy day-one fixture starts")
	if bankruptcy_day_one != null:
		var bankruptcy_deposit_before: int = int(bankruptcy_day_one.state["players"][0]["deposit"])
		var bankrupt_player_deposit: int = int(bankruptcy_day_one.state["players"][1]["deposit"])
		bankruptcy_day_one.state["players"][1]["cash"] = 0
		bankruptcy_day_one.state["players"][1]["deposit"] = 0
		bankruptcy_day_one.state["bank"]["deposits"] -= bankrupt_player_deposit
		bankruptcy_day_one._declare_bankruptcy(1, 0, 1, "test")
		bankruptcy_day_one.state["day"] = 30
		bankruptcy_day_one._sync_state()
		_end_setup_round(bankruptcy_day_one)
		_expect_equal(bankruptcy_day_one.state["date"], {"year": 1999, "month": 1, "day": 1}, "ordinary bankruptcy fixture reaches the first day of the next month")
		_expect_equal(bankruptcy_day_one.state["last_settled_month"], {"year": 1998, "month": 12}, "ordinary bankruptcy day one settles the previous month")
		_expect_equal(bankruptcy_day_one.state["players"][0]["deposit"], int(float(bankruptcy_deposit_before) * 1.1), "ordinary bankruptcy day one pays the previous month interest")
		var bankruptcy_validation: Dictionary = GameState.validate_save(bankruptcy_day_one.to_dict())
		_expect(bool(bankruptcy_validation.get("ok", false)), "ordinary bankruptcy day-one save validates: %s" % str(bankruptcy_validation.get("errors", [])))


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


func _test_deposit_backed_charges_keep_bank_cash_saveable() -> void:
	for seed_value in [3, 5, 6]:
		var game: Object = _new_setup(seed_value, 4, {"start_date": {"year": 1998, "month": 1, "day": 1}, "initial_fund": 300000, "day_limit": 730})
		_expect(game != null, "deposit-backed charge fixture starts for seed %d" % seed_value)
		if game == null:
			continue
		var result: Dictionary = game.run_ai_match(4000)
		_expect(bool(result.get("ok", false)), "deposit-backed charge match completes for seed %d" % seed_value)
		_expect(int(game.state["bank"].get("cash", -1)) >= 0, "bank cash stays non-negative after deposit-backed charges for seed %d" % seed_value)
		var saved: Dictionary = game.to_dict()
		_expect(bool(GameState.validate_save(saved).get("ok", false)), "deposit-backed charge save validates for seed %d" % seed_value)
		if seed_value == 6:
			_expect_equal(game.state["elapsed"], 730, "seed 6 completes the full 730-day setup match")
			var payload: Variant = JSON.parse_string(game.to_json())
			var restored: Object = GameState.from_dict(payload) if payload is Dictionary else null
			_expect(restored != null, "seed 6 final setup save reloads")
			if restored != null:
				_expect_equal(restored.to_json(), game.to_json(), "seed 6 final setup save round-trips exactly")


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
