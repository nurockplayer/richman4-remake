extends SceneTree

# Owner EXE 41c927..41c965 releases detention before admitting sleep state.
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")
var checks := 0
var failures := 0

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	for field in ["dream_days", "winter_sleep_days"]:
		for days in [2, 128]:
			check_release(field, days)
	print("Sleep detention release checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func check_release(field: String, days: int) -> void:
	var game: Object = Game.new_game_on_board(69700 + days, 4, Fixture.definition(), Fixture.new_game_options())
	expect(game != null, "release fixture factory")
	if game == null: return
	game.state.god_objects = []
	for id in range(4):
		game.set_player_ai(id, false)
	var status_kind := "hospital" if field == "dream_days" else "prison"
	var admitted: Dictionary = game._admit_player_status(0, status_kind, 1)
	expect(admitted.get("ok", false), "release fixture uses real detention admission")
	var player: Dictionary = game.state.players[0]
	player[status_kind + "_days"] = 128
	player[field] = days
	if field == "dream_days":
		player["dream_vehicle_backup"] = {"previous_vehicle": "walking", "previous_dice_count": 1}
		player["turtle_days"] = 1
	game.state.current_player = 0
	game.state.phase = "await_roll"
	game._set_action_options(0)
	expect(Game.validate_save(game.to_dict()).get("ok", false), "detention plus sleep fixture validates")
	var before_position: int = int(player.position)
	var before_rng: String = str(game.state.rng_state_text)
	if not game.has_method("run_sleep_turn"):
		expect(false, "sleep driver exists for detention release")
		return
	var result: Dictionary = game.run_sleep_turn()
	expect(result.get("ok", false), "detention release driver succeeds")
	expect(int(player.get(status_kind + "_days", 0)) == 0, "detention marker clears before sleep handling")
	if days == 128:
		expect(int(player.get(field, 0)) == 0, "sleep marker wakes during same admission")
		expect(not player.has("dream_vehicle_backup"), "wake clears optional vehicle backup")
		expect(int(game.state.current_player) == 0 and game.state.phase == "await_roll", "double release returns pre-roll control")
		expect(int(player.position) == before_position, "double release never moves")
		expect(str(game.state.rng_state_text) == before_rng, "double release does not consume RNG")
	else:
		expect(int(player.get(field, 0)) == 1, "active sleep decrements once on detention release")
		expect(int(game.state.current_player) == 1, "active sleep completes its restricted turn")
		if field == "winter_sleep_days":
			expect(int(player.position) == before_position, "released winter sleeper stays in place")
			expect(str(game.state.rng_state_text) == before_rng, "winter skip consumes no RNG")
		else:
			expect(int(player.position) != before_position, "released dream sleeper takes forced one-step route")
	expect(player.is_human and not player.is_ai, "release preserves human identity")
	expect(Game.validate_save(game.to_dict()).get("ok", false), "release continuation validates")
