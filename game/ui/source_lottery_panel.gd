extends Control
class_name RichmanSourceLotteryPanel

## Source-shaped S29/S30 lottery presenter.
##
## The host supplies a detached snapshot and owns all financial/state changes.
## This control only presents the snapshot and emits an explicit ticket/return
## intent; it never mutates the supplied dictionary or performs payment/RNG.

signal ticket_selected(number: int)
signal cancelled
signal continued

const REFERENCE_SIZE := Vector2(640.0, 480.0)
const GRID_ORIGIN := Vector2(30.0, 271.0)
const CELL_SIZE := Vector2(64.0, 48.0)
const SOLD_ORIGIN := Vector2(31.0, 272.0)
const SOLD_SIZE := Vector2(62.0, 46.0)
const TICKET_COUNT := 36
const TICKET_PRICE := 1000
const VALID_EDITIONS := ["Game", "MultiverseJourney"]

const SOURCE_LOGICAL_SIZES := {
	"purchase_background": Vector2(640.0, 480.0),
	"dealer": Vector2(358.0, 298.0),
	"speech": Vector2(237.0, 192.0),
	"amount": Vector2(172.0, 28.0),
	"draw_background": Vector2(640.0, 480.0),
	"heart": Vector2(187.0, 140.0),
	"burst": Vector2(233.0, 192.0),
	"red_burst": Vector2(295.0, 262.0),
}

var _model: Dictionary = {}
var _visual_accessor: Variant = null
var _kind := ""
var _edition := ""
var _model_valid := false
var _is_open := false
var _closed := false
var _pressed_ticket := -1
var _selected_number := 0
var _continued_emitted := false
var _source_art_available := false
var _source_frames: Dictionary = {}
var _presentation_elapsed := 0.0
var _draw_stage := 0
var _animation_nodes: Dictionary = {}


func _init() -> void:
	name = "SourceLotteryPanel"
	size = REFERENCE_SIZE
	custom_minimum_size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Replace the detached purchase/draw snapshot.  The presenter does not write
## to the caller's arrays or dictionaries.
func set_view_model(model: Dictionary) -> bool:
	_model = model.duplicate(true)
	_kind = _canonical_kind(_model.get("kind", null))
	_edition = _canonical_edition(_model.get("edition", null))
	_model_valid = _validate_model(_model)
	_is_open = _model_valid
	_closed = false
	_pressed_ticket = -1
	_selected_number = 0
	_continued_emitted = false
	_source_frames.clear()
	_presentation_elapsed = 0.0
	_draw_stage = 0
	_render()
	show()
	return _model_valid


## Install a caller-owned original-art resolver.  A dictionary, Callable, or
## object exposing ui()/texture() is accepted; animation providers may expose
## animation_frame()/frame()/animation().
func set_visuals(accessor: Variant) -> void:
	if _visual_accessor == accessor: return
	if accessor is Dictionary:
		_visual_accessor = (accessor as Dictionary).duplicate(true)
	else:
		_visual_accessor = accessor
	if not _model.is_empty():
		_render()


func set_visual_accessor(accessor: Variant) -> void:
	set_visuals(accessor)


func view_model() -> Dictionary:
	return _model.duplicate(true)


func model() -> Dictionary:
	return view_model()


func kind() -> String:
	return _kind


func is_model_valid() -> bool:
	return _model_valid


func is_open() -> bool:
	return _is_open and _model_valid and visible


func selected_number() -> int:
	return _selected_number


func source_art_available() -> bool:
	return _source_art_available


func has_source_art() -> bool:
	return source_art_available()


func source_frames() -> Dictionary:
	return _source_frames.duplicate(true)


func source_art_status() -> Dictionary:
	return {
		"available": _source_art_available,
		"kind": _kind,
		"edition": _edition,
		"frames": source_frames(),
	}


## Contract for the optional decoded FLIC provider.  The provider returns one
## RGBA Texture2D for a requested frame through
## animation_frame(edition, archive, resource, frame_index).  Palette index 0
## is already transparent for 14/17 and opaque for 16; the presenter never
## infers transparency from RGB values.
func source_animation_contract() -> Dictionary:
	return {
		14: {"origin": Vector2(8.0, 8.0), "size": Vector2(213.0, 68.0), "flags": 5, "interval_ms": 100, "loop": true, "index_zero_transparent": true},
		16: {"origin": Vector2(183.0, 75.0), "size": Vector2(275.0, 270.0), "flags": 8, "interval_ms": 50, "loop": false, "index_zero_transparent": false},
		17: {"origin": Vector2(205.0, 0.0), "size": Vector2(280.0, 480.0), "flags": 1, "interval_ms": 50, "loop": false, "index_zero_transparent": true},
	}


func get_source_animation_contract() -> Dictionary:
	return source_animation_contract()


func source_geometry() -> Dictionary:
	return {
		"canvas": REFERENCE_SIZE,
		"kind": _kind,
		"edition": _edition,
		"grid_origin": GRID_ORIGIN,
		"cell_size": CELL_SIZE,
		"ticket_count": TICKET_COUNT,
		"sold_transform": {"origin": SOLD_ORIGIN, "cell_size": SOLD_SIZE},
		"dealer_origin": Vector2(210.0, -5.0),
		"draw_animation_origins": {
			"drum": Vector2(183.0, 75.0),
			"red_ball": Vector2(205.0, 0.0),
		},
	}


func get_source_geometry() -> Dictionary:
	return source_geometry()


func source_hitboxes() -> Dictionary:
	return {
		"grid": Rect2(GRID_ORIGIN, Vector2(CELL_SIZE.x * 9.0, CELL_SIZE.y * 4.0)),
		"return": Rect2(Vector2.ZERO, REFERENCE_SIZE),
	}


func get_source_hitboxes() -> Dictionary:
	return source_hitboxes()


func ticket_at(point: Vector2) -> int:
	var local := point - GRID_ORIGIN
	if local.x < 0.0 or local.y < 0.0:
		return 0
	var column := int(floor(local.x / CELL_SIZE.x))
	var row := int(floor(local.y / CELL_SIZE.y))
	if column < 0 or column >= 9 or row < 0 or row >= 4:
		return 0
	var number := row * 9 + column + 1
	return number if number >= 1 and number <= TICKET_COUNT else 0


func is_ticket_sold(number: int) -> bool:
	if number < 1 or number > TICKET_COUNT:
		return false
	var tickets: Array = _model.get("tickets", [])
	if tickets.size() != TICKET_COUNT:
		return false
	return _slot_sold(tickets[number - 1])


func can_select_ticket(number: int) -> bool:
	if not _model_valid or _kind != "purchase" or not _is_open:
		return false
	if number < 1 or number > TICKET_COUNT or is_ticket_sold(number):
		return false
	var cash_value: Variant = _model.get("cash", -1)
	return _numeric_int(cash_value, TICKET_PRICE)


func continue_draw() -> bool:
	if not _model_valid or _kind != "draw" or not _is_open or _continued_emitted:
		return false
	_continued_emitted = true
	_is_open = false
	_closed = true
	hide()
	continued.emit()
	return true


func close_lottery() -> bool:
	if not _is_open or _closed:
		return false
	_closed = true
	_is_open = false
	_pressed_ticket = -1
	hide()
	cancelled.emit()
	return true


func close() -> bool:
	return close_lottery()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	accept_event()
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		if not mouse.pressed:
			close_lottery()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT or not _is_open:
		return
	if _kind == "purchase":
		var number := ticket_at(mouse.position)
		if mouse.pressed:
			_pressed_ticket = number
			# Source selection is immediate; a valid number is consumed on the
			# first left press, and there is exactly one ticket per encounter.
			if number > 0 and can_select_ticket(number):
				_select_ticket(number)
		else:
			_pressed_ticket = -1
	elif not mouse.pressed:
		continue_draw()


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree() or not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT and not mouse.pressed:
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		close_lottery()


func _select_ticket(number: int) -> bool:
	if not can_select_ticket(number):
		return false
	_selected_number = number
	_is_open = false
	_closed = true
	_add_selected_overlay(number)
	if has_node("LotteryPrompt"): get_node("LotteryPrompt").text = "祝你中大獎！"
	ticket_selected.emit(number)
	return true


func _render() -> void:
	for child in get_children():
		child.free()
	_source_frames.clear()
	_animation_nodes.clear()
	_source_art_available = false
	if not _model_valid:
		size = REFERENCE_SIZE
		custom_minimum_size = REFERENCE_SIZE
		_add_fallback_surface("資料格式無法顯示")
		return
	if _kind == "purchase":
		_render_purchase()
	else:
		_render_draw()
		_draw_stage = -1
		_process(0.0)


func _render_purchase() -> void:
	_add_source_or_fallback("LotteryPurchaseBackground", 12, 0, Vector2.ZERO, REFERENCE_SIZE, "purchase_background")
	_add_source_or_fallback("LotteryDealer", 12, 1, Vector2(210, -5), SOURCE_LOGICAL_SIZES.dealer, "dealer")
	_add_source_or_fallback("LotterySpeech", 12, 8, Vector2(360, 20), SOURCE_LOGICAL_SIZES.speech, "speech")
	_add_animation_or_placeholder("LotteryPoolAnimation", 14, Vector2(8, 8), Vector2(213, 68), 5)
	_add_source_or_fallback("LotteryAmountPlaque", 12, 9, Vector2(28, 27), SOURCE_LOGICAL_SIZES.amount, "amount")
	_add_dynamic_label("LotteryJackpot", "$" + _numeric_display(_model.jackpot), Rect2(28, 27, 172, 28), 18, Color("#fff2b4"))
	var amount_label := get_node("LotteryJackpot") as Label
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if _source_currency(int(_model.jackpot)): amount_label.hide()
	var prompt := "選一個幸運號碼！\n每張彩券 $1,000"
	if int(_model.cash) < TICKET_PRICE: prompt = "現金不足\n下次再來吧！"
	elif (_model.tickets as Array).count(0) == 0: prompt = "彩券已售完\n下次再來吧！"
	_add_dynamic_label("LotteryPrompt", prompt, Rect2(400, 54, 180, 105), 20, Color("#101010"))
	for number in range(1, TICKET_COUNT + 1):
		var cell := number - 1
		var target := Button.new()
		target.name = "LotteryTicket%02d" % number
		target.position = GRID_ORIGIN + Vector2((cell % 9) * 64, int(cell / 9) * 48)
		target.size = CELL_SIZE
		target.focus_mode = Control.FOCUS_NONE
		target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_set_button_transparent(target)
		target.gui_input.connect(_on_ticket_gui_input.bind(number))
		add_child(target)
		if is_ticket_sold(number): _add_sold_overlay(number, cell)
	if _selected_number > 0: _add_selected_overlay(_selected_number)


func _render_draw() -> void:
	_add_source_or_fallback("LotteryDrawBackground", 15, 0, Vector2.ZERO, REFERENCE_SIZE, "draw_background")
	_source_sprite("LotteryHostRight", 15, 1, Vector2(472,66))
	_source_sprite("LotteryHostLeft", 15, 3, Vector2(7,66))
	_add_dynamic_label("LotteryPoolTitle", "累積獎金", Rect2(12,180,130,26), 20, Color("#b1354f"))
	_add_dynamic_label("LotteryPool", "$" + _numeric_display(_model.jackpot), Rect2(12,215,130,26), 20, Color.RED)
	_add_animation_or_placeholder("LotteryDrumAnimation", 16, Vector2(183,75), Vector2(275,270), 8)
	_add_animation_or_placeholder("LotteryRedBallAnimation", 17, Vector2(205,0), Vector2(280,480), 1)
	if has_node("LotteryRedBallAnimation"): get_node("LotteryRedBallAnimation").hide()
	# Keep one staged outcome, not three simultaneous speech overlays.
	_source_sprite("LotteryOutcomeBubble", 15, 24, Vector2(320,200))
	if has_node("LotteryOutcomeBubble"): get_node("LotteryOutcomeBubble").hide()
	_add_dynamic_label("LotteryWinner", "無人中獎" if int(_model.get("winner_id", -1)) < 0 else _player_name(int(_model.winner_id)), Rect2(205,155,230,54), 26, Color("#e02020"))
	get_node("LotteryWinner").hide()
	_source_sprite("LotteryTens", 15, 37 + int(int(_model.number) / 10), Vector2(286,405))
	_source_sprite("LotteryUnits", 15, 37 + int(_model.number) % 10, Vector2(358,405))
	for node_name in ["LotteryTens","LotteryUnits"]:
		if has_node(node_name): get_node(node_name).hide()
	_add_dynamic_label("LotteryDrawNumber", "%02d" % int(_model.number), Rect2(250,370,140,70), 48, Color.WHITE)
	get_node("LotteryDrawNumber").hide()
	_render_ticket_list()


func _render_ticket_list() -> void:
	var list := Control.new()
	list.name = "LotteryParticipants"
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(list)
	var entries: Array = _model.players.filter(func(player: Variant) -> bool: return player is Dictionary and bool(player.get("alive", true)))
	var origins := [Vector2(16,340),Vector2(16,410),Vector2(328,340),Vector2(328,410)]
	for row in range(mini(4, entries.size())):
		var entry: Dictionary = entries[row]
		var origin: Vector2 = origins[row]
		var shade := ColorRect.new()
		shade.position = origin
		shade.size = Vector2(296,60)
		shade.color = Color(0,0,0,0.35)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.add_child(shade)
		var character_id := int(entry.get("character_id", -1))
		if character_id >= 0 and character_id < 12:
			var icon := _source_sprite("LotteryPlayer%d" % row,15,25+character_id,origin+Vector2(20,30))
			if icon != null: icon.reparent(list)
		var numbers: Array = []
		for slot in range(36):
			if int(_model.tickets[slot]) == int(entry.id)+1: numbers.append(slot+1)
		for index in range(mini(12,numbers.size())):
			var y := 30 if numbers.size() <= 6 else (15 if index < 6 else 45)
			var anchor := origin + Vector2(54+(index%6)*40,y)
			for digit in range(2):
				var value := int(int(numbers[index])/10) if digit == 0 else int(numbers[index])%10
				var sprite := _source_sprite("LotteryTicketRow%d_%d_%d" % [row,index,digit],13,value,anchor+Vector2(digit*16,0))
				if sprite != null: sprite.reparent(list)


func _source_sprite(node_name: String, resource: int, chunk: int, anchor: Vector2) -> TextureRect:
	var texture: Variant = _resolve_chunk_visual(resource,chunk,"%s.Panel%d.chunk%d" % [_edition,resource,chunk])
	if not texture is Texture2D: return null
	var logical := {"width":texture.get_width(),"height":texture.get_height(),"anchor_x":0,"anchor_y":0}
	if _visual_accessor is Object and _visual_accessor.has_method("ui"):
		var record: Dictionary = _visual_accessor.ui(_edition,"Panel",resource,chunk)
		logical = record.get("logical",logical)
	var sprite := _sprite(texture,Vector2(logical.get("width",texture.get_width()),logical.get("height",texture.get_height())))
	sprite.name = node_name
	sprite.position = anchor - Vector2(logical.get("anchor_x",0),logical.get("anchor_y",0))
	add_child(sprite)
	return sprite


func _source_currency(amount: int) -> bool:
	var digit: Variant = _resolve_chunk_visual(13,0,"%s.Panel13.chunk0" % _edition)
	if not digit is Texture2D or digit.get_width() < 7: return false
	var text := "$" + _numeric_display(amount)
	# Large remake values exceed the source plaque; keep the complete label.
	if text.length()*18 - text.count(",")*12 > 172: return false
	var x := 184
	for index in range(text.length()-1,-1,-1):
		var character := text[index]
		var chunk := int(character) if character in "0123456789" else (10 if character == "," else 11)
		if character == ",": x += 6
		_source_sprite("LotteryCurrency%d" % index,13,chunk,Vector2(x,41))
		x -= 12 if character == "," else 18
	return true


func _process(delta: float) -> void:
	if not visible or not _model_valid: return
	_presentation_elapsed += delta
	if _kind == "purchase":
		_update_animation(14,int(_presentation_elapsed/0.1)%5)
		return
	var stage := 0 if _presentation_elapsed < 2.1 else (1 if _presentation_elapsed < 3.95 else 2)
	if stage != _draw_stage:
		_draw_stage = stage
		if has_node("LotteryDrumAnimation"): get_node("LotteryDrumAnimation").visible = stage == 0
		if has_node("LotteryRedBallAnimation"): get_node("LotteryRedBallAnimation").visible = stage >= 1
		if has_node("LotteryParticipants"): get_node("LotteryParticipants").visible = stage == 0
		if has_node("LotteryOutcomeBubble"): get_node("LotteryOutcomeBubble").visible = stage == 2
		get_node("LotteryWinner").visible = stage == 2
		if stage == 2 and int(_model.get("winner_id", -1)) >= 0:
			for host in ["LotteryHostLeft", "LotteryHostRight"]:
				if has_node(host): get_node(host).free()
			_source_sprite("LotteryHostRight",15,5,Vector2(505,66))
			_source_sprite("LotteryHostLeft",15,6,Vector2.ZERO)
			# The source raised sign moves its text centers to (91,19)/(91,56).
			get_node("LotteryPoolTitle").position = Vector2(26,6)
			get_node("LotteryPool").position = Vector2(26,43)
			move_child(get_node("LotteryPoolTitle"),get_child_count()-1)
			move_child(get_node("LotteryPool"),get_child_count()-1)
		for node_name in ["LotteryTens","LotteryUnits"]:
			if has_node(node_name): get_node(node_name).visible = stage == 2
		get_node("LotteryDrawNumber").visible = stage == 2 and not has_node("LotteryTens")
	_update_animation(16,mini(41,int(_presentation_elapsed/0.05)))
	_update_animation(17,clampi(int((_presentation_elapsed-2.1)/0.05),0,36))


func _update_animation(resource: int, frame: int) -> void:
	if not _animation_nodes.has(resource): return
	var node: TextureRect = _animation_nodes[resource]
	if not is_instance_valid(node) or int(node.get_meta("frame",-1)) == frame: return
	var texture: Variant = _resolve_animation_frame(resource,frame,"%s.Panel%d.frame%d" % [_edition,resource,frame])
	if not texture is Texture2D: return
	node.texture = texture
	node.set_meta("frame",frame)
	_source_frames["animation_%d" % resource]["frame"] = frame


func _on_ticket_gui_input(event: InputEvent, number: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT and not mouse.pressed:
		close_lottery()
		return
	if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		_select_ticket(number)


func _add_sold_overlay(number: int, cell: int) -> void:
	var overlay := ColorRect.new()
	overlay.name = "LotterySold%02d" % number
	overlay.position = SOLD_ORIGIN + Vector2(float(cell % 9) * CELL_SIZE.x, float(cell / 9) * CELL_SIZE.y)
	overlay.size = SOLD_SIZE
	overlay.color = Color(0.12, 0.12, 0.12, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	move_child(overlay, 1)


func _add_selected_overlay(number: int) -> void:
	var cell := number - 1
	var center := GRID_ORIGIN + Vector2((cell % 9) * 64 + 32, int(cell / 9) * 48 + 24)
	_source_sprite("LotterySelected%02d" % number,12,7,center)

func purchase_confirmation_seconds() -> float:
	return 0.5 if _selected_number > 0 else 0.0


func _add_source_or_fallback(node_name: String, resource: int, chunk: int, origin: Vector2, logical_size: Vector2, role: String) -> void:
	var visual: Variant = _resolve_chunk_visual(resource, chunk, "%s.Panel%d.chunk%d" % [_edition, resource, chunk])
	if visual is Texture2D:
		var item := _sprite(visual, logical_size)
		item.name = node_name
		item.position = origin
		add_child(item)
		_source_frames[role] = {"resource": resource, "chunk": chunk, "origin": origin, "size": logical_size}
		_source_art_available = _source_art_available or (role in ["purchase_background", "draw_background"])
		return
	if role in ["purchase_background", "draw_background"]:
		var fallback := ColorRect.new()
		fallback.name = node_name + "Fallback"
		fallback.position = origin
		fallback.size = logical_size
		fallback.color = Color("#173e49") if _kind == "purchase" else Color("#293b65")
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fallback)


func _add_animation_or_placeholder(node_name: String, resource: int, origin: Vector2, logical_size: Vector2, flags: int) -> void:
	var visual: Variant = _resolve_animation_frame(resource, 0, "%s.Panel%d.frame0" % [_edition, resource])
	if visual is Texture2D:
		var item := _sprite(visual, logical_size)
		item.name = node_name
		item.position = origin
		item.set_meta("source_resource", resource)
		item.set_meta("source_flags", flags)
		item.set_meta("frame", 0)
		_animation_nodes[resource] = item
		add_child(item)
		_source_frames["animation_%d" % resource] = {"resource": resource, "frame": 0, "origin": origin, "size": logical_size, "flags": flags, "available": true}
		return
	# Keep a named inert boundary when animation data is unavailable, so the
	# presenter never fakes a source frame from a solid RGB key.
	var placeholder := Control.new()
	placeholder.name = node_name + "Unavailable"
	placeholder.position = origin
	placeholder.size = logical_size
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placeholder.set_meta("source_resource", resource)
	placeholder.set_meta("source_flags", flags)
	add_child(placeholder)
	_source_frames["animation_%d" % resource] = {"resource": resource, "frame": 0, "origin": origin, "size": logical_size, "flags": flags, "available": false}


func _add_fallback_surface(message: String) -> void:
	var panel := Panel.new()
	panel.name = "LotteryUnavailable"
	panel.size = REFERENCE_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#203a3a")
	style.border_color = Color("#b9bd7d")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_add_dynamic_label("LotteryUnavailableMessage", message, Rect2(24, 24, 592, 34), 18, Color("#ffb3a4"))


func _add_dynamic_label(node_name: String, text_value: String, rect: Rect2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.name = node_name
	label.position = rect.position
	label.size = rect.size
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _sprite(texture: Texture2D, logical_size: Vector2) -> TextureRect:
	var item := TextureRect.new()
	item.texture = texture
	item.size = logical_size
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.stretch_mode = TextureRect.STRETCH_SCALE
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item


func _set_button_transparent(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, empty)


func _resolve_chunk_visual(resource: int, chunk: int, key: String) -> Variant:
	if _visual_accessor == null or _edition.is_empty():
		return null
	if _visual_accessor is Dictionary:
		var visuals: Dictionary = _visual_accessor
		for candidate in [key, "%s.Panel%d.%d" % [_edition, resource, chunk], "%s.Panel%d.chunk%d" % [_edition, resource, chunk], "%s.Panel%d/chunk%d" % [_edition, resource, chunk]]:
			var value: Variant = _resolve_dictionary_visual(visuals, candidate)
			if value != null:
				return value
		return null
	if _visual_accessor is Callable:
		return _visual_accessor.call(key)
	if _visual_accessor is Object and _visual_accessor.has_method("ui") and _visual_accessor.has_method("texture"):
		var frame: Variant = _visual_accessor.call("ui", _edition, "Panel", resource, chunk)
		if frame is Dictionary:
			var texture: Variant = _visual_accessor.call("texture", frame)
			if texture is Texture2D:
				return texture
	for method in ["texture", "get_texture", "visual", "resolve"]:
		if _visual_accessor is Object and _visual_accessor.has_method(method):
			var result: Variant = _visual_accessor.call(method, key)
			if result != null:
				return result
	return null


func _resolve_animation_frame(resource: int, frame_index: int, key: String) -> Variant:
	if _visual_accessor == null or _edition.is_empty():
		return null
	if _visual_accessor is Dictionary:
		var visuals: Dictionary = _visual_accessor
		for candidate in [key, "%s.Panel%d.frame%d" % [_edition, resource, frame_index], "%s.Panel%d.animation%d" % [_edition, resource, frame_index]]:
			var value: Variant = _resolve_dictionary_visual(visuals, candidate)
			if value != null:
				return value
		return null
	if _visual_accessor is Object:
		for method in ["animation_frame", "frame", "animation"]:
			if not _visual_accessor.has_method(method):
				continue
			var result: Variant
			if method == "animation_frame":
				result = _visual_accessor.call(method, _edition, "Panel", resource, frame_index)
			else:
				result = _visual_accessor.call(method, "%s.Panel%d.frame%d" % [_edition, resource, frame_index])
			if result is Texture2D:
				return result
	return _resolve_chunk_visual(resource, frame_index, key)


func _resolve_dictionary_visual(visuals: Dictionary, key: String) -> Variant:
	var aliases := [key, key.to_lower(), key.to_upper(), key.replace(".", "/"), key.replace(".", "_")]
	if key.begins_with("MultiverseJourney"):
		aliases.append(key.replace("MultiverseJourney", "MJ"))
	for alias in aliases:
		if visuals.has(alias):
			return visuals.get(alias)
	return null


func _canonical_kind(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var normalized := str(value).to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	if normalized in ["purchase", "buy", "ticket", "lottery_purchase"]:
		return "purchase"
	if normalized in ["draw", "result", "lottery_draw"]:
		return "draw"
	return ""


func _canonical_edition(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var normalized := str(value).to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	if normalized in ["game", "g"]:
		return "Game"
	if normalized in ["multiversejourney", "multiverse_journey", "mj", "journey"]:
		return "MultiverseJourney"
	return ""


func _validate_model(model: Dictionary) -> bool:
	if _kind not in ["purchase", "draw"] or _edition not in VALID_EDITIONS:
		return false
	var tickets_value: Variant = model.get("tickets", null)
	if typeof(tickets_value) != TYPE_ARRAY or (tickets_value as Array).size() != TICKET_COUNT:
		return false
	for slot in tickets_value as Array:
		if not _valid_ticket_slot(slot):
			return false
	if not _valid_nonnegative_integer(model.get("jackpot", null)):
		return false
	if typeof(model.get("players", null)) != TYPE_ARRAY or model.players.is_empty() or model.players.size() > 4:
		return false
	var ids: Array = []
	for player in model.players:
		if not player is Dictionary or not _valid_integer_in_range(player.get("id"),0,3) or not player.get("name") is String or player.name.is_empty(): return false
		if ids.has(int(player.id)): return false
		ids.append(int(player.id))
		if player.has("character_id") and not _valid_integer_in_range(player.character_id,0,11): return false
		if player.has("alive") and not player.alive is bool: return false
	if _kind == "purchase":
		return _valid_nonnegative_integer(model.get("cash", null)) and _valid_nonnegative_integer(model.get("player_id", null))
	if not _valid_integer_in_range(model.get("number", null), 1, TICKET_COUNT):
		return false
	if not _valid_nonnegative_integer(model.get("amount", null)):
		return false
	var winner: Variant = model.get("winner_id", null)
	return winner == null or _valid_integer_in_range(winner, -1, 2147483647)


func _valid_ticket_slot(value: Variant) -> bool:
	return _valid_integer_in_range(value,0,4)


func _valid_nonnegative_integer(value: Variant) -> bool:
	return _valid_integer_in_range(value, 0, 1000000000000)


func _valid_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_BOOL or typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and floor(number) == number and number >= float(minimum) and number <= float(maximum)


func _numeric_int(value: Variant, minimum: int) -> bool:
	return _valid_integer_in_range(value, minimum, 1000000000000)


func _slot_sold(value: Variant) -> bool:
	if value == null:
		return false
	if typeof(value) in [TYPE_INT, TYPE_FLOAT] and typeof(value) != TYPE_BOOL:
		return float(value) > 0.0
	return true


func _numeric_display(value: Variant) -> String:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or typeof(value) == TYPE_BOOL:
		return "—"
	var number := float(value)
	if not is_finite(number) or floor(number) != number:
		return "—"
	return _group_integer(int(number))


func _group_integer(value: int) -> String:
	var text := str(value)
	var sign := ""
	if text.begins_with("-"):
		sign = "-"
		text = text.substr(1)
	var grouped := ""
	while text.length() > 3:
		grouped = "," + text.right(3) + grouped
		text = text.left(text.length() - 3)
	return sign + text + grouped


func _player_name(player_id: int) -> String:
	var players: Array = _model.get("players", [])
	for player in players:
		if not player is Dictionary:
			continue
		var candidate: Variant = player.get("id", player.get("player_id", null))
		if _valid_integer_in_range(candidate, -2147483648, 2147483647) and int(candidate) == player_id:
			var name_value: Variant = player.get("name", player.get("display_name", ""))
			if typeof(name_value) == TYPE_STRING and not str(name_value).is_empty():
				return str(name_value)
	return "玩家 %d" % player_id if player_id >= 0 else "—"


