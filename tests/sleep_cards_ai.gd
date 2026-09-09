extends "res://tests/sleep_cards_flow.gd"

func _initialize() -> void:
	for scenario in ["dream", "winter", "winter_targets", "human_response"]:
		var game := new_game(69821)
		var actor: Dictionary = game.state.players[0]
		game.state.bank.deposits -= int(actor.deposit)
		actor.deposit = 0
		actor.cash = 0
		if scenario == "winter_targets":
			stage_card(game, 0, WINTER_CARD)
			expect(game.choose_action("use_card", {"card_id": WINTER_CARD}).get("ok", false), "prepare winter opponents through public action")
		if scenario == "human_response":
			stage_card(game, 1, SCAPEGOAT_CARD)
		stage_card(game, 0, WINTER_CARD if scenario == "winter" else DREAM_CARD)
		game.set_player_ai(0, true)
		prepare(game, 0)
		expect(Game.validate_save(game.to_dict()).get("ok", false), scenario + " AI fixture validates")
		var mirror: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		expect(mirror != null, scenario + " AI fixture reloads")
		var result: Dictionary = game.run_ai_turn()
		expect(result.get("ok", false), scenario + " public AI turn succeeds")
		if scenario == "human_response":
			expect(result.get("awaiting_response", false) and not result.get("completed", true), "AI dream pauses for human defense")
			expect(game.state.get("pending_trap_card", "") == DREAM_CARD, "AI created dream response discriminator")
			expect(int(game.state.players[1].get("dream_days", 0)) == 0, "AI waits before applying human dream")
		elif scenario == "winter_targets":
			expect(actor.cards.has(DREAM_CARD), "AI preserves dream when all opponents winter")
		else:
			expect(actor.cards.is_empty(), scenario + " AI consumes its action card")
			expect(int(game.state.players[1].get("winter_sleep_days" if scenario == "winter" else "dream_days", 0)) == 5, scenario + " AI affects an eligible opponent")
			expect(int(game.state.current_player) != 0, scenario + " AI completes and hands off")
		expect(Game.validate_save(game.to_dict()).get("ok", false), scenario + " AI result validates")
		if mirror != null:
			mirror.run_ai_turn()
			expect(game.to_json() == mirror.to_json(), scenario + " AI replay exactly matches JSON")
	print("Sleep cards AI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
