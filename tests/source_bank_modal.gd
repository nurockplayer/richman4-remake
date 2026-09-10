extends "res://tests/source_bank_visual.gd"

func run() -> void:
	for edition in ["Game", "MultiverseJourney"]:
		for rear in [false, true]:
			await modal_case(edition, rear)
	print("Source bank modal checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func modal_case(edition: String, rear: bool) -> void:
	var view := viewport()
	var panel := Bank.new()
	view.add_child(panel)
	var closed_events: Array = []
	var requests: Array = []
	panel.closed.connect(func() -> void: closed_events.append(true))
	panel.action_requested.connect(func(action: String, amount: int) -> void: requests.append([action, amount]))
	panel.set_visuals(Visuals.new())
	panel.set_view_model({"edition": edition, "entry_mode": "loan", "can_special": true, "cash": 100, "deposit": 100, "loan": 100,
		"allowed_actions": ["take_loan", "repay_loan", "take_special_finance", "repay_special_finance"],
		"action_limits": {"take_loan": 100, "repay_loan": 100, "take_special_finance": 100, "repay_special_finance": 100}})
	await settle()
	if rear:
		click(view, Vector2(490, 110))
		await settle()
	var expected_scene := "rear" if rear else "front"
	check(panel.get("_bank_scene") == expected_scene, "fixture enters the requested bank scene")
	click(view, Vector2(67, 325) if rear else Vector2(345, 345))
	await settle()
	var initial_pad := panel.get("_amount_pad") as Control
	check(initial_pad != null, "pointer opens the nested calculator")
	panel.set_amount_text("25")
	# The source nested wait excludes all parent callbacks until it returns.
	for point in ([Vector2(51, 439), Vector2(67, 382)] if rear else [Vector2(588, 451), Vector2(490, 110), Vector2(530, 345)]):
		click(view, point)
		await settle()
		check(closed_events.is_empty(), "calculator blocks the background bank exit")
		check(panel.get("_bank_scene") == expected_scene, "calculator blocks background scene changes")
		check(is_instance_valid(initial_pad) and panel.get("_amount_pad") == initial_pad and panel.current_amount() == 25, "background click preserves the same calculator and amount")
		check(requests.is_empty(), "background click does not submit a transaction")
	# Restore only for continued diagnostics if the baseline leaked input.
	if not is_instance_valid(initial_pad) or panel.get("_amount_pad") != initial_pad:
		panel.free()
		view.queue_free()
		await settle()
		return
	for button_name in (["SpecialBorrow", "SpecialRepay", "BankExit"] if rear else ["LoanBorrow", "LoanRepay", "BankExit", "BankRearEntry"]):
		var button := panel.find_child(button_name, true, false) as BaseButton
		check(button != null and button.disabled, "background button cannot receive keyboard activation during calculator")
	initial_pad.grab_focus()
	var cancel_key := InputEventKey.new()
	cancel_key.keycode = KEY_ESCAPE
	cancel_key.pressed = true
	view.push_input(cancel_key, true)
	await settle()
	check(panel.get("_amount_pad") == null and panel.get("_bank_scene") == expected_scene, "Escape returns to the same bank scene")
	check(closed_events.is_empty() and requests.is_empty(), "calculator cancellation neither exits bank nor transacts")
	click(view, Vector2(51, 439) if rear else Vector2(588, 451))
	await settle()
	check(panel.get("_bank_scene") == "front" and closed_events.is_empty() if rear else closed_events == [true], "bank exit becomes available after calculator cancellation")
	view.queue_free()
	await settle()
