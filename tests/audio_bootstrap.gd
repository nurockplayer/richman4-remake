extends SceneTree

const OriginalAudio = preload("res://game/platform/original_audio.gd")

class AudioFixture extends OriginalAudio:
	var settings_path_override := ""
	var default_paths_override: Array[String] = []
	var selected_path := ""
	var observed_startup_volume := -1.0

	func _settings_path() -> String:
		return settings_path_override

	func _default_source_paths() -> Array[String]:
		return default_paths_override

	func _save_settings() -> void:
		pass

	func next_track() -> void:
		selected_path = tracks[0] if not tracks.is_empty() else ""
		observed_startup_volume = player.volume_linear


var failures := 0
var temporary_root := "user://audio-bootstrap-regression"


func _initialize() -> void:
	call_deferred("run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _write_track(source: String, name: String, payload: String = "synthetic ogg fixture") -> String:
	var music := source.path_join("Media/Music")
	DirAccess.make_dir_recursive_absolute(music)
	var path := music.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(payload)
	file.close()
	return path


func _write_settings(path: String, source: String, enabled: bool, volume: float) -> void:
	var settings := ConfigFile.new()
	settings.set_value("audio", "source", source)
	settings.set_value("audio", "enabled", enabled)
	settings.set_value("audio", "volume", volume)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_expect(settings.save(path) == OK, "isolated audio settings should save")


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory != null:
		for file in directory.get_files():
			DirAccess.remove_absolute(path.path_join(file))
		for child in directory.get_directories():
			_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func _new_fixture(settings_path: String, defaults: Array[String]) -> AudioFixture:
	var audio := AudioFixture.new()
	audio.settings_path_override = settings_path
	audio.default_paths_override = defaults
	return audio


func run() -> void:
	# Keep the RED seed from invoking the legacy _ready path, which reads the
	# owner's user://audio.cfg before the injectable test seams exist.
	var api_probe := OriginalAudio.new()
	if not api_probe.has_method("configure_default"):
		push_error("RED seed: OriginalAudio.configure_default() is not implemented")
		api_probe.add_child(api_probe.player)
		api_probe.free()
		print("Audio bootstrap failures: 1")
		quit(1)
		return
	api_probe.add_child(api_probe.player)
	api_probe.free()

	var custom := temporary_root.path_join("custom")
	var bundled := temporary_root.path_join("bundled")
	var developer := temporary_root.path_join("developer")
	var isolated_settings := temporary_root.path_join("custom.cfg")
	var custom_track := _write_track(custom, "custom.ogg")
	_write_track(bundled, "bundled.ogg")
	_write_track(developer, "developer.ogg")
	_write_settings(isolated_settings, custom, false, 0.62)

	var root_node := Node.new()
	root.add_child(root_node)
	var custom_audio := _new_fixture(isolated_settings, [bundled, developer])
	root_node.add_child(custom_audio)
	_expect(custom_audio.source_path == custom, "valid custom library must have priority over bundled defaults")
	_expect(custom_audio.tracks.size() == 1 and custom_audio.tracks[0] == custom_track, "custom library track should be selected")
	_expect(is_equal_approx(custom_audio.volume, 0.62), "saved volume must be preserved")
	_expect(not custom_audio.enabled, "saved enabled state must be preserved")
	custom_audio.set_enabled(true)
	_expect(custom_audio.selected_path == custom_track, "enabling custom library must select its track")
	custom_audio.queue_free()

	var autoplay_settings := temporary_root.path_join("autoplay.cfg")
	_write_settings(autoplay_settings, custom, true, 0.17)
	var autoplay_audio := _new_fixture(autoplay_settings, [bundled, developer])
	root_node.add_child(autoplay_audio)
	_expect(is_equal_approx(autoplay_audio.observed_startup_volume, 0.17), "automatic startup playback must use the saved volume")
	autoplay_audio.queue_free()

	var invalid_settings := temporary_root.path_join("invalid.cfg")
	_write_settings(invalid_settings, temporary_root.path_join("missing-custom"), false, 0.4)
	var bundled_audio := _new_fixture(invalid_settings, [bundled, developer])
	root_node.add_child(bundled_audio)
	_expect(bundled_audio.source_path == bundled, "bundled library must win when custom source is invalid")
	_expect(bundled_audio.tracks.size() == 1, "bundled library should expose its Ogg track")
	bundled_audio.queue_free()

	var developer_settings := temporary_root.path_join("developer.cfg")
	_write_settings(developer_settings, temporary_root.path_join("missing-custom"), false, 0.4)
	var developer_audio := _new_fixture(developer_settings, [temporary_root.path_join("missing-bundle"), developer])
	root_node.add_child(developer_audio)
	_expect(developer_audio.source_path == developer, "developer bootstrap source must be the final fallback")
	developer_audio.queue_free()

	var empty_settings := temporary_root.path_join("empty.cfg")
	_write_settings(empty_settings, temporary_root.path_join("missing-custom"), false, 0.4)
	var empty_audio := _new_fixture(empty_settings, [temporary_root.path_join("missing-bundle"), temporary_root.path_join("missing-developer")])
	root_node.add_child(empty_audio)
	_expect(empty_audio.source_path.is_empty() and empty_audio.tracks.is_empty(), "missing music must leave a usable silent fallback")
	empty_audio.queue_free()

	root_node.queue_free()
	await create_timer(0.1).timeout
	_remove_tree(temporary_root)
	print("Audio bootstrap failures: ", failures)
	quit(1 if failures else 0)
