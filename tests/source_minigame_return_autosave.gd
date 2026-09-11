extends "res://tests/source_autosave_ui.gd"

func run() -> void:
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("PRECONDITION_UNMET actual installed catalog required")
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640,480)
	root.add_child(viewport)
	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	ui._source_settings.autosave = true
	ui._source_settings.animation = false
	var folder := "/tmp/richman4-minigame-return-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	var storage := CountSlots.new(folder.path_join("slots"),folder.path_join("legacy.json"))
	ui.source_save_menu.storage = storage
	var definition := find_map(ui,"Game",1)
	for event_code in [6,7,8]:
		var options: Dictionary = ui._default_setup_options(4,definition)
		options.human_flags = [true,true,true,true]
		check(ui._new_game(71,4,definition,options),"normal source setup for daily return")
		var game: Object = ui.game_state
		var node := -1
		for index in range(game.state.board.size()):
			if int(game.state.board[index].get("event_code",0))==event_code and int(game.state.board[index].get("type_and_idx",0))==0:
				node=index
				break
		if node<0:
			print("PRECONDITION_UNMET source event node")
			quit(2)
			return
		game.state.current_player=3
		game.state.players[3].position=node
		game.state.phase="await_action"
		game.configure_minigames(false)
		game._resolve_landing(3)
		ui._handle_result(game._result(true))
		await settle()
		var controller: Control=ui.source_minigame_controller
		controller.set_process(false)
		var panel: Control=controller.panel
		if panel==null:
			print("PRECONDITION_UNMET actual MainUI result panel")
			quit(2)
			return
		panel.set_process(false)
		var attempts := storage.attempts
		check(not ui._invoke_game("end_turn").ok and storage.attempts==attempts,"pending shortcut cannot wrap day or autosave")
		panel.tick(2.28)
		panel.tick(4.0)
		panel.tick(2.0)
		await settle()
		check(not ui._source_minigame_modal_open() and game.state.phase=="await_action","source result releases actual host")
		check(storage.attempts==attempts,"minigame completion itself is not a daily autosave trigger")
		ui._on_end_turn_pressed()
		await settle()
		check(game.state.day==2 and game.state.phase=="await_roll","returned last actor can wrap day normally")
		check(storage.attempts==attempts+1 and not ui._source_autosave.pending(),"daily wrap after minigame autosaves exactly once")
		ui._refresh_from_state()
		ui._flush_source_autosave()
		check(storage.attempts==attempts+1,"refresh cannot repeat post-minigame autosave")
	viewport.queue_free()
	await settle()
	print("Minigame return/autosave checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
