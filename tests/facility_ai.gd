extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
var checks := 0
var failures := 0
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func visit(game: Object, index: int) -> void:
	game.state.current_player = 0
	game.state.players[0].position = index
	game.state.players[0].previous_position = int(game.state.board[index].adjacent[0])
	game.state.phase = "await_action"
	game.state.property_action_used = false
	game._set_action_options(0)
func _initialize() -> void:
	var raw := Fixture.make()
	raw.nodes[2].type_and_idx = 4001
	raw.nodes[3].type_and_idx = 4001
	raw.nodes[4].type_and_idx = 2001
	raw.nodes[4].event_code = 0
	raw.lands.resize(1)
	raw.facilities = [{"id": 1, "display_name": "測試設施", "name_bytes_hex": "74657374000000000000000000000000", "facility_type": 0, "owner": 0, "level": 0, "tmp_state": 0, "land_price": 1000, "price_per_level": 300, "house_price": 300, "reserved_hex": "6400c8002c019001f401"}]
	var definition: Dictionary = Maps.normalize_map(raw, true).definition
	var game = Game.new_game_on_board(42, 2, definition, {"start_date": {"year": 1998, "month": 1, "day": 1}, "original_facilities": true})
	expect(game != null, "AI facility fixture starts")
	if game != null:
		game.set_player_ai(0, true)
		visit(game, 2)
		expect(bool(game.run_ai_turn().get("ok", false)), "AI completes facility purchase turn")
		expect(int(game.state.board[2].owner) == 0 and int(game.state.board[3].owner) == 0, "AI purchases one shared facility")
		expect(int(game.state.board[2].building_level) == 0, "AI land purchase preserves separate build stage")
		visit(game, 3)
		expect(bool(game.run_ai_turn().get("ok", false)), "AI completes construction from second entrance")
		expect(int(game.state.board[2].building_level) == 1 and int(game.state.board[3].building_level) == 1, "AI builds the shared facility on a later visit")
		expect(int(game.state.board[2].facility_type) in [1, 2], "AI chooses an operational upgradeable facility")
		visit(game, 2)
		expect(bool(game.run_ai_turn().get("ok", false)), "AI completes facility upgrade turn")
		expect(int(game.state.board[2].building_level) == 2 and int(game.state.board[3].building_level) == 2, "AI upgrades both entrances as one building")
		var validation: Dictionary = Game.validate_save(game.to_dict())
		expect(bool(validation.get("ok", false)), "AI facility decisions remain save-valid: " + str(validation.get("errors", [])))
		# Facility integration must also preserve the established housing AI.
		game.state.board[4].owner = 0
		game.state.board[4].building_level = 1
		game._sync_state()
		visit(game, 4)
		expect(bool(game.run_ai_turn().get("ok", false)), "AI completes ordinary housing turn")
		expect(int(game.state.board[4].building_level) == 2, "ordinary housing AI still upgrades owned property")
	print("Facility AI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
