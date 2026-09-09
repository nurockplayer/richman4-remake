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

func select_target(picker: OptionButton, target_id: int) -> bool:
	for index in range(picker.item_count):
		if picker.get_item_id(index) == target_id:
			picker.select(index)
			picker.item_selected.emit(index)
			return true
	return false

func select_item(picker: OptionButton, kind: String, item_id: String) -> bool:
	for index in range(picker.item_count):
		var value: Variant = picker.get_item_metadata(index)
		if value is Dictionary and value.get("item_kind") == kind and value.get("item_id") == item_id:
			picker.select(index)
			picker.item_selected.emit(index)
			return true
	return false

func use_theft(ui: Node, target_id: int, kind: String, item_id: String) -> void:
	ui._on_cards_pressed()
	var target: Node = ui.cards_popup.find_child("TheftTarget_搶奪", true, false)
	var item: Node = ui.cards_popup.find_child("TheftItem_搶奪", true, false)
	var use: Node = ui.cards_popup.find_child("UseCard_搶奪", true, false)
	check(target is OptionButton and item is OptionButton, "real inventory exposes opponent and held-item pickers")
	if target is OptionButton and item is OptionButton:
		check(select_target(target, target_id), "visible opponent can be selected")
		check(select_item(item, kind, item_id), "requested held item can be selected")
	check(use is Button and not use.disabled, "theft card has an executable confirmation button")
	if use is Button and not use.disabled:
		use.pressed.emit()

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	check(ui._new_game(64001, 4, Fixture.definition(), Fixture.new_game_options()), "theft UI uses the existing legal v13 factory")
	ui.set_process(false)
	var game: Object = ui.game_state
	game.state.god_objects = []
	for id in range(4):
		game.set_player_ai(id, false)
		game.state.players[id].position = id
		game.state.players[id].previous_position = -1
	var actor: Dictionary = game.state.players[0]
	check(Inventory.grant_card(game.state.inventory_supply, actor.cards, "搶奪").get("ok", false), "grant first robbery card from finite supply")
	check(Inventory.grant_card(game.state.inventory_supply, actor.cards, "搶奪").get("ok", false), "grant second robbery card from finite supply")
	check(Inventory.grant_card(game.state.inventory_supply, game.state.players[1].cards, "紅").get("ok", false), "opponent holds a source-backed card")
	game._set_action_options(0)
	check(Game.validate_save(game.to_dict()).get("ok", false), "theft UI input validates")
	ui._refresh_from_state()
	await process_frame
	var visible: Array = ui.board_view.visible_node_indices()
	check(visible.has(1) and visible.has(2), "both fixture opponents are actually visible")
	use_theft(ui, 1, "card", "紅")
	check(game.state.players[0].cards.has("紅") and not game.state.players[1].cards.has("紅"), "actual UI transfers the selected card")
	check(game.state.players[0].cards.count("搶奪") == 1, "successful UI transfer consumes one robbery card")
	var tool_before: int = int(game.state.players[0].tools.get("機器工人", 0))
	var target_before: int = int(game.state.players[2].tools.get("機器工人", 0))
	use_theft(ui, 2, "tool", "機器工人")
	check(int(game.state.players[0].tools.get("機器工人", 0)) == tool_before + 1 and int(game.state.players[2].tools.get("機器工人", 0)) == target_before - 1, "actual UI transfers exactly one selected research tool")
	check(not game.state.players[0].cards.has("搶奪"), "both confirmed steals consume exactly two robbery cards")
	check(Game.validate_save(game.to_dict()).get("ok", false), "UI results preserve finite inventory and save invariants")
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	check(restored != null and restored.to_json() == game.to_json(), "UI action results survive canonical JSON reload")
	ui.queue_free()
	print("Theft UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
