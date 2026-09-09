extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/fate_fixture.gd")
const Fate = preload("res://game/core/fate_events.gd")
const LegacyFixture = preload("res://tests/fixtures/original_map_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func arm(game: Object, first: int) -> void:
	var order: Array = [first, 20]
	for id in range(37):
		if id not in order: order.append(id)
	game.state.fate = {"order":order,"cursor":0,"draw_count":0,"last":{}}
func verify(game: Object, label: String) -> void:
	check(Game.validate_save(game.to_dict()).get("ok", false), label + " validates")
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	check(restored != null and restored.to_json() == game.to_json(), label + " JSON round-trip")
func _initialize() -> void:
	var valid: Object = Fixture.new_game(5660)
	arm(valid, 21)
	valid._graph_visit_tile(0, valid.state.board.back(), true)
	verify(valid, "completed result")
	for outcome in ["unsupported", "unresolved"]:
		var invalid: Dictionary = valid.to_dict()
		invalid.fate.last.outcome = outcome
		check(not Game.validate_save(invalid).get("ok", true), "noncanonical outcome is rejected")
		check(Game.from_dict(invalid) == null, "noncanonical outcome cannot load")
	for id in [33,34,35,36]:
		var game: Object = Fixture.new_game(5660, 4, 5)
		arm(game, id)
		verify(game, "outside source map range input")
		check(not Fate.has_eligible_target(game, id), "map5 never admits map1-4 prison candidate")
		game._graph_visit_tile(0, game.state.board.back(), true)
		check(int(game.state.fate.last.id) == 20 and int(game.state.players[0].prison_days) == 0, "outside-map candidate skips to next supported candidate")
		verify(game, "outside source map range result")
	for id in [12, 15, 33]:
		var source: Dictionary = LegacyFixture.make()
		source.nodes[0].type_and_idx = 0
		source.nodes[5].type_and_idx = 0
		source.nodes[5].event_code = 3
		var normalized: Dictionary = Maps.normalize_map(source)
		check(normalized.get("ok", false), "legacy map without status destinations normalizes")
		var game: Object = Game.new_game_on_board(5660, 2, normalized.definition)
		check(game != null, "legacy map without status destinations constructs")
		if game == null: continue
		arm(game, id)
		verify(game, "missing destination input")
		check(not Fate.has_eligible_target(game, id), "missing destination makes status candidate ineligible")
		var cards: Array = game.state.players[0].cards.duplicate()
		game._graph_visit_tile(0, game.state.board.back(), true)
		check(int(game.state.fate.last.id) == 20, "missing destination skips to cash reward")
		check(game.state.players[0].cards == cards and int(game.state.players[0].hospital_days) == 0, "skipped unavailable status preserves cards and status")
		verify(game, "missing destination result")
	print("Fate state contract checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
