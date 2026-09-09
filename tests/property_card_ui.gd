extends SceneTree

const MainScene = preload("res://game/main.tscn")
const Fixture = preload("res://tests/fixtures/hazard_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func select_target(picker: OptionButton, tile_id: int) -> bool:
	if picker == null:
		return false
	for index in range(picker.item_count):
		if picker.get_item_id(index) == tile_id:
			picker.select(index)
			return true
	return false

func finish(ui: Node) -> void:
	ui.queue_free()
	print("Property card UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var definition := Fixture.definition()
	definition["supports_original_property_cards"] = true
	var options: Dictionary = ui._default_setup_options(4, definition)
	expect(options.get("original_property_cards", false), "complete source setup enables property cards")
	# Keep subsequent UI assertions reachable before the setup toggle is wired.
	options["original_property_cards"] = true
	expect(ui._new_game(42, 4, definition, options), "property-card UI game starts")
	expect(ui.state.get("version", 0) == 10, "property-card UI starts v10")
	if ui.state.get("version", 0) != 10:
		finish(ui)
		return
	var game: Object = ui.game_state
	game.state.god_objects = []
	game.state.players[0].position = 2
	for id in range(4):
		game.set_player_ai(id, false)
		game.state.players[id].properties = []
	game.state.board[2].owner = 0
	game.state.board[2].building_level = 1
	game.state.board[3].owner = 1
	game.state.board[3].building_level = 4
	game.state.players[0].properties = [2]
	game.state.players[1].properties = [3]
	game._update_tile_rent(game.state.board[2])
	game._update_tile_rent(game.state.board[3])
	game._recalculate_property_values()
	for card_id in ["換地", "換屋"]:
		expect(Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, card_id).get("ok", false), "grant UI fixture card " + card_id)
	game._set_action_options(0)
	ui._refresh_from_state()
	await process_frame
	ui._on_cards_pressed()
	for card_id in ["換地", "換屋"]:
		var use: Button = ui.cards_popup.find_child("UseCard_" + card_id, true, false)
		var picker: OptionButton = ui.cards_popup.find_child("Target_" + card_id, true, false)
		expect(use != null and not use.disabled, card_id + " exposes an executable button")
		expect(select_target(picker, 3), card_id + " offers the visible other property")
		expect(not select_target(picker, 2), card_id + " excludes the current property")
	var before: String = game.to_json()
	ui.cards_popup.hide()
	expect(game.to_json() == before, "closing property selection preserves game, cards and RNG")
	ui.board_view.pan_by(Vector2(10000, 10000))
	ui._on_cards_pressed()
	for card_id in ["換地", "換屋"]:
		var picker: OptionButton = ui.cards_popup.find_child("Target_" + card_id, true, false)
		var use: Button = ui.cards_popup.find_child("UseCard_" + card_id, true, false)
		expect(picker != null and picker.disabled and use != null and use.disabled, card_id + " cannot target a property outside the viewport")
	ui.cards_popup.hide()
	ui.board_view.pan_by(Vector2(-10000, -10000))
	ui._on_cards_pressed()
	var land_picker: OptionButton = ui.cards_popup.find_child("Target_換地", true, false)
	if select_target(land_picker, 3):
		var use: Button = ui.cards_popup.find_child("UseCard_換地", true, false)
		if use != null:
			use.pressed.emit()
	await process_frame
	expect(game.state.board[2].owner == 1 and game.state.board[3].owner == 0, "actual swap-land button exchanges the selected owners")
	expect(game.state.board[2].building_level == 1 and game.state.board[3].building_level == 4, "land swap retains buildings at their original sites")
	expect(not ui.cards_popup.visible, "successful property exchange closes inventory")
	ui._on_cards_pressed()
	var house_picker: OptionButton = ui.cards_popup.find_child("Target_換屋", true, false)
	if select_target(house_picker, 3):
		var use: Button = ui.cards_popup.find_child("UseCard_換屋", true, false)
		if use != null:
			use.pressed.emit()
	await process_frame
	expect(game.state.board[2].building_level == 4 and game.state.board[3].building_level == 1, "actual swap-house button exchanges the selected buildings")
	expect(game.state.board[2].owner == 1 and game.state.board[3].owner == 0, "house swap retains owners")
	expect(game.state.players[0].cards.is_empty(), "both successful exchanges consume their cards")
	expect(ui._setup_options_from_state().get("original_property_cards", false), "restart options preserve property-card mode")
	expect(ui._event_detail("card_used", {"card_id":"換地", "effect":"swap_ownership", "source_tile_id":2, "target_tile_id":3}).contains("所有權"), "land-swap history explains ownership exchange")
	expect(ui._event_detail("card_used", {"card_id":"換屋", "effect":"swap_buildings", "source_tile_id":2, "target_tile_id":3}).contains("建物"), "house-swap history explains building exchange")
	for malformed in [{}, [], null, "invalid", 1.5]:
		expect(ui._event_detail("card_used", {"card_id":"換地", "effect":"swap_ownership", "source_tile_id":malformed, "target_tile_id":3}).contains("未知格位"), "malformed exchange history does not break rendering")
	ui._map_catalog = [JSON.parse_string(JSON.stringify(definition))]
	ui._update_map_selector()
	ui._active_map_definition = {}
	ui._adopt_map_from_snapshot(game.to_dict())
	ui._on_end_restart_pressed()
	expect(ui.game_state != game, "loaded v10 end-screen restart creates a fresh game")
	expect(ui.game_state.state.get("version", 0) == 10 and ui.game_state.state.get("original_property_cards", false), "actual restart preserves v10 property-card capability")
	expect(ui.game_state.state.get("phase", "") == "await_roll", "restarted property-card game begins at roll phase")
	expect(ui.game_state.validate_save(ui.game_state.to_dict()).get("ok", false), "restarted property-card save validates")
	var legacy := Fixture.definition()
	expect(not ui._default_setup_options(4, legacy).get("original_property_cards", false), "hazard-only definition retains legacy setup")
	finish(ui)
