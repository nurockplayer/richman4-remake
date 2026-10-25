extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Calendar = preload("res://game/core/game_calendar.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/auction_fixture.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_factory_and_source_dates()
	_test_purchase_and_expiry()
	_test_acquisition_boundaries()
	_test_auction_dates()
	_test_save_and_end_order()
	print("Land tenure checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _new_game(months: Variant = 1, date: Dictionary = {"year": 1998, "month": 1, "day": 1}) -> Object:
	var options: Dictionary = Fixture.new_game_options()
	options.start_date = date
	options.human_flags = [true, true, true, true]
	if months != null:
		options.land_tenure_months = months
	var game: Object = Game.new_game_on_board(120, 4, Fixture.definition(), options)
	return game


func _valid(game: Object, label: String) -> void:
	var result: Dictionary = Game.validate_save(game.to_dict())
	_expect(bool(result.ok), label + ": " + str(result.get("errors", [])))


func _buy(game: Object, player_id: int, node_id: int) -> bool:
	Fixture.prepare(game, player_id, node_id)
	_valid(game, "fixture is valid before public purchase")
	var result: Dictionary = game.choose_action("buy")
	_expect(bool(result.get("ok", false)), "public buy accepts the available property/facility")
	return bool(result.get("ok", false))


func _card(game: Object, player_id: int, node_id: int, card_id: String, target: int = -1) -> bool:
	Fixture.prepare(game, player_id, node_id)
	var grant: Dictionary = Inventory.grant_card(game.state.inventory_supply, game.state.players[player_id].cards, card_id)
	_expect(bool(grant.get("ok", false)), "finite supply stages " + card_id)
	game._set_action_options(player_id)
	_valid(game, "fixture is valid before public " + card_id)
	var params := {"card_id": card_id}
	if target >= 0:
		params.tile_id = target
	var result: Dictionary = game.choose_action("use_card", params)
	_expect(bool(result.get("ok", false)), "public card succeeds: " + card_id)
	return bool(result.get("ok", false))


func _advance_days(game: Object, days: int) -> void:
	for _day in range(days):
		for player_id in range(4):
			Fixture.prepare(game, player_id, 0)
			game.state.last_roll = []
			game.state.last_total = 0
			game.state.last_roll_total = 0
			var result: Dictionary = game.end_turn()
			if not bool(result.get("ok", false)):
				_expect(false, "public end_turn advances tenure calendar: " + str(result))
				return


func _test_factory_and_source_dates() -> void:
	var baseline: Object = _new_game(null)
	_expect(baseline != null, "existing full source factory baseline remains available")
	if baseline == null:
		return
	_expect(not baseline.state.has("land_tenure_months"), "omitted option preserves old top-level metadata")
	for tile in baseline.state.board:
		_expect(not tile.has("land_expiry"), "omitted option adds no board metadata")
	for months in [0, 1, 3, 6, 12, 24]:
		var game: Object = _new_game(months)
		_expect(game != null, "factory accepts original tenure choice " + str(months))
		if game == null:
			continue
		_expect(game.state.get("land_tenure_months", -1) == months, "explicit tenure setting is retained")
		_expect(game.state.rng_state_text == baseline.state.rng_state_text, "tenure initialization consumes no RNG")
		_valid(game, "fresh tenure save validates")
		if _buy(game, 0, 2):
			var expected: int = {0: 0, 1: 0x07ce0201, 3: 0x07ce0401, 6: 0x07ce0701, 12: 0x07cf0101, 24: 0x07d00101}[months]
			_expect(int(game.state.board[2].get("land_expiry", 0)) == expected, "purchase stores the source packed calendar expiry")
	for invalid in [-1, 2, 30, 1.5, "1", true, [], {}]:
		_expect(_new_game(invalid) == null, "invalid tenure option is rejected: " + str(invalid))
	for row in [
		[{"year": 1998, "month": 12, "day": 5}, 3, 0x07cf0305],
		[{"year": 2000, "month": 2, "day": 29}, 12, 0x07d1021d],
		[{"year": 1998, "month": 1, "day": 31}, 1, 0x07ce021f],
		[{"year": 9999, "month": 12, "day": 31}, 24, 0x27110c1f],
	]:
		var game: Object = _new_game(row[1], row[0])
		_expect(game != null, "source date boundary setup is admitted")
		if game != null and _buy(game, 0, 2):
			_expect(game.state.board[2].get("land_expiry", -1) == row[2], "source month arithmetic preserves day, including short-month tokens")
			_valid(game, "source packed expiry is save-valid without inventing a calendar clamp")
	var simple: Object = Game.new_game(120, 2, {"start_date": {"year": 1998, "month": 1, "day": 1}, "land_tenure_months": 1})
	_expect(simple != null and Game.validate_save(simple.to_dict()).ok, "non-graph setup factory accepts the same optional rule")


func _test_purchase_and_expiry() -> void:
	var game: Object = _new_game()
	_expect(game != null, "tenure expiry fixture starts through public factory")
	if game == null:
		return
	if not _buy(game, 0, 2) or not _buy(game, 1, 1):
		return
	Fixture.prepare(game, 0, 2)
	_expect(bool(game.choose_action("upgrade").ok), "residential building is upgraded before tenure ends")
	Fixture.prepare(game, 1, 1)
	_expect(bool(game.choose_action("build_facility", {"facility_type": 1}).ok), "facility is constructed before tenure ends")
	var level: int = game.state.board[2].building_level
	var facility_level: int = game.state.board[1].building_level
	_expect(game.state.board[1].land_expiry == game.state.board[6].land_expiry, "shared facility acquisition stores one consistent expiry")
	_advance_days(game, 30)
	_expect(game.state.date == {"year": 1998, "month": 1, "day": 31} and game.state.board[2].owner == 0, "land remains owned through the day before expiry")
	var saved: String = game.to_json()
	var restored: Object = Game.from_dict(JSON.parse_string(saved))
	_expect(restored != null, "save reloads immediately before expiry")
	_advance_days(game, 1)
	_expect(game.state.board[2].owner == -1 and game.state.board[2].land_expiry == 0, "residential tenure expires on the exact date")
	_expect(game.state.board[2].building_level == level, "expiry preserves residential improvements")
	for node_id in [1, 6]:
		_expect(game.state.board[node_id].owner == -1 and game.state.board[node_id].land_expiry == 0, "facility expiry updates every entrance")
		_expect(game.state.board[node_id].building_level == facility_level and game.state.board[node_id].facility_type == 1, "facility expiry preserves construction/type")
	_expect(not game.state.players[0].properties.has(2) and not game.state.players[1].properties.has(1), "expiry removes the correct canonical property references")
	_valid(game, "expired assets and recalculated values remain save-valid")
	if restored != null:
		_advance_days(restored, 1)
		_expect(restored.to_json() == game.to_json(), "expiry after reload preserves exact continuation and RNG")
	_expect(_buy(game, 2, 2), "expired improved land can be purchased again")
	_expect(game.state.board[2].land_expiry == 0x07ce0301 and game.state.board[2].building_level == level, "reacquisition creates a new term and preserves the building")
	var short_month: Object = _new_game(1, {"year": 1998, "month": 1, "day": 31})
	if short_month != null and _buy(short_month, 0, 2):
		_advance_days(short_month, 29)
		_expect(short_month.state.date == {"year": 1998, "month": 3, "day": 1} and short_month.state.board[2].owner == 0, "source invalid February-31 token does not falsely expire on another date")


func _test_acquisition_boundaries() -> void:
	var game: Object = _new_game()
	_expect(game != null, "transfer fixture starts through public factory")
	if game == null:
		return
	if not _buy(game, 0, 2) or not _buy(game, 0, 1):
		return
	_advance_days(game, 1)
	for node_id in [2, 1]:
		if _card(game, 1, node_id, "購地"):
			_expect(game.state.board[node_id].land_expiry == 0x07ce0202, "purchase card resets the acquired asset term")
	_expect(game.state.board[6].land_expiry == 0x07ce0202, "purchase card resets all facility entrances")
	if not _buy(game, 2, 3):
		return
	var source_expiry: int = game.state.board[2].land_expiry
	var target_expiry: int = game.state.board[3].land_expiry
	_advance_days(game, 1)
	if _card(game, 1, 2, "換地", 3):
		_expect(game.state.board[2].land_expiry == source_expiry and game.state.board[3].land_expiry == target_expiry, "swap ownership preserves each land's existing expiry")
	var before_god: int = game.state.board[2].land_expiry
	_expect(bool(game._occupy_with_land_god(3, game.state.board[2])), "existing god occupation seam transfers owned land")
	_expect(game.state.board[2].land_expiry == before_god, "land-god occupation preserves the existing term")
	_valid(game, "mixed acquisition paths retain validated ownership and expiry")


func _auction(game: Object, node_id: int) -> void:
	if not _card(game, 0, node_id, "拍賣"):
		return
	var pending: Dictionary = game.auction_response()
	_expect(not pending.is_empty(), "auction exposes an actual bid response")
	if pending.is_empty():
		return
	_expect(bool(game.choose_action("respond_auction", {"increment": 100, "cancel": false}).ok), "first participant bids")
	for _step in range(32):
		if game.auction_response().is_empty():
			return
		if not bool(game.choose_action("respond_auction", {"increment": 0, "cancel": true}).ok):
			break
	_expect(false, "auction completes after bounded withdrawals")


func _test_auction_dates() -> void:
	for node_id in [2, 1]:
		for owned in [false, true]:
			var game: Object = _new_game()
			_expect(game != null, "auction tenure fixture starts through public factory")
			if game == null:
				continue
			if owned and not _buy(game, 1, node_id):
				continue
			_advance_days(game, 1)
			_auction(game, node_id)
			_expect(game.state.board[node_id].owner >= 0, "auction assigns a winning owner")
			_expect(game.state.board[node_id].land_expiry == (0x07ce0201 if owned else 0x07ce0202), "auction preserves owned term and starts a term only for unowned land")
			_valid(game, "auction tenure result validates")


func _test_save_and_end_order() -> void:
	var game: Object = _new_game()
	_expect(game != null, "metadata rejection fixture starts through public factory")
	if game == null:
		return
	_buy(game, 0, 2)
	for bad in [-1, 2, "1", true, 1.5]:
		var data: Dictionary = game.to_dict()
		data.land_tenure_months = bad
		_expect(not Game.validate_save(data).ok and Game.from_dict(data) == null, "malformed tenure save setting is rejected")
	for bad in [-1, 1, true, "130941441", 0x07ce0201 + 0.5, 0x07ce0d01]:
		var data: Dictionary = game.to_dict()
		data.board[2].land_expiry = bad
		_expect(not Game.validate_save(data).ok, "malformed packed expiry is rejected")
	var missing: Dictionary = game.to_dict()
	missing.board[2].erase("land_expiry")
	_expect(not Game.validate_save(missing).ok, "enabled tenure requires complete board metadata")
	var grafted: Dictionary = game.to_dict()
	grafted.erase("land_tenure_months")
	_expect(not Game.validate_save(grafted).ok, "expiry cannot be grafted into an omitted-option old save")
	var non_land: Dictionary = game.to_dict()
	non_land.board[0].land_expiry = 0
	_expect(not Game.validate_save(non_land).ok, "non-land tiles cannot carry expiry metadata")
	var duplicate: Dictionary = game.to_dict()
	duplicate.board[6].land_expiry = 0x07ce0201
	_expect(not Game.validate_save(duplicate).ok, "shared facility expiry divergence is rejected")
	# A source 30-day game ends on Jan31 before the later land-expiry pass.
	var options: Dictionary = Fixture.new_game_options()
	options.human_flags = [true, true, true, true]
	options.land_tenure_months = 1
	options.day_limit = 30
	var terminal: Object = Game.new_game_on_board(120, 4, Fixture.definition(), options)
	if terminal == null:
		_expect(false, "deadline fixture constructs")
		return
	_buy(terminal, 0, 2)
	terminal.state.board[2].land_expiry = 0x07ce011f
	_advance_days(terminal, 30)
	_expect(terminal.state.phase == "game_over" and terminal.state.board[2].owner == 0, "source terminal settlement takes precedence over same-day tenure expiry")
	_valid(terminal, "terminal save may retain a same-day expiry that did not run")
