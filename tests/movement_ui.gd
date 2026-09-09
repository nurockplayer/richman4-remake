extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func busy(ui: Node) -> bool:
	return ui.get("_presentation_busy") == true

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	var definition: Dictionary = Maps.normalize_map(Fixture.make()).definition
	check(ui._new_game(1, 2, definition), "movement UI creates a legal graph match")
	ui.set_process(false)
	ui.board_view.set_process(false)
	var game: Object = ui.game_state
	for id in range(2): game.set_player_ai(id, false)
	game.state.players[0].position = 0
	game.state.players[0].previous_position = -1
	ui._refresh_from_state()
	check(Game.validate_save(game.to_dict()).get("ok", false), "movement UI input validates")
	var result: Dictionary = ui._invoke_game("roll")
	check(result.get("ok", false) and int(result.get("total", 0)) == 4, "actual seeded roll reaches a branch")
	ui._handle_result(result)
	ui.board_view.set_process(false)
	var rolled: String = game.to_json()
	check(int(game.state.players[0].position) == 1 and game.state.phase == "await_route", "simulation completes synchronously")
	check(busy(ui), "actual roll starts movement presentation")
	check(int(ui.state.players[0].position) == 0, "UI retains departure snapshot until arrival")
	if busy(ui):
		var rejected: Dictionary = ui._invoke_game("choose_route", [2])
		check(not rejected.get("ok", true), "movement blocks the next mutating action")
		ui._on_ai_timer_timeout()
		check(game.to_json() == rolled, "movement blocks queued AI and preserves core RNG/state")
		ui._refresh_from_state()
		check(busy(ui) and int(ui.state.players[0].position) == 0, "ordinary refresh cannot snap or replay active movement")
	else:
		check(false, "movement has a real input-lock interval")
	var board: Node = ui.board_view
	check(board.has_method("_advance_movement") and board.has_method("get_player_screen_position"), "board provides timed movement presentation")
	if board.has_method("_advance_movement"):
		var start: Vector2 = board.get_screen_position_for_index(0)
		var finish: Vector2 = board.get_screen_position_for_index(1)
		board._advance_movement(0.08)
		var midpoint: Vector2 = board.get_player_screen_position(0)
		check(midpoint.distance_to(start) > 0.1 and midpoint.distance_to(finish) > 0.1, "character is visibly between graph nodes during a step")
		board._advance_movement(100.0)
	check(not busy(ui) and int(ui.state.players[0].position) == 1, "arrival adopts final snapshot and unlocks route choices")
	check(game.to_json() == rolled, "animation completion never changes simulation or RNG")
	ui._refresh_from_state()
	check(not busy(ui), "repeated refresh never replays completed movement")
	result = ui._invoke_game("choose_route", [2])
	check(result.get("ok", false), "branch choice resumes actual movement")
	ui._handle_result(result)
	ui.board_view.set_process(false)
	check(busy(ui) and int(game.state.players[0].position) == 4, "branch continuation presents multiple edges before next choice")
	check(Game.validate_save(game.to_dict()).get("ok", false), "branch continuation remains save-valid")
	check(ui._new_game(3, 2, definition), "new match replaces an animating match")
	ui.set_process(false)
	ui.board_view.set_process(false)
	var fresh: String = ui.game_state.to_json()
	check(not busy(ui), "new match cancels the previous presentation")
	if board.has_method("_advance_movement"): board._advance_movement(100.0)
	check(ui.game_state.to_json() == fresh and int(ui.state.seed) == 3, "stale completion cannot overwrite the new match")
	ui.queue_free()
	print("Movement UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
