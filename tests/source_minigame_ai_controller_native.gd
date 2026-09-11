extends "res://tests/source_autosave_ui.gd"

# Native MainUI/controller lifecycle gate. Only wall-clock AI scheduling is
# disabled; the real timeout handler is invoked explicitly after result return.
class Host extends TitleTestUI:
	func _maybe_schedule_ai_turn() -> void: pass

func run() -> void:
	if OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("PRECONDITION_UNMET actual installed catalog required")
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640,480)
	root.add_child(viewport)
	var ui := Host.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	ui._source_settings.autosave = true
	ui._source_settings.animation = true
	var folder := "/tmp/richman4-minigame-ai-native-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	var storage := CountSlots.new(folder.path_join("slots"),folder.path_join("legacy.json"))
	ui.source_save_menu.storage = storage
	var definition := find_map(ui,"Game",1)
	for event_code in [6,7,8]:
		for mode in ["ai","trustee"]:
			var options: Dictionary = ui._default_setup_options(4,definition)
			options.human_flags = [true,true,true,mode == "trustee"]
			check(ui._new_game(71,4,definition,options),"actual catalog normal new-game entry")
			var game: Object = ui.game_state
			if mode == "trustee":
				var rows: Array = game.trustee_rows()
				rows[3].trustee = true
				check(game.apply_trustee_settings(rows),"public trustee admission")
			var node := -1
			for index in range(game.state.board.size()):
				if int(game.state.board[index].get("event_code",0)) == event_code and int(game.state.board[index].get("type_and_idx",0)) == 0:
					node = index
					break
			if node < 0:
				print("PRECONDITION_UNMET source event node")
				quit(2)
				return
			# Rare-event fixture: actual source node, internal landing; no injected reward.
			game.state.current_player = 3
			game.state.players[3].position = node
			game.state.phase = "await_action"
			game.configure_minigames(true)
			game._resolve_landing(3)
			var snapshot: Dictionary = game.minigame_snapshot()
			var player: Dictionary = game.state.players[3]
			var points := int(player.points)
			var cash := int(player.cash)
			var attempts := storage.attempts
			var waiting: Dictionary = game.run_ai_turn()
			check(waiting.ok and waiting.get("awaiting_response",false) and not waiting.get("completed",true),"UI turn runner preserves delayed shortcut presentation")
			check(game.minigame_snapshot() == snapshot and int(player.points) == points,"waiting does not settle or reroll")
			ui._handle_result(waiting)
			await settle()
			var controller: Control = ui.source_minigame_controller
			controller.set_process(false)
			var panel: Control = controller.panel
			if panel == null:
				print("PRECONDITION_UNMET actual MainUI shortcut panel")
				quit(2)
				return
			panel.set_process(false)
			ui._on_ai_timer_timeout()
			check(game.minigame_snapshot() == snapshot and storage.attempts == attempts,"host timer cannot advance through pending modal")
			panel.tick(2.28)
			panel.tick(4.0)
			panel.tick(2.0)
			await settle()
			check(not ui._source_minigame_modal_open() and game.state.phase == "await_action","real controller finish returns to host")
			check(int(player.points) == points + int(snapshot.reward) and int(player.cash) == cash,"host settles POINT once without cash")
			check(storage.attempts == attempts,"result return is not daily autosave")
			var after: Dictionary = game.to_dict()
			check(not ui._invoke_game("finish_minigame",[int(snapshot.encounter_id)]).ok and game.to_dict() == after,"stale host finish is inert")
			ui._on_ai_timer_timeout()
			await settle()
			check(game.state.current_player == 0 and game.state.phase == "await_roll" and game.state.day == 2,"real host AI timeout completes turn and wraps day")
			check(storage.attempts == attempts + 1 and not ui._source_autosave.pending(),"host continuation autosaves once")
			ui._refresh_from_state()
			ui._flush_source_autosave()
			check(storage.attempts == attempts + 1,"refresh cannot repeat autosave")
	viewport.queue_free()
	await settle()
	print("Minigame AI native controller checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
