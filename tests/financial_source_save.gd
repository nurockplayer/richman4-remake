extends "res://tests/financial_fees.gd"

func _initialize() -> void:
	var g := fee_game(74911)
	own_property(g, 1)
	card(g, 0, "免費")
	land(g, 2, 1, 0)
	var decision := pending(g, "rent")
	if not decision.is_empty():
		legal(g, "source rent pending legal before isolated mutations")
		for patch in [{"kind": "facility"}, {"creditor_id": 2}, {"kind": "company", "creditor_id": -2}]:
			var data: Dictionary = g.to_dict().duplicate(true)
			for key in patch: data.pending_finance[key] = patch[key]
			expect(not Game.validate_save(data).get("ok", false), "pending source identity mutation rejected: %s" % str(patch))
			expect(Game.from_dict(data) == null, "malformed source identity cannot load: %s" % str(patch))
	g = fee_game(74912)
	own_company(g)
	card(g, 0, "免費")
	land(g, 5, 4, 2)
	decision = pending(g, "company")
	if not decision.is_empty():
		legal(g, "source company pending legal before isolated mutation")
		var data: Dictionary = g.to_dict().duplicate(true)
		data.pending_finance.creditor_id = -999
		expect(not Game.validate_save(data).get("ok", false), "nonexistent company creditor rejected")
		expect(Game.from_dict(data) == null, "nonexistent company creditor cannot load")
	print("Financial source save checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
