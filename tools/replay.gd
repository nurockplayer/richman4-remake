extends SceneTree
## Deterministic AI replay: godot --headless --path . --script tools/replay.gd -- 42 4

const Simulation = preload("res://game/core/game_state.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 else 42
	var players := int(args[1]) if args.size() > 1 else 4
	if players < 2 or players > 4:
		printerr("Player count must be 2..4.")
		quit(2)
		return
	var first = Simulation.new_game(seed_value, players)
	var second = Simulation.new_game(seed_value, players)
	first.run_ai_match(10000)
	second.run_ai_match(10000)
	var result: Dictionary = first.to_dict()
	var serialized := JSON.stringify(result, "", true)
	if serialized != JSON.stringify(second.to_dict(), "", true):
		printerr("Seed replay diverged.")
		quit(1)
		return
	if first.state.get("phase") != "game_over":
		printerr("Replay did not finish within 10,000 AI turns.")
		quit(1)
		return
	print(JSON.stringify({
		"seed": seed_value,
		"players": players,
		"turn": first.state.get("turn"),
		"winner": first.state.get("winner"),
		"snapshot_sha256": serialized.sha256_text(),
		"replay_identical": true,
	}))
	quit(0)
