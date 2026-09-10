extends SceneTree

const MainScene = preload("res://game/main.tscn")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var ui := MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	if ui.audio_controller != null:
		ui.audio_controller.call("stop")
	var shell: Control = ui.source_shell
	_expect(shell != null, "source shell exists for ordinary START")
	if shell == null:
		quit(1)
		return
	_expect(shell.has_method("show_setup"), "source shell exposes the setup surface")
	_expect(shell.has_method("is_setup_visible"), "source shell exposes setup visibility")
	ui._on_source_start_requested()
	await process_frame
	var setup: Node = shell.get_node_or_null("SourceSetupPanel")
	_expect(setup != null, "ordinary START creates the source setup panel")
	var setup_open := shell.has_method("is_setup_visible") and bool(shell.call("is_setup_visible"))
	_expect(setup_open, "ordinary START opens the source setup panel")
	if setup != null:
		_expect(setup.has_method("set_catalog"), "source setup accepts the validated map catalog")
		_expect(setup.has_method("collect_options"), "source setup exposes validated choices")
		_expect(setup.has_method("cancel"), "source setup has an explicit cancel path")
		_expect(setup.find_child("CharacterPortrait_0", true, false) != null, "source setup shows the first character portrait")
		_expect(setup.find_child("CharacterPortrait_11", true, false) != null, "source setup shows all twelve character portraits")
		_expect(setup.find_child("PlayerType_0", true, false) != null, "source setup exposes human or AI for player one")
		_expect(setup.find_child("PlayerType_3", true, false) != null, "source setup exposes human or AI for player four")
		_expect(setup.find_child("MapChoice_0", true, false) != null, "source setup exposes the first source map choice")
		_expect(setup.find_child("MapChoice_3", true, false) != null, "source setup exposes the fourth source map choice")
		_expect(setup.find_child("InitialFund", true, false) != null, "source setup keeps the initial fund selector")
		_expect(setup.find_child("DayLimit", true, false) != null, "source setup keeps the game time selector")
		_expect(setup.find_child("WealthTarget", true, false) != null, "source setup keeps the victory target selector")
		_expect(setup.find_child("OK", true, false) != null and setup.find_child("EXIT", true, false) != null, "source setup has OK and EXIT controls")
	ui.queue_free()
	await create_timer(0.1).timeout
	print("Source setup UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
