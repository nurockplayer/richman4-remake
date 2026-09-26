extends "res://tests/source_inventory_test_helper.gd"
const Core = preload("res://game/core/game_state.gd")
const Catalogue = preload("res://game/content/original_inventory.gd")

func run() -> void:
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("PRECONDITION_UNMET actual catalog required")
		quit(2)
		return
	var view := SubViewport.new()
	view.size = Vector2i(640,480)
	root.add_child(view)
	var ui: Variant = make_ui(view)
	await settle()
	var definition := find_map(ui,"Game",1)
	var setup_options: Dictionary = ui._default_setup_options(4,definition)
	setup_options["original_hazards"] = true
	check(ui._new_game(160,4,definition,setup_options),"catalog-backed lifecycle owner")
	var game: Object = ui.game_state
	var before: String = game.to_json()
	var prior_quit := auto_accept_quit
	ui._on_source_cards_requested()
	check(ui._source_inventory_modal_open() and not auto_accept_quit,"held list owns a modal quit hold")
	var generation: int = ui._inventory_generation
	ui._on_source_tools_requested()
	check(ui._inventory_mode == "cards" and ui._inventory_generation == generation,"second entry cannot replace active list")
	ui._on_source_start_requested()
	ui._on_source_load_requested()
	ui._on_source_ai_requested()
	ui._on_roll_pressed()
	check(game.to_json() == before and ui._source_inventory_modal_open(),"new/load/AI/roll paths cannot mutate active game")
	ui._close_source_inventory()
	await settle()
	ui._on_source_tools_requested()
	await settle()
	var old_panel: Control = ui.source_inventory_panel
	check(old_panel.view_model().mode == "tools" and old_panel.is_open(),"owner race opens the Tools list")
	var old_has_source3 := false
	for slot in range(15): old_has_source3 = old_has_source3 or old_panel.slot_source_id(slot) == 3
	check(old_has_source3,"default game actually holds source tool 3")
	var replacement: Object = Core.from_dict(game.to_dict())
	old_panel.selected.emit(3)
	ui.game_state = replacement
	ui._refresh_from_state()
	check(not old_panel.is_open() and not ui._source_inventory_modal_open(),"replaced owner clears stale held list")
	await settle()
	check(game.to_json() == before and replacement.to_json() == before and not ui._source_inventory_modal_open() and not ui.cards_popup.visible,"stale owner callback cannot mutate either game or open a target")
	check(auto_accept_quit == prior_quit,"owner replacement restores original quit policy")
	ui._on_source_tools_requested()
	await settle()
	var current_panel: Control = ui.source_inventory_panel
	var current_has_source3 := false
	for slot in range(15): current_has_source3 = current_has_source3 or current_panel.slot_source_id(slot) == 3
	check(current_panel.is_open() and current_panel.view_model().mode == "tools" and current_has_source3,"current generation test uses Tools mode with held source tool 3")
	var current_owner: Object = ui.game_state
	current_panel.selected.emit(3)
	ui._presentation_generation += 1
	await settle()
	check(game.to_json() == before and current_owner == ui.game_state and current_owner.to_json() == before,"stale generation callback preserves game JSON and current owner")
	check(ui._source_inventory_modal_open() and current_panel.is_open() and not ui.cards_popup.visible,"stale generation callback leaves current held list open")
	check(not auto_accept_quit,"stale generation callback retains modal quit hold")
	ui._close_source_inventory()
	await settle()
	check(not ui._source_inventory_modal_open() and auto_accept_quit == prior_quit,"cancel returns to board and restores quit policy")
	# Exercise the production starting roadblock through queue-before-cancel.
	var roadblock_owner: Object = ui.game_state
	roadblock_owner.state.phase = "await_roll"
	roadblock_owner._set_action_options(0)
	ui._refresh_from_state()
	ui._on_source_tools_requested()
	await settle()
	var roadblock_id := int(Catalogue.tool("路障").source_id)
	var roadblock_panel: Control = ui.source_inventory_panel
	var roadblock_count := int(roadblock_owner.state.players[0].tools.get("路障", 0))
	var roadblock_before: String = roadblock_owner.to_json()
	check(roadblock_panel.is_open() and roadblock_count > 0, "ordinary starting inventory contains a usable roadblock")
	roadblock_panel.selected.emit(roadblock_id)
	await settle()
	var roadblock_use: Button = ui.cards_popup.find_child("UseTool_路障",true,false)
	var roadblock_picker: OptionButton = ui.cards_popup.find_child("Target_路障",true,false)
	check(ui.cards_popup.visible and roadblock_use != null and not roadblock_use.disabled and roadblock_picker != null and not roadblock_picker.disabled, "starting roadblock exposes a legal target adapter")
	if roadblock_use != null:
		roadblock_use.call_deferred("emit_signal", "pressed")
		ui.cards_popup.hide()
		await settle()
		check(roadblock_panel.is_open() and ui.game_state == roadblock_owner and roadblock_owner.to_json() == roadblock_before and int(roadblock_owner.state.players[0].tools.get("路障", 0)) == roadblock_count and not auto_accept_quit, "queued roadblock use is revoked with unchanged effect, quantity, active owner, and modal hold")
		ui._close_source_inventory()
		await settle()
		check(not ui._source_inventory_modal_open() and auto_accept_quit == prior_quit, "roadblock cancellation returns cleanly and restores quit policy")
	else:
		check(false, "queued roadblock callback was created")
	view.queue_free()
	await settle()
	print("Source inventory lifetime checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
