extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const SaveSlotsScript = preload("res://game/platform/save_slots.gd")

var checks := 0
var failures := 0
var _root := ""
var _slot_directory := ""
var _default_path := ""


class FaultIO extends RefCounted:
	var mode := ""

	func make_directory(path: String) -> int:
		return DirAccess.make_dir_recursive_absolute(path)

	func file_exists(path: String) -> bool:
		return FileAccess.file_exists(path)

	func read_bytes(path: String) -> Dictionary:
		if mode == "unreadable" and path.ends_with("slot-4.json"):
			return {"ok": false, "error": "permission_denied", "created": false}
		if mode == "readback" and path.contains(".tmp."):
			return {"ok": false, "error": "injected_readback_failure", "created": false}
		if not FileAccess.file_exists(path):
			return {"ok": false, "error": "missing", "created": false}
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {"ok": false, "error": "open_failed", "created": false}
		var length := file.get_length()
		var bytes := file.get_buffer(length) if length >= 0 else PackedByteArray()
		var read_error := file.get_error()
		file.close()
		if length < 0 or read_error != OK or bytes.size() != length:
			return {"ok": false, "error": "read_failed", "created": false}
		return {"ok": true, "bytes": bytes, "created": false}

	func write_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
		if mode == "write" and path.contains(".tmp."):
			return {"ok": false, "error": "injected_write_failure", "created": false}
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return {"ok": false, "error": "open_failed", "created": false}
		file.store_buffer(bytes)
		var write_error := file.get_error()
		file.close()
		if write_error != OK:
			return {"ok": false, "error": "write_failed", "created": true}
		return {"ok": true, "created": true}

	func rename(source: String, destination: String) -> int:
		if mode == "rename":
			return ERR_CANT_CREATE
		return DirAccess.rename_absolute(source, destination)

	func remove(path: String) -> int:
		return DirAccess.remove_absolute(path)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _initialize() -> void:
	var temp_base := OS.get_environment("TMPDIR")
	if temp_base.is_empty():
		temp_base = "/tmp"
	_root = temp_base.path_join("richman4-save-slots-%d-%d" % [Time.get_ticks_usec(), OS.get_process_id()])
	_slot_directory = _root.path_join("slots")
	_default_path = _root.path_join("richman4_save.json")
	var create_error := DirAccess.make_dir_recursive_absolute(_root)
	expect(create_error == OK, "isolated temporary root is created")
	if create_error != OK:
		quit(1)
	_test_empty_corrupt_invalid_and_unreadable()
	_test_valid_round_trip_and_rng_continuation()
	_test_five_independent_slots()
	_test_readonly_default()
	_test_malformed_ids_and_payloads()
	_test_stale_fingerprint_protection()
	_test_read_expected_fingerprint_protection()
	_test_failure_preserves_existing_bytes()
	_test_preview_and_read_do_not_mutate_game()
	_cleanup()
	print("Save-slot checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _store(io_adapter: Object = null) -> Object:
	return SaveSlotsScript.new(_slot_directory, _default_path, io_adapter)


func _game(seed_value: int) -> GameState:
	return GameState.new_game(seed_value, 2)


func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	expect(file != null, "test fixture opens raw path")
	if file == null:
		return
	file.store_string(text)
	file.close()


func _bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _test_empty_corrupt_invalid_and_unreadable() -> void:
	_clear_slots()
	var store := _store()
	var empty: Dictionary = store.preview(1)
	expect(bool(empty.get("ok", false)), "empty preview operation succeeds")
	expect_equal(empty.get("status"), SaveSlotsScript.STATUS_EMPTY, "missing slot is explicitly empty")
	expect_equal(empty.get("fingerprint"), "", "empty slot has an empty fingerprint")

	_write_raw(store.slot_path(2), "{not valid json")
	var corrupt: Dictionary = store.preview(2)
	expect(not bool(corrupt.get("ok", true)), "malformed JSON preview is rejected")
	expect_equal(corrupt.get("status"), SaveSlotsScript.STATUS_CORRUPT, "malformed JSON is corrupt")
	expect(str(corrupt.get("error", "")).length() > 0, "corrupt preview has an explicit error")

	_write_raw(store.slot_path(3), JSON.stringify({}))
	var invalid: Dictionary = store.preview(3)
	expect(not bool(invalid.get("ok", true)), "semantically invalid JSON preview is rejected")
	expect_equal(invalid.get("status"), SaveSlotsScript.STATUS_INVALID, "validated JSON is invalid when save schema rejects it")
	expect(invalid.get("validation_errors", []).size() > 0, "invalid preview exposes validation errors")

	var unreadable_io := FaultIO.new()
	unreadable_io.mode = "unreadable"
	_write_raw(store.slot_path(4), JSON.stringify({"fixture": "unreadable"}))
	var unreadable: Dictionary = _store(unreadable_io).preview(4)
	expect(not bool(unreadable.get("ok", true)), "unreadable path is rejected")
	expect_equal(unreadable.get("status"), SaveSlotsScript.STATUS_UNREADABLE, "unreadable path has its own status")

	var scanned: Dictionary = store.scan()
	expect(bool(scanned.get("ok", false)), "scan operation succeeds with mixed row states")
	expect_equal(scanned.get("slots", []).size(), 6, "scan returns source-shaped rows zero through five")
	expect_equal(scanned.get("slots", [])[1].get("status"), SaveSlotsScript.STATUS_EMPTY, "scan preserves empty row status")
	expect_equal(scanned.get("slots", [])[2].get("status"), SaveSlotsScript.STATUS_CORRUPT, "scan preserves corrupt row status")
	expect_equal(scanned.get("slots", [])[3].get("status"), SaveSlotsScript.STATUS_INVALID, "scan preserves invalid row status")


func _test_valid_round_trip_and_rng_continuation() -> void:
	_clear_slots()
	var store := _store()
	var game := _game(11701)
	var payload: Dictionary = game.to_dict()
	var expected_json := JSON.stringify(payload)
	var written: Dictionary = store.write(1, payload, "")
	expect(bool(written.get("ok", false)), "valid payload writes to slot one")
	expect_equal(written.get("status"), SaveSlotsScript.STATUS_WRITTEN, "write returns written status")
	expect_equal(_bytes(store.slot_path(1)), expected_json.to_utf8_buffer(), "slot bytes exactly match current JSON save contract")
	expect_equal(written.get("snapshot"), payload, "write returns the validated snapshot")

	var preview: Dictionary = store.preview(1)
	expect(bool(preview.get("ok", false)), "valid slot preview succeeds")
	expect_equal(preview.get("status"), SaveSlotsScript.STATUS_VALID, "valid slot has valid status")
	expect(preview.get("fingerprint", "").length() == 64, "valid preview includes SHA-256 fingerprint")
	expect_equal(preview.get("metadata", {}).get("player_count"), 2, "metadata derives player count from validated snapshot")
	expect_equal(preview.get("metadata", {}).get("date"), {"day": 1, "month": 1, "weekday": 1}, "metadata derives date from validated snapshot")

	var read: Dictionary = store.read(1)
	expect(bool(read.get("ok", false)), "valid slot read succeeds")
	expect_equal(read.get("status"), SaveSlotsScript.STATUS_VALID, "read validates again and remains valid")
	expect_equal(read.get("snapshot", {}).get("seed"), payload.get("seed"), "read returns the saved seed")
	expect_equal(read.get("snapshot", {}).get("rng_state_text"), payload.get("rng_state_text"), "read returns exact RNG state text")

	var original_continuation := GameState.from_dict(payload)
	var loaded_continuation := GameState.from_dict(read.get("snapshot", {}))
	expect(original_continuation != null and loaded_continuation != null, "round-trip snapshots instantiate continuation states")
	if original_continuation != null and loaded_continuation != null:
		var original_roll := original_continuation.roll()
		var loaded_roll := loaded_continuation.roll()
		expect_equal(original_roll.get("dice"), loaded_roll.get("dice"), "loaded state preserves deterministic RNG continuation")
		expect_equal(loaded_continuation.state.get("position"), original_continuation.state.get("position"), "loaded state preserves post-roll position")
		expect_equal(loaded_continuation.state.get("rng_state_text"), original_continuation.state.get("rng_state_text"), "loaded state preserves post-roll RNG text")


func _test_five_independent_slots() -> void:
	_clear_slots()
	var store := _store()
	var payloads: Dictionary = {}
	for slot_id in range(1, 6):
		var payload: Dictionary = _game(11700 + slot_id).to_dict()
		payloads[slot_id] = payload
		var result: Dictionary = store.write(slot_id, payload, "")
		expect(bool(result.get("ok", false)), "slot %d writes independently" % slot_id)
		expect_equal(result.get("slot"), slot_id, "slot %d reports its own id" % slot_id)
	for slot_id in range(1, 6):
		var row: Dictionary = store.read(slot_id)
		expect(bool(row.get("ok", false)), "slot %d remains readable" % slot_id)
		expect_equal(row.get("snapshot", {}).get("seed"), 11700 + slot_id, "slot %d retains its own seed" % slot_id)
		expect_equal(row.get("snapshot", {}).get("rng_state_text"), payloads[slot_id].get("rng_state_text"), "slot %d retains its exact RNG state" % slot_id)
		expect(store.slot_path(slot_id) != store.slot_path(slot_id + 1) if slot_id < 5 else true, "canonical slot paths are independent")


func _test_readonly_default() -> void:
	_clear_slots()
	var store := _store()
	var default_payload: Dictionary = _game(11700).to_dict()
	_write_raw(_default_path, JSON.stringify(default_payload))
	var original_bytes := _bytes(_default_path)
	var preview: Dictionary = store.preview(0)
	expect(bool(preview.get("ok", false)), "row zero reads the existing default JSON")
	expect_equal(preview.get("status"), SaveSlotsScript.STATUS_VALID, "row zero is a valid read-only adapter")
	var write_result: Dictionary = store.write(0, _game(11999).to_dict())
	expect(not bool(write_result.get("ok", true)), "row zero write is rejected")
	expect_equal(write_result.get("status"), SaveSlotsScript.STATUS_READONLY, "row zero reports read-only status")
	expect_equal(_bytes(_default_path), original_bytes, "row zero default bytes remain unchanged")
	var slot_write: Dictionary = store.write(1, _game(11888).to_dict(), "")
	expect(bool(slot_write.get("ok", false)), "writable row still succeeds beside default")
	expect_equal(_bytes(_default_path), original_bytes, "writing a dedicated slot never changes default bytes")


func _test_malformed_ids_and_payloads() -> void:
	_clear_slots()
	var store := _store()
	var valid_payload: Dictionary = _game(11777).to_dict()
	for malformed_id in [null, -1, 6, 1.5, "1", "1/../../outside", true, {}, []]:
		var preview: Dictionary = store.preview(malformed_id)
		expect(not bool(preview.get("ok", true)), "malformed slot id is rejected by preview: %s" % str(malformed_id))
		expect_equal(preview.get("error"), "invalid_slot_id", "malformed slot id exposes stable error: %s" % str(malformed_id))
		var read: Dictionary = store.read(malformed_id)
		expect(not bool(read.get("ok", true)), "malformed slot id is rejected by read: %s" % str(malformed_id))
		var write: Dictionary = store.write(malformed_id, valid_payload)
		expect(not bool(write.get("ok", true)), "malformed slot id is rejected by write: %s" % str(malformed_id))
	for malformed_payload in [null, [], "bad", true, 1, {}]:
		var result: Dictionary = store.write(1, malformed_payload)
		expect(not bool(result.get("ok", true)), "malformed payload is rejected: %s" % str(malformed_payload))
		expect_equal(result.get("status"), SaveSlotsScript.STATUS_INVALID, "malformed payload is explicitly invalid")
	var invalid_payload := valid_payload.duplicate(true)
	invalid_payload.erase("rng_state")
	var invalid_result: Dictionary = store.write(1, invalid_payload)
	expect(not bool(invalid_result.get("ok", true)), "schema-invalid dictionary is rejected")
	expect_equal(invalid_result.get("status"), SaveSlotsScript.STATUS_INVALID, "schema-invalid dictionary reports invalid status")


func _test_stale_fingerprint_protection() -> void:
	_clear_slots()
	var store := _store()
	var first_preview: Dictionary = store.preview(1)
	expect_equal(first_preview.get("fingerprint"), "", "empty preview records empty expected destination")
	var first_payload: Dictionary = _game(12001).to_dict()
	var second_payload: Dictionary = _game(12002).to_dict()
	expect(bool(store.write(1, first_payload, "").get("ok", false)), "first writer occupies empty slot")
	var stale_empty: Dictionary = store.write(1, second_payload, first_preview.get("fingerprint"))
	expect(not bool(stale_empty.get("ok", true)), "empty preview cannot overwrite a newly occupied slot")
	expect_equal(stale_empty.get("status"), SaveSlotsScript.STATUS_STALE, "empty preview race reports stale status")
	expect_equal(store.read(1).get("snapshot", {}).get("seed"), 12001, "stale empty write preserves occupant bytes")

	var current_preview: Dictionary = store.preview(1)
	var third_payload: Dictionary = _game(12003).to_dict()
	expect(bool(store.write(1, third_payload, current_preview.get("fingerprint")).get("ok", false)), "matching fingerprint permits overwrite")
	var stale_existing: Dictionary = store.write(1, first_payload, current_preview.get("fingerprint"))
	expect(not bool(stale_existing.get("ok", true)), "old existing preview cannot overwrite changed slot")
	expect_equal(stale_existing.get("status"), SaveSlotsScript.STATUS_STALE, "changed existing slot reports stale status")
	expect_equal(store.read(1).get("snapshot", {}).get("seed"), 12003, "stale existing write preserves newer bytes")


func _test_read_expected_fingerprint_protection() -> void:
	_clear_slots()
	var store := _store()
	var payload_a: Dictionary = _game(12011).to_dict()
	var payload_b: Dictionary = _game(12012).to_dict()
	expect(bool(store.write(1, payload_a, "").get("ok", false)), "read fingerprint fixture writes snapshot A")
	var preview_a: Dictionary = store.preview(1)
	var expected_a := str(preview_a.get("fingerprint", ""))
	expect_equal(expected_a.length(), 64, "read fingerprint fixture captures snapshot A fingerprint")

	var same_fingerprint := _read_with_expected(store, 1, expected_a)
	expect(bool(same_fingerprint.get("ok", false)), "matching read fingerprint succeeds")
	expect_equal(same_fingerprint.get("status"), SaveSlotsScript.STATUS_VALID, "matching read fingerprint remains valid")
	expect_equal(same_fingerprint.get("snapshot", {}).get("seed"), payload_a.get("seed"), "matching read returns snapshot A")

	expect(bool(store.write(1, payload_b).get("ok", false)), "read fingerprint fixture replaces snapshot with valid B")
	var stale_read := _read_with_expected(store, 1, expected_a)
	expect(not bool(stale_read.get("ok", true)), "read rejects a replaced valid snapshot")
	expect_equal(stale_read.get("status"), SaveSlotsScript.STATUS_STALE, "replaced valid snapshot reports stale status")
	expect(not stale_read.has("snapshot"), "stale read never exposes a replacement snapshot")
	expect_equal(stale_read.get("error"), "stale_destination", "stale read exposes the stable destination error")
	var current_read: Dictionary = store.read(1)
	expect(bool(current_read.get("ok", false)), "raw read still succeeds for the current snapshot")
	expect_equal(current_read.get("status"), SaveSlotsScript.STATUS_VALID, "raw read remains valid after replacement")
	expect_equal(current_read.get("snapshot", {}).get("seed"), payload_b.get("seed"), "raw read returns snapshot B only when explicitly requested")

	var invalid_expected := _read_with_expected(store, 1, "not-a-sha256")
	expect(not bool(invalid_expected.get("ok", true)), "malformed expected read fingerprint is rejected")
	expect_equal(invalid_expected.get("status"), SaveSlotsScript.STATUS_ERROR, "malformed expected read fingerprint reports error")
	expect_equal(invalid_expected.get("error"), "invalid_expected_fingerprint", "malformed expected read fingerprint exposes stable error")
	expect(not invalid_expected.has("snapshot"), "invalid expected fingerprint never exposes a snapshot")


func _read_with_expected(store: Object, slot_id: int, expected_fingerprint: Variant) -> Dictionary:
	# Replay the same assertions on the original public API. Its actual raw
	# read returns replacement B; an invalid call with two arguments would only
	# prove a harness/API mismatch, not the missing stale-selection behavior.
	for method in store.get_method_list():
		if str(method.get("name", "")) == "read":
			var arguments: Array = method.get("args", [])
			var result: Variant = store.callv("read", [slot_id, expected_fingerprint] if arguments.size() >= 2 else [slot_id])
			return result if result is Dictionary else {}
	return {}


func _test_failure_preserves_existing_bytes() -> void:
	_clear_slots()
	var baseline := _store()
	var old_payload: Dictionary = _game(12101).to_dict()
	expect(bool(baseline.write(1, old_payload, "").get("ok", false)), "failure fixture writes a baseline slot")
	var old_bytes := _bytes(baseline.slot_path(1))
	var new_payload: Dictionary = _game(12102).to_dict()
	var expected: String = str(baseline.preview(1).get("fingerprint", ""))

	var write_fault := FaultIO.new()
	write_fault.mode = "write"
	var write_failed: Dictionary = _store(write_fault).write(1, new_payload, expected)
	expect(not bool(write_failed.get("ok", true)), "injected temporary write failure is returned")
	expect_equal(_bytes(baseline.slot_path(1)), old_bytes, "temporary write failure preserves old bytes")

	var readback_fault := FaultIO.new()
	readback_fault.mode = "readback"
	var readback_failed: Dictionary = _store(readback_fault).write(1, new_payload, expected)
	expect(not bool(readback_failed.get("ok", true)), "injected temporary readback failure is returned")
	expect_equal(_bytes(baseline.slot_path(1)), old_bytes, "temporary readback failure preserves old bytes")

	var rename_fault := FaultIO.new()
	rename_fault.mode = "rename"
	var rename_failed: Dictionary = _store(rename_fault).write(1, new_payload, expected)
	expect(not bool(rename_failed.get("ok", true)), "injected atomic rename failure is returned")
	expect_equal(_bytes(baseline.slot_path(1)), old_bytes, "atomic rename failure preserves old bytes")
	var slot_dir := DirAccess.open(_slot_directory)
	if slot_dir != null:
		for file_name in slot_dir.get_files():
			expect(not str(file_name).contains(".tmp."), "failed write cleans only owned temporary files")


func _test_preview_and_read_do_not_mutate_game() -> void:
	_clear_slots()
	var store := _store()
	var game := _game(12201)
	var payload: Dictionary = game.to_dict()
	var before_json := game.to_json()
	var before_state := game.state.duplicate(true)
	expect(bool(store.write(1, payload, "").get("ok", false)), "mutation fixture writes")
	store.preview(1)
	store.read(1)
	expect_equal(game.to_json(), before_json, "preview/read do not mutate supplied game JSON")
	expect_equal(game.state, before_state, "preview/read do not mutate supplied game state")
	var after_preview_continuation := GameState.from_dict(payload)
	var after_read_continuation := GameState.from_dict(store.read(1).get("snapshot", {}))
	if after_preview_continuation != null and after_read_continuation != null:
		var first := after_preview_continuation.roll()
		var second := after_read_continuation.roll()
		expect_equal(first.get("dice"), second.get("dice"), "preview/read preserve RNG continuation")


func _cleanup() -> void:
	_clear_slots()
	_remove_if_exists(_default_path)
	DirAccess.remove_absolute(_root)


func _clear_slots() -> void:
	for slot_id in range(1, 6):
		_remove_if_exists(_slot_directory.path_join("slot-%d.json" % slot_id))
	var slot_dir := DirAccess.open(_slot_directory)
	if slot_dir != null:
		for file_name in slot_dir.get_files():
			_remove_if_exists(_slot_directory.path_join(str(file_name)))
	DirAccess.remove_absolute(_slot_directory)
