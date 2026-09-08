extends SceneTree
const Calendar = preload("res://game/core/game_calendar.gd")
var checks := 0
var failures := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	for pair in [
		[{"year": 1998, "month": 1, "day": 31}, {"year": 1998, "month": 2, "day": 1}],
		[{"year": 1998, "month": 2, "day": 28}, {"year": 1998, "month": 3, "day": 1}],
		[{"year": 2000, "month": 2, "day": 28}, {"year": 2000, "month": 2, "day": 29}],
		[{"year": 2000, "month": 2, "day": 29}, {"year": 2000, "month": 3, "day": 1}],
		[{"year": 2001, "month": 4, "day": 30}, {"year": 2001, "month": 5, "day": 1}],
		[{"year": 1999, "month": 12, "day": 31}, {"year": 2000, "month": 1, "day": 1}],
		[{"year": 2100, "month": 2, "day": 28}, {"year": 2100, "month": 2, "day": 29}]]:
		expect(Calendar.add_days(pair[0], 1) == pair[1], "date boundary " + str(pair[0]))
	var epoch := {"year": 1998, "month": 1, "day": 1}
	expect(Calendar.weekday(epoch) == 4, "1998 epoch is Thursday")
	expect(Calendar.weekday(Calendar.add_days(epoch, 3)) == 7, "Sunday is seven")
	expect(Calendar.weekday(Calendar.add_days(epoch, 4)) == 1, "Monday is one")
	expect(Calendar.add_days(epoch, 0) == epoch, "zero elapsed preserves date")
	expect(Calendar.add_days(epoch, 730) == {"year": 2000, "month": 1, "day": 1}, "two-year game crosses year boundary")
	for invalid in [null, [], {}, {"year": 2001, "month": 2, "day": 29}, {"year": 2000, "month": 13, "day": 1}, {"year": true, "month": 1, "day": 1}, {"year": 2000, "month": 1, "day": 1.5}]:
		expect(not Calendar.is_valid(invalid), "reject malformed date " + str(invalid))
	expect(Calendar.is_valid({"year": 2000.0, "month": 2.0, "day": 29.0}), "JSON numeric date accepted")
	expect(Calendar.add_days(epoch, -1).is_empty(), "reject negative elapsed")
	expect(Calendar.add_days({"year": 9999, "month": 12, "day": 31}, 1).is_empty(), "reject date overflow")
	var sequential := epoch.duplicate()
	for elapsed in range(5000):
		expect(Calendar.add_days(epoch, elapsed) == sequential, "direct and daily advance agree at %d" % elapsed)
		sequential = Calendar.add_days(sequential, 1)
	print("Calendar checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
