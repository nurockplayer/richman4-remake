extends SceneTree
const Maps = preload("res://game/content/original_maps.gd")
var failures := 0
func _initialize() -> void:
	var result := Maps.load_catalog("", true)
	if not result.ok:
		push_error("PRECONDITION_UNMET: actual catalog required")
		quit(2)
		return
	var encounters := 0
	for definition in result.maps:
		for tile in definition.board:
			if int(tile.type_and_idx) < 2001 and int(tile.event_code) == 9:
				encounters += 1
				if tile.kind != "lottery":
					failures += 1
					push_error("FAIL: normal catalog event9 must admit lottery: %s/%d" % [definition.id, tile.index])
	if encounters == 0:
		push_error("PRECONDITION_UNMET: no actual lottery encounters")
		quit(2)
		return
	print("Lottery normal catalog admission: %d encounters, failures: %d" % [encounters, failures])
	quit(1 if failures else 0)
