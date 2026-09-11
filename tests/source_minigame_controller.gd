extends SceneTree

const ControllerScript = preload("res://game/ui/source_minigame_controller.gd")

var checks := 0
var failures := 0
var finish_intents: Array = []

class Worker extends RefCounted:
	var configured: Array = []
	var pointers: Array = []
	func configure(kind: String, seed: int, input_data: Variant) -> void:
		configured = [kind, seed, input_data]
	func tick() -> void:
		pass
	func pointer(position: Vector2, pressed: bool) -> void:
		pointers.append([position, pressed])
	func snapshot() -> Dictionary:
		return {"finished": false}
	func finished() -> bool:
		return false
	func reward() -> int:
		return 0

class Owner extends RefCounted:
	var phase := "await_minigame"
	var pointed: Array = []
	var ticks := 0
	var encounter_id := 41
	var done := false
	func minigame_snapshot() -> Dictionary:
		return {"phase": phase, "kind": "S32", "encounter_id": encounter_id, "seed": 9, "input_data": {"speed": 3}, "model": {"finished": done}, "reward": 60, "finished": done}
	func minigame_tick(id: int) -> Dictionary:
		ticks += 1
		return minigame_snapshot()
	func minigame_pointer(id: int, position: Vector2, pressed: bool) -> Dictionary:
		pointed.append([id, position, pressed])
		if pressed:
			done = true
		return minigame_snapshot()
	func finish_minigame(id: int) -> Dictionary:
		phase = "await_turn"
		return {"ok": id == encounter_id}

func _initialize() -> void:
	call_deferred("_run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var owner := Owner.new()
	var worker := Worker.new()
	var controller := ControllerScript.new()
	controller.model_factory = func(_kind: String) -> Variant: return worker
	root.add_child(controller)
	controller.action_requested.connect(func(method: String, args: Array) -> void: finish_intents.append([method, args]))
	controller.sync(owner, true)
	expect(controller.is_open() and controller.panel != null and not controller.visible, "blocked encounter stays pending without starting presentation")
	var panel: Control = controller.panel
	panel.tick(20.0)
	expect(panel.phase() == "intro", "hidden pending panel does not advance intro")
	controller.sync(owner, false)
	expect(controller.visible and panel.visible, "unblocked encounter is shown")
	expect(worker.configured == ["penguin", 9, {"speed": 3}], "worker receives source configuration")
	panel.tick(20.0)
	panel.pointer(Vector2(80, 90), true)
	expect(owner.pointed.size() == 1 and owner.pointed[0][0] == 41, "pointer carries encounter identity")
	expect(panel.is_result(), "core completion enters result presentation")
	panel.tick(2.0)
	expect(finish_intents == [["finish_minigame", [41]]], "finish intent carries id and no reward")
	owner.finish_minigame(41)
	controller.sync(owner, false)
	expect(not controller.is_open() and controller.panel == null, "phase transition releases presentation")
	controller.cancel()
	expect(not controller.is_open(), "cancel is idempotent after release")
	print("Source minigame controller checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
