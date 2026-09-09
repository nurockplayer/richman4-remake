extends PopupPanel

## Presents the current bidder's response without changing the simulation.
## The game state remains the authority for eligibility and settlement.

signal answered(params: Dictionary)

const INCREMENTS := [100, 500, 1000, 5000, 10000]

var prompt: Label
var status: Label
var increment_buttons: Dictionary = {}
var withdraw: Button
var _pending: Dictionary = {}


func _init() -> void:
	name = "AuctionResponsePopup"
	size = Vector2i(620, 410)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#203447")
	panel.border_color = Color("#54748a")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(16)
	add_theme_stylebox_override("panel", panel)
	exclusive = true
	# Keep the response visible when the parent window temporarily loses focus.
	popup_window = false
	popup_hide.connect(func() -> void: call_deferred("_restore_unanswered"))

	var margin := MarginContainer.new()
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "拍賣回應"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color("#edf5fa"))
	box.add_child(title)
	prompt = Label.new()
	prompt.name = "AuctionPrompt"
	prompt.add_theme_font_size_override("font_size", 15)
	prompt.add_theme_color_override("font_color", Color("#edf5fa"))
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size.x = 560
	box.add_child(prompt)
	status = Label.new()
	status.name = "AuctionStatus"
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color("#e2b25b"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)

	var increment_box := HBoxContainer.new()
	increment_box.name = "AuctionIncrements"
	increment_box.add_theme_constant_override("separation", 6)
	box.add_child(increment_box)
	for amount in INCREMENTS:
		var button := Button.new()
		button.name = "AuctionIncrement%d" % amount
		button.text = "+%s" % money(amount)
		button.custom_minimum_size = Vector2(100, 40)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(func() -> void:
			if not _pending.is_empty():
				answered.emit({"increment": amount, "cancel": false})
		)
		increment_box.add_child(button)
		increment_buttons[amount] = button

	withdraw = Button.new()
	withdraw.name = "WithdrawAuction"
	withdraw.text = "退出拍賣"
	withdraw.custom_minimum_size = Vector2(0, 40)
	withdraw.pressed.connect(func() -> void:
		if not _pending.is_empty():
			answered.emit({"increment": 0, "cancel": true})
	)
	box.add_child(withdraw)


func cancel_presentation() -> void:
	_pending = {}
	hide()


static func human_pending(snapshot: Dictionary) -> bool:
	var pending: Variant = snapshot.get("pending_auction", {})
	if typeof(pending) != TYPE_DICTIONARY or pending.is_empty():
		return false
	var players: Variant = snapshot.get("players", [])
	if typeof(players) != TYPE_ARRAY:
		return false
	var bidder_id := int(pending.get("bidder_id", -1))
	if bidder_id < 0 or bidder_id >= players.size() or typeof(players[bidder_id]) != TYPE_DICTIONARY:
		return false
	var bidder: Dictionary = players[bidder_id]
	return bool(bidder.get("alive", false)) and bool(bidder.get("is_human", false)) and not bool(bidder.get("is_ai", false))


func sync(snapshot: Dictionary) -> void:
	var pending_value: Variant = snapshot.get("pending_auction", {})
	if not human_pending(snapshot):
		_pending = {}
		hide()
		return
	var pending: Dictionary = pending_value
	var same := pending == _pending
	_pending = pending.duplicate(true)
	var players: Array = snapshot.get("players", [])
	var bidder_id := int(pending.get("bidder_id", -1))
	var bidder: Dictionary = players[bidder_id]
	var caster_id := int(pending.get("caster_id", -1))
	var current_bid := int(pending.get("current_bid", 0))
	var opening_bid := int(pending.get("opening_bid", 0))
	prompt.text = "%s 請回應目前報價 $%s。" % [str(bidder.get("name", "玩家 %d" % (bidder_id + 1))), money(current_bid)]
	status.text = "底價 $%s · 出價後輪到下一位玩家。" % money(opening_bid)
	if caster_id >= 0 and caster_id < players.size() and typeof(players[caster_id]) == TYPE_DICTIONARY:
		status.text += "　收款人：%s" % str(players[caster_id].get("name", "玩家 %d" % (caster_id + 1)))
	var cash := int(bidder.get("cash", 0))
	for amount in INCREMENTS:
		var button: Button = increment_buttons[amount]
		button.disabled = current_bid + amount > cash
	withdraw.disabled = false
	if not visible:
		popup_centered()


func _restore_unanswered() -> void:
	if is_inside_tree() and not is_queued_for_deletion() and not _pending.is_empty() and not visible:
		popup_centered()


static func money(amount: int) -> String:
	var digits := str(amount)
	var result := ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += ","
		result += digits[index]
	return result
