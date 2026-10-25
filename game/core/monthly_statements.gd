extends RefCounted

## Detached presentation records of amounts calculated by the settlement core.
## No financial calculations, state writes, RNG or persistence occur here.

static func begin(state: Dictionary, kind: String) -> Dictionary:
	var edition: String = str(state.get("map_source", {}).get("edition", ""))
	if edition not in ["Game", "MultiverseJourney"] or not state.has("date"):
		return {}
	var players: Array = []
	for player in state.get("players", []):
		if not bool(player.get("alive", false)):
			continue
		# A game created without the setup path (new_game_on_board with empty
		# options, run_ai_match, or a pre-setup legacy save) has players from
		# _build_players(): real ledger fields but no character identity. The
		# report is presentation only, so it must not abort settlement; -1 marks
		# "no source character" for the presenter.
		var entry := {
			"id": int(player.get("id", -1)),
			"name": str(player.get("name", "")),
			"character_id": int(player.get("character_id", -1)),
		}
		if kind == "interest":
			entry.merge({
				"deposit_before": int(player.get("deposit", 0)),
				"interest": 0,
				"loan_active": int(player.get("loan", 0)) > 0,
			})
		players.append(entry)
	if players.is_empty():
		return {}
	return {"kind": kind, "edition": edition, "date": state.date.duplicate(true), "players": players}

static func dividend(state: Dictionary, rows: Array, payouts: Dictionary) -> Dictionary:
	var report := begin(state, "dividend")
	if report.is_empty():
		return {}
	for player in report.players:
		player["total"] = int(payouts.get(int(player.id), 0))
	var ordered := rows.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.stock_index) < int(b.stock_index))
	for row in ordered:
		row.erase("stock_index")
	report["companies"] = ordered
	return report

static func record_interest(report: Dictionary, player_id: int, amount: int) -> void:
	for player in report.get("players", []):
		if int(player.id) == player_id:
			player.interest = amount
			return
