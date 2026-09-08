extends RefCounted

## Private scene images are optional and bound to the loaded map's provenance.
var manifest: Dictionary = {}
var base_path := ""
var _textures: Dictionary = {}

func _init(path := "") -> void:
	if path.is_empty():
		path = OS.get_environment("RICHMAN4_SCENE_MANIFEST")
	if path.is_empty():
		path = OS.get_executable_path().get_base_dir().path_join("../Resources/Original/scenes/manifest.json").simplify_path()
		if not FileAccess.file_exists(path):
			path = ProjectSettings.globalize_path("res://.local/original-scenes/manifest.json")
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 8 * 1024 * 1024:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and parsed.get("schema") == "richman4.scene-images/v1" and parsed.get("maps") is Array and parsed.get("characters") is Dictionary:
		manifest = parsed
		base_path = path.get_base_dir()

func scene_for(definition: Dictionary) -> Dictionary:
	var source: Variant = definition.get("source", {})
	if not source is Dictionary or source.is_empty():
		return {}
	var identity := "%s:%d" % [source.get("edition", ""), int(source.get("map_number", 0))]
	for entry in manifest.get("maps", []):
		if entry is Dictionary and entry.get("id") == identity and entry.get("source_file_sha256") == source.get("source_file_sha256") and entry.get("graph_payload_sha256") == source.get("payload_sha256"):
			if world_rect(entry).has_area() and entry.get("lands") is Array and entry.get("house_sprites") is Array and entry.get("scenery", []) is Array and entry.get("scenery_sprites", []) is Array:
				var valid := true
				for land in entry.lands + entry.get("scenery", []):
					if not land is Dictionary:
						valid = false
						break
					for field in ["id", "x", "y", "direction"] + (["sprite_id"] if land.has("sprite_id") else []):
						if not _number(land.get(field), 0, 65535):
							valid = false
				if valid:
					return entry
	return {}

func texture(record: Variant) -> Texture2D:
	if not record is Dictionary or not record.get("path") is String or not record.get("sha256") is String:
		return null
	var relative: String = record.path
	if not relative.begins_with("images/") or relative.contains("..") or relative.contains("\\") or relative.is_absolute_path():
		return null
	var key: String = relative + ":" + record.sha256
	if _textures.has(key):
		return _textures[key]
	var path := base_path.path_join(relative)
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != record.sha256:
		return null
	var loaded := Image.load_from_file(path)
	if loaded == null or loaded.is_empty() or loaded.get_width() != record.get("width") or loaded.get_height() != record.get("height") or loaded.get_width() > 16384 or loaded.get_height() > 16384:
		return null
	var result := ImageTexture.create_from_image(loaded)
	_textures[key] = result
	return result

func character(edition: String, character_id: int, direction := 0) -> Dictionary:
	var group: Variant = manifest.get("characters", {}).get(edition, {})
	if not group is Dictionary or not group.get("sprites", []) is Array:
		return {}
	return _frame(group.get("sprites", []), "character_id", character_id, direction)

func house(scene: Dictionary, level: int, direction: int) -> Dictionary:
	return _frame(scene.get("house_sprites", []), "level", level, direction)

func scenery(scene: Dictionary, sprite_id: int, direction: int) -> Dictionary:
	return _frame(scene.get("scenery_sprites", []), "sprite_id", sprite_id, direction)

func _frame(sprites: Array, field: String, value: int, direction: int) -> Dictionary:
	for sprite in sprites:
		if not sprite is Dictionary or sprite.get(field) != value:
			continue
		var frames: Variant = sprite.get("frames", [])
		if frames is Array and direction >= 0 and direction < frames.size() and frames[direction] is Dictionary:
			var frame: Dictionary = frames[direction]
			if not frame.get("logical") is Dictionary:
				return {}
			for key in ["anchor_x", "anchor_y", "width", "height"]:
				if not _number(frame.logical.get(key), 1 if key in ["width", "height"] else -65535, 65535):
					return {}
			return frame
	return {}

func _number(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value) and value >= low and value <= high

func world_rect(scene: Dictionary) -> Rect2:
	var rect: Variant = scene.get("world_rect")
	if not rect is Dictionary:
		return Rect2()
	for key in ["x", "y", "width", "height"]:
		if not _number(rect.get(key), 1 if key in ["width", "height"] else -65535, 65535):
			return Rect2()
	return Rect2(rect.x, rect.y, rect.width, rect.height)

func sprite_rect(frame: Dictionary, center: Vector2, scale_factor: float) -> Rect2:
	var logical: Dictionary = frame.get("logical", {})
	return Rect2(center - Vector2(logical.get("anchor_x", 0), logical.get("anchor_y", 0)) * scale_factor, Vector2(logical.get("width", 0), logical.get("height", 0)) * scale_factor)
