extends SceneTree
const Fixture = preload("res://tests/fixtures/news_fixture.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func arm(game: Object, id: int) -> void:
	var order: Array = [id]
	for candidate in range(36):
		if candidate != id: order.append(candidate)
	game.state.news = {"order": order, "cursor": 0, "draw_count": 0, "last": {}}

func _initialize() -> void:
	for seed in [1, 2]:
		var game: Object = Fixture.new_game(seed)
		check(game != null, "price-boundary fixture constructs")
		if game == null: continue
		for tile in game.state.board:
			if tile.kind in ["property", "facility"]:
				tile.land_price = 65000
				tile.cost = 65000
		for record in game.state.map_source.facilities:
			record.land_price = 65000
		game._recalculate_property_values()
		arm(game, 6)
		check(game.validate_save(game.to_dict()).get("ok", false), "price-boundary fixture and retained source validate")
		game._graph_visit_tile(0, game.state.board.back(), true)
		check(int(game.state.news.last.get("id", -1)) == 6, "price-boundary landing applies rising news")
		var target: int = int(game.state.news.last.targets[0])
		check(game.state.board[target].kind == ("property" if seed == 1 else "facility"), "price-boundary covers housing and facility targets")
		check(game.state.news.last.changes.size() == 2, "price-boundary includes the matching group or aliases")
		for change in game.state.news.last.changes:
			var tile: Dictionary = game.state.board[int(change.tile_id)]
			check(int(tile.land_price) == 18964 and int(tile.cost) == 18964, "65000 raised by 30 percent retains the source unsigned 16-bit result")
		check(game.validate_save(game.to_dict()).get("ok", false), "price-boundary result validates")
		var restored: Object = game.from_dict(JSON.parse_string(game.to_json()))
		check(restored != null and restored.to_json() == game.to_json(), "price-boundary JSON preserves aliases and result")
	for id in [8, 9, 10]:
		var game: Object = Fixture.new_game(541600 + id)
		check(game != null, "reward fixture constructs")
		if game == null: continue
		game.state.board[2].owner = 0
		game.state.players[0].properties = [2]
		game._recalculate_property_values()
		if id == 10:
			game.state.players[0].stocks.s01 = 10
			game.state.market.rows.s01.market_supply = 4990
			game._update_company_owners()
		arm(game, id)
		check(game.validate_save(game.to_dict()).get("ok", false), "reward fixture validates")
		var recipient := 1 if id == 9 else 0
		var cash: int = int(game.state.players[recipient].cash)
		var bank_before: Dictionary = game.state.bank.duplicate(true)
		var amount: int = (5000 if id == 9 else 10000) * int(game.state.price_index)
		game._graph_visit_tile(0, game.state.board.back(), true)
		check(int(game.state.news.last.get("id", -1)) == id, "reward landing applies selected award")
		check(int(game.state.players[recipient].cash) == cash + amount, "reward credits the selected player's cash")
		check(game.state.bank == bank_before, "source cash reward does not debit bank reserves")
		check(game.validate_save(game.to_dict()).get("ok", false), "reward result validates")
	for id in [18, 21]:
		var game: Object = Fixture.new_game(1)
		check(game != null, "single-target damage fixture constructs")
		if game == null: continue
		for player_id in [0, 1]:
			var tile_id: int = player_id + 2
			game.state.board[tile_id].owner = player_id
			game.state.board[tile_id].building_level = 2
			game.state.players[player_id].properties = [tile_id]
			game._update_tile_rent(game.state.board[tile_id])
		game._recalculate_property_values()
		arm(game, id)
		check(game.validate_save(game.to_dict()).get("ok", false), "single-target damage fixture validates")
		var before: Array = game.state.board.duplicate(true)
		game._graph_visit_tile(0, game.state.board.back(), true)
		check(int(game.state.news.last.get("id", -1)) == id and game.state.news.last.targets == [3], "damage landing selects one known housing target")
		for tile_id in range(game.state.board.size()):
			var affected: bool = tile_id == 3 or (id == 18 and tile_id == 2)
			if affected:
				check(int(game.state.board[tile_id].building_level) == 1 and game.state.board[tile_id].owner == before[tile_id].owner, "damage reduces intended building and preserves ownership")
			else:
				check(game.state.board[tile_id] == before[tile_id], "news %d preserves non-target tile %d" % [id, tile_id])
		check(game.validate_save(game.to_dict()).get("ok", false), "single-target damage result validates")
	var company_game: Object = Fixture.new_game(541635)
	check(company_game != null, "wrapped company event fixture constructs")
	if company_game != null:
		for company in company_game.state.companies:
			company.monthly_profit = 0
		company_game.state.companies[0].monthly_profit = 160000
		company_game.state.companies[0].cumulative_profit = 200000
		arm(company_game, 35)
		check(company_game.validate_save(company_game.to_dict()).get("ok", false), "wrapped company event fixture validates")
		var market_before: Dictionary = company_game.state.market.duplicate(true)
		company_game._graph_visit_tile(0, company_game.state.board.back(), true)
		check(int(company_game.state.news.last.get("id", -1)) == 35, "wrapped company event landing applies profit news")
		check(int(company_game.state.companies[0].monthly_profit) == 320000 and int(company_game.state.companies[0].cumulative_profit) == 520000, "wrapped stock event still updates company profits")
		check(company_game.state.market == market_before, "zero packed stock event leaves market quote, history and index unchanged")
		check(company_game.validate_save(company_game.to_dict()).get("ok", false), "wrapped company event result validates")
	for id in [18, 21]:
		for temporary_state in [0x50, 0x51]:
			var game: Object = Fixture.new_game(2)
			check(game != null, "facility damage cleanup fixture constructs")
			if game == null: continue
			game._update_facility_records(2, {"owner": 0, "building_level": 1, "facility_type": 1, "facility_state": temporary_state})
			game.state.players[0].properties = [7]
			game._recalculate_property_values()
			arm(game, id)
			check(game.validate_save(game.to_dict()).get("ok", false), "facility damage cleanup fixture validates")
			game._graph_visit_tile(0, game.state.board.back(), true)
			check(int(game.state.news.last.get("id", -1)) == id and game.state.news.last.targets == [7], "facility damage selects the intended source object")
			for alias_id in [7, 8]:
				var tile: Dictionary = game.state.board[alias_id]
				check(int(tile.building_level) == 0 and int(tile.facility_type) == 0 and int(tile.facility_state) == 0, "news clears temporary state when the facility is destroyed across aliases")
			check(game.validate_save(game.to_dict()).get("ok", false), "facility damage cleanup result validates")
			var restored: Object = game.from_dict(JSON.parse_string(game.to_json()))
			check(restored != null and restored.to_json() == game.to_json(), "facility damage cleanup survives JSON")
	print("News effect regression checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
