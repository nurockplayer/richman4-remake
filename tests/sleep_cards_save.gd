extends SceneTree
## Issue #69 save-boundary seed on the existing v13 graph schema.
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")
const DREAM := "夢遊"
const WINTER := "冬眠"
const TRAP := "陷害"
const SCAPEGOAT := "嫁禍"
var checks := 0
var failures := 0
func _initialize() -> void:
	_public_states()
	_metadata()
	_pending()
	print("Sleep cards save checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
func eq(actual: Variant, expected: Variant, label: String) -> void:
	expect(actual == expected, label)
func fresh(seed_value: int) -> Object:
	var game: Object = Game.new_game_on_board(seed_value, 4, Fixture.definition(), Fixture.new_game_options())
	expect(game != null, "legal v13 fixture starts")
	if game == null: return null
	game.state["god_objects"] = []
	for id in range(4):
		game.set_player_ai(id, false)
		var player: Dictionary = game.state["players"][id]
		player["position"] = id
		player["previous_position"] = -1
		player["hospital_days"] = 0
		player["prison_days"] = 0
		player["god_id"] = 0
	game.state["current_player"] = 0
	game.state["phase"] = "await_action"
	game.state["property_action_used"] = false
	game.state["research_action_used"] = false
	game.call("_set_action_options", 0)
	expect(bool(Game.validate_save(game.to_dict()).get("ok", false)), "fixture preconditions validate")
	return game
func stage(game: Object, player_id: int, card_id: String) -> bool:
	var result: Dictionary = Inventory.grant_card(game.state["inventory_supply"], game.state["players"][player_id]["cards"], card_id)
	expect(bool(result.get("ok", false)), "finite grant stages " + card_id); return bool(result.get("ok", false))
func valid(data: Dictionary, label: String) -> void:
	expect(bool(Game.validate_save(data).get("ok", false)), label + " validates")
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	expect(parsed is Dictionary, label + " JSON object")
	if parsed is Dictionary:
		var restored: Object = Game.from_dict(parsed)
		expect(restored != null, label + " JSON continuation loads")
		if restored != null:
				expect(bool(Game.validate_save(restored.to_dict()).get("ok", false)), label + " continuation remains valid")
				eq(restored.to_dict(), data, label + " preserves full save fields")
func rejected(data: Dictionary, label: String) -> void:
	expect(not bool(Game.validate_save(data).get("ok", false)), label + " validator rejects")
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	if parsed is Dictionary: expect(Game.from_dict(parsed) == null, label + " loader rejects")
func base_data(seed_value: int) -> Dictionary:
	var game: Object = fresh(seed_value); return game.to_dict() if game != null else {}
func dream_data(base: Dictionary, days: int = 4, backup: Dictionary = {}) -> Dictionary:
	var data: Dictionary = base.duplicate(true)
	var player: Dictionary = data["players"][0]
	player.erase("winter_sleep_days")
	player["dream_days"] = days
	player["vehicle"] = "walking"
	player["dice_count"] = 1
	player["dream_vehicle_backup"] = backup if not backup.is_empty() else {"previous_vehicle": "walking", "previous_dice_count": 1}
	player.erase("engineering_vehicle")
	data["action_options"] = ["end_turn"] if days > 0 else data["action_options"]
	return data
func _public_states() -> void:
	var self_game: Object = fresh(69031)
	stage(self_game, 0, DREAM)
	if not bool(self_game.item_is_implemented("card", DREAM)):
		expect(false, "RED: public self dream API is admitted")
	else:
		var result: Dictionary = self_game.choose_action("use_card", {"card_id": DREAM, "target_id": 0})
		expect(bool(result.get("ok", false)), "public self dream creates future state")
		if bool(result.get("ok", false)):
			var player: Dictionary = self_game.state["players"][0]
			expect(int(player.get("dream_days", 0)) > 0, "self dream stores active counter")
			eq(player.get("vehicle", ""), "walking", "self dream stores walking vehicle")
			valid(self_game.to_dict(), "public self dream save")
	var other_game: Object = fresh(69032)
	stage(other_game, 0, DREAM)
	stage(other_game, 1, SCAPEGOAT)
	if not bool(other_game.item_is_implemented("card", DREAM)):
		expect(false, "RED: public other dream API is admitted")
	else:
		var result: Dictionary = other_game.choose_action("use_card", {"card_id": DREAM, "target_id": 1})
		expect(bool(result.get("ok", false)), "public other dream plus 嫁禍 creates future state")
		if bool(result.get("ok", false)):
			expect(bool(result.get("awaiting_response", false)), "other dream pending response is explicit")
			var data: Dictionary = other_game.to_dict()
			eq(data.get("pending_trap", {}).size(), 2, "dream pending keeps exactly two trap keys")
			eq(data.get("pending_trap_card", ""), DREAM, "dream pending has discriminator")
			valid(data, "public other dream pending save")
func _metadata() -> void:
	var base: Dictionary = base_data(69041)
	if base.is_empty(): return
	valid(base, "v13 old save with missing optional sleep fields")
	for value in [0, 128]:
		var winter: Dictionary = base.duplicate(true); winter["players"][0]["winter_sleep_days"] = value
		winter["action_options"] = ["end_turn"] if value > 0 else winter["action_options"]
		valid(winter, "winter_sleep_days boundary %d" % value)
	var dream_zero: Dictionary = dream_data(base, 0)
	dream_zero["players"][0].erase("dream_vehicle_backup")
	valid(dream_zero, "inactive dream counter zero")
	valid(dream_data(base, 128), "dream_days upper boundary")
	var both: Dictionary = dream_data(base, 4)
	both["players"][0]["winter_sleep_days"] = 5
	rejected(both, "winter and dream counters are mutually exclusive")
	for field in ["winter_sleep_days", "dream_days"]:
		for value in [-1, 129, "bad", [], {}]:
			var malformed: Dictionary = base.duplicate(true)
			malformed["players"][0][field] = value
			rejected(malformed, field + " malformed boundary")
	var missing: Dictionary = dream_data(base, 4)
	missing["players"][0].erase("dream_vehicle_backup")
	rejected(missing, "active dream requires vehicle backup")
	var car: Dictionary = dream_data(base, 4)
	car["players"][0]["vehicle"] = "car"
	rejected(car, "active dream requires walking")
	var dice: Dictionary = dream_data(base, 4)
	dice["players"][0]["dice_count"] = 2
	rejected(dice, "active dream requires one die")
	var engineering: Dictionary = dream_data(base, 4)
	engineering["players"][0]["engineering_vehicle"] = {"remaining_admissions": 2, "previous_vehicle": "car", "previous_dice_count": 2}
	rejected(engineering, "active dream cannot keep top-level engineering metadata")
	var inactive: Dictionary = base.duplicate(true)
	inactive["players"][0]["dream_vehicle_backup"] = {"previous_vehicle": "walking", "previous_dice_count": 1}
	rejected(inactive, "inactive dream cannot keep vehicle backup")
	var nested: Dictionary = dream_data(base, 4, {"previous_vehicle": "engineering", "previous_dice_count": 1, "engineering_vehicle": {"remaining_admissions": 2, "previous_vehicle": "car", "previous_dice_count": 2}})
	valid(nested, "active dream preserves nested engineering metadata")
	var nested_missing: Dictionary = nested.duplicate(true)
	nested_missing["players"][0]["dream_vehicle_backup"]["engineering_vehicle"].erase("previous_dice_count")
	rejected(nested_missing, "nested engineering metadata requires three keys")
	var nested_extra: Dictionary = nested.duplicate(true)
	nested_extra["players"][0]["dream_vehicle_backup"]["engineering_vehicle"]["extra"] = true
	rejected(nested_extra, "nested engineering metadata rejects extra keys")
func pending_data(seed_value: int, marker: String, caster: int, target: int) -> Dictionary:
	var game: Object = fresh(seed_value)
	stage(game, target, SCAPEGOAT)
	var data: Dictionary = game.to_dict()
	data["current_player"] = caster
	data["phase"] = "await_action"
	data["pending_trap"] = {"caster_id": caster, "target_id": target}
	data["action_options"] = ["respond_trap"]
	if not marker.is_empty(): data["pending_trap_card"] = marker
	return data
func _pending() -> void:
	var dream: Dictionary = pending_data(69051, DREAM, 0, 1)
	valid(dream, "other dream pending discriminator")
	valid(pending_data(69052, DREAM, 0, 0), "dream pending allows self target")
	var missing: Dictionary = dream.duplicate(true)
	missing["pending_trap"].erase("target_id")
	rejected(missing, "pending trap requires target_id")
	var extra: Dictionary = dream.duplicate(true)
	extra["pending_trap"]["extra"] = true
	rejected(extra, "pending trap remains exactly two keys")
	var wrong: Dictionary = dream.duplicate(true)
	wrong["pending_trap_card"] = TRAP
	rejected(wrong, "pending trap discriminator only identifies dream")
	var cleared: Dictionary = base_data(69053)
	cleared["pending_trap_card"] = DREAM
	rejected(cleared, "cleared pending trap cannot retain discriminator")
	var trap_game: Object = fresh(69054)
	stage(trap_game, 0, TRAP)
	stage(trap_game, 1, SCAPEGOAT)
	var result: Dictionary = trap_game.choose_action("use_card", {"card_id": TRAP, "target_id": 1})
	expect(bool(result.get("ok", false)), "existing trap public pending remains available")
	if bool(result.get("ok", false)):
		var trap: Dictionary = trap_game.to_dict()
		eq(trap.get("pending_trap", {}).size(), 2, "existing trap save has exactly two keys")
		expect(not trap.has("pending_trap_card"), "existing trap has no discriminator")
		valid(trap, "existing trap pending save without discriminator")
