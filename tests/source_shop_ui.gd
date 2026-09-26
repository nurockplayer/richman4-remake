extends "res://tests/source_shop_catalog.gd"

var capture_records: Array = []
var capture_directory := ""

func run() -> void:
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("PRECONDITION_UNMET installed catalog required")
		quit(2)
		return
	var requested_edition := OS.get_environment("RICHMAN4_SHOP_EDITION")
	if requested_edition.is_empty(): requested_edition = "Game"
	var edition := "Game" if requested_edition == "Game1" else "MultiverseJourney" if requested_edition == "MJ7" else requested_edition
	var scale_value := int(OS.get_environment("RICHMAN4_SHOP_SCALE")) if not OS.get_environment("RICHMAN4_SHOP_SCALE").is_empty() else 1
	if requested_edition not in ["Game", "Game1", "MultiverseJourney", "MJ7"] or scale_value not in [1, 2]:
		print("PRECONDITION_UNMET edition must be Game1/MJ7 and scale 1/2")
		quit(2)
		return
	capture_directory = OS.get_environment("RICHMAN4_SHOP_CAPTURE")
	var view := SubViewport.new()
	view.size = Vector2i(640, 480) * scale_value
	view.gui_embed_subwindows = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.notify_mouse_entered()
	var ui := MainScene.instantiate()
	ui.scale = Vector2.ONE * scale_value
	view.add_child(ui)
	await settle()
	ui.set_process(false)
	var definition := find_map(ui, edition, 1 if edition == "Game" else 7)
	var source: Dictionary = definition.get("source", {})
	check(not definition.is_empty() and str(source.get("edition", "")) == edition and int(source.get("map_number", -1)) == (1 if edition == "Game" else 7), "requested catalog definition is active: " + edition)
	check(ui._new_game(1, 4, definition), "catalog-backed MainUI default game starts")
	var initial_source: Dictionary = ui._active_map_definition.get("source", {})
	check(str(initial_source.get("edition", "")) == edition and int(initial_source.get("map_number", -1)) == (1 if edition == "Game" else 7) and str(ui.game_state.state.map_source.edition) == edition, "active state and source edition match before owner bridge")
	var options: Dictionary = ui._default_setup_options(4, definition)
	var game: Object = await normal_shop(definition, options)
	check(game != null, "ordinary movement reaches a human shop visit")
	if game == null:
		quit(1)
		return
	var actor := int(game.state.current_player)
	game.state.players[actor].points = 10000
	var pending: Dictionary = game.to_dict()
	var prior_quit: bool = root.get_tree().auto_accept_quit
	ui._apply_loaded_game(game, pending, false)
	ui._sync_source_shop()
	if ui.news_popup.visible: ui.news_popup.hide()
	if ui.fate_popup.visible: ui.fate_popup.hide()
	await settle()
	ui._sync_source_shop()
	var controller: Control = ui.source_shop_controller
	var panel: Control = controller.panel
	check(panel != null and panel.is_open(), "loaded pending visit opens source panel")
	var actual_source: Dictionary = ui._active_map_definition.get("source", {})
	check(str(actual_source.get("edition", "")) == edition and str(game.state.map_source.edition) == edition, "owner bridge retains requested source edition")
	var visit: Dictionary = game.shop_visit_snapshot()
	check(str(visit.get("edition", "")) == edition and panel.source_geometry().edition == edition, "visit snapshot and Panel10 geometry use requested edition")
	if panel != null:
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
		if panel.is_open():
			await capture(view, ui, "card-offers")
			var offer: Dictionary = game.shop_visit_snapshot().card_offers[0]
			var points := int(game.state.players[actor].points)
			await _push_panel(view, panel, Vector2(14, 81), MOUSE_BUTTON_LEFT, true)
			check(game.state.players[actor].points == points - int(offer.price) and game.shop_visit_snapshot().card_offers[0].is_empty(), "viewport input buys one row and preserves its hole")
			var held := str(offer.get("id", ""))
			var held_index: int = game.state.players[actor].cards.find(held)
			check(held_index >= 0, "purchased card is held before sale")
			await capture(view, ui, "completed-hole-held")
			await _push_panel(view, panel, Vector2(233 + (held_index % 5) * 80 + 1, 299 + (held_index / 5) * 56 + 1), MOUSE_BUTTON_LEFT, true)
			check(held_index >= 0 and game.state.players[actor].cards.find(held) < 0, "viewport input sells one held card")
			var offers_before_tab: Array = game.state.shop_visit.card_offers.duplicate(true)
			var rng_before_tab: int = game._rng.state
			await _push_panel(view, panel, Vector2(542, 13), MOUSE_BUTTON_LEFT, true)
			await _push_panel(view, panel, Vector2(1, 479), MOUSE_BUTTON_LEFT, false)
			await settle()
			check(panel.view_model().mode == "tools" and game.state.shop_visit.card_offers == offers_before_tab and game._rng.state == rng_before_tab, "tab activates on release outside without reroll through viewport input")
			await capture(view, ui, "tools")
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
			var return_before: Dictionary = game.to_dict()
			await _push_panel(view, panel, Vector2(556, 246), MOUSE_BUTTON_LEFT, true)
			await _push_panel(view, panel, Vector2(1, 479), MOUSE_BUTTON_LEFT, false)
			await settle()
			check(game.state.phase == "await_action" and game.state.shop_visit.closed and not ui._source_shop_modal_open() and game.state.players[actor].points == int(return_before.players[actor].points) and game.state.players[actor].cards == return_before.players[actor].cards and game.state.inventory_supply == return_before.inventory_supply, "EXIT cancels and returns with completed trades preserved")
			check(root.get_tree().auto_accept_quit == prior_quit, "leaving shop restores the exact prior window-close policy")
			await capture(view, ui, "return-board")
			var right_owner: Object = Core.from_dict(save)
			ui._apply_loaded_game(right_owner, right_owner.to_dict(), false)
			ui._sync_source_shop()
			await settle()
			var right_panel: Control = ui.source_shop_controller.panel
			check(right_panel.is_open(), "saved visit reopens for right-up cancel")
			await _push_panel(view, right_panel, Vector2(1, 1), MOUSE_BUTTON_RIGHT, false)
			await settle()
			check(right_owner.state.phase == "await_action" and right_owner.state.shop_visit.closed and right_owner.state.inventory_supply == save.inventory_supply and right_owner.state.players[actor].cards == save.players[actor].cards, "right-up cancels a loaded visit and preserves completed trades")
	if not capture_directory.is_empty():
		var file := FileAccess.open(capture_directory.path_join("captures.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(capture_records))
	view.queue_free()
	await settle()
	print("Source shop UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func _push_panel(view: SubViewport, panel: Control, point: Vector2, button: MouseButton, down: bool) -> void:
	var transform := panel.get_global_transform_with_canvas()
	var canvas_point: Vector2 = transform * point
	var event := InputEventMouseButton.new()
	event.position = canvas_point
	event.global_position = canvas_point
	event.button_index = button
	event.pressed = down
	view.push_input(event, true)
	await process_frame

func capture(view: SubViewport, ui: Control, label: String) -> void:
	if capture_directory.is_empty(): return
	if DisplayServer.get_name() == "headless": return
	var panel: Control = ui.source_shop_controller.panel if ui.source_shop_controller != null else null
	var panel_open: bool = panel != null and panel.is_open()
	if FileAccess.file_exists("res://.local/imported-original/manifest.json"):
		if panel_open:
			check(panel.source_art_available(), "actual displayed Panel10 art loaded: " + label)
			var art_status: Dictionary = panel.source_art_status()
			for role in art_status:
				check(bool(art_status[role]), "actual displayed Panel10 role loaded (%s): %s" % [role, label])
	DirAccess.make_dir_recursive_absolute(capture_directory)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	var path := capture_directory.path_join(label + ".png")
	check(image != null and image.get_size() == view.size and image.save_png(path) == OK, "native viewport capture: " + label)
	var core_snapshot: Dictionary = ui.game_state.to_dict()
	var visit_snapshot: Dictionary = ui.game_state.shop_visit_snapshot()
	var snapshot_json := JSON.stringify(core_snapshot)
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(snapshot_json.to_utf8_buffer())
	var snapshot_hash := hash_context.finish().hex_encode()
	var mode: Variant = panel.view_model().mode if panel_open else null
	var geometry: Variant = panel.source_geometry() if panel_open else null
	capture_records.append({"path": path, "sha256": FileAccess.get_sha256(path), "size": [view.size.x, view.size.y], "panel_open": panel_open, "mode": mode, "geometry": geometry, "phase": ui.game_state.state.phase, "actor": int(ui.game_state.state.current_player), "edition": ui._active_map_definition.get("source", {}).get("edition", ""), "core_snapshot": core_snapshot, "core_snapshot_sha256": snapshot_hash, "shop_visit_snapshot": visit_snapshot, "review_head": OS.get_environment("RICHMAN4_REVIEW_HEAD"), "input": "injected loaded-owner/component capture; not physical OS ordinary entry"})
