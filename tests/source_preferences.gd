extends SceneTree

## Hermetic checks for source preference adaptation. Audio is a RefCounted fake;
## no owner ConfigFile, filesystem, InputMap, or scene-tree audio is involved.

const PREFS_PATH := "res://game/ui/source_preferences.gd"
const HOTKEYS := preload("res://game/platform/system_hotkeys.gd")
var checks := 0
var failures := 0


class FakeAudio extends RefCounted:
	var enabled := true
	var volume := 0.5
	var enable_calls: Array = []
	var volume_calls: Array = []

	func set_enabled(value: bool, persist := true) -> void:
		enable_calls.append([value, persist])
		enabled = value

	func set_volume(value: float, persist := true) -> void:
		volume_calls.append([value, persist])
		volume = value


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _settings(level := 4, speed := 1) -> Dictionary:
	return {"speed": speed, "animation": true, "music_level": level, "sound_level": 4, "autosave": true, "view": 1}


func _key(code: Key, ctrl := false, alt := false, meta := false, shift := false, echo := false, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.meta_pressed = meta
	event.shift_pressed = shift
	event.echo = echo
	event.pressed = pressed
	return event


func _run() -> void:
	if not FileAccess.file_exists(PREFS_PATH):
		push_error("FAIL: source preferences presenter is absent")
		quit(1)
		return
	var script: Script = load(PREFS_PATH)
	var prefs: RefCounted = script.new()
	_test_audio(prefs)
	_test_movement(prefs)
	_test_hotkeys(prefs)
	print("Source preferences checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _test_audio(prefs: RefCounted) -> void:
	var audio := FakeAudio.new()
	prefs.capture_audio_baseline(audio)
	audio.volume = 0.9
	_expect(prefs.apply(_settings(2), audio), "valid preferences apply to audio")
	_expect_equal(audio.volume_calls, [[0.4, false]], "music gain multiplies captured startup volume")
	_expect_equal(audio.enable_calls, [], "unchanged enabled state does not restart audio")
	_expect(prefs.apply(_settings(0), audio), "music disable applies")
	_expect_equal(audio.enable_calls, [[false, false]], "music level zero disables at runtime without persistence")
	_expect_equal(audio.volume_calls[1], [0.0, false], "disabled music still applies zero runtime gain")
	prefs.apply(_settings(0), audio)
	_expect_equal(audio.enable_calls.size(), 1, "repeated disabled apply does not restart or toggle audio")
	var second := FakeAudio.new()
	second.volume = 0.25
	prefs.capture_audio_baseline(second)
	prefs.apply(_settings(4), second)
	_expect_equal(second.volume_calls[0], [0.25, false], "baseline is captured independently per audio object")
	audio.enabled = true
	prefs.apply(_settings(4), audio)
	_expect_equal(audio.volume_calls[3], [0.5, false], "switching back retains the first object's startup baseline")
	var before := audio.volume_calls.size()
	var invalid := _settings()
	invalid.erase("view")
	_expect(not prefs.apply(invalid, audio) and audio.volume_calls.size() == before, "invalid settings are rejected without audio mutation")


func _test_movement(prefs: RefCounted) -> void:
	_expect_equal(prefs.movement_seconds(_settings(4, 0)), 0.24, "source speed 0 uses six-tick presentation duration")
	_expect_equal(prefs.movement_seconds(_settings(4, 1)), 0.16, "source speed 1 uses four-tick baseline duration")
	_expect_equal(prefs.movement_seconds(_settings(4, 2)), 0.08, "source speed 2 uses two-tick presentation duration")
	_expect_equal(prefs.movement_seconds({}), 0.16, "invalid speed falls back to inferred baseline duration")


func _test_hotkeys(prefs: RefCounted) -> void:
	var bindings: Array = []
	bindings.resize(28)
	bindings.fill(0)
	bindings[10] = 0x52
	bindings[12] = 0x1157
	bindings[24] = 0x48
	_expect_equal(prefs.hotkey_command(_key(KEY_R), bindings), "roll", "regular remap reaches roll command")
	_expect_equal(prefs.hotkey_command(_key(KEY_W, true), bindings), "stocks", "exact Ctrl remap reaches stocks command")
	_expect_equal(prefs.hotkey_command(_key(KEY_W), bindings), "", "Ctrl binding does not match unmodified event")
	_expect_equal(prefs.hotkey_command(_key(KEY_H), bindings), "help", "help command maps from configured slot")
	_expect_equal(prefs.hotkey_command(_key(KEY_R, false, true), bindings), "", "alt modified event is rejected")
	_expect_equal(prefs.hotkey_command(_key(KEY_R, false, false, true), bindings), "", "meta modified event is rejected")
	_expect_equal(prefs.hotkey_command(_key(KEY_R, false, false, false, true), bindings), "", "shift modified event is rejected")
	_expect_equal(prefs.hotkey_command(_key(KEY_R, false, false, false, false, true), bindings), "", "echo event is rejected")
	_expect_equal(prefs.hotkey_command(_key(KEY_R, false, false, false, false, false, false), bindings), "", "released event is rejected")
	_expect_equal(prefs.hotkey_command(_key(KEY_R), bindings.slice(0, 27)), "", "incomplete bindings disable all commands")
	bindings[10] = 0
	_expect_equal(prefs.hotkey_command(_key(KEY_R), bindings), "", "zero binding disables its command slot")
	var defaults := HOTKEYS.new().defaults()
	_expect_equal(prefs.hotkey_command(_key(KEY_SPACE), defaults), "roll", "source default slot maps roll")
	_expect_equal(prefs.hotkey_command(_key(KEY_TAB), defaults), "view", "slot7 independently cycles view")
	defaults[7] = 0x56
	_expect_equal(prefs.hotkey_command(_key(KEY_TAB), defaults), "", "unknown slot6 TAB is not borrowed")
	_expect_equal(prefs.hotkey_command(_key(KEY_V), defaults), "view", "slot7 remap reaches view")
	_expect_equal(prefs.hotkey_command(_key(KEY_M), defaults), "map", "slot17 fullmap remains separate")
