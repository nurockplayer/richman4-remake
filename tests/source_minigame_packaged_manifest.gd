extends SceneTree

## Focused check: a packaged app resolves the minigame input manifest from
## Contents/Resources/Original/minigame before the development fallback.
## The fixture manifest, mask and grid are generated here; no original files.

const Assets = preload("res://game/platform/source_minigame_assets.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)


func _sha256(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "fixture file is writable: " + path)
	if file == null:
		return
	file.store_buffer(data)
	file.close()


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		DirAccess.remove_absolute(path)
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while name != "":
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _run() -> void:
	var root := ProjectSettings.globalize_path(
		"res://.local/minigame-packaged-%d-%d" % [
			OS.get_process_id(), Time.get_ticks_usec(),
		]
	)
	var previous := OS.get_environment("RICHMAN4_MINIGAME_MANIFEST")
	OS.set_environment("RICHMAN4_MINIGAME_MANIFEST", "")
	var macos_dir := root.path_join("Fake.app/Contents/MacOS")
	var packaged_dir := root.path_join(
		"Fake.app/Contents/Resources/Original/minigame"
	)
	DirAccess.make_dir_recursive_absolute(macos_dir)
	DirAccess.make_dir_recursive_absolute(packaged_dir.path_join("input"))
	var mask := PackedByteArray()
	mask.resize(640 * 480)
	var grid := {"schema": "richman4.private-source-penguin-coordinate-table/v1",
		"records": []}
	for index in range(81):
		grid.records.append({"x": index % 9, "y": floori(index / 9.0),
			"source_initial_flags": 0})
	var grid_bytes := JSON.stringify(grid).to_utf8_buffer()
	_write(packaged_dir.path_join("input/penguin-mask.bin"), mask)
	_write(packaged_dir.path_join("input/penguin-grid.json"), grid_bytes)
	var manifest := {
		"schema": "richman4.minigame-assets/v1",
		"version": 1,
		"input": {
			"penguin_mask": {
				"path": "input/penguin-mask.bin",
				"sha256": _sha256(mask),
				"width": 640,
				"height": 480,
			},
			"penguin_grid": {
				"path": "input/penguin-grid.json",
				"sha256": _sha256(grid_bytes),
			},
		},
		"resources": {},
	}
	_write(packaged_dir.path_join("manifest.json"), JSON.stringify(manifest).to_utf8_buffer())

	var resolved := Assets.manifest_path(macos_dir)
	_check(
		resolved == packaged_dir.path_join("manifest.json").simplify_path(),
		"packaged app resolves Original/minigame/manifest.json first",
	)
	var data: Dictionary = Assets.input_data_from(resolved)
	var loaded_mask: Variant = data.get("penguin_mask", PackedByteArray())
	_check(
		loaded_mask is PackedByteArray and loaded_mask.size() == 640 * 480,
		"packaged mask loads at its declared size",
	)
	var loaded_grid: Variant = data.get("penguin_grid", [])
	_check(
		loaded_grid is Array and loaded_grid.size() == 81
			and loaded_grid[80] == Vector2i(8, 8),
		"packaged grid loads all 81 source coordinates",
	)
	var empty_dir := root.path_join("Empty.app/Contents/MacOS")
	DirAccess.make_dir_recursive_absolute(empty_dir)
	var fallback := Assets.manifest_path(empty_dir)
	_check(
		fallback.ends_with(".local/source-minigames-scene/manifest.json"),
		"without a package the development fallback stays explicit",
	)

	OS.set_environment("RICHMAN4_MINIGAME_MANIFEST", previous)
	_remove_tree(root)
	print("Packaged minigame manifest checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
