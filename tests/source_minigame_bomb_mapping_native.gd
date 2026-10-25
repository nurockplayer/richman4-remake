extends SceneTree
const Visuals = preload("res://game/platform/original_visuals.gd")
const PanelScript = preload("res://game/ui/source_minigame_panel.gd")
const PAYLOAD = "50e851d43030406e1f2d2d181d41e52267e90938904bcf9740667858a94f96fd"
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var visuals := Visuals.new()
	if DisplayServer.get_name()=="headless" or visuals.manifest.is_empty():
		print("PRECONDITION_UNMET native display and existing source scene")
		quit(2)
		return
	for edition in ["Game","MultiverseJourney"]:
		var view := SubViewport.new()
		view.size=Vector2i(640,480)
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var panel := PanelScript.new()
		view.add_child(panel)
		panel.set_process(false)
		panel.set_visuals(visuals)
		panel.configure("catching",71)
		var model := {"kind":"catching","edition":edition,"finished":true,"reward":5,"model":{"bomb":true,"finished":true,"character_position":Vector2(320,380),"counts":[0,1,0,0]}}
		panel.set_view_model(model)
		panel.show_result(model)
		check(panel.phase()=="ending","bomb has a source ending interval")
		panel.tick(0.5)
		await process_frame
		await RenderingServer.frame_post_draw
		var expected := 485 if edition=="Game" else 526
		var frames: Dictionary=panel.source_frames().get("gameplay",{})
		var selected := "Data/%d/4" % expected
		check(frames.has(selected) and frames[selected].available,"actual renderer selects physical bomb frame4 for "+edition)
		if edition=="Game": check(not frames.has("Data/526/11"),"Game must not draw parachutist resource")
		var record: Dictionary=visuals.manifest.ui[edition].Data.resources.get(str(expected),{})
		check(record.get("payload_sha256","")==PAYLOAD and int(record.get("resource_index",-1))==expected,"selected resource has byte-identified bomb payload and truthful index")
		check(record.get("source",{}).get("payload_sha256","")==PAYLOAD and int(record.get("source",{}).get("resource_index",-1))==expected,"physical source provenance agrees with selected bomb")
		check(record.get("chunks",{}).size()==8 and int(record.get("caller",{}).get("delay_ms",0))==114,"actual decoded bomb is eight114ms frames")
		if not record.is_empty():
			var chunk: Dictionary=record.chunks.get("4",{})
			check(int(chunk.get("width",0))==110 and int(chunk.get("height",0))==110 and bool(chunk.get("transparent_index_zero",false)),"source bomb dimensions and overlay alpha role preserved")
		panel.tick(0.411)
		check(panel.phase()=="ending","bomb remains in ending at911ms")
		panel.tick(0.001)
		check(panel.is_result(),"bomb enters result exactly at912ms")
		view.queue_free()
		await process_frame
	print("Bomb source mapping native checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
