extends RefCounted
class_name RichmanSystemHotkeys
## Source VK words only. No global InputMap mutation or implicit owner I/O.

const SCHEMA := "richman4.system-hotkeys/v1"
const DEFAULT_PATH := "user://system-hotkeys.json"
const MAX_BYTES := 4096
const DEFAULTS := [0x26,0x27,0x28,0x25,0x0d,0x1b,0x09,0x09,0x59,0x4e,0x20,0x44,0x57,0x58,0x43,0x45,0x46,0x4d,0xbc,0xbe,0x41,0x56,0x53,0x4c,0x48,0x21,0x22,0x1151]
const NAMED_KEYS := {
	0x08:"BS", 0x09:"TAB", 0x0d:"ENTER", 0x11:"CTRL-", 0x1b:"ESC",
	0x20:"SPACE", 0x21:"PG UP", 0x22:"PG DN", 0x23:"END", 0x24:"HOME",
	0x25:"←", 0x26:"↑", 0x27:"→", 0x28:"↓", 0x2d:"INS",
	0x6a:"*", 0x6b:"+", 0x6d:"-", 0x6f:"/",
}
const OEM_ASCII := {0xba:59,0xbb:61,0xbc:44,0xbd:45,0xbe:46,0xbf:47,0xc0:96,0xdb:91,0xdc:92,0xdd:93,0xde:39}
const GODOT_TO_SOURCE := {
	KEY_BACKSPACE:0x08, KEY_TAB:0x09, KEY_ENTER:0x0d, KEY_KP_ENTER:0x0d,
	KEY_CTRL:0x11, KEY_ESCAPE:0x1b, KEY_SPACE:0x20, KEY_PAGEUP:0x21,
	KEY_PAGEDOWN:0x22, KEY_END:0x23, KEY_HOME:0x24, KEY_LEFT:0x25,
	KEY_UP:0x26, KEY_RIGHT:0x27, KEY_DOWN:0x28, KEY_INSERT:0x2d,
	KEY_KP_MULTIPLY:0x6a, KEY_KP_ADD:0x6b, KEY_KP_SUBTRACT:0x6d, KEY_KP_DIVIDE:0x6f,
}

func defaults() -> Array:
	return DEFAULTS.duplicate()

func validate_bindings(value: Variant, json_numbers := false) -> Dictionary:
	if not value is Array or value.size() != 28:
		return _unavailable("invalid_bindings")
	var result: Array = []
	for raw in value:
		if typeof(raw) != TYPE_INT:
			if not json_numbers or typeof(raw) != TYPE_FLOAT or not is_finite(raw) or raw != floor(raw):
				return _unavailable("invalid_binding_type")
		if raw < 0 or raw > 0x11ff:
			return _unavailable("invalid_binding_range")
		var word := int(raw)
		if (word >> 8) not in [0,0x11] or not _known_key(word & 0xff):
			return _unavailable("unsupported_binding")
		result.append(word)
	# Source defaults duplicate TAB, and an unfinished edit can commit zero.
	# Rejecting an attempted duplicate assignment belongs to the presenter.
	return {"ok":true, "bindings":result}

func key_name(word: int) -> String:
	if word < 0 or word > 0x11ff or (word >> 8) not in [0,0x11]:
		return ""
	var key := word & 0xff
	if key == 0:
		return ""
	var label := ""
	if NAMED_KEYS.has(key):
		label = str(NAMED_KEYS[key])
	elif key >= 0x30 and key <= 0x39 or key >= 0x41 and key <= 0x5a:
		label = String.chr(key)
	elif key >= 0x70 and key <= 0x7b:
		label = "F%d" % (key - 0x6f)
	elif OEM_ASCII.has(key):
		label = String.chr(int(OEM_ASCII[key]))
	if label.is_empty():
		return ""
	return ("CTRL-" if (word >> 8) == 0x11 else "") + label

func event_key(event: InputEventKey) -> int:
	var code := int(event.keycode if event.keycode != 0 else event.physical_keycode)
	if code >= KEY_0 and code <= KEY_9 or code >= KEY_A and code <= KEY_Z:
		return code
	if code >= KEY_F1 and code <= KEY_F12:
		return 0x70 + code - KEY_F1
	if GODOT_TO_SOURCE.has(code):
		return int(GODOT_TO_SOURCE[code])
	for key in OEM_ASCII:
		if int(OEM_ASCII[key]) == code:
			return int(key)
	return 0

func read_bindings(path: String) -> Dictionary:
	if path.is_empty() or DirAccess.dir_exists_absolute(path) or _is_link(path):
		return _unavailable("invalid_path")
	if not FileAccess.file_exists(path):
		return {"ok":true, "status":"defaults", "bindings":defaults()}
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
	var result := validate_bindings(document.get("bindings"), true)
	if result.ok:
		result["status"] = "loaded"
	return result

func write_bindings(path: String, bindings: Array) -> Dictionary:
	var checked := validate_bindings(bindings)
	if not checked.ok:
		return checked
	if path.is_empty() or DirAccess.dir_exists_absolute(path) or _is_link(path) or not DirAccess.dir_exists_absolute(path.get_base_dir()):
		return _unavailable("invalid_path")
	var text := JSON.stringify({"schema":SCHEMA, "bindings":checked.bindings}, "\t") + "\n"
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
	var readback := read_bindings(temporary)
	if write_error != OK or not readback.ok or readback.bindings != checked.bindings or FileAccess.get_file_as_string(temporary) != text:
		DirAccess.remove_absolute(temporary)
		return _unavailable("write_validation_failed")
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return _unavailable("replace_failed")
	return {"ok":true, "status":"saved", "bindings":checked.bindings.duplicate()}

func _known_key(key: int) -> bool:
	return key == 0 or NAMED_KEYS.has(key) or OEM_ASCII.has(key) \
		or key >= 0x30 and key <= 0x39 or key >= 0x41 and key <= 0x5a \
		or key >= 0x70 and key <= 0x7b

func _is_link(path: String) -> bool:
	var directory := DirAccess.open(path.get_base_dir())
	return directory != null and directory.is_link(path.get_file())

func _unavailable(error: String) -> Dictionary:
	return {"ok":false, "status":"unavailable", "error":error, "bindings":defaults()}
