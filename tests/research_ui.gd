extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Fixture = preload("res://tests/fixtures/research_fixture.gd")
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
func finish(ui: Node) -> void:
	ui.queue_free()
	print("Research UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var definition: Dictionary = Fixture.definition()
	var options: Dictionary = ui._default_setup_options(4, definition)
	expect(options.get("original_research", false), "complete source capability selects research rules")
	options["original_research"] = true
	expect(ui._new_game(8521, 4, definition, options), "UI starts explicit research game")
	expect(ui.state.get("version", 0) == 12, "research UI starts v12")
	if ui.state.get("version", 0) != 12:
		finish(ui); return
	var game: Object = ui.game_state
	game.state.god_objects = []
	for id in range(4): game.set_player_ai(id, false)
	game.state.players[0].position = 1
	game.state.players[0].previous_position = 0
	game.state.players[0].properties = [1]
	game.state.phase = "await_action"
	game.state.last_roll = [1]
	game.state.last_total = 1
	game.state.last_roll_total = 1
	game._update_facility_records(1, {"owner": 0, "building_level": 0})
	game._recalculate_property_values()
	game._set_action_options(0)
	ui._refresh_from_state()
	ui.upgrade_button.pressed.emit()
	var build: Button = ui.facility_popup.find_child("BuildFacility_4", true, false)
	expect(build != null and not build.disabled, "lab is selectable in real build popup")
	if build != null and not build.disabled: build.pressed.emit()
	await process_frame
	expect(game.state.board[1].facility_type == 4 and game.state.board[1].building_level == 1, "real build button constructs level-one research facility")
	var research: Button = ui.find_child("ResearchButton", true, false)
	expect(research != null and research.visible and not research.disabled, "research action appears after actual lab build")
	if research != null and not research.disabled: research.pressed.emit()
	var first: Button = ui.find_child("ResearchTool_9", true, false)
	var high: Button = ui.find_child("ResearchTool_10", true, false)
	expect(first != null and not first.disabled, "level-one tool can be selected")
	expect(high != null and high.disabled, "higher-level product is disabled")
	# Issue #98 acceptance: implemented research products must not advertise
	# themselves as having an unrestored use effect. Availability by lab level
	# is a separate concern from runtime implementation capability.
	for tool_id in range(10, 14):
		var tool_button := ui.find_child("ResearchTool_%d" % tool_id, true, false) as Button
		expect(tool_button != null, "research picker exposes implemented product %d" % tool_id)
		if tool_button != null:
			expect(not tool_button.tooltip_text.contains("尚未還原"), "implemented research product %d does not show stale unrestored-effect text" % tool_id)
	var before: Dictionary = game.to_dict()
	var cancel: Button = ui.find_child("CancelResearch", true, false)
	if cancel != null: cancel.pressed.emit()
	expect(game.to_dict() == before, "closing research picker leaves state exact")
	if research != null and not research.disabled: research.pressed.emit()
	first = ui.find_child("ResearchTool_9", true, false)
	if first != null and not first.disabled: first.pressed.emit()
	await process_frame
	expect(game.state.board[1].research_tool == 1 and game.state.board[1].research_turns == 5, "real product button schedules five owner turns")
	expect(game.state.board[6].research_turns == 5, "selection updates other facility entrance")
	expect(str(ui.current_property_detail.text).contains("機器工人") and str(ui.current_property_detail.text).contains("5"), "property panel reports product and remaining owner turns")
	expect(game.validate_save(game.to_dict()).get("ok", false), "UI selection leaves loadable v12 state")
	expect(research != null and (not research.visible or research.disabled), "same visit cannot schedule twice")
	Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, "改建")
	game._set_action_options(0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	var picker: OptionButton = ui.cards_popup.find_child("RemodelType_改建", true, false)
	expect(picker != null and not picker.is_item_disabled(4), "v12 remodel picker enables research facility")
	ui.cards_popup.hide()
	expect(ui._setup_options_from_state().get("original_research", false), "loaded setup preserves research option")
	ui._map_catalog = [JSON.parse_string(JSON.stringify(definition))]
	ui._update_map_selector()
	ui._active_map_definition = {}
	ui._adopt_map_from_snapshot(game.to_dict())
	ui._on_end_restart_pressed()
	expect(ui.game_state != game and ui.game_state.state.get("version", 0) == 12, "restart preserves v12")
	expect(ui.game_state.validate_save(ui.game_state.to_dict()).get("ok", false), "restarted v12 save validates")
	finish(ui)
