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
func make_game() -> Object:
	var game: Object = Game.new_game_on_board(39612, 4, Fixture.definition(), Fixture.new_game_options())
	expect(game != null, "landing starts v12 factory")
	if game == null: return null
	game.state.god_objects = []
	game.state.players[0].properties = [1]
	game.state.players[0].position = 0
	game.state.players[0].previous_position = -1
	game._update_facility_records(1, {"owner": 0, "facility_type": 4, "building_level": 1})
	game._recalculate_property_values()
	game._set_action_options(0)
	return game
func _initialize() -> void:
	for mode in ["existing", "build", "remodel"]:
		var game: Object = make_game()
		if game == null: continue
		if mode != "existing":
			game._update_facility_records(1, {"facility_type": 0, "building_level": 0 if mode == "build" else 1})
			game._recalculate_property_values()
		game.state.players[0].turtle_days = 1
		expect(game.roll().get("ok", false), "public roll begins research visit")
		if game.state.phase == "await_route":
			expect(game.choose_route(1).get("ok", false), "public route chooses facility entrance")
		expect(game.state.phase == "await_action" and game.state.players[0].position == 1, "public movement settles on facility")
		if mode == "build":
			expect(game.choose_action("build_facility", {"facility_type": 4}).get("ok", false), "build lab after public landing")
		elif mode == "remodel":
			expect(Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, "改建").get("ok", false), "stage remodel card")
			game._set_action_options(0)
			expect(game.choose_action("use_card", {"card_id": "改建", "facility_type": 4}).get("ok", false), "remodel lab after public landing")
		expect(game.state.action_options.has("choose_research"), mode + " landing exposes research action")
		expect(game.choose_action("choose_research", {"tool_id": "機器工人"}).get("ok", false), mode + " actual visit selects product")
		expect(game.state.board[1].research_turns == 5 and game.state.board[6].research_turns == 5, "actual visit synchronizes countdown")
		var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		expect(restored != null and restored.to_json() == game.to_json(), "actual landing and research reload exactly")
	var skipped: Object = make_game()
	if skipped != null:
		skipped.state.players[0].position = 1
		skipped.state.players[0].skip_turns = 1
		expect(skipped.roll().get("ok", false), "public roll resolves skipped turn")
		expect(not skipped.state.action_options.has("choose_research"), "skipped turn is not a research visit")
		var before: String = skipped.to_json()
		expect(not skipped.choose_action("choose_research", {"tool_id": "機器工人"}).get("ok", false), "skipped turn cannot select research")
		expect(skipped.to_json() == before, "skipped-turn rejection is atomic")
	print("Research landing checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
