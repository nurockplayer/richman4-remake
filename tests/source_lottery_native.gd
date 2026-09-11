extends "res://tests/source_title_ui.gd"
const LotteryPanel = preload("res://game/ui/source_lottery_panel.gd")
const Flow = preload("res://game/core/lottery_flow.gd")
func run() -> void:
	var output := OS.get_environment("RICHMAN4_LOTTERY_CAPTURE")
	var edition := OS.get_environment("RICHMAN4_LOTTERY_EDITION")
	if output.is_empty() or edition not in ["Game","MultiverseJourney"] or OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		print("PRECONDITION_UNMET: native capture directory, edition, installed catalog required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var ui := TitleTestUI.new()
	root.add_child(ui)
	await settle()
	ui.set_process(false)
	check(ui._map_catalog_complete and ui._map_catalog.size() == 12, "native host loads actual installed catalog without capability injection")
	var definition := find_map(ui,edition,1 if edition == "Game" else 7)
	check(ui._new_game(42,4,definition,ui._default_setup_options(4,definition)), "native ordinary source factory creates selected edition")
	var visuals: Variant = ui.source_shell.get("_visuals")
	var players: Array = Flow.presentation_players(ui.game_state.state.players)
	var records: Array = []
	for scale_value in [1,2]:
		var view := SubViewport.new()
		view.size = Vector2i(640,480)*scale_value
		view.handle_input_locally = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var panel := LotteryPanel.new()
		panel.scale = Vector2.ONE*scale_value
		view.add_child(panel)
		panel.set_visuals(visuals)
		var tickets: Array = []
		tickets.resize(36)
		tickets.fill(0)
		tickets[1] = 2
		var purchase := {"kind":"purchase","edition":edition,"players":players,"player_id":0,"cash":1000,"jackpot":12000,"tickets":tickets}
		check(panel.set_view_model(purchase) and panel.source_art_available(), "source purchase uses verified original art")
		await capture(view,output,"%s-purchase-live-%dx" % [edition,scale_value],records)
		var before: Dictionary = purchase.duplicate(true)
		check(panel.ticket_at(Vector2(30,271)) == 1 and panel.ticket_at(Vector2(605,462)) == 36 and panel.ticket_at(Vector2(606,463)) == 0, "source logical boundaries are physical-scale independent")
		check(not panel.can_select_ticket(2), "sold source number remains inert")
		panel.call("_select_ticket",1)
		check(purchase == before and panel.selected_number() == 1, "native injected selection leaves owner data unchanged")
		await capture(view,output,"%s-purchase-selected-%dx" % [edition,scale_value],records)
		purchase.cash = 999
		panel.set_view_model(purchase)
		check(not panel.can_select_ticket(1), "native refusal at999")
		await capture(view,output,"%s-purchase-refused-%dx" % [edition,scale_value],records)
		purchase.cash = 1000
		purchase.tickets.fill(1)
		panel.set_view_model(purchase)
		check(not panel.can_select_ticket(36), "native soldout is inert")
		await capture(view,output,"%s-purchase-soldout-%dx" % [edition,scale_value],records)
		var draw := {"kind":"draw","edition":edition,"players":players,"tickets":purchase.tickets.duplicate(),"number":7,"winner_id":0,"amount":36000,"jackpot":36000}
		panel.set_view_model(draw)
		await capture(view,output,"%s-draw-drum-%dx" % [edition,scale_value],records)
		await create_timer(2.3).timeout
		await capture(view,output,"%s-draw-ball-%dx" % [edition,scale_value],records)
		await create_timer(1.8).timeout
		await capture(view,output,"%s-draw-winner-%dx" % [edition,scale_value],records)
		check(panel.get_node("LotteryPool").get_index() > panel.get_node("LotteryHostLeft").get_index(), "raised sign text is drawn above final host")
		check(panel.get_node("LotteryPool").position == Vector2(26,43), "winning host moves pool text to source raised sign")
		check(panel.source_frames().get("animation_17",{}).get("frame",-1) == 36, "all red-ball animation frames progressed to final frame")
		draw.winner_id = -1
		draw.amount = 0
		draw.tickets.fill(0)
		draw.tickets[0] = 1
		panel.set_view_model(draw)
		# Explicitly injected presentation time for rare no-winner capture.
		panel.call("_process",4.0)
		await capture(view,output,"%s-draw-no-winner-%dx" % [edition,scale_value],records)
		view.queue_free()
		await settle()
	FileAccess.open(output.path_join("%s-captures.json" % edition),FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
	ui.queue_free()
	await settle()
	print("Lottery native render/injected checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
func capture(view: SubViewport, output: String, label: String, records: Array) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	var path := output.path_join(label+".png")
	check(picture != null and picture.get_size() == view.size, "native capture dimensions: " + label)
	check(picture.save_png(path) == OK, "native capture saved: " + label)
	records.append({"path":path,"sha256":FileAccess.get_sha256(path),"width":view.size.x,"height":view.size.y,"input":"injected/native SubViewport; physical OS input unverified"})
