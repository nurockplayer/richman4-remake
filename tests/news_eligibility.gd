extends SceneTree
const Fixture = preload("res://tests/fixtures/news_fixture.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	for candidate in [8, 9, 10, 12, 13]:
		var game: Object = Fixture.new_game(541300 + candidate)
		check(game != null, "eligibility fixture constructs")
		if game == null: continue
		var no_assets := true
		for player in game.state.players:
			no_assets = no_assets and player.properties.is_empty()
			for amount in player.stocks.values():
				no_assets = no_assets and int(amount) == 0
		check(no_assets, "eligibility fixture has no owned property or stock")
		var order: Array = [candidate, 11]
		for id in range(36):
			if id != candidate and id != 11: order.append(id)
		game.state.news = {"order": order, "cursor": 0, "draw_count": 0, "last": {}}
		check(game.validate_save(game.to_dict()).get("ok", false), "eligibility pre-effect fixture validates")
		game._graph_visit_tile(0, game.state.board.back(), true)
		check(int(game.state.news.last.get("id", -1)) == 11, "assetless candidate %d skips to cash tax" % candidate)
		check(int(game.state.news.cursor) == 2 and int(game.state.news.draw_count) == 1, "assetless candidate advances cursor without another draw")
		check(game.validate_save(game.to_dict()).get("ok", false), "eligibility post-effect save validates")
	print("News eligibility checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
