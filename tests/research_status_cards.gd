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
func make_game(owner: int, options: Dictionary) -> Object:
	var game: Object = Game.new_game_on_board(94715, 4, Fixture.definition(), options)
	expect(game != null, "status-card fixture starts")
	if game == null: return null
	game.state.god_objects = []
	game.state.players[owner].properties = [1]
	var fields := {"owner": owner, "facility_type": 4, "building_level": 3}
	if game.state.version == 12:
		fields["research_tool"] = 2
		fields["research_turns"] = 3
	game._update_facility_records(1, fields)
	game._recalculate_property_values()
	game._set_action_options(0)
	return game
func _initialize() -> void:
	for card in ["漲價", "查封"]:
		var owner := 0 if card == "漲價" else 1
		var game: Object = make_game(owner, Fixture.new_game_options())
		if game == null: continue
		expect(Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, card).get("ok", false), "grant status card through shared inventory")
		game._set_action_options(0)
		expect(game.inventory_target_tiles(card).has(1), "v12 status target API includes the laboratory")
		var before_count: int = game.state.players[0].cards.count(card)
		expect(game.choose_action("use_card", {"card_id": card, "tile_id": 1}).get("ok", false), "public status card accepts a built laboratory")
		expect(game.state.players[0].cards.count(card) == before_count - 1, "accepted status card consumes exactly once")
		for index in [1, 6]:
			expect(game.state.board[index].facility_state == (0x50 if card == "漲價" else 0x51), "status reaches every physical-facility alias")
			expect(game.state.board[index].research_tool == 2, "status card preserves selected product rank")
			expect(game.state.board[index].research_turns == (3 if card == "漲價" else 0), "raise preserves countdown while direct seal cancels it")
		expect(Game.validate_save(game.to_dict()).get("ok", false), "status-card result is a valid save")
		expect(Game.from_dict(JSON.parse_string(game.to_json())) != null, "status-card result JSON reloads")
		game.state.current_player = owner
		game.state.players[owner].position = 1
		game.state.phase = "await_action"
		game.state.last_roll = [1]
		game.state.last_total = 1
		game.state.last_roll_total = 1
		game._set_action_options(owner)
		var before: String = game.to_json()
		var result: Dictionary = game.choose_action("choose_research", {"tool_id": "機器工人"})
		expect(result.get("ok", false) == (card == "漲價"), "raised lab permits selection while sealed lab rejects it")
		if card == "查封": expect(game.to_json() == before, "sealed selection rejection is atomic")
		var old: Object = make_game(owner, Fixture.v11_game_options())
		if old == null: continue
		expect(Inventory.grant_card(old.state.inventory_supply, old.state.players[0].cards, card).get("ok", false), "grant legacy status card")
		old._set_action_options(0)
		var old_before: String = old.to_json()
		expect(not old.inventory_target_tiles(card).has(1), "v11 retains prior lab target exclusion")
		expect(not old.choose_action("use_card", {"card_id": card, "tile_id": 1}).get("ok", false), "v11 direct lab target stays rejected")
		expect(old.to_json() == old_before, "v11 rejection preserves state and card")
	print("Research status-card checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
