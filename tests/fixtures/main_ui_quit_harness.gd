extends "res://game/ui/main_ui.gd"

## Standalone MainUI host for settlement tests: no audio device work, and the
## ordinary process-exit seam is counted instead of terminating the test run.

var quit_requests := 0


func _setup_audio() -> void:
	pass


func _request_quit() -> void:
	quit_requests += 1
