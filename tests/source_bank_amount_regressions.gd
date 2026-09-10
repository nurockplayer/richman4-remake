extends "res://tests/source_bank_visual.gd"

class SourceBarVisuals extends RefCounted:
	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		return {"edition": edition, "archive": archive, "resource": resource, "chunk": chunk}
	func texture(frame: Dictionary) -> Texture2D:
		var dimensions := Vector2i(128, 192) if frame.resource == 21 and frame.chunk == 0 else Vector2i(108, 12)
		var image := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
		# Source Panel21 chunk0 contains filled bars; chunk1 is the empty bar.
		image.fill(Color.RED if frame.chunk == 0 else Color.BLUE)
		return ImageTexture.create_from_image(image)

func run() -> void:
	for edition in ["Game", "MultiverseJourney"]:
		await zero_prefix(edition)
		await source_progress(edition)
		await keypad_limit(edition)
	print("Source bank amount regression checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func zero_prefix(edition: String) -> void:
	var view := viewport()
	var pad := Pad.new()
	view.add_child(pad)
	var amounts: Array = []
	pad.confirmed.connect(func(amount: int) -> void: amounts.append(amount))
	pad.set_visuals(Visuals.new(), edition)
	pad.configure("take_loan", 9)
	await settle()
	click(view, Vector2(64, 103))
	click(view, Vector2(64, 103))
	check(pad.raw_text() == "0", "calculator repeated zero remains one source zero")
	click(view, Vector2(24, 175))
	check(pad.raw_text() == "1" and pad.parsed_amount().get("amount", -1) == 1, "calculator zero then one becomes the valid amount one")
	click(view, Vector2(92, 75))
	check(amounts == [1], "calculator zero-prefix sequence can confirm under one-digit limit")
	pad.free()
	var bank := Bank.new()
	view.add_child(bank)
	var requests: Array = []
	bank.action_requested.connect(func(action: String, amount: int) -> void: requests.append([action, amount]))
	bank.set_visuals(Visuals.new())
	bank.set_view_model({"edition": edition, "entry_mode": "atm", "allowed_actions": ["withdraw"], "action_limits": {"withdraw": 9}, "cash": 0, "deposit": 9})
	await settle()
	click(view, Vector2(97, 69))
	click(view, Vector2(113, 276))
	click(view, Vector2(113, 276))
	check(bank.get("_amount_text") == "0", "ATM repeated zero remains one source zero")
	click(view, Vector2(74, 257))
	check(bank.current_amount() == 1, "ATM zero then one remains a legal amount")
	click(view, Vector2(203, 272))
	check(requests == [["withdraw", 1]], "ATM zero-prefix sequence can confirm under one-digit limit")
	view.queue_free()
	await settle()

func source_progress(edition: String) -> void:
	var view := viewport()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var pad := Pad.new()
	view.add_child(pad)
	pad.set_visuals(SourceBarVisuals.new(), edition)
	pad.configure("take_loan", 3300)
	await settle()
	# Exact source threshold entries and zero's separately empty state.
	for sample in [[0, 0], [1, 3], [1700, 57], [3300, 107]]:
		pad.set_amount_text(str(sample[0]))
		await settle()
		var progress := pad.find_child("AmountSourceProgress", true, false) as Control
		check(progress != null and progress.size.x == sample[1], "calculator amount %d clips to source threshold %d" % sample)
		if DisplayServer.get_name() == "headless": continue
		await RenderingServer.frame_post_draw
		var rendered := view.get_texture().get_image()
		# The original draws empty chunk1, then restores the filled background
		# prefix. Check both sides; merely clipping chunk1 reverses the bar.
		for offset in [1, 4, 55, 60, 106, 107]:
			var expected := Color.RED if offset < int(sample[1]) else Color.BLUE
			var actual := rendered.get_pixel(10 + offset, 48)
			check(actual.is_equal_approx(expected), "source bar amount %d pixel %d reflects filled-left/empty-right" % [sample[0], offset])
	if DisplayServer.get_name() == "headless": print("SKIP: source bar pixel comparison requires native rendering")
	view.queue_free()
	await settle()

func keypad_limit(edition: String) -> void:
	for maximum_value in [9, 123]:
		var view := viewport()
		var pad := Pad.new()
		view.add_child(pad)
		var amounts: Array = []
		var cancellations: Array = []
		pad.confirmed.connect(func(amount: int) -> void: amounts.append(amount))
		pad.cancelled.connect(func() -> void: cancellations.append(true))
		pad.set_visuals(Visuals.new(), edition)
		pad.configure("take_loan", maximum_value)
		await settle()
		for point in [Vector2(24, 175), Vector2(64, 175), Vector2(104, 175), Vector2(24, 151)]: click(view, point)
		check(pad.raw_text() == str(maximum_value), "calculator keypad caps each appended digit at the source limit")
		check(amounts.is_empty(), "calculator capped digits do not submit before ENTER")
		click(view, Vector2(92, 75))
		check(amounts == [maximum_value], "calculator capped keypad amount confirms the exact limit")
		# Original calculator ENTER returns zero to its caller as cancellation;
		# it does not create a zero-valued banking transaction.
		click(view, Vector2(24, 103))
		click(view, Vector2(92, 75))
		check(cancellations == [true] and amounts == [maximum_value], "calculator cleared zero ENTER cancels without another transaction")
		pad.free()
		var bank := Bank.new()
		view.add_child(bank)
		var requests: Array = []
		bank.action_requested.connect(func(action: String, amount: int) -> void: requests.append([action, amount]))
		bank.set_visuals(Visuals.new())
		bank.set_view_model({"edition": edition, "entry_mode": "atm", "allowed_actions": ["withdraw"], "action_limits": {"withdraw": maximum_value}, "cash": 0, "deposit": maximum_value})
		await settle()
		click(view, Vector2(97, 69))
		for point in [Vector2(74, 257), Vector2(113, 257), Vector2(152, 257), Vector2(74, 238)]: click(view, point)
		check(bank.current_amount() == maximum_value, "ATM keypad caps each appended digit at the source limit")
		check(requests.is_empty(), "ATM capped digits do not submit before ENTER")
		click(view, Vector2(203, 272))
		check(requests == [["withdraw", maximum_value]], "ATM capped keypad amount confirms the exact limit")
		view.queue_free()
		await settle()
