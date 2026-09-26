extends "res://tests/source_shop_catalog.gd"

func run() -> void:
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("PRECONDITION_UNMET installed catalog required")
		quit(2)
		return
	var view := SubViewport.new()
	view.size = Vector2i(640, 480)
	view.gui_embed_subwindows = true
	root.add_child(view)
	var ui := MainScene.instantiate()
	view.add_child(ui)
	await settle()
	ui.set_process(false)
	var definition := find_map(ui, "Game", 1)
	var options: Dictionary = ui._default_setup_options(4, definition)
	options.human_flags = [true, true, true, true]
	check(ui._new_game(1, 4, definition, options), "catalog-backed MainUI is startable")
	var game: Object = await normal_shop(definition, options)
	check(game != null, "public movement produces a human shop visit")
	if game == null:
		quit(1)
		return
	var actor := int(game.state.current_player)
	game.state.players[actor].points = 10000
	var pending: Dictionary = game.to_dict()
	ui._apply_loaded_game(game, pending, false)
	ui._sync_source_shop()
	if ui.news_popup.visible: ui.news_popup.hide()
	if ui.fate_popup.visible: ui.fate_popup.hide()
	await settle()
	ui._sync_source_shop()
	var controller: Control = ui.source_shop_controller
	var panel: Control = controller.panel
	check(panel != null and panel.is_open(), "loaded pending visit opens source panel")
	check(ui._source_modal_open() and ui._load_blocked_by_presentation() and not ui._source_save_operation_allowed(), "shop owns modal, load, and save gates")
	check(not root.get_tree().auto_accept_quit, "shop owns window-close policy")
	var before: String = game.to_json()
	ui._on_roll_pressed()
	ui._on_source_stocks_requested()
	ui._on_source_start_requested()
	ui._on_source_load_requested()
	ui._on_source_cards_requested()
	ui._on_source_tools_requested()
	ui._on_new_game_pressed()
	ui._on_ai_timer_timeout(ui._presentation_generation)
	check(game.to_json() == before and not ui.new_game_popup.visible, "pending shop blocks competing operations")
	if panel != null and panel.is_open():
		var offer: Dictionary = game.shop_visit_snapshot().card_offers[0]
		var points := int(game.state.players[actor].points)
		panel._gui_input(_event(Vector2(14, 81), MOUSE_BUTTON_LEFT, true))
		await settle()
		check(game.state.players[actor].points == points - int(offer.price) and game.shop_visit_snapshot().card_offers[0].is_empty(), "source panel buys one row and preserves its hole")
		var offers: Array = game.state.shop_visit.card_offers.duplicate(true)
		var rng_state: int = game._rng.state
		panel._gui_input(_event(Vector2(542, 13), MOUSE_BUTTON_LEFT, true))
		panel._gui_input(_event(Vector2(1, 479), MOUSE_BUTTON_LEFT, false))
		await settle()
		check(panel.view_model().mode == "tools" and game.state.shop_visit.card_offers == offers and game._rng.state == rng_state, "tab activates on up outside and does not reroll")
		var save: Dictionary = game.to_dict()
		check(Core.validate_save(save).ok and Core.from_dict(JSON.parse_string(game.to_json())) != null, "pending traded visit passes save validation and round trips")
		var old_panel := panel
		var replacement: Object = Core.from_dict(save)
		ui._apply_loaded_game(replacement, replacement.to_dict(), false)
		old_panel.action_requested.emit("buy_item", {"visit_id": int(save.shop_visit.visit_id), "item_kind": "tool", "source_id": 2, "offer_index": 0})
		await settle()
		check(controller.panel != old_panel and controller.panel.is_open(), "formal owner replacement rebuilds a visit-guarded panel")
		check(replacement.state.phase == "await_shop" and game.to_dict() == save, "stale panel cannot mutate either owner")
		game = replacement
		controller = ui.source_shop_controller
		panel = controller.panel
		panel._gui_input(_event(Vector2(556, 246), MOUSE_BUTTON_LEFT, true))
		panel._gui_input(_event(Vector2(1, 479), MOUSE_BUTTON_LEFT, false))
		await settle()
		check(game.state.phase == "await_action" and not ui._source_shop_modal_open(), "EXIT leaves the shop after a latched release")
		check(root.get_tree().auto_accept_quit, "leaving shop restores window-close policy")
	else:
		check(false, "source panel is available for interaction checks")
	view.queue_free()
	await settle()
	print("Source shop UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func _event(point: Vector2, button: MouseButton, down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = down
	return event
