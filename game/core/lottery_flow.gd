extends RefCounted

## Source lottery integration. Financial settlement is synchronous; presentation
## receives detached results and can never award the same draw a second time.
const Rules = preload("res://game/core/lottery_rules.gd")
const Calendar = preload("res://game/core/game_calendar.gd")
const LIMIT := 1000000000000

static func initialize(state: Dictionary) -> void:
	state["lottery_tickets"] = Rules.empty_slots()
	state["lottery_draw_day"] = 0
	state["lottery_pending"] = -1

static func admit(game: Object, player_id: int) -> void:
	if not game._is_companies(): return
	game.state.lottery_pending = player_id
	game.state.phase = "await_lottery"
	game.state.action_options = []
	game._record_event("lottery_entered", {"player_id": player_id})

static func purchase(game: Object, number: int, ai: bool = false) -> Dictionary:
	var state: Dictionary = game.state
	var player_id := int(state.get("current_player", -1))
	if not game._is_companies() or state.get("phase", "") != "await_lottery" or int(state.get("lottery_pending", -1)) != player_id:
		return game._error("目前沒有彩券購買事件")
	var player: Dictionary = game._player(player_id)
	var result: Dictionary = Rules.purchase(state.lottery_tickets, player_id, int(player.cash), int(state.jackpot), number, ai)
	if not result.get("ok", false): return game._error("無法購買這個號碼")
	state.lottery_tickets = result.tickets
	state.jackpot = result.jackpot
	player.cash = result.cash
	game._record_event("lottery_purchased", {"player_id": player_id, "number": number, "amount": 1000})
	return leave(game)

static func leave(game: Object) -> Dictionary:
	if game.state.get("phase", "") != "await_lottery" or int(game.state.get("lottery_pending", -1)) != int(game.state.current_player):
		return game._error("目前沒有彩券購買事件")
	game.state.lottery_pending = -1
	game.state.phase = "await_action"
	game._set_action_options(int(game.state.current_player))
	return game._result(true, "已離开彩券行")

static func ai_turn(game: Object) -> void:
	var player: Dictionary = game._player(int(game.state.current_player))
	var available: Array = Rules.available_numbers(game.state.lottery_tickets)
	if int(player.cash) > 1000 and int(game.state.jackpot) <= LIMIT - 1000 and not available.is_empty():
		purchase(game, int(available[game._rng.randi_range(0, available.size() - 1)]), true)
	else:
		leave(game)

static func settle_day(game: Object) -> void:
	if not game._is_companies() or not game._is_setup(): return
	var state: Dictionary = game.state
	var day := int(state.get("elapsed", 0))
	if day <= 0 or int(state.get("date", {}).get("day", 0)) != 15 or int(state.lottery_draw_day) >= day: return
	state.lottery_draw_day = day
	var choices: Array = Rules.selection_numbers(state.lottery_tickets)
	if choices.is_empty(): return
	# Refuse an unrepresentable award before consuming RNG. Retain tickets/pool
	# and record this bounded safety deviation rather than truncating the prize.
	for owner in state.lottery_tickets:
		if int(owner) > 0 and int(game._player(int(owner) - 1).cash) > LIMIT - int(state.jackpot):
			game._record_event("lottery_draw_blocked", {"reason": "cash_headroom", "day": day})
			return
	var number := int(choices[game._rng.randi_range(0, choices.size() - 1)])
	var pool_before := int(state.jackpot)
	var tickets: Array = state.lottery_tickets.duplicate()
	var result: Dictionary = Rules.settle(tickets, int(state.jackpot), number)
	if int(result.winner_id) >= 0:
		var winner: Dictionary = game._player(int(result.winner_id))
		winner.cash = int(winner.cash) + int(result.amount)
	state.lottery_tickets = result.tickets
	state.jackpot = result.jackpot
	var report := {"kind": "draw", "edition": str(state.get("map_source", {}).get("edition", "")), "date": state.date.duplicate(true), "draw_day": day, "number": number, "winner_id": result.winner_id, "amount": result.amount, "jackpot": pool_before, "jackpot_after": int(state.jackpot), "tickets": tickets, "players": presentation_players(state.players)}
	game._record_event("lottery_draw", {"report": report})

static func clear_player(state: Dictionary, player_id: int) -> void:
	if not state.has("lottery_tickets"): return
	state.lottery_tickets = Rules.clear_owner(state.lottery_tickets, player_id)
	if int(state.get("lottery_pending", -1)) == player_id: state.lottery_pending = -1

static func integer(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

static func validate(state: Dictionary, enabled: bool) -> Array:
	var errors: Array = []
	if not enabled:
		for key in ["lottery_tickets", "lottery_draw_day", "lottery_pending"]:
			if state.has(key): errors.append("lottery requires original companies")
		return errors
	var tickets: Variant = state.get("lottery_tickets")
	var players: Variant = state.get("players")
	if not tickets is Array or tickets.size() != 36 or not players is Array:
		return ["invalid lottery ticket shape"]
	for owner in tickets:
		if not integer(owner, 0, players.size()): return ["invalid lottery owner"]
		if int(owner) > 0:
			var player: Variant = players[int(owner) - 1]
			if not player is Dictionary or not bool(player.get("alive", false)): return ["lottery owner is not alive"]
	var elapsed: Variant = state.get("elapsed", 0)
	if not integer(elapsed, 0, 1000000000) or not state.get("start_date", {}) is Dictionary: return ["invalid lottery calendar"]
	if not integer(state.get("lottery_draw_day"), 0, int(elapsed)): errors.append("invalid lottery draw identity")
	if integer(state.get("lottery_draw_day"), 1, int(state.get("elapsed", 0))):
		var draw_date := Calendar.add_days(state.get("start_date", {}), int(state.lottery_draw_day))
		if int(draw_date.get("day", 0)) != 15: errors.append("lottery identity is not a draw date")
	if not integer(state.get("lottery_pending"), -1, players.size() - 1): return ["invalid lottery pending owner"]
	var pending := int(state.lottery_pending)
	if (pending >= 0) != (state.get("phase", "") == "await_lottery"): errors.append("lottery pending phase mismatch")
	if pending >= 0:
		if pending != state.get("current_player") or not players[pending] is Dictionary or not bool(players[pending].get("alive", false)): return ["invalid lottery actor"]
		var position: Variant = players[pending].get("position")
		var board: Variant = state.get("board")
		if not board is Array or not integer(position, 0, board.size()-1) or not board[int(position)] is Dictionary or board[int(position)].get("kind", "") != "lottery": errors.append("lottery requires source landing")
		if state.get("action_options", []) != []: errors.append("lottery has ordinary actions")
		for key in ["pending_bank_visit", "pending_finance", "pending_auction", "pending_trap"]:
			if state.has(key) and (not state[key] is Dictionary or not state[key].is_empty()): errors.append("overlapping lottery modal")
	return errors

static func presentation_players(players: Array) -> Array:
	var entries: Array = []
	for player in players:
		entries.append({"id": int(player.id), "name": str(player.name), "character_id": int(player.character_id), "alive": bool(player.alive)})
	return entries
