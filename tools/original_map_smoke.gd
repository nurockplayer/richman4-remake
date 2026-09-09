extends SceneTree
## Local-only acceptance; reads an owner-provided catalog and performs no upload.
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
	var browse_only := 0
	var banks := 0
	for definition in result.maps:
		for tile in definition.board:
			if tile.event_code == 14:
				banks += 1
				if tile.kind != "bank":
					push_error("Source bank event lost service classification")
					failures += 1
		var game = GameState.new_game_on_board(42, 4, definition)
		if not definition.supports_new_game:
			browse_only += 1
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
	if playable != 11 or browse_only != 1:
		push_error("Expected 11 housing maps and one commercial-only map")
		failures += 1
	if banks != 15:
		push_error("Expected 15 source bank nodes across the owner catalog")
		failures += 1
	print("Original map acceptance: ", playable, " playable maps, ", failures, " failures")
	quit(1 if failures else 0)
