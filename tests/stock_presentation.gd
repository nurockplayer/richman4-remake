extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")
const StockPanel = preload("res://game/ui/stock_panel.gd")
const QuantityPad = preload("res://game/ui/source_quantity_pad.gd")
const Chart = preload("res://game/ui/stock_chart.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func make_game() -> Object:
	var game := Game.new_game_on_board(90101, 4, Fixture.definition(), {
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	expect(game != null, "stock presentation fixture creates a source game")
	if game == null:
		return null
	game.state.god_objects = []
	game.state.phase = "await_action"
	game.state.current_player = 0
	game.state.weekday = 1
	game.state.market.open = true
	game.state.players[0].deposit = 1000
	game.state.players[0].stocks.s01 = 2
	game.state.players[0].stock_average_costs.s01 = 74.5
	game.state.players[1].stocks.s01 = 3
	game.state.players[2].stocks.s01 = 4
	game.state.players[3].stocks.s01 = 5
	for index in range(12):
		var symbol := "s%02d" % (index + 1)
		var row: Dictionary = game.state.market.rows[symbol]
		row.turn_supply = 120 + index
		row.market_supply = 5000 if index == 0 else 10000
		row.price = 12.5 + float(index) * 20.0
		row.previous_price = row.price - 1.0
		game.state.market.prices[symbol] = row.price
		game.state.market.history[symbol] = []
		for value in range(1, 145):
			game.state.market.history[symbol].append(float(value + index))
		game.state.market.history[symbol][143] = row.price
	game._sync_state()
	game._set_action_options(0)
	return game


func run() -> void:
	var game := make_game()
	if game == null:
		quit(1)
		return
	var snapshot: Dictionary = game.get_snapshot()
	var panel := StockPanel.new()
	root.add_child(panel)
	await process_frame
	panel.set_snapshot(snapshot, Fixture.definition())
	await process_frame

	expect(panel.custom_minimum_size == Vector2(640, 480), "stock panel keeps 640x480 reference container")
	expect(StockPanel.stock_symbols(snapshot, Fixture.definition()).size() == 12, "source snapshot exposes twelve ordered stocks")
	expect(panel.find_child("StockRow_s12", true, false) != null, "overview renders twelfth row")
	expect(panel.find_child("StockHeader_5", true, false) != null, "overview renders six column headers")
	expect(panel.find_child("StockRow_s01", true, false).find_child("StockSelect_s01", true, false) != null, "rows have real selectable controls")
	expect(panel.find_child("StockDeposit", true, false).text.contains("1,000"), "deposit is read-only projection")
	expect(panel.find_child("StockRow_s01", true, false).get_children().size() > 2, "row contains projected source values")
	var original_snapshot: Dictionary = snapshot.duplicate(true)
	panel.set_snapshot(snapshot, Fixture.definition())
	snapshot.market.rows.s01.price = 9999.0
	expect(panel.get_snapshot().market.rows.s01.price != 9999.0, "panel deep copies caller snapshot")
	expect(snapshot.market.rows.s01.price == 9999.0 and original_snapshot.market.rows.s01.price != 9999.0, "caller snapshot remains independently mutable")
	panel.set_snapshot(original_snapshot, Fixture.definition())

	expect(StockPanel.format_price(12.5) == "12.50", "source price under 15 uses two decimals")
	expect(StockPanel.format_price(33.4) == "33.4", "source price under 150 uses one decimal")
	expect(StockPanel.format_price(388.0) == "388", "source price at 150 or above uses integer format")
	expect(StockPanel.buy_limit(original_snapshot, "s01") == 80, "buy limit combines deposit floor, turn supply and market supply")
	expect(StockPanel.sell_limit(original_snapshot, "s01") == 2, "sell limit uses current player holdings")
	var floor_snapshot: Dictionary = original_snapshot.duplicate(true)
	floor_snapshot.players[0].deposit = 100
	floor_snapshot.market.rows.s01.price = 33.4
	floor_snapshot.market.prices.s01 = 33.4
	expect(StockPanel.buy_limit(floor_snapshot, "s01") == 2, "buy limit floors deposit affordability at a fractional source price")

	panel.select_symbol("s01")
	expect(panel.selected_symbol() == "s01", "first selection stays on selected stock")
	var buy_button: Button = panel.find_child("StockBuy", true, false)
	var sell_button: Button = panel.find_child("StockSell", true, false)
	expect(buy_button != null and not buy_button.disabled, "legal selected buy is enabled")
	expect(sell_button != null and not sell_button.disabled, "legal selected sell is enabled")
	panel.clear_selection()
	var row_button: Button = panel.find_child("StockSelect_s01", true, false)
	expect(row_button != null, "stock row exposes its source click control")
	if row_button != null:
		row_button.pressed.emit()
		await process_frame
	expect(panel.selected_symbol() == "s01" and panel.current_screen() == "overview", "actual row button click refreshes selection safely")
	var guard_panel := StockPanel.new()
	root.add_child(guard_panel)
	await process_frame
	guard_panel.set_snapshot(original_snapshot, Fixture.definition())
	guard_panel.select_symbol("s01")
	var guard_buy: Button = guard_panel.find_child("StockBuy", true, false)
	guard_buy.pressed.emit()
	await process_frame
	var guarded_requests: Array = []
	guard_panel.trade_requested.connect(func(action: String, symbol: String, quantity: int) -> void: guarded_requests.append([action, symbol, quantity]))
	for blocked_case in [
		{"label": "empty action options", "patch": {"action_options": []}},
		{"label": "game over", "patch": {"phase": "game_over", "action_options": ["buy_stock", "sell_stock"]}},
		{"label": "pending finance", "patch": {"pending_finance": {"kind": "tax"}, "action_options": ["buy_stock", "sell_stock"]}},
	]:
		var blocked_snapshot: Dictionary = original_snapshot.duplicate(true)
		for key in blocked_case.patch:
			blocked_snapshot[key] = blocked_case.patch[key]
		guard_panel.set_snapshot(blocked_snapshot, Fixture.definition())
		guard_panel._on_quantity_accepted(1)
		expect(guard_buy.disabled and guarded_requests.is_empty(), "%s blocks the button and trade signal" % blocked_case.label)
	guard_panel.queue_free()
	await process_frame

	var upper_snapshot: Dictionary = original_snapshot.duplicate(true)
	upper_snapshot.market.rows.s01.previous_price = 10.0
	upper_snapshot.market.rows.s01.price = 12.5
	upper_snapshot.market.prices.s01 = 12.5
	panel.set_snapshot(upper_snapshot, Fixture.definition())
	panel.clear_selection()
	panel.select_symbol("s01")
	var upper_background: ColorRect = panel.find_child("StockRow_s01", true, false).find_child("StockLimitBackground", true, false)
	expect(upper_background.visible and upper_background.position == Vector2(137, 0) and upper_background.size == Vector2(103, 32), "upper-limit tint is restricted to the source price cell")
	expect(not bool(panel.trade_limit("buy_stock").get("ok", false)), "upper-limit stock blocks buying")
	expect(bool(panel.trade_limit("sell_stock").get("ok", false)), "upper-limit stock keeps selling available")
	var lower_snapshot: Dictionary = upper_snapshot.duplicate(true)
	lower_snapshot.market.rows.s01.previous_price = 10.0
	lower_snapshot.market.rows.s01.price = 8.0
	lower_snapshot.market.prices.s01 = 8.0
	panel.set_snapshot(lower_snapshot, Fixture.definition())
	panel.clear_selection()
	panel.select_symbol("s01")
	var lower_background: ColorRect = panel.find_child("StockRow_s01", true, false).find_child("StockLimitBackground", true, false)
	expect(lower_background.visible and lower_background.position == Vector2(137, 0) and lower_background.size == Vector2(103, 32), "lower-limit tint is restricted to the source price cell")
	expect(bool(panel.trade_limit("buy_stock").get("ok", false)), "lower-limit stock keeps buying available")
	expect(not bool(panel.trade_limit("sell_stock").get("ok", false)), "lower-limit stock blocks selling")
	panel.set_snapshot(original_snapshot, Fixture.definition())
	panel.clear_selection()
	panel.select_symbol("s01")
	panel.show_holdings()
	expect(panel.current_screen() == "holdings" and panel.find_child("StockHeader_5", true, false) != null, "holdings table toggles in place")
	panel.show_overview()
	panel.select_symbol("s01")
	expect(panel.current_screen() == "detail", "selecting the same row opens company detail")
	expect(panel.find_child("StockDetailChart", true, false) != null, "detail owns a real history chart")
	expect(panel.find_child("DetailCompanyName", true, false).text == "股票 1", "detail company title comes from source row")
	var detail_left0: Label = panel.find_child("DetailLeft0", true, false)
	var detail_right_left0: Label = panel.find_child("DetailRightLeft0", true, false)
	var detail_right_right0: Label = panel.find_child("DetailRightRight0", true, false)
	var detail_history0: Label = panel.find_child("DetailHistory0", true, false)
	expect(detail_left0 != null and not detail_left0.text.contains("\n") and detail_left0.text.begins_with("本月盈餘 "), "detail left earnings stay on one source row")
	expect(detail_right_left0 != null and detail_right_right0 != null and not detail_right_left0.text.contains("\n") and not detail_right_right0.text.contains("\n"), "detail upper metrics use paired columns")
	expect(detail_history0 != null and detail_history0.position.y < panel.find_child("StockDetailChart", true, false).position.y + 65.0, "detail high/low metrics stay above the chart")
	var company_button: Button = panel.find_child("StockCompanyInfo", true, false)
	company_button.pressed.emit()
	expect(panel.current_screen() == "overview", "company info button returns from detail to overview")
	panel.select_symbol("s01")
	var detail_pad_button: Button = panel.find_child("StockBuy", true, false)
	detail_pad_button.pressed.emit()
	await process_frame
	var detail_pad: Node = panel.find_child("SourceQuantityPad", true, false)
	expect(panel.current_screen() == "overview" and detail_pad != null and detail_pad.visible, "buy from detail refreshes the overview below quantity pad")
	if detail_pad != null:
		detail_pad.cancel()
	var statistics := StockPanel.history_statistics(original_snapshot.market.history.s01)
	expect(int(statistics.sample_count) == 144, "history keeps the existing 144 samples")
	expect(statistics.weekly_mean != null and is_equal_approx(float(statistics.weekly_mean), 119.583333), "weekly mean uses latest six samples")
	expect(statistics.monthly_mean != null and is_equal_approx(float(statistics.monthly_mean), 127.020833), "monthly mean uses latest 24 samples")
	expect(statistics.historical_high != null and is_equal_approx(float(statistics.historical_high), 143.0), "historical high uses existing history only")
	expect(statistics.historical_low != null and is_equal_approx(float(statistics.historical_low), 1.0), "historical low uses existing history only")
	panel.show_overview()

	var projection_before_trade: String = game.to_json()
	var requested: Array = []
	panel.trade_requested.connect(func(action: String, symbol: String, quantity: int) -> void: requested.append([action, symbol, quantity]))
	panel.clear_selection()
	panel.select_symbol("s01")
	buy_button.pressed.emit()
	await process_frame
	var pad: Node = panel.find_child("SourceQuantityPad", true, false)
	expect(pad != null and pad.visible, "buy opens source quantity pad")
	if pad != null:
		var input: LineEdit = pad.find_child("QuantityInput", true, false)
		var slider: HSlider = pad.find_child("QuantitySlider", true, false)
		var digit_one: Button = pad.find_child("QuantityDigit1", true, false)
		expect(slider != null and is_equal_approx(slider.max_value, 80.0), "source quantity pad exposes a slider synced to the buy limit")
		if slider != null:
			slider.value = 3
			expect(input.text == "3", "slider changes preserve the raw input field")
			input.text = "4"
			input.text_changed.emit(input.text)
			expect(is_equal_approx(slider.value, 4.0), "valid direct text updates the quantity slider")
			input.text = " 4"
			input.text_changed.emit(input.text)
			expect(is_equal_approx(slider.value, 4.0) and input.text == " 4", "invalid direct text remains raw without slider clamping")
			pad.find_child("QuantityMax", true, false).pressed.emit()
			expect(input.text == "80" and is_equal_approx(slider.value, 80.0), "MAX synchronizes the quantity slider and raw input")
		pad.find_child("QuantityClear", true, false).pressed.emit()
		if digit_one != null:
			digit_one.pressed.emit()
		expect(input.text == "1" and pad.find_child("QuantityAmount", true, false).text == "金額 12", "source keypad entry refreshes raw text and amount")
		pad.find_child("QuantityClear", true, false).pressed.emit()
		input.text = "2"
		pad.find_child("QuantitySubmit", true, false).pressed.emit()
		expect(requested.size() == 1 and requested[0] == ["buy_stock", "s01", 2], "valid raw quantity emits trade request")
		for invalid in [" 2", "2.5", "-2", "0", "81", "0002"]:
			input.text = invalid
			pad.find_child("QuantitySubmit", true, false).pressed.emit()
			expect(requested.size() == 1, "blank/space/fraction/negative/zero never emit trade")
	expect(not bool(QuantityPad.parse_quantity("81", 80).get("ok", false)), "raw quantity over the buy limit is rejected")
	expect(bool(QuantityPad.parse_quantity("0", 80).get("cancel", false)), "raw zero quantity remains the source cancel action")
	expect(game.to_json() == projection_before_trade, "stock projection and trade request do not mutate game state")

	var result: Dictionary = game.choose_action("buy_stock", {"symbol": "s01", "quantity": 2})
	panel.apply_trade_result(result, Fixture.definition())
	expect(pad == null or not pad.visible, "successful trade result closes quantity pad")
	expect(panel.selected_symbol() == "s01", "successful trade keeps selected symbol")
	var status_label: Label = panel.find_child("StockStatus", true, false)
	expect(status_label != null and status_label.text == str(result.get("message", "交易完成")), "successful trade result remains visible until the next stock open")
	var reopened_game: Object = make_game()
	if reopened_game != null:
		panel.open_for(reopened_game.get_snapshot(), Fixture.definition())
	expect(reopened_game != null and status_label != null and status_label.text.is_empty(), "reopening a new game clears the prior stock trade result")
	var failed: Dictionary = {"ok": false, "message": "銀行存款不足", "state": game.get_snapshot()}
	panel.clear_selection()
	panel.select_symbol("s01")
	buy_button.pressed.emit()
	await process_frame
	if pad != null:
		panel.apply_trade_result(failed, Fixture.definition())
		expect(pad.visible, "failed trade result keeps quantity pad open")
		pad.find_child("QuantityClear", true, false).pressed.emit()

	game.state.market.closed_days = 128
	game._sync_state()
	panel.set_snapshot(game.get_snapshot(), Fixture.definition())
	panel.clear_selection()
	panel.select_symbol("s01")
	expect(panel.trade_limit("buy_stock").error == "本日休市", "closed market is a visible domain gate")
	expect(panel.find_child("StockRow_s01", true, false) == null, "closed market leaves overview data rows blank")
	var closed_overlay: Label = panel.find_child("MarketClosedOverlay", true, false)
	var exit_button: Button = panel.find_child("StockExit", true, false)
	expect(panel.market_closed_overlay_visible() and closed_overlay != null and closed_overlay.text == "本日休市", "closed market renders the source closure overlay")
	expect(exit_button != null and exit_button.visible and not exit_button.disabled, "closed market keeps EXIT available")
	game.state.market.closed_days = 0
	game.state.market.open = true
	game.state.market.rows.s01.suspension = 2
	game._sync_state()
	panel.set_snapshot(game.get_snapshot(), Fixture.definition())
	panel.select_symbol("s01")
	expect(panel.trade_limit("buy_stock").error == "這檔股票暫停交易", "suspended row is a visible domain gate")

	panel.close_panel()
	expect(not panel.visible, "explicit close hides panel")
	expect(game.to_json() != "", "panel close does not erase game state")
	panel.queue_free()
	await process_frame
	print("Stock presentation checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
