extends SceneTree

var checks := 0
var failures := 0
var hotkeys: Variant

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	if not ResourceLoader.exists("res://game/platform/system_hotkeys.gd"):
		print("System hotkeys availability RED: module missing; no behavior claim")
		print("System hotkeys checks: 1, failures: 1")
		quit(1)
		return
	hotkeys = load("res://game/platform/system_hotkeys.gd").new()
	var expected := [0x26,0x27,0x28,0x25,0x0d,0x1b,0x09,0x09,0x59,0x4e,0x20,0x44,0x57,0x58,0x43,0x45,0x46,0x4d,0xbc,0xbe,0x41,0x56,0x53,0x4c,0x48,0x21,0x22,0x1151]
	_expect(hotkeys.defaults() == expected, "all28 defaults preserve source slot order and Ctrl-Q")
	var changed: Array = hotkeys.defaults()
	changed[0] = 0
	_expect(hotkeys.defaults() == expected, "defaults are detached")
	_expect(hotkeys.validate_bindings(expected).ok, "duplicate default TAB is valid")
	for invalid in [null, {}, [], expected.slice(0,27), expected + [0]]:
		_expect(not hotkeys.validate_bindings(invalid).ok, "binding array has exact28 shape")
	for invalid in [-1, true, 1.5, 65.0, 0x1251, 0x10000, 0x2e, 0x60, INF, NAN]:
		changed = expected.duplicate()
		changed[8] = invalid
		_expect(not hotkeys.validate_bindings(changed).ok, "public bindings reject unsupported key/modifier/type")
	changed = expected.duplicate()
	changed[8] = 65.0
	var decoded: Dictionary = hotkeys.validate_bindings(changed, true)
	_expect(decoded.ok and typeof(decoded.bindings[8]) == TYPE_INT, "JSON whole numbers normalize only on explicit decode")
	changed[8] = 0
	changed[9] = 0x1100
	_expect(hotkeys.validate_bindings(changed).ok, "source can commit unbound or pending Ctrl-only rows")
	var detached: Dictionary = hotkeys.validate_bindings(changed)
	detached.bindings[8] = 0x42
	_expect(changed[8] == 0, "validated output is detached")
	for pair in [[0,""],[0x1100,""],[0x1151,"CTRL-Q"],[0x26,"↑"],[0x08,"BS"],[0x21,"PG UP"],[0x7b,"F12"],[0xbc,","],[0x41,"A"]]:
		_expect(hotkeys.key_name(pair[0]) == pair[1], "source key captions retain original names")
	for pair in [[KEY_A,0x41],[KEY_8,0x38],[KEY_UP,0x26],[KEY_ENTER,0x0d],[KEY_CTRL,0x11],[KEY_F12,0x7b],[KEY_COMMA,0xbc],[KEY_KP_MULTIPLY,0x6a],[KEY_DELETE,0],[KEY_KP_1,0],[KEY_SHIFT,0],[KEY_META,0]]:
		var event := InputEventKey.new()
		event.keycode = pair[0]
		_expect(hotkeys.event_key(event) == pair[1], "Godot key conversion uses the source whitelist")
	var physical := InputEventKey.new()
	physical.physical_keycode = KEY_Q
	_expect(hotkeys.event_key(physical) == 0x51, "physical key fallback converts without global InputMap changes")

	var root_path := OS.get_environment("RICHMAN4_HOTKEYS_TEST_ROOT")
	if root_path.is_empty() or DirAccess.dir_exists_absolute(root_path) or FileAccess.file_exists(root_path):
		_expect(false, "test requires explicit new isolated root")
	else:
		_expect(DirAccess.make_dir_recursive_absolute(root_path) == OK, "isolated root created")
		var path := root_path.path_join("keys.json")
		_expect(hotkeys.read_bindings(path).status == "defaults", "missing config reports defaults")
		var saved: Dictionary = hotkeys.write_bindings(path, changed)
		_expect(saved.ok and saved.status == "saved", "valid bindings saved")
		var readback: Dictionary = hotkeys.read_bindings(path)
		_expect(readback.ok and readback.bindings == changed, "unbound/Ctrl-only settings roundtrip")
		var old_bytes := FileAccess.get_file_as_bytes(path)
		_expect(not hotkeys.write_bindings(path, [1]).ok, "invalid write rejected")
		_expect(FileAccess.get_file_as_bytes(path) == old_bytes, "rejected write preserves file bytes")
		_expect(not hotkeys.write_bindings(root_path, expected).ok, "directory rejected as file")
		_expect(not hotkeys.write_bindings(root_path.path_join("missing/keys.json"), expected).ok, "absent destination parent not created implicitly")
		_expect(not hotkeys.read_bindings("").ok and not hotkeys.read_bindings(root_path).ok, "invalid read paths unavailable")
		var bad_documents := [
			{"schema":"wrong","bindings":expected},
			{"schema":"richman4.system-hotkeys/v1","bindings":expected,"extra":true},
			{"schema":"richman4.system-hotkeys/v1","bindings":[]},
		]
		for document in bad_documents:
			_write(path, JSON.stringify(document))
			var unavailable: Dictionary = hotkeys.read_bindings(path)
			_expect(not unavailable.ok and unavailable.status == "unavailable", "malformed stored document never reports loaded")
		_write(path, "{")
		_expect(not hotkeys.read_bindings(path).ok, "malformed JSON rejected")
		_write(path, " ".repeat(4097))
		_expect(not hotkeys.read_bindings(path).ok, "oversized file rejected")
		_expect(hotkeys.write_bindings(path, expected).ok, "explicit valid write can repair invalid config")
		var directory := DirAccess.open(root_path)
		_expect(directory.get_files() == PackedStringArray(["keys.json"]), "temporary files cleaned after writes")
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(root_path)
	print("System hotkeys checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func _write(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()
