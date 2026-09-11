extends SceneTree

## Focused pure contract checks for S04 runtime trustee preferences.

const Preferences := preload("res://game/core/trustee_preferences.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _player(player_id: int, human: bool, alive := true, bankrupt := false) -> Dictionary:
	return {
		"id": player_id,
		"name": ["甲", "乙", "丙"][player_id],
		"is_human": human,
		"is_ai": not human,
		"alive": alive,
		"bankrupt": bankrupt,
		"init_cash_ratio": 50 if human else 40,
	}


func _state() -> Dictionary:
	return {
		"initial_human_flags": [true, true, false],
		"players": [_player(0, true), _player(1, true), _player(2, false)],
	}


func _run() -> void:
	var state := _state()
	_expect(Preferences.validate(state).is_empty(), "valid mixed-origin state has no preference errors")
	var rows: Array = Preferences.rows(state)
	_expect(rows.size() == 2 and rows[0].player_id == 0 and rows[1].player_id == 1, "rows include only living original humans")
	_expect(rows[0].use_cards and rows[0].use_tools and rows[0].personality == 1 and rows[0].cash_ratio == 50 and rows[0].stock_ratio == 30, "rows expose source defaults without changing opening ratio")
	_expect(Preferences.for_player(state, 2).is_empty() and Preferences.for_player(state, 0).is_empty(), "native AI and non-delegated human have no strategy preference")

	var configured: Dictionary = rows[0].duplicate(true)
	configured.trustee = true
	configured.use_cards = false
	configured.use_tools = false
	configured.personality = 2
	configured.cash_ratio = 0
	configured.stock_ratio = 100
	rows[0] = configured
	var before_opening := int(state.players[0].init_cash_ratio)
	_expect(Preferences.commit(state, rows), "valid rows commit atomically")
	_expect(state.trustee_preferences.has("0") and state.players[0].is_ai and not state.players[0].is_human, "commit stores config and delegates the original human")
	_expect(int(state.players[0].init_cash_ratio) == before_opening, "commit preserves immutable opening cash ratio")
	_expect(Preferences.for_player(state, 0).cash_ratio == 0 and not Preferences.for_player(state, 0).use_cards, "strategy accessor returns saved delegated preferences")

	var snapshot: String = JSON.stringify(state)
	var duplicate_rows: Array = Preferences.rows(state)
	duplicate_rows.append(duplicate_rows[0].duplicate(true))
	duplicate_rows[1].player_id = 0
	_expect(not Preferences.commit(state, duplicate_rows) and JSON.stringify(state) == snapshot, "duplicate row actor rejects without partial writes")
	var invalid_ratio: Array = Preferences.rows(state)
	invalid_ratio[0].cash_ratio = 15
	_expect(not Preferences.commit(state, invalid_ratio) and JSON.stringify(state) == snapshot, "non-ten-point ratio rejects atomically")
	var extra_field: Array = Preferences.rows(state)
	extra_field[0]["unexpected"] = true
	_expect(not Preferences.commit(state, extra_field) and JSON.stringify(state) == snapshot, "extra row field rejects atomically")

	state.players[1].alive = false
	state.trustee_preferences["1"] = {"use_cards": true, "use_tools": true, "personality": 1, "cash_ratio": 50, "stock_ratio": 30}
	_expect(Preferences.validate(state).is_empty(), "dead original trustee preference remains save-valid")
	_expect(Preferences.rows(state).size() == 1 and Preferences.rows(state)[0].player_id == 0, "dead original actor is excluded from editable rows")
	var native_preference: Dictionary = state.duplicate(true)
	native_preference.trustee_preferences["2"] = state.trustee_preferences["0"].duplicate(true)
	_expect(not Preferences.validate(native_preference).is_empty(), "native AI preference ID is rejected")
	var malformed := state.duplicate(true)
	malformed.trustee_preferences["0"].use_cards = "false"
	_expect(not Preferences.validate(malformed).is_empty(), "malformed preference type is rejected")
	var malformed_players: Dictionary = {"players": [{"id": 0}], "initial_human_flags": [true]}
	_expect(not Preferences.validate(malformed_players).is_empty(), "malformed player payload validates safely")

	var recovery_state := _state()
	var recovery_rows: Array = Preferences.rows(recovery_state)
	recovery_rows[0].trustee = true
	_expect(Preferences.commit(recovery_state, recovery_rows), "all original humans can be delegated")
	_expect(not Preferences.request_recovery(recovery_state), "recovery waits while an actionable original human remains")
	recovery_rows = Preferences.rows(recovery_state)
	recovery_rows[0].trustee = true
	recovery_rows[1].trustee = true
	_expect(Preferences.commit(recovery_state, recovery_rows), "remaining original human can be delegated")
	_expect(Preferences.request_recovery(recovery_state), "recovery request is scheduled once all originals are delegated")
	_expect(recovery_state.players[0].is_ai, "request does not switch actor during current turn")
	Preferences.recover(recovery_state)
	_expect(not recovery_state.has("trustee_recovery_requested") and not recovery_state.players[0].is_ai and recovery_state.players[0].is_human, "recovery restores eligible player zero and consumes request")

	var fallback_state := _state()
	var fallback_rows: Array = Preferences.rows(fallback_state)
	for row in fallback_rows:
		row.trustee = true
	_expect(Preferences.commit(fallback_state, fallback_rows), "fallback recovery config commits")
	fallback_state.players[0].alive = false
	fallback_state.players[0].is_ai = true
	fallback_state.players[0].is_human = false
	fallback_state.players[1].is_ai = true
	fallback_state.players[1].is_human = false
	_expect(Preferences.request_recovery(fallback_state), "fallback recovery request accepts living trustee")
	Preferences.recover(fallback_state)
	_expect(fallback_state.players[1].is_human and not fallback_state.players[1].is_ai, "recovery falls back to first living original human")

	print("Trustee preferences checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
