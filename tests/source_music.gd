extends SceneTree
## Source music layout (rich4.exe 47e773 / 454d91 / 4549cf / 454bcc): board
## tracks cycle among the first eight, scene cues play once and resume the
## board track, and MainUI cues the magic house, bail service and month end.
const OriginalAudio = preload("res://game/platform/original_audio.gd")
const MainScene = preload("res://game/main.tscn")
const Fixture = preload("res://tests/fixtures/status_fixture.gd")


class AudioFixture extends OriginalAudio:
	func _settings_path() -> String:
		return ""

	func _default_source_paths() -> Array[String]:
		return []

	func _save_settings() -> void:
		pass

	func _load_track(path: String) -> AudioStream:
		return AudioStreamGenerator.new()

	func _play_current() -> void:
		pass


class CueRecorder extends Node:
	var cues: Array = []

	func play_cue(cue: int) -> bool:
		cues.append(cue)
		return true


var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func source_library(count: int) -> PackedStringArray:
	var names: PackedStringArray = []
	for index in range(count):
		names.append("synthetic://track%02d.ogg" % (index + 2))
	return names


func run() -> void:
	if OS.get_environment("RICHMAN4_USER_ROOT").is_empty():
		push_error("RICHMAN4_USER_ROOT must point at a throwaway directory.")
		quit(2)
		return
	var audio := AudioFixture.new()
	audio.tracks = source_library(25)
	var order: Array = []
	for step in range(10):
		audio.next_track()
		order.append(audio.current_track)
	expect(order == [0, 1, 2, 3, 4, 5, 6, 7, 0, 1], "board tracks cycle among the first eight: %s" % [order])
	expect(audio.play_cue(7), "a source library plays scene cues")
	expect(audio.current_track == 1 and audio.player.stream != null, "a cue leaves the board track index alone")
	expect(audio.play_cue(9), "a second cue may interrupt the first")
	audio._on_finished()
	expect(audio.current_track == 1, "the cue's end resumes the interrupted board track, not the next one")
	audio._on_finished()
	expect(audio.current_track == 2, "a board track's end moves to the next board track")
	expect(not audio.play_cue(17), "cues beyond the source table are refused")
	audio.tracks = source_library(5)
	audio.current_track = -1
	order.clear()
	for step in range(6):
		audio.next_track()
		order.append(audio.current_track)
	expect(order == [0, 1, 2, 3, 4, 0] and not audio.play_cue(0), "other libraries cycle every track and have no cues")
	audio.free()

	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var recorder := CueRecorder.new()
	ui.add_child(recorder)
	var definition: Dictionary = Fixture.definition()
	definition.board[1].merge({"kind": "unsupported", "event_code": 16, "source_status_bits": 16, "name": "魔法屋"}, true)
	definition.board[1].erase("points")
	expect(ui._new_game(42, 4, definition, ui._default_setup_options(4, definition)), "status-capable UI new game starts")
	ui.audio_controller = recorder
	var game: Object = ui.game_state
	game.state.god_objects = []
	ui._refresh_from_state()
	expect(recorder.cues.is_empty(), "a new game only sets the cue baseline")
	game.state.current_player = 0
	game.state.players[0].position = 1
	game._graph_visit_tile(0, game.state.board[1], true)
	ui._refresh_from_state()
	expect(recorder.cues == [7], "landing on the magic house plays cue 7 (MIDI08): %s" % [recorder.cues])
	ui._refresh_from_state()
	expect(recorder.cues == [7], "a refresh does not replay the cue")
	var clinic_definition: Dictionary = Fixture.definition()
	clinic_definition.board[1].merge({"kind": "unsupported", "event_code": 5, "source_status_bits": 5, "name": "醫院入口"}, true)
	clinic_definition.board[1].erase("points")
	expect(ui._new_game(43, 4, clinic_definition, ui._default_setup_options(4, clinic_definition)), "hospital-entrance UI new game starts")
	ui.audio_controller = recorder
	game = ui.game_state
	game.state.god_objects = []
	ui._refresh_from_state()
	game._admit_player_status(3, "hospital", 3)
	game.state.current_player = 0
	game.state.players[0].position = 1
	game._graph_visit_tile(0, game.state.board[1], true)
	ui._refresh_from_state()
	expect(recorder.cues == [7, 16], "the hospital entrance service plays cue 16 (MIDI16): %s" % [recorder.cues])
	game._record_event("month_end_settlement", {"month": 1})
	ui._refresh_from_state()
	expect(recorder.cues == [7, 16, 9], "the month-end statement plays cue 9 (MIDI10): %s" % [recorder.cues])
	ui.game_state = Game_from(game)
	ui._refresh_from_state()
	expect(recorder.cues == [7, 16, 9], "loading a game does not replay its last cue")
	ui.queue_free()
	await process_frame
	print("Source music checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func Game_from(game: Object) -> Object:
	return game.get_script().from_dict(JSON.parse_string(game.to_json()))
