extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/research_fixture.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func make_game() -> Object:
	var definition: Dictionary = Fixture.definition()
	definition.companies[0].company_type = 11
	var game: Object = Game.new_game_on_board(39512, 4, definition, Fixture.new_game_options())
	expect(game != null, "construction starts real v12 factory")
	if game == null:
		game = Game.new_game_on_board(39512, 4, definition, Fixture.v11_game_options())
		if game == null: return null
		game.state.version = 12
		game.state.original_research = true
		game.state.research_action_used = false
		for tile in game.state.board:
			if tile.kind == "facility":
				tile.research_tool = 0
				tile.research_turns = 0
	game.state.god_objects = []
	game.state.players[0].stocks.s01 = 1
	game.state.companies[0].treasury -= 1
	game._update_company_owners()
	return game
func lab(game: Object, owner: int, level: int) -> void:
	game._update_facility_records(1, {"owner": owner, "facility_type": 4, "building_level": level, "research_tool": 1, "research_turns": 3})
	for player in game.state.players: player.properties.erase(1)
	game.state.players[owner].properties.append(1)
	game._recalculate_property_values()
func landing(game: Object, player_id: int, tile_id: int) -> void:
	game.state.current_player = player_id
	game.state.players[player_id].position = tile_id
	game.state.players[player_id].previous_position = -1
	game.state.phase = "await_action"
	game.state.property_action_used = false
	game.state.last_roll = [1]
	game.state.last_total = 1
	game.state.last_roll_total = 1
	game._set_action_options(player_id)
func attached_god(game: Object, god_id: int) -> void:
	game.state.players[0].god_id = god_id
	game.state.god_objects = [{"id": god_id, "node": 1, "owner": 0, "days": 3}]
func verify_lab(game: Object, level: int, label: String) -> void:
	for index in [1, 6]:
		var tile: Dictionary = game.state.board[index]
		expect(tile.facility_type == 4 and tile.building_level == level, label + " updates each building alias")
		expect(tile.research_tool == 1 and tile.research_turns == 3, label + " preserves each job alias")
	game._set_action_options(int(game.state.current_player))
	var validation: Dictionary = Game.validate_save(game.to_dict())
	expect(validation.get("ok", false), label + " validates: " + str(validation.get("errors", [])))
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(restored != null and restored.to_json() == game.to_json(), label + " reloads exactly")
func _initialize() -> void:
	var angel: Object = make_game()
	if angel != null:
		lab(angel, 0, 4)
		landing(angel, 0, 1)
		attached_god(angel, 9)
		angel._apply_god_property_effect(0, angel.state.board[1], true)
		verify_lab(angel, 5, "angel raises research facility")
		angel._apply_god_property_effect(0, angel.state.board[1], true)
		verify_lab(angel, 5, "angel preserves five-level cap")
	for god_id in [3, 4]:
		var game: Object = make_game()
		if game == null: continue
		lab(game, 0, 1)
		landing(game, 0, 1)
		attached_god(game, god_id)
		expect(game.choose_action("upgrade").get("ok", false), "fortune allows normal lab upgrade")
		verify_lab(game, 3, "fortune adds one level to normal upgrade")
		lab(game, 0, 4)
		landing(game, 0, 1)
		expect(game.choose_action("upgrade").get("ok", false), "fortune allows final lab upgrade")
		verify_lab(game, 5, "fortune preserves five-level cap")
	for player_id in [0, 1]:
		for level in [0, 4]:
			var game: Object = make_game()
			if game == null: continue
			lab(game, player_id, level)
			landing(game, player_id, 5)
			game._resolve_company_visit(player_id, game.state.board[5])
			game._set_action_options(player_id)
			expect(game.get_company_upgrade_targets(player_id).has(1), "company offers canonical lab target")
			expect(game.choose_action("company_upgrade", {"tile_id": 1, "facility_type": 4}).get("ok", false), "company builds or raises research facility")
			var expected_level: int = mini(5, level + (2 if player_id == 0 else 1))
			verify_lab(game, expected_level, "company research construction")
			if expected_level == 5:
				expect(not game.get_company_upgrade_targets(player_id).has(1), "company excludes capped lab")
	print("Research construction checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
