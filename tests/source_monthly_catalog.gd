extends "res://tests/source_title_ui.gd"

## Normal-ingress coverage for source monthly statements.
##
## This test deliberately starts from the real catalog and MainUI's accepted
## setup options.  Calendar discovery uses only public GameState actions and
## result/get_snapshot data.  The UI replay accelerates ordinary earlier AI
## turns by applying returned snapshots, but sends every report-producing turn
## through MainUI's normal invoke/handle boundary.

const Core = preload("res://game/core/game_state.gd")

const PLAYER_COUNT := 4
const SEARCH_SEED_LIMIT := 16
const ACTION_LIMIT := 200
const CATALOG_MAP_COUNT := 12
const EXPECTED_START_DATE := {"year": 1998, "month": 1, "day": 1}
const EXPECTED_DIVIDEND_DATE := {"year": 1998, "month": 1, "day": 15}
const EXPECTED_INTEREST_DATE := {"year": 1998, "month": 2, "day": 1}

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var catalog_path := OS.get_environment("RICHMAN4_MAP_CATALOG")
	if catalog_path.is_empty():
		print("SKIP: RICHMAN4_MAP_CATALOG is absent; source monthly catalog coverage is not applicable")
		quit(0)
		return
	if not FileAccess.file_exists(catalog_path):
		push_error("FAIL: RICHMAN4_MAP_CATALOG is provided but does not point to a readable catalog: %s" % catalog_path)
		quit(1)
		return
	call_deferred("run")


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _settle() -> void:
	await process_frame
	await process_frame


func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.disable_3d = true
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.notify_mouse_entered()

	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await _settle()
	ui.set_process(false)

	_expect(ui._map_catalog_ok, "provided catalog parses through MainUI's normal loader")
	_expect(ui._map_catalog_complete, "provided catalog is a complete original twelve-stock catalog")
	_expect(ui._map_catalog.size() == CATALOG_MAP_COUNT, "provided catalog exposes all twelve source maps")
	if not (ui._map_catalog_ok and ui._map_catalog_complete and ui._map_catalog.size() == CATALOG_MAP_COUNT):
		viewport.queue_free()
		await _settle()
		print("Source monthly catalog checks: %d, failures: %d" % [_checks, _failures])
		quit(1)
		return

	await _run_catalog_case(ui, viewport, "Game", 3)
	await _run_catalog_case(ui, viewport, "MultiverseJourney", 7)

	viewport.queue_free()
	await _settle()
	print("Source monthly catalog checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures else 0)


func _run_catalog_case(ui: Control, viewport: SubViewport, edition: String, map_number: int) -> void:
	var definition := _find_map(ui, edition, map_number)
	_expect(not definition.is_empty(), "%s map %d is present in the actual catalog" % [edition, map_number])
	if definition.is_empty():
		return

	var setup_options: Dictionary = ui._default_setup_options(PLAYER_COUNT, definition)
	_expect(_date_equal(setup_options.get("start_date", {}), EXPECTED_START_DATE), "%s map %d accepted defaults start at 1998-01-01" % [edition, map_number])
	_expect(bool(setup_options.get("original_companies", false)), "%s map %d accepted defaults enable original companies" % [edition, map_number])
	_expect(bool(setup_options.get("original_facilities", false)), "%s map %d accepted defaults enable original facilities" % [edition, map_number])
	# The source setup factory accepts human_flags as the resolved player-control
	# choice.  Four AI players are permitted for bounded calendar discovery and
	# keep every action on the public run_ai_turn path.
	setup_options["human_flags"] = [false, false, false, false]

	var plan := _discover_calendar_plan(definition, setup_options, edition, map_number)
	_expect(not plan.is_empty(), "%s map %d finds dividend and interest through bounded public calendar actions" % [edition, map_number])
	if plan.is_empty():
		return
	print("SEED_MAP: edition=%s map=%d seed=%d dividend_action=%d interest_action=%d actions=%d" % [
		edition,
		map_number,
		int(plan.get("seed", -1)),
		int(plan.get("dividend_action", -1)),
		int(plan.get("interest_action", -1)),
		int(plan.get("actions", -1)),
	])

	var seed := int(plan.get("seed", 0))
	var started: bool = ui._new_game(seed, PLAYER_COUNT, definition, setup_options)
	_expect(started, "%s map %d starts through MainUI._new_game" % [edition, map_number])
	await _settle()
	if not started or ui.game_state == null:
		return

	var game: Object = ui.game_state
	var initial: Dictionary = game.get_snapshot()
	_expect(str(ui.source_shell.get("_source_edition")) == edition, "%s map %d updates the source edition" % [edition, map_number])
	_expect(int(initial.get("map_source", {}).get("map_number", 0)) == map_number, "%s map %d keeps the actual map identity" % [edition, map_number])
	_expect(game.get_stock_symbols().size() == 12, "%s map %d exposes the actual twelve-stock capability" % [edition, map_number])
	_expect(bool(initial.get("original_companies", false)) and bool(initial.get("original_facilities", false)), "%s map %d preserves accepted source capability flags" % [edition, map_number])
	_expect(initial.get("initial_human_flags", []) == [false, false, false, false], "%s map %d preserves the supported all-AI setup option" % [edition, map_number])
	_expect(_date_equal(initial.get("start_date", {}), EXPECTED_START_DATE), "%s map %d starts the real calendar at 1998-01-01" % [edition, map_number])
	_expect(_date_equal(initial.get("date", {}), EXPECTED_START_DATE) and int(initial.get("day", 0)) == 1 and int(initial.get("elapsed", -1)) == 0, "%s map %d initial calendar snapshot is day one" % [edition, map_number])
	_expect(bool(Core.validate_save(game.to_dict()).get("ok", false)), "%s map %d initial source save validates" % [edition, map_number])
	var initial_json: String = game.to_json()
	var initial_decoded: Variant = JSON.parse_string(initial_json)
	_expect(initial_decoded is Dictionary and bool(Core.validate_save(initial_decoded).get("ok", false)), "%s map %d initial JSON round-trips as a valid save" % [edition, map_number])

	var controller: Control = ui.source_monthly_controller
	_expect(controller != null, "%s map %d builds the source monthly controller" % [edition, map_number])
	if controller == null:
		return
	_expect(controller.get_parent() == ui.source_shell.reference_canvas, "%s map %d places the controller on the source reference canvas" % [edition, map_number])

	var dividend_seen := false
	var interest_seen := false
	var replay_actions := 0
	var seen_report_keys: Dictionary = {}
	for action_index in range(ACTION_LIMIT):
		if dividend_seen and interest_seen:
			break
		var before: Dictionary = game.get_snapshot()
		if str(before.get("phase", "")) == "game_over":
			break
		var result: Dictionary = ui._invoke_game("run_ai_turn")
		var after: Dictionary = _result_snapshot(result, game)
		replay_actions += 1
		_expect(bool(result.get("ok", false)), "%s map %d public AI action %d succeeds" % [edition, map_number, action_index + 1])
		if not bool(result.get("ok", false)):
			break

		var reports := _fresh_monthly_reports(before, after, seen_report_keys)
		if reports.is_empty():
			# Accelerated calendar setup: state already advanced through the public
			# action; skip visual movement playback for ordinary earlier turns.
			ui._refresh_from_state(result)
			await process_frame
			continue

		_expect(reports.size() == 1, "%s map %d action %d emits exactly one fresh monthly report" % [edition, map_number, action_index + 1])
		for report in reports:
			var kind := str(report.get("kind", ""))
			if kind not in ["dividend", "interest"]:
				_expect(false, "%s map %d emits only a dividend or interest report kind" % [edition, map_number])
				continue
			ui._handle_result(result)
			await _wait_for_report(ui, controller)
			if not controller.is_open() or controller.report_panel == null:
				_expect(false, "%s map %d displays the fresh %s report through the normal UI boundary" % [edition, map_number, kind])
				continue
			var panel: Control = controller.report_panel
			_expect(panel.get_parent() == controller and panel.visible, "%s map %d real %s presenter is visible" % [edition, map_number, kind])
			_expect(panel.has_method("view_model") and panel.has_method("is_model_valid"), "%s map %d uses the real presenter public model API" % [edition, map_number])
			if panel.has_method("set_auto_advance_seconds"):
				panel.call("set_auto_advance_seconds", 0.0)
			_expect(bool(panel.call("is_model_valid")), "%s map %d real %s presenter accepts the authoritative model" % [edition, map_number, kind])
			_expect(panel.call("view_model") == report, "%s map %d %s presenter displays the exact detached core report" % [edition, map_number, kind])
			_expect(str(report.get("edition", "")) == edition, "%s map %d %s report preserves the source edition" % [edition, map_number, kind])
			_expect(_date_equal(report.get("date", {}), EXPECTED_DIVIDEND_DATE if kind == "dividend" else EXPECTED_INTEREST_DATE), "%s map %d %s report has the expected 1998 calendar date" % [edition, map_number, kind])
			if panel.has_method("source_art_available"):
				var art_available: bool = bool(panel.call("source_art_available"))
				print("SOURCE_ART: edition=%s map=%d kind=%s display=%s available=%s status=%s" % [edition, map_number, kind, DisplayServer.get_name(), art_available, JSON.stringify(panel.call("source_art_status"))])
				if DisplayServer.get_name() == "headless" or not art_available:
					print("UNAVAILABLE: %s map %d %s source-art visual evidence is not claimed by this functional run" % [edition, map_number, kind])
			if kind == "dividend":
				_expect(not dividend_seen, "%s map %d dividend is emitted exactly once in the bounded replay" % [edition, map_number])
				_verify_dividend_summary(edition, map_number, before, after, report)
				dividend_seen = true
			else:
				_expect(not interest_seen, "%s map %d interest is emitted exactly once in the bounded replay" % [edition, map_number])
				_verify_interest_summary(edition, map_number, before, after, report)
				interest_seen = true
			await _verify_block_and_ack(ui, viewport, game, controller, panel, edition, map_number, kind, after)

	_expect(dividend_seen, "%s map %d naturally reaches the day-15 dividend report" % [edition, map_number])
	_expect(interest_seen, "%s map %d naturally reaches the month-boundary interest report" % [edition, map_number])
	_expect(replay_actions <= ACTION_LIMIT, "%s map %d replay stays within the public-action bound" % [edition, map_number])
	if not dividend_seen or not interest_seen:
		print("UNAVAILABLE: %s map %d did not complete both real reports; renderer/controller dependency or calendar route remains unresolved" % [edition, map_number])


func _discover_calendar_plan(definition: Dictionary, setup_options: Dictionary, edition: String, map_number: int) -> Dictionary:
	var observed_dates: Array = []
	for seed_value in range(1, SEARCH_SEED_LIMIT + 1):
		var game: Object = Core.new_game_on_board(seed_value, PLAYER_COUNT, definition, setup_options.duplicate(true))
		if game == null:
			continue
		var first_snapshot: Dictionary = game.get_snapshot()
		var seen_report_keys: Dictionary = {}
		var dividend_action := -1
		var interest_action := -1
		var dividend_date: Dictionary = {}
		var interest_date: Dictionary = {}
		for action_index in range(ACTION_LIMIT):
			var before: Dictionary = game.get_snapshot()
			if str(before.get("phase", "")) == "game_over":
				break
			var result: Dictionary = game.run_ai_turn()
			if not bool(result.get("ok", false)):
				break
			var after: Dictionary = _result_snapshot(result, game)
			var reports := _fresh_monthly_reports(before, after, seen_report_keys)
			for report in reports:
				var kind := str(report.get("kind", ""))
				var report_date: Dictionary = report.get("date", {}) if report.get("date", {}) is Dictionary else {}
				if kind == "dividend" and dividend_action < 0 and int(report_date.get("day", 0)) == 15:
					dividend_action = action_index + 1
					dividend_date = report_date.duplicate(true)
				if kind == "interest" and interest_action < 0 and int(report_date.get("day", 0)) == 1:
					interest_action = action_index + 1
					interest_date = report_date.duplicate(true)
			if dividend_action >= 0 and interest_action >= 0:
				return {
					"seed": seed_value,
					"dividend_action": dividend_action,
					"interest_action": interest_action,
					"actions": action_index + 1,
					"start_date": first_snapshot.get("start_date", {}).duplicate(true),
					"dividend_date": dividend_date,
					"interest_date": interest_date,
				}
		if dividend_action >= 0 or interest_action >= 0:
			observed_dates.append({"seed": seed_value, "dividend": dividend_date, "interest": interest_date})
	if not observed_dates.is_empty():
		print("ROUTE_DISCOVERY: edition=%s map=%d observed=%s" % [edition, map_number, JSON.stringify(observed_dates)])
	return {}


func _verify_dividend_summary(edition: String, map_number: int, before: Dictionary, after: Dictionary, report: Dictionary) -> void:
	var before_players: Array = _array_value(before.get("players", []))
	var after_players: Array = _array_value(after.get("players", []))
	var report_players: Array = _array_value(report.get("players", []))
	var report_companies: Array = _array_value(report.get("companies", []))
	_expect(report_players.size() == before_players.size(), "%s map %d dividend report includes all alive source players" % [edition, map_number])
	_expect(not report_companies.is_empty(), "%s map %d dividend report includes the source company rows" % [edition, map_number])
	var totals: Array = []
	for _player_index in range(report_players.size()):
		totals.append(0)
	for company_value in report_companies:
		if not company_value is Dictionary:
			_expect(false, "%s map %d dividend company row is an object" % [edition, map_number])
			continue
		var company: Dictionary = company_value
		var company_id := int(company.get("company_id", -1))
		var before_company := _company_by_id(before.get("companies", []), company_id)
		_expect(not before_company.is_empty(), "%s map %d dividend row references a real company" % [edition, map_number])
		_expect(int(company.get("monthly_profit", 0)) == int(before_company.get("monthly_profit", 0)), "%s map %d dividend row preserves the pre-settlement company profit" % [edition, map_number])
		var payouts: Array = _array_value(company.get("payouts", []))
		_expect(payouts.size() == report_players.size(), "%s map %d dividend payouts align with active players" % [edition, map_number])
		for ordinal in range(mini(payouts.size(), totals.size())):
			totals[ordinal] = int(totals[ordinal]) + int(payouts[ordinal])
	for ordinal in range(report_players.size()):
		var report_player: Dictionary = report_players[ordinal] if report_players[ordinal] is Dictionary else {}
		_expect(int(report_player.get("total", 0)) == int(totals[ordinal]), "%s map %d dividend player total equals authoritative company payouts" % [edition, map_number])
		var player_id := int(report_player.get("id", -1))
		var before_player := _player_by_id(before_players, player_id)
		var after_player := _player_by_id(after_players, player_id)
		_expect(not before_player.is_empty() and not after_player.is_empty(), "%s map %d dividend player identity survives settlement" % [edition, map_number])
		if before_player.is_empty() or after_player.is_empty():
			continue
		var payout := int(report_player.get("total", 0))
		var projected_deposit := int(before_player.get("deposit", 0)) + payout
		var expected_deposit := maxi(0, projected_deposit)
		_expect(int(after_player.get("deposit", 0)) == expected_deposit, "%s map %d dividend changes the authoritative deposit ledger exactly once" % [edition, map_number])
		var expected_cash := int(before_player.get("cash", 0)) - maxi(0, -projected_deposit)
		_expect(int(after_player.get("cash", 0)) == expected_cash, "%s map %d dividend applies any authoritative cash loss after deposit exhaustion" % [edition, map_number])
	var before_bank: Dictionary = before.get("bank", {})
	var after_bank: Dictionary = after.get("bank", {})
	var deposit_delta := 0
	for report_player_value in report_players:
		var player_id := int(report_player_value.get("id", -1)) if report_player_value is Dictionary else -1
		var old_player := _player_by_id(before_players, player_id)
		var new_player := _player_by_id(after_players, player_id)
		if not old_player.is_empty() and not new_player.is_empty():
			deposit_delta += int(new_player.get("deposit", 0)) - int(old_player.get("deposit", 0))
	_expect(int(after_bank.get("deposits", 0)) - int(before_bank.get("deposits", 0)) == deposit_delta, "%s map %d dividend report matches the bank deposit liability delta" % [edition, map_number])
	for company_value in report_companies:
		if company_value is Dictionary:
			var company_after := _company_by_id(after.get("companies", []), int(company_value.get("company_id", -1)))
			_expect(not company_after.is_empty() and int(company_after.get("monthly_profit", 0)) == 0, "%s map %d dividend settlement resets each source company pool after capture" % [edition, map_number])


func _verify_interest_summary(edition: String, map_number: int, before: Dictionary, after: Dictionary, report: Dictionary) -> void:
	var before_players: Array = _array_value(before.get("players", []))
	var after_players: Array = _array_value(after.get("players", []))
	var report_players: Array = _array_value(report.get("players", []))
	_expect(report_players.size() == _alive_count(before_players), "%s map %d interest report includes every alive player, including zero interest" % [edition, map_number])
	var interest_total := 0
	var report_deposits_before := 0
	for report_value in report_players:
		if not report_value is Dictionary:
			_expect(false, "%s map %d interest player row is an object" % [edition, map_number])
			continue
		var report_player: Dictionary = report_value
		var player_id := int(report_player.get("id", -1))
		var before_player := _player_by_id(before_players, player_id)
		var after_player := _player_by_id(after_players, player_id)
		_expect(not before_player.is_empty() and not after_player.is_empty(), "%s map %d interest player identity survives settlement" % [edition, map_number])
		if before_player.is_empty() or after_player.is_empty():
			continue
		var deposit_before := int(report_player.get("deposit_before", -1))
		var loan_active := bool(report_player.get("loan_active", false))
		var expected_interest := 0
		if not loan_active and deposit_before > 0:
			expected_interest = int(floor(float(deposit_before) * 0.1))
		_expect(deposit_before >= 0, "%s map %d interest report preserves the pre-interest deposit" % [edition, map_number])
		_expect(int(report_player.get("interest", -1)) == expected_interest, "%s map %d interest report carries the core-calculated amount" % [edition, map_number])
		_expect(int(after_player.get("deposit", 0)) == deposit_before + expected_interest, "%s map %d interest credits the authoritative deposit ledger once" % [edition, map_number])
		interest_total += expected_interest
		report_deposits_before += deposit_before
	var before_bank: Dictionary = before.get("bank", {})
	var after_bank: Dictionary = after.get("bank", {})
	var before_deposits := 0
	for report_value in report_players:
		if report_value is Dictionary:
			var player_id := int(report_value.get("id", -1))
			var before_player := _player_by_id(before_players, player_id)
			if not before_player.is_empty():
				before_deposits += int(before_player.get("deposit", 0))
	var settlement_baseline_adjustment := report_deposits_before - before_deposits
	_expect(int(after_bank.get("deposits", 0)) - int(before_bank.get("deposits", 0)) == settlement_baseline_adjustment + interest_total, "%s map %d interest report matches the bank deposit liability" % [edition, map_number])
	_expect(int(after_bank.get("cash", 0)) == int(before_bank.get("cash", 0)) - interest_total, "%s map %d interest report matches bank cash outflow" % [edition, map_number])
	var settled_month: Variant = after.get("last_settled_month", {})
	_expect(settled_month is Dictionary and int(settled_month.get("year", 0)) == int(before.get("date", {}).get("year", 0)) and int(settled_month.get("month", 0)) == int(before.get("date", {}).get("month", 0)), "%s map %d interest advances the month settlement marker from the real boundary" % [edition, map_number])


func _verify_block_and_ack(ui: Control, viewport: SubViewport, game: Object, controller: Control, panel: Control, edition: String, map_number: int, kind: String, settled_snapshot: Dictionary) -> void:
	var settled_json: String = game.to_json()
	var settled_rng := int(settled_snapshot.get("rng_state", -1))
	var blocked: Dictionary = ui._invoke_game("run_ai_turn")
	_expect(not bool(blocked.get("ok", false)), "%s map %d monthly %s queue blocks another public AI action" % [edition, map_number, kind])
	_expect(game.to_json() == settled_json, "%s map %d blocked monthly %s action preserves the full ledger and RNG" % [edition, map_number, kind])
	ui._on_ai_timer_timeout()
	await _settle()
	var timer_snapshot: Dictionary = game.get_snapshot()
	_expect(game.to_json() == settled_json and int(timer_snapshot.get("rng_state", -2)) == settled_rng, "%s map %d AI timer cannot advance while monthly %s is open" % [edition, map_number, kind])

	var release_point := panel.get_global_transform_with_canvas() * Vector2(320.0, 240.0)
	var motion := InputEventMouseMotion.new()
	motion.position = release_point
	motion.global_position = release_point
	viewport.push_input(motion, true)
	var down := InputEventMouseButton.new()
	down.position = release_point
	down.global_position = release_point
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	viewport.push_input(down, true)
	var up := InputEventMouseButton.new()
	up.position = release_point
	up.global_position = release_point
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	viewport.push_input(up, true)
	await process_frame
	var release_closed: bool = not controller.is_open()
	_expect(release_closed, "%s map %d viewport-local mouse release acknowledges the real monthly %s presenter" % [edition, map_number, kind])
	if is_instance_valid(panel) and not release_closed:
		# Keep the failure visible; this fallback is only a cleanup path so a
		# broken presenter cannot leak into the next calendar case.
		panel.call("continue_report")
	await _settle()
	_expect(not controller.is_open() and not ui._source_monthly_modal_open(), "%s map %d monthly %s acknowledgment closes the controller" % [edition, map_number, kind])
	_expect(game.to_json() == settled_json, "%s map %d monthly %s acknowledgment does not repeat settlement or alter RNG" % [edition, map_number, kind])
	ui._refresh_from_state()
	await _settle()
	_expect(not controller.is_open(), "%s map %d acknowledged monthly %s does not replay on refresh" % [edition, map_number, kind])


func _wait_for_report(ui: Control, controller: Control) -> void:
	for _frame in range(1200):
		if controller.report_panel != null and is_instance_valid(controller.report_panel):
			var panel: Control = controller.report_panel
			if panel.has_method("set_auto_advance_seconds"):
				panel.call("set_auto_advance_seconds", 0.0)
		if not ui._presentation_busy and controller.is_open() and controller.report_panel != null:
			return
		await process_frame
	_expect(false, "monthly presenter did not become visible within the bounded movement wait")


func _fresh_monthly_reports(before: Dictionary, after: Dictionary, seen_report_keys: Dictionary) -> Array:
	var fresh: Array = []
	for event_value in _array_value(after.get("event_log", [])):
		if not event_value is Dictionary or str(event_value.get("type", "")) != "monthly_statement":
			continue
		var event: Dictionary = event_value
		var key := JSON.stringify(event)
		if seen_report_keys.has(key):
			continue
		seen_report_keys[key] = true
		var report: Variant = event.get("report", null)
		if report is Dictionary and str(report.get("kind", "")) in ["dividend", "interest"]:
			fresh.append(report.duplicate(true))
	return fresh


func _result_snapshot(result: Dictionary, game: Object) -> Dictionary:
	var value: Variant = result.get("state", null)
	if value is Dictionary:
		return value.duplicate(true)
	return game.get_snapshot()


func _find_map(ui: Control, edition: String, map_number: int) -> Dictionary:
	for value in ui.get("_map_catalog"):
		if not value is Dictionary:
			continue
		var source: Variant = value.get("source", {})
		if source is Dictionary and str(source.get("edition", "")) == edition and int(source.get("map_number", 0)) == map_number:
			return value.duplicate(true)
	return {}


func _date_equal(value: Variant, expected: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	return int(value.get("year", -1)) == int(expected.get("year", -2)) and int(value.get("month", -1)) == int(expected.get("month", -2)) and int(value.get("day", -1)) == int(expected.get("day", -2))


func _array_value(value: Variant) -> Array:
	return value if value is Array else []


func _player_by_id(players: Array, player_id: int) -> Dictionary:
	for value in players:
		if value is Dictionary and int(value.get("id", -1)) == player_id:
			return value
	return {}


func _company_by_id(companies_value: Variant, company_id: int) -> Dictionary:
	for value in _array_value(companies_value):
		if value is Dictionary and int(value.get("id", value.get("company_id", -1))) == company_id:
			return value
	return {}


func _alive_count(players: Array) -> int:
	var count := 0
	for player in players:
		if player is Dictionary and bool(player.get("alive", false)):
			count += 1
	return count
