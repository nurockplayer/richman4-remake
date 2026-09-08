extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")

var _checks: int = 0
var _failures: int = 0
var _definition: Dictionary = {}


func _initialize() -> void:
	var normalized: Dictionary = Maps.normalize_map(Fixture.make())
	_expect(bool(normalized.get("ok", false)), "synthetic graph source normalizes")
	if bool(normalized.get("ok", false)):
		_definition = normalized["definition"]
	_test_graph_constructor_and_legacy_compatibility()
	_test_branch_movement_and_previous_node()
	_test_card_points_and_unsupported_tiles()
	_test_fixed_property_economics()
	_test_pending_route_save_load_and_validation()
	_test_graph_save_degree_limit()
	_test_ai_completes_pending_routes_deterministically()
	print("Graph flow checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures else 0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_graph(seed_value: int, player_count: int = 2) -> Object:
	var constructor := Callable(GameState, "new_game_on_board")
	if not constructor.is_valid():
		return null
	var result: Variant = constructor.call(seed_value, player_count, _definition)
	return result if result is Object else null


func _prepare_roll(game: Object, origin: int, previous: int = -1) -> void:
	game.state["current_player"] = 0
	game.state["phase"] = "await_roll"
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["players"][0]["position"] = origin
	game.state["players"][0]["previous_position"] = previous


func _find_roll(total: int, origin: int, previous: int = -1) -> Dictionary:
	for seed_value in range(1, 10000):
		var game: Object = _new_graph(seed_value)
		if game == null:
			return {}
		_prepare_roll(game, origin, previous)
		var result: Dictionary = game.roll()
		if bool(result.get("ok", false)) and int(result.get("total", -1)) == total:
			return {"game": game, "seed": seed_value, "result": result}
	return {}


func _finish_routes(game: Object, first_choice: int = -1) -> void:
	var safety := 0
	while game.state.get("phase", "") == "await_route" and safety < 16:
		var options: Array = game.state.get("route_options", [])
		if options.is_empty():
			break
		var choice: int = int(options[0]) if first_choice < 0 or safety > 0 else first_choice
		game.choose_route(choice)
		safety += 1
	_expect(safety < 16, "route resolution terminates")


func _test_graph_constructor_and_legacy_compatibility() -> void:
	var constructor := Callable(GameState, "new_game_on_board")
	_expect(constructor.is_valid(), "graph constructor is exposed")
	var game: Object = _new_graph(1001)
	_expect(game != null, "valid graph definition starts a game")
	if game != null:
		_expect_equal(game.state["version"], 2, "graph save uses version two")
		_expect_equal(game.state["board_mode"], "graph", "graph mode is explicit in state")
		_expect_equal(game.state["map_id"], _definition["id"], "map identity is persisted")
		_expect_equal(game.state["players"][0]["position"], _definition["start_position"], "players start at normalized map start")
		_expect_equal(game.state["players"][0]["previous_position"], -1, "graph players start without a previous node")
		_expect_equal(game.state["board"][1]["x"], _definition["board"][1]["x"], "node geometry is preserved")
		_expect_equal(game.state["board"][1]["adjacent"], [0, 2, 3], "zero-based adjacency is preserved")
		_expect_equal(game.state["board"][0]["type_and_idx"], 8002, "raw node status is preserved")
		_expect_equal(game.state["route_options"], [], "new graph game has no pending route")
		_expect_equal(game.state["remaining_steps"], 0, "new graph game has no remaining movement")
	var legacy: Object = GameState.new_game(1001, 2)
	_expect(legacy != null, "legacy constructor remains available")
	if legacy != null:
		_expect_equal(legacy.state["version"], 1, "legacy save version remains one")
		_expect_equal(legacy.state["board"].size(), 40, "legacy board remains forty tiles")
		_expect(not legacy.state.has("board_mode"), "legacy state does not require graph fields")
		_expect(bool(GameState.validate_save(legacy.to_dict()).get("ok", false)), "legacy save remains valid")
	var unsupported: Dictionary = _definition.duplicate(true)
	unsupported["supports_new_game"] = false
	_expect(_new_game_from_definition(unsupported) == null, "browse-only definition cannot start a game")
	var bad_identity: Dictionary = _definition.duplicate(true)
	bad_identity["source"]["payload_sha256"] = ""
	_expect(_new_game_from_definition(bad_identity) == null, "missing source hash rejects graph game")


func _new_game_from_definition(definition: Dictionary) -> Object:
	var constructor := Callable(GameState, "new_game_on_board")
	if not constructor.is_valid():
		return null
	var result: Variant = constructor.call(1001, 2, definition)
	return result if result is Object else null


func _test_branch_movement_and_previous_node() -> void:
	var found: Dictionary = _find_roll(2, 1)
	_expect(not found.is_empty(), "deterministic two-step branch fixture is available")
	if found.is_empty():
		return
	var game: Object = found["game"]
	_expect_equal(game.state["phase"], "await_route", "branching roll pauses for route choice")
	_expect_equal(game.state["remaining_steps"], 2, "pending route retains all unspent steps")
	_expect_equal(game.state["route_options"], [0, 2, 3], "route choices are sorted and legal")
	_expect_equal(game.state["pending_movement"]["player_id"], 0, "pending route records actor")
	_expect_equal(game.state["pending_movement"]["current_node"], 1, "pending route records current node")
	var choose_result: Dictionary = game.choose_route(2)
	_expect(bool(choose_result.get("ok", false)), "legal route choice succeeds")
	_expect_equal(game.state["players"][0]["position"], 4, "forced continuation advances one edge after choice")
	_expect_equal(game.state["players"][0]["previous_position"], 2, "previous node records the traversed edge")
	_expect_equal(game.state["remaining_steps"], 0, "two-step route consumes exactly two edges")
	_expect_equal(game.state["phase"], "await_action", "final landing resolves after route completion")
	_expect_equal(game.state["route_options"], [], "route choices clear after landing")
	_expect_equal(game.state["pending_movement"], {}, "pending movement clears after landing")
	var event_draws := 0
	for event in game.state["event_log"]:
		if event.get("type", "") == "event_drawn":
			event_draws += 1
	_expect_equal(event_draws, 1, "one roll triggers one final card landing effect")
	_expect_equal(game.state["players"][0]["cards"].size(), 1, "card landing grants one card")

	var branch_again: Dictionary = _find_roll(3, 1)
	if not branch_again.is_empty():
		var branch_game: Object = branch_again["game"]
		branch_game.choose_route(2)
		if branch_game.state.get("phase", "") == "await_route":
			var previous: int = int(branch_game.state["players"][0]["previous_position"])
			_expect(not branch_game.state["route_options"].has(previous), "branch options exclude immediate previous node")


func _test_card_points_and_unsupported_tiles() -> void:
	var point_landing: Dictionary = _find_roll(1, 0)
	_expect(not point_landing.is_empty(), "deterministic point landing fixture is available")
	if not point_landing.is_empty():
		var game: Object = point_landing["game"]
		_expect_equal(game.state["players"][0].get("points", 0), 50, "point landing awards exact fifty points")
		_expect_equal(game.state["last_event"].get("type", ""), "points_landed", "point landing records a supported effect")

	var point_pass: Dictionary = _find_roll(2, 0)
	_expect(not point_pass.is_empty(), "deterministic point pass-through fixture is available")
	if not point_pass.is_empty():
		var pass_game: Object = point_pass["game"]
		_expect_equal(pass_game.state["players"][0].get("points", 0), 50, "point pass-through awards exact points once")
		_expect_equal(pass_game.state["players"][0]["position"], 1, "point pass-through stops at the next branch")
		_expect_equal(pass_game.state["phase"], "await_route", "point pass-through leaves route choice pending")
		_finish_routes(pass_game, 2)
		_expect_equal(pass_game.state["players"][0]["position"], 2, "point pass-through then lands on chosen property")

	var card_pass: Dictionary = _find_roll(2, 2, 1)
	_expect(not card_pass.is_empty(), "deterministic card pass-through fixture is available")
	if not card_pass.is_empty():
		var card_game: Object = card_pass["game"]
		_expect_equal(card_game.state["players"][0]["cards"].size(), 1, "card pass-through grants one card")
		_expect_equal(card_game.state["last_event"].get("type", ""), "card_passed", "card pass-through records a card event")
		_expect_equal(card_game.state["phase"], "await_route", "card pass-through exposes the next branch")
		card_game.choose_route(5)
		_expect_equal(card_game.state["last_event"].get("type", ""), "bank_landed", "bank landing resolves after the chosen route")

	var unsupported_landing: Dictionary = _find_roll(1, 1)
	_expect(not unsupported_landing.is_empty(), "deterministic unsupported landing fixture is available")
	if not unsupported_landing.is_empty():
		var unsupported_game: Object = unsupported_landing["game"]
		_expect_equal(unsupported_game.state["phase"], "await_route", "unsupported branch still requires a route choice")
		unsupported_game.choose_route(0)
		_expect_equal(unsupported_game.state["last_event"].get("type", ""), "unsupported_landing", "unsupported tile records explicit unsupported effect")
		_expect_equal(unsupported_game.state["players"][0]["cards"].size(), 0, "unsupported tile does not grant a guessed card")


func _test_fixed_property_economics() -> void:
	var game: Object = _new_graph(1200)
	_expect(game != null, "property economy fixture starts")
	if game == null:
		return
	game.state["phase"] = "await_action"
	game.state["current_player"] = 0
	game.state["players"][0]["position"] = 2
	game.state["players"][0]["previous_position"] = 1
	game.state["property_action_used"] = false
	var buy_result: Dictionary = game.choose_action("buy")
	_expect(bool(buy_result.get("ok", false)), "graph property can be bought")
	_expect_equal(game.state["players"][0]["cash"], 14000, "graph property uses base land price")
	game.state["property_action_used"] = false
	var first_upgrade: Dictionary = game.choose_action("upgrade")
	_expect(bool(first_upgrade.get("ok", false)), "first graph property upgrade succeeds")
	_expect_equal(first_upgrade["event"]["price"], 300, "first graph upgrade uses source house price")
	_expect_equal(game.state["board"][2]["rent"], 250, "first graph rent uses source rent table")
	game.state["property_action_used"] = false
	var second_upgrade: Dictionary = game.choose_action("upgrade")
	_expect(bool(second_upgrade.get("ok", false)), "second graph property upgrade succeeds")
	_expect_equal(second_upgrade["event"]["price"], 300, "graph upgrade price remains fixed at house price")
	_expect_equal(game.state["board"][2]["rent"], 600, "second graph rent uses source rent table")


func _test_graph_save_degree_limit() -> void:
	var game := _new_graph(42)
	var saved: Dictionary = game.to_dict()
	saved.board[1].adjacent = [0, 2, 3, 4, 5]
	for index in [0, 2, 3, 4, 5]:
		if not saved.board[index].adjacent.has(1):
			saved.board[index].adjacent.append(1)
	var validation := GameState.validate_save(saved)
	_expect(not validation.ok, "degree-five graph save is rejected despite symmetric connected edges")
	_expect(validation.errors.has("invalid graph adjacency 1"), "oversized adjacency receives a direct shape error")


func _test_pending_route_save_load_and_validation() -> void:
	var found: Dictionary = _find_roll(2, 1)
	_expect(not found.is_empty(), "pending route save fixture is available")
	if found.is_empty():
		return
	var game: Object = found["game"]
	var saved: Dictionary = game.to_dict()
	_expect(bool(GameState.validate_save(saved).get("ok", false)), "pending graph save validates")
	var restored: Object = GameState.from_dict(saved)
	_expect(restored != null, "pending graph save restores")
	if restored != null:
		_expect_equal(restored.state["route_options"], game.state["route_options"], "restored route choices match")
		_expect_equal(restored.state["remaining_steps"], game.state["remaining_steps"], "restored remaining steps match")
		game.choose_route(2)
		restored.choose_route(2)
		_expect_equal(restored.to_json(), game.to_json(), "restored route replay matches exact state")
		game.end_turn()
		restored.end_turn()
		var first_roll: Dictionary = game.roll()
		var second_roll: Dictionary = restored.roll()
		_expect_equal(second_roll.get("dice", []), first_roll.get("dice", []), "restored RNG continues after route replay")
	var bad_identity: Dictionary = saved.duplicate(true)
	bad_identity["map_id"] = "Game:tampered"
	_expect(not bool(GameState.validate_save(bad_identity).get("ok", false)), "tampered map identity is rejected")
	var bad_coord: Dictionary = saved.duplicate(true)
	bad_coord["board"][1]["x"] = "bad"
	_expect(not bool(GameState.validate_save(bad_coord).get("ok", false)), "tampered graph coordinate is rejected")
	var bad_edge: Dictionary = saved.duplicate(true)
	bad_edge["board"][1]["adjacent"] = [99]
	_expect(not bool(GameState.validate_save(bad_edge).get("ok", false)), "out of range graph edge is rejected")
	var bad_pending: Dictionary = saved.duplicate(true)
	bad_pending["route_options"] = [5]
	_expect(not bool(GameState.validate_save(bad_pending).get("ok", false)), "pending route outside legal options is rejected")
	var bad_phase: Dictionary = saved.duplicate(true)
	bad_phase["phase"] = "await_route"
	bad_phase["route_options"] = []
	_expect(not bool(GameState.validate_save(bad_phase).get("ok", false)), "route phase without choices is rejected")
	var bad_board_mode: Dictionary = saved.duplicate(true)
	bad_board_mode["board_mode"] = {}
	_expect(not bool(GameState.validate_save(bad_board_mode).get("ok", false)), "malformed graph board mode is rejected")
	var bad_map_schema: Dictionary = saved.duplicate(true)
	bad_map_schema["map_schema"] = []
	_expect(not bool(GameState.validate_save(bad_map_schema).get("ok", false)), "malformed graph map schema is rejected")
	var bad_pending_shape: Dictionary = saved.duplicate(true)
	bad_pending_shape["pending_movement"]["current_node"] = {}
	_expect(not bool(GameState.validate_save(bad_pending_shape).get("ok", false)), "malformed pending route node is rejected")
	var bad_adjacency_shape: Dictionary = saved.duplicate(true)
	bad_adjacency_shape["board"][1]["adjacent"] = {}
	_expect(not bool(GameState.validate_save(bad_adjacency_shape).get("ok", false)), "malformed graph adjacency is rejected")
	var property_index: int = -1
	for index in range(saved["board"].size()):
		if typeof(saved["board"][index]) == TYPE_DICTIONARY and saved["board"][index].get("kind", "") == "property":
			property_index = index
			break
	_expect(property_index >= 0, "graph save fixture includes a property tile")
	if property_index >= 0:
		var bad_source_object: Dictionary = saved.duplicate(true)
		bad_source_object["board"][property_index]["source_object_id"] = 0
		_expect(not bool(GameState.validate_save(bad_source_object).get("ok", false)), "invalid graph source object is rejected")
		var bad_land_price: Dictionary = saved.duplicate(true)
		bad_land_price["board"][property_index]["land_price"] = -1
		_expect(not bool(GameState.validate_save(bad_land_price).get("ok", false)), "negative graph land price is rejected")
		var bad_house_price: Dictionary = saved.duplicate(true)
		bad_house_price["board"][property_index]["house_price"] = -1
		_expect(not bool(GameState.validate_save(bad_house_price).get("ok", false)), "negative graph house price is rejected")
		var bad_rent_table: Dictionary = saved.duplicate(true)
		bad_rent_table["board"][property_index]["rent_by_level"] = [-1, -1, -1, -1, -1, -1]
		_expect(not bool(GameState.validate_save(bad_rent_table).get("ok", false)), "negative graph rent table value is rejected")
		var bad_property_cost: Dictionary = saved.duplicate(true)
		bad_property_cost["board"][property_index]["cost"] += 1
		_expect(not bool(GameState.validate_save(bad_property_cost).get("ok", false)), "graph land price and board cost must match")
		var bad_upgrade_price: Dictionary = saved.duplicate(true)
		bad_upgrade_price["board"][property_index]["upgrade_cost"] += 1
		_expect(not bool(GameState.validate_save(bad_upgrade_price).get("ok", false)), "graph house price and upgrade cost must match")
		var bad_base_rent: Dictionary = saved.duplicate(true)
		bad_base_rent["board"][property_index]["base_rent"] += 1
		_expect(not bool(GameState.validate_save(bad_base_rent).get("ok", false)), "graph base rent must match rent table")
		var bad_current_rent: Dictionary = saved.duplicate(true)
		bad_current_rent["board"][property_index]["rent"] += 1
		_expect(not bool(GameState.validate_save(bad_current_rent).get("ok", false)), "graph current rent must match building level")


func _test_ai_completes_pending_routes_deterministically() -> void:
	var first: Object = _new_graph(1500)
	var second: Object = _new_graph(1500)
	_expect(first != null and second != null, "AI graph fixtures start")
	if first == null or second == null:
		return
	first.set_player_ai(0, true)
	second.set_player_ai(0, true)
	var first_result: Dictionary = first.run_ai_turn()
	var second_result: Dictionary = second.run_ai_turn()
	_expect(bool(first_result.get("ok", false)), "AI turn resolves graph routes")
	_expect(bool(second_result.get("ok", false)), "second AI turn resolves graph routes")
	_expect(first.state.get("phase", "") != "await_route", "AI does not stop at pending route")
	_expect(second.state.get("phase", "") != "await_route", "second AI does not stop at pending route")
	_expect_equal(first.state.get("route_options", []), [], "AI clears route options")
	_expect_equal(first.to_json(), second.to_json(), "AI graph route choice is deterministic")
