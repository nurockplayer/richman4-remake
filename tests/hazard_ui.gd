extends SceneTree
const MainScene=preload("res://game/main.tscn")
const Fixture=preload("res://tests/fixtures/status_fixture.gd")
var checks:=0
var failures:=0
func _initialize() -> void:
	call_deferred("run")
func expect(condition: bool,message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)
func labels(node: Node) -> String:
	var result: String=node.text+"\n" if node is Label else ""
	for child in node.get_children(): result+=labels(child)
	return result
func select_target(picker: OptionButton,node: int) -> bool:
	if picker==null:return false
	for i in range(picker.item_count):
		if picker.get_item_id(i)==node: picker.select(i);return true
	return false
func finish(ui: Node) -> void:
	ui.queue_free()
	print("Hazard UI checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
func run() -> void:
	var ui=MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var definition:=Fixture.definition()
	definition["supports_original_hazards"]=true
	var options: Dictionary=ui._default_setup_options(4,definition)
	expect(options.get("original_hazards",false),"complete source setup enables hazards")
	expect(ui._new_game(42,4,definition,options),"hazard UI game starts")
	expect(ui.state.get("version",0)==9,"hazard-capable UI starts v9")
	if ui.state.get("version",0)!=9:finish(ui);return
	var game: Object=ui.game_state
	game.state.god_objects=[]
	game.state.players[0].position=2
	for p in range(4):game.set_player_ai(p,false)
	game._set_action_options(0)
	ui._refresh_from_state()
	await process_frame
	ui._on_cards_pressed()
	await process_frame
	for tool_id in ["地雷","定時炸彈","機器娃娃"]:
		var button: Button=ui.cards_popup.find_child("UseTool_"+tool_id,true,false)
		expect(button!=null and not button.disabled,tool_id+" has an executable tool button")
	var picker: OptionButton=ui.cards_popup.find_child("Target_地雷",true,false)
	expect(select_target(picker,0),"mine picker offers a visible vacant anchor")
	var before: String=game.to_json()
	ui.cards_popup.hide()
	expect(game.to_json()==before,"closing picker leaves inventory and RNG untouched")
	ui._on_cards_pressed()
	picker=ui.cards_popup.find_child("Target_地雷",true,false)
	if select_target(picker,0):
		var button: Button=ui.cards_popup.find_child("UseTool_地雷",true,false)
		button.pressed.emit()
	await process_frame
	expect(game.state.ground_hazards.get("0",{}).get("kind","")=="mine","mine button submits the selected node")
	expect(ui.board_view.ground_hazards_data.get("0",{}).get("kind","")=="mine","live board receives the placed mine")
	expect(not ui.cards_popup.visible,"successful placement closes inventory")
	# Stage a carrier while retaining the finite tool total.
	game.state.inventory_supply.tools["定時炸彈"]-=1
	game.state.players[0].bomb_steps=7
	expect(game.validate_save(game.to_dict()).get("ok",false),"carried-bomb UI staging is a valid v9 snapshot")
	ui._refresh_from_state()
	await process_frame
	expect(labels(ui.players_list).contains("定時炸彈 · 剩餘 7 步"),"roster explains carried bomb in movement steps")
	expect(ui._setup_options_from_state().get("original_hazards",false),"restart preserves hazard mode")
	expect(ui._event_detail("bomb_transferred",{"from_player_id":0,"to_player_id":1,"remaining":7}).contains("7 步"),"bomb transfer event explains remaining steps")
	expect(ui._event_detail("mine_triggered",{"node":0,"hospital_days":3}).contains("地雷"),"mine event has a player-facing explanation")
	expect(ui._event_detail("bomb_picked_up",{"remaining":38}).contains("38 步"),"pickup explains its initial movement countdown")
	expect(ui._event_detail("bomb_exploded",{"hospital_days":5,"damage":{"damaged":true,"to_level":1}}).contains("建築降至 1 級"),"explosion explains property damage")
	expect(ui._event_detail("machine_doll_cleared",{"steps":9,"removed_hazards":[{"node":0}],"removed_roadblocks":[],"removed_gods":[]}).contains("清除 1 個物件"),"machine result explains its cleanup count")
	ui.board_view.set_preview_definition(definition)
	expect(ui.board_view.ground_hazards_data.is_empty(),"map preview cannot retain live hazard markers")
	var legacy:=Fixture.definition()
	expect(not ui._default_setup_options(4,legacy).get("original_hazards",false),"status-only definition keeps v8 setup")
	finish(ui)
