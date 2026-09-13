extends SceneTree

# M7 reads only COUNT and _NAMES from the frozen source.  It deliberately does
# not call catalog(), name_for(), the resolver, state, RNG, eligibility, or any
# other gameplay helper.
const FateSource = preload("res://game/core/fate_events.gd")
const PREFIX := "RICHMAN4_FATE_EVENTS_ORACLE="

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func _initialize() -> void:
	var count: Variant = FateSource.COUNT
	if typeof(count) != TYPE_INT or count != 37:
		fail("M7 COUNT must be exactly 37")
		return
	var names: Variant = FateSource._NAMES
	if typeof(names) != TYPE_ARRAY or names.size() != count:
		fail("M7 _NAMES must contain exactly 37 labels")
		return
	var rows: Array = []
	for fate_id in range(count):
		var display_name: Variant = names[fate_id]
		if typeof(display_name) != TYPE_STRING or display_name.strip_edges().is_empty():
			fail("M7 _NAMES labels must be non-empty Text")
			return
		rows.append({
			"fate_id": fate_id,
			"display_name": display_name,
		})
	print(PREFIX + JSON.stringify({"fate_names": rows}))
	quit(0)
