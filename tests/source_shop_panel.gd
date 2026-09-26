extends SceneTree

const PATH := "res://game/ui/source_shop_panel.gd"
var checks := 0
var failures := 0
var actions: Array = []
var cancels := 0

func _initialize() -> void: call_deferred("_run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + message)

func _event(point: Vector2, button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = button; event.pressed = pressed; return event

func _settle() -> void:
	await process_frame; await process_frame

func _model(mode := "cards", edition := "Game", ready := true, gift := "") -> Dictionary:
	var card_offers: Array = [{"source_id": 1, "name": "均富", "price": 200}, {}, {"source_id": 1, "name": "均富", "price": 200}, {"source_id": 2, "name": "均貧", "price": 200}]
	var tool_offers: Array = [{"source_id": 1, "name": "娃娃", "price": 15}, {}, {"source_id": 3, "name": "地雷", "price": 25}]
	return {"edition":edition, "visit_id":42, "mode":mode, "card_offers":card_offers, "tool_offers":tool_offers, "cards":[{"source_id":4,"name":"換地"},{"source_id":4,"name":"換地"}], "tools":[{"source_id":2,"name":"路障","count":9},{"source_id":5,"name":"機車","count":10}], "points":1000, "ready":ready, "feedback":"", "gift_message":gift}

func _run() -> void:
	var panel: Control = load(PATH).new()
	root.add_child(panel)
	panel.action_requested.connect(func(action: String, params: Dictionary) -> void: actions.append([action, params.duplicate(true)]))
	panel.cancelled.connect(func() -> void: cancels += 1)
	expect(panel.configure(_model()), "valid card shop model accepted")
	expect(panel.is_open(), "ready shop opens")
	expect(panel.source_geometry().held_grid_origin == Vector2(232,298) and panel.source_geometry().canvas == Vector2(640,480), "held grid and logical canvas geometry exact")
	expect(panel.view_model().card_offers[0].source_id == panel.view_model().card_offers[2].source_id, "duplicate offer rows preserve source IDs")
	var before: Dictionary = panel.view_model()
	var detached := _model()
	panel.configure(detached)
	detached.card_offers[0].source_id = 30
	expect(panel.view_model().card_offers[0].source_id == 1, "configured snapshot is detached from caller mutation")
	panel._gui_input(_event(Vector2(14,81), MOUSE_BUTTON_LEFT, true))
	expect(actions.size() == 1 and actions[0][0] == "buy_item" and actions[0][1].offer_index == 0 and actions[0][1].item_kind == "card", "card offer buys on left-down")
	panel._gui_input(_event(Vector2(14,105), MOUSE_BUTTON_LEFT, true))
	expect(actions.size() == 1, "offer hole is inert")
	panel._gui_input(_event(Vector2(14,441), MOUSE_BUTTON_LEFT, true))
	panel._gui_input(_event(Vector2(216,81), MOUSE_BUTTON_LEFT, true))
	expect(actions.size() == 1, "card one-past and outside boundaries are inert")
	panel._gui_input(_event(Vector2(232,298), MOUSE_BUTTON_LEFT, true))
	expect(actions.size() == 1, "strict held boundary is inert")
	panel._gui_input(_event(Vector2(632,299), MOUSE_BUTTON_LEFT, true)); panel._gui_input(_event(Vector2(233,466), MOUSE_BUTTON_LEFT, true))
	expect(actions.size() == 1, "held right and bottom strict boundaries are inert")
	panel._gui_input(_event(Vector2(233,299), MOUSE_BUTTON_LEFT, true))
	expect(actions.size() == 2 and actions[1][0] == "sell_item" and actions[1][1].held_index == 0, "held item sells one unit on left-down")
	panel._gui_input(_event(Vector2(542,13), MOUSE_BUTTON_LEFT, true)); panel._gui_input(_event(Vector2(0,0), MOUSE_BUTTON_LEFT, false))
	expect(panel.view_model().mode == "tools" and panel.view_model().card_offers == before.card_offers, "tab release toggles mode without changing offers")
	panel._gui_input(_event(Vector2(12,80), MOUSE_BUTTON_LEFT, true))
	expect(actions.size() == 3 and actions[2][0] == "buy_item" and actions[2][1].item_kind == "tool", "tool offer maps compact row")
	panel._gui_input(_event(Vector2(556,246), MOUSE_BUTTON_LEFT, true)); panel._gui_input(_event(Vector2(0,0), MOUSE_BUTTON_LEFT, false))
	expect(cancels == 1 and actions.size() == 3, "exit release closes through cancel intent")
	panel.configure(_model())
	panel._gui_input(_event(Vector2(636,286), MOUSE_BUTTON_LEFT, true)); panel._gui_input(_event(Vector2(0,0), MOUSE_BUTTON_LEFT, false))
	expect(cancels == 2 and not panel.is_open(), "inclusive exit edge cancels")
	panel.configure(_model("tools"))
	panel._gui_input(_event(Vector2(0,0), MOUSE_BUTTON_LEFT, false))
	expect(actions.size() == 3, "release-only outside is inert")
	panel._gui_input(_event(Vector2(12,80), MOUSE_BUTTON_LEFT, true))
	expect(actions.size() == 4 and actions[3][0] == "buy_item" and actions[3][1].item_kind == "tool" and actions[3][1].source_id == 1, "tool row maps source ID")
	panel._gui_input(_event(Vector2(313,299), MOUSE_BUTTON_LEFT, true))
	expect(actions.size() == 5 and actions[4][0] == "sell_item" and actions[4][1].source_id == 5, "quantity ten returned vehicle still sells one unit")
	panel._gui_input(_event(Vector2(500,400), MOUSE_BUTTON_RIGHT, false))
	expect(cancels == 3 and not panel.is_open(), "right release closes from anywhere")
	panel._gui_input(_event(Vector2(12,80), MOUSE_BUTTON_LEFT, true))
	expect(actions.size() == 5, "closed panel ignores stale input")
	for edition in ["Game", "MultiverseJourney"]:
		panel.configure(_model("cards", edition))
		panel.scale = Vector2(2, 2)
		expect(panel.source_geometry().canvas == Vector2(640,480) and panel.source_geometry().held_grid_origin == Vector2(232,298), edition + " logical geometry survives 2x viewport scale")
		panel.scale = Vector2.ONE
	panel.configure(_model("cards", "Game", false, "店主送你一件禮物"))
	expect(panel.is_open() and panel.visible and panel.find_child("SourceShopGiftMessage", true, false) != null, "gift pending keeps source panel and message visible")
	var gift_mode: String = panel.view_model().mode
	panel._gui_input(_event(Vector2(542,13), MOUSE_BUTTON_LEFT, true)); panel._gui_input(_event(Vector2(0,0), MOUSE_BUTTON_LEFT, false))
	expect(panel.view_model().mode == gift_mode and actions.size() == 5, "gift pending gates tab and trade actions")
	panel._gui_input(_event(Vector2(14,81), MOUSE_BUTTON_LEFT, true))
	expect(actions.size() == 5, "gift pending ignores buy")
	panel._gui_input(_event(Vector2(556,246), MOUSE_BUTTON_LEFT, true)); panel._gui_input(_event(Vector2(0,0), MOUSE_BUTTON_LEFT, false))
	expect(cancels == 4 and not panel.is_open(), "gift pending exit cancels")
	panel.configure({})
	expect(not panel.is_open() and not panel.source_art_available(), "invalid model fails closed")
	var invalid := _model()
	invalid.card_offers[0].source_id = 31
	expect(not panel.configure(invalid), "stale card source ID fails closed")
	invalid = _model()
	invalid.tools[0].count = 10
	expect(not panel.configure(invalid), "non-vehicle quantity ten fails closed")
	panel.hide()
	await _physical_edges()
	print("Source shop panel checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)

func _physical_edges() -> void:
	for edition in ["Game","MultiverseJourney"]:
		for scale_value in [1,2]:
			var view := SubViewport.new()
			view.size = Vector2i(640,480)*scale_value
			view.handle_input_locally = true
			root.add_child(view)
			view.notify_mouse_entered()
			var panel: Control = load(PATH).new()
			panel.scale = Vector2.ONE*scale_value
			view.add_child(panel)
			var requests: Array = []
			panel.action_requested.connect(func(action: String, params: Dictionary) -> void: requests.append([action,params]))
			for mode in ["cards","tools"]:
				var model := _model(mode,edition)
				model.card_offers = []
				model.cards = []
				model.tool_offers = []
				model.tools = []
				for source_id in range(1,16):
					model.card_offers.append({"source_id":source_id,"name":"card","price":1})
					model.cards.append({"source_id":source_id,"name":"held"})
				for source_id in range(1,9):
					model.tool_offers.append({"source_id":source_id,"name":"tool","price":1})
					model.tools.append({"source_id":source_id,"name":"held","count":1})
				expect(panel.configure(model),"physical input fixture accepts complete rows")
				await _settle()
				var outside: Array = [Vector2(232,299),Vector2(233,298),Vector2(632,299),Vector2(233,466)]
				outside += [Vector2(13,81),Vector2(216,81),Vector2(14,80),Vector2(14,441)] if mode == "cards" else [Vector2(11,80),Vector2(214,80),Vector2(12,79),Vector2(12,464)]
				for logical in outside:
					var count := requests.size()
					_push(view,logical*scale_value,MOUSE_BUTTON_LEFT,true)
					_push(view,logical*scale_value,MOUSE_BUTTON_LEFT,false)
					expect(requests.size()==count,"source outside edge is inert in %s/%s/%dx: %s" % [edition,mode,scale_value,logical])
				var last_point := Vector2(215,440) if mode=="cards" else Vector2(213,463)
				var last_source := 15 if mode=="cards" else 8
				var count := requests.size()
				_push(view,last_point*scale_value,MOUSE_BUTTON_LEFT,true)
				_push(view,last_point*scale_value,MOUSE_BUTTON_LEFT,false)
				expect(requests.size()==count+1 and requests.back()[1].source_id==last_source and requests.back()[1].offer_index==last_source-1,"last source offer maps exactly at physical scale")
				_push(view,Vector2(233,299)*scale_value,MOUSE_BUTTON_LEFT,true)
				_push(view,Vector2(233,299)*scale_value,MOUSE_BUTTON_LEFT,false)
				expect(requests.back()[0]=="sell_item" and requests.back()[1].source_id==1 and requests.back()[1].held_index==0,"strict held interior maps exact source ID")
				_push(view,Vector2(627,98)*scale_value,MOUSE_BUTTON_LEFT,true)
				_push(view,Vector2(1,479)*scale_value,MOUSE_BUTTON_LEFT,false)
				expect(panel.view_model().mode != mode,"inclusive far tab edge releases outside at physical scale")
				_push(view,Vector2(636,286)*scale_value,MOUSE_BUTTON_LEFT,true)
				_push(view,Vector2(1,479)*scale_value,MOUSE_BUTTON_LEFT,false)
				expect(not panel.is_open(),"inclusive far EXIT edge releases outside at physical scale")
			view.queue_free()
			await _settle()

func _push(view: SubViewport, point: Vector2, button: MouseButton, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	view.push_input(motion,true)
	view.push_input(_event(point,button,pressed),true)
