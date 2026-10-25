extends SceneTree
## Full-match MainUI soak: drives the real MainUI (not only the simulation
## helper) through complete matches and fails on a soft-lock or an invalid save.
##
## Every seed plays through the same entry points a player uses: the source
## shell's GO/YES/NO buttons and route buttons (pressed through their real
## signals and required to be visible and enabled), the payment/auction/trap
## responses, and the presenter modals (bank, monthly statements, SALE, lottery,
## minigame). Presentation is never skipped: movement has to deliver its own
## movement_finished callback, or the stall detector fails the run. The only
## direct model call is the minigame clock tick the presenter itself drives;
## pointer input inside minigames is covered by the dedicated minigame tests.
## Human matches are bounded soaks that stop at the turn cap; the all-AI seed
## carries a day limit and must reach game_over with a winner.
##
## Checkpoints assert:
##   * the simulation makes visible progress within a bounded number of steps;
##   * GameState.validate_save accepts the live snapshot;
##   * a SaveSlots write/read round-trip restores an identical snapshot;
##   * every match writes a fresh, valid AUTO checkpoint for its own seed.
##
## RICHMAN4_SOAK_LONG=1 runs more seeds and a larger turn cap. When
## RICHMAN4_MAP_CATALOG is set, one match also runs on the first playable real
## source map with every original capability the map supports (skipped
## otherwise, like the other catalog gates).
##
## RICHMAN4_USER_ROOT is required: the soak writes save slots and autosave
## checkpoints, so it must never fall back to the owner's user:// directory.

const GameState = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
const SaveSlots = preload("res://game/platform/save_slots.gd")
const OriginalMaps = preload("res://game/content/original_maps.gd")
const CompanyFixture = preload("res://tests/fixtures/company_fixture.gd")
const FinancialPresentation = preload("res://game/ui/financial_presentation.gd")
const AuctionPresentation = preload("res://game/ui/auction_presentation.gd")
const SourceSale = preload("res://game/core/source_sale_flow.gd")

const CI_SEEDS := [20261026, 424242, 777]
const LONG_SEEDS := [20261026, 424242, 777, 13579, 86420]
const CI_TURN_CAP := 360
const LONG_TURN_CAP := 1500
const CATALOG_TURN_CAP := 480
const CHECKPOINT_STEPS := 24
const STALL_STEPS := 220

var checks := 0
var failures := 0
var _ui: Control
var _scratch_root := ""
var _round_trip_dir := ""
var _saw_autosave := false
var _match_saw_autosave := false
var _label := ""
var _steps := 0
var _last_progress := ""
var _last_progress_step := 0
var _surrender_turn := -1
var _surrender_done := false
var _sale_probe_done := false
var _skip_action_turn := -1


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SOAK FAIL [%s]: %s" % [_label, message])


func _run() -> void:
	_scratch_root = OS.get_environment("RICHMAN4_USER_ROOT")
	if _scratch_root.is_empty():
		push_error("RICHMAN4_USER_ROOT must point at a throwaway directory; the soak never writes the owner's saves.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_scratch_root)
	_ui = MainScene.instantiate()
	root.add_child(_ui)
	if _ui.audio_controller != null:
		_ui.audio_controller.call("stop")
	# The soak owns every advance: AI turns, modals and presentation are driven
	# explicitly so a silent stall can never be hidden by a scheduled timer. The
	# 0.82 s AI timer is only created from MainUI._process, so disabling it also
	# guarantees no asynchronous turn competes with the manual driver.
	_ui.set_process(false)
	_ui._set_development_path(true)
	# Presentation is real, not skipped: movement must deliver its own
	# movement_finished callback. Compress its clock so a full match stays fast.
	_ui._source_settings["speed"] = 2
	Engine.time_scale = 30.0

	var long_run := OS.get_environment("RICHMAN4_SOAK_LONG") == "1"
	var seeds: Array = LONG_SEEDS if long_run else CI_SEEDS
	var turn_cap := LONG_TURN_CAP if long_run else CI_TURN_CAP
	var definition: Dictionary = CompanyFixture.construction_definition()
	_check(not definition.is_empty(), "fixture map normalizes for the soak")
	if not definition.is_empty():
		for index in range(seeds.size()):
			var seed_value := int(seeds[index])
			# Seed 0 keeps one human through the match; seed 1 concedes so the
			# SURRENDER path is soaked too; seed 2 is all-AI scheduling with a
			# day limit, so at least one match reaches game_over and a winner.
			var flags := [true, false, false, false]
			var all_ai := index == 2
			if all_ai:
				flags = [false, false, false, false]
			_surrender_turn = 40 if index == 1 else -1
			_surrender_done = false
			_label = "fixture seed %d" % seed_value
			var day_limit := 91 if all_ai else 0
			await _run_match(seed_value, 4, definition, flags, turn_cap, "fixture", {}, day_limit)
			if index == 1:
				_check(_surrender_done, "the surrender path was exercised")
				var players: Array = _as_array(_ui.game_state.state.get("players", []))
				_check(not players.is_empty() and not bool(players[0].get("alive", true)), "the conceding player left the match")
			if day_limit > 0:
				_check(str(_ui.game_state.state.get("phase", "")) == "game_over", "day-limited match reaches game_over")
				_check(int(_ui.game_state.state.get("winner", -1)) >= 0, "the completed match declares a winner")
				_check(_ui.end_overlay != null and _ui.end_overlay.visible, "the settlement overlay is shown for the completed match")

	var catalog := OS.get_environment("RICHMAN4_MAP_CATALOG")
	if catalog.is_empty():
		print("SKIP: RICHMAN4_MAP_CATALOG is absent; the real source-map soak variant is not applicable")
	else:
		await _run_catalog_match(catalog, turn_cap if long_run else CATALOG_TURN_CAP)

	_ui.queue_free()
	await process_frame
	if failures == 0:
		print("MainUI full-match soak passed: %d checks, autosave checkpoints seen=%s" % [checks, str(_saw_autosave)])
	else:
		printerr("MainUI full-match soak failed: %d failure(s) out of %d checks" % [failures, checks])
	quit(1 if failures else 0)


func _run_catalog_match(catalog_path: String, turn_cap: int) -> void:
	var loaded: Dictionary = OriginalMaps.load_catalog(catalog_path, true)
	if not bool(loaded.get("ok", false)):
		_check(false, "RICHMAN4_MAP_CATALOG is provided but unreadable: " + catalog_path)
		return
	var definition: Dictionary = {}
	for candidate in _as_array(loaded.get("maps", [])):
		if candidate is Dictionary and _ui._map_is_playable(candidate):
			definition = (candidate as Dictionary).duplicate(true)
			break
	if definition.is_empty():
		print("SKIP: the source catalog has no playable map for the soak")
		return
	_label = "catalog %s" % str(definition.get("id", "?"))
	_surrender_turn = -1
	# Real maps start from the source setup defaults so every capability the
	# map advertises (statuses, hazards, cards, research) is exercised.
	var options: Dictionary = _ui._default_setup_options(4, definition)
	options["human_flags"] = [true, false, false, false]
	await _run_match(int(definition.get("map_number", 1)) + 9100, 4, definition, [true, false, false, false], turn_cap, "catalog", options)


func _fixture_options(flags: Array, day_limit: int) -> Dictionary:
	return {
		"original_inventory": true,
		"original_facilities": true,
		"original_gods": true,
		"original_companies": true,
		"human_flags": flags,
		"initial_fund": 200000,
		"day_limit": day_limit,
		"wealth_multiplier": 0,
		"start_date": {"year": 1998, "month": 1, "day": 1},
		"character_ids": [0, 1, 2, 3],
	}


func _run_match(seed_value: int, player_count: int, definition: Dictionary, flags: Array, turn_cap: int, kind: String, options: Dictionary = {}, fixture_day_limit: int = 0) -> void:
	var effective := options.duplicate(true)
	if effective.is_empty():
		effective = _fixture_options(flags, fixture_day_limit)
	_ui._cancel_presentation()
	_ui._set_development_path(true)
	var started: bool = _ui._new_game(seed_value, player_count, definition, effective)
	_check(started, "new game starts through the ordinary UI path")
	if not started:
		return
	var game: Object = _ui.game_state
	_check(game != null, "MainUI owns a live simulation")
	if game == null:
		return
	var expected_humans := 0
	for flag in flags:
		if bool(flag):
			expected_humans += 1
	var human_players := 0
	for player in game.state.players:
		if not bool(player.get("is_ai", false)):
			human_players += 1
	_check(human_players == expected_humans, "human/AI roster matches the requested setup")
	_check(not _ui.is_processing(), "MainUI process is disabled so no scheduled timer competes with the soak")
	_check(not _ui._ai_pending, "no asynchronous AI turn is pending at match start")
	_ui._refresh_from_state()
	_match_saw_autosave = false
	_round_trip_dir = _scratch_root.path_join("soak-round-trip-%d-%d" % [seed_value, kind.hash()])
	DirAccess.make_dir_recursive_absolute(_round_trip_dir)
	_steps = 0
	_sale_probe_done = false
	_skip_action_turn = -1
	_last_progress = ""
	_last_progress_step = 0
	var stall := false
	var step_cap := turn_cap * 16 + 4000
	while true:
		if str(game.state.get("phase", "")) == "game_over":
			break
		if int(game.state.get("turn", 0)) > turn_cap:
			break
		if _steps >= step_cap:
			_dump_stall("step cap %d reached before game_over/turn cap" % step_cap, game)
			stall = true
			break
		var action := _soak_step(game)
		_steps += 1
		var progress := _progress_signature(game)
		if progress != _last_progress:
			_last_progress = progress
			_last_progress_step = _steps
		elif _steps - _last_progress_step >= STALL_STEPS:
			_dump_stall("no simulation or modal progress for %d steps (last step: %s)" % [STALL_STEPS, action], game)
			stall = true
			break
		if _steps % CHECKPOINT_STEPS == 0:
			_checkpoint(game, "step %d" % _steps)
		await process_frame
	if str(game.state.get("phase", "")) == "game_over":
		await _settle_finished_match(game)
	if not stall:
		_checkpoint(game, "end")
		_check(_match_saw_autosave, "the UI autosave wrote a fresh AUTO checkpoint for this match")
		var validation: Dictionary = GameState.validate_save(game.to_dict())
		_check(bool(validation.get("ok", false)), "final snapshot validates: " + str(validation.get("errors", [])))
		if str(game.state.get("phase", "")) == "game_over":
			print("SOAK %s: finished at turn %d, winner %s, steps %d" % [_label, int(game.state.get("turn", 0)), str(game.state.get("winner", -1)), _steps])
		else:
			print("SOAK %s: reached the turn cap at turn %d, steps %d" % [_label, int(game.state.get("turn", 0)), _steps])
	if failures == 0:
		_ui._cancel_presentation()


func _settle_finished_match(game: Object) -> void:
	# A report queued on the closing day outranks the settlement overlay, so a
	# finished match still has to be walked through its remaining presenters.
	for _attempt in range(8):
		if _ui._source_monthly_modal_open():
			_close_monthly()
		elif _ui._source_lottery_modal_open():
			_close_lottery()
		elif _ui._source_minigame_modal_open():
			_play_minigame(game)
		else:
			break
		await process_frame
	_ui._refresh_from_state()
	await process_frame


func _soak_step(game: Object) -> String:
	if _ui._presentation_busy:
		# Movement must complete through board_view.movement_finished, exactly as
		# it does for a player; a dead callback therefore trips the stall detector.
		return "wait movement"
	if _ui.news_popup != null and _ui.news_popup.visible:
		_ui.news_popup.cancel_presentation()
		return "close news"
	if _ui.fate_popup != null and _ui.fate_popup.visible:
		_ui.fate_popup.cancel_presentation()
		return "close fate"
	# Presenters whose dismissal never calls back into the simulation are closed
	# before the autosave flush: the flush refuses to run while they are open, and
	# a day boundary often queues the monthly report together with the checkpoint.
	if _ui._source_monthly_modal_open():
		return _close_monthly()
	if _ui._source_lottery_modal_open():
		return _close_lottery()
	if _ui._source_options_modal_open():
		_ui.source_options_panel.call("close_options")
		return "close options"
	if _ui._source_help_modal_open():
		_ui.source_help_controller.cancel()
		return "close help"
	if _ui._source_trustee_modal_open():
		_ui.source_trustee_controller.cancel()
		return "cancel trustee"
	if _ui._source_inventory_modal_open():
		_ui._close_source_inventory(false)
		return "close inventory"
	if _ui._legacy_save_modal_open():
		_ui._cancel_legacy_save_load()
		return "cancel legacy load"
	if _ui.source_save_menu != null and _ui.source_save_menu.visible:
		_ui.source_save_menu.call("close_menu")
		return "close save menu"
	if _ui.source_stock_panel != null and _ui.source_stock_panel.visible:
		_ui.source_stock_panel.hide()
		return "close stocks"

	if _ui._source_autosave.pending():
		_ui._flush_source_autosave()
		if _ui._source_autosave.pending():
			_ui._refresh_from_state()
		return "flush autosave"
	if FinancialPresentation.human_pending(game.state):
		_ui._respond_to_finance({"cancel": true})
		return "decline free card"
	if AuctionPresentation.human_pending(game.state):
		_ui._respond_to_auction({"increment": 0, "cancel": true})
		return "withdraw auction"
	if _ui._human_trap_response_pending():
		_ui._respond_to_trap(true)
		return "decline trap"
	if _ui._source_shop_modal_open():
		_ui.source_shop_controller.close_current()
		return "leave shop"
	if _ui._source_minigame_modal_open():
		return _play_minigame(game)
	if _ui._source_bank_modal_open():
		return _close_bank()
	if _ui._source_sale_modal_open():
		_ui.source_sale_controller.close_current()
		return "close sale"
	var popup_action := _act_on_source_popup(game)
	if not popup_action.is_empty():
		return popup_action

	if _ui._is_human_turn():
		return _human_turn(game)

	# AI or sleeping actor: the handler the ordinary 0.82s timer calls.
	_ui._on_ai_timer_timeout(-1)
	return "ai turn"


func _act_on_source_popup(game: Object) -> String:
	if _ui.facility_popup != null and _ui.facility_popup.visible:
		for child in _ui.facility_popup_list.get_children():
			if child is Button and str(child.name).begins_with("BuildFacility_"):
				if not child.disabled:
					child.pressed.emit()
					return "build facility"
		_ui.facility_popup.hide()
		_skip_action_turn = int(game.state.get("turn", 0))
		return "dismiss facility popup"
	if _ui.company_popup != null and _ui.company_popup.visible:
		var purchase: Button = _ui._company_purchase_button
		if purchase != null and is_instance_valid(purchase) and not purchase.disabled:
			purchase.pressed.emit()
			return "buy company shares"
		var service: Button = _ui._company_service_button
		if service != null and is_instance_valid(service) and not service.disabled:
			service.pressed.emit()
			return "company build service"
		_ui.company_popup.hide()
		_skip_action_turn = int(game.state.get("turn", 0))
		return "dismiss company popup"
	return ""


func _human_turn(game: Object) -> String:
	var phase := str(game.state.get("phase", ""))
	var options: Array = _as_array(game.state.get("action_options", []))
	if _surrender_turn > 0 and int(game.state.get("turn", 0)) >= _surrender_turn and _ui._source_options_operation_allowed():
		_surrender_turn = -1
		_ui._open_source_options("game")
		_ui._on_source_options_command("surrender")
		_ui._confirm_source_options_command()
		_surrender_done = true
		return "surrender"
	match phase:
		"await_roll":
			if not _sale_probe_done and int(game.state.get("turn", 0)) >= 6 and SourceSale.can_open(game):
				_sale_probe_done = true
				_ui._on_source_sale_requested()
				return "open sale"
			if _press_source_control("roll_button", "GO"):
				return "roll"
			return "wait GO control"
		"await_route":
			var route_options: Array = _as_array(game.state.get("route_options", []))
			if route_options.is_empty():
				return "wait route"
			if _press_source_route(route_options.size()):
				return "route"
			return "wait route control"
		"await_action":
			if int(game.state.get("turn", 0)) == _skip_action_turn:
				if _press_source_control("end_turn_button", "NO"):
					return "end turn after popup"
				return "wait action"
			if _has_option(options, "buy"):
				if _press_source_control("buy_button", "YES (buy)"):
					return "buy"
				return "wait buy control"
			if _has_option(options, "upgrade"):
				if _press_source_control("upgrade_button", "YES (upgrade)"):
					return "upgrade"
				return "wait upgrade control"
			if _press_source_control("end_turn_button", "NO"):
				return "end turn"
			return "wait action"
		"await_sale":
			_ui.source_sale_controller.close_current()
			return "close sale"
		"await_shop", "await_lottery", "await_minigame":
			return "wait modal %s" % phase
	return "wait human %s" % phase


func _press_source_control(control_name: String, description: String) -> bool:
	# Press the control the player actually clicks, and require it to be on screen
	# and enabled: a broken, hidden or disconnected button must fail the soak
	# instead of being bypassed by calling the handler behind it.
	var button: Button = null
	if _ui.source_shell != null:
		button = _ui.source_shell.get(control_name) as Button
	if button == null or not is_instance_valid(button):
		_check(false, "%s control exists in the source shell" % description)
		return false
	_check(button.is_visible_in_tree(), "%s control is visible to the player" % description)
	_check(not button.disabled, "%s control is enabled for the player" % description)
	if not button.is_visible_in_tree() or button.disabled:
		return false
	button.pressed.emit()
	return true


func _press_source_route(route_count: int) -> bool:
	if _ui.source_shell == null:
		return false
	var route_buttons: Control = _ui.source_shell.get("route_buttons") as Control
	if route_buttons == null or not is_instance_valid(route_buttons) or route_buttons.get_child_count() != route_count:
		return false
	var button := route_buttons.get_child(0) as Button
	if button == null:
		return false
	_check(button.is_visible_in_tree(), "route control 0 is visible to the player")
	_check(not button.disabled, "route control 0 is enabled for the player")
	if not button.is_visible_in_tree() or button.disabled:
		return false
	button.pressed.emit()
	return true


func _close_lottery() -> String:
	var controller: Control = _ui.source_lottery_controller
	if controller.report_panel != null and controller.report_panel.has_signal("continued"):
		if str(controller.current_report().get("kind", "")) == "purchase":
			controller.report_panel.cancelled.emit()
			return "leave lottery"
		controller.report_panel.continued.emit()
		return "continue lottery report"
	controller.cancel()
	return "cancel lottery presenter"


func _close_monthly() -> String:
	var controller: Control = _ui.source_monthly_controller
	if controller.report_panel != null and controller.report_panel.has_signal("continued"):
		controller.report_panel.continued.emit()
		return "continue monthly report"
	controller.cancel()
	return "cancel monthly presenter"


func _play_minigame(game: Object) -> String:
	var snapshot: Dictionary = game.minigame_snapshot()
	var encounter_id := int(snapshot.get("encounter_id", -1))
	if encounter_id < 0:
		_ui.source_minigame_controller.cancel()
		return "cancel empty minigame"
	if not bool(snapshot.get("finished", false)):
		# A human minigame blocks the turn until its model reaches a result;
		# tick the core model through its public boundary.
		_ui._invoke_game("minigame_tick", [encounter_id])
		return "tick minigame"
	_ui.source_minigame_controller.action_requested.emit("finish_minigame", [encounter_id])
	return "finish minigame"


func _close_bank() -> String:
	var controller: Control = _ui.source_bank_controller
	if controller != null and controller.bank_panel != null and controller.is_open():
		controller.bank_panel.emit_signal("closed")
		return "close bank panel"
	if controller != null:
		controller.cancel()
	return "cancel bank presenter"


func _checkpoint(game: Object, tag: String) -> void:
	var snapshot: Dictionary = game.to_dict()
	var validation: Dictionary = GameState.validate_save(snapshot)
	_check(bool(validation.get("ok", false)), "validate_save at %s: %s" % [tag, str(validation.get("errors", []))])
	if not bool(validation.get("ok", false)):
		_dump_stall("invalid save at %s" % tag, game)
		return
	var slots := SaveSlots.new(_round_trip_dir, _round_trip_dir.path_join("legacy.json"))
	var written: Dictionary = slots.write(1, snapshot)
	_check(bool(written.get("ok", false)), "SaveSlots write at %s: %s" % [tag, str(written.get("error", ""))])
	if not bool(written.get("ok", false)):
		return
	var read_back: Dictionary = slots.read(1)
	_check(bool(read_back.get("ok", false)) and str(read_back.get("status", "")) == "valid", "SaveSlots read-back at %s is valid" % tag)
	if not bool(read_back.get("ok", false)):
		return
	var restored: Variant = GameState.from_dict(read_back.get("snapshot", {}))
	_check(restored != null, "SaveSlots snapshot restores a game at %s" % tag)
	if restored == null:
		return
	# Compare through the loader on both sides: the live snapshot still carries
	# the writer's number types, while the stored copy is canonicalized.
	var live_restored: Variant = GameState.from_dict(snapshot)
	_check(live_restored != null, "live snapshot reloads at %s" % tag)
	if live_restored == null:
		return
	var live_normalized: Dictionary = live_restored.to_dict()
	var restored_normalized: Dictionary = restored.to_dict()
	if restored_normalized != live_normalized:
		_check(false, "save->load round-trip restores an identical snapshot at %s (differing keys: %s)" % [tag, str(_differing_keys(live_normalized, restored_normalized))])
	# The ordinary UI autosave writes AUTO on a day boundary. The shared scratch
	# user root can already hold an AUTO from an earlier check or seed, so only a
	# checkpoint carrying this match's seed and an elapsed turn counts. Every
	# match must produce a fresh one, otherwise the autosave path silently broke.
	var auto_slots := SaveSlots.new(_ui.source_save_directory, _ui.source_legacy_save_path)
	var auto: Dictionary = auto_slots.read(0)
	var auto_snapshot: Dictionary = auto.get("snapshot", {}) if auto.get("snapshot", {}) is Dictionary else {}
	var auto_seed := int(auto_snapshot.get("seed", -2))
	var current_seed := int(game.state.get("seed", -1))
	var same_match := auto_seed == current_seed and int(auto_snapshot.get("turn", 0)) <= int(game.state.get("turn", 0))
	if str(auto.get("status", "")) == "valid":
		_saw_autosave = true
		if same_match:
			_match_saw_autosave = true
	elif same_match and str(auto.get("status", "empty")) != "empty":
		_check(false, "AUTO checkpoint at %s is not a valid save: %s" % [tag, str(auto.get("status", ""))])


func _differing_keys(left: Dictionary, right: Dictionary) -> Array:
	var keys: Array = []
	for key in left.keys():
		if not right.has(key) or str(right[key]) != str(left[key]):
			keys.append(str(key))
	for key in right.keys():
		if not left.has(key):
			keys.append(str(key))
	keys.sort()
	return keys


func _progress_signature(game: Object) -> String:
	var keys := ["phase", "turn", "day", "month", "day_of_month", "current_player", "winner", "rng_state"]
	var parts: Array = []
	for key in keys:
		parts.append(str(game.state.get(key, "")))
	parts.append(str(_as_array(game.state.get("event_log", [])).size()))
	parts.append(str(game.state.get("last_event", "")))
	parts.append(str(game.state.get("position", "")))
	parts.append(str(_pending_keys(game.state)))
	return "|".join(parts)


func _pending_keys(snapshot: Dictionary) -> Array:
	var keys: Array = []
	for key in snapshot.keys():
		if str(key).begins_with("pending_") and snapshot.get(key) is Dictionary and not (snapshot.get(key) as Dictionary).is_empty():
			keys.append(key)
	keys.append("finance" if snapshot.has("pending_finance") else "")
	keys.append("auction" if not (snapshot.get("pending_auction", {}) as Dictionary).is_empty() else "")
	return keys


func _dump_stall(reason: String, game: Object) -> void:
	var modals: Array = []
	for pair in [
		["shop", _ui._source_shop_modal_open()],
		["sale", _ui._source_sale_modal_open()],
		["lottery", _ui._source_lottery_modal_open()],
		["minigame", _ui._source_minigame_modal_open()],
		["bank", _ui._source_bank_modal_open()],
		["monthly", _ui._source_monthly_modal_open()],
		["help", _ui._source_help_modal_open()],
		["options", _ui._source_options_modal_open()],
		["trustee", _ui._source_trustee_modal_open()],
		["inventory", _ui._source_inventory_modal_open()],
		["news", _ui.news_popup != null and _ui.news_popup.visible],
		["fate", _ui.fate_popup != null and _ui.fate_popup.visible],
		["facility", _ui.facility_popup != null and _ui.facility_popup.visible],
		["company", _ui.company_popup != null and _ui.company_popup.visible],
		["stocks", _ui.stocks_popup != null and _ui.stocks_popup.visible],
		["bank", _ui.bank_popup != null and _ui.bank_popup.visible],
		["cards", _ui.cards_popup != null and _ui.cards_popup.visible],
		["trap", _ui.trap_popup != null and _ui.trap_popup.visible],
		["financial", _ui.financial_popup != null and _ui.financial_popup.visible],
		["research", _ui.research_popup != null and _ui.research_popup.visible],
		["shop_popup", _ui.shop_popup != null and _ui.shop_popup.visible],
		["presentation", _ui._presentation_busy],
	]:
		if bool(pair[1]):
			modals.append(pair[0])
	var pending: Dictionary = {}
	for key in game.state.keys():
		if str(key).begins_with("pending_") and game.state.get(key) is Dictionary and not (game.state.get(key) as Dictionary).is_empty():
			pending[key] = game.state.get(key)
	var events: Array = _as_array(game.state.get("event_log", []))
	var recent: Array = events.slice(max(0, events.size() - 20), events.size())
	printerr("SOAK STALL [%s]: %s" % [_label, reason])
	printerr("  phase=%s turn=%d day=%d current_player=%d human_turn=%s" % [
		str(game.state.get("phase", "")), int(game.state.get("turn", 0)), int(game.state.get("day", 0)),
		int(game.state.get("current_player", -1)), str(_ui._is_human_turn())])
	printerr("  modals=%s" % str(modals))
	printerr("  pending=%s" % JSON.stringify(pending))
	printerr("  action_options=%s" % str(game.state.get("action_options", [])))
	printerr("  last 20 events=%s" % JSON.stringify(recent))
	failures += 1


func _as_array(value: Variant) -> Array:
	return value if value is Array else []


func _has_option(options: Array, expected: String) -> bool:
	for option in options:
		if typeof(option) == TYPE_STRING and str(option) == expected:
			return true
	return false
