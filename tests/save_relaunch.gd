extends SceneTree

## Two-process save/relaunch contract. Run the same script twice, sharing one
## RICHMAN4_USER_ROOT: phase `a` plays a few turns and saves slot 1 through the
## source save menu; phase `b` is a brand-new Godot process that loads slot 1
## through the source load menu, compares the snapshot and rolls the next
## human turn.

const MainScene = preload("res://game/main.tscn")
const UserPaths = preload("res://game/platform/user_paths.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _settle() -> void:
	await process_frame
	await process_frame


func _expected_path() -> String:
	return UserPaths.path("relaunch_expected.json")


func _slot_path() -> String:
	return UserPaths.path("richman4-save-slots/slot-1.json")


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


## check.sh shares one user root across every test, so this probe removes only
## its own artifacts instead of leaving slot 1 behind for later suites.
func _cleanup_artifacts() -> void:
	for path in [_slot_path(), _expected_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var slot_directory := UserPaths.path("richman4-save-slots")
	if DirAccess.dir_exists_absolute(slot_directory):
		var entries := DirAccess.get_files_at(slot_directory)
		if entries.is_empty():
			DirAccess.remove_absolute(slot_directory)


func _make_ui() -> Object:
	var ui: Object = MainScene.instantiate()
	root.add_child(ui)
	if ui.audio_controller != null:
		ui.audio_controller.call("stop")
	await process_frame
	ui.set_process(false)
	ui._set_development_path(true)
	ui._source_settings["autosave"] = false
	return ui


func _finish_presentation(ui: Object) -> void:
	if bool(ui._presentation_busy):
		ui._on_movement_finished()


func _new_classic(ui: Object) -> Object:
	var options := {
		"initial_fund": 200000,
		"day_limit": 0,
		"wealth_multiplier": 0,
		"start_date": {"year": 1998, "month": 1, "day": 1},
		"character_ids": [0, 1],
		"human_flags": [true, true],
	}
	var started: bool = ui._new_game(42, 2, ui._make_fallback_map_definition(), options)
	_expect(started, "MainUI creates the relaunch fixture match")
	return ui.game_state


func _play_human_turn(ui: Object, game: Object, player_id: int) -> void:
	_expect(int(game.state.current_player) == player_id, "player %d owns the resumed turn" % (player_id + 1))
	_expect(str(game.state.phase) == "await_roll", "player %d starts at the roll phase" % (player_id + 1))
	ui._on_roll_pressed()
	await _settle()
	_finish_presentation(ui)
	await _settle()
	_expect(str(game.state.phase) == "await_action", "player %d reaches the action phase" % (player_id + 1))
	ui._on_end_turn_pressed()
	await _settle()
	_finish_presentation(ui)
	await _settle()


func run_a() -> void:
	_cleanup_artifacts()
	var ui: Object = await _make_ui()
	var game := _new_classic(ui)
	if game == null:
		return
	_expect(int(game.state.day) == 1 and int(game.state.turn) == 1, "A starts on the first turn of day one")

	# First human turn: a real roll, a property purchase and a stock trade.
	ui._on_roll_pressed()
	await _settle()
	_finish_presentation(ui)
	await _settle()
	_expect(str(game.state.phase) == "await_action", "A's first roll lands on an action phase")
	var position := int(game.state.players[0].position)
	var tile: Dictionary = game.state.board[position]
	_expect(str(tile.get("kind", "")) == "property", "seed 42 lands A on a property")
	ui._on_buy_pressed()
	await _settle()
	_expect(game.state.players[0].properties.has(position), "A buys the landed property")
	var cash_before := int(game.state.players[0].cash)
	var stocks_before := int(game.state.players[0].stocks.get("tech", 0))
	var trade: Dictionary = ui._invoke_game("choose_action", ["buy_stock", {"symbol": "tech", "quantity": 1}])
	_expect(bool(trade.get("ok", false)), "A submits a stock purchase")
	ui._handle_result(trade)
	await _settle()
	_expect(int(game.state.players[0].stocks.get("tech", 0)) == stocks_before + 1, "A owns the purchased stock")
	_expect(int(game.state.players[0].cash) < cash_before, "A pays for the purchase and the stock")
	ui._on_end_turn_pressed()
	await _settle()

	# Second human turn, then back to the first player at a clean roll prompt.
	await _play_human_turn(ui, game, 1)
	_expect(int(game.state.current_player) == 0, "the match returns to the first player")
	_expect(str(game.state.phase) == "await_roll", "the first player is ready to roll again")
	_expect(int(game.state.day) >= 2, "A has advanced the calendar")
	_expect(not ui._source_autosave.pending(), "no automatic checkpoint blocks the manual save")

	var expected: Dictionary = game.to_dict()
	var expected_text := JSON.stringify(expected)
	_expect(_write_text(_expected_path(), expected_text), "A records the expected snapshot outside the slot")

	ui._on_source_save_requested()
	await _settle()
	_expect(ui.source_save_menu.visible, "A opens the source save menu")
	var scan: Dictionary = ui.source_save_menu.storage.scan()
	_expect(bool(scan.get("ok", false)), "A's save menu scans the slot rows")
	ui.source_save_menu.picker.confirmed.emit(1, "", {})
	await _settle()
	_expect(not ui.source_save_menu.visible, "A's save menu closes after writing")
	_expect(FileAccess.file_exists(_slot_path()), "A writes slot 1 under the isolated user root")
	var stored: Variant = JSON.parse_string(_read_text(_slot_path()))
	_expect(stored is Dictionary, "slot 1 holds a JSON snapshot")
	if stored is Dictionary:
		_expect(stored == JSON.parse_string(expected_text), "slot 1 stores the live match snapshot")
	var preview: Dictionary = ui.source_save_menu.storage.preview(1)
	_expect(str(preview.get("status", "")) == "valid", "slot 1 validates after the write")
	ui.queue_free()
	await _settle()


func run_b() -> void:
	var expected_text := _read_text(_expected_path())
	var expected: Variant = JSON.parse_string(expected_text)
	_expect(expected is Dictionary, "A left an expected snapshot in the shared user root")
	_expect(FileAccess.file_exists(_slot_path()), "slot 1 survives into the fresh process")
	var ui: Object = await _make_ui()
	ui._source_settings["autosave"] = false

	ui._on_source_load_requested()
	await _settle()
	_expect(ui.source_save_menu.visible, "B opens the source load menu")
	var preview: Dictionary = ui.source_save_menu.storage.preview(1)
	_expect(str(preview.get("status", "")) == "valid", "B reads slot 1 as valid")
	ui.source_save_menu.picker.confirmed.emit(1, str(preview.get("fingerprint", "")), preview)
	await _settle()
	await _settle()
	_expect(ui._legacy_save_modal_open(), "classic snapshot asks for the legacy-market confirmation")
	ui.legacy_save_dialog.confirmed.emit()
	await _settle()
	var game: Object = ui.game_state
	_expect(game != null, "B adopts the loaded match")
	if game == null:
		return
	var loaded_snapshot: Dictionary = game.to_dict()
	var loaded_parsed: Variant = JSON.parse_string(JSON.stringify(loaded_snapshot))
	_expect(loaded_parsed == expected, "the reloaded snapshot equals A's snapshot")
	if expected is Dictionary:
		_expect(int(game.state.seed) == int(expected.get("seed", 0)), "B keeps A's seed")
		_expect(int(game.state.day) == int(expected.get("day", 0)), "B keeps A's calendar day")
		_expect(int(game.state.turn) == int(expected.get("turn", 0)), "B keeps A's turn counter")
		_expect(int(game.state.current_player) == int(expected.get("current_player", -1)), "B keeps the pending actor")
		_expect(int(game.state.players[0].cash) == int(expected.players[0].cash), "B keeps A's cash")
		var loaded_properties: Variant = JSON.parse_string(JSON.stringify(loaded_snapshot.players[0].properties))
		var loaded_stocks: Variant = JSON.parse_string(JSON.stringify(loaded_snapshot.players[0].stocks))
		_expect(loaded_properties == expected.players[0].properties, "B keeps A's property portfolio")
		_expect(loaded_stocks == expected.players[0].stocks, "B keeps A's stock portfolio")
		_expect(loaded_properties is Array and not (loaded_properties as Array).is_empty(), "B loads the purchased property")
		_expect(loaded_stocks is Dictionary and int((loaded_stocks as Dictionary).get("tech", 0)) >= 1, "B loads the purchased stock")
		_expect(str(game.state.rng_state_text) == str(expected.get("rng_state_text", "")), "B keeps A's RNG cursor")
	_expect(str(game.state.phase) == "await_roll", "B resumes at the human roll prompt")
	_expect(int(game.state.current_player) == 0 and bool(game.state.players[0].is_human), "B resumes on the first human player")
	_expect(not ui.roll_button.disabled, "the reloaded roll control is enabled")
	var roll: Dictionary = ui._invoke_game("roll")
	_expect(bool(roll.get("ok", false)), "the reloaded human turn can roll")
	ui._handle_result(roll)
	await _settle()
	_finish_presentation(ui)
	await _settle()
	_expect(not game.state.last_roll.is_empty(), "the reloaded turn consumes a new roll")
	_expect(str(game.state.phase) != "await_roll", "the reloaded turn advances past the roll phase")
	ui.queue_free()
	await _settle()
	_cleanup_artifacts()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var phase := str(args[0]).to_lower() if args.size() > 0 else ""
	# Both phases delete slot 1; without a scratch root that would be the
	# owner's real save.
	if UserPaths.override_root().is_empty():
		_expect(false, "RICHMAN4_USER_ROOT must point at a throwaway directory")
	elif phase == "a":
		await run_a()
	elif phase == "b":
		await run_b()
	else:
		_expect(false, "run this script with `-- a` then `-- b`")
	print("Save relaunch (%s) checks: %d, failures: %d" % [phase, checks, failures])
	quit(1 if failures else 0)
