extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const MapFixture = preload("res://tests/fixtures/original_map_fixture.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_initial_controls()
	_test_initial_vehicles()
	_test_rejected_options()
	_test_save_metadata()
	print("Setup control checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _options() -> Dictionary:
	return {"start_date": {"year": 1998, "month": 1, "day": 1}, "character_ids": [0, 1, 2]}


func _test_initial_controls() -> void:
	var options := _options()
	options["human_flags"] = [true, true, false]
	var before := JSON.stringify(options)
	var game: Object = Game.new_game(118, 3, options)
	_expect(game != null, "factory accepts the source choice of multiple human characters")
	_expect(JSON.stringify(options) == before, "factory does not mutate caller setup choices")
	if game == null:
		return
	var players: Array = game.state.players
	_expect(players[0].is_human and players[1].is_human and players[2].is_ai, "selected humans and computer opponent are initialized")
	_expect(players[1].cash == 100000 and players[1].deposit == 100000, "second human starts with equal cash and deposit")
	_expect(players[2].cash == 140000 and players[2].deposit == 60000, "computer retains the selected character cash ratio")
	_expect(game.state.bank.deposits == 260000, "bank liability sums the actual opening deposits")
	_expect(game.state.initial_human_flags == [true, true, false], "initial control metadata is retained independently of later AI toggles")
	_expect(game.set_player_ai(1, true), "later delegation can change a human to AI")
	_expect(Game.validate_save(game.to_dict()).ok, "changing current AI control does not invalidate original opening funds")
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	_expect(restored != null, "mixed-control game round-trips validated JSON")
	if restored != null:
		_expect(game.to_json() == restored.to_json(), "mixed-control round-trip preserves exact state and RNG")
		var expected: Dictionary = game.roll()
		var actual: Dictionary = restored.roll()
		_expect(bool(expected.get("ok", false)) and expected == actual and game.to_json() == restored.to_json(), "rolling after reload consumes identical RNG and continues deterministically")
	var all_ai := _options()
	all_ai["human_flags"] = [false, false, false]
	var ai_game: Object = Game.new_game(118, 3, all_ai)
	_expect(ai_game != null and ai_game.state.players.all(func(p: Dictionary) -> bool: return p.is_ai), "factory also supports a deterministic AI-only session")


func _test_initial_vehicles() -> void:
	for inventory in [false, true]:
		var baseline_options := _options()
		baseline_options["original_inventory"] = inventory
		var baseline: Object = Game.new_game(118, 3, baseline_options)
		_expect(baseline != null, "baseline setup remains available")
		if baseline == null:
			continue
		_expect(not baseline.state.has("initial_vehicle") and not baseline.state.has("initial_human_flags"), "omitted setup options keep the existing snapshot shape")
		for vehicle in ["walking", "motorcycle", "car"]:
			var options := baseline_options.duplicate(true)
			options["initial_vehicle"] = vehicle
			var game: Object = Game.new_game(118, 3, options)
			_expect(game != null, "factory accepts initial %s with inventory=%s" % [vehicle, inventory])
			if game == null:
				continue
			var maximum := 1 if vehicle == "walking" else 2 if vehicle == "motorcycle" else 3
			for player in game.state.players:
				_expect(player.vehicle == vehicle and player.dice_count == maximum and player.vehicles[vehicle], "every player owns/equips the selected starting vehicle and dice")
			_expect(str(game.state.rng_state_text) == str(baseline.state.rng_state_text), "initial vehicle selection consumes no additional game RNG")
			_expect(Game.validate_save(game.to_dict()).ok, "selected initial vehicle is save-valid")
			if inventory:
				for tool in ["機車", "汽車"]:
					var equipped := 3 if (vehicle == "motorcycle" and tool == "機車") or (vehicle == "car" and tool == "汽車") else 0
					_expect(game.state.inventory_supply.tools[tool] == baseline.state.inventory_supply.tools[tool] - equipped, "equipped starting vehicles deduct exactly once from shared supply")
					_expect(game.state.players.all(func(p: Dictionary) -> bool: return int(p.tools.get(tool, 0)) == 0), "equipping a starting vehicle does not add spare copies")
			if vehicle == "walking":
				var without_metadata: Dictionary = game.to_dict()
				without_metadata.erase("initial_vehicle")
				_expect(JSON.stringify(without_metadata) == JSON.stringify(baseline.to_dict()), "explicit walking changes only its optional source-choice metadata")
	var normalized: Dictionary = Maps.normalize_map(MapFixture.make())
	_expect(bool(normalized.get("ok", false)), "source graph format fixture normalizes")
	if not bool(normalized.get("ok", false)):
		return
	var definition: Dictionary = normalized.definition
	var graph_options := _options()
	graph_options["original_inventory"] = true
	graph_options["initial_vehicle"] = "car"
	graph_options["human_flags"] = [true, true, false]
	var graph: Object = Game.new_game_on_board(118, 3, definition, graph_options)
	_expect(graph != null and Game.validate_save(graph.to_dict()).ok, "source graph factory uses the same validated setup choices")


func _test_rejected_options() -> void:
	for vehicle in ["engineering", "CAR", "", 1, 1.5, true, null]:
		var options := _options()
		options["initial_vehicle"] = vehicle
		_expect(Game.new_game(118, 3, options) == null, "invalid initial vehicle fails before creating a game: " + str(vehicle))
	for flags in [[], [true], [true, false, false, false], [true, 1, false], [true, 1.0, false], [true, "false", false], null, true, {}]:
		var options := _options()
		options["human_flags"] = flags
		_expect(Game.new_game(118, 3, options) == null, "initial control flags require exactly one boolean per player")


func _test_save_metadata() -> void:
	var options := _options()
	options["human_flags"] = [true, true, false]
	options["initial_vehicle"] = "car"
	var game: Object = Game.new_game(118, 3, options)
	_expect(game != null, "save-metadata fixture is admitted through public factory")
	if game == null:
		return
	for bad_flags in [[], [true, false], [true, 1, false], "human"]:
		var bad: Dictionary = game.to_dict()
		bad["initial_human_flags"] = bad_flags
		_expect(not Game.validate_save(bad).ok and Game.from_dict(bad) == null, "malformed initial-control save metadata is rejected")
	var removed: Dictionary = game.to_dict()
	removed.erase("initial_human_flags")
	_expect(not Game.validate_save(removed).ok, "mixed-human opening ratios cannot silently lose their initial-control metadata")
	for bad_vehicle in ["engineering", 2, true, null]:
		var bad: Dictionary = game.to_dict()
		bad["initial_vehicle"] = bad_vehicle
		_expect(not Game.validate_save(bad).ok, "malformed initial-vehicle metadata is rejected")
	var legacy: Object = Game.new_game(118, 3)
	var misplaced: Dictionary = legacy.to_dict()
	misplaced["initial_human_flags"] = [true, true, false]
	_expect(not Game.validate_save(misplaced).ok, "setup metadata cannot be grafted onto a non-setup save")
