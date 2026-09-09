extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/property_card_fixture.gd")

var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func staged_game(card_id: String, reverse: bool = false, beneficial: bool = true) -> Object:
	var options := Fixture.new_game_options()
	options["day_limit"] = 30
	var game = Game.new_game_on_board(718, 4, Fixture.definition(), options)
	if game == null:
		return null
	game.state.god_objects = []
	for id in range(4):
		game.set_player_ai(id, true)
		var player: Dictionary = game.state.players[id]
		# Remove competing tool choices through the existing finite inventory API.
		for tool_id in player.tools.keys():
			Inventory.consume_tool(game.state.inventory_supply, player.tools, tool_id, int(player.tools[tool_id]))
	game.state.players[0].position = 2
	game.state.board[2].owner = 1 if reverse else 0
	game.state.board[3].owner = 0 if reverse else 1
	var low_current := beneficial != reverse
	game.state.board[2].building_level = 0 if low_current else 5
	game.state.board[3].building_level = 5 if low_current else 0
	game.state.players[0].properties = [3] if reverse else [2]
	game.state.players[1].properties = [2] if reverse else [3]
	game._update_tile_rent(game.state.board[2])
	game._update_tile_rent(game.state.board[3])
	game._recalculate_property_values()
	Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, card_id)
	game._set_action_options(0)
	return game

func used_card(game: Object, card_id: String) -> bool:
	for event in game.state.event_log:
		if event.get("type", "") == "card_used" and event.get("card_id", "") == card_id and int(event.get("player_id", -1)) == 0:
			return true
	return false

func _initialize() -> void:
	for card_id in ["換地", "換屋"]:
		for reverse in [false, true]:
			var game := staged_game(card_id, reverse)
			expect(game != null, card_id + " AI fixture starts v10")
			if game == null:
				continue
			expect(Game.validate_save(game.to_dict()).get("ok", false), "staged AI property ownership is a valid save")
			var restored = Game.from_dict(JSON.parse_string(game.to_json()))
			expect(restored != null, "AI fixture survives real JSON serialization")
			if restored == null:
				continue
			var result: Dictionary = game.run_ai_turn()
			var replayed: Dictionary = restored.run_ai_turn()
			expect(result.get("ok", false) and result.get("completed", false), card_id + " public AI turn completes")
			expect(used_card(game, card_id), card_id + " AI uses a beneficial exchange in either ownership direction")
			expect(replayed.get("ok", false) and game.to_dict() == restored.to_dict(), "JSON-restored AI chooses the same exchange and continuation")
			expect(Game.validate_save(game.to_dict()).get("ok", false), "AI exchange leaves a valid finite-inventory save")
		var skip_game := staged_game(card_id, false, false)
		if skip_game != null:
			var result: Dictionary = skip_game.run_ai_turn()
			expect(result.get("ok", false) and result.get("completed", false), "AI without a useful exchange still completes its turn")
			expect(not used_card(skip_game, card_id), card_id + " AI avoids a harmful exchange")
			expect(skip_game.state.players[0].cards.has(card_id), "unused exchange card remains in inventory")
	var match_game := staged_game("換地")
	if match_game != null:
		Inventory.grant_card(match_game.state.inventory_supply, match_game.state.players[1].cards, "換屋")
		var result: Dictionary = match_game.run_ai_match(200)
		expect(result.get("ok", false), "property-card AI match succeeds")
		expect(match_game.state.phase == "game_over" and match_game.state.elapsed == 30, "four AI players complete the thirty-day match")
		expect(Game.validate_save(match_game.to_dict()).get("ok", false), "completed property-card match remains loadable")
	print("Property card AI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
