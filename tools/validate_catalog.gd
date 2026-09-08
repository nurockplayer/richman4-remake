extends SceneTree
const Maps = preload("res://game/content/original_maps.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var original_facilities := false
	if args.size() == 2 and args[1] == "--original-facilities":
		original_facilities = true
	elif args.size() != 1:
		push_error("Expected one local map catalog path, optionally followed by --original-facilities")
		quit(1)
		return
	var result := Maps.load_catalog(args[0], original_facilities)
	if not result.ok or result.maps.is_empty():
		push_error(result.get("error", "Map catalog is empty"))
		quit(1)
		return
	print("Validated local map catalog: %d maps (original facilities: %s)" % [result.maps.size(), original_facilities])
	quit(0)
