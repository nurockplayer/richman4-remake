extends SceneTree
const Game = preload("res://game/core/game_state.gd")
const Maps = preload("res://game/content/original_maps.gd")
const BasicFixture = preload("res://tests/fixtures/original_map_fixture.gd")
const InventoryFixture = preload("res://tests/fixtures/god_card_fixture.gd")
const Inventory = preload("res://game/core/inventory_rules.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(label)
func reject_active(game: Object, label: String) -> void:
 check(game != null,label+" constructs")
 if game == null:return
 var data: Dictionary = game.to_dict()
 check(Game.validate_save(data).get("ok",false),label+" predecessor validates")
 check(Game.from_dict(JSON.parse_string(game.to_json())) != null,label+" predecessor reloads")
 data.players[0].vehicle = "engineering"
 data.players[0].dice_count = 1
 data.players[0].engineering_vehicle = {"remaining_admissions":7,"previous_vehicle":"walking","previous_dice_count":1}
 var before := JSON.stringify(data)
 check(not Game.validate_save(data).get("ok",false),label+" rejects engineering without inventory graph")
 check(Game.from_dict(JSON.parse_string(before)) == null,label+" cannot load permanent engineering mode")
 check(JSON.stringify(data) == before,label+" validation leaves input unchanged")
func _initialize() -> void:
 var normalized := Maps.normalize_map(BasicFixture.make())
 check(normalized.get("ok",false),"basic graph fixture normalizes")
 if not normalized.get("ok",false):quit(1);return
 reject_active(Game.new_game(505115,2),"v1 fixed board")
 reject_active(Game.new_game_on_board(505115,2,normalized.definition),"v2 graph")
 var options := {"start_date":{"year":1998,"month":1,"day":1}}
 reject_active(Game.new_game(505115,2,options),"v3 setup fixed board")
 reject_active(Game.new_game_on_board(505115,2,normalized.definition,options),"v3 setup graph")
 var active: Object = Game.new_game_on_board(505116,2,InventoryFixture.definition(),InventoryFixture.new_game_options())
 check(active != null,"inventory graph constructs")
 if active != null:
  check(Inventory.grant_tool(active.state.inventory_supply,active.state.players[0].tools,"工程車").get("ok",false),"inventory graph stages research tool")
  active._set_action_options(0)
  check(active.choose_action("use_tool",{"tool_id":"工程車"}).get("ok",false),"inventory graph activates through public action")
  check(Game.validate_save(active.to_dict()).get("ok",false),"inventory graph accepts actual active vehicle")
  check(Game.from_dict(JSON.parse_string(active.to_json())) != null,"inventory graph actual vehicle reloads")
 print("Engineering capability checks: %d, failures: %d" % [checks,failures])
 quit(1 if failures else 0)
