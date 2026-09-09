extends RefCounted
const Base = preload("res://tests/fixtures/research_fixture.gd")

static func definition() -> Dictionary:
	var result: Dictionary = Base.definition()
	result["supports_original_building_cards"] = true
	return result

static func new_game_options() -> Dictionary:
	var result: Dictionary = Base.new_game_options()
	result["original_building_cards"] = true
	return result

static func v12_game_options() -> Dictionary:
	return Base.new_game_options()
