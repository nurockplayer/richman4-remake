extends "res://tests/source_inventory_test_helper.gd"
const Core = preload("res://game/core/game_state.gd")

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
	check(ui._new_game(160,4,definition,ui._default_setup_options(4,definition)),"catalog-backed lifecycle owner")
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
	var old_panel: Control = ui.source_inventory_panel
	var replacement: Object = Core.from_dict(game.to_dict())
	ui.game_state = replacement
	ui._refresh_from_state()
	check(not old_panel.is_open() and not ui._source_inventory_modal_open(),"replaced owner clears stale held list")
	old_panel.selected.emit(1)
	check(game.to_json() == before and replacement.to_json() == before,"stale callback cannot affect either owner")
	check(auto_accept_quit == prior_quit,"owner replacement restores original quit policy")
	ui._on_source_cards_requested()
	ui._presentation_generation += 1
	old_panel.selected.emit(1)
	check(ui._source_inventory_modal_open(),"old generation callbacks cannot consume the active list")
	ui._close_source_inventory()
	await settle()
	check(not ui._source_inventory_modal_open() and auto_accept_quit == prior_quit,"cancel returns to board and restores quit policy")
	view.queue_free()
	await settle()
	print("Source inventory lifetime checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
