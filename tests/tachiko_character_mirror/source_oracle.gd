extends SceneTree

# Read-only M2 witness: expose only the static selectable-character identity/name catalog.
const GameState = preload("res://game/core/game_state.gd")

func _initialize() -> void:
	if GameState.SETUP_CHARACTER_COUNT != GameState.SETUP_CHARACTER_NAMES.size():
		push_error("character count/name table mismatch")
		quit(1)
		return
	var rows: Array = []
	for legacy_id in range(GameState.SETUP_CHARACTER_COUNT):
		rows.append({
			"legacy_id": legacy_id,
			"display_name": GameState.SETUP_CHARACTER_NAMES[legacy_id],
		})
	print("RICHMAN4_CHARACTER_ORACLE=" + JSON.stringify({"characters": rows}))
	quit(0)
