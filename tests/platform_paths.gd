extends SceneTree
const Paths = preload("res://game/platform/original_paths.gd")
var failures := 0
func _initialize() -> void:
	for sample in [
		["/opt/Richman 4/Richman4.x86_64", "Linux", "/opt/Richman 4/Original"],
		["/home/me/Games/大富翁4/Richman4.x86_64", "Linux", "/home/me/Games/大富翁4/Original"],
		["/Applications/Richman4.app/Contents/MacOS/Richman4", "macOS", "/Applications/Richman4.app/Contents/Resources/Original"],
		["C:/Games/Richman4/Richman4.exe", "Windows", "C:/Games/Richman4/Original"],
	]:
		if Paths.packaged_root(sample[0], sample[1]) != sample[2]:
			failures += 1
			push_error("Wrong private asset root for " + sample[0])
	if Paths.packaged("maps/catalog.json") != Paths.packaged_root().path_join("maps/catalog.json"):
		failures += 1
		push_error("Packaged catalog must resolve relative to executable")
	print("Platform paths: 5 checks, %d failures" % failures)
	quit(1 if failures else 0)
