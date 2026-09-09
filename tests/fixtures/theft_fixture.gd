extends RefCounted

## Legal v13 inventory fixture for the robbery-card acceptance seeds.
##
## Every inventory change in this helper goes through the existing finite
## inventory API.  The fixture therefore starts with a valid shared supply and
## can be used for both public-action and save/reload tests.

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Base = preload("res://tests/fixtures/building_card_fixture.gd")


static func definition() -> Dictionary:
	return Base.definition()


static func new_game_options() -> Dictionary:
	return Base.new_game_options()


static func new_game(seed_value: int = 64001, player_count: int = 4) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, definition(), new_game_options())
	if game == null:
		return null
	game.state["god_objects"] = []
	for player_id in range(player_count):
		game.set_player_ai(player_id, false)
		var player: Dictionary = game.state["players"][player_id]
		player["position"] = player_id
		player["previous_position"] = -1
		player["hospital_days"] = 0
		player["prison_days"] = 0
		player["god_id"] = 0
		for card_id in player.get("cards", []).duplicate():
			Inventory.consume_card(game.state["inventory_supply"], player["cards"], card_id)
		for tool_id in player.get("tools", {}).keys().duplicate():
			var quantity: int = int(player["tools"].get(tool_id, 0))
			if quantity > 0:
				Inventory.consume_tool(game.state["inventory_supply"], player["tools"], tool_id, quantity)
	prepare_action(game, 0)
	return game


static func prepare_action(game: Object, player_id: int = 0, phase: String = "await_action") -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}
	game.state["pending_remote_dice"] = {}
	game._set_action_options(player_id)


static func grant_card(game: Object, player_id: int, card_id: String) -> bool:
	return bool(Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id).get("ok", false))


static func grant_tool(game: Object, player_id: int, tool_id: String, quantity: int = 1) -> bool:
	return bool(Inventory.grant_tool(game.state["inventory_supply"], game.state["players"][player_id]["tools"], tool_id, quantity).get("ok", false))
