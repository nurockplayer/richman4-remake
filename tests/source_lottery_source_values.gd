extends "res://tests/source_lottery_panel.gd"
class AnimatedVisuals extends Visuals:
	func animation_frame(_edition: String, _archive: String, _resource: int, frame: int) -> Texture2D:
		var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
		image.fill(Color(float(frame % 4) / 4.0, 0.2, 0.1,1))
		return ImageTexture.create_from_image(image)
func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640,480)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var panel := PanelScript.new()
	viewport.add_child(panel)
	panel.set_visuals(AnimatedVisuals.new())
	panel.set_view_model(purchase_model())
	await process_frame
	await RenderingServer.frame_post_draw
	var first := viewport.get_texture().get_image()
	var changed := purchase_model()
	changed.jackpot = 123000
	panel.set_view_model(changed)
	await process_frame
	await RenderingServer.frame_post_draw
	var second := viewport.get_texture().get_image()
	expect(first.get_region(Rect2i(20,25,180,32)).get_data() != second.get_region(Rect2i(20,25,180,32)).get_data(), "source purchase plaque visibly reflects changing live jackpot")
	panel.set_view_model(draw_model())
	await process_frame
	await RenderingServer.frame_post_draw
	first = viewport.get_texture().get_image()
	await create_timer(0.16).timeout
	await RenderingServer.frame_post_draw
	second = viewport.get_texture().get_image()
	expect(first.get_region(Rect2i(183,75,275,200)).get_data() != second.get_region(Rect2i(183,75,275,200)).get_data(), "source drum animation progresses through decoded frames")
	viewport.queue_free()
	await process_frame
	print("Lottery source visible-value checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
