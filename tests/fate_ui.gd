extends SceneTree
const MainScene = preload("res://game/main.tscn")
const Game = preload("res://game/core/game_state.gd")
const Base = preload("res://tests/fixtures/news_fixture.gd")
const Maps = preload("res://game/content/original_maps.gd")

func definition() -> Dictionary:
	var result: Dictionary = Base.definition()
	result.board.back().event_code = 3
	result.board.back().source_status_bits = 3
	result.board.back().kind = Maps.classify_source_node(0, 3).kind
	return result
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ui = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui.set_process(false)
	check(ui._new_game(5611, 4, definition(), Base.new_game_options()), "fate UI creates legal map")
	var game: Object = ui.game_state
	game.state.god_objects = []
	for player_id in range(4): game.set_player_ai(player_id, false)
	var order: Array = [20]
	for id in range(37):
		if id != 20: order.append(id)
	game.state.fate = {"order": order, "cursor": 0, "draw_count": 0, "last": {}}
	check(Game.validate_save(game.to_dict()).get("ok", false), "fate UI fixture validates")
	check(ui._kind_label("fate") == "命運", "property card names fate kind")
	check(ui.board_view._kind_label("fate") == "命運", "board names fate kind")
	ui._refresh_from_state()
	var initial_popup: Node = ui.find_child("FatePopup", true, false)
	check(initial_popup == null or not initial_popup.visible, "no fate result popup before draw")
	game._graph_visit_tile(0, game.state.board.back(), true)
	var after: String = game.to_json()
	ui._refresh_from_state()
	await process_frame
	var popup: Node = ui.find_child("FatePopup", true, false)
	check(popup != null and popup.visible, "actual fate landing shows a popup")
	var summary: Node = ui.find_child("FateSummary", true, false)
	check(summary != null, "fate popup exposes readable summary")
	if summary != null:
		var text: String = str(summary.text)
		check((text.contains("1000") or text.contains("1,000")), "fate summary displays actual 1000 cash reward")
		check(not text.contains("event_id") and not text.contains("raw_payload") and not text.contains("0x1b9"), "fate UI hides implementation payload")
	if popup != null and popup.visible:
		game.set_player_ai(0, true)
		ui._refresh_from_state()
		var paused: String = game.to_json()
		ui._on_ai_timer_timeout()
		check(game.to_json() == paused, "visible fate result pauses queued UI AI timer")
		game.set_player_ai(0, false)
		ui._refresh_from_state()
	else:
		check(false, "fate result presentation guards UI AI timer")
	var close: Button = ui.find_child("CloseFate", true, false)
	check(close != null and not close.disabled, "fate popup has an enabled close action")
	if close != null: close.pressed.emit()
	await process_frame
	check(popup == null or not popup.visible, "close dismisses fate result")
	check(game.to_json() == after, "viewing and closing never reapplies fate")
	ui._refresh_from_state()
	check(popup == null or not popup.visible, "refresh does not reopen same completed result")
	var restored: Object = Game.from_dict(JSON.parse_string(after))
	check(restored != null, "fate UI state reloads")
	if restored != null:
		ui.game_state = restored
		ui._refresh_from_state()
		check(restored.to_json() == after, "display after load does not charge reward again")
		check(int(restored.state.get("fate", {}).get("draw_count", 0)) == 1, "display after load preserves one draw")
	check(ui._new_game(5612, 4, definition(), Base.new_game_options()), "fate UI starts a fresh match")
	ui.set_process(false)
	check(not ui.game_state.state.has("fate"), "new match has no stale fate result")
	popup = ui.find_child("FatePopup", true, false)
	check(popup == null or not popup.visible, "new match hides prior fate popup")
	ui.queue_free()
	print("Fate UI checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
