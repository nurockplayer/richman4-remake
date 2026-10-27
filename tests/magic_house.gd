extends SceneTree
## Source event 16 (魔法屋): target groups, human choice, AI draw, effects,
## and save validation. docs/original-landing-events.md.

const Game = preload("res://game/core/game_state.gd")
const StatusFixture = preload("res://tests/fixtures/status_fixture.gd")
const MagicHouse = preload("res://game/core/source_magic_house.gd")
var MAGIC_NODE := -1

var checks := 0
var failures := 0


func _initialize() -> void:
	run()
	print("Magic house checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func make_game() -> Object:
	var definition: Dictionary = StatusFixture.definition()
	MAGIC_NODE = 1  # the fixture's points node; ordinary road with no company
	definition.board[MAGIC_NODE].merge({"kind": "unsupported", "event_code": 16, "source_status_bits": 16, "name": "魔法屋（待還原）"}, true)
	definition.board[MAGIC_NODE].erase("points")
	var game: Object = Game.new_game_on_board(2718, 4, definition, {
		"original_inventory": true, "original_facilities": true, "original_gods": true,
		"original_companies": true, "original_statuses": true, "day_limit": 30,
		"start_date": {"year": 1998, "month": 1, "day": 1},
	})
	if game == null:
		return null
	game.state["god_objects"] = []
	for player_id in range(1, 4):
		game.set_player_ai(player_id, true)
	return game


func open_visit(game: Object, targets: Array) -> int:
	var sequence := int(game.state.magic_house_sequence) + 1
	game.state.magic_house_sequence = sequence
	game.state.current_player = 0
	game.state.players[0].position = MAGIC_NODE
	game.state.magic_house = {"visit_id": sequence, "player_id": 0, "node_id": MAGIC_NODE, "turn": int(game.state.turn), "group_id": 3, "targets": targets}
	game.state.phase = "await_magic_house"
	game.state.action_options = []
	return sequence


func run() -> void:
	var game: Object = make_game()
	expect(game != null, "status/company fixture game starts")
	if game == null:
		return
	expect(MagicHouse.enabled(game) and int(game.state.get("magic_house_sequence", -1)) == 0, "complete source rules enable the magic house")
	expect(str(game.state.board[MAGIC_NODE].name) == "魔法屋", "live magic house node drops the unrestored suffix")

	# Save/load of a pending visit, on an untouched game so every other save
	# invariant still holds.
	var clean: Object = make_game()
	clean.state.current_player = 0
	clean.state.players[0].position = MAGIC_NODE
	clean._graph_visit_tile(0, clean.state.board[MAGIC_NODE], true)
	var saved: Dictionary = Game.validate_save(JSON.parse_string(clean.to_json()))
	var restored: Object = Game.from_dict(JSON.parse_string(clean.to_json()))
	expect(clean.state.phase == "await_magic_house" and bool(saved.get("ok", false)) and restored != null and restored.state.phase == "await_magic_house", "pending magic house survives save/load: %s" % [saved.get("errors", [])])

	# Target groups: highest value with ties; zero only qualifies for wealth.
	var players: Array = game.state.players
	for index in range(4):
		players[index].cash = [500, 900, 900, 0][index]
		players[index].points = 0
		players[index].character_id = [3, 0, 1, 2][index]
	players[1].vehicle = "car"
	expect(MagicHouse.group_members(game, 3) == [1, 2], "richest-cash group keeps ties in player order")
	expect(MagicHouse.group_members(game, 5).is_empty(), "all-zero points group is empty")
	expect(MagicHouse.group_members(game, 8) == [1], "car group lists drivers")
	expect(MagicHouse.group_members(game, 11) == [0], "female group follows the character roster")
	expect(MagicHouse.group_members(game, 10) == [1, 2, 3], "male group follows the character roster")

	# Human landing waits for a choice; nothing else can act meanwhile.
	game.state.current_player = 0
	players[0].position = MAGIC_NODE
	game.state.phase = "await_action"
	game._graph_visit_tile(0, game.state.board[MAGIC_NODE], true)
	var snapshot: Dictionary = game.magic_house_snapshot()
	expect(game.state.phase == "await_magic_house" and not snapshot.is_empty(), "human landing opens a pending magic house")
	expect(snapshot.get("effects", []).size() == 12 and str(snapshot.get("group", "")) != "", "snapshot names the group and all twelve effects")
	expect(game.state.action_options == [], "pending magic house offers no ordinary actions")
	expect(not bool(game.end_turn().get("ok", true)), "turn cannot end before choosing")
	expect(not bool(game.choose_magic_house_effect(int(snapshot.visit_id), 11).get("ok", true)), "unrestored effects are refused")
	expect(not bool(game.choose_magic_house_effect(int(snapshot.visit_id) + 7, 4).get("ok", true)), "stale visit id is refused")

	# Effect 4: every target deposits all cash.
	var visit_id := open_visit(game, [1, 2])
	var deposits := [int(players[1].deposit), int(players[2].deposit)]
	expect(bool(game.choose_magic_house_effect(visit_id, 4).get("ok", false)), "deposit effect resolves")
	expect(int(players[1].cash) == 0 and int(players[1].deposit) == deposits[0] + 900 and int(players[2].deposit) == deposits[1] + 900, "targets deposit all their cash")
	expect(int(players[0].cash) == 500, "caster outside the group is untouched")
	expect(game.state.phase == "await_action" and game.state.magic_house.is_empty(), "choice returns to the action phase")

	# Effect 0: cards sell at their listed point price and return to supply.
	players[1].cards.clear()
	game._grant_card(1, "均富")
	game._grant_card(1, "停留")
	var supply_before := int(game.state.inventory_supply.cards["均富"])
	visit_id = open_visit(game, [1])
	game.choose_magic_house_effect(visit_id, 0)
	expect(players[1].cards.is_empty() and int(players[1].points) == 220, "selling all cards pays 200 + 20 points")
	expect(int(game.state.inventory_supply.cards["均富"]) == supply_before + 1, "sold cards return to the shared supply")

	# Effect 8: the active car goes back and sells with the tools.
	players[2].points = 0
	players[2].tools = {}
	OriginalInventoryHelper.grant(game, 2, "路障", 2)
	players[2].vehicle = "car"
	visit_id = open_visit(game, [2])
	game.choose_magic_house_effect(visit_id, 8)
	expect(int(players[2].points) == 2 * 30 + 150 and players[2].tools.is_empty() and str(players[2].vehicle) == "walking", "selling all tools includes the active car")

	# Effect 2: 免罪 cancels the prison stay and is consumed.
	players[3].cards.clear()
	game._grant_card(3, "免罪")
	visit_id = open_visit(game, [3])
	game.choose_magic_house_effect(visit_id, 2)
	expect(int(players[3].get("prison_days", 0)) == 0 and not players[3].cards.has("免罪"), "免罪 blocks the magic-house prison")
	visit_id = open_visit(game, [3])
	game.choose_magic_house_effect(visit_id, 2)
	expect(int(players[3].get("prison_days", 0)) == 3, "without 免罪 the target is jailed for three days")

	# Effect 3 and 7 reuse the card helpers.
	visit_id = open_visit(game, [1])
	game.choose_magic_house_effect(visit_id, 3)
	expect(int(players[1].get("stay_next", 0)) >= 1, "stay effect holds the target one turn")

	# AI: resolves on landing without a pending phase.
	game.set_player_ai(0, true)
	game.state.phase = "await_action"
	game.state.magic_house = {}
	var events_before: int = game.state.event_log.size()
	game._graph_visit_tile(0, game.state.board[MAGIC_NODE], true)
	var cast := false
	for event in game.state.event_log.slice(events_before):
		cast = cast or str(event.get("type", "")) == "magic_house_cast"
	expect(game.state.phase != "await_magic_house" and cast, "AI casts on landing without waiting")

	# Validation rejects a visit outside its phase.
	var bad: Dictionary = JSON.parse_string(game.to_json())
	bad.magic_house = {"visit_id": 1, "player_id": 0, "node_id": MAGIC_NODE, "turn": int(bad.turn), "group_id": 0, "targets": [0]}
	expect(not bool(Game.validate_save(bad).get("ok", true)), "a magic house visit outside its phase is rejected")


class OriginalInventoryHelper:
	static func grant(game: Object, player_id: int, tool_id: String, quantity: int) -> void:
		preload("res://game/core/inventory_rules.gd").grant_tool(game.state.inventory_supply, game.state.players[player_id].tools, tool_id, quantity)
