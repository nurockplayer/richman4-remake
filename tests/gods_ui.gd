extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func labels(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child in node.get_children():
		result += labels(child)
	return result
func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var loaded: Dictionary = Maps.normalize_map(Fixture.make(), true)
	expect(bool(loaded.get("ok", false)), "god UI map fixture normalizes")
	ui._selected_map_definition = loaded.definition
	var defaults: Dictionary = ui._default_setup_options(4)
	expect(bool(defaults.get("original_gods", false)), "source map new-game defaults enable gods")
	ui._selected_map_definition = {}
	expect(not bool(ui._default_setup_options(4).get("original_gods", false)), "asset-free fallback does not request graph-only gods")
	var options := {"start_date": {"year": 1998, "month": 1, "day": 1}, "original_inventory": true, "original_facilities": true}
	expect(ui._new_game(42, 4, loaded.definition, options), "legacy v5 UI game remains startable")
	ui.state["version"] = 6
	ui.state["original_gods"] = true
	ui.state["god_objects"] = [{"id": 1, "node": 2, "owner": 0, "days": 6}, {"id": 11, "node": 3, "owner": -1, "days": 0}]
	ui.state.players[0]["god_id"] = 1
	ui.state.players[0]["position"] = 2
	ui.state.players[0]["hospital_days"] = 3
	ui._update_all()
	await process_frame
	await process_frame
	var roster := labels(ui.players_list)
	expect(roster.contains("小財神") and roster.contains("6 天"), "roster names attached god and remaining days")
	expect(roster.contains("住院") and roster.contains("3 天"), "roster shows dog hospitalization")
	expect(ui.roll_button.text == "休養", "hospital turn offers rest instead of suggesting a dice roll")
	var drawn: Variant = ui.board_view.get("god_objects_data")
	expect(drawn is Array and drawn.size() == 2, "board receives attached and unbound god objects")
	expect(ui.end_turn_button.get_global_rect().end.y <= root.get_visible_rect().end.y, "four-player god roster preserves action-bar viewport")
	expect(bool(ui._setup_options_from_state().get("original_gods", false)), "restart preserves v6 gods capability")
	expect(ui._event_detail("god_attached", {"god_id": 1, "days": 7}).contains("小財神"), "attachment event uses player-facing god name")
	ui.board_view.set_map_definition(loaded.definition, true)
	drawn = ui.board_view.get("god_objects_data")
	expect(drawn is Array and drawn.is_empty(), "map preview clears live god markers")
	ui._update_property_card({"kind": "property", "index": 2, "cost": 1000, "land_price": 1000, "house_price": 300, "building_level": 2, "owner": -1})
	expect(ui.current_property_detail.text.contains("1,600"), "unowned angel-improved house shows total purchase price")
	ui.state["version"] = 5
	ui._update_all()
	expect(ui.board_view.god_objects_data.is_empty() and not labels(ui.players_list).contains("小財神"), "legacy saves ignore foreign god fields")
	expect(ui.roll_button.text == "擲骰", "legacy saves retain their original turn controls")
	ui.free()
	print("God UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
