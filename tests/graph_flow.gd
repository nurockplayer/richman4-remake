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
	_test_graph_source_classification_and_points()
	_test_fixed_property_economics()
	_test_unowned_improvements_rejected()
	_test_pending_route_save_load_and_validation()
	_test_graph_remaining_step_bounds()
	_test_graph_save_degree_limit()
	_test_graph_save_positions()
	_test_ai_completes_pending_routes_deterministically()
	_test_ai_completes_eighteen_step_car_route()
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
	var asymmetric: Dictionary = _definition.duplicate(true)
	asymmetric["board"][1]["adjacent"].erase(0)
	_expect(not bool(GameState.validate_board_definition(asymmetric).get("ok", false)), "asymmetric definition is rejected")
	_expect(_new_game_from_definition(asymmetric) == null, "asymmetric definition cannot create an unsaveable game")
	for change in [
		{"field": "source_node_id", "value": 0},
		{"field": "type_and_idx", "value": 0},
		{"field": "type_and_idx", "value": 2002},
		{"field": "cost", "value": 999},
		{"field": "upgrade_cost", "value": 999},
		{"field": "building_level", "value": 6}]:
		var invalid: Dictionary = _definition.duplicate(true)
		invalid["board"][2][change.field] = change.value
		_expect(not bool(GameState.validate_board_definition(invalid).get("ok", false)), "reject invalid definition " + str(change))
		_expect(_new_game_from_definition(invalid) == null, "invalid definition never creates unsaveable game " + str(change))
	var missing_node: Dictionary = _definition.duplicate(true)
	missing_node["board"][0].erase("source_node_id")
	_expect(_new_game_from_definition(missing_node) == null, "missing source node identity cannot start")
	var invalid_level: Dictionary = _definition.duplicate(true)
	invalid_level["board"][0]["building_level"] = 6
	_expect(_new_game_from_definition(invalid_level) == null, "non-property cannot start with invalid level")
	var disguised_housing: Dictionary = _definition.duplicate(true)
	disguised_housing["board"][2]["kind"] = "rest"
	_expect(_new_game_from_definition(disguised_housing) == null, "housing cannot be admitted as inert non-property")
	var duplicate_housing: Dictionary = _definition.duplicate(true)
	duplicate_housing["board"][3]["source_object_id"] = 1
	duplicate_housing["board"][3]["type_and_idx"] = 2001
	_expect(_new_game_from_definition(duplicate_housing) == null, "one source house cannot occupy two purchase records")
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


func _test_graph_source_classification_and_points() -> void:
	var source_kinds := {0: "unsupported", 1: "points", 4: "card", 5: "bank"}
	for index in source_kinds:
		var tampered: Dictionary = _definition.duplicate(true)
		tampered["board"][index]["kind"] = "rest"
		_expect(not bool(GameState.validate_board_definition(tampered).get("ok", false)), "source kind tampering is rejected for node %d" % index)
		_expect(_new_game_from_definition(tampered) == null, "source kind tampering cannot start node %d" % index)

	var rest: Dictionary = _definition.duplicate(true)
	rest["board"][0]["type_and_idx"] = 0
	rest["board"][0]["event_code"] = 0
	rest["board"][0]["kind"] = "rest"
	_expect(bool(GameState.validate_board_definition(rest).get("ok", false)), "event zero source remains an inert rest tile")
	for invalid_kind in ["tax", "event", "stock", "start", "news"]:
		var active_rest: Dictionary = rest.duplicate(true)
		active_rest["board"][0]["kind"] = invalid_kind
		_expect(not bool(GameState.validate_board_definition(active_rest).get("ok", false)), "event zero cannot opt into %s" % invalid_kind)
	var event_two: Dictionary = rest.duplicate(true)
	event_two["board"][0]["event_code"] = 2
	_expect(not bool(GameState.validate_board_definition(event_two).get("ok", false)), "event two cannot remain an inert rest tile")
	var event_two_card: Dictionary = event_two.duplicate(true)
	event_two_card["board"][0]["kind"] = "card"
	_expect(not bool(GameState.validate_board_definition(event_two_card).get("ok", false)), "event two cannot masquerade as a card")
	var raw_event_two: Dictionary = Fixture.make()
	raw_event_two["nodes"][1]["event_code"] = 2
	var normalized_event_two: Dictionary = Maps.normalize_map(raw_event_two)
	_expect(bool(normalized_event_two.get("ok", false)), "event two source normalizes")
	if bool(normalized_event_two.get("ok", false)):
		_expect_equal(normalized_event_two["definition"]["board"][1]["kind"], "news", "event two source enables news landing")
		_expect_equal(normalized_event_two["definition"]["board"][1]["name"], "新聞", "event two keeps its supported source event name")
	_expect_equal(Maps.classify_source_node(0, 2).kind, "news", "ordinary source news road classifies as news")
	_expect_equal(Maps.classify_source_node(2001, 2).kind, "property", "housing retains priority over news event")
	_expect_equal(Maps.classify_source_node(4001, 2, true).kind, "facility", "facility retains priority over news event")
	_expect_equal(Maps.classify_source_node(6001, 2, true).kind, "unsupported", "company type does not become a generic news road")
	_expect_equal(Maps.classify_source_node(0, 3).kind, "unsupported", "fate remains outside news scope")

	for source_points in [{"event_code": 10, "points": 50}, {"event_code": 11, "points": 30}, {"event_code": 12, "points": 10}]:
		var mapped: Dictionary = _definition.duplicate(true)
		mapped["board"][1]["event_code"] = source_points["event_code"]
		mapped["board"][1]["source_status_bits"] = (int(mapped["board"][1]["source_status_bits"]) & ~0xff) | int(source_points["event_code"])
		mapped["board"][1]["points"] = source_points["points"]
		_expect(bool(GameState.validate_board_definition(mapped).get("ok", false)), "point source %d keeps exact value" % source_points["event_code"])
		var wrong_points: Dictionary = mapped.duplicate(true)
		wrong_points["board"][1]["points"] = int(source_points["points"]) + 1
		_expect(not bool(GameState.validate_board_definition(wrong_points).get("ok", false)), "point source %d rejects wrong value" % source_points["event_code"])
	var negative_points: Dictionary = _definition.duplicate(true)
	negative_points["board"][1]["points"] = -1
	_expect(not bool(GameState.validate_board_definition(negative_points).get("ok", false)), "negative point tile value is rejected")
	var point_extra: Dictionary = _definition.duplicate(true)
	point_extra["board"][4]["points"] = 1
	_expect(not bool(GameState.validate_board_definition(point_extra).get("ok", false)), "non-point tile cannot carry point value")

	var game: Object = _new_graph(1101)
	_expect(game != null, "source classification save fixture starts")
	if game == null:
		return
	var saved: Dictionary = game.to_dict()
	for index in source_kinds:
		var bad_save: Dictionary = saved.duplicate(true)
		bad_save["board"][index]["kind"] = "rest"
		_expect(not bool(GameState.validate_save(bad_save).get("ok", false)), "source kind tampering is rejected in save for node %d" % index)
	var bad_rest_save: Dictionary = saved.duplicate(true)
	bad_rest_save["board"][0]["type_and_idx"] = 0
	bad_rest_save["board"][0]["event_code"] = 0
	bad_rest_save["board"][0]["kind"] = "tax"
	_expect(not bool(GameState.validate_save(bad_rest_save).get("ok", false)), "rest source cannot opt into an active save tile")
	saved["board"][1]["points"] = -1
	_expect(not bool(GameState.validate_save(saved).get("ok", false)), "negative point tile value is rejected in save")
	var capped_points: Object = _new_graph(1102)
	_expect(capped_points != null, "point ceiling transition fixture starts")
	if capped_points != null:
		capped_points.state["players"][0]["points"] = GameState.MAX_GRAPH_POINTS
		capped_points._graph_visit_tile(0, capped_points.state["board"][1], false)
		_expect_equal(capped_points.state["players"][0]["points"], GameState.MAX_GRAPH_POINTS, "point award saturates at the save ceiling")
		_expect_equal(capped_points.state["last_event"].get("points", -1), 0, "capped point event records the actual award")
		_expect_equal(capped_points.state["last_event"].get("source_points", -1), 50, "capped point event preserves source value")
		_expect(bool(GameState.validate_save(capped_points.to_dict()).get("ok", false)), "capped point transition remains saveable")

	var facility_event: Dictionary = _definition.duplicate(true)
	facility_event["board"][4]["type_and_idx"] = 4001
	facility_event["board"][4]["kind"] = "unsupported"
	_expect(bool(GameState.validate_board_definition(facility_event).get("ok", false)), "facility event remains explicitly unsupported")
	var facility_as_card: Dictionary = facility_event.duplicate(true)
	facility_as_card["board"][4]["kind"] = "card"
	_expect(not bool(GameState.validate_board_definition(facility_as_card).get("ok", false)), "facility event cannot masquerade as a card")


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
		_expect_equal(restored.state["action_options"], game.state["action_options"], "pending-route load preserves immediately available actions")
		_expect_equal(restored.to_json(), game.to_json(), "pending-route save round trip is identical before continuing")
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
	var disguised_housing: Dictionary = saved.duplicate(true)
	disguised_housing["board"][2]["kind"] = "rest"
	_expect(not bool(GameState.validate_save(disguised_housing).get("ok", false)), "save housing cannot masquerade as a non-property")
	var duplicate_housing: Dictionary = saved.duplicate(true)
	duplicate_housing["board"][3]["source_object_id"] = 1
	duplicate_housing["board"][3]["type_and_idx"] = 2001
	_expect(not bool(GameState.validate_save(duplicate_housing).get("ok", false)), "duplicate source house in save is rejected")
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


func _test_graph_remaining_step_bounds() -> void:
	var game: Object = _new_graph(1601)
	_expect(game != null, "remaining-step validation fixture starts")
	if game == null:
		return
	var pending: Dictionary = game.to_dict()
	pending["phase"] = "await_route"
	pending["route_options"] = [0, 2, 3]
	pending["pending_movement"] = {"player_id": 0, "current_node": 1, "previous_node": -1}
	pending["last_roll"] = [6, 6, 6]
	pending["last_total"] = 18
	pending["remaining_steps"] = 19
	pending["players"][0]["vehicles"]["car"] = true
	pending["players"][0]["vehicle"] = "car"
	pending["players"][0]["dice_count"] = 3
	_expect(not bool(GameState.validate_save(pending).get("ok", false)), "graph remaining steps above eighteen are rejected")
	pending["remaining_steps"] = 1000000000
	_expect(not bool(GameState.validate_save(pending).get("ok", false)), "graph billion-step cycle payload is rejected")
	pending["remaining_steps"] = 18
	pending["last_roll"] = [1]
	_expect(not bool(GameState.validate_save(pending).get("ok", false)), "graph pending roll total must match dice")
	pending["last_roll"] = [6, 6, 6]
	pending["last_total"] = 18
	pending["players"][0]["vehicle"] = "walking"
	pending["players"][0]["dice_count"] = 1
	_expect(not bool(GameState.validate_save(pending).get("ok", false)), "graph pending roll cannot exceed vehicle dice limit")
	pending["players"][0]["vehicle"] = "car"
	pending["players"][0]["dice_count"] = 3
	pending["last_roll"] = []
	pending["last_total"] = 0
	pending["remaining_steps"] = 1
	_expect(not bool(GameState.validate_save(pending).get("ok", false)), "route phase requires an actual pending roll")

	var guarded: Object = _new_graph(1602)
	_expect(guarded != null, "runtime remaining-step guard fixture starts")
	if guarded != null:
		guarded.set_player_ai(0, true)
		guarded.state["phase"] = "await_route"
		guarded.state["route_options"] = [0, 2, 3]
		guarded.state["pending_movement"] = {"player_id": 0, "current_node": 1, "previous_node": -1}
		guarded.state["last_roll"] = [6, 6, 6]
		guarded.state["last_total"] = 18
		guarded.state["remaining_steps"] = 1000000000
		var result: Dictionary = guarded.run_ai_turn()
		_expect(not bool(result.get("ok", false)), "AI rejects an unbounded pending route explicitly")
		_expect_equal(result.get("completed", true), false, "AI marks an invalid pending route incomplete")


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


func _long_branch_definition() -> Dictionary:
	var board: Array = []
	var node_count := 20
	for index in range(node_count):
		var adjacent: Array = []
		for delta in [-3, -1, 1, 3]:
			adjacent.append((index + delta + node_count) % node_count)
		adjacent.sort()
		var tile: Dictionary = {
			"index": index, "source_node_id": index + 1, "x": index * 10, "y": 0, "adjacent": adjacent,
			"type_and_idx": 0, "visual_index": 0, "event_code": 0, "source_object_id": 0,
			"kind": "rest", "name": "道路 %d" % index, "owner": -1, "building_level": 0,
			"cost": 0, "upgrade_cost": 0, "base_rent": 0, "rent": 0, "group": "", "tax_amount": 0}
		if index == node_count - 1:
			tile.merge({
				"type_and_idx": 2001, "source_object_id": 1, "kind": "property", "name": "長路住宅",
				"cost": 100, "land_price": 100, "house_price": 50, "upgrade_cost": 50,
				"base_rent": 10, "rent": 10, "rent_by_level": [10, 20, 30, 40, 50, 60], "group": "long"}, true)
		board.append(tile)
	return {
		"schema": "richman4.runtime-map/v1", "version": 1, "id": "Game:98", "name": "長路分岔測試",
		"source": {"edition": "Game", "map_number": 98, "archive": "Game/map.mkf", "entry_index": 1,
			"payload_sha256": "a".repeat(64), "source_file_sha256": "b".repeat(64)},
		"board": board, "start_position": 0, "supports_new_game": true}


func _test_ai_completes_eighteen_step_car_route() -> void:
	var definition := _long_branch_definition()
	var found: Dictionary = {}
	for seed_value in range(1, 10000):
		var game: Object = GameState.new_game_on_board(seed_value, 2, definition)
		if game == null:
			continue
		game.state["players"][0]["vehicles"]["car"] = true
		game.state["players"][0]["vehicle"] = "car"
		game.state["players"][0]["dice_count"] = 3
		var roll_result: Dictionary = game.roll()
		if bool(roll_result.get("ok", false)) and int(roll_result.get("total", 0)) == 18:
			found = {"game": game, "seed": seed_value}
			break
	_expect(not found.is_empty(), "car eighteen-step branch fixture is available")
	if found.is_empty():
		return
	var game: Object = found["game"]
	game.set_player_ai(0, true)
	var result: Dictionary = game.run_ai_turn()
	_expect(bool(result.get("ok", false)), "AI completes an eighteen-step car route")
	_expect_equal(result.get("completed", false), true, "eighteen-step AI result is explicitly complete")
	_expect(int(result.get("iterations", 99)) <= 16, "car route does not expand the AI action budget")
	_expect_equal(result.get("route_iterations", -1), 18, "car route uses a separate route budget")
	_expect(game.state.get("phase", "") != "await_route", "eighteen-step AI route does not remain pending")
	_expect_equal(game.state.get("remaining_steps", -1), 0, "eighteen-step route consumes all movement")
	_expect_equal(game.state.get("route_options", []), [], "eighteen-step route clears choices")
	var route_choices := 0
	for event in game.state.get("event_log", []):
		if event.get("type", "") == "route_chosen":
			route_choices += 1
	_expect_equal(route_choices, 18, "AI chooses one branch for every car step")


func _test_graph_save_positions() -> void:
	var game: Object = _new_graph(42)
	var saved: Dictionary = game.to_dict()
	var bad_previous: Dictionary = saved.duplicate(true)
	bad_previous["players"][0]["previous_position"] = saved["board"].size()
	_expect(not bool(GameState.validate_save(bad_previous).get("ok", false)), "previous position beyond board is rejected")
	var isolated: Dictionary = saved.duplicate(true)
	var extra: Dictionary = isolated["board"][0].duplicate(true)
	extra["index"] = isolated["board"].size()
	extra["source_node_id"] = int(extra["index"]) + 1
	extra["adjacent"] = []
	isolated["board"].append(extra)
	_expect(bool(GameState.validate_save(isolated).get("ok", false)), "isolated non-property source node remains valid for browsing")
	isolated["players"][0]["position"] = extra["index"]
	_expect(not bool(GameState.validate_save(isolated).get("ok", false)), "player on isolated source node is rejected")
	for phase in ["await_roll", "await_route"]:
		var empty: Dictionary = saved.duplicate(true)
		empty["board"] = []
		empty["start_position"] = 0
		empty["phase"] = phase
		if phase == "await_route":
			empty["route_options"] = [0]
			empty["remaining_steps"] = 1
			empty["pending_movement"] = {"player_id": 0, "current_node": 0, "previous_node": -1}
		var result: Dictionary = GameState.validate_save(empty)
		_expect(result.has("ok") and result.has("errors"), "empty graph validation returns a result in " + phase)
		_expect(not bool(result.get("ok", true)), "empty graph is rejected in " + phase)

func _test_unowned_improvements_rejected() -> void:
	var game = _new_graph(42)
	var snapshot: Dictionary = game.to_dict()
	for tile in snapshot.board:
		if tile.kind == "property":
			tile.building_level = 3
			tile.rent = tile.rent_by_level[3]
			break
	_expect(not GameState.validate_save(snapshot).ok, "unowned graph property cannot contain improvements")
	_expect(GameState.from_dict(snapshot) == null, "unowned improvement save cannot load")
