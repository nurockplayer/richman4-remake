extends RefCounted
## Source bank-chair financing is separate from ordinary loans. The original
## wealth routine intentionally does not subtract this principal.

const MONEY_MAX := 1000000000000


static func chair(state: Dictionary) -> int:
	var result := -1
	for company in state.get("companies", []):
		if int(company.get("company_type", 0)) == 7 and int(company.get("owner", -1)) >= 0:
			result = int(company.owner)
	return result


static func other_deposits(state: Dictionary, player_id: int, active_only: bool) -> int:
	var total := 0
	for player in state.get("players", []):
		if int(player.id) != player_id and (not active_only or bool(player.alive)):
			total += int(player.deposit)
	return total


static func limit(action: String, state: Dictionary, player_id: int) -> int:
	var player: Dictionary = state.players[player_id]
	var principal: int = int(player.get("special_finance", 0))
	if action == "take_special_finance":
		var credit: int = maxi(0, other_deposits(state, player_id, false) - principal)
		for headroom in [MONEY_MAX - principal, MONEY_MAX - int(player.deposit), MONEY_MAX - int(state.bank.deposits)]:
			credit = mini(credit, int(headroom))
		return maxi(0, credit)
	if action == "repay_special_finance":
		var cash: int = mini(int(player.cash), maxi(0, MONEY_MAX - int(state.bank.cash)))
		return mini(principal, int(player.deposit) + cash)
	return 0


static func take(state: Dictionary, player_id: int, amount: int) -> void:
	var player: Dictionary = state.players[player_id]
	player["special_finance"] = int(player.get("special_finance", 0)) + amount
	player.deposit = int(player.deposit) + amount
	state.bank.deposits = int(state.bank.deposits) + amount


static func repay(state: Dictionary, player_id: int, amount: int) -> void:
	var player: Dictionary = state.players[player_id]
	var deposit: int = mini(amount, int(player.deposit))
	var cash: int = amount - deposit
	player.special_finance = int(player.special_finance) - amount
	player.deposit = int(player.deposit) - deposit
	player.cash = int(player.cash) - cash
	state.bank.deposits = int(state.bank.deposits) - deposit
	state.bank.cash = int(state.bank.cash) + cash


static func collect(game: Object, player_id: int, required: int, reason: String) -> void:
	if required <= 0:
		return
	var player: Dictionary = game.state.players[player_id]
	var liquid: int = int(player.deposit) + int(player.cash)
	var paid: int = mini(required, limit("repay_special_finance", game.state, player_id))
	if paid > 0:
		repay(game.state, player_id, paid)
		game._record_event("special_finance_collected", {"player_id": player_id, "amount": paid, "reason": reason})
	if liquid < required:
		game._declare_bankruptcy(player_id, -1, required, reason)
	elif paid < required:
		# Existing save money bounds must not bankrupt a solvent player solely
		# because the bank cash counter has no room. Retry at the next source hook.
		game._record_event("special_finance_collection_deferred", {"player_id": player_id, "amount": required - paid, "reason": "bank_cash_limit"})


static func after_withdrawal(game: Object, withdrawing_id: int) -> void:
	var owner := chair(game.state)
	if owner < 0 or owner == withdrawing_id:
		return
	var player: Dictionary = game.state.players[owner]
	if bool(player.alive):
		collect(game, owner, maxi(0, int(player.get("special_finance", 0)) - other_deposits(game.state, owner, true)), "special_finance_capacity")


static func reconcile_ownership(game: Object) -> void:
	# Bankruptcy may clear stock holdings and change the chair during this
	# settlement. Revisit the bounded roster; reentrant Game callbacks are held.
	var collected: Dictionary = {}
	for _pass in range(game.state.players.size()):
		for player in game.state.players:
			if bool(player.alive) and int(player.id) != chair(game.state) and not collected.has(int(player.id)):
				collected[int(player.id)] = true
				collect(game, int(player.id), int(player.get("special_finance", 0)), "special_finance_chair_loss")
