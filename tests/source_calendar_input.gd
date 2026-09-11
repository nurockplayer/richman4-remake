extends SceneTree
const SHELL = preload("res://game/ui/game_shell.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func click(viewport: SubViewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		viewport.push_input(event, true)
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var shell := SHELL.new()
	viewport.add_child(shell)
	await process_frame
	shell.show_game()
	var snapshot := {"date": {"year": 2024, "month": 5, "day": 31}}
	shell.sync_snapshot(snapshot)
	var panel: Control = shell.calendar_panel
	check(panel.season_index() == 1, "May follows source summer boundary")
	for scale_factor in [1, 2]:
		viewport.size = Vector2i(640, 480) * scale_factor
		shell.size = Vector2(viewport.size)
		shell._layout_reference_canvas()
		shell.set_view_mode(0)
		panel.set_style("day")
		await process_frame
		click(viewport, Vector2(504, 300) * scale_factor)
		check(panel.style() == "month", "moon inclusive right edge reaches real calendar at%dx" % scale_factor)
		click(viewport, Vector2(448, 288) * scale_factor)
		check(panel.style() == "day", "sun inclusive top-left reaches real calendar at%dx" % scale_factor)
		click(viewport, Vector2(505, 300) * scale_factor)
		check(panel.style() == "day", "outside moon hitbox leaves style at%dx" % scale_factor)
		shell.set_view_mode(1)
		click(viewport, Vector2(492, 301) * scale_factor)
		check(panel.style() == "day", "hidden calendar cannot capture minimap region at%dx" % scale_factor)
		shell.set_view_mode(2)
		var tab: Button = shell.tab_buttons.property
		var old: String = shell.active_tab
		click(viewport, Vector2(628, 100) * scale_factor)
		check(shell.active_tab == old and not tab.visible, "compact hidden HUD tab cannot capture at%dx" % scale_factor)
		shell.presentation_input_guard = func() -> bool: return false
		click(viewport, Vector2(492, 301) * scale_factor)
		check(panel.style() == "day", "host guard blocks day-month pointer input at%dx" % scale_factor)
		shell.presentation_input_guard = Callable()
		click(viewport, Vector2(492, 301) * scale_factor)
		check(panel.style() == "month", "combined mode calendar remains interactive at%dx" % scale_factor)
	check(shell.snapshot == snapshot, "calendar pointers preserve detached source snapshot")
	viewport.queue_free()
	await process_frame
	print("Source calendar input: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
