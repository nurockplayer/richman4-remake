class_name OriginalAudio
extends Node
## Optional owner-provided music. Files are loaded from disk, never from res://.

signal library_changed(track_count: int)
signal playback_changed(track_name: String)

var source_path := ""
var tracks: PackedStringArray = []
var current_track := -1
var enabled := true
var volume := 0.35
var player := AudioStreamPlayer.new()
var _preferred_source_path := ""


func _ready() -> void:
	add_child(player)
	player.finished.connect(next_track)
	var settings := ConfigFile.new()
	if settings.load(_settings_path()) == OK:
		volume = clampf(float(settings.get_value("audio", "volume", 0.35)), 0.0, 1.0)
		enabled = bool(settings.get_value("audio", "enabled", true))
		_preferred_source_path = str(settings.get_value("audio", "source", ""))
	configure_default()
	player.volume_linear = volume


## Load the user's preferred library, then the bundled and developer defaults.
## A missing or invalid library is a normal silent-fallback state.
func configure_default() -> bool:
	var preferred := _preferred_source_path
	if preferred.is_empty():
		var settings := ConfigFile.new()
		if settings.load(_settings_path()) == OK:
			preferred = str(settings.get_value("audio", "source", ""))
			_preferred_source_path = preferred
	if not preferred.is_empty() and configure(preferred, false):
		return true
	for candidate in _default_source_paths():
		var path := str(candidate)
		if path.is_empty() or path == preferred:
			continue
		if configure(path, false):
			return true
	_clear_library()
	return false


## Overridable source roots for isolated tests and platform-specific runners.
## Each root contains the existing Media/Music subtree.
func _default_source_paths() -> Array[String]:
	var paths: Array[String] = []
	var executable_dir := OS.get_executable_path().get_base_dir()
	if not executable_dir.is_empty():
		paths.append(executable_dir.path_join("../Resources/Original/audio").simplify_path())
	var project_root := ProjectSettings.globalize_path("res://")
	paths.append(project_root.path_join(".local/private-assets/source/dfw4cskzl_136622"))
	return paths


## Overridable so tests never read the owner's user://audio.cfg.
func _settings_path() -> String:
	return "user://audio.cfg"


func configure(path: String, persist := true) -> bool:
	var folder := path.path_join("Media/Music")
	var directory := DirAccess.open(folder)
	if directory == null:
		return false
	var found: PackedStringArray = []
	for file in directory.get_files():
		if file.get_extension().to_lower() == "ogg" and not directory.is_link(file):
			found.append(folder.path_join(file))
	found.sort()
	if found.is_empty():
		return false
	stop()
	player.stream = null
	source_path = path
	tracks = found
	current_track = -1
	if persist:
		_preferred_source_path = path
		_save_settings()
	library_changed.emit(tracks.size())
	if enabled:
		next_track()
	return true


func next_track() -> void:
	if tracks.is_empty() or not enabled:
		return
	for offset in range(1, tracks.size() + 1):
		var index := (current_track + offset) % tracks.size()
		var stream := AudioStreamOggVorbis.load_from_file(tracks[index])
		if stream != null:
			current_track = index
			player.stream = stream
			player.play()
			playback_changed.emit(tracks[index].get_file())
			return
	stop()


func set_enabled(value: bool) -> void:
	enabled = value
	if enabled:
		if player.stream != null:
			player.play()
		else:
			next_track()
	else:
		stop()
	_save_settings()


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	player.volume_linear = volume
	_save_settings()


func stop() -> void:
	player.stop()


func _clear_library() -> void:
	var changed := not source_path.is_empty() or not tracks.is_empty()
	stop()
	player.stream = null
	source_path = ""
	tracks = []
	current_track = -1
	if changed:
		library_changed.emit(0)


func _exit_tree() -> void:
	player.stop()
	player.stream = null


func _save_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("audio", "source", _preferred_source_path)
	settings.set_value("audio", "volume", volume)
	settings.set_value("audio", "enabled", enabled)
	settings.save(_settings_path())
