extends "res://tests/source_sale_rules.gd"
const Controller = preload("res://game/ui/source_sale_controller.gd")
var controller: Control
var actor: Object
var calls: Array = []

func _initialize() -> void:
	call_deferred("controller_checks")

func intent(action: String, params: Dictionary = {}) -> void:
	controller.panel.action_requested.emit(action,params)

func select_tool() -> void:
	intent("category_selected",{"category":"tool"})
	intent("item_selected",{"category":"tool","source_id":1,"held_index":-1})

func controller_checks() -> void:
	actor = sale_game()
	open_for(actor,0)
	controller = Controller.new()
	root.add_child(controller)
	controller.action_requested.connect(func(method: String, args: Array) -> void:
		calls.append(method)
		var result: Dictionary = actor.callv(method,args)
		controller.apply_action_result(result))
	controller.sync(actor,false)
	expect(controller.is_open() and controller.panel.is_open(),"durable session renders board")
	select_tool()
	expect(controller.amount_pad != null and controller.panel.view_model().view == "reference","tool opens asking amount child")
	var stale: Control = controller.amount_pad
	stale.cancelled.emit()
	expect(controller.amount_pad == null and controller.panel.view_model().view == "picker","cancel returns to picker")
	var before: String = actor.to_json()
	stale.confirmed.emit(1)
	expect(actor.to_json() == before and calls.is_empty(),"detached amount callback is ignored")
	select_tool()
	controller.amount_pad.confirmed.emit(1)
	expect(actor.sale_snapshot().players[0].offers.size() == 1 and controller.panel.view_model().view == "board","asking confirmation publishes through public core")
	var offer: Dictionary = actor.sale_snapshot().players[0].offers[0]
	intent("offer_selected",{"offer_id":offer.offer_id,"revision":offer.revision})
	intent("detail_primary",{"offer_id":offer.offer_id,"revision":offer.revision})
	expect(actor.sale_snapshot().players[0].offers.is_empty() and controller.confirmation == null,"own primary cancels immediately")
	select_tool()
	controller.amount_pad.confirmed.emit(1)
	offer = actor.sale_snapshot().players[0].offers[0]
	controller.close_current()
	expect(not controller.is_open() and actor.state.phase == "await_action","public close disposes controller and returns turn")
	open_for(actor,1)
	controller.sync(actor,false)
	intent("offer_selected",{"offer_id":offer.offer_id,"revision":offer.revision})
	intent("detail_primary",{"offer_id":offer.offer_id,"revision":offer.revision})
	expect(controller.confirmation != null,"other primary requires source confirmation")
	before = actor.to_json()
	controller.confirmation.decided.emit(false)
	expect(actor.to_json() == before and controller.panel.view_model().view == "detail","NO leaves detail and listing intact")
	intent("detail_primary",{"offer_id":offer.offer_id,"revision":offer.revision})
	controller.confirmation.decided.emit(true)
	expect(actor.sale_snapshot().players[0].offers.is_empty() and controller.panel.view_model().view == "board","YES settles public offer and returns board")
	select_tool()
	stale = controller.amount_pad
	controller.sync(actor,true)
	before = actor.to_json()
	stale.confirmed.emit(1)
	expect(actor.to_json() == before and not controller.visible,"blocked presentation rejects child callback")
	controller.sync(actor,false)
	var restored: Object = Game.from_dict(JSON.parse_string(actor.to_json()))
	expect(restored != null,"active durable session loads")
	actor = restored
	controller.sync(actor,false)
	expect(controller.amount_pad == null and controller.panel.view_model().view == "board","new owner resumes durable board without stale transient picker")
	before = actor.to_json()
	stale.confirmed.emit(1)
	expect(actor.to_json() == before,"replaced owner rejects former child callback")
	controller.close_current()
	controller.queue_free()
	await process_frame
	print("Source SALE controller checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
