extends "res://tests/source_date_panel.gd"

class HotkeyVisuals extends FakeVisuals:
	func _logical(chunk: int) -> Vector2:
		return Vector2(328,336) if chunk == 1 else super._logical(chunk)

func _run() -> void:
	var pair := _new_panel()
	var viewport: SubViewport = pair.viewport
	var panel: Control = pair.panel
	for edition in ["Game","MultiverseJourney"]:
		await _present(panel,_model({"year":1998,"month":1,"day":31},{"year":2026,"month":9,"day":11},edition),FakeVisuals.new())
		_expect(panel.is_model_valid() and panel.source_art_available(),"date legibility fixture is valid")
		for area in [HITBOXES.month_up,HITBOXES.accept]:
			viewport.push_input(_mouse_event(FRAME_ORIGIN+area.get_center(),MOUSE_BUTTON_LEFT,true),true)
			await _settle()
			viewport.push_input(_mouse_event(FRAME_ORIGIN+area.get_center(),MOUSE_BUTTON_LEFT,false),true)
			await _settle()
		_expect(panel.is_open() and not panel.is_draft_date_valid() and panel.invalid_confirm_visible(),"invalid date confirmation remains open with explanation")
		var hint: Label = panel.find_child("SourceDateInvalidConfirm",true,false)
		var frame: TextureRect = panel.find_child("SourceDateFrame",true,false)
		_expect(hint.z_index > frame.z_index or hint.z_index == frame.z_index and hint.get_index() > frame.get_index(),"invalid date explanation draws above the opaque source frame")
	panel.queue_free()
	await _settle()
	var hotkeys: Control = load("res://game/ui/source_hotkeys_panel.gd").new()
	viewport.add_child(hotkeys)
	hotkeys.set_visual_accessor(HotkeyVisuals.new())
	for edition in ["Game","MultiverseJourney"]:
		hotkeys.set_view_model({"edition":edition,"bindings":load("res://game/platform/system_hotkeys.gd").new().defaults()})
		await _settle()
		_expect(hotkeys.is_model_valid() and hotkeys.source_art_available(),"hotkey legibility fixture is valid")
		for name_value in ["Reset","Cancel","Accept"]:
			var label: Label = hotkeys.find_child("SourceHotkeys%sLabel" % name_value,true,false)
			_expect(label.get_theme_color("font_color") == Color("#101010"),"source precomposed hotkey footer uses dark text on light buttons")
	viewport.queue_free()
	await _settle()
	print("Source children legibility checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
