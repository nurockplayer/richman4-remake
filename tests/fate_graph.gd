extends SceneTree
const Maps = preload("res://game/content/original_maps.gd")
const Game = preload("res://game/core/game_state.gd")
const Base = preload("res://tests/fixtures/news_fixture.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	check(Maps.classify_source_node(0, 3).kind == "fate", "event3 ordinary road classifies fate")
	check(Maps.classify_source_node(2001, 3).kind == "property", "property precedes fate event")
	check(Maps.classify_source_node(4001, 3, true).kind == "facility", "facility precedes fate event")
	check(Maps.classify_source_node(8001, 3).kind == "unsupported", "hospital object is not a fate road")
	check(Maps.classify_source_node(0, 2).kind == "news", "news remains available")
	check(Maps.classify_source_node(0, 4).kind == "unsupported", "other unsupported event remains unsupported")
	var definition: Dictionary = Base.definition()
	definition.board.back().event_code = 3
	definition.board.back().source_status_bits = 3
	definition.board.back().kind = "unsupported"
	var game: Object = Game.new_game_on_board(5601, 4, definition, Base.new_game_options())
	check(game != null, "old source graph fixture constructs")
	if game != null:
		var saved: Dictionary = game.to_dict()
		var restored: Object = Game.from_dict(JSON.parse_string(JSON.stringify(saved)))
		check(restored != null, "old unsupported fate road loads through one migration")
		if restored != null:
			check(restored.state.board.back().kind == "fate", "load migrates event3 kind")
			check(not restored.state.has("fate"), "migration does not draw or create deck")
			game.state.board.back().kind = "fate"
			check(restored.to_json() == game.to_json(), "kind migration preserves every other field including RNG")
			check(Game.validate_save(restored.to_dict()).get("ok", false), "migrated graph validates")
			var before_rng: int = restored._rng.state
			restored._graph_visit_tile(0, restored.state.board.back(), false)
			check(not restored.state.has("fate"), "passing fate does not create a deck")
			check(int(restored.state.players[0].cash) == int(game.state.players[0].cash), "passing fate does not change cash")
			check(restored._rng.state == before_rng, "passing fate does not consume RNG")
	print("Fate graph checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
