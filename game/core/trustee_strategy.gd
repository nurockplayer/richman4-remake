extends RefCounted
## Runtime trustee choices adapt the existing deterministic policy. Native AI
## keeps its prior policy. Personality affects the property's cash reserve;
## exact original character-specific tactics are intentionally not invented.
const Preferences = preload("res://game/core/trustee_preferences.gd")

static func action_allowed(state: Dictionary, action: String, _params: Dictionary) -> bool:
	var preferences := Preferences.for_player(state, int(state.get("current_player", -1)))
	if preferences.is_empty():
		return true
	if action == "use_card":
		return preferences.use_cards
	if action == "use_tool":
		return preferences.use_tools
	return true

static func upgrade_reserve(state: Dictionary, player_id: int) -> int:
	var preferences := Preferences.for_player(state, player_id)
	return 500 if preferences.is_empty() else [1000, 500, 0][int(preferences.personality)]

static func balance_bank(game: Object, player_id: int, preferences: Dictionary) -> bool:
	var player: Dictionary = game.state.players[player_id]
	var cash := int(player.get("cash", 0))
	var liquid := cash + int(player.get("deposit", 0))
	# Source clamps the effective bank target away from empty cash/deposit.
	var target := int(liquid * clampi(int(preferences.cash_ratio), 10, 90) / 100)
	var action := "deposit" if cash > target else "withdraw"
	var amount := mini(absi(cash - target), game.bank_transfer_limit(action, player_id))
	return amount > 0 and bool(game.choose_action(action, {"amount": amount}).get("ok", false))

static func may_invest(state: Dictionary, player_id: int) -> bool:
	var preferences := Preferences.for_player(state, player_id)
	if preferences.is_empty():
		return true
	var ratio := int(preferences.stock_ratio)
	if ratio == 0:
		return false
	var player: Dictionary = state.players[player_id]
	var invested := 0
	var prices: Dictionary = state.get("market", {}).get("prices", {})
	for symbol in player.get("stocks", {}):
		invested += int(int(player.stocks[symbol]) * float(prices.get(symbol, 0)))
	var funds := int(player.get("cash", 0)) + int(player.get("deposit", 0)) + invested
	return invested < int(funds * ratio / 100)

static func may_buy(state: Dictionary, player_id: int, symbol: String, quantity: int) -> bool:
	var preferences := Preferences.for_player(state, player_id)
	if preferences.is_empty():
		return true
	var player: Dictionary = state.players[player_id]
	var prices: Dictionary = state.get("market", {}).get("prices", {})
	var invested := 0
	for held_symbol in player.get("stocks", {}):
		invested += int(int(player.stocks[held_symbol]) * float(prices.get(held_symbol, 0)))
	var funds := int(player.get("cash", 0)) + int(player.get("deposit", 0)) + invested
	var cost := int(float(prices.get(symbol, 0)) * quantity)
	return int(preferences.stock_ratio) > 0 and cost > 0 and invested + cost <= int(funds * int(preferences.stock_ratio) / 100)
