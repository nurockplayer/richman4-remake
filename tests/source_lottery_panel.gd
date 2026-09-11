extends SceneTree

## Hermetic S29/S30 presenter checks.  The host model is detached and the
## presenter emits intents only; no game state or finance owner is loaded.
const PanelScript = preload("res://game/ui/source_lottery_panel.gd")
var checks := 0
var failures := 0
var selected: Array = []
var cancelled_count := 0
var continued_count := 0

class Visuals extends RefCounted:
	var calls: Array = []
	func ui(edition: String, archive: String, resource: int, chunk: int) -> Dictionary:
		calls.append([edition, archive, resource, chunk])
		var size := Vector2(1, 1)
		if resource in [12, 15] and chunk == 0: size = Vector2(640, 480)
		elif resource == 12 and chunk == 1: size = Vector2(358, 298)
		elif resource == 12 and chunk == 9: size = Vector2(172, 28)
		elif resource == 15 and chunk == 22: size = Vector2(187, 140)
		elif resource == 15 and chunk == 23: size = Vector2(233, 192)
		elif resource == 15 and chunk == 24: size = Vector2(295, 262)
		return {"edition": edition, "archive": archive, "resource": resource, "chunk": chunk, "logical": {"width": size.x, "height": size.y}}
	func texture(frame: Dictionary) -> Texture2D:
		var logical: Dictionary = frame.get("logical", {})
		var image := Image.create(maxi(1, int(logical.get("width", 1))), maxi(1, int(logical.get("height", 1))), false, Image.FORMAT_RGBA8)
		image.fill(Color("#2e6a73"))
		return ImageTexture.create_from_image(image)

func _initialize() -> void:
	call_deferred("_run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func purchase_model(cash: int = 1000) -> Dictionary:
	var tickets: Array = []
	for index in 36: tickets.append(0)
	tickets[1] = 2
	return {"kind": "purchase", "edition": "Game", "tickets": tickets, "cash": cash, "jackpot": 9000, "player_id": 1, "players": [{"id": 1, "name": "玩家一"}, {"id": 2, "name": "玩家二"}]}

func draw_model() -> Dictionary:
	var tickets: Array = []
	for index in 36: tickets.append(0)
	tickets[1] = 2
	return {"kind": "draw", "edition": "MultiverseJourney", "tickets": tickets, "number": 2, "winner_id": 2, "amount": 10000, "jackpot": 10000, "players": [{"id": 2, "name": "沙隆巴斯"}]}

func _run() -> void:
	var panel := PanelScript.new()
	root.add_child(panel)
	panel.ticket_selected.connect(func(number: int) -> void: selected.append(number))
	panel.cancelled.connect(func() -> void: cancelled_count += 1)
	panel.continued.connect(func() -> void: continued_count += 1)
	var model := purchase_model()
	var before := model.duplicate(true)
	var visuals := Visuals.new()
	panel.set_visuals(visuals)
	expect(panel.set_view_model(model), "purchase model accepted")
	expect(panel.is_model_valid() and panel.is_open(), "purchase opens")
	expect(panel.source_geometry().get("grid_origin") == Vector2(30, 271), "source grid origin is exact")
	expect(panel.source_geometry().get("cell_size") == Vector2(64, 48), "source grid cell is exact")
	expect(panel.source_animation_contract()[14]["interval_ms"] == 100 and panel.source_animation_contract()[16]["interval_ms"] == 50, "FLIC caller cadence contract is exposed")
	expect(panel.is_ticket_sold(2) and not panel.is_ticket_sold(1), "sold slots are distinguished")
	expect(not panel.can_select_ticket(2), "sold ticket is inert")
	expect(not panel.can_select_ticket(37), "outside ticket is inert")
	panel.call("_select_ticket", 1)
	expect(selected == [1] and not panel.is_open(), "valid purchase emits once and closes")
	expect(model == before, "presenter does not mutate purchase host model")
	panel.set_view_model(purchase_model(999))
	panel.call("_select_ticket", 1)
	expect(selected == [1], "cash below source price cannot select")
	panel.set_view_model(purchase_model())
	panel.close_lottery()
	expect(cancelled_count == 1, "explicit close emits cancellation")
	panel.set_view_model(draw_model())
	expect(panel.is_model_valid() and panel.kind() == "draw", "draw model accepted")
	expect(panel.find_child("LotteryDrawNumber", true, false) != null, "draw result number is presented")
	panel.continue_draw()
	panel.continue_draw()
	expect(continued_count == 1 and not panel.is_open(), "draw continues exactly once")
	panel.set_view_model({"kind": "purchase", "edition": "Game", "tickets": [0], "cash": 1000, "jackpot": 0, "player_id": 1, "players": []})
	expect(not panel.is_model_valid() and panel.find_child("LotteryUnavailable", true, false) != null, "wrong ticket shape is rejected fail closed")
	print("Source lottery panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
