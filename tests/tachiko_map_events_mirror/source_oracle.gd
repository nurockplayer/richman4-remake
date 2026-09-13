extends SceneTree

# M5 reads only the frozen static EVENT_NAMES constant. Never call load_catalog,
# normalize_map, classify_source_node or any runtime/gameplay helper.
const MapSource = preload("res://game/content/original_maps.gd")
const PREFIX := "RICHMAN4_MAP_EVENTS_ORACLE="

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func _initialize() -> void:
	var codes: Array = MapSource.EVENT_NAMES.keys()
	codes.sort()
	if codes.size() != 17:
		fail("M5 EVENT_NAMES must contain exactly 17 rows")
		return
	var rows: Array = []
	for expected_code in range(0, 17):
		if codes[expected_code] != expected_code:
			fail("M5 EVENT_NAMES codes must be exactly 0..16")
			return
		var display_name: Variant = MapSource.EVENT_NAMES[expected_code]
		if typeof(display_name) != TYPE_STRING or display_name.strip_edges().is_empty():
			fail("M5 event display_name must be non-empty Text")
			return
		rows.append({
			"event_code": expected_code,
			"display_name": display_name,
		})
	print(PREFIX + JSON.stringify({"event_names": rows}))
	quit(0)
