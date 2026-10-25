extends SceneTree

## SURRENDER: the human concedes through the ordinary bankruptcy path.
##
## The transition must remove the player from the active roster without a
## creditor, release owned assets to the bank, hand the turn to the next living
## player, draw no RNG, and end the match only when one player remains.

const GameState = preload("res://game/core/game_state.gd")
const CompanyFixture = preload("res://tests/fixtures/company_fixture.gd")
const AuctionFixture = preload("res://tests/fixtures/auction_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")

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


## A pending trap / tax or remote-dice record that names the conceding player
## must not survive the concession: the next actor would otherwise be stuck
## behind a response that can only ever answer "已失效".
func pending_game(kind: String) -> Object:
	# The v13 fixture keeps the card supply conserved, which the save validator
	# checks together with each pending record's own rules.
	var game: Object = AuctionFixture.new_game(7800)
	var actor := int(game.state.current_player)
	var phase := "await_roll" if kind == "remote_dice" else "await_action"
	AuctionFixture.prepare(game, actor, int(game.state.players[actor].position), phase)
	match kind:
		"trap":
			Inventory.grant_card(game.state.inventory_supply, game.state.players[1].cards, "嫁禍")
			game.state["pending_trap"] = {"caster_id": actor, "target_id": 1}
		"finance":
			Inventory.grant_card(game.state.inventory_supply, game.state.players[1].cards, "嫁禍")
			game.state["pending_finance"] = {
				"kind": "tax", "stage": "redirect", "payer_id": 1, "creditor_id": actor,
				"amount": 3001, "node_id": int(game.state.players[actor].position), "caster_id": actor}
		"remote_dice":
			game.state["pending_remote_dice"] = {"player_id": actor, "value": 3}
	game._set_action_options(actor)
	return game


func pending_cases() -> void:
	for kind in ["trap", "finance", "remote_dice"]:
		var game := pending_game(kind)
		var actor := int(game.state.current_player)
		var before: Dictionary = GameState.validate_save(game.to_dict())
		check(bool(before.get("ok", false)), "pending %s state validates before surrender: %s" % [kind, str(before.get("errors", []))])
		check(bool(game.surrender(actor).get("ok", false)), "surrender succeeds while %s is pending" % kind)
		match kind:
			"trap":
				check((game.state.pending_trap as Dictionary).is_empty() and not game.state.has("pending_trap_card"), "the pending trap record is dropped with its caster")
			"finance":
				check(not game.state.has("pending_finance"), "the pending financial response is dropped")
			"remote_dice":
				check((game.state.pending_remote_dice as Dictionary).is_empty(), "the pending remote dice roll is dropped")
		check(not (game.state.action_options as Array).has("respond_trap") and not (game.state.action_options as Array).has("respond_finance"), "the next actor is not offered a stale %s response" % kind)
		var after: Dictionary = GameState.validate_save(game.to_dict())
		check(bool(after.get("ok", false)), "state after a pending %s surrender validates: %s" % [kind, str(after.get("errors", []))])
		check(bool(game.roll().get("ok", false)), "the next actor can roll after a pending %s surrender" % kind)


## An auction recomputes its participants from the living roster, so a departed
## caster or bidder cannot stay in a valid record.
func auction_case() -> void:
	var game: Object = AuctionFixture.new_game(7800)
	var staged: Dictionary = AuctionFixture.stage_card(game, 0)
	check(bool(staged.get("ok", false)), "auction fixture stages the 拍賣 card")
	var started: Dictionary = game.choose_action("use_card", {"card_id": "拍賣", "cancel": false})
	check(bool(started.get("ok", false)) and not (game.auction_response() as Dictionary).is_empty(), "auction fixture leaves a pending auction")
	if (game.auction_response() as Dictionary).is_empty():
		return
	var before: Dictionary = GameState.validate_save(game.to_dict())
	check(bool(before.get("ok", false)), "pending auction state validates before surrender: " + str(before.get("errors", [])))
	var caster := int(game.state.current_player)
	check(bool(game.surrender(caster).get("ok", false)), "the auction caster can surrender")
	check((game.auction_response() as Dictionary).is_empty(), "surrender cancels the pending auction")
	var after: Dictionary = GameState.validate_save(game.to_dict())
	check(bool(after.get("ok", false)), "state after cancelling the auction validates: " + str(after.get("errors", [])))


## The construction service is tied to the actor who landed on their own
## company, so it cannot outlive that actor.
func company_service_case() -> void:
	var definition: Dictionary = CompanyFixture.definition()
	definition.companies[0].company_type = 11
	var construction: Object = GameState.new_game_on_board(42, 4, definition, {
		"original_facilities": true, "original_gods": true, "original_companies": true,
		"start_date": {"year": 1998, "month": 1, "day": 1}})
	construction.state.god_objects = []
	construction.state.players[0].stocks.s01 = 1
	construction.state.companies[0].treasury -= 1
	construction._update_company_owners()
	construction.state.board[2].owner = 1
	construction.state.players[1].properties = [2]
	construction._recalculate_property_values()
	construction.state.current_player = 1
	construction.state.players[1].position = 5
	construction.state.players[1].previous_position = 4
	construction.state.phase = "await_action"
	construction._resolve_company_visit(1, construction.state.board[5])
	construction._set_action_options(1)
	check(int(construction.state.company_service_pending) == 1, "construction service is pending for the visiting actor")
	var before: Dictionary = GameState.validate_save(construction.to_dict())
	check(bool(before.get("ok", false)), "pending construction state validates before surrender: " + str(before.get("errors", [])))
	check(bool(construction.surrender(1).get("ok", false)), "the visiting actor can surrender")
	check(int(construction.state.company_service_pending) == 0, "surrender clears the pending construction service")
	check(not (construction.state.action_options as Array).has("company_upgrade"), "the next actor is not offered the departed construction service")
	var after: Dictionary = GameState.validate_save(construction.to_dict())
	check(bool(after.get("ok", false)), "state after clearing the construction service validates: " + str(after.get("errors", [])))


## A ruleset that never tracked company services must not gain the key from a
## bankruptcy: the serialized save is part of the deterministic replay contract.
func shape_case() -> void:
	var legacy: Object = GameState.new_game(42, 4)
	check(not legacy.state.has("company_service_pending"), "default match does not track company services")
	legacy.surrender(int(legacy.state.current_player))
	check(not legacy.state.has("company_service_pending"), "surrender never adds the company service key to a match that does not track it")
	check(bool(GameState.validate_save(legacy.to_dict()).get("ok", false)), "a default-match surrender validates")


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

	pending_cases()
	auction_case()
	company_service_case()
	shape_case()

	print("Surrender checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
