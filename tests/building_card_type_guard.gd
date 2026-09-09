extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var failures := 0
var checks := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var game: Object = Game.new_game_on_board(4414, 4, Fixture.definition(), Fixture.new_game_options())
	expect(game != null, "v13 type guard fixture starts")
	if game == null:
		quit(1)
		return
	game.state.god_objects = []
	game._update_facility_records(1, {"owner": 0, "facility_type": 4, "building_level": 4, "research_tool": 3, "research_turns": 4})
	game.state.players[0].properties = [1]
	game._recalculate_property_values()
	expect(Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, "天使").get("ok", false), "finite angel card staged")
	game._set_action_options(0)
	var before: String = game.to_json()
	var rejected: Dictionary = game.choose_action("use_card", {"card_id": "天使", "tile_id": 6, "facility_type": 0})
	expect(not rejected.get("ok", false), "angel cannot remodel an existing laboratory through a second entrance")
	expect(game.to_json() == before, "rejected type override preserves the complete state and card")
	var accepted: Dictionary = game.choose_action("use_card", {"card_id": "天使", "tile_id": 6})
	expect(accepted.get("ok", false), "existing facility needs no type selection")
	for index in [1, 6]:
		var tile: Dictionary = game.state.board[index]
		expect(tile.facility_type == 4 and tile.building_level == 5, "angel raises existing laboratory without changing its type")
		expect(tile.research_tool == 3 and tile.research_turns == 4, "angel preserves the laboratory production job")
	expect(not game.state.players[0].cards.has("天使"), "successful raise consumes exactly one card")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "type-guard continuation remains save-valid")
	print("Building card type guard: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
