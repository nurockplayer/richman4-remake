extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/auction_fixture.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	check(ui._new_game(7881, 4, Fixture.definition(), Fixture.new_game_options()), "auction UI starts legal factory")
	ui.set_process(false)
	var g: Object = ui.game_state
	for id in range(4):
		g.set_player_ai(id, false)
		for held in g.state.players[id].cards.duplicate():
			Inventory.consume_card(g.state.inventory_supply, g.state.players[id].cards, held)
	Fixture.prepare(g, 0, 2)
	check(Fixture.stage_card(g, 0).get("ok", false), "auction UI receives finite card")
	check(Game.validate_save(g.to_dict()).get("ok", false), "auction UI fixture validates before public action")
	ui._refresh_from_state()
	var before: String = g.to_json()
	ui._on_cards_pressed()
	ui.cards_popup.hide()
	await process_frame
	check(g.to_json() == before, "closing inventory preserves auction card and state")
	ui._on_cards_pressed()
	var use: Node = ui.cards_popup.find_child("UseCard_拍賣", true, false)
	check(use is Button and not use.disabled, "real backpack auction card is executable")
	if use is Button and not use.disabled:
		use.pressed.emit()
		await process_frame
		var response: Node = ui.find_child("AuctionResponsePopup", true, false)
		check(response is Window and response.visible, "auction opens visible response window")
		check(g.state.has("pending_auction"), "backpack enters pending auction")
		check(not ui.cards_popup.visible, "inventory closes before auction response")
		if response is Window and g.state.has("pending_auction"):
			var pending: Dictionary = g.state.pending_auction
			check(response.exclusive and not response.popup_window, "auction response survives passive focus loss")
			var prompt: Node = response.find_child("AuctionPrompt", true, false)
			check(prompt is Label and str(g.state.players[pending.bidder_id].name) in prompt.text, "prompt identifies current bidder")
			for increment in [100, 500, 1000, 5000, 10000]:
				var button: Node = response.find_child("AuctionIncrement%d" % increment, true, false)
				check(button is Button, "auction offers increment %d" % increment)
			var raise_button: Node = response.find_child("AuctionIncrement100", true, false)
			if raise_button is Button and not raise_button.disabled:
				var opening: int = pending.current_bid
				check(Game.validate_save(g.to_dict()).get("ok", false), "save validates before UI raise")
				raise_button.pressed.emit()
				await process_frame
				check(g.state.pending_auction.current_bid == opening + 100, "actual raise button adds exactly 100")
				check(g.state.current_player == 0 and g.state.pending_auction.bidder_id == 1, "raise advances bidder while preserving caster")
			else:
				check(false, "legal opening allows 100 raise")
			var pending_json: String = g.to_json()
			response.hide()
			await process_frame
			await process_frame
			check(response.visible and g.to_json() == pending_json, "closing unanswered auction restores popup without a response")
			var restored: Object = Game.from_dict(JSON.parse_string(pending_json))
			check(restored != null and restored.to_json() == pending_json, "UI pending JSON roundtrip is exact")
			var withdraw: Node = response.find_child("WithdrawAuction", true, false)
			check(withdraw is Button and not withdraw.disabled, "auction offers explicit withdrawal")
			if withdraw is Button and not withdraw.disabled:
				check(Game.validate_save(g.to_dict()).get("ok", false), "save validates before UI withdrawal")
				withdraw.pressed.emit()
				await process_frame
				check(g.state.pending_auction.withdrawn.has(1), "withdraw button withdraws live bidder")
			check(ui._new_game(7882, 4, Fixture.definition(), Fixture.new_game_options()), "new game replaces pending auction")
			ui.set_process(false)
			await process_frame
			await process_frame
			check(not response.visible and not ui.game_state.state.has("pending_auction"), "new game clears popup and pending without stale reopening")
	ui.queue_free()
	print("Auction UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
