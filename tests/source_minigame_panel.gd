extends SceneTree

const PanelScript = preload("res://game/ui/source_minigame_panel.gd")

var checks := 0
var failures := 0
var finish_count := 0

class Worker extends RefCounted:
	var done := false
	var configured: Array = []
	var pointers: Array = []
	func configure(kind: String, seed: int, input_data: Variant) -> void:
		configured = [kind, seed, input_data]
	func tick() -> void:
		pass
	func pointer(position: Vector2, pressed: bool) -> void:
		pointers.append([position, pressed])
	func snapshot() -> Dictionary:
		return {"finished": done, "reward": 25}
	func finished() -> bool:
		return done
	func reward() -> int:
		return 25

func _initialize() -> void:
	call_deferred("_run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var panel := PanelScript.new()
	root.add_child(panel)
	var worker := Worker.new()
	panel.finish_requested.connect(func() -> void: finish_count += 1)
	expect(panel.configure("S31", 17, {"difficulty": 2}, worker), "S31 config accepted")
	expect(panel.kind() == "balloon" and panel.phase() == "intro", "intro starts before gameplay")
	expect(panel.source_geometry().get("canvas") == Vector2(640, 480), "canvas keeps source dimensions")
	expect(panel.source_geometry().get("intro").get("frame_count") == 20, "intro has twenty source frames")
	expect(panel.source_geometry().get("intro").get("interval_ms") == 114, "intro cadence is 114ms")
	expect(panel.set_scale_factor(2.0) and panel.scale_factor() == 2.0, "2x scale is supported")
	expect(not panel.pointer(Vector2(20, 20), true), "intro does not accept pointer input")
	panel.tick(20.0)
	expect(panel.phase() == "gameplay" and panel.is_playing(), "intro transitions to gameplay")
	expect(not panel.pointer(Vector2(-1, 10), true), "outside pointer is ignored")
	expect(panel.pointer(Vector2(100, 100), true), "canvas pointer is routed")
	expect(worker.pointers.size() == 1 and worker.pointers[0][0] == Vector2(100, 100), "worker receives logical canvas point")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = false
	panel.call("_gui_input", right_click)
	expect(panel.is_playing(), "right click cannot close active game")
	worker.done = true
	panel.tick(0.0, true)
	expect(panel.is_result() and panel.reward() == 25, "finished worker enters result phase")
	panel.tick(1.99)
	expect(finish_count == 0, "result hold is two seconds")
	panel.tick(0.01)
	expect(finish_count == 1, "result completion emits once")
	panel.tick(2.0)
	expect(finish_count == 1, "result completion does not repeat")
	panel.cancel()
	expect(not panel.is_open(), "cancel closes panel")
	print("Source minigame panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
