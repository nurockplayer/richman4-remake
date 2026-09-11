extends Control
class_name RichmanSourceTrusteeController

## S04 host boundary for the source trustee presenter.
##
## This controller owns a detached row snapshot only.  It deliberately does
## not know GameState, save files, RNG, or the AI turn dispatcher.  A later
## host may consume accepted rows through the public signal.

const DialogScript := preload("res://game/ui/source_trustee_dialog.gd")
const OriginalVisualsScript := preload("res://game/platform/original_visuals.gd")
const REFERENCE_SIZE := Vector2(640.0, 480.0)
const VALID_EDITIONS := ["Game", "MultiverseJourney"]

signal accepted(rows: Array)
signal cancelled

var dialog: Control
var visual_accessor: Variant = null

var _rows: Array = []
var _current_player_id := -1
var _edition := ""
var _manifest_path := ""
var _open := false
var _generation := 0


func _init() -> void:
	name = "SourceTrusteeController"
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	dialog = DialogScript.new()
	dialog.name = "SourceTrusteeDialog"
	add_child(dialog)
	_connect_dialog()
	hide()


func _ready() -> void:
	hide()


## Configure and open one detached trustee session.  The caller owns the
## input rows; all values are copied before the presenter can mutate them.
## `manifest_path` is optional and is used only to construct the bounded
## private visual resolver.  It is never written or copied into the project.
func configure(rows: Array, current_player_id: int, edition: String, manifest_path: Variant = "") -> bool:
	var normalized := _normalize_rows(rows)
	if normalized.is_empty() or edition not in VALID_EDITIONS:
		return false
	if not _contains_player(normalized, current_player_id):
		return false
	_generation += 1
	_rows = normalized
	_current_player_id = current_player_id
	_edition = edition
	_manifest_path = str(manifest_path) if manifest_path is String else ""
	if manifest_path is Object or (manifest_path is String and not str(manifest_path).is_empty()):
		visual_accessor = _new_visual_accessor(manifest_path)
	if dialog.has_method("set_visual_accessor"):
		dialog.call("set_visual_accessor", visual_accessor)
	if not bool(dialog.call("configure", _rows, _current_player_id, _edition)):
		_open = false
		hide()
		return false
	_open = true
	show()
	grab_focus()
	return true


func is_open() -> bool:
	return _open and is_instance_valid(dialog) and bool(dialog.call("is_open"))


func current_player_id() -> int:
	return _current_player_id


func edition() -> String:
	return _edition


func manifest_path() -> String:
	return _manifest_path


func rows() -> Array:
	return _rows.duplicate(true)


func draft_rows() -> Array:
	if is_instance_valid(dialog) and dialog.has_method("draft_rows"):
		return dialog.call("draft_rows")
	return rows()


func selected_player_id() -> int:
	if is_instance_valid(dialog) and dialog.has_method("selected_player_id"):
		return int(dialog.call("selected_player_id"))
	return -1


func select_player(player_id: int) -> bool:
	if not is_instance_valid(dialog) or not dialog.has_method("select_player"):
		return false
	return bool(dialog.call("select_player", player_id))


func confirm() -> bool:
	if not is_open() or not is_instance_valid(dialog) or not dialog.has_method("accept_dialog"):
		return false
	return bool(dialog.call("accept_dialog"))


func set_visual_accessor(accessor: Variant) -> void:
	visual_accessor = accessor
	if is_instance_valid(dialog) and dialog.has_method("set_visual_accessor"):
		dialog.call("set_visual_accessor", accessor)


func set_visuals(accessor: Variant) -> void:
	set_visual_accessor(accessor)


func cancel() -> bool:
	if not is_open():
		return false
	return bool(dialog.call("cancel_dialog"))


func _connect_dialog() -> void:
	if dialog.has_signal("accepted"):
		dialog.connect("accepted", Callable(self, "_on_dialog_accepted"))
	if dialog.has_signal("cancelled"):
		dialog.connect("cancelled", Callable(self, "_on_dialog_cancelled"))


func _on_dialog_accepted(value: Array) -> void:
	if not _open:
		return
	_open = false
	_rows = value.duplicate(true)
	hide()
	accepted.emit(_rows.duplicate(true))


func _on_dialog_cancelled() -> void:
	if not _open:
		return
	_open = false
	hide()
	cancelled.emit()


func _new_visual_accessor(value: Variant) -> Variant:
	if value is Object:
		return value
	var path := str(value)
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var resolver: Variant = OriginalVisualsScript.new(path)
	return resolver


func _contains_player(rows_value: Array, player_id: int) -> bool:
	for row in rows_value:
		if int(row.get("player_id", -1)) == player_id:
			return true
	return false


func _normalize_rows(value: Array) -> Array:
	if value.is_empty() or value.size() > 4:
		return []
	var result: Array = []
	var ids: Dictionary = {}
	for raw in value:
		if not raw is Dictionary:
			return []
		var source: Dictionary = raw as Dictionary
		var player_id_value: Variant = source.get("player_id", null)
		if not (player_id_value is int) or int(player_id_value) < 0 or int(player_id_value) > 3:
			return []
		var player_id := int(player_id_value)
		if ids.has(player_id):
			return []
		ids[player_id] = true
		var personality := int(source.get("personality", 1))
		if personality < 0 or personality > 2:
			return []
		result.append({
			"player_id": player_id,
			"name": str(source.get("name", "玩家%d" % (player_id + 1))),
			"trustee": bool(source.get("trustee", false)),
			"use_cards": bool(source.get("use_cards", true)),
			"use_tools": bool(source.get("use_tools", true)),
			"personality": personality,
			"cash_ratio": _ratio(source.get("cash_ratio", 50)),
			"stock_ratio": _ratio(source.get("stock_ratio", 50)),
		})
	return result


func _ratio(value: Variant) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return 50
	return clampi(int(round(float(value) / 10.0) * 10), 0, 100)

func set_character_ids(value: Dictionary) -> void:
	dialog.set_character_ids(value)
