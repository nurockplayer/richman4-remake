extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Game = preload("res://game/core/game_state.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
const Fixture = preload("res://tests/fixtures/building_card_fixture.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	check(ui._new_game(75001, 4, Fixture.definition(), Fixture.new_game_options()), "alliance UI starts legal factory")
	ui.set_process(false)
	var g: Object = ui.game_state
	g.state.god_objects = []
	for id in range(4):
		g.set_player_ai(id, false)
		g.state.players[id].position = id
		g.state.players[id].previous_position = -1
	check(Inventory.grant_card(g.state.inventory_supply, g.state.players[0].cards, "同盟").get("ok", false), "alliance card comes from finite supply")
	g._set_action_options(0)
	check(Game.validate_save(g.to_dict()).get("ok", false), "alliance UI fixture validates before public action")
	ui._refresh_from_state()
	await process_frame
	var before: String = g.to_json()
	ui._on_cards_pressed()
	ui.cards_popup.hide()
	check(g.to_json() == before, "closing alliance selection changes nothing")
	ui._on_cards_pressed()
	var picker: Node = ui.cards_popup.find_child("CardTarget_同盟", true, false)
	var use: Node = ui.cards_popup.find_child("UseCard_同盟", true, false)
	check(picker is OptionButton, "alliance inventory has real visible-player picker")
	check(use is Button and not use.disabled, "alliance card can execute")
	if picker is OptionButton and use is Button and not use.disabled:
		var found := false
		for i in range(picker.item_count):
			if picker.get_item_id(i) == 1:
				picker.select(i)
				found = true
		check(found, "alliance selects a visible opponent")
		use.pressed.emit()
		check(g.state.players[0].get("alliance", {}).get("partner_id", -1) == 1 and g.state.players[1].get("alliance", {}).get("partner_id", -1) == 0, "real UI creates reciprocal pair")
		check(not g.state.players[0].cards.has("同盟"), "UI consumes one confirmed alliance card")
		var badge: Node = ui.players_list.find_child("AllianceStatus_0", true, false)
		check(badge is Label and str(g.state.players[1].name) in badge.text and "7" in badge.text, "player status shows partner and remaining turns")
		check(Game.validate_save(g.to_dict()).get("ok", false), "alliance UI result remains legal")
		var restored: Object = Game.from_dict(JSON.parse_string(g.to_json()))
		check(restored != null and restored.to_json() == g.to_json(), "alliance UI pair survives exact JSON reload")
	ui.queue_free()
	print("Alliances UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
