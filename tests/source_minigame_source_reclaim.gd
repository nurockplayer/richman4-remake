extends SceneTree
const Model = preload("res://game/core/source_minigame_model.gd")
const Controller = preload("res://game/ui/source_minigame_controller.gd")
var checks := 0
var failures := 0
class Owner extends RefCounted:
	var ticks := 0
	func minigame_snapshot() -> Dictionary:
		return {"kind":"balloon","encounter_id":1,"model":{"tick_ms":100},"finished":false}
	func minigame_tick(_id: int) -> bool:
		ticks += 1
		return true
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1;push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var catcher := Model.new().configure("catching",71)
	check(catcher.state.character_position.y==380,"source catching actor baseline is380")
	var appeared := false
	for i in range(200):
		catcher.tick()
		appeared = appeared or not catcher.state.items.is_empty()
	check(appeared,"ordinary catching naturally spawns items without injected records")
	var drain := Model.new().configure("catching",71,{"items":[{"id":0,"x":100,"y":100,"speed":0}]})
	drain.state.tick=359
	drain.tick()
	check(not drain.finished(),"18second deadline drains existing thrown items")
	var mask := PackedByteArray()
	mask.resize(640*480)
	var penguin := Model.new().configure("penguin",71,{"penguin_mask":mask})
	penguin.pointer(Vector2(80+5*48,81+4*24),true)
	check(penguin.state.movement_state=="idle","zero source mask byte is invalid rather than nearest-cell fallback")
	var owner := Owner.new()
	var controller := Controller.new()
	root.add_child(controller)
	controller.set_process(false)
	controller.sync(owner,false)
	controller.panel.set_process(false)
	controller.panel.tick(2.28)
	controller._process(0.35)
	check(owner.ticks==3,"source accumulator retains three ticks across a350ms render interval")
	controller.cancel()
	controller.queue_free()
	print("Minigame source reclaim checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
