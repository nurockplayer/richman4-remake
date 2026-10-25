extends "res://tests/source_lottery_core.gd"
func settle_deposits(game: Object) -> void:
	# Keep the fixture bank ledger independent of the bankruptcy deposit path.
	for player in game.state.players: player.deposit = 0
	game.state.bank.deposits = 0
func _initialize() -> void:
	var game = fresh()
	expect(game != null, "lottery fixture constructs")
	if game == null:
		quit(1)
		return
	settle_deposits(game)
	enter(game)
	expect(game.state.phase == "await_lottery" and int(game.state.lottery_pending) == 0, "actor 0 holds the pending lottery encounter")
	game._declare_bankruptcy(0, -1, 1, "test")
	expect(game.state.players[0].bankrupt == true, "pending actor is bankrupt")
	expect(int(game.state.lottery_pending) == -1, "bankruptcy clears the pending encounter")
	expect(game.state.phase != "await_lottery", "game does not stay stuck in await_lottery")
	expect(int(game.state.current_player) != 0 and bool(game.state.players[int(game.state.current_player)].alive), "turn advances to a living player")
	expect(Game.validate_save(game.to_dict()).ok, "advanced state passes validate_save")
	# A different player's bankruptcy leaves the pending actor's encounter alone.
	var other = fresh()
	settle_deposits(other)
	enter(other)
	other._declare_bankruptcy(2, -1, 1, "test")
	expect(other.state.phase == "await_lottery" and int(other.state.lottery_pending) == 0 and int(other.state.current_player) == 0, "other actor's bankruptcy keeps the pending encounter")
	expect(Game.validate_save(other.to_dict()).ok, "untouched pending state still validates")
	print("Lottery bankruptcy checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
