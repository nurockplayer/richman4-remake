extends SceneTree

# Keep audio/owner preferences outside this setup test. CI uses a validated
# synthetic company catalog; an explicit local catalog uses the normal loader.
class SetupTestUI extends "res://game/ui/main_ui.gd":
	func _setup_audio() -> void: pass
	func _load_map_catalog(path: String = "", _allow_development_fallback: bool = false) -> void:
		if not OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
			super._load_map_catalog(path)
			return
		var fixture = preload("res://tests/fixtures/company_fixture.gd")
		_map_catalog = [fixture.definition()]
		_map_catalog_complete = _catalog_has_complete_original_content(_map_catalog)
		_map_catalog_ok = _map_catalog_complete
		_selected_map_definition = _map_catalog[0].duplicate(true)
		_update_map_selector()


var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var ui := SetupTestUI.new()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	if ui.audio_controller != null:
		ui.audio_controller.call("stop")
	var shell: Control = ui.source_shell
	_expect(shell != null, "source shell exists for ordinary START")
	if shell == null:
		quit(1)
		return
	_expect(bool(shell.call("is_title_visible")), "ordinary startup keeps the source title visible")
	_expect(shell.has_method("show_setup"), "source shell exposes the setup surface")
	_expect(shell.has_method("is_setup_visible"), "source shell exposes setup visibility")
	ui._on_source_start_requested()
	await process_frame
	var setup: Node = shell.get_node_or_null("SourceSetupPanel")
	_expect(setup != null, "ordinary START creates the source setup panel")
	var setup_open := shell.has_method("is_setup_visible") and bool(shell.call("is_setup_visible"))
	_expect(setup_open, "ordinary START opens the source setup panel")
	_expect(not bool(shell.call("is_title_visible")), "START hides the source title while setup is open")
	if setup != null:
		_expect(setup.has_method("set_catalog"), "source setup accepts the validated map catalog")
		_expect(setup.has_method("collect_options"), "source setup exposes validated choices")
		_expect(setup.has_method("cancel"), "source setup has an explicit cancel path")
		_expect(setup.find_child("CharacterPortrait_0", true, false) != null, "source setup shows the first character portrait")
		_expect(setup.find_child("CharacterPortrait_11", true, false) != null, "source setup shows all twelve character portraits")
		_expect(setup.find_child("PlayerType_0", true, false) == null, "source selects humans by portraits without an extra player-type control")
		_expect(setup.find_child("PlayerType_3", true, false) == null, "AI is filled on confirmation without invented slots")
		_expect(setup.find_child("MapChoice_0", true, false) != null, "source setup exposes the first source map choice")
		_expect(setup.find_child("MapChoice_3", true, false) != null, "source setup exposes the fourth source map choice")
		_expect(setup.find_child("InitialFund", true, false) != null, "source setup keeps the initial fund selector")
		_expect(setup.find_child("DayLimit", true, false) != null, "source setup keeps the game time selector")
		_expect(setup.find_child("WealthTarget", true, false) != null, "source setup keeps the victory target selector")
		_expect(setup.find_child("InitialVehicle", true, false) != null, "source setup exposes the initial vehicle selector")
		_expect(setup.find_child("LandTenure", true, false) != null, "source setup exposes the bounded land-tenure status")
		_expect(setup.find_child("MapStage", true, false) == null, "stage choice belongs to the upstream title menu")
		_expect(setup.find_child("MapChoiceLabel_0", true, false) != null and setup.find_child("MapChoiceCheck_0", true, false) != null, "source setup keeps visible map labels and selection markers")
		_expect(setup.find_child("SourceSettingLabel_0", true, false) != null and setup.find_child("SourceSettingLabel_5", true, false) != null, "source setup keeps visible labels for all six source settings")
		var source_frame := setup.find_child("SourcePortraitFrame", true, false) as TextureRect
		var settings_frame := setup.find_child("SourceSettingsFrame", true, false) as TextureRect
		_expect(source_frame != null and source_frame.position == Vector2(4, 10) and source_frame.size == Vector2(440, 155), "source setup keeps the source portrait frame geometry")
		_expect(settings_frame != null and settings_frame.position == Vector2(445, 10) and settings_frame.size == Vector2(192, 461), "source setup keeps the source settings strip geometry")
		_expect(setup.find_child("OK", true, false) != null and setup.find_child("EXIT", true, false) != null, "source setup has OK and EXIT controls")
		var land_tenure := setup.find_child("LandTenure", true, false) as OptionButton
		_expect(land_tenure != null and not land_tenure.get_popup().is_item_disabled(1), "reviewed nonzero land tenure choices are available")
		if land_tenure != null:
			land_tenure.select(1)
			var blocked_tenure: Dictionary = setup.call("collect_options")
			_expect(bool(blocked_tenure.get("ok", false)) and blocked_tenure.get("options", {}).get("land_tenure_months", -1) == 1, "source land tenure is retained for the factory")
			land_tenure.select(0)
		var before_cancel: String = ui.game_state.to_json() if ui.game_state != null else JSON.stringify(ui.state)
		setup.call("cancel")
		await process_frame
		_expect(not bool(shell.call("is_setup_visible")), "EXIT closes the source setup panel")
		_expect(bool(shell.call("is_title_visible")), "title START then EXIT returns to the visible source title")
		_expect((ui.game_state.to_json() if ui.game_state != null else JSON.stringify(ui.state)) == before_cancel, "cancel leaves the current match unchanged")
		shell.call("show_game")
		_expect(not bool(shell.call("is_title_visible")), "source game surface is visible before restart")
		ui._on_source_start_requested()
		await process_frame
		setup = shell.get_node_or_null("SourceSetupPanel")
		_expect(bool(shell.call("is_setup_visible")), "in-game restart opens the source setup panel")
		if setup != null:
			setup.call("cancel")
			await process_frame
			_expect(not bool(shell.call("is_title_visible")), "in-game restart then EXIT returns to the visible source game")
		ui._on_source_start_requested()
		await process_frame
		var confirmed_options: Dictionary = ui._default_setup_options(3, ui._active_map_definition)
		confirmed_options["character_ids"] = [0, 1, 2]
		confirmed_options["human_flags"] = [true, true, false]
		confirmed_options["initial_vehicle"] = "car"
		ui._on_source_setup_confirmed(confirmed_options, ui._active_map_definition)
		await process_frame
		var players: Array = ui.state.get("players", [])
		_expect(players.size() == 3, "source setup confirmation creates the requested player count")
		if players.size() == 3:
			_expect(bool(players[0].get("is_human", false)) and bool(players[1].get("is_human", false)) and bool(players[2].get("is_ai", false)), "source setup confirmation preserves selected human and AI controls")
			_expect(int(players[0].get("cash", 0)) == 100000 and int(players[0].get("deposit", 0)) == 100000 and int(players[1].get("cash", 0)) == 100000 and int(players[1].get("deposit", 0)) == 100000, "source setup confirmation gives each selected human equal opening cash and deposit")
			_expect(int(players[2].get("cash", 0)) == 140000 and int(players[2].get("deposit", 0)) == 60000, "source setup confirmation preserves the computer character cash ratio")
			_expect(players.all(func(player: Dictionary) -> bool: return str(player.get("vehicle", "")) == "car" and int(player.get("dice_count", 0)) == 3), "source setup confirmation applies the selected vehicle and dice")
			_expect(int(ui.state.get("inventory_supply", {}).get("tools", {}).get("汽車", -1)) == 7 and players.all(func(player: Dictionary) -> bool: return int(player.get("tools", {}).get("汽車", 0)) == 0), "source setup confirmation deducts equipped cars once from the shared supply")
			_expect(int(ui.state.get("bank", {}).get("deposits", -1)) == int(players[0].get("deposit", 0)) + int(players[1].get("deposit", 0)) + int(players[2].get("deposit", 0)), "source setup confirmation keeps bank deposits authoritative")
			var restart_options: Dictionary = ui._setup_options_from_state()
			_expect(restart_options.get("human_flags", []) == [true, true, false] and restart_options.get("initial_vehicle", "") == "car", "restart setup defaults preserve the selected source controls")
	var ordered_options := ui._default_setup_options(4, ui._active_map_definition)
	ordered_options.erase("character_ids")
	ordered_options.erase("human_flags")
	ordered_options["human_character_ids"] = [4,6]
	ordered_options["player_count"] = 4
	ordered_options["initial_vehicle"] = "walking"
	ordered_options["land_tenure_months"] = 3
	_expect(ui._new_game(115, 4, ui._active_map_definition, ordered_options), "source human selection enters the validated factory")
	_expect(ui.state.get("character_ids", []).slice(0,2) == [4,6] and ui.state.get("initial_human_flags", []) == [true,true,false,false], "factory preserves humans then fills computer identities")
	_expect(ui.state.get("land_tenure_months", -1) == 3 and ui._setup_options_from_state().get("land_tenure_months", -1) == 3, "land tenure survives source setup and restart defaults")
	_expect(ui.state.players.all(func(player: Dictionary) -> bool: return player.vehicle == "walking" and player.dice_count == 1), "car-to-walking restart resets every vehicle")
	var exact_state: String = ui.game_state.to_json()
	_expect(ui._new_game(115, 4, ui._active_map_definition, ordered_options) and ui.game_state.to_json() == exact_state, "fixed setup seed reproduces AI choice and full initial state")
	var setup_script := load("res://game/ui/source_setup_panel.gd")
	var map_probe: Control = setup_script.new()
	root.add_child(map_probe)
	await process_frame
	var map_definitions: Array = []
	for map_number in range(1, 9):
		map_definitions.append({"id": "mj:%d" % map_number, "source": {"edition": "MultiverseJourney", "map_number": map_number}})
	map_probe.call("set_catalog", map_definitions, map_definitions[0], {})
	_expect(int(map_probe.call("get_map_background_resource")) == 0, "MJ stage one starts at jump background resource zero")
	map_probe.call("set_catalog", map_definitions, map_definitions[4], {})
	_expect(int(map_probe.call("get_setup_atlas_offset")) == 21, "MJ stage two keeps the source setup atlas offset 21")
	_expect(int(map_probe.call("get_map_background_resource")) == 4, "MJ stage two starts at jump background resource four")
	map_probe.call("_select_map", 3)
	_expect(int(map_probe.call("get_map_background_resource")) == 7, "MJ stage two map four uses jump background resource seven")
	map_probe.queue_free()
	ui.queue_free()
	await create_timer(0.1).timeout
	print("Source setup UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
