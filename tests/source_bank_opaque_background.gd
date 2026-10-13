extends "res://tests/source_bank_visual.gd"

class OpaqueSourceVisuals extends RefCounted:
	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		return {"edition": edition, "archive": archive, "resource": resource, "chunk": chunk}
	func texture(frame: Dictionary) -> Texture2D:
		var image := Image.create(640, 480, false, Image.FORMAT_RGBA8)
		image.fill(Color("c08870"))
		# UI atlas decoding represents a zero RGB555 word with alpha zero.
		# Bank backgrounds use the source opaque copy, unlike sprite overlays.
		if int(frame.resource) == 23 and int(frame.chunk) in [0, 2]:
			image.fill_rect(Rect2i(580, 10, 20, 20), Color(0, 0, 0, 0))
		return ImageTexture.create_from_image(image)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: opaque source-background compositing requires native rendering")
		quit(0)
		return
	for edition in ["Game", "MultiverseJourney"]:
		var view := viewport()
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var behind := ColorRect.new()
		behind.size = Vector2(640, 480)
		view.add_child(behind)
		var panel := Bank.new()
		view.add_child(panel)
		panel.set_view_model({"edition": edition, "entry_mode": "loan", "allowed_actions": ["take_loan", "take_special_finance", "exit"], "action_limits": {"take_loan": 3300, "take_special_finance": 400}, "cash": 6800, "deposit": 3400, "can_special": true})
		panel.set_visuals(OpaqueSourceVisuals.new())
		for scene in ["front", "rear"]:
			if scene == "rear":
				click(view, Vector2(492, 245))
				await settle()
			for color in [Color.BLUE, Color.GREEN]:
				behind.color = color
				await settle()
				await RenderingServer.frame_post_draw
				var rendered := view.get_texture().get_image()
				check(rendered != null and rendered.get_pixel(570, 20).is_equal_approx(Color("c08870")), "qualified source background renders before opacity assertion")
				var actual := rendered.get_pixel(588, 20)
				print("OPAQUE_COPY_PROBE edition=%s scene=%s behind=%s pixel=%s" % [edition, scene, color, actual])
				check(actual.is_equal_approx(Color.BLACK), "source full-bank background overwrites zero RGB555 with black")
		view.queue_free()
		await settle()
	print("Source bank opacity checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
