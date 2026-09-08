extends SceneTree
const Maps = preload("res://game/content/original_maps.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected one local map catalog path")
		quit(1)
		return
	var result := Maps.load_catalog(args[0])
	if not result.ok or result.maps.is_empty():
		push_error(result.get("error", "Map catalog is empty"))
		quit(1)
		return
	print("Validated local map catalog: %d maps" % result.maps.size())
	quit(0)
