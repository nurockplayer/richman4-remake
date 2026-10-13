extends RefCounted
## A source bank decision belongs to the simulation, including the unexecuted
## movement suffix. The presenter may close/rebuild without losing this token.

const SleepRules = preload("res://game/core/sleep_rules.gd")
const ATM_ACTIONS := ["deposit", "withdraw"]
const BANK_ACTIONS := ["deposit", "withdraw", "take_loan", "repay_loan", "take_special_finance", "repay_special_finance"]

static func has_pending(data: Dictionary) -> bool:
	return data.has("pending_bank_visit") and (not data.pending_bank_visit is Dictionary or not data.pending_bank_visit.is_empty())

static func is_bank_node(data: Dictionary, node_id: int) -> bool:
	var board: Variant = data.get("board", [])
	if not board is Array or node_id < 0 or node_id >= board.size() or not board[node_id] is Dictionary:
		return false
	var tile: Dictionary = board[node_id]
	if tile.get("kind", "") is String and tile.get("kind", "") == "bank":
		return true
	var source_id: Variant = tile.get("type_and_idx", null)
	if not _integer(source_id, 6001, 7999) or not data.get("companies", []) is Array:
		return false
	for company in data.get("companies", []):
		if company is Dictionary and _integer(company.get("id"), int(source_id) - 6000, int(source_id) - 6000) and _integer(company.get("company_type"), 7, 7):
			return true
	return false

static func eligible(game: Object, player_id: int, node_id: int) -> bool:
	if not game._is_companies() or not game._is_graph() or game._is_sunday() or game.state.get("phase", "") == "game_over":
		return false
	var actor: Dictionary = game._player(player_id)
	if not bool(actor.get("is_human", false)) or bool(actor.get("is_ai", true)) or not bool(actor.get("alive", false)) or game._status_active(actor) or game._sleep_active(actor):
		return false
	for key in ["pending_finance", "pending_auction", "pending_trap"]:
		if not game.state.get(key, {}).is_empty():
			return false
	return int(game.state.get("current_player", -1)) == player_id and int(game.state.get("company_service_pending", 0)) == 0 and is_bank_node(game.state, node_id)

static func admit(game: Object, player_id: int, node_id: int, kind: String) -> bool:
	if has_pending(game.state) or not eligible(game, player_id, node_id):
		return false
	if kind == "pass":
		if int(game.state.get("remaining_steps", 0)) <= 0:
			return false
		# Bound gods follow the already-completed edge; encounter effects wait.
		game._sync_attached_gods()
		game.state["phase"] = "await_bank"
		game.state["route_options"] = []
		game._record_event("bank_passed", {"player_id": player_id, "tile": node_id})
	elif kind != "landing" or game.state.get("phase", "") != "await_action":
		return false
	game.state["bank_access"] = true
	game.state["bank_landing"] = kind == "landing"
	game.state["pending_bank_visit"] = {"kind": kind, "player_id": player_id, "node_id": node_id}
	game.state["action_options"] = []
	game._set_action_options(player_id)
	return true

static func options(game: Object, token: Dictionary) -> Array:
	var result: Array = []
	var actor_id := int(token.player_id)
	for action in ATM_ACTIONS:
		if game.bank_transfer_limit(action, actor_id) > 0:
			result.append(action)
	if token.kind == "landing":
		for action in ["take_loan", "repay_loan"]:
			if (action != "take_loan" or not game._loan_block_active(game._player(actor_id))) and game.bank_loan_limit(action, actor_id) > 0:
				result.append(action)
		for action in ["take_special_finance", "repay_special_finance"]:
			if game.special_finance_limit(action, actor_id) > 0:
				result.append(action)
	return result

static func validate(data: Dictionary, enabled: bool) -> Array:
	var phase: Variant = data.get("phase", "")
	if not phase is String:
		return ["invalid bank visit phase"]
	if not has_pending(data):
		return ["await_bank missing bank visit"] if phase == "await_bank" else []
	var token: Variant = data.get("pending_bank_visit")
	if not enabled or not token is Dictionary or token.size() != 3 or not token.has_all(["kind", "player_id", "node_id"]):
		return ["invalid pending bank visit shape"]
	if not token.kind is String or token.kind not in ["pass", "landing"]:
		return ["invalid pending bank visit kind"]
	var players: Variant = data.get("players", [])
	var board: Variant = data.get("board", [])
	if not players is Array or not board is Array or not _integer(token.player_id, 0, players.size() - 1) or not _integer(token.node_id, 0, board.size() - 1):
		return ["invalid pending bank visit actor or node"]
	var actor: Variant = players[int(token.player_id)]
	if not actor is Dictionary or not _integer(data.get("current_player"), int(token.player_id), int(token.player_id)) or not _integer(actor.get("position"), int(token.node_id), int(token.node_id)) or not is_bank_node(data, int(token.node_id)):
		return ["pending bank visit position mismatch"]
	if not _boolean(actor.get("is_human"), true) or not _boolean(actor.get("is_ai"), false) or not _boolean(actor.get("alive"), true) or not _boolean(actor.get("bankrupt"), false) or not _integer(data.get("weekday"), 1, 6):
		return ["pending bank visit actor unavailable"]
	for key in ["hospital_days", "prison_days"]:
		if _integer(actor.get(key, 0), 1, 1000000000):
			return ["pending bank visit actor detained"]
	if SleepRules.is_active(actor.get("winter_sleep_days", 0)) or SleepRules.is_active(actor.get("dream_days", 0)):
		return ["pending bank visit actor asleep"]
	for key in ["pending_finance", "pending_auction", "pending_trap"]:
		var response: Variant = data.get(key, {})
		if not response is Dictionary or not response.is_empty():
			return ["pending bank visit conflicts with response"]
	if not _integer(data.get("company_service_pending", 0), 0, 0) or not _boolean(data.get("bank_access"), true) or not _boolean(data.get("bank_landing"), token.kind == "landing"):
		return ["pending bank visit admission mismatch"]
	var routes: Variant = data.get("route_options", [])
	var movement: Variant = data.get("pending_movement", {})
	if not routes is Array or not routes.is_empty() or not movement is Dictionary:
		return ["pending bank visit movement shape mismatch"]
	if token.kind == "pass":
		if phase != "await_bank" or not _integer(data.get("remaining_steps"), 1, 18) or not _integer(data.get("last_total"), int(data.get("remaining_steps", 0)), 18):
			return ["pending bank pass phase mismatch"]
		if movement.size() != 3 or not movement.has_all(["player_id", "current_node", "previous_node"]) or not _integer(movement.get("player_id"), int(token.player_id), int(token.player_id)) or not _integer(movement.get("current_node"), int(token.node_id), int(token.node_id)) or not _integer(movement.get("previous_node"), -1, board.size() - 1) or not _integer(actor.get("previous_position"), int(movement.previous_node), int(movement.previous_node)):
			return ["pending bank pass continuation mismatch"]
	else:
		if phase != "await_action" or not _integer(data.get("remaining_steps"), 0, 0) or not movement.is_empty():
			return ["pending bank landing phase mismatch"]
	var allowed: Array = ATM_ACTIONS if token.kind == "pass" else BANK_ACTIONS
	var actions: Variant = data.get("action_options", [])
	if not actions is Array:
		return ["invalid bank visit actions"]
	var seen: Array = []
	for action in actions:
		if not action is String or not allowed.has(action) or seen.has(action):
			return ["invalid bank visit action"]
		seen.append(action)
	return []

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and floor(float(value)) == float(value) and float(value) >= minimum and float(value) <= maximum

static func _boolean(value: Variant, expected: bool) -> bool:
	return typeof(value) == TYPE_BOOL and value == expected
