extends SceneTree

const Lottery = preload("res://game/core/lottery_rules.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_empty_and_available_numbers()
	_test_purchase_accounting_and_boundaries()
	_test_selection_numbers()
	_test_settlement_and_owner_cleanup()
	_test_state_validation()
	print("Lottery checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _test_empty_and_available_numbers() -> void:
	var tickets: Array = Lottery.empty_slots()
	_expect_equal(tickets.size(), 36, "empty ticket state has all 36 numbers")
	_expect(tickets.all(func(value: Variant) -> bool: return value == 0), "empty ticket state has zero owners")
	_expect_equal(Lottery.available_numbers(tickets), range(1, 37), "all numbers are available initially")
	_expect_equal(Lottery.available_numbers([]), [], "malformed empty ticket state has no available numbers")


func _test_purchase_accounting_and_boundaries() -> void:
	var tickets: Array = Lottery.empty_slots()
	var bought: Dictionary = Lottery.purchase(tickets, 0, 5000, 0, 7)
	_expect(bool(bought.ok), "human purchase succeeds")
	_expect_equal(bought.tickets[6], 1, "ticket stores player id plus one")
	_expect_equal(bought.cash, 4000, "ticket costs 1000 cash")
	_expect_equal(bought.jackpot, 1000, "ticket price enters jackpot")
	_expect_equal(tickets[6], 0, "purchase does not mutate input tickets")
	for invalid in [0, 37, -1, "7", true]:
		var rejected: Dictionary = Lottery.purchase(bought.tickets, 0, 4000, 1000, invalid)
		_expect(not bool(rejected.ok), "invalid number is rejected: " + str(invalid))
	var duplicate: Dictionary = Lottery.purchase(bought.tickets, 1, 5000, 1000, 7, true)
	_expect(not bool(duplicate.ok), "sold number cannot be purchased twice")
	_expect(not bool(Lottery.purchase(bought.tickets, 1, 999, 1000, 8).ok), "insufficient cash rejects purchase")
	_expect(not bool(Lottery.purchase(bought.tickets, 1, 1000, 1000000000000, 8).ok), "jackpot headroom rejects overflow")
	var ai_purchase: Dictionary = Lottery.purchase(bought.tickets, 1, 1000, 1000, 8, true)
	_expect(not bool(ai_purchase.ok), "source AI requires strictly more than1000")


func _test_selection_numbers() -> void:
	_expect_equal(Lottery.selection_numbers([]), [], "empty state has no selection numbers")
	_expect_equal(Lottery.selection_numbers(Lottery.empty_slots()), [], "empty tickets skip draw")
	var tickets: Array = Lottery.empty_slots()
	for number in range(1, 12):
		tickets[number - 1] = 1
	_expect_equal(Lottery.selection_numbers(tickets), range(1, 12), "more than ten sold tickets draw from sold numbers")


func _test_settlement_and_owner_cleanup() -> void:
	var tickets: Array = Lottery.empty_slots()
	tickets[2] = 1
	tickets[17] = 2
	var no_winner: Dictionary = Lottery.settle(tickets, 12000, 4)
	_expect_equal(no_winner.winner_id, -1, "unowned winning number has no winner")
	_expect_equal(no_winner.amount, 0, "unowned winning number pays nothing")
	_expect_equal(no_winner.jackpot, 12000, "unclaimed jackpot rolls forward")
	_expect_equal(no_winner.tickets, tickets, "unclaimed tickets remain active")
	var winner: Dictionary = Lottery.settle(tickets, 12000, 3)
	_expect_equal(winner.winner_id, 0, "owned winning number resolves player id")
	_expect_equal(winner.amount, 12000, "winner receives the complete jackpot")
	_expect_equal(winner.jackpot, 0, "winning draw resets jackpot")
	_expect_equal(winner.tickets[2], 0, "winning ticket is consumed")
	_expect_equal(winner.tickets[17], 0, "winner clears all tickets")
	var cleared: Array = Lottery.clear_owner(tickets, 0)
	_expect_equal(cleared[2], 0, "clear_owner removes every ticket for one owner")
	_expect_equal(cleared[17], 2, "clear_owner preserves other owners")


func _test_state_validation() -> void:
	var tickets: Array = Lottery.empty_slots()
	_expect(Lottery.valid_state(tickets, [{"id": 0}, {"id": 1}], 0), "valid empty state is accepted")
	tickets[0] = 3
	_expect(Lottery.valid_state(tickets, [{"id": 0}, {"id": 1}, {"id": 2}], 1000), "owner encoding is bounded by player count")
	_expect(not Lottery.valid_state(tickets, [{"id": 0}, {"id": 1}], 1000), "owner beyond player count is rejected")
	_expect(not Lottery.valid_state(tickets, [{"id": 0}], -1), "negative jackpot is rejected")
