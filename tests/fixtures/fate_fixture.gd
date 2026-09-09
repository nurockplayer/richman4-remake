extends RefCounted

## Synthetic Game-edition source road for the fate landing contract.
##
## The fixture deliberately derives its runtime kind from the canonical source
## classifier.  Before the fate adapter exists event_code 3 remains an
## unsupported road, so the fixture itself stays a legal positive save while
## the landing assertions provide the RED signal.

const Base = preload("res://tests/fixtures/building_card_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Game = preload("res://game/core/game_state.gd")


static func definition(map_number: int = 1) -> Dictionary:
	var result: Dictionary = Base.definition()
	var tile: Dictionary = result.board.back()
	tile["type_and_idx"] = 0
	tile["event_code"] = 3
	tile["source_status_bits"] = 3
	tile["kind"] = Maps.classify_source_node(0, 3).kind
	tile["name"] = "測試命運"
	var source: Dictionary = result.get("source", {}).duplicate(true)
	source["edition"] = "Game"
	source["map_number"] = map_number
	result["source"] = source
	result["id"] = "Game:%d" % map_number
	result["name"] = "測試命運 · 地圖 %d" % map_number
	return result


static func new_game_options() -> Dictionary:
	return Base.new_game_options()


static func new_game(seed_value: int = 5600, player_count: int = 4, map_number: int = 1) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, definition(map_number), new_game_options())
	if game != null:
		# Fate tests control all god and AI state explicitly so selection and gate
		# assertions cannot depend on setup-side spawn or policy decisions.
		game.state["god_objects"] = []
		for player_id in range(player_count):
			game.set_player_ai(player_id, false)
	return game
