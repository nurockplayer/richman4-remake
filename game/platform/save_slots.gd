class_name SaveSlots
extends RefCounted

## Validated JSON storage for the S34 save/load picker.
##
## Slot zero is the existing default save and is intentionally read-only.  The
## writable source-shaped rows are 1..5 and always resolve to canonical files
## below the configured remake-owned directory.  This module does not adopt a
## loaded game; callers receive the validated snapshot and may apply it only
## after their own presentation/legacy guards.

const GameState = preload("res://game/core/game_state.gd")

const DEFAULT_SLOT_DIRECTORY := "user://richman4-save-slots"
const DEFAULT_SAVE_PATH := "user://richman4_save.json"
const FIRST_SLOT := 0
const LAST_SLOT := 5
const FIRST_WRITABLE_SLOT := 1
const LAST_WRITABLE_SLOT := 5
const SLOT_FILE_PREFIX := "slot-"
const SLOT_FILE_SUFFIX := ".json"

const STATUS_EMPTY := "empty"
const STATUS_VALID := "valid"
const STATUS_CORRUPT := "corrupt"
const STATUS_INVALID := "invalid"
const STATUS_UNREADABLE := "unreadable"
const STATUS_ERROR := "error"
const STATUS_STALE := "stale"
const STATUS_READONLY := "readonly"
const STATUS_WRITTEN := "written"

## The default filesystem adapter is deliberately tiny so tests can replace it
## with an object that overrides only one operation (for example rename).
class FileSystemIO extends RefCounted:
	func make_directory(path: String) -> int:
		return DirAccess.make_dir_recursive_absolute(path)

	func file_exists(path: String) -> bool:
		return FileAccess.file_exists(path)

	func read_bytes(path: String) -> Dictionary:
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
		return DirAccess.rename_absolute(source, destination)

	func remove(path: String) -> int:
		return DirAccess.remove_absolute(path)


var _slot_directory: String
var _default_save_path: String
var _io: Object
var _temporary_sequence := 0


func _init(
		slot_directory: String = DEFAULT_SLOT_DIRECTORY,
		default_save_path: String = DEFAULT_SAVE_PATH,
		io_adapter: Object = null,
) -> void:
	if slot_directory.is_empty():
		slot_directory = DEFAULT_SLOT_DIRECTORY
	if default_save_path.is_empty():
		default_save_path = DEFAULT_SAVE_PATH
	_slot_directory = _canonical_path(slot_directory)
	_default_save_path = _canonical_path(default_save_path)
	_io = io_adapter if io_adapter != null else FileSystemIO.new()


## Return the canonical directory used by writable slots.
func slots_directory() -> String:
	return _slot_directory


## Return a canonical path for a valid row.  Invalid rows return an empty path.
## Callers cannot supply an arbitrary path for rows 1..5.
func slot_path(slot_id: Variant) -> String:
	var resolved := _resolve_slot(slot_id)
	return str(resolved.get("path", "")) if bool(resolved.get("ok", false)) else ""


func default_path() -> String:
	return _default_save_path


## Scan all six source-shaped load rows.  The scan operation itself succeeds
## even when an individual row is empty or malformed; each row keeps its own
## explicit status so the picker cannot treat unknown data as a valid save.
func scan() -> Dictionary:
	var rows: Array = []
	for slot_id in range(FIRST_SLOT, LAST_SLOT + 1):
		rows.append(preview(slot_id))
	return {
		"ok": true,
		"status": "scanned",
		"slots": rows,
	}


func scan_slots() -> Dictionary:
	return scan()


## Inspect a row without returning a live game object.  Valid metadata is only
## derived after both validate_save and from_dict accept the parsed snapshot.
func preview(slot_id: Variant) -> Dictionary:
	var resolved := _resolve_slot(slot_id)
	if not bool(resolved.get("ok", false)):
		return _error_result(str(resolved.get("error", "invalid_slot_id")), slot_id)
	return _inspect(int(resolved.slot), str(resolved.path), false)


func preview_slot(slot_id: Variant) -> Dictionary:
	return preview(slot_id)


## Read and validate a row again, returning the parsed snapshot/path.  Nothing
## is assigned to a caller's live game by this module.
func read(slot_id: Variant) -> Dictionary:
	var resolved := _resolve_slot(slot_id)
	if not bool(resolved.get("ok", false)):
		return _error_result(str(resolved.get("error", "invalid_slot_id")), slot_id)
	return _inspect(int(resolved.slot), str(resolved.path), true)


func read_slot(slot_id: Variant) -> Dictionary:
	return read(slot_id)


## Validate and atomically write a writable row.  expected_fingerprint is
## optional: null skips the compare for trusted callers, while an empty string
## explicitly means that the destination was empty at preview time.
func write(slot_id: Variant, payload: Variant, expected_fingerprint: Variant = null) -> Dictionary:
	var resolved := _resolve_slot(slot_id)
	if not bool(resolved.get("ok", false)):
		return _error_result(str(resolved.get("error", "invalid_slot_id")), slot_id)
	var slot := int(resolved.slot)
	if slot == FIRST_SLOT:
		return {
			"ok": false,
			"status": STATUS_READONLY,
			"error": "readonly_slot",
			"slot": slot,
			"path": str(resolved.path),
		}
	if typeof(payload) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"status": STATUS_INVALID,
			"error": "invalid_payload",
			"slot": slot,
			"path": str(resolved.path),
		}
	if not _valid_expected_fingerprint(expected_fingerprint):
		return {
			"ok": false,
			"status": STATUS_ERROR,
			"error": "invalid_expected_fingerprint",
			"slot": slot,
			"path": str(resolved.path),
		}

	var snapshot: Dictionary = payload.duplicate(true)
	var validation := _validate_snapshot(snapshot)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"status": STATUS_INVALID,
			"error": "invalid_payload",
			"validation_errors": validation.get("errors", []),
			"slot": slot,
			"path": str(resolved.path),
		}

	var destination := str(resolved.path)
	var fingerprint_result := _current_fingerprint(destination)
	if expected_fingerprint != null:
		var current_fingerprint := str(fingerprint_result.get("fingerprint", ""))
		var current_readable := bool(fingerprint_result.get("ok", false))
		var destination_exists := bool(fingerprint_result.get("exists", false))
		if not current_readable and destination_exists:
			return _stale_result(slot, destination, str(expected_fingerprint), "destination_unreadable")
		if current_fingerprint != str(expected_fingerprint):
			return _stale_result(slot, destination, str(expected_fingerprint), "destination_changed")

	var directory_error := _ensure_slot_directory()
	if directory_error != OK:
		return {
			"ok": false,
			"status": STATUS_ERROR,
			"error": "directory_create_failed",
			"io_error": directory_error,
			"slot": slot,
			"path": destination,
		}

	var json_text := JSON.stringify(snapshot)
	var bytes := json_text.to_utf8_buffer()
	var temporary := _temporary_path(destination)
	if temporary.is_empty():
		return {
			"ok": false,
			"status": STATUS_ERROR,
			"error": "temporary_path_unavailable",
			"slot": slot,
			"path": destination,
		}
	var temporary_owned := false
	var write_result := _io_call("write_bytes", [temporary, bytes])
	if not bool(write_result.get("ok", false)):
		temporary_owned = bool(write_result.get("created", false))
		_cleanup_temporary(temporary, temporary_owned)
		return {
			"ok": false,
			"status": STATUS_ERROR,
			"error": "temporary_write_failed",
			"io_error": write_result.get("error", "write_failed"),
			"slot": slot,
			"path": destination,
		}
	temporary_owned = true

	var readback := _io_call("read_bytes", [temporary])
	if not bool(readback.get("ok", false)):
		_cleanup_temporary(temporary, temporary_owned)
		return {
			"ok": false,
			"status": STATUS_ERROR,
			"error": "temporary_readback_failed",
			"io_error": readback.get("error", "read_failed"),
			"slot": slot,
			"path": destination,
		}
	var readback_bytes: Variant = readback.get("bytes", null)
	if typeof(readback_bytes) != TYPE_PACKED_BYTE_ARRAY or readback_bytes != bytes:
		_cleanup_temporary(temporary, temporary_owned)
		return {
			"ok": false,
			"status": STATUS_ERROR,
			"error": "temporary_bytes_mismatch",
			"slot": slot,
			"path": destination,
		}
	var readback_validation := _decode_and_validate(readback_bytes)
	if not bool(readback_validation.get("ok", false)):
		_cleanup_temporary(temporary, temporary_owned)
		return {
			"ok": false,
			"status": STATUS_ERROR,
			"error": "temporary_validation_failed",
			"validation_errors": readback_validation.get("errors", []),
			"slot": slot,
			"path": destination,
		}
	if expected_fingerprint != null:
		# Re-check immediately before rename so a writer that occupied an empty
		# destination while this write was preparing its temporary is rejected.
		var final_fingerprint_result := _current_fingerprint(destination)
		var final_fingerprint := str(final_fingerprint_result.get("fingerprint", ""))
		var final_readable := bool(final_fingerprint_result.get("ok", false))
		var final_exists := bool(final_fingerprint_result.get("exists", false))
		if not final_readable and final_exists:
			_cleanup_temporary(temporary, temporary_owned)
			return _stale_result(slot, destination, str(expected_fingerprint), "destination_unreadable")
		if final_fingerprint != str(expected_fingerprint):
			_cleanup_temporary(temporary, temporary_owned)
			return _stale_result(slot, destination, str(expected_fingerprint), "destination_changed")

	var rename_error: int = int(_io_call_value("rename", [temporary, destination], ERR_CANT_CREATE))
	if rename_error != OK:
		_cleanup_temporary(temporary, temporary_owned)
		return {
			"ok": false,
			"status": STATUS_ERROR,
			"error": "atomic_rename_failed",
			"io_error": rename_error,
			"slot": slot,
			"path": destination,
		}
	temporary_owned = false
	# The validated temporary bytes are the exact bytes committed by rename.
	# Avoid a fallible post-rename operation: once rename succeeds, no later
	# check is allowed to report a failure after the old destination is gone.
	var fingerprint := _fingerprint_bytes(bytes)
	return {
		"ok": true,
		"status": STATUS_WRITTEN,
		"slot": slot,
		"path": destination,
		"fingerprint": fingerprint,
		"metadata": _metadata(readback_validation.snapshot),
		"snapshot": snapshot.duplicate(true),
	}


func write_slot(slot_id: Variant, payload: Variant, expected_fingerprint: Variant = null) -> Dictionary:
	return write(slot_id, payload, expected_fingerprint)


func _resolve_slot(slot_id: Variant) -> Dictionary:
	if typeof(slot_id) != TYPE_INT or int(slot_id) < FIRST_SLOT or int(slot_id) > LAST_SLOT:
		return {"ok": false, "error": "invalid_slot_id"}
	var slot := int(slot_id)
	if slot == FIRST_SLOT:
		return {"ok": true, "slot": slot, "path": _default_save_path}
	return {
		"ok": true,
		"slot": slot,
		"path": _slot_directory.path_join(SLOT_FILE_PREFIX + str(slot) + SLOT_FILE_SUFFIX).simplify_path(),
	}


func _inspect(slot: int, path: String, include_snapshot: bool) -> Dictionary:
	var read_result := _io_call("read_bytes", [path])
	if not bool(read_result.get("ok", false)):
		if str(read_result.get("error", "")) == "missing" or not bool(_io_call_value("file_exists", [path], false)):
			return {
				"ok": true,
				"status": STATUS_EMPTY,
				"slot": slot,
				"path": path,
				"fingerprint": "",
			}
		return {
			"ok": false,
			"status": STATUS_UNREADABLE,
			"error": str(read_result.get("error", "read_failed")),
			"slot": slot,
			"path": path,
			"fingerprint": "",
		}
	var bytes: Variant = read_result.get("bytes", null)
	if typeof(bytes) != TYPE_PACKED_BYTE_ARRAY:
		return {
			"ok": false,
			"status": STATUS_UNREADABLE,
			"error": "invalid_io_bytes",
			"slot": slot,
			"path": path,
			"fingerprint": "",
		}
	var fingerprint := _fingerprint_bytes(bytes)
	var decoded := _decode_and_validate(bytes)
	if str(decoded.get("status", "")) == STATUS_CORRUPT:
		return {
			"ok": false,
			"status": STATUS_CORRUPT,
			"error": decoded.get("error", "malformed_json"),
			"slot": slot,
			"path": path,
			"fingerprint": fingerprint,
		}
	if not bool(decoded.get("ok", false)):
		return {
			"ok": false,
			"status": STATUS_INVALID,
			"error": decoded.get("error", "save_validation_failed"),
			"validation_errors": decoded.get("errors", []),
			"slot": slot,
			"path": path,
			"fingerprint": fingerprint,
		}
	var result := {
		"ok": true,
		"status": STATUS_VALID,
		"slot": slot,
		"path": path,
		"fingerprint": fingerprint,
		"metadata": _metadata(decoded.snapshot),
	}
	if include_snapshot:
		result["snapshot"] = decoded.snapshot.duplicate(true)
	return result


func _validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation: Variant = GameState.validate_save(snapshot)
	if typeof(validation) != TYPE_DICTIONARY or not bool(validation.get("ok", false)):
		return {"ok": false, "errors": validation.get("errors", ["save_validation_failed"]) if validation is Dictionary else ["save_validation_failed"]}
	var restored: Variant = GameState.from_dict(snapshot)
	if restored == null:
		return {"ok": false, "errors": ["save_load_validation_failed"]}
	return {"ok": true, "snapshot": snapshot.duplicate(true), "state": restored}


func _decode_and_validate(bytes: PackedByteArray) -> Dictionary:
	var text := bytes.get_string_from_utf8()
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {"ok": false, "status": STATUS_CORRUPT, "error": "malformed_json"}
	var parsed: Variant = parser.data
	var validation := _validate_snapshot(parsed)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"status": STATUS_INVALID,
			"error": "save_validation_failed",
			"errors": validation.get("errors", []),
		}
	return {
		"ok": true,
		"status": STATUS_VALID,
		"snapshot": parsed.duplicate(true),
		"state": validation.get("state"),
	}


func _metadata(snapshot: Dictionary) -> Dictionary:
	# snapshot is only called after GameState validation/from_dict approval.
	var players: Array = snapshot.get("players", []) if snapshot.get("players", []) is Array else []
	var names: Array = []
	var player_character_ids: Array = []
	for player_value in players:
		if player_value is Dictionary:
			names.append(str(player_value.get("name", "")))
	# Setup saves persist this ordered list at the top level.  Older/base saves
	# only carry the optional per-player field, so retain it when available
	# without guessing a portrait from the player's array position.
	var raw_character_ids: Variant = snapshot.get("character_ids", null)
	if raw_character_ids is Array and raw_character_ids.size() == players.size():
		for character_id in raw_character_ids:
			var parsed_character_id := _metadata_int(character_id, 0, 11)
			if parsed_character_id < 0:
				player_character_ids.clear()
				break
			player_character_ids.append(parsed_character_id)
	if player_character_ids.is_empty():
		for player_value in players:
			if not player_value is Dictionary:
				player_character_ids.clear()
				break
			var character_id_value: Variant = player_value.get("character_id", null)
			var parsed_character_id := _metadata_int(character_id_value, 0, 11)
			if parsed_character_id < 0:
				player_character_ids.clear()
				break
			player_character_ids.append(parsed_character_id)
	var date_value: Variant = snapshot.get("date", null)
	var date: Dictionary = date_value.duplicate(true) if date_value is Dictionary else {}
	if date.is_empty() and snapshot.has("day_of_month") and snapshot.has("month"):
		date = {
			"day": int(snapshot.get("day_of_month", 0)),
			"month": int(snapshot.get("month", 0)),
		}
		if snapshot.has("weekday"):
			date["weekday"] = int(snapshot.get("weekday", 0))
	var map_id := str(snapshot.get("map_id", ""))
	var map_name := str(snapshot.get("map_name", ""))
	var map_source_value: Variant = snapshot.get("map_source", {})
	var map_source: Dictionary = map_source_value.duplicate(true) if map_source_value is Dictionary else {}
	var map_edition := str(map_source.get("edition", ""))
	var map_number := -1
	var map_number_value: Variant = map_source.get("map_number", snapshot.get("map_number", null))
	var parsed_map_number := _metadata_int(map_number_value, 1, 99)
	if parsed_map_number >= 1:
		map_number = parsed_map_number
	if map_edition.is_empty() and map_id.contains(":"):
		var map_id_parts := map_id.split(":", false, 1)
		if map_id_parts.size() == 2:
			map_edition = str(map_id_parts[0])
	if map_number < 0 and map_id.contains(":"):
		var map_id_parts := map_id.split(":", false, 1)
		if map_id_parts.size() == 2 and str(map_id_parts[1]).is_valid_int():
			var parsed_map_id_number := int(map_id_parts[1])
			if parsed_map_id_number >= 1 and parsed_map_id_number <= 99:
				map_number = parsed_map_id_number
	var map_preview_chunk := -1
	if map_number >= 1 and map_edition in ["Game", "MultiverseJourney"]:
		var map_count := 4 if map_edition == "Game" else 8
		if map_number <= map_count:
			# The source map_number is one-based; Data479/Data520 previews begin
			# at chunk two, matching the original save/load draw path.
			map_preview_chunk = map_number + 1
	return {
		"date": date,
		"date_text": _date_text(date),
		"map_id": map_id,
		"map_name": map_name,
		"map": map_name if not map_name.is_empty() else map_id,
		"map_source": map_source,
		"map_edition": map_edition,
		"map_number": map_number,
		"map_preview_chunk": map_preview_chunk,
		"board_mode": str(snapshot.get("board_mode", "")),
		"player_count": players.size(),
		"player_names": names,
		"player_character_ids": player_character_ids,
	}


func _metadata_int(value: Variant, minimum: int, maximum: int) -> int:
	var kind := typeof(value)
	var number := 0
	if kind == TYPE_INT:
		number = int(value)
	elif kind == TYPE_FLOAT:
		var float_value := float(value)
		if not is_finite(float_value) or floor(float_value) != float_value:
			return -1
		number = int(float_value)
	else:
		return -1
	return number if number >= minimum and number <= maximum else -1


func _date_text(date: Dictionary) -> String:
	if date.has("year") and date.has("month") and date.has("day"):
		return "%04d-%02d-%02d" % [int(date.year), int(date.month), int(date.day)]
	if date.has("month") and date.has("day"):
		return "%02d-%02d" % [int(date.month), int(date.day)]
	return ""


func _current_fingerprint(path: String) -> Dictionary:
	var exists := bool(_io_call_value("file_exists", [path], false))
	if not exists:
		return {"ok": true, "exists": false, "fingerprint": ""}
	var read_result := _io_call("read_bytes", [path])
	if not bool(read_result.get("ok", false)):
		return {"ok": false, "exists": true, "fingerprint": "", "error": read_result.get("error", "read_failed")}
	var bytes: Variant = read_result.get("bytes", null)
	if typeof(bytes) != TYPE_PACKED_BYTE_ARRAY:
		return {"ok": false, "exists": true, "fingerprint": "", "error": "invalid_io_bytes"}
	return {"ok": true, "exists": true, "fingerprint": _fingerprint_bytes(bytes)}


func _ensure_slot_directory() -> int:
	return int(_io_call_value("make_directory", [_slot_directory], ERR_CANT_CREATE))


func _temporary_path(destination: String) -> String:
	for _attempt in range(100):
		_temporary_sequence += 1
		var candidate := "%s.tmp.%d" % [destination, _temporary_sequence]
		if not bool(_io_call_value("file_exists", [candidate], false)):
			return candidate
	return ""


func _cleanup_temporary(path: String, owned: bool) -> void:
	if owned:
		_io_call_value("remove", [path], ERR_CANT_CREATE)


func _stale_result(slot: int, path: String, expected: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"status": STATUS_STALE,
		"error": "stale_destination",
		"reason": reason,
		"expected_fingerprint": expected,
		"slot": slot,
		"path": path,
	}


func _error_result(error: String, slot_id: Variant) -> Dictionary:
	return {
		"ok": false,
		"status": STATUS_ERROR,
		"error": error,
		"slot": slot_id,
	}


func _valid_expected_fingerprint(value: Variant) -> bool:
	if value == null:
		return true
	if typeof(value) != TYPE_STRING:
		return false
	var fingerprint := str(value)
	if fingerprint.is_empty():
		return true
	if fingerprint.length() != 64:
		return false
	for character in fingerprint:
		if not (character in "0123456789abcdefABCDEF"):
			return false
	return true


func _fingerprint_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func _canonical_path(path: String) -> String:
	if path.is_empty():
		return ""
	var normalized := path.simplify_path()
	if normalized.begins_with("user://") or normalized.begins_with("res://"):
		normalized = ProjectSettings.globalize_path(normalized)
	return normalized.simplify_path()


func _io_call(method: String, args: Array) -> Dictionary:
	if _io == null or not _io.has_method(method):
		return {"ok": false, "error": "io_method_unavailable", "created": false}
	var result: Variant = _io.callv(method, args)
	return result if result is Dictionary else {"ok": false, "error": "invalid_io_result", "created": false}


func _io_call_value(method: String, args: Array, fallback: Variant) -> Variant:
	if _io == null or not _io.has_method(method):
		return fallback
	return _io.callv(method, args)
