extends RefCounted

## Source event 16 (魔法屋), docs/original-landing-events.md. A landing draws one
## target group, then one effect is applied to every member in player order.
## Humans choose the effect from all twelve; AI uses the source draw.
const Catalogue = preload("res://game/content/original_inventory.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const EVENT_CODE := 16
const SEQUENCE_LIMIT := 1000000000

const GROUP_NAMES := [
	"財產最多的人", "土地最多的人", "房屋最多的人", "現金最多的人", "存款最多的人", "點券最多的人",
	"走路的人", "騎機車的人", "開汽車的人", "神明附身的人", "所有男生", "所有女生",
]
const EFFECT_NAMES := [
	"變賣所有卡片", "抽取命運三張", "立刻坐牢三天", "原地停留一回合", "存入所有現金", "就地加蓋房屋",
	"得一張卡片", "向後轉", "變賣所有道具", "就地拆除房屋", "住院檢查三天", "拍賣當格土地",
]
## Effects whose source helpers are not traced yet (build path, demolition
## helper, auction caller). They resolve as an explicit no-op and are
## disabled in the human menu; AI never draws 11 and logs 5/9 as skipped.
const UNRESTORED_EFFECTS := [5, 9, 11]
## Gender byte +0x14 per setup character (SETUP_CHARACTER_NAMES order). The
## source table was not traced; values follow the published character roster.
const CHARACTER_IS_MALE := [true, true, true, false, true, false, true, false, false, false, true, true]

static func enabled(game: Object) -> bool:
	return game._is_statuses() and game._is_inventory() and game._is_gods() and game._is_companies() and game._is_graph()

static func supports_save(data: Dictionary) -> bool:
	return bool(data.get("original_statuses", false)) and bool(data.get("original_companies", false)) and data.get("board_mode", "") == "graph"

static func initialize(state: Dictionary) -> void:
	state["magic_house_sequence"] = 0
	state["magic_house"] = {}

static func current(game: Object) -> Dictionary:
	if not enabled(game) or game.state.get("phase", "") != "await_magic_house": return {}
	var visit: Variant = game.state.get("magic_house", {})
	return visit if visit is Dictionary and not visit.is_empty() else {}

static func admit(game: Object, player_id: int) -> bool:
	if not enabled(game) or str(game.state.get("phase", "")) == "game_over": return false
	var player: Dictionary = game._player(player_id)
	var tile: Dictionary = game._tile_at(int(player.get("position", -1)))
	if player_id != int(game.state.current_player) or not bool(player.get("alive", false)) or int(tile.get("event_code", -1)) != EVENT_CODE: return false
	var sequence := int(game.state.get("magic_house_sequence", 0)) + 1
	if sequence > SEQUENCE_LIMIT: return false
	var group_id := -1
	var targets: Array = []
	# Source 432719/433910: rand % 12 until the group has a member. Every alive
	# player is in one gender group, so the loop always ends.
	for attempt in range(1000):
		group_id = game._rng.randi_range(0, 11)
		targets = group_members(game, group_id)
		if not targets.is_empty(): break
	if targets.is_empty(): return false
	game.state.magic_house_sequence = sequence
	var human := bool(player.get("is_human", false)) and not bool(player.get("is_ai", true))
	game.state.magic_house = {"visit_id": sequence, "player_id": player_id, "node_id": int(player.position), "turn": int(game.state.turn), "group_id": group_id, "targets": targets}
	game._record_event("magic_house_entered", {"player_id": player_id, "visit_id": sequence, "group_id": group_id, "group": GROUP_NAMES[group_id], "targets": targets.duplicate()})
	if human:
		game.state.phase = "await_magic_house"
		game.state.action_options = []
		return true
	_resolve(game, ai_effect(game, player_id, targets))
	return true

## Source 433966: an AI inside the group takes a card; otherwise rand % 11
## with 6 remapped to 7.
static func ai_effect(game: Object, player_id: int, targets: Array) -> int:
	if targets.has(player_id): return 6
	var effect: int = game._rng.randi_range(0, 10)
	return 7 if effect == 6 else effect

static func choose(game: Object, visit_id: int, effect_id: int) -> Dictionary:
	var visit := current(game)
	if visit.is_empty() or int(visit.visit_id) != visit_id: return game._error("魔法屋已失效")
	if effect_id < 0 or effect_id >= EFFECT_NAMES.size() or UNRESTORED_EFFECTS.has(effect_id): return game._error("這個魔法尚未開放")
	game.state.phase = "await_action"
	_resolve(game, effect_id)
	return game._result(true, "已施展魔法：" + EFFECT_NAMES[effect_id])

## A pending human visit taken over by AI resolves with the AI draw.
static func ai_turn(game: Object) -> void:
	var visit := current(game)
	if visit.is_empty(): return
	game.state.phase = "await_action"
	_resolve(game, ai_effect(game, int(visit.player_id), visit.targets))

static func _resolve(game: Object, effect_id: int) -> void:
	var visit: Dictionary = game.state.magic_house
	var caster_id := int(visit.player_id)
	game._record_event("magic_house_cast", {"player_id": caster_id, "visit_id": int(visit.visit_id), "effect_id": effect_id, "effect": EFFECT_NAMES[effect_id], "targets": visit.targets.duplicate()})
	for target_id in visit.targets:
		if str(game.state.get("phase", "")) == "game_over": break
		var target: Dictionary = game._player(int(target_id))
		if target.is_empty() or not bool(target.get("alive", false)): continue
		_apply(game, effect_id, int(target_id), caster_id)
	game.state.magic_house = {}
	if str(game.state.get("phase", "")) != "game_over":
		game._set_action_options(caster_id)

static func _apply(game: Object, effect_id: int, target_id: int, caster_id: int) -> void:
	var target: Dictionary = game._player(target_id)
	var detail := {"player_id": caster_id, "target_id": target_id, "effect_id": effect_id}
	match effect_id:
		0:
			var total := 0
			for card_id in target.cards.duplicate():
				if bool(Inventory.consume_card(game.state.inventory_supply, target.cards, card_id).get("ok", false)):
					total += int(Catalogue.card(str(card_id)).get("price", 0))
			target.points = int(target.get("points", 0)) + total
			detail["points"] = total
		1:
			for draw in range(3):
				if not bool(game._player(target_id).get("alive", false)) or str(game.state.get("phase", "")) == "game_over": break
				game._resolve_fate_landing(target_id)
		2, 10:
			var kind := "prison" if effect_id == 2 else "hospital"
			# Source 441210 consumes 免罪 and cancels. 嫁禍 may redirect in the
			# source; its target rule is not traced, so it is not offered here.
			if game._trap_has_card(target, "免罪") and game._trap_consume_card(target_id, "免罪"):
				detail["blocked"] = true
			else:
				game._admit_player_status(target_id, kind, 3)
		3:
			target["stay_next"] = max(1, int(target.get("stay_next", 0)))
		4:
			# Same ledger as an ATM deposit: the bank holds the cash and owes it.
			var amount: int = mini(int(target.get("cash", 0)), game.bank_transfer_limit("deposit", target_id))
			if amount > 0:
				target.cash = int(target.cash) - amount
				target.deposit = int(target.get("deposit", 0)) + amount
				game.state.bank.cash = int(game.state.bank.get("cash", 0)) + amount
				game.state.bank.deposits = int(game.state.bank.get("deposits", 0)) + amount
			detail["amount"] = max(amount, 0)
		6:
			var draw: Dictionary = Inventory.receive_random_card(game.state.inventory_supply, target.cards, game._rng)
			detail["card_id"] = str(draw.get("drawn_card_id", ""))
		7:
			# Source 40c78c only runs when the status dword is clear; a detained
			# player keeps no previous node.
			if game._status_active(target) or game._sleep_active(target):
				detail["skipped"] = "detained"
			else:
				game._reverse_player_direction(target_id)
		8:
			detail["points"] = game._sell_all_tools_for_points(target_id)
		_:
			detail["skipped"] = "unrestored"
	game._record_event("magic_house_effect", detail)

static func group_members(game: Object, group_id: int) -> Array:
	var members: Array = []
	var best := 0
	for player in game._players():
		if not player is Dictionary or not bool(player.get("alive", false)): continue
		var player_id := int(player.get("id", -1))
		var value: int = 0
		match group_id:
			0: value = game._player_wealth(player_id)
			1: value = _owned_count(game, player, false)
			2: value = _owned_count(game, player, true)
			3: value = int(player.get("cash", 0))
			4: value = int(player.get("deposit", 0))
			5: value = int(player.get("points", 0))
			6, 7, 8:
				if str(player.get("vehicle", "walking")) == ["walking", "motorcycle", "car"][group_id - 6]: members.append(player_id)
				continue
			9:
				if game._player_god_id(player_id) != 0: members.append(player_id)
				continue
			10, 11:
				var character := int(player.get("character_id", -1))
				if character >= 0 and character < CHARACTER_IS_MALE.size() and CHARACTER_IS_MALE[character] == (group_id == 10): members.append(player_id)
				continue
		# Highest value wins with ties. Wealth starts at zero so a zero-wealth
		# tie qualifies; every other ranking needs a positive value.
		if value < 0 or (value == 0 and group_id != 0): continue
		if value > best:
			members = [player_id]
			best = value
		elif value == best:
			members.append(player_id)
	return members

static func _owned_count(game: Object, player: Dictionary, built_only: bool) -> int:
	var seen := {}
	for property_id in player.get("properties", []):
		var tile: Dictionary = game._tile_at(int(property_id))
		if tile.is_empty() or (built_only and int(tile.get("building_level", 0)) <= 0): continue
		seen["facility:%d" % int(tile.get("source_object_id", -1)) if tile.get("kind", "") == "facility" else "tile:%d" % int(property_id)] = true
	return seen.size()

static func _integer(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

static func validate(data: Dictionary, supported: bool) -> Array:
	if not supported:
		return ["magic house requires original statuses and companies"] if data.has("magic_house") or data.has("magic_house_sequence") or data.get("phase") == "await_magic_house" else []
	if not data.has("magic_house") and not data.has("magic_house_sequence"):
		return ["pending magic house has no visit"] if data.get("phase") == "await_magic_house" else []
	if not _integer(data.get("magic_house_sequence"), 0, SEQUENCE_LIMIT) or not data.get("magic_house") is Dictionary: return ["invalid magic house state"]
	var visit: Dictionary = data.magic_house
	if visit.is_empty():
		return ["pending magic house has no visit"] if data.get("phase") == "await_magic_house" else []
	if data.get("phase") != "await_magic_house": return ["magic house visit outside its phase"]
	var players: Variant = data.get("players")
	var board: Variant = data.get("board")
	if not players is Array or not board is Array: return ["invalid magic house identity"]
	if not _integer(visit.get("visit_id"), 1, int(data.magic_house_sequence)) or not _integer(visit.get("player_id"), 0, players.size() - 1) or not _integer(visit.get("node_id"), 0, board.size() - 1) or not _integer(visit.get("group_id"), 0, 11): return ["invalid magic house identity"]
	if not _integer(data.get("current_player"), int(visit.player_id), int(visit.player_id)) or not _integer(data.get("turn"), int(visit.get("turn", -1)), int(visit.get("turn", -1))): return ["stale magic house owner"]
	var player: Variant = players[int(visit.player_id)]
	var tile: Variant = board[int(visit.node_id)]
	if not player is Dictionary or not tile is Dictionary or not bool(player.get("alive", false)) or not _integer(player.get("position"), int(visit.node_id), int(visit.node_id)) or not _integer(tile.get("event_code"), EVENT_CODE, EVENT_CODE): return ["stale magic house owner"]
	var targets: Variant = visit.get("targets")
	if not targets is Array or targets.is_empty() or targets.size() > players.size(): return ["invalid magic house targets"]
	var previous := -1
	for target_id in targets:
		if not _integer(target_id, previous + 1, players.size() - 1): return ["invalid magic house targets"]
		previous = int(target_id)
	if data.get("action_options") != []: return ["pending magic house has ordinary actions"]
	return []
