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
	expect(bool(loaded.get("ok", false)), "fortune facility UI source normalizes")
	var options := {"start_date": {"year": 1998, "month": 1, "day": 1}, "original_facilities": true, "original_gods": true}
	var started: bool = ui._new_game(42, 4, loaded.definition, options)
	expect(started, "fortune facility UI starts v6 game")
	if started:
		var game = ui.game_state
		game.state.players[0].position = 2
		game.state.players[0].previous_position = 1
		game.state.players[0].god_id = 3
		game.state.god_objects = [{"id": 3, "node": 2, "owner": 0, "days": 7}]
		game.state.phase = "await_action"
		game._set_action_options(0)
		ui._refresh_from_state()
		var before: String = game.to_json()
		var cash_before: int = game.state.players[0].cash
		ui.buy_button.pressed.emit()
		expect(ui.facility_popup.visible, "fortune purchase requests a free-building type")
		expect(game.to_json() == before, "opening fortune choice does not buy or consume RNG")
		if ui.facility_popup.visible:
			await process_frame
			await process_frame
			expect(ui.facility_popup.find_child("BuildFacility_4", true, false).disabled, "unsupported laboratory stays disabled for fortune construction")
			ui.facility_popup.find_child("CancelFacility", true, false).pressed.emit()
			expect(game.to_json() == before, "canceling fortune purchase preserves entire state")
			ui.buy_button.pressed.emit()
			ui.facility_popup.find_child("BuildFacility_1", true, false).pressed.emit()
			expect(not ui.facility_popup.visible, "fortune purchase closes type chooser")
			expect(int(game.state.players[0].cash) == cash_before - 1000, "fortune purchase charges only land price")
			for node in [2, 3]:
				expect(int(game.state.board[node].owner) == 0 and int(game.state.board[node].building_level) == 1 and int(game.state.board[node].facility_type) == 1, "fortune choice creates shared first-level hotel")
			expect(bool(game.state.property_action_used), "fortune purchase and free construction consume one landing action")
			expect(ui.current_property_label.text.contains("旅館"), "chosen fortune building is visible immediately")
	ui.free()
	print("God facility UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
