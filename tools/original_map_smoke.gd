extends SceneTree
## Local-only acceptance; reads owner-provided catalog, never uploads its data.
const Maps = preload("res://game/content/original_maps.gd")
const GameState = preload("res://game/core/game_state.gd")
var failures := 0
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else ""
	var result := Maps.load_catalog(path)
	if not result.ok:
		push_error(result.error)
		quit(1)
		return
	var playable := 0
	for definition in result.maps:
		var game = GameState.new_game_on_board(42, 4, definition)
		if not definition.supports_new_game:
			if game != null:
				push_error("Unsupported economy was incorrectly admitted")
				failures += 1
			continue
		if game == null:
			push_error("Supported map could not start: %s" % definition.id)
			failures += 1
			continue
		playable += 1
		for player_id in range(4):
			game.set_player_ai(player_id, true)
		for turn in range(4):
			var step: Dictionary = game.run_ai_turn()
			if not step.get("ok", false):
				push_error("Original-map AI stalled: %s" % definition.id)
				failures += 1
		var restored = GameState.from_dict(JSON.parse_string(game.to_json()))
		if restored == null:
			push_error("Original-map disk-shaped snapshot failed validation: %s" % definition.id)
			failures += 1
		else:
			game.run_ai_turn()
			restored.run_ai_turn()
			if game.to_json() != restored.to_json():
				push_error("Original-map save continuation diverged: %s" % definition.id)
				failures += 1
		var match_result: Dictionary = game.run_ai_match(3000)
		if not match_result.get("ok", false):
			push_error("Original-map match did not finish: %s (%s)" % [definition.id, match_result.get("message", "")])
			failures += 1
		print("Original map ", definition.id, " nodes=", definition.board.size(), " winner=", match_result.get("winner", -1), " turns=", match_result.get("completed_turns", 0))
	print("Original map acceptance: ", playable, " playable maps, ", failures, " failures")
	quit(1 if failures else 0)
