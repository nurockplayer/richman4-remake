extends SceneTree

const MainScene = preload("res://game/main.tscn")
const Base = preload("res://tests/fixtures/property_card_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func finish(ui: Node) -> void:
	ui.queue_free()
	print("Remodel UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var definition := Base.definition()
	definition["supports_original_remodel"] = true
	for tile in definition.board:
		if tile.kind == "property":
			tile["is_chain_store"] = false
	var options: Dictionary = ui._default_setup_options(4, definition)
	expect(options.get("original_remodel", false), "complete map setup enables remodel")
	options["original_remodel"] = true
	expect(ui._new_game(42, 4, definition, options), "remodel UI starts a game")
	expect(ui.state.get("version", 0) == 11, "remodel UI starts v11")
	if ui.state.get("version", 0) != 11:
		finish(ui)
		return
	var game: Object = ui.game_state
	game.state.god_objects = []
	for id in range(4):
		game.set_player_ai(id, false)
	game.state.players[0].position = 2
	game.state.players[0].previous_position = -1
	for index in [2, 3]:
		game.state.board[index].owner = 0
		game.state.board[index].building_level = 1
		game.state.board[index].is_chain_store = index == 3
		game._update_tile_rent(game.state.board[index])
	game.state.players[0].properties = [2, 3]
	game._recalculate_property_values()
	expect(Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, "改建").get("ok", false), "grant remodel UI card")
	game._set_action_options(0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	var use: Button = ui.cards_popup.find_child("UseCard_改建", true, false)
	expect(use != null and not use.disabled, "built housing exposes remodel button")
	var before: String = game.to_json()
	ui.cards_popup.hide()
	expect(before == game.to_json(), "closing remodel popup changes no state")
	ui._on_cards_pressed()
	use = ui.cards_popup.find_child("UseCard_改建", true, false)
	if use != null and not use.disabled:
		use.pressed.emit()
	await process_frame
	expect(game.state.board[2].get("is_chain_store", false), "actual remodel button creates chain store")
	expect(ui.current_property_label.text.contains("連鎖店") or ui.current_property_detail.text.contains("連鎖店"), "property panel identifies chain store")
	expect(ui.current_property_detail.text.contains("4,000"), "property panel shows all-owned-chain rent")
	expect(ui.current_property_detail.text.contains("最高 1 級"), "property panel explains chain upgrade cap")
	expect(game.state.players[0].cards.is_empty(), "successful UI remodel consumes card")
	game.state.players[0].position = 1
	game._update_facility_records(1, {"owner":0, "building_level":4, "facility_type":1})
	game.state.players[0].properties.append(1)
	game._recalculate_property_values()
	Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, "改建")
	game._set_action_options(0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	var picker: OptionButton = ui.cards_popup.find_child("RemodelType_改建", true, false)
	expect(picker != null, "facility remodel offers a type picker")
	if picker != null:
		var selected := false
		for index in range(picker.item_count):
			if picker.get_item_id(index) == 3:
				picker.select(index)
				selected = true
			if picker.get_item_id(index) == 4:
				expect(picker.is_item_disabled(index), "unimplemented research remains unavailable")
		expect(selected, "gas-station remodel can be selected")
	use = ui.cards_popup.find_child("UseCard_改建", true, false)
	if use != null and not use.disabled and picker != null:
		use.pressed.emit()
	await process_frame
	expect(game.state.board[1].facility_type == 3 and game.state.board[1].building_level == 1, "actual facility button applies selected type and cap")
	expect(game.state.board[6].facility_type == 3 and game.state.board[6].building_level == 1, "facility remodel updates other entrance")
	expect(game.validate_save(game.to_dict()).get("ok", false), "UI remodelling leaves a valid save")
	game.state.players[0].position = 0
	Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, "改建")
	game._set_action_options(0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	use = ui.cards_popup.find_child("UseCard_改建", true, false)
	expect(use != null and use.disabled, "non-property tile disables remodel")
	ui.cards_popup.hide()
	expect(ui._setup_options_from_state().get("original_remodel", false), "snapshot setup preserves remodel")
	ui._map_catalog = [JSON.parse_string(JSON.stringify(definition))]
	ui._update_map_selector()
	ui._active_map_definition = {}
	ui._adopt_map_from_snapshot(game.to_dict())
	ui._on_end_restart_pressed()
	expect(ui.game_state != game and ui.game_state.state.get("version", 0) == 11, "loaded game restart preserves v11")
	expect(ui.game_state.validate_save(ui.game_state.to_dict()).get("ok", false), "restarted v11 game is valid")
	expect(not ui._default_setup_options(4, Base.definition()).get("original_remodel", false), "legacy map capability stays legacy")
	finish(ui)
