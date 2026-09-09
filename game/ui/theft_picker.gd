extends VBoxContainer

## Presentation of the current action's legal inventory choices. The core
## validates the selected identity again when the user confirms the action.
signal selection_changed(available: bool)
const Catalogue = preload("res://game/content/original_inventory.gd")
var _targets: OptionButton
var _items: OptionButton
var _warning: Label
var _choices: Array = []

func _init() -> void:
	name = "TheftPicker_搶奪"
	var row := HBoxContainer.new()
	add_child(row)
	_targets = OptionButton.new()
	_targets.name = "TheftTarget_搶奪"
	_targets.custom_minimum_size = Vector2(110, 34)
	_targets.add_theme_font_size_override("font_size", 11)
	row.add_child(_targets)
	_items = OptionButton.new()
	_items.name = "TheftItem_搶奪"
	_items.custom_minimum_size = Vector2(170, 34)
	_items.add_theme_font_size_override("font_size", 11)
	row.add_child(_items)
	_warning = Label.new()
	_warning.name = "TheftCapacity_搶奪"
	_warning.add_theme_font_size_override("font_size", 10)
	_warning.add_theme_color_override("font_color", Color("#e2b25b"))
	add_child(_warning)
	_targets.item_selected.connect(func(_index: int): _refresh_items())
	_items.item_selected.connect(func(_index: int): _refresh_warning())

func configure(snapshot: Dictionary, choices: Array, visible_nodes: Array) -> void:
	_choices.clear()
	_targets.clear()
	var players: Array = snapshot.get("players", [])
	var actor_id := int(snapshot.get("current_player", -1))
	var seen: Dictionary = {}
	for value in choices:
		if not value is Dictionary:
			continue
		var target_id := int(value.get("target_id", -1))
		if target_id < 0 or target_id >= players.size() or target_id == actor_id:
			continue
		var player: Dictionary = players[target_id]
		if not player.get("alive", false) or not visible_nodes.has(int(player.get("position", -1))):
			continue
		_choices.append(value.duplicate(true))
		if not seen.has(target_id):
			seen[target_id] = true
			_targets.add_item(str(player.get("name", "玩家 %d" % (target_id + 1))), target_id)
	_targets.disabled = _targets.item_count == 0
	if _targets.disabled:
		_targets.add_item("畫面內沒有可用對手", -1)
		_targets.tooltip_text = "可關閉背包後平移或縮放地圖。"
	_refresh_items()

func selection() -> Dictionary:
	if _targets.disabled or _items.disabled or _items.selected < 0:
		return {}
	var value: Variant = _items.get_item_metadata(_items.selected)
	if not value is Dictionary:
		return {}
	return {"target_id": _targets.get_selected_id(), "item_kind": str(value.item_kind), "item_id": str(value.item_id)}

func _refresh_items() -> void:
	_items.clear()
	for choice in _choices:
		if int(choice.get("target_id", -1)) != _targets.get_selected_id():
			continue
		var kind := str(choice.get("item_kind", ""))
		var item_id := str(choice.get("item_id", ""))
		var record: Dictionary = Catalogue.card(item_id) if kind == "card" else Catalogue.tool(item_id)
		var label := "%s · %s ×%d" % ["卡片" if kind == "card" else "道具", str(record.get("name", item_id)), int(choice.get("quantity", 1))]
		_items.add_item(label)
		_items.set_item_metadata(_items.item_count - 1, choice.duplicate(true))
	_items.disabled = _items.item_count == 0
	if _items.disabled:
		_items.add_item("沒有可搶奪物品", -1)
	_refresh_warning()

func _refresh_warning() -> void:
	var full := false
	if not _items.disabled and _items.selected >= 0:
		var value: Variant = _items.get_item_metadata(_items.selected)
		full = value is Dictionary and bool(value.get("capacity_full", false))
	_warning.text = "持有已滿：物品不會加入背包，仍會消耗搶奪卡。" if full else ""
	_warning.visible = full
	selection_changed.emit(not selection().is_empty())
