extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Base = preload("res://tests/fixtures/property_card_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")

var checks := 0
var failures := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func staged_game(chain: bool) -> Object:
	var definition := Base.definition()
	definition["supports_original_remodel"] = true
	for tile in definition.board:
		if tile.kind == "property":
			tile["is_chain_store"] = false
	var options := Base.new_game_options()
	options["original_remodel"] = true
	options["day_limit"] = 30
	var game = Game.new_game_on_board(717, 4, definition, options)
	if game == null:
		return null
	game.state.god_objects = []
	for id in range(4):
		game.set_player_ai(id, true)
		var player: Dictionary = game.state.players[id]
		for tool_id in player.tools.keys():
			Inventory.consume_tool(game.state.inventory_supply, player.tools, tool_id, int(player.tools[tool_id]))
	game.state.players[0].position = 2
	game.state.players[0].previous_position = -1
	game.state.board[2].owner = 0
	game.state.board[2].building_level = 1
	game.state.board[2].is_chain_store = chain
	game.state.players[0].properties = [2]
	game._update_tile_rent(game.state.board[2])
	game._recalculate_property_values()
	Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, "改建")
	game._set_action_options(0)
	return game

func used_remodel(game: Object) -> bool:
	for event in game.state.event_log:
		if event.get("type", "") == "card_used" and event.get("card_id", "") == "改建" and int(event.get("player_id", -1)) == 0:
			return true
	return false

func _initialize() -> void:
	for chain in [false, true]:
		var game := staged_game(chain)
		expect(game != null, "AI remodel fixture starts v11")
		if game == null:
			continue
		expect(Game.validate_save(game.to_dict()).get("ok", false), "AI remodel fixture validates")
		var restored = Game.from_dict(JSON.parse_string(game.to_json()))
		expect(restored != null, "AI remodel fixture reloads from JSON")
		if restored == null:
			continue
		var result: Dictionary = game.run_ai_turn()
		var counterpart: Dictionary = restored.run_ai_turn()
		expect(result.get("ok", false) and result.get("completed", false), "AI remodel public turn completes")
		expect(counterpart.get("ok", false) and restored.to_dict() == game.to_dict(), "reloaded AI makes the same remodel and movement decisions")
		expect(used_remodel(game) == (not chain), "AI improves low-rent housing and preserves a better chain store")
		expect(Game.validate_save(game.to_dict()).get("ok", false), "AI remodel turn leaves a valid save")
		if chain:
			expect(game.state.players[0].cards.has("改建"), "AI retains a harmful remodel card")
	var match_game := staged_game(false)
	if match_game != null:
		var result: Dictionary = match_game.run_ai_match(200)
		expect(result.get("ok", false), "four-player remodel AI match succeeds")
		expect(match_game.state.phase == "game_over" and match_game.state.elapsed == 30, "remodel AI completes thirty days")
		expect(Game.validate_save(match_game.to_dict()).get("ok", false), "completed remodel match remains loadable")
	print("Remodel AI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
