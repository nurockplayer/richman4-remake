extends "res://tests/financial_tax.gd"

func _initialize() -> void:
	var g: Object = fresh(74901)
	stage_card(g, 0, TAX_CARD)
	stage_card(g, 1, FREE_CARD)
	prepare(g, 0, "await_action", 3)
	expect(Game.validate_save(g.to_dict()).get("ok", false), "non-origin caster fixture legal")
	expect(use_tax(g, 1).get("ok", false), "non-origin caster tax starts")
	expect_equal(pending(g).get("node_id", -1), 3, "tax stores caster position rather than player id")
	expect(Game.validate_save(g.to_dict()).get("ok", false), "non-origin pending save legal")
	expect(respond(g, false).get("ok", false), "non-origin free response succeeds")
	for cancel in [false, true]:
		g = fresh(74902)
		for held in player(g, 1).cards.duplicate():
			Inventory.consume_card(g.state.inventory_supply, player(g, 1).cards, held)
		stage_card(g, 0, TAX_CARD)
		stage_card(g, 1, SCAPEGOAT_CARD)
		set_cash(g, 1, 20000)
		expect(Game.validate_save(g.to_dict()).get("ok", false), "scapegoat-only fixture legal")
		expect(use_tax(g, 1).get("ok", false), "scapegoat-only tax starts")
		expect_equal(pending(g).get("stage", ""), "redirect", "human without free chooses redirect")
		expect_equal(player(g, 1).cash, 20000, "redirect waits before payment")
		expect(player(g, 1).cards.has(SCAPEGOAT_CARD), "redirect waits before consumption")
		if pending(g).is_empty(): continue
		expect(Game.validate_save(g.to_dict()).get("ok", false), "scapegoat-only pending legal")
		var mirror: Object = Game.from_dict(JSON.parse_string(g.to_json()))
		expect(respond(g, cancel, 0).get("ok", false), "scapegoat-only response succeeds")
		expect_equal(player(g, 1).cash, 16000 if cancel else 20000, "redirect decision settles chosen target")
		expect(player(g, 1).cards.has(SCAPEGOAT_CARD) == cancel, "only selected redirect consumes card")
		if mirror != null:
			mirror.choose_action("respond_finance", {"cancel": cancel, "target_id": 0})
			expect_equal(g.to_json(), mirror.to_json(), "scapegoat-only JSON continuation exact")
	g = fresh(74903)
	stage_card(g, 0, FREE_CARD)
	var cash: int = player(g, 0).cash
	g.call("_charge_amount", 0, 2500, 1, "rent")
	expect(not g.state.has("pending_finance"), "generic primitive does not create source-specific free prompt")
	expect_equal(player(g, 0).cash, cash - 2500, "generic primitive retains payment behavior")
	g = fresh(74904)
	expect(not player(g, 0).has("insurance_days"), "financial cards do not add redundant insurance schema")
	print("Financial boundary checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
