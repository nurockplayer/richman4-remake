extends RefCounted

## Source new-game choices. Current control/vehicle may later change; initial
## control metadata keeps opening-fund validation independent of those actions.

const VEHICLES := {"walking": 1, "motorcycle": 2, "car": 3}
const VEHICLE_TOOLS := {"motorcycle": "機車", "car": "汽車"}


static func valid_human_flags(value: Variant, player_count: int) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != player_count:
		return false
	for flag in value:
		if typeof(flag) != TYPE_BOOL:
			return false
	return true


static func valid_vehicle(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and VEHICLES.has(value)


static func normalize(options: Dictionary, player_count: int) -> Dictionary:
	var choices: Dictionary = {}
	if options.has("human_flags"):
		if not valid_human_flags(options.human_flags, player_count):
			return {"ok": false}
		choices["human_flags"] = options.human_flags.duplicate()
	if options.has("initial_vehicle"):
		if not valid_vehicle(options.initial_vehicle):
			return {"ok": false}
		choices["initial_vehicle"] = options.initial_vehicle
	return {"ok": true, "choices": choices}


static func initially_human(flags: Variant, index: int) -> bool:
	if typeof(flags) == TYPE_ARRAY and index >= 0 and index < flags.size() and typeof(flags[index]) == TYPE_BOOL:
		return flags[index]
	return index == 0


static func apply_vehicle(players: Array, supply: Dictionary, vehicle: String, inventory: bool) -> bool:
	if not valid_vehicle(vehicle):
		return false
	var tool_id: String = VEHICLE_TOOLS.get(vehicle, "")
	if inventory and not tool_id.is_empty():
		var tools: Variant = supply.get("tools", null)
		if typeof(tools) != TYPE_DICTIONARY or int(tools.get(tool_id, 0)) < players.size():
			return false
		# Initial equipment is taken straight from the finite shared pool, not
		# granted to the backpack and then counted a second time.
		tools[tool_id] = int(tools[tool_id]) - players.size()
	for player in players:
		player["vehicle"] = vehicle
		player["dice_count"] = VEHICLES[vehicle]
		player["vehicles"][vehicle] = true
	return true


static func validate_metadata(data: Dictionary, player_count: int, setup_save: bool) -> Array[String]:
	var errors: Array[String] = []
	if data.has("initial_human_flags"):
		if not setup_save or not valid_human_flags(data.initial_human_flags, player_count):
			errors.append("invalid initial_human_flags")
	if data.has("initial_vehicle"):
		if not setup_save or not valid_vehicle(data.initial_vehicle):
			errors.append("invalid initial_vehicle")
	return errors
