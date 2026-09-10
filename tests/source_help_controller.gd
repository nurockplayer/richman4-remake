extends SceneTree

const Controller = preload("res://game/ui/source_help_controller.gd")

class PanelDouble extends Control:
	signal closed
	var model: Dictionary
	var visuals: Variant
	func set_view_model(value: Dictionary) -> void: model = value.duplicate(true)
	func set_visuals(value: Variant) -> void: visuals = value

class LoaderDouble extends RefCounted:
	func for_edition(edition: String) -> Dictionary:
		return {"edition": edition, "available": true}

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var controller := Controller.new()
	controller.panel_factory = func() -> Control: return PanelDouble.new()
	controller.loader_factory = func() -> RefCounted: return LoaderDouble.new()
	var done := [0]
	controller.finished.connect(func() -> void: done[0] += 1)
	root.add_child(controller)
	var owner := RefCounted.new()
	var other := RefCounted.new()
	check(not controller.open(null, "Game", null), "missing owner cannot open help")
	check(not controller.open(owner, "Unknown", null), "unknown edition cannot silently open Game help")
	check(controller.open(owner, "Game", owner), "valid owner opens help")
	var first: Control = controller.help_panel
	check(first.get_parent() == controller and first.model.edition == "Game" and first.visuals == owner, "controller passes exact edition and resolver after attaching presenter")
	check(not controller.open(owner, "MultiverseJourney", other) and controller.help_panel == first, "duplicate opening preserves current browsing session")
	controller.sync(owner)
	check(controller.is_open() and controller.current_edition() == "Game", "same owner refresh keeps help open")
	controller.sync(other)
	check(not controller.is_open() and done[0] == 0, "owner replacement cancels without a stale completion")
	check(controller.open(other, "MultiverseJourney", other), "replacement owner opens its own edition")
	var second: Control = controller.help_panel
	first.closed.emit()
	check(controller.help_panel == second and done[0] == 0, "old closed callback cannot close the replacement session")
	second.closed.emit()
	check(not controller.is_open() and done[0] == 1, "current close returns to host once")
	second.closed.emit()
	check(done[0] == 1, "duplicate close does not notify host twice")
	controller.cancel()
	check(controller.current_edition().is_empty() and done[0] == 1, "idempotent cancellation clears ownership")
	controller.queue_free()
	await process_frame
	print("Source help controller checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
