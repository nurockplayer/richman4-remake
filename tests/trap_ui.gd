extends SceneTree
const MainScene=preload("res://game/main.tscn")
const Fixture=preload("res://tests/fixtures/status_fixture.gd")
const Inventory=preload("res://game/core/inventory_rules.gd")
var checks:=0
var failures:=0
func expect(condition: bool,label: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func stage(ui: Node, ai_caster: bool) -> Object:
	var definition: Dictionary=Fixture.definition()
	ui._new_game(6622,4,definition,ui._default_setup_options(4,definition))
	var game: Object=ui.game_state
	game.state.god_objects=[]
	for id in range(4):
		game.set_player_ai(id,ai_caster and id==0)
		var p: Dictionary=game.state.players[id]
		for card in p.cards.duplicate(): Inventory.consume_card(game.state.inventory_supply,p.cards,card)
	Inventory.grant_card(game.state.inventory_supply,game.state.players[0].cards,"陷害")
	Inventory.grant_card(game.state.inventory_supply,game.state.players[1].cards,"嫁禍")
	game._set_action_options(0)
	return game
func run() -> void:
	var ui=MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var game:=stage(ui,true)
	expect(game.choose_action("use_card",{"card_id":"陷害","target_id":1}).get("ok",false),"AI caster attacks human with response card")
	ui._refresh_from_state()
	await process_frame
	if game.state.get("pending_trap",{}).is_empty():
		expect(false,"UI reaction fixture is pending")
		await finish(ui);return
	expect(ui.trap_popup.visible and ui._human_trap_response_pending(),"human response popup opens during opponent turn")
	expect(not ui._is_human_turn(),"response does not change current AI caster")
	expect(ui.trap_target_option.item_count==3,"all other live players offered as redirect targets")
	expect(ui.roll_button.disabled and ui.cards_button.disabled and ui.stocks_button.disabled and ui.end_turn_button.disabled,"main actions disabled during response")
	ui._ai_pending=false
	ui._maybe_schedule_ai_turn()
	expect(not ui._ai_pending,"AI is not scheduled while human response pending")
	for index in range(ui.trap_target_option.item_count):
		if ui.trap_target_option.get_item_id(index)==0: ui.trap_target_option.select(index)
	ui.trap_redirect_button.pressed.emit()
	await process_frame
	expect(game.state.pending_trap.is_empty() and not ui.trap_popup.visible,"redirect button resolves and closes popup")
	expect(int(game.state.players[0].prison_days)==4 and int(game.state.players[1].prison_days)==0,"human can redirect to AI caster outside own turn")
	expect(not game.state.players[1].cards.has("嫁禍"),"successful UI redirect consumes scapegoat")
	# A fresh all-human stage verifies popup close means decline, never silent
	# attack cancellation or card loss. No user save file is touched.
	game=stage(ui,false)
	game.choose_action("use_card",{"card_id":"陷害","target_id":1})
	ui._refresh_from_state()
	await process_frame
	expect(ui.trap_popup.visible,"second response popup opens")
	ui.trap_popup.hide()
	await process_frame
	await process_frame
	expect(game.state.pending_trap.is_empty() and int(game.state.players[1].prison_days)==5,"closing response accepts original punishment")
	expect(game.state.players[1].cards.has("嫁禍"),"closing response preserves unplayed scapegoat")
	game=stage(ui,false)
	for card in ["免罪","復仇","嫁禍"]:
		Inventory.grant_card(game.state.inventory_supply,game.state.players[0].cards,card)
	game._admit_player_status(2,"hospital",3)
	game._set_action_options(0)
	ui._refresh_from_state()
	await process_frame
	ui._update_cards_popup()
	for card in ["免罪","復仇","嫁禍"]:
		var passive: Button=ui.cards_popup_list.find_child("UseCard_"+card,true,false)
		expect(passive!=null and passive.disabled and passive.text==("遭陷害時選擇" if card=="嫁禍" else "自動觸發"),"inventory explains passive "+card)
	var picker: OptionButton=ui.cards_popup_list.find_child("CardTarget_陷害",true,false)
	var legal: Array=game.trap_target_players(0)
	var visible: Array=ui.board_view.visible_node_indices()
	var expected: Array=[]
	for id in legal:
		if visible.has(int(game.state.players[id].position)): expected.append(int(id))
	var actual: Array=[]
	if picker!=null and not picker.disabled:
		for index in range(picker.item_count): actual.append(picker.get_item_id(index))
	expect(actual==expected,"initial trap picker intersects current viewport and legal non-detained opponents")
	expect(not actual.has(0) and not actual.has(2),"initial trap picker excludes caster and hospital player")
	if actual.has(1):
		for index in range(picker.item_count):
			if picker.get_item_id(index)==1: picker.select(index)
		ui.cards_popup.popup_centered()
		var use_trap: Button=ui.cards_popup_list.find_child("UseCard_陷害",true,false)
		use_trap.pressed.emit()
		await process_frame
		expect(not ui.cards_popup.visible and ui.trap_popup.visible and not game.state.pending_trap.is_empty(),"backpack Use button closes inventory and opens victim response")
		ui._respond_to_trap(true)
		await process_frame
	await finish(ui)
func finish(ui: Node) -> void:
	ui.queue_free()
	await process_frame
	print("Trap UI checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
