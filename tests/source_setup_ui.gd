extends SceneTree

const MainScene = preload("res://game/main.tscn")

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
	var ui := MainScene.instantiate()
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
	_expect(shell.has_method("show_setup"), "source shell exposes the setup surface")
	_expect(shell.has_method("is_setup_visible"), "source shell exposes setup visibility")
	ui._on_source_start_requested()
	await process_frame
	var setup: Node = shell.get_node_or_null("SourceSetupPanel")
	_expect(setup != null, "ordinary START creates the source setup panel")
	var setup_open := shell.has_method("is_setup_visible") and bool(shell.call("is_setup_visible"))
	_expect(setup_open, "ordinary START opens the source setup panel")
	if setup != null:
		_expect(setup.has_method("set_catalog"), "source setup accepts the validated map catalog")
		_expect(setup.has_method("collect_options"), "source setup exposes validated choices")
		_expect(setup.has_method("cancel"), "source setup has an explicit cancel path")
		_expect(setup.find_child("CharacterPortrait_0", true, false) != null, "source setup shows the first character portrait")
		_expect(setup.find_child("CharacterPortrait_11", true, false) != null, "source setup shows all twelve character portraits")
		_expect(setup.find_child("PlayerType_0", true, false) != null, "source setup exposes human or AI for player one")
		_expect(setup.find_child("PlayerType_3", true, false) != null, "source setup exposes human or AI for player four")
		_expect(setup.find_child("MapChoice_0", true, false) != null, "source setup exposes the first source map choice")
		_expect(setup.find_child("MapChoice_3", true, false) != null, "source setup exposes the fourth source map choice")
		_expect(setup.find_child("InitialFund", true, false) != null, "source setup keeps the initial fund selector")
		_expect(setup.find_child("DayLimit", true, false) != null, "source setup keeps the game time selector")
		_expect(setup.find_child("WealthTarget", true, false) != null, "source setup keeps the victory target selector")
		_expect(setup.find_child("InitialVehicle", true, false) != null, "source setup exposes the initial vehicle selector")
		_expect(setup.find_child("LandTenure", true, false) != null, "source setup exposes the bounded land-tenure status")
		_expect(setup.find_child("OK", true, false) != null and setup.find_child("EXIT", true, false) != null, "source setup has OK and EXIT controls")
		var land_tenure := setup.find_child("LandTenure", true, false) as OptionButton
		_expect(land_tenure != null and land_tenure.get_popup().is_item_disabled(1), "unsupported nonzero land tenure choices are visibly disabled")
		if land_tenure != null:
			land_tenure.select(1)
			var blocked_tenure: Dictionary = setup.call("collect_options")
			_expect(not bool(blocked_tenure.get("ok", false)), "unsupported nonzero land tenure cannot be silently discarded")
			land_tenure.select(0)
		var before_cancel: String = ui.game_state.to_json() if ui.game_state != null else JSON.stringify(ui.state)
		setup.call("cancel")
		await process_frame
		_expect(not bool(shell.call("is_setup_visible")), "EXIT closes the source setup panel")
		_expect((ui.game_state.to_json() if ui.game_state != null else JSON.stringify(ui.state)) == before_cancel, "cancel leaves the current match unchanged")
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
	ui.queue_free()
	await create_timer(0.1).timeout
	print("Source setup UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
