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

func select_id(picker: OptionButton, id: int) -> bool:
	if picker == null: return false
	for index in range(picker.item_count):
		if picker.get_item_id(index) == id:
			picker.select(index)
			picker.item_selected.emit(index)
			return true
	return false

func select_transport(ui: Node, category: int, target_id: int, destination: int) -> bool:
	if not select_id(ui.cards_popup.find_child("TransportKind", true, false), category): return false
	if not select_id(ui.cards_popup.find_child("TransportTarget", true, false), target_id): return false
	return select_id(ui.cards_popup.find_child("TransportDestination", true, false), destination)

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	check(ui._new_game(8181, 4, Fixture.definition(), Fixture.new_game_options()), "time/transport UI factory starts")
	ui.set_process(false)
	var game: Object = ui.game_state
	for id in range(4): game.set_player_ai(id, false)
	game.state.god_objects = []
	for player in game.state.players: player.god_id = 0
	game.state.players[0].position = 2
	game.state.players[0].previous_position = -1
	game.state.board[2].owner = 0
	game.state.board[2].building_level = 3
	game.state.board[2].is_chain_store = false
	game.state.players[0].properties = [2]
	game.call("_update_tile_rent", game.state.board[2])
	game.call("_recalculate_property_values")
	check(Inventory.grant_tool(game.state.inventory_supply, game.state.players[0].tools, "傳送機", 2).get("ok", false), "two legal research transport tools granted")
	check(Inventory.grant_tool(game.state.inventory_supply, game.state.players[0].tools, "時光機", 1).get("ok", false), "legal research time tool granted")
	game.call("_set_action_options", 0)
	check(Game.validate_save(game.to_dict()).get("ok", false), "UI fixture validates before public interaction")
	ui._refresh_from_state()
	ui.board_view.reset_view()
	ui._on_cards_pressed()
	await process_frame
	var time_use: Button = ui.cards_popup.find_child("UseTool_時光機", true, false)
	var time_status: Label = ui.cards_popup.find_child("TimeMachineStatus", true, false)
	check(time_use != null and time_use.disabled, "time tool cannot run without an anchor")
	check(time_status != null and not time_status.text.is_empty(), "time tool visibly explains unavailable anchor")
	var use: Button = ui.cards_popup.find_child("UseTool_傳送機", true, false)
	check(use != null and not use.disabled, "transport has executable backpack control")
	# Regression: an initially empty property category must become executable
	# when switching to a legal player target, then become disabled again when
	# switching back to the still-invalid property category.
	var property_snapshots: Dictionary = {}
	for index in range(game.state.board.size()):
		var tile: Dictionary = game.state.board[index]
		if tile.get("kind", "") != "property":
			continue
		property_snapshots[index] = tile.duplicate(true)
		game.state.board[index]["owner"] = -1
		game.state.board[index]["building_level"] = 0
		game.state.board[index]["is_chain_store"] = false
		game.call("_update_tile_rent", game.state.board[index])
	var properties_snapshots: Array = []
	for player in game.state.players:
		properties_snapshots.append(player.get("properties", []).duplicate(true))
		player["properties"] = []
	game.call("_recalculate_property_values")
	game.call("_set_action_options", 0)
	ui.cards_popup.hide()
	ui._refresh_from_state()
	ui._on_cards_pressed()
	await process_frame
	use = ui.cards_popup.find_child("UseTool_傳送機", true, false)
	check(use != null and use.disabled, "transport is disabled when the property category has no source")
	check(select_id(ui.cards_popup.find_child("TransportKind", true, false), 2), "transport switches from empty property category to player category")
	use = ui.cards_popup.find_child("UseTool_傳送機", true, false)
	check(use != null and not use.disabled, "transport becomes enabled for a legal player selection")
	check(select_id(ui.cards_popup.find_child("TransportKind", true, false), 0), "transport switches back to the empty property category")
	use = ui.cards_popup.find_child("UseTool_傳送機", true, false)
	check(use != null and use.disabled, "transport becomes disabled again for the invalid property selection")
	ui.cards_popup.hide()
	for index_value in property_snapshots.keys():
		game.state.board[int(index_value)] = property_snapshots[index_value].duplicate(true)
	for index in range(properties_snapshots.size()):
		game.state.players[index]["properties"] = properties_snapshots[index].duplicate(true)
	game.call("_recalculate_property_values")
	game.call("_set_action_options", 0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	await process_frame
	check(select_transport(ui, 0, 2, 3), "transport selects property source and empty destination")
	var before: String = game.to_json()
	ui.cards_popup.hide()
	await process_frame
	check(game.to_json() == before, "closing selected transport preserves world, RNG and inventory")
	ui._on_cards_pressed()
	var selected := select_transport(ui, 0, 2, 3)
	use = ui.cards_popup.find_child("UseTool_傳送機", true, false)
	if selected and use != null and not use.disabled:
		check(Game.validate_save(game.to_dict()).get("ok", false), "property transport validates immediately before button")
		use.pressed.emit()
		await process_frame
		check(game.state.board[2].owner == -1 and game.state.board[2].building_level == 0, "property transport clears source")
		check(game.state.board[3].owner == 0 and game.state.board[3].building_level == 3, "property transport moves selected payload")
		check(game.state.players[0].tools.get("傳送機", 0) == 1, "property transport consumes one tool")
		check(not ui.cards_popup.visible, "property transport closes picker")
		check(ui.board_view.board_data[3].building_level == 3, "board receives relocated property")
		check(Game.validate_save(game.to_dict()).get("ok", false), "property transport UI result validates")
		ui._on_cards_pressed()
		selected = select_transport(ui, 2, 0, 9)
		check(selected, "transport offers self and a legal road destination")
		use = ui.cards_popup.find_child("UseTool_傳送機", true, false)
		if selected and use != null and not use.disabled:
			check(Game.validate_save(game.to_dict()).get("ok", false), "self transport validates immediately before button")
			use.pressed.emit()
			await process_frame
			check(game.state.players[0].position == 9, "self transport visibly moves the player")
			check(game.state.players[0].tools.get("傳送機", 0) == 0, "self transport consumes one tool")
			ui._on_cards_pressed()
			time_use = ui.cards_popup.find_child("UseTool_時光機", true, false)
			check(time_use != null and not time_use.disabled, "self transport establishes usable time anchor")
			if time_use != null and not time_use.disabled:
				check(Game.validate_save(game.to_dict()).get("ok", false), "time restore validates immediately before button")
				time_use.pressed.emit()
				await process_frame
				check(game.state.players[0].position == 2, "time button restores pre-transport position")
				check(game.state.players[0].tools.get("時光機", 0) == 0, "time button consumes exactly one restored tool")
				check(game.state.players[0].tools.get("傳送機", 0) == 1, "time restores pre-self-transport inventory")
				check(game.state.board[3].owner == 0 and game.state.board[3].building_level == 3, "time anchor retains earlier property relocation")
				check(not ui.cards_popup.visible, "time button closes backpack after restoration")
				check(Game.validate_save(game.to_dict()).get("ok", false), "time UI result is a legal save")
	ui.queue_free()
	await process_frame
	print("Time transport UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
