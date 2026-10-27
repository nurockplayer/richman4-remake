class_name OriginalAudio
extends Node
## Optional owner-provided music. Files are loaded from disk, never from res://.

const UserPaths = preload("res://game/platform/user_paths.gd")

signal library_changed(track_count: int)
signal playback_changed(track_name: String)

var source_path := ""
var tracks: PackedStringArray = []
var current_track := -1
var enabled := true
var volume := 0.35
var player := AudioStreamPlayer.new()
var _preferred_source_path := ""
## Board track resumed after a scene cue, or -1 when no cue is playing.
var _resume_track := -1

## Source music table (rich4.exe 47e773): eight board tracks (RICH08,
## RICH16..22; CD tracks 02-09) cycled in order by 454d91, then seventeen scene
## cues (MIDI01..16 with 14-1/14-2; CD tracks 10-26) played once by 4549cf,
## which then resumes the board track from its start (454bcc).
const BOARD_TRACKS := 8
const SOURCE_TRACK_COUNT := 25


func _ready() -> void:
	add_child(player)
	player.finished.connect(_on_finished)
	var settings := ConfigFile.new()
	if settings.load(_settings_path()) == OK:
		volume = clampf(float(settings.get_value("audio", "volume", 0.35)), 0.0, 1.0)
		enabled = bool(settings.get_value("audio", "enabled", true))
		_preferred_source_path = str(settings.get_value("audio", "source", ""))
	player.volume_linear = volume
	configure_default()


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
	return UserPaths.path("audio.cfg")


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
	_resume_track = -1
	if persist:
		_preferred_source_path = path
		_save_settings()
	library_changed.emit(tracks.size())
	if enabled:
		next_track()
	return true


## Load and preview exactly one selected track without changing preferences.
## Invalid or unavailable tracks leave the current playback untouched.
func play_track(index: int) -> bool:
	if not enabled or index < 0 or index >= tracks.size():
		return false
	var stream := _load_track(tracks[index])
	if stream == null:
		return false
	current_track = index
	_resume_track = -1
	player.stream = stream
	_play_current()
	playback_changed.emit(tracks[index].get_file())
	return true


## Board tracks in a source-layout library; any other library cycles all.
func _board_count() -> int:
	return BOARD_TRACKS if tracks.size() == SOURCE_TRACK_COUNT else tracks.size()


## Play source scene cue `cue` (0 = MIDI01) once, then resume the board track.
## Libraries without the source layout have no cues and keep playing.
func play_cue(cue: int) -> bool:
	if not enabled or tracks.size() != SOURCE_TRACK_COUNT or cue < 0 or BOARD_TRACKS + cue >= tracks.size():
		return false
	var stream := _load_track(tracks[BOARD_TRACKS + cue])
	if stream == null:
		return false
	if _resume_track < 0:
		_resume_track = current_track
	player.stream = stream
	_play_current()
	return true


func _on_finished() -> void:
	if _resume_track < 0:
		next_track()
		return
	var board := _resume_track
	_resume_track = -1
	if not play_track(board):
		next_track()


## Narrow loading seam for isolated fixtures; production uses the original Ogg
## decoder and still skips unreadable tracks in next_track().
func _load_track(path: String) -> AudioStream:
	return AudioStreamOggVorbis.load_from_file(path)


func _play_current() -> void:
	player.play()


func next_track() -> void:
	if tracks.is_empty() or not enabled:
		return
	_resume_track = -1
	var count := _board_count()
	for offset in range(1, count + 1):
		var index := (current_track + offset) % count
		var stream := _load_track(tracks[index])
		if stream != null:
			current_track = index
			player.stream = stream
			_play_current()
			playback_changed.emit(tracks[index].get_file())
			return
	stop()


func set_enabled(value: bool, persist := true) -> void:
	enabled = value
	if enabled:
		if player.stream != null:
			player.play()
		else:
			next_track()
	else:
		stop()
	if persist:
		_save_settings()


func set_volume(value: float, persist := true) -> void:
	volume = clampf(value, 0.0, 1.0)
	player.volume_linear = volume
	if persist:
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
	_resume_track = -1
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
