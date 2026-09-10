extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const MONEY_LIMIT := 1000000000000
const HOLDING_LIMIT := 1000000000
const PRICE := 120
var checks := 0
var failures := 0

func _initialize() -> void:
	for spec in [
		{"label": "bank cash overflow", "action": "buy_stock", "cash": 8000, "bank": MONEY_LIMIT, "holding": 0, "quantity": 1},
		{"label": "player cash overflow", "action": "sell_stock", "cash": MONEY_LIMIT, "bank": PRICE, "holding": 1, "quantity": 1},
		{"label": "holding overflow", "action": "buy_stock", "cash": 8000, "bank": 0, "holding": HOLDING_LIMIT, "quantity": 1},
		{"label": "quantity multiplication overflow", "action": "buy_stock", "cash": 8000, "bank": 0, "holding": 0, "quantity": 9223372036854775807},
		{"label": "fractional quantity", "action": "buy_stock", "cash": 8000, "bank": 0, "holding": 0, "quantity": 1.5},
		{"label": "string quantity", "action": "buy_stock", "cash": 8000, "bank": 0, "holding": 0, "quantity": "1"},
		{"label": "negative quantity", "action": "sell_stock", "cash": 0, "bank": PRICE, "holding": 1, "quantity": -1},
		{"label": "insufficient cash", "action": "buy_stock", "cash": PRICE - 1, "bank": 0, "holding": 0, "quantity": 1},
		{"label": "insufficient bank cash", "action": "sell_stock", "cash": 0, "bank": PRICE - 1, "holding": 1, "quantity": 1},
		{"label": "insufficient holding", "action": "sell_stock", "cash": 0, "bank": PRICE, "holding": 0, "quantity": 1},
	]:
		_reject(spec)
	_exact_buy()
	_exact_sell()
	print("Legacy stock bounds checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func _fixture(cash: int, bank_cash: int, holding: int) -> Object:
	var game = Game.new_game(11101, 2)
	game.state.players[0].cash = cash
	game.state.players[0].stocks.tech = holding
	game.state.bank.cash = bank_cash
	game._set_action_options(0)
	return game

func _valid(game: Object, label: String) -> bool:
	var result: Dictionary = Game.validate_save(game.to_dict())
	var ok: bool = result.get("ok", false)
	_expect(ok, label + " validates: " + str(result.get("errors", [])))
	if not ok:
		return false
	var restored = Game.from_dict(JSON.parse_string(game.to_json()))
	# Legacy v1 retains JSON numeric types in nested records. Compare both
	# serialized snapshots after parsing; rng_state_text remains exact.
	_expect(restored != null and JSON.parse_string(restored.to_json()) == JSON.parse_string(game.to_json()), label + " JSON snapshot continuation")
	return true

func _reject(spec: Dictionary) -> void:
	var game = _fixture(spec.cash, spec.bank, spec.holding)
	if not _valid(game, spec.label + " before"):
		return
	var before: String = game.to_json()
	var result: Dictionary = game.choose_action(spec.action, {"symbol": "tech", "quantity": spec.quantity})
	_expect(not result.get("ok", false), spec.label + " rejects")
	_expect(game.to_json() == before, spec.label + " preserves complete state/RNG/events")
	_valid(game, spec.label + " after")

func _exact_buy() -> void:
	var game = _fixture(PRICE, MONEY_LIMIT - PRICE, HOLDING_LIMIT - 1)
	if not _valid(game, "exact buy before"):
		return
	var before: Dictionary = game.to_dict()
	var result: Dictionary = game.choose_action("buy_stock", {"symbol": "tech", "quantity": 1})
	_expect(result.get("ok", false), "exact bank and holding limit buy succeeds")
	_expect(game.state.bank.cash == MONEY_LIMIT and game.state.players[0].stocks.tech == HOLDING_LIMIT and game.state.players[0].cash == 0, "exact buy balances and holding")
	_expect(game.state.players[0].deposit == before.players[0].deposit, "legacy buy remains cash-funded")
	_expect(game.to_dict().rng_state_text == before.rng_state_text, "exact buy does not draw RNG")
	_valid(game, "exact buy after")

func _exact_sell() -> void:
	var game = _fixture(MONEY_LIMIT - PRICE, PRICE, 1)
	if not _valid(game, "exact sell before"):
		return
	var before: Dictionary = game.to_dict()
	var result: Dictionary = game.choose_action("sell_stock", {"symbol": "tech", "quantity": 1})
	_expect(result.get("ok", false), "exact player cash limit sell succeeds")
	_expect(game.state.bank.cash == 0 and game.state.players[0].stocks.tech == 0 and game.state.players[0].cash == MONEY_LIMIT, "exact sell balances and holding")
	_expect(game.state.players[0].deposit == before.players[0].deposit, "legacy sell remains cash-funded")
	_expect(game.to_dict().rng_state_text == before.rng_state_text, "exact sell does not draw RNG")
	_valid(game, "exact sell after")
