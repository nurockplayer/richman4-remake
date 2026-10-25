extends SceneTree
const SHELL = preload("res://game/ui/game_shell.gd")
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
		# Leaving compact mode must restore every label the compact HUD hides.
		shell.set_view_mode(0)
		shell.cash_label.hide()
		shell.deposit_label.hide()
		shell.wealth_label.hide()
		for item in [shell.cash_caption, shell.deposit_caption, shell.wealth_caption, shell.property_label, shell.stock_label, shell.other_label]:
			item.hide()
		shell.sync_snapshot({"date": {"year": 2024, "month": 3, "day": 3}, "players": [{"name": "玩家", "cash": 100, "deposit": 5}], "current_player": 0})
		shell.set_view_mode(2)
		for item in [shell.cash_label, shell.deposit_label]:
			check(item.visible, "compact HUD shows the cash and deposit labels")
		check(not shell.wealth_label.visible and not shell.property_label.visible, "compact HUD hides the full-HUD detail rows")
		shell.set_view_mode(0)
		check(shell.cash_label.visible and shell.deposit_label.visible and shell.wealth_label.visible, "full HUD restores hidden cash labels after compact mode")
		check(shell.cash_caption.visible and shell.deposit_caption.visible and shell.wealth_caption.visible, "full HUD restores the cash captions after compact mode")
		shell.select_tab("property")
		check(shell.property_label.visible, "full HUD shows the selected property row")
		shell.set_view_mode(2)
		check(not shell.property_label.visible, "compact HUD hides the selected property row")
		shell.set_view_mode(0)
		check(shell.property_label.visible and shell.active_tab == "property", "full HUD restores the selected row after compact mode")
		shell.select_tab("cash")
	shell.queue_free()
	print("Source view modes: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
