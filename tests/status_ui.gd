extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Fixture = preload("res://tests/fixtures/status_fixture.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func expect(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)
func labels(node: Node) -> String:
	var result: String = node.text+"\n" if node is Label else ""
	for child in node.get_children(): result+=labels(child)
	return result
func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	var definition: Dictionary = Fixture.definition()
	var options: Dictionary = ui._default_setup_options(4,definition)
	expect(options.get("original_statuses",false),"complete source capability enables status rules in new-game setup")
	expect(ui._new_game(42,4,definition,options),"status-capable UI new game starts")
	expect(int(ui.state.get("version",0))==8,"status-capable UI starts v8")
	var game: Object = ui.game_state
	if int(ui.state.get("version",0))!=8 or not game.has_method("_admit_player_status"):
		ui.queue_free()
		await process_frame
		print("Status UI checks: %d, failures: %d"%[checks,failures])
		quit(1);return
	game.state.god_objects=[]
	expect(game.call("_admit_player_status",0,"hospital",3).get("ok",false),"UI fixture enters hospital")
	ui._refresh_from_state()
	await process_frame
	await process_frame
	expect(labels(ui.players_list).contains("住院 · 剩餘 3 回合"),"roster explains hospital duration in own turns")
	expect(ui.roll_button.text=="休養" and not ui.roll_button.disabled,"hospitalized human can advance the rest turn")
	expect(ui.bank_button.disabled and ui.cards_button.disabled and ui.stocks_button.disabled,"detained turn does not offer active optional actions")
	expect(not ui.current_property_detail.text.contains("尚未還原") and ui.current_property_detail.text.contains("繼續行動"),"hospital tile explains release behavior")
	expect(ui._setup_options_from_state().get("original_statuses",false),"restart preserves v8 capability")
	ui._on_roll_pressed()
	expect(game.state.players[0].hospital_days==2 and game.state.phase=="await_action","rest button advances one status turn")
	expect(not ui.end_turn_button.disabled and ui.buy_button.disabled and ui.upgrade_button.disabled,"resting human can end turn without property actions")
	game.state.phase="await_roll"
	expect(game.call("_admit_player_status",0,"prison",5).get("ok",false),"UI fixture transfers to prison")
	ui._refresh_from_state()
	await process_frame
	expect(ui.roll_button.text=="服刑" and labels(ui.players_list).contains("服刑 · 剩餘 5 回合"),"prison turn has distinct duration and control")
	expect(not labels(ui.players_list).contains("住院 ·"),"opposite status disappears from roster")
	game.state.players[0].prison_days=128
	ui._refresh_from_state()
	await process_frame
	expect(ui.roll_button.text=="出獄擲骰" and labels(ui.players_list).contains("待出獄"),"terminal marker is explained as release, not 128 days")
	expect(not labels(ui.players_list).contains("128"),"raw status marker is not displayed to player")
	expect(ui._event_detail("status_released",{"status_kind":"prison"}).contains("監獄格"),"release log explains continuing from prison")
	expect(ui._event_detail("status_skipped",{"status_kind":"hospital","remaining":128})=="待出院","hospital terminal log uses release language")
	ui._on_roll_pressed()
	expect(game.state.players[0].prison_days==0,"release button resumes normal movement")
	ui.queue_free()
	await process_frame
	print("Status UI checks: %d, failures: %d"%[checks,failures])
	quit(1 if failures else 0)
