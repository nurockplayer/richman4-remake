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
		var entry := {"id": int(player.id), "name": str(player.name), "character_id": int(player.character_id)}
		if kind == "interest":
			entry.merge({"deposit_before": int(player.deposit), "interest": 0, "loan_active": int(player.loan) > 0})
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
