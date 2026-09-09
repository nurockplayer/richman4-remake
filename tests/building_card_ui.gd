extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func select_id(picker: OptionButton, id: int) -> bool:
	if picker == null: return false
	for index in range(picker.item_count):
		if picker.get_item_id(index) == id:
			picker.select(index)
			picker.item_selected.emit(index)
			return true
	return false
func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var definition := Fixture.definition()
	var options: Dictionary = ui._default_setup_options(4, definition)
	expect(options.get("original_building_cards", false), "source capability enables building cards in setup")
	var started: bool = ui._new_game(4413, 4, definition, Fixture.new_game_options())
	expect(started, "UI explicit v13 new game succeeds")
	if not started:
		ui.game_state = Game.new_game_on_board(4413, 4, definition, Fixture.v12_game_options())
		ui.game_state.state.version = 13
		ui.game_state.state["original_building_cards"] = true
		ui._refresh_from_state()
	var game: Object = ui.game_state
	expect(game != null, "v12 fallback permits UI behavior seed")
	if game == null:
		ui.queue_free(); quit(1); return
	game.state.god_objects = []
	for id in range(4): game.set_player_ai(id, false)
	game.state.players[0].position = 0
	game._update_facility_records(1, {"owner": 0, "building_level": 0})
	game.state.players[0].properties = [1]
	game._update_facility_records(2, {"owner": 1, "building_level": 3, "facility_type": 1})
	game.state.players[1].properties = [7]
	for card in ["天使", "惡魔", "怪獸"]:
		expect(Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, card).get("ok", false), "grant UI building card " + card)
	game._recalculate_property_values()
	game._set_action_options(0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	for card in ["天使", "惡魔", "怪獸"]:
		var button: Button = ui.cards_popup.find_child("UseCard_" + card, true, false)
		expect(button != null and not button.disabled, "implemented UI button " + card)
	var target: OptionButton = ui.cards_popup.find_child("Target_天使", true, false)
	expect(select_id(target, 1), "angel picker includes empty facility")
	var type: OptionButton = ui.cards_popup.find_child("AngelFacilityType", true, false)
	expect(type != null, "angel empty-facility type picker appears")
	expect(select_id(type, 4), "angel allows laboratory selection")
	var before: String = game.to_json()
	ui.cards_popup.hide()
	expect(game.to_json() == before, "closing angel picker is atomic cancellation")
	ui._on_cards_pressed()
	target = ui.cards_popup.find_child("Target_天使", true, false)
	select_id(target, 1)
	type = ui.cards_popup.find_child("AngelFacilityType", true, false)
	select_id(type, 4)
	var use: Button = ui.cards_popup.find_child("UseCard_天使", true, false)
	if use != null and not use.disabled: use.pressed.emit()
	await process_frame
	expect(game.state.board[1].facility_type == 4 and game.state.board[1].building_level == 1, "actual angel button builds selected laboratory")
	expect(game.state.board[6].facility_type == 4 and game.state.board[6].building_level == 1, "angel updates other entrance")
	expect(not game.state.players[0].cards.has("天使"), "angel UI consumes card once")
	ui._on_cards_pressed()
	target = ui.cards_popup.find_child("Target_怪獸", true, false)
	expect(select_id(target, 7), "monster picker includes enemy building")
	use = ui.cards_popup.find_child("UseCard_怪獸", true, false)
	if use != null and not use.disabled: use.pressed.emit()
	await process_frame
	expect(game.state.board[7].building_level == 0 and game.state.board[7].owner == 1, "actual monster button destroys building and preserves landlord")
	expect(game.state.board[8].building_level == 0, "monster updates facility alias")
	ui._on_cards_pressed()
	target = ui.cards_popup.find_child("Target_惡魔", true, false)
	expect(select_id(target, 1), "demon picker allows own facility")
	use = ui.cards_popup.find_child("UseCard_惡魔", true, false)
	if use != null and not use.disabled: use.pressed.emit()
	await process_frame
	expect(game.state.board[1].building_level == 0 and game.state.board[1].owner == 0, "actual demon button clears own building preserving owner")
	expect(game.validate_save(game.to_dict()).get("ok", false), "UI card sequence leaves strict loadable save")
	expect(ui._setup_options_from_state().get("original_building_cards", false), "snapshot setup retains building cards")
	ui._map_catalog = [JSON.parse_string(JSON.stringify(definition))]
	ui._update_map_selector()
	ui._active_map_definition = {}
	ui._adopt_map_from_snapshot(game.to_dict())
	ui._on_end_restart_pressed()
	expect(ui.game_state != game and ui.game_state.state.get("version", 0) == 13, "restart preserves v13")
	expect(ui.game_state.validate_save(ui.game_state.to_dict()).get("ok", false), "restarted v13 validates")
	ui.queue_free()
	print("Building card UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
