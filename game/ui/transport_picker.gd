extends HBoxContainer

## The transport tool's category, target and destination selector.
##
## This presentation component owns all three selections and emits a fresh
## validity value whenever any selection changes.  GameState remains the
## authority and validates the selected IDs again on confirmation.
signal selection_changed(available: bool)

const OriginalGods = preload("res://game/content/original_gods.gd")
const TRANSPORT_KINDS := ["property", "facility", "player", "god"]

var _game_state: Object
var _snapshot: Dictionary = {}
var _kind: OptionButton
var _target: OptionButton
var _destination: OptionButton


func _init() -> void:
	name = "TransportPicker"
	_kind = OptionButton.new()
	_kind.name = "TransportKind"
	_kind.custom_minimum_size = Vector2(92.0, 34.0)
	_kind.add_theme_font_size_override("font_size", 11)
	add_child(_kind)
	_target = OptionButton.new()
	_target.name = "TransportTarget"
	_target.custom_minimum_size = Vector2(164.0, 34.0)
	_target.add_theme_font_size_override("font_size", 11)
	add_child(_target)
	_destination = OptionButton.new()
	_destination.name = "TransportDestination"
	_destination.custom_minimum_size = Vector2(164.0, 34.0)
	_destination.add_theme_font_size_override("font_size", 11)
	add_child(_destination)
	_kind.item_selected.connect(func(_index: int) -> void:
		_refresh_targets()
	)
	_target.item_selected.connect(func(_index: int) -> void:
		_refresh_destinations()
	)
	_destination.item_selected.connect(func(_index: int) -> void:
		_emit_validity()
	)


func configure(game_state: Object, snapshot: Dictionary) -> void:
	_game_state = game_state
	_snapshot = snapshot.duplicate(true)
	_kind.clear()
	for kind_index in range(TRANSPORT_KINDS.size()):
		_kind.add_item(_kind_label(TRANSPORT_KINDS[kind_index]), kind_index)
	_kind.select(0)
	_refresh_targets()


func selection() -> Dictionary:
	if _kind == null or _target == null or _destination == null:
		return {}
	if _kind.disabled or _target.disabled or _destination.disabled:
		return {}
	var kind_index := _kind.get_selected_id()
	var target_id := _target.get_selected_id()
	var destination_id := _destination.get_selected_id()
	if kind_index < 0 or kind_index >= TRANSPORT_KINDS.size() or target_id < 0 or destination_id < 0:
		return {}
	return {
		"target_kind": TRANSPORT_KINDS[kind_index],
		"target_id": target_id,
		"destination_id": destination_id,
	}


func _refresh_targets() -> void:
	_target.clear()
	_target.disabled = true
	_destination.clear()
	_destination.disabled = true
	var kind_index := _kind.get_selected_id()
	if kind_index < 0 or kind_index >= TRANSPORT_KINDS.size() or _game_state == null or not _game_state.has_method("transport_targets"):
		_target.add_item("沒有可用目標", -1)
		_destination.add_item("沒有可用目的地", -1)
		_emit_validity()
		return
	var targets: Variant = _game_state.call("transport_targets", TRANSPORT_KINDS[kind_index])
	if not targets is Array or targets.is_empty():
		_target.add_item("沒有可用目標", -1)
		_destination.add_item("沒有可用目的地", -1)
		_emit_validity()
		return
	for target_value in targets:
		var target_id := int(target_value)
		_target.add_item(_target_label(TRANSPORT_KINDS[kind_index], target_id), target_id)
	_target.disabled = false
	_target.select(0)
	_refresh_destinations()


func _refresh_destinations() -> void:
	_destination.clear()
	_destination.disabled = true
	var kind_index := _kind.get_selected_id()
	var target_id := _target.get_selected_id()
	if _target.disabled or kind_index < 0 or kind_index >= TRANSPORT_KINDS.size() or target_id < 0 or _game_state == null or not _game_state.has_method("transport_destinations"):
		_destination.add_item("沒有可用目的地", -1)
		_emit_validity()
		return
	var destinations: Variant = _game_state.call("transport_destinations", TRANSPORT_KINDS[kind_index], target_id)
	if not destinations is Array or destinations.is_empty():
		_destination.add_item("沒有可用目的地", -1)
		_emit_validity()
		return
	for destination_value in destinations:
		var destination_id := int(destination_value)
		_destination.add_item(_node_label(destination_id), destination_id)
	_destination.disabled = false
	_destination.select(0)
	_emit_validity()


func _emit_validity() -> void:
	selection_changed.emit(not selection().is_empty())


func _kind_label(kind: String) -> String:
	return {
		"property": "住宅",
		"facility": "設施",
		"player": "玩家",
		"god": "神明",
	}.get(kind, kind)


func _target_label(kind: String, target_id: int) -> String:
	if kind == "player":
		var players: Variant = _snapshot.get("players", [])
		if players is Array and target_id >= 0 and target_id < players.size() and players[target_id] is Dictionary:
			return str(players[target_id].get("name", "玩家 %d" % (target_id + 1)))
		return "玩家 %d" % (target_id + 1)
	if kind == "god":
		return OriginalGods.name_for(target_id)
	return _node_label(target_id)


func _node_label(node_id: int) -> String:
	var board: Variant = _snapshot.get("board", [])
	if not board is Array or node_id < 0 or node_id >= board.size() or not board[node_id] is Dictionary:
		return "節點 %d" % (node_id + 1)
	return "%s · 節點 %d" % [str(board[node_id].get("name", "道路")), node_id + 1]
