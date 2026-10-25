extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const SaveSlotsScript = preload("res://game/platform/save_slots.gd")

var checks := 0
var failures := 0
var _root := ""
var _slot_directory := ""
var _legacy_path := ""


class FaultIO extends SaveSlotsScript.FileSystemIO:
	var mode := ""

	func acquire_write_lock(destination: String) -> Dictionary:
		if mode == "lock":
			return {"ok": false, "path": destination + ".write-lock", "io_error": ERR_BUSY}
		return super.acquire_write_lock(destination)

	func write_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
		if mode == "write" and path.contains(".tmp."):
			return {"ok": false, "error": "injected_write_failure", "created": false}
		return super.write_bytes(path, bytes)

	func read_bytes(path: String) -> Dictionary:
		if mode == "readback" and path.contains(".tmp."):
			return {"ok": false, "error": "injected_readback_failure", "created": false}
		return super.read_bytes(path)

	func rename(source: String, destination: String) -> int:
		if mode == "rename":
			return ERR_CANT_CREATE
		return super.rename(source, destination)


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
	_root = temp_base.path_join("richman4-save-autosave-%d-%d" % [Time.get_ticks_usec(), OS.get_process_id()])
	_slot_directory = _root.path_join("slots")
	_legacy_path = _root.path_join("legacy.json")
	expect(DirAccess.make_dir_recursive_absolute(_root) == OK, "test-owned temporary root is created")
	_test_paths_and_identity()
	_test_automatic_path_collision_preserves_owner()
	_test_automatic_round_trip_and_precedence()
	_test_automatic_fingerprint_switch_is_stale()
	_test_readonly_and_legacy_preservation()
	_test_automatic_failure_and_lock_guards()
	_cleanup()
	print("Save-slot autosave checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _store(io_adapter: Object = null) -> Object:
	return SaveSlotsScript.new(_slot_directory, _legacy_path, io_adapter)


func _payload(seed_value: int) -> Dictionary:
	return GameState.new_game(seed_value, 2).to_dict()


func _write_raw(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	expect(file != null, "test fixture opens raw path")
	if file == null:
		return
	file.store_buffer(bytes)
	file.close()


func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _test_paths_and_identity() -> void:
	var store := _store()
	expect_equal(store.automatic_path(), _slot_directory.path_join("auto.json"), "automatic path is canonical below slot directory")
	expect(store.automatic_path() != store.default_path(), "automatic path never aliases the legacy path")
	for slot_id in range(1, 6):
		expect(store.automatic_path() != store.slot_path(slot_id), "automatic path never aliases manual slot %d" % slot_id)
	var colliding_legacy := SaveSlotsScript.new(_slot_directory, store.automatic_path())
	expect_equal(colliding_legacy.default_path(), store.automatic_path(), "caller legacy path is preserved even when it aliases automatic path")
	var colliding_manual := SaveSlotsScript.new(_slot_directory, _slot_directory.path_join("slot-1.json"))
	expect_equal(colliding_manual.default_path(), colliding_manual.slot_path(1), "caller legacy path is preserved even when it aliases manual path")


func _test_automatic_path_collision_preserves_owner() -> void:
	var colliding := SaveSlotsScript.new(_slot_directory, _slot_directory.path_join("auto.json"))
	var sentinel := "legacy-owner-sentinel".to_utf8_buffer()
	_write_raw(colliding.default_path(), sentinel)
	var result: Dictionary = colliding.write_automatic(_payload(13099))
	expect(not bool(result.get("ok", true)), "automatic write rejects a legacy path collision")
	expect_equal(_bytes(colliding.default_path()), sentinel, "automatic collision preserves the caller-owned legacy file")
	var row_zero: Dictionary = colliding.preview(0)
	expect_equal(row_zero.get("source_identity"), "legacy", "row zero keeps legacy identity under automatic collision")
	var manual_colliding := SaveSlotsScript.new(_slot_directory, _slot_directory.path_join("slot-1.json"))
	var manual_sentinel := "manual-owner-sentinel".to_utf8_buffer()
	_write_raw(manual_colliding.default_path(), manual_sentinel)
	var manual_result: Dictionary = manual_colliding.write_automatic(_payload(13100))
	expect(not bool(manual_result.get("ok", true)), "automatic write rejects a manual-path collision")
	expect_equal(_bytes(manual_colliding.default_path()), manual_sentinel, "manual collision preserves the caller-owned file")
	expect_equal(manual_colliding.preview(0).get("source_identity"), "legacy", "row zero keeps legacy identity under manual collision")
	_remove(colliding.default_path())
	_remove(manual_colliding.default_path())


func _test_automatic_round_trip_and_precedence() -> void:
	var store := _store()
	var payload := _payload(13101)
	var before := payload.duplicate(true)
	var written: Dictionary = store.write_automatic(payload)
	expect(bool(written.get("ok", false)), "automatic payload writes atomically")
	expect_equal(written.get("status"), SaveSlotsScript.STATUS_WRITTEN, "automatic write reports written")
	expect_equal(written.get("source_identity"), "automatic", "automatic write identifies its source")
	expect_equal(_bytes(store.automatic_path()), JSON.stringify(payload).to_utf8_buffer(), "automatic write preserves payload bytes")
	expect_equal(payload, before, "automatic write does not mutate caller payload")

	_write_raw(store.default_path(), JSON.stringify(_payload(13102)).to_utf8_buffer())
	var row_zero: Dictionary = store.preview(0)
	expect_equal(row_zero.get("source_identity"), "automatic", "row zero prefers an existing automatic file")
	expect_equal(row_zero.get("snapshot", null), null, "preview remains metadata-only")
	expect_equal(store.read(0, row_zero.get("fingerprint", "")).get("snapshot", {}).get("seed"), 13101, "row zero reads automatic snapshot")

	_write_raw(store.automatic_path(), "{corrupt".to_utf8_buffer())
	var corrupt: Dictionary = store.preview(0)
	expect_equal(corrupt.get("source_identity"), "automatic", "corrupt automatic source is still selected")
	expect_equal(corrupt.get("status"), SaveSlotsScript.STATUS_CORRUPT, "corrupt automatic source never falls back")

	_remove(store.automatic_path())
	var legacy: Dictionary = store.preview(0)
	expect_equal(legacy.get("source_identity"), "legacy", "row zero falls back only when automatic file is absent")
	expect_equal(legacy.get("status"), SaveSlotsScript.STATUS_VALID, "legacy fallback remains readable")
	expect_equal(store.read(0, legacy.get("fingerprint", "")).get("snapshot", {}).get("seed"), 13102, "legacy fallback reads legacy snapshot")


func _test_automatic_fingerprint_switch_is_stale() -> void:
	var store := _store()
	var bytes := JSON.stringify(_payload(13201)).to_utf8_buffer()
	_write_raw(store.default_path(), bytes)
	var legacy: Dictionary = store.preview(0)
	_write_raw(store.automatic_path(), bytes)
	var automatic: Dictionary = store.preview(0)
	expect_equal(legacy.get("fingerprint", "").length(), 64, "legacy fingerprint is present")
	expect_equal(automatic.get("fingerprint", "").length(), 64, "automatic fingerprint is present")
	expect(legacy.get("fingerprint") != automatic.get("fingerprint"), "source identity domain-separates identical bytes")
	var stale: Dictionary = store.read(0, legacy.get("fingerprint", ""))
	expect_equal(stale.get("status"), SaveSlotsScript.STATUS_STALE, "legacy preview cannot load after automatic source appears")
	expect(not stale.has("snapshot"), "stale source switch exposes no snapshot")


func _test_readonly_and_legacy_preservation() -> void:
	var store := _store()
	var legacy_bytes := JSON.stringify(_payload(13301)).to_utf8_buffer()
	_write_raw(store.default_path(), legacy_bytes)
	var automatic_bytes := JSON.stringify(_payload(13302)).to_utf8_buffer()
	_write_raw(store.automatic_path(), automatic_bytes)
	var rejected: Dictionary = store.write(0, _payload(13303))
	expect_equal(rejected.get("status"), SaveSlotsScript.STATUS_READONLY, "row zero remains read-only")
	expect_equal(rejected.get("source_identity"), "automatic", "row zero write reports selected automatic identity")
	expect_equal(_bytes(store.default_path()), legacy_bytes, "row zero write preserves legacy bytes")
	expect_equal(_bytes(store.automatic_path()), automatic_bytes, "row zero write preserves automatic bytes")
	var manual: Dictionary = store.write(1, _payload(13304), "")
	expect(bool(manual.get("ok", false)), "manual write remains available beside automatic source")
	expect_equal(_bytes(store.default_path()), legacy_bytes, "manual write preserves legacy bytes")
	expect_equal(_bytes(store.automatic_path()), automatic_bytes, "manual write preserves automatic bytes")


func _test_automatic_failure_and_lock_guards() -> void:
	var store := _store()
	var baseline := _payload(13401)
	expect(bool(store.write_automatic(baseline).get("ok", false)), "failure fixture writes automatic baseline")
	var old_bytes := _bytes(store.automatic_path())
	var expected := str(store.preview(0).get("fingerprint", ""))
	var changed := _payload(13402)
	var stale: Dictionary = store.write_automatic(changed, "0".repeat(64))
	expect_equal(stale.get("status"), SaveSlotsScript.STATUS_STALE, "automatic expected fingerprint rejects changed destination")

	for mode in ["lock", "write", "readback", "rename"]:
		var fault := FaultIO.new()
		fault.mode = mode
		var result: Dictionary = _store(fault).write_automatic(changed, expected)
		expect(not bool(result.get("ok", true)), "automatic %s failure is surfaced" % mode)
		expect_equal(_bytes(store.automatic_path()), old_bytes, "automatic %s failure preserves old bytes" % mode)
		if mode != "lock":
			expect(DirAccess.get_directories_at(_slot_directory).is_empty(), "automatic %s failure releases lock" % mode)


func _cleanup() -> void:
	_remove(_legacy_path)
	var directory := DirAccess.open(_slot_directory)
	if directory != null:
		for file_name in directory.get_files():
			_remove(_slot_directory.path_join(str(file_name)))
		for directory_name in directory.get_directories():
			DirAccess.remove_absolute(_slot_directory.path_join(str(directory_name)))
	DirAccess.remove_absolute(_slot_directory)
	DirAccess.remove_absolute(_root)
