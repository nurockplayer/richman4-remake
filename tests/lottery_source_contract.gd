extends SceneTree
const Rules = preload("res://game/core/lottery_rules.gd")
var failures := 0
func expect(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var empty := Rules.empty_slots()
	expect(Rules.selection_numbers(empty).is_empty(), "empty tickets must not request RNG")
	expect(not Rules.purchase(empty, 0, 1000, 0, 1, true).ok, "AI exact1000 cannot purchase")
	var spread := empty.duplicate()
	for i in range(12): spread[i] = i % 4 + 1
	expect(Rules.selection_numbers(spread).size() == 36, "total12 sold does not trigger single-owner>10 rule")
	var concentrated := empty.duplicate()
	for i in range(11): concentrated[i] = 1
	concentrated[20] = 2
	expect(Rules.selection_numbers(concentrated).size() == 12, "one owner11 selects all sold numbers")
	var result := Rules.settle(concentrated, 12000, 1)
	expect(result.tickets.count(0) == 36, "winner clears ALL tickets")
	print("Lottery source contract: 5 checks, failures: %d" % failures)
	quit(1 if failures else 0)
