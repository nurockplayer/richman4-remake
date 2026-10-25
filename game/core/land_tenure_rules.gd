extends RefCounted

## Source land holding periods use packed dates, including the original
## short-month edge case. A February-31 token never equals a real game date.
const Calendar = preload("res://game/core/game_calendar.gd")
const MONTHS := [0, 24, 12, 6, 3, 1]
const EXPIRY_KEY := "land_expiry"


static func _integer(value: Variant, low: int, high: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) and number >= low and number <= high


static func valid_months(value: Variant) -> bool:
	return _integer(value, 0, 24) and MONTHS.has(int(value))


static func enabled(state: Dictionary) -> bool:
	return valid_months(state.get("land_tenure_months", null)) and int(state.land_tenure_months) > 0


static func initialize(state: Dictionary, options: Dictionary) -> void:
	if not options.has("land_tenure_months"):
		return
	state["land_tenure_months"] = int(options.land_tenure_months)
	if enabled(state):
		for tile in state.get("board", []):
			if typeof(tile) == TYPE_DICTIONARY and tile.get("kind", "") in ["property", "facility"]:
				tile[EXPIRY_KEY] = 0


static func packed_date(date: Dictionary) -> int:
	return (int(date.year) << 16) | (int(date.month) << 8) | int(date.day)


static func expiry(date: Dictionary, months: int) -> int:
	if not Calendar.is_valid(date) or not valid_months(months) or months == 0:
		return 0
	var year := int(date.year)
	var month := int(date.month) + months
	while month > 12:
		year += 1
		month -= 12
	return (year << 16) | (month << 8) | int(date.day)


static func acquire(game: Object, tile: Dictionary) -> void:
	if not enabled(game.state):
		return
	var token := expiry(game.state.get("date", {}), int(game.state.land_tenure_months))
	if tile.get("kind", "") == "facility":
		game._update_facility_records(int(tile.get("source_object_id", -1)), {EXPIRY_KEY: token})
	elif tile.get("kind", "") == "property":
		tile[EXPIRY_KEY] = token


static func transfer(game: Object, source: Dictionary, destination: Dictionary) -> void:
	if not enabled(game.state):
		return
	var token: int = int(source.get(EXPIRY_KEY, 0))
	if source.get("kind", "") == "facility":
		game._update_facility_records(int(source.get("source_object_id", -1)), {EXPIRY_KEY: 0})
		game._update_facility_records(int(destination.get("source_object_id", -1)), {EXPIRY_KEY: token})
	else:
		source[EXPIRY_KEY] = 0
		destination[EXPIRY_KEY] = token


static func expire_today(game: Object) -> void:
	if not enabled(game.state) or not Calendar.is_valid(game.state.get("date", null)):
		return
	var today := packed_date(game.state.date)
	var changed := false
	# Updating all facility entrances clears their token immediately, so later
	# aliases cannot settle the same source facility a second time.
	for tile in game.state.get("board", []):
		if typeof(tile) != TYPE_DICTIONARY or tile.get("kind", "") not in ["property", "facility"]:
			continue
		if int(tile.get(EXPIRY_KEY, 0)) != today:
			continue
		var old_owner := int(tile.get("owner", -1))
		var asset_id := int(tile.get("index", -1))
		if tile.get("kind", "") == "facility":
			asset_id = game._facility_canonical_index(asset_id)
			game._update_facility_records(int(tile.get("source_object_id", -1)), {"owner": -1, EXPIRY_KEY: 0})
		else:
			tile["owner"] = -1
			tile[EXPIRY_KEY] = 0
		if old_owner >= 0:
			game._remove_property_reference(old_owner, asset_id)
		game._record_event("land_tenure_expired", {"tile_id": asset_id, "previous_owner": old_owner, "expiry": today})
		changed = true
	if changed:
		game._recalculate_property_values()


static func _valid_expiry(value: Variant) -> bool:
	if not _integer(value, 0, ((Calendar.MAX_YEAR + 2) << 16) | 0x0c1f):
		return false
	var token := int(value)
	if token == 0:
		return true
	var year := token >> 16
	var month := (token >> 8) & 255
	var day := token & 255
	return year >= Calendar.MIN_YEAR and year <= Calendar.MAX_YEAR + 2 and month >= 1 and month <= 12 and day >= 1 and day <= 31


static func validate_metadata(data: Dictionary, setup_save: bool) -> Array[String]:
	var errors: Array[String] = []
	if data.has("land_tenure_months") and (not setup_save or not valid_months(data.land_tenure_months)):
		errors.append("invalid land_tenure_months")
	var active := setup_save and enabled(data)
	var board: Variant = data.get("board", null)
	if typeof(board) != TYPE_ARRAY:
		return errors
	for index in range(board.size()):
		var tile: Variant = board[index]
		if typeof(tile) != TYPE_DICTIONARY:
			continue
		if active and tile.get("kind", "") in ["property", "facility"]:
			if not _valid_expiry(tile.get(EXPIRY_KEY, null)):
				errors.append("invalid land expiry %d" % index)
		elif tile.has(EXPIRY_KEY):
			errors.append("land expiry without enabled tenure or land %d" % index)
	return errors
