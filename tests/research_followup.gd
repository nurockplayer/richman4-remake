extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/research_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func make_game(legacy: bool = false, seed_value: int = 4521) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.v11_game_options() if legacy else Fixture.new_game_options())
	expect(game != null, "followup fixture starts")
	game.state.god_objects = []
	for id in range(4): game.set_player_ai(id, false)
	return game
func land(game: Object, owner: int, type: int, level: int) -> void:
	game._update_facility_records(1, {"owner": owner, "facility_type": type, "building_level": level})
	if owner >= 0: game.state.players[owner].properties = [1]
	game.state.players[0].position = 0
	game.state.players[0].previous_position = -1
	game.state.players[0].turtle_days = 1
	game._recalculate_property_values()
	expect(game.roll().get("ok", false), "public one-step roll")
	if game.state.phase == "await_route": expect(game.choose_route(1).get("ok", false), "public facility route")
	expect(game.state.phase == "await_action" and game.state.players[0].position == 1, "actual facility landing")
func _initialize() -> void:
	for legacy in [false, true]:
		for god in [3, 4]:
			var game: Object = make_game(legacy)
			land(game, -1, 0, 0)
			game.state.players[0].god_id = god
			game.state.god_objects = [{"id":god,"node":1,"owner":0,"days":3}]
			game._set_action_options(0)
			var before: String = game.to_json()
			var result: Dictionary = game.choose_action("buy", {"facility_type":4})
			expect(bool(result.get("ok", false)) == not legacy, "fortune lab purchase follows version")
			if legacy:
				expect(game.to_json() == before, "v11 rejected lab buy is atomic")
			else:
				expect(game.state.board[1].owner == 0 and game.state.board[1].facility_type == 4 and game.state.board[1].building_level == 1, "fortune purchase constructs owned lab")
				expect(game.state.board[6].facility_type == 4 and game.state.board[6].building_level == 1, "fortune purchase updates alias")
				expect(game.choose_action("choose_research", {"tool_id":"機器工人"}).get("ok", false), "fortune buyer chooses product on actual visit")
				expect(Game.from_dict(JSON.parse_string(game.to_json())) != null, "fortune buy JSON reload")
	for legacy in [false, true]:
		var ai: Object = make_game(legacy)
		land(ai, 0, 4, 0)
		ai.set_player_ai(0, true)
		var mirror: Object = Game.from_dict(JSON.parse_string(ai.to_json()))
		expect(mirror != null, "AI empty type4 snapshot reloads")
		var result: Dictionary = ai.run_ai_turn()
		expect(result.get("ok", false) and result.get("completed", false), "AI builds and completes turn")
		expect(ai.state.board[1].facility_type == (1 if legacy else 4) and ai.state.board[1].building_level == 1, "AI preserves v12 lab / v11 fallback")
		if not legacy: expect(ai.state.board[1].research_tool == 1 and ai.state.board[1].research_turns == 5, "AI newly built lab starts production")
		if mirror != null:
			mirror.run_ai_turn()
			expect(ai.to_json() == mirror.to_json(), "AI construction JSON replay exact")
	var stayed: Object = make_game()
	land(stayed, 0, 4, 1)
	stayed.choose_action("choose_research", {"tool_id":"機器工人"})
	# Return via public turn admissions, then apply the real stay card.
	expect(stayed.end_turn().get("ok", false), "end owner turn")
	for other_id in range(1, 4):
		stayed.set_player_ai(other_id, true)
		expect(stayed.run_ai_turn().get("completed", false), "advance intervening player")
	expect(stayed.state.current_player == 0 and stayed.state.phase == "await_roll", "owner admitted before stay")
	expect(Inventory.grant_card(stayed.state.inventory_supply, stayed.state.players[0].cards, "停留").get("ok", false), "grant real stay card")
	stayed._set_action_options(0)
	expect(stayed.choose_action("use_card", {"card_id":"停留", "target_id":0}).get("ok", false), "use public stay card")
	var countdown: int = stayed.state.board[1].research_turns
	expect(stayed.roll().get("ok", false), "stay roll resolves")
	expect(stayed.state.players[0].position == 1 and stayed.state.last_roll_total > 0, "stay retains positive dice without movement")
	expect(not stayed.state.action_options.has("choose_research"), "stay turn has no research action")
	var before: String = stayed.to_json()
	expect(not stayed.choose_action("choose_research", {"tool_id":"機器工人"}).get("ok", false), "stay cannot restart product")
	expect(stayed.to_json() == before and stayed.state.board[1].research_turns == countdown, "stay refusal is atomic and retains countdown")
	var restored: Object = Game.from_dict(JSON.parse_string(before))
	expect(restored != null, "stay save reloads")
	if restored != null:
		expect(not restored.state.action_options.has("choose_research"), "loaded stay retains blocked action")
		expect(not restored.choose_action("choose_research", {"tool_id":"機器工人"}).get("ok", false), "loaded stay API remains blocked")
	stayed.end_turn()
	for count in range(3): stayed.run_ai_turn()
	stayed.state.players[0].position = 0
	stayed.state.players[0].previous_position = -1
	stayed.state.players[0].turtle_days = 1
	stayed.roll()
	if stayed.state.phase == "await_route": stayed.choose_route(1)
	expect(stayed.choose_action("choose_research", {"tool_id":"機器工人"}).get("ok", false), "next actual landing can schedule again")
	var ai_labs := 0
	for seed_value in range(32):
		var game: Object = make_game(false, seed_value)
		land(game, -1, 0, 0)
		game.set_player_ai(0, true)
		game.state.players[0].god_id = 3
		game.state.god_objects = [{"id":3,"node":1,"owner":0,"days":3}]
		game._set_action_options(0)
		expect(game.choose_action("buy").get("ok", false), "AI fortune random facility purchase")
		if game.state.board[1].facility_type == 4: ai_labs += 1
	expect(ai_labs > 0, "AI fortune selection includes laboratories")
	print("Research followup checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
