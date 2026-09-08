extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
const Fixture = preload("res://tests/fixtures/company_fixture.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func labels(node: Node) -> String:
	var result := ""
	if node is Label:
		result += node.text + "\n"
	for child in node.get_children():
		result += labels(child)
	return result


func company_game(ui: Control, definition: Dictionary) -> bool:
	return ui._new_game(42, 2, definition, {})


func prepare_company_visit(game: Object, player_id: int = 0) -> void:
	game.state.current_player = player_id
	game.state.players[player_id].position = 5
	game.state.players[player_id].previous_position = 4
	game.state.phase = "await_action"
	game.state.property_action_used = false
	game.state.last_roll = [1]
	game._set_action_options(player_id)


func run() -> void:
	var ui: Control = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)

	var definition: Dictionary = Fixture.definition()
	definition.stock_rows[0].base_price = 12.5
	definition.stock_rows[0].previous_price = 12.5
	definition.stock_rows[0].price = 12.5
	definition.companies[0].monthly_profit = 2400
	definition.companies[0].cumulative_profit = 7200
	expect(company_game(ui, definition), "company UI starts a v7 source game")
	var game: Object = ui.game_state
	expect(int(ui.state.get("version", 0)) == 7 and ui._has_original_companies(), "company UI advertises explicit v7 capability")
	expect(bool(ui._setup_options_from_state().get("original_companies", false)), "company restart options preserve company capability")

	game.state.god_objects = []
	game.state.company_purchase_remaining = 6
	game.state.companies[0].treasury = 8
	game.state.company_months = 3
	game.state.players[0].cash = 200
	game.state.players[0].deposit = 2000
	game.state.bank.deposits = 2000
	prepare_company_visit(game)
	ui._refresh_from_state()
	expect(ui.current_property_label.text == "測試企業", "company property card names the visited company")
	expect(ui.current_property_detail.text.contains("你的持股") and ui.current_property_detail.text.contains("經營者"), "company property card shows ownership and holdings")
	expect(ui.current_property_detail.text.contains("平均盈餘") and ui.current_property_detail.text.contains("$2,400"), "company property card shows cumulative average earnings")
	expect(not ui.buy_button.disabled and ui.buy_button.text == "購買企業股份", "company visit exposes share purchase action")
	ui.buy_button.pressed.emit()
	expect(ui.company_popup.visible, "company purchase action opens the company popup")
	await process_frame
	await process_frame
	expect(labels(ui.company_popup_list).contains("測試企業") and labels(ui.company_popup_list).contains("市價 $12.50"), "company popup shows company identity and float market price")
	expect(labels(ui.company_popup_list).contains("平均盈餘 $2,400"), "company popup shows average earnings")
	var purchase_quantity: SpinBox = ui.company_popup.find_child("CompanyPurchaseQuantity", true, false)
	var purchase_button: Button = ui.company_popup.find_child("BuyCompanyShares", true, false)
	expect(purchase_quantity != null and is_equal_approx(purchase_quantity.max_value, 5.0), "company purchase cap combines cash, treasury, visit limit and thousand-share cap")
	expect(purchase_button != null and not purchase_button.disabled, "company purchase button is enabled within the cap")
	if purchase_quantity != null and purchase_button != null:
		purchase_quantity.value = 3
		purchase_button.pressed.emit()
		await process_frame
		await process_frame
	expect(int(game.state.players[0].cash) == 80 and int(game.state.players[0].stocks.s01) == 3, "company purchase uses face price and cash")
	expect(int(game.state.company_purchase_remaining) == 3 and int(game.state.companies[0].treasury) == 5, "company purchase consumes visit and treasury supply")
	expect(not ui.company_popup.visible, "successful company purchase closes the popup")

	game.state.players[0].deposit = 1000
	game.state.bank.deposits = 1000
	game.state.players[0].stocks.s01 = 1
	game.state.market.rows.s01.market_supply = 4
	game.state.market.rows.s01.turn_supply = 2
	game.state.market.rows.s01.suspension = 1
	game.state.market.open = true
	game.state.phase = "await_action"
	game._set_action_options(0)
	ui._refresh_from_state()
	ui._on_stocks_pressed()
	expect(ui.stocks_popup.visible, "stock action opens the market popup")
	await process_frame
	await process_frame
	expect(ui.stocks_popup_list.get_child_count() == 13, "stock popup renders all twelve dynamic rows")
	expect(ui.stocks_popup.find_child("StockRow_s12", true, false) != null, "stock popup keeps the twelfth stock row")
	expect(labels(ui.stocks_popup_list).contains("價格 $12.50"), "stock popup retains fractional quote precision")
	var stock_quantity: SpinBox = ui.stocks_popup.find_child("StockQuantity_s01", true, false)
	var stock_buy: Button = ui.stocks_popup.find_child("BuyStock_s01", true, false)
	var stock_sell: Button = ui.stocks_popup.find_child("SellStock_s01", true, false)
	expect(stock_buy != null and stock_sell != null and stock_buy.disabled and stock_sell.disabled, "suspended stock disables both trade directions")
	game.state.market.rows.s01.suspension = 0
	ui._refresh_from_state()
	stock_quantity = ui.stocks_popup.find_child("StockQuantity_s01", true, false)
	stock_buy = ui.stocks_popup.find_child("BuyStock_s01", true, false)
	stock_sell = ui.stocks_popup.find_child("SellStock_s01", true, false)
	if stock_quantity != null and stock_buy != null and stock_sell != null:
		expect(is_equal_approx(stock_quantity.max_value, 2.0), "stock quantity picker caps buy quantity at turn supply")
		stock_quantity.value = 2
		expect(not stock_buy.disabled and stock_sell.disabled, "stock quantity picker enforces turn supply and holdings")
		stock_quantity.value = 1
		stock_buy.pressed.emit()
		await process_frame
		await process_frame
	expect(int(game.state.players[0].stocks.s01) == 2 and int(game.state.players[0].deposit) == 988, "stock purchase uses the selected quantity and bank deposit")

	game.state.players[0].insurance_status = 128
	ui._refresh_from_state()
	expect(labels(ui.players_list).contains("保險：128（到期當日仍有效）"), "roster renders the source insurance expiry marker")
	game.state.players[0].cards = ["紅", "黑"]
	game.state.phase = "await_roll"
	game._set_action_options(0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	var red_picker: OptionButton = ui.cards_popup.find_child("StockSymbol_紅", true, false)
	var black_picker: OptionButton = ui.cards_popup.find_child("StockSymbol_黑", true, false)
	expect(red_picker != null and red_picker.item_count == 12 and black_picker != null and black_picker.item_count == 12, "red and black cards expose all twelve dynamic stocks")
	ui.cards_popup.hide()

	var construction_definition: Dictionary = Fixture.construction_definition()
	expect(company_game(ui, construction_definition), "company construction UI starts the shared facility fixture")
	var construction: Object = ui.game_state
	construction.state.god_objects = []
	construction.state.players[0].stocks.s01 = 1
	construction.state.companies[0].treasury -= 1
	construction._update_company_owners()
	construction._update_facility_records(1, {"owner": 1})
	construction.state.board[2].owner = 1
	construction.state.players[1].is_human = true
	construction.state.players[1].is_ai = false
	construction.state.players[1].properties = [1, 2]
	construction.state.players[1].cash = 5000
	prepare_company_visit(construction, 1)
	construction._resolve_company_visit(1, construction.state.board[5])
	construction._set_action_options(1)
	ui._refresh_from_state()
	expect(int(construction.state.company_service_pending) == 1 and ui.upgrade_button.text == "企業建設", "company construction visit creates a pending UI action")
	ui.upgrade_button.pressed.emit()
	expect(ui.company_popup.visible, "company construction action opens the company popup")
	await process_frame
	await process_frame
	var target_picker: OptionButton = ui.company_popup.find_child("CompanyUpgradeTarget", true, false)
	var facility_picker: OptionButton = ui.company_popup.find_child("CompanyFacilityType", true, false)
	var service_button: Button = ui.company_popup.find_child("CompanyUpgrade", true, false)
	expect(target_picker != null and target_picker.item_count == 2, "company construction lists property and shared facility targets")
	expect(facility_picker != null and facility_picker.item_count == 4, "vacant facility target requires a supported type selection")
	expect(service_button != null and not service_button.disabled and labels(ui.company_popup_list).contains("服務費 $1,000"), "visitor construction shows the target service fee")
	construction.state.players[1].god_id = 6
	construction.state.god_objects = [{"id": 6, "node": 5, "owner": 1, "days": 7}]
	ui._refresh_from_state()
	await process_frame
	await process_frame
	service_button = ui.company_popup.find_child("CompanyUpgrade", true, false)
	expect(labels(ui.company_popup_list).contains("服務費 $2,000") and service_button != null and service_button.text.contains("$2,000"), "construction UI displays the doubled God 6 service fee")
	construction.state.players[1].god_id = 2
	construction.state.god_objects = [{"id": 2, "node": 5, "owner": 1, "days": 7}]
	ui._refresh_from_state()
	await process_frame
	await process_frame
	service_button = ui.company_popup.find_child("CompanyUpgrade", true, false)
	expect(labels(ui.company_popup_list).contains("服務費 $0") and service_button != null and service_button.text.contains("$0"), "construction UI displays the waived God 2 service fee")
	construction.state.players[1].god_id = 0
	construction.state.god_objects = []
	ui._refresh_from_state()
	await process_frame
	await process_frame
	target_picker = ui.company_popup.find_child("CompanyUpgradeTarget", true, false)
	facility_picker = ui.company_popup.find_child("CompanyFacilityType", true, false)
	service_button = ui.company_popup.find_child("CompanyUpgrade", true, false)
	if target_picker != null and facility_picker != null and service_button != null:
		target_picker.select(1)
		target_picker.item_selected.emit(1)
		expect(ui.company_popup.find_child("CompanyFacilityType", true, false) == null, "switching to a property removes the facility type picker")
		target_picker.select(0)
		target_picker.item_selected.emit(0)
		facility_picker = ui.company_popup.find_child("CompanyFacilityType", true, false)
		expect(facility_picker != null and facility_picker.item_count == 4, "switching back to a vacant facility restores the type picker")
		if facility_picker != null:
			facility_picker.select(1)
		var construction_cash := int(construction.state.players[1].cash)
		service_button.pressed.emit()
		await process_frame
		await process_frame
		expect(int(construction.state.board[1].building_level) == 1 and int(construction.state.board[1].facility_type) == 1, "company construction sends the selected facility type")
		expect(int(construction.state.players[1].cash) == construction_cash - 1000 and int(construction.state.company_service_pending) == 0, "visitor construction charges the displayed service fee")

	ui.queue_free()
	await create_timer(0.1).timeout
	print("Company UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
