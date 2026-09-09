extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/god_card_fixture.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var game: Object = Game.new_game_on_board(48991, 4, Fixture.definition(), Fixture.new_game_options())
	check(game != null, "near-distance fixture starts")
	if game == null:
		quit(1)
		return
	game.state.players[0].position = 1
	game.state.players[0].previous_position = -1
	game.state.board[1].x = 0
	game.state.board[1].y = 0
	game.state.board[2].x = 9000
	game.state.board[2].y = 0
	game.state.board[3].x = 9000
	game.state.board[3].y = 1
	# The farther, lower-ID actor appears later. These are not equidistant.
	game.state.god_objects = [{"id":6,"owner":-1,"node":2,"days":0},{"id":5,"owner":-1,"node":3,"days":0}]
	check(Game.validate_save(game.to_dict()).get("ok", false), "near-distance fixture validates")
	var before: String = game.to_json()
	check(game.has_method("god_card_target"), "target preview is available")
	if game.has_method("god_card_target"):
		var target: Dictionary = game.god_card_target(0)
		check(int(target.get("id", -1)) == 6, "strict nearest distance wins over a farther lower god ID")
		check(game.to_json() == before, "target preview is read-only")
	print("God card distance failures: ", failures)
	quit(1 if failures else 0)
