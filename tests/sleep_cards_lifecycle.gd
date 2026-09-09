extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")
var checks := 0
var failures := 0
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func fresh(seed_value: int) -> Object:
	var g: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.new_game_options())
	g.state.god_objects = []
	for id in range(4):
		g.set_player_ai(id, false)
		g.state.players[id].position = 1
		g.state.players[id].previous_position = -1
	expect(Game.validate_save(g.to_dict()).get("ok", false), "fresh legal lifecycle fixture")
	return g
func turn(g: Object, id: int, phase: String = "await_roll") -> void:
	g.state.current_player = id
	g.state.phase = phase
	g.state.last_roll = []
	g.state.last_total = 0
	g.state.last_roll_total = 0
	g.state.property_action_used = false
	g.state.bank_access = false
	g.state.bank_landing = false
	g._set_action_options(id)
func card(g: Object, id: int, name: String) -> void:
	expect(Inventory.grant_card(g.state.inventory_supply, g.state.players[id].cards, name).get("ok", false), "grant " + name)
	g._set_action_options(int(g.state.current_player))
func cast(g: Object, name: String, target: int = 1) -> bool:
	legal(g, "before public " + name)
	var result: Dictionary = g.choose_action("use_card", {"card_id": name, "target_id": target})
	expect(result.get("ok", false), "public " + name + " succeeds")
	return result.get("ok", false)
func driver(g: Object) -> Dictionary:
	if not g.has_method("run_sleep_turn"):
		expect(false, "sleep driver exists")
		return {}
	return g.call("run_sleep_turn")
func legal(g: Object, name: String) -> void:
	expect(Game.validate_save(g.to_dict()).get("ok", false), name + " legal save")
	var loaded: Object = Game.from_dict(JSON.parse_string(g.to_json()))
	expect(loaded != null and loaded.to_json() == g.to_json(), name + " exact JSON")
func equip_car(g: Object) -> void:
	turn(g, 1)
	expect(Inventory.grant_tool(g.state.inventory_supply, g.state.players[1].tools, "汽車").get("ok", false), "grant car")
	expect(g.set_vehicle("car", 2).get("ok", false), "equip car with chosen two dice")
	turn(g, 0)
func _initialize() -> void:
	winter()
	dream_restore(false)
	dream_restore(true)
	replace_dream()
	engineering()
	detention()
	rent(false)
	rent(true)
	print("Sleep lifecycle checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
func winter() -> void:
	var g := fresh(69101)
	card(g, 0, "冬眠")
	if not cast(g, "冬眠"): return
	var position: int = int(g.state.players[1].position)
	for count in [4, 3, 2, 1, 128]:
		turn(g, 1)
		var result := driver(g)
		expect(result.get("ok", false), "winter auto skip succeeds")
		expect(int(g.state.players[1].winter_sleep_days) == count, "winter decrements exactly once per own turn")
		expect(int(g.state.players[1].position) == position, "winter never moves")
		expect(int(g.state.current_player) == 2, "winter hands off turn")
		legal(g, "winter tick")
	turn(g, 1)
	var before_rng: String = str(g.state.rng_state_text)
	var released := driver(g)
	expect(released.get("ok", false), "winter marker releases")
	expect(int(g.state.players[1].get("winter_sleep_days", 0)) == 0, "winter marker cleared")
	expect(int(g.state.current_player) == 1 and g.state.phase == "await_roll", "awake human keeps pre-roll control")
	expect(str(g.state.rng_state_text) == before_rng, "waking does not roll RNG")
func dream_restore(stolen: bool) -> void:
	var g := fresh(69103 if stolen else 69102)
	equip_car(g)
	card(g, 0, "夢遊")
	card(g, 0, "搶奪")
	if not cast(g, "夢遊"): return
	expect(g.state.players[1].vehicle == "walking" and int(g.state.players[1].tools.get("汽車", 0)) == 1, "dream returns equipped car into backpack")
	if stolen:
		var theft: Dictionary = g.choose_action("use_card", {"card_id": "搶奪", "target_id": 1, "item_kind": "tool", "item_id": "汽車"})
		expect(theft.get("ok", false), "public theft can take dream vehicle from backpack")
	g.state.players[1].dream_days = 128
	turn(g, 1)
	legal(g, "dream release marker")
	var result := driver(g)
	expect(result.get("ok", false), "dream wakes")
	expect(g.state.players[1].vehicle == ("walking" if stolen else "car"), "restore requires held car")
	expect(int(g.state.players[1].dice_count) == (1 if stolen else 2), "restore keeps exact chosen dice")
	expect(not g.state.players[1].has("dream_vehicle_backup"), "release removes backup")
	expect(int(g.state.players[1].tools.get("汽車", 0)) == 0, "restored car removed from backpack once")
	legal(g, "dream released")
func replace_dream() -> void:
	var g := fresh(69104)
	equip_car(g)
	card(g, 0, "夢遊")
	card(g, 0, "夢遊")
	card(g, 0, "冬眠")
	if not cast(g, "夢遊"): return
	if not cast(g, "夢遊"): return
	expect(g.state.players[1].dream_vehicle_backup == {"previous_vehicle": "walking", "previous_dice_count": 1}, "repeat dream overwrites original car backup")
	if not cast(g, "冬眠"): return
	expect(int(g.state.players[1].get("dream_days", 0)) == 0 and not g.state.players[1].has("dream_vehicle_backup"), "winter clears dream and backup")
	expect(g.state.players[1].vehicle == "walking" and int(g.state.players[1].tools.get("汽車", 0)) == 1, "winter never restores saved vehicle")
	legal(g, "winter cancels dream")
func engineering() -> void:
	var g := fresh(69105)
	equip_car(g)
	turn(g, 1)
	expect(Inventory.grant_tool(g.state.inventory_supply, g.state.players[1].tools, "工程車").get("ok", false), "grant engineering research tool")
	g._set_action_options(1)
	expect(g.choose_action("use_tool", {"tool_id": "工程車"}).get("ok", false), "activate engineering")
	g.state.players[1].engineering_vehicle.remaining_admissions = 1
	var original: Dictionary = g.state.players[1].engineering_vehicle.duplicate(true)
	turn(g, 0)
	card(g, 0, "夢遊")
	if not cast(g, "夢遊"): return
	expect(not g.state.players[1].has("engineering_vehicle"), "dream suspends active engineering")
	expect(g.state.players[1].dream_vehicle_backup.get("engineering_vehicle", {}) == original, "dream saves complete engineering metadata")
	g._advance_to_next_alive(0)
	expect(g.state.players[1].dream_vehicle_backup.get("engineering_vehicle", {}) == original, "sleep admission freezes engineering deadline")
	g.state.players[1].dream_days = 128
	legal(g, "suspended engineering")
	var result := driver(g)
	expect(result.get("ok", false), "engineering dream wakes")
	expect(g.state.players[1].vehicle == "engineering" and g.state.players[1].get("engineering_vehicle", {}) == original, "wake restores exact engineering deadline")
	g._advance_to_next_alive(0)
	expect(g.state.players[1].vehicle == "car" and int(g.state.players[1].dice_count) == 2, "next admission expires engineering and restores held ordinary car")
	legal(g, "engineering expiry after dream")
func detention() -> void:
	var g := fresh(69106)
	card(g, 0, "夢遊")
	if not cast(g, "夢遊"): return
	expect(g._admit_player_status(1, "hospital", 2).get("ok", false), "hospital admission during dream")
	turn(g, 1)
	legal(g, "hospital with dream")
	var before: int = int(g.state.players[1].dream_days)
	var result := driver(g)
	expect(result.get("ok", false), "detained sleeper can advance")
	expect(int(g.state.players[1].dream_days) == before, "hospital pauses dream countdown")
	expect(int(g.state.players[1].hospital_days) == 1, "hospital countdown continues")
	legal(g, "paused dream")

func rent(sleeping_owner: bool) -> void:
	var g := fresh(69108 if sleeping_owner else 69107)
	var tile: Dictionary = g.state.board[2]
	expect(tile.kind == "property", "rent fixture node2 is property")
	tile.owner = 0
	g.state.players[0].properties = [2]
	tile.building_level = 1
	g._update_tile_rent(tile)
	g._recalculate_property_values()
	card(g, 0, "夢遊")
	if not cast(g, "夢遊"): return
	if sleeping_owner: g.state.players[0].winter_sleep_days = 5
	turn(g, 1)
	g.state.players[1].previous_position = 0
	g.state.players[1].turtle_days = 1
	legal(g, "rent movement fixture")
	var cash_before: int = int(g.state.players[1].cash)
	var owner_before: int = int(g.state.players[0].cash)
	var result := driver(g)
	expect(result.get("ok", false), "dream movement completes rent settlement")
	expect(int(g.state.players[1].position) == 2, "one-step dream reaches property")
	expect(int(g.state.players[1].dream_days) == 4, "normal dream turn decrements once")
	expect(int(g.state.current_player) == 2, "dream does not pause at property action")
	if sleeping_owner:
		expect(int(g.state.players[1].cash) == cash_before and int(g.state.players[0].cash) == owner_before, "sleeping owner collects no rent")
	else:
		expect(int(g.state.players[1].cash) < cash_before and int(g.state.players[0].cash) > owner_before, "dream player still pays awake landlord")
	legal(g, "dream rent settled")
