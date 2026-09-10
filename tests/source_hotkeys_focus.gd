extends SceneTree

## Minimal native focus precondition probe. Never synthesizes focus or changes
## the foreground app. Injected mouse events are not ordinary physical input.
## Exit 2 means the real OS precondition was unavailable, not product RED/PASS.
var panel: Control
var trace: Array = []

func _initialize() -> void:
	call_deferred("run")

func record(reason: String) -> void:
	var row := {"event":reason,"ms":Time.get_ticks_msec(),"windows":[]}
	for id in DisplayServer.get_window_list():
		row.windows.append({"id":id,"focused":DisplayServer.window_is_focused(id)})
	if is_instance_valid(panel):
		var timer: Timer = panel.get("_timer")
		row.merge({"active":panel.get("_application_active"),"editing":panel.get("_editing_slot"),"blink_on":panel.get("_blink_on"),"pending":panel.pending_blink_visible()})
		if is_instance_valid(timer):
			row.merge({"paused":timer.paused,"time_left":timer.time_left})
	trace.append(row)
	if trace.size()>64: trace.pop_front()

func _notification(what: int) -> void:
	if what in [Node.NOTIFICATION_APPLICATION_FOCUS_IN,Node.NOTIFICATION_APPLICATION_FOCUS_OUT]:
		record("OS_IN" if what==Node.NOTIFICATION_APPLICATION_FOCUS_IN else "OS_OUT")

func focused() -> bool:
	for id in DisplayServer.get_window_list():
		if DisplayServer.window_is_focused(id): return true
	return false

func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("HOTKEY_NATIVE_FOCUS PRECONDITION_UNMET: native display required")
		quit(2)
		return
	panel = load("res://game/ui/source_hotkeys_panel.gd").new()
	root.add_child(panel)
	panel.set_view_model({"edition":"Game","bindings":load("res://game/platform/system_hotkeys.gd").new().defaults()})
	panel.get("_timer").timeout.connect(func() -> void: record("TIMER_TIMEOUT"))
	var deadline := Time.get_ticks_msec()+3000
	while not focused() and Time.get_ticks_msec()<deadline:
		await create_timer(0.01).timeout
	if not focused():
		record("STARTUP_FOCUS_UNAVAILABLE")
		await finish("PRECONDITION_UNMET: no actual OS focus",2)
		return
	record("REAL_FOCUS_ESTABLISHED")
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = Vector2(288,233)
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		await process_frame
	var seen_on := false
	var seen_off := false
	deadline = Time.get_ticks_msec()+800
	while Time.get_ticks_msec()<deadline:
		if not focused():
			record("REAL_FOCUS_LOST")
			await finish("PRECONDITION_UNMET: focus left during observation",2)
			return
		seen_on = seen_on or panel.pending_blink_visible()
		seen_off = seen_off or not panel.pending_blink_visible()
		await create_timer(0.01).timeout
	record("OBSERVATION_END")
	var passed: bool = panel.get("_editing_slot")==8 and bool(panel.get("_application_active")) and seen_on and seen_off
	await finish("PASS: real focused native timer showed both phases" if passed else "FAIL: focused native edit did not show both phases",0 if passed else 1)

func finish(result: String, code: int) -> void:
	print("HOTKEY_FOCUS_AUDIT ",JSON.stringify(trace))
	print("HOTKEY_NATIVE_FOCUS ",result)
	panel.queue_free()
	await process_frame
	quit(code)
