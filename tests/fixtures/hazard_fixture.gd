extends RefCounted

const Base = preload("res://tests/fixtures/status_fixture.gd")


static func definition() -> Dictionary:
	var result: Dictionary = Base.definition()
	# The fixture keeps the complete status/company/god/facility chain and only
	# opts into the v9 hazard capability. It contains synthetic data only.
	result["supports_original_hazards"] = true
	return result
