extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Market = preload("res://game/core/original_stock_market.gd")
const Fixture = preload("res://tests/fixtures/research_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var prices := [20.0, 30.9, 8.2, 79.5, 47.1, 32.6, 31.4, 17.9, 578.5, 42.0, 34.3, 37.5]
	for options in [Fixture.v11_game_options(), Fixture.new_game_options()]:
		var game: Object = Game.new_game_on_board(105, 4, Fixture.definition(), options)
		expect(game != null, "synthetic company JSON fixture starts")
		if game == null: continue
		for index in range(prices.size()):
			var symbol := Market.symbol(index)
			var price := snappedf(float(prices[index]), 0.01)
			game.state.market.rows[symbol].price = price
			game.state.market.prices[symbol] = price
			game.state.market.history[symbol][-1] = price
		game.state.market.index = 9599
		var saved: Dictionary = game.to_dict()
		expect(Game.validate_save(saved).get("ok", false), "cent-normalized market validates before JSON")
		var parsed: Dictionary = JSON.parse_string(game.to_json())
		expect(Game.validate_save(parsed).get("ok", false), "serialized market preserves total index validation")
		var restored: Object = Game.from_dict(parsed)
		expect(restored != null, "serialized cent-boundary market reloads")
		if restored != null:
			expect(game.to_json() == restored.to_json(), "market JSON roundtrip preserves canonical state")
			for player_id in range(4):
				game.set_player_ai(player_id, true)
				restored.set_player_ai(player_id, true)
			for turn in range(8):
				expect(game.run_ai_turn().get("completed", false), "original continues after market boundary")
				expect(restored.run_ai_turn().get("completed", false), "restored continues after market boundary")
				expect(game.to_json() == restored.to_json(), "continuation remains identical after market boundary")
		var corrupt: Dictionary = parsed.duplicate(true)
		corrupt.market.index += 10
		expect(not Game.validate_save(corrupt).get("ok", false), "wrong total index remains rejected")
		expect(Game.from_dict(corrupt) == null, "wrong total index cannot load")
	print("Company JSON index checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
