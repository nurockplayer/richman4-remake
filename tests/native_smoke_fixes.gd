extends SceneTree

## Focused acceptance checks for the 2026-10-26 JST native RC smoke defects:
## the art-free bank keypad overlap, the ATM status line, the setup frame's
## stray legacy rectangle and preview overflow, and the jail action label.
##
## Every check runs against the same fallback path the smoke used (no private
## art loaded), so a missing asset cache cannot hide a layout regression.

const BankPanel = preload("res://game/ui/source_bank_panel.gd")
const AmountPad = preload("res://game/ui/source_amount_pad.gd")
const GameShell = preload("res://game/ui/game_shell.gd")
const REFERENCE_SIZE := Vector2(640.0, 480.0)
const ATM_SIZE := Vector2(320.0, 338.0)
const PAD_SIZE := Vector2(128.0, 192.0)
const SOURCE_MAP_RECT := Rect2(4.0, 173.0, 440.0, 307.0)

class SetupTestUI extends "res://game/ui/main_ui.gd":
	func _setup_audio() -> void: pass
	func _load_map_catalog(path: String = "", _allow_development_fallback: bool = false) -> void:
		var fixture = preload("res://tests/fixtures/company_fixture.gd")
		_map_catalog = [fixture.definition()]
		_map_catalog_complete = _catalog_has_complete_original_content(_map_catalog)
		_map_catalog_ok = _map_catalog_complete
		_selected_map_definition = _map_catalog[0].duplicate(true)
		_update_map_selector()

var checks := 0
var failures := 0
var _requests: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _panel_rect(control: Control) -> Rect2:
	if control == null:
		return Rect2()
	return Rect2(control.get_global_transform_with_canvas() * Vector2.ZERO, control.size * control.get_global_transform_with_canvas().get_scale())


## Every keypad hit area must keep the source rectangle, so no two buttons may
## share pixels and every button must stay inside its own panel.
func _check_keypad(panel: Control, names: Array, inside: Rect2, label: String) -> void:
	var rects: Array = []
	for node_name in names:
		var button := panel.find_child(str(node_name), true, false) as Button
		_expect(button != null, "%s keeps %s" % [label, node_name])
		if button == null:
			continue
		var rect := Rect2(button.position, button.size)
		rects.append([str(node_name), rect])
		_expect(inside.encloses(rect), "%s %s stays inside the panel frame (%s in %s)" % [label, node_name, rect, inside])
	for first in range(rects.size()):
		for second in range(first + 1, rects.size()):
			var a: Rect2 = rects[first][1]
			var b: Rect2 = rects[second][1]
			_expect(not a.intersects(b), "%s keypad buttons %s and %s do not overlap (%s vs %s)" % [label, rects[first][0], rects[second][0], a, b])


func _atm_model(cash_value: int, deposit_value: int) -> Dictionary:
	return {
		"entry_mode": "atm",
		"edition": "Game",
		"cash": cash_value,
		"deposit": deposit_value,
		"action_limits": {"withdraw": cash_value, "deposit": deposit_value},
		"allowed_actions": ["withdraw", "deposit"],
	}


func _capture(action: String, amount: int) -> void:
	_requests.append([action, amount])


func _run() -> void:
	await _test_atm_keypad_and_status()
	await _test_amount_pad_keypad()
	await _test_setup_frame()
	await _test_jail_action_label()
	print("Native smoke fix checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func _test_atm_keypad_and_status() -> void:
	var panel: Control = BankPanel.new()
	root.add_child(panel)
	await process_frame
	panel.connect("action_requested", Callable(self, "_capture"))
	panel.call("set_view_model", _atm_model(100000, 5000))
	await process_frame
	panel.size = ATM_SIZE
	await process_frame
	_check_keypad(panel, [
		"ATMWithdraw", "ATMDeposit", "ATMExit",
		"ATMDigit7", "ATMDigit8", "ATMDigit9",
		"ATMDigit4", "ATMDigit5", "ATMDigit6",
		"ATMDigit1", "ATMDigit2", "ATMDigit3",
		"ATMClear", "ATMDigit0", "ATMBackspace", "ATMMax", "ATMEnter",
	], Rect2(Vector2.ZERO, ATM_SIZE), "ATM fallback")

	var feedback := panel.find_child("ATMFeedback", true, false) as Label
	_expect(feedback != null and feedback.text == "請先選擇提款或存款", "ATM opens with the choose prompt")
	_expect(panel.call("select_action", "withdraw"), "ATM accepts a withdraw choice")
	_expect(feedback != null and feedback.text == "提款：選擇金額後按 ENTER", "ATM status follows the withdraw choice")
	panel.call("set_amount_text", "5000")
	_expect(panel.call("confirm_amount"), "ATM confirms the entered amount")
	_expect(_requests.size() == 1 and _requests[0] == ["withdraw", 5000], "ATM reports the settled withdrawal once")
	_expect(feedback != null and not feedback.text.begins_with("已提款"), "ATM does not claim a withdrawal before the core accepts it")
	panel.call("settle_status")
	_expect(feedback != null and feedback.text == "已提款 $5000", "ATM status reads back the accepted withdrawal")

	# The host rebuilds the panel from the post-action snapshot and restores the
	# previous choice; the settled amount must survive that rebuild.
	panel.call("set_view_model", _atm_model(95000, 5000))
	panel.call("select_action", "withdraw", true)
	panel.call("set_amount_text", "5000")
	await process_frame
	feedback = panel.find_child("ATMFeedback", true, false) as Label
	_expect(feedback != null and feedback.text == "已提款 $5000", "settled withdrawal survives the host rebuild")

	# A rejected transaction must not leave the success line behind.
	panel.call("select_action", "withdraw")
	panel.call("set_amount_text", "1000")
	_expect(panel.call("confirm_amount"), "ATM confirms a second withdrawal attempt")
	panel.call("reject_status", "銀行操作未完成。")
	_expect(feedback != null and feedback.text == "銀行操作未完成。", "a rejected withdrawal shows the failure instead of a settled amount")
	panel.call("settle_status")
	_expect(feedback != null and feedback.text != "已提款 $1000", "a rejected withdrawal can never be read back as settled")

	# A new encounter starts clean.
	panel.call("reset_status")
	panel.call("set_view_model", _atm_model(95000, 5000))
	await process_frame
	feedback = panel.find_child("ATMFeedback", true, false) as Label
	_expect(feedback != null and feedback.text == "請先選擇提款或存款", "a new bank encounter resets the status line")
	panel.queue_free()
	await process_frame


func _test_amount_pad_keypad() -> void:
	var pad: Control = AmountPad.new()
	root.add_child(pad)
	await process_frame
	pad.call("configure", "take_loan", 100000)
	await process_frame
	pad.size = PAD_SIZE
	await process_frame
	_check_keypad(pad, [
		"AmountMax", "AmountEnter",
		"AmountClear", "AmountDigit0", "AmountBackspace",
		"AmountDigit7", "AmountDigit8", "AmountDigit9",
		"AmountDigit4", "AmountDigit5", "AmountDigit6",
		"AmountDigit1", "AmountDigit2", "AmountDigit3",
	], Rect2(Vector2.ZERO, PAD_SIZE), "Panel21 fallback")
	pad.queue_free()
	await process_frame


func _test_setup_frame() -> void:
	var ui := SetupTestUI.new()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var shell: Control = ui.source_shell
	_expect(shell != null, "source shell exists for the setup frame checks")
	if shell == null:
		return
	var glow := ui.find_child("LegacyBackdropGlow", false, false) as CanvasItem
	_expect(glow != null and not glow.is_visible_in_tree(), "the legacy backdrop glow is hidden behind the title screen")
	ui._on_source_start_requested()
	await process_frame
	await process_frame
	_expect(glow != null and not glow.is_visible_in_tree(), "the legacy backdrop glow stays hidden behind the setup screen")
	var setup := shell.get_node_or_null("SourceSetupPanel") as Control
	_expect(setup != null and setup.is_visible_in_tree(), "START opens the setup surface")
	if setup == null:
		return
	_expect(setup.size == REFERENCE_SIZE, "the setup surface is the 640x480 reference frame")
	_expect(_panel_rect(setup) == _panel_rect(shell.get("reference_canvas") as Control), "the setup surface lines up with the scaled reference canvas")
	var clip := setup.find_child("SourceMapPreviewClip", true, false) as Control
	_expect(clip != null and clip.clip_contents, "the map preview is clipped to its frame")
	if clip != null:
		_expect(Rect2(clip.position, clip.size) == SOURCE_MAP_RECT, "the preview clip keeps the source map rectangle")
		_expect(Rect2(Vector2.ZERO, REFERENCE_SIZE).encloses(Rect2(clip.position, clip.size)), "the preview clip stays inside the 640x480 frame")
	var preview := setup.find_child("SourceMapPreview", true, false) as TextureRect
	_expect(preview != null and preview.get_parent() == clip, "the map preview draws inside the clipping frame")
	if preview != null:
		_expect(Rect2(preview.position, preview.size) == Rect2(Vector2.ZERO, SOURCE_MAP_RECT.size), "the map preview covers exactly the clipped frame")
		_expect(Rect2(Vector2.ZERO, REFERENCE_SIZE).encloses(Rect2(clip.position + preview.position, preview.size)), "the map preview cannot extend past the 640x480 frame")
	ui.queue_free()
	await process_frame


func _test_jail_action_label() -> void:
	var shell := GameShell.new()
	shell.size = REFERENCE_SIZE
	root.add_child(shell)
	await process_frame
	shell.call("sync_action_state", "服刑", false, "購買地產", true, "升級", true, true, "服刑 · 剩餘 3 回合，按服刑推進回合", [], "await_roll", [])
	_expect(shell.roll_button.visible and shell.roll_button.text == "服刑", "the jail turn labels the action button 服刑")
	shell.call("sync_action_state", "休養", false, "購買地產", true, "升級", true, true, "住院休養 · 剩餘 2 天，按休養推進回合", [], "await_roll", [])
	_expect(shell.roll_button.text == "休養", "the hospital turn labels the action button 休養")
	shell.call("sync_action_state", "出獄擲骰", false, "購買地產", true, "升級", true, true, "按出獄擲骰回到道路並開始行動", [], "await_roll", [])
	_expect(shell.roll_button.text == "出獄擲骰", "release labels the action button 出獄擲骰")
	shell.call("sync_action_state", "擲骰", false, "購買地產", true, "升級", true, true, "輪到你了，請擲骰", [], "await_roll", [])
	_expect(shell.roll_button.text == "GO", "an ordinary turn keeps the source GO label")
	shell.queue_free()
	await process_frame
