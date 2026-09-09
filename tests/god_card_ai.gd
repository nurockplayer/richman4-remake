extends SceneTree

## Issue #48 AI seed.
##
## The AI uses the same current graph, inventory and god state as a human
## player.  It intentionally runs on the current v13 save schema so missing
## card behavior is reported as semantic RED rather than a bootstrap/version
## failure.  Fixture validation failures are counted separately.
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/god_card_fixture.gd")

const DISMISS_CARD := "送神符"
const SUMMON_CARD := "請神符"

var checks := 0
var failures := 0
var fixture_validation_failures := 0


func _initialize() -> void:
	_test_song_dismisses_bad_gods()
	_test_song_dismisses_bad_god_without_bomb()
	_test_song_dismisses_bad_god_with_long_bomb()
	_test_song_clears_short_carried_bombs()
	_test_song_keeps_other_gods_with_bomb()
	_test_song_rejects_without_effect()
	_test_qing_accepts_nearest_beneficial_god()
	_test_qing_rejects_nonbeneficial_target()
	_test_qing_keeps_an_existing_beneficial_god()
	print("Original god-card AI checks: %d, failures: %d, fixture_validation_failures: %d" % [checks, failures, fixture_validation_failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_fixture(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		fixture_validation_failures += 1
		push_error("FIXTURE FAIL: " + message)


func _new_god_game(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.new_game_options())
	_expect_fixture(game != null, "v13 god-card AI fixture starts")
	return game


func _stage_turn(seed_value: int, card_id: String) -> Object:
	var game: Object = _new_god_game(seed_value)
	if game == null:
		return null
	var players: Array = game.state.get("players", [])
	for player_id in range(players.size()):
		game.set_player_ai(player_id, player_id == 0)
		var player: Dictionary = players[player_id]
		# Keep the public AI turn in await_action so movement and random landing
		# effects cannot mask the card strategy under test.
		player["position"] = 1 + player_id
		player["previous_position"] = -1
		player["god_id"] = 0
		player["bomb_steps"] = 0
		player["cards"] = []
	game.state["god_objects"] = []
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = true
	game.state["research_action_used"] = true
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	# Prevent the generic AI fallback from buying stock before it reaches the
	# staged card. Keep bank deposit accounting valid for the fixture.
	players[0]["deposit"] = 0
	var deposits := 0
	for player in players:
		deposits += int(player.get("deposit", 0))
	game.state["bank"]["deposits"] = deposits
	var player_zero: Dictionary = players[0]
	var grant_result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], player_zero["cards"], card_id)
	_expect(bool(grant_result.get("ok", false)), card_id + " AI fixture grants a finite card")
	game._set_action_options(0)
	_expect_fixture(bool(Game.validate_save(game.to_dict()).get("ok", false)), card_id + " AI fixture is save-valid before the turn")
	return game


func _carry_bomb(game: Object, steps: int) -> void:
	var player: Dictionary = game.state["players"][0]
	var tools: Dictionary = player.get("tools", {})
	var held: int = int(tools.get("定時炸彈", 0))
	_expect(held > 0, "AI fixture has a finite bomb to carry")
	if held <= 0:
		return
	# Active carried bombs are counted by validate_save through bomb_steps, not
	# through the player's ordinary tool bag. Move one held copy into that
	# active state without manually changing the shared supply.
	if held == 1:
		tools.erase("定時炸彈")
	else:
		tools["定時炸彈"] = held - 1
	player["bomb_steps"] = steps


func _add_god(game: Object, god_id: int, owner: int, node: int) -> void:
	var actor: Dictionary = {"id": god_id, "node": node, "owner": owner, "days": 7 if owner >= 0 else 0}
	game.state["god_objects"].append(actor)
	if owner >= 0:
		game.state["players"][owner]["god_id"] = god_id


func _card_event(game: Object, card_id: String) -> Dictionary:
	for event_value in game.state.get("event_log", []):
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		if str(event_value.get("type", "")) == "card_used" and str(event_value.get("card_id", "")) == card_id and int(event_value.get("player_id", -1)) == 0:
			return event_value
	return {}


func _run_ai(game: Object, label: String) -> Dictionary:
	_expect_fixture(game != null, label + " fixture starts")
	if game == null:
		return {}
	var before_validation: Dictionary = Game.validate_save(game.to_dict())
	_expect_fixture(bool(before_validation.get("ok", false)), label + " fixture validates before AI")
	var mirror: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	_expect_fixture(mirror != null, label + " fixture reloads from JSON")
	var result: Dictionary = game.run_ai_turn()
	_expect(bool(result.get("ok", false)) and bool(result.get("completed", false)), label + " completes through public run_ai_turn")
	var after_validation: Dictionary = Game.validate_save(game.to_dict())
	_expect_fixture(bool(after_validation.get("ok", false)), label + " AI state remains save-valid")
	if mirror != null:
		var mirror_result: Dictionary = mirror.run_ai_turn()
		_expect(mirror_result == result, label + " JSON-restored AI result matches")
		_expect(mirror.to_json() == game.to_json(), label + " JSON-restored AI state matches")
		_expect_fixture(bool(Game.validate_save(mirror.to_dict()).get("ok", false)), label + " JSON-restored AI state remains save-valid")
	return result


func _test_song_dismisses_bad_gods() -> void:
	for index in range([5, 6, 7, 8, 10].size()):
		var god_id: int = [5, 6, 7, 8, 10][index]
		var game: Object = _stage_turn(14100 + index, DISMISS_CARD)
		if game == null:
			continue
		_add_god(game, god_id, 0, 1)
		var tool_supply: Dictionary = game.state["inventory_supply"]["tools"]
		var supply_before: int = int(tool_supply.get("定時炸彈", 0))
		_carry_bomb(game, 5)
		_run_ai(game, "送神符解除壞神%d" % god_id)
		var event: Dictionary = _card_event(game, DISMISS_CARD)
		_expect(not event.is_empty(), "送神符 records card_used for 壞神%d" % god_id)
		_expect(int(game.state["players"][0].get("god_id", -1)) == 0, "送神符解除自己攜帶的壞神%d" % god_id)
		_expect(int(game.state["players"][0].get("bomb_steps", -1)) == 0, "送神符 also clears a short bomb with 壞神%d" % god_id)
		_expect(int(tool_supply.get("定時炸彈", -1)) == supply_before + 1, "送神符 returns the bomb cleared with 壞神%d" % god_id)
		_expect(game.state["players"][0]["cards"].find(DISMISS_CARD) < 0, "送神符 is consumed after removing 壞神%d" % god_id)


func _test_song_dismisses_bad_god_without_bomb() -> void:
	var game: Object = _stage_turn(14107, DISMISS_CARD)
	if game == null:
		return
	_add_god(game, 7, 0, 1)
	_run_ai(game, "送神符無炸彈仍解除壞神7")
	_expect(not _card_event(game, DISMISS_CARD).is_empty(), "送神符 uses the card for 壞神7 without a carried bomb")
	_expect(int(game.state["players"][0].get("god_id", -1)) == 0, "送神符解除無炸彈時自己攜帶的壞神7")
	_expect(int(game.state["players"][0].get("bomb_steps", -1)) == 0, "送神符無炸彈案例保持零倒數")
	_expect(game.state["players"][0]["cards"].find(DISMISS_CARD) < 0, "送神符 is consumed after removing bomb-free 壞神7")


func _test_song_dismisses_bad_god_with_long_bomb() -> void:
	var game: Object = _stage_turn(14108, DISMISS_CARD)
	if game == null:
		return
	_add_god(game, 7, 0, 1)
	var tool_supply: Dictionary = game.state["inventory_supply"]["tools"]
	var supply_before: int = int(tool_supply.get("定時炸彈", 0))
	_carry_bomb(game, 38)
	_run_ai(game, "送神符同時解除壞神7與長炸彈")
	_expect(not _card_event(game, DISMISS_CARD).is_empty(), "送神符 uses the card for 壞神7 with a 38-step bomb")
	_expect(int(game.state["players"][0].get("god_id", -1)) == 0, "送神符解除攜帶長炸彈時的壞神7")
	_expect(int(game.state["players"][0].get("bomb_steps", -1)) == 0, "送神符 clears the 38-step bomb beside 壞神7")
	_expect(int(tool_supply.get("定時炸彈", -1)) == supply_before + 1, "送神符 returns the long bomb cleared beside 壞神7")
	_expect(game.state["players"][0]["cards"].find(DISMISS_CARD) < 0, "送神符 is consumed after clearing long bomb and 壞神7")


func _test_song_clears_short_carried_bombs() -> void:
	for steps in range(1, 13):
		var game: Object = _stage_turn(14200 + steps, DISMISS_CARD)
		if game == null:
			continue
		var tool_supply: Dictionary = game.state["inventory_supply"]["tools"]
		var supply_before: int = int(tool_supply.get("定時炸彈", 0))
		_carry_bomb(game, steps)
		_run_ai(game, "送神符清除%d步定時炸彈" % steps)
		_expect(not _card_event(game, DISMISS_CARD).is_empty(), "送神符 uses the card for a %d-step carried bomb" % steps)
		_expect(int(game.state["players"][0].get("bomb_steps", -1)) == 0, "送神符 clears a %d-step carried bomb" % steps)
		_expect(int(tool_supply.get("定時炸彈", -1)) == supply_before + 1, "送神符 returns a cleared %d-step bomb to finite supply" % steps)

	for steps in [13, 38]:
		var game: Object = _stage_turn(14300 + steps, DISMISS_CARD)
		if game == null:
			continue
		var tool_supply: Dictionary = game.state["inventory_supply"]["tools"]
		var supply_before: int = int(tool_supply.get("定時炸彈", 0))
		_carry_bomb(game, steps)
		_run_ai(game, "送神符保留%d步定時炸彈" % steps)
		_expect(_card_event(game, DISMISS_CARD).is_empty(), "送神符 retains a %d-step carried bomb" % steps)
		_expect(game.state["players"][0]["cards"].find(DISMISS_CARD) >= 0, "送神符 card remains when bomb has %d steps" % steps)
		_expect(int(game.state["players"][0].get("bomb_steps", -1)) == steps, "送神符 does not clear a %d-step carried bomb" % steps)
		_expect(int(tool_supply.get("定時炸彈", -1)) == supply_before, "long carried bomb keeps its finite slot at %d steps" % steps)


func _test_song_keeps_other_gods_with_bomb() -> void:
	for god_id in [1, 9, 12]:
		var game: Object = _stage_turn(14400 + god_id, DISMISS_CARD)
		if game == null:
			continue
		_add_god(game, god_id, 0, 1)
		var tool_supply: Dictionary = game.state["inventory_supply"]["tools"]
		var supply_before: int = int(tool_supply.get("定時炸彈", 0))
		_carry_bomb(game, 5)
		_run_ai(game, "送神符保留神明%d並保留炸彈" % god_id)
		_expect(_card_event(game, DISMISS_CARD).is_empty(), "送神符 retains its card with existing god%d and a bomb" % god_id)
		_expect(int(game.state["players"][0].get("god_id", -1)) == god_id, "送神符 keeps existing god%d" % god_id)
		_expect(int(game.state["players"][0].get("bomb_steps", -1)) == 5, "送神符 keeps the bomb while preserving god%d" % god_id)
		_expect(int(tool_supply.get("定時炸彈", -1)) == supply_before, "送神符 leaves the finite bomb slot with god%d" % god_id)


func _test_song_rejects_without_effect() -> void:
	var game: Object = _stage_turn(14501, DISMISS_CARD)
	if game == null:
		return
	var before: String = game.to_json()
	_run_ai(game, "送神符無可清除效果")
	_expect(_card_event(game, DISMISS_CARD).is_empty(), "送神符 emits no card event without a removable god or bomb")
	_expect(game.state["players"][0]["cards"].find(DISMISS_CARD) >= 0, "送神符 remains atomic when no effect is available")
	_expect(game.to_json() != before, "AI no-effect turn advances without consuming 送神符")


func _test_qing_accepts_nearest_beneficial_god() -> void:
	var game: Object = _stage_turn(14601, SUMMON_CARD)
	if game == null:
		return
	_add_god(game, 5, 0, 1)
	# Node 6 is nearer to node 1 than node 5 in the synthetic source
	# coordinates. Both are free and attachable; the nearest beneficial god is 3.
	_add_god(game, 3, -1, 6)
	_add_god(game, 4, -1, 5)
	var origin: Vector2 = Vector2(game.state["board"][1]["x"], game.state["board"][1]["y"])
	var near: Vector2 = Vector2(game.state["board"][6]["x"], game.state["board"][6]["y"])
	var far: Vector2 = Vector2(game.state["board"][5]["x"], game.state["board"][5]["y"])
	_expect(origin.distance_to(near) < origin.distance_to(far), "Qing fixture makes beneficial god3 the nearest candidate")
	_run_ai(game, "請神符選擇最近的有益神明")
	var event: Dictionary = _card_event(game, SUMMON_CARD)
	_expect(not event.is_empty(), "請神符 records card_used for a beneficial candidate")
	_expect(int(game.state["players"][0].get("god_id", -1)) == 3, "請神符 attaches the nearest beneficial god")
	_expect(game.state["players"][0]["cards"].find(SUMMON_CARD) < 0, "請神符 is consumed after attaching a beneficial god")


func _test_qing_rejects_nonbeneficial_target() -> void:
	var game: Object = _stage_turn(14701, SUMMON_CARD)
	if game == null:
		return
	_add_god(game, 5, 0, 1)
	_add_god(game, 9, -1, 6)
	_add_god(game, 3, -1, 5)
	var origin: Vector2 = Vector2(game.state["board"][1]["x"], game.state["board"][1]["y"])
	var nearest: Vector2 = Vector2(game.state["board"][6]["x"], game.state["board"][6]["y"])
	var farther: Vector2 = Vector2(game.state["board"][5]["x"], game.state["board"][5]["y"])
	_expect(origin.distance_to(nearest) < origin.distance_to(farther), "Qing fixture makes nonbeneficial god9 the nearest candidate")
	_run_ai(game, "請神符拒絕非有益神明")
	_expect(_card_event(game, SUMMON_CARD).is_empty(), "請神符 emits no card event for a nearest nonbeneficial god")
	_expect(game.state["players"][0]["cards"].find(SUMMON_CARD) >= 0, "請神符 remains when no beneficial god is selected")
	_expect(int(game.state["players"][0].get("god_id", -1)) == 5, "請神符 keeps the current god after rejecting a nonbeneficial candidate")


func _test_qing_keeps_an_existing_beneficial_god() -> void:
	for god_id in [1, 2, 3, 4, 12]:
		var game: Object = _stage_turn(14800 + god_id, SUMMON_CARD)
		if game == null:
			continue
		_add_god(game, god_id, 0, 1)
		var another_good: int = 1 if god_id != 1 else 2
		_add_god(game, another_good, -1, 6)
		var origin: Vector2 = Vector2(game.state["board"][1]["x"], game.state["board"][1]["y"])
		var nearest: Vector2 = Vector2(game.state["board"][6]["x"], game.state["board"][6]["y"])
		_expect(origin.distance_to(nearest) < 10000.0, "Qing fixture has a nearby alternate beneficial god%d" % another_good)
		_run_ai(game, "請神符保留現有有益神明%d" % god_id)
		_expect(_card_event(game, SUMMON_CARD).is_empty(), "請神符 emits no event when god%d is already attached" % god_id)
		_expect(game.state["players"][0]["cards"].find(SUMMON_CARD) >= 0, "請神符 remains when god%d is already attached" % god_id)
		_expect(int(game.state["players"][0].get("god_id", -1)) == god_id, "請神符 preserves existing god%d" % god_id)
