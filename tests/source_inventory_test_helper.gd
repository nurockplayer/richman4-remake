extends SceneTree

const MainScene = preload("res://game/main.tscn")
const OriginalMaps = preload("res://game/content/original_maps.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	pass

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func settle() -> void:
	await process_frame
	await process_frame

func make_ui(parent: Node) -> Variant:
	var ui: Control = MainScene.instantiate()
	parent.add_child(ui)
	ui.set_process(false)
	if ui.get("audio_controller") != null:
		ui.audio_controller.call("stop")
	return ui

func find_map(ui: Control, edition: String, source_id: int) -> Dictionary:
	for value in ui._map_catalog:
		if str(value.get("edition", "")) == edition and int(value.get("source_map_id", -1)) == source_id:
			return value
	return {}

func press(view: SubViewport, button: Control) -> void:
	button.pressed.emit()
	await process_frame
