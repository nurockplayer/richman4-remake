extends RefCounted

## Loads the private source-help text bundle written by
## tools/export_original_help.py.
##
## The original body text stays in the private bundle; this loader only
## validates the index and each edition document, bounds every read and
## returns detached copies.  A missing or invalid edition never borrows the
## other edition's content.  The whole-file digest from the index covers
## content integrity; per-topic payload digests are checked structurally.
## ``source_payload_sha256`` records the exact decoded original resource bytes
## and is enforced here; the pure presenter does not need it.

const SCHEMA_INDEX := "richman4.help/v1"
const SCHEMA_EDITION := "richman4.help-edition/v1"
const SUPPORTED_EDITIONS := ["Game", "MultiverseJourney"]
const SECTION_TOPIC_COUNTS := [1, 6, 12, 3, 16, 18, 30, 13]
const TOTAL_TOPICS := 99
const ENTRY_COUNT := 100
const MAX_INDEX_BYTES := 64 * 1024
const MAX_EDITION_BYTES := 2 * 1024 * 1024
const MIN_PAGE_LINES := 1
const MAX_PAGE_LINES := 14

## Validated index document; empty when no usable manifest was found.
var manifest: Dictionary = {}
## Directory that owns the index, used to resolve relative content paths.
var base_path := ""
## edition -> {"content": Dictionary} or {"error": String}
var _editions: Dictionary = {}


func _init(path := "") -> void:
	if path.is_empty():
		path = OS.get_environment("RICHMAN4_HELP_MANIFEST")
	if path.is_empty():
		var packaged := OS.get_executable_path().get_base_dir().path_join("../Resources/Original/help/manifest.json").simplify_path()
		if FileAccess.file_exists(packaged):
			path = packaged
		else:
			path = ProjectSettings.globalize_path("res://.local/original-help/manifest.json")
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var text := _read_bounded(path, MAX_INDEX_BYTES)
	if text.is_empty():
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and _valid_index(parsed):
		manifest = parsed
		base_path = path.get_base_dir()


## Detached edition content dictionary, or {} when the edition is unusable.
func for_edition(edition: String) -> Dictionary:
	var resolved := _resolve(edition)
	var content: Variant = resolved.get("content")
	if not content is Dictionary:
		return {}
	return (content as Dictionary).duplicate(true)


## True only when this exact edition validated.
func available(edition: String) -> bool:
	var content: Variant = _resolve(edition).get("content")
	return content is Dictionary and not (content as Dictionary).is_empty()


## Human-readable readiness for one edition.
func status(edition: String) -> String:
	if not edition in SUPPORTED_EDITIONS:
		return "unsupported edition: %s" % edition
	if manifest.is_empty():
		return "help manifest unavailable"
	var error: Variant = _resolve(edition).get("error")
	return str(error) if error != null and str(error) != "" else "ok"


func _resolve(edition: String) -> Dictionary:
	if not edition in SUPPORTED_EDITIONS:
		return {"error": "unsupported edition: %s" % edition}
	if _editions.has(edition):
		return _editions[edition]
	var result: Dictionary = {"error": "help manifest unavailable"}
	if not manifest.is_empty():
		var editions: Dictionary = manifest.get("editions", {})
		result = _load_edition(edition, editions.get(edition))
	_editions[edition] = result
	return result


func _load_edition(edition: String, record: Variant) -> Dictionary:
	if not record is Dictionary:
		return {"error": "%s: missing index entry" % edition}
	var relative: Variant = record.get("path")
	if not relative is String or not _safe_relative_path(relative):
		return {"error": "%s: unsafe content path" % edition}
	var expected_sha: Variant = record.get("sha256")
	if not _is_hex64(expected_sha):
		return {"error": "%s: invalid content digest" % edition}
	var archive_sha: Variant = record.get("archive_sha256")
	if not _is_hex64(archive_sha):
		return {"error": "%s: invalid archive digest" % edition}
	if not _int_field(record.get("entry_count"), ENTRY_COUNT, ENTRY_COUNT):
		return {"error": "%s: unexpected archive entry count" % edition}
	var path := base_path.path_join(relative)
	var text := _read_bounded(path, MAX_EDITION_BYTES)
	if text.is_empty():
		return {"error": "%s: unreadable content" % edition}
	if FileAccess.get_sha256(path) != expected_sha:
		return {"error": "%s: content digest mismatch" % edition}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"error": "%s: invalid content JSON" % edition}
	var problem := _validate_edition(parsed, edition, str(archive_sha))
	if not problem.is_empty():
		return {"error": problem}
	return {"content": parsed}


func _valid_index(index: Dictionary) -> bool:
	if index.get("schema") != SCHEMA_INDEX:
		return false
	var editions: Variant = index.get("editions")
	if not editions is Dictionary or (editions as Dictionary).size() != SUPPORTED_EDITIONS.size():
		return false
	for edition in SUPPORTED_EDITIONS:
		var record: Variant = (editions as Dictionary).get(edition)
		if not record is Dictionary:
			return false
		var relative: Variant = (record as Dictionary).get("path")
		if not relative is String or not _safe_relative_path(relative):
			return false
		if not _is_hex64((record as Dictionary).get("sha256")) or not _is_hex64((record as Dictionary).get("archive_sha256")):
			return false
		if not _int_field((record as Dictionary).get("entry_count"), ENTRY_COUNT, ENTRY_COUNT):
			return false
	return true


func _validate_edition(document: Dictionary, edition: String, archive_sha: String) -> String:
	if document.get("schema") != SCHEMA_EDITION:
		return "%s: unsupported content schema" % edition
	if document.get("edition") != edition:
		return "%s: content is bound to another edition" % edition
	if document.get("archive_sha256") != archive_sha:
		return "%s: archive provenance mismatch" % edition
	var sections: Variant = document.get("sections")
	if not sections is Array or (sections as Array).size() != SECTION_TOPIC_COUNTS.size():
		return "%s: unexpected section count" % edition
	var section_list: Array = sections
	var expected_resource := 1
	for section_index in range(SECTION_TOPIC_COUNTS.size()):
		var section: Variant = section_list[section_index]
		if not section is Dictionary:
			return "%s: section %d is not an object" % [edition, section_index]
		var section_map: Dictionary = section
		if not _int_field(section_map.get("id"), section_index, section_index):
			return "%s: section %d id mismatch" % [edition, section_index]
		var label: Variant = section_map.get("label")
		if not label is String or (label as String).is_empty():
			return "%s: section %d label is missing" % [edition, section_index]
		var topics: Variant = section_map.get("topics")
		if not topics is Array or (topics as Array).size() != SECTION_TOPIC_COUNTS[section_index]:
			return "%s: section %d topic count mismatch" % [edition, section_index]
		for topic in topics:
			if not topic is Dictionary:
				return "%s: resource %d is not an object" % [edition, expected_resource]
			var topic_map: Dictionary = topic
			if not _int_field(topic_map.get("resource_index"), expected_resource, expected_resource):
				return "%s: resource %d index mismatch" % [edition, expected_resource]
			var title: Variant = topic_map.get("title")
			if not title is String or (title as String).is_empty():
				return "%s: resource %d title is missing" % [edition, expected_resource]
			if not _is_hex64(topic_map.get("payload_sha256")):
				return "%s: resource %d payload digest is invalid" % [edition, expected_resource]
			if not _is_hex64(topic_map.get("source_payload_sha256")):
				return "%s: resource %d source digest is invalid" % [edition, expected_resource]
			var problem := _validate_pages(topic_map.get("pages"), edition, expected_resource)
			if not problem.is_empty():
				return problem
			expected_resource += 1
	if expected_resource - 1 != TOTAL_TOPICS:
		return "%s: unexpected topic count" % edition
	return ""


func _validate_pages(value: Variant, edition: String, resource_index: int) -> String:
	if not value is Array or (value as Array).is_empty():
		return "%s: resource %d has no pages" % [edition, resource_index]
	for page in value:
		if not page is Array or (page as Array).size() < MIN_PAGE_LINES or (page as Array).size() > MAX_PAGE_LINES:
			return "%s: resource %d page line count is invalid" % [edition, resource_index]
		for line in page:
			if not line is String or (line as String).to_utf8_buffer().has(0):
				return "%s: resource %d has a non-text line" % [edition, resource_index]
	return ""


func _safe_relative_path(value: String) -> bool:
	if value.is_empty() or value.is_absolute_path() or value.contains("\\") or value.contains("..") or value.contains(":"):
		return false
	return value.ends_with(".json")


func _is_hex64(value: Variant) -> bool:
	if not value is String:
		return false
	var text: String = value
	if text.length() != 64:
		return false
	for index in range(64):
		var code := text.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


func _int_field(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value) and value >= low and value <= high


func _read_bounded(path: String, limit: int) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	if file.get_length() > limit:
		file.close()
		return ""
	var text := file.get_as_text()
	file.close()
	return text
