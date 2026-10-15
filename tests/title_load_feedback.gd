extends SceneTree
## Supporting regression for a screenshot-observed title LOAD no-feedback bug.
const MainScene = preload("res://game/main.tscn")
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("_run")
func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	ui.set_process(false)
	ui.content_error_dialog.hide()
	ui.source_shell.show_title()
	var previous_game = ui.game_state
	var previous_snapshot := JSON.stringify(ui.state)
	ui._load_game_from_path("user://nonexistent-title-load-regression.json")
	_expect(ui.content_error_dialog.visible, "Missing title save must have visible feedback")
	_expect(ui.content_error_dialog.title == "無法讀取存檔", "Load error has a relevant title")
	_expect(ui.content_error_dialog.dialog_text.contains("找不到存檔"), "Missing-save explanation is visible")
	_expect(ui.source_shell.is_title_visible(), "Failure preserves title")
	_expect(ui.game_state == previous_game and JSON.stringify(ui.state) == previous_snapshot, "Failure preserves current game")
	ui.content_error_dialog.hide()
	var bad_path := "user://invalid-title-load-regression.json"
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_string("[]")
	bad_file.close()
	ui._load_game_from_path(bad_path)
	_expect(ui.content_error_dialog.visible, "Malformed title save has visible feedback")
	_expect(ui.content_error_dialog.dialog_text.contains("格式無效"), "Malformed-save explanation is visible")
	_expect(FileAccess.get_file_as_string(bad_path) == "[]", "Failed load does not rewrite the file")
	_expect(ui.game_state == previous_game and JSON.stringify(ui.state) == previous_snapshot, "Malformed save preserves current game")
	ui.content_error_dialog.hide()
	ui._show_content_error("content check")
	_expect(ui.content_error_dialog.title == "無法開始對局", "Content error resets its own title")
	ui.content_error_dialog.hide()
	ui.source_shell.show_game()
	ui._load_game_from_path("user://nonexistent-title-load-regression.json")
	_expect(not ui.content_error_dialog.visible, "Board log behavior is unchanged outside title")
	DirAccess.remove_absolute(bad_path)
	ui.queue_free()
	await process_frame
	print("Title load feedback: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
