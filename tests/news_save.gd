extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/news_fixture.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func deck(first_id: int = 11) -> Dictionary:
	var order: Array = [first_id]
	for id in range(36):
		if id != first_id: order.append(id)
	return {"order": order, "cursor": 0, "draw_count": 0, "last": {}}

func reject(data: Dictionary, label: String) -> void:
	var before := JSON.stringify(data)
	check(not Game.validate_save(data).get("ok", false), label + " rejects validation")
	check(Game.from_dict(JSON.parse_string(before)) == null, label + " rejects load")
	check(JSON.stringify(data) == before, label + " leaves input unchanged")

func _initialize() -> void:
	var game: Object = Fixture.new_game()
	check(game != null, "news fixture constructs")
	if game == null: quit(1); return
	var baseline: Dictionary = game.to_dict()
	check(Game.validate_save(baseline).get("ok", false), "pre-draw fixture validates")
	check(not baseline.has("news"), "new game defers news shuffle")
	check(Game.from_dict(JSON.parse_string(game.to_json())) != null, "pre-draw snapshot reloads")
	game.state.news = deck()
	var valid: Dictionary = game.to_dict()
	check(Game.validate_save(valid).get("ok", false), "complete untouched deck validates")
	var loaded: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	check(loaded != null, "complete untouched deck loads")
	if loaded != null: check(loaded.to_json() == game.to_json(), "deck canonical JSON round trip")
	for value in [null, [], "news", 1]:
		var bad := valid.duplicate(true)
		bad.news = value
		reject(bad, "news container " + str(value))
	for key in ["order", "cursor", "draw_count", "last"]:
		var bad := valid.duplicate(true)
		bad.news.erase(key)
		reject(bad, "missing news " + key)
	for value in [[], range(35), range(37), "deck"]:
		var bad := valid.duplicate(true)
		bad.news.order = value
		reject(bad, "invalid permutation size/type")
	for value in [11, -1, 36, 0.5, "1", true]:
		var bad := valid.duplicate(true)
		bad.news.order[1] = value
		reject(bad, "invalid permutation member " + str(value))
	for value in [-1, 36, 0.5, "0", true]:
		var bad := valid.duplicate(true)
		bad.news.cursor = value
		reject(bad, "invalid cursor " + str(value))
	for value in [-1, 0.5, "0", true]:
		var bad := valid.duplicate(true)
		bad.news.draw_count = value
		reject(bad, "invalid draw count " + str(value))
	for value in [[], null, "result", {"id": 11}]:
		var bad := valid.duplicate(true)
		bad.news.last = value
		reject(bad, "malformed last result")
	var historical := valid.duplicate(true)
	historical.news.draw_count = 1
	historical.news.last = {"id": 11, "player_id": 0, "targets": [], "changes": [], "summary": "所得稅結算完成"}
	check(Game.validate_save(historical).get("ok", false), "complete historical result validates")
	for entry in [["id", -1], ["id", 36], ["id", 4], ["id", 7], ["id", 20], ["id", 29], ["id", 0.5], ["player_id", -1], ["player_id", 4], ["player_id", "0"], ["targets", {}], ["changes", {}], ["changes", ["unstructured"]], ["summary", 12]]:
		var bad := historical.duplicate(true)
		bad.news.last[entry[0]] = entry[1]
		reject(bad, "invalid historical " + str(entry[0]) + " " + str(entry[1]))
	for value in [-1, 129, 0.5, "15", true]:
		var bad := valid.duplicate(true)
		bad.players[0].loan_block_days = value
		reject(bad, "invalid loan ban " + str(value))
	for value in [0, 1, 15, 128]:
		var data := valid.duplicate(true)
		data.players[0].loan_block_days = value
		check(Game.validate_save(data).get("ok", false), "loan ban boundary validates " + str(value))
		check(Game.from_dict(JSON.parse_string(JSON.stringify(data))) != null, "loan ban boundary loads")
	# A structural migration updates only this old unsupported news classification.
	var old := baseline.duplicate(true)
	old.board.back().kind = "unsupported"
	var old_before := JSON.stringify(old)
	var migrated: Object = Game.from_dict(JSON.parse_string(old_before))
	check(migrated != null, "predecessor news road migrates")
	if migrated != null:
		check(migrated.state.board.back().kind == "news", "migration enables current news semantics")
		check(not migrated.state.has("news"), "migration does not draw news")
		check(migrated.state.rng_state == old.rng_state, "migration preserves RNG")
		var migrated_data: Dictionary = migrated.to_dict()
		migrated_data.board.back().kind = old.board.back().kind
		check(JSON.parse_string(JSON.stringify(migrated_data)) == JSON.parse_string(old_before), "migration preserves every other field")
	check(JSON.stringify(old) == old_before, "migration preserves caller input")
	var forged := old.duplicate(true)
	forged.board.back().kind = "property"
	reject(forged, "unrelated forged source classification")
	# Real landing applies exactly once and persists both result and continuation.
	var cash_before: int = int(game.state.players[0].cash)
	game._graph_visit_tile(0, game.state.board.back(), true)
	check(int(game.state.players[0].cash) == cash_before - int(cash_before * 5 / 100), "actual news landing applies income tax")
	check(int(game.state.news.draw_count) == 1, "landing records one draw")
	check(int(game.state.news.last.get("id", -1)) == 11, "landing records applied result")
	check(Game.validate_save(game.to_dict()).get("ok", false), "applied news save validates")
	var after: String = game.to_json()
	loaded = Game.from_dict(JSON.parse_string(after))
	check(loaded != null, "applied news reloads")
	if loaded != null:
		check(loaded.to_json() == after, "loading never reapplies a news effect")
		for step in range(4):
			game._graph_visit_tile(0, game.state.board.back(), true)
			loaded._graph_visit_tile(0, loaded.state.board.back(), true)
			check(loaded.to_json() == game.to_json(), "JSON news continuation " + str(step))
	print("News save checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
