extends RefCounted
class_name Richman4TrusteePreferences

## Detached runtime preferences for source trustee mode.
##
## The opening `init_cash_ratio` remains immutable save metadata.  These
## preferences are a separate runtime map keyed by string player IDs.

const SetupControls := preload("res://game/core/setup_controls.gd")
const CONFIG_KEYS := ["use_cards", "use_tools", "personality", "cash_ratio", "stock_ratio"]
const ROW_KEYS := ["player_id", "name", "trustee", "use_cards", "use_tools", "personality", "cash_ratio", "stock_ratio"]
const DEFAULT_STOCK_RATIO := 30


static func rows(state: Dictionary) -> Array:
	var players: Array = _players(state)
	var result: Array = []
	for index in range(players.size()):
		if typeof(players[index]) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = players[index]
		if not _original_human(state, index) or not _eligible_player(player):
			continue
		var player_id := int(player.get("id", index))
		var preference: Dictionary = _stored_preference(state, player_id)
		var trustee := bool(player.get("is_ai", false))
		var cash_default := _default_cash_ratio(player)
		result.append({
			"player_id": player_id,
			"name": str(player.get("name", "玩家%d" % (player_id + 1))),
			"trustee": trustee,
			"use_cards": bool(preference.get("use_cards", true)),
			"use_tools": bool(preference.get("use_tools", true)),
			"personality": int(preference.get("personality", 1)),
			"cash_ratio": int(preference.get("cash_ratio", cash_default)),
			"stock_ratio": int(preference.get("stock_ratio", DEFAULT_STOCK_RATIO)),
		})
	return result


static func commit(state: Dictionary, value: Array) -> bool:
	var errors := validate_rows(state, value)
	if not errors.is_empty():
		return false
	var next_preferences: Dictionary = _existing_preferences(state)
	for raw in value:
		var row: Dictionary = raw
		var player_id := int(row.get("player_id", -1))
		next_preferences[str(player_id)] = _config_from_row(row)
	var players: Array = _players(state)
	# All validation is complete before either map is replaced or a player flag
	# changes, keeping malformed batches atomic from the caller's perspective.
	if next_preferences.is_empty():
		state.erase("trustee_preferences")
	else:
		state["trustee_preferences"] = next_preferences
	for raw in value:
		var row: Dictionary = raw
		var player_id := int(row.get("player_id", -1))
		var index := _player_index(players, player_id)
		if index < 0:
			continue
		var player: Dictionary = players[index]
		var delegated := bool(row.get("trustee", false))
		player["is_ai"] = delegated
		player["is_human"] = not delegated
	return true


static func validate(state: Dictionary) -> Array:
	var errors: Array = []
	if typeof(state) != TYPE_DICTIONARY:
		return ["state must be a dictionary"]
	if not state.has("players") or typeof(state.get("players")) != TYPE_ARRAY:
		return ["players missing"]
	var players: Array = _players(state)
	for index in range(players.size()):
		if typeof(players[index]) != TYPE_DICTIONARY:
			errors.append("player %d invalid" % index)
			continue
		var player: Dictionary = players[index]
		if not _valid_player_identity(player, index):
			errors.append("player %d identity invalid" % index)
	var preferences_value: Variant = state.get("trustee_preferences", null)
	if state.has("trustee_preferences"):
		if typeof(preferences_value) != TYPE_DICTIONARY:
			errors.append("trustee_preferences invalid")
		else:
			var preferences: Dictionary = preferences_value
			for key in preferences.keys():
				if typeof(key) != TYPE_STRING or not _decimal_id(str(key)):
					errors.append("trustee preference key invalid")
					continue
				var player_id := int(str(key))
				if player_id < 0 or player_id >= players.size() or not _original_human(state, player_id):
					errors.append("trustee preference actor invalid")
				var config: Variant = preferences[key]
				errors.append_array(_validate_config(config))
	var recovery: Variant = state.get("trustee_recovery_requested", null)
	if state.has("trustee_recovery_requested") and (typeof(recovery) != TYPE_BOOL or not bool(recovery)):
		errors.append("trustee recovery request invalid")
	elif state.has("trustee_recovery_requested") and bool(recovery) and not _has_any_original_preference(state):
		errors.append("trustee recovery has no original trustee")
	return errors


static func validate_rows(state: Dictionary, value: Array) -> Array:
	var errors: Array = []
	if not validate(state).is_empty():
		# The source dialog cannot safely commit against an already malformed
		# state, even when the visible row payload itself looks valid.
		errors.append("state invalid")
	var expected: Dictionary = {}
	for row in rows(state):
		expected[int(row.get("player_id", -1))] = true
	if value.size() != expected.size():
		errors.append("trustee rows incomplete")
	var seen: Dictionary = {}
	for raw in value:
		if typeof(raw) != TYPE_DICTIONARY:
			errors.append("trustee row invalid")
			continue
		var row: Dictionary = raw
		if row.keys().size() != ROW_KEYS.size():
			errors.append("trustee row fields invalid")
		for key in ROW_KEYS:
			if not row.has(key):
				errors.append("trustee row missing %s" % key)
		var player_id: Variant = row.get("player_id", null)
		if typeof(player_id) != TYPE_INT or not expected.has(int(player_id)) or seen.has(int(player_id)):
			errors.append("trustee row actor invalid")
		else:
			seen[int(player_id)] = true
		var name: Variant = row.get("name", null)
		if typeof(name) != TYPE_STRING:
			errors.append("trustee row name invalid")
		var trustee: Variant = row.get("trustee", null)
		if typeof(trustee) != TYPE_BOOL:
			errors.append("trustee row trustee invalid")
		var config: Dictionary = _config_from_row(row)
		errors.append_array(_validate_config(config))
	if seen.size() != expected.size():
		errors.append("trustee rows omit actor")
	return errors


static func for_player(state: Dictionary, player_id: int) -> Dictionary:
	var players: Array = _players(state)
	if player_id < 0 or player_id >= players.size() or not _original_human(state, player_id):
		return {}
	if typeof(players[player_id]) != TYPE_DICTIONARY:
		return {}
	var player: Dictionary = players[player_id]
	if not bool(player.get("is_ai", false)):
		return {}
	return _stored_preference(state, player_id)


static func request_recovery(state: Dictionary) -> bool:
	if not validate(state).is_empty() or state.has("trustee_recovery_requested"):
		return false
	var has_actionable_human := false
	var has_trustee := false
	var players: Array = _players(state)
	for index in range(players.size()):
		if typeof(players[index]) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = players[index]
		if not _original_human(state, index) or not _eligible_player(player):
			continue
		if bool(player.get("is_human", false)) and not bool(player.get("is_ai", false)):
			has_actionable_human = true
		if bool(player.get("is_ai", false)) and not _stored_preference(state, int(player.get("id", index))).is_empty():
			has_trustee = true
	if has_actionable_human or not has_trustee:
		return false
	state["trustee_recovery_requested"] = true
	return true


static func recover(state: Dictionary) -> void:
	if not state.has("trustee_recovery_requested") or state.get("trustee_recovery_requested") != true:
		return
	state.erase("trustee_recovery_requested")
	var players: Array = _players(state)
	var fallback := -1
	for index in range(players.size()):
		if typeof(players[index]) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = players[index]
		if not _original_human(state, index) or not _eligible_player(player):
			continue
		if bool(player.get("is_ai", false)) and not _stored_preference(state, int(player.get("id", index))).is_empty():
			if int(player.get("id", index)) == 0:
				fallback = index
				break
			if fallback < 0:
				fallback = index
	if fallback >= 0:
		players[fallback]["is_ai"] = false
		players[fallback]["is_human"] = true


static func _config_from_row(row: Dictionary) -> Dictionary:
	return {
		"use_cards": row.get("use_cards", null),
		"use_tools": row.get("use_tools", null),
		"personality": row.get("personality", null),
		"cash_ratio": row.get("cash_ratio", null),
		"stock_ratio": row.get("stock_ratio", null),
	}


static func _validate_config(value: Variant) -> Array:
	var errors: Array = []
	if typeof(value) != TYPE_DICTIONARY:
		return ["trustee preference config invalid"]
	var config: Dictionary = value
	if config.keys().size() != CONFIG_KEYS.size():
		errors.append("trustee preference fields invalid")
	for key in CONFIG_KEYS:
		if not config.has(key):
			errors.append("trustee preference missing %s" % key)
	if typeof(config.get("use_cards", null)) != TYPE_BOOL or typeof(config.get("use_tools", null)) != TYPE_BOOL:
		errors.append("trustee preference flags invalid")
	var personality: Variant = config.get("personality", null)
	if not _valid_whole_number(personality, 0, 2):
		errors.append("trustee personality invalid")
	for key in ["cash_ratio", "stock_ratio"]:
		var ratio: Variant = config.get(key, null)
		if not _valid_whole_number(ratio, 0, 100) or int(ratio) % 10 != 0:
			errors.append("trustee %s invalid" % key)
	return errors


static func _stored_preference(state: Dictionary, player_id: int) -> Dictionary:
	var value: Variant = state.get("trustee_preferences", {})
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var config: Variant = value.get(str(player_id), null)
	if _validate_config(config).is_empty():
		return (config as Dictionary).duplicate(true)
	return {}


static func _existing_preferences(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var value: Variant = state.get("trustee_preferences", {})
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for key in value.keys():
		if typeof(key) != TYPE_STRING or not _decimal_id(str(key)):
			continue
		var player_id := int(str(key))
		if _original_human(state, player_id):
			var config: Variant = value[key]
			if _validate_config(config).is_empty():
				result[str(player_id)] = (config as Dictionary).duplicate(true)
	return result


static func _has_any_original_preference(state: Dictionary) -> bool:
	var players: Array = _players(state)
	var value: Variant = state.get("trustee_preferences", {})
	if typeof(value) != TYPE_DICTIONARY:
		return false
	for key in value.keys():
		if typeof(key) != TYPE_STRING or not _decimal_id(str(key)):
			continue
		var player_id := int(str(key))
		if player_id >= 0 and player_id < players.size() and _original_human(state, player_id) and _validate_config(value[key]).is_empty():
			return true
	return false


static func _players(state: Dictionary) -> Array:
	var value: Variant = state.get("players", [])
	return value as Array if typeof(value) == TYPE_ARRAY else []


static func _player_index(players: Array, player_id: int) -> int:
	for index in range(players.size()):
		if typeof(players[index]) == TYPE_DICTIONARY and int((players[index] as Dictionary).get("id", -1)) == player_id:
			return index
	return -1


static func _original_human(state: Dictionary, index: int) -> bool:
	return SetupControls.initially_human(state.get("initial_human_flags", []), index)


static func _eligible_player(player: Dictionary) -> bool:
	return bool(player.get("alive", false)) and not bool(player.get("bankrupt", false))


static func _default_cash_ratio(player: Dictionary) -> int:
	var value: Variant = player.get("init_cash_ratio", 50)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 50
	return clampi(int(round(float(value) / 10.0) * 10), 0, 100)


static func _valid_player_identity(player: Dictionary, index: int) -> bool:
	return _valid_whole_number(player.get("id", null), index, index) and typeof(player.get("name", null)) == TYPE_STRING


static func _valid_whole_number(value: Variant, low: int, high: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return is_finite(numeric) and floor(numeric) == numeric and numeric >= low and numeric <= high


static func _decimal_id(value: String) -> bool:
	if value.is_empty():
		return false
	if value.length() > 1 and value.begins_with("0"):
		return false
	for character in value:
		if character < "0" or character > "9":
			return false
	return true
