extends RefCounted

## Input-plane data is loaded once, outside gameplay ticks, and hash verified.
## It is a logical source plane, never inferred from displayed sprite alpha.
static var _loaded_path := ""
static var _data: Dictionary = {}

## Resolve the input manifest next to the executable first, so a packaged app
## never falls back to the development-only res:// path. `executable_dir` is a
## parameter so the packaged lookup is testable without building an app.
static func manifest_path(executable_dir: String) -> String:
	var path := OS.get_environment("RICHMAN4_MINIGAME_MANIFEST")
	if not path.is_empty(): return path
	var packaged := executable_dir.path_join("../Resources/Original/minigame/manifest.json").simplify_path()
	if FileAccess.file_exists(packaged): return packaged
	return ProjectSettings.globalize_path("res://.local/source-minigames-scene/manifest.json")

static func input_data() -> Dictionary:
	return input_data_from(manifest_path(OS.get_executable_path().get_base_dir()))

static func input_data_from(path: String) -> Dictionary:
	if path == _loaded_path: return _data
	_loaded_path = path
	_data = {}
	if not FileAccess.file_exists(path): return _data
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("schema","") != "richman4.minigame-assets/v1": return _data
	var input: Variant = parsed.get("input",{})
	if not input is Dictionary: return _data
	var entry: Variant = input.get("penguin_mask",{})
	if not entry is Dictionary: return _data
	var relative: String = str(entry.get("path",""))
	if relative.is_empty() or relative.is_absolute_path() or ".." in relative.split("/"): return _data
	var source := path.get_base_dir().path_join(relative)
	if FileAccess.get_sha256(source) != str(entry.get("sha256","")): return _data
	var bytes := FileAccess.get_file_as_bytes(source)
	if bytes.size() != 640*480: return _data
	var grid_entry: Variant = input.get("penguin_grid",{})
	if not grid_entry is Dictionary: return {}
	var grid_relative := str(grid_entry.get("path",""))
	if grid_relative.is_empty() or grid_relative.is_absolute_path() or ".." in grid_relative.split("/"): return {}
	var grid_source := path.get_base_dir().path_join(grid_relative)
	if FileAccess.get_sha256(grid_source) != str(grid_entry.get("sha256","")): return {}
	var grid: Variant = JSON.parse_string(FileAccess.get_file_as_string(grid_source))
	if not grid is Dictionary or not grid.get("records") is Array or grid.records.size()!=81: return {}
	var coordinates: Array = []
	var flags: Array = []
	for record in grid.records:
		if not record is Dictionary or not record.get("x") is float or not record.get("y") is float: return {}
		coordinates.append(Vector2i(int(record.x),int(record.y)))
		flags.append(int(record.get("source_initial_flags",0)))
	_data["penguin_mask"] = bytes
	_data["penguin_grid"] = coordinates
	_data["penguin_flags"] = flags
	var characters: Dictionary = {}
	for edition in ["Game","MultiverseJourney"]:
		var resources: Dictionary = parsed.get("resources",{}).get(edition,{})
		var entries: Array = []
		for character_id in range(12):
			var chunks: Dictionary = resources.get(str(100+character_id),{}).get("chunks",{})
			var frames: Array = []
			for index in range(chunks.size()):
				var logical: Dictionary = chunks.get(str(index),{}).get("logical",{})
				frames.append({"x":int(logical.get("anchor_x",0)),"y":int(logical.get("anchor_y",0)),"width":int(logical.get("width",0)),"height":int(logical.get("height",0))})
			entries.append(frames)
		characters[edition]=entries
	_data["catching_characters"] = characters
	return _data
