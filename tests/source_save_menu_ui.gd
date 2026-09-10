extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Storage = preload("res://game/platform/save_slots.gd")

class TestUI extends "res://game/ui/main_ui.gd":
	var direct_load_calls := 0
	var direct_save_calls := 0
	func _setup_audio() -> void: pass
	func _load_game() -> void: direct_load_calls += 1
	func _save_game() -> void: direct_save_calls += 1
	func _load_map_catalog(_path: String = "", _fallback: bool = false) -> void:
		if not OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
			super._load_map_catalog(_path)
			return
		_map_catalog = [preload("res://tests/fixtures/company_fixture.gd").definition()]
		_map_catalog_complete = _catalog_has_complete_original_content(_map_catalog)
		_map_catalog_ok = _map_catalog_complete
		_selected_map_definition = _map_catalog[0].duplicate(true)
		_update_map_selector()

var checks := 0
var failures := 0
var temp_root := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for step in range(5):
		await process_frame

func run() -> void:
	temp_root = "/tmp/richman4-source-save-menu-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(DirAccess.make_dir_recursive_absolute(temp_root) == OK, "isolated test root exists")
	var store := Storage.new(temp_root.path_join("slots"), temp_root.path_join("default.json"))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var ui := TestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	var shell: Control = ui.source_shell
	var before: String = ui.game_state.to_json()
	var menu: Control = shell.get_node_or_null("SourceSaveMenu")
	if menu != null:
		menu.set("storage", store)
	shell.title_load_button.pressed.emit()
	await process_frame
	check(ui.direct_load_calls == 0, "title LOAD opens picker instead of reading default path directly")
	check(menu != null and menu.visible, "title LOAD presents the source save menu")
	if menu == null:
		ui.queue_free()
		await settle()
		finish()
		return
	check(menu.get("picker").get_mode() == "load", "title LOAD uses six-row load picker")
	check(ui._source_modal_open(), "picker blocks game input and AI scheduling")
	check(ui.game_state.to_json() == before, "opening picker preserves current state and RNG")
	_secondary_cancel(viewport, menu)
	check(not menu.visible and shell.is_title_visible(), "title cancel returns to title intent")
	check(ui.game_state.to_json() == before, "title cancel preserves current game")

	# Use a real source-capability game made by the ordinary factory as slot A.
	var snapshot_a: Dictionary = ui.game_state.to_dict()
	check(store.write(1, snapshot_a).get("ok", false), "source-capability slot A writes")
	check(ui._new_game(12922, 4, ui._selected_map_definition, ui._default_setup_options(4, ui._selected_map_definition)), "second live game constructs")
	var before_b: String = ui.game_state.to_json()
	# Ordinary source-board shortcuts must use the same picker as HUD controls.
	# The legacy overrides count attempted owner-path access without doing I/O.
	for mode in ["save", "load"]:
		_ctrl_shortcut(viewport, KEY_S if mode == "save" else KEY_L)
		check(menu.visible and menu.get("picker").get_mode() == mode, "Ctrl shortcut opens source " + mode + " chooser")
		check(ui.direct_save_calls == 0 and ui.direct_load_calls == 0, "Ctrl shortcut never reaches direct owner-path " + mode + " adapter")
		check(ui.game_state.to_json() == before_b, "Ctrl shortcut preserves current state and RNG for " + mode)
		if menu.visible:
			menu.cancel()
		# Isolate failures from subsequent, already existing entry assertions.
		ui.direct_save_calls = 0
		ui.direct_load_calls = 0
	shell.load_requested.emit()
	check(menu.visible and not shell.is_title_visible(), "HUD LOAD opens chooser over current game")
	_press_row(viewport, menu, 1)
	check(menu.is_busy(), "load confirmation enters guarded work state")
	await settle()
	check(not menu.visible, "successful load closes source picker")
	check(ui.state.seed == snapshot_a.seed and ui.game_state.to_json() != before_b, "selected source-capability game is adopted")
	check(not shell.is_title_visible(), "load success returns to board")
	check(ui.direct_load_calls == 0, "slot adoption never reopens default path")

	# A changed valid file cannot be loaded under an earlier selection.
	shell.load_requested.emit()
	menu.get("picker").select_slot(1)
	var replacement: Object = Game.new_game_on_board(12933, 4, ui._selected_map_definition, ui._default_setup_options(4, ui._selected_map_definition))
	check(replacement != null, "replacement uses the real factory to preserve setup seed invariants")
	var changed: Dictionary = replacement.to_dict() if replacement != null else {}
	check(store.write(1, changed).get("ok", false), "external valid replacement is written")
	var unchanged: String = ui.game_state.to_json()
	_press_row(viewport, menu, 1)
	await settle()
	check(menu.visible and not menu.is_busy(), "stale selection remains in chooser")
	check(menu.get("message_label").visible and not menu.get("message_label").text.is_empty(), "stale selection shows an error")
	check(ui.game_state.to_json() == unchanged, "stale valid replacement is never adopted")
	menu.cancel()

	# SAVE has the mandated owner-data overwrite confirmation and preserves the default adapter.
	var default_file := FileAccess.open(store.default_path(), FileAccess.WRITE)
	default_file.store_string(Game.new_game(12944, 2).to_json())
	default_file.close()
	var default_bytes := FileAccess.get_file_as_bytes(store.default_path())
	shell.save_requested.emit()
	check(menu.visible and menu.get("picker").get_mode() == "save", "HUD SAVE opens five writable rows")
	check(ui.direct_save_calls == 0, "HUD SAVE does not overwrite default path")
	_press_row(viewport, menu, 1)
	check(menu.get("picker").overwrite_overlay.visible, "occupied save row asks for overwrite")
	menu.get("picker").overwrite_cancel_button.pressed.emit()
	check(menu.visible and store.read(1).snapshot.seed == 12933, "overwrite cancellation preserves destination")
	_press_row(viewport, menu, 1)
	menu.get("picker").overwrite_confirm_button.pressed.emit()
	await settle()
	check(not menu.visible, "successful save returns to board")
	check(store.read(1).snapshot.seed == ui.state.seed, "confirmed slot receives current snapshot")
	var saved_game: Object = Game.from_dict(store.read(1).snapshot)
	check(saved_game != null and saved_game.to_json() == ui.game_state.to_json(), "slot payload is exactly the core snapshot without presentation or controller metadata")
	check(FileAccess.get_file_as_bytes(store.default_path()) == default_bytes, "slot writes leave existing default untouched")
	check(ui.game_state.to_json() == unchanged, "save and confirmations preserve live state and RNG")

	# Supported legacy choice stays explicit and uses the validated candidate.
	shell.show_title()
	shell.title_load_button.pressed.emit()
	_press_row(viewport, menu, 0)
	await settle()
	check(ui._legacy_save_modal_open(), "row0 legacy load presents existing compatibility decision")
	check(ui.game_state.to_json() == unchanged, "legacy candidate is not adopted before consent")
	ui._cancel_legacy_save_load()
	check(menu.visible and not menu.is_busy() and shell.is_title_visible(), "legacy cancellation resumes title chooser")
	_press_row(viewport, menu, 0)
	await settle()
	var original_candidate_seed := 12944
	default_file = FileAccess.open(store.default_path(), FileAccess.WRITE)
	default_file.store_string(Game.new_game(12955, 2).to_json())
	default_file.close()
	ui._confirm_legacy_save_load()
	check(ui.state.seed == original_candidate_seed, "legacy confirmation adopts validated candidate without a second disk read")
	check(not menu.visible and not shell.is_title_visible(), "legacy acceptance returns to board")

	# Existing presentation guard applies at entry and again before deferred I/O.
	ui._presentation_busy = true
	shell.load_requested.emit()
	check(not menu.visible, "movement presentation blocks opening picker")
	ui._presentation_busy = false
	shell.load_requested.emit()
	_press_row(viewport, menu, 1)
	var prior: String = ui.game_state.to_json()
	ui._presentation_busy = true
	await settle()
	check(ui.game_state.to_json() == prior and menu.visible, "presentation activated before read prevents adoption")
	ui._presentation_busy = false
	menu.cancel()
	shell.load_requested.emit()
	_press_row(viewport, menu, 1)
	menu.cancel()
	await settle()
	check(not menu.visible and ui.game_state.to_json() == prior, "cancel invalidates deferred read")
	ui.game_state.set_player_ai(int(ui.state.current_player), true)
	ui._refresh_from_state()
	var ai_before: String = ui.game_state.to_json()
	shell.save_requested.emit()
	check(menu.visible and menu.get("picker").get_mode() == "save", "stable AI turn can be saved without issuing a player action")
	if menu.visible:
		ui._on_ai_timer_timeout(ui._presentation_generation)
		check(ui.game_state.to_json() == ai_before, "queued AI timer cannot advance while the save chooser is open")
		_press_row(viewport, menu, 2)
		var saved_ai: Object = Game.from_dict(store.read(2).snapshot)
		check(saved_ai != null and saved_ai.to_json() == ai_before, "AI save preserves the exact core snapshot")
		check(ui.game_state.to_json() == ai_before, "AI save never advances state or RNG")

	viewport.queue_free()
	await settle()
	finish()

func finish() -> void:
	var slots := temp_root.path_join("slots")
	if DirAccess.dir_exists_absolute(slots):
		for name in DirAccess.get_files_at(slots):
			DirAccess.remove_absolute(slots.path_join(name))
		DirAccess.remove_absolute(slots)
	DirAccess.remove_absolute(temp_root.path_join("default.json"))
	DirAccess.remove_absolute(temp_root)
	print("Source save menu UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _press_row(viewport: SubViewport, menu: Control, slot: int) -> void:
	var picker: Control = menu.get("picker")
	var row: Rect2 = picker.get_row_rect(slot)
	var point: Vector2 = picker.reference_canvas.get_global_transform_with_canvas() * row.get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		viewport.push_input(event, true)


func _secondary_cancel(viewport: SubViewport, menu: Control) -> void:
	var picker: Control = menu.get("picker")
	var point: Vector2 = picker.reference_canvas.get_global_transform_with_canvas() * Vector2(20, 20)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		viewport.push_input(event, true)


func _ctrl_shortcut(viewport: SubViewport, key: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.ctrl_pressed = true
		event.pressed = down
		viewport.push_input(event, true)
