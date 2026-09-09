extends RefCounted
const Base = preload("res://tests/fixtures/building_card_fixture.gd")

static func definition() -> Dictionary:
	var result: Dictionary = Base.definition()
	result["supports_original_god_cards"] = true
	return result

static func new_game_options() -> Dictionary:
	var result: Dictionary = Base.new_game_options()
	result["original_god_cards"] = true
	return result

static func v13_game_options() -> Dictionary:
	return Base.new_game_options()
