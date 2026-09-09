extends SceneTree

## Issue #75 focused boundary regressions.
##
## These cases deliberately enter the public card and AI APIs from legal
## inventory factories.  They cover the two integration seams that are easy to
## miss when the alliance rule itself is exercised with hand-built state:
## inventory (v4) saves must accept the new optional player record, and the
## v13 AI must provide a legal target before dispatching 同盟.
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")

const INVENTORY_OPTIONS := {
	"start_date": {"year": 1998, "month": 1, "day": 1},
	"original_inventory": true,
}
const ALLIANCE_CARD := "同盟"

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_inventory_public_card_save_boundary()
	_test_v13_public_ai_alliance_boundary()
	print("Alliances boundary checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _stage_alliance(game: Object, player_id: int = 0) -> bool:
	var player: Dictionary = game.state["players"][player_id]
	var granted: Dictionary = Inventory.grant_card(game.state["inventory_supply"], player["cards"], ALLIANCE_CARD)
	expect(bool(granted.get("ok", false)), "legal factory stages one 同盟 card")
	game._set_action_options(player_id)
	return bool(granted.get("ok", false))


func _test_inventory_public_card_save_boundary() -> void:
	var game: Object = Game.new_game(75201, 2, INVENTORY_OPTIONS)
	expect(game != null, "inventory factory creates a v4 game")
	if game == null:
		return
	expect_equal(int(game.state.get("version", -1)), 4, "inventory boundary fixture uses v4")
	if not _stage_alliance(game):
		return
	expect(game.state.get("action_options", []).has("use_card"), "v4 public action exposes staged 同盟")
	var used: Dictionary = game.choose_action("use_card", {"card_id": ALLIANCE_CARD, "target_id": 1, "cancel": false})
	expect(bool(used.get("ok", false)), "v4 public use_card creates an alliance")
	if not bool(used.get("ok", false)):
		return
	expect_equal(game.state["players"][0]["alliance"], {"partner_id": 1, "turns": 7}, "v4 public use_card records caster alliance")
	expect_equal(game.state["players"][1]["alliance"], {"partner_id": 0, "turns": 7}, "v4 public use_card records reciprocal alliance")
	var snapshot: Dictionary = game.to_dict()
	var validation: Dictionary = Game.validate_save(snapshot)
	expect(bool(validation.get("ok", false)), "v4 alliance save validates: " + str(validation.get("errors", [])))
	var parsed: Variant = JSON.parse_string(game.to_json())
	expect(parsed is Dictionary, "v4 alliance JSON parses")
	if parsed is Dictionary:
		var restored: Object = Game.from_dict(parsed)
		expect(restored != null, "v4 alliance JSON reloads")
		if restored != null:
			expect_equal(restored.to_json(), game.to_json(), "v4 alliance JSON continuation is exact")


func _clear_tools(game: Object, player_id: int) -> void:
	var player: Dictionary = game.state["players"][player_id]
	var tools: Dictionary = player.get("tools", {}).duplicate(true)
	for tool_id_value in tools.keys():
		var tool_id: String = str(tool_id_value)
		var quantity: int = int(tools[tool_id_value])
		if quantity <= 0:
			continue
		var consumed: Dictionary = Inventory.consume_tool(game.state["inventory_supply"], player["tools"], tool_id, quantity)
		expect(bool(consumed.get("ok", false)), "AI fixture returns opening %s tools legally" % tool_id)


func _prepare_v13_card_stage(game: Object) -> void:
	var player: Dictionary = game.state["players"][0]
	game.set_player_ai(0, true)
	_clear_tools(game, 0)
	var grant_ok: bool = _stage_alliance(game)
	if not grant_ok:
		return
	# Land on the source card node and leave only the card-stage action.  Cash
	# and deposits are emptied through the normal save-shaped fields so the AI
	# cannot take a stock, property, or facility action before the card.
	player["position"] = 4
	player["previous_position"] = -1
	player["cash"] = 0
	player["deposit"] = 0
	var total_deposits: int = 0
	for candidate_value in game.state.get("players", []):
		if typeof(candidate_value) == TYPE_DICTIONARY:
			total_deposits += int(candidate_value.get("deposit", 0))
	var bank: Dictionary = game.state.get("bank", {})
	bank["deposits"] = total_deposits
	game.state["bank"] = bank
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game.state["property_action_used"] = true
	game.state["research_action_used"] = true
	game.state["bank_access"] = false
	game.state["bank_landing"] = false
	game.state["day"] = 4
	game._sync_state()
	game._set_action_options(0)


func _test_v13_public_ai_alliance_boundary() -> void:
	var game: Object = Game.new_game_on_board(75202, 4, Fixture.definition(), Fixture.new_game_options())
	expect(game != null, "v13 factory creates an AI alliance game")
	if game == null:
		return
	expect_equal(int(game.state.get("version", -1)), 13, "AI boundary fixture uses v13")
	_prepare_v13_card_stage(game)
	var options: Array = game.state.get("action_options", [])
	expect_equal(options, ["use_card", "end_turn"], "v13 AI fixture exposes only alliance card-stage actions")
	var before_json: String = game.to_json()
	var restored: Object = Game.from_dict(JSON.parse_string(before_json))
	expect(restored != null, "v13 AI boundary fixture reloads before turn")
	var result: Dictionary = game.run_ai_turn()
	expect(bool(result.get("ok", false)) and bool(result.get("completed", false)), "public v13 AI turn completes")
	expect(not game.state["players"][0]["cards"].has(ALLIANCE_CARD), "public v13 AI consumes the alliance card")
	expect_equal(game.state["players"][0].get("alliance", {}), {"partner_id": 1, "turns": 7}, "public v13 AI selects the first legal target")
	# run_ai_turn closes the AI's action phase and admits player 1, so the
	# reciprocal side has already taken its first countdown tick.
	expect_equal(game.state["players"][1].get("alliance", {}), {"partner_id": 0, "turns": 6}, "public v13 AI creates reciprocal alliance")
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "public v13 AI alliance result remains save-valid")
	if restored != null:
		var replay: Dictionary = restored.run_ai_turn()
		expect(bool(replay.get("ok", false)) and bool(replay.get("completed", false)), "reloaded v13 AI turn completes")
		expect_equal(restored.to_json(), game.to_json(), "public v13 AI alliance turn replays exactly")
