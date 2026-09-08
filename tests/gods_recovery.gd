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
func new_game() -> Object:
	var raw := Fixture.make()
	raw.nodes[2].type_and_idx = 4001
	raw.nodes[3].type_and_idx = 4001
	raw.nodes[4].type_and_idx = 2001
	raw.nodes[4].event_code = 0
	raw.lands.resize(1)
	raw.facilities = [{"id": 1, "display_name": "測試設施", "name_bytes_hex": "74657374000000000000000000000000", "facility_type": 0, "owner": 0, "level": 0, "tmp_state": 0, "land_price": 1000, "price_per_level": 300, "house_price": 300, "reserved_hex": "6400c8002c019001f401"}]
	var loaded: Dictionary = Maps.normalize_map(raw, true)
	var game = Game.new_game_on_board(42, 2, loaded.definition, {"original_facilities": true, "original_gods": true, "start_date": {"year": 1998, "month": 1, "day": 1}})
	game.state.god_objects = []
	return game
func rejects(saved: Dictionary, message: String) -> void:
	expect(not Game.validate_save(saved).get("ok", false), message)
	expect(Game.from_dict(JSON.parse_string(JSON.stringify(saved))) == null, message + " through JSON restore")
func _initialize() -> void:
	var game = new_game()
	var saved: Dictionary = game.to_dict()
	expect(Game.validate_save(saved).get("ok", false), "recovery base is valid")
	var attached: Dictionary = saved.duplicate(true)
	attached.players[0].god_id = 1
	attached.god_objects = [{"id": 1, "node": attached.players[0].position, "owner": 0, "days": 7}]
	expect(Game.validate_save(attached).get("ok", false), "attached recovery control is valid")
	var extended: Dictionary = attached.duplicate(true)
	extended.god_objects[0].days = 8
	rejects(extended, "ordinary god cannot have more than seven days")
	var ghost_owner: Dictionary = attached.duplicate(true)
	ghost_owner.players[1].god_id = 1
	rejects(ghost_owner, "a second player cannot claim the first player's god")
	var duplicate_node: Dictionary = saved.duplicate(true)
	duplicate_node.god_objects = [{"id": 1, "node": 2, "owner": -1, "days": 0}, {"id": 3, "node": 2, "owner": -1, "days": 0}]
	rejects(duplicate_node, "two unbound gods cannot occupy one node")
	for unsupported_id in [13, 14]:
		var unsupported: Dictionary = saved.duplicate(true)
		unsupported.god_objects = [{"id": unsupported_id, "node": 2, "owner": -1, "days": 0}]
		rejects(unsupported, "unsupported pickup cannot enter a playable save: %d" % unsupported_id)
	for bad_flags in [-1, 4294967296, 0.5, "0", 11]:
		var malformed: Dictionary = saved.duplicate(true)
		malformed.board[0].source_status_bits = bad_flags
		rejects(malformed, "source status flags must remain valid and agree with event byte: %s" % str(bad_flags))
	# Existing buildings on unowned commercial lots are reachable via angel effects.
	for god_id in [0, 4]:
		var buying = new_game()
		buying.state.players[0].position = 2
		buying.state.players[0].previous_position = 1
		buying.state.players[0].god_id = god_id
		if god_id != 0:
			buying.state.god_objects = [{"id": god_id, "node": 2, "owner": 0, "days": 7}]
		for node in [2, 3]:
			buying.state.board[node].building_level = 3
			buying.state.board[node].facility_type = 1
		buying.state.phase = "await_action"
		buying._set_action_options(0)
		buying._recalculate_property_values()
		var before_buy: Dictionary = buying.to_dict()
		expect(Game.validate_save(before_buy).get("ok", false), "unowned improved facility is a valid pre-purchase state")
		var cash_before: int = buying.state.players[0].cash
		var result: Dictionary = buying.choose_action("buy")
		expect(result.get("ok", false), "existing facility can be purchased without changing its type")
		expect(int(buying.state.players[0].cash) == cash_before - 1000, "existing facility purchase charges only land price")
		for node in [2, 3]:
			expect(int(buying.state.board[node].owner) == 0 and int(buying.state.board[node].facility_type) == 1 and int(buying.state.board[node].building_level) == (4 if god_id == 4 else 3), "purchase preserves the built facility and applies only the eligible fortune level")
		expect(Game.validate_save(buying.to_dict()).get("ok", false), "purchased facility remains save-valid")
	var legacy = Game.new_game(42, 2)
	legacy.state.players[0].rent_shield = 1
	legacy._charge_rent(0, 1, 0)
	expect(int(legacy.state.players[0].rent_shield) == 0, "legacy zero rent preserves its prior shield consumption")
	expect(legacy.state.last_event.get("type", "") == "rent_blocked", "legacy zero rent preserves its prior event")
	print("God recovery checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
