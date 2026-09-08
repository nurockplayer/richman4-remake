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
	for key in ["version", "ruleset", "seed", "rng_state", "rng_state_text", "phase", "turn", "round", "day", "current_player", "winner", "board", "players", "bank", "market", "event_log", "action_options"]:
		_expect(snapshot.has(key), "snapshot has " + key)
	_expect_equal(snapshot["version"], 1, "save version is one")
	_expect_equal(snapshot["players"].size(), 4, "four players are initialized")
	_expect_equal(snapshot["board"].size(), 40, "forty board tiles are initialized")
	_expect_equal(snapshot["players"][0]["dice_count"], 1, "walking defaults to one die")
	_expect_equal(snapshot["players"][0]["vehicle"], "walking", "walking is the default vehicle")
	_expect(not snapshot["event_log"].is_empty(), "new game records an event")


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
	for level in range(1, 6):
		game.state["phase"] = "await_action"
		var upgrade_result: Dictionary = game.choose_action("upgrade")
		_expect(bool(upgrade_result["ok"]), "upgrade to level %d succeeds" % level)
		_expect_equal(game.state["board"][1]["building_level"], level, "building level %d is recorded" % level)
	_expect(game.state["players"][0]["cash"] < first_level_cash, "upgrades deduct cash")
	game.state["phase"] = "await_action"
	var sixth_result: Dictionary = game.choose_action("upgrade")
	_expect(not bool(sixth_result["ok"]), "sixth property level is rejected")


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
	game.state["day"] = 30
	game._sync_state()
	game.state["players"][0]["deposit"] = 1000
	game.state["bank"]["deposits"] = 1000
	game._apply_month_boundary()
	_expect_equal(game.state["players"][0]["deposit"], 1100, "last day of month pays ten percent deposit interest")
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
