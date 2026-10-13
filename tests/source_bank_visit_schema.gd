extends "res://tests/source_bank_visit.gd"

func _initialize() -> void:
	_definition = Fixture.definition()
	var found := _find_roll(2, 0, -1)
	_setup_expect(not found.is_empty(), "schema fixture reaches a bank through a valid roll")
	if found.is_empty():
		_finish(2)
		return
	var game: Object = found.game
	var base: Dictionary = game.to_dict()
	_setup_expect(Game.validate_save(base).get("ok", false), "unmodified pending bank save is valid")
	if _setup_failures:
		_finish(2)
		return
	for key in ["is_human", "is_ai", "alive", "bankrupt"]:
		for malformed in ["bad", [], {}, null]:
			var data := base.duplicate(true)
			data.players[0][key] = malformed
			check_rejected(data, "actor " + key)
	for key in ["bank_access", "bank_landing", "weekday", "company_service_pending", "remaining_steps"]:
		for malformed in ["bad", [], {}, null]:
			var data := base.duplicate(true)
			data[key] = malformed
			check_rejected(data, "state " + key)
	var landing := base.duplicate(true)
	landing.phase = "await_action"
	landing.pending_bank_visit.kind = "landing"
	landing.bank_landing = true
	landing.remaining_steps = 0
	landing.pending_movement = {}
	_setup_expect(Game.validate_save(landing).get("ok", false), "coherent landing schema fixture is valid")
	for malformed in ["bad", [], {}, null]:
		var data := landing.duplicate(true)
		data.remaining_steps = malformed
		check_rejected(data, "landing remaining steps")
	print("Source bank schema checks: %d, failures: %d, setup_failures: %d" % [_checks, _failures, _setup_failures])
	quit(1 if _failures else 0)

func check_rejected(data: Dictionary, label: String) -> void:
	var validation: Dictionary = Game.validate_save(data)
	_expect(validation.has("ok") and validation.get("ok") == false, label + " returns an explicit validation rejection")
	_expect(Game.from_dict(data) == null, label + " cannot restore")
