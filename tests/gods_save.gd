extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")

var checks: int = 0
var failures: int = 0


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _definition() -> Dictionary:
	var raw: Dictionary = Fixture.make()
	raw["nodes"] = []
	for index in range(18):
		raw["nodes"].append({
			"id": index + 1,
			"x": index * 120,
			"y": (index % 3) * 120,
			"adjacent": [(index + 17) % 18 + 1, (index + 1) % 18 + 1],
			"type_and_idx": 0,
			"event_code": 0,
			"status_bits": 0,
			"visual_index": 0,
		})
	raw["nodes"][2]["type_and_idx"] = 2001
	raw["nodes"][5]["type_and_idx"] = 2002
	for index in [8, 9]:
		raw["nodes"][index]["type_and_idx"] = 4001
	raw["facilities"] = [{
		"id": 1,
		"display_name": "測試設施",
		"name_bytes_hex": "74657374000000000000000000000000",
		"facility_type": 0,
		"owner": 0,
		"level": 0,
		"tmp_state": 0,
		"land_price": 1000,
		"price_per_level": 300,
		"house_price": 300,
		"reserved_hex": "6400c8002c019001f401",
	}]
	var loaded: Dictionary = Maps.normalize_map(raw, true)
	_expect(bool(loaded.get("ok", false)), "save fixture normalizes")
	return loaded.get("definition", {})


func _new_gods_game() -> Game:
	return Game.new_game_on_board(4242, 2, _definition(), {
		"original_facilities": true,
		"original_gods": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
		"day_limit": 0,
	})


func _test_v6_roundtrip() -> void:
	var game: Game = _new_gods_game()
	_expect(game != null, "v6 save fixture starts")
	if game == null:
		return
	var saved: Dictionary = game.to_dict()
	_expect(bool(Game.validate_save(saved).get("ok", false)), "fresh v6 save validates")
	var restored: Game = Game.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_expect(restored != null, "v6 JSON save restores")
	if restored != null:
		_expect_equal(restored.to_json(), game.to_json(), "v6 JSON roundtrip preserves exact state")
		game.state["phase"] = "await_action"
		restored.state["phase"] = "await_action"
		game.end_turn()
		restored.end_turn()
		_expect_equal(restored.to_json(), game.to_json(), "v6 continuation remains deterministic")


func _test_v6_strict_markers() -> void:
	var game: Game = _new_gods_game()
	if game == null:
		return
	var saved: Dictionary = game.to_dict()
	var missing_objects: Dictionary = saved.duplicate(true)
	missing_objects.erase("god_objects")
	_expect(not bool(Game.validate_save(missing_objects).get("ok", false)), "v6 requires god objects")
	var missing_marker: Dictionary = saved.duplicate(true)
	missing_marker.erase("original_gods")
	_expect(not bool(Game.validate_save(missing_marker).get("ok", false)), "v6 requires original gods marker")
	var missing_player_field: Dictionary = saved.duplicate(true)
	missing_player_field["players"][0].erase("god_id")
	_expect(not bool(Game.validate_save(missing_player_field).get("ok", false)), "v6 requires player god id")
	var duplicate_object: Dictionary = saved.duplicate(true)
	duplicate_object["god_objects"].append(duplicate_object["god_objects"][0].duplicate(true))
	_expect(not bool(Game.validate_save(duplicate_object).get("ok", false)), "duplicate god objects are rejected")
	var owner_mismatch: Dictionary = saved.duplicate(true)
	owner_mismatch["god_objects"][0]["owner"] = 0
	owner_mismatch["god_objects"][0]["days"] = 1
	_expect(not bool(Game.validate_save(owner_mismatch).get("ok", false)), "attached god owner mismatch is rejected")
	var invalid_days: Dictionary = saved.duplicate(true)
	invalid_days["god_objects"][0]["days"] = 14
	_expect(not bool(Game.validate_save(invalid_days).get("ok", false)), "god day range is bounded")
	var invalid_id: Dictionary = saved.duplicate(true)
	invalid_id["god_objects"][0]["id"] = 99
	_expect(not bool(Game.validate_save(invalid_id).get("ok", false)), "unknown god id is rejected")


func _test_v6_effect_state_and_legacy() -> void:
	var game: Game = _new_gods_game()
	if game == null:
		return
	var saved: Dictionary = game.to_dict()
	var improved_unowned: Dictionary = saved.duplicate(true)
	var property: Dictionary = improved_unowned["board"][2]
	property["owner"] = -1
	property["building_level"] = 1
	game._update_tile_rent(property)
	var improved_validation: Dictionary = Game.validate_save(improved_unowned)
	_expect(bool(improved_validation.get("ok", false)), "v6 permits an unowned god-improved property: " + str(improved_validation.get("errors", [])))

	var facility_game: Game = Game.new_game_on_board(4242, 2, _definition(), {"original_facilities": true, "start_date": {"year": 1998, "month": 1, "day": 1}})
	_expect(facility_game != null, "v5 facility fixture starts")
	if facility_game != null:
		var legacy: Dictionary = facility_game.to_dict()
		_expect_equal(int(legacy.get("version", -1)), 5, "legacy facility save remains v5")
		_expect(bool(Game.validate_save(legacy).get("ok", false)), "v5 facility save remains valid")
		var legacy_improved: Dictionary = legacy.duplicate(true)
		legacy_improved["board"][2]["owner"] = -1
		legacy_improved["board"][2]["building_level"] = 1
		_expect(not bool(Game.validate_save(legacy_improved).get("ok", false)), "v5 rejects unowned improvements")
	var wrong_marker: Dictionary = saved.duplicate(true)
	wrong_marker["original_gods"] = false
	_expect(not bool(Game.validate_save(wrong_marker).get("ok", false)), "disabled v6 marker is rejected")


func _test_unbound_spawn_validation() -> void:
	var game := _new_gods_game()
	var saved: Dictionary = game.to_dict()
	var unbound_death: Dictionary = saved.duplicate(true)
	unbound_death.god_objects[0].id=15
	_expect(not Game.validate_save(unbound_death).get("ok",false),"unsupported unbound death cannot validate")
	_expect(Game.from_dict(JSON.parse_string(JSON.stringify(unbound_death)))==null,"unsupported unbound death cannot load")
	var attached_death: Dictionary = unbound_death.duplicate(true)
	attached_death.god_objects[0].owner=0
	attached_death.god_objects[0].node=0
	attached_death.god_objects[0].days=13
	attached_death.players[0].god_id=15
	_expect(Game.validate_save(attached_death).get("ok",false),"already attached death remains supported")
	_expect(Game.from_dict(JSON.parse_string(JSON.stringify(attached_death)))!=null,"attached death continuation can load")

	var masked: Dictionary = saved.duplicate(true)
	var node: int = int(masked.god_objects[0].node)
	masked.board[node].source_status_bits = 0x100
	var without_gods: Dictionary = masked.duplicate(true)
	without_gods.god_objects=[]
	_expect(Game.validate_save(without_gods).get("ok",false),"masked board remains otherwise valid")
	_expect(not Game.validate_save(masked).get("ok",false),"unbound god on source-masked node is rejected")
	_expect(Game.from_dict(JSON.parse_string(JSON.stringify(masked)))==null,"masked unbound god cannot load")
	var isolated: Dictionary = saved.duplicate(true)
	for i in range(18,20):
		var tile: Dictionary = saved.board[0].duplicate(true)
		tile.index=i
		tile.source_node_id=i+1
		tile.adjacent=[19 if i==18 else 18]
		isolated.board.append(tile)
	isolated.god_objects=[]
	_expect(Game.validate_save(isolated).get("ok",false),"unreachable non-property component remains otherwise valid")
	isolated.god_objects=[{"id":1,"node":18,"owner":-1,"days":0}]
	_expect(not Game.validate_save(isolated).get("ok",false),"unbound god outside reachable component is rejected")
	_expect(Game.from_dict(JSON.parse_string(JSON.stringify(isolated)))==null,"unreachable unbound god cannot load")
	var attached: Dictionary = saved.duplicate(true)
	attached.board[0].source_status_bits=0x100
	attached.god_objects[0].owner=0
	attached.god_objects[0].node=0
	attached.god_objects[0].days=7
	attached.players[0].god_id=attached.god_objects[0].id
	_expect(Game.validate_save(attached).get("ok",false),"attached god can follow owner onto a non-spawnable node")


func _initialize() -> void:
	_test_v6_roundtrip()
	_test_v6_strict_markers()
	_test_v6_effect_state_and_legacy()
	_test_unbound_spawn_validation()
	print("God save checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
