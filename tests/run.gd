extends SceneTree

const GameState = preload("res://game/core/game_state.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_new_game_and_schema()
	_test_deterministic_rolls()
	_test_property_buy_and_five_levels()
	_test_rent_payment_uses_deposit_exactly()
	_test_bankruptcy_auction_and_game_over()
	_test_non_final_bankruptcy_advances_to_next_actor()
	_test_loan_bankruptcy_bookkeeping()
	_test_bank_and_monthly_interest()
	_test_vehicles_and_verified_cards()
	_test_save_load_and_validation()
	_test_ai_full_match()
	if _failures > 0:
		push_error("simulation tests failed: %d/%d checks" % [_failures, _checks])
		quit(1)
	else:
		print("simulation tests passed: %d checks" % _checks)
		quit(0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _complete_turn(game: GameState) -> void:
	if game.state.get("phase", "") == "await_roll":
		var roll_result: Dictionary = game.roll()
		_expect(bool(roll_result.get("ok", false)), "roll completes")
	if game.state.get("phase", "") == "await_action":
		var options: Array = game.state.get("action_options", [])
		if options.has("buy"):
			game.choose_action("buy")
		elif options.has("upgrade"):
			game.choose_action("upgrade")
		var end_result: Dictionary = game.end_turn()
		_expect(bool(end_result.get("ok", false)), "end turn completes")


func _test_new_game_and_schema() -> void:
	var game: GameState = GameState.new_game(2, 4)
	_expect(game != null, "new game accepts four players")
	_expect(GameState.new_game(2, 1) == null, "new game rejects one player")
	_expect(GameState.new_game(2, 5) == null, "new game rejects five players")
	var snapshot: Dictionary = game.get_snapshot()
	for key in ["version", "ruleset", "seed", "seed_text", "rng_state", "rng_state_text", "phase", "turn", "round", "day", "current_player", "winner", "board", "players", "bank", "market", "event_log", "action_options"]:
		_expect(snapshot.has(key), "snapshot has " + key)
	_expect_equal(snapshot["version"], 1, "save version is one")
	_expect_equal(snapshot["players"].size(), 4, "four players are initialized")
	_expect_equal(snapshot["board"].size(), 40, "forty board tiles are initialized")
	_expect_equal(snapshot["players"][0]["dice_count"], 1, "walking defaults to one die")
	_expect_equal(snapshot["players"][0]["vehicle"], "walking", "walking is the default vehicle")
	_expect_equal(snapshot["seed_text"], "2", "seed has a canonical text form")
	_expect(GameState.new_game(2147483648, 2) == null, "new game rejects seed above signed 32-bit range")
	_expect(GameState.new_game(-2147483649, 2) == null, "new game rejects seed below signed 32-bit range")
	_expect(not snapshot["event_log"].is_empty(), "new game records an event")
	_expect(snapshot["action_options"].has("buy_stock"), "pre-roll action options expose stock buying")
	_expect(snapshot["action_options"].has("sell_stock"), "pre-roll action options expose stock selling")
	_expect(bool(GameState.validate_save(snapshot).get("ok", false)), "pre-roll save with stock options validates")
	game.state["day"] = 7
	game._sync_state()
	game._set_action_options(0)
	_expect(game.state["action_options"].is_empty(), "Sunday pre-roll action options close stock trading")
	var Sunday_pre_roll_stock: Dictionary = game.choose_action("buy_stock", {"symbol": "tech", "quantity": 1})
	_expect(not bool(Sunday_pre_roll_stock.get("ok", false)), "Sunday pre-roll stock buying is rejected")
	var equal_roll_seed: int = -1
	for candidate_seed in range(1, 1000):
		var equal_candidate: GameState = GameState.new_game(candidate_seed, 2)
		equal_candidate.state["players"][0]["vehicles"]["car"] = true
		equal_candidate.state["players"][0]["vehicle"] = "car"
		equal_candidate.state["players"][0]["dice_count"] = 2
		var equal_result: Dictionary = equal_candidate.roll()
		if equal_result.get("dice", []).size() == 2 and equal_result["dice"][0] == equal_result["dice"][1]:
			equal_roll_seed = candidate_seed
			_expect_equal(equal_candidate.state["extra_roll"], false, "equal dice do not grant an extra turn")
			_expect_equal(equal_candidate.state["players"][0]["skip_turns"], 0, "equal dice do not impose a penalty")
			break
	_expect(equal_roll_seed >= 1, "a deterministic equal-dice fixture is available")


func _test_deterministic_rolls() -> void:
	var first: GameState = GameState.new_game(9981, 2)
	var second: GameState = GameState.new_game(9981, 2)
	for index in range(8):
		if first.state.get("phase", "") == "game_over" or second.state.get("phase", "") == "game_over":
			break
		var first_result: Dictionary = first.roll()
		var second_result: Dictionary = second.roll()
		_expect_equal(first_result["dice"], second_result["dice"], "same seed produces same roll %d" % index)
		_expect_equal(first.state["players"][0]["position"], second.state["players"][0]["position"], "same seed produces same position %d" % index)
		if first.state.get("phase", "") == "await_action":
			_complete_turn(first)
			_complete_turn(second)
	_expect_equal(first.to_json(), second.to_json(), "same seed remains deterministic after turns")


func _test_property_buy_and_five_levels() -> void:
	var game: GameState = GameState.new_game(101, 2)
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["players"][0]["position"] = 1
	game.state["property_action_used"] = false
	var buy_result: Dictionary = game.choose_action("buy")
	_expect(bool(buy_result["ok"]), "player can buy landed property")
	_expect_equal(game.state["board"][1]["owner"], 0, "property owner is recorded")
	_expect(game.state["players"][0]["properties"].has(1), "player property list is updated")
	var first_level_cash: int = int(game.state["players"][0]["cash"])
	var repeated_upgrade: Dictionary = game.choose_action("upgrade")
	_expect(not bool(repeated_upgrade.get("ok", false)), "second property action in one visit is rejected")
	for level in range(1, 6):
		_game_return_to_property(game, 0, 1)
		var upgrade_result: Dictionary = game.choose_action("upgrade")
		_expect(bool(upgrade_result["ok"]), "upgrade to level %d succeeds" % level)
		_expect_equal(game.state["board"][1]["building_level"], level, "building level %d is recorded" % level)
	_expect(game.state["players"][0]["cash"] < first_level_cash, "upgrades deduct cash")
	_game_return_to_property(game, 0, 1)
	var sixth_result: Dictionary = game.choose_action("upgrade")
	_expect(not bool(sixth_result["ok"]), "sixth property level is rejected")


func _game_return_to_property(game: GameState, player_id: int, property_id: int) -> void:
	# Return through ordinary end_turn/roll transitions. The fixture uses the
	# verified 停留 effect to make the final landing deterministic, while the
	# intervening player's turn still runs through the public API.
	game.state["players"][1]["cash"] = 100000000
	var safety: int = 0
	while int(game.state.get("current_player", -1)) != player_id and safety < 20:
		safety += 1
		if game.state.get("phase", "") == "await_roll":
			game.roll()
		elif game.state.get("phase", "") == "await_action":
			game.end_turn()
	_expect_equal(int(game.state.get("current_player", -1)), player_id, "ordinary turns return to player %d" % player_id)
	var player: Dictionary = game.state["players"][player_id]
	player["position"] = property_id
	player["stay_next"] = 1
	game.state["phase"] = "await_roll"
	var roll_result: Dictionary = game.roll()
	_expect(bool(roll_result.get("ok", false)), "ordinary roll starts a new property visit")
	_expect_equal(int(player["position"]), property_id, "stay fixture resolves the intended property visit")


func _test_rent_payment_uses_deposit_exactly() -> void:
	var game: GameState = GameState.new_game(202, 2)
	game.state["players"][0]["cash"] = 100
	game.state["players"][0]["deposit"] = 200
	game.state["players"][1]["cash"] = 0
	game.state["bank"]["cash"] = 1000000
	game._charge_amount(0, 250, 1, "rent_test")
	_expect_equal(game.state["players"][0]["cash"], 0, "rent consumes cash first")
	_expect_equal(game.state["players"][0]["deposit"], 50, "rent consumes only needed deposit")
	_expect_equal(game.state["players"][1]["cash"], 250, "creditor receives exact cash plus deposit payment")
	_expect(bool(game.state["players"][0]["alive"]), "player survives when cash plus deposit covers rent")


func _test_bankruptcy_auction_and_game_over() -> void:
	var game: GameState = GameState.new_game(303, 2)
	game.state["players"][1]["position"] = 1
	game.state["current_player"] = 1
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = false
	var buy_result: Dictionary = game.choose_action("buy")
	_expect(bool(buy_result["ok"]), "bankruptcy fixture buys property")
	game.state["players"][1]["cash"] = 0
	game.state["players"][1]["deposit"] = 0
	game._charge_amount(1, 100, 0, "rent_test")
	_expect(bool(game.state["players"][1]["bankrupt"]), "insolvent player is marked bankrupt")
	_expect(not bool(game.state["players"][1]["alive"]), "bankrupt player leaves active game")
	_expect_equal(game.state["board"][1]["owner"], 0, "rent bankruptcy transfers property to creditor provisionally")
	_expect_equal(game.state["bankruptcy_auctions"].size(), 1, "bankruptcy creates an auction record")
	_expect_equal(game.state["phase"], "game_over", "last surviving player ends game")
	_expect_equal(game.state["winner"], 0, "creditor wins after bankruptcy")
	var auction: Dictionary = game.state["bankruptcy_auctions"][0]
	_expect_equal(auction["provisional_resolution"], "transfer_to_creditor_or_release_to_bank", "auction fallback is explicitly provisional")


func _test_non_final_bankruptcy_advances_to_next_actor() -> void:
	var game: GameState = GameState.new_game(313, 3)
	var player_zero: Dictionary = game.state["players"][0]
	var bankrupt_player: Dictionary = game.state["players"][1]
	var next_player: Dictionary = game.state["players"][2]
	player_zero["properties"] = [1, 2, 3, 4, 5, 6]
	for tile_index in range(1, 7):
		var tile: Dictionary = game.state["board"][tile_index]
		tile["kind"] = "property"
		tile["owner"] = 0
		tile["group"] = "normal_flow_fixture"
		tile["cost"] = 1000
		tile["base_rent"] = 100
		tile["rent"] = 100
	bankrupt_player["position"] = 0
	bankrupt_player["cash"] = 0
	bankrupt_player["deposit"] = 0
	bankrupt_player["is_human"] = true
	bankrupt_player["is_ai"] = false
	next_player["is_human"] = false
	next_player["is_ai"] = true
	game.state["current_player"] = 1
	game.state["phase"] = "await_roll"
	var roll_result: Dictionary = game.roll()
	_expect(bool(roll_result.get("ok", false)), "normal roll accepts non-final bankruptcy fixture")
	_expect(bool(bankrupt_player["bankrupt"]), "normal landing marks middle player bankrupt")
	_expect(not bool(bankrupt_player["alive"]), "middle player leaves active roster")
	_expect_equal(game.state["current_player"], 2, "normal landing advances to next living player")
	_expect_equal(game.state["phase"], "await_roll", "next living player is ready to roll")
	_expect(bool(next_player["alive"]), "next player remains alive")
	var ai_result: Dictionary = game.run_ai_turn()
	_expect(bool(ai_result.get("ok", false)), "next AI actor can be scheduled immediately")


func _test_loan_bankruptcy_bookkeeping() -> void:
	var game: GameState = GameState.new_game(323, 3)
	game.state["bank_landing"] = true
	_expect(bool(game._take_loan(0, 1000).get("ok", false)), "first borrower can take a loan")
	_expect(bool(game._take_loan(1, 2000).get("ok", false)), "second borrower can take a loan")
	_expect(bool(game._take_loan(2, 3000).get("ok", false)), "third borrower can take a loan")
	_expect_equal(game.state["bank"]["loans"], 6000, "bank tracks all borrower principals")
	game.state["players"][0]["cash"] = 0
	game.state["players"][0]["deposit"] = 0
	game._charge_amount(0, 1, 1, "loan_bankruptcy_test")
	_expect(bool(game.state["players"][0]["bankrupt"]), "loan borrower can be declared bankrupt")
	_expect_equal(game.state["players"][0]["loan"], 0, "bankrupt borrower loan is cleared")
	_expect_equal(game.state["bank"]["loans"], 5000, "bank loan total removes only bankrupt borrower principal")
	_expect_equal(game.state["players"][1]["loan"], 2000, "other borrower loan survives bankruptcy")
	_expect_equal(game.state["players"][2]["loan"], 3000, "third borrower loan survives bankruptcy")
	game.state["players"][1]["cash"] = 500
	game.state["players"][1]["deposit"] = 1500
	game.state["bank"]["deposits"] = 1500
	game.state["players"][1]["loan_due_day"] = 1
	var bank_loans_before_repay: int = int(game.state["bank"]["loans"])
	game._repay_due_loan(1)
	_expect_equal(game.state["players"][1]["cash"], 0, "normal repayment uses cash and deposit exactly once")
	_expect_equal(game.state["players"][1]["deposit"], 0, "normal repayment clears the required deposit")
	_expect_equal(game.state["players"][1]["loan"], 0, "normal repayment clears borrower loan")
	_expect_equal(game.state["bank"]["loans"], bank_loans_before_repay - 2000, "normal repayment removes only its borrower principal")
	_expect_equal(game.state["bank"]["loans"], 3000, "third borrower principal remains after normal repayment")
	game._repay_due_loan(1)
	_expect_equal(game.state["bank"]["loans"], 3000, "repeating a settled repayment does not double deduct bank loans")


func _test_bank_and_monthly_interest() -> void:
	var game: GameState = GameState.new_game(404, 2)
	game.state["phase"] = "await_action"
	game.state["bank_access"] = true
	var before_bank_cash: int = int(game.state["bank"]["cash"])
	var deposit_result: Dictionary = game.choose_action("deposit", {"amount": 1000})
	_expect(bool(deposit_result["ok"]), "bank pass permits deposit")
	_expect_equal(game.state["players"][0]["deposit"], 1000, "deposit is recorded on player")
	_expect_equal(game.state["bank"]["cash"], before_bank_cash + 1000, "bank cash receives deposit")
	var withdraw_result: Dictionary = game.choose_action("withdraw", {"amount": 400})
	_expect(bool(withdraw_result["ok"]), "bank pass permits withdrawal")
	_expect_equal(game.state["players"][0]["deposit"], 600, "withdrawal reduces deposit")
	game.state["day"] = 29
	game._sync_state()
	game.state["players"][0]["deposit"] = 1000
	game.state["bank"]["deposits"] = 1000
	game._apply_month_boundary()
	_expect_equal(game.state["players"][0]["deposit"], 1000, "interest is deferred before the last day of month")
	game.state["day"] = 30
	game._sync_state()
	game._apply_month_boundary()
	_expect_equal(game.state["players"][0]["deposit"], 1100, "last day of month pays ten percent deposit interest")
	var settlement_event: Dictionary = game.state["event_log"].back()
	_expect_equal(settlement_event.get("type", ""), "month_end_settlement", "month settlement event uses end-of-month label")
	game.state["day"] = 31
	game._sync_state()
	game._apply_month_boundary()
	_expect_equal(game.state["players"][0]["deposit"], 1100, "interest is paid once per month")
	game.state["day"] = 7
	game._sync_state()
	game.state["phase"] = "await_action"
	var Sunday_stock_result: Dictionary = game.choose_action("buy_stock", {"symbol": "tech", "quantity": 1})
	_expect(not bool(Sunday_stock_result["ok"]), "stock trading is closed on Sunday")


func _test_vehicles_and_verified_cards() -> void:
	var game: GameState = GameState.new_game(505, 2)
	var free_car_result: Dictionary = game.set_vehicle("car")
	_expect(not bool(free_car_result["ok"]), "unowned car cannot be selected for free")
	game.state["phase"] = "await_action"
	var vehicle_result: Dictionary = game.choose_action("buy_vehicle", {"vehicle": "car"})
	_expect(bool(vehicle_result["ok"]), "car can be purchased")
	game.state["phase"] = "await_roll"
	var select_car_result: Dictionary = game.set_vehicle("car", 2)
	_expect(bool(select_car_result["ok"]), "owned car can select up to three dice")
	var roll_result: Dictionary = game.roll()
	_expect_equal(roll_result["dice"].size(), 2, "selected car dice count is used")
	game.state["phase"] = "await_action"
	game.state["players"][0]["cards"] = ["均富", "停留", "烏龜", "紅", "黑"]
	var malformed_cards_before: Array = game.state["players"][0]["cards"].duplicate(true)
	var malformed_turn_before: int = int(game.state["turn"])
	var malformed_current_before: int = int(game.state["current_player"])
	var missing_card_result: Dictionary = game.choose_action("use_card", {})
	_expect(not bool(missing_card_result.get("ok", false)), "missing card id is rejected")
	_expect_equal(game.state["players"][0]["cards"], malformed_cards_before, "missing card id does not consume a card")
	_expect_equal(game.state["turn"], malformed_turn_before, "missing card id does not advance turn")
	_expect_equal(game.state["current_player"], malformed_current_before, "missing card id does not change current player")
	var unknown_card_result: Dictionary = game.choose_action("use_card", {"card_id": "不存在"})
	_expect(not bool(unknown_card_result.get("ok", false)), "unknown card id is rejected")
	_expect_equal(game.state["players"][0]["cards"], malformed_cards_before, "unknown card id does not consume a card")
	var turtle_result: Dictionary = game.choose_action("use_card", {"card_id": "烏龜", "target_id": 1})
	_expect(bool(turtle_result["ok"]), "verified turtle card accepts target")
	_expect_equal(game.state["players"][1]["turtle_days"], 3, "turtle applies for three days")
	var red_result: Dictionary = game.choose_action("use_card", {"card_id": "紅", "symbol": "tech"})
	_expect(bool(red_result["ok"]), "verified red card accepts one company")
	_expect_equal(game.state["market"]["trends"]["tech"]["direction"], "up", "red sets one stock trend up")
	var stay_result: Dictionary = game.choose_action("use_card", {"card_id": "停留"})
	_expect(bool(stay_result["ok"]), "stay card defaults to self")
	_expect_equal(game.state["players"][0]["stay_next"], 1, "stay keeps next movement on the same tile")
	game.state["players"][0]["position"] = 1
	game.state["players"][0]["turtle_days"] = 1
	game.state["phase"] = "await_roll"
	var stay_roll: Dictionary = game.roll()
	_expect(bool(stay_roll["ok"]), "stay movement resolves")
	_expect_equal(game.state["players"][0]["position"], 1, "stay leaves player on the same tile")
	_expect_equal(stay_roll["total"], 1, "turtle movement is exactly one step")
	var ai_cards: GameState = GameState.new_game(506, 2)
	ai_cards.state["phase"] = "await_action"
	ai_cards.state["players"][0]["is_human"] = false
	ai_cards.state["players"][0]["is_ai"] = true
	ai_cards.state["players"][0]["cash"] = 1000
	ai_cards.state["players"][0]["cards"] = ["紅"]
	var ai_card_result: Dictionary = ai_cards.run_ai_turn()
	_expect(bool(ai_card_result.get("ok", false)), "AI turn handles targeted red card")
	_expect_equal(ai_cards.state["players"][0]["cards"].size(), 0, "AI consumes red card")
	_expect_equal(ai_cards.state["market"]["trends"]["tech"]["direction"], "up", "AI supplies red card stock target")


func _test_save_load_and_validation() -> void:
	var game: GameState = GameState.new_game(606, 2)
	game.roll()
	var saved: Dictionary = game.to_dict()
	var validation: Dictionary = GameState.validate_save(saved)
	_expect(bool(validation["ok"]), "fresh save validates")
	var restored: GameState = GameState.from_dict(saved)
	_expect(restored != null, "save restores")
	if restored != null:
		var first_next: Dictionary = game.end_turn()
		var second_next: Dictionary = restored.end_turn()
		_expect_equal(first_next["state"]["current_player"], second_next["state"]["current_player"], "restored turn identity matches")
		var first_roll: Dictionary = game.roll()
		var second_roll: Dictionary = restored.roll()
		_expect_equal(first_roll["dice"], second_roll["dice"], "restored RNG reproduces next roll")
	var bad_version: Dictionary = saved.duplicate(true)
	bad_version["version"] = 999
	_expect(not bool(GameState.validate_save(bad_version)["ok"]), "unsupported save version rejected")
	var bad_position: Dictionary = saved.duplicate(true)
	bad_position["players"][0]["position"] = 999
	_expect(not bool(GameState.validate_save(bad_position)["ok"]), "invalid player position rejected")
	var bad_tile: Dictionary = saved.duplicate(true)
	bad_tile["board"][1] = "not a tile"
	_expect(not bool(GameState.validate_save(bad_tile)["ok"]), "invalid board tile rejected")
	var bad_stock: Dictionary = saved.duplicate(true)
	bad_stock["players"][0]["stocks"]["tech"] = -1
	_expect(not bool(GameState.validate_save(bad_stock)["ok"]), "negative stock holding rejected")
	var bad_event_log: Dictionary = saved.duplicate(true)
	bad_event_log["event_log"] = "corrupted"
	_expect(not bool(GameState.validate_save(bad_event_log)["ok"]), "non-array event log rejected")
	var bad_action_options: Dictionary = saved.duplicate(true)
	bad_action_options.erase("action_options")
	_expect(not bool(GameState.validate_save(bad_action_options)["ok"]), "missing action options rejected")
	var bad_action_options_type: Dictionary = saved.duplicate(true)
	bad_action_options_type["action_options"] = "buy"
	_expect(not bool(GameState.validate_save(bad_action_options_type)["ok"]), "non-array action options rejected")
	var bad_current_player: Dictionary = saved.duplicate(true)
	bad_current_player["phase"] = "await_roll"
	bad_current_player["players"][0]["alive"] = false
	bad_current_player["players"][0]["bankrupt"] = true
	_expect(not bool(GameState.validate_save(bad_current_player)["ok"]), "dead current player rejected")
	var bad_control_flags: Dictionary = saved.duplicate(true)
	bad_control_flags["players"][0]["is_ai"] = true
	_expect(not bool(GameState.validate_save(bad_control_flags)["ok"]), "player control flags must be exclusive")
	var bad_alive_state: Dictionary = saved.duplicate(true)
	bad_alive_state["players"][0]["bankrupt"] = true
	_expect(not bool(GameState.validate_save(bad_alive_state)["ok"]), "alive player cannot be bankrupt")
	var bad_dice_count: Dictionary = saved.duplicate(true)
	bad_dice_count["players"][0]["dice_count"] = 0
	_expect(not bool(GameState.validate_save(bad_dice_count)["ok"]), "zero dice count is rejected")
	var bad_vehicle_ownership: Dictionary = saved.duplicate(true)
	bad_vehicle_ownership["players"][0]["vehicle"] = "car"
	_expect(not bool(GameState.validate_save(bad_vehicle_ownership)["ok"]), "unowned selected vehicle is rejected")
	var bad_property_membership: Dictionary = saved.duplicate(true)
	bad_property_membership["board"][1]["owner"] = 0
	_expect(not bool(GameState.validate_save(bad_property_membership)["ok"]), "board property owner must match player membership")
	var malformed_values: Array = [{}, [], "bad", null, false]
	var root_numeric_fields: Array = ["version", "seed", "rng_state", "turn", "round", "day", "month", "day_of_month", "weekday", "current_player", "winner", "last_total", "doubles_count"]
	for field in root_numeric_fields:
		for malformed_value in malformed_values:
			var malformed_root: Dictionary = saved.duplicate(true)
			malformed_root[field] = malformed_value
			var malformed_root_validation: Dictionary = GameState.validate_save(malformed_root)
			_expect(not bool(malformed_root_validation.get("ok", false)), "malformed root %s is rejected" % field)
	var player_numeric_fields: Array = ["id", "cash", "deposit", "property_values", "position", "dice_count", "skip_turns", "rent_shield", "turtle_days", "stay_next", "loan", "loan_due_day", "turns_taken"]
	for field in player_numeric_fields:
		for malformed_value in malformed_values:
			var malformed_player: Dictionary = saved.duplicate(true)
			malformed_player["players"][0][field] = malformed_value
			var malformed_player_validation: Dictionary = GameState.validate_save(malformed_player)
			_expect(not bool(malformed_player_validation.get("ok", false)), "malformed player %s is rejected" % field)
	var tile_numeric_fields: Array = ["index", "owner", "building_level", "cost", "upgrade_cost", "base_rent", "rent", "tax_amount"]
	for field in tile_numeric_fields:
		for malformed_value in malformed_values:
			var malformed_tile: Dictionary = saved.duplicate(true)
			malformed_tile["board"][1][field] = malformed_value
			var malformed_tile_validation: Dictionary = GameState.validate_save(malformed_tile)
			_expect(not bool(malformed_tile_validation.get("ok", false)), "malformed tile %s is rejected" % field)
	for seed in range(1, 21):
		var seeded: GameState = GameState.new_game(seed, 4)
		seeded.roll()
		var save_path: String = "user://richman4-simulation-roundtrip.json"
		_expect(seeded.save_to_path(save_path), "seed %d writes a save" % seed)
		var disk_restored: GameState = GameState.load_from_path(save_path)
		_expect(disk_restored != null, "seed %d reads a save" % seed)
		if disk_restored == null:
			continue
		_expect_equal(seeded.to_dict()["rng_state_text"], disk_restored.to_dict()["rng_state_text"], "seed %d preserves RNG text" % seed)
		if seeded.state.get("phase", "") == "await_action":
			seeded.end_turn()
			disk_restored.end_turn()
			var seeded_next: Dictionary = seeded.roll()
			var restored_next: Dictionary = disk_restored.roll()
			_expect_equal(seeded_next.get("dice", []), restored_next.get("dice", []), "seed %d replays after disk roundtrip" % seed)


func _test_ai_full_match() -> void:
	var game: GameState = GameState.new_game(707, 4)
	var result: Dictionary = game.run_ai_match(5000)
	_expect(bool(result.get("ok", false)), "AI match completes within cap")
	_expect_equal(game.state["phase"], "game_over", "AI match reaches game over")
	_expect(int(game.state["winner"]) >= 0 and int(game.state["winner"]) < 4, "AI match has a valid winner")
	var alive_count: int = 0
	for player in game.state["players"]:
		if bool(player["alive"]):
			alive_count += 1
	_expect_equal(alive_count, 1, "AI match leaves one survivor")
