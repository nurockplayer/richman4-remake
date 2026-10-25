extends SceneTree
const Fixture = preload("res://tests/fixtures/company_fixture.gd")
class TitleTestUI extends "res://game/ui/main_ui.gd":
	var quit_intents := 0
	var option_intents := 0
	func _on_source_option_requested() -> void: option_intents += 1
	func _setup_audio() -> void: pass
	func _on_source_quit_requested() -> void: quit_intents += 1
	func _load_map_catalog(path: String = "", _fallback: bool = false) -> void:
		if not OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
			super._load_map_catalog(path)
			return
		_map_catalog = []
		for edition in ["Game", "MultiverseJourney"]:
			for number in range(1, 5 if edition == "Game" else 9):
				var definition: Dictionary = Fixture.definition().duplicate(true)
				definition.id = "%s:%d" % [edition, number]
				definition.source.edition = edition
				definition.source.map_number = number
				definition.source.archive = edition + "/map.mkf"
				definition.source.entry_index = number
				_map_catalog.append(definition)
		_map_catalog_complete = _catalog_has_complete_original_content(_map_catalog)
		_map_catalog_ok = _map_catalog_complete
		_selected_map_definition = _map_catalog[0].duplicate(true)
		_update_map_selector()
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func settle() -> void:
	await process_frame
	await process_frame
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	viewport.notify_mouse_entered()
	var ui := TitleTestUI.new()
	viewport.add_child(ui)
	await settle()
	ui.set_process(false)
	var shell: Control = ui.source_shell
	check(ui._map_catalog_complete and ui.game_state != null, "ordinary catalog entry is source-capable")
	check(shell.is_title_visible() and shell.get("_source_edition") == "Game", "ordinary launch uses the Game title")
	var before: String = ui.game_state.to_json()
	press(viewport, shell.title_option_button)
	check(ui.option_intents == 1, "ordinary title OPTION reaches the S35 host entry")
	check(ui.game_state.to_json() == before, "OPTION entry preserves current match and RNG")
	var exit_button: Button = shell.title_screen.find_child("SourceTitleExit", true, false)
	check(exit_button != null, "source title supplies the missing EXIT control")
	check(shell.has_signal("quit_requested"), "title exit has a host quit-intent boundary")
	if exit_button != null:
		press(viewport, exit_button)
		check(ui.quit_intents == 1, "source EXIT reaches host exactly once without the test quitting")
	check(ui.game_state.to_json() == before, "title quit intent does not mutate game or RNG")
	check(shell.title_screen.find_child("SourceTitleNewStage", true, false) == null, "Game title has no expansion NEW STAGE")
	press(viewport, shell.title_start_button)
	await settle()
	var setup: Control = shell.source_setup_panel
	check(shell.is_setup_visible() and setup.get("_edition") == "Game" and setup.get("_stage") == 0, "Game START enters its four-map stage")
	check(ui.game_state.to_json() == before, "opening source setup preserves game and RNG")
	setup.cancel()
	check(shell.is_title_visible(), "setup cancellation returns to title intent")
	var expansion := find_map(ui, "MultiverseJourney", 7)
	check(not expansion.is_empty(), "catalog has the requested expansion stage fixture")
	check(ui._new_game(13307, 4, expansion, ui._default_setup_options(4, expansion)), "validated factory enters actual expansion map seven")
	before = ui.game_state.to_json()
	check(shell.get("_source_edition") == "MultiverseJourney", "shell follows the adopted expansion edition")
	shell.show_title()
	var new_stage: Button = shell.title_screen.find_child("SourceTitleNewStage", true, false)
	check(new_stage != null and new_stage.visible, "expansion title exposes NEW STAGE")
	press(viewport, shell.title_start_button)
	await settle()
	check(setup.get("_edition") == "MultiverseJourney" and setup.get("_stage") == 0, "expansion START resets to original stage instead of active map seven")
	var selected: Dictionary = setup.get("_selected_map")
	check(int(selected.get("source", {}).get("map_number", 0)) in range(1, 5), "expansion START selects one of its first four catalog maps")
	check(bool(selected.get("supports_original_companies", false)), "stage selection preserves validated source capabilities")
	check(ui.game_state.to_json() == before, "stage selection preserves active expansion match and RNG")
	setup.cancel()
	check(shell.is_title_visible(), "expansion setup cancellation returns to expansion title")
	if new_stage != null:
		press(viewport, new_stage)
		await settle()
		selected = setup.get("_selected_map")
		check(shell.is_setup_visible() and setup.get("_stage") == 1, "NEW STAGE enters stage one")
		check(int(selected.get("source", {}).get("map_number", 0)) in range(5, 9), "NEW STAGE selects only expansion maps five through eight")
		check(ui.game_state.to_json() == before, "NEW STAGE waits for setup confirmation before mutation")
		setup.get_node("OK").pressed.emit()
		await settle()
		check(not shell.is_setup_visible() and not shell.is_title_visible(), "new-stage confirmation returns to board")
		check(ui.game_state.get_stock_symbols().size() == 12 and bool(ui.state.get("original_companies", false)), "new-stage confirmation retains the twelve-company capability")
		check(int(ui.state.get("map_source", {}).get("map_number", 0)) in range(5, 9), "new-stage game uses the selected source stage")
		# A missing expansion stage cannot silently fall back to another set.
		shell.show_title()
		ui._map_catalog = ui._map_catalog.filter(func(definition: Dictionary) -> bool: return definition.get("source", {}).get("edition", "") != "MultiverseJourney" or int(definition.get("source", {}).get("map_number", 0)) < 5)
		before = ui.game_state.to_json()
		new_stage = shell.title_screen.find_child("SourceTitleNewStage", true, false)
		press(viewport, new_stage)
		check(shell.is_title_visible() and not shell.is_setup_visible(), "missing stage keeps the title instead of opening the wrong map set")
		check(ui.content_error_dialog.visible and ui.game_state.to_json() == before, "missing stage is explicit and preserves active match")
		ui.content_error_dialog.hide()
	var base_game := find_map(ui, "Game", 1)
	check(ui._new_game(13301, 4, base_game, ui._default_setup_options(4, base_game)), "source factory can return to Game")
	shell.show_title()
	check(shell.get("_source_edition") == "Game" and shell.title_screen.find_child("SourceTitleNewStage", true, false) == null, "returning to Game removes expansion title actions")
	viewport.queue_free()
	await settle()
	print("Source title UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
func find_map(ui: Control, edition: String, number: int) -> Dictionary:
	for value in ui.get("_map_catalog"):
		if value.get("source", {}).get("edition", "") == edition and int(value.get("source", {}).get("map_number", 0)) == number:
			return value.duplicate(true)
	return {}
func press(viewport: SubViewport, button: Button) -> void:
	if button == null:
		return
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		viewport.push_input(event, true)
