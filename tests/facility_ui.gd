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
func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var raw := Fixture.make()
	raw.nodes[2].type_and_idx = 4001
	raw.nodes[3].type_and_idx = 4001
	raw.lands = []
	raw.facilities = [{"id": 1, "display_name": "測試設施", "name_bytes_hex": "74657374000000000000000000000000", "facility_type": 0, "owner": 0, "level": 0, "tmp_state": 0, "land_price": 1000, "price_per_level": 300, "house_price": 300, "reserved_hex": "6400c8002c019001f401"}]
	var loaded: Dictionary = Maps.normalize_map(raw, true)
	expect(bool(loaded.get("ok", false)), "facility UI source normalizes")
	if bool(loaded.get("ok", false)):
		var options := {"start_date": {"year": 1998, "month": 1, "day": 1}, "original_inventory": true, "original_facilities": true}
		var started: bool = ui._new_game(42, 2, loaded.definition, options)
		expect(started, "facility-only map starts from UI")
		if started:
			ui.game_state.state.players[0].position = 2
			ui.game_state.state.players[0].previous_position = 1
			ui.game_state.state.phase = "await_action"
			ui.game_state._set_action_options(0)
			ui._refresh_from_state()
			expect(not ui.buy_button.disabled, "unowned facility offers purchase")
			expect(ui.current_property_detail.text.contains("購地") and ui.current_property_detail.text.contains("建造"), "facility panel separates purchase and build prices")
			ui.buy_button.pressed.emit()
			expect(int(ui.state.board[2].owner) == 0 and int(ui.state.board[3].owner) == 0, "buy button acquires both entrances as one facility")
			expect(int(ui.state.board[2].building_level) == 0, "land purchase does not immediately build")
			ui.game_state.state.property_action_used = false
			ui.game_state._set_action_options(0)
			ui._refresh_from_state()
			expect(not ui.upgrade_button.disabled and ui.upgrade_button.text.contains("建造"), "owned vacant facility offers construction")
			var before_cancel: String = ui.game_state.to_json()
			ui.upgrade_button.pressed.emit()
			expect(ui.facility_popup.visible, "construction opens type selection")
			await process_frame
			await process_frame
			expect(ui.facility_popup.size.y <= 800, "construction choices and cancel fit the viewport")
			var laboratory: Button = ui.facility_popup.find_child("BuildFacility_4", true, false)
			expect(laboratory != null and laboratory.disabled, "unimplemented laboratory is explicitly disabled")
			ui.facility_popup.find_child("CancelFacility", true, false).pressed.emit()
			expect(not ui.facility_popup.visible and before_cancel == ui.game_state.to_json(), "cancel leaves money and facility state untouched")
			ui.upgrade_button.pressed.emit()
			ui.facility_popup.find_child("BuildFacility_1", true, false).pressed.emit()
			expect(not ui.facility_popup.visible, "successful construction closes selection")
			expect(int(ui.state.board[2].facility_type) == 1 and int(ui.state.board[2].building_level) == 1, "hotel selection creates first hotel level")
			expect(ui.current_property_label.text.contains("旅館"), "current facility identifies its chosen type")
			expect(ui.upgrade_button.disabled, "construction consumes the landing property action")
			ui.game_state.state.property_action_used = false
			ui.game_state._set_action_options(0)
			ui._refresh_from_state()
			expect(not ui.upgrade_button.disabled and ui.upgrade_button.text == "升級", "built hotel offers ordinary upgrade")
			ui.upgrade_button.pressed.emit()
			expect(int(ui.state.board[2].building_level) == 2 and int(ui.state.board[3].building_level) == 2, "upgrade updates the shared facility")
			ui.game_state.state.board[2].facility_state = 0x51
			ui.game_state.state.board[3].facility_state = 0x51
			ui._refresh_from_state()
			await process_frame
			expect(ui.current_property_detail.text.contains("查封") and ui.current_property_detail.text.contains("5 天"), "facility status is visible with remaining duration")
			expect(ui.end_turn_button.get_global_rect().end.y <= ui.size.y, "facility details preserve access to the end-turn control")
	ui.queue_free()
	await create_timer(0.1).timeout
	print("Facility UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
