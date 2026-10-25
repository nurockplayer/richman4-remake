extends SceneTree

## SURRENDER: the human concedes through the ordinary bankruptcy path.
##
## The transition must remove the player from the active roster without a
## creditor, release owned assets to the bank, hand the turn to the next living
## player, draw no RNG, and end the match only when one player remains.

const GameState = preload("res://game/core/game_state.gd")
const CompanyFixture = preload("res://tests/fixtures/company_fixture.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func fresh(players: int = 4, actor: int = 3, phase: String = "await_action") -> Object:
	var flags: Array = []
	for index in range(players):
		flags.append(true)
	var game: Object = GameState.new_game_on_board(42, players, CompanyFixture.definition(), {
		"original_facilities": true, "original_gods": true, "original_companies": true,
		"start_date": {"year": 1998, "month": 1, "day": 1}, "human_flags": flags})
	if game == null:
		return null
	game.state.day = 14
	game.state.current_player = actor
	game.state.phase = phase
	game._sync_state()
	if phase == "await_action":
		game._set_action_options(actor)
	return game


## The fixture starts every player with a deposit but an empty bank ledger;
## mirror the living deposits so the ledger invariant is the only variable.
func normalize_ledger(game: Object) -> int:
	var total := 0
	for player in game.state.players:
		total += int(player.deposit)
	game.state.bank["deposits"] = total
	return total


func run() -> void:
	var game := fresh()
	check(game != null, "surrender fixture constructs")
	if game == null:
		quit(1)
		return
	var actor := int(game.state.current_player)
	game.state.board[1]["owner"] = actor
	game.state.players[actor]["properties"] = [1]
	game.state.players[actor]["cash"] = 50000
	game.state.players[actor]["deposit"] = 7000
	var ledger_before := normalize_ledger(game)
	game._sync_state()
	var result: Dictionary = game.surrender()
	check(bool(result.get("ok", false)), "surrender is a public successful transition")
	var player: Dictionary = game.state.players[actor]
	check(not bool(player.get("alive", true)) and bool(player.get("bankrupt", false)), "surrender leaves the roster through bankruptcy")
	check(int(player.get("cash", -1)) == 0 and int(player.get("deposit", -1)) == 0, "surrender releases cash and deposits")
	check((player.get("properties", [1]) as Array).is_empty() and int(game.state.board[1].get("owner", actor)) == -1, "owned property returns to the bank")
	var bankrupt_events: Array = game.state.event_log.filter(func(event: Variant) -> bool: return typeof(event) == TYPE_DICTIONARY and str(event.get("type", "")) == "bankruptcy")
	check(bankrupt_events.size() == 1 and str(bankrupt_events[0].get("reason", "")) == "surrender", "bankruptcy event records the surrender reason")
	var auctions: Array = game.state.bankruptcy_auctions
	check(auctions.size() == 1 and int(auctions[0].get("creditor", 0)) == -1, "surrender has no creditor")
	check(int(game.state.bank.deposits) == ledger_before - 7000, "released deposit leaves the bank ledger")
	check(game.state.phase != "game_over", "a four-player match continues after one surrender")
	check(int(game.state.current_player) != actor and bool(game.state.players[int(game.state.current_player)].get("alive", false)), "the turn passes to the next living player")
	check(bool(GameState.validate_save(game.to_dict()).get("ok", false)), "surrendered state passes validate_save")
	check(not bool(game.surrender(actor).get("ok", true)), "an already-bankrupt player cannot surrender twice")

	var twin := fresh()
	twin.state.board[1]["owner"] = actor
	twin.state.players[actor]["properties"] = [1]
	twin.state.players[actor]["cash"] = 50000
	twin.state.players[actor]["deposit"] = 7000
	normalize_ledger(twin)
	twin._sync_state()
	twin.surrender()
	check(game.to_json() == twin.to_json(), "surrender is deterministic for the same seed and state")

	var moving := fresh(4, 2, "await_roll")
	moving.surrender()
	check(moving.state.phase == "await_roll" and int(moving.state.current_player) != 2 and bool(moving.state.players[int(moving.state.current_player)].get("alive", false)), "a surrendering roll-phase actor hands over without leaving a dead current player")

	var duel := fresh(2, 0)
	duel.surrender()
	check(duel.state.phase == "game_over" and int(duel.state.winner) == 1, "the last remaining player wins when the opponent surrenders")
	check(bool(GameState.validate_save(duel.to_dict()).get("ok", false)), "finished surrender state passes validate_save")

	var finished := fresh()
	finished.state.phase = "game_over"
	finished._sync_state()
	check(not bool(finished.surrender().get("ok", true)), "surrender refuses a finished match")

	print("Surrender checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
