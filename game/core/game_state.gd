class_name Richman4GameState
extends RefCounted

## Deterministic, serializable simulation for the Godot runtime.
##
## The original executable and data files are kept outside this repository. The
## rules below are therefore an explicit provisional reconstruction. They are
## deliberately kept in one small state object so that observed corrections
## can be made without coupling the renderer to the simulation.

const SAVE_VERSION = 1
const GRAPH_SAVE_VERSION = 2
const RULESET_ID = "richman4_provisional_v1"
const RUNTIME_MAP_SCHEMA = "richman4.runtime-map/v1"
const GRAPH_BOARD_MODE = "graph"
const OriginalMaps = preload("res://game/content/original_maps.gd")
const BOARD_SIZE = 40
const MIN_PLAYERS = 2
const MAX_PLAYERS = 4
const START_CASH = 15000
const START_POSITION = 0
const MAX_PROPERTY_LEVEL = 5
const MAX_GRAPH_STEPS = 18
const MAX_AI_TURN_ITERATIONS = 16
const MAX_GRAPH_POINTS = 1000000000000
const PASS_START_BONUS = 0 # The reference manual does not support an invented bonus.
const DAYS_PER_MONTH = 30
const MONTHLY_DEPOSIT_RATE = 0.10
const LOAN_TERM_DAYS = 90
const INITIAL_BANK_CASH = 1000000
const INT64_MIN = -9223372036854775808
const INT64_MAX = 9223372036854775807
const MIN_SEED = -2147483648
const MAX_SEED = 2147483647

const VEHICLE_DICE = {
	"walking": 1,
	"motorcycle": 2,
	"car": 3,
}
const VEHICLE_COSTS = {
	"walking": 0,
	"motorcycle": 3000,
	"car": 7000,
}

const STOCK_SYMBOLS = ["tech", "transport", "energy"]
const STOCK_BASE_PRICES = {
	"tech": 120,
	"transport": 100,
	"energy": 80,
}

# Board locations, names, and values are provisional reconstruction data.
const PROPERTY_SPECS = [
	{"index": 1, "name": "和平路", "group": "north", "cost": 1000, "rent": 100, "upgrade_cost": 600},
	{"index": 2, "name": "中山路", "group": "north", "cost": 1200, "rent": 120, "upgrade_cost": 700},
	{"index": 3, "name": "民權路", "group": "north", "cost": 1400, "rent": 140, "upgrade_cost": 800},
	{"index": 5, "name": "忠孝路", "group": "east", "cost": 1600, "rent": 160, "upgrade_cost": 900},
	{"index": 6, "name": "仁愛路", "group": "east", "cost": 1800, "rent": 180, "upgrade_cost": 1000},
	{"index": 7, "name": "信義路", "group": "east", "cost": 2000, "rent": 200, "upgrade_cost": 1100},
	{"index": 9, "name": "復興路", "group": "east", "cost": 2200, "rent": 220, "upgrade_cost": 1200},
	{"index": 10, "name": "敦化路", "group": "east", "cost": 2400, "rent": 240, "upgrade_cost": 1300},
	{"index": 12, "name": "建國路", "group": "south", "cost": 2600, "rent": 260, "upgrade_cost": 1400},
	{"index": 13, "name": "光復路", "group": "south", "cost": 2800, "rent": 280, "upgrade_cost": 1500},
	{"index": 14, "name": "松江路", "group": "south", "cost": 3000, "rent": 300, "upgrade_cost": 1600},
	{"index": 16, "name": "南京路", "group": "south", "cost": 3200, "rent": 320, "upgrade_cost": 1700},
	{"index": 17, "name": "長春路", "group": "south", "cost": 3400, "rent": 340, "upgrade_cost": 1800},
	{"index": 18, "name": "民生路", "group": "south", "cost": 3600, "rent": 360, "upgrade_cost": 1900},
	{"index": 20, "name": "北平路", "group": "west", "cost": 3800, "rent": 380, "upgrade_cost": 2000},
	{"index": 21, "name": "天津路", "group": "west", "cost": 4000, "rent": 400, "upgrade_cost": 2100},
	{"index": 23, "name": "重慶路", "group": "west", "cost": 4200, "rent": 420, "upgrade_cost": 2200},
	{"index": 24, "name": "成都路", "group": "west", "cost": 4400, "rent": 440, "upgrade_cost": 2300},
	{"index": 25, "name": "西寧路", "group": "west", "cost": 4600, "rent": 460, "upgrade_cost": 2400},
	{"index": 27, "name": "華山路", "group": "central", "cost": 4800, "rent": 480, "upgrade_cost": 2500},
	{"index": 28, "name": "八德路", "group": "central", "cost": 5000, "rent": 500, "upgrade_cost": 2600},
	{"index": 29, "name": "光華路", "group": "central", "cost": 5200, "rent": 520, "upgrade_cost": 2700},
	{"index": 31, "name": "基隆路", "group": "central", "cost": 5400, "rent": 540, "upgrade_cost": 2800},
	{"index": 32, "name": "安和路", "group": "central", "cost": 5600, "rent": 560, "upgrade_cost": 2900},
	{"index": 34, "name": "大直路", "group": "harbor", "cost": 5800, "rent": 580, "upgrade_cost": 3000},
	{"index": 35, "name": "士林路", "group": "harbor", "cost": 6000, "rent": 600, "upgrade_cost": 3100},
	{"index": 36, "name": "北投路", "group": "harbor", "cost": 6200, "rent": 620, "upgrade_cost": 3200},
	{"index": 38, "name": "淡水路", "group": "harbor", "cost": 6400, "rent": 640, "upgrade_cost": 3300},
]

const EVENT_CARDS = [
	{"id": "均富", "name": "均富", "kind": "card", "effect": "equalize_cash"},
	{"id": "停留", "name": "停留", "kind": "card", "effect": "stay"},
	{"id": "烏龜", "name": "烏龜", "kind": "card", "effect": "turtle"},
	{"id": "紅", "name": "紅", "kind": "card", "effect": "stock_up"},
	{"id": "黑", "name": "黑", "kind": "card", "effect": "stock_down"},
]

var state: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func new_game(seed_value: int, player_count: int = 4) -> Richman4GameState:
	if seed_value < MIN_SEED or seed_value > MAX_SEED:
		return null
	if player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		return null
	var game = new()
	game._initialize(seed_value, player_count)
	return game


static func new_game_on_board(seed_value: int, player_count: int, definition: Dictionary) -> Richman4GameState:
	if seed_value < MIN_SEED or seed_value > MAX_SEED:
		return null
	if player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		return null
	var validation: Dictionary = validate_board_definition(definition)
	if not bool(validation.get("ok", false)):
		return null
	var game := new()
	game._initialize_graph(seed_value, player_count, validation["definition"])
	return game


func _initialize(seed_value: int, player_count: int) -> void:
	_rng.seed = seed_value
	state = {
		"version": SAVE_VERSION,
		"ruleset": RULESET_ID,
		"seed": seed_value,
		"seed_text": str(seed_value),
		"rng_state": int(_rng.state),
		"phase": "await_roll",
		"turn": 1,
		"round": 1,
		"day": 1,
		"month": 1,
		"day_of_month": 1,
		"weekday": 1,
		"current_player": 0,
		"winner": -1,
		"last_roll": [],
		"last_total": 0,
		"last_event": {},
		"event_log": [],
		"action_options": [],
		"extra_roll": false,
		"doubles_count": 0,
		"property_action_used": false,
		"bank_access": false,
		"bank_landing": false,
		"bank": {
			"cash": INITIAL_BANK_CASH,
			"deposits": 0,
			"loans": 0,
		},
		"market": {
			"prices": STOCK_BASE_PRICES.duplicate(true),
			"open": true,
			"trends": {},
		},
		"board": _build_board(),
		"players": _build_players(player_count),
		"bankruptcy_auctions": [],
	}
	_sync_state()
	_set_action_options(0)
	_record_event("new_game", {"seed": seed_value, "player_count": player_count})


func _initialize_graph(seed_value: int, player_count: int, definition: Dictionary) -> void:
	_rng.seed = seed_value
	var start_position: int = int(definition.get("start_position", 0))
	var board_value: Variant = _canonicalize_json_numbers(definition.get("board", []).duplicate(true))
	var board: Array = board_value
	var map_source_value: Variant = _canonicalize_json_numbers(definition.get("source", {}).duplicate(true))
	var map_source: Dictionary = map_source_value
	state = {
		"version": GRAPH_SAVE_VERSION,
		"ruleset": RULESET_ID,
		"seed": seed_value,
		"seed_text": str(seed_value),
		"rng_state": int(_rng.state),
		"phase": "await_roll",
		"turn": 1,
		"round": 1,
		"day": 1,
		"month": 1,
		"day_of_month": 1,
		"weekday": 1,
		"current_player": 0,
		"winner": -1,
		"last_roll": [],
		"last_total": 0,
		"last_event": {},
		"event_log": [],
		"action_options": [],
		"extra_roll": false,
		"doubles_count": 0,
		"property_action_used": false,
		"bank_access": false,
		"bank_landing": false,
		"bank": {
			"cash": INITIAL_BANK_CASH,
			"deposits": 0,
			"loans": 0,
		},
		"market": {
			"prices": STOCK_BASE_PRICES.duplicate(true),
			"open": true,
			"trends": {},
		},
		"board_mode": GRAPH_BOARD_MODE,
		"map_id": str(definition.get("id", "")),
		"map_name": str(definition.get("name", "")),
		"map_schema": str(definition.get("schema", RUNTIME_MAP_SCHEMA)),
		"map_version": int(definition.get("version", 1)),
		"map_source": map_source,
		"start_position": start_position,
		"board": board,
		"players": _build_players(player_count, start_position, true),
		"bankruptcy_auctions": [],
		"route_options": [],
		"remaining_steps": 0,
		"pending_movement": {},
	}
	_sync_state()
	_set_action_options(0)
	_record_event("new_game", {"seed": seed_value, "player_count": player_count, "map_id": state["map_id"]})


func _build_players(player_count: int, start_position: int = START_POSITION, graph_mode: bool = false) -> Array:
	var players: Array = []
	for player_id in range(player_count):
		var player: Dictionary = {
			"id": player_id,
			"name": "玩家 %d" % (player_id + 1),
			"is_human": player_id == 0,
			"is_ai": player_id != 0,
			"alive": true,
			"bankrupt": false,
			"cash": START_CASH,
			"deposit": 0,
			"position": start_position,
			"properties": [],
			"property_values": 0,
			"stocks": {"tech": 0, "transport": 0, "energy": 0},
			"cards": [],
			"vehicle": "walking",
			"dice_count": 1,
			"vehicles": {"walking": true, "motorcycle": false, "car": false},
			"skip_turns": 0,
			"rent_shield": 0,
			"turtle_days": 0,
			"stay_next": 0,
			"loan": 0,
			"loan_due_day": 0,
			"turns_taken": 0,
		}
		if graph_mode:
			player["previous_position"] = -1
			player["points"] = 0
		players.append(player)
	return players


func _build_board() -> Array:
	var property_by_index: Dictionary = {}
	for spec in PROPERTY_SPECS:
		property_by_index[int(spec["index"])] = spec
	var board: Array = []
	for index in range(BOARD_SIZE):
		var tile: Dictionary = {
			"index": index,
			"kind": "rest",
			"name": "休息區 %d" % index,
			"owner": -1,
			"building_level": 0,
			"cost": 0,
			"upgrade_cost": 0,
			"base_rent": 0,
			"rent": 0,
			"group": "",
			"tax_amount": 0,
		}
		if property_by_index.has(index):
			var spec: Dictionary = property_by_index[index]
			tile["kind"] = "property"
			tile["name"] = spec["name"]
			tile["cost"] = int(spec["cost"])
			tile["upgrade_cost"] = int(spec["upgrade_cost"])
			tile["base_rent"] = int(spec["rent"])
			tile["rent"] = int(spec["rent"])
			tile["group"] = spec["group"]
		elif index == 0:
			tile["kind"] = "start"
			tile["name"] = "起點"
		elif index in [4, 15, 26, 37]:
			tile["kind"] = "event"
			tile["name"] = "命運"
		elif index in [8, 22]:
			tile["kind"] = "tax"
			tile["name"] = "稅務局"
			tile["tax_amount"] = 1000 if index == 22 else 500
		elif index in [11, 30]:
			tile["kind"] = "bank"
			tile["name"] = "銀行"
		elif index in [19, 33]:
			tile["kind"] = "stock"
			tile["name"] = "證券交易所"
		board.append(tile)
	return board


func get_snapshot() -> Dictionary:
	_sync_state()
	return state.duplicate(true)


func _sync_state() -> void:
	if state.is_empty():
		return
	state["rng_state"] = int(_rng.state)
	state["rng_state_text"] = str(_rng.state)
	var day: int = int(state.get("day", 1))
	state["day_of_month"] = ((day - 1) % DAYS_PER_MONTH) + 1
	state["month"] = ((day - 1) / DAYS_PER_MONTH) + 1
	state["weekday"] = ((day - 1) % 7) + 1
	var market: Dictionary = state.get("market", {})
	market["open"] = not _is_sunday()
	state["market"] = market


func _is_sunday() -> bool:
	return int(state.get("weekday", 1)) == 7


func _players() -> Array:
	return state.get("players", [])


func _player(player_id: int) -> Dictionary:
	var players: Array = _players()
	if player_id < 0 or player_id >= players.size():
		return {}
	return players[player_id]


func _current_player() -> Dictionary:
	return _player(int(state.get("current_player", -1)))


func _valid_player(player_id: int, require_alive: bool = false) -> bool:
	var player: Dictionary = _player(player_id)
	if player.is_empty():
		return false
	return not require_alive or bool(player.get("alive", false))


func _record_event(event_type: String, payload: Dictionary = {}) -> void:
	var event: Dictionary = {"type": event_type, "day": int(state.get("day", 1)), "turn": int(state.get("turn", 1))}
	for key in payload:
		event[key] = payload[key]
	state["last_event"] = event
	var log: Array = state.get("event_log", [])
	log.append(event)
	if log.size() > 200:
		log.pop_front()
	state["event_log"] = log


func _result(ok: bool, message: String = "", extra: Dictionary = {}) -> Dictionary:
	_sync_state()
	var result: Dictionary = {
		"ok": ok,
		"message": message,
		"phase": state.get("phase", ""),
		"current_player": int(state.get("current_player", -1)),
		"event": state.get("last_event", {}).duplicate(true),
		"state": get_snapshot(),
	}
	for key in extra:
		result[key] = extra[key]
	return result


func _error(message: String) -> Dictionary:
	return _result(false, message)


func _require_phase(expected: String) -> bool:
	return state.get("phase", "") == expected


func _set_action_options(player_id: int) -> void:
	var phase: String = str(state.get("phase", ""))
	if phase == "game_over":
		state["action_options"] = []
		return
	var options: Array = []
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		state["action_options"] = options
		return
	var bank_open: bool = not _is_sunday()
	if bank_open:
		options.push_front("sell_stock")
		if int(player.get("cash", 0)) >= 10:
			options.push_front("buy_stock")
	if phase != "await_action":
		state["action_options"] = options
		return
	options.push_back("end_turn")
	var tile: Dictionary = _tile_at(int(player.get("position", 0)))
	if tile.get("kind", "") == "property" and not bool(state.get("property_action_used", false)):
		var owner: int = int(tile.get("owner", -1))
		if owner == -1 and int(player.get("cash", 0)) >= int(tile.get("cost", 0)):
			options.push_front("buy")
		elif owner == player_id:
			var level: int = int(tile.get("building_level", 0))
			if level < MAX_PROPERTY_LEVEL and int(player.get("cash", 0)) >= _upgrade_price(tile):
				options.push_front("upgrade")
	if tile.get("kind", "") == "bank":
		state["bank_landing"] = true
		if bank_open:
			options.push_front("take_loan")
	if bool(state.get("bank_access", false)) and bank_open:
		if int(player.get("cash", 0)) > 0:
			options.push_front("deposit")
		if int(player.get("deposit", 0)) > 0:
			options.push_front("withdraw")
	if bank_open:
		options.push_front("sell_stock")
		if int(player.get("cash", 0)) >= 10:
			options.push_front("buy_stock")
		var vehicles: Dictionary = player.get("vehicles", {})
		for vehicle in ["motorcycle", "car"]:
			if not bool(vehicles.get(vehicle, false)) and int(player.get("cash", 0)) >= int(VEHICLE_COSTS[vehicle]):
				options.push_front("buy_vehicle")
	if player.get("cards", []).size() > 0:
		options.push_front("use_card")
	state["action_options"] = options


func _tile_at(index: int) -> Dictionary:
	var board: Array = state.get("board", [])
	if index < 0 or index >= board.size():
		return {}
	return board[index]


func _is_graph() -> bool:
	return state.get("board_mode", "") == GRAPH_BOARD_MODE


func _array_contains_int(values: Variant, target: int) -> bool:
	if typeof(values) != TYPE_ARRAY:
		return false
	for value in values:
		if _valid_int(value) and int(value) == target:
			return true
	return false


func _upgrade_price(tile: Dictionary) -> int:
	if _is_graph():
		# The original housing record stores one house price.  Each level uses
		# that same price; the rent table, rather than a guessed multiplier,
		# determines the resulting rent.
		return int(tile.get("house_price", tile.get("upgrade_cost", 0)))
	return int(tile.get("upgrade_cost", 0)) * (int(tile.get("building_level", 0)) + 1)


func _player_owns_tile(player_id: int, tile_index: int) -> bool:
	var tile: Dictionary = _tile_at(tile_index)
	return int(tile.get("owner", -1)) == player_id


func set_player_ai(player_id: int, enabled: bool) -> bool:
	if not _valid_player(player_id):
		return false
	var player: Dictionary = _player(player_id)
	player["is_ai"] = enabled
	player["is_human"] = not enabled
	return true


func set_vehicle(vehicle: String, dice_count: int = -1) -> Dictionary:
	if not _require_phase("await_roll"):
		return _error("只能在擲骰前選擇交通工具")
	var player: Dictionary = _current_player()
	if player.is_empty() or not bool(player.get("alive", false)):
		return _error("目前玩家無法行動")
	if not VEHICLE_DICE.has(vehicle):
		return _error("未知的交通工具")
	var vehicles: Dictionary = player.get("vehicles", {})
	if not bool(vehicles.get(vehicle, false)):
		return _error("尚未擁有這項交通工具")
	var maximum: int = int(VEHICLE_DICE[vehicle])
	var selected: int = maximum if dice_count < 1 else dice_count
	if selected < 1 or selected > maximum:
		return _error("骰子數量超出交通工具限制")
	player["vehicle"] = vehicle
	player["dice_count"] = selected
	_record_event("vehicle_selected", {"player_id": int(player["id"]), "vehicle": vehicle, "dice_count": selected})
	return _result(true, "已選擇交通工具")


func roll(dice_count: int = -1) -> Dictionary:
	if not _require_phase("await_roll"):
		return _error("目前不是擲骰階段")
	var player_id: int = int(state.get("current_player", -1))
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return _error("目前玩家無法擲骰")
	if int(player.get("skip_turns", 0)) > 0:
		player["skip_turns"] = int(player.get("skip_turns", 0)) - 1
		state["last_roll"] = []
		state["last_total"] = 0
		state["extra_roll"] = false
		state["doubles_count"] = 0
		state["phase"] = "await_action"
		_set_action_options(player_id)
		_record_event("turn_skipped", {"player_id": player_id, "remaining": int(player["skip_turns"])})
		return _result(true, "本回合跳過")
	var maximum: int = int(VEHICLE_DICE.get(str(player.get("vehicle", "walking")), 1))
	var count: int = int(player.get("dice_count", maximum)) if dice_count < 1 else dice_count
	var turtle_step: bool = int(player.get("turtle_days", 0)) > 0
	if turtle_step:
		player["turtle_days"] = int(player.get("turtle_days", 0)) - 1
	if count < 1 or count > maximum:
		return _error("骰子數量超出交通工具限制")
	var dice: Array = []
	var total: int = 0
	if turtle_step:
		dice = [1]
		total = 1
	else:
		for _index in range(count):
			var face: int = _rng.randi_range(1, 6)
			dice.append(face)
			total += face
	state["last_roll"] = dice
	state["last_total"] = total
	state["property_action_used"] = false
	var graph_should_move: bool = false
	if int(player.get("stay_next", 0)) > 0:
		player["stay_next"] = int(player.get("stay_next", 0)) - 1
		_record_event("stay_resolved", {"player_id": player_id, "tile": int(player.get("position", 0))})
	elif _is_graph():
		graph_should_move = true
	else:
		_move_player(player_id, total)
	# The reference movement is one chosen roll per turn. Doubles do not grant
	# Monopoly-style bonus turns or automatic penalties.
	state["doubles_count"] = 0
	state["extra_roll"] = false
	_record_event("roll", {"player_id": player_id, "dice": dice, "total": total, "vehicle": player.get("vehicle", "walking")})
	if graph_should_move:
		_graph_begin_movement(player_id, total)
	if not _is_graph() or state.get("phase", "") != "await_route":
		_resolve_landing(player_id)
	return _result(true, "擲骰完成", {"dice": dice, "total": total})


func _graph_candidates(current_node: int, previous_node: int) -> Array:
	var tile: Dictionary = _tile_at(current_node)
	if tile.is_empty():
		return []
	var adjacent: Array = tile.get("adjacent", [])
	var candidates: Array = []
	for neighbor in adjacent:
		var neighbor_id: int = int(neighbor)
		if neighbor_id < 0 or neighbor_id >= state.get("board", []).size():
			continue
		if neighbor_id != previous_node and not candidates.has(neighbor_id):
			candidates.append(neighbor_id)
	if candidates.is_empty() and previous_node >= 0 and _array_contains_int(adjacent, previous_node):
		candidates.append(previous_node)
	candidates.sort()
	return candidates


func _graph_begin_movement(player_id: int, steps: int) -> void:
	var player: Dictionary = _player(player_id)
	var current_node: int = int(player.get("position", -1))
	var previous_node: int = int(player.get("previous_position", -1))
	var requested_steps: int = max(0, steps)
	var roll_total: int = int(state.get("last_total", 0))
	if requested_steps > MAX_GRAPH_STEPS or requested_steps > roll_total:
		state["route_options"] = []
		state["pending_movement"] = {}
		state["remaining_steps"] = 0
		state["phase"] = "await_roll"
		_record_event("movement_invalid", {"player_id": player_id, "steps": requested_steps, "last_total": roll_total})
		return
	state["bank_access"] = false
	state["bank_landing"] = false
	state["remaining_steps"] = requested_steps
	state["pending_movement"] = {
		"player_id": player_id,
		"current_node": current_node,
		"previous_node": previous_node,
	}
	state["route_options"] = []
	_graph_continue_movement(player_id)


func _graph_continue_movement(player_id: int) -> void:
	var player: Dictionary = _player(player_id)
	if player.is_empty():
		return
	var remaining: int = int(state.get("remaining_steps", 0))
	var roll_total: int = int(state.get("last_total", 0))
	if remaining < 0 or remaining > MAX_GRAPH_STEPS or remaining > roll_total:
		state["route_options"] = []
		state["pending_movement"] = {}
		state["remaining_steps"] = 0
		state["phase"] = "await_roll"
		_record_event("movement_invalid", {"player_id": player_id, "steps": remaining, "last_total": roll_total})
		return
	while int(state.get("remaining_steps", 0)) > 0:
		var current_node: int = int(player.get("position", -1))
		var previous_node: int = int(player.get("previous_position", -1))
		var candidates: Array = _graph_candidates(current_node, previous_node)
		if candidates.size() > 1:
			state["phase"] = "await_route"
			state["route_options"] = candidates
			state["pending_movement"] = {
				"player_id": player_id,
				"current_node": current_node,
				"previous_node": previous_node,
			}
			_set_action_options(player_id)
			return
		if candidates.is_empty():
			# A valid map can contain an isolated non-housing node. Preserve the
			# explicit stop instead of inventing a connection to another node.
			state["remaining_steps"] = 0
			_record_event("movement_blocked", {"player_id": player_id, "node": current_node})
			break
		var next_node: int = int(candidates[0])
		var old_node: int = current_node
		player["previous_position"] = old_node
		player["position"] = next_node
		state["remaining_steps"] = int(state.get("remaining_steps", 0)) - 1
		state["pending_movement"] = {
			"player_id": player_id,
			"current_node": next_node,
			"previous_node": old_node,
		}
		_record_event("move", {"player_id": player_id, "from": old_node, "to": next_node, "steps": 1})
		if int(state.get("remaining_steps", 0)) > 0:
			_graph_visit_tile(player_id, _tile_at(next_node), false)
			if not bool(player.get("alive", false)):
				state["remaining_steps"] = 0
				break
	state["route_options"] = []
	state["pending_movement"] = {}
	state["remaining_steps"] = 0
	state["phase"] = "await_roll"


func choose_route(route: int) -> Dictionary:
	if not _require_phase("await_route"):
		return _error("目前沒有待選路線")
	var player_id: int = int(state.get("current_player", -1))
	var pending: Dictionary = state.get("pending_movement", {})
	if pending.is_empty() or int(pending.get("player_id", -1)) != player_id:
		return _error("待選路線的玩家無效")
	var options: Array = state.get("route_options", [])
	if not _array_contains_int(options, route):
		return _error("選擇的路線無效")
	var remaining_steps: Variant = state.get("remaining_steps", null)
	var roll_total: Variant = state.get("last_total", null)
	if not _valid_int(remaining_steps, 1, MAX_GRAPH_STEPS) or not _valid_int(roll_total, 1, MAX_GRAPH_STEPS) or int(remaining_steps) > int(roll_total):
		return _error("待選路線步數無效")
	var player: Dictionary = _player(player_id)
	if player.is_empty() or int(player.get("position", -1)) != int(pending.get("current_node", -2)):
		return _error("待選路線與玩家位置不一致")
	var current_node: int = int(player.get("position", -1))
	var previous_node: int = int(player.get("previous_position", -1))
	var legal_options: Array = _graph_candidates(current_node, previous_node)
	if not _array_contains_int(legal_options, route):
		return _error("選擇的路線已失效")
	player["previous_position"] = current_node
	player["position"] = route
	state["remaining_steps"] = int(state.get("remaining_steps", 0)) - 1
	state["pending_movement"] = {
		"player_id": player_id,
		"current_node": route,
		"previous_node": current_node,
	}
	_record_event("route_chosen", {"player_id": player_id, "from": current_node, "to": route})
	if int(state.get("remaining_steps", 0)) > 0:
		_graph_visit_tile(player_id, _tile_at(route), false)
	_graph_continue_movement(player_id)
	if int(state.get("remaining_steps", 0)) == 0 and state.get("phase", "") != "game_over":
		_resolve_landing(player_id)
	return _result(true, "已選擇路線", {"route": route})


func _graph_visit_tile(player_id: int, tile: Dictionary, final_landing: bool) -> void:
	if tile.is_empty():
		return
	var tile_index: int = int(tile.get("index", -1))
	match str(tile.get("kind", "rest")):
		"property":
			if final_landing:
				var owner: int = int(tile.get("owner", -1))
				if owner >= 0 and owner != player_id:
					_charge_rent(player_id, owner, _calculate_rent(tile, owner))
		"tax":
			if final_landing:
				_charge_amount(player_id, int(tile.get("tax_amount", 0)), -1, "tax")
		"stock":
			if final_landing:
				_record_event("stock_landed", {"player_id": player_id, "tile": tile_index})
		"event":
			if final_landing:
				_draw_event_card(player_id)
		"points":
			var player: Dictionary = _player(player_id)
			var points: int = int(tile.get("points", 0))
			var current_points: int = clampi(int(player.get("points", 0)), 0, MAX_GRAPH_POINTS)
			var awarded_points: int = clampi(points, 0, MAX_GRAPH_POINTS - current_points)
			player["points"] = current_points + awarded_points
			_record_event("points_landed" if final_landing else "points_passed", {"player_id": player_id, "tile": tile_index, "points": awarded_points, "source_points": points})
		"card":
			if final_landing:
				_draw_event_card(player_id)
			else:
				_grant_random_card(player_id, "card_passed")
		"bank":
			if not _is_sunday():
				state["bank_access"] = true
				if final_landing:
					state["bank_landing"] = true
					_record_event("bank_landed", {"player_id": player_id, "tile": tile_index})
				else:
					_record_event("bank_passed", {"player_id": player_id, "tile": tile_index})
		"unsupported":
			_record_event("unsupported_landing" if final_landing else "unsupported_passed", {"player_id": player_id, "tile": tile_index, "name": tile.get("name", "")})


func _move_player(player_id: int, steps: int) -> void:
	var player: Dictionary = _player(player_id)
	var old_position: int = int(player.get("position", 0))
	var position: int = old_position
	var bank_access: bool = false
	var board: Array = state.get("board", [])
	for step in range(steps):
		position = (position + 1) % BOARD_SIZE
		var crossed: Dictionary = board[position]
		if crossed.get("kind", "") == "bank" and not _is_sunday():
			bank_access = true
			_record_event("bank_passed", {"player_id": player_id, "tile": position})
		if crossed.get("kind", "") == "event" and step < steps - 1:
			_grant_random_card(player_id, "card_passed")
	player["position"] = position
	state["bank_access"] = bank_access
	state["bank_landing"] = false
	_record_event("move", {"player_id": player_id, "from": old_position, "to": position, "steps": steps})


func _resolve_landing(player_id: int) -> void:
	var player: Dictionary = _player(player_id)
	var tile: Dictionary = _tile_at(int(player.get("position", 0)))
	if tile.is_empty():
		state["phase"] = "await_action"
		_set_action_options(player_id)
		return
	if _is_graph():
		_graph_visit_tile(player_id, tile, true)
		if bool(player.get("alive", false)) and state.get("phase", "") != "game_over":
			state["phase"] = "await_action"
			_set_action_options(player_id)
		_check_game_over()
		return
	match str(tile.get("kind", "rest")):
		"property":
			var owner: int = int(tile.get("owner", -1))
			if owner >= 0 and owner != player_id:
				_charge_rent(player_id, owner, _calculate_rent(tile, owner))
		"tax":
			_charge_amount(player_id, int(tile.get("tax_amount", 0)), -1, "tax")
		"event":
			_draw_event_card(player_id)
		"bank":
			if not _is_sunday():
				state["bank_access"] = true
				state["bank_landing"] = true
				_record_event("bank_landed", {"player_id": player_id, "tile": int(tile["index"])})
		"stock":
			_record_event("stock_landed", {"player_id": player_id, "tile": int(tile["index"])})
		_:
			_record_event("rest", {"player_id": player_id, "tile": int(tile["index"])})
	if bool(player.get("alive", false)) and state.get("phase", "") != "game_over":
		state["phase"] = "await_action"
		_set_action_options(player_id)
	_check_game_over()


func _calculate_rent(tile: Dictionary, owner_id: int) -> int:
	var group: String = str(tile.get("group", ""))
	var base: int = 0
	var board: Array = state.get("board", [])
	for candidate in board:
		if candidate.get("kind", "") == "property" and int(candidate.get("owner", -1)) == owner_id and str(candidate.get("group", "")) == group:
			base += int(candidate.get("rent", 0))
	# The reference describes same-owner same-road rent as combined. This is a
	# compact reconstruction until exact road segmentation is verified.
	return max(1, base)


func _charge_rent(debtor_id: int, creditor_id: int, amount: int) -> void:
	var debtor: Dictionary = _player(debtor_id)
	if int(debtor.get("rent_shield", 0)) > 0:
		debtor["rent_shield"] = int(debtor["rent_shield"]) - 1
		_record_event("rent_blocked", {"player_id": debtor_id, "creditor_id": creditor_id, "amount": amount})
		return
	_charge_amount(debtor_id, amount, creditor_id, "rent")


func _charge_amount(debtor_id: int, amount: int, creditor_id: int, reason: String) -> void:
	if amount <= 0:
		return
	var debtor: Dictionary = _player(debtor_id)
	if debtor.is_empty() or not bool(debtor.get("alive", false)):
		return
	# The manual's bankruptcy trigger is based on cash plus deposit. Deposits
	# are withdrawn to meet a charge; properties and shares go to auction only
	# after the player is declared bankrupt, never as a hidden rescue sale.
	var remaining: int = amount
	var cash_payment: int = min(remaining, int(debtor.get("cash", 0)))
	if cash_payment > 0:
		_pay_from_player(debtor_id, cash_payment, creditor_id)
		remaining -= cash_payment
	if remaining > 0 and int(debtor.get("deposit", 0)) > 0:
		var deposit_payment: int = min(remaining, int(debtor.get("deposit", 0)))
		_withdraw_internal(debtor_id, deposit_payment)
		_pay_from_player(debtor_id, deposit_payment, creditor_id)
		remaining -= deposit_payment
	if remaining > 0:
		_declare_bankruptcy(debtor_id, creditor_id, amount, reason)
		return
	_record_event("payment", {"player_id": debtor_id, "creditor_id": creditor_id, "amount": amount, "reason": reason})


func _pay_from_player(player_id: int, amount: int, creditor_id: int) -> void:
	if amount <= 0:
		return
	var player: Dictionary = _player(player_id)
	var paid: int = min(amount, int(player.get("cash", 0)))
	player["cash"] = int(player.get("cash", 0)) - paid
	if creditor_id >= 0 and _valid_player(creditor_id, true):
		var creditor: Dictionary = _player(creditor_id)
		creditor["cash"] = int(creditor.get("cash", 0)) + paid
	else:
		_bank_add_cash(paid)


func _declare_bankruptcy(debtor_id: int, creditor_id: int, debt: int, reason: String) -> void:
	var debtor: Dictionary = _player(debtor_id)
	if debtor.is_empty() or not bool(debtor.get("alive", false)):
		return
	var was_current_roll: bool = int(state.get("current_player", -1)) == debtor_id and state.get("phase", "") == "await_roll"
	var auction: Dictionary = _auction_assets(debtor_id, creditor_id)
	var loan: int = int(debtor.get("loan", 0))
	if loan > 0:
		var bank: Dictionary = state.get("bank", {})
		bank["loans"] = max(0, int(bank.get("loans", 0)) - loan)
		state["bank"] = bank
	debtor["cash"] = 0
	debtor["deposit"] = 0
	debtor["loan"] = 0
	debtor["loan_due_day"] = 0
	debtor["alive"] = false
	debtor["bankrupt"] = true
	var auctions: Array = state.get("bankruptcy_auctions", [])
	auctions.append(auction)
	state["bankruptcy_auctions"] = auctions
	_record_event("bankruptcy", {"player_id": debtor_id, "creditor_id": creditor_id, "debt": debt, "reason": reason, "auction_id": auction["auction_id"]})
	_check_game_over()
	# A landing charge happens while the phase is still await_roll. Advance
	# immediately so a non-final bankruptcy can never leave a dead player as the
	# current actor for a renderer or an AI scheduler. Loan-debt bankruptcy from
	# end_turn is advanced by that caller after its final bookkeeping instead.
	if was_current_roll and state.get("phase", "") != "game_over":
		_advance_to_next_alive(debtor_id)


func _auction_assets(debtor_id: int, creditor_id: int) -> Dictionary:
	var debtor: Dictionary = _player(debtor_id)
	var board: Array = state.get("board", [])
	var property_ids: Array = debtor.get("properties", []).duplicate()
	var stock_holdings: Dictionary = debtor.get("stocks", {}).duplicate(true)
	var auction_id: int = state.get("bankruptcy_auctions", []).size() + 1
	var transfer_to: int = creditor_id if _valid_player(creditor_id, true) else -1
	for property_id in property_ids:
		var tile: Dictionary = _tile_at(int(property_id))
		if tile.is_empty():
			continue
		if transfer_to >= 0:
			tile["owner"] = transfer_to
			var receiver: Dictionary = _player(transfer_to)
			var receiver_properties: Array = receiver.get("properties", [])
			if not receiver_properties.has(int(property_id)):
				receiver_properties.append(int(property_id))
			receiver["properties"] = receiver_properties
		else:
			tile["owner"] = -1
			tile["building_level"] = 0
			_update_tile_rent(tile)
		_record_event("auction_property", {"auction_id": auction_id, "property_id": int(property_id), "winner": transfer_to})
	debtor["properties"] = []
	debtor["stocks"] = {"tech": 0, "transport": 0, "energy": 0}
	if transfer_to >= 0:
		var receiver_stocks: Dictionary = _player(transfer_to).get("stocks", {})
		for symbol in STOCK_SYMBOLS:
			receiver_stocks[symbol] = int(receiver_stocks.get(symbol, 0)) + int(stock_holdings.get(symbol, 0))
		_player(transfer_to)["stocks"] = receiver_stocks
	# The reference resolves this as an auction. Until bidding is implemented,
	# the deterministic fallback releases assets to the bank.
	_recalculate_property_values()
	return {
		"auction_id": auction_id,
		"debtor": debtor_id,
		"creditor": creditor_id,
		"property_ids": property_ids,
		"stocks": stock_holdings,
		"provisional_resolution": "transfer_to_creditor_or_release_to_bank",
	}


func choose_action(action: String, params: Dictionary = {}) -> Dictionary:
	var normalized: String = action.to_lower().strip_edges()
	if normalized == "set_vehicle":
		return set_vehicle(str(params.get("vehicle", "walking")), int(params.get("dice_count", -1)))
	if normalized == "end_turn":
		return end_turn()
	if normalized == "buy_stock" or normalized == "sell_stock":
		return _trade_stock(normalized, params)
	if not _require_phase("await_action"):
		return _error("目前不是行動階段")
	var player_id: int = int(state.get("current_player", -1))
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return _error("目前玩家無法行動")
	if _is_sunday() and ["deposit", "withdraw", "take_loan", "buy_vehicle"].has(normalized):
		return _error("週日銀行休息")
	_set_action_options(player_id)
	var allowed_options: Array = state.get("action_options", [])
	if not allowed_options.has(normalized):
		return _error("目前位置不能執行此行動")
	match normalized:
		"buy":
			return _buy_property(player_id)
		"upgrade":
			return _upgrade_property(player_id)
		"deposit":
			return _deposit(player_id, int(params.get("amount", 0)))
		"withdraw":
			return _withdraw(player_id, int(params.get("amount", 0)))
		"take_loan":
			return _take_loan(player_id, int(params.get("amount", 0)))
		"buy_vehicle":
			return _buy_vehicle(player_id, str(params.get("vehicle", "")))
		"use_card":
			return _use_card(player_id, str(params.get("card_id", "")), int(params.get("target_id", player_id)), str(params.get("symbol", "")).to_lower())
		_:
			return _error("未知的行動")


func _buy_property(player_id: int) -> Dictionary:
	var player: Dictionary = _player(player_id)
	var tile: Dictionary = _tile_at(int(player.get("position", 0)))
	if bool(state.get("property_action_used", false)):
		return _error("本次造訪已完成土地行動")
	if tile.get("kind", "") != "property" or int(tile.get("owner", -1)) != -1:
		return _error("目前位置沒有可購買的土地")
	var price: int = int(tile.get("cost", 0))
	if int(player.get("cash", 0)) < price:
		return _error("現金不足")
	player["cash"] = int(player.get("cash", 0)) - price
	_bank_add_cash(price)
	tile["owner"] = player_id
	var properties: Array = player.get("properties", [])
	properties.append(int(tile["index"]))
	player["properties"] = properties
	state["property_action_used"] = true
	_recalculate_property_values()
	_record_event("property_bought", {"player_id": player_id, "property_id": int(tile["index"]), "price": price})
	_set_action_options(player_id)
	return _result(true, "已購買土地")


func _upgrade_property(player_id: int) -> Dictionary:
	var player: Dictionary = _player(player_id)
	var tile: Dictionary = _tile_at(int(player.get("position", 0)))
	if bool(state.get("property_action_used", false)):
		return _error("本次造訪已完成土地行動")
	if tile.get("kind", "") != "property" or int(tile.get("owner", -1)) != player_id:
		return _error("目前位置不是自己的土地")
	var level: int = int(tile.get("building_level", 0))
	if level >= MAX_PROPERTY_LEVEL:
		return _error("土地已達最高五級")
	var price: int = _upgrade_price(tile)
	if int(player.get("cash", 0)) < price:
		return _error("現金不足")
	player["cash"] = int(player.get("cash", 0)) - price
	_bank_add_cash(price)
	tile["building_level"] = level + 1
	_update_tile_rent(tile)
	state["property_action_used"] = true
	_recalculate_property_values()
	_record_event("property_upgraded", {"player_id": player_id, "property_id": int(tile["index"]), "level": int(tile["building_level"]), "price": price})
	_set_action_options(player_id)
	return _result(true, "已升級土地")


func _buy_vehicle(player_id: int, vehicle: String) -> Dictionary:
	var player: Dictionary = _player(player_id)
	if not VEHICLE_COSTS.has(vehicle) or vehicle == "walking":
		return _error("交通工具無效")
	var vehicles: Dictionary = player.get("vehicles", {})
	if bool(vehicles.get(vehicle, false)):
		return _error("已擁有這項交通工具")
	var price: int = int(VEHICLE_COSTS[vehicle])
	if int(player.get("cash", 0)) < price:
		return _error("現金不足")
	player["cash"] = int(player.get("cash", 0)) - price
	vehicles[vehicle] = true
	player["vehicles"] = vehicles
	_bank_add_cash(price)
	_record_event("vehicle_bought", {"player_id": player_id, "vehicle": vehicle, "price": price})
	_set_action_options(player_id)
	return _result(true, "已購買交通工具")


func _deposit(player_id: int, amount: int) -> Dictionary:
	var player: Dictionary = _player(player_id)
	if not bool(state.get("bank_access", false)):
		return _error("尚未經過銀行")
	if amount <= 0 or amount > int(player.get("cash", 0)):
		return _error("存款金額無效")
	player["cash"] = int(player.get("cash", 0)) - amount
	player["deposit"] = int(player.get("deposit", 0)) + amount
	var bank: Dictionary = state.get("bank", {})
	bank["cash"] = int(bank.get("cash", 0)) + amount
	bank["deposits"] = int(bank.get("deposits", 0)) + amount
	state["bank"] = bank
	_record_event("deposit", {"player_id": player_id, "amount": amount})
	_set_action_options(player_id)
	return _result(true, "已存款")


func _withdraw(player_id: int, amount: int) -> Dictionary:
	var player: Dictionary = _player(player_id)
	if not bool(state.get("bank_access", false)):
		return _error("尚未經過銀行")
	if amount <= 0 or amount > int(player.get("deposit", 0)):
		return _error("提款金額無效")
	if not _bank_can_pay(amount):
		return _error("銀行現金暫不足")
	_withdraw_internal(player_id, amount)
	_record_event("withdraw", {"player_id": player_id, "amount": amount})
	_set_action_options(player_id)
	return _result(true, "已提款")


func _withdraw_internal(player_id: int, amount: int) -> void:
	var player: Dictionary = _player(player_id)
	var actual: int = min(amount, int(player.get("deposit", 0)))
	if actual <= 0:
		return
	player["deposit"] = int(player.get("deposit", 0)) - actual
	player["cash"] = int(player.get("cash", 0)) + actual
	var bank: Dictionary = state.get("bank", {})
	bank["cash"] = int(bank.get("cash", 0)) - actual
	bank["deposits"] = max(0, int(bank.get("deposits", 0)) - actual)
	state["bank"] = bank


func _take_loan(player_id: int, amount: int) -> Dictionary:
	var player: Dictionary = _player(player_id)
	if not bool(state.get("bank_landing", false)):
		return _error("只有落在銀行時才能申請貸款")
	if amount <= 0 or amount > 10000:
		return _error("貸款金額必須介於 1 到 10000")
	if not _bank_can_pay(amount):
		return _error("銀行現金暫不足")
	player["cash"] = int(player.get("cash", 0)) + amount
	player["loan"] = int(player.get("loan", 0)) + amount
	player["loan_due_day"] = max(int(player.get("loan_due_day", 0)), int(state.get("day", 1)) + LOAN_TERM_DAYS)
	var bank: Dictionary = state.get("bank", {})
	bank["cash"] = int(bank.get("cash", 0)) - amount
	bank["loans"] = int(bank.get("loans", 0)) + amount
	state["bank"] = bank
	_record_event("loan_taken", {"player_id": player_id, "amount": amount, "due_day": int(player["loan_due_day"])})
	_set_action_options(player_id)
	return _result(true, "已取得三個月免息貸款")


func _trade_stock(action: String, params: Dictionary) -> Dictionary:
	if state.get("phase", "") == "game_over":
		return _error("遊戲已結束")
	if _is_sunday():
		return _error("週日證券市場休市")
	var player_id: int = int(state.get("current_player", -1))
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return _error("目前玩家無法交易")
	var symbol: String = str(params.get("symbol", params.get("stock", ""))).to_lower()
	var quantity: int = int(params.get("quantity", params.get("shares", 0)))
	if not STOCK_SYMBOLS.has(symbol) or quantity <= 0:
		return _error("股票代號或數量無效")
	var market: Dictionary = state.get("market", {})
	var prices: Dictionary = market.get("prices", {})
	var price: int = int(prices.get(symbol, 0))
	var shares: Dictionary = player.get("stocks", {})
	if action == "buy_stock":
		var cost: int = price * quantity
		if int(player.get("cash", 0)) < cost:
			return _error("現金不足")
		player["cash"] = int(player.get("cash", 0)) - cost
		shares[symbol] = int(shares.get(symbol, 0)) + quantity
		_bank_add_cash(cost)
		_record_event("stock_bought", {"player_id": player_id, "symbol": symbol, "quantity": quantity, "price": price})
	else:
		if int(shares.get(symbol, 0)) < quantity:
			return _error("持股不足")
		var proceeds: int = price * quantity
		if not _bank_can_pay(proceeds):
			return _error("銀行現金暫不足")
		shares[symbol] = int(shares.get(symbol, 0)) - quantity
		player["cash"] = int(player.get("cash", 0)) + proceeds
		_bank_subtract_cash(proceeds)
		_record_event("stock_sold", {"player_id": player_id, "symbol": symbol, "quantity": quantity, "price": price})
	player["stocks"] = shares
	return _result(true, "股票交易完成")


func _use_card(player_id: int, card_id: String, target_id: int = -1, symbol: String = "") -> Dictionary:
	var player: Dictionary = _player(player_id)
	var cards: Array = player.get("cards", [])
	if card_id.is_empty():
		return _error("卡片代號無效")
	var index: int = cards.find(card_id)
	if index < 0 or index >= cards.size():
		return _error("沒有這張卡片")
	if target_id < 0:
		target_id = player_id
	if card_id == "停留" or card_id == "烏龜":
		var target_check: Dictionary = _player(target_id)
		if target_check.is_empty() or not bool(target_check.get("alive", false)):
			return _error("卡片目標無效")
	if card_id == "紅" or card_id == "黑":
		if not STOCK_SYMBOLS.has(symbol):
			return _error("紅／黑卡需要指定股票代號")
	cards.remove_at(index)
	player["cards"] = cards
	if card_id == "均富":
		var alive_players: Array = []
		var total_cash: int = 0
		for candidate in _players():
			if bool(candidate.get("alive", false)):
				alive_players.append(candidate)
				total_cash += int(candidate.get("cash", 0))
		if alive_players.size() > 0:
			var share: int = int(total_cash / alive_players.size())
			var remainder: int = total_cash - share * alive_players.size()
			for candidate in alive_players:
				candidate["cash"] = share
			if remainder > 0:
				player["cash"] = int(player.get("cash", 0)) + remainder
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "effect": "equalize_cash"})
	elif card_id == "停留":
		# The target is intentionally supplied through the action's target_id.
		var target: Dictionary = _player(target_id)
		target["stay_next"] = max(1, int(target.get("stay_next", 0)))
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "target_id": target_id, "effect": "stay"})
	elif card_id == "烏龜":
		var turtle_target: Dictionary = _player(target_id)
		turtle_target["turtle_days"] = max(3, int(turtle_target.get("turtle_days", 0)))
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "target_id": target_id, "effect": "turtle"})
	elif card_id == "紅" or card_id == "黑":
		var market: Dictionary = state.get("market", {})
		var trends: Dictionary = market.get("trends", {})
		trends[symbol] = {"direction": "up" if card_id == "紅" else "down", "days": 3, "rate": 0.10}
		market["trends"] = trends
		state["market"] = market
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "symbol": symbol, "effect": "stock_up" if card_id == "紅" else "stock_down", "days": 3})
	else:
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "effect": "provisional_unknown"})
	_set_action_options(player_id)
	return _result(true, "已使用卡片")


func _draw_event_card(player_id: int) -> void:
	var card: Dictionary = EVENT_CARDS[_rng.randi_range(0, EVENT_CARDS.size() - 1)].duplicate(true)
	_record_event("event_drawn", {"player_id": player_id, "card_id": card["id"], "name": card["name"]})
	match str(card.get("kind", "")):
		"card":
			_grant_card(player_id, str(card["id"]))
		"fee":
			_charge_amount(player_id, int(card["amount"]), -1, "event")
		"move":
			_move_player(player_id, int(card["amount"]))
			if bool(_player(player_id).get("alive", false)):
				_resolve_landing(player_id)
		"deposit":
			var player: Dictionary = _player(player_id)
			player["deposit"] = int(player.get("deposit", 0)) + int(card["amount"])
			var bank: Dictionary = state.get("bank", {})
			bank["deposits"] = int(bank.get("deposits", 0)) + int(card["amount"])
			state["bank"] = bank
			_record_event("event_deposit", {"player_id": player_id, "amount": int(card["amount"])})


func _grant_random_card(player_id: int, reason: String) -> void:
	var card: Dictionary = EVENT_CARDS[_rng.randi_range(0, EVENT_CARDS.size() - 1)]
	if str(card.get("kind", "")) != "card":
		card = EVENT_CARDS[0]
	_grant_card(player_id, str(card["id"]))
	_record_event(reason, {"player_id": player_id, "card_id": str(card["id"])})


func _grant_card(player_id: int, card_id: String) -> void:
	var player: Dictionary = _player(player_id)
	var cards: Array = player.get("cards", [])
	if cards.size() >= 15:
		_record_event("card_limit", {"player_id": player_id, "card_id": card_id, "limit": 15})
		return
	cards.append(card_id)
	player["cards"] = cards


func end_turn() -> Dictionary:
	if not _require_phase("await_action"):
		return _error("目前不是結束回合階段")
	var player_id: int = int(state.get("current_player", -1))
	var player: Dictionary = _player(player_id)
	if bool(player.get("alive", false)):
		player["turns_taken"] = int(player.get("turns_taken", 0)) + 1
		_repay_due_loan(player_id)
		_tick_market()
	state["bank_access"] = false
	state["bank_landing"] = false
	state["doubles_count"] = 0
	state["property_action_used"] = false
	_advance_to_next_alive(player_id)
	return _result(true, "回合結束")


func _advance_to_next_alive(previous_id: int) -> void:
	_check_game_over()
	if state.get("phase", "") == "game_over":
		return
	var players: Array = _players()
	var next_id: int = -1
	for offset in range(1, players.size() + 1):
		var candidate: int = (previous_id + offset) % players.size()
		if bool(players[candidate].get("alive", false)):
			next_id = candidate
			break
	if next_id < 0:
		_check_game_over()
		return
	var wraps: bool = next_id <= previous_id
	if wraps:
		state["round"] = int(state.get("round", 1)) + 1
		state["day"] = int(state.get("day", 1)) + 1
		var market: Dictionary = state.get("market", {})
		var trends: Dictionary = market.get("trends", {})
		for symbol in trends.keys():
			var trend: Dictionary = trends[symbol]
			trend["days"] = int(trend.get("days", 0)) - 1
			if int(trend["days"]) <= 0:
				trends.erase(symbol)
			else:
				trends[symbol] = trend
		market["trends"] = trends
		state["market"] = market
		_apply_month_boundary()
	state["turn"] = int(state.get("turn", 1)) + 1
	state["current_player"] = next_id
	state["phase"] = "await_roll"
	state["last_roll"] = []
	state["last_total"] = 0
	_set_action_options(next_id)
	_record_event("turn_started", {"player_id": next_id, "day": int(state["day"])})


func _apply_month_boundary() -> void:
	_sync_state()
	if int(state.get("day_of_month", 1)) != DAYS_PER_MONTH:
		return
	var players: Array = _players()
	for player in players:
		if not bool(player.get("alive", false)) or int(player.get("loan", 0)) > 0:
			continue
		var deposit: int = int(player.get("deposit", 0))
		if deposit <= 0:
			continue
		var interest: int = int(floor(float(deposit) * MONTHLY_DEPOSIT_RATE))
		if interest <= 0:
			continue
		player["deposit"] = deposit + interest
		var bank: Dictionary = state.get("bank", {})
		bank["deposits"] = int(bank.get("deposits", 0)) + interest
		bank["cash"] = int(bank.get("cash", 0)) - interest
		state["bank"] = bank
		_record_event("monthly_interest", {"player_id": int(player["id"]), "amount": interest})
	_record_event("month_end_settlement", {"month": int(state.get("month", 1))})


func _repay_due_loan(player_id: int) -> void:
	var player: Dictionary = _player(player_id)
	var loan: int = int(player.get("loan", 0))
	if loan <= 0 or int(state.get("day", 1)) < int(player.get("loan_due_day", 0)):
		return
	var available: int = int(player.get("cash", 0)) + int(player.get("deposit", 0))
	if available < loan:
		var deposit_payment: int = int(player.get("deposit", 0))
		if deposit_payment > 0:
			_withdraw_internal(player_id, deposit_payment)
		var cash_payment: int = int(player.get("cash", 0))
		if cash_payment > 0:
			_pay_from_player(player_id, cash_payment, -1)
		var remaining_loan: int = max(0, loan - cash_payment)
		player["loan"] = remaining_loan
		var bank: Dictionary = state.get("bank", {})
		bank["loans"] = max(0, int(bank.get("loans", 0)) - cash_payment)
		state["bank"] = bank
		_declare_bankruptcy(player_id, -1, remaining_loan, "loan_due")
		return
	if int(player.get("cash", 0)) < loan:
		_withdraw_internal(player_id, loan - int(player.get("cash", 0)))
	player["cash"] = int(player.get("cash", 0)) - loan
	player["loan"] = 0
	player["loan_due_day"] = 0
	var bank: Dictionary = state.get("bank", {})
	bank["cash"] = int(bank.get("cash", 0)) + loan
	bank["loans"] = max(0, int(bank.get("loans", 0)) - loan)
	state["bank"] = bank
	_record_event("loan_repaid", {"player_id": player_id, "amount": loan})


func _tick_market() -> void:
	if _is_sunday():
		return
	var market: Dictionary = state.get("market", {})
	var prices: Dictionary = market.get("prices", {})
	var trends: Dictionary = market.get("trends", {})
	for symbol in STOCK_SYMBOLS:
		var old_price: int = int(prices.get(symbol, STOCK_BASE_PRICES[symbol]))
		var delta: int = _rng.randi_range(-10, 10)
		var trend: Dictionary = trends.get(symbol, {})
		if int(trend.get("days", 0)) > 0:
			delta += 10 if str(trend.get("direction", "")) == "up" else -10
		prices[symbol] = max(10, int(round(float(old_price) * (100.0 + float(delta)) / 100.0)))
	market["prices"] = prices
	state["market"] = market
	_record_event("market_tick", {"prices": prices.duplicate(true)})


func _update_tile_rent(tile: Dictionary) -> void:
	if _is_graph() and tile.has("rent_by_level") and tile.get("rent_by_level") is Array:
		var rents: Array = tile.get("rent_by_level", [])
		var graph_level: int = clampi(int(tile.get("building_level", 0)), 0, max(0, rents.size() - 1))
		if not rents.is_empty():
			tile["rent"] = int(rents[graph_level])
			return
	var base: int = int(tile.get("base_rent", 0))
	var level: int = int(tile.get("building_level", 0))
	tile["rent"] = base * (1 + level * 2)


func _recalculate_property_values() -> void:
	var board: Array = state.get("board", [])
	for player in _players():
		var total: int = 0
		for property_id in player.get("properties", []):
			var tile: Dictionary = board[int(property_id)]
			total += int(tile.get("cost", 0)) + int(tile.get("upgrade_cost", 0)) * int(tile.get("building_level", 0))
		player["property_values"] = total


func _bank_can_pay(amount: int) -> bool:
	return int(state.get("bank", {}).get("cash", 0)) >= amount


func _bank_add_cash(amount: int) -> void:
	var bank: Dictionary = state.get("bank", {})
	bank["cash"] = int(bank.get("cash", 0)) + max(0, amount)
	state["bank"] = bank


func _bank_subtract_cash(amount: int) -> void:
	var bank: Dictionary = state.get("bank", {})
	bank["cash"] = max(0, int(bank.get("cash", 0)) - max(0, amount))
	state["bank"] = bank


func _check_game_over() -> void:
	if state.get("phase", "") == "game_over":
		return
	var alive_ids: Array = []
	for player in _players():
		if bool(player.get("alive", false)):
			alive_ids.append(int(player.get("id", -1)))
	if alive_ids.size() <= 1:
		state["winner"] = alive_ids[0] if alive_ids.size() == 1 else -1
		state["phase"] = "game_over"
		state["action_options"] = []
		_record_event("game_over", {"winner": int(state["winner"])})


func run_ai_turn() -> Dictionary:
	if state.get("phase", "") == "game_over":
		return _error("遊戲已結束")
	var player_id: int = int(state.get("current_player", -1))
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		if not player.is_empty():
			_advance_to_next_alive(player_id)
			if state.get("phase", "") == "game_over":
				return _result(true, "AI 對局完成")
			player_id = int(state.get("current_player", -1))
			player = _player(player_id)
		if player.is_empty() or not bool(player.get("alive", false)):
			return _error("目前玩家無法行動")
	if not bool(player.get("is_ai", false)):
		return _error("目前玩家不是 AI")
	var safety: int = 0
	var route_safety: int = 0
	while state.get("phase", "") != "game_over" and int(state.get("current_player", -1)) == player_id:
		if state.get("phase", "") == "await_route":
			if route_safety >= MAX_GRAPH_STEPS:
				return _result(false, "AI 路線在限制內未完成", {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": false})
			var options: Array = state.get("route_options", [])
			if options.is_empty():
				return _result(false, "AI 找不到可用路線", {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": false})
			var route_result: Dictionary = choose_route(int(options[0]))
			route_safety += 1
			if not bool(route_result.get("ok", false)):
				return _result(false, str(route_result.get("message", "AI 選路失敗")), {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": false})
			continue
		if safety >= MAX_AI_TURN_ITERATIONS:
			break
		safety += 1
		if state.get("phase", "") == "await_roll":
			var roll_result: Dictionary = roll()
			if not bool(roll_result.get("ok", false)):
				return _result(false, str(roll_result.get("message", "AI 擲骰失敗")), {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": false})
		elif state.get("phase", "") == "await_action":
			if not bool(_player(player_id).get("alive", false)):
				_advance_to_next_alive(player_id)
				break
			_ai_action(player_id)
		else:
			break
	if state.get("phase", "") == "await_action" and int(state.get("current_player", -1)) == player_id:
		var end_result: Dictionary = end_turn()
		if not bool(end_result.get("ok", false)):
			return _result(false, str(end_result.get("message", "AI 結束回合失敗")), {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": false})
	var completed: bool = state.get("phase", "") == "game_over" or int(state.get("current_player", -1)) != player_id
	if not completed:
		return _result(false, "AI 回合在限制內未完成", {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": false})
	return _result(true, "AI 回合完成", {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": true})


func _ai_action(player_id: int) -> void:
	var player: Dictionary = _player(player_id)
	var tile: Dictionary = _tile_at(int(player.get("position", 0)))
	if tile.get("kind", "") == "property":
		var owner: int = int(tile.get("owner", -1))
		if owner == -1 and not bool(state.get("property_action_used", false)) and int(player.get("cash", 0)) >= int(tile.get("cost", 0)):
			choose_action("buy")
			return
		if owner == player_id and not bool(state.get("property_action_used", false)) and int(tile.get("building_level", 0)) < MAX_PROPERTY_LEVEL and int(player.get("cash", 0)) >= _upgrade_price(tile) + 500:
			choose_action("upgrade")
			return
	if bool(state.get("bank_access", false)) and not _is_sunday() and int(player.get("cash", 0)) > 5000:
		choose_action("deposit", {"amount": int(player.get("cash", 0)) / 4})
		return
	if not _is_sunday() and int(player.get("cash", 0)) >= 3000:
		var prices: Dictionary = state.get("market", {}).get("prices", {})
		var symbol: String = STOCK_SYMBOLS[player_id % STOCK_SYMBOLS.size()]
		var price: int = int(prices.get(symbol, 100))
		if price > 0:
			choose_action("buy_stock", {"symbol": symbol, "quantity": 1})
			return
	if player.get("cards", []).size() > 0:
		var card_id: String = str(player["cards"][0])
		var card_params: Dictionary = {"card_id": card_id}
		if card_id == "停留" or card_id == "烏龜":
			card_params["target_id"] = player_id
		elif card_id == "紅" or card_id == "黑":
			card_params["symbol"] = STOCK_SYMBOLS[player_id % STOCK_SYMBOLS.size()]
		choose_action("use_card", card_params)
		return
	end_turn()


func run_ai_match(max_turns: int = 10000) -> Dictionary:
	if max_turns < 1:
		return _error("最大回合數無效")
	for player in _players():
		if bool(player.get("alive", false)):
			player["is_ai"] = true
			player["is_human"] = false
	var completed: int = 0
	while state.get("phase", "") != "game_over" and completed < max_turns:
		var result: Dictionary = run_ai_turn()
		if not bool(result.get("ok", false)):
			return _result(false, str(result.get("message", "AI 失敗")), {"completed_turns": completed})
		completed += 1
	if state.get("phase", "") != "game_over":
		return _result(false, "AI 對局在限制內未結束", {"completed_turns": completed})
	return _result(true, "AI 對局完成", {"completed_turns": completed, "winner": int(state.get("winner", -1))})


static func _valid_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func _validate_graph_source(source: Variant, expected_id: String = "") -> Array:
	var errors: Array = []
	if typeof(source) != TYPE_DICTIONARY:
		return ["missing map source"]
	var edition: Variant = source.get("edition", null)
	var map_number: Variant = source.get("map_number", null)
	if typeof(edition) != TYPE_STRING or not ["Game", "MultiverseJourney"].has(edition):
		errors.append("invalid map source edition")
	if not _valid_int(map_number, 1, 99):
		errors.append("invalid map source number")
	if typeof(edition) == TYPE_STRING and _valid_int(map_number, 1, 99):
		var canonical_id := "%s:%d" % [edition, int(map_number)]
		if not expected_id.is_empty() and expected_id != canonical_id:
			errors.append("map identity mismatch")
	var archive: Variant = source.get("archive", null)
	if typeof(archive) != TYPE_STRING or (typeof(edition) == TYPE_STRING and archive != "%s/map.mkf" % edition):
		errors.append("invalid map source archive")
	if not _valid_int(source.get("entry_index", null), 0, 999):
		errors.append("invalid map source entry")
	for hash_key in ["payload_sha256", "source_file_sha256"]:
		if not _valid_sha256(source.get(hash_key, null)):
			errors.append("invalid map source hash")
	return errors


static func validate_board_definition(definition: Dictionary) -> Dictionary:
	var errors: Array = []
	if typeof(definition) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["map definition must be a dictionary"]}
	if definition.get("schema", "") != RUNTIME_MAP_SCHEMA:
		errors.append("unsupported map schema")
	if not _valid_int(definition.get("version", null), 1, 1):
		errors.append("unsupported map version")
	var map_id: Variant = definition.get("id", null)
	if typeof(map_id) != TYPE_STRING or str(map_id).is_empty():
		errors.append("invalid map id")
	var map_name: Variant = definition.get("name", null)
	if typeof(map_name) != TYPE_STRING or str(map_name).is_empty():
		errors.append("invalid map name")
	var source_errors: Array = _validate_graph_source(definition.get("source", null), str(map_id) if typeof(map_id) == TYPE_STRING else "")
	errors.append_array(source_errors)
	if typeof(definition.get("supports_new_game", null)) != TYPE_BOOL or not bool(definition.get("supports_new_game", false)):
		errors.append("map does not support new games")
	var board: Variant = definition.get("board", null)
	if typeof(board) != TYPE_ARRAY or board.size() < 2 or board.size() > 4096:
		errors.append("invalid graph board")
	var board_array: Array = board if typeof(board) == TYPE_ARRAY else []
	var property_count := 0
	var source_properties: Dictionary = {}
	for index in range(board_array.size()):
		var tile_value: Variant = board_array[index]
		if typeof(tile_value) != TYPE_DICTIONARY:
			errors.append("invalid graph tile %d" % index)
			continue
		var tile: Dictionary = tile_value
		if not _valid_int(tile.get("index", null), index, index):
			errors.append("graph tile index mismatch %d" % index)
		if not _valid_int(tile.get("source_node_id", null), index + 1, index + 1):
			errors.append("graph source node mismatch %d" % index)
		for coordinate in ["x", "y"]:
			if not _valid_int(tile.get(coordinate, null), -1000000, 1000000):
				errors.append("invalid graph tile coordinate %d" % index)
		var kind: Variant = tile.get("kind", null)
		if _valid_int(tile.get("type_and_idx", null), 2001, 3999) and (typeof(kind) != TYPE_STRING or kind != "property"):
			errors.append("housing source must remain a property %d" % index)
		var graph_kinds: Array = ["start", "rest", "property", "points", "card", "bank", "unsupported", "stock", "tax", "event"]
		if typeof(kind) != TYPE_STRING or not graph_kinds.has(kind):
			errors.append("invalid graph tile kind %d" % index)
		if not tile.get("adjacent") is Array or tile.adjacent.size() > 4:
			errors.append("invalid graph adjacency %d" % index)
		else:
			var adjacent: Array = []
			for neighbor in tile.adjacent:
				if not _valid_int(neighbor, 0, max(0, board_array.size() - 1)) or int(neighbor) == index or adjacent.has(int(neighbor)):
					errors.append("invalid graph edge %d" % index)
				else:
					adjacent.append(int(neighbor))
					var reverse_tile: Variant = board_array[int(neighbor)]
					var reverse_has := false
					if typeof(reverse_tile) == TYPE_DICTIONARY:
						var reverse_edges: Variant = reverse_tile.get("adjacent", null)
						if typeof(reverse_edges) == TYPE_ARRAY:
							for reverse_neighbor in reverse_edges:
								if _valid_int(reverse_neighbor) and int(reverse_neighbor) == index:
									reverse_has = true
									break
					if not reverse_has:
						errors.append("asymmetric graph edge %d" % index)
		for text_key in ["name", "group"]:
			if not _valid_string(tile.get(text_key, null)):
				errors.append("invalid graph tile text %d" % index)
		if not _valid_int(tile.get("owner", null), -1, -1):
			errors.append("graph definition has owned tile %d" % index)
		if not _valid_int(tile.get("building_level", null), 0, 0):
			errors.append("graph definition must start at level zero %d" % index)
		for numeric_key in ["building_level", "cost", "upgrade_cost", "base_rent", "rent", "tax_amount"]:
			if not _valid_int(tile.get(numeric_key, null), 0, 1000000000):
				errors.append("invalid graph tile value %d" % index)
		if typeof(kind) == TYPE_STRING and kind == "property":
			property_count += 1
			var source_object_id: Variant = tile.get("source_object_id", null)
			if not _valid_int(source_object_id, 1, 1999):
				errors.append("invalid graph property identity %d" % index)
			elif source_properties.has(int(source_object_id)):
				errors.append("duplicate graph property identity %d" % index)
			else:
				source_properties[int(source_object_id)] = true
			var land_price: Variant = tile.get("land_price", null)
			var house_price: Variant = tile.get("house_price", null)
			if not _valid_int(land_price, 0, 1000000) or not _valid_int(house_price, 0, 1000000):
				errors.append("invalid graph property prices %d" % index)
			var property_type: Variant = tile.get("type_and_idx", null)
			if not _valid_int(property_type, 2001, 3999):
				errors.append("invalid graph property source type %d" % index)
			elif _valid_int(source_object_id, 1, 1999) and int(property_type) - 2000 != int(source_object_id):
				errors.append("graph property source mismatch %d" % index)
			if _valid_int(land_price, 0, 1000000) and _valid_int(tile.get("cost", null), 0, 1000000000) and int(tile.cost) != int(land_price):
				errors.append("graph property cost mismatch %d" % index)
			if _valid_int(house_price, 0, 1000000) and _valid_int(tile.get("upgrade_cost", null), 0, 1000000000) and int(tile.upgrade_cost) != int(house_price):
				errors.append("graph property upgrade price mismatch %d" % index)
			var rents: Variant = tile.get("rent_by_level", null)
			if typeof(rents) != TYPE_ARRAY or rents.size() != 6:
				errors.append("invalid graph rent table %d" % index)
			else:
				for rent in rents:
					if not _valid_int(rent, 0, 1000000):
						errors.append("invalid graph rent value %d" % index)
				var base_rent: Variant = tile.get("base_rent", null)
				var rent: Variant = tile.get("rent", null)
				if _valid_int(base_rent, 0, 1000000000) and _valid_int(rents[0], 0, 1000000) and int(base_rent) != int(rents[0]):
					errors.append("graph base rent mismatch %d" % index)
				if _valid_int(rent, 0, 1000000000) and _valid_int(rents[0], 0, 1000000) and int(rent) != int(rents[0]):
					errors.append("graph rent mismatch %d" % index)
		else:
			var owner: Variant = tile.get("owner", null)
			var building_level: Variant = tile.get("building_level", null)
			if _valid_int(owner, -1, -1) and _valid_int(building_level, 0, MAX_PROPERTY_LEVEL) and (int(owner) != -1 or int(building_level) != 0):
				errors.append("non-property graph tile state %d" % index)
		var type_value: Variant = tile.get("type_and_idx", null)
		var event_value: Variant = tile.get("event_code", null)
		if not _valid_int(type_value, 0, 65535) or not _valid_int(event_value, 0, 255):
			errors.append("invalid graph source tile status %d" % index)
		else:
			_validate_graph_source_classification(tile, index, errors)
	var start_position: Variant = definition.get("start_position", null)
	if not _valid_int(start_position, 0, max(0, board_array.size() - 1)):
		errors.append("invalid graph start position")
	else:
		var start_tile: Dictionary = board_array[int(start_position)] if int(start_position) < board_array.size() and typeof(board_array[int(start_position)]) == TYPE_DICTIONARY else {}
		if start_tile.is_empty() or not start_tile.get("adjacent", []) is Array or start_tile.adjacent.is_empty():
			errors.append("graph start is not movable")
	if property_count <= 0:
		errors.append("graph map has no playable housing")
	if errors.is_empty():
		var visited: Dictionary = {int(start_position): true}
		var queue: Array = [int(start_position)]
		while not queue.is_empty():
			var node: int = int(queue.pop_front())
			for neighbor in board_array[node].adjacent:
				var next: int = int(neighbor)
				if not visited.has(next):
					visited[next] = true
					queue.append(next)
		for index in range(board_array.size()):
			if board_array[index].get("kind", "") == "property" and not visited.has(index):
				errors.append("housing is unreachable from graph start")
	return {"ok": errors.is_empty(), "errors": errors, "definition": definition.duplicate(true)}


static func _valid_int(value: Variant, minimum: int = INT64_MIN, maximum: int = INT64_MAX) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= minimum and value <= maximum
	if typeof(value) == TYPE_FLOAT:
		var real: float = value
		return is_finite(real) and floor(real) == real and real >= float(minimum) and real <= float(maximum)
	return false


static func _valid_bool(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL


static func _valid_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING


static func _validate_graph_source_classification(tile: Dictionary, index: int, errors: Array) -> void:
	var type_value: Variant = tile.get("type_and_idx", null)
	var event_value: Variant = tile.get("event_code", null)
	if not _valid_int(type_value, 0, 65535) or not _valid_int(event_value, 0, 255):
		return
	var classification: Dictionary = OriginalMaps.classify_source_node(type_value, event_value)
	if not bool(classification.get("ok", false)):
		return
	var kind: Variant = tile.get("kind", null)
	var canonical_kind: String = str(classification.get("kind", ""))
	if typeof(kind) != TYPE_STRING or str(kind) != canonical_kind:
		errors.append("graph tile kind does not match source %d" % index)
	if canonical_kind == "points":
		var expected_points: int = int(classification.get("points", 0))
		if not _valid_int(tile.get("points", null), expected_points, expected_points):
			errors.append("invalid graph points value %d" % index)
	elif tile.has("points"):
		errors.append("non-points graph tile has points %d" % index)


static func validate_save(data: Dictionary) -> Dictionary:
	var errors: Array = []
	var board_mode_marker: Variant = data.get("board_mode", "")
	var version_marker: Variant = data.get("version", null)
	var graph_save: bool = (typeof(board_mode_marker) == TYPE_STRING and board_mode_marker == GRAPH_BOARD_MODE) or (_valid_int(version_marker) and int(version_marker) == GRAPH_SAVE_VERSION)
	var required_top: Array = [
		"version", "ruleset", "seed", "seed_text", "rng_state", "rng_state_text",
		"phase", "turn", "round", "day", "month", "day_of_month", "weekday",
		"current_player", "winner", "last_roll", "last_total", "last_event",
		"event_log", "action_options", "extra_roll", "doubles_count",
		"property_action_used", "bank_access", "bank_landing", "bank", "market",
		"board", "players", "bankruptcy_auctions",
	]
	if graph_save:
		required_top.append_array(["board_mode", "map_id", "map_name", "map_schema", "map_version", "map_source", "start_position", "route_options", "remaining_steps", "pending_movement"])
	for key in required_top:
		if not data.has(key):
			errors.append("missing %s" % key)

	var expected_save_version: int = GRAPH_SAVE_VERSION if graph_save else SAVE_VERSION
	if not _valid_int(data.get("version", null), expected_save_version, expected_save_version):
		errors.append("unsupported save version")
	if not _valid_string(data.get("ruleset", null)) or data.get("ruleset", "") != RULESET_ID:
		errors.append("unsupported ruleset")
	var seed_value: Variant = data.get("seed", null)
	var seed_valid: bool = _valid_int(seed_value, MIN_SEED, MAX_SEED)
	if not seed_valid:
		errors.append("invalid seed")
	var seed_text: Variant = data.get("seed_text", null)
	var seed_text_valid: bool = false
	if typeof(seed_text) == TYPE_STRING and seed_text.is_valid_int():
		var parsed_seed: int = int(seed_text)
		seed_text_valid = seed_valid and parsed_seed >= MIN_SEED and parsed_seed <= MAX_SEED and str(parsed_seed) == seed_text and parsed_seed == int(seed_value)
	if not seed_text_valid:
		errors.append("invalid seed text")
	var rng_value: Variant = data.get("rng_state", null)
	if typeof(rng_value) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("missing rng state")
	var rng_text: Variant = data.get("rng_state_text", null)
	if typeof(rng_text) != TYPE_STRING or not rng_text.is_valid_int():
		errors.append("invalid rng state")
	else:
		var parsed_rng: int = int(rng_text)
		if parsed_rng < INT64_MIN or parsed_rng > INT64_MAX or str(parsed_rng) != rng_text:
			errors.append("invalid rng state")

	var phase: Variant = data.get("phase", null)
	var allowed_phases: Array = ["await_roll", "await_action", "game_over"]
	if graph_save:
		allowed_phases.append("await_route")
	if typeof(phase) != TYPE_STRING or not allowed_phases.has(phase):
		errors.append("invalid phase")
	var phase_name: String = phase if typeof(phase) == TYPE_STRING else ""
	for key in ["turn", "round", "day", "month"]:
		if not _valid_int(data.get(key, null), 1, 1000000000):
			errors.append("invalid %s" % key)
	if not _valid_int(data.get("day_of_month", null), 1, DAYS_PER_MONTH):
		errors.append("invalid day_of_month")
	if not _valid_int(data.get("weekday", null), 1, 7):
		errors.append("invalid weekday")
	var day_value: Variant = data.get("day", null)
	var day_of_month_value: Variant = data.get("day_of_month", null)
	var month_value: Variant = data.get("month", null)
	var weekday_value: Variant = data.get("weekday", null)
	if _valid_int(day_value, 1, 1000000000):
		var day_int: int = day_value
		if not _valid_int(day_of_month_value, 1, DAYS_PER_MONTH) or int(day_of_month_value) != ((day_int - 1) % DAYS_PER_MONTH) + 1:
			errors.append("day_of_month mismatch")
		if not _valid_int(month_value, 1, 1000000000) or int(month_value) != ((day_int - 1) / DAYS_PER_MONTH) + 1:
			errors.append("month mismatch")
		if not _valid_int(weekday_value, 1, 7) or int(weekday_value) != ((day_int - 1) % 7) + 1:
			errors.append("weekday mismatch")

	var players: Variant = data.get("players", null)
	var player_count: int = players.size() if typeof(players) == TYPE_ARRAY else 0
	if typeof(players) != TYPE_ARRAY or player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		errors.append("invalid player count")
	var board: Variant = data.get("board", null)
	var board_valid: bool = typeof(board) == TYPE_ARRAY
	if board_valid:
		if graph_save:
			board_valid = board.size() >= 2 and board.size() <= 4096
		else:
			board_valid = board.size() == BOARD_SIZE
	if not board_valid:
		errors.append("invalid board")
	var current_value: Variant = data.get("current_player", null)
	if not _valid_int(current_value, 0, max(0, player_count - 1)):
		errors.append("invalid current player")
	var current_player: int = current_value if _valid_int(current_value) else -1
	var winner_value: Variant = data.get("winner", null)
	if not _valid_int(winner_value, -1, max(-1, player_count - 1)):
		errors.append("invalid winner")
	var winner: int = winner_value if _valid_int(winner_value) else -1

	for key in ["extra_roll", "property_action_used", "bank_access", "bank_landing"]:
		if not _valid_bool(data.get(key, null)):
			errors.append("invalid %s" % key)
	var doubles_count_value: Variant = data.get("doubles_count", null)
	var doubles_count_valid: bool = _valid_int(doubles_count_value, 0, 3)
	if not doubles_count_valid:
		errors.append("invalid doubles_count")
	var extra_roll_value: Variant = data.get("extra_roll", null)
	if (_valid_bool(extra_roll_value) and bool(extra_roll_value)) or (doubles_count_valid and int(doubles_count_value) != 0):
		errors.append("unsupported doubles state")

	var last_roll: Variant = data.get("last_roll", null)
	var last_roll_sum: int = 0
	var last_roll_valid: bool = typeof(last_roll) == TYPE_ARRAY and last_roll.size() <= 3
	if typeof(last_roll) != TYPE_ARRAY or last_roll.size() > 3:
		errors.append("invalid last_roll")
	else:
		for face in last_roll:
			if not _valid_int(face, 1, 6):
				errors.append("invalid die face")
			else:
				last_roll_sum += int(face)
	var last_total_value: Variant = data.get("last_total", null)
	var last_total_valid: bool = _valid_int(last_total_value, 0, MAX_GRAPH_STEPS)
	if not last_total_valid:
		errors.append("invalid last_total")
	if graph_save and last_roll_valid and last_total_valid:
		if last_roll.is_empty() and int(last_total_value) != 0:
			errors.append("graph last roll is missing for total")
		elif not last_roll.is_empty() and last_roll_sum != int(last_total_value):
			errors.append("graph last roll total mismatch")
	if typeof(data.get("last_event", null)) != TYPE_DICTIONARY:
		errors.append("invalid last_event")
	var event_log: Variant = data.get("event_log", null)
	if typeof(event_log) != TYPE_ARRAY or event_log.size() > 200:
		errors.append("invalid event_log")
	else:
		for event in event_log:
			if typeof(event) != TYPE_DICTIONARY:
				errors.append("invalid event entry")
	var action_options: Variant = data.get("action_options", null)
	var known_actions: Array = ["buy", "upgrade", "deposit", "withdraw", "take_loan", "buy_vehicle", "buy_stock", "sell_stock", "use_card", "end_turn"]
	if typeof(action_options) != TYPE_ARRAY:
		errors.append("invalid action_options")
	else:
		for option in action_options:
			if typeof(option) != TYPE_STRING or not known_actions.has(option):
				errors.append("invalid action option")
		if phase_name == "await_action" and not action_options.has("end_turn"):
			errors.append("await_action missing end_turn")
		if phase_name in ["await_roll", "await_route"]:
			for option in action_options:
				if not ["buy_stock", "sell_stock"].has(option):
					errors.append("await_roll has non-stock action")
		elif phase_name != "await_action" and not action_options.is_empty():
			errors.append("non-action phase has action options")

	var bank: Variant = data.get("bank", null)
	if typeof(bank) != TYPE_DICTIONARY:
		errors.append("missing bank")
	else:
		for bank_key in ["cash", "deposits", "loans"]:
			if not _valid_int(bank.get(bank_key, null), 0, 1000000000000):
				errors.append("invalid bank %s" % bank_key)

	var market: Variant = data.get("market", null)
	if typeof(market) != TYPE_DICTIONARY:
		errors.append("missing market")
	else:
		if not _valid_bool(market.get("open", null)):
			errors.append("invalid market open")
		var prices: Variant = market.get("prices", null)
		if typeof(prices) != TYPE_DICTIONARY:
			errors.append("missing market prices")
		else:
			for symbol in STOCK_SYMBOLS:
				if not _valid_int(prices.get(symbol, null), 1, 1000000000):
					errors.append("invalid market price %s" % symbol)
		var trends: Variant = market.get("trends", null)
		if typeof(trends) != TYPE_DICTIONARY:
			errors.append("missing market trends")
		else:
			for symbol in trends.keys():
				if not STOCK_SYMBOLS.has(symbol) or typeof(trends[symbol]) != TYPE_DICTIONARY:
					errors.append("invalid market trend")
					continue
				var trend: Dictionary = trends[symbol]
				if not ["up", "down"].has(str(trend.get("direction", ""))) or not _valid_int(trend.get("days", null), 1, 3):
					errors.append("invalid market trend values")
				var rate_type: int = typeof(trend.get("rate", null))
				if rate_type not in [TYPE_INT, TYPE_FLOAT] or float(trend.get("rate", 0.0)) <= 0.0 or float(trend.get("rate", 0.0)) > 1.0:
					errors.append("invalid market trend rate")

	var graph_reachable: Dictionary = {}
	var source_properties: Dictionary = {}
	var property_owners: Dictionary = {}
	if typeof(board) == TYPE_ARRAY:
		for index in range(board.size()):
			if typeof(board[index]) != TYPE_DICTIONARY:
				errors.append("invalid board tile %d" % index)
				continue
			var tile: Dictionary = board[index]
			if not _valid_int(tile.get("index", null), index, index):
				errors.append("board index mismatch %d" % index)
			var allowed_board_kinds: Array = ["start", "property", "event", "tax", "bank", "stock", "rest"]
			if graph_save:
				allowed_board_kinds.append_array(["points", "card", "unsupported"])
			if not _valid_string(tile.get("kind", null)) or not allowed_board_kinds.has(tile.get("kind", "")):
				errors.append("invalid board kind %d" % index)
			if not _valid_string(tile.get("name", null)) or not _valid_string(tile.get("group", null)):
				errors.append("invalid board text %d" % index)
			var owner_value: Variant = tile.get("owner", null)
			var owner_valid: bool = _valid_int(owner_value, -1, max(-1, player_count - 1))
			if not owner_valid:
				errors.append("invalid board owner %d" % index)
			if not _valid_int(tile.get("building_level", null), 0, MAX_PROPERTY_LEVEL):
				errors.append("invalid board level %d" % index)
			for money_key in ["cost", "upgrade_cost", "base_rent", "rent", "tax_amount"]:
				if not _valid_int(tile.get(money_key, null), 0, 1000000000):
					errors.append("invalid board %s %d" % [money_key, index])
			if graph_save and owner_valid and int(owner_value) == -1 and _valid_int(tile.get("building_level", null), 1, MAX_PROPERTY_LEVEL):
				errors.append("unowned graph property has improvements %d" % index)
			if owner_valid and tile.get("kind", "") != "property" and int(owner_value) != -1:
				errors.append("non-property has owner %d" % index)
			if owner_valid and tile.get("kind", "") == "property" and int(owner_value) >= 0:
				property_owners[index] = int(owner_value)

	if graph_save:
		var board_mode_value: Variant = data.get("board_mode", null)
		if typeof(board_mode_value) != TYPE_STRING or board_mode_value != GRAPH_BOARD_MODE:
			errors.append("invalid graph board mode")
		var map_id_value: Variant = data.get("map_id", null)
		if not _valid_string(map_id_value) or str(map_id_value).is_empty():
			errors.append("invalid graph map id")
		var graph_map_id: String = str(map_id_value) if _valid_string(map_id_value) else ""
		var map_name_value: Variant = data.get("map_name", null)
		if not _valid_string(map_name_value) or str(map_name_value).is_empty():
			errors.append("invalid graph map name")
		var map_schema_value: Variant = data.get("map_schema", null)
		if typeof(map_schema_value) != TYPE_STRING or map_schema_value != RUNTIME_MAP_SCHEMA or not _valid_int(data.get("map_version", null), 1, 1):
			errors.append("invalid graph map schema")
		errors.append_array(_validate_graph_source(data.get("map_source", null), graph_map_id))
		var graph_start: Variant = data.get("start_position", null)
		var graph_board_size: int = board.size() if typeof(board) == TYPE_ARRAY else 0
		if not _valid_int(graph_start, 0, graph_board_size - 1):
			errors.append("invalid graph start position")
		if typeof(board) == TYPE_ARRAY:
			for index in range(board.size()):
				if typeof(board[index]) != TYPE_DICTIONARY:
					continue
				var tile: Dictionary = board[index]
				for coordinate in ["x", "y"]:
					if not _valid_int(tile.get(coordinate, null), -1000000, 1000000):
						errors.append("invalid graph tile coordinate %d" % index)
				var source_node_id: Variant = tile.get("source_node_id", null)
				if not _valid_int(source_node_id, index + 1, index + 1):
					errors.append("graph source node mismatch %d" % index)
				var type_value: Variant = tile.get("type_and_idx", null)
				var event_value: Variant = tile.get("event_code", null)
				if not _valid_int(type_value, 0, 65535) or not _valid_int(event_value, 0, 255):
					errors.append("invalid graph source tile status %d" % index)
				else:
					_validate_graph_source_classification(tile, index, errors)
				var tile_kind: Variant = tile.get("kind", null)
				if _valid_int(tile.get("type_and_idx", null), 2001, 3999) and (typeof(tile_kind) != TYPE_STRING or tile_kind != "property"):
					errors.append("housing source must remain a property %d" % index)
				if typeof(tile_kind) == TYPE_STRING and tile_kind == "property":
					var source_object_id: Variant = tile.get("source_object_id", null)
					var source_object_valid: bool = _valid_int(source_object_id, 1, 1999)
					if not source_object_valid:
						errors.append("invalid graph property identity %d" % index)
					elif source_properties.has(int(source_object_id)):
						errors.append("duplicate graph property identity %d" % index)
					else:
						source_properties[int(source_object_id)] = true
					var land_price: Variant = tile.get("land_price", null)
					var house_price: Variant = tile.get("house_price", null)
					var land_price_valid: bool = _valid_int(land_price, 0, 1000000)
					var house_price_valid: bool = _valid_int(house_price, 0, 1000000)
					if not land_price_valid:
						errors.append("invalid graph property land price %d" % index)
					if not house_price_valid:
						errors.append("invalid graph property house price %d" % index)
					var rents: Variant = tile.get("rent_by_level", null)
					var rents_valid: bool = typeof(rents) == TYPE_ARRAY and rents.size() == MAX_PROPERTY_LEVEL + 1
					if not rents_valid:
						errors.append("invalid graph property rent table %d" % index)
					else:
						for rent_value in rents:
							if not _valid_int(rent_value, 0, 1000000):
								errors.append("invalid graph property rent value %d" % index)
						var base_rent: Variant = tile.get("base_rent", null)
						var rent: Variant = tile.get("rent", null)
						var level: Variant = tile.get("building_level", null)
						var base_rent_valid: bool = _valid_int(base_rent, 0, 1000000000)
						var rent_valid: bool = _valid_int(rent, 0, 1000000000)
						var level_valid: bool = _valid_int(level, 0, MAX_PROPERTY_LEVEL)
						if base_rent_valid and _valid_int(rents[0], 0, 1000000) and int(base_rent) != int(rents[0]):
							errors.append("graph property base rent mismatch %d" % index)
						if rent_valid and level_valid and _valid_int(rents[int(level)], 0, 1000000) and int(rent) != int(rents[int(level)]):
							errors.append("graph property rent mismatch %d" % index)
					if land_price_valid and _valid_int(tile.get("cost", null), 0, 1000000000) and int(tile["cost"]) != int(land_price):
						errors.append("graph property cost mismatch %d" % index)
					if house_price_valid and _valid_int(tile.get("upgrade_cost", null), 0, 1000000000) and int(tile["upgrade_cost"]) != int(house_price):
						errors.append("graph property upgrade price mismatch %d" % index)
					var property_type_valid: bool = _valid_int(type_value, 2001, 3999)
					if not property_type_valid:
						errors.append("invalid graph property source type %d" % index)
					elif source_object_valid and int(type_value) - 2000 != int(source_object_id):
						errors.append("graph property source mismatch %d" % index)
				var adjacent: Variant = tile.get("adjacent", null)
				if typeof(adjacent) != TYPE_ARRAY or adjacent.size() > 4:
					errors.append("invalid graph adjacency %d" % index)
					continue
				var seen_neighbors: Dictionary = {}
				for neighbor in adjacent:
					if not _valid_int(neighbor, 0, max(0, board.size() - 1)) or int(neighbor) == index or seen_neighbors.has(int(neighbor)):
						errors.append("invalid graph edge %d" % index)
						continue
					seen_neighbors[int(neighbor)] = true
					if typeof(board[int(neighbor)]) == TYPE_DICTIONARY:
						var reverse_adjacent: Variant = board[int(neighbor)].get("adjacent", [])
						var reverse_has: bool = false
						if typeof(reverse_adjacent) == TYPE_ARRAY:
							for reverse_neighbor in reverse_adjacent:
								if _valid_int(reverse_neighbor) and int(reverse_neighbor) == index:
									reverse_has = true
									break
						if not reverse_has:
							errors.append("asymmetric graph edge %d" % index)
			if _valid_int(graph_start, 0, graph_board_size - 1):
				graph_reachable[int(graph_start)] = true
				var queue: Array = [int(graph_start)]
				while not queue.is_empty():
					var node: int = int(queue.pop_front())
					if typeof(board[node]) != TYPE_DICTIONARY:
						continue
					var reachable_adjacent: Variant = board[node].get("adjacent", [])
					if typeof(reachable_adjacent) != TYPE_ARRAY:
						continue
					for neighbor in reachable_adjacent:
						if not _valid_int(neighbor, 0, max(0, board.size() - 1)):
							continue
						var next_node: int = int(neighbor)
						if not graph_reachable.has(next_node):
							graph_reachable[next_node] = true
							queue.append(next_node)
				for index in range(board.size()):
					if typeof(board[index]) == TYPE_DICTIONARY and board[index].get("kind", "") == "property" and not graph_reachable.has(index):
						errors.append("graph property is unreachable %d" % index)
		else:
			for _unused in range(0):
				pass

	if typeof(players) == TYPE_ARRAY:
		var position_limit: int = (board.size() - 1) if typeof(board) == TYPE_ARRAY else BOARD_SIZE - 1
		for index in range(players.size()):
			if typeof(players[index]) != TYPE_DICTIONARY:
				errors.append("invalid player %d" % index)
				continue
			var player: Dictionary = players[index]
			var required_player: Array = ["id", "name", "is_human", "is_ai", "alive", "bankrupt", "cash", "deposit", "position", "properties", "property_values", "stocks", "cards", "vehicle", "dice_count", "vehicles", "skip_turns", "rent_shield", "turtle_days", "stay_next", "loan", "loan_due_day", "turns_taken"]
			if graph_save:
				required_player.append_array(["previous_position", "points"])
			for required_key in required_player:
				if not player.has(required_key):
					errors.append("player %d missing %s" % [index, required_key])
			if not _valid_int(player.get("id", null), index, index) or not _valid_string(player.get("name", null)):
				errors.append("player %d identity invalid" % index)
			for bool_key in ["is_human", "is_ai", "alive", "bankrupt"]:
				if not _valid_bool(player.get(bool_key, null)):
					errors.append("player %d %s invalid" % [index, bool_key])
			if _valid_bool(player.get("is_human", null)) and _valid_bool(player.get("is_ai", null)) and bool(player["is_human"]) == bool(player["is_ai"]):
				errors.append("player %d control flags invalid" % index)
			if _valid_bool(player.get("alive", null)) and _valid_bool(player.get("bankrupt", null)) and bool(player["alive"]) == bool(player["bankrupt"]):
				errors.append("player %d alive state invalid" % index)
			for money_key in ["cash", "deposit", "property_values", "loan"]:
				if not _valid_int(player.get(money_key, null), 0, 1000000000000):
					errors.append("player %d %s invalid" % [index, money_key])
			for counter_key in ["position", "skip_turns", "rent_shield", "turtle_days", "stay_next", "loan_due_day", "turns_taken"]:
				if not _valid_int(player.get(counter_key, null), 0, 1000000000):
					errors.append("player %d %s invalid" % [index, counter_key])
			if graph_save:
				if not _valid_int(player.get("previous_position", null), -1, position_limit):
					errors.append("player %d previous_position invalid" % index)
				if not _valid_int(player.get("points", null), 0, 1000000000000):
					errors.append("player %d points invalid" % index)
			var dice_count_value: Variant = player.get("dice_count", null)
			var dice_count_valid: bool = _valid_int(dice_count_value, 1, 3)
			if not dice_count_valid:
				errors.append("player %d dice_count invalid" % index)
			if _valid_int(player.get("position", null)) and int(player["position"]) > position_limit:
				errors.append("player %d position out of range" % index)
			var vehicle_value: Variant = player.get("vehicle", null)
			var vehicle_valid: bool = _valid_string(vehicle_value) and VEHICLE_DICE.has(vehicle_value)
			if dice_count_valid and vehicle_valid and int(dice_count_value) > int(VEHICLE_DICE[vehicle_value]):
				errors.append("player %d dice count exceeds vehicle" % index)
			if not vehicle_valid:
				errors.append("player %d vehicle invalid" % index)
			var properties: Variant = player.get("properties", null)
			if typeof(properties) != TYPE_ARRAY:
				errors.append("player %d properties invalid" % index)
			else:
				for property_id in properties:
					if not _valid_int(property_id, 0, position_limit):
						errors.append("player %d property invalid" % index)
					elif property_owners.has(int(property_id)):
						if int(property_owners[int(property_id)]) != index:
							errors.append("player %d property owner mismatch" % index)
						property_owners.erase(int(property_id))
			var stocks: Variant = player.get("stocks", null)
			if typeof(stocks) != TYPE_DICTIONARY:
				errors.append("player %d stocks invalid" % index)
			else:
				for symbol in STOCK_SYMBOLS:
					if not _valid_int(stocks.get(symbol, null), 0, 1000000000):
						errors.append("player %d stock %s invalid" % [index, symbol])
				for symbol in stocks.keys():
					if not STOCK_SYMBOLS.has(symbol):
						errors.append("player %d unknown stock" % index)
			var cards: Variant = player.get("cards", null)
			if typeof(cards) != TYPE_ARRAY or cards.size() > 15:
				errors.append("player %d cards invalid" % index)
			else:
				for card_id in cards:
					if not _valid_string(card_id):
						errors.append("player %d card invalid" % index)
			var vehicles: Variant = player.get("vehicles", null)
			if typeof(vehicles) != TYPE_DICTIONARY:
				errors.append("player %d vehicles invalid" % index)
			else:
				for vehicle in ["walking", "motorcycle", "car"]:
					if not _valid_bool(vehicles.get(vehicle, null)):
						errors.append("player %d vehicle ownership invalid" % index)
				if vehicle_valid and (not vehicles.has(vehicle_value) or not bool(vehicles.get(vehicle_value, false))):
					errors.append("player %d selected vehicle is not owned" % index)

	if graph_save:
		var graph_board_size: int = board.size() if typeof(board) == TYPE_ARRAY else 0
		if typeof(players) == TYPE_ARRAY and typeof(board) == TYPE_ARRAY:
			for index in range(players.size()):
				if typeof(players[index]) != TYPE_DICTIONARY:
					continue
				var graph_player: Dictionary = players[index]
				var position: Variant = graph_player.get("position", null)
				var previous_position: Variant = graph_player.get("previous_position", null)
				if _valid_int(position, 0, graph_board_size - 1) and _valid_int(previous_position, -1, max(-1, graph_board_size - 1)):
					if int(previous_position) >= 0 and typeof(board[int(position)]) == TYPE_DICTIONARY:
						var player_adjacent: Variant = board[int(position)].get("adjacent", [])
						var player_previous_valid: bool = false
						if typeof(player_adjacent) == TYPE_ARRAY:
							for player_neighbor in player_adjacent:
								if _valid_int(player_neighbor) and int(player_neighbor) == int(previous_position):
									player_previous_valid = true
									break
						if not player_previous_valid:
							errors.append("player %d previous node is not adjacent" % index)
					if not graph_reachable.has(int(position)):
						errors.append("player %d position is unreachable" % index)
		var route_options: Variant = data.get("route_options", null)
		var remaining_steps_value: Variant = data.get("remaining_steps", null)
		if typeof(route_options) != TYPE_ARRAY:
			errors.append("invalid graph route options")
		if not _valid_int(remaining_steps_value, 0, MAX_GRAPH_STEPS):
			errors.append("invalid graph remaining steps")
		var pending_value: Variant = data.get("pending_movement", null)
		if typeof(pending_value) != TYPE_DICTIONARY:
			errors.append("invalid graph pending movement")
		var pending: Dictionary = pending_value if typeof(pending_value) == TYPE_DICTIONARY else {}
		if phase_name == "await_route":
			if typeof(route_options) != TYPE_ARRAY or route_options.is_empty():
				errors.append("route phase missing route options")
			if not _valid_int(remaining_steps_value, 1, MAX_GRAPH_STEPS):
				errors.append("route phase has no remaining steps")
			if _valid_int(remaining_steps_value, 0, MAX_GRAPH_STEPS) and last_total_valid and int(remaining_steps_value) > int(last_total_value):
				errors.append("route phase exceeds pending roll")
			if not last_roll_valid or last_roll.is_empty():
				errors.append("route phase missing pending roll")
			if last_roll_valid and typeof(players) == TYPE_ARRAY and current_player >= 0 and current_player < players.size() and typeof(players[current_player]) == TYPE_DICTIONARY:
				var pending_actor: Dictionary = players[current_player]
				var pending_vehicle: Variant = pending_actor.get("vehicle", null)
				if _valid_string(pending_vehicle) and VEHICLE_DICE.has(pending_vehicle) and last_roll.size() > int(VEHICLE_DICE[pending_vehicle]):
					errors.append("route phase exceeds vehicle dice limit")
			if pending.is_empty():
				errors.append("route phase missing pending movement")
			else:
				var pending_player_id: Variant = pending.get("player_id", null)
				var pending_current_node: Variant = pending.get("current_node", null)
				var pending_previous_node: Variant = pending.get("previous_node", null)
				var pending_player_valid: bool = _valid_int(pending_player_id, 0, max(0, player_count - 1))
				var pending_current_valid: bool = _valid_int(pending_current_node, 0, graph_board_size - 1)
				var pending_previous_valid: bool = _valid_int(pending_previous_node, -1, max(-1, graph_board_size - 1))
				if not pending_player_valid or int(pending_player_id) != current_player:
					errors.append("pending route player mismatch")
				if not pending_current_valid or not pending_previous_valid:
					errors.append("pending route node invalid")
				if typeof(players) == TYPE_ARRAY and current_player >= 0 and current_player < players.size() and typeof(players[current_player]) == TYPE_DICTIONARY and pending_current_valid and pending_previous_valid:
					var route_player: Dictionary = players[current_player]
					var route_position: Variant = route_player.get("position", null)
					var route_previous_position: Variant = route_player.get("previous_position", null)
					if not _valid_int(route_position, 0, graph_board_size - 1) or not _valid_int(route_previous_position, -1, max(-1, graph_board_size - 1)) or int(route_position) != int(pending_current_node) or int(route_previous_position) != int(pending_previous_node):
						errors.append("pending route position mismatch")
				if pending_current_valid and pending_previous_valid:
					var legal_routes: Array = []
					var pending_tile: Dictionary = {}
					if typeof(board) == TYPE_ARRAY:
						var pending_tile_value: Variant = board[int(pending_current_node)]
						if typeof(pending_tile_value) == TYPE_DICTIONARY:
							pending_tile = pending_tile_value
					var pending_adjacent: Variant = pending_tile.get("adjacent", [])
					if typeof(pending_adjacent) == TYPE_ARRAY:
						for neighbor in pending_adjacent:
							if not _valid_int(neighbor, 0, graph_board_size - 1):
								continue
							var neighbor_id: int = int(neighbor)
							if neighbor_id != int(pending_previous_node):
								legal_routes.append(neighbor_id)
					if legal_routes.is_empty() and int(pending_previous_node) >= 0:
						legal_routes.append(int(pending_previous_node))
					legal_routes.sort()
					var canonical_route_options: Array = []
					if typeof(route_options) == TYPE_ARRAY:
						for route_option in route_options:
							if _valid_int(route_option):
								canonical_route_options.append(int(route_option))
					if canonical_route_options != legal_routes or canonical_route_options.size() != route_options.size():
						errors.append("pending route options are not canonical")
		else:
			if typeof(route_options) == TYPE_ARRAY and not route_options.is_empty():
				errors.append("non-route phase has route options")
			if _valid_int(remaining_steps_value, 0, MAX_GRAPH_STEPS) and int(remaining_steps_value) != 0:
				errors.append("non-route phase has remaining steps")
			if typeof(pending_value) == TYPE_DICTIONARY and not pending.is_empty():
				errors.append("non-route phase has pending movement")

	if not property_owners.is_empty():
		errors.append("board property missing player ownership")
	if phase_name != "game_over" and current_player >= 0 and current_player < player_count and typeof(players[current_player]) == TYPE_DICTIONARY:
		var current_actor: Dictionary = players[current_player]
		if not _valid_bool(current_actor.get("alive", null)) or not bool(current_actor.get("alive", false)) or not _valid_bool(current_actor.get("bankrupt", null)) or bool(current_actor.get("bankrupt", false)):
			errors.append("dead current player")
	if phase_name == "game_over":
		if winner < 0 or winner >= player_count or typeof(players[winner]) != TYPE_DICTIONARY or not bool(players[winner].get("alive", false)):
			errors.append("invalid game over winner")
	elif winner != -1:
		errors.append("winner set before game over")

	var auctions: Variant = data.get("bankruptcy_auctions", null)
	if typeof(auctions) != TYPE_ARRAY:
		errors.append("invalid bankruptcy auctions")
	else:
		for auction in auctions:
			if typeof(auction) != TYPE_DICTIONARY:
				errors.append("invalid bankruptcy auction entry")
	return {"ok": errors.is_empty(), "errors": errors}


func to_dict() -> Dictionary:
	_sync_state()
	var copy: Dictionary = state.duplicate(true)
	copy["rng_state_text"] = str(_rng.state)
	return copy


func to_json() -> String:
	return JSON.stringify(to_dict())


static func _canonicalize_json_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value:
		return int(value)
	if typeof(value) == TYPE_ARRAY:
		var array_value: Array = value.duplicate(true)
		for index in range(array_value.size()):
			array_value[index] = _canonicalize_json_numbers(array_value[index])
		return array_value
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary_value: Dictionary = value.duplicate(true)
		for key in dictionary_value.keys():
			dictionary_value[key] = _canonicalize_json_numbers(dictionary_value[key])
		return dictionary_value
	return value

static func from_dict(data: Dictionary) -> Richman4GameState:
	var validation: Dictionary = validate_save(data)
	if not bool(validation.get("ok", false)):
		return null
	var game = new()
	game.state = data.duplicate(true)
	if game.state.get("board_mode", "") == GRAPH_BOARD_MODE:
		game.state = _canonicalize_json_numbers(game.state)
	game._rng = RandomNumberGenerator.new()
	game._rng.seed = int(game.state.get("seed", 0))
	var rng_text: String = str(game.state.get("rng_state_text", ""))
	game._rng.state = int(rng_text) if rng_text != "" else int(game.state.get("rng_state", 0))
	game._sync_state()
	if game.state.get("phase", "") in ["await_roll", "await_action", "await_route"]:
		game._set_action_options(int(game.state.get("current_player", -1)))
	else:
		game.state["action_options"] = []
	return game


func save_to_path(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(to_json())
	file.close()
	return true


static func load_from_path(path: String) -> Richman4GameState:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed)
