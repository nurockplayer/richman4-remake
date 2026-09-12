extends SceneTree

# Read compiled constants only. Never instantiate MainUI or start a game.
const MainUISource = preload("res://game/ui/main_ui.gd")

func _initialize() -> void:
	var kinds := ["initial_fund", "day_limit", "wealth_multiplier"]
	var tables := [
		MainUISource.SETUP_INITIAL_FUNDS,
		MainUISource.SETUP_DAY_LIMITS,
		MainUISource.SETUP_WEALTH_MULTIPLIERS,
	]
	var rows: Array = []
	for group in range(kinds.size()):
		if tables[group].size() != 6:
			push_error("M3 source table must contain six options")
			quit(1)
			return
		for legacy_index in range(tables[group].size()):
			var value = tables[group][legacy_index]
			if typeof(value) != TYPE_INT:
				push_error("M3 source option must be an integer")
				quit(1)
				return
			rows.append({"kind": kinds[group], "legacy_index": legacy_index, "value": value})
	print("RICHMAN4_SETUP_ORACLE=" + JSON.stringify({"setup_options": rows}))
	quit(0)
