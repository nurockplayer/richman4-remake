extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/fate_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func stage(id: int) -> Object:
	var game: Object = Fixture.new_game(561234)
	var order: Array = [id]
	for candidate in range(37):
		if candidate != id: order.append(candidate)
	game.state.fate = {"order": order, "cursor": 0, "draw_count": 0, "last": {}}
	return game

func verify(game: Object, label: String) -> void:
	var valid: Dictionary = Game.validate_save(game.to_dict())
	check(valid.get("ok", false), label + " validates: " + str(valid.get("errors", [])))
	var mirror: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	check(mirror != null and mirror.to_json() == game.to_json(), label + " JSON round-trip")

func vehicle(game: Object, id: int, name: String) -> void:
	var player: Dictionary = game.state.players[id]
	var tool := "機車" if name == "motorcycle" else "汽車"
	player.vehicle = name
	player.dice_count = 2 if name == "motorcycle" else 3
	player.vehicles[name] = true
	player.tools[tool] = 0
	game.state.inventory_supply.tools[tool] = int(game.state.inventory_supply.tools[tool]) - 1

func _initialize() -> void:
	for id in [0, 1]:
		for god in [0, 1, 2, 6]:
			var game: Object = stage(id)
			var tile: Dictionary = game.state.board[2]
			tile.owner = 0
			tile.building_level = 1 if id == 0 else 0
			tile.is_chain_store = id == 0
			game.state.players[0].properties = [2]
			game._update_tile_rent(tile)
			game._recalculate_property_values()
			if god > 0:
				game.state.players[0].god_id = god
				game.state.god_objects = [{"id": god, "node": int(game.state.players[0].position), "owner": 0, "days": 7}]
			verify(game, "housing input")
			var cash: int = int(game.state.players[0].cash)
			var amount: int = int(tile.house_price if id == 0 else tile.land_price)
			var expected_rng := RandomNumberGenerator.new()
			expected_rng.state = game._rng.state
			expected_rng.randi_range(0, 0)
			game._graph_visit_tile(0, game.state.board.back(), true)
			check(int(game.state.players[0].cash) == cash + amount, "housing sale ignores attached god cash modifiers")
			check(int(game.state.fate.last.gate_result) == 0 and game.state.fate.last.outcome == "applied", "housing fate has no god gate")
			check(game._rng.state == expected_rng.state, "housing selection consumes no additional god RNG")
			check(int(tile.building_level) == 0 and not tile.is_chain_store, "housing sale clears the chain flag with the building")
			check(int(tile.owner) == (0 if id == 0 else -1), "housing retains or releases its owner as specified")
			verify(game, "housing result")
	var walking: Object = stage(16)
	verify(walking, "walking traffic input")
	var cash: int = int(walking.state.players[0].cash)
	var position: int = int(walking.state.players[0].position)
	walking._graph_visit_tile(0, walking.state.board.back(), true)
	check(int(walking.state.fate.last.id) == 14 and int(walking.state.fate.last.raw_amount) == 3000 * int(walking.state.price_index), "walking candidate16 remaps to cash fine14")
	check(int(walking.state.players[0].cash) == cash - 3000 * int(walking.state.price_index), "walking candidate16 pays its fine")
	check(int(walking.state.players[0].hospital_days) == 0 and int(walking.state.players[0].position) == position, "walking candidate16 never uses candidate15 hospital fallback")
	verify(walking, "walking traffic result")
	var redirected: Object = stage(13)
	vehicle(redirected, 0, "motorcycle")
	vehicle(redirected, 1, "car")
	check(Inventory.grant_card(redirected.state.inventory_supply, redirected.state.players[0].cards, "嫁禍").get("ok", false), "redirect fixture grants finite defense")
	verify(redirected, "redirect input")
	var actor_before: Dictionary = redirected.state.players[0].duplicate(true)
	var supply: Dictionary = redirected.state.inventory_supply.tools.duplicate(true)
	redirected._graph_visit_tile(0, redirected.state.board.back(), true)
	check(redirected.state.players[0].vehicle == "motorcycle" and int(redirected.state.players[0].dice_count) == 2, "redirect preserves the original actor vehicle")
	check(int(redirected.state.players[0].hospital_days) == 0 and int(redirected.state.players[0].position) == int(actor_before.position), "redirect keeps original actor out of hospital")
	check(redirected.state.players[1].vehicle == "walking" and int(redirected.state.players[1].dice_count) == 1 and int(redirected.state.players[1].hospital_days) == 3, "actual hospital target loses its active vehicle")
	check(int(redirected.state.inventory_supply.tools["汽車"]) == int(supply["汽車"]) + 1 and int(redirected.state.inventory_supply.tools["機車"]) == int(supply["機車"]), "redirect returns only the actual target finite vehicle")
	check(not redirected.state.players[0].cards.has("嫁禍"), "redirect still consumes defense exactly once")
	verify(redirected, "redirect result")
	print("Fate contract checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
