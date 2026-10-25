class_name RichmanSystemSettings
extends RefCounted
## Source system preferences only. The host owns applying them to live systems.
## Paths are explicit so tests and previews never access the owner's settings.

const SCHEMA := "richman4.system-settings/v1"
const DEFAULT_PATH := "user://system-options.json"
const MAX_BYTES := 4096
const LIMITS := {"speed": 2, "music_level": 4, "sound_level": 4, "view": 2}

func defaults() -> Dictionary:
	return {"speed": 1, "animation": true, "music_level": 4, "sound_level": 4, "autosave": true, "view": 1}

func validate_settings(value: Variant, json_numbers := false) -> Dictionary:
	if not value is Dictionary or value.size() != 6:
		return _unavailable("invalid_settings")
	var normalized := defaults()
	for key in LIMITS:
		var number: Variant = value.get(key)
		if typeof(number) != TYPE_INT:
			if not json_numbers or typeof(number) != TYPE_FLOAT or not is_finite(number) or number != floor(number):
				return _unavailable("invalid_" + key)
		if number < 0 or number > LIMITS[key]:
			return _unavailable("invalid_" + key)
		normalized[key] = int(number)
	for key in ["animation", "autosave"]:
		if typeof(value.get(key)) != TYPE_BOOL:
			return _unavailable("invalid_" + key)
		normalized[key] = value[key]
	return {"ok": true, "settings": normalized}

func read_settings(path: String) -> Dictionary:
	if path.is_empty() or DirAccess.dir_exists_absolute(path) or _is_link(path):
		return _unavailable("invalid_path")
	if not FileAccess.file_exists(path):
		return {"ok": true, "status": "defaults", "settings": defaults()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _unavailable("read_failed")
	if file.get_length() > MAX_BYTES:
		file.close()
		return _unavailable("file_too_large")
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return _unavailable("invalid_json")
	var document: Variant = parser.data
	if not document is Dictionary or document.size() != 2 or document.get("schema") != SCHEMA:
		return _unavailable("invalid_schema")
	var result := validate_settings(document.get("settings"), true)
	if not result.ok:
		return result
	result["status"] = "loaded"
	return result

func write_settings(path: String, settings: Dictionary) -> Dictionary:
	var checked := validate_settings(settings)
	if not checked.ok:
		return checked
	if path.is_empty() or DirAccess.dir_exists_absolute(path) or _is_link(path) or not DirAccess.dir_exists_absolute(path.get_base_dir()):
		return _unavailable("invalid_path")
	var text := JSON.stringify({"schema": SCHEMA, "settings": checked.settings}, "\t") + "\n"
	var temporary := path + ".tmp-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary) or _is_link(temporary):
		return _unavailable("temporary_exists")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _unavailable("write_failed")
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	var readback := read_settings(temporary)
	if write_error != OK or not readback.ok or readback.settings != checked.settings or FileAccess.get_file_as_string(temporary) != text:
		DirAccess.remove_absolute(temporary)
		return _unavailable("write_validation_failed")
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		return _unavailable("replace_failed")
	return {"ok": true, "status": "saved", "settings": checked.settings.duplicate(true)}

func _is_link(path: String) -> bool:
	var directory := DirAccess.open(path.get_base_dir())
	return directory != null and directory.is_link(path.get_file())

func _unavailable(error: String) -> Dictionary:
	return {"ok": false, "status": "unavailable", "error": error, "settings": defaults()}
