extends "res://tests/source_lottery_core.gd"

func make_actor(mode: String, cash: int) -> Object:
	var definition := Fixture.definition()
	definition.board[3].merge({"kind":"lottery","type_and_idx":0,"event_code":9,"source_status_bits":9},true)
	var game: Object = Game.new_game_on_board(42,4,definition,{"original_facilities":true,"original_gods":true,"original_companies":true,"human_flags":[mode != "ai",true,true,true],"start_date":{"year":1998,"month":1,"day":14}})
	if mode == "trustee":
		var rows: Array = game.trustee_rows()
		rows[0].trustee = true
		if not game.apply_trustee_settings(rows): return null
	game.state.players[0].cash = cash
	enter(game)
	return game

func _initialize() -> void:
	for mode in ["human","ai","trustee"]:
		for cash in [1000,1001]:
			var game: Object = make_actor(mode,cash)
			if game == null or not Game.validate_save(game.to_dict()).ok:
				print("PRECONDITION_UNMET: valid public purchase actor ",mode,"/",cash)
				quit(2)
				return
			var before: String = game.to_json()
			var allowed: bool = mode == "human" or cash > 1000
			var result: Dictionary = game.purchase_lottery(1)
			expect(bool(result.ok) == allowed, "public purchase applies owner identity threshold: %s/%d" % [mode,cash])
			if allowed:
				expect(game.state.players[0].cash == cash-1000 and game.state.jackpot == 1000 and game.state.lottery_tickets[0] == 1 and game.state.phase == "await_action", "public purchase accounts for one ticket: %s/%d" % [mode,cash])
				var paid: String = game.to_json()
				expect(not game.purchase_lottery(2).ok and game.to_json() == paid, "public repeated purchase remains inert")
			else:
				expect(game.to_json() == before, "public AI refusal preserves cash pool tickets phase and RNG: %s/%d" % [mode,cash])
	# Public AI/real trustee dispatch remains a separate consumer of the flow.
	for mode in ["ai","trustee"]:
		for cash in [1000,1001]:
			var game: Object = make_actor(mode,cash)
			var result: Dictionary = game.run_ai_turn()
			var purchased := 0
			for event in game.state.event_log:
				if event.get("type","") == "lottery_purchased": purchased += 1
			expect(result.ok and purchased == (1 if cash > 1000 else 0), "public AI dispatch preserves threshold: %s/%d" % [mode,cash])
	print("Lottery public purchase acceptance: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
