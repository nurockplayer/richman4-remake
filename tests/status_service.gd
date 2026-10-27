extends SceneTree
## Source events 4/5 (監獄入口、醫院入口): bail roster, human choice, AI draw,
## and save validation. docs/original-landing-events.md.

const Game = preload("res://game/core/game_state.gd")
const StatusFixture = preload("res://tests/fixtures/status_fixture.gd")
const StatusService = preload("res://game/core/source_status_service.gd")
var SERVICE_NODE := -1

var checks := 0
var failures := 0


func _initialize() -> void:
	run()
	print("Status service checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func make_game(event_code: int = 4) -> Object:
	var definition: Dictionary = StatusFixture.definition()
	SERVICE_NODE = 1  # the fixture's points node; ordinary road with no company
	definition.board[SERVICE_NODE].merge({"kind": "unsupported", "event_code": event_code, "source_status_bits": event_code, "name": ("監獄入口" if event_code == 4 else "醫院入口") + "（待還原）"}, true)
	definition.board[SERVICE_NODE].erase("points")
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


func land(game: Object) -> void:
	game.state.current_player = 0
	game.state.players[0].position = SERVICE_NODE
	game.state.phase = "await_action"
	game._graph_visit_tile(0, game.state.board[SERVICE_NODE], true)


func run() -> void:
	var game: Object = make_game()
	expect(game != null, "status fixture game starts")
	if game == null:
		return
	expect(StatusService.enabled(game) and int(game.state.get("status_service_sequence", -1)) == 0, "complete source rules enable the status service")
	expect(str(game.state.board[SERVICE_NODE].name) == "監獄入口", "live service node drops the unrestored suffix")

	# Empty roster: landing on the entrance opens nothing.
	land(game)
	expect(game.state.phase == "await_action" and game.state.status_service.is_empty(), "an empty roster opens nothing")

	# Save/load of a pending service, on an untouched game so every other save
	# invariant still holds.
	var clean: Object = make_game()
	clean._admit_player_status(2, "prison", 3)
	land(clean)
	var saved: Dictionary = Game.validate_save(JSON.parse_string(clean.to_json()))
	var restored: Object = Game.from_dict(JSON.parse_string(clean.to_json()))
	expect(clean.state.phase == "await_status_service" and bool(saved.get("ok", false)) and restored != null and restored.state.phase == "await_status_service", "pending status service survives save/load: %s" % [saved.get("errors", [])])

	# Human landing with a jailed player waits for the choice.
	game._admit_player_status(2, "prison", 3)
	expect(StatusService.roster(game, "prison", 0) == [2], "the roster lists the jailed player")
	land(game)
	var snapshot: Dictionary = game.status_service_snapshot()
	expect(game.state.phase == "await_status_service" and snapshot.get("roster", []).size() == 1 and int(snapshot.roster[0].get("id", -1)) == 2 and int(snapshot.get("price", 0)) == 30, "human landing lists the roster at 30 points")
	var visit_id := int(game.state.status_service.visit_id)

	# 29 points is not enough; the visit stays open and nothing changes.
	game.state.players[0].points = 29
	var refused: Dictionary = game.bail_status_service(visit_id, 2)
	expect(not bool(refused.get("ok", true)) and game.state.phase == "await_status_service" and int(game.state.players[0].points) == 29 and int(game.state.players[2].get("prison_days", 0)) == 3, "29 points cannot bail")

	# 30 points bails, marks the release-next-turn counter and closes the visit.
	game.state.players[0].points = 30
	var bailed: Dictionary = game.bail_status_service(visit_id, 2)
	expect(bool(bailed.get("ok", false)) and int(game.state.players[0].points) == 0 and int(game.state.players[2].get("prison_days", 0)) == 128 and game.state.phase == "await_action" and game.state.status_service.is_empty(), "30 points bail the player and close the service")
	expect(StatusService.roster(game, "prison", 0).is_empty(), "128 is the release marker, not a bailable counter")

	# Leaving closes the service without a change.
	game._admit_player_status(3, "prison", 3)
	land(game)
	expect(game.state.phase == "await_status_service", "a new landing re-opens the service")
	var points_before := int(game.state.players[0].points)
	var left: Dictionary = game.leave_status_service(int(game.state.status_service.visit_id))
	expect(bool(left.get("ok", false)) and game.state.phase == "await_action" and game.state.status_service.is_empty() and int(game.state.players[0].points) == points_before and int(game.state.players[3].get("prison_days", 0)) == 3, "leaving closes the service without a change")

	# AI: resolves on landing without a pending phase.
	game._admit_player_status(1, "prison", 3)
	game.set_player_ai(0, true)
	game.state.players[0].points = 100
	land(game)
	expect(game.state.phase != "await_status_service" and game.state.status_service.is_empty(), "AI landing never leaves the phase pending")

	# AI draw: a coin flip leaves; a bail needs strictly more than 30 points,
	# costs exactly 30 and sets the release marker.
	var bails := 0
	var leaves := 0
	for trial in range(24):
		var ai_game: Object = make_game()
		ai_game._rng.seed = 1000 + trial
		ai_game._admit_player_status(1, "prison", 3)
		ai_game.set_player_ai(0, true)
		ai_game.state.players[0].points = 100
		land(ai_game)
		if int(ai_game.state.players[1].get("prison_days", 0)) == 128:
			bails += 1
			expect(int(ai_game.state.players[0].points) == 70, "an AI bail costs exactly 30 points")
		else:
			leaves += 1
			expect(int(ai_game.state.players[0].points) == 100 and int(ai_game.state.players[1].get("prison_days", 0)) == 3, "an AI that leaves changes nothing")
	expect(bails > 0 and leaves > 0, "AI both bails and leaves across seeds (%d/%d)" % [bails, leaves])
	for trial in range(12):
		var poor_game: Object = make_game()
		poor_game._rng.seed = 2000 + trial
		poor_game._admit_player_status(1, "prison", 3)
		poor_game.set_player_ai(0, true)
		poor_game.state.players[0].points = 30
		land(poor_game)
		expect(int(poor_game.state.players[1].get("prison_days", 0)) == 3 and int(poor_game.state.players[0].points) == 30, "an AI with exactly 30 points never bails")

	# Event 5: the hospital entrance bails hospital patients only.
	var clinic: Object = make_game(5)
	clinic._admit_player_status(2, "hospital", 3)
	clinic._admit_player_status(3, "prison", 3)
	clinic.state.players[0].points = 50
	land(clinic)
	var clinic_visit: Dictionary = clinic.status_service_snapshot()
	var clinic_ids: Array = []
	for row in clinic_visit.get("roster", []):
		clinic_ids.append(int(row.id))
	expect(clinic.state.phase == "await_status_service" and str(clinic_visit.get("kind", "")) == "hospital" and clinic_ids == [2], "hospital entrance lists only hospital patients")
	expect(bool(clinic.bail_status_service(int(clinic_visit.visit_id), 2).get("ok", false)) and int(clinic.state.players[2].get("hospital_days", 0)) == 128 and int(clinic.state.players[0].points) == 20, "hospital bail sets the release marker and costs 30")

	# Validation rejects a visit outside its phase.
	var bad: Dictionary = JSON.parse_string(game.to_json())
	bad.status_service = {"visit_id": 1, "player_id": 0, "node_id": SERVICE_NODE, "turn": int(bad.turn), "kind": "prison"}
	expect(not bool(Game.validate_save(bad).get("ok", true)), "a status service visit outside its phase is rejected")
