extends Control

## Source raster placement; simulation remains in the deterministic core.
const SIZE := Vector2(640,480)
var _visuals: Variant
var _view: Dictionary = {}
var _phase := "intro"
var _ending_seconds := 0.0
var _frames: Dictionary = {}
var _play: Control
var _overlay: Control
var _target: CanvasItem

func _init() -> void:
	name="SourceMinigameArt"
	size=SIZE
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_play=Control.new()
	_play.size=Vector2(640,388)
	_play.clip_contents=true
	_play.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_play.draw.connect(_draw_play)
	add_child(_play)
	_overlay=Control.new()
	_overlay.size=SIZE
	_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

func set_visuals(value: Variant) -> void:
	if _visuals==value: return
	_visuals=value
	_frames.clear()
	refresh()

func set_view_model(value: Dictionary, phase: String, ending_seconds: float=0.0) -> void:
	if str(value.get("edition","Game"))!=str(_view.get("edition","Game")): _frames.clear()
	_view=value
	_phase=phase
	_ending_seconds=ending_seconds
	refresh()

func refresh() -> void:
	queue_redraw()
	_play.queue_redraw()
	_overlay.queue_redraw()

func available() -> bool:
	return _frame("Panel",_background(),0).get("texture") is Texture2D

func source_frames() -> Dictionary:
	var output: Dictionary={}
	for key in _frames:
		var record: Dictionary=_frames[key].get("record",{})
		output[key]={"path":record.get("path",""),"sha256":record.get("sha256",""),"available":_frames[key].get("texture") is Texture2D}
	return output

func ending_duration() -> float:
	var model: Dictionary=_view.get("model",{})
	if bool(_view.get("shortcut",false)): return 0.0
	if str(_view.get("kind",""))=="catching" and bool(model.get("bomb",false)):
		var effect := _effect("catching_bomb")
		var entry := _resource(str(effect.get("archive","")),int(effect.get("resource_index",-1)))
		return entry.get("chunks",{}).size()*float(entry.get("caller",{}).get("delay_ms",50))/1000.0
	if str(_view.get("kind",""))=="penguin":
		if str(model.get("finish_reason",""))=="bomb": return 1.5
		if str(model.get("finish_reason",""))=="timeout":
			var score := int(_view.get("reward",0))
			return 3.2 if score>55 else (2.4 if score<40 else 1.5)
	return 0.0

func _background() -> int:
	return {"penguin":80,"balloon":91,"catching":92}.get(str(_view.get("kind","")),91)

func _draw() -> void:
	_target=self
	_sprite("Panel",_background(),0,Vector2.ZERO)
	if not available(): return
	var model: Dictionary=_view.get("model",{})
	var remaining := maxi(0,int(model.get("deadline_ticks",150))-int(model.get("tick",0)))
	if str(_view.get("kind",""))=="catching": remaining=int(remaining/2)
	var digits := "%03d0" % remaining
	for i in range(4): _sprite("Panel",79,int(digits[i]),Vector2([49,69,94,114][i],421))
	var score := int(_view.get("reward",model.get("score",0)))
	if str(_view.get("kind",""))=="balloon":
		_number(score,4,529)
	else:
		var counts: Array=model.get("counts",[0,0,0,0])
		var order: Array=[3,1,2,0] if str(_view.get("kind",""))=="penguin" else [0,1,2,3]
		for i in range(4): _number(int(counts[order[i]]),2,[185,276,367,458][i])
		_number(score,3,549)

func _draw_play() -> void:
	_target=_play
	var model: Dictionary=_view.get("model",{})
	match str(_view.get("kind","")):
		"balloon":
			for balloon in model.get("balloons",[]):
				if int(balloon.get("phase",0))==0: continue
				_sprite("Panel",91,13 if int(balloon.get("phase",0))==2 else int(balloon.get("id",0))+1,Vector2(float(balloon.get("x",0)),float(balloon.get("y",0))))
		"penguin": _draw_penguin(model)
		"catching": _draw_catching(model)

func _draw_penguin(model: Dictionary) -> void:
	var anchors: Array=model.get("cell_anchors",[])
	var grid: Array=model.get("items_grid",[])
	if _phase=="intro":
		for index in range(mini(anchors.size(),grid.size())):
			if int(grid[index])>0: _sprite("Panel",80,int(grid[index])+3,Vector2(anchors[index]))
	for found in model.get("items_found",[]):
		var cell: Vector2i=found.get("cell",Vector2i.ZERO)
		var point := _penguin_anchor(cell,anchors)
		_sprite("Panel",80,9,point)
		var age := int(found.get("age",0))
		if _phase=="ending": age+=int(_ending_seconds*10)
		if int(found.get("item",0))>0 and age<6: _sprite("Panel",85+int(found.item),age,point)
	var position: Vector2=model.get("penguin_position",Vector2.ZERO)
	var direction := int(model.get("movement_direction",0))
	var motion := str(model.get("movement_state","idle"))
	if _phase=="ending":
		var frame := int(_ending_seconds*10)
		if str(model.get("finish_reason",""))=="bomb": _sprite("Panel",80,1 if frame<3 else 2,position)
		elif int(_view.get("reward",0))>55: _sprite("Panel",84,frame%8,position)
		elif int(_view.get("reward",0))<40: _sprite("Panel",85,frame%6,position)
		else: _sprite("Panel",80,1,position)
	elif motion=="walking": _sprite("Panel",82,direction*4+int(model.get("movement_frame",0))%4,position)
	elif motion=="digging":
		if int(model.get("dig_frame",0))>=2: _sprite("Panel",80,9,position)
		_sprite("Panel",83,direction*4+int(model.get("dig_frame",0))%4,position)
	else: _sprite("Panel",80,1,position)
	var current: Vector2i=model.get("current_cell",Vector2i.ZERO)
	var flags: Array=model.get("cell_flags",[])
	var index := current.y*9+current.x
	if index>=0 and index<flags.size() and (int(flags[index])&0xf0)!=0: _sprite("Panel",80,3,Vector2(320,225))

func _draw_catching(model: Dictionary) -> void:
	for item in model.get("items",[]):
		if item.is_empty() or bool(item.get("caught",false)) or bool(item.get("retired",false)): continue
		_sprite("Panel",95+int(item.get("id",0)),int(item.get("frame",0))%8,Vector2(float(item.get("display_x",item.get("x",0))),float(item.get("y",100))),float(item.get("scale",0.5)))
	var thrower := int(model.get("thrower_state",3))*6+int(model.get("thrower_frame",4))
	var lookup: Array=[]
	if _visuals is Object:
		lookup=_visuals.get("manifest").get("minigame_source",{}).get("thrower_frames",[])
	if thrower>=0 and thrower<lookup.size(): _sprite("Panel",93,int(lookup[thrower]),Vector2(float(model.get("thrower_x",110)),126))
	var bomb_frame := int(model.get("bomb_throw_frame",-1))
	if bomb_frame>=0: _sprite("Panel",94,bomb_frame,Vector2(float(model.get("bomb_throw_x",0)),125))
	var character_resource := 100+int(_view.get("character_id",0))
	var count: int=_resource("Panel",character_resource).get("chunks",{}).size()
	var direction := int(model.get("character_direction",0))
	var frame := int(model.get("character_reaction",0))
	if direction>0: frame=5+int(model.get("character_frame",0))+(direction-1)*int((count-5)/2)
	var position: Vector2=model.get("character_position",Vector2(320,380))
	_sprite("Panel",character_resource,frame,position)
	if _phase=="ending" and bool(model.get("bomb",false)):
		var effect := _effect("catching_bomb")
		var explosion := _resource(str(effect.get("archive","")),int(effect.get("resource_index",-1)))
		var total: int=explosion.get("chunks",{}).size()
		var interval := float(explosion.get("caller",{}).get("delay_ms",50))/1000.0
		if total>0: _sprite(str(effect.archive),int(effect.resource_index),mini(total-1,int(_ending_seconds/interval)),Vector2(position.x-55,295))

func _draw_overlay() -> void:
	if _phase!="result": return
	_target=_overlay
	var digits := str(maxi(0,int(_view.get("reward",0))))
	var start := 353-digits.length()*33
	for index in range(digits.length()): _sprite("Panel",79,10+int(digits[index]),Vector2(start+index*66,150))

func _number(value: int, count: int, x: int) -> void:
	var digits := str(maxi(0,value)).pad_zeros(count)
	# Preserve source field width; unusually large bounded rewards remain in the
	# result overlay and core ledger even when the fixed HUD cannot fit them.
	for i in range(count): _sprite("Panel",79,int(digits[i]),Vector2(x+i*20,421))

func _penguin_anchor(cell: Vector2i, anchors: Array) -> Vector2:
	var index := cell.y*9+cell.x
	return Vector2(anchors[index]) if index>=0 and index<anchors.size() else Vector2(80+cell.x*48,81+cell.y*24)

func _effect(name: String) -> Dictionary:
	if not _visuals is Object: return {}
	var manifest: Dictionary=_visuals.get("manifest")
	return manifest.get("minigame_source",{}).get("effects",{}).get(name,{}).get(str(_view.get("edition","Game")),{})

func _resource(archive: String, resource: int) -> Dictionary:
	if not _visuals is Object: return {}
	var manifest: Dictionary=_visuals.get("manifest")
	return manifest.get("ui",{}).get(str(_view.get("edition","Game")),{}).get(archive,{}).get("resources",{}).get(str(resource),{})

func _frame(archive: String, resource: int, chunk: int) -> Dictionary:
	var key := "%s/%d/%d" % [archive,resource,chunk]
	if _frames.has(key): return _frames[key]
	var result: Dictionary={}
	if _visuals is Object and _visuals.has_method("ui") and _visuals.has_method("texture"):
		var record: Dictionary=_visuals.ui(str(_view.get("edition","Game")),archive,resource,chunk)
		result={"record":record,"texture":_visuals.texture(record)}
	_frames[key]=result
	return result

func _sprite(archive: String, resource: int, chunk: int, point: Vector2, factor: float=1.0) -> void:
	var frame := _frame(archive,resource,chunk)
	var texture: Variant=frame.get("texture")
	if not texture is Texture2D: return
	var logical: Dictionary=frame.get("record",{}).get("logical",{})
	var anchor := Vector2(float(logical.get("anchor_x",0)),float(logical.get("anchor_y",0)))
	var dimensions := Vector2(float(logical.get("width",texture.get_width())),float(logical.get("height",texture.get_height())))
	_target.draw_texture_rect(texture,Rect2(point-anchor*factor,dimensions*factor),false)
