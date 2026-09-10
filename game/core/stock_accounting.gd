extends RefCounted
## Source-compatible average purchase-cost bookkeeping for stock holdings.
##
## A missing metadata field is an explicitly unknown legacy position.  The
## accounting helpers never infer a cost for an already-held unknown position;
## they only create a known value when a new position is opened.

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
		if typeof(average) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(average)):
			costs[symbol] = source_float(float(average))


static func _known_cost(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


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
		var holding := int(player.get("stocks", {}).get(symbol, 0))
		if average == null:
			if holding <= 0:
				errors.append("unknown stock average cost with no holding %s" % symbol)
			continue
		if not _known_cost(average):
			errors.append("invalid stock average cost %s" % symbol)
		elif holding <= 0 and not is_zero_approx(float(average)):
			errors.append("zero stock holding has nonzero average cost %s" % symbol)
		elif holding > 0 and is_zero_approx(float(average)):
			errors.append("positive stock holding has zero average cost %s" % symbol)
	for key in costs.keys():
		if not symbols.has(key):
			errors.append("unknown stock average cost symbol %s" % str(key))
	return errors
