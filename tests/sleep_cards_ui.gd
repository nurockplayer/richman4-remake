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

func setup(ui: Node, seed_value: int) -> Object:
	check(ui._new_game(seed_value, 4, Fixture.definition(), Fixture.new_game_options()), "legal v13 UI factory")
	ui.set_process(false)
	var game: Object = ui.game_state
	game.state.god_objects = []
	for id in range(4):
		game.set_player_ai(id, false)
		game.state.players[id].position = id
		game.state.players[id].previous_position = -1
		var cards: Array = game.state.players[id].cards
		while not cards.is_empty():
			Inventory.consume_card(game.state.inventory_supply, cards, str(cards[0]))
	game._set_action_options(0)
	check(Game.validate_save(game.to_dict()).get("ok", false), "clean finite-inventory UI fixture validates")
	return game

func give(game: Object, id: int, card_id: String) -> void:
	check(Inventory.grant_card(game.state.inventory_supply, game.state.players[id].cards, card_id).get("ok", false), "grant %s through finite inventory" % card_id)
	game._set_action_options(0)

func use_card(ui: Node, card_id: String, target_id: int = -1) -> void:
	ui._refresh_from_state()
	# Wait for the source viewport to follow the fixture's current player
	# before checking the real visible-target filter and opening the picker.
	await process_frame
	var visible: Array = ui.board_view.visible_node_indices()
	check(target_id < 0 or visible.has(int(ui.state.players[target_id].position)), "requested card target is actually visible")
	ui._on_cards_pressed()
	if target_id >= 0:
		var picker: Node = ui.cards_popup.find_child("CardTarget_" + card_id, true, false)
		var found := false
		if picker is OptionButton:
			for index in range(picker.item_count):
				if picker.get_item_id(index) == target_id:
					picker.select(index)
					found = true
		check(found, "actual %s picker offers requested visible player including self" % card_id)
	var button: Node = ui.cards_popup.find_child("UseCard_" + card_id, true, false)
	check(button is Button and not button.disabled, "%s confirmation enabled" % card_id)
	if button is Button and not button.disabled:
		button.pressed.emit()

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	var game := setup(ui, 69001)
	give(game, 0, "夢遊")
	await use_card(ui, "夢遊", 0)
	check(int(game.state.players[0].get("dream_days", 0)) == 4, "self dream from actual card UI")
	check(str(ui._rest_status_label(ui._player_rest_status(game.state.players[0]))).contains("夢遊"), "status identifies dream instead of prison")
	check(ui.cards_button.disabled and ui.bank_button.disabled and ui.stocks_button.disabled and ui.roll_button.disabled, "dream blocks manual cards bank stock and dice")
	if int(game.state.players[0].get("dream_days", 0)) > 0:
		ui._on_ai_timer_timeout(ui._presentation_generation)
		check(int(game.state.current_player) != 0, "UI timer advances human dream without changing control flags")
		check(game.state.players[0].is_human and not game.state.players[0].is_ai, "human identity remains human")
		while ui._presentation_busy:
			await process_frame
	game = setup(ui, 69002)
	give(game, 0, "夢遊")
	give(game, 1, "嫁禍")
	await use_card(ui, "夢遊", 1)
	check(ui._human_trap_response_pending(), "dream offers existing human defense response")
	check(ui.trap_popup.visible and ui.trap_prompt_label.text.contains("夢遊") and not ui.trap_prompt_label.text.contains("入獄"), "dream defense prompt has correct consequence")
	if ui._human_trap_response_pending():
		ui._respond_to_trap(true)
	check(int(game.state.players[1].get("dream_days", 0)) == 5 and game.state.players[1].cards.has("嫁禍"), "decline keeps scapegoat and resolves dream")
	game = setup(ui, 69003)
	give(game, 0, "冬眠")
	await use_card(ui, "冬眠")
	check(int(game.state.players[1].get("winter_sleep_days", 0)) == 5, "winter uses actual button without target picker")
	check(str(ui._rest_status_label(ui._player_rest_status(game.state.players[1]))).contains("冬眠"), "winter status shown to player")
	check(Game.validate_save(game.to_dict()).get("ok", false), "UI results keep legal save")
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	check(restored != null and restored.to_json() == game.to_json(), "UI state exact JSON continuation")
	ui.queue_free()
	print("Sleep cards UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
