extends SceneTree

const MainScene = preload("res://game/main.tscn")
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func select_target(picker: OptionButton, node_id: int) -> bool:
	if picker == null:
		return false
	for index in range(picker.item_count):
		if picker.get_item_id(index) == node_id:
			picker.select(index)
			return true
	return false

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	for tool_id in ["飛彈", "核子飛彈"]:
		check(ui._new_game(8012, 4, Fixture.definition(), Fixture.new_game_options()), tool_id + " UI factory starts")
		ui.set_process(false)
		var game: Object = ui.game_state
		for player_id in range(4):
			game.set_player_ai(player_id, false)
		game.state.god_objects = []
		for player in game.state.players:
			player.god_id = 0
		game.state.current_player = 0
		game.state.phase = "await_roll"
		game.state.players[0].position = 2
		game.state.players[0].previous_position = -1
		game.state.board[2].owner = 0
		game.state.board[2].building_level = 3
		game.state.board[2].is_chain_store = false
		game.state.players[0].properties = [2]
		game.call("_update_tile_rent", game.state.board[2])
		game.call("_recalculate_property_values")
		check(Inventory.grant_tool(game.state.inventory_supply, game.state.players[0].tools, tool_id).get("ok", false), tool_id + " receives valid inventory")
		game.call("_set_action_options", 0)
		check(Game.validate_save(game.to_dict()).get("ok", false), tool_id + " legal pre-action fixture")
		ui._refresh_from_state()
		ui.board_view.reset_view()
		await process_frame
		ui._on_cards_pressed()
		await process_frame
		var use: Button = ui.cards_popup.find_child("UseTool_" + tool_id, true, false)
		var picker: OptionButton = ui.cards_popup.find_child("Target_" + tool_id, true, false)
		check(use != null and not use.disabled, tool_id + " has executable backpack button")
		check(select_target(picker, 2), tool_id + " offers actual logical target")
		var before: String = game.to_json()
		ui.cards_popup.hide()
		await process_frame
		check(game.to_json() == before, tool_id + " closing inventory preserves JSON and RNG")
		ui._on_cards_pressed()
		use = ui.cards_popup.find_child("UseTool_" + tool_id, true, false)
		picker = ui.cards_popup.find_child("Target_" + tool_id, true, false)
		if use == null or use.disabled or not select_target(picker, 2):
			ui.cards_popup.hide()
			continue
		var held: int = game.state.players[0].tools.get(tool_id, 0)
		var supply_before: Dictionary = game.state.inventory_supply.tools.duplicate(true)
		check(Game.validate_save(game.to_dict()).get("ok", false), tool_id + " validates immediately before button")
		use.pressed.emit()
		await process_frame
		check(not ui.cards_popup.visible, tool_id + " success closes backpack")
		check(game.state.board[2].building_level == (2 if tool_id == "飛彈" else 0), tool_id + " selected target receives correct blast")
		check(game.state.board[2].owner == (0 if tool_id == "飛彈" else -1), tool_id + " ownership follows blast mode")
		check(ui.board_view.board_data[2].building_level == game.state.board[2].building_level, tool_id + " live board receives damaged construction")
		check(game.state.players[0].tools.get(tool_id, 0) == held - 1, tool_id + " button consumes exactly once")
		if tool_id == "飛彈":
			check(game.state.inventory_supply.tools[tool_id] == supply_before[tool_id] + 1, "missile returns to finite supply")
		else:
			check(game.state.inventory_supply.tools == supply_before, "research nuclear does not invent supply")
		check(Game.validate_save(game.to_dict()).get("ok", false), tool_id + " UI result remains valid")
		var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		check(restored != null and restored.to_json() == game.to_json(), tool_id + " result JSON roundtrip is exact")
	ui.queue_free()
	await process_frame
	print("Missiles UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
