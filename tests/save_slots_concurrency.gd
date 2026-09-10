extends SceneTree
const Slots = preload("res://game/platform/save_slots.gd")
const Game = preload("res://game/core/game_state.gd")
var checks := 0
var failures := 0

class Schedule extends RefCounted:
	var a_selected := Semaphore.new()
	var b_selected := Semaphore.new()
	var a_final_read := Semaphore.new()
	var b_at_rename := Semaphore.new()
	var a_renamed := Semaphore.new()
	var timeouts: Array = []
	var guard := Mutex.new()
	func wait_for(semaphore: Semaphore, label: String) -> void:
		var deadline := Time.get_ticks_msec() + 4000
		while not semaphore.try_wait():
			if Time.get_ticks_msec() >= deadline:
				guard.lock()
				timeouts.append(label)
				guard.unlock()
				return
			OS.delay_msec(1)

class RacingIO extends Slots.FileSystemIO:
	var actor := ""
	var schedule: Schedule
	var destination := ""
	var destination_reads := 0
	var temporary := ""
	func file_exists(path: String) -> bool:
		var result := super.file_exists(path)
		if path.contains(".tmp.") and temporary.is_empty():
			temporary = path
			# Both writers observe the same absent path before either creates it.
			if actor == "A":
				schedule.a_selected.post()
				schedule.wait_for(schedule.b_selected, "A waits for B path selection")
			else:
				schedule.wait_for(schedule.a_selected, "B waits for A path selection")
				schedule.b_selected.post()
		return result
	func write_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
		if actor == "B":
			schedule.wait_for(schedule.a_final_read, "B waits until A validated its temporary")
		return super.write_bytes(path, bytes)
	func read_bytes(path: String) -> Dictionary:
		var result := super.read_bytes(path)
		if path == destination:
			destination_reads += 1
			if actor == "A" and destination_reads == 2:
				schedule.a_final_read.post()
				schedule.wait_for(schedule.b_at_rename, "A waits for B validated replacement")
		return result
	func rename(source: String, target: String) -> int:
		if actor == "B":
			schedule.b_at_rename.post()
			schedule.wait_for(schedule.a_renamed, "B waits for A rename")
		var result := super.rename(source, target)
		if actor == "A": schedule.a_renamed.post()
		return result

class Writer extends RefCounted:
	var store: RefCounted
	var io: RacingIO
	var payload: Dictionary
	var expected := ""
	var result: Dictionary
	func run() -> void:
		result = store.write(1, payload, expected)
		if io.actor == "B":
			# With exclusion B exits before touching A's temporary. Unblock A's
			# old-implementation schedule without altering any assertion.
			io.schedule.b_selected.post()
			io.schedule.b_at_rename.post()

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var root_path := "/tmp/richman4-save-concurrency-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var directory := root_path.path_join("slots")
	var baseline := Slots.new(directory, root_path.path_join("original.json"))
	var original: Dictionary = Game.new_game(11701, 2).to_dict()
	var first: Dictionary = baseline.write(1, original, "")
	expect(first.get("ok", false), "seed destination through the real filesystem")
	var schedule := Schedule.new()
	var writers: Array = []
	var threads: Array = []
	for actor in ["A", "B"]:
		var io := RacingIO.new()
		io.actor = actor
		io.schedule = schedule
		io.destination = baseline.slot_path(1)
		var writer := Writer.new()
		writer.io = io
		writer.store = Slots.new(directory, root_path.path_join("original.json"), io)
		writer.payload = Game.new_game(11702 if actor == "A" else 11703, 2).to_dict()
		writer.expected = first.fingerprint
		writers.append(writer)
		threads.append(Thread.new())
	# A must obtain the transaction first in the fixed implementation.
	expect(threads[0].start(writers[0].run) == OK, "start independent writer A")
	schedule.wait_for(schedule.a_selected, "coordinator waits for A ownership")
	schedule.a_selected.post()
	expect(threads[1].start(writers[1].run) == OK, "start independent writer B")
	for thread: Thread in threads: thread.wait_to_finish()
	expect(schedule.timeouts.is_empty(), "controlled interleaving completes without timeout: " + str(schedule.timeouts))
	var successes := 0
	for writer: Writer in writers:
		if writer.result.get("ok", false):
			successes += 1
			var actual := FileAccess.get_sha256(baseline.slot_path(1))
			expect(writer.result.get("fingerprint") == actual, writer.io.actor + " successful fingerprint agrees with bytes actually committed")
			expect(FileAccess.get_file_as_bytes(baseline.slot_path(1)) == JSON.stringify(writer.payload).to_utf8_buffer(), writer.io.actor + " successful write committed its own validated snapshot")
	expect(successes == 1, "same-preview concurrent writers admit exactly one transaction")
	expect(writers[0].result.get("ok", false), "owner A completes its transaction")
	expect(not writers[1].result.get("ok", true), "contender B does not overwrite A's temporary or destination")
	var current: Dictionary = baseline.preview(1)
	var retry: Dictionary = baseline.write(1, writers[1].payload, current.get("fingerprint"))
	expect(retry.get("ok", false), "a new transaction succeeds after owner releases the slot")
	expect(retry.get("fingerprint") == FileAccess.get_sha256(baseline.slot_path(1)), "retry result matches actual destination bytes")
	var entries := DirAccess.get_files_at(directory)
	expect(entries.size() == 1 and entries[0] == "slot-1.json", "writers leave no temporary file")
	expect(DirAccess.get_directories_at(directory).is_empty(), "writers leave no owned lock directory")
	for name in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(root_path)
	print("Save-slot concurrency checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
