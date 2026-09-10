extends Control

signal finished

var help_panel: Control
var panel_factory: Callable
var loader_factory: Callable
var _owner: Object
var _edition := ""
var _generation := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func open(owner: Object, edition: String, visuals: Variant) -> bool:
	if owner == null or is_open() or edition not in ["Game", "MultiverseJourney"]:
		return false
	var panel: Control = panel_factory.call() if panel_factory.is_valid() else load("res://game/ui/source_help_panel.gd").new()
	var loader: RefCounted = loader_factory.call() if loader_factory.is_valid() else load("res://game/platform/original_help.gd").new()
	if panel == null or loader == null:
		return false
	_generation += 1
	var generation := _generation
	_owner = owner
	_edition = edition
	help_panel = panel
	panel.name = "SourceHelpPanel"
	panel.closed.connect(func() -> void:
		if generation == _generation and help_panel == panel:
			cancel()
			finished.emit())
	add_child(panel)
	panel.set_visuals(visuals)
	# Empty data intentionally reaches the presenter's explicit unavailable view.
	# Missing content must still leave a clear path back to the current board.
	panel.set_view_model(loader.for_edition(edition))
	return true

func is_open() -> bool:
	return help_panel != null and is_instance_valid(help_panel)

func current_edition() -> String:
	return _edition

func sync(owner: Object) -> void:
	if is_open() and owner != _owner:
		cancel()

func cancel() -> void:
	_generation += 1
	_owner = null
	_edition = ""
	if help_panel != null and is_instance_valid(help_panel):
		remove_child(help_panel)
		help_panel.queue_free()
	help_panel = null
