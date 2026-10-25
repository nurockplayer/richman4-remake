extends RefCounted
## Source bank loans credit deposits; repayments use deposits before cash.
## Entry/phase/status admission remains in GameState.

const MONEY_MAX := 1000000000000
const TERM_DAYS := 90


static func limit(action: String, player: Dictionary, bank: Dictionary, wealth: int) -> int:
	var deposit: int = int(player.get("deposit", 0))
	var cash: int = int(player.get("cash", 0))
	var loan: int = int(player.get("loan", 0))
	if action == "take_loan":
		var credit: int = maxi(0, wealth - loan)
		for remaining in [MONEY_MAX - deposit, MONEY_MAX - loan, MONEY_MAX - int(bank.get("deposits", 0)), MONEY_MAX - int(bank.get("loans", 0))]:
			credit = mini(credit, int(remaining))
		return maxi(0, credit)
	if action == "repay_loan":
		var available_cash: int = mini(cash, maxi(0, MONEY_MAX - int(bank.get("cash", 0))))
		return mini(loan, deposit + available_cash)
	return 0


static func take(player: Dictionary, bank: Dictionary, amount: int, day: int, weekday: int) -> void:
	player.deposit = int(player.deposit) + amount
	player.loan = int(player.loan) + amount
	bank.deposits = int(bank.deposits) + amount
	bank.loans = int(bank.loans) + amount
	if int(player.get("loan_due_day", 0)) == 0:
		# The source closes on Sunday as well as map-specific holidays. The
		# latter are not mapped yet; retain the existing Sunday-only calendar.
		var due: int = day + TERM_DAYS
		if posmod(weekday - 1 + TERM_DAYS, 7) + 1 == 7:
			due += 1
		player.loan_due_day = due


static func repay(player: Dictionary, bank: Dictionary, amount: int) -> void:
	var from_deposit: int = mini(amount, int(player.deposit))
	var from_cash: int = amount - from_deposit
	player.deposit = int(player.deposit) - from_deposit
	player.cash = int(player.cash) - from_cash
	player.loan = int(player.loan) - amount
	bank.deposits = maxi(0, int(bank.deposits) - from_deposit)
	bank.cash = int(bank.cash) + from_cash
	bank.loans = maxi(0, int(bank.loans) - amount)
	if int(player.loan) == 0:
		player.loan_due_day = 0
