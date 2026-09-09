extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/hazard_fixture.gd")
const StatusFixture = preload("res://tests/fixtures/status_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")
const BaseFixture = preload("res://tests/fixtures/original_map_fixture.gd")

var checks := 0
var failures := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func make_hazard_game(seed_value: int = 3401) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"original_statuses": true,
		"original_hazards": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	expect(game != null, "hazard save fixture starts")
	if game == null:
		return null
	for player_id in range(4):
		game.set_player_ai(player_id, false)
	game.state.god_objects = []
	game._set_action_options(0)
	return game


func set_turn(game: Object, player_id: int, phase: String = "await_roll") -> void:
	game.state.current_player = player_id
	game.state.phase = phase
	game.state.route_options = []
	game.state.remaining_steps = 0
	game.state.pending_movement = {}
	game.state.pending_remote_dice = {}
	game._set_action_options(player_id)


func remote_roll(game: Object, player_id: int, value: int) -> Dictionary:
	set_turn(game, player_id, "await_roll")
	game.state.pending_remote_dice = {"player_id": player_id, "value": value}
	game._set_action_options(player_id)
	return game.roll()


func reject(data: Dictionary, message: String) -> void:
	var validation: Dictionary = Game.validate_save(data)
	expect(not bool(validation.get("ok", false)), message + " validation")
	expect(Game.from_dict(data) == null, message + " JSON restore")


func _test_v9_roundtrip_and_route_overlap() -> void:
	var game: Object = make_hazard_game(3401)
	if game == null:
		return
	var initial: Dictionary = game.to_dict()
	expect(bool(Game.validate_save(initial).get("ok", false)), "fresh v9 snapshot validates")
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null, "fresh v9 JSON restores")
	if restored != null:
		expect(restored.to_json() == game.to_json(), "fresh v9 JSON roundtrip is exact")

	set_turn(game, 0, "await_roll")
	expect(game.choose_action("use_tool", {"tool_id": "地雷", "tile_id": 2}).get("ok", false), "v9 ground hazard can be serialized")
	var ground_json: String = game.to_json()
	var ground_restored: Object = Game.from_dict(JSON.parse_string(ground_json))
	expect(ground_restored != null, "ground mine JSON restores")
	if ground_restored != null:
		expect(ground_restored.to_json() == ground_json, "ground mine JSON roundtrip is exact")

	# A route pause is allowed to retain an unbound god on the moving player's
	# current node. This is the saveable passing state introduced by v9.
	var route_game: Object = make_hazard_game(3402)
	if route_game == null:
		return
	route_game.state.god_objects = [{"id": 1, "node": 1, "owner": -1, "days": 0}]
	set_turn(route_game, 0, "await_roll")
	var route_roll: Dictionary = remote_roll(route_game, 0, 2)
	expect(route_roll.get("ok", false) and route_game.state.phase == "await_route", "v9 route pause is reached")
	expect(int(route_game.state.remaining_steps) > 0, "route pause retains remaining steps")
	var route_snapshot: Dictionary = route_game.to_dict()
	expect(bool(Game.validate_save(route_snapshot).get("ok", false)), "route pause with actor overlap validates")
	var route_restored: Object = Game.from_dict(JSON.parse_string(route_game.to_json()))
	expect(route_restored != null, "route pause with actor overlap restores")
	if route_restored != null:
		expect(route_restored.to_json() == route_game.to_json(), "route overlap save roundtrip is exact")
		expect(route_restored.choose_route(int(route_restored.state.route_options[0])).get("ok", false), "restored route accepts the same branch")
		expect(route_game.choose_route(int(route_game.state.route_options[0])).get("ok", false), "original route accepts the same branch")
		expect(route_restored.to_json() == route_game.to_json(), "route continuation remains deterministic")


func _test_carried_bomb_roundtrip() -> void:
	var game: Object = make_hazard_game(3403)
	if game == null:
		return
	set_turn(game, 0, "await_roll")
	expect(game.choose_action("use_tool", {"tool_id": "定時炸彈", "tile_id": 2}).get("ok", false), "bomb ground fixture is placed")
	var pickup_roll: Dictionary = remote_roll(game, 1, 1)
	expect(pickup_roll.get("ok", false) and game.state.route_options.has(2), "bomb pickup route is available")
	expect(game.choose_route(2).get("ok", false), "bomb pickup route resolves")
	expect(int(game.state.players[1].bomb_steps) == Game.MAX_BOMB_STEPS, "carried bomb stores 38 steps")
	var saved_json: String = game.to_json()
	var restored: Object = Game.from_dict(JSON.parse_string(saved_json))
	expect(restored != null, "carried bomb JSON restores")
	if restored == null:
		return
	expect(restored.to_json() == saved_json, "carried bomb JSON roundtrip is exact")
	var original_next: Dictionary = remote_roll(game, 1, 1)
	var restored_next: Dictionary = remote_roll(restored, 1, 1)
	expect(original_next.get("ok", false) and restored_next.get("ok", false), "both carried bomb continuations roll")
	expect(game.to_json() == restored.to_json(), "carried countdown continuation replays exactly")
	expect(int(game.state.players[1].bomb_steps) == Game.MAX_BOMB_STEPS - 1, "one actual edge decrements the carried bomb")


func _test_status_anchor_hazard_overlap() -> void:
	# Status admission teleports to a canonical anchor. The hazard stays on the
	# ground and must not be treated as a normal occupied-road corruption.
	var cases: Array = [
		{"kind": "hospital", "tool_id": "地雷", "ground_kind": "mine", "player_id": 1},
		{"kind": "prison", "tool_id": "定時炸彈", "ground_kind": "timed_bomb", "player_id": 2},
	]
	for index in range(cases.size()):
		var entry: Dictionary = cases[index]
		var game: Object = make_hazard_game(3420 + index)
		if game == null:
			continue
		var anchor: int = game._status_node_index(str(entry.kind))
		set_turn(game, 0, "await_roll")
		var placement: Dictionary = game.choose_action("use_tool", {"tool_id": str(entry.tool_id), "tile_id": anchor})
		expect(placement.get("ok", false), str(entry.kind) + " anchor accepts ground hazard placement")
		set_turn(game, int(entry.player_id), "await_action")
		game.state.players[int(entry.player_id)].position = 2
		game.state.players[int(entry.player_id)].previous_position = 1
		var admission: Dictionary = game._admit_player_status(int(entry.player_id), str(entry.kind), 3)
		expect(admission.get("ok", false), str(entry.kind) + " admission uses existing status entry")
		expect(int(game.state.players[int(entry.player_id)].position) == anchor, str(entry.kind) + " admission reaches canonical anchor")
		expect(game.state.ground_hazards.get(str(anchor), {}).get("kind", "") == str(entry.ground_kind), str(entry.kind) + " hazard remains on ground after teleport")
		var active_snapshot: Dictionary = game.to_dict()
		expect(bool(Game.validate_save(active_snapshot).get("ok", false)), str(entry.kind) + " active anchor overlap validates")
		var active_restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		expect(active_restored != null, str(entry.kind) + " active anchor overlap reloads")

		# The terminal status marker is consumed by the next roll. Persist it with
		# stay_next so the existing release path can leave the player at the anchor.
		var player: Dictionary = game.state.players[int(entry.player_id)]
		player[str(entry.kind) + "_days"] = 128
		player["stay_next"] = 1
		player["position"] = anchor
		player["previous_position"] = -1
		set_turn(game, int(entry.player_id), "await_roll")
		var terminal_snapshot: Dictionary = game.to_dict()
		expect(bool(Game.validate_save(terminal_snapshot).get("ok", false)), str(entry.kind) + " terminal release anchor saves")
		var terminal_restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		expect(terminal_restored != null, str(entry.kind) + " terminal release anchor reloads")
		if terminal_restored != null:
			expect(int(terminal_restored.state.players[int(entry.player_id)].position) == anchor and int(terminal_restored.state.players[int(entry.player_id)].stay_next) == 1, str(entry.kind) + " restored release retains anchor")


func _test_v9_shape_rejection() -> void:
	var game: Object = make_hazard_game(3404)
	if game == null:
		return
	var good: Dictionary = game.to_dict()
	expect(bool(Game.validate_save(good).get("ok", false)), "malformation baseline is valid")
	var missing_marker: Dictionary = good.duplicate(true)
	missing_marker.erase("original_hazards")
	reject(missing_marker, "missing original_hazards")
	var missing_ground: Dictionary = good.duplicate(true)
	missing_ground.erase("ground_hazards")
	reject(missing_ground, "missing ground_hazards")
	var false_marker: Dictionary = good.duplicate(true)
	false_marker.original_hazards = false
	reject(false_marker, "false original_hazards")
	var old_version: Dictionary = good.duplicate(true)
	old_version.version = Game.STATUS_SAVE_VERSION
	old_version.erase("original_hazards")
	old_version.ground_hazards = {"2": {"kind": "mine", "placer_id": 0}}
	for player in old_version.players:
		player.erase("bomb_steps")
	reject(old_version, "v8 snapshot containing ground hazard fields")
	var valid_v8: Dictionary = good.duplicate(true)
	valid_v8.version = Game.STATUS_SAVE_VERSION
	valid_v8.erase("original_hazards")
	valid_v8.erase("ground_hazards")
	for player in valid_v8.players:
		player.erase("bomb_steps")
	expect(bool(Game.validate_save(valid_v8).get("ok", false)), "v8 snapshot without hazard fields remains valid")
	expect(Game.from_dict(valid_v8) != null, "v8 snapshot without hazard fields remains loadable")

	for bad_ground in [[], null, "ground", {"2": []}, {"2": {"kind": "mine"}}, {"2": {"kind": "mine", "placer_id": 0, "extra": true}}, {"2": {"kind": "unknown", "placer_id": 0}}, {"2": {"kind": "mine", "placer_id": 9}}, {2: {"kind": "mine", "placer_id": 0}}, {"02": {"kind": "mine", "placer_id": 0}}]:
		var broken: Dictionary = good.duplicate(true)
		broken.ground_hazards = bad_ground
		reject(broken, "malformed ground hazard " + str(bad_ground))

	var occupied: Dictionary = good.duplicate(true)
	occupied.ground_hazards = {"1": {"kind": "mine", "placer_id": 0}}
	reject(occupied, "ground hazard on ordinary occupied node")
	var road_overlap: Dictionary = good.duplicate(true)
	road_overlap.roadblocks = {"2": 0}
	road_overlap.ground_hazards = {"2": {"kind": "mine", "placer_id": 0}}
	reject(road_overlap, "ground hazard overlaps roadblock")
	var god_overlap: Dictionary = good.duplicate(true)
	god_overlap.god_objects = [{"id": 1, "node": 2, "owner": -1, "days": 0}]
	god_overlap.ground_hazards = {"2": {"kind": "mine", "placer_id": 0}}
	reject(god_overlap, "ground hazard overlaps unbound god")

	for bad_steps in [-1, 39, 0.5, "1", null, {}, []]:
		var broken_steps: Dictionary = good.duplicate(true)
		broken_steps.players[0].bomb_steps = bad_steps
		reject(broken_steps, "invalid bomb_steps " + str(bad_steps))


func _test_legacy_versions_and_pool_replay() -> void:
	var legacy_v1: Object = Game.new_game(3501, 2)
	expect(legacy_v1 != null and int(legacy_v1.state.version) == Game.SAVE_VERSION, "v1 game remains constructible")
	if legacy_v1 != null:
		expect(Game.from_dict(JSON.parse_string(legacy_v1.to_json())) != null, "v1 save remains loadable")

	var legacy_v3: Object = Game.new_game(3502, 2, {"start_date": {"year": 1998, "month": 1, "day": 1}})
	expect(legacy_v3 != null and int(legacy_v3.state.version) == Game.SETUP_SAVE_VERSION, "v3 setup save remains constructible")
	if legacy_v3 != null:
		expect(Game.from_dict(JSON.parse_string(legacy_v3.to_json())) != null, "v3 save remains loadable")

	var legacy_raw: Dictionary = BaseFixture.make()
	var legacy_loaded: Dictionary = Maps.normalize_map(legacy_raw, false)
	var legacy_definition: Dictionary = legacy_loaded.get("definition", {})
	var legacy_v2: Object = Game.new_game_on_board(3503, 2, legacy_definition, {})
	expect(legacy_v2 != null and int(legacy_v2.state.version) == Game.GRAPH_SAVE_VERSION, "v2 graph save remains constructible")
	if legacy_v2 != null:
		expect(Game.from_dict(JSON.parse_string(legacy_v2.to_json())) != null, "v2 graph save remains loadable")

	var legacy_options: Array = [
		{"original_facilities": true},
		{"original_facilities": true, "original_gods": true},
		{"original_facilities": true, "original_gods": true, "original_companies": true},
		{"original_facilities": true, "original_gods": true, "original_companies": true, "original_statuses": true},
	]
	var expected_versions: Array = [Game.FACILITY_SAVE_VERSION, Game.GODS_SAVE_VERSION, Game.COMPANY_SAVE_VERSION, Game.STATUS_SAVE_VERSION]
	for index in range(legacy_options.size()):
		var options: Dictionary = legacy_options[index].duplicate(true)
		options["start_date"] = {"year": 1998, "month": 1, "day": 1}
		var legacy: Object = Game.new_game_on_board(3504 + index, 4, StatusFixture.definition(), options)
		expect(legacy != null and int(legacy.state.version) == int(expected_versions[index]), "legacy v%d remains constructible" % int(expected_versions[index]))
		if legacy == null:
			continue
		var data: Dictionary = legacy.to_dict()
		expect(Game.validate_save(data).get("ok", false), "legacy v%d validates" % int(expected_versions[index]))
		expect(Game.from_dict(JSON.parse_string(legacy.to_json())) != null, "legacy v%d remains loadable" % int(expected_versions[index]))

	# v8 keeps the historical placement lifecycle: consuming a roadblock returns
	# the finite unit immediately. v9's flow test covers the changed ownership.
	var status_game: Object = Game.new_game_on_board(3510, 4, StatusFixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"original_statuses": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	expect(status_game != null, "v8 pool fixture starts")
	if status_game != null:
		for player_id in range(4):
			status_game.set_player_ai(player_id, false)
		status_game.state.god_objects = []
		status_game._set_action_options(0)
		var roadblock_pool_before: int = int(status_game.state.inventory_supply.tools["路障"])
		expect(status_game.choose_action("use_tool", {"tool_id": "路障", "tile_id": 2}).get("ok", false), "v8 roadblock placement succeeds")
		expect(int(status_game.state.inventory_supply.tools["路障"]) == roadblock_pool_before + 1, "v8 roadblock placement returns supply")


func _initialize() -> void:
	_test_v9_roundtrip_and_route_overlap()
	_test_carried_bomb_roundtrip()
	_test_status_anchor_hazard_overlap()
	_test_v9_shape_rejection()
	_test_legacy_versions_and_pool_replay()
	print("Hazard save checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
