extends SceneTree

## Issue #61 AI ordering regression coverage.
##
## The landing action must resolve a usable building card before deciding whether
## to spend the finite 工程車 inventory.  Fixtures use the public graph/save
## setup and keep ownership and inventory supply in sync before exercising
## run_ai_turn.
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_destructive_card_preserves_engineering("惡魔", 61101)
	_test_destructive_card_preserves_engineering("怪獸", 61102)
	_test_no_card_engineering_demolishes_target()
	_test_unusable_card_does_not_block_engineering()
	print("Engineering vehicle/card AI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _stage_game(seed_value: int, card_id: String = "") -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.new_game_options())
	_expect(game != null, "AI card-order fixture starts")
	if game == null:
		return null

	game.state["god_objects"] = []
	for player_id in range(4):
		game.set_player_ai(player_id, player_id == 0)

	# Return the opening inventory through the same finite-pool API used by the
	# runtime.  This keeps the fixture legal instead of overwriting containers.
	var actor: Dictionary = game.state["players"][0]
	for existing_card in actor.get("cards", []).duplicate(true):
		var returned_card: Dictionary = Inventory.consume_card(game.state["inventory_supply"], actor["cards"], existing_card)
		_expect(bool(returned_card.get("ok", false)), "fixture returns opening card")
	for existing_tool in actor.get("tools", {}).keys().duplicate():
		var returned_tool: Dictionary = Inventory.consume_tool(game.state["inventory_supply"], actor["tools"], existing_tool, int(actor["tools"][existing_tool]))
		_expect(bool(returned_tool.get("ok", false)), "fixture returns opening tool")
	_expect(bool(Inventory.grant_tool(game.state["inventory_supply"], actor["tools"], "工程車", 2).get("ok", false)), "fixture grants two engineering vehicles")
	_expect(bool(Inventory.grant_tool(game.state["inventory_supply"], actor["tools"], "汽車").get("ok", false)), "fixture grants an ordinary car")
	_expect(bool(Inventory.grant_tool(game.state["inventory_supply"], actor["tools"], "機車").get("ok", false)), "fixture grants an ordinary motorcycle")
	if not card_id.is_empty():
		var granted_card: Dictionary = Inventory.grant_card(game.state["inventory_supply"], actor["cards"], card_id)
		_expect(bool(granted_card.get("ok", false)), "fixture grants " + card_id + " from finite supply")

	# Clear all housing ownership and references before assigning the one enemy
	# landing.  This also makes 天使 intentionally unusable in its positive case.
	for player_value in game.state.get("players", []):
		if typeof(player_value) == TYPE_DICTIONARY:
			player_value["properties"] = []
	for tile_value in game.state.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = tile_value
		if tile.get("kind", "") != "property":
			continue
		tile["owner"] = -1
		tile["building_level"] = 0
		tile["is_chain_store"] = false
		game._update_tile_rent(tile)

	var enemy_tile: Dictionary = game.state["board"][3]
	_expect(enemy_tile.get("kind", "") == "property", "fixture landing is a property")
	enemy_tile["owner"] = 1
	enemy_tile["building_level"] = 3
	enemy_tile["is_chain_store"] = false
	enemy_tile["group"] = "engineering-card-enemy"
	game.state["players"][1]["properties"] = [3]
	game._update_tile_rent(enemy_tile)
	game._recalculate_property_values()

	actor["position"] = 3
	actor["previous_position"] = -1
	actor["cash"] = 0
	actor["vehicle"] = "walking"
	actor["dice_count"] = 1
	actor.erase("engineering_vehicle")
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = true
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state["bank_access"] = false
	game.state["bank_landing"] = false
	game._set_action_options(0)
	return game


func _assert_legal_round_trip(game: Object, label: String) -> Object:
	_expect(game != null, label + " fixture exists")
	if game == null:
		return null
	var before: Dictionary = game.to_dict()
	var before_validation: Dictionary = Game.validate_save(before)
	_expect(bool(before_validation.get("ok", false)), label + " before state validates: " + str(before_validation.get("errors", [])))
	var parsed: Variant = JSON.parse_string(game.to_json())
	_expect(parsed is Dictionary, label + " before state JSON parses")
	var mirror: Object = Game.from_dict(parsed if parsed is Dictionary else {})
	_expect(mirror != null, label + " before state reloads")
	if mirror != null:
		var mirror_validation: Dictionary = Game.validate_save(mirror.to_dict())
		_expect(bool(mirror_validation.get("ok", false)), label + " reloaded before state validates: " + str(mirror_validation.get("errors", [])))
		_expect(mirror.to_json() == game.to_json(), label + " before state round trips exactly")
	return mirror


func _assert_after_round_trip(game: Object, mirror: Object, label: String) -> void:
	var after: Dictionary = game.to_dict()
	var after_validation: Dictionary = Game.validate_save(after)
	_expect(bool(after_validation.get("ok", false)), label + " after state validates: " + str(after_validation.get("errors", [])))
	var after_parsed: Variant = JSON.parse_string(game.to_json())
	_expect(after_parsed is Dictionary, label + " after state JSON parses")
	var after_mirror: Object = Game.from_dict(after_parsed if after_parsed is Dictionary else {})
	_expect(after_mirror != null, label + " after state reloads")
	if after_mirror != null:
		var after_mirror_validation: Dictionary = Game.validate_save(after_mirror.to_dict())
		_expect(bool(after_mirror_validation.get("ok", false)), label + " reloaded after state validates: " + str(after_mirror_validation.get("errors", [])))
		_expect(after_mirror.to_json() == game.to_json(), label + " after state round trips exactly")
	if mirror != null:
		var mirror_result: Dictionary = mirror.run_ai_turn()
		_expect(bool(mirror_result.get("ok", false)) and bool(mirror_result.get("completed", false)), label + " reloaded AI turn completes")
		_expect(mirror.to_json() == game.to_json(), label + " AI continuation replays exactly")


func _card_event(game: Object, card_id: String) -> Dictionary:
	for event_value in game.state.get("event_log", []):
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		if str(event.get("type", "")) == "card_used" and str(event.get("card_id", "")) == card_id and int(event.get("player_id", -1)) == 0:
			return event
	return {}


func _engineering_event(game: Object) -> Dictionary:
	for event_value in game.state.get("event_log", []):
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		if str(event.get("type", "")) == "tool_used" and str(event.get("tool_id", "")) == "工程車" and int(event.get("player_id", -1)) == 0:
			return event
	return {}


func _demolition_event(game: Object) -> Dictionary:
	for event_value in game.state.get("event_log", []):
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		if str(event.get("type", "")) == "engineering_demolition" and int(event.get("player_id", -1)) == 0:
			return event
	return {}


func _test_destructive_card_preserves_engineering(card_id: String, seed_value: int) -> void:
	var label := card_id + " card resolves before engineering"
	var game: Object = _stage_game(seed_value, card_id)
	var mirror: Object = _assert_legal_round_trip(game, label)
	if game == null:
		return
	var supply_before: int = int(game.state["inventory_supply"]["cards"].get(card_id, 0))
	var result: Dictionary = game.run_ai_turn()
	_expect(bool(result.get("ok", false)) and bool(result.get("completed", false)), label + " AI turn completes")
	var card_event: Dictionary = _card_event(game, card_id)
	_expect(not card_event.is_empty(), label + " consumes the target card")
	_expect(int(game.state["board"][3].get("building_level", -1)) == 0, label + " card removes the enemy landing")
	_expect(not game.state["players"][0]["cards"].has(card_id), label + " removes the used card from hand")
	_expect(int(game.state["inventory_supply"]["cards"].get(card_id, 0)) == supply_before + 1, label + " returns the used card to finite supply")
	_expect(int(game.state["players"][0]["tools"].get("工程車", 0)) == 2, label + " retains both engineering vehicles after card removal")
	_expect(str(game.state["players"][0].get("vehicle", "")) == "walking", label + " does not activate engineering after card removal")
	_expect(game.state["players"][0].get("engineering_vehicle", null) == null, label + " leaves no engineering metadata after card removal")
	_expect(_engineering_event(game).is_empty(), label + " emits no engineering activation event")
	_expect(_demolition_event(game).is_empty(), label + " emits no wasted engineering demolition event")
	_assert_after_round_trip(game, mirror, label)


func _test_no_card_engineering_demolishes_target() -> void:
	var label := "no-card useful enemy landing"
	var game: Object = _stage_game(61103)
	var mirror: Object = _assert_legal_round_trip(game, label)
	if game == null:
		return
	var result: Dictionary = game.run_ai_turn()
	_expect(bool(result.get("ok", false)) and bool(result.get("completed", false)), label + " AI turn completes")
	_expect(int(game.state["players"][0]["tools"].get("工程車", 0)) == 1, label + " spends one engineering vehicle for a useful target")
	_expect(str(game.state["players"][0].get("vehicle", "")) == "engineering", label + " activates engineering for a useful target")
	_expect(int(game.state["board"][3].get("building_level", -1)) == 0, label + " engineering clears the enemy landing")
	_expect(not _engineering_event(game).is_empty(), label + " records engineering activation")
	var demolition: Dictionary = _demolition_event(game)
	_expect(not demolition.is_empty(), label + " records engineering demolition")
	_assert_after_round_trip(game, mirror, label)


func _test_unusable_card_does_not_block_engineering() -> void:
	# With only an unowned 天使 card, there is no legal card target.  The card
	# remains usable in hand while 工程車 still handles the enemy landing.
	var label := "unusable Angel card with useful enemy landing"
	var game: Object = _stage_game(61104, "天使")
	var mirror: Object = _assert_legal_round_trip(game, label)
	if game == null:
		return
	var result: Dictionary = game.run_ai_turn()
	_expect(bool(result.get("ok", false)) and bool(result.get("completed", false)), label + " AI turn completes")
	_expect(game.state["players"][0]["cards"].has("天使"), label + " retains the card without a legal own target")
	_expect(int(game.state["players"][0]["tools"].get("工程車", 0)) == 1, label + " spends engineering for the useful enemy target")
	_expect(str(game.state["players"][0].get("vehicle", "")) == "engineering", label + " activates engineering after card target rejection")
	_expect(int(game.state["board"][3].get("building_level", -1)) == 0, label + " engineering clears the enemy landing")
	_expect(_card_event(game, "天使").is_empty(), label + " emits no Angel card event")
	_assert_after_round_trip(game, mirror, label)
