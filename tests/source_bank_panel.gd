extends SceneTree

## Focused, hermetic acceptance checks for the source-shaped bank presenter.
##
## The first tests-only commit intentionally loads the component dynamically.
## A missing implementation is a qualified RED; a missing script must not turn
## the result into a parser error.  This suite never instantiates GameState or
## calls a domain action.

var checks := 0
var failures := 0
var _requests: Array = []
var _closed_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source_path := "res://game/ui/source_bank_panel.gd"
	if not FileAccess.file_exists(source_path):
		failures += 1
		checks += 1
		print("FAIL: Source bank panel implementation is absent (qualified RED)")
		print("Source bank panel RED: implementation absent; checks: %d, failures: %d" % [checks, failures])
		quit(1)
		return
	var source_script: Variant = load(source_path)
	if source_script == null:
		failures += 1
		checks += 1
		print("FAIL: Source bank panel script could not load")
		quit(1)
		return
	var panel: Node = source_script.new()
	root.add_child(panel)
	panel.connect("action_requested", Callable(self, "_on_action_requested"))
	panel.connect("closed", Callable(self, "_on_closed"))
	await process_frame

	_check_public_api(panel)
	_test_model_isolation(panel)
	_test_invalid_models_and_source_bounds(panel)
	_test_atm_selection_and_bounds(panel)
	_test_visual_accessor(panel)
	await _test_keypad_input_dispatch(panel)
	_test_loan_front_and_calculator(panel)
	await _test_bank_scene_transition_and_action_gates(panel)
	await _test_rear_special_gate(panel)
	await _test_hidden_input_guard(panel)
	await _test_visual_layering_and_source_chunks(panel)
	await _test_amount_pad_source_layering()
	_test_cancel_paths(panel)

	panel.queue_free()
	await process_frame
	print("Source bank panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _check_public_api(panel: Node) -> void:
	for method in ["set_view_model", "set_visuals", "select_action", "set_amount_text", "confirm_amount", "cancel_amount", "current_action", "current_amount"]:
		expect(panel.has_method(method), "bank presenter exposes " + method)
	expect(panel.has_signal("action_requested"), "bank presenter exposes action_requested")
	expect(panel.has_signal("closed"), "bank presenter exposes closed")


func _base_model() -> Dictionary:
	return {
		"edition": "Game",
		"entry_mode": "atm",
		"allowed_actions": ["withdraw", "deposit", "exit"],
		"action_limits": {"withdraw": 250, "deposit": 600},
		"cash": 1250,
		"deposit": 900,
		"loan": 400,
		"due_date": 37,
		"special_principal": 80,
		"other_deposits": 1000,
		"can_special": false,
	}


func _test_model_isolation(panel: Node) -> void:
	var model := _base_model()
	var before: Dictionary = model.duplicate(true)
	panel.call("set_view_model", model)
	expect(model == before, "set_view_model does not mutate the host dictionary")
	panel.call("select_action", "withdraw")
	panel.call("set_amount_text", "125")
	panel.call("confirm_amount")
	expect(model == before, "selection and confirmation do not mutate host data")
	expect(_requests.size() == 1 and _requests[0] == ["withdraw", 125], "explicit confirmation emits the requested withdrawal")
	_requests.clear()


func _test_invalid_models_and_source_bounds(panel: Node) -> void:
	var invalid_mode := _base_model()
	invalid_mode.entry_mode = "unsupported"
	panel.call("set_view_model", invalid_mode)
	var invalid_message_visible := false
	for child in panel.get_children():
		var label := child as Label
		if label != null and label.text.contains("資料格式無法顯示"):
			invalid_message_visible = true
	expect(invalid_message_visible, "invalid model uses a visible error fallback")
	var invalid_button: BaseButton = panel.find_child("ATMWithdraw", true, false) as BaseButton
	expect(invalid_button == null, "invalid mode does not expose active ATM controls")
	expect(not bool(panel.call("select_action", "withdraw")), "invalid model rejects action selection")

	var invalid_edition := _base_model()
	invalid_edition.edition = 42
	panel.call("set_view_model", invalid_edition)
	invalid_button = panel.find_child("ATMWithdraw", true, false) as BaseButton
	expect(invalid_button == null, "invalid edition does not expose active controls")
	var legacy_scene_edition := _base_model()
	legacy_scene_edition.edition = "rear"
	panel.call("set_view_model", legacy_scene_edition)
	invalid_button = panel.find_child("ATMWithdraw", true, false) as BaseButton
	expect(invalid_button == null, "legacy front/rear scene labels are not accepted as source editions")
	var mj_model := _base_model()
	mj_model.edition = "MJ"
	panel.call("set_view_model", mj_model)
	var mj_button: BaseButton = panel.find_child("ATMWithdraw", true, false) as BaseButton
	expect(mj_button != null, "MJ source edition keeps the ATM entry available")

	var atm_model := _base_model()
	panel.call("set_view_model", atm_model)
	expect(panel.custom_minimum_size == Vector2(320, 338), "ATM keeps the source logical panel size")
	var bar: HSlider = panel.find_child("ATMAmountBar", true, false) as HSlider
	expect(bar != null and bar.position == Vector2(53, 137) and bar.size == Vector2(215, 29), "ATM amount bar keeps the source rectangle")
	if bar != null:
		panel.call("select_action", "withdraw")
		expect(is_equal_approx(bar.max_value, 250.0), "ATM amount bar uses the host withdrawal limit")


func _test_visual_accessor(panel: Node) -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color("#7bc6a3"))
	var texture := ImageTexture.create_from_image(image)
	var visuals := {"Game.Panel24": texture}
	panel.call("set_view_model", _base_model())
	panel.call("set_visuals", visuals)
	var source_visual: TextureRect = panel.find_child("SourceVisual", true, false) as TextureRect
	expect(source_visual != null and source_visual.texture == texture, "host visual accessor supplies the source texture")
	expect(visuals.has("Game.Panel24") and visuals["Game.Panel24"] == texture, "set_visuals does not mutate the host accessor")
	var amount_bar: HSlider = panel.find_child("ATMAmountBar", true, false) as HSlider
	if amount_bar != null:
		expect(amount_bar.get_theme_stylebox("slider") is StyleBoxEmpty, "source ATM amount control is transparent over the source art")
	var mj_model := _base_model()
	mj_model.edition = "MJ"
	panel.call("set_view_model", mj_model)
	panel.call("set_visuals", {"MJ.Panel24": texture})
	source_visual = panel.find_child("SourceVisual", true, false) as TextureRect
	expect(source_visual != null and source_visual.texture == texture, "MJ visual aliases resolve the canonical source edition")


func _test_atm_selection_and_bounds(panel: Node) -> void:
	panel.call("set_view_model", _base_model())
	var withdraw_button: BaseButton = panel.find_child("ATMWithdraw", true, false) as BaseButton
	var deposit_button: BaseButton = panel.find_child("ATMDeposit", true, false) as BaseButton
	var maximum_button: BaseButton = panel.find_child("ATMMax", true, false) as BaseButton
	var enter_button: BaseButton = panel.find_child("ATMEnter", true, false) as BaseButton
	expect(withdraw_button != null and deposit_button != null, "ATM keeps source left/right direction controls")
	expect(maximum_button != null and enter_button != null, "ATM exposes source MAX and ENTER controls")
	if withdraw_button == null or deposit_button == null or maximum_button == null or enter_button == null:
		return

	_requests.clear()
	withdraw_button.pressed.emit()
	expect(str(panel.call("current_action")) == "withdraw", "ATM withdraw selects without emitting")
	expect(_requests.is_empty(), "selection alone never emits a domain action")
	panel.call("set_amount_text", "0")
	panel.call("confirm_amount")
	expect(_requests.is_empty(), "zero amount is rejected without an action")
	panel.call("set_amount_text", "251")
	panel.call("confirm_amount")
	expect(_requests.is_empty(), "over-limit amount is rejected without an action")
	panel.call("set_amount_text", "-1")
	panel.call("confirm_amount")
	expect(_requests.is_empty(), "negative amount is rejected without an action")
	panel.call("set_amount_text", "bad")
	panel.call("confirm_amount")
	expect(_requests.is_empty(), "non-numeric amount is rejected without an action")
	maximum_button.pressed.emit()
	expect(int(panel.call("current_amount")) == 250, "MAX fills the exact host withdrawal limit")
	enter_button.pressed.emit()
	expect(_requests.size() == 1 and _requests[0] == ["withdraw", 250], "exact MAX confirms through ENTER")
	_requests.clear()

	var gated_model := _base_model()
	gated_model.allowed_actions = ["withdraw", "exit"]
	panel.call("set_view_model", gated_model)
	deposit_button = panel.find_child("ATMDeposit", true, false) as BaseButton
	expect(deposit_button != null and deposit_button.disabled, "denied ATM action is visibly disabled")
	if deposit_button != null:
		deposit_button.pressed.emit()
	panel.call("set_amount_text", "1")
	panel.call("confirm_amount")
	expect(_requests.is_empty(), "denied ATM action cannot emit")


func _test_keypad_input_dispatch(panel: Node) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 338)
	viewport.disable_3d = true
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var input_panel: Node = panel.get_script().new()
	viewport.add_child(input_panel)
	input_panel.call("set_view_model", _base_model())
	input_panel.connect("action_requested", Callable(self, "_on_action_requested"))
	await process_frame
	input_panel.call("select_action", "withdraw")
	input_panel.call("set_amount_text", "")
	_requests.clear()
	viewport.push_input(_key_event(KEY_1, "1"))
	viewport.push_input(_key_event(KEY_2, "2"))
	viewport.push_input(_key_event(KEY_ENTER, "\n"))
	expect(_requests.size() == 1 and _requests[0] == ["withdraw", 12], "SubViewport key events dispatch through the amount pad")
	_requests.clear()
	input_panel.queue_free()
	viewport.queue_free()
	await process_frame


func _test_loan_front_and_calculator(panel: Node) -> void:
	var model := _base_model()
	model.entry_mode = "loan"
	model.edition = "Game"
	model.allowed_actions = ["take_loan", "repay_loan", "exit"]
	model.action_limits = {"take_loan": 1200, "repay_loan": 400}
	panel.call("set_view_model", model)
	var borrow_button: BaseButton = panel.find_child("LoanBorrow", true, false) as BaseButton
	var repay_button: BaseButton = panel.find_child("LoanRepay", true, false) as BaseButton
	var exit_button: BaseButton = panel.find_child("BankExit", true, false) as BaseButton
	expect(borrow_button != null and repay_button != null and exit_button != null, "front bank exposes source loan controls and EXIT")
	if borrow_button == null or repay_button == null:
		return
	_requests.clear()
	borrow_button.pressed.emit()
	expect(str(panel.call("current_action")) == "take_loan", "loan borrow selects a source action")
	expect(panel.find_child("SourceAmountPad", true, false) != null, "loan opens the separate calculator pad")
	panel.call("set_amount_text", "1200")
	panel.call("confirm_amount")
	expect(_requests.size() == 1 and _requests[0] == ["take_loan", 1200], "loan confirmation emits exact host amount")
	_requests.clear()
	repay_button.pressed.emit()
	panel.call("set_amount_text", "400")
	panel.call("confirm_amount")
	expect(_requests.size() == 1 and _requests[0] == ["repay_loan", 400], "repayment confirmation emits exact host amount")
	_requests.clear()


func _test_bank_scene_transition_and_action_gates(panel: Node) -> void:
	var model := _base_model()
	model.entry_mode = "loan"
	model.edition = "Game"
	model.allowed_actions = ["take_loan", "repay_loan", "take_special_finance", "repay_special_finance", "exit"]
	model.action_limits = {"take_loan": 1200, "repay_loan": 400, "take_special_finance": 700, "repay_special_finance": 80}
	model.can_special = true
	var viewport := _new_viewport(Vector2i(640, 480))
	var input_panel: Node = panel.get_script().new()
	viewport.add_child(input_panel)
	input_panel.call("set_view_model", model)
	input_panel.connect("closed", Callable(self, "_on_closed"))
	await process_frame
	var borrow_button: BaseButton = input_panel.find_child("LoanBorrow", true, false) as BaseButton
	var special_button: BaseButton = input_panel.find_child("SpecialBorrow", true, false) as BaseButton
	expect(borrow_button != null, "loan entry always starts on the source front scene")
	expect(special_button == null, "owner permission does not auto-switch loan entry to the rear scene")
	var rear_entry: BaseButton = input_panel.find_child("BankRearEntry", true, false) as BaseButton
	expect(rear_entry != null and rear_entry.position == Vector2(268, 51) and rear_entry.size == Vector2(323, 222), "owner front scene exposes the exact rear-entry hit target")
	expect(not bool(input_panel.call("select_action", "take_special_finance")), "front scene rejects direct special-finance selection")
	_click(viewport, Vector2(300, 100))
	await process_frame
	special_button = input_panel.find_child("SpecialBorrow", true, false) as BaseButton
	borrow_button = input_panel.find_child("LoanBorrow", true, false) as BaseButton
	expect(special_button != null, "owner rear-entry hit target opens the source special scene")
	expect(borrow_button == null, "rear scene does not expose ordinary loan actions")
	expect(not bool(input_panel.call("select_action", "take_loan")), "rear scene rejects direct ordinary-loan selection")
	var refreshed_model: Dictionary = model.duplicate(true)
	input_panel.call("set_view_model", refreshed_model)
	await process_frame
	expect(input_panel.find_child("SpecialBorrow", true, false) != null, "model refresh preserves a valid owner rear scene")
	refreshed_model.can_special = false
	input_panel.call("set_view_model", refreshed_model)
	await process_frame
	expect(input_panel.find_child("LoanBorrow", true, false) != null and input_panel.find_child("SpecialBorrow", true, false) == null, "owner revocation returns a refreshed rear scene to front")
	refreshed_model.can_special = true
	input_panel.call("set_view_model", refreshed_model)
	await process_frame
	_click(viewport, Vector2(300, 100))
	await process_frame
	var exit_button: BaseButton = input_panel.find_child("BankExit", true, false) as BaseButton
	_closed_count = 0
	if exit_button != null:
		exit_button.pressed.emit()
	await process_frame
	expect(_closed_count == 0, "rear EXIT returns to the source front scene")
	expect(input_panel.find_child("LoanBorrow", true, false) != null and input_panel.find_child("SpecialBorrow", true, false) == null, "rear EXIT rebuilds the ordinary front scene")
	input_panel.queue_free()
	viewport.queue_free()
	await process_frame


func _test_rear_special_gate(panel: Node) -> void:
	var model := _base_model()
	model.entry_mode = "loan"
	model.edition = "Game"
	model.allowed_actions = ["take_loan", "repay_loan", "take_special_finance", "repay_special_finance", "exit"]
	model.action_limits = {"take_loan": 1200, "repay_loan": 400, "take_special_finance": 700, "repay_special_finance": 80}
	model.can_special = false
	panel.call("set_view_model", model)
	var special_button: BaseButton = panel.find_child("SpecialBorrow", true, false) as BaseButton
	expect(special_button == null, "non-owner cannot enter or render the owner-only rear scene")
	expect(panel.find_child("BankRearEntry", true, false) == null, "non-owner front scene has no rear-entry hit target")
	expect(not bool(panel.call("select_action", "take_special_finance")), "non-owner cannot select special financing from the front scene")

	model.can_special = true
	var viewport := _new_viewport(Vector2i(640, 480))
	var input_panel: Node = panel.get_script().new()
	viewport.add_child(input_panel)
	input_panel.call("set_view_model", model)
	input_panel.connect("action_requested", Callable(self, "_on_action_requested"))
	await process_frame
	_click(viewport, Vector2(300, 100))
	await process_frame
	special_button = input_panel.find_child("SpecialBorrow", true, false) as BaseButton
	expect(special_button != null and not special_button.disabled, "owner gate enables special financing after rear entry")
	var principal: Label = input_panel.find_child("SpecialPrincipal", true, false) as Label
	var other_deposits: Label = input_panel.find_child("SpecialOtherDeposits", true, false) as Label
	expect(principal != null and principal.text.contains("80") and other_deposits != null and other_deposits.text.contains("1000"), "rear scene displays supplied principal and other deposits")
	if special_button != null:
		_requests.clear()
		special_button.pressed.emit()
		input_panel.call("set_amount_text", "700")
		input_panel.call("confirm_amount")
		expect(_requests.size() == 1 and _requests[0] == ["take_special_finance", 700], "special action uses canonical core action name")
	_requests.clear()
	input_panel.queue_free()
	viewport.queue_free()
	await process_frame


func _test_hidden_input_guard(panel: Node) -> void:
	var viewport := _new_viewport(Vector2i(320, 338))
	var input_panel: Node = panel.get_script().new()
	viewport.add_child(input_panel)
	input_panel.call("set_view_model", _base_model())
	input_panel.call("select_action", "withdraw")
	input_panel.call("set_amount_text", "")
	await process_frame
	input_panel.hide()
	viewport.push_input(_key_event(KEY_1, "1"))
	await process_frame
	expect(int(input_panel.call("current_amount")) == 0, "hidden bank panel does not intercept keyboard input")
	input_panel.show()
	input_panel.call("set_amount_text", "")
	viewport.push_input(_key_event(KEY_1, "1"))
	await process_frame
	expect(int(input_panel.call("current_amount")) == 1, "visible bank panel still accepts keyboard input")
	input_panel.queue_free()
	viewport.queue_free()
	await process_frame


func _test_visual_layering_and_source_chunks(panel: Node) -> void:
	var model := _base_model()
	model.entry_mode = "loan"
	model.edition = "Game"
	model.allowed_actions = ["take_loan", "repay_loan", "exit"]
	model.action_limits = {"take_loan": 1200, "repay_loan": 400}
	model.can_special = false
	var front_texture := _solid_texture(Vector2i(640, 480), Color("#d83b87"))
	var rear_texture := _solid_texture(Vector2i(640, 480), Color("#3bbfd1"))
	var blind_texture := _solid_texture(Vector2i(333, 231), Color("#15366f"))
	var summary_texture := _solid_texture(Vector2i(128, 128), Color("#e4ca42"))
	var visuals := {
		"Game.Panel23.front": front_texture,
		"Game.Panel23.rear": rear_texture,
		"Game.Panel23.chunk1": blind_texture,
		"Game.Panel23.chunk20": summary_texture,
	}
	var viewport := _new_viewport(Vector2i(640, 480))
	var input_panel: Node = panel.get_script().new()
	viewport.add_child(input_panel)
	input_panel.call("set_view_model", model)
	input_panel.call("set_visuals", visuals)
	await process_frame
	var source_visual: TextureRect = input_panel.find_child("SourceVisual", true, false) as TextureRect
	expect(source_visual != null and source_visual.texture == front_texture, "front scene binds the Game Panel23 source background")
	var loan_button: Button = input_panel.find_child("LoanBorrow", true, false) as Button
	if loan_button != null:
		expect(loan_button.get_theme_stylebox("normal") is StyleBoxEmpty, "source loan controls are transparent hit targets")
	var blind: TextureRect = input_panel.find_child("SourceRearBlind", true, false) as TextureRect
	expect(blind != null and blind.texture == blind_texture and blind.position == Vector2(258, 42), "non-owner front scene assembles the anchored rear-entry blind")
	var render_texture := viewport.get_texture()
	if DisplayServer.get_name() == "headless" or render_texture == null or render_texture.get_width() <= 0 or render_texture.get_height() <= 0:
		print("SKIP: source loan hit-target pixel check requires a rendered SubViewport")
	else:
		var rendered := render_texture.get_image()
		if rendered == null or rendered.is_empty():
			print("SKIP: source loan hit-target pixel check received an empty SubViewport image")
		else:
			var button_pixel := rendered.get_pixel(286, 330)
			expect(button_pixel.r > 0.65 and button_pixel.b > 0.25, "source loan art remains visible beneath transparent hit targets")

	model.can_special = true
	model.allowed_actions = ["take_loan", "repay_loan", "take_special_finance", "repay_special_finance", "exit"]
	model.action_limits = {"take_loan": 1200, "repay_loan": 400, "take_special_finance": 700, "repay_special_finance": 80}
	input_panel.call("set_view_model", model)
	input_panel.call("set_visuals", visuals)
	await process_frame
	_click(viewport, Vector2(300, 100))
	await process_frame
	source_visual = input_panel.find_child("SourceVisual", true, false) as TextureRect
	expect(source_visual != null and source_visual.texture == rear_texture, "rear scene binds the Game Panel23 special background")
	var summary: TextureRect = input_panel.find_child("SourceSpecialSummary", true, false) as TextureRect
	expect(summary != null and summary.texture == summary_texture, "rear scene assembles the source summary chunk20")
	input_panel.queue_free()
	viewport.queue_free()
	await process_frame


func _test_amount_pad_source_layering() -> void:
	var viewport := _new_viewport(Vector2i(128, 192))
	var pad_script: Script = load("res://game/ui/source_amount_pad.gd")
	var pad: Node = pad_script.new()
	viewport.add_child(pad)
	var texture := _solid_texture(Vector2i(128, 192), Color("#e63f7f"))
	pad.call("set_visuals", {"Game.Panel21": texture}, "Game")
	pad.call("configure", "take_loan", 1200)
	await process_frame
	var source_visual: TextureRect = pad.find_child("AmountPadSourceVisual", true, false) as TextureRect
	var surface: Panel = pad.find_child("AmountPadSurface", true, false) as Panel
	expect(source_visual != null and surface != null and source_visual.get_index() < surface.get_index(), "Panel21 source image stays below controls but above the fallback surface")
	if surface != null:
		expect(surface.get_theme_stylebox("panel") is StyleBoxEmpty, "Panel21 fallback surface is transparent when source art is bound")
	var amount_button: Button = pad.find_child("AmountDigit7", true, false) as Button
	if amount_button != null:
		expect(amount_button.get_theme_stylebox("normal") is StyleBoxEmpty, "Panel21 keypad uses transparent source hit targets")
	await process_frame
	var render_texture := viewport.get_texture()
	if DisplayServer.get_name() == "headless" or render_texture == null or render_texture.get_width() <= 0 or render_texture.get_height() <= 0:
		print("SKIP: Panel21 source-layer pixel check requires a rendered SubViewport")
	else:
		var rendered := render_texture.get_image()
		if rendered == null or rendered.is_empty():
			print("SKIP: Panel21 source-layer pixel check received an empty SubViewport image")
		else:
			var sample := rendered.get_pixel(124, 120)
			expect(sample.r > 0.7 and sample.b > 0.35 and sample.g < 0.45, "Panel21 source image remains visible above the calculator surface")
	pad.queue_free()
	viewport.queue_free()
	await process_frame


func _test_cancel_paths(panel: Node) -> void:
	var model := _base_model()
	model.entry_mode = "atm"
	panel.call("set_view_model", model)
	_requests.clear()
	_closed_count = 0
	panel.call("select_action", "withdraw")
	panel.call("set_amount_text", "12")
	panel.call("cancel_amount")
	expect(str(panel.call("current_action")) == "", "amount-pad cancel returns to bank scene")
	expect(_closed_count == 0, "amount-pad cancel does not close the whole flow")
	var exit_button: BaseButton = panel.find_child("ATMExit", true, false) as BaseButton
	if exit_button != null:
		exit_button.pressed.emit()
	expect(_closed_count == 1, "bank EXIT emits closed as the explicit cancel")


func _new_viewport(viewport_size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.disable_3d = true
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _click(viewport: SubViewport, position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = position
	down.global_position = position
	down.pressed = true
	viewport.push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = position
	up.global_position = position
	up.pressed = false
	viewport.push_input(up)


func _solid_texture(texture_size: Vector2i, color: Color) -> Texture2D:
	var image := Image.create(texture_size.x, texture_size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _key_event(keycode: Key, unicode_value: String) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.unicode = unicode_value.unicode_at(0)
	event.pressed = true
	return event


func _on_action_requested(action: String, amount: int) -> void:
	_requests.append([action, amount])


func _on_closed() -> void:
	_closed_count += 1
