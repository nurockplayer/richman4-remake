extends "res://tests/financial_fees.gd"
func _initialize() -> void:
	for free in [false, true]:
		var g := fee_game(74921)
		own_property(g, 1)
		set_funds(g, 0, 500)
		set_funds(g, 1, 999999999500)
		if free: card(g, 0, "免費")
		land(g, 2, 1, 0)
		if free:
			var decision := pending(g, "rent")
			if not decision.is_empty():
				legal(g, "actual payable credit fits ceiling while free pending")
				answer(g, false)
		expect(int(g.state.players[0].cash) == 0 and g.state.players[0].bankrupt, "partial rent pays available funds then bankruptcy")
		expect(int(g.state.players[1].cash) == 1000000000000, "actual partial rent reaches exact creditor cash ceiling")
		legal(g, "partial rent ceiling result remains valid")
	print("Financial fee cap checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
