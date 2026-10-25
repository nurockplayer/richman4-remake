extends RefCounted
## Source-compatible average purchase-cost bookkeeping for stock holdings.
##
## A missing metadata field is an explicitly unknown legacy position.  The
## accounting helpers never infer a cost for an already-held unknown position;
## they only create a known value when a new position is opened.

# Known costs are source float32 values.  Market quotes are bounded by the
# stock market's 1..9999 price range, while a company purchase uses
# int(stock_value / 10000) and the existing company value/cash contract allows
# stock_value up to 1e12.  Keep the larger face price as the accounting ceiling
# and below INT64_MAX even at the save validator's one-billion-share bound.
const MARKET_PRICE_MAX: float = 9999.0
const COMPANY_STOCK_VALUE_MAX: int = 1000000000000
const COMPANY_FACE_PRICE_SCALE: int = 10000
const MAX_COMPANY_FACE_PRICE: float = float(COMPANY_STOCK_VALUE_MAX / COMPANY_FACE_PRICE_SCALE)
const MAX_KNOWN_COST: float = MAX_COMPANY_FACE_PRICE if MAX_COMPANY_FACE_PRICE > MARKET_PRICE_MAX else MARKET_PRICE_MAX
# Canonical float32(1 / 1_000_000_000): minimum positive SALE total ask
# divided by the maximum legal share quantity; partial sales retain this cost.
const MIN_KNOWN_COST: float = 9.999999717180685e-10

static func source_float(value: float) -> float:
	return float(PackedFloat32Array([value])[0])


static func new_costs(symbols: Array) -> Dictionary:
	var costs: Dictionary = {}
	for symbol in symbols:
		costs[str(symbol)] = source_float(0.0)
	return costs


static func initialize_player(player: Dictionary, symbols: Array) -> void:
	player["stock_average_costs"] = new_costs(symbols)


static func normalize_player(player: Dictionary, symbols: Array) -> void:
	var value: Variant = player.get("stock_average_costs", null)
	if typeof(value) != TYPE_DICTIONARY:
		return
	var costs: Dictionary = value
	for symbol_value in symbols:
		var symbol := str(symbol_value)
		var average: Variant = costs.get(symbol, null)
		if _valid_cost_number(average):
			costs[symbol] = source_float(float(average))


static func _valid_cost_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return false
	var raw := float(value)
	if raw == 0.0:
		return true
	if raw < 0.0 or raw > MAX_KNOWN_COST:
		return false
	var canonical := source_float(raw)
	return is_finite(canonical) and canonical >= MIN_KNOWN_COST and canonical <= MAX_KNOWN_COST


static func _known_cost(value: Variant) -> bool:
	if not _valid_cost_number(value):
		return false
	var canonical := source_float(float(value))
	return canonical >= MIN_KNOWN_COST and canonical <= MAX_KNOWN_COST


static func _costs_for_mutation(player: Dictionary, symbols: Array) -> Dictionary:
	var existing: Variant = player.get("stock_average_costs", null)
	if typeof(existing) == TYPE_DICTIONARY:
		return existing
	var costs := new_costs(symbols)
	var stocks: Variant = player.get("stocks", {})
	if typeof(stocks) == TYPE_DICTIONARY:
		for symbol in symbols:
			var stock_symbol := str(symbol)
			if int(stocks.get(stock_symbol, 0)) > 0:
				# The legacy position has no historical cost. Preserve that fact
				# while allowing a new symbol to become known independently.
				costs[stock_symbol] = null
	player["stock_average_costs"] = costs
	return costs


static func record_purchase(player: Dictionary, symbol: String, quantity: int, amount: int, symbols: Array) -> void:
	if quantity <= 0:
		return
	var stocks: Dictionary = player.get("stocks", {})
	var old_quantity := int(stocks.get(symbol, 0)) - quantity
	var costs_value: Variant = player.get("stock_average_costs", null)
	var has_costs := typeof(costs_value) == TYPE_DICTIONARY
	var costs: Dictionary = costs_value if has_costs else _costs_for_mutation(player, symbols)
	var old_cost: Variant = costs.get(symbol, null)
	var new_quantity := old_quantity + quantity
	if new_quantity <= 0:
		return
	if old_quantity <= 0:
		costs[symbol] = source_float(float(amount) / float(quantity))
	elif _known_cost(old_cost):
		# The source truncates the prior float32 average total before adding
		# the integer purchase amount, then stores the new average as float32.
		var old_total := int(float(old_cost) * float(old_quantity))
		costs[symbol] = source_float(float(old_total + amount) / float(new_quantity))
	else:
		# A legacy held position remains unknown after buying more shares.
		if not has_costs:
			costs = _costs_for_mutation(player, symbols)
		costs[symbol] = null
	player["stock_average_costs"] = costs


static func record_sale(player: Dictionary, symbol: String, quantity: int, symbols: Array) -> void:
	if quantity <= 0:
		return
	var stocks: Variant = player.get("stocks", {})
	if typeof(stocks) != TYPE_DICTIONARY:
		return
	var remaining := int(stocks.get(symbol, 0))
	if remaining > 0:
		return
	var costs_value: Variant = player.get("stock_average_costs", null)
	var costs: Dictionary = costs_value if typeof(costs_value) == TYPE_DICTIONARY else _costs_for_mutation(player, symbols)
	costs[symbol] = source_float(0.0)
	player["stock_average_costs"] = costs


static func clear_player(player: Dictionary, symbols: Array) -> void:
	var stocks: Dictionary = player.get("stocks", {})
	for symbol in symbols:
		stocks[str(symbol)] = 0
	player["stocks"] = stocks
	player["stock_average_costs"] = new_costs(symbols)


static func reconcile_implicit_holding(player: Dictionary, symbol: String, symbols: Array) -> void:
	# Existing source tests stage shares directly before owner recomputation.
	# There is no historical amount to recover from that mutation, so preserve
	# the position as explicitly unknown rather than inferring a current quote.
	var stocks: Variant = player.get("stocks", {})
	if typeof(stocks) != TYPE_DICTIONARY or int(stocks.get(symbol, 0)) <= 0:
		return
	var costs: Variant = player.get("stock_average_costs", null)
	if typeof(costs) != TYPE_DICTIONARY or not costs.has(symbol) or costs.get(symbol) == 0.0:
		var updated: Dictionary = _costs_for_mutation(player, symbols)
		if updated.get(symbol, null) == 0.0:
			updated[symbol] = null
		player["stock_average_costs"] = updated


static func validate_player(player: Dictionary, symbols: Array) -> Array:
	var errors: Array = []
	if not player.has("stock_average_costs"):
		# Saves produced before Issue #106 carry no historical accounting. The
		# held position remains legal but its cost is unavailable.
		return errors
	var value: Variant = player.get("stock_average_costs", null)
	if typeof(value) != TYPE_DICTIONARY:
		return ["player stock average costs invalid"]
	var costs: Dictionary = value
	if costs.size() != symbols.size():
		errors.append("player stock average cost symbols invalid")
	for symbol_value in symbols:
		var symbol := str(symbol_value)
		if not costs.has(symbol):
			errors.append("player stock average cost missing %s" % symbol)
			continue
		var average: Variant = costs.get(symbol)
		var stocks_value: Variant = player.get("stocks", {})
		var holding := int(stocks_value.get(symbol, 0)) if typeof(stocks_value) == TYPE_DICTIONARY else 0
		if average == null:
			if holding <= 0:
				errors.append("unknown stock average cost with no holding %s" % symbol)
			continue
		if not _valid_cost_number(average):
			errors.append("invalid stock average cost %s" % symbol)
		elif source_float(float(average)) == 0.0:
			if holding > 0:
				errors.append("positive stock holding has zero average cost %s" % symbol)
		elif holding <= 0:
			errors.append("zero stock holding has nonzero average cost %s" % symbol)
	for key in costs.keys():
		if not symbols.has(key):
			errors.append("unknown stock average cost symbol %s" % str(key))
	return errors
