extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func make_definition() -> Dictionary:
	var raw := Fixture.make()
	raw.nodes = []
	for index in range(18):
		raw.nodes.append({"id": index + 1, "x": index * 120, "y": (index % 3) * 120,
			"adjacent": [(index + 17) % 18 + 1, (index + 1) % 18 + 1],
			"type_and_idx": 0, "event_code": 0, "status_bits": 0, "visual_index": 0})
	raw.nodes[2].type_and_idx = 2001
	raw.nodes[5].type_and_idx = 2002
	for index in [8, 9]:
		raw.nodes[index].type_and_idx = 4001
	raw.facilities = [{"id": 1, "display_name": "測試設施", "name_bytes_hex": "74657374000000000000000000000000", "facility_type": 0, "owner": 0, "level": 0, "tmp_state": 0, "land_price": 1000, "price_per_level": 300, "house_price": 300, "reserved_hex": "6400c8002c019001f401"}]
	var loaded: Dictionary = Maps.normalize_map(raw, true)
	expect(bool(loaded.get("ok", false)), "AI source-ring fixture normalizes")
	return loaded.get("definition", {})
func _initialize() -> void:
	var definition := make_definition()
	var observed_gods: Dictionary = {}
	for player_count in [2, 3, 4]:
		for seed_value in [3, 42]:
			var game = Game.new_game_on_board(seed_value, player_count, definition, {"original_facilities": true, "original_gods": true, "start_date": {"year": 1998, "month": 1, "day": 1}, "day_limit": 30})
			expect(game != null, "God AI game starts for %d players, seed %d" % [player_count, seed_value])
			if game == null:
				continue
			expect(int(game.state.version) == 6 and game.state.god_objects.size() == 6, "six initial actors are active in the match")
			for player_id in range(player_count):
				game.set_player_ai(player_id, true)
			var resumed: Object = null
			for turn_index in range(200):
				if game.state.phase == "game_over":
					break
				var result: Dictionary = game.run_ai_turn()
				expect(bool(result.get("ok", false)), "AI advances through god, dog and ordinary turns")
				var valid: Dictionary = Game.validate_save(game.to_dict())
				expect(bool(valid.get("ok", false)), "every AI turn remains save-valid: " + str(valid.get("errors", [])))
				if not bool(result.get("ok", false)) or not bool(valid.get("ok", false)):
					break
				for event in game.state.event_log:
					if event.get("type", "") in ["god_attached", "dog_encounter"]:
						observed_gods[int(event.get("god_id", 11))] = true
				if resumed != null:
					var continuation: Dictionary = resumed.run_ai_turn()
					expect(bool(continuation.get("ok", false)) and resumed.to_json() == game.to_json(), "JSON continuation reproduces each later AI turn")
				elif turn_index == 7:
					resumed = Game.from_dict(JSON.parse_string(game.to_json()))
					expect(resumed != null, "mid-match god state restores through JSON")
			expect(game.state.phase == "game_over", "bounded god AI match finishes")
			expect(int(game.state.get("elapsed", -1)) == 30, "match reaches configured thirty-day settlement")
			expect(resumed != null and resumed.to_json() == game.to_json(), "final settlement is identical after restore")
	expect(observed_gods.size() >= 4, "AI production path encountered multiple different gods")
	print("God AI checks: %d, failures: %d; encountered IDs: %s" % [checks, failures, str(observed_gods.keys())])
	quit(1 if failures else 0)
