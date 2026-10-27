extends RefCounted

## Source events 4 (監獄入口) and 5 (醫院入口), docs/original-landing-events.md.
## Ending a move on either node offers to bail any other alive player who is
## currently detained in that facility, at 30 points each. Humans choose from
## the roster and confirm; AI leaves on a coin flip or bails the drawn player
## only when its points are strictly above the price.
const KIND_BY_EVENT := {4: "prison", 5: "hospital"}
const PRICE := 30
const SEQUENCE_LIMIT := 1000000000

static func enabled(game: Object) -> bool:
	return game._is_statuses() and game._is_inventory() and game._is_graph()

static func supports_save(data: Dictionary) -> bool:
	return bool(data.get("original_statuses", false)) and data.get("board_mode", "") == "graph"

static func initialize(state: Dictionary) -> void:
	state["status_service_sequence"] = 0
	state["status_service"] = {}

static func current(game: Object) -> Dictionary:
	if not enabled(game) or game.state.get("phase", "") != "await_status_service": return {}
	var visit: Variant = game.state.get("status_service", {})
	return visit if visit is Dictionary and not visit.is_empty() else {}

## Ids of alive players other than the lander whose counter for the facility is
## 1..127. 128 is the source "release next turn" marker and is not bailable.
static func roster(game: Object, kind: String, lander_id: int) -> Array:
	var status_key: String = game._status_key(kind)
	var ids: Array = []
	if status_key.is_empty(): return ids
	for player in game._players():
		if not player is Dictionary or not bool(player.get("alive", false)): continue
		var player_id := int(player.get("id", -1))
		if player_id == lander_id: continue
		var count := int(player.get(status_key, 0))
		if count >= 1 and count <= 127: ids.append(player_id)
	ids.sort()
	return ids

static func admit(game: Object, player_id: int) -> bool:
	if not enabled(game) or str(game.state.get("phase", "")) == "game_over": return false
	var player: Dictionary = game._player(player_id)
	var tile: Dictionary = game._tile_at(int(player.get("position", -1)))
	var event_code := int(tile.get("event_code", -1))
	if not KIND_BY_EVENT.has(event_code): return false
	if player_id != int(game.state.current_player) or not bool(player.get("alive", false)): return false
	var kind: String = KIND_BY_EVENT[event_code]
	var members := roster(game, kind, player_id)
	if members.is_empty(): return false
	var sequence := int(game.state.get("status_service_sequence", 0)) + 1
	if sequence > SEQUENCE_LIMIT: return false
	game.state.status_service_sequence = sequence
	var visit := {"visit_id": sequence, "player_id": player_id, "node_id": int(player.position), "turn": int(game.state.turn), "kind": kind}
	var human := bool(player.get("is_human", false)) and not bool(player.get("is_ai", true))
	if human:
		game.state.status_service = visit
		game.state.phase = "await_status_service"
		game.state.action_options = []
		return true
	game.state.status_service = visit
	_resolve_ai(game, visit, members)
	return true

## Source draw: a coin flip leaves; otherwise one roster player is drawn and
## bailed only when the lander's points are strictly above the price.
static func _resolve_ai(game: Object, visit: Dictionary, members: Array) -> void:
	var target := -1
	if game._rng.randi_range(0, 1) != 0 and not members.is_empty():
		target = int(members[game._rng.randi_range(0, members.size() - 1)])
	if target >= 0 and int(game._player(int(visit.player_id)).get("points", 0)) > PRICE:
		_pay(game, visit, target)
	_finish(game)

static func bail(game: Object, visit_id: int, target_id: int) -> Dictionary:
	var visit := current(game)
	if visit.is_empty() or int(visit.visit_id) != visit_id: return game._error("保釋服務已失效")
	if not roster(game, str(visit.kind), int(visit.player_id)).has(target_id): return game._error("該玩家不在保釋名單")
	if int(game._player(int(visit.player_id)).get("points", 0)) < PRICE: return game._error("點券不足")
	_pay(game, visit, target_id)
	_finish(game)
	return game._result(true, "已保釋")

static func leave(game: Object, visit_id: int) -> Dictionary:
	var visit := current(game)
	if visit.is_empty() or int(visit.visit_id) != visit_id: return game._error("保釋服務已失效")
	_finish(game)
	return game._result(true, "已離開")

static func _pay(game: Object, visit: Dictionary, target_id: int) -> void:
	var lander: Dictionary = game._player(int(visit.player_id))
	var target: Dictionary = game._player(target_id)
	lander.points = int(lander.get("points", 0)) - PRICE
	target[game._status_key(str(visit.kind))] = 128
	game._record_event("status_bailed", {"player_id": int(visit.player_id), "target_id": target_id, "status_kind": str(visit.kind), "points": PRICE})

static func _finish(game: Object) -> void:
	var visit: Variant = game.state.get("status_service", {})
	var player_id: int = int(visit.get("player_id", game.state.get("current_player", -1))) if visit is Dictionary and not visit.is_empty() else int(game.state.get("current_player", -1))
	game.state.status_service = {}
	game.state.phase = "await_action"
	game._set_action_options(player_id)

static func _integer(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

static func validate(data: Dictionary, supported: bool) -> Array:
	if not supported:
		return ["status service requires original statuses"] if data.has("status_service") or data.has("status_service_sequence") or data.get("phase") == "await_status_service" else []
	if not data.has("status_service") and not data.has("status_service_sequence"):
		return ["pending status service has no visit"] if data.get("phase") == "await_status_service" else []
	if not _integer(data.get("status_service_sequence"), 0, SEQUENCE_LIMIT) or not data.get("status_service") is Dictionary: return ["invalid status service state"]
	var visit: Dictionary = data.status_service
	if visit.is_empty():
		return ["pending status service has no visit"] if data.get("phase") == "await_status_service" else []
	if data.get("phase") != "await_status_service": return ["status service visit outside its phase"]
	var players: Variant = data.get("players")
	var board: Variant = data.get("board")
	if not players is Array or not board is Array: return ["invalid status service identity"]
	if not _integer(visit.get("visit_id"), 1, int(data.status_service_sequence)) or not _integer(visit.get("player_id"), 0, players.size() - 1) or not _integer(visit.get("node_id"), 0, board.size() - 1): return ["invalid status service identity"]
	if not _integer(data.get("current_player"), int(visit.player_id), int(visit.player_id)) or not _integer(data.get("turn"), int(visit.get("turn", -1)), int(visit.get("turn", -1))): return ["stale status service owner"]
	var player: Variant = players[int(visit.player_id)]
	var tile: Variant = board[int(visit.node_id)]
	if not player is Dictionary or not tile is Dictionary or not bool(player.get("alive", false)) or not _integer(player.get("position"), int(visit.node_id), int(visit.node_id)): return ["stale status service owner"]
	var event_code: Variant = tile.get("event_code")
	if not _integer(event_code, 4, 5) or str(visit.get("kind", "")) != str(KIND_BY_EVENT[int(event_code)]): return ["invalid status service kind"]
	if data.get("action_options") != []: return ["pending status service has ordinary actions"]
	return []
