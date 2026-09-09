extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func setup(ui: Node) -> Object:
	check(ui._new_game(74001, 4, Fixture.definition(), Fixture.new_game_options()), "financial UI starts legal factory")
	ui.set_process(false)
	var g: Object = ui.game_state
	g.state.god_objects = []
	for id in range(4):
		g.set_player_ai(id, false)
		g.state.players[id].position = id
		g.state.players[id].previous_position = -1
		for held in g.state.players[id].cards.duplicate():
			Inventory.consume_card(g.state.inventory_supply, g.state.players[id].cards, held)
	for pair in [[0, "查稅"], [1, "免費"], [1, "嫁禍"]]:
		check(Inventory.grant_card(g.state.inventory_supply, g.state.players[pair[0]].cards, pair[1]).get("ok", false), "grant UI card from finite supply")
	g.state.players[1].cash = 15005
	g.state.players[2].cash = 25000
	g._set_action_options(0)
	check(Game.validate_save(g.to_dict()).get("ok", false), "financial UI precondition validates")
	ui._refresh_from_state()
	return g

func select(picker: OptionButton, target_id: int) -> bool:
	for index in range(picker.item_count):
		if picker.get_item_id(index) == target_id:
			picker.select(index)
			picker.item_selected.emit(index)
			return true
	return false

func press_tax(ui: Node) -> bool:
	ui._on_cards_pressed()
	var picker: Node = ui.cards_popup.find_child("CardTarget_查稅", true, false)
	var use: Node = ui.cards_popup.find_child("UseCard_查稅", true, false)
	check(picker is OptionButton, "tax card exposes real visible-player picker")
	check(use is Button and not use.disabled, "tax card is executable")
	if not picker is OptionButton or not use is Button or use.disabled: return false
	check(select(picker, 1), "tax selects visible opponent")
	use.pressed.emit()
	return true

func popup(ui: Node) -> Node:
	var result: Node = ui.find_child("FinancialResponsePopup", true, false)
	check(result is Window and result.visible, "pending finance opens player-visible response window")
	return result if result is Window and result.visible else null

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	var g := setup(ui)
	await process_frame
	var before: String = g.to_json()
	ui._on_cards_pressed()
	ui.cards_popup.hide()
	check(g.to_json() == before, "closing card selection consumes nothing")
	if press_tax(ui):
		await process_frame
		var response := popup(ui)
		check(not ui.cards_popup.visible, "inventory closes before response window")
		check(int(g.state.players[1].cash) == 15005, "UI waits before collecting tax")
		if response != null:
			var prompt: Node = response.find_child("FinancialPrompt", true, false)
			check(prompt is Label and "3,001" in prompt.text and "查稅" in prompt.text, "response states exact amount and cause")
			check(response.exclusive and not response.popup_window, "passive decision survives parent focus loss")
			var frozen: String = g.to_json()
			response.notification(Window.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			await process_frame
			check(response.visible and g.to_json() == frozen, "focus loss cannot answer or consume a card")
			var accept: Node = response.find_child("AcceptFinancial", true, false)
			check(accept is Button, "free response has explicit accept button")
			if accept is Button: accept.pressed.emit()
			check(not g.state.has("pending_finance") and not g.state.players[1].cards.has("免費"), "accepting free consumes only free and clears pending")
			check(int(g.state.players[1].cash) == 15005 and g.state.players[1].cards.has("嫁禍"), "free wins before redirect and transfers no money")
	g = setup(ui)
	await process_frame
	if press_tax(ui):
		await process_frame
		var response := popup(ui)
		if response != null:
			var decline: Node = response.find_child("DeclineFinancial", true, false)
			check(decline is Button, "free response offers explicit decline")
			if decline is Button: decline.pressed.emit()
			response = popup(ui)
			if response != null:
				var redirect: Node = response.find_child("FinancialRedirectTarget", true, false)
				check(redirect is OptionButton and select(redirect, 2), "decline exposes legal redirect target picker")
				var accept: Node = response.find_child("AcceptFinancial", true, false)
				if accept is Button: accept.pressed.emit()
				check(int(g.state.players[2].cash) == 20000 and int(g.state.players[1].cash) == 15005, "redirect UI recomputes new payer tax")
				check(g.state.players[1].cards.has("免費") and not g.state.players[1].cards.has("嫁禍"), "redirect UI consumes only redirect defense")
	check(Game.validate_save(g.to_dict()).get("ok", false), "financial UI result validates")
	g = setup(ui)
	await process_frame
	if press_tax(ui):
		await process_frame
		check(g.state.has("pending_finance"), "new-game cancellation starts with genuine pending")
		setup(ui)
		await process_frame
		var response: Node = ui.find_child("FinancialResponsePopup", true, false)
		check(response is Window and not response.visible and not ui.game_state.state.has("pending_finance"), "new game removes stale financial response without answering")
	ui.queue_free()
	print("Financial UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
