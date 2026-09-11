extends "res://tests/source_monthly_ui.gd"
class DiskIO extends "res://game/platform/save_slots.gd".FileSystemIO:
	var fail_rename := false
	func rename(source: String, destination: String) -> int:
		return ERR_CANT_CREATE if fail_rename else super.rename(source, destination)

class CountSlots extends "res://game/platform/save_slots.gd":
	var attempts := 0
	func write_automatic(payload: Variant, expected_fingerprint: Variant = null) -> Dictionary:
		attempts += 1
		return super.write_automatic(payload, expected_fingerprint)

const Slots = preload("res://game/platform/save_slots.gd")

func run() -> void:
	var folder := "/tmp/richman4-autosave-host-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(folder)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var ui := TitleTestUI.new()
	ui.source_settings_path = folder.path_join("settings.json")
	ui.source_hotkeys_path = folder.path_join("hotkeys.json")
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	var disk := DiskIO.new()
	var storage := CountSlots.new(folder.path_join("slots"), folder.path_join("legacy.json"), disk)
	ui.source_save_menu.storage = storage
	var game := monthly_game(14)
	var valid: Dictionary = Core.validate_save(game.to_dict())
	if not valid.get("ok", false):
		print("PRECONDITION_UNMET: ", valid)
		quit(2)
		return
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state()
	var automatic := folder.path_join("slots/auto.json")
	check(not FileAccess.file_exists(automatic), "load/refresh never fabricates a daily checkpoint")
	ui._on_end_turn_pressed()
	await settle()
	check(int(game.state.day) == 15 and game.state.phase == "await_roll", "qualified public full wrap settles day and admits next actor")
	check(ui.source_monthly_controller.is_open(), "daily settlement queues actual monthly report")
	check(not FileAccess.file_exists(automatic), "pending monthly acknowledgement delays autosave")
	var settled: String = game.to_json()
	ui.source_monthly_controller.report_panel.continued.emit()
	await settle()
	check(FileAccess.file_exists(automatic), "daily checkpoint is written after report ack")
	if FileAccess.file_exists(automatic):
		check(Core.from_dict(JSON.parse_string(FileAccess.get_file_as_string(automatic))).to_json() == settled, "automatic file preserves exact admitted ledger and RNG")
	check(not FileAccess.file_exists(folder.path_join("legacy.json")), "daily auto never writes legacy owner file")
	await inspect_checkpoint(ui, "auto-row")
	check(storage.attempts == 1, "exactly one write per acknowledged daily wrap")
	ui._refresh_from_state()
	ui._flush_source_autosave()
	check(storage.attempts == 1, "repeated refresh is once-only")
	ui._on_source_load_requested()
	await settle()
	check(ui.source_save_menu.visible and ui.source_save_menu.picker.select_row(0), "ordinary LOAD selects valid AUTO row")
	check(ui.source_save_menu.picker.confirm_selection(), "ordinary AUTO confirmation reaches storage read")
	for _frame in range(8): await process_frame
	var loaded: Object = ui.game_state
	check(loaded != game and not ui.source_save_menu.visible, "AUTO load adopts a newly validated owner through ordinary menu")
	ui._flush_source_autosave()
	check(storage.attempts == 1 and loaded.to_json() == settled, "reload adopts checkpoint without rewriting or repeating month settlement")
	var twin: Object = Core.from_dict(loaded.to_dict())
	var result: Dictionary = ui._invoke_game("roll")
	ui._handle_result(result)
	twin.roll()
	for _frame in range(500):
		if not ui._presentation_busy: break
		await create_timer(0.01).timeout
	check(loaded.to_json() == twin.to_json(), "loaded continuation retains deterministic dice, ledger and RNG")
	check(storage.attempts == 1, "non-wrap player action does not autosave")
	# Toggle applies at the next actual day wrap. Disabled wrap is not replayed.
	game = monthly_game(4)
	ui._cancel_presentation()
	ui.game_state = game
	await commit_autosave(ui, false)
	ui._refresh_from_state()
	ui._on_end_turn_pressed()
	await settle()
	check(int(game.state.day) == 5 and storage.attempts == 1, "disabled at wrap suppresses checkpoint")
	await commit_autosave(ui, true)
	ui._refresh_from_state()
	check(storage.attempts == 1, "enable mid-day never backfills previous wrap")
	game = monthly_game(7)
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state()
	disk.fail_rename = true
	var old_bytes := FileAccess.get_file_as_bytes(automatic)
	ui._on_end_turn_pressed()
	await settle()
	check(storage.attempts == 2 and ui._source_autosave.failed(), "actual rename failure is visible and retryable")
	check(FileAccess.get_file_as_bytes(automatic) == old_bytes, "failed disk replacement preserves previous AUTO")
	var old_dialog: ConfirmationDialog = ui._autosave_failure_dialog
	await inspect_checkpoint(ui, "failed-write")
	var failed_state: String = game.to_json()
	ui._on_ai_timer_timeout()
	ui._on_roll_pressed()
	ui._on_source_start_requested()
	ui._on_source_load_requested()
	ui._flush_source_autosave()
	check(game.to_json() == failed_state and storage.attempts == 2, "failed checkpoint gates actors and never busy-retries")
	disk.fail_rename = false
	ui._autosave_failure_dialog.hide()
	ui._autosave_failure_dialog.confirmed.emit()
	await settle()
	check(storage.attempts == 3 and not ui._source_autosave.pending(), "explicit retry commits retained stable snapshot")
	check(Core.from_dict(JSON.parse_string(FileAccess.get_file_as_string(automatic))).to_json() == failed_state, "retry snapshot is exact and settlement never repeats")
	# An owner replacement during pending monthly presentation cancels its save.
	game = monthly_game(31, false)
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state()
	result = ui._invoke_game("run_ai_turn")
	ui._handle_result(result)
	for _frame in range(500):
		if not ui._presentation_busy: break
		await create_timer(0.01).timeout
	await settle()
	check(int(game.state.day) == 32 and ui.source_monthly_controller.is_open(), "actual AI day wrap awaits month-end report")
	check(storage.attempts == 3, "AI/month-end pending report delays auto")
	ui._on_ai_timer_timeout()
	var next_game := monthly_game(2)
	ui._apply_loaded_game(next_game, next_game.to_dict(), false)
	await settle()
	check(storage.attempts == 3 and not ui._source_autosave.pending(), "owner replacement clears pending checkpoint epoch")
	game = monthly_game(7)
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state()
	disk.fail_rename = true
	ui._on_end_turn_pressed()
	await settle()
	check(storage.attempts == 4 and ui._source_autosave.failed(), "replacement owner can fail its own new daily write")
	disk.fail_rename = false
	if is_instance_valid(old_dialog): old_dialog.confirmed.emit()
	await settle()
	check(storage.attempts == 4 and ui._source_autosave.failed(), "stale previous-owner retry callback cannot act on new checkpoint")
	ui._autosave_failure_dialog.hide()
	ui._autosave_failure_dialog.confirmed.emit()
	await settle()
	check(storage.attempts == 5 and not ui._source_autosave.pending(), "new owner retry requires its current dialog")
	# Window X may deliver close_requested without canceled. It must release
	# this checkpoint without another write and restore every actor/menu gate.
	game = monthly_game(9)
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state()
	disk.fail_rename = true
	ui._on_end_turn_pressed()
	await settle()
	check(storage.attempts == 6 and ui._source_autosave.failed() and ui._autosave_failure_dialog.visible, "close-request fixture reaches real rename failure")
	var before_close: String = game.to_json()
	ui._autosave_failure_dialog.close_requested.emit()
	await settle()
	check(not ui._source_autosave.pending() and not ui._autosave_failure_dialog.visible, "close_requested alone hides dialog and skips pending checkpoint")
	check(storage.attempts == 6 and game.to_json() == before_close, "window close neither retries nor mutates ledger/RNG")
	ui._on_source_load_requested()
	await settle()
	check(ui.source_save_menu.visible, "window close restores ordinary load ingress")
	ui.source_save_menu.cancel()
	ui._on_source_start_requested()
	check(ui.source_shell.is_setup_visible(), "window close restores new-game ingress")
	ui._on_source_setup_cancelled()
	result = ui._invoke_game("roll")
	check(result.get("ok", false), "window close restores the admitted actor")
	ui._handle_result(result)
	for _frame in range(500):
		if not ui._presentation_busy: break
		await create_timer(0.01).timeout
	disk.fail_rename = false
	# Exercise the ordinary factory and its selected catalog definition, without
	# injecting elapsed/date/phase. AI public turns must reach an actual wrap.
	var map: Dictionary = ui._map_catalog[0]
	if OS.get_environment("RICHMAN4_AUTOSAVE_TEST_EDITION") == "MultiverseJourney":
		for candidate in ui._map_catalog:
			if candidate.get("source", {}).get("edition") == "MultiverseJourney":
				map = candidate
				break
	check(ui._new_game(42, 4, map, ui._default_setup_options(4, map)), "ordinary catalog factory starts a valid source-capable match")
	for id in range(4): ui.game_state.set_player_ai(id, true)
	ui._refresh_from_state()
	var fresh_store := CountSlots.new(folder.path_join("actual-slots"), folder.path_join("actual-legacy.json"))
	ui.source_save_menu.storage = fresh_store
	for turn in range(8):
		if int(ui.game_state.state.day) >= 2: break
		result = ui._invoke_game("run_ai_turn")
		check(result.get("ok", false), "ordinary AI turn reaches actual catalog rules")
		ui._handle_result(result)
		for _frame in range(500):
			if not ui._presentation_busy: break
			await create_timer(0.01).timeout
		await settle()
	check(int(ui.game_state.state.day) == 2 and fresh_store.attempts == 1, "actual catalog completes one full cycle and exactly one daily auto")
	check(fresh_store.read(0).get("source_identity") == "automatic", "ordinary row0 identifies new AUTO source")
	await inspect_checkpoint(ui, "catalog-auto-row")
	viewport.queue_free()
	await settle()
	print("Autosave MainUI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func inspect_checkpoint(_ui: Control, _label: String) -> void:
	pass

func commit_autosave(ui: Control, enabled: bool) -> void:
	var controller: Control = ui.source_options_controller
	var edition := str(ui.source_shell.get("_source_edition"))
	check(controller.open(ui.game_state, "game", edition, ui.source_shell.get("_visuals"), ui._future_start_date(), {"year": 1998, "month": 1, "day": 1}), "real options controller opens for daily toggle")
	var settings: Dictionary = controller.settings()
	settings.autosave = enabled
	controller.options_panel.accepted.emit(settings)
	await settle()
	check(not controller.is_open() and ui._source_settings.autosave == enabled, "persisted parent OK applies daily toggle")
	check(ui.SystemSettings.new().read_settings(ui.source_settings_path).get("settings", {}).get("autosave") == enabled, "daily toggle persisted to owned settings path")
