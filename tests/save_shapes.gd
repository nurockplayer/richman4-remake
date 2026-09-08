extends SceneTree
## Malformed JSON numeric shapes must be rejected without throwing script errors.
const Simulation = preload("res://game/core/game_state.gd")


func _initialize() -> void:
	var good = Simulation.new_game(42, 3).to_dict()
	var groups := {
		"root": ["seed", "day", "turn", "round", "month", "day_of_month", "weekday", "current_player", "winner", "last_total"],
		"player": ["id", "cash", "deposit", "position", "skip_turns", "dice_count"],
		"tile": ["index", "owner", "building_level", "cost", "rent"],
	}
	var failures := 0
	var total := 0
	for group in groups:
		for key in groups[group]:
			for bad in [{}, [], "bad", null, false, 0.5]:
				var data: Dictionary = good.duplicate(true)
				var record: Dictionary = data
				if group == "player":
					record = data.players[0]
				elif group == "tile":
					record = data.board[0]
				record[key] = bad
				var result: Dictionary = Simulation.validate_save(data)
				if result.get("ok", true):
					push_error("Accepted malformed %s.%s = %s" % [group, key, str(bad)])
					failures += 1
				total += 1
	print("Malformed save checks: %d cases, %d failures" % [total, failures])
	quit(1 if failures else 0)
