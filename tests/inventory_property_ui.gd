extends SceneTree

const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
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

func prepare_player(ui, player_id: int, position: int, phase: String) -> void:
	ui.game_state.state.current_player = player_id
	ui.game_state.state.players[player_id].position = position
	ui.game_state.state.players[player_id].previous_position = 1
	ui.game_state.state.phase = phase
	ui.game_state.state.property_action_used = false
	ui.game_state._set_action_options(player_id)
	ui._refresh_from_state()

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var definition: Dictionary = Maps.normalize_map(Fixture.make()).definition
	var options := {"start_date": {"year": 1998, "month": 1, "day": 1}, "original_inventory": true}
	expect(ui._new_game(61, 2, definition, options), "property UI fixture starts")
	ui.game_state.set_player_ai(1, false)
	ui.game_state.state.players[1].position = 5
	ui.game_state.state.players[1].previous_position = 4
	prepare_player(ui, 0, 2, "await_action")
	expect(bool(ui.game_state.choose_action("buy").get("ok", false)), "property UI fixture buys home")
	prepare_player(ui, 0, 2, "await_roll")
	ui._on_cards_pressed()
	var worker: Button = ui.cards_popup.find_child("UseTool_機器工人", true, false)
	var worker_target: OptionButton = ui.cards_popup.find_child("Target_機器工人", true, false)
	expect(worker != null and not worker.disabled, "worker is available for owned visible home")
	expect(select_target(worker_target, 2), "worker target picker includes home")
	var cash_before: int = ui.state.players[0].cash
	if worker != null and not worker.disabled:
		worker.pressed.emit()
		expect(int(ui.state.board[2].building_level) == 1, "worker button upgrades selected home")
		expect(int(ui.state.players[0].cash) == cash_before, "worker button does not charge cash")
	ui.game_state._grant_card(0, "拆除")
	ui.game_state._set_action_options(0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	var demolish: Button = ui.cards_popup.find_child("UseCard_拆除", true, false)
	var demolish_target: OptionButton = ui.cards_popup.find_child("Target_拆除", true, false)
	expect(demolish != null and not demolish.disabled and select_target(demolish_target, 2), "demolition offers selected built home")
	if demolish != null and not demolish.disabled:
		demolish.pressed.emit()
		expect(int(ui.state.board[2].building_level) == 0, "demolition button lowers home one level")
	ui._on_cards_pressed()
	var roadblock: Button = ui.cards_popup.find_child("UseTool_路障", true, false)
	var road_target: OptionButton = ui.cards_popup.find_child("Target_路障", true, false)
	expect(roadblock != null and not roadblock.disabled and select_target(road_target, 1), "roadblock picker offers visible vacant road")
	if roadblock != null and not roadblock.disabled:
		roadblock.pressed.emit()
		expect(ui.state.get("roadblocks", {}).has("1"), "roadblock button places selected barrier")
		expect(ui.board_view.roadblocks_data.has("1"), "board view receives barrier overlay state")
	ui.game_state._grant_card(0, "拆除")
	ui.game_state._set_action_options(0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	demolish = ui.cards_popup.find_child("UseCard_拆除", true, false)
	demolish_target = ui.cards_popup.find_child("Target_拆除", true, false)
	expect(demolish != null and not demolish.disabled and select_target(demolish_target, 1), "demolition picker offers placed roadblock")
	if demolish != null and not demolish.disabled:
		demolish.pressed.emit()
		expect(ui.state.get("roadblocks", {}).is_empty() and ui.board_view.roadblocks_data.is_empty(), "demolition clears barrier state and overlay")
	ui.cards_popup.hide()
	Inventory.grant_tool(ui.game_state.state.inventory_supply, ui.game_state.state.players[0].tools, "路障")
	ui.game_state._set_action_options(0)
	ui._refresh_from_state()
	ui.board_view.pan_by(Vector2(100000, 0))
	expect(ui.board_view.visible_node_indices().is_empty(), "panned offscreen nodes are not visible targets")
	ui._on_cards_pressed()
	roadblock = ui.cards_popup.find_child("UseTool_路障", true, false)
	road_target = ui.cards_popup.find_child("Target_路障", true, false)
	expect(roadblock != null and roadblock.disabled and road_target != null and road_target.disabled, "offscreen road targets disable placement")
	ui.cards_popup.hide()
	ui.board_view.reset_view()
	prepare_player(ui, 1, 3, "await_action")
	expect(bool(ui.game_state.choose_action("buy").get("ok", false)), "purchase card fixture gives opponent a home")
	prepare_player(ui, 0, 3, "await_roll")
	ui.game_state._grant_card(0, "購地")
	ui.game_state._set_action_options(0)
	ui._refresh_from_state()
	var price: int = ui.state.board[3].cost
	var deposit_before: int = ui.state.players[1].deposit
	cash_before = ui.state.players[0].cash
	ui._on_cards_pressed()
	var purchase: Button = ui.cards_popup.find_child("UseCard_購地", true, false)
	expect(purchase != null and not purchase.disabled, "purchase card is usable on opponent home")
	if purchase != null and not purchase.disabled:
		purchase.pressed.emit()
		expect(int(ui.state.board[3].owner) == 0, "purchase button transfers current home")
		expect(int(ui.state.players[0].cash) == cash_before - price and int(ui.state.players[1].deposit) == deposit_before + price, "purchase button pays seller deposit from buyer cash")
	ui.queue_free()
	await create_timer(0.15).timeout
	print("Inventory property UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
