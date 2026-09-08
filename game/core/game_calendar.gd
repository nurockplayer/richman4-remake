extends RefCounted
## Original calendar: years divisible by four are leap years, including 2100.
## Weekdays use Monday=1 through Sunday=7. No system clock enters simulation.

const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

static func _integer(value: Variant, low: int, high: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) and number >= low and number <= high

static func days_in_month(year: int, month: int) -> int:
	if month < 1 or month > 12:
		return 0
	return 29 if month == 2 and year % 4 == 0 else MONTH_DAYS[month - 1]

static func is_valid(date: Variant) -> bool:
	if typeof(date) != TYPE_DICTIONARY:
		return false
	if not _integer(date.get("year"), 1998, 9999) or not _integer(date.get("month"), 1, 12):
		return false
	return _integer(date.get("day"), 1, days_in_month(int(date.year), int(date.month)))

static func _serial(date: Dictionary) -> int:
	var year := int(date.year)
	var serial := 365 * (year - 1) + int((year - 1) / 4) + int(date.day) - 1
	for month in range(1, int(date.month)):
		serial += days_in_month(year, month)
	return serial

static func weekday(date: Dictionary) -> int:
	if not is_valid(date):
		return 0
	var epoch := _serial({"year": 1998, "month": 1, "day": 1})
	return ((_serial(date) - epoch + 3) % 7) + 1

static func add_days(date: Dictionary, elapsed: int) -> Dictionary:
	if not is_valid(date) or elapsed < 0 or elapsed > 3000000:
		return {}
	var serial := _serial(date) + elapsed
	var year := int(serial / 1461) * 4 + 1
	var remainder := serial % 1461
	while remainder >= (366 if year % 4 == 0 else 365):
		remainder -= 366 if year % 4 == 0 else 365
		year += 1
	if year > 9999:
		return {}
	var month := 1
	while remainder >= days_in_month(year, month):
		remainder -= days_in_month(year, month)
		month += 1
	return {"year": year, "month": month, "day": remainder + 1}
