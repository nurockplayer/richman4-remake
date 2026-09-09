extends RefCounted

## Synthetic source-shaped news road, sharing the established v13 fixture.
const Base = preload("res://tests/fixtures/god_card_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Game = preload("res://game/core/game_state.gd")

static func definition() -> Dictionary:
	var result: Dictionary = Base.definition()
	var tile: Dictionary = result.board.back()
	tile.type_and_idx = 0
	tile.event_code = 2
	tile.source_status_bits = 2
	tile.kind = Maps.classify_source_node(0, 2).kind
	tile.name = "測試新聞"
	return result

static func new_game_options() -> Dictionary:
	return Base.new_game_options()

static func new_game(seed_value: int = 5400, player_count: int = 4) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, definition(), new_game_options())
	if game != null:
		game.state.god_objects = []
		for player_id in range(player_count):
			game.set_player_ai(player_id, false)
	return game
