extends SceneTree
const Bank = preload("res://game/ui/source_bank_panel.gd")
const Pad = preload("res://game/ui/source_amount_pad.gd")
var checks := 0
var failures := 0
class Visuals extends RefCounted:
	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		return {"edition": edition, "archive": archive, "resource": resource, "chunk": chunk}
	func texture(frame: Dictionary) -> Texture2D:
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color(float(int(frame.chunk) % 5 + 1) / 6.0, 0.4, 0.6))
		return ImageTexture.create_from_image(image)
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func settle() -> void:
	await process_frame
	await process_frame
func click(viewport: SubViewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.pressed = down
		event.button_index = MOUSE_BUTTON_LEFT
		viewport.push_input(event, true)
func hidden(node: Node, names: Array) -> void:
	for key in names:
		var child := node.find_child(key, true, false) as CanvasItem
		check(child == null or not child.is_visible_in_tree(), key + " cannot duplicate baked source information")
func blank_buttons(node: Node) -> void:
	for child in node.get_children():
		if child is Button: check(child.text.is_empty(), str(child.name) + " keeps source legends free of duplicate text")
func label(node: Node, key: String, center: Vector2, font: int, color: Color, expected_text: String) -> void:
	var item := node.find_child(key, true, false) as Label
	check(item != null, key + " source dynamic text exists")
	if item == null: return
	check(item.get_rect().get_center() == center, key + " uses the source text center")
	check(item.get_theme_font_size("font_size") == font and item.get_theme_color("font_color") == color, key + " preserves source typography")
	check(item.text == expected_text, key + " displays the source text or amount")
func digit(node: Node, group_name: String, position: Vector2, chunk: int, count: int) -> void:
	var group := node.find_child(group_name, true, false)
	check(group != null, group_name + " uses source numeric sprites")
	if group == null: return
	check(group.get_child_count() == count, group_name + " draws exactly the displayed digits")
	if group.get_child_count() == 0: return
	var sprite := group.get_child(0) as TextureRect
	check(sprite != null and sprite.texture != null and sprite.position == position and sprite.get_meta("source_chunk", -1) == chunk, group_name + " rightmost digit uses the source chunk and anchor")
func run() -> void:
	for edition in ["Game", "MultiverseJourney"]:
		await bank_case(edition)
		await calculator_case(edition)
	print("Source bank visual checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
func viewport() -> SubViewport:
	var result := SubViewport.new()
	result.size = Vector2i(640, 480)
	result.handle_input_locally = true
	root.add_child(result)
	result.notify_mouse_entered()
	return result
func bank_case(edition: String) -> void:
	var view := viewport()
	var panel := Bank.new()
	view.add_child(panel)
	var model := {"edition": edition, "entry_mode": "atm", "allowed_actions": ["withdraw", "deposit", "exit"], "action_limits": {"withdraw": 3400, "deposit": 6800}, "cash": 6800, "deposit": 3400, "can_special": false}
	var original: Dictionary = model.duplicate(true)
	var requests: Array = []
	panel.action_requested.connect(func(action: String, amount: int) -> void: requests.append([action, amount]))
	panel.set_view_model(model)
	panel.set_visuals(Visuals.new())
	await settle()
	hidden(panel, ["ATMTitle", "ATMCash", "ATMDepositValue", "ATMAmountValue", "ATMFeedback", "ATMAmountBar"])
	blank_buttons(panel)
	digit(panel, "ATMSourceDigits", Vector2(244, 101), 19, 1)
	click(view, Vector2(97, 69))
	check(panel.current_action() == "withdraw" and requests.is_empty(), "ATM source withdrawal chooses without confirming")
	for point in [Vector2(74, 219), Vector2(74, 238), Vector2(74, 257)]: click(view, point)
	check(panel.current_amount() == 741, "ATM source digit rows produce 741")
	click(view, Vector2(152, 276))
	check(panel.current_amount() == 74, "ATM source backspace removes the last digit")
	click(view, Vector2(113, 276))
	check(panel.current_amount() == 740, "ATM source zero appends zero")
	click(view, Vector2(74, 276))
	check(panel.current_amount() == 0, "ATM source C clears")
	click(view, Vector2(58, 150))
	check(panel.current_amount() == 0, "ATM percent left endpoint is zero")
	click(view, Vector2(160, 150))
	check(panel.current_amount() == 1818, "ATM percent uses original 34-step interior mapping")
	var progress := panel.find_child("ATMSourceProgress", true, false) as Control
	check(progress != null and progress.position == Vector2(58, 139) and progress.size.x == 108, "ATM source progress clips to eighteen six-pixel steps")
	click(view, Vector2(262, 150))
	check(panel.current_amount() == 3400, "ATM percent right endpoint is the current limit")
	digit(panel, "ATMSourceDigits", Vector2(244, 101), 19, 4)
	click(view, Vector2(203, 272))
	check(requests == [["withdraw", 3400]], "ATM source Enter emits exact selected maximum")
	click(view, Vector2(179, 69))
	check(panel.current_action() == "deposit", "ATM source deposit switches direction")
	click(view, Vector2(206, 245))
	check(panel.current_amount() == 6800, "ATM source MAX follows the selected deposit limit")
	check(model == original, "ATM interactions preserve host model")
	model = {"edition": edition, "entry_mode": "loan", "allowed_actions": ["take_loan", "repay_loan", "take_special_finance", "repay_special_finance", "exit"], "action_limits": {"take_loan": 3300, "repay_loan": 400, "take_special_finance": 120000, "repay_special_finance": 80000}, "cash": 6800, "deposit": 3400, "loan": 400, "due_date": 37, "can_special": true, "other_deposits": 100000, "special_principal": 80000}
	panel.set_view_model(model)
	await settle()
	hidden(panel, ["LoanTitle", "LoanCash", "LoanDeposit", "LoanBalance", "LoanDueDate", "BankFeedback"])
	blank_buttons(panel)
	label(panel, "LoanBorrowLabel", Vector2(345, 345), 26, Color("#101010"), "申請貸款")
	label(panel, "LoanRepayLabel", Vector2(530, 345), 26, Color("#101010"), "償還貸款")
	label(panel, "BankRearEntryLabel", Vector2(492, 245), 14, Color("#808080"), "特別融資")
	click(view, Vector2(492, 245))
	await settle()
	hidden(panel, ["SpecialTitle", "BankFeedback"])
	blank_buttons(panel)
	label(panel, "SpecialWindowTitle", Vector2(443, 427), 26, Color("#101010"), "特別融資")
	label(panel, "SpecialBorrowLabel", Vector2(67, 324), 20, Color("#f0f0f0"), "週轉現金")
	label(panel, "SpecialRepayLabel", Vector2(67, 382), 20, Color("#f0f0f0"), "歸還款項")
	for item in [["SpecialOtherDepositsLabel", 147, "客戶存款總額"], ["SpecialPrincipalLabel", 195, "目前融資金額"], ["SpecialAvailableLabel", 243, "尚可融資金額"]]:
		label(panel, item[0], Vector2(78, item[1]), 16, Color("#202020"), item[2])
	for item in [["SpecialOtherDeposits", 163, "$100,000"], ["SpecialPrincipal", 211, "$80,000"], ["SpecialAvailable", 259, "$120,000"]]:
		var amount := panel.find_child(item[0], true, false) as Label
		check(amount != null and amount.text == item[2] and amount.get_rect().end.x == 128 and amount.get_rect().get_center().y == item[1] and amount.get_theme_font_size("font_size") == 16 and amount.get_theme_color("font_color") == Color("#f0f0f0"), str(item[0]) + " source money is right aligned and formatted")
	for name in ["SpecialBorrow", "SpecialRepay", "BankExit"]:
		var button := panel.find_child(name, true, false)
		var art := button.find_child("SourceButtonArt", true, false) if button != null else null
		check(art is TextureRect and art.texture != null, name + " assembles original normal button art")
	view.queue_free()
	await settle()
func calculator_case(edition: String) -> void:
	var view := viewport()
	var pad := Pad.new()
	view.add_child(pad)
	var amounts: Array = []
	pad.confirmed.connect(func(value: int) -> void: amounts.append(value))
	pad.set_visuals(Visuals.new(), edition)
	pad.configure("take_loan", 3300)
	await settle()
	hidden(pad, ["AmountPadTitle", "AmountInput", "AmountValue", "AmountLimit", "AmountError"])
	blank_buttons(pad)
	digit(pad, "AmountSourceDigits", Vector2(107, 11), 16, 1)
	for point in [Vector2(24, 127), Vector2(24, 151), Vector2(24, 175)]: click(view, point)
	check(pad.raw_text() == "741", "calculator source digit rows produce 741")
	click(view, Vector2(104, 103))
	check(pad.raw_text() == "74", "calculator source backspace removes one digit")
	click(view, Vector2(64, 103))
	check(pad.raw_text() == "740", "calculator source zero appends one digit")
	click(view, Vector2(24, 103))
	check(pad.current_amount() == 0 if pad.has_method("current_amount") else not pad.parsed_amount().get("ok", false), "calculator source C clears the selected amount")
	click(view, Vector2(10, 48))
	check(not pad.parsed_amount().get("ok", false), "calculator percent zero cannot confirm")
	click(view, Vector2(65, 48))
	check(pad.parsed_amount().get("amount", -1) == 1700, "calculator percent uses original threshold index17 of33")
	click(view, Vector2(117, 48))
	check(pad.parsed_amount().get("amount", -1) == 3300, "calculator percent right endpoint is maximum")
	click(view, Vector2(24, 103))
	click(view, Vector2(32, 75))
	check(pad.parsed_amount().get("amount", -1) == 3300, "calculator MAX uses source top-row geometry")
	digit(pad, "AmountSourceDigits", Vector2(107, 11), 16, 4)
	click(view, Vector2(92, 75))
	check(amounts == [3300], "calculator source Enter confirms once")
	view.queue_free()
	await settle()
