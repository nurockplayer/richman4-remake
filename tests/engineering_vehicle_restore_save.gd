extends SceneTree
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
func exercise(previous_vehicle: String) -> void:
 var game: Object = Game.new_game_on_board(505117,2,Fixture.definition(),Fixture.new_game_options())
 check(game != null,previous_vehicle+" fixture constructs")
 if game == null:return
 var player: Dictionary = game.state.players[0]
 check(Inventory.grant_tool(game.state.inventory_supply,player.tools,"工程車").get("ok",false),previous_vehicle+" stages engineering tool")
 game._set_action_options(0)
 check(game.choose_action("use_tool",{"tool_id":"工程車"}).get("ok",false),previous_vehicle+" activates actual vehicle")
 # Preserve the accepted optional-metadata shape from engineering_vehicle_save:
 # held inventory authorizes restoration even if its ordinary flag is false.
 if previous_vehicle == "car":
  check(Inventory.grant_tool(game.state.inventory_supply,player.tools,"汽車").get("ok",false),"restore save stages held car")
 player.engineering_vehicle = {"remaining_admissions":1,"previous_vehicle":previous_vehicle,"previous_dice_count":2 if previous_vehicle == "car" else 1}
 player.vehicles[previous_vehicle] = false
 game.state.current_player = 1
 game.state.phase = "await_action"
 game.state.last_roll = []
 game.state.last_total = 0
 game.state.last_roll_total = 0
 game._set_action_options(1)
 check(Game.validate_save(game.to_dict()).get("ok",false),previous_vehicle+" accepted active shape validates")
 var restored: Object = Game.from_dict(JSON.parse_string(game.to_json()))
 check(restored != null,previous_vehicle+" accepted active shape reloads")
 if restored == null:return
 check(restored.end_turn().get("ok",false),previous_vehicle+" admission reaches expiry")
 var after: Dictionary = restored.state.players[0]
 check(after.vehicle == previous_vehicle,previous_vehicle+" restored mode")
 check(int(after.dice_count) == (2 if previous_vehicle == "car" else 1),previous_vehicle+" restored dice")
 check(bool(after.vehicles.get(previous_vehicle,false)),previous_vehicle+" restore refreshes ordinary ownership flag")
 check(Game.validate_save(restored.to_dict()).get("ok",false),previous_vehicle+" post-expiry state remains valid")
 check(Game.from_dict(JSON.parse_string(restored.to_json())) != null,previous_vehicle+" post-expiry state reloads")
 if previous_vehicle == "car":
  check(int(after.tools.get("汽車",0)) == 0,"restoration equips exactly one held car")
func _initialize() -> void:
 exercise("car")
 exercise("walking")
 print("Engineering restore save checks: %d, failures: %d" % [checks,failures])
 quit(1 if failures else 0)
