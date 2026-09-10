extends SceneTree

const GameState = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
const BaseMap = preload("res://tests/fixtures/original_map_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _legacy_options(version: int) -> Dictionary:
	var options := {
		"start_date": {"year": 1998, "month": 1, "day": 1},
		"character_ids": [0, 1],
	}
	if version >= 4:
		options["original_inventory"] = true
	if version >= 5:
		options["original_facilities"] = true
	if version >= 6:
		options["original_gods"] = true
	return options


func _legacy_game(version: int) -> Object:
	if version == 1:
		return GameState.new_game(61001, 2)
	var normalized := Maps.normalize_map(BaseMap.make())
	if not bool(normalized.get("ok", false)):
		return null
	var definition: Dictionary = normalized.get("definition", {})
	if version == 2:
		return GameState.new_game_on_board(61002, 2, definition)
	return GameState.new_game_on_board(61000 + version, 2, definition, _legacy_options(version))


func _legacy_snapshot(version: int) -> Dictionary:
	var game := _legacy_game(version)
	if game == null:
		return {}
	return game.to_dict()


func _set_human_game(ui: Control, seed_value: int) -> Object:
	var game := GameState.new_game(seed_value, 2)
	game.state.phase = "await_roll"
	game.state.current_player = 0
	game._set_action_options(0)
	game._sync_state()
	ui.game_state = game
	ui._refresh_from_state()
	return game


func _set_ai_game(ui: Control, seed_value: int) -> Object:
	var game := GameState.new_game(seed_value, 2)
	game.state.phase = "await_roll"
	game.state.current_player = 1
	game._set_action_options(1)
	game._sync_state()
	ui.game_state = game
	ui._refresh_from_state()
	return game


func _open_legacy_modal(ui: Control, version: int) -> Dictionary:
	if ui.legacy_save_dialog != null:
		ui.legacy_save_dialog.hide()
	var snapshot := _legacy_snapshot(version)
	var restored: Object = GameState.from_dict(snapshot)
	ui._pending_legacy_load_snapshot = snapshot.duplicate(true)
	ui._pending_legacy_load_state = restored
	ui._show_legacy_save_dialog(snapshot)
	return snapshot


func _test_legacy_versions(ui: Control) -> void:
	for version in range(1, 7):
		var snapshot := _legacy_snapshot(version)
		_expect(not snapshot.is_empty(), "legacy v%d fixture exists" % version)
		_expect(GameState.validate_save(snapshot).get("ok", false), "legacy v%d fixture validates" % version)
		_expect(ui._is_legacy_market_snapshot(snapshot), "legacy v%d save requires an explicit market choice" % version)
		var shown := _open_legacy_modal(ui, version)
		_expect(ui.legacy_save_dialog.visible, "legacy v%d opens a confirmation dialog" % version)
		_expect(str(ui.legacy_save_dialog.dialog_text).contains("v%d" % version), "legacy v%d dialog identifies its save version" % version)
		_expect(str(ui.legacy_save_dialog.dialog_text).contains("繼續") and str(ui.legacy_save_dialog.dialog_text).contains("取消"), "legacy v%d dialog exposes continue and cancel choices" % version)
		ui._cancel_legacy_save_load()
		_expect(ui._pending_legacy_load_snapshot.is_empty(), "legacy v%d cancellation clears the pending load" % version)
		_expect(shown.get("version", -1) == version, "legacy v%d fixture keeps its original version" % version)
		ui.legacy_save_dialog.hide()


func _test_legacy_continue_and_labels(ui: Control) -> void:
	var current := _set_human_game(ui, 61101)
	var before: String = current.to_json()
	var snapshot := _open_legacy_modal(ui, 4)
	var restored: Object = ui._pending_legacy_load_state
	ui._confirm_legacy_save_load()
	_expect(ui.game_state == restored, "continuing a legacy load applies the prepared save")
	_expect(ui.game_state != current and ui.state.get("version", -1) == 4, "continuing keeps the legacy save version")
	_expect(ui._market_symbols_from_snapshot(snapshot).size() == 3, "legacy snapshot retains exactly three stock symbols")
	_expect(ui._stock_symbols_for_ui() == ["tech", "transport", "energy"], "legacy market UI retains its three source symbols")
	_expect(str(ui.market_mode_label.text).contains("舊版三股市"), "legacy market mode is visible in the header")
	_expect(current.to_json() == before, "pre-load game object is unchanged until explicit continuation")


func _test_modal_guards(ui: Control) -> void:
	var human := _set_human_game(ui, 61102)
	var before: String = human.to_json()
	_open_legacy_modal(ui, 1)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	space.echo = false
	ui._unhandled_input(space)
	_expect(human.to_json() == before, "legacy modal blocks space-roll input")
	_expect(not ui._presentation_busy, "legacy modal blocks delayed movement presentation")
	ui._cancel_legacy_save_load()
	ui.legacy_save_dialog.hide()

	human = _set_human_game(ui, 61103)
	before = human.to_json()
	_open_legacy_modal(ui, 1)
	var result: Dictionary = ui._invoke_game("roll")
	_expect(not bool(result.get("ok", false)), "legacy modal rejects direct game actions")
	_expect(human.to_json() == before, "legacy modal keeps direct action state and RNG unchanged")
	ui._cancel_legacy_save_load()
	ui.legacy_save_dialog.hide()

	var ai := _set_ai_game(ui, 61104)
	before = ai.to_json()
	_open_legacy_modal(ui, 1)
	ui._ai_pending = false
	ui._maybe_schedule_ai_turn()
	_expect(not ui._ai_pending, "legacy modal blocks new AI turn scheduling")
	ui._on_ai_timer_timeout()
	_expect(ai.to_json() == before, "legacy modal blocks an already queued AI turn")
	ui._cancel_legacy_save_load()
	ui.legacy_save_dialog.hide()

	human = _set_human_game(ui, 61105)
	var before_state: Dictionary = human.to_dict()
	_open_legacy_modal(ui, 1)
	var changed := before_state.duplicate(true)
	changed["turn"] = int(changed.get("turn", 1)) + 1
	ui._handle_result({"state": changed})
	_expect(ui.state == before_state, "legacy modal blocks delayed movement state refresh")
	ui._cancel_legacy_save_load()
	ui.legacy_save_dialog.hide()


func _test_modal_cancellation(ui: Control) -> void:
	for route in ["cancel", "close", "escape"]:
		var current := _set_human_game(ui, 61110 + route.length())
		var before: String = current.to_json()
		_open_legacy_modal(ui, 2)
		if route == "cancel":
			ui._cancel_legacy_save_load()
		elif route == "close":
			ui._legacy_save_dialog_close_requested()
		else:
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			escape.echo = false
			ui._unhandled_input(escape)
		_expect(ui._pending_legacy_load_snapshot.is_empty(), "legacy %s clears pending state" % route)
		_expect(current.to_json() == before, "legacy %s preserves JSON, RNG and phase" % route)
		ui.legacy_save_dialog.hide()


func _complete_catalog_payload() -> Dictionary:
	var raw := BaseMap.make()
	raw.nodes[5].type_and_idx = 6001
	raw.nodes[5].event_code = 0
	raw.companies = [{"id": 1, "display_name": "測試企業", "company_type": 3, "stock_index": 0,
		"stock_value": 400000, "toll_fee": 150, "monthly_profit": 0, "cumulative_profit": 0,
		"treasury": 5000, "source_owner": 0}]
	raw.stock_rows = []
	for index in range(12):
		raw.stock_rows.append({"index": index, "name": "股票 %02d" % (index + 1),
			"company_id": 1 if index == 0 else 0, "market_supply": 5000 if index == 0 else 10000,
			"turn_supply": 0, "base_price": 100.0, "previous_price": 100.0, "price": 100.0,
			"volatility": 1.0, "momentum": 0.0, "shock": 0.0, "suspension": 0, "event": 0})
	return {"schema": "richman4.map-catalog/v1", "version": 1, "count": 1, "maps": [raw]}


func _write_json(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()


func _read_file_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _test_disk_cancellation(ui: Control) -> void:
	# Use an isolated user:// fixture; the owner save path is left to the native
	# wrapper and is never opened by this headless acceptance test.
	var path := "user://issue100-legacy-cancel.json"
	var had_original := FileAccess.file_exists(path)
	var original_text := _read_file_text(path) if had_original else ""
	var disk_payload := _legacy_snapshot(1)
	_write_json(path, disk_payload)
	var before_disk := _read_file_text(path)
	var current := _set_human_game(ui, 61130)
	var before_state: String = current.to_json()
	ui._load_game_from_path(path)
	_expect(ui.legacy_save_dialog.visible, "isolated legacy disk load opens a choice modal")
	ui._cancel_legacy_save_load()
	_expect(_read_file_text(path) == before_disk, "cancelling legacy disk load leaves the save bytes unchanged")
	_expect(current.to_json() == before_state, "cancelling legacy disk load leaves the current game unchanged")
	if had_original:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(original_text)
		restore.close()
	else:
		DirAccess.remove_absolute(path)


func _test_catalog_gate_and_complete_market(ui: Control) -> void:
	ui._set_development_path(false)
	ui._load_map_catalog("user://issue100-catalog-missing.json")
	_expect(not ui._map_catalog_ok and ui._map_catalog.is_empty(), "production path rejects a missing catalog without a demo map")
	_expect(ui.new_game_confirm_button.disabled, "production path disables new game without original content")
	var blocked_before: Dictionary = ui._read_snapshot().duplicate(true)
	_expect(not ui._new_game(61120, 2, ui._selected_map_definition), "production path blocks new game without original content")
	_expect(ui._read_snapshot() == blocked_before, "blocked production entry preserves the current game")
	_expect(str(ui.map_catalog_status_label.text).contains("無法開始正常對局"), "production block explains the missing content action")

	ui._set_development_path(true)
	ui._load_map_catalog("user://issue100-catalog-missing.json")
	_expect(ui._map_catalog.size() == 1 and str(ui.map_catalog_status_label.text).contains("開發路徑"), "development fallback is explicitly labelled")
	_expect(ui._new_game(61121, 2, ui._selected_map_definition), "development fallback remains usable for tests")

	var path := "user://issue100-complete-catalog.json"
	_write_json(path, _complete_catalog_payload())
	ui._set_development_path(false)
	ui._load_map_catalog(path)
	_expect(ui._map_catalog_complete and ui._map_catalog.size() == 1, "complete catalog is recognized at the UI selection boundary")
	_expect(ui._new_game(61122, 2, ui._selected_map_definition), "complete catalog starts a normal source map")
	_expect(int(ui.state.get("version", 0)) == GameState.COMPANY_SAVE_VERSION, "normal complete catalog enables company market capability")
	_expect(ui._stock_symbols_for_ui().size() == 12, "normal complete catalog exposes all twelve source stocks")
	_expect(str(ui.market_mode_label.text).contains("原版十二股"), "normal complete catalog is visible as twelve-stock mode")
	DirAccess.remove_absolute(path)


func _run() -> void:
	var ui: Control = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	_test_legacy_versions(ui)
	_test_legacy_continue_and_labels(ui)
	_test_modal_guards(ui)
	_test_modal_cancellation(ui)
	_test_disk_cancellation(ui)
	_test_catalog_gate_and_complete_market(ui)
	ui.queue_free()
	await create_timer(0.15).timeout
	print("Market entry UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
