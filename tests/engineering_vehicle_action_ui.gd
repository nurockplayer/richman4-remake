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
 check(ui._new_game(505114,4,definition,Fixture.new_game_options()),"action UI new game")
 var game: Object = ui.game_state
 for id in range(4): game.set_player_ai(id,false)
 var player: Dictionary = game.state.players[0]
 check(Inventory.grant_tool(game.state.inventory_supply,player.tools,"工程車",2).get("ok",false),"action UI stages engineering")
 if int(player.tools.get("汽車",0)) == 0:
  check(Inventory.grant_tool(game.state.inventory_supply,player.tools,"汽車").get("ok",false),"action UI stages ordinary car")
 game.state.phase = "await_action"
 game.state.last_roll = []
 game.state.last_total = 0
 game.state.last_roll_total = 0
 game._set_action_options(0)
 check(Game.validate_save(game.to_dict()).get("ok",false),"action UI fixture validates before activation")
 check("use_tool" in game.state.action_options,"action options expose engineering activation")
 ui._refresh_from_state()
 ui._on_cards_pressed()
 var engineering: Button = ui.cards_popup.find_child("UseTool_工程車",true,false)
 var ordinary: Button = ui.cards_popup.find_child("UseTool_汽車",true,false)
 check(engineering != null and not engineering.disabled,"human can activate engineering after landing")
 check(ordinary != null and ordinary.disabled,"ordinary car remains unavailable after landing")
 if engineering != null and not engineering.disabled:
  engineering.pressed.emit()
 await process_frame
 check(player.vehicle == "engineering","action-phase actual button activates engineering")
 check(int(player.tools.get("工程車",0)) == 1,"action-phase actual button consumes one tool")
 check(Game.validate_save(game.to_dict()).get("ok",false),"action-phase activation remains save valid")
 ui._on_cards_pressed()
 engineering = ui.cards_popup.find_child("UseTool_工程車",true,false)
 check(engineering != null and engineering.disabled,"active action-phase engineering cannot reactivate")
 ui.queue_free()
 print("Engineering action UI checks: %d, failures: %d" % [checks,failures])
 quit(1 if failures else 0)
