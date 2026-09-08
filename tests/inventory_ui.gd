extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
const InventoryRules = preload("res://game/core/inventory_rules.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	expect(int(ui.state.get("version", 0)) == 4, "UI new game opts into original inventory")
	ui._on_cards_pressed()
	expect(ui.cards_popup.visible, "backpack opens before rolling")
	await process_frame
	await process_frame
	expect(ui.cards_popup.size.y <= 800, "backpack and close button fit the default viewport")
	expect(ui.cards_popup.size.x >= 600, "backpack keeps room for target controls")
	expect(ui.inventory_balance_label.text.contains("點券 0"), "backpack displays starting points")
	expect(ui.cards_popup_list.get_child_count() >= 8, "backpack displays all six opening tools")
	ui.cards_popup.hide()
	var raw := Fixture.make()
	raw.nodes[1].event_code = 15
	var definition: Dictionary = Maps.normalize_map(raw).definition
	var options := {"start_date": {"year": 1998, "month": 1, "day": 1}, "original_inventory": true}
	expect(ui._new_game(42, 2, definition, options), "inventory UI starts on source graph")
	# The runtime suite verifies movement into the shop; this UI fixture opens
	# the resulting action state to exercise actual buttons and quantity input.
	ui.game_state.state.players[0].position = 1
	ui.game_state.state.players[0].points = 500
	ui.game_state.state.phase = "await_action"
	ui.game_state._set_action_options(0)
	ui._refresh_from_state()
	expect(ui.shop_button.visible and not ui.shop_button.disabled, "landing exposes the point shop button")
	ui.shop_button.pressed.emit()
	expect(ui.shop_popup.visible, "point shop opens from its button")
	await process_frame
	await process_frame
	expect(ui.shop_popup.size.y <= 800, "shop and close button fit the default viewport")
	expect(ui.shop_popup.size.x >= 700, "shop keeps room for transaction controls")
	var buy: Button = ui.shop_popup.find_child("Buy_路障", true, false)
	expect(buy != null, "shop exposes roadblock purchase")
	if buy != null:
		var quantity: SpinBox = buy.get_parent().get_child(1)
		quantity.value = 2
		expect(buy.text.contains("60"), "quantity input updates total purchase price")
		buy.pressed.emit()
		await process_frame
		await process_frame
		expect(int(ui.state.players[0].tools.get("路障", 0)) == 3, "buy button purchases the selected two roadblocks")
		expect(int(ui.state.players[0].points) == 440, "purchase uses points rather than cash")
	var sell: Button = ui.shop_popup.find_child("Sell_路障", true, false)
	expect(sell != null and not sell.disabled, "owned tool can be sold")
	if sell != null:
		var quantity: SpinBox = sell.get_parent().get_child(1)
		quantity.value = 2
		expect(sell.text.contains("54"), "quantity sale quote uses total-price rounding")
		sell.pressed.emit()
		await process_frame
		await process_frame
		expect(int(ui.state.players[0].tools.get("路障", 0)) == 1 and int(ui.state.players[0].points) == 494, "sale button restores stock and point proceeds")
	ui.game_state.state.phase = "await_roll"
	ui.game_state._set_action_options(0)
	ui._refresh_from_state()
	expect(not ui.shop_popup.visible and not ui.shop_button.visible, "shop closes outside landing action phase")
	ui.game_state._grant_card(0, "天使")
	ui.game_state._set_action_options(0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	var unsupported_found := false
	for row in ui.cards_popup_list.get_children():
		if not row is HBoxContainer:
			continue
		var label = row.get_child(0)
		if label is Label and label.text == "天使卡":
			var use = row.get_child(row.get_child_count() - 1)
			unsupported_found = use is Button and use.disabled and use.text == "尚未還原"
	expect(unsupported_found, "unsupported card remains visible with use disabled")
	ui.cards_popup.hide()
	ui.game_state._grant_card(0, "均貧")
	ui.game_state._grant_card(0, "轉向")
	ui.game_state._set_action_options(0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	var poor_targets := -1
	var reverse_targets := -1
	for row in ui.cards_popup_list.get_children():
		if not row is HBoxContainer or not row.get_child(0) is Label:
			continue
		var text: String = row.get_child(0).text
		if text == "均貧卡" or text == "轉向卡":
			var targets = row.get_child(1)
			if targets is OptionButton:
				if text == "均貧卡":
					poor_targets = targets.item_count
				else:
					reverse_targets = targets.item_count
	expect(poor_targets == 1, "equal-poor target selector excludes current player")
	expect(reverse_targets == 2, "reverse target selector includes alive players")
	var remote: Button = ui.cards_popup.find_child("UseTool_遙控骰子", true, false)
	expect(remote != null, "remote control has a named use button")
	if remote != null:
		var values: OptionButton = remote.get_parent().find_child("RemoteValue", true, false)
		expect(values != null and values.item_count == 6 and values.get_item_id(5) == 6, "remote control offers source-verified values one through six")
		expect(not remote.disabled, "implemented remote control is available before rolling")
		if values != null and not remote.disabled:
			values.select(3)
			remote.pressed.emit()
			expect(int(ui.state.get("pending_remote_dice", {}).get("value", 0)) == 4, "remote use button sends selected value to core")
			expect(ui.phase_label.text.contains("遙控 4 點"), "pending remote value is visible after closing backpack")
			expect(not ui.cards_popup.visible, "successful remote selection closes backpack")
			ui._on_cards_pressed()
			var pending_use: Button = ui.cards_popup.find_child("UseTool_遙控骰子", true, false)
			expect(pending_use == null or pending_use.disabled, "pending remote cannot be consumed twice from UI")
	ui.cards_popup.hide()
	expect(ui._new_game(51, 2, definition, options), "vehicle UI fixture starts")
	var grant: Dictionary = InventoryRules.grant_tool(ui.game_state.state.inventory_supply, ui.game_state.state.players[0].tools, "汽車")
	expect(bool(grant.get("ok", false)), "vehicle UI fixture receives car")
	ui.game_state._set_action_options(0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	var car: Button = ui.cards_popup.find_child("UseTool_汽車", true, false)
	expect(car != null and not car.disabled, "car can be equipped from backpack")
	if car != null and not car.disabled:
		car.pressed.emit()
		expect(ui.state.players[0].vehicle == "car" and int(ui.state.players[0].dice_count) == 3, "car button equips three dice")
		ui._on_cards_pressed()
		var dice: OptionButton = ui.cards_popup.find_child("VehicleDice", true, false)
		expect(dice != null and dice.item_count == 3, "equipped car exposes one to three dice")
		if dice != null:
			dice.select(1)
			dice.item_selected.emit(1)
			await process_frame
			expect(int(ui.state.players[0].dice_count) == 2, "dice selector changes equipped car roll count")
		var walk: Button = ui.cards_popup.find_child("UnequipVehicle", true, false)
		expect(walk != null and not walk.disabled, "equipped car can return to walking")
		if walk != null and not walk.disabled:
			walk.pressed.emit()
			await process_frame
			expect(ui.state.players[0].vehicle == "walking" and int(ui.state.players[0].tools.get("汽車", 0)) == 1, "walking button returns equipped car to backpack")
	ui.queue_free()
	await create_timer(0.15).timeout
	print("Inventory UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
