extends Control
class_name RichmanSourceBankController

## Host boundary for the source bank encounter.
##
## The controller owns modal lifetime and the small amount of presentation
## adaptation needed by SourceBankPanel.  GameState remains the owner of all
## accounting and admission decisions: this node reads only its public token,
## limit and company queries, then forwards confirmed actions through the host
## adapters.

const SourceBankPanel = preload("res://game/ui/source_bank_panel.gd")

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const ATM_POSITION := Vector2(60.0, 71.0)
const ATM_SIZE := Vector2(320.0, 338.0)
const BANK_POSITION := Vector2.ZERO
const BANK_SIZE := Vector2(640.0, 480.0)
const BANK_ACTIONS := [
	"deposit", "withdraw", "take_loan", "repay_loan",
	"take_special_finance", "repay_special_finance",
]

## MainUI assigns these to its existing _invoke_game/_handle_result methods.
## They remain Callables so the controller can be tested without constructing
## MainUI or a live GameState.
var invoke_game: Callable = Callable()
var handle_result: Callable = Callable()

## Public for the host and focused tests; the panel itself remains a source
## presenter with no knowledge of GameState or persistence.
var bank_panel: Control
var error_label: Label

var _core: Object = null
var _snapshot: Dictionary = {}
var _edition := "Game"
var _visuals: Variant = null
var _active_token: Dictionary = {}
var _entry_kind := ""
var _panel_mode := "atm"
var _open := false
var _blocked := false
var _generation := 0
var _action_pending := false
var _model_signature := ""


func _init() -> void:
	name = "SourceBankController"
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	bank_panel = SourceBankPanel.new()
	bank_panel.name = "SourceBankPanel"
	bank_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	bank_panel.hide()
	add_child(bank_panel)
	bank_panel.connect("action_requested", Callable(self, "_on_action_requested"))
	bank_panel.connect("closed", Callable(self, "_on_panel_closed"))
	error_label = Label.new()
	error_label.name = "SourceBankControllerError"
	error_label.position = Vector2(12.0, 8.0)
	error_label.size = Vector2(616.0, 28.0)
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_font_size_override("font_size", 13)
	error_label.add_theme_color_override("font_color", Color("#ffb3a4"))
	error_label.add_theme_color_override("font_outline_color", Color("#111b22"))
	error_label.add_theme_constant_override("outline_size", 4)
	error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	error_label.z_index = 100
	error_label.hide()
	add_child(error_label)
	hide()


## Reconcile the controller with the current core token and host snapshot.
##
## A valid token is the only ingress signal.  In particular, the controller
## does not infer an encounter from event_log/last_event or from bank flags.
func sync(
		core: Object,
		snapshot: Dictionary,
		edition: String,
		visuals: Variant,
		blocked: bool = false,
) -> void:
	_core = core
	_snapshot = snapshot.duplicate(true)
	_edition = _canonical_edition(edition)
	_visuals = visuals
	_blocked = blocked
	var token := _read_pending_token(core)
	var valid := _valid_ingress(token, _snapshot)
	if _open:
		if not valid or token != _active_token:
			_cancel_local()
			if blocked or not valid:
				return
		if blocked:
			return
	else:
		if blocked or not valid:
			return
		_active_token = token.duplicate(true)
		_entry_kind = str(token.get("kind", ""))
		_panel_mode = "atm"
		_open = true
		_generation += 1
		show()

	var model := _build_model(token, _snapshot, _panel_mode == "loan")
	_configure_panel(model)
	_clear_error()


## Cancel without calling a core action.  This is used for game replacement,
## terminal state, ownership drift or an explicit host cancel.
func cancel() -> void:
	_cancel_local()


func is_open() -> bool:
	return _open and bank_panel != null and bank_panel.visible


func _cancel_local() -> void:
	_generation += 1
	_action_pending = false
	_open = false
	_entry_kind = ""
	_panel_mode = "atm"
	_active_token = {}
	_model_signature = ""
	if bank_panel != null:
		bank_panel.hide()
	if error_label != null:
		error_label.hide()
	hide()


func _read_pending_token(core: Object) -> Dictionary:
	if core == null or not core.has_method("pending_bank_visit"):
		return {}
	var value: Variant = core.call("pending_bank_visit")
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var token: Dictionary = value
	var keys: Array = token.keys()
	keys.sort()
	if keys != ["kind", "node_id", "player_id"]:
		return {}
	var kind_value: Variant = token.get("kind", null)
	var player_value: Variant = token.get("player_id", null)
	var node_value: Variant = token.get("node_id", null)
	if typeof(kind_value) != TYPE_STRING or str(kind_value) not in ["pass", "landing"]:
		return {}
	if typeof(player_value) != TYPE_INT or typeof(node_value) != TYPE_INT:
		return {}
	if int(player_value) < 0 or int(node_value) < 0:
		return {}
	return token.duplicate(true)


func _valid_ingress(token: Dictionary, snapshot: Dictionary) -> bool:
	if token.is_empty():
		return false
	var kind := str(token.get("kind", ""))
	var actor := int(token.get("player_id", -1))
	var node_id := int(token.get("node_id", -1))
	if kind not in ["pass", "landing"] or actor < 0 or node_id < 0:
		return false
	var phase := str(snapshot.get("phase", ""))
	if (kind == "pass" and phase != "await_bank") or (kind == "landing" and phase != "await_action"):
		return false
	if phase == "game_over":
		return false
	var current_value: Variant = snapshot.get("current_player", null)
	if typeof(current_value) != TYPE_INT or int(current_value) != actor:
		return false
	var player := _player_record(snapshot, actor)
	if player.is_empty():
		return false
	if typeof(player.get("is_human", null)) != TYPE_BOOL or not bool(player.get("is_human", false)):
		return false
	if typeof(player.get("alive", null)) != TYPE_BOOL or not bool(player.get("alive", false)):
		return false
	if typeof(player.get("bankrupt", false)) == TYPE_BOOL and bool(player.get("bankrupt", false)):
		return false
	if typeof(player.get("position", null)) != TYPE_INT or int(player.get("position", -1)) != node_id:
		return false
	if kind == "pass":
		var remaining: Variant = snapshot.get("remaining_steps", null)
		if typeof(remaining) != TYPE_INT or int(remaining) <= 0:
			return false
		var movement: Variant = snapshot.get("pending_movement", null)
		if typeof(movement) != TYPE_DICTIONARY:
			return false
		if typeof(movement.get("player_id", null)) != TYPE_INT or typeof(movement.get("current_node", null)) != TYPE_INT:
			return false
		if int(movement.get("player_id", -1)) != actor or int(movement.get("current_node", -1)) != node_id:
			return false
		if typeof(snapshot.get("route_options", [])) != TYPE_ARRAY or not snapshot.get("route_options", []).is_empty():
			return false
	else:
		var landing_remaining: Variant = snapshot.get("remaining_steps", null)
		if typeof(landing_remaining) != TYPE_INT or int(landing_remaining) != 0:
			return false
		if typeof(snapshot.get("pending_movement", null)) != TYPE_DICTIONARY or not snapshot.get("pending_movement", {}).is_empty():
			return false
	return true


func _player_record(snapshot: Dictionary, player_id: int) -> Dictionary:
	var players_value: Variant = snapshot.get("players", null)
	if typeof(players_value) == TYPE_ARRAY:
		var players: Array = players_value
		if player_id >= 0 and player_id < players.size() and typeof(players[player_id]) == TYPE_DICTIONARY:
			var indexed: Dictionary = players[player_id]
			var indexed_id: Variant = indexed.get("id", player_id)
			if typeof(indexed_id) == TYPE_INT and int(indexed_id) == player_id:
				return indexed
		for value in players:
			if typeof(value) == TYPE_DICTIONARY:
				var value_id: Variant = value.get("id", null)
				if typeof(value_id) == TYPE_INT and int(value_id) == player_id:
					return value
	elif typeof(players_value) == TYPE_DICTIONARY:
		var players_map: Dictionary = players_value
		var direct: Variant = players_map.get(str(player_id), players_map.get(player_id, null))
		if typeof(direct) == TYPE_DICTIONARY:
			return direct
	return {}


func _build_model(token: Dictionary, snapshot: Dictionary, front: bool) -> Dictionary:
	var actor := int(token.get("player_id", -1))
	var node_id := int(token.get("node_id", -1))
	var player := _player_record(snapshot, actor)
	var model: Dictionary = player.duplicate(true)
	model["edition"] = _edition
	model["entry_mode"] = "loan" if front else "atm"
	model["allowed_actions"] = []
	model["action_limits"] = {}
	model["node_id"] = node_id
	model["pending_kind"] = str(token.get("kind", ""))
	var action_options: Variant = snapshot.get("action_options", [])
	var can_special := false
	if str(token.get("kind", "")) == "landing":
		can_special = _company_owner_can_special(node_id, actor)
	model["can_special"] = can_special
	for action in BANK_ACTIONS:
		if not _action_in_snapshot(action_options, action):
			continue
		if action in ["take_special_finance", "repay_special_finance"] and not can_special:
			continue
		var method := "bank_transfer_limit"
		if action in ["take_loan", "repay_loan"]:
			method = "bank_loan_limit"
		elif action in ["take_special_finance", "repay_special_finance"]:
			method = "special_finance_limit"
		var limit := _public_limit(method, action, actor)
		model.action_limits[action] = limit
		if limit > 0:
			model.allowed_actions.append(action)
	if str(token.get("kind", "")) == "pass":
		model["can_special"] = false
	return model


func _action_in_snapshot(action_options: Variant, action: String) -> bool:
	if typeof(action_options) == TYPE_ARRAY or typeof(action_options) == TYPE_PACKED_STRING_ARRAY:
		for value in action_options:
			if typeof(value) == TYPE_STRING and _canonical_action(str(value)) == action:
				return true
	elif typeof(action_options) == TYPE_DICTIONARY:
		var options: Dictionary = action_options
		for alias in _action_aliases(action):
			if options.has(alias):
				return typeof(options.get(alias)) == TYPE_BOOL and bool(options.get(alias))
	return false


func _company_owner_can_special(node_id: int, actor: int) -> bool:
	if _core == null or not _core.has_method("get_company_at"):
		return false
	var value: Variant = _call_with_actor("get_company_at", [node_id])
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var company: Dictionary = value
	var type_value: Variant = company.get("company_type", company.get("type", null))
	var owner_value: Variant = company.get("owner", company.get("owner_id", null))
	return typeof(type_value) == TYPE_INT and int(type_value) == 7 and typeof(owner_value) == TYPE_INT and int(owner_value) == actor


func _public_limit(method: String, action: String, actor: int) -> int:
	if _core == null or not _core.has_method(method):
		return 0
	var value: Variant = _call_with_actor(method, [action, actor])
	if typeof(value) in [TYPE_INT, TYPE_FLOAT] and typeof(value) != TYPE_BOOL and is_finite(float(value)) and floor(float(value)) == float(value) and float(value) >= 0.0:
		return int(value)
	return 0


func _call_with_actor(method: String, args: Array) -> Variant:
	if _core == null or not _core.has_method(method):
		return null
	var count := _method_argument_count(_core, method)
	var call_args: Array = []
	for index in mini(count, args.size()):
		call_args.append(args[index])
	return _core.callv(method, call_args)


func _method_argument_count(object: Object, method: String) -> int:
	for method_value in object.get_method_list():
		if typeof(method_value) == TYPE_DICTIONARY and str(method_value.get("name", "")) == method:
			var args: Variant = method_value.get("args", [])
			return args.size() if typeof(args) == TYPE_ARRAY else 0
	return 0


func _configure_panel(model: Dictionary) -> void:
	if bank_panel == null:
		return
	var previous_action := ""
	var previous_amount := 0
	if _open and bank_panel.visible and bank_panel.has_method("current_action"):
		previous_action = str(bank_panel.call("current_action"))
		if bank_panel.has_method("current_amount"):
			previous_amount = int(bank_panel.call("current_amount"))
	var next_signature := JSON.stringify(model)
	if next_signature == _model_signature and bank_panel.visible:
		return
	_model_signature = next_signature
	if bank_panel.has_method("set_visuals"):
		bank_panel.call("set_visuals", _visuals)
	if bank_panel.has_method("set_view_model"):
		bank_panel.call("set_view_model", model)
	if model.get("entry_mode", "atm") == "atm":
		bank_panel.position = ATM_POSITION
		bank_panel.size = ATM_SIZE
		bank_panel.custom_minimum_size = ATM_SIZE
	else:
		bank_panel.position = BANK_POSITION
		bank_panel.size = BANK_SIZE
		bank_panel.custom_minimum_size = BANK_SIZE
	if not previous_action.is_empty() and bank_panel.has_method("action_allowed") and bool(bank_panel.call("action_allowed", previous_action)):
		bank_panel.call("select_action", previous_action)
		if previous_amount > 0:
			bank_panel.call("set_amount_text", str(previous_amount))
	bank_panel.show()


func _on_action_requested(action: String, amount: int) -> void:
	if not is_open() or _action_pending:
		return
	_action_pending = true
	var result: Variant = null
	if invoke_game.is_valid():
		result = invoke_game.call("choose_action", [action, {"amount": amount}])
	if typeof(result) != TYPE_DICTIONARY:
		result = {"ok": false, "message": "模擬核心未回傳有效結果。"}
	var generation := _generation
	call_deferred("_finish_action", result, generation)


func _finish_action(result: Dictionary, generation: int) -> void:
	if generation != _generation:
		return
	_action_pending = false
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("message", "銀行操作未完成。")))
		if handle_result.is_valid():
			handle_result.call(result)
		return
	_clear_error()
	if handle_result.is_valid():
		handle_result.call(result)
	var latest: Variant = result.get("state", null)
	if typeof(latest) == TYPE_DICTIONARY and _open:
		_snapshot = latest.duplicate(true)
		var token := _read_pending_token(_core)
		if _valid_ingress(token, _snapshot) and token == _active_token:
			_configure_panel(_build_model(token, _snapshot, _panel_mode == "loan"))


func _on_panel_closed() -> void:
	if not _open or _action_pending:
		return
	if _entry_kind == "pass":
		_open = false
		bank_panel.hide()
		hide()
		_defer_core_close("resume_bank_visit")
		return
	if _entry_kind == "landing" and _panel_mode == "atm":
		bank_panel.hide()
		_model_signature = ""
		call_deferred("_show_landing_front", _generation)
		return
	if _entry_kind == "landing" and _panel_mode == "loan":
		_open = false
		bank_panel.hide()
		hide()
		_defer_core_close("complete_bank_visit")


func _show_landing_front(generation: int) -> void:
	if generation != _generation or not _open or _entry_kind != "landing":
		return
	var live_token := _read_pending_token(_core)
	if live_token != _active_token or not _valid_ingress(live_token, _snapshot):
		_cancel_local()
		return
	_panel_mode = "loan"
	var model := _build_model(_active_token, _snapshot, true)
	_configure_panel(model)
	_clear_error()
	show()
	bank_panel.show()


func _defer_core_close(method: String) -> void:
	var generation := _generation
	call_deferred("_invoke_core_close", method, generation)


func _invoke_core_close(method: String, generation: int) -> void:
	if generation != _generation:
		return
	var result: Variant = null
	if _core != null and _core.has_method(method):
		result = _core.call(method)
	else:
		result = {"ok": false, "message": "模擬核心缺少銀行結束介面。"}
	if typeof(result) != TYPE_DICTIONARY:
		result = {"ok": false, "message": "模擬核心未回傳有效結果。"}
	if handle_result.is_valid():
		handle_result.call(result)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("message", "銀行操作未完成。")))


func _show_error(message: String) -> void:
	if error_label == null:
		return
	error_label.text = message
	error_label.show()


func _clear_error() -> void:
	if error_label == null:
		return
	error_label.text = ""
	error_label.hide()


func _canonical_edition(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return "Game"
	var normalized := str(value).to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	if normalized in ["mj", "multiversejourney", "multiverse_journey", "journey"]:
		return "MultiverseJourney"
	return "Game"


func _canonical_action(value: String) -> String:
	var normalized := value.to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	if normalized in ["deposit", "atm_deposit", "bank_deposit", "存款"]:
		return "deposit"
	if normalized in ["withdraw", "atm_withdraw", "bank_withdraw", "提款"]:
		return "withdraw"
	if normalized in ["take_loan", "borrow", "loan_borrow", "apply_loan", "申請貸款"]:
		return "take_loan"
	if normalized in ["repay_loan", "repay", "loan_repay", "償還貸款"]:
		return "repay_loan"
	if normalized in ["take_special_finance", "special_finance", "special_borrow", "working_capital", "週轉現金"]:
		return "take_special_finance"
	if normalized in ["repay_special_finance", "special_repay", "repay_special", "歸還款項"]:
		return "repay_special_finance"
	return ""


func _action_aliases(action: String) -> Array:
	match action:
		"deposit": return ["deposit", "atm_deposit", "bank_deposit", "存款"]
		"withdraw": return ["withdraw", "atm_withdraw", "bank_withdraw", "提款"]
		"take_loan": return ["take_loan", "borrow", "loan_borrow", "apply_loan", "申請貸款"]
		"repay_loan": return ["repay_loan", "repay", "loan_repay", "償還貸款"]
		"take_special_finance": return ["take_special_finance", "special_finance", "special_borrow", "working_capital", "週轉現金"]
		"repay_special_finance": return ["repay_special_finance", "special_repay", "repay_special", "歸還款項"]
	return []
