extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
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
	ui.queue_free()
	await create_timer(0.15).timeout
	print("Inventory UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
