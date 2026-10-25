class_name RichmanLotteryRules
extends RefCounted

## Pure rules for the original 1--36 lottery.
##
## A ticket array has one slot for each number.  A zero slot is available;
## otherwise the slot stores the original player id plus one.  The caller owns
## the random source and passes the selected winning number to `settle`.

const NUMBER_COUNT: int = 36
const FIRST_NUMBER: int = 1
const LAST_NUMBER: int = NUMBER_COUNT
const TICKET_PRICE: int = 1000
const MAX_MONEY: int = 1000000000000


static func empty_slots() -> Array:
	var tickets: Array = []
	for _index in range(NUMBER_COUNT):
		tickets.append(0)
	return tickets


static func available_numbers(tickets: Variant) -> Array:
	if not _valid_tickets(tickets):
		return []
	var available: Array = []
	for index in range(NUMBER_COUNT):
		if int(tickets[index]) == 0:
			available.append(index + FIRST_NUMBER)
	return available


static func purchase(tickets: Variant, player_id: Variant, cash: Variant, pool: Variant, number: Variant, is_ai: bool = false) -> Dictionary:
	var unchanged: Array = tickets.duplicate(true) if typeof(tickets) == TYPE_ARRAY else []
	var unchanged_pool: int = int(pool) if _valid_money(pool) else 0
	var unchanged_cash: int = int(cash) if _valid_money(cash) else 0
	if not _valid_tickets(tickets):
		return _purchase_result(false, unchanged, unchanged_cash, unchanged_pool)
	if not _valid_money(cash) or not _valid_money(pool):
		return _purchase_result(false, unchanged, unchanged_cash, unchanged_pool)
	if typeof(player_id) != TYPE_INT or int(player_id) < 0:
		return _purchase_result(false, unchanged, int(cash), int(pool))
	if typeof(number) != TYPE_INT or int(number) < FIRST_NUMBER or int(number) > LAST_NUMBER:
		return _purchase_result(false, unchanged, int(cash), int(pool))
	if int(cash) < TICKET_PRICE or (is_ai and int(cash) <= TICKET_PRICE) or int(pool) > MAX_MONEY - TICKET_PRICE:
		return _purchase_result(false, unchanged, int(cash), int(pool))
	var slot: int = int(number) - FIRST_NUMBER
	if int(tickets[slot]) != 0:
		return _purchase_result(false, unchanged, int(cash), int(pool))
	# AI selection is deliberately kept outside this pure accounting boundary;
	# the caller chooses the number and may use this same transition.
	var next_tickets: Array = tickets.duplicate(true)
	next_tickets[slot] = int(player_id) + 1
	return _purchase_result(true, next_tickets, int(cash) - TICKET_PRICE, int(pool) + TICKET_PRICE)


static func selection_numbers(tickets: Variant) -> Array:
	if typeof(tickets) != TYPE_ARRAY or tickets.is_empty():
		return []
	if not _valid_tickets(tickets):
		return []
	var sold: Array = []
	for index in range(NUMBER_COUNT):
		if int(tickets[index]) > 0:
			sold.append(index + FIRST_NUMBER)
	if sold.is_empty(): return []
	var counts: Dictionary = {}
	for owner in tickets:
		if int(owner) > 0:
			counts[owner] = int(counts.get(owner, 0)) + 1
	for count in counts.values():
		if int(count) > 10: return sold
	var all_numbers: Array = []
	for number in range(FIRST_NUMBER, LAST_NUMBER + 1):
		all_numbers.append(number)
	return all_numbers


static func settle(tickets: Variant, pool: Variant, winning_number: Variant) -> Dictionary:
	var settled_tickets: Array = tickets.duplicate(true) if typeof(tickets) == TYPE_ARRAY else []
	var jackpot: int = int(pool) if _valid_money(pool) else 0
	if not _valid_tickets(tickets) or not _valid_money(pool):
		return _settle_result(-1, 0, settled_tickets, jackpot)
	if typeof(winning_number) != TYPE_INT or int(winning_number) < FIRST_NUMBER or int(winning_number) > LAST_NUMBER:
		return _settle_result(-1, 0, settled_tickets, jackpot)
	var slot: int = int(winning_number) - FIRST_NUMBER
	var owner: int = int(tickets[slot])
	if owner <= 0:
		# Unclaimed draws roll the jackpot forward and leave every ticket active.
		return _settle_result(-1, 0, settled_tickets, jackpot)
	settled_tickets = empty_slots()
	return _settle_result(owner - 1, jackpot, settled_tickets, 0)


static func clear_owner(tickets: Variant, player_id: Variant) -> Array:
	if not _valid_tickets(tickets) or typeof(player_id) != TYPE_INT or int(player_id) < 0:
		return tickets.duplicate(true) if typeof(tickets) == TYPE_ARRAY else []
	var cleared: Array = tickets.duplicate(true)
	var owner: int = int(player_id) + 1
	for index in range(NUMBER_COUNT):
		if int(cleared[index]) == owner:
			cleared[index] = 0
	return cleared


static func valid_state(tickets: Variant, players: Variant, pool: Variant) -> bool:
	if not _valid_tickets(tickets) or not _valid_money(pool) or typeof(players) != TYPE_ARRAY:
		return false
	for value in tickets:
		var owner: int = int(value)
		if owner > players.size():
			return false
	return true


static func _valid_tickets(tickets: Variant) -> bool:
	if typeof(tickets) != TYPE_ARRAY or tickets.size() != NUMBER_COUNT:
		return false
	for value in tickets:
		if typeof(value) != TYPE_INT or int(value) < 0:
			return false
	return true


static func _valid_money(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= MAX_MONEY


static func _purchase_result(ok: bool, tickets: Array, cash: int, jackpot: int) -> Dictionary:
	return {"ok": ok, "tickets": tickets, "cash": cash, "jackpot": jackpot}


static func _settle_result(winner_id: int, amount: int, tickets: Array, jackpot: int) -> Dictionary:
	return {"winner_id": winner_id, "amount": amount, "tickets": tickets, "jackpot": jackpot}
