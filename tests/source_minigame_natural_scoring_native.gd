extends "res://tests/source_minigame_native.gd"

var trace: Array = []
func run() -> void:
	var output := OS.get_environment("RICHMAN4_MINIGAME_CAPTURE")
	if DisplayServer.get_name()=="headless" or output.is_empty() or OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty() or Assets.input_data().is_empty():
		print("PRECONDITION_UNMET native display, catalog, source input and capture path")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	for edition in ["Game","MultiverseJourney"]:
		for scale_value in [1,2]:
			var view := SubViewport.new()
			view.size=Vector2i(640,480)*scale_value
			view.handle_input_locally=true
			view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			root.add_child(view)
			view.notify_mouse_entered()
			var ui := TitleTestUI.new()
			view.add_child(ui)
			await settle()
			ui.set_process(false)
			for scenario in ["penguin_score","catching_score","catching_bomb"]:
				var event_code := 6 if scenario=="penguin_score" else 8
				var seek_bomb: bool= scenario=="catching_bomb"
				var definition := find_map(ui,edition,1 if edition=="Game" else 7)
				var options: Dictionary=ui._default_setup_options(4,definition)
				options.human_flags=[true,true,true,true]
				if not ui._new_game(71,4,definition,options):
					print("PRECONDITION_UNMET real source new game")
					quit(2)
					return
				var game: Object=ui.game_state
				var node := -1
				for i in range(game.state.board.size()):
					if int(game.state.board[i].get("event_code",0))==event_code and int(game.state.board[i].get("type_and_idx",0))==0:
						node=i
						break
				if node<0:
					print("PRECONDITION_UNMET source event")
					quit(2)
					return
				# Same legal rare-event setup as preserved native test. Gameplay
				# below reads detached snapshots and only injects viewport input.
				game.configure_minigames(true,Assets.input_data())
				game.state.players[0].position=node
				game.state.phase="await_action"
				game._resolve_landing(0)
				ui._handle_result(game._result(true))
				await settle()
				var controller: Control=ui.source_minigame_controller
				controller.set_process(false)
				var panel: Control=controller.panel
				if panel==null or not panel.source_art_available():
					print("PRECONDITION_UNMET actual source art")
					quit(2)
					return
				panel.set_process(false)
				controller._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
				panel.tick(2.28)
				var kind: String=game.minigame_snapshot().kind
				var label := "%s-%s-%dx" % [edition,scenario,scale_value]
				var initial: Dictionary=game.minigame_snapshot()
				trace.append({"label":label,"initial":initial})
				if kind=="penguin":
					var model: Dictionary=initial.model
					var best := -1
					var distance := 1000
					for index in range(model.items_grid.size()):
						var cell := Vector2i(index%9,int(index/9))
						var steps := maxi(absi(cell.x-model.current_cell.x),absi(cell.y-model.current_cell.y))
						if int(model.items_grid[index])>=2 and steps>0 and steps<distance:
							best=index
							distance=steps
					check(best>=0,"naturally populated reachable positive penguin item")
					if best>=0:
						var point := mask_point(best)
						trace.append({"label":label,"target_cell":best,"item":model.items_grid[best],"viewport_point":point})
						push_click(view,panel,point)
						for tick in range(150):
							if int(game.minigame_snapshot().reward)>0 or bool(game.minigame_snapshot().finished): break
							controller._process(0.1)
				else:
					push_motion(view,panel,Vector2(330,380))
					for tick in range(420):
						var snapshot: Dictionary=game.minigame_snapshot()
						if (not seek_bomb and int(snapshot.reward)>0) or bool(snapshot.finished): break
						var selected: Dictionary={}
						for item in snapshot.model.items:
							if not item.is_empty() and not bool(item.get("caught",false)) and not bool(item.get("retired",false)) and ((seek_bomb and int(item.id)==4) or (not seek_bomb and int(item.id)<4)):
								selected=item
								break
						if not selected.is_empty():
							var x := float(selected.origin_x)+float(selected.drift)*0.8
							push_motion(view,panel,Vector2(x,380))
							trace.append({"label":label,"tick":tick,"natural_item":selected,"pointer_x":x,"actor":snapshot.model.character_position})
						controller._process(0.05)
				var scored: Dictionary=game.minigame_snapshot()
				trace.append({"label":label,"scored":scored})
				var succeeded: bool=bool(scored.model.get("bomb",false)) if seek_bomb else int(scored.reward)>0
				check(succeeded,"legal natural "+scenario+" reaches the intended outcome")
				if seek_bomb and succeeded:
					check(panel.phase()=="ending","natural bomb starts source ending")
					panel.tick(0.5)
					trace.append({"label":label,"source_bomb_top_left":Vector2(scored.model.character_position.x-55,295),"source_delay_ms":114,"source_dimensions":Vector2i(110,110),"source_frame":4,"alpha":"palette index0 transparent"})
				await capture(view,output,label+("-bomb-active" if seek_bomb else "-scored"),panel)
				if not succeeded:
					FileAccess.open(output.path_join("trace.json"),FileAccess.WRITE).store_string(JSON.stringify(trace,"\t"))
					print("STOP natural scoring failed; no retry")
					quit(1)
					return
				for tick in range(420):
					if bool(game.minigame_snapshot().finished): break
					controller._process(0.1 if kind=="penguin" else 0.05)
				if panel.phase()=="ending": panel.tick(4.0)
				check(panel.is_result(),"natural score reaches source result")
				await capture(view,output,label+"-result",panel)
				var points := int(game.state.players[0].points)
				var cash := int(game.state.players[0].cash)
				var reward := int(game.minigame_snapshot().reward)
				var id := int(game.minigame_snapshot().encounter_id)
				panel.tick(2.0)
				await settle()
				check(game.state.phase=="await_action" and not ui._source_minigame_modal_open(),"natural-score result returns to host")
				check(int(game.state.players[0].points)==points+reward and int(game.state.players[0].cash)==cash,"natural earned POINT coupons only")
				var after: Dictionary=game.to_dict()
				check(not game.finish_minigame(id).ok and game.to_dict()==after,"natural reward settles exactly once")
			view.queue_free()
			await settle()
	FileAccess.open(output.path_join("trace.json"),FileAccess.WRITE).store_string(JSON.stringify(trace,"\t"))
	FileAccess.open(output.path_join("captures.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
	print("Natural scoring native checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
