extends SceneTree
const OriginalAudio = preload("res://game/platform/original_audio.gd")
class AudioFixture extends OriginalAudio:
	var selected_path := ""
	func _save_settings() -> void:
		pass
	func next_track() -> void:
		selected_path = tracks[0] if not tracks.is_empty() else ""
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var audio := AudioFixture.new()
	root.add_child(audio)
	audio.enabled = false
	audio.player.stream = AudioStreamGenerator.new()
	var source := "user://audio-library-regression"
	DirAccess.make_dir_recursive_absolute(source.path_join("Media/Music"))
	var track := source.path_join("Media/Music/synthetic.ogg")
	var file := FileAccess.open(track, FileAccess.WRITE)
	file.store_string("Synthetic filename fixture: decoding is replaced in AudioFixture.")
	file.close()
	if not audio.configure(source, false):
		failures += 1
		push_error("New music library should be accepted")
	audio.set_enabled(true)
	if audio.selected_path != track:
		failures += 1
		push_error("Enabling music must select from the newly configured library")
	audio.queue_free()
	DirAccess.remove_absolute(track)
	DirAccess.remove_absolute(source.path_join("Media/Music"))
	DirAccess.remove_absolute(source.path_join("Media"))
	DirAccess.remove_absolute(source)
	await create_timer(0.1).timeout
	print("Audio library regression failures: ", failures)
	quit(1 if failures else 0)
