extends SceneTree

## Guard: a headless MainUI run with RICHMAN4_USER_ROOT set keeps every
## default write root (save slots, autosave, legacy save, settings, hotkeys,
## audio) inside that root and never creates or modifies anything under the
## owner's real OS.get_user_data_dir().
##
## Godot itself writes its own files under the user data directory on every
## desktop run (file logs, shader cache, temporary files), so those
## engine-owned top-level entries are not part of the compared snapshot.

const MainScene = preload("res://game/main.tscn")
const Core = preload("res://game/core/game_state.gd")
const CompanyFixture = preload("res://tests/fixtures/company_fixture.gd")
const UserPaths = preload("res://game/platform/user_paths.gd")

const ENGINE_OWNED := ["logs", "shader_cache", "temporary"]

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)


func _settle() -> void:
	await process_frame
	await process_frame


## Same validated day-14 fixture the autosave UI checks use to reach a real
## day wrap without touching any persistent state.
func _monthly_game(day: int) -> Object:
	var flags := [true, true, true, true]
	var game: Object = Core.new_game_on_board(42, 4, CompanyFixture.definition(), {
		"original_facilities": true, "original_gods": true, "original_companies": true,
		"start_date": {"year": 1998, "month": 1, "day": 1}, "human_flags": flags})
	game.state.god_objects = []
	game.state.day = day
	game.state.current_player = 3
	game.state.phase = "await_action"
	game._sync_state()
	game._set_action_options(3)
	return game


func _run() -> void:
	var real_root := OS.get_user_data_dir()
	var before := _snapshot(real_root)

	var scratch := ProjectSettings.globalize_path("res://.local/userdata-isolation-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	_check(DirAccess.make_dir_recursive_absolute(scratch) == OK, "isolation fixture directory is created")
	OS.set_environment(UserPaths.ENV_ROOT, scratch)
	_check(OS.get_environment(UserPaths.ENV_ROOT) == scratch, "RICHMAN4_USER_ROOT points at the fixture root")
	_check(OS.get_user_data_dir() == real_root, "the engine user data directory is unchanged by the override")

	# Defaults are resolved when MainUI is constructed, so the override must be
	# in place before instantiate(); nothing below injects storage.
	var ui: Control = MainScene.instantiate()
	root.add_child(ui)
	await _settle()
	ui.set_process(false)

	_check(ui.settings_path.begins_with(scratch), "default settings path resolves under the override root")
	_check(ui.hotkeys_path.begins_with(scratch), "default hotkey path resolves under the override root")
	_check(ui.source_save_directory.begins_with(scratch), "default save-slot directory resolves under the override root")
	_check(ui.source_legacy_save_path.begins_with(scratch), "default legacy save path resolves under the override root")
	_check(ui.game_state != null, "ordinary MainUI starts a game")
	_check(not UserPaths.path("probe.json").begins_with("user://"), "relative runtime paths follow the override root")
	_check(UserPaths.resolve("user://probe.json").begins_with(scratch), "explicit user:// paths follow the override root")

	# Force one real day wrap through the ordinary end-turn handler; the daily
	# checkpoint is written only after the monthly statement is acknowledged.
	var game := _monthly_game(14)
	ui._cancel_presentation()
	ui.game_state = game
	ui._refresh_from_state()
	ui._on_end_turn_pressed()
	await _settle()
	if ui.source_monthly_controller != null and ui.source_monthly_controller.is_open():
		ui.source_monthly_controller.report_panel.continued.emit()
		await _settle()
	var automatic := scratch.path_join("richman4-save-slots").path_join("auto.json")
	_check(int(game.state.day) == 15, "end turn settles a full day")
	_check(FileAccess.file_exists(automatic), "daily autosave lands under the override root")

	# A real settings write through the ordinary options handler.
	ui._on_source_options_accepted(ui.system_settings.defaults())
	_check(FileAccess.file_exists(scratch.path_join("system-options.json")), "settings write lands under the override root")

	var after := _snapshot(real_root)
	_report_diff(before, after)
	_check(_same_snapshot(before, after), "no file under the owner's real user data directory was created or modified")

	ui.queue_free()
	await _settle()
	_remove_tree(scratch)
	_check(not DirAccess.dir_exists_absolute(scratch), "isolation fixture directory is removed")
	print("Userdata isolation checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


## Absolute listing with type, size and mtime for every entry below [root],
## skipping the engine-owned top-level directories.
func _snapshot(root_path: String) -> Dictionary:
	var result := {}
	if not DirAccess.dir_exists_absolute(root_path):
		return result
	_walk(root_path, "", ENGINE_OWNED, result)
	return result


func _walk(base: String, relative: String, skip_top: Array, out: Dictionary) -> void:
	var folder := base if relative.is_empty() else base.path_join(relative)
	var directory := DirAccess.open(folder)
	if directory == null:
		out[relative] = ["unreadable"]
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if relative.is_empty() and name in skip_top:
			name = directory.get_next()
			continue
		var child := name if relative.is_empty() else relative.path_join(name)
		var absolute := folder.path_join(name)
		if directory.current_is_dir():
			out[child] = ["dir"]
			_walk(base, child, [], out)
		else:
			out[child] = ["file", FileAccess.get_modified_time(absolute), _file_size(absolute)]
		name = directory.get_next()
	directory.list_dir_end()


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var length := file.get_length()
	file.close()
	return length


func _same_snapshot(before: Dictionary, after: Dictionary) -> bool:
	if before.size() != after.size():
		return false
	for key in before:
		if not after.has(key) or not _same_entry(before[key], after[key]):
			return false
	return true


func _same_entry(left: Variant, right: Variant) -> bool:
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not _same_entry(left[index], right[index]):
				return false
		return true
	return left == right


func _report_diff(before: Dictionary, after: Dictionary) -> void:
	for key in before:
		if not after.has(key):
			push_error("REMOVED from real user data dir: " + key)
		elif not _same_entry(before[key], after[key]):
			push_error("CHANGED in real user data dir: %s %s -> %s" % [key, str(before[key]), str(after[key])])
	for key in after:
		if not before.has(key):
			push_error("CREATED in real user data dir: " + key)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if directory.current_is_dir() and not directory.is_link(name):
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
