extends "res://tests/source_bank_visit.gd"

## Current-main adaptation: exercise the new token boundary without requiring
## the encounter implementation that this RED is meant to qualify.  The
## reference test starts from a serialized pending visit, which current main
## cannot produce yet.  Here the valid base is an ordinary save; adding any
## bank-visit token to that non-bank phase must be rejected atomically.

func _initialize() -> void:
	_definition = Fixture.definition()
	_setup_expect(not _definition.is_empty(), "schema fixture normalizes")
	var game: Object = _new_game()
	if game == null:
		_finish(2)
		return
	var base: Dictionary = game.to_dict()
	_setup_expect(bool(Game.validate_save(base).get("ok", false)), "ordinary save is a valid schema base")
	if _setup_failures:
		_finish(2)
		return

	for malformed in ["bad", 0, [], {}, null]:
		var data: Dictionary = base.duplicate(true)
		data["pending_bank_visit"] = malformed
		check_rejected(data, "pending bank token shape")

	var token: Dictionary = {"kind": "pass", "player_id": 0, "node_id": 1}
	var orphan: Dictionary = base.duplicate(true)
	orphan["pending_bank_visit"] = token.duplicate(true)
	check_rejected(orphan, "orphan pass token outside bank pause")

	for key in ["kind", "player_id", "node_id"]:
		for malformed in ["bad", [], {}, null]:
			var data: Dictionary = base.duplicate(true)
			var candidate: Dictionary = token.duplicate(true)
			candidate[key] = malformed
			data["pending_bank_visit"] = candidate
			check_rejected(data, "pending bank token field " + key)

	var missing_key: Dictionary = base.duplicate(true)
	var missing_token: Dictionary = token.duplicate(true)
	missing_token.erase("node_id")
	missing_key["pending_bank_visit"] = missing_token
	check_rejected(missing_key, "pending token missing node")
	var extra_key: Dictionary = base.duplicate(true)
	var extra_token: Dictionary = token.duplicate(true)
	extra_token["unexpected"] = true
	extra_key["pending_bank_visit"] = extra_token
	check_rejected(extra_key, "pending token extra field")
	print("Source bank schema checks: %d, failures: %d, setup_failures: %d" % [_checks, _failures, _setup_failures])
	quit(1 if _failures else 0)


func check_rejected(data: Dictionary, label: String) -> void:
	var validation: Dictionary = Game.validate_save(data)
	_expect(validation.has("ok") and validation.get("ok") == false, label + " returns an explicit validation rejection")
	_expect(Game.from_dict(data) == null, label + " cannot restore")
