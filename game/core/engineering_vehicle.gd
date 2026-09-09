class_name RichmanEngineeringVehicle
extends RefCounted

## Pure lifecycle rules for the optional research tool 工程車.
##
## The game state owns phase, inventory, land and event concerns.  This small
## value module keeps the representation and countdown rules in one place so
## save validation and runtime transitions cannot drift apart.

const VEHICLE_ID := "engineering"
const MAX_ADMISSIONS: int = 7
const METADATA_KEYS := ["remaining_admissions", "previous_vehicle", "previous_dice_count"]
const ORDINARY_DICE := {"walking": 1, "motorcycle": 2, "car": 3}


static func metadata(previous_vehicle: String, previous_dice_count: int, remaining_admissions: int = MAX_ADMISSIONS) -> Dictionary:
	return {
		"remaining_admissions": remaining_admissions,
		"previous_vehicle": previous_vehicle,
		"previous_dice_count": previous_dice_count,
	}


static func validate_metadata(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "error": "engineering metadata must be an object"}
	var data: Dictionary = value
	if data.size() != METADATA_KEYS.size():
		return {"ok": false, "error": "engineering metadata keys are not canonical"}
	for key in METADATA_KEYS:
		if not data.has(key):
			return {"ok": false, "error": "engineering metadata missing %s" % key}
	var remaining: Variant = data.get("remaining_admissions", null)
	if not _valid_integer(remaining, 1, MAX_ADMISSIONS):
		return {"ok": false, "error": "engineering remaining admissions invalid"}
	var previous_vehicle: Variant = data.get("previous_vehicle", null)
	if typeof(previous_vehicle) != TYPE_STRING or not ORDINARY_DICE.has(str(previous_vehicle)):
		return {"ok": false, "error": "engineering previous vehicle invalid"}
	var previous_dice: Variant = data.get("previous_dice_count", null)
	if not _valid_integer(previous_dice, 1, int(ORDINARY_DICE[str(previous_vehicle)])):
		return {"ok": false, "error": "engineering previous dice invalid"}
	return {"ok": true, "error": ""}


static func validate_player(player: Dictionary) -> Dictionary:
	var has_metadata: bool = player.has("engineering_vehicle")
	var vehicle: Variant = player.get("vehicle", null)
	var dice: Variant = player.get("dice_count", null)
	if not has_metadata:
		if vehicle == VEHICLE_ID:
			return {"ok": false, "error": "engineering vehicle requires metadata"}
		return {"ok": true, "error": ""}
	var metadata_value: Variant = player.get("engineering_vehicle", null)
	var metadata_result: Dictionary = validate_metadata(metadata_value)
	if not bool(metadata_result.get("ok", false)):
		return metadata_result
	if vehicle != VEHICLE_ID:
		return {"ok": false, "error": "engineering metadata requires active vehicle"}
	if not _valid_integer(dice, 1, 1):
		return {"ok": false, "error": "engineering vehicle requires one die"}
	if not bool(player.get("alive", false)):
		return {"ok": false, "error": "dead player cannot have engineering metadata"}
	return {"ok": true, "error": ""}


static func is_active(player: Dictionary) -> bool:
	return str(player.get("vehicle", "")) == VEHICLE_ID and player.has("engineering_vehicle")


static func tick(value: Variant) -> Dictionary:
	var checked: Dictionary = validate_metadata(value)
	if not bool(checked.get("ok", false)):
		return {"ok": false, "expired": false, "metadata": {}, "error": str(checked.get("error", "engineering metadata invalid"))}
	var current: Dictionary = value
	var remaining: int = int(current["remaining_admissions"]) - 1
	if remaining > 0:
		var next: Dictionary = current.duplicate(true)
		next["remaining_admissions"] = remaining
		return {"ok": true, "expired": false, "metadata": next, "error": ""}
	return {"ok": true, "expired": true, "metadata": current.duplicate(true), "error": ""}


static func restore(value: Variant, ordinary_vehicle_available: bool) -> Dictionary:
	var checked: Dictionary = validate_metadata(value)
	if not bool(checked.get("ok", false)):
		return {"ok": false, "vehicle": "walking", "dice_count": 1, "error": str(checked.get("error", "engineering metadata invalid"))}
	var data: Dictionary = value
	var previous_vehicle: String = str(data["previous_vehicle"])
	var restored_vehicle: String = previous_vehicle if ordinary_vehicle_available else "walking"
	var restored_dice: int = int(data["previous_dice_count"]) if ordinary_vehicle_available else 1
	return {"ok": true, "vehicle": restored_vehicle, "dice_count": restored_dice, "error": ""}


static func ordinary_dice(vehicle: String) -> int:
	return int(ORDINARY_DICE.get(vehicle, 1))


static func _valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	if typeof(value) == TYPE_FLOAT:
		var real: float = float(value)
		return is_finite(real) and floor(real) == real and real >= float(minimum) and real <= float(maximum)
	return false
