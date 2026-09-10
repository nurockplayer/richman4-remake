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
	# The current 440x440 source viewport is laid out on the next frame.  Put
	# the initial building-card target in view through the public camera API so
	# this test exercises card selection rather than the visibility filter.
	await process_frame
	var initial_camera_state: Dictionary = ui.board_view.get_camera_state()
	var initial_tile: Dictionary = game.state.board[1]
	var monster_tile: Dictionary = game.state.board[7]
	var target_world := Vector2(float(initial_tile.get("x", 0)), float(initial_tile.get("y", 0)))
	var monster_world := Vector2(float(monster_tile.get("x", 0)), float(monster_tile.get("y", 0)))
	var target_midpoint := (target_world + monster_world) * 0.5
	ui.board_view.set_zoom(0.55)
	var initial_target_screen: Vector2 = ui.board_view.map_to_screen(target_midpoint)
	var initial_viewport_size: Vector2 = initial_camera_state.get("viewport_size", Vector2.ZERO)
	ui.board_view.pan_by(initial_viewport_size * 0.5 - initial_target_screen)
	await process_frame
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
	var board_camera: Object = ui.board_view
	var target_tile: Dictionary = game.state.board[7]
	var target_position := Vector2(float(target_tile.get("x", 0)), float(target_tile.get("y", 0)))
	var camera_state: Dictionary = board_camera.get_camera_state()
	var target_screen: Vector2 = board_camera.map_to_screen(target_position)
	var viewport_size: Vector2 = camera_state.get("viewport_size", Vector2.ZERO)
	board_camera.pan_by(viewport_size * 0.5 - target_screen)
	await process_frame
	var manual_pan: Vector2 = board_camera.get_camera_state().get("pan", Vector2.ZERO)
	expect(board_camera.visible_node_indices().has(7), "camera setup moves monster target into the visible rect")
	ui._refresh_from_state()
	await process_frame
	expect(board_camera.get_camera_state().get("pan", Vector2.ZERO) == manual_pan, "current-player follow preserves a manually panned camera")
	ui._on_cards_pressed()
	await process_frame
	expect(board_camera.get_camera_state().get("pan", Vector2.ZERO) == manual_pan, "card popup refresh preserves a manually panned camera")
	target = ui.cards_popup.find_child("Target_怪獸", true, false)
	expect(select_id(target, 7), "monster picker includes enemy building")
	use = ui.cards_popup.find_child("UseCard_怪獸", true, false)
	if use != null and not use.disabled: use.pressed.emit()
	await process_frame
	expect(game.state.board[7].building_level == 0 and game.state.board[7].owner == 1, "actual monster button destroys building and preserves landlord")
	expect(game.state.board[8].building_level == 0, "monster updates facility alias")
	# Return the source camera to the current player's facility before opening
	# the demon picker; building-card targets are intentionally limited to the
	# visible 440x440 board region.
	var own_target: Dictionary = game.state.board[1]
	var own_world := Vector2(float(own_target.get("x", 0)), float(own_target.get("y", 0)))
	var own_screen: Vector2 = board_camera.map_to_screen(own_world)
	var own_viewport_size: Vector2 = board_camera.get_camera_state().get("viewport_size", Vector2.ZERO)
	board_camera.pan_by(own_viewport_size * 0.5 - own_screen)
	await process_frame
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
