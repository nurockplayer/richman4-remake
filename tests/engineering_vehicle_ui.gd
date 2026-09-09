extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Game = preload("res://game/core/game_state.gd")
const Fixture = preload("res://tests/fixtures/god_card_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
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
	await process_frame
	ui.set_process(false)
	var definition := Fixture.definition()
	check(ui._new_game(5014, 4, definition, Fixture.new_game_options()), "UI creates existing v13 game")
	var game: Object = ui.game_state
	for player_id in range(4):
		game.set_player_ai(player_id, false)
	check(Inventory.grant_tool(game.state.inventory_supply, game.state.players[0].tools, "工程車", 2).get("ok", false), "UI fixture grants two research tools")
	game._set_action_options(0)
	check(Game.validate_save(game.to_dict()).get("ok", false), "initial UI fixture validates")
	ui._refresh_from_state()
	ui._on_cards_pressed()
	var use: Button = ui.cards_popup.find_child("UseTool_工程車", true, false)
	check(use != null and not use.disabled, "real engineering tool button is enabled")
	check(ui.cards_popup.find_child("Target_工程車", true, false) == null, "engineering tool requires no target selector")
	var before: String = game.to_json()
	ui.cards_popup.hide()
	check(game.to_json() == before, "closing tool popup is atomic cancellation")
	ui._on_cards_pressed()
	use = ui.cards_popup.find_child("UseTool_工程車", true, false)
	if use != null and not use.disabled:
		use.pressed.emit()
	await process_frame
	check(game.state.players[0].vehicle == "engineering", "real button activates engineering vehicle")
	check(int(game.state.players[0].dice_count) == 1, "active engineering exposes one die")
	check(int(game.state.players[0].tools.get("工程車", 0)) == 1, "real button consumes exactly one research tool")
	ui._on_cards_pressed()
	use = ui.cards_popup.find_child("UseTool_工程車", true, false)
	check(use != null and use.disabled, "remaining tool cannot reactivate an active vehicle")
	var status: Label = ui.cards_popup.find_child("EngineeringVehicleStatus", true, false)
	check(status != null and status.text.contains("工程車") and status.text.contains("7"), "inventory names engineering vehicle and remaining duration")
	check(Game.validate_save(game.to_dict()).get("ok", false), "activated UI state remains valid")
	var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
	check(restored != null, "active engineering snapshot reloads")
	if restored != null:
		ui.game_state = restored
		ui._refresh_from_state()
		ui._on_cards_pressed()
		status = ui.cards_popup.find_child("EngineeringVehicleStatus", true, false)
		check(status != null and status.text.contains("7"), "loaded vehicle duration is visible")
		restored._admit_player_status(0, "hospital", 2)
		restored._set_action_options(0)
		ui._refresh_from_state()
		ui._on_cards_pressed()
		use = ui.cards_popup.find_child("UseTool_工程車", true, false)
		check(use != null and use.disabled, "hospital state disables engineering tool")
	ui._map_catalog = [JSON.parse_string(JSON.stringify(definition))]
	ui._update_map_selector()
	ui._active_map_definition = {}
	ui._adopt_map_from_snapshot(ui.game_state.to_dict())
	ui._on_end_restart_pressed()
	check(ui.game_state.state.get("version", 0) == 13, "restart does not invent a new schema")
	check(not ui.game_state.state.players[0].has("engineering_vehicle"), "new match has no stale engineering timer")
	check(Game.validate_save(ui.game_state.to_dict()).get("ok", false), "restarted game validates")
	ui.queue_free()
	print("Engineering vehicle UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
