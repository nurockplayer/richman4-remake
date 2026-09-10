extends Control
class_name RichmanStockPanel

## First playable source-oriented stock presentation.
##
## The panel is a pure projection of a caller-owned runtime snapshot.  It
## never calls the simulation, saves, or random generator.  A host connects
## `trade_requested`, calls its existing choose_action entrypoint, then feeds
## the returned state to `apply_trade_result`.

signal trade_requested(action: String, symbol: String, quantity: int)
signal closed

const OriginalStockMarket = preload("res://game/core/original_stock_market.gd")
const OriginalVisuals = preload("res://game/platform/original_visuals.gd")
const QuantityPad = preload("res://game/ui/source_quantity_pad.gd")
const StockChart = preload("res://game/ui/stock_chart.gd")

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const TABLE_LEFT := 15.0
const TABLE_WIDTH := 609.0
const HEADER_Y := 48.0
const ROW_Y := 80.0
const ROW_HEIGHT := 32.0
const OVERVIEW_COLUMNS := [122.0, 103.0, 80.0, 98.0, 97.0, 109.0]
const TEXT_LIGHT := Color("#f7f3dc")
const TEXT_MUTED := Color("#bfd0bc")
const SOURCE_CYAN := Color("#52e6d1")
const LIMIT_RED := Color("#c81722", 0.62)
const LIMIT_GREEN := Color("#0aa92e", 0.62)

var snapshot: Dictionary = {}
var map_definition: Dictionary = {}

var _visuals
var _background: TextureRect
var _fallback_background: ColorRect
var _top_buttons: Dictionary = {}
var _deposit_label: Label
var _table_root: Control
var _detail_root: Control
var _detail_texture: TextureRect
var _status_label: Label
var _quantity_pad
var _detail_chart
var _symbols: Array = []
var _selected_symbol := ""
var _table_mode := "overview"
var _screen_mode := "overview"
var _pending_trade: Dictionary = {}


func _init() -> void:
	name = "StockPanel"
	custom_minimum_size = REFERENCE_SIZE
	size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_visuals = OriginalVisuals.new()

	_fallback_background = ColorRect.new()
	_fallback_background.name = "StockFallbackBackground"
	_fallback_background.color = Color("#26382b")
	_fallback_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fallback_background)

	_background = TextureRect.new()
	_background.name = "StockSourceBackground"
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_build_toolbar()
	_table_root = Control.new()
	_table_root.name = "StockTable"
	_table_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_table_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_table_root)

	_detail_root = Control.new()
	_detail_root.name = "StockDetail"
	_detail_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_root.visible = false
	add_child(_detail_root)
	_build_detail_shell()

	_status_label = Label.new()
	_status_label.name = "StockStatus"
	_status_label.position = Vector2(18.0, 463.0)
	_status_label.size = Vector2(604.0, 16.0)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", Color("#ffbdb0"))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_label)

	_quantity_pad = QuantityPad.new()
	_quantity_pad.position = Vector2(214.0, 145.0)
	_quantity_pad.name = "SourceQuantityPad"
	_quantity_pad.accepted.connect(_on_quantity_accepted)
	_quantity_pad.cancelled.connect(_on_quantity_cancelled)
	_quantity_pad.invalid_input.connect(func(message: String) -> void: _status_label.text = message)
	_quantity_pad.visible = false
	add_child(_quantity_pad)

	_refresh()


func set_snapshot(snapshot_value: Dictionary, map_definition_value: Dictionary = {}) -> void:
	snapshot = snapshot_value.duplicate(true)
	map_definition = map_definition_value.duplicate(true)
	_symbols = stock_symbols(snapshot, map_definition)
	if not _symbols.has(_selected_symbol):
		_selected_symbol = ""
	if _pending_trade.is_empty():
		_quantity_pad.visible = false
	_refresh()


func open_for(snapshot_value: Dictionary = {}, map_definition_value: Dictionary = {}, selected_symbol := "") -> void:
	if not snapshot_value.is_empty():
		set_snapshot(snapshot_value, map_definition_value)
	elif not map_definition_value.is_empty():
		map_definition = map_definition_value.duplicate(true)
	var normalized := selected_symbol.to_lower().strip_edges()
	if not normalized.is_empty() and _symbols.has(normalized):
		_selected_symbol = normalized
	show()
	_refresh()


func apply_trade_result(result: Dictionary, map_definition_value: Dictionary = {}) -> void:
	var ok := bool(result.get("ok", false))
	var returned_state: Variant = result.get("state", null)
	if returned_state is Dictionary:
		var definition := map_definition if map_definition_value.is_empty() else map_definition_value
		set_snapshot(returned_state, definition)
	if ok:
		_pending_trade = {}
		_quantity_pad.visible = false
		_status_label.text = str(result.get("message", "交易完成"))
	else:
		_status_label.text = str(result.get("message", "交易未完成"))
		if not _pending_trade.is_empty():
			_quantity_pad.visible = true
			_quantity_pad.grab_focus()


func handle_trade_result(result: Dictionary, map_definition_value: Dictionary = {}) -> void:
	apply_trade_result(result, map_definition_value)


func get_snapshot() -> Dictionary:
	return snapshot.duplicate(true)


func selected_symbol() -> String:
	return _selected_symbol


func current_screen() -> String:
	return _screen_mode


func current_table_mode() -> String:
	return _table_mode


func select_symbol(symbol_value: String) -> bool:
	var normalized := symbol_value.to_lower().strip_edges()
	if not _symbols.has(normalized):
		return false
	if _selected_symbol == normalized and _screen_mode != "detail":
		show_detail(normalized)
		return true
	_selected_symbol = normalized
	_refresh()
	return true


func clear_selection() -> void:
	_selected_symbol = ""
	_refresh()


func show_detail(symbol_value := "") -> bool:
	var normalized := symbol_value.to_lower().strip_edges() if not symbol_value.is_empty() else _selected_symbol
	if not _symbols.has(normalized):
		return false
	_selected_symbol = normalized
	_screen_mode = "detail"
	_quantity_pad.visible = false
	_pending_trade = {}
	_refresh()
	return true


func show_overview() -> void:
	_table_mode = "overview"
	_screen_mode = "overview"
	_quantity_pad.visible = false
	_pending_trade = {}
	_refresh()


func show_holdings() -> void:
	_table_mode = "holdings"
	_screen_mode = "holdings"
	_quantity_pad.visible = false
	_pending_trade = {}
	_refresh()


func close_panel() -> void:
	_quantity_pad.visible = false
	_pending_trade = {}
	hide()
	closed.emit()


func trade_limit(action: String, symbol_value := "") -> Dictionary:
	var normalized := symbol_value.to_lower().strip_edges() if not symbol_value.is_empty() else _selected_symbol
	return _trade_gate(action.to_lower().strip_edges(), normalized)


static func stock_symbols(snapshot_value: Dictionary, map_definition_value: Dictionary = {}) -> Array:
	var result: Array = []
	var market: Variant = snapshot_value.get("market", {})
	var rows: Variant = market.get("rows", {}) if market is Dictionary else {}
	if rows is Dictionary and not rows.is_empty():
		var keyed: Array = []
		for key in rows.keys():
			var row: Variant = rows[key]
			if row is Dictionary:
				keyed.append({"key": str(key).to_lower(), "index": int(row.get("index", 99999))})
		keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.index) < int(b.index))
		for value in keyed:
			if not result.has(value.key):
				result.append(value.key)
	if result.is_empty():
		var prices: Variant = market.get("prices", {}) if market is Dictionary else {}
		if prices is Dictionary:
			for key in prices.keys():
				var normalized := str(key).to_lower()
				if not result.has(normalized):
					result.append(normalized)
	if result.is_empty():
		var definition_rows: Variant = map_definition_value.get("stock_rows", [])
		if definition_rows is Array:
			for row in definition_rows:
				if row is Dictionary:
					var index := int(row.get("index", result.size()))
					result.append("s%02d" % (index + 1))
	return result


static func format_price(value: float) -> String:
	if not is_finite(value) or value <= 0.0:
		return "—"
	if value < 15.0:
		return "%.2f" % value
	if value < 150.0:
		return "%.1f" % value
	return "%.0f" % value


static func format_change(value: float, reference_price := 0.0) -> String:
	if not is_finite(value):
		return "—"
	var precision := 0
	if reference_price > 0.0 and reference_price < 15.0:
		precision = 2
	elif reference_price > 0.0 and reference_price < 150.0:
		precision = 1
	var formatted := ("%.*f" % [precision, value])
	if value > 0.0:
		formatted = "+" + formatted
	return formatted


static func history_statistics(history_value: Variant) -> Dictionary:
	return StockChart.history_statistics(history_value)


static func buy_limit(snapshot_value: Dictionary, symbol_value: String) -> int:
	var row := _snapshot_row(snapshot_value, symbol_value)
	var price := float(row.get("price", 0.0))
	if price <= 0.0 or not is_finite(price):
		return 0
	var player := _snapshot_current_player(snapshot_value)
	var deposit := int(player.get("deposit", player.get("cash", 0)))
	var affordable := floori(float(deposit) / price)
	var turn_supply := int(row.get("turn_supply", -1))
	var market_supply := int(row.get("market_supply", -1))
	var result := affordable
	if turn_supply >= 0:
		result = mini(result, turn_supply)
	if market_supply >= 0:
		result = mini(result, market_supply)
	return maxi(0, result)


static func sell_limit(snapshot_value: Dictionary, symbol_value: String) -> int:
	var player := _snapshot_current_player(snapshot_value)
	var holdings: Variant = player.get("stocks", {})
	return maxi(0, int(holdings.get(symbol_value.to_lower(), 0))) if holdings is Dictionary else 0


func _build_toolbar() -> void:
	_add_top_button("StockViewToggle", "持有股數表", Rect2(0, 0, 96, 40), _toggle_view)
	_add_top_button("StockBuy", "買進", Rect2(97, 0, 90, 40), func() -> void: _open_quantity_pad("buy_stock"))
	_add_top_button("StockSell", "賣出", Rect2(192, 0, 90, 40), func() -> void: _open_quantity_pad("sell_stock"))
	_add_top_button("StockCompanyInfo", "上市公司資訊", Rect2(287, 0, 96, 40), _toggle_detail_screen)
	_deposit_label = Label.new()
	_deposit_label.name = "StockDeposit"
	_deposit_label.position = Vector2(384, 2)
	_deposit_label.size = Vector2(166, 36)
	_deposit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deposit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_deposit_label.add_theme_font_size_override("font_size", 11)
	_deposit_label.add_theme_color_override("font_color", Color("#f7e9a7"))
	_deposit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_deposit_label)
	_add_top_button("StockExit", "EXIT", Rect2(552, 0, 88, 40), close_panel)


func _add_top_button(node_name: String, text_value: String, rect: Rect2, callback: Callable) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", TEXT_LIGHT)
	button.add_theme_stylebox_override("normal", _toolbar_style(Color(0.04, 0.14, 0.22, 0.20), Color("#8aa7b3")))
	button.add_theme_stylebox_override("hover", _toolbar_style(Color(0.29, 0.47, 0.57, 0.55), Color("#f5e6a2")))
	button.add_theme_stylebox_override("pressed", _toolbar_style(Color(0.05, 0.20, 0.29, 0.75), Color("#f5e6a2")))
	button.add_theme_stylebox_override("disabled", _toolbar_style(Color(0.05, 0.12, 0.16, 0.30), Color("#73828a")))
	button.pressed.connect(callback)
	_top_buttons[node_name] = button
	add_child(button)


func _toolbar_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(1)
	return style


func _build_detail_shell() -> void:
	_detail_texture = TextureRect.new()
	_detail_texture.name = "StockDetailSource"
	_detail_texture.position = Vector2(26, 52)
	_detail_texture.size = Vector2(587, 375)
	_detail_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_texture.stretch_mode = TextureRect.STRETCH_KEEP
	_detail_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_root.add_child(_detail_texture)
	_detail_chart = StockChart.new()
	_detail_chart.name = "StockDetailChart"
	_detail_chart.position = Vector2(38, 185)
	_detail_chart.size = Vector2(542, 180)
	_detail_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_root.add_child(_detail_chart)


func _refresh() -> void:
	if _background == null:
		return
	_set_source_background(0 if _screen_mode in ["overview", "detail"] else 1)
	_refresh_toolbar()
	_clear_table()
	_detail_root.visible = _screen_mode == "detail"
	_table_root.visible = _screen_mode != "detail"
	if _screen_mode == "detail":
		_refresh_detail()
	elif _table_mode == "holdings":
		_set_source_background(1)
		_refresh_holdings()
	else:
		_refresh_overview()
	_refresh_action_buttons()


func _set_source_background(chunk: int) -> void:
	var frame: Dictionary = _visuals.ui(_edition(), "Panel", 75, chunk)
	var texture: Texture2D = _visuals.texture(frame)
	_background.texture = texture
	_background.visible = texture != null


func _refresh_toolbar() -> void:
	var player := _snapshot_current_player(snapshot)
	var account := int(player.get("deposit", player.get("cash", 0)))
	_deposit_label.text = "存款 %s" % _format_money(account)
	var toggle: Button = _top_buttons.get("StockViewToggle")
	if toggle != null:
		toggle.text = "行情表" if _table_mode == "holdings" and _screen_mode != "detail" else "持有股數表"
	var detail_button: Button = _top_buttons.get("StockCompanyInfo")
	if detail_button != null:
		detail_button.text = "返回行情" if _screen_mode == "detail" else "上市公司資訊"


func _refresh_action_buttons() -> void:
	var buy: Button = _top_buttons.get("StockBuy")
	var sell: Button = _top_buttons.get("StockSell")
	var detail: Button = _top_buttons.get("StockCompanyInfo")
	var has_selection := _symbols.has(_selected_symbol)
	var buy_gate := _trade_gate("buy_stock", _selected_symbol) if has_selection else {"ok": false}
	var sell_gate := _trade_gate("sell_stock", _selected_symbol) if has_selection else {"ok": false}
	if buy != null:
		buy.disabled = not has_selection or not bool(buy_gate.get("ok", false))
	if sell != null:
		sell.disabled = not has_selection or not bool(sell_gate.get("ok", false))
	if detail != null:
		detail.disabled = not has_selection


func _clear_table() -> void:
	for child in _table_root.get_children():
		child.free()


func _refresh_overview() -> void:
	_add_headers(["股票名稱", "成交價", "漲跌", "交易量", "持有股數", "平均成本"], OVERVIEW_COLUMNS)
	for index in range(_symbols.size()):
		var symbol := str(_symbols[index])
		_add_overview_row(symbol, index)


func _add_overview_row(symbol: String, index: int) -> void:
	var row := _snapshot_row(snapshot, symbol)
	var player := _snapshot_current_player(snapshot)
	var holdings := _holding(player, symbol)
	var price := float(row.get("price", 0.0))
	var previous := float(row.get("previous_price", price))
	var difference := price - previous
	var limit_state := OriginalStockMarket.limit_state(previous, price) if previous > 0.0 and price > 0.0 else 0
	var holder_cost := _average_cost(player, symbol, holdings)
	var values := [
		_stock_display_name(row, symbol),
		"停牌" if int(row.get("suspension", 0)) > 0 else format_price(price),
		format_change(difference, previous),
		str(int(row.get("turn_supply", -1))) if row.has("turn_supply") else "—",
		str(holdings),
		holder_cost.get("text", ""),
	]
	var row_control := _make_row_control(symbol, index, limit_state)
	for column in range(values.size()):
		var label := _cell_label(str(values[column]), _overview_x(column), OVERVIEW_COLUMNS[column], TEXT_LIGHT)
		if column == 0 and int(row.get("company_id", 0)) > 0:
			label.add_theme_color_override("font_color", SOURCE_CYAN)
		if column == 1 and int(row.get("suspension", 0)) > 0:
			label.tooltip_text = "暫停交易 %d 天；成交價仍以目前 snapshot 顯示。" % int(row.get("suspension", 0))
		if column == 5 and not str(holder_cost.get("tooltip", "")).is_empty():
			label.tooltip_text = str(holder_cost.tooltip)
		row_control.add_child(label)
	_table_root.add_child(row_control)


func _refresh_holdings() -> void:
	var players: Array = _snapshot_players(snapshot)
	var player_count := clampi(players.size(), 2, 4)
	var widths: Array = [112.0]
	var remaining: float = TABLE_WIDTH - float(widths[0]) - 88.0 - 104.0
	for _index in range(player_count):
		widths.append(remaining / float(player_count))
	widths.append(88.0)
	widths.append(104.0)
	var headers: Array = ["股票名稱"]
	for index in range(player_count):
		headers.append(str(players[index].get("name", "玩家 %d" % (index + 1))))
	headers.append("公司資金")
	headers.append("累計盈餘")
	_add_headers(headers, widths)
	for index in range(_symbols.size()):
		var symbol := str(_symbols[index])
		var row := _snapshot_row(snapshot, symbol)
		var company := _company_for_symbol(snapshot, symbol, row)
		var values: Array = [_stock_display_name(row, symbol)]
		for player in players.slice(0, player_count):
			values.append(str(_holding(player, symbol)))
		values.append(str(company.get("treasury", "—")) if not company.is_empty() and company.has("treasury") else "—")
		values.append(str(company.get("cumulative_profit", "—")) if not company.is_empty() and company.has("cumulative_profit") else "—")
		var previous := float(row.get("previous_price", row.get("price", 0.0)))
		var price := float(row.get("price", 0.0))
		var state := OriginalStockMarket.limit_state(previous, price) if previous > 0.0 and price > 0.0 else 0
		var row_control := _make_row_control(symbol, index, state)
		var x := TABLE_LEFT
		for column in range(values.size()):
			var label := _cell_label(str(values[column]), x, widths[column], TEXT_LIGHT)
			if column == 0 and int(row.get("company_id", 0)) > 0:
				label.add_theme_color_override("font_color", SOURCE_CYAN)
			row_control.add_child(label)
			x += widths[column]
		_table_root.add_child(row_control)


func _add_headers(headers: Array, widths: Array) -> void:
	var x := TABLE_LEFT
	for index in range(headers.size()):
		var label := _cell_label(str(headers[index]), x, float(widths[index]), TEXT_LIGHT)
		label.name = "StockHeader_%d" % index
		label.add_theme_font_size_override("font_size", 11)
		label.position.y = HEADER_Y
		label.size.y = 25.0
		_table_root.add_child(label)
		x += float(widths[index])


func _cell_label(text_value: String, x: float, width: float, color: Color) -> Label:
	var label := Label.new()
	label.position = Vector2(x, 0)
	label.size = Vector2(width, ROW_HEIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = text_value
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _overview_x(column: int) -> float:
	var x := TABLE_LEFT
	for index in range(column):
		x += float(OVERVIEW_COLUMNS[index])
	return x


func _make_row_control(symbol: String, index: int, limit_state: int) -> Control:
	var row_control := Control.new()
	row_control.name = "StockRow_" + symbol
	row_control.position = Vector2(0, ROW_Y + ROW_HEIGHT * index)
	row_control.size = Vector2(REFERENCE_SIZE.x, ROW_HEIGHT)
	row_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := ColorRect.new()
	background.name = "StockLimitBackground"
	background.position = Vector2(TABLE_LEFT, 0)
	background.size = Vector2(TABLE_WIDTH, ROW_HEIGHT)
	background.color = LIMIT_RED if limit_state == 1 else LIMIT_GREEN if limit_state == 3 else Color(0, 0, 0, 0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_control.add_child(background)
	if _selected_symbol == symbol:
		var highlight := ColorRect.new()
		highlight.name = "StockSelectionHighlight"
		highlight.position = Vector2(TABLE_LEFT, 1)
		highlight.size = Vector2(TABLE_WIDTH, ROW_HEIGHT - 2)
		highlight.color = Color("#f5e28a", 0.25)
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_control.add_child(highlight)
	var hit := Button.new()
	hit.name = "StockSelect_" + symbol
	hit.position = Vector2(TABLE_LEFT, 0)
	hit.size = Vector2(TABLE_WIDTH, ROW_HEIGHT)
	hit.flat = true
	hit.focus_mode = Control.FOCUS_ALL
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.add_theme_stylebox_override("normal", _transparent_style())
	hit.add_theme_stylebox_override("hover", _hover_row_style())
	hit.add_theme_stylebox_override("pressed", _transparent_style())
	hit.pressed.connect(func() -> void: select_symbol(symbol))
	row_control.add_child(hit)
	return row_control


func _transparent_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	return style


func _hover_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#d6d89b", 0.18)
	style.border_color = Color("#d6d89b", 0.55)
	style.set_border_width_all(1)
	return style


func _refresh_detail() -> void:
	var row := _snapshot_row(snapshot, _selected_symbol)
	var company := _company_for_symbol(snapshot, _selected_symbol, row)
	var history: Variant = snapshot.get("market", {}).get("history", {}).get(_selected_symbol, [])
	_detail_texture.texture = _visuals.texture(_visuals.ui(_edition(), "Panel", 75, 2))
	_detail_texture.visible = _detail_texture.texture != null
	_detail_chart.configure(history, _holding(_snapshot_current_player(snapshot), _selected_symbol), 10000)
	_clear_detail_labels()
	var title := _detail_label("DetailCompanyName", _stock_display_name(row, _selected_symbol), Vector2(235, 66), Vector2(170, 30), TEXT_LIGHT, 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_root.add_child(title)
	if not company.is_empty():
		var image_frame: Dictionary = _visuals.ui(_edition(), "Panel", 75, 3 + int(row.get("index", 0)))
		var image_texture: Texture2D = _visuals.texture(image_frame)
		if image_texture != null:
			var image := TextureRect.new()
			image.name = "DetailCompanyImage"
			image.position = Vector2(50, 107)
			image.size = Vector2(80, 112)
			image.texture = image_texture
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP
			image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_detail_root.add_child(image)

	var stats := StockChart.history_statistics(history)
	var monthly := str(int(company.get("monthly_profit", 0))) if not company.is_empty() and company.has("monthly_profit") else "—"
	var average := _average_earnings(company)
	var owner := _owner_name(company)
	var price := float(row.get("price", 0.0))
	var previous := float(row.get("previous_price", price))
	var difference := price - previous
	var percent := difference / previous * 100.0 if previous != 0.0 else NAN
	var left_fields := [
		["本月盈餘", monthly],
		["平均盈餘", average],
		["經營者", owner],
	]
	for index in range(left_fields.size()):
		_detail_root.add_child(_detail_label("DetailLeft%d" % index, "%s\n%s" % [left_fields[index][0], left_fields[index][1]], Vector2(132, 103 + index * 36), Vector2(145, 34), TEXT_LIGHT, 11))
	var right_fields := [
		["成交價", format_price(price)],
		["交易量", str(int(row.get("turn_supply", -1))) if row.has("turn_supply") else "—"],
		["漲跌", format_change(difference, previous)],
		["漲跌幅", "—" if not is_finite(percent) else "%+.2f%%" % percent],
		["週均價", _stat_text(stats.get("weekly_mean", null))],
		["月均價", _stat_text(stats.get("monthly_mean", null))],
		["歷史高價", _stat_text(stats.get("historical_high", null))],
		["歷史低價", _stat_text(stats.get("historical_low", null))],
	]
	for index in range(right_fields.size()):
		_detail_root.add_child(_detail_label("DetailRight%d" % index, "%s\n%s" % [right_fields[index][0], right_fields[index][1]], Vector2(399, 99 + index * 29), Vector2(150, 28), TEXT_LIGHT, 10))
	var pie_title := _detail_label("DetailPieTitle", "持股比例", Vector2(440, 407), Vector2(130, 18), TEXT_LIGHT, 10)
	pie_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_root.add_child(pie_title)
	if int(row.get("suspension", 0)) > 0:
		_status_label.text = "暫停交易 %d 天" % int(row.get("suspension", 0))


func _clear_detail_labels() -> void:
	for child in _detail_root.get_children():
		if child == _detail_texture or child == _detail_chart:
			continue
		child.free()


func _detail_label(node_name: String, text_value: String, position_value: Vector2, size_value: Vector2, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = position_value
	label.size = size_value
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _toggle_view() -> void:
	if _screen_mode == "detail":
		show_overview()
	elif _table_mode == "overview":
		show_holdings()
	else:
		show_overview()


func _toggle_detail_screen() -> void:
	if _screen_mode == "detail":
		show_overview()
	else:
		show_detail()


func _open_quantity_pad(action: String) -> void:
	if _screen_mode == "detail":
		_screen_mode = "overview"
		_table_mode = "overview"
		_refresh()
	if _selected_symbol.is_empty():
		_status_label.text = "請先選擇股票"
		return
	var gate := _trade_gate(action, _selected_symbol)
	var row := _snapshot_row(snapshot, _selected_symbol)
	var maximum_value := int(gate.get("maximum", 0))
	_quantity_pad.configure(action, _selected_symbol, float(row.get("price", 0.0)), maximum_value, int(_snapshot_current_player(snapshot).get("deposit", 0)))
	_quantity_pad.set_available(bool(gate.get("ok", false)), str(gate.get("error", "")))
	_pending_trade = {"action": action, "symbol": _selected_symbol}
	_quantity_pad.visible = true
	_quantity_pad.grab_focus()


func _on_quantity_accepted(quantity: int) -> void:
	if _pending_trade.is_empty():
		return
	var action := str(_pending_trade.get("action", ""))
	var symbol := str(_pending_trade.get("symbol", ""))
	var gate := _trade_gate(action, symbol)
	if not bool(gate.get("ok", false)) or quantity <= 0 or quantity > int(gate.get("maximum", 0)):
		_status_label.text = str(gate.get("error", "交易股數無效"))
		return
	trade_requested.emit(action, symbol, quantity)


func _on_quantity_cancelled() -> void:
	_pending_trade = {}
	_quantity_pad.visible = false
	_status_label.text = ""


func _trade_gate(action: String, symbol: String) -> Dictionary:
	if not _symbols.has(symbol):
		return {"ok": false, "maximum": 0, "error": "股票不存在"}
	var player := _snapshot_current_player(snapshot)
	if player.is_empty() or not bool(player.get("alive", true)) or bool(player.get("is_ai", false)):
		return {"ok": false, "maximum": 0, "error": "目前玩家無法交易"}
	var market: Dictionary = snapshot.get("market", {})
	if (market.has("open") and not bool(market.get("open", false))) or int(market.get("closed_days", 0)) > 0:
		return {"ok": false, "maximum": 0, "error": "本日休市"}
	if action not in ["buy_stock", "sell_stock"]:
		return {"ok": false, "maximum": 0, "error": "目前不是可交易行動"}
	var row := _snapshot_row(snapshot, symbol)
	if row.is_empty():
		return {"ok": false, "maximum": 0, "error": "股票資料不存在"}
	if int(row.get("suspension", 0)) > 0:
		return {"ok": false, "maximum": 0, "error": "這檔股票暫停交易"}
	var previous := float(row.get("previous_price", 0.0))
	var price := float(row.get("price", 0.0))
	var limit_state := OriginalStockMarket.limit_state(previous, price) if previous > 0.0 and price > 0.0 else 0
	if action == "buy_stock" and limit_state == 1:
		return {"ok": false, "maximum": 0, "error": "漲停無法買入"}
	if action == "sell_stock" and limit_state == 3:
		return {"ok": false, "maximum": 0, "error": "跌停無法賣出"}
	var options: Variant = snapshot.get("action_options", null)
	if options is Array and not options.is_empty() and not options.has(action):
		return {"ok": false, "maximum": 0, "error": "目前不是可交易行動階段"}
	var maximum_value := buy_limit(snapshot, symbol) if action == "buy_stock" else sell_limit(snapshot, symbol)
	if maximum_value <= 0:
		return {"ok": false, "maximum": 0, "error": "目前沒有可交易股數"}
	return {"ok": true, "maximum": maximum_value, "error": ""}


static func _snapshot_row(snapshot_value: Dictionary, symbol_value: String) -> Dictionary:
	var market: Variant = snapshot_value.get("market", {})
	if not market is Dictionary:
		return {}
	var rows: Variant = market.get("rows", {})
	if rows is Dictionary:
		var value: Variant = rows.get(symbol_value.to_lower(), rows.get(StringName(symbol_value.to_lower()), {}))
		if value is Dictionary:
			return value
	var prices: Variant = market.get("prices", {})
	if prices is Dictionary and prices.has(symbol_value.to_lower()):
		return {"price": float(prices[symbol_value.to_lower()]), "previous_price": float(prices[symbol_value.to_lower()])}
	return {}


static func _snapshot_current_player(snapshot_value: Dictionary) -> Dictionary:
	var players: Variant = snapshot_value.get("players", [])
	if not players is Array or players.is_empty():
		return {}
	var index := int(snapshot_value.get("current_player", 0))
	return players[index].duplicate(true) if index >= 0 and index < players.size() and players[index] is Dictionary else {}


static func _snapshot_players(snapshot_value: Dictionary) -> Array:
	var players: Variant = snapshot_value.get("players", [])
	return players if players is Array else []


func _snapshot_row_local(symbol: String) -> Dictionary:
	return _snapshot_row(snapshot, symbol)


func _stock_display_name(row: Dictionary, symbol: String) -> String:
	var name_value: Variant = row.get("display_name", row.get("name", ""))
	return str(name_value) if name_value is String and not str(name_value).is_empty() else symbol


func _company_for_symbol(snapshot_value: Dictionary, symbol: String, row: Dictionary) -> Dictionary:
	var company_id := int(row.get("company_id", 0))
	if company_id <= 0:
		return {}
	var companies: Variant = snapshot_value.get("companies", [])
	if companies is Array:
		for company in companies:
			if company is Dictionary and int(company.get("id", -1)) == company_id:
				return company.duplicate(true)
	var definition_companies: Variant = map_definition.get("companies", [])
	if definition_companies is Array:
		for company in definition_companies:
			if company is Dictionary and int(company.get("id", -1)) == company_id:
				return company.duplicate(true)
	return {}


func _average_cost(player: Dictionary, symbol: String, holdings: int) -> Dictionary:
	if holdings <= 0:
		return {"text": "", "tooltip": ""}
	var costs: Variant = player.get("stock_average_costs", null)
	if not costs is Dictionary:
		return {"text": "—", "tooltip": "此持股沒有可用的歷史成本資料。"}
	var value: Variant = costs.get(symbol, null)
	if value is int or value is float:
		var cost := float(value)
		if is_finite(cost) and cost > 0.0:
			return {"text": format_price(cost), "tooltip": ""}
	return {"text": "—", "tooltip": "此持股沒有可用的歷史成本資料。"}


func _average_earnings(company: Dictionary) -> String:
	if company.is_empty() or not company.has("cumulative_profit"):
		return "—"
	var cumulative := int(company.get("cumulative_profit", 0))
	var months := int(snapshot.get("company_months", 0))
	return str(cumulative if months <= 0 else int(float(cumulative) / float(months)))


func _owner_name(company: Dictionary) -> String:
	if company.is_empty():
		return "—"
	var owner := int(company.get("owner", -1))
	if owner < 0:
		return "無"
	var players := _snapshot_players(snapshot)
	if owner >= 0 and owner < players.size() and players[owner] is Dictionary:
		return str(players[owner].get("name", "玩家 %d" % (owner + 1)))
	return "—"


func _stat_text(value: Variant) -> String:
	return "—" if value == null else format_price(float(value))


func _holding(player: Dictionary, symbol: String) -> int:
	var holdings: Variant = player.get("stocks", {})
	return int(holdings.get(symbol, 0)) if holdings is Dictionary else 0


func _format_money(value: int) -> String:
	var sign := "-" if value < 0 else ""
	var absolute := absi(value)
	var raw := str(absolute)
	var grouped := ""
	while raw.length() > 3:
		grouped = "," + raw.right(3) + grouped
		raw = raw.left(raw.length() - 3)
	return sign + raw + grouped


func _edition() -> String:
	var source: Variant = map_definition.get("source", {})
	if not source is Dictionary or source.is_empty():
		source = snapshot.get("map_source", {})
	var edition := str(source.get("edition", "Game")) if source is Dictionary else "Game"
	return edition if edition in ["Game", "MultiverseJourney"] else "Game"


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if _quantity_pad.visible:
			_quantity_pad.cancel()
		else:
			close_panel()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var global_point: Vector2 = get_global_transform_with_canvas() * event.position
	if _quantity_pad.visible and not _quantity_pad.get_global_rect().has_point(global_point):
		_quantity_pad.cancel()
		accept_event()
