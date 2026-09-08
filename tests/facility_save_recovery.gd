extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	ui._load_map_catalog("user://facility-recovery-missing-catalog.json")
	var options: Dictionary = ui._default_setup_options(4)
	expect(ui._new_game(42, 4, ui._selected_map_definition, options), "asset-free fallback starts")
	expect(int(ui.state.version) == 4, "asset-free fallback retains nongraph inventory save")
	expect(Game.from_dict(JSON.parse_string(ui.game_state.to_json())) != null, "asset-free UI game survives JSON save and load")
	var forbidden := options.duplicate(true)
	forbidden.original_facilities = true
	expect(Game.new_game(42, 4, forbidden) == null, "classic constructor rejects graph-only facility mode")
	ui.queue_free()
	await process_frame
	var definition: Dictionary = Maps.normalize_map(Fixture.make(), true).definition
	var game = Game.new_game_on_board(42, 2, definition, {"original_facilities": true, "start_date": {"year": 1998, "month": 1, "day": 1}})
	game.roll()
	expect(game.state.phase == "await_route", "roll fixture pauses at route selection")
	var snapshot: Dictionary = JSON.parse_string(game.to_json())
	expect(bool(Game.validate_save(snapshot).ok), "unaltered pending roll snapshot validates")
	var resumed = Game.from_dict(snapshot)
	if resumed != null:
		game.run_ai_match(500)
		resumed.run_ai_match(500)
		expect(game.to_json() == resumed.to_json(), "unaltered route snapshot resumes identically")
	for changed_total in range(19):
		if changed_total == int(snapshot.last_total):
			continue
		var malformed := snapshot.duplicate(true)
		malformed.last_roll_total = changed_total
		expect(not bool(Game.validate_save(malformed).ok), "reject inconsistent preserved total %d" % changed_total)
	print("Facility save recovery checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
