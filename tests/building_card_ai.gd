extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")

const BUILDING_CARD_SAVE_VERSION := 13

var checks := 0
var failures := 0
var bootstrap_red := 0
var bootstrap_reported := false


func _initialize() -> void:
	_test_angel_prefers_own_beneficial_target()
	_test_demon_chooses_enemy_without_group_collateral()
	_test_monster_chooses_enemy_built_target()
	_test_demon_avoids_shared_own_group()
	_test_angel_minimizes_other_gains()
	print("Original building-card AI checks: %d, failures: %d, bootstrap_red: %d" % [checks, failures, bootstrap_red])
	quit(1 if failures or bootstrap_red > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _new_building_game(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.new_game_options())
	if game != null:
		return game
	bootstrap_red += 1
	if not bootstrap_reported:
		bootstrap_reported = true
		print("BOOTSTRAP RED: v13 building-card factory is unavailable; AI uses a stamped v12 fallback for strategy coverage")
	var legacy: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.v12_game_options())
	_expect(legacy != null, "v12 predecessor bootstraps the AI fallback")
	if legacy == null:
		return null
	legacy.state["version"] = BUILDING_CARD_SAVE_VERSION
	legacy.state["original_building_cards"] = true
	return legacy


func _stage_game(seed_value: int, card_id: String, own_level: int, enemy_level: int, own_group: String, enemy_group: String) -> Object:
	var game: Object = _new_building_game(seed_value)
	if game == null:
		return null
	game.state["god_objects"] = []
	for player_id in range(4):
		game.set_player_ai(player_id, player_id == 0)
	var own_player: Dictionary = game.state["players"][0]
	var enemy_player: Dictionary = game.state["players"][1]
	own_player["position"] = 2
	own_player["previous_position"] = -1
	own_player["properties"] = [2]
	own_player["cash"] = 0
	enemy_player["position"] = 3
	enemy_player["previous_position"] = -1
	enemy_player["properties"] = [3]
	var own_tile: Dictionary = game.state["board"][2]
	var enemy_tile: Dictionary = game.state["board"][3]
	own_tile["owner"] = 0
	own_tile["building_level"] = own_level
	own_tile["is_chain_store"] = false
	own_tile["group"] = own_group
	enemy_tile["owner"] = 1
	enemy_tile["building_level"] = enemy_level
	enemy_tile["is_chain_store"] = false
	enemy_tile["group"] = enemy_group
	game._update_tile_rent(own_tile)
	game._update_tile_rent(enemy_tile)
	game._recalculate_property_values()
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = true
	game.state["last_roll"] = [1]
	game.state["last_roll_total"] = 1
	game.state["pending_remote_dice"] = {}
	var supply_before: int = int(game.state["inventory_supply"]["cards"].get(card_id, 0))
	var grant_result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], own_player["cards"], card_id)
	_expect(bool(grant_result.get("ok", false)), card_id + " AI fixture grants a finite card")
	_expect(int(game.state["inventory_supply"]["cards"].get(card_id, 0)) == supply_before - 1, card_id + " AI fixture debits card supply")
	game._set_action_options(0)
	return game


func _card_event(game: Object, card_id: String) -> Dictionary:
	var events: Array = game.state.get("event_log", [])
	for event_value in events:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		if str(event_value.get("type", "")) == "card_used" and str(event_value.get("card_id", "")) == card_id and int(event_value.get("player_id", -1)) == 0:
			return event_value
	return {}


func _event_target(event: Dictionary) -> int:
	for key in ["target_tile_id", "tile_id"]:
		if event.has(key):
			return int(event.get(key, -1))
	return -1


func _event_affected(event: Dictionary) -> Array:
	for key in ["affected_tile_ids", "affected_tiles", "affected_ids"]:
		if typeof(event.get(key, null)) == TYPE_ARRAY:
			return event.get(key, [])
	return []


func _assert_ai_card_case(game: Object, card_id: String, expected_target: int, label: String, avoid_target: int = -1) -> void:
	_expect(game != null, label + " fixture starts")
	if game == null:
		return
	var before_supply: int = int(game.state["inventory_supply"]["cards"].get(card_id, 0))
	var mirror: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	_expect(mirror != null, label + " fixture reloads from JSON")
	var result: Dictionary = game.run_ai_turn()
	_expect(bool(result.get("ok", false)) and bool(result.get("completed", false)), label + " AI turn completes through public API")
	var event: Dictionary = _card_event(game, card_id)
	_expect(not event.is_empty(), label + " AI uses the requested card")
	if not event.is_empty():
		_expect(_event_target(event) == expected_target, label + " event identifies the deterministic target")
		var affected: Array = _event_affected(event)
		_expect(not affected.is_empty(), label + " event identifies affected building tiles")
		_expect(affected.has(expected_target), label + " affected tiles include the selected target")
		if avoid_target >= 0:
			_expect(not affected.has(avoid_target), label + " avoids collateral damage to own building")
	_expect(not game.state["players"][0]["cards"].has(card_id), label + " consumes the AI card")
	_expect(int(game.state["inventory_supply"]["cards"].get(card_id, 0)) == before_supply + 1, label + " returns the consumed card to finite supply")
	if mirror != null:
		var replay: Dictionary = mirror.run_ai_turn()
		_expect(bool(replay.get("ok", false)) and bool(replay.get("completed", false)), label + " JSON-restored AI turn completes")
		_expect(game.to_json() == mirror.to_json(), label + " AI choice and continuation replay exactly")
		_expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), label + " AI card turn remains save-valid")


func _test_angel_prefers_own_beneficial_target() -> void:
	# Both homes share a group. The own level-four home is one step from its cap;
	# the enemy home is lower, so selecting the own tile is the deterministic
	# beneficial choice even though the card affects the whole group.
	var game: Object = _stage_game(13101, "天使", 4, 1, "shared-group", "shared-group")
	_assert_ai_card_case(game, "天使", 2, "天使 beneficial-own strategy")


func _test_demon_chooses_enemy_without_group_collateral() -> void:
	# The enemy building is in a separate group. A target scan that blindly uses
	# the first built tile would clear the current player's own group instead.
	var game: Object = _stage_game(13102, "惡魔", 1, 3, "own-group", "enemy-group")
	_assert_ai_card_case(game, "惡魔", 3, "惡魔 enemy strategy", 2)


func _test_monster_chooses_enemy_built_target() -> void:
	var game: Object = _stage_game(13103, "怪獸", 1, 3, "own-group", "enemy-group")
	_assert_ai_card_case(game, "怪獸", 3, "怪獸 enemy strategy", 2)



func _test_demon_avoids_shared_own_group() -> void:
	var game: Object = _stage_game(13104, "惡魔", 2, 3, "shared-group", "shared-group")
	if game == null: return
	var result: Dictionary = game.run_ai_turn()
	_expect(result.get("ok", false) and result.get("completed", false), "collateral-avoidance AI turn completes")
	_expect(game.state.players[0].cards.has("惡魔"), "AI retains demon when only enemy target would destroy its own group")
	_expect(_card_event(game, "惡魔").is_empty(), "AI produces no destructive card event for shared own group")
	_expect(game.state.board[2].building_level == 2 and game.state.board[3].building_level == 3, "AI preserves both buildings when avoiding group collateral")


func _test_angel_minimizes_other_gains() -> void:
	# Both choices give the AI one level. The own facility improves nobody
	# else; the own house would also give a rival a free level.
	var game: Object = _stage_game(13105, "天使", 4, 1, "shared-group", "shared-group")
	if game == null:
		return
	game._update_facility_records(1, {"owner": 0, "building_level": 1, "facility_type": 1})
	game.state.players[0].properties = [1, 2]
	game._recalculate_property_values()
	game._set_action_options(0)
	_assert_ai_card_case(game, "天使", 1, "Angel equal-own-benefit conservative choice", 3)
	_expect(game.state.board[3].building_level == 1, "Angel tie choice leaves the rival building unchanged")
