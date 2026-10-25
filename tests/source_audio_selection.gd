extends SceneTree

## Focused, hermetic checks for the source-options music preview adapter.
##
## The fixture keeps the audio object out of the scene tree so its production
## _ready path cannot read the owner's settings or default source folders.  A
## synthetic loader supplies in-memory AudioStream resources; no
## source or owner audio files are needed.

const OriginalAudio = preload("res://game/platform/original_audio.gd")


class AudioFixture extends OriginalAudio:
	var load_calls: Array[String] = []
	var save_calls := 0
	var play_calls := 0
	var stop_calls := 0
	var streams: Dictionary = {}

	func _settings_path() -> String:
		return ""

	func _default_source_paths() -> Array[String]:
		return []

	func _save_settings() -> void:
		save_calls += 1

	func _load_track(path: String) -> AudioStream:
		load_calls.append(path)
		var candidate: Variant = streams.get(path, null)
		if candidate is AudioStream:
			return candidate
		return null

	func _play_current() -> void:
		play_calls += 1

	func stop() -> void:
		stop_calls += 1


var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _stream() -> AudioStream:
	return AudioStream.new()


func _new_fixture() -> AudioFixture:
	# Keep the fixture and player outside the tree so its production _ready path
	# cannot read owner settings or open an audible backend.
	return AudioFixture.new()


func _track_names(audio: AudioFixture, names: Array[String]) -> void:
	audio.tracks = PackedStringArray(names)
	for name in names:
		audio.streams[name] = _stream()


func _remove_fixture(audio: AudioFixture) -> void:
	if is_instance_valid(audio.player):
		audio.player.stop()
		audio.player.stream = null
		audio.player.free()
	audio.streams.clear()
	audio.free()


func _run() -> void:
	var api_probe := OriginalAudio.new()
	var has_selection_api := api_probe.has_method("play_track")
	api_probe.player.free()
	api_probe.free()
	if not has_selection_api:
		checks += 1
		failures += 1
		print("Source audio selection RED: play_track unavailable (availability RED, not a behaviour failure)")
		print("Source audio selection checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return

	_test_direct_selection_and_signal()
	_test_rejections_preserve_playback()
	_test_runtime_persistence_flags()
	_test_next_track_compatibility()
	await process_frame
	await process_frame
	await process_frame
	print("Source audio selection checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _test_direct_selection_and_signal() -> void:
	var audio := _new_fixture()
	var names: Array[String] = ["synthetic://track-0.ogg", "synthetic://track-1.ogg", "synthetic://track-2.ogg"]
	_track_names(audio, names)
	audio.source_path = "synthetic-source"
	audio.set("_preferred_source_path", "preferred-source")
	audio.enabled = true
	audio.volume = 0.62
	audio.player.volume_linear = audio.volume
	var previews: Array[String] = []
	audio.playback_changed.connect(func(track_name: String) -> void: previews.append(track_name))
	var result: bool = audio.play_track(2)
	_expect(result, "valid selected track returns success")
	_expect_equal(audio.current_track, 2, "valid selected track updates current index")
	_expect(audio.player.stream == audio.streams[names[2]], "valid selected track installs only its stream")
	_expect_equal(audio.play_calls, 1, "valid selected track starts playback")
	_expect_equal(audio.load_calls, [names[2]], "selected track loads exactly one requested path")
	_expect_equal(previews, ["track-2.ogg"], "successful selection emits playback_changed exactly once")
	_expect_equal(audio.save_calls, 0, "preview selection never writes settings")
	_expect_equal(audio.enabled, true, "preview selection preserves enabled state")
	_expect(is_equal_approx(audio.volume, 0.62), "preview selection preserves volume")
	_expect_equal(audio.source_path, "synthetic-source", "preview selection preserves source path")
	_expect_equal(str(audio.get("_preferred_source_path")), "preferred-source", "preview selection preserves source preference")
	_remove_fixture(audio)


func _test_rejections_preserve_playback() -> void:
	var audio := _new_fixture()
	var names: Array[String] = ["synthetic://good.ogg", "synthetic://unreadable.ogg"]
	_track_names(audio, names)
	audio.streams[names[1]] = null
	audio.enabled = true
	var previews: Array[String] = []
	audio.playback_changed.connect(func(track_name: String) -> void: previews.append(track_name))
	_expect(audio.play_track(0), "baseline valid selection starts before rejection checks")
	previews.clear()
	var previous_stream: AudioStream = audio.player.stream
	var previous_index := audio.current_track
	var previous_play_calls := audio.play_calls
	var previous_load_count := audio.load_calls.size()
	var previous_save_count := audio.save_calls
	_expect(not audio.play_track(-1), "negative index is rejected")
	_expect(not audio.play_track(audio.tracks.size()), "out-of-range index is rejected")
	_expect_equal(audio.load_calls.size(), previous_load_count, "range rejection does not load a fallback track")
	_expect_equal(previews, [], "range rejection emits no playback signal")
	_expect(audio.player.stream == previous_stream and audio.current_track == previous_index and audio.play_calls == previous_play_calls, "range rejection preserves prior playback")
	_expect(not audio.play_track(1), "unreadable requested stream is rejected")
	_expect_equal(audio.load_calls[-1], names[1], "unreadable request loads only its requested path")
	_expect(audio.player.stream == previous_stream and audio.current_track == previous_index and audio.play_calls == previous_play_calls, "unreadable request preserves prior playback")
	_expect_equal(previews, [], "unreadable request emits no playback signal")
	_expect_equal(audio.save_calls, previous_save_count, "rejected previews never write settings")
	# Permission belongs to the committed host state; the adapter still fails
	# closed while disabled and leaves the current stream untouched.
	audio.enabled = false
	var disabled_load_count := audio.load_calls.size()
	_expect(not audio.play_track(0), "disabled music rejects preview")
	_expect_equal(audio.load_calls.size(), disabled_load_count, "disabled preview does not load a stream")
	_expect(audio.player.stream == previous_stream and audio.current_track == previous_index and audio.play_calls == previous_play_calls, "disabled preview preserves prior playback")
	_expect_equal(previews, [], "disabled preview emits no playback signal")
	_remove_fixture(audio)


func _test_next_track_compatibility() -> void:
	var audio := _new_fixture()
	var skip := "synthetic://skip.ogg"
	var first := "synthetic://first.ogg"
	var second := "synthetic://second.ogg"
	audio.tracks = PackedStringArray([skip, first, second])
	audio.streams[first] = _stream()
	audio.streams[second] = _stream()
	audio.streams[skip] = null
	audio.enabled = true
	var previews: Array[String] = []
	audio.playback_changed.connect(func(track_name: String) -> void: previews.append(track_name))
	audio.next_track()
	_expect_equal(audio.current_track, 1, "next_track skips an unreadable first track")
	_expect_equal(audio.load_calls, [skip, first], "next_track tries tracks sequentially while skipping bad files")
	_expect_equal(previews, ["first.ogg"], "next_track emits only for the selected valid track")
	audio.next_track()
	_expect_equal(audio.current_track, 2, "next_track advances to the following valid track")
	audio.next_track()
	_expect_equal(audio.current_track, 1, "next_track wraps and skips the unreadable track")
	_expect_equal(previews, ["first.ogg", "second.ogg", "first.ogg"], "wrapped next_track playback signals retain order")
	var before_all_bad_stream: AudioStream = audio.player.stream
	audio.tracks = PackedStringArray(["synthetic://bad-a.ogg", "synthetic://bad-b.ogg"])
	audio.streams["synthetic://bad-a.ogg"] = null
	audio.streams["synthetic://bad-b.ogg"] = null
	var previous_stop_calls := audio.stop_calls
	audio.next_track()
	_expect_equal(audio.stop_calls, previous_stop_calls + 1, "next_track stops when every candidate is unreadable")
	_expect(audio.player.stream == before_all_bad_stream, "all-bad next_track keeps the prior stream while stopping")
	_expect_equal(previews, ["first.ogg", "second.ogg", "first.ogg"], "all-bad next_track emits no playback signal")
	_remove_fixture(audio)


func _test_runtime_persistence_flags() -> void:
	var audio := _new_fixture()
	audio.set_volume(0.2)
	_expect_equal(audio.save_calls, 1, "default set_volume persists once")
	audio.set_enabled(false)
	_expect_equal(audio.save_calls, 2, "default set_enabled persists once")
	audio.set_volume(0.7, false)
	_expect_equal(audio.save_calls, 2, "runtime-only set_volume does not persist")
	audio.set_enabled(true, false)
	_expect_equal(audio.save_calls, 2, "runtime-only set_enabled does not persist")
	_expect(is_equal_approx(audio.volume, 0.7), "runtime-only volume still applies immediately")
	_expect(audio.enabled, "runtime-only enabled state still applies immediately")
	_remove_fixture(audio)
