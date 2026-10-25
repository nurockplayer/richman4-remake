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
	# A listed property must render: rebuilding the board from a property offer
	# that omits the top-level building fields used to hide the whole panel and
	# leave the game soft-locked in await_sale with no way to close the session.
	actor = sale_game()
	actor.state.players[0].position = 2
	actor._set_action_options(0)
	expect(actor.choose_action("buy").ok,"property fixture supplies a legal land holding")
	var property_source := int(actor.state.board[2].type_and_idx)
	open_for(actor,0)
	expect(create(actor,"property",property_source,1,Sale.reference_value(actor,"property",property_source)).get("ok",false),"property listing publishes")
	controller.sync(actor,false)
	expect(controller.is_open() and controller.panel.is_open(),"property offer renders the durable board instead of hiding it")
	var property_board: Dictionary = controller.panel.view_model() if is_instance_valid(controller.panel) else {}
	var property_rows: Array = property_board.get("players", [])
	expect(property_rows.size() == 4 and property_rows[0].offers.size() == 1,"property offer carries top-level building identity")
	controller.close_current()
	expect(not controller.is_open() and actor.state.phase == "await_action","property board still closes without soft-lock")
	# A close request the host drops (blocked or pending) must leave the open
	# amount pad intact; only an accepted request tears the child down.
	actor = sale_game()
	open_for(actor,0)
	controller.sync(actor,false)
	select_tool()
	var pending_pad: Control = controller.amount_pad
	expect(pending_pad != null,"amount pad pending before the dropped close")
	calls.clear()
	controller.set("_action_pending",true)
	controller.close_current()
	expect(controller.amount_pad == pending_pad and controller.is_open(),"pending close keeps the amount pad")
	expect(calls.is_empty(),"pending close never reaches the core")
	controller.set("_action_pending",false)
	controller.sync(actor,true)
	controller.close_current()
	expect(controller.amount_pad == pending_pad,"blocked close keeps the amount pad")
	expect(calls.is_empty(),"blocked close never reaches the core")
	controller.sync(actor,false)
	controller.close_current()
	expect(controller.amount_pad == null and not controller.is_open(),"accepted close clears the pad and disposes the controller")
	# A dispatched close the domain rejects must keep the amount pad too.
	open_for(actor,0)
	var rejecting: Control = Controller.new()
	root.add_child(rejecting)
	rejecting.action_requested.connect(func(_method: String, _args: Array) -> void:
		rejecting.apply_action_result({"ok": false, "message": "無法關閉"}))
	rejecting.sync(actor,false)
	rejecting.panel.action_requested.emit("category_selected",{"category":"tool"})
	rejecting.panel.action_requested.emit("item_selected",{"category":"tool","source_id":1,"held_index":-1})
	var rejected_pad: Control = rejecting.amount_pad
	expect(rejected_pad != null,"rejecting fixture opens the asking amount pad")
	rejecting.close_current()
	expect(rejecting.amount_pad == rejected_pad and rejecting.is_open(),"domain-rejected close keeps the amount pad")
	expect(rejecting.panel.view_model().view == "reference","domain-rejected close stays on the asking view")
	rejecting.cancel()
	rejecting.queue_free()
	controller.queue_free()
	await process_frame
	print("Source SALE controller checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
