extends RefCounted
const Base = preload("res://tests/fixtures/remodel_fixture.gd")

static func definition() -> Dictionary:
	var result: Dictionary = Base.definition()
	result["supports_original_research"] = true
	for tile in result.board:
		if tile.get("kind", "") == "facility":
			tile["research_tool"] = 0
			tile["research_turns"] = 0
	return result

static func new_game_options() -> Dictionary:
	var result: Dictionary = Base.new_game_options()
	result["original_research"] = true
	return result

static func v11_game_options() -> Dictionary:
	return Base.new_game_options()
