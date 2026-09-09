extends PopupPanel

signal answered(params: Dictionary)
var prompt: Label
var target: OptionButton
var accept: Button
var decline: Button
var _pending: Dictionary = {}

func _init() -> void:
	name = "FinancialResponsePopup"
	size = Vector2i(540, 240)
	exclusive = true
	popup_window = false
	popup_hide.connect(func() -> void: call_deferred("_restore_unanswered"))
	var margin := MarginContainer.new()
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	prompt = Label.new()
	prompt.name = "FinancialPrompt"
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size.x = 490
	box.add_child(prompt)
	target = OptionButton.new()
	target.name = "FinancialRedirectTarget"
	target.custom_minimum_size.y = 36
	box.add_child(target)
	accept = Button.new()
	accept.name = "AcceptFinancial"
	accept.custom_minimum_size.y = 38
	accept.pressed.connect(func() -> void:
		if _pending.is_empty(): return
		var params := {"cancel": false}
		if _pending.get("stage", "") == "redirect":
			if target.item_count == 0: return
			params["target_id"] = target.get_selected_id()
		answered.emit(params)
	)
	box.add_child(accept)
	decline = Button.new()
	decline.name = "DeclineFinancial"
	decline.custom_minimum_size.y = 38
	decline.pressed.connect(func() -> void:
		if not _pending.is_empty(): answered.emit({"cancel": true})
	)
	box.add_child(decline)

func _restore_unanswered() -> void:
	if is_inside_tree() and not is_queued_for_deletion() and not _pending.is_empty() and not visible:
		popup_centered()

static func human_pending(snapshot: Dictionary) -> bool:
	var pending: Variant = snapshot.get("pending_finance", {})
	if not pending is Dictionary or pending.is_empty(): return false
	var players: Array = snapshot.get("players", [])
	var payer := int(pending.get("payer_id", -1))
	return payer >= 0 and payer < players.size() and bool(players[payer].get("alive", false)) and bool(players[payer].get("is_human", false))

func sync(snapshot: Dictionary, targets: Array) -> void:
	if not human_pending(snapshot):
		_pending = {}
		hide()
		return
	var pending: Dictionary = snapshot.pending_finance
	var same := pending == _pending
	_pending = pending.duplicate(true)
	var players: Array = snapshot.players
	var payer := int(pending.payer_id)
	var cause := str({"rent": "地租", "facility": "設施費用", "company": "企業服務費", "tax": "查稅"}.get(str(pending.kind), "費用"))
	var redirect: bool = pending.stage == "redirect"
	prompt.text = "%s · %s $%s\n%s" % [str(players[payer].name), cause, money(int(pending.amount)), "使用嫁禍卡改由另一位玩家接受查稅？金額依新目標的現金重新計算。" if redirect else "使用免費卡免除這筆付款？"]
	var prior := target.get_selected_id() if same and target.item_count > 0 else -1
	target.clear()
	if redirect:
		for id in targets:
			target.add_item(str(players[int(id)].name), int(id))
			if int(id) == prior: target.select(target.item_count - 1)
	target.visible = redirect
	accept.text = "使用嫁禍卡" if redirect else "使用免費卡"
	accept.disabled = redirect and target.item_count == 0
	decline.text = "不使用，支付稅款" if redirect else "不使用免費卡"
	if not visible: popup_centered()

static func money(amount: int) -> String:
	var digits := str(amount)
	var result := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0: result += ","
		result += digits[i]
	return result
