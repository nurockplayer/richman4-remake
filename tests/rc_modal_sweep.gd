extends SceneTree
## #204 rows 20/24 without a screen: every toolbar modal closes on ESC and on
## right-click, and opening/closing it never changes the simulation.

const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const BaseMap = preload("res://tests/fixtures/original_map_fixture.gd")

# Commands that must open a source modal on the fixture map at await_roll;
# the rest may be disabled or fall back to a legacy popup there.
const REQUIRED_KEYS := ["help", "options", "save", "load", "inspect"]

# keys whose toolbar command opens a modal (main_ui.gd ~479-489 dispatch)
const MODAL_KEYS := ["help", "options", "save", "load", "stocks", "inspect", "cards", "tools", "sale"]

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RC SWEEP FAIL: " + message)


func _set_human_graph_game(ui: Control) -> Object:
	var normalized: Dictionary = Maps.normalize_map(BaseMap.make())
	_expect(bool(normalized.get("ok", false)), "HUD fixture map normalizes")
	var definition: Dictionary = normalized.get("definition", {})
	ui._set_development_path(true)
	var started: bool = ui._new_game(2301, 2, definition)
	_expect(started, "HUD fixture starts through the existing new-game path")
	var game: Object = ui.game_state
	for player_id in range(2):
		game.set_player_ai(player_id, false)
		game.state.players[player_id].position = 0
		game.state.players[player_id].previous_position = -1
	game.state.current_player = 0
	game.state.phase = "await_roll"
	game._set_action_options(0)
	game._sync_state()
	ui._refresh_from_state()
	return game


func _key(ui: Control, keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		ui.get_viewport().push_input(event)
	await process_frame
	await process_frame


func _right_click(ui: Control) -> void:
	# The headless window is 1280x800 while every source surface lives on the
	# 640x480 reference canvas in its top-left corner, so the window centre
	# would miss the modal.  Aim at the canvas centre, which is inside each
	# source window and card.
	var canvas: Control = ui.source_shell.get("reference_canvas")
	var point: Vector2 = ui.get_viewport().get_visible_rect().size * 0.5
	if canvas != null:
		point = canvas.get_global_transform_with_canvas() * (canvas.size * 0.5)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		ui.get_viewport().push_input(event)
	await process_frame
	await process_frame


## A modal that ignored both inputs stays open and would hide every later key
## behind a disabled toolbar; close it through its own surface API so each key
## is still swept from a clean state.  This is a reset, not a close input.
func _reset_modal(ui: Control) -> void:
	if ui._source_help_modal_open():
		ui.source_help_controller.call("cancel")
	if ui._source_options_modal_open():
		ui.source_options_panel.call("close")
	if ui.source_stock_panel != null and ui.source_stock_panel.visible:
		ui.source_stock_panel.call("close_panel")
	if ui.source_save_menu != null and ui.source_save_menu.visible:
		ui.source_save_menu.call("cancel")
	if ui.source_shell != null and ui.source_shell.has_method("is_player_inspector_visible") and ui.source_shell.is_player_inspector_visible():
		ui.source_shell.call("close_player_inspector")
	await process_frame
	# The toolbar gates re-evaluate modal state on refresh; a programmatic reset
	# has to run it so the next key's button is live again.
	ui._refresh_from_state()
	await process_frame
	await process_frame


func _run() -> void:
	if OS.get_environment("RICHMAN4_USER_ROOT").is_empty():
		push_error("RICHMAN4_USER_ROOT must point at a throwaway directory.")
		quit(2)
		return
	var ui: Control = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	if ui.audio_controller != null:
		ui.audio_controller.call("stop")
	var shell: Control = ui.source_shell
	var game: Object = _set_human_graph_game(ui)
	for key in MODAL_KEYS:
		for close_input in ["esc", "right_click"]:
			var button: Button = shell.toolbar_buttons.get(key)
			if button == null or button.disabled:
				_expect(not REQUIRED_KEYS.has(key), "%s toolbar button is enabled at await_roll" % key)
				print("RC sweep: skip %s (no button or disabled at await_roll)" % key)
				break
			var before: String = game.to_json()
			button.pressed.emit()
			# Some surfaces (stocks) build over several frames; a modal that
			# appears late would otherwise linger and eat the next key's input.
			for _frame in range(30):
				await process_frame
				if ui._source_modal_open():
					break
			if not ui._source_modal_open():
				_expect(not REQUIRED_KEYS.has(key), "%s toolbar button opens its modal" % key)
				# The fixture map has no original companies, so stocks falls back
				# to the legacy popup (never reached on a real catalog map); close
				# it so it cannot eat the next key's ESC.
				if ui.stocks_popup != null and ui.stocks_popup.visible:
					ui.stocks_popup.hide()
				print("RC sweep: skip %s (opens no source modal on the fixture map)" % key)
				break
			if close_input == "esc":
				await _key(ui, KEY_ESCAPE)
			else:
				await _right_click(ui)
			_expect(not ui._source_modal_open(), "%s modal closes on %s" % [key, close_input])
			if ui._source_modal_open():
				await _key(ui, KEY_ESCAPE)  # best effort so the next key starts clean
			_expect(game.to_json() == before, "%s open/close via %s leaves the simulation unchanged" % [key, close_input])
			await _reset_modal(ui)
	await _sweep_options_children(ui, shell, game)
	print("RC modal sweep checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


## Options' date and hotkeys children back out to Options on ESC and on a
## right-click; a second ESC then closes Options itself.
func _sweep_options_children(ui: Control, shell: Control, game: Object) -> void:
	for child in ["date", "hotkeys"]:
		for close_input in ["esc", "right_click"]:
			var before: String = game.to_json()
			shell.toolbar_buttons["options"].pressed.emit()
			await process_frame
			await process_frame
			var panel: Control = ui.source_date_panel if child == "date" else ui.source_hotkeys_panel
			if child == "date":
				ui._open_source_date_child()
			else:
				ui._open_source_hotkeys_child()
			await process_frame
			_expect(panel.is_open(), "options %s child opens" % child)
			if close_input == "esc":
				await _key(ui, KEY_ESCAPE)
			else:
				await _right_click(ui)
			_expect(not panel.is_open() and ui._source_options_modal_open(), "options %s child backs out to options on %s" % [child, close_input])
			await _key(ui, KEY_ESCAPE)
			_expect(not ui._source_modal_open(), "options closes on esc after its %s child (%s)" % [child, close_input])
			_expect(game.to_json() == before, "options %s child via %s leaves the simulation unchanged" % [child, close_input])
			await _reset_modal(ui)
