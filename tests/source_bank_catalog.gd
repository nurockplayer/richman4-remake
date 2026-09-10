extends "res://tests/source_title_ui.gd"

## Normal-ingress coverage for the original catalog bank encounter.
##
## The search is deliberately performed by the public core surface first.  It
## records only a seed and route choices, then replays those same public
## actions through MainUI.  No position, pending token, or complete game
## snapshot is injected into either side of the check.

const Core = preload("res://game/core/game_state.gd")

const PLAYER_COUNT := 4
const SEARCH_SEED_LIMIT := 64
const SEARCH_ROUTE_LIMIT := 8
const CATALOG_MAP_COUNT := 12

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var catalog_path := OS.get_environment("RICHMAN4_MAP_CATALOG")
	if catalog_path.is_empty():
		print("SKIP: RICHMAN4_MAP_CATALOG is absent; original catalog bank coverage is not applicable")
		quit(0)
		return
	call_deferred("run")


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _settle() -> void:
	await process_frame
	await process_frame


func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	viewport.notify_mouse_entered()

	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await _settle()
	ui.set_process(false)

	_expect(ui._map_catalog_ok and ui._map_catalog_complete, "actual catalog loads as a complete normal-ingress catalog")
	_expect(ui._map_catalog.size() == CATALOG_MAP_COUNT, "actual catalog exposes all twelve source maps")
	if not (ui._map_catalog_ok and ui._map_catalog_complete):
		viewport.queue_free()
		await _settle()
		print("Source bank catalog checks: %d, failures: %d" % [_checks, _failures])
		quit(1)
		return

	await _run_catalog_case(ui, viewport, "Game", 3)
	await _run_catalog_case(ui, viewport, "MultiverseJourney", 7)

	viewport.queue_free()
	await _settle()
	print("Source bank catalog checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures else 0)


func _run_catalog_case(ui: Control, viewport: SubViewport, edition: String, map_number: int) -> void:
	var definition := _find_map(ui, edition, map_number)
	_expect(not definition.is_empty(), "%s map %d is present in the actual catalog" % [edition, map_number])
	if definition.is_empty():
		return

	var setup_options: Dictionary = ui._default_setup_options(PLAYER_COUNT, definition)
	_expect(bool(setup_options.get("original_companies", false)), "%s map %d default setup enables companies" % [edition, map_number])
	_expect(bool(setup_options.get("original_facilities", false)), "%s map %d default setup enables facilities" % [edition, map_number])
	var plan := _find_core_bank_plan(definition, setup_options)
	_expect(not plan.is_empty(), "%s map %d reaches a bank through public core movement" % [edition, map_number])
	if plan.is_empty():
		return

	var seed := int(plan.get("seed", 0))
	var route_choices: Array = plan.get("route_choices", [])
	var expected_token: Dictionary = plan.get("token", {})
	_expect(seed >= 1 and seed <= SEARCH_SEED_LIMIT, "%s map %d keeps a bounded replay seed" % [edition, map_number])
	_expect(str(expected_token.get("kind", "")) == "landing", "%s map %d search ends at a landing bank token" % [edition, map_number])

	var started: bool = ui._new_game(seed, PLAYER_COUNT, definition, setup_options)
	_expect(started, "%s map %d starts through MainUI._new_game" % [edition, map_number])
	await _settle()
	if not started or ui.game_state == null:
		return

	var game: Object = ui.game_state
	_expect(str(ui.source_shell.get("_source_edition")) == edition, "%s map %d updates the source edition" % [edition, map_number])
	_expect(game.get_stock_symbols().size() == 12, "%s map %d exposes twelve stock symbols" % [edition, map_number])
	_expect(bool(ui.state.get("original_companies", false)) and bool(ui.state.get("original_facilities", false)), "%s map %d preserves source capability flags" % [edition, map_number])
	_expect(Core.validate_save(game.to_dict()).get("ok", false), "%s map %d initial source save validates" % [edition, map_number])

	ui._on_roll_pressed()
	await _settle()
	for route_value in route_choices:
		if str(ui.state.get("phase", "")) != "await_route":
			break
		ui._on_route_selected(int(route_value))
		await _wait_for_presentation(ui)

	var controller: Control = ui.source_bank_controller
	_expect(controller != null, "%s map %d builds the source bank controller" % [edition, map_number])
	if controller == null:
		return
	var panel: Control = controller.bank_panel
	var actual_token: Dictionary = game.pending_bank_visit()
	_expect(controller.is_open() and str(ui.state.get("phase", "")) == "await_action", "%s map %d opens the ATM on landing" % [edition, map_number])
	_expect(actual_token == expected_token and str(actual_token.get("kind", "")) == "landing", "%s map %d exposes the authoritative landing token" % [edition, map_number])
	var token_keys: Array = actual_token.keys()
	token_keys.sort()
	_expect(token_keys == ["kind", "node_id", "player_id"] and int(actual_token.get("player_id", -1)) == 0 and int(actual_token.get("node_id", -1)) == int(expected_token.get("node_id", -2)), "%s map %d landing token has the exact actor and node identity" % [edition, map_number])
	_expect(Core.validate_save(game.to_dict()).get("ok", false), "%s map %d pending landing save validates" % [edition, map_number])
	var snapshot: Variant = game.get_snapshot()
	var snapshot_dict: Dictionary = snapshot if snapshot is Dictionary else {}
	_expect(snapshot is Dictionary and str(snapshot.get("phase", "")) == "await_action", "%s map %d exposes an await_action snapshot" % [edition, map_number])
	_expect(snapshot is Dictionary and Core.validate_save(snapshot_dict).get("ok", false), "%s map %d pending landing snapshot validates" % [edition, map_number])
	var encoded: String = str(game.to_json())
	var decoded: Variant = JSON.parse_string(encoded)
	var decoded_save: Dictionary = decoded if decoded is Dictionary else {}
	_expect(decoded is Dictionary and Core.validate_save(decoded_save).get("ok", false), "%s map %d pending landing JSON round-trips" % [edition, map_number])
	_expect(str(panel.view_model().get("edition", "")) == edition, "%s map %d ATM model keeps the source edition" % [edition, map_number])
	_expect(str(panel.view_model().get("entry_mode", "")) == "atm", "%s map %d landing opens in ATM mode before the bank front" % [edition, map_number])
	_expect(panel.position == Vector2(60, 71), "%s map %d ATM uses the source reference coordinate" % [edition, map_number])
	_expect(controller.get_parent() == ui.source_shell.reference_canvas, "%s map %d ATM uses the source reference canvas" % [edition, map_number])
	_expect(ui._source_modal_open() and ui._load_blocked_by_presentation() and not ui._source_save_operation_allowed(), "%s map %d modal and persistence guards engage" % [edition, map_number])

	press(viewport, panel.find_child("ATMExit", true, false))
	await _settle()
	_expect(controller.is_open() and str(panel.view_model().get("entry_mode", "")) == "loan", "%s map %d landing ATM exit enters the bank front" % [edition, map_number])

	press(viewport, panel.find_child("BankExit", true, false))
	await _settle()
	await _wait_for_presentation(ui)
	_expect(not controller.is_open() and game.pending_bank_visit().is_empty(), "%s map %d bank front close uses the host adapter" % [edition, map_number])
	_expect(str(ui.state.get("phase", "")) == "await_action", "%s map %d releases the board at the landing action phase" % [edition, map_number])
	_expect(not ui._source_modal_open() and not ui._load_blocked_by_presentation() and not ui._presentation_busy, "%s map %d releases modal, load, and movement guards" % [edition, map_number])


func _find_core_bank_plan(definition: Dictionary, setup_options: Dictionary) -> Dictionary:
	for seed_value in range(1, SEARCH_SEED_LIMIT + 1):
		var game: Object = Core.new_game_on_board(seed_value, PLAYER_COUNT, definition, setup_options)
		if game == null:
			continue
		var roll_result: Dictionary = game.roll(1)
		if not bool(roll_result.get("ok", false)):
			continue
		var route_choices: Array = []
		for _step in range(SEARCH_ROUTE_LIMIT):
			var phase := str(game.state.get("phase", ""))
			var token: Dictionary = game.pending_bank_visit()
			if phase == "await_action" and str(token.get("kind", "")) == "landing":
				return {"seed": seed_value, "route_choices": route_choices, "token": token}
			if phase == "await_bank":
				# Only replay plans that reach a landing directly.  A pass pause
				# would require an additional public action that is not recorded in
				# this seed-and-route replay.
				break
			if phase != "await_route":
				break
			var route_options: Variant = game.state.get("route_options", [])
			if not route_options is Array or route_options.is_empty():
				break
			var selected_route := _route_toward_bank(game.state.get("board", []), route_options, definition)
			if selected_route < 0:
				break
			route_choices.append(selected_route)
			var chosen: Dictionary = game.choose_route(selected_route)
			if not bool(chosen.get("ok", false)):
				break
	return {}


func _route_toward_bank(board_value: Variant, options: Array, definition: Dictionary) -> int:
	if not board_value is Array:
		return -1
	var board: Array = board_value
	var bank_nodes: Array = []
	for tile in definition.get("board", []):
		if tile is Dictionary and str(tile.get("kind", "")) == "bank":
			bank_nodes.append(int(tile.get("index", -1)))
	if bank_nodes.is_empty():
		return -1
	var selected := -1
	var selected_distance := 1_000_000
	for route_value in options:
		if typeof(route_value) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var route := int(route_value)
		if route < 0 or route >= board.size():
			continue
		for bank_node in bank_nodes:
			var distance := _graph_distance(board, route, bank_node)
			if distance < selected_distance:
				selected = route
				selected_distance = distance
	return selected


func _graph_distance(board: Array, start: int, goal: int) -> int:
	if start < 0 or start >= board.size() or goal < 0 or goal >= board.size():
		return 1_000_000
	var queue: Array = [start]
	var distances: Dictionary = {start: 0}
	while not queue.is_empty():
		var current := int(queue.pop_front())
		if current == goal:
			return int(distances[current])
		var tile: Variant = board[current]
		if not tile is Dictionary:
			continue
		var adjacent: Variant = tile.get("adjacent", [])
		if not adjacent is Array:
			continue
		for neighbor_value in adjacent:
			var neighbor := int(neighbor_value)
			if neighbor < 0 or neighbor >= board.size() or distances.has(neighbor):
				continue
			distances[neighbor] = int(distances[current]) + 1
			queue.append(neighbor)
	return 1_000_000


func _find_map(ui: Control, edition: String, map_number: int) -> Dictionary:
	for value in ui.get("_map_catalog"):
		if value is Dictionary:
			var source: Dictionary = value.get("source", {})
			if str(source.get("edition", "")) == edition and int(source.get("map_number", 0)) == map_number:
				return value.duplicate(true)
	return {}


func _wait_for_presentation(ui: Control) -> void:
	for _frame in range(500):
		if not bool(ui.get("_presentation_busy")):
			break
		await create_timer(0.01).timeout
	await _settle()
