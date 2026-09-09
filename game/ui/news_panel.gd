extends PopupPanel

## Presents completed simulation results. Closing never mutates game state.
var _summary: RichTextLabel
var _last_draw := -1

func _init() -> void:
	name = "NewsPopup"
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#203447")
	panel.border_color = Color("#54748a")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(16)
	add_theme_stylebox_override("panel", panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var title := Label.new()
	title.text = "即時新聞"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#e2b25b"))
	column.add_child(title)
	_summary = RichTextLabel.new()
	_summary.name = "NewsSummary"
	_summary.bbcode_enabled = false
	_summary.custom_minimum_size = Vector2(0, 160)
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary.add_theme_font_size_override("normal_font_size", 17)
	_summary.add_theme_color_override("default_color", Color("#e8f0f4"))
	column.add_child(_summary)
	var close := Button.new()
	close.name = "CloseNews"
	close.text = "返回棋盤"
	close.custom_minimum_size = Vector2(0, 42)
	close.pressed.connect(hide)
	column.add_child(close)

func sync_snapshot(snapshot: Dictionary) -> void:
	var news: Variant = snapshot.get("news", {})
	if typeof(news) != TYPE_DICTIONARY or news.get("last", {}).is_empty():
		_last_draw = -1
		hide()
		return
	var last: Dictionary = news.last
	# Read the last *applied* draw, since a no-eligible scan preserves news.last.
	# Event history is saved, so refreshing or loading never reapplies effects.
	var applied_draw := -1
	var events: Array = snapshot.get("event_log", [])
	for index in range(events.size() - 1, -1, -1):
		var event: Variant = events[index]
		if typeof(event) == TYPE_DICTIONARY and event.get("type", "") == "news_applied":
			applied_draw = int(event.get("draw_count", -1))
			break
	if applied_draw < 0 or applied_draw == _last_draw:
		return
	_last_draw = applied_draw
	_summary.text = str(last.get("summary", ""))
	var viewport_size: Vector2 = get_tree().root.get_visible_rect().size
	popup_centered(Vector2i(mini(660, int(viewport_size.x) - 48), mini(400, int(viewport_size.y) - 48)))
