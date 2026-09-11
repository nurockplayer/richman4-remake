extends "res://tests/source_options_ui.gd"
class ViewStore extends RefCounted:
	var fail := false
	var corrupt := false
	var writes := 0
	var settings: Dictionary = {"speed": 1, "animation": true, "music_level": 4, "sound_level": 4, "autosave": true, "view": 1}
	func read_settings(_path: String) -> Dictionary:
		return {"ok": false, "error": "invalid_json"} if corrupt else {"ok": true, "settings": settings.duplicate(true)}
	func write_settings(_path: String, value: Dictionary) -> Dictionary:
		writes += 1
		if fail: return {"ok": false, "error": "write_failed"}
		settings = value.duplicate(true)
		return {"ok": true}
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 960)
	viewport.handle_input_locally = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var ui := OptionsTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	var shell: Control = ui.source_shell
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	check(shell.view_mode == 1, "successful missing-file defaults apply source view1")
	ui._unhandled_input(key)
	check(shell.view_mode == 1, "title rejects view hotkey")
	shell.show_game()
	ui._refresh_from_state()
	var game: Object = ui.game_state
	var before: String = game.to_json()
	var store := ViewStore.new()
	var controller: Control = ui.source_options_controller
	controller.settings_store = store
	shell.roll_button.grab_focus()
	viewport.push_input(key, true)
	check(shell.view_mode == 2 and store.writes == 0, "TAB cycles once without disk write")
	key.echo = true
	ui._unhandled_input(key)
	check(shell.view_mode == 2, "TAB echo does not cycle")
	key.echo = false
	ui._on_source_option_requested()
	check(controller.settings().view == 2, "reopen options reflects runtime TAB choice")
	ui._unhandled_input(key)
	check(shell.view_mode == 2, "options modal rejects view hotkey")
	controller.cancel()
	check(shell.view_mode == 2, "Cancel preserves runtime view")
	ui._on_source_option_requested()
	var draft: Dictionary = controller.settings()
	draft.view = 0
	controller.options_panel.restore_draft(draft)
	store.fail = true
	controller.options_panel._accept()
	check(controller.is_open() and shell.view_mode == 2, "failed persistence cannot change runtime view")
	controller.cancel()
	store.fail = false
	ui._on_source_option_requested()
	check(controller.settings().view == 2, "reopen after failed write preserves runtime view")
	controller.options_panel.restore_draft(draft)
	controller.options_panel._accept()
	check(shell.view_mode == 0 and not controller.is_open(), "successful persist applies view0")
	store.corrupt = true
	ui._on_source_option_requested()
	check(not controller.persistence_error().is_empty() and controller.settings().is_empty(), "runtime override never hides read error")
	controller.cancel()
	check(shell.view_mode == 0, "read-error Cancel preserves runtime")
	ui._presentation_busy = true
	ui._unhandled_input(key)
	check(shell.view_mode == 0, "movement busy rejects view hotkey")
	ui._presentation_busy = false
	ui.state["pending_finance"] = {"kind": "test_pending"}
	ui._unhandled_input(key)
	check(shell.view_mode == 0, "pending finance blocks display input before modal construction")
	ui.state.erase("pending_finance")
	ui._ai_pending = true
	ui._unhandled_input(key)
	check(shell.view_mode == 0, "queued actor transition blocks display input")
	ui._ai_pending = false
	ui._on_source_ai_requested()
	ui._unhandled_input(key)
	check(shell.view_mode == 0, "trustee modal rejects view hotkey")
	ui.source_trustee_controller.cancel()
	ui._on_source_map_requested()
	var full: bool = shell.full_map_visible
	ui._unhandled_input(key)
	check(shell.view_mode == 1 and shell.full_map_visible == full, "view cycle preserves separate fullmap")
	ui._on_source_map_requested()
	check(game.to_json() == before, "all display options preserve complete core save and RNG")
	viewport.queue_free()
	await settle()
	print("Source view MainUI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
