extends RefCounted
## Source-backed twelve-stock rules. Random values come from the saved runtime
## generator; the original's wall-clock reseeding cannot be replayed.
const COUNT := 12
const TOTAL_SHARES := 10000
const HISTORY_LIMIT := 144

static func source_float(value: float) -> float:
	return float(PackedFloat32Array([value])[0])

static func normalize_numbers(market: Dictionary) -> void:
	for stock_symbol in symbols():
		var row: Dictionary = market.rows[stock_symbol]
		for field in ["volatility", "momentum", "shock"]:
			if _number(row.get(field), -10000.0, 10000.0): row[field] = source_float(float(row[field]))
		for field in ["base_price", "previous_price", "price"]:
			if _number(row.get(field), 1.0, 9999.0): row[field] = snappedf(float(row[field]), 0.01)
		market.prices[stock_symbol] = float(row.price)
		var history: Array = market.history[stock_symbol]
		for index in range(history.size()): history[index] = snappedf(float(history[index]), 0.01)

static func normalize_price_events(value: Variant) -> void:
	if typeof(value) == TYPE_ARRAY:
		for item in value: normalize_price_events(item)
	elif typeof(value) == TYPE_DICTIONARY:
		for key in value:
			if key == "price" and typeof(value[key]) in [TYPE_INT, TYPE_FLOAT]:
				value[key] = snappedf(float(value[key]), 0.01)
			elif key == "prices" and typeof(value[key]) == TYPE_DICTIONARY:
				for stock_symbol in value[key]:
					if typeof(value[key][stock_symbol]) in [TYPE_INT, TYPE_FLOAT]:
						value[key][stock_symbol] = snappedf(float(value[key][stock_symbol]), 0.01)
			else: normalize_price_events(value[key])

static func symbol(index: int) -> String:
	return "s%02d" % (index + 1)

static func symbols() -> Array:
	var result: Array = []
	for index in range(COUNT):
		result.append(symbol(index))
	return result

static func quote(price: float, quantity: int) -> int:
	return int(price * quantity)

static func adjusted_rate(previous: float, base_price: float, company_price: float, rate: float) -> float:
	var anchor := company_price if company_price > 0.0 else base_price
	var upper := 3.0 if company_price > 0.0 else 8.0
	var lower := 0.85 if company_price > 0.0 else 0.5
	if previous > upper * anchor:
		rate *= 0.5 if rate > 0.0 else 2.0
	elif previous < lower * anchor:
		rate *= 2.0 if rate > 0.0 else 0.5
	return clampf(rate, -10.0, 10.0)

static func next_price(previous: float, rate: float) -> float:
	var candidate := previous * (100.0 + rate) / 100.0
	var tick := 0.01 if candidate < 5.0 else 0.05 if candidate < 15.0 else 0.1 if candidate < 50.0 else 0.5 if candidate < 150.0 else 1.0
	var change := (candidate - previous) / tick
	# Round only the price change toward zero, then retain cent precision.
	var price: float = previous + (floor(change) if change >= 0.0 else ceil(change)) * tick
	return snappedf(clampf(price, 1.0, 9999.0), 0.01)

static func reset_turn_supply(market: Dictionary, rng: RandomNumberGenerator) -> void:
	for stock_symbol in symbols():
		var row: Dictionary = market.rows[stock_symbol]
		var supply := int(row.market_supply)
		row.turn_supply = supply if supply <= 1000 else int(supply * (1000 + rng.randi_range(0, 1999)) / 10000)

static func create(rows: Array) -> Dictionary:
	var market := {"prices": {}, "open": true, "trends": {}, "rows": {}, "history": {}, "history_index": 0, "closed_days": 0, "index": 0}
	var total := 0.0
	for source in rows:
		var stock_symbol := symbol(int(source.index))
		var row: Dictionary = source.duplicate(true)
		market.rows[stock_symbol] = row
		market.prices[stock_symbol] = float(row.price)
		market.history[stock_symbol] = [float(row.price)]
		total += float(row.price)
	market.index = int(total * 10.0)
	normalize_numbers(market)
	return market

static func decrement_status(market: Dictionary) -> void:
	var closure := int(market.closed_days)
	market.closed_days = 0 if closure == 128 else 128 if closure == 1 else maxi(0, closure - 1)
	for row in market.rows.values():
		row.suspension = maxi(0, int(row.suspension)-1)
		var high := int(row.event) & 0xf0
		var low := int(row.event) & 0x0f
		row.event = maxi(0, high-0x10) | maxi(0, low-1)

static func apply_card(market: Dictionary, stock_symbol: String, rising: bool) -> void:
	var row: Dictionary = market.rows[stock_symbol]
	row.event = 0x20 if rising else 2
	row.momentum = 10.0 if rising else -10.0
	row.price = next_price(float(row.previous_price), float(row.momentum))
	market.prices[stock_symbol] = float(row.price)
	var history: Array = market.history[stock_symbol]
	history[history.size()-1] = float(row.price)
	var total := 0.0
	for price in market.prices.values(): total += float(price)
	market.index = int(total*10.0)

static func tick(market: Dictionary, company_prices: Dictionary, rng: RandomNumberGenerator) -> void:
	if not bool(market.open):
		return
	var global_shock := float(rng.randi_range(0, 32767) - 16384) / 4097.0
	var total := 0.0
	for stock_symbol in symbols():
		var row: Dictionary = market.rows[stock_symbol]
		var previous := float(row.price)
		row.previous_price = previous
		var rate := 0.0
		if int(row.suspension) != 0:
			rate = 0.0
		elif int(row.event) != 0:
			rate = 10.0 if (int(row.event) & 0xf0) != 0 else -10.0
		else:
			row.shock = source_float(float(rng.randi_range(0, 32767) - 16384) / 1171.0)
			rate = float(row.momentum) + global_shock + float(row.shock) * float(row.volatility)
			rate = adjusted_rate(previous, float(row.base_price), float(company_prices.get(int(row.company_id), 0.0)), rate)
		row.momentum = source_float(clampf(rate, -10.0, 10.0))
		row.price = next_price(previous, float(row.momentum))
		market.prices[stock_symbol] = float(row.price)
		var history: Array = market.history[stock_symbol]
		history.append(float(row.price))
		if history.size() > HISTORY_LIMIT:
			history.pop_front()
		total += float(row.price)
	market.history_index = (int(market.history_index) + 1) % HISTORY_LIMIT
	market.index = int(total * 10.0)

static func _integer(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and floor(float(value))==float(value) and float(value)>=low and float(value)<=high

static func _number(value: Variant, low: float, high: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func validate(market: Variant, players: Variant, companies: Variant) -> Array:
	var errors: Array = []
	if typeof(market)!=TYPE_DICTIONARY:
		return ["invalid company market"]
	for key in ["prices","rows","history","trends"]:
		if typeof(market.get(key))!=TYPE_DICTIONARY:
			errors.append("invalid company market %s" % key)
	if not errors.is_empty(): return errors
	if not market.trends.is_empty(): errors.append("company market uses packed source events")
	if typeof(market.get("open"))!=TYPE_BOOL or not _integer(market.get("closed_days"),0,255):
		errors.append("invalid company market status")
	if not _integer(market.get("history_index"),0,HISTORY_LIMIT-1) or not _integer(market.get("index"),0,COUNT*99990):
		errors.append("invalid company market index")
	if market.rows.size()!=COUNT or market.prices.size()!=COUNT or market.history.size()!=COUNT:
		errors.append("company market requires twelve stocks")
	if typeof(players)!=TYPE_ARRAY or typeof(companies)!=TYPE_ARRAY:
		return errors+["invalid company market participants"]
	var companies_by_id: Dictionary = {}
	for company in companies:
		if typeof(company)!=TYPE_DICTIONARY or not _integer(company.get("id"),1,1999):
			errors.append("invalid company record")
			continue
		if companies_by_id.has(int(company.id)): errors.append("duplicate company id")
		companies_by_id[int(company.id)]=company
	for company in companies:
		if typeof(company) != TYPE_DICTIONARY or not _integer(company.get("stock_index"),0,COUNT-1) or not _integer(company.get("id"),1,1999): continue
		var linked_row: Variant = market.rows.get(symbol(int(company.stock_index)))
		if typeof(linked_row) != TYPE_DICTIONARY or not _integer(linked_row.get("company_id"), int(company.id), int(company.id)):
			errors.append("company reverse stock link mismatch")
	var total := 0.0
	for stock_index in range(COUNT):
		var stock_symbol := symbol(stock_index)
		var row: Variant = market.rows.get(stock_symbol)
		if typeof(row)!=TYPE_DICTIONARY:
			errors.append("missing company stock %s" % stock_symbol)
			continue
		if not _integer(row.get("index"),stock_index,stock_index) or typeof(row.get("name"))!=TYPE_STRING or row.get("name","").is_empty() or row.get("name","").length()>128:
			errors.append("invalid company stock identity %s" % stock_symbol)
		for field in ["base_price","previous_price","price"]:
			if _number(row.get(field),1.0,9999.0) and absf(float(row[field])-snappedf(float(row[field]),0.01))>0.000000001: errors.append("non-cent company stock price")
			if not _number(row.get(field),1.0,9999.0): errors.append("invalid company stock %s" % field)
		if not _number(row.get("volatility"),0.0,1000.0) or not _number(row.get("momentum"),-10.0,10.0) or not _number(row.get("shock"),-100.0,100.0):
			errors.append("invalid company stock dynamics")
		for field in ["suspension","event"]:
			if not _integer(row.get(field),0,255): errors.append("invalid company stock status")
		var supply_valid := _integer(row.get("market_supply"),0,TOTAL_SHARES)
		var turn_valid := _integer(row.get("turn_supply"),0,TOTAL_SHARES)
		if not supply_valid or not turn_valid or (supply_valid and turn_valid and int(row.turn_supply)>int(row.market_supply)):
			errors.append("invalid company stock supply")
		if not _number(row.get("price"),1.0,9999.0) or not _number(market.prices.get(stock_symbol),1.0,9999.0) or float(market.prices[stock_symbol])!=float(row.price):
			errors.append("company stock price mismatch")
		if _number(row.get("price"),1.0,9999.0): total+=float(row.price)
		var history: Variant = market.history.get(stock_symbol)
		if typeof(history)!=TYPE_ARRAY or history.is_empty() or history.size()>HISTORY_LIMIT:
			errors.append("invalid company stock history")
		else:
			for price in history:
				if not _number(price,1.0,9999.0): errors.append("invalid company stock history price")
				elif absf(float(price)-snappedf(float(price),0.01))>0.000000001: errors.append("non-cent company stock history price")
			if not _number(history.back(),1.0,9999.0) or not _number(row.get("price"),1.0,9999.0) or float(history.back())!=float(row.price): errors.append("company stock history tail mismatch")
		var treasury := 0
		if not _integer(row.get("company_id"),0,1999):
			errors.append("invalid stock company link")
		elif int(row.company_id)>0:
			var company: Variant = companies_by_id.get(int(row.company_id))
			if typeof(company)!=TYPE_DICTIONARY or not _integer(company.get("stock_index"),stock_index,stock_index):
				errors.append("stock company link mismatch")
			elif not _integer(company.get("treasury"),0,TOTAL_SHARES):
				errors.append("invalid company treasury")
			else:
				treasury=int(company.treasury)
		var holdings := 0
		for player in players:
			if typeof(player)!=TYPE_DICTIONARY or typeof(player.get("stocks"))!=TYPE_DICTIONARY:
				errors.append("invalid company stock holder")
				continue
			var shares: Variant = player.stocks.get(stock_symbol)
			if not _integer(shares,0,TOTAL_SHARES):
				errors.append("invalid company stock holding")
			else:
				holdings+=int(shares)
				if typeof(player.get("alive"))==TYPE_BOOL and not player.alive and int(shares)!=0:
					errors.append("bankrupt player retains company stocks")
		if supply_valid and int(row.market_supply)+treasury+holdings!=TOTAL_SHARES:
			errors.append("company stock conservation mismatch %s" % stock_symbol)
	if _integer(market.get("index"),0,COUNT*99990) and int(market.index)!=int(total*10.0):
		errors.append("company market total mismatch")
	return errors
