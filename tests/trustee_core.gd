extends SceneTree
const Game = preload("res://game/core/game_state.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	var game: Object = make_game()
	check(game != null, "valid mixed-origin setup")
	check(game.has_method("trustee_rows") and game.has_method("apply_trustee_settings") and game.has_method("request_trustee_recovery"), "public trustee draft, atomic commit and boundary recovery exist")
	if game.has_method("trustee_rows"):
		var before: String = game.to_json()
		var rows: Array = game.trustee_rows()
		check(rows.size() == 2 and rows[0].player_id == 0 and rows[1].player_id == 1, "only original humans appear")
		rows[0].cash_ratio = 0
		rows[0].stock_ratio = 0
		rows[0].use_cards = false
		rows[0].use_tools = false
		rows[0].trustee = true
		check(game.to_json() == before, "draft mutation never changes simulation")
		var bad: Array = rows.duplicate(true)
		bad[1].player_id = 0
		check(not game.apply_trustee_settings(bad) and game.to_json() == before, "duplicate actors reject atomically")
		bad = rows.duplicate(true)
		bad[1].cash_ratio = 15
		check(not game.apply_trustee_settings(bad) and game.to_json() == before, "invalid ratio rejects the full batch")
		check(game.apply_trustee_settings(rows), "valid settings commit")
		check(game.state.players[0].init_cash_ratio == 50 and game.state.players[0].is_ai and game.state.players[2].is_ai, "opening ratio and native AI identity remain")
		check(game.trustee_rows()[0].cash_ratio == 0, "reopen reflects committed ratios")
		check(Game.validate_save(game.to_dict()).ok, "committed runtime state validates")
		var loaded: Object = Game.from_dict(JSON.parse_string(game.to_json()))
		check(loaded != null and loaded.to_json() == game.to_json(), "preferences survive exact JSON roundtrip")
		check(not game.request_trustee_recovery(), "remaining actionable human prevents all-trustee recovery")
		rows = game.trustee_rows()
		rows[1].trustee = true
		check(game.apply_trustee_settings(rows) and game.request_trustee_recovery(), "all original humans delegated schedules recovery")
		check(game.state.players[0].is_ai, "request does not switch actor during current turn")
		loaded = Game.from_dict(JSON.parse_string(game.to_json()))
		check(loaded != null, "pending recovery is save-valid")
		var result: Dictionary = game.run_ai_turn()
		check(result.get("ok", false), "public AI turn completes with runtime preferences")
		check(not game.state.players[0].is_ai and game.state.players[1].is_ai and game.state.players[2].is_ai, "next actor boundary restores only source player zero")
		if loaded != null:
			check(loaded.run_ai_turn() == result and loaded.to_json() == game.to_json(), "pending recovery resumes deterministically")
		var corrupted: Dictionary = game.to_dict()
		corrupted.trustee_preferences["0"].use_cards = "false"
		check(not Game.validate_save(corrupted).ok, "malformed runtime preference rejected on load")
	print("Trustee core checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
func make_game() -> Object:
	return Game.new_game(118, 3, {"start_date": {"year":1998,"month":1,"day":1}, "character_ids":[0,1,2], "human_flags":[true,true,false]})
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)
