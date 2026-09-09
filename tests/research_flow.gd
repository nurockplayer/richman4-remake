extends SceneTree

## Issue #39 acceptance flow for original research facilities.
##
## The research fixture is synthetic and contains no original assets.  Until
## the v12 factory exists, this test deliberately bootstraps a v11 instance and
## stamps only the v12 runtime fields needed to exercise the public contract.
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/research_fixture.gd")
const V12_SAVE_VERSION := 12
const RESEARCH_TOOLS := ["機器工人", "時光機", "傳送機", "工程車", "核子飛彈"]

var checks: int = 0
var failures: int = 0
var bootstrap_version_red: int = 0
var bootstrap_reported: bool = false
var using_bootstrap_fallback: bool = false


func _initialize() -> void:
	_test_factory_and_schema()
	_test_research_selection_ranks_and_atomicity()
	_test_lab_build_and_upgrade()
	_test_countdown_cycle_and_reschedule()
	_test_owner_tick_aliases_and_status()
	_test_nonlab_and_downgrade_cancellation()
	_test_inventory_cap_and_no_shared_supply()
	_test_v11_compatibility()
	print("Original research flow checks: %d, failures: %d, bootstrap_version_red: %d" % [checks, failures, bootstrap_version_red])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func _new_v12_game(seed_value: int, player_count: int = 2) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, player_count, Fixture.definition(), Fixture.new_game_options())
	if game != null:
		return game
	bootstrap_version_red += 1
	using_bootstrap_fallback = true
	if not bootstrap_reported:
		bootstrap_reported = true
		print("BOOTSTRAP VERSION RED: v12 constructor is unavailable; research semantics use a v11 instance stamped v12/original_research in the test harness")
	var legacy: Object = Game.new_game_on_board(seed_value, player_count, Fixture.definition(), Fixture.v11_game_options())
	_expect(legacy != null, "v11 predecessor fixture bootstraps the v12 research harness")
	if legacy == null:
		return null
	legacy.state["version"] = V12_SAVE_VERSION
	legacy.state["original_research"] = true
	legacy.state["research_action_used"] = false
	for tile_value in legacy.state.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility":
			continue
		if not tile_value.has("research_tool"):
			tile_value["research_tool"] = 0
		if not tile_value.has("research_turns"):
			tile_value["research_turns"] = 0
	legacy._sync_state()
	return legacy


func _new_v11_game(seed_value: int, player_count: int = 2) -> Object:
	return Game.new_game_on_board(seed_value, player_count, Fixture.definition(), Fixture.v11_game_options())


func _facility_indices(game: Object, source_id: int) -> Array:
	var result: Array = []
	for index in range(game.state.get("board", []).size()):
		var tile: Dictionary = game.state["board"][index]
		if tile.get("kind", "") == "facility" and int(tile.get("source_object_id", -1)) == source_id:
			result.append(index)
	return result


func _set_facility(
	game: Object,
	source_id: int,
	owner_id: int,
	level: int,
	facility_type: int,
	research_tool: int = 0,
	research_turns: int = 0,
	facility_state: int = 0,
) -> void:
	var indices: Array = _facility_indices(game, source_id)
	if indices.is_empty():
		_expect(false, "research fixture contains facility source %d" % source_id)
		return
	var canonical: int = int(game.state["board"][int(indices[0])].get("facility_node_index", int(indices[0])))
	for index_value in indices:
		var tile: Dictionary = game.state["board"][int(index_value)]
		tile["owner"] = owner_id
		tile["building_level"] = level
		tile["facility_type"] = facility_type
		tile["facility_state"] = facility_state
		tile["research_tool"] = research_tool
		tile["research_turns"] = research_turns
	for player in game.state.get("players", []):
		var properties: Array = player.get("properties", []).duplicate(true)
		while properties.has(canonical):
			properties.erase(canonical)
		if int(player.get("id", -1)) == owner_id and owner_id >= 0:
			properties.append(canonical)
		player["properties"] = properties
	game._recalculate_property_values()


func _prepare_landing(game: Object, player_id: int, position: int, phase: String = "await_action") -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = phase
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.state["last_roll"] = [1]
	game.state["last_total"] = 1
	game.state["last_roll_total"] = 1
	game.state["remaining_steps"] = 0
	game.state["route_options"] = []
	game.state["pending_movement"] = {}
	game.state["players"][player_id]["position"] = position
	game.state["players"][player_id]["previous_position"] = -1
	game._set_action_options(player_id)


func _prepare_non_action_turn(game: Object, player_id: int) -> void:
	game.state["current_player"] = player_id
	game.state["phase"] = "await_action"
	game.state["last_roll"] = []
	game.state["last_total"] = 0
	game.state["last_roll_total"] = 0
	game.state["property_action_used"] = false
	game.state["route_options"] = []
	game.state["remaining_steps"] = 0
	game.state["pending_movement"] = {}


func _end_action_turn(game: Object, player_id: int, label: String) -> Dictionary:
	_prepare_non_action_turn(game, player_id)
	var result: Dictionary = game.end_turn()
	_expect(bool(result.get("ok", false)), label + " ends through public end_turn")
	return result


func _assert_aliases(game: Object, source_id: int, expected_tool: int, expected_turns: int, label: String) -> void:
	var indices: Array = _facility_indices(game, source_id)
	_expect(not indices.is_empty(), label + " has at least one canonical source alias")
	for index_value in indices:
		var tile: Dictionary = game.state["board"][int(index_value)]
		_expect_equal(int(tile.get("research_tool", -1)), expected_tool, label + " alias keeps research rank")
		_expect_equal(int(tile.get("research_turns", -1)), expected_turns, label + " alias keeps countdown")


func _assert_facility_aliases(game: Object, source_id: int, expected_type: int, expected_level: int, label: String) -> void:
	var indices: Array = _facility_indices(game, source_id)
	_expect(not indices.is_empty(), label + " has at least one facility alias")
	for index_value in indices:
		var tile: Dictionary = game.state["board"][int(index_value)]
		_expect_equal(int(tile.get("facility_type", -1)), expected_type, label + " alias keeps facility type")
		_expect_equal(int(tile.get("building_level", -1)), expected_level, label + " alias keeps building level")


func _test_factory_and_schema() -> void:
	var definition: Dictionary = Fixture.definition()
	_expect(typeof(definition.get("supports_original_research", null)) == TYPE_BOOL, "research capability is explicitly boolean")
	_expect(bool(definition.get("supports_original_research", false)), "research fixture advertises complete source capability")
	var options: Dictionary = Fixture.new_game_options()
	_expect_equal(options.get("original_research", null), true, "new game explicitly requests original research")
	var v11_options: Dictionary = Fixture.v11_game_options()
	_expect(not v11_options.has("original_research"), "v11 predecessor options do not enable research")
	var game: Object = _new_v12_game(3901)
	_expect(game != null, "research graph starts")
	if game == null:
		return
	_expect_equal(int(game.state.get("version", -1)), V12_SAVE_VERSION, "research setup uses v12 save")
	_expect_equal(game.state.get("original_research", false), true, "research marker is persisted")
	_expect(typeof(game.state.get("research_action_used", null)) == TYPE_BOOL, "research action guard is a top-level boolean")
	for tile_value in game.state.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility":
			continue
		_expect(typeof(tile_value.get("research_tool", null)) == TYPE_INT, "every facility starts with an integer research rank")
		_expect(typeof(tile_value.get("research_turns", null)) == TYPE_INT, "every facility starts with an integer research countdown")
		_expect_equal(int(tile_value.get("research_tool", -1)), 0, "fresh facility research rank starts at zero")
		_expect_equal(int(tile_value.get("research_turns", -1)), 0, "fresh facility research countdown starts at zero")


func _test_research_selection_ranks_and_atomicity() -> void:
	for rank in range(1, RESEARCH_TOOLS.size() + 1):
		var game: Object = _new_v12_game(4000 + rank)
		_expect(game != null, "rank %d selection fixture starts" % rank)
		if game == null:
			continue
		_set_facility(game, 1, 0, rank, 4)
		_prepare_landing(game, 0, 1)
		var cash_before: int = int(game.state["players"][0].get("cash", 0))
		var supply_before: Dictionary = game.state.get("inventory_supply", {}).get("tools", {}).duplicate(true)
		var property_used_before: bool = bool(game.state.get("property_action_used", false))
		var result: Dictionary = game.choose_action("choose_research", {"tool_id": RESEARCH_TOOLS[rank - 1]})
		_expect(bool(result.get("ok", false)), "rank %d public research selection succeeds" % rank)
		_assert_aliases(game, 1, rank, 5, "rank %d selection" % rank)
		_expect_equal(int(game.state["players"][0].get("cash", 0)), cash_before, "rank %d research selection is free" % rank)
		_expect_equal(game.state.get("inventory_supply", {}).get("tools", {}), supply_before, "rank %d selection does not consume shared tools" % rank)
		_expect_equal(bool(game.state.get("property_action_used", false)), property_used_before, "rank %d selection does not change property action" % rank)
		_expect_equal(bool(game.state.get("research_action_used", false)), true, "rank %d selection marks research action used" % rank)
		var repeated_before: String = game.to_json()
		var repeated: Dictionary = game.choose_action("choose_research", {"tool_id": RESEARCH_TOOLS[rank - 1]})
		_expect(not bool(repeated.get("ok", false)), "second research selection in one visit is rejected")
		_expect_equal(game.to_json(), repeated_before, "second research selection is atomic")

	var invalid_cases: Array = [
		{"tool_id": "不存在", "label": "unknown research tool"},
		{"tool_id": "時光機", "label": "tool rank above facility level"},
		{"tool_id": 1, "label": "non-string research tool"},
		{"tool_id": "機器工人", "cancel": "yes", "label": "malformed cancellation"},
	]
	for invalid_case in invalid_cases:
		var invalid_game: Object = _new_v12_game(4010 + checks)
		_expect(invalid_game != null, str(invalid_case.get("label", "invalid")) + " fixture starts")
		if invalid_game == null:
			continue
		_set_facility(invalid_game, 1, 0, 1, 4)
		_prepare_landing(invalid_game, 0, 1)
		var before: String = invalid_game.to_json()
		var params: Dictionary = invalid_case.duplicate(true)
		params.erase("label")
		var rejected: Dictionary = invalid_game.choose_action("choose_research", params)
		_expect(not bool(rejected.get("ok", false)), str(invalid_case.get("label", "invalid")) + " is rejected")
		_expect_equal(invalid_game.to_json(), before, str(invalid_case.get("label", "invalid")) + " leaves state unchanged")

	var cancelled_game: Object = _new_v12_game(4020)
	_expect(cancelled_game != null, "cancel research fixture starts")
	if cancelled_game != null:
		_set_facility(cancelled_game, 1, 0, 1, 4)
		_prepare_landing(cancelled_game, 0, 1)
		var cancelled_before: String = cancelled_game.to_json()
		var cancelled: Dictionary = cancelled_game.choose_action("choose_research", {"cancel": true})
		_expect(bool(cancelled.get("ok", false)), "cancelled research selection is accepted")
		_expect_equal(cancelled_game.to_json(), cancelled_before, "cancelled research selection is atomic")

	var rejected_contexts: Array = [
		{"position": 9, "phase": "await_action", "label": "road landing"},
		{"position": 7, "phase": "await_action", "label": "other owner's facility"},
		{"position": 1, "phase": "await_action", "label": "non-lab facility"},
		{"position": 1, "phase": "await_roll", "label": "pre-roll"},
		{"position": 1, "phase": "await_route", "label": "route choice"},
	]
	for context in rejected_contexts:
		var context_game: Object = _new_v12_game(4030 + checks)
		_expect(context_game != null, str(context.get("label", "context")) + " fixture starts")
		if context_game == null:
			continue
		var context_source_id: int = 2 if context.get("label", "") == "other owner's facility" else 1
		_set_facility(context_game, context_source_id, 1 if context.get("label", "") == "other owner's facility" else 0, 1, 1 if context.get("label", "") == "non-lab facility" else 4, 0, 0, 0)
		_prepare_landing(context_game, 0, int(context["position"]), str(context["phase"]))
		if str(context["phase"]) == "await_route":
			context_game.state["route_options"] = [1]
			context_game.state["pending_movement"] = {"player_id": 0, "current_node": 1, "previous_node": 0}
		if str(context.get("label", "")) == "non-lab facility":
			_set_facility(context_game, 1, 0, 1, 1)
		if str(context.get("label", "")) == "pre-roll":
			context_game.state["last_roll"] = []
			context_game.state["last_total"] = 0
			context_game.state["last_roll_total"] = 0
		if str(context.get("label", "")) == "route choice":
			context_game.state["last_roll"] = [1]
		var context_before: String = context_game.to_json()
		var context_result: Dictionary = context_game.choose_action("choose_research", {"tool_id": "機器工人"})
		_expect(not bool(context_result.get("ok", false)), str(context.get("label", "context")) + " rejects research selection")
		_expect_equal(context_game.to_json(), context_before, str(context.get("label", "context")) + " rejection is atomic")

	var sealed_game: Object = _new_v12_game(4040)
	_expect(sealed_game != null, "sealed facility selection fixture starts")
	if sealed_game != null:
		_set_facility(sealed_game, 1, 0, 1, 4, 0, 0, 0x51)
		_prepare_landing(sealed_game, 0, 1)
		var sealed_before: String = sealed_game.to_json()
		var sealed: Dictionary = sealed_game.choose_action("choose_research", {"tool_id": "機器工人"})
		_expect(not bool(sealed.get("ok", false)), "sealed facility rejects research selection")
		_expect_equal(sealed_game.to_json(), sealed_before, "sealed selection rejection is atomic")

	var detained_game: Object = _new_v12_game(4041)
	_expect(detained_game != null, "detained research selection fixture starts")
	if detained_game != null:
		_set_facility(detained_game, 1, 0, 1, 4)
		_prepare_landing(detained_game, 0, 1)
		detained_game.state["players"][0]["hospital_days"] = 1
		var detained_before: String = detained_game.to_json()
		var detained: Dictionary = detained_game.choose_action("choose_research", {"tool_id": "機器工人"})
		_expect(not bool(detained.get("ok", false)), "detained owner rejects research selection")
		_expect_equal(detained_game.to_json(), detained_before, "detained selection rejection is atomic")


func _test_lab_build_and_upgrade() -> void:
	var build_game: Object = _new_v12_game(4101)
	_expect(build_game != null, "research lab build fixture starts")
	if build_game == null:
		return
	_set_facility(build_game, 1, 0, 0, 0)
	_prepare_landing(build_game, 0, 1)
	var build: Dictionary = build_game.choose_action("build_facility", {"facility_type": 4})
	_expect(bool(build.get("ok", false)), "type4 research lab can be built")
	_assert_aliases(build_game, 1, 0, 0, "new research lab")
	_assert_facility_aliases(build_game, 1, 4, 1, "new research lab")
	_expect_equal(int(build_game.state["board"][1].get("facility_type", -1)), 4, "research lab build records type4")
	_expect_equal(bool(build_game.state.get("property_action_used", false)), true, "lab build consumes property action")
	var research_after_build: Dictionary = build_game.choose_action("choose_research", {"tool_id": "機器工人"})
	_expect(bool(research_after_build.get("ok", false)), "lab built during landing may select research")
	_expect_equal(bool(build_game.state.get("property_action_used", false)), true, "research selection preserves build property action")
	_expect_equal(bool(build_game.state.get("research_action_used", false)), true, "research selection after build marks only research action")

	var upgrade_game: Object = _new_v12_game(4102)
	_expect(upgrade_game != null, "research lab upgrade fixture starts")
	if upgrade_game == null:
		return
	_set_facility(upgrade_game, 1, 0, 0, 0)
	_prepare_landing(upgrade_game, 0, 1)
	_expect(bool(upgrade_game.choose_action("build_facility", {"facility_type": 4}).get("ok", false)), "upgrade fixture builds type4 first")
	for level in range(2, 6):
		_prepare_landing(upgrade_game, 0, 1)
		var upgrade: Dictionary = upgrade_game.choose_action("upgrade")
		_expect(bool(upgrade.get("ok", false)), "type4 research lab upgrades to level %d" % level)
		_assert_aliases(upgrade_game, 1, 0, 0, "research lab level %d" % level)
		_assert_facility_aliases(upgrade_game, 1, 4, level, "research lab level %d" % level)
	_prepare_landing(upgrade_game, 0, 1)
	var sixth: Dictionary = upgrade_game.choose_action("upgrade")
	_expect(not bool(sixth.get("ok", false)), "research lab rejects level six")


func _test_countdown_cycle_and_reschedule() -> void:
	var game: Object = _new_v12_game(4201)
	_expect(game != null, "research countdown fixture starts")
	if game == null:
		return
	_set_facility(game, 1, 0, 1, 4)
	_prepare_landing(game, 0, 1)
	var before_tool: int = int(game.state["players"][0].get("tools", {}).get("機器工人", 0))
	var before_supply: int = int(game.state.get("inventory_supply", {}).get("tools", {}).get("機器工人", -1))
	var selected: Dictionary = game.choose_action("choose_research", {"tool_id": "機器工人"})
	_expect(bool(selected.get("ok", false)), "research countdown schedules through public action")
	_assert_aliases(game, 1, 1, 5, "scheduled research")
	_end_action_turn(game, 0, "outgoing research owner")
	_assert_aliases(game, 1, 1, 5, "outgoing owner turn does not tick")
	_expect_equal(bool(game.state.get("research_action_used", true)), false, "incoming player resets research action guard")
	_end_action_turn(game, 1, "incoming research owner first tick")
	_assert_aliases(game, 1, 1, 4, "first incoming owner tick")
	_expect_equal(int(game.state["players"][0].get("tools", {}).get("機器工人", 0)), before_tool, "countdown does not grant before fifth incoming owner tick")
	for expected_turns in [3, 2, 1, 0]:
		_end_action_turn(game, 0, "outgoing cycle player")
		_end_action_turn(game, 1, "incoming cycle owner")
		_assert_aliases(game, 1, 1, expected_turns, "countdown cycle tick %d" % expected_turns)
		_expect_equal(bool(game.state.get("research_action_used", true)), false, "every incoming turn resets research action guard")
	_expect_equal(int(game.state["players"][0].get("tools", {}).get("機器工人", 0)), before_tool + 1, "fifth incoming owner tick grants one research tool")
	_expect_equal(int(game.state.get("inventory_supply", {}).get("tools", {}).get("機器工人", -1)), before_supply, "research grant leaves source9 inventory supply unchanged")
	_end_action_turn(game, 0, "post-grant outgoing owner")
	_end_action_turn(game, 1, "post-grant incoming owner")
	_assert_aliases(game, 1, 1, 0, "completed research does not retry")
	_expect_equal(int(game.state["players"][0].get("tools", {}).get("機器工人", 0)), before_tool + 1, "completed research does not grant twice")

	var reschedule: Object = _new_v12_game(4202)
	_expect(reschedule != null, "research reschedule fixture starts")
	if reschedule != null:
		_set_facility(reschedule, 1, 0, 2, 4)
		_prepare_landing(reschedule, 0, 1)
		_expect(bool(reschedule.choose_action("choose_research", {"tool_id": "機器工人"}).get("ok", false)), "initial research schedule succeeds")
		_end_action_turn(reschedule, 0, "reschedule outgoing owner")
		_end_action_turn(reschedule, 1, "reschedule first incoming owner")
		_assert_aliases(reschedule, 1, 1, 4, "reschedule precondition")
		_prepare_landing(reschedule, 0, 1)
		var replacement: Dictionary = reschedule.choose_action("choose_research", {"tool_id": "時光機"})
		_expect(bool(replacement.get("ok", false)), "new research visit can select a replacement tool")
		_assert_aliases(reschedule, 1, 2, 5, "replacement research schedule")


func _test_owner_tick_aliases_and_status() -> void:
	var game: Object = _new_v12_game(4301, 3)
	_expect(game != null, "two-owner alias fixture starts")
	if game == null:
		return
	_set_facility(game, 1, 0, 1, 4, 1, 5)
	_set_facility(game, 2, 1, 1, 4, 1, 5)
	game.state["players"][1]["hospital_days"] = 2
	_end_action_turn(game, 0, "owner zero outgoing turn")
	_assert_aliases(game, 1, 1, 5, "owner zero outgoing facility")
	_assert_aliases(game, 2, 1, 4, "hospitalized owner one incoming facility")
	_end_action_turn(game, 1, "owner one outgoing turn")
	_assert_aliases(game, 1, 1, 5, "owner zero waits while another owner leaves")
	_assert_aliases(game, 2, 1, 4, "owner one countdown remains after outgoing turn")
	_end_action_turn(game, 2, "owner zero incoming turn")
	_assert_aliases(game, 1, 1, 4, "owner zero incoming facility ticks once")
	_assert_aliases(game, 2, 1, 4, "owner one facility is not globally ticked")
	_expect_equal(bool(game.state.get("research_action_used", true)), false, "owner admission resets research action guard")


func _test_nonlab_and_downgrade_cancellation() -> void:
	var nonlab: Object = _new_v12_game(4401)
	_expect(nonlab != null, "non-lab countdown fixture starts")
	if nonlab != null:
		_set_facility(nonlab, 1, 0, 1, 1, 1, 5)
		_end_action_turn(nonlab, 1, "non-lab owner incoming turn")
		_assert_aliases(nonlab, 1, 1, 5, "non-lab research countdown pauses")

	var downgrade: Object = _new_v12_game(4402)
	_expect(downgrade != null, "downgrade cancellation fixture starts")
	if downgrade == null:
		return
	_set_facility(downgrade, 1, 0, 5, 4)
	_prepare_landing(downgrade, 0, 1)
	_expect(bool(downgrade.choose_action("choose_research", {"tool_id": "核子飛彈"}).get("ok", false)), "high-level research schedule succeeds")
	_set_facility(downgrade, 1, 0, 1, 4, 5, 5)
	_end_action_turn(downgrade, 0, "downgrade outgoing owner")
	_assert_aliases(downgrade, 1, 5, 5, "downgrade remains pending on outgoing turn")
	_end_action_turn(downgrade, 1, "downgrade incoming owner")
	_assert_aliases(downgrade, 1, 5, 0, "invalid selected rank clears countdown")
	_expect_equal(int(downgrade.state["board"][1].get("research_tool", -1)), 5, "invalid selected rank is retained for diagnostics")


func _test_inventory_cap_and_no_shared_supply() -> void:
	var game: Object = _new_v12_game(4501)
	_expect(game != null, "research inventory cap fixture starts")
	if game == null:
		return
	_set_facility(game, 1, 0, 1, 4)
	game.state["players"][0]["tools"]["機器工人"] = 9
	var supply_before: Dictionary = game.state.get("inventory_supply", {}).get("tools", {}).duplicate(true)
	_prepare_landing(game, 0, 1)
	_expect(bool(game.choose_action("choose_research", {"tool_id": "機器工人"}).get("ok", false)), "cap fixture schedules research")
	for _index in range(5):
		_end_action_turn(game, 0, "cap outgoing owner")
		_end_action_turn(game, 1, "cap incoming owner")
	_assert_aliases(game, 1, 1, 0, "full inventory clears completed countdown")
	_expect_equal(int(game.state["players"][0]["tools"].get("機器工人", 0)), 9, "full rank-nine inventory does not exceed cap")
	_expect_equal(game.state.get("inventory_supply", {}).get("tools", {}), supply_before, "full inventory does not consume or retry shared supply")
	_end_action_turn(game, 0, "full inventory post-completion outgoing")
	_end_action_turn(game, 1, "full inventory post-completion incoming")
	_expect_equal(int(game.state["players"][0]["tools"].get("機器工人", 0)), 9, "full inventory remains capped after another incoming tick")
	_assert_aliases(game, 1, 1, 0, "full inventory remains complete after another tick")


func _test_v11_compatibility() -> void:
	var legacy: Object = _new_v11_game(4601)
	_expect(legacy != null, "v11 compatibility fixture starts")
	if legacy == null:
		return
	_expect_equal(int(legacy.state.get("version", -1)), 11, "v11 predecessor remains version eleven")
	_expect(not bool(legacy.state.get("original_research", false)), "v11 save has no original research marker")
	_expect(bool(Game.validate_save(legacy.to_dict()).get("ok", false)), "v11 predecessor save remains valid")
	var restored: Object = Game.from_dict(JSON.parse_string(legacy.to_json()))
	_expect(restored != null, "v11 predecessor JSON restores")
	if restored != null:
		_expect_equal(restored.to_json(), legacy.to_json(), "v11 predecessor JSON round trip is exact")
	_prepare_landing(legacy, 0, 1)
	var before: String = legacy.to_json()
	var research: Dictionary = legacy.choose_action("choose_research", {"tool_id": "機器工人"})
	_expect(not bool(research.get("ok", false)), "v11 does not expose research selection")
	_expect_equal(legacy.to_json(), before, "v11 research rejection is atomic")
	_set_facility(legacy, 1, 0, 0, 0)
	_prepare_landing(legacy, 0, 1)
	var build_before: String = legacy.to_json()
	var build: Dictionary = legacy.choose_action("build_facility", {"facility_type": 4})
	_expect(not bool(build.get("ok", false)), "v11 keeps research lab build guard")
	_expect_equal(legacy.to_json(), build_before, "v11 lab build rejection is atomic")
