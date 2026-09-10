extends SceneTree

var checks := 0
var failures := 0
var scratch := ""

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: " + message)

func put(path: String, data: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(data)
	file.close()

func run() -> void:
	var implementation := "res://game/platform/system_settings.gd"
	expect(FileAccess.file_exists(implementation), "system settings module is available")
	if not FileAccess.file_exists(implementation):
		finish()
		return
	var Settings = load(implementation)
	var settings = Settings.new()
	var defaults: Dictionary = settings.defaults()
	expect(defaults == {"speed":1,"animation":true,"music_level":4,"sound_level":4,"autosave":true,"view":1}, "defaults match the six source fields")
	var detached: Dictionary = settings.defaults()
	detached.speed = 0
	expect(settings.defaults().speed == 1, "defaults are independently returned")
	scratch = OS.get_environment("RICHMAN4_SETTINGS_TEST_ROOT")
	expect(not scratch.is_empty() and not DirAccess.dir_exists_absolute(scratch), "tests require a new explicit temporary directory")
	if scratch.is_empty() or DirAccess.dir_exists_absolute(scratch):
		finish()
		return
	expect(DirAccess.make_dir_recursive_absolute(scratch) == OK, "temporary settings directory is created")
	var path := scratch.path_join("settings.json")
	var missing: Dictionary = settings.read_settings(path)
	expect(missing.ok and missing.status == "defaults" and missing.settings == defaults, "missing settings use explicit source defaults")
	expect(not FileAccess.file_exists(path), "reading defaults does not write a settings file")
	expect(settings.write_settings(path, defaults).ok, "valid settings persist")
	var result: Dictionary = settings.read_settings(path)
	expect(result.ok and result.status == "loaded" and result.settings == defaults, "persisted settings reload exactly")
	var before := FileAccess.get_file_as_string(path)
	for key in ["speed", "music_level", "sound_level", "view"]:
		for value in [-1, 99, true, "1", 1.5, null]:
			var bad := defaults.duplicate(true)
			bad[key] = value
			expect(not settings.write_settings(path, bad).ok, "invalid %s value is rejected before writing: %s" % [key, str(value)])
			expect(FileAccess.get_file_as_string(path) == before, "invalid settings preserve the existing committed file")
	for key in ["animation", "autosave"]:
		var bad := defaults.duplicate(true)
		bad[key] = 1
		expect(not settings.write_settings(path, bad).ok, "numeric values do not impersonate Boolean %s" % key)
	var missing_key := defaults.duplicate(true)
	missing_key.erase("view")
	expect(not settings.write_settings(path, missing_key).ok, "missing required field is rejected")
	var extra := defaults.duplicate(true)
	extra["audio_source"] = "unexpected"
	expect(not settings.write_settings(path, extra).ok, "the module does not accept unrelated owner audio fields")
	var alternate := {"speed":2,"animation":false,"music_level":0,"sound_level":1,"autosave":false,"view":2}
	expect(settings.write_settings(path, alternate).ok and settings.read_settings(path).settings == alternate, "valid changed fields replace atomically and roundtrip")
	alternate.view = 0
	expect(settings.read_settings(path).settings.view == 2, "mutation of caller data cannot change persisted state")
	for raw in ["{", "[]", '{"schema":"unknown","settings":{}}', JSON.stringify({"schema":"richman4.system-settings/v1","settings":{"speed":0}}), " ".repeat(5000)]:
		put(path, raw)
		result = settings.read_settings(path)
		expect(not result.ok and result.status == "unavailable" and result.settings == defaults, "malformed settings are explicitly unavailable with safe defaults")
		expect(FileAccess.get_file_as_string(path) == raw, "unavailable settings are not silently rewritten")
	expect(not settings.write_settings(scratch.path_join("absent/settings.json"), defaults).ok, "unavailable parent reports a write failure")
	expect(not settings.write_settings(scratch, defaults).ok, "a directory is not replaced with settings")
	expect(settings.write_settings(path, defaults).ok, "a later explicit valid commit recovers invalid settings")
	var listed := DirAccess.open(scratch).get_files()
	expect(listed.size() == 1 and listed[0] == "settings.json", "successful and rejected writes leave no temporary files")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(scratch)
	finish()

func finish() -> void:
	print("System settings checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
