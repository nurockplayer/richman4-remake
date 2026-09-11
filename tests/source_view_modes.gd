extends SceneTree
const SHELL = preload("res://game/ui/game_shell.gd")
const PREFS = preload("res://game/ui/source_preferences.gd")
const KEYS = preload("res://game/platform/system_hotkeys.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var shell := SHELL.new()
	root.add_child(shell)
	await process_frame
	shell.show_game()
	check(shell.has_method("set_view_mode"), "normal shell consumes source three-view preference")
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	check(PREFS.new().hotkey_command(key, KEYS.new().defaults()) == "view", "source slot7 TAB dispatches view cycle")
	if shell.has_method("set_view_mode"):
		for mode in range(3):
			shell.set_view_mode(mode)
			check(shell.hud_panel.size == Vector2(200, 80 if mode == 2 else 280), "HUD geometry mode%d" % mode)
			check(shell.calendar_panel.visible == (mode != 1), "calendar visibility mode%d" % mode)
			check(shell.minimap.visible == (mode != 0), "minimap visibility mode%d" % mode)
			check(shell.minimap.position == Vector2(440, 80 if mode == 2 else 280), "minimap geometry mode%d" % mode)
			for tab in shell.tab_buttons.values():
				check(tab.visible == (mode != 2), "hidden compact tab cannot capture pointer")
			var old: int = shell.view_mode
			shell.cycle_view_mode()
			check(shell.view_mode == (old + 1) % 3, "view cycles three source states")
	shell.queue_free()
	print("Source view modes: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
