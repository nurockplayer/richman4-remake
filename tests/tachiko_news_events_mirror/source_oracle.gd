extends SceneTree

# M6 reads only the frozen static COUNT and _NAMES constants. Never call catalog,
# is_supported, name_for, new_state, validate_state or any runtime/gameplay helper.
const NewsSource = preload("res://game/core/news_events.gd")
const PREFIX := "RICHMAN4_NEWS_EVENTS_ORACLE="
const EXPECTED_COUNT := 36

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func _initialize() -> void:
	var count: int = NewsSource.COUNT
	if count != EXPECTED_COUNT:
		fail("M6 news COUNT must be exactly 36")
		return
	var names: Array = NewsSource._NAMES
	if names.size() != count:
		fail("M6 _NAMES must contain exactly COUNT entries")
		return
	var rows: Array = []
	for news_id in range(count):
		var display_name: Variant = names[news_id]
		if typeof(display_name) != TYPE_STRING or display_name.strip_edges().is_empty():
			fail("M6 news display_name must be non-empty Text")
			return
		rows.append({
			"news_id": news_id,
			"display_name": display_name,
		})
	print(PREFIX + JSON.stringify({"news_names": rows}))
	quit(0)
