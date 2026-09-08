extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/status_fixture.gd")

var checks := 0
var failures := 0


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func make_game() -> Object:
	var game := Game.new_game_on_board(9494, 4, Fixture.definition(), {
		"original_statuses": true,
		"original_companies": true,
		"original_gods": true,
		"original_facilities": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	game.state.god_objects = []
	for player_id in range(4):
		game.set_player_ai(player_id, false)
		var player: Dictionary = game.state.players[player_id]
		for card in player.cards.duplicate():
			Inventory.consume_card(game.state.inventory_supply, player.cards, card)
	return game


func give(game: Object, player_id: int, card_id: String) -> void:
	expect(Inventory.grant_card(game.state.inventory_supply, game.state.players[player_id].cards, card_id).get("ok", false), "grant "+card_id)


func _initialize() -> void:
	# Healthy deposits and an open market must not starve the trap opportunity.
	# This starts at the real pre-roll entry, without disabling other systems.
	var ordinary_game := make_game()
	ordinary_game.set_player_ai(1,true)
	give(ordinary_game,1,"陷害")
	give(ordinary_game,0,"嫁禍")
	ordinary_game.state.current_player=1
	ordinary_game._set_action_options(1)
	var deposit_before: int=int(ordinary_game.state.players[1].deposit)
	var ordinary: Dictionary=ordinary_game.run_ai_turn()
	expect(ordinary.get("ok",false) and ordinary.get("awaiting_response",false) and not ordinary.get("completed",true),"normal-market AI uses trap before stock heuristic starves card")
	expect(ordinary_game.state.phase=="await_roll" and ordinary_game.state.last_roll.is_empty(),"AI pending trap pauses before dice movement")
	expect(int(ordinary_game.state.players[1].deposit)==deposit_before,"pending trap does not trade while waiting")
	expect(Game.validate_save(ordinary_game.to_dict()).get("ok",false),"normal-market AI pending snapshot valid")
	var cautious := make_game()
	cautious.set_player_ai(1,true)
	give(cautious,1,"陷害")
	give(cautious,0,"復仇")
	give(cautious,2,"嫁禍")
	cautious.state.current_player=1
	cautious._set_action_options(1)
	var cautious_result: Dictionary=cautious.run_ai_turn()
	expect(cautious_result.get("awaiting_response",false) and int(cautious.state.get("pending_trap",{}).get("target_id",-1))==2,"AI avoids revenge holder when another target exists")
	# An AI caster pauses the turn when a human target has 嫁禍.  The pending
	# record belongs to the current caster, while the response is accepted from
	# the human target without changing the caster's phase.
	var pending_game := make_game()
	pending_game.set_player_ai(1, true)
	pending_game.state.market.closed_days = 1
	pending_game.state.market.open = false
	give(pending_game, 1, "陷害")
	give(pending_game, 0, "嫁禍")
	pending_game.state.current_player = 1
	pending_game.state.phase = "await_action"
	pending_game._set_action_options(1)
	var ai_pending: Dictionary = pending_game.run_ai_turn()
	expect(ai_pending.get("ok", false) and ai_pending.get("awaiting_response", false), "AI pauses for human trap response")
	expect(pending_game.state.pending_trap == {"caster_id": 1, "target_id": 0}, "AI pending identifies caster and target")
	expect(pending_game.state.current_player == 1 and pending_game.state.phase == "await_action", "pending AI trap preserves caster phase")
	expect(pending_game.state.action_options == ["respond_trap"], "pending AI trap gates actions")
	var pending_json: String = pending_game.to_json()
	var restored: Object = Game.from_dict(JSON.parse_string(pending_json))
	expect(restored != null, "AI pending JSON restores")
	var response: Dictionary = pending_game.choose_action("respond_trap", {"cancel": true})
	expect(response.get("ok", false), "human can decline AI trap")
	expect(pending_game.state.pending_trap.is_empty() and int(pending_game.state.players[0].prison_days) == 5, "declined AI trap resolves original target")
	if restored != null:
		var restored_response: Dictionary = restored.choose_action("respond_trap", {"cancel": true})
		expect(restored_response.get("ok", false), "restored AI pending accepts same response")
		expect(pending_game.to_json() == restored.to_json(), "paired pending JSON replay is deterministic")
	var resume: Dictionary = pending_game.run_ai_turn()
	expect(resume.get("ok", false) and pending_game.state.current_player != 1, "AI resumes and completes after response")

	# An AI target responds automatically.  The deterministic lowest-id living
	# player is selected, including a detained player; the redirected admission
	# bypasses that player's own defense cards.
	var redirect_game := make_game()
	redirect_game.set_player_ai(1, true)
	redirect_game.set_player_ai(2, true)
	redirect_game.state.market.closed_days = 1
	redirect_game.state.market.open = false
	give(redirect_game, 1, "陷害")
	give(redirect_game, 2, "嫁禍")
	redirect_game._admit_player_status(0, "hospital", 3)
	redirect_game.state.current_player = 1
	redirect_game.state.phase = "await_action"
	redirect_game._set_action_options(1)
	var auto: Dictionary = redirect_game.run_ai_turn()
	expect(auto.get("ok", false), "AI resolves AI trap response automatically")
	expect(not redirect_game.state.players[2].cards.has("嫁禍"), "AI consumes successful scapegoat response")
	expect(int(redirect_game.state.players[0].hospital_days) == 0 and int(redirect_game.state.players[0].prison_days) == 5, "AI redirects to detained lowest-id player")
	expect(str(redirect_game.state.last_event.get("type", "")) in ["turn_started", "trap_redirected"], "AI redirect records deterministic event")

	# The pre-existing deposit heuristic remains available during ordinary AI
	# action resolution when no trap is pending.
	var deposit_game := make_game()
	deposit_game.set_player_ai(1, true)
	deposit_game.state.current_player = 1
	deposit_game.state.phase = "await_action"
	deposit_game.state.bank_access = true
	deposit_game.state.players[1].cash = 10000
	deposit_game.state.players[1].deposit = 0
	deposit_game._set_action_options(1)
	deposit_game._ai_action(1)
	expect(int(deposit_game.state.players[1].deposit) == 2500 and int(deposit_game.state.players[1].cash) == 7500, "ordinary AI deposit remains available")
	expect(deposit_game.state.pending_trap.is_empty(), "ordinary AI action has no pending trap")
	finish()


func finish() -> void:
	print("Trap AI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
