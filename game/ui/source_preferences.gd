extends RefCounted
class_name RichmanSourcePreferences

## Small host adapter for the source options values.  It translates the
## source's discrete controls into runtime audio and presentation behaviour;
## it does not own settings persistence or mutate InputMap.

const SETTINGS_SCRIPT := preload("res://game/platform/system_settings.gd")
const HOTKEYS_SCRIPT := preload("res://game/platform/system_hotkeys.gd")
const MUSIC_GAINS := [0.0, 0.6, 0.8, 0.9, 1.0]
const MOVEMENT_SECONDS := [0.24, 0.16, 0.08]
const SOURCE_TICKS := [6, 4, 2]
const COMMAND_SLOTS := {
	10: "roll",
	12: "stocks",
	14: "cards",
	15: "tools",
	16: "inspect",
	17: "map",
	21: "options",
	22: "save",
	23: "load",
	24: "help",
}

var _startup_volumes: Dictionary = {}


## Capture startup volume once for each audio object.  Reapplying settings
## never treats a previously adjusted runtime volume as the new baseline.
func capture_audio_baseline(audio: Object) -> void:
	if audio == null:
		return
	var audio_id := audio.get_instance_id()
	if _startup_volumes.has(audio_id):
		return
	var startup_volume := 0.35
	var volume: Variant = audio.get("volume")
	if typeof(volume) == TYPE_FLOAT or typeof(volume) == TYPE_INT:
		startup_volume = clampf(float(volume), 0.0, 1.0)
	else:
		var player: Variant = audio.get("player")
		if player is Object:
			var linear: Variant = player.get("volume_linear")
			if typeof(linear) == TYPE_FLOAT or typeof(linear) == TYPE_INT:
				startup_volume = clampf(float(linear), 0.0, 1.0)
	_startup_volumes[audio_id] = startup_volume


func apply(settings: Dictionary, audio: Object) -> bool:
	var checked := SETTINGS_SCRIPT.new().validate_settings(settings)
	if not bool(checked.get("ok", false)) or audio == null:
		return false
	capture_audio_baseline(audio)
	var normalized: Dictionary = checked.get("settings", {})
	var level := clampi(int(normalized.get("music_level", 0)), 0, MUSIC_GAINS.size() - 1)
	var enabled := level > 0
	var startup_volume := float(_startup_volumes.get(audio.get_instance_id(), 0.35))
	var currently_enabled := bool(audio.get("enabled"))
	# set_enabled can restart the current track when enabling. Avoid calling it
	# when the enabled state is unchanged; volume changes are independent.
	if currently_enabled != enabled and audio.has_method("set_enabled"):
		audio.call("set_enabled", enabled, false)
	if audio.has_method("set_volume"):
		audio.call("set_volume", MUSIC_GAINS[level] * startup_volume, false)
	return audio.has_method("set_enabled") and audio.has_method("set_volume")


## Source movement pacing inferred from its 6/4/2 tick controls. This is a
## presentation adapter only; it does not alter simulation timing.
func movement_seconds(settings: Dictionary) -> float:
	var checked := SETTINGS_SCRIPT.new().validate_settings(settings)
	if not bool(checked.get("ok", false)):
		return MOVEMENT_SECONDS[1]
	var speed := clampi(int(checked.settings.get("speed", 1)), 0, MOVEMENT_SECONDS.size() - 1)
	return MOVEMENT_SECONDS[speed]


func hotkey_command(event: InputEvent, bindings: Array) -> String:
	if not event is InputEventKey:
		return ""
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.alt_pressed or key_event.meta_pressed or key_event.shift_pressed:
		return ""
	var checked := HOTKEYS_SCRIPT.new().validate_bindings(bindings)
	if not bool(checked.get("ok", false)):
		return ""
	var source_key := HOTKEYS_SCRIPT.new().event_key(key_event)
	if source_key == 0:
		return ""
	for raw_slot in COMMAND_SLOTS:
		var slot := int(raw_slot)
		var word := int(checked.bindings[slot])
		if word == 0:
			continue
		var ctrl_binding := (word >> 8) == 0x11
		if ctrl_binding != key_event.ctrl_pressed:
			continue
		if (word & 0xff) == source_key:
			return str(COMMAND_SLOTS[raw_slot])
	return ""
