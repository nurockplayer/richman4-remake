extends "res://tests/source_title_ui.gd"
const Assets = preload("res://game/platform/source_minigame_assets.gd")
const Core = preload("res://game/core/game_state.gd")
var records: Array=[]
func run() -> void:
	var output := OS.get_environment("RICHMAN4_MINIGAME_CAPTURE")
	var edition := OS.get_environment("RICHMAN4_MINIGAME_EDITION")
	if DisplayServer.get_name()=="headless" or output.is_empty() or edition not in ["Game","MultiverseJourney"] or OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty() or Assets.input_data().is_empty():
		print("PRECONDITION_UNMET native display, installed catalog and private minigame data required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	for scale_value in [1,2]:
		var viewport := SubViewport.new()
		viewport.size=Vector2i(640,480)*scale_value
		viewport.handle_input_locally=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		viewport.notify_mouse_entered()
		var ui := TitleTestUI.new()
		viewport.add_child(ui)
		await settle()
		ui.set_process(false)
		check(ui._map_catalog_complete and ui._map_catalog.size()==12,"native MainUI loads actual twelve-map catalog")
		var stale: Callable
		for event_code in [7,6,8]:
			var definition := find_map(ui,edition,1 if edition=="Game" else 7)
			var options: Dictionary=ui._default_setup_options(4,definition)
			options.human_flags=[true,true,true,true]
			check(ui._new_game(71,4,definition,options),"native normal source factory constructs")
			var game: Object=ui.game_state
			var node := -1
			for i in range(game.state.board.size()):
				if int(game.state.board[i].get("event_code",0))==event_code and int(game.state.board[i].get("type_and_idx",0))==0: node=i;break
			if node<0:
				print("PRECONDITION_UNMET source event node missing")
				quit(2)
				return
			game.configure_minigames(true,Assets.input_data())
			game.state.players[0].position=node
			game.state.phase="await_action"
			game._resolve_landing(0)
			ui._handle_result(game._result(true))
			await settle()
			var controller: Control=ui.source_minigame_controller
			controller.set_process(false)
			var panel: Control=controller.panel
			if panel==null:
				print("PRECONDITION_UNMET actual MainUI minigame panel missing")
				quit(2)
				return
			controller._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
			check(controller.is_open() and panel.visible and panel.source_art_available(),"actual source art opens through MainUI")
			var before: Dictionary=game.to_dict()
			check(not ui._invoke_game("end_turn").get("ok",false) and not ui._source_save_operation_allowed() and ui._load_blocked_by_presentation(),"pending game excludes end/save/load")
			if stale.is_valid(): stale.call()
			check(game.to_dict()==before and controller.is_open(),"old owner callback is inert")
			stale=panel.finish_requested.get_connections()[0].callable
			var kind: String=game.minigame_snapshot().kind
			panel.tick(1.14)
			await capture(viewport,output,"%s-%s-intro-%dx" % [edition,kind,scale_value],panel)
			controller._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			var frozen: Dictionary=game.minigame_snapshot()
			controller._process(1.0)
			check(game.minigame_snapshot()==frozen,"native notified focus loss pauses core and intro")
			controller._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
			panel.tick(1.14)
			check(panel.is_playing(),"intro finishes separately from zero gameplay ticks")
			check(int(game.minigame_snapshot().model.tick)==0,"intro does not consume gameplay deadline")
			if kind=="catching":
				push_motion(viewport,panel,Vector2(430,300))
				controller._process(0.05)
				check(game.minigame_snapshot().model.character_position.x==330,"viewport mouse motion follows source horizontal target at both scales")
				for i in range(59): controller._process(0.05)
				check(int(game.minigame_snapshot().model.spawn_count)>0,"native catching naturally throws source items")
			elif kind=="penguin":
				var point := mask_point(6*9+3)
				push_click(viewport,panel,point)
				controller._process(0.2)
				check(game.minigame_snapshot().model.movement_state=="walking","viewport source click-plane starts penguin movement at both scales")
			else:
				controller._process(1.0)
				var balloon: Dictionary={}
				for entry in game.minigame_snapshot().model.balloons:
					if int(entry.get("phase",0))==1 and int(entry.id)<9 and float(entry.y)>35 and float(entry.y)<380: balloon=entry;break
				check(not balloon.is_empty(),"natural balloon spawn supplies a source click target")
				if not balloon.is_empty():
					var reward := int(game.minigame_snapshot().reward)
					push_click(viewport,panel,Vector2(balloon.x,balloon.y))
					check(int(game.minigame_snapshot().reward)>reward,"viewport balloon click awards source points at both scales")
			await capture(viewport,output,"%s-%s-play-%dx" % [edition,kind,scale_value],panel)
			push_click(viewport,panel,Vector2(320,240),MOUSE_BUTTON_RIGHT)
			check(controller.is_open(),"right-click cannot abandon active minigame")
			for i in range(420):
				if panel.is_playing(): controller._process(0.05 if kind=="catching" else 0.1)
			check(bool(game.minigame_snapshot().finished),"source deadline and any airborne drain complete")
			if panel.phase()=="ending": panel.tick(4.0)
			check(panel.is_result(),"result waits after source ending animation")
			await capture(viewport,output,"%s-%s-result-%dx" % [edition,kind,scale_value],panel)
			var cash := int(game.state.players[0].cash)
			var points := int(game.state.players[0].points)
			var reward := int(game.minigame_snapshot().reward)
			var id := int(game.minigame_snapshot().encounter_id)
			panel.tick(2.0)
			await settle()
			check(game.state.phase=="await_action" and not ui._source_minigame_modal_open(),"actual MainUI completion releases pending game")
			check(int(game.state.players[0].points)==points+reward and int(game.state.players[0].cash)==cash,"native settlement changes only points once")
			var after: Dictionary=game.to_dict()
			check(not game.finish_minigame(id).ok and game.to_dict()==after,"native duplicate completion is inert")
			check(Core.validate_save(after).ok and ui._source_save_operation_allowed(),"native returned owner is saveable")
		viewport.queue_free()
		await settle()
	FileAccess.open(output.path_join(edition+"-captures.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
	print("Minigame native MainUI/render/injected checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
func push_motion(view: SubViewport,panel: Control,point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position=panel.get_global_transform_with_canvas()*point
	event.global_position=event.position
	view.push_input(event,true)
func push_click(view: SubViewport,panel: Control,point: Vector2,button: int=MOUSE_BUTTON_LEFT) -> void:
	push_motion(view,panel,point)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=panel.get_global_transform_with_canvas()*point
		event.global_position=event.position
		event.button_index=button
		event.pressed=down
		view.push_input(event,true)
func mask_point(id: int) -> Vector2:
	var mask: PackedByteArray=Assets.input_data().penguin_mask
	var sum := Vector2.ZERO
	var count := 0
	for i in range(mask.size()):
		if int(mask[i])==id: sum+=Vector2(i%640,int(i/640));count+=1
	return sum/float(maxi(1,count))
func capture(view: SubViewport,output: String,label: String,panel: Control) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	var path := output.path_join(label+".png")
	check(picture!=null and picture.get_size()==view.size,"native capture dimensions "+label)
	check(picture.save_png(path)==OK,"native capture written "+label)
	records.append({"path":path,"sha256":FileAccess.get_sha256(path),"width":view.size.x,"height":view.size.y,"source_frames":panel.source_frames(),"input":"injected SubViewport mouse/focus notifications; physical OS input PRECONDITION_UNMET"})
