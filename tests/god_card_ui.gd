extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Fixture = preload("res://tests/fixtures/god_card_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var checks := 0
var failures := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var definition := Fixture.definition()
	expect(ui._default_setup_options(4, definition).get("original_god_cards", false), "source setup enables v14 god cards")
	var started: bool = ui._new_game(4814, 4, definition, Fixture.new_game_options())
	expect(started, "actual UI factory starts v14")
	if not started:
		if not ui._new_game(4814, 4, definition, Fixture.v13_game_options()):
			expect(false, "v13 predecessor permits UI RED coverage")
			ui.queue_free()
			quit(1)
			return
		ui.game_state.state.version = 14
		ui.game_state.state["original_god_cards"] = true
	var game: Object = ui.game_state
	for player_id in range(4):
		game.set_player_ai(player_id, false)
	game.state.players[0].position = 0
	game.state.players[0].previous_position = -1
	game.state.players[0].god_id = 5
	game.state.god_objects = [{"id": 5, "owner": 0, "node": 0, "days": 4}]
	var held: int = int(game.state.players[0].tools.get("定時炸彈", 0))
	expect(held > 0, "fixture has a finite bomb to carry")
	if held == 1:
		game.state.players[0].tools.erase("定時炸彈")
	else:
		game.state.players[0].tools["定時炸彈"] = held - 1
	game.state.players[0].bomb_steps = 9
	var bomb_supply: int = int(game.state.inventory_supply.tools["定時炸彈"])
	expect(Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, "送神符").get("ok", false), "grant dismiss card")
	game._set_action_options(0)
	ui._refresh_from_state()
	ui._on_cards_pressed()
	var dismiss: Button = ui.cards_popup.find_child("UseCard_送神符", true, false)
	expect(dismiss != null and not dismiss.disabled, "dismiss card button is usable for bad god and carried bomb")
	var before: String = game.to_json()
	ui.cards_popup.hide()
	expect(game.to_json() == before, "closing god-card inventory is atomic cancellation")
	ui._on_cards_pressed()
	dismiss = ui.cards_popup.find_child("UseCard_送神符", true, false)
	if dismiss != null and not dismiss.disabled:
		dismiss.pressed.emit()
	await process_frame
	expect(game.state.players[0].god_id == 0 and game.state.players[0].bomb_steps == 0, "actual dismiss button clears both supported effects")
	expect(int(game.state.inventory_supply.tools["定時炸彈"]) == bomb_supply + 1, "dismiss UI returns one carried bomb to finite supply")
	expect(not game.state.players[0].cards.has("送神符"), "dismiss UI consumes one card")
	game.state.players[0].god_id = 0
	game.state.god_objects = [{"id": 3, "owner": -1, "node": 2, "days": 0}]
	expect(Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, "請神符").get("ok", false), "grant summon card")
	game._set_action_options(0)
	ui._refresh_from_state()
	ui.board_view.reset_view()
	await process_frame
	ui._on_cards_pressed()
	var summon: Button = ui.cards_popup.find_child("UseCard_請神符", true, false)
	var preview: Label = ui.cards_popup.find_child("SummonGodTarget", true, false)
	expect(preview != null and preview.text.contains("小福神"), "summon preview names the visible automatic target")
	expect(summon != null and not summon.disabled, "visible summon target enables real button")
	expect(ui.cards_popup.find_child("CardTarget_請神符", true, false) == null and ui.cards_popup.find_child("Target_請神符", true, false) == null, "summon has no manual target selector")
	before = game.to_json()
	ui._update_cards_popup()
	expect(game.to_json() == before, "summon preview does not consume RNG or mutate gameplay")
	summon = ui.cards_popup.find_child("UseCard_請神符", true, false)
	if summon != null and not summon.disabled:
		summon.pressed.emit()
	await process_frame
	expect(game.state.players[0].god_id == 3, "actual summon button attaches the previewed god")
	expect(not game.state.players[0].cards.has("請神符"), "summon UI consumes one card")
	game.state.god_objects.append({"id": 5, "owner": -1, "node": 3, "days": 0})
	expect(Inventory.grant_card(game.state.inventory_supply, game.state.players[0].cards, "請神符").get("ok", false), "grant next summon card")
	game._set_action_options(0)
	ui._refresh_from_state()
	ui.board_view.pan_by(Vector2(100000, 100000))
	ui._on_cards_pressed()
	summon = ui.cards_popup.find_child("UseCard_請神符", true, false)
	expect(summon != null and summon.disabled, "empty visible viewport disables summon rather than falling back to the whole map")
	expect(game.validate_save(game.to_dict()).get("ok", false), "god-card UI state validates for JSON loading")
	expect(ui._setup_options_from_state().get("original_god_cards", false), "snapshot setup retains god-card capability")
	ui._map_catalog = [JSON.parse_string(JSON.stringify(definition))]
	ui._update_map_selector()
	ui._active_map_definition = {}
	ui._adopt_map_from_snapshot(game.to_dict())
	ui._on_end_restart_pressed()
	expect(ui.game_state != game and ui.game_state.state.get("version", 0) == 14, "restart preserves v14")
	expect(ui.game_state.validate_save(ui.game_state.to_dict()).get("ok", false), "restarted god-card game validates")
	ui.queue_free()
	print("God card UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
