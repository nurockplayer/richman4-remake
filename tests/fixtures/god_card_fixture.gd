extends RefCounted
const Base = preload("res://tests/fixtures/building_card_fixture.gd")

static func definition() -> Dictionary:
	return Base.definition()

static func new_game_options() -> Dictionary:
	return Base.new_game_options()
