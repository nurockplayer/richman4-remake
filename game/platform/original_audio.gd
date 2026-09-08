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


func _ready() -> void:
	add_child(player)
	player.finished.connect(next_track)
	var settings := ConfigFile.new()
	if settings.load("user://audio.cfg") == OK:
		volume = clampf(float(settings.get_value("audio", "volume", 0.35)), 0.0, 1.0)
		enabled = bool(settings.get_value("audio", "enabled", true))
		configure(str(settings.get_value("audio", "source", "")), false)
	player.volume_linear = volume


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
	source_path = path
	tracks = found
	current_track = -1
	if persist:
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


func _exit_tree() -> void:
	player.stop()
	player.stream = null


func _save_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("audio", "source", source_path)
	settings.set_value("audio", "volume", volume)
	settings.set_value("audio", "enabled", enabled)
	settings.save("user://audio.cfg")
