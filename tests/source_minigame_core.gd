extends "res://tests/source_title_ui.gd"
const Core = preload("res://game/core/game_state.gd")
func run() -> void:
	var core := Core.new_game(42,4)
	check(core.has_method("minigame_snapshot") and core.has_method("finish_minigame"), "core owns validated minigame completion API")
	if not core.has_method("minigame_snapshot"):
		print("Minigame core checks: %d, failures: %d" % [checks,failures])
		quit(1)
		return
	var viewport := SubViewport.new()
	root.add_child(viewport)
	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	var definition := find_map(ui,"Game",1)
	for event_code in [6,7,8]:
		for mode in ["human","ai","trustee","animation_off"]:
			var options: Dictionary = ui._default_setup_options(4,definition)
			options.human_flags = [mode != "ai",true,true,true]
			var game: Object = Core.new_game_on_board(71,4,definition,options)
			var node := -1
			for i in game.state.board.size():
				if int(game.state.board[i].get("event_code",0)) == event_code and int(game.state.board[i].get("type_and_idx",0)) == 0: node=i;break
			if node < 0:
				check(false,"required source node exists")
				continue
			var player: Dictionary = game.state.players[0]
			if mode == "trustee":
				var rows: Array = game.trustee_rows()
				rows[0].trustee = true
				check(game.apply_trustee_settings(rows),"public trustee settings commit")
			game.configure_minigames(mode != "animation_off")
			player.position = node
			game.state.phase = "await_action"
			game._resolve_landing(0)
			var snapshot: Dictionary = game.minigame_snapshot()
			check(snapshot.get("kind","") == {6:"penguin",7:"balloon",8:"catching"}[event_code],"event and screen IDs stay correctly mapped")
			var id := int(snapshot.get("encounter_id",-1))
			var before: Dictionary = game.to_dict()
			check(not game.choose_action("buy_stock",{"symbol":"s01","quantity":1}).ok and not game.end_turn().ok and game.to_dict()==before,"pending modal excludes public actions")
			check(not Core.validate_save(before).ok and Core.from_dict(before)==null,"active minigame snapshots cannot be loaded as arbitrary rewards")
			check(not game.save_to_path("/tmp/richman4-active-minigame-forbidden.json"),"active direct saves refused")
			check(not game.finish_minigame(id-1).ok and game.to_dict()==before,"stale encounter completion rejected")
			var shortcut: bool = mode != "human"
			check(bool(snapshot.get("shortcut",false)) == shortcut,"source animation and actor shortcut gate")
			if not shortcut:
				check(not game.finish_minigame(id).ok,"cannot finish before deterministic deadline")
				for tick in range(420): game.minigame_tick(id)
				snapshot = game.minigame_snapshot()
			else:
				check(int(snapshot.get("reward",-1)) >= 50 and int(snapshot.get("reward",-1)) <= 69,"shortcut returns50–69 point coupons")
			var cash := int(player.cash)
			var points := int(player.points)
			var reward := int(snapshot.get("reward",-1))
			check(game.finish_minigame(id).ok and int(player.points)==points+reward and int(player.cash)==cash,"core settles model reward as points exactly once")
			var after: Dictionary = game.to_dict()
			check(not game.finish_minigame(id).ok and game.to_dict()==after,"duplicate result is inert")
			check(game.state.phase=="await_action" and Core.validate_save(after).ok,"normal return is saveable and permits turn continuation")
	viewport.queue_free()
	await settle()
	print("Minigame core checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
