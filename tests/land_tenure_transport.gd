extends SceneTree

const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/time_transport_fixture.gd")
const Base = preload("res://tests/fixtures/building_card_fixture.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	for kind in ["property", "facility"]:
		_test_transport(kind)
	print("Land tenure transport checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func valid(game: Object, label: String) -> void:
	var result: Dictionary = Game.validate_save(game.to_dict())
	expect(bool(result.ok), label + str(result.get("errors", [])))


func _test_transport(kind: String) -> void:
	var options: Dictionary = Base.new_game_options()
	options.land_tenure_months = 1
	options.start_date = {"year": 1998, "month": 1, "day": 1}
	var game: Object = Game.new_game_on_board(120, 4, Fixture.definition(), options)
	game.state.god_objects = []
	var source_id := 2 if kind == "property" else 1
	var destination_id := 3 if kind == "property" else 7
	Fixture.prepare_action(game, 0, source_id, "await_action")
	valid(game, kind + " before public purchase")
	var bought: Dictionary = game.choose_action("buy")
	expect(bool(bought.get("ok", false)), kind + " public purchase succeeds")
	if not bool(bought.get("ok", false)):
		return
	Fixture.prepare_action(game, 0, source_id, "await_action")
	var built: Dictionary = game.choose_action("upgrade") if kind == "property" else game.choose_action("build_facility", {"facility_type": 0})
	expect(bool(built.get("ok", false)), kind + " public construction succeeds")
	if not bool(built.get("ok", false)):
		return
	var expiry: int = game.state.board[source_id].land_expiry
	expect(expiry == (1998 << 16) | (2 << 8) | 1, kind + " purchase starts February 1 term")
	expect(Fixture.stage_tool(game, 0, "傳送機"), kind + " finite tool grant")
	Fixture.prepare_action(game, 0, 1, "await_roll")
	valid(game, kind + " before public transport")
	var transported: Dictionary = game.choose_action("use_tool", {"tool_id": "傳送機", "target_kind": kind, "target_id": source_id, "destination_id": destination_id})
	expect(bool(transported.get("ok", false)), kind + " public transport succeeds")
	if not bool(transported.get("ok", false)):
		return
	expect(int(game.state.board[source_id].land_expiry) == 0, kind + " source expiry cleared")
	expect(int(game.state.board[destination_id].land_expiry) == expiry, kind + " destination preserves original expiry")
	if kind == "facility":
		expect(int(game.state.board[6].land_expiry) == 0, "source facility aliases cleared")
		expect(int(game.state.board[8].land_expiry) == expiry, "destination facility aliases carry original expiry")
	valid(game, kind + " after transport")
	var loaded: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	expect(loaded != null, kind + " moved expiry reloads")
	if loaded == null:
		return
	expect(loaded.to_json() == game.to_json(), kind + " moved expiry JSON exact")
	game = loaded
	game.state.day = 31
	game._sync_state()
	Fixture.prepare_action(game, 3, 9, "await_action")
	valid(game, kind + " before original expiry day")
	expect(bool(game.end_turn().get("ok", false)), kind + " public day boundary succeeds")
	expect(game.state.date == {"year": 1998, "month": 2, "day": 1}, kind + " reached original expiry date")
	expect(int(game.state.board[destination_id].owner) == -1 and int(game.state.board[destination_id].land_expiry) == 0, kind + " moved land expires on original date")
	expect(not game.state.players[0].properties.has(destination_id), kind + " expired destination ownership reference removed")
	var expiry_events: Array = []
	for event in game.state.event_log:
		if event.get("type", "") == "land_tenure_expired":
			expiry_events.append(event)
	expect(expiry_events.size() == 1 and int(expiry_events[0].get("tile_id", -1)) == destination_id, kind + " only moved destination settles once")
	valid(game, kind + " after transported expiry")
