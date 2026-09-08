class_name Richman4GameState
extends RefCounted

## Deterministic, serializable simulation for the Godot runtime.
##
## The original executable and data files are kept outside this repository. The
## rules below are therefore an explicit provisional reconstruction. They are
## deliberately kept in one small state object so that observed corrections
## can be made without coupling the renderer to the simulation.

const SAVE_VERSION = 1
const RULESET_ID = "richman4_provisional_v1"
const BOARD_SIZE = 40
const MIN_PLAYERS = 2
const MAX_PLAYERS = 4
const START_CASH = 15000
const START_POSITION = 0
const MAX_PROPERTY_LEVEL = 5
const PASS_START_BONUS = 0 # The reference manual does not support an invented bonus.
const DAYS_PER_MONTH = 30
const MONTHLY_DEPOSIT_RATE = 0.10
const LOAN_TERM_DAYS = 90
const INITIAL_BANK_CASH = 1000000
const INT64_MIN = -9223372036854775808
const INT64_MAX = 9223372036854775807

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
	if player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		return null
	var game = new()
	game._initialize(seed_value, player_count)
	return game


func _initialize(seed_value: int, player_count: int) -> void:
	_rng.seed = seed_value
	state = {
		"version": SAVE_VERSION,
		"ruleset": RULESET_ID,
		"seed": seed_value,
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


func _build_players(player_count: int) -> Array:
	var players: Array = []
	for player_id in range(player_count):
		players.append({
			"id": player_id,
			"name": "玩家 %d" % (player_id + 1),
			"is_human": player_id == 0,
			"is_ai": player_id != 0,
			"alive": true,
			"bankrupt": false,
			"cash": START_CASH,
			"deposit": 0,
			"position": START_POSITION,
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
		})
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
	var options: Array = ["end_turn"]
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		state["action_options"] = options
		return
	var tile: Dictionary = _tile_at(int(player.get("position", 0)))
	var bank_open: bool = not _is_sunday()
	if tile.get("kind", "") == "property" and not bool(state.get("property_action_used", false)):
		var owner: int = int(tile.get("owner", -1))
		if owner == -1 and bank_open and int(player.get("cash", 0)) >= int(tile.get("cost", 0)):
			options.push_front("buy")
		elif owner == player_id and bank_open:
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


func _upgrade_price(tile: Dictionary) -> int:
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
	if int(player.get("stay_next", 0)) > 0:
		player["stay_next"] = int(player.get("stay_next", 0)) - 1
		_record_event("stay_resolved", {"player_id": player_id, "tile": int(player.get("position", 0))})
	else:
		_move_player(player_id, total)
	var doubled: bool = not turtle_step and count == 2 and dice[0] == dice[1]
	if doubled:
		state["doubles_count"] = int(state.get("doubles_count", 0)) + 1
		state["extra_roll"] = int(state["doubles_count"]) < 3
		if not bool(state["extra_roll"]):
			player["skip_turns"] = max(1, int(player.get("skip_turns", 0)))
	else:
		state["doubles_count"] = 0
		state["extra_roll"] = false
	_record_event("roll", {"player_id": player_id, "dice": dice, "total": total, "vehicle": player.get("vehicle", "walking")})
	_resolve_landing(player_id)
	return _result(true, "擲骰完成", {"dice": dice, "total": total})


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
	var auction: Dictionary = _auction_assets(debtor_id, creditor_id)
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
	if _is_sunday() and ["buy", "upgrade", "deposit", "withdraw", "take_loan"].has(normalized):
		return _error("週日銀行休息")
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
	var index: int = cards.find(card_id) if card_id != "" else 0
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
	if bool(state.get("extra_roll", false)) and _valid_player(player_id, true):
		state["extra_roll"] = false
		state["phase"] = "await_roll"
		state["action_options"] = []
		_record_event("extra_roll", {"player_id": player_id})
		return _result(true, "同一玩家獲得額外回合")
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
	_record_event("month_started", {"month": int(state.get("month", 1)) + 1})


func _repay_due_loan(player_id: int) -> void:
	var player: Dictionary = _player(player_id)
	var loan: int = int(player.get("loan", 0))
	if loan <= 0 or int(state.get("day", 1)) < int(player.get("loan_due_day", 0)):
		return
	var available: int = int(player.get("cash", 0)) + int(player.get("deposit", 0))
	if available < loan:
		_declare_bankruptcy(player_id, -1, loan, "loan_due")
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
	while state.get("phase", "") != "game_over" and int(state.get("current_player", -1)) == player_id and safety < 16:
		safety += 1
		if state.get("phase", "") == "await_roll":
			roll()
		elif state.get("phase", "") == "await_action":
			if not bool(_player(player_id).get("alive", false)):
				_advance_to_next_alive(player_id)
				break
			_ai_action(player_id)
		else:
			break
	if state.get("phase", "") == "await_action" and int(state.get("current_player", -1)) == player_id:
		end_turn()
	return _result(true, "AI 回合完成", {"player_id": player_id, "iterations": safety})


func _ai_action(player_id: int) -> void:
	var player: Dictionary = _player(player_id)
	var tile: Dictionary = _tile_at(int(player.get("position", 0)))
	if tile.get("kind", "") == "property":
		var owner: int = int(tile.get("owner", -1))
		if owner == -1 and not bool(state.get("property_action_used", false)) and int(player.get("cash", 0)) >= int(tile.get("cost", 0)) and not _is_sunday():
			choose_action("buy")
			return
		if owner == player_id and not bool(state.get("property_action_used", false)) and int(tile.get("building_level", 0)) < MAX_PROPERTY_LEVEL and not _is_sunday() and int(player.get("cash", 0)) >= _upgrade_price(tile) + 500:
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
		choose_action("use_card", {"card_id": player["cards"][0]})
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


static func validate_save(data: Dictionary) -> Dictionary:
	var errors: Array = []
	if int(data.get("version", -1)) != SAVE_VERSION:
		errors.append("unsupported save version")
	if str(data.get("ruleset", "")) != RULESET_ID:
		errors.append("unsupported ruleset")
	var players: Variant = data.get("players", null)
	if typeof(players) != TYPE_ARRAY or players.size() < MIN_PLAYERS or players.size() > MAX_PLAYERS:
		errors.append("invalid player count")
	var board: Variant = data.get("board", null)
	if typeof(board) != TYPE_ARRAY or board.size() != BOARD_SIZE:
		errors.append("invalid board")
	var player_count: int = players.size() if typeof(players) == TYPE_ARRAY else 0
	var phase: String = str(data.get("phase", ""))
	if not ["await_roll", "await_action", "game_over"].has(phase):
		errors.append("invalid phase")
	var current_player: int = int(data.get("current_player", -1))
	if typeof(players) == TYPE_ARRAY and (current_player < 0 or current_player >= players.size()):
		errors.append("invalid current player")
	var rng_text: String = ""
	if data.has("rng_state_text"):
		if typeof(data.get("rng_state_text")) != TYPE_STRING:
			errors.append("invalid rng state")
		else:
			rng_text = data.get("rng_state_text")
			var parsed_rng: int = int(rng_text)
			if not rng_text.is_valid_int() or parsed_rng < INT64_MIN or parsed_rng > INT64_MAX or str(parsed_rng) != rng_text:
				errors.append("invalid rng state")
	elif typeof(data.get("rng_state", null)) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("missing rng state")
	var bank: Variant = data.get("bank", null)
	if typeof(bank) != TYPE_DICTIONARY:
		errors.append("missing bank")
	else:
		for bank_key in ["cash", "deposits", "loans"]:
			if typeof(bank.get(bank_key, null)) not in [TYPE_INT, TYPE_FLOAT]:
				errors.append("missing bank %s" % bank_key)
			elif int(bank.get(bank_key, 0)) < 0:
				errors.append("negative bank %s" % bank_key)
	var market: Variant = data.get("market", null)
	if typeof(market) != TYPE_DICTIONARY:
		errors.append("missing market")
	else:
		var prices: Variant = market.get("prices", null)
		if typeof(prices) != TYPE_DICTIONARY:
			errors.append("missing market prices")
		else:
			for symbol in STOCK_SYMBOLS:
				if typeof(prices.get(symbol, null)) not in [TYPE_INT, TYPE_FLOAT] or int(prices.get(symbol, 0)) <= 0:
					errors.append("invalid market price %s" % symbol)
	if typeof(board) == TYPE_ARRAY:
		for index in range(board.size()):
			if typeof(board[index]) != TYPE_DICTIONARY:
				errors.append("invalid board tile %d" % index)
				continue
			var tile: Dictionary = board[index]
			if int(tile.get("index", -1)) != index:
				errors.append("board index mismatch %d" % index)
			if not ["start", "property", "event", "tax", "bank", "stock", "rest"].has(str(tile.get("kind", ""))):
				errors.append("invalid board kind %d" % index)
			if int(tile.get("owner", -1)) < -1 or int(tile.get("owner", -1)) >= player_count:
				errors.append("invalid board owner %d" % index)
			if int(tile.get("building_level", 0)) < 0 or int(tile.get("building_level", 0)) > MAX_PROPERTY_LEVEL:
				errors.append("invalid board level %d" % index)
			for money_key in ["cost", "upgrade_cost", "base_rent", "rent"]:
				if typeof(tile.get(money_key, null)) not in [TYPE_INT, TYPE_FLOAT] or int(tile.get(money_key, 0)) < 0:
					errors.append("invalid board %s %d" % [money_key, index])
	if typeof(players) == TYPE_ARRAY:
		for index in range(players.size()):
			if typeof(players[index]) != TYPE_DICTIONARY:
				errors.append("invalid player %d" % index)
				continue
			var player: Dictionary = players[index]
			for required_key in ["id", "cash", "deposit", "position", "properties", "stocks", "cards", "alive"]:
				if not player.has(required_key):
					errors.append("player %d missing %s" % [index, required_key])
			if int(player.get("id", -1)) != index:
				errors.append("player %d id mismatch" % index)
			if int(player.get("cash", 0)) < 0 or int(player.get("deposit", 0)) < 0:
				errors.append("player %d has negative balance" % index)
			if int(player.get("position", -1)) < 0 or int(player.get("position", -1)) >= BOARD_SIZE:
				errors.append("player %d has invalid position" % index)
			if typeof(player.get("properties", null)) != TYPE_ARRAY:
				errors.append("player %d has invalid properties" % index)
			else:
				for property_id in player.get("properties", []):
					if typeof(property_id) not in [TYPE_INT, TYPE_FLOAT] or int(property_id) < 0 or int(property_id) >= BOARD_SIZE:
						errors.append("player %d has invalid property" % index)
			if typeof(player.get("stocks", null)) != TYPE_DICTIONARY:
				errors.append("player %d has invalid stocks" % index)
			else:
				for symbol in STOCK_SYMBOLS:
					if typeof(player["stocks"].get(symbol, null)) not in [TYPE_INT, TYPE_FLOAT] or int(player["stocks"].get(symbol, 0)) < 0:
						errors.append("player %d has invalid stock %s" % [index, symbol])
			if typeof(player.get("cards", null)) != TYPE_ARRAY or player.get("cards", []).size() > 15:
				errors.append("player %d has invalid cards" % index)
			if typeof(player.get("alive", null)) != TYPE_BOOL:
				errors.append("player %d has invalid alive state" % index)
	if phase == "game_over":
		var winner: int = int(data.get("winner", -1))
		if winner < -1 or (typeof(players) == TYPE_ARRAY and winner >= players.size()):
			errors.append("invalid winner")
	else:
		if int(data.get("winner", -1)) != -1:
			errors.append("winner set before game over")
	return {"ok": errors.is_empty(), "errors": errors}


func to_dict() -> Dictionary:
	_sync_state()
	var copy: Dictionary = state.duplicate(true)
	copy["rng_state_text"] = str(_rng.state)
	return copy


func to_json() -> String:
	return JSON.stringify(to_dict())


static func from_dict(data: Dictionary) -> Richman4GameState:
	var validation: Dictionary = validate_save(data)
	if not bool(validation.get("ok", false)):
		return null
	var game = new()
	game.state = data.duplicate(true)
	game._rng = RandomNumberGenerator.new()
	game._rng.seed = int(game.state.get("seed", 0))
	var rng_text: String = str(game.state.get("rng_state_text", ""))
	game._rng.state = int(rng_text) if rng_text != "" else int(game.state.get("rng_state", 0))
	game._sync_state()
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
