extends "res://tests/source_setup_ui.gd"


func _run() -> void:
	for reselect in [false, true]:
		var ui := SetupTestUI.new()
		root.add_child(ui)
		await process_frame
		await process_frame
		ui.set_process(false)
		_expect(ui._map_catalog_complete and ui.game_state != null, "fixture or explicit catalog has complete company capabilities")
		var before: Object = ui.game_state
		ui._on_source_start_requested()
		await process_frame
		var panel: Control = ui.source_shell.get_node("SourceSetupPanel")
		_expect(bool(panel.get("_selected_map").get("supports_original_companies", false)), "unchanged setup map resolves source capabilities instead of display snapshot")
		if reselect:
			panel.get_node("MapChoice_0").pressed.emit()
		panel.find_child("CharacterPortrait_4", true, false).pressed.emit()
		var vehicle: OptionButton = panel.get_node("InitialVehicle")
		vehicle.select(2)
		vehicle.item_selected.emit(2)
		panel.get_node("LandTenure").select(2)
		panel.get_node("OK").pressed.emit()
		await process_frame
		_expect(ui.game_state != before, "real source OK creates a new match, reselect=" + str(reselect))
		_expect(ui.game_state.get_stock_symbols().size() == 12 and bool(ui.state.get("original_companies", false)), "source OK preserves the twelve-stock company rules")
		_expect(int(ui.state.get("land_tenure_months", 0)) == 3, "source OK retains selected land period")
		_expect(ui.state.get("initial_human_flags", []) == [true,true,false,false] and ui.state.get("character_ids", []).slice(0,2) == [0,4], "source OK resolves ordered humans and unique AI")
		_expect(ui.state.get("initial_vehicle", "") == "car", "source OK retains source vehicle")
		_expect(not ui.source_shell.is_setup_visible(), "successful source OK returns to game")
		var validation: Dictionary = ui.game_state.validate_save(ui.game_state.to_dict())
		_expect(bool(validation.ok), "source OK result is a validated save")
		ui.queue_free()
		await process_frame
	print("Source setup factory checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
