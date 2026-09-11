class_name SourceMinigameModel
extends RefCounted

## Deterministic, presentation-free source minigame simulation.
##
## The model deliberately owns no intro/result timers.  A controller may keep
## those phases separate and call tick only while the active game has focus.
## All coordinates are source coordinates in a 640x480 canvas; presenters are
## responsible for scaling them to the actual viewport.

const SOURCE_SIZE := Vector2(640.0, 480.0)
const BALLOON_TICK_MS := 100
const PENGUIN_TICK_MS := 100
const CATCHING_TICK_MS := 50
const BALLOON_DEADLINE_TICKS := 150
const PENGUIN_DEADLINE_TICKS := 150
const CATCHING_DEADLINE_TICKS := 360
const MAX_REWARD := 1000000000000

const BALLOON_LANES := [40, 120, 200, 280, 360, 440, 520, 600]
const BALLOON_SPEEDS := [15, 15, 15, 15, 18, 18, 18, 24, 24, 24, 24, 18]
const BALLOON_SPECIAL_TYPES := [9, 9, 10, 10, 10, 10, 10, 11, 11, 11]
const CATCHING_POINTS := [10, 5, 3, 1]

# The source Panel81 coordinate table is a 9x9 table.  Its 64 valid cells
# have a central hole at (4,4) and missing exterior cells.  Keeping this
# table here lets tests exercise source DDA without shipping the private mask.
const PENGUIN_VALID_CELLS := [
	[2, 3, 4, 5],
	[0, 1, 2, 3, 4, 5, 6],
	[0, 1, 2, 3, 4, 5, 6, 7, 8],
	[0, 1, 2, 3, 4, 5, 6, 7, 8],
	[0, 1, 2, 3, 5, 6, 7, 8],
	[0, 1, 2, 3, 4, 5, 6, 7, 8],
	[0, 1, 2, 3, 4, 5, 6],
	[0, 1, 2, 3, 4, 5, 6],
	[1, 2, 3, 4],
]

var kind: String = ""
var state: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _input_data: Dictionary = {}
var _pointer_position := Vector2.ZERO
var _pointer_pressed := false
var _penguin_grid: Array = []
var _penguin_mask: Variant = null
var _penguin_original_target := Vector2i(-1, -1)
var _penguin_step_fixed := Vector2i.ZERO
var _penguin_current_fixed := Vector2i.ZERO
var _penguin_next_fixed := Vector2i.ZERO
var _penguin_next_cell := Vector2i(-1, -1)
var _penguin_move_frame: int = 0
var _penguin_reroute := false


func configure(game_kind: String, seed: int, input_data: Dictionary = {}) -> SourceMinigameModel:
	kind = game_kind.strip_edges().to_lower()
	if not ["balloon", "penguin", "catching"].has(kind):
		kind = ""
	_input_data = input_data.duplicate(true)
	_rng.seed = seed
	_pointer_position = Vector2.ZERO
	_pointer_pressed = false
	state = {
		"kind": kind,
		"seed": seed,
		"tick": 0,
		"elapsed_ms": 0,
		"tick_ms": _tick_ms(),
		"deadline_ticks": _deadline_ticks(),
		"active": not kind.is_empty(),
		"finished": false,
		"finish_reason": "",
		"pointer": Vector2.ZERO,
		"pressed": false,
		"score": 0,
		"reward": 0,
	}
	if kind == "balloon":
		_configure_balloon()
	elif kind == "penguin":
		_configure_penguin()
	elif kind == "catching":
		_configure_catching()
	return self


func tick() -> void:
	if not bool(state.get("active", false)) or bool(state.get("finished", false)):
		return
	state["tick"] = int(state.get("tick", 0)) + 1
	state["elapsed_ms"] = int(state["tick"]) * int(state["tick_ms"])
	if kind == "balloon":
		_tick_balloon()
	elif kind == "penguin":
		_tick_penguin()
	elif kind == "catching":
		_tick_catching()
	if kind != "catching" and not bool(state.get("finished", false)) and int(state["tick"]) >= int(state["deadline_ticks"]):
		_finish("timeout")


func pointer(position: Vector2, pressed: bool) -> void:
	# Keep the source coordinate exactly as received.  This is intentionally not
	# a viewport coordinate and is never converted using the window size.
	_pointer_position = position
	state["pointer"] = position
	state["pressed"] = pressed
	if not bool(state.get("active", false)) or bool(state.get("finished", false)):
		_pointer_pressed = pressed
		return
	var down_edge := pressed
	_pointer_pressed = pressed
	if not down_edge:
		return
	if kind == "balloon":
		_balloon_click(position)
	elif kind == "penguin":
		_penguin_click(position)
	# Catching follows the pointer continuously; its movement is applied by tick.


func snapshot() -> Dictionary:
	return state.duplicate(true)


func finished() -> bool:
	return bool(state.get("finished", false))


func reward() -> int:
	return int(state.get("reward", 0))


func _tick_ms() -> int:
	if kind == "catching":
		return CATCHING_TICK_MS
	return 100


func _deadline_ticks() -> int:
	if kind == "catching":
		return CATCHING_DEADLINE_TICKS
	return 150


func _configure_balloon() -> void:
	state["balloons"] = []
	state["counts"] = [0]
	state["effects"] = {"freeze_ticks": 0, "speed_modifier": 0, "end_next_tick": false}
	state["special_effect"] = ""
	state["spawn_attempts"] = 0


func _tick_balloon() -> void:
	var balloons: Array = state["balloons"]
	# Source tries each empty slot every callback.  A deterministic RNG replaces
	# libc rand while preserving the documented bucket probabilities and lanes.
	for index in range(16):
		if _balloon_slot_free(balloons, index) and _rng.randi_range(0, 999) < 30:
			_spawn_balloon(balloons, index)
	state["spawn_attempts"] = int(state["spawn_attempts"]) + 16
	var effects: Dictionary = state["effects"]
	if int(effects.get("end_next_tick", false)):
		_finish("effect_end")
		return
	var freeze := int(effects.get("freeze_ticks", 0))
	if freeze > 0:
		effects["freeze_ticks"] = freeze - 1
	else:
		for balloon in balloons:
			if typeof(balloon) != TYPE_DICTIONARY or int(balloon.get("phase", 0)) != 1:
				continue
			var modifier := int(effects.get("speed_modifier", 0))
			var speed := int(BALLOON_SPEEDS[int(balloon.get("id", 0))])
			if modifier < 0:
				speed *= 2
			elif modifier > 0:
				speed = int(speed / 2)
			balloon["y"] = int(balloon.get("y", 0)) - speed
			if int(balloon["y"]) < -60:
				balloon["phase"] = 0
		# Popped source slots animate separately, with no gameplay score change.
		for balloon in balloons:
			if typeof(balloon) == TYPE_DICTIONARY and int(balloon.get("phase", 0)) == 2:
				balloon["pop_frame"] = int(balloon.get("pop_frame", 60)) - 16
				if int(balloon["pop_frame"]) <= 0:
					balloon["phase"] = 0
	state["reward"] = int(state["score"])


func _balloon_slot_free(balloons: Array, index: int) -> bool:
	if index >= balloons.size():
		return true
	return typeof(balloons[index]) != TYPE_DICTIONARY or int(balloons[index].get("phase", 0)) == 0


func _spawn_balloon(balloons: Array, index: int) -> void:
	var roll := _rng.randi_range(0, 999)
	var id := -1
	if roll < 20:
		id = int(roll / 4)
	elif roll < 28:
		id = [8, 8, 7, 7, 6, 6, 5, 5][roll - 20]
	elif roll < 30:
		id = BALLOON_SPECIAL_TYPES[_rng.randi_range(0, 9)]
	if id < 0:
		return
	var available: Array = []
	for lane in BALLOON_LANES:
		var clear := true
		for balloon in balloons:
			if typeof(balloon) == TYPE_DICTIONARY and int(balloon.get("phase", 0)) == 1 and int(balloon.get("x", -999)) == lane and int(balloon.get("y", 999)) < 300:
				clear = false
		if clear:
			available.append(lane)
	if available.is_empty():
		return
	var record := {"slot": index, "id": id, "x": available[_rng.randi_range(0, available.size() - 1)], "y": 420, "phase": 1, "pop_frame": 0}
	while balloons.size() <= index:
		balloons.append({})
	balloons[index] = record


func _balloon_click(position: Vector2) -> void:
	var balloons: Array = state["balloons"]
	var effects: Dictionary = state["effects"]
	for balloon in balloons:
		if typeof(balloon) != TYPE_DICTIONARY or int(balloon.get("phase", 0)) != 1:
			continue
		var id := int(balloon.get("id", 0))
		var half_x := 22 if id < 6 else 18
		var half_y := 30 if id < 6 else 26
		if abs(position.x - float(balloon.get("x", 0))) <= half_x and abs(position.y - float(balloon.get("y", 0))) <= half_y:
			if id < 9:
				state["score"] = mini(999, int(state["score"]) + id + 1)
			elif id == 9:
				state["score"] = _double_score(int(state["score"]))
			elif id == 10:
				state["score"] = int(int(state["score"]) / 2)
			else:
				var effect := _rng.randi_range(0, 5)
				effects["freeze_ticks"] = 0
				effects["speed_modifier"] = 0
				state["special_effect"] = effect
				if effect == 0:
					effects["end_next_tick"] = true
				elif effect == 1:
					effects["freeze_ticks"] = 20
				elif effect == 2:
					effects["speed_modifier"] = -1
				elif effect == 3:
					effects["speed_modifier"] = 1
				elif effect == 4:
					state["score"] = 0
				else:
					state["score"] = _double_score(int(state["score"]))
			balloon["phase"] = 2
			balloon["pop_frame"] = 60
	state["reward"] = int(state["score"])


func _configure_penguin() -> void:
	var current := _as_cell(_input_data.get("current_cell", Vector2i(2, 6)), Vector2i(2, 6))
	_penguin_current_fixed = current * 65536 + Vector2i(32768, 32768)
	_penguin_next_fixed = _penguin_current_fixed
	_penguin_next_cell = current
	state["current_cell"] = current
	state["target_cell"] = Vector2i(-1, -1)
	state["penguin_cell"] = current
	state["penguin_position"] = _penguin_anchor(current)
	state["movement_state"] = "idle"
	state["movement_frame"] = 0
	state["movement_ticks_per_step"] = 4
	state["reroute"] = false
	state["counts"] = [0, 0, 0, 0]
	state["items_found"] = []
	state["dig_count"] = 0
	state["dig_frame"] = 0
	state["movement_direction"] = 0
	state["cell_anchors"] = _input_data.get("penguin_grid", [])
	state["cell_flags"] = _input_data.get("penguin_flags", [])
	_penguin_mask = _input_data.get("mask", _input_data.get("penguin_mask", null))
	_penguin_grid = _normalise_penguin_grid(_input_data)
	state["grid_fallback"] = _input_data.get("grid", null) == null and _input_data.get("item_grid", null) == null and _input_data.get("cell_items", null) == null
	state["grid_source"] = "source_distribution" if bool(state["grid_fallback"]) else "input_data"
	state["items_grid"] = _penguin_grid


func _tick_penguin() -> void:
	for item in state.get("items_found", []): item["age"] = int(item.get("age", 0)) + 1
	if str(state.get("movement_state", "idle")) == "digging":
		state["dig_frame"] = int(state.get("dig_frame", 0)) + 1
		if int(state.dig_frame) >= 4:
			_penguin_dig(_as_cell(state.current_cell, Vector2i(2,6)))
			if not finished(): state.movement_state = "idle"
		return
	if str(state.get("movement_state", "idle")) == "walking":
		_penguin_move_frame += 1
		state["movement_frame"] = _penguin_move_frame
		var start_cell: Vector2i = _as_cell(state["current_cell"], Vector2i(2, 6))
		var from := _penguin_anchor(start_cell)
		var to := _penguin_anchor(_penguin_next_cell)
		state["penguin_position"] = from.lerp(to, float(_penguin_move_frame) / 4.0)
		if _penguin_move_frame >= 4:
			_penguin_current_fixed = _penguin_next_fixed
			state["current_cell"] = _penguin_next_cell
			state["penguin_cell"] = _penguin_next_cell
			state["penguin_position"] = _penguin_anchor(_penguin_next_cell)
			if _penguin_next_cell == _penguin_original_target:
				state["movement_state"] = "digging"
				state["dig_frame"] = 0
			else:
				if _penguin_reroute:
					_prepare_penguin_target(_penguin_original_target)
				else:
					_penguin_next_cell = _penguin_compute_next()
					_penguin_move_frame = 0
					state["movement_frame"] = 0
					_update_penguin_direction()


func _penguin_click(position: Vector2) -> void:
	if str(state.get("movement_state", "idle")) != "idle":
		return
	var target := _penguin_cell_at(position)
	if not _penguin_valid_cell(target) or target == _as_cell(state["current_cell"], Vector2i(2, 6)):
		return
	_prepare_penguin_target(target)


func _prepare_penguin_target(target: Vector2i) -> void:
	var current := _as_cell(state["current_cell"], Vector2i(2, 6))
	if not _penguin_valid_cell(target) or target == current:
		return
	_penguin_original_target = target
	_penguin_current_fixed = current * 65536 + Vector2i(32768, 32768)
	_penguin_next_fixed = _penguin_current_fixed
	var dx := target.x - current.x
	var dy := target.y - current.y
	var denominator := maxi(absi(dx), absi(dy))
	_penguin_step_fixed = Vector2i(int(float(dx * 65536) / denominator), int(float(dy * 65536) / denominator))
	_penguin_reroute = false
	_penguin_next_cell = _penguin_compute_next()
	_penguin_move_frame = 0
	state["target_cell"] = target
	state["movement_state"] = "walking"
	state["movement_frame"] = 0
	state["reroute"] = _penguin_reroute
	_update_penguin_direction()


func _update_penguin_direction() -> void:
	var current: Vector2i = state.current_cell
	var dx := _penguin_next_cell.x-current.x
	var dy := _penguin_next_cell.y-current.y
	state["movement_direction"] = (3-dy) if dx>0 else ((1 if dy>0 else 5) if dx==0 else ((dy+7)&7))

func _penguin_compute_next() -> Vector2i:
	var nominal := Vector2i(int(floor(float(_penguin_current_fixed.x + _penguin_step_fixed.x) / 65536.0)), int(floor(float(_penguin_current_fixed.y + _penguin_step_fixed.y) / 65536.0)))
	if _penguin_valid_cell(nominal):
		_penguin_next_fixed = _penguin_current_fixed + _penguin_step_fixed
		return nominal
	_penguin_reroute = true
	var prior := _penguin_next_cell
	var candidate := nominal
	if absi(_penguin_step_fixed.x) == 65536:
		candidate.x = nominal.x
		candidate.y = prior.y
		if candidate.y == nominal.y:
			candidate.y += 1 if _penguin_step_fixed.y >= 0 else -1
	else:
		candidate.y = nominal.y
		candidate.x = prior.x
		if candidate.x == nominal.x:
			candidate.x += 1 if _penguin_step_fixed.x >= 0 else -1
	_penguin_next_fixed = candidate * 65536 + Vector2i(32768, 32768)
	return candidate


func _penguin_dig(cell: Vector2i) -> void:
	var index := cell.y * 9 + cell.x
	var item := int(_penguin_grid[index]) if index >= 0 and index < _penguin_grid.size() else 0
	if item == 0:
		state["items_found"].append({"cell": cell, "item": 0, "age": 0})
		state["dig_count"] = int(state["dig_count"]) + 1
		return
	if index < _penguin_grid.size():
		_penguin_grid[index] = 0
	state["items_found"].append({"cell": cell, "item": item, "age": 0})
	state["dig_count"] = int(state["dig_count"]) + 1
	if item == 1:
		state["finish_reason"] = "bomb"
		_finish("bomb")
		return
	if item >= 2 and item <= 5:
		var counts: Array = state["counts"]
		counts[item - 2] = int(counts[item - 2]) + 1
		state["score"] = int(counts[0]) * 5 + int(counts[1]) * 12 + int(counts[2]) * 8 + int(counts[3]) * 20
		state["reward"] = int(state["score"])


func _normalise_penguin_grid(data: Dictionary) -> Array:
	var source: Variant = data.get("grid", data.get("item_grid", null))
	var grid: Array = []
	for i in range(81):
		grid.append(0)
	if typeof(source) == TYPE_ARRAY:
		for i in range(mini(81, source.size())):
			grid[i] = clampi(int(source[i]), 0, 5)
		return grid
	var cells: Variant = data.get("cell_items", {})
	if typeof(cells) == TYPE_DICTIONARY:
		for key in cells:
			var index := _cell_index(key)
			if index >= 0 and index < 81:
				grid[index] = clampi(int(cells[key]), 0, 5)
		if not cells.is_empty():
			return grid
	# Safe fallback: distribute the source counts over the 64 source-valid cells.
	var ids: Array = []
	for item_id in [1, 2, 3, 4, 5]:
		var count: int = [3, 12, 3, 9, 1][item_id - 1]
		for _i in range(count):
			ids.append(item_id)
	while ids.size() < 64:
		ids.append(0)
	for i in range(ids.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap = ids[i]
		ids[i] = ids[j]
		ids[j] = swap
	var valid := _all_penguin_cells()
	for i in range(mini(valid.size(), ids.size())):
		var cell: Vector2i = valid[i]
		grid[cell.y * 9 + cell.x] = ids[i]
	return grid


func _penguin_cell_at(position: Vector2) -> Vector2i:
	if typeof(_penguin_mask) == TYPE_PACKED_BYTE_ARRAY or typeof(_penguin_mask) == TYPE_ARRAY:
		if position.x < 0.0 or position.x >= 640.0 or position.y < 0.0 or position.y >= 480.0:
			return Vector2i(-1, -1)
		var x := int(position.x)
		var y := int(position.y)
		var offset := y * 640 + x
		if offset >= 0 and offset < _penguin_mask.size():
			var cell_id := int(_penguin_mask[offset])
			if cell_id > 0:
				return Vector2i(cell_id % 9, int(cell_id / 9))
		return Vector2i(-1,-1)
	var nearest := Vector2i(-1, -1)
	var best := INF
	for cell in _all_penguin_cells():
		var distance := position.distance_squared_to(_penguin_anchor(cell))
		if distance < best:
			best = distance
			nearest = cell
	return nearest if best <= float(_input_data.get("hit_radius", 28.0)) ** 2 else Vector2i(-1, -1)


func _penguin_valid_cell(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= 9 or cell.y < 0 or cell.y >= 9:
		return false
	var supplied: Variant = _input_data.get("penguin_grid", null)
	var index := cell.y * 9 + cell.x
	if typeof(supplied) == TYPE_ARRAY and index < supplied.size():
		var value = supplied[index]
		if value is Vector2i:
			return value.x != 0
		if value is Vector2:
			return value.x != 0.0
		if typeof(value) == TYPE_ARRAY and value.size() >= 2:
			return int(value[0]) != 0
	return PENGUIN_VALID_CELLS[cell.y].has(cell.x)


func _all_penguin_cells() -> Array:
	var result: Array = []
	for y in range(9):
		for x in range(9):
			if _penguin_valid_cell(Vector2i(x,y)): result.append(Vector2i(x,y))
	return result


func _penguin_anchor(cell: Vector2i) -> Vector2:
	# Logical fallback anchors follow the 48px source grid, while callers with
	# a decoded source table may supply exact anchors as [[x,y], ...].
	var anchors: Variant = _input_data.get("anchors", _input_data.get("penguin_grid", null))
	var index := cell.y * 9 + cell.x
	if typeof(anchors) == TYPE_ARRAY and index >= 0 and index < anchors.size():
		var value = anchors[index]
		if value is Vector2i:
			return Vector2(value)
		if value is Vector2:
			return value
		if typeof(value) == TYPE_ARRAY and value.size() >= 2:
			return Vector2(float(value[0]), float(value[1]))
	return Vector2(80 + cell.x * 48, 81 + cell.y * 24)


func _configure_catching() -> void:
	state["character_position"] = Vector2(320, 380)
	_pointer_position = Vector2(320,380)
	state["pointer"] = _pointer_position
	state["character_direction"] = 0
	state["character_frame"] = 0
	state["character_reaction"] = 0
	state["items"] = _input_data.get("items", []).duplicate(true)
	state["counts"] = [0,0,0,0]
	state["bomb"] = false
	state["draining"] = false
	state["spawn_attempts"] = 0
	state["spawn_count"] = 0
	state["spawn_distribution"] = "source_rand20_separate_bomb"
	state["thrower_x"] = 110
	state["thrower_state"] = 3
	state["thrower_frame"] = 4
	state["throw_at"] = 0 # Source cold-process value; repeat-entry carry is unknown.
	state["bomb_throw_frame"] = -1
	state["bomb_throw_x"] = 0


func _tick_catching() -> void:
	if int(state.tick) >= 360: state.draining = true
	var character: Vector2 = state.character_position
	for item in state.items:
		if item.is_empty() or bool(item.get("caught",false)) or bool(item.get("retired",false)): continue
		var factor: float = maxf(float(item.get("y",100))-130.0,0.0)/250.0
		item["display_x"] = float(item.get("origin_x",item.get("x",0))) + int(float(item.get("drift",0))*factor)
		item["scale"] = float(int(32768.0*(1.0+factor)))/65536.0
		if int(state.character_direction)!=0 and _catching_collides(item,character):
			_catch_item(item)
			if finished(): return
			continue
		item["frame"] = (int(item.get("frame",0))+1)%8
		if item.has("speed"): # Deterministic collision fixture only.
			item["y"] = float(item.get("y",0))+float(item.speed)
		elif float(item.get("y",100))<130:
			item["velocity"] = mini(int(item.get("velocity",-16))+2,16)
			item["y"] = float(item.get("y",100))+int(item.velocity)
		else:
			item["y"] = float(item.y)+[24,18,15,12,15][int(item.id)]
		if float(item.y)>380: item["retired"]=true
	var dx := _pointer_position.x-character.x
	if absf(dx)>8:
		state.character_direction = 1 if dx<0 else 2
		character.x = clampf(character.x+(-10.0 if dx<0 else 10.0),0.0,640.0)
		state.character_frame = (int(state.character_frame)+1)%_catching_direction_frames()
	state.character_position = character
	_update_catching_bomb_thrower()
	if not bool(state.draining):
		_update_catching_thrower()
	else:
		state.thrower_state=2
		state.thrower_frame=2
		var live := false
		for item in state.items:
			live = live or (not item.is_empty() and not bool(item.get("caught",false)) and not bool(item.get("retired",false)))
		# Finish after airborne objects and an already-started bomb throw drain.
		# This avoids source's post-pass flag discarding a just-emitted bomb.
		if not live and int(state.bomb_throw_frame)<0:
			state.character_direction=0
			state.character_reaction = 0 if reward()<40 else (1 if reward()<50 else (2 if reward()<60 else 3))
			_finish("timeout")


func _spawn_catching(origin_x: int, bomb: bool) -> bool:
	var slot := -1
	for i in range(16):
		if i>=state.items.size() or state.items[i].is_empty() or bool(state.items[i].get("caught",false)) or bool(state.items[i].get("retired",false)):
			slot=i
			break
	if slot<0: return false
	state.spawn_attempts = int(state.spawn_attempts)+1
	var item_id := 4
	if not bomb:
		var choice := _rng.randi_range(0,19)
		item_id = 3 if choice<9 else (2 if choice<15 else (1 if choice<18 else 0))
	var offset := origin_x-320
	var record := {"slot":slot,"id":item_id,"origin_x":origin_x,"x":origin_x,"display_x":origin_x,"y":100.0,"velocity":-16,"drift":int(float(offset)/210.0*260.0-offset),"frame":0,"scale":0.5,"caught":false,"retired":false}
	if slot==state.items.size(): state.items.append(record)
	else: state.items[slot]=record
	state.spawn_count=int(state.spawn_count)+1
	return true


func _update_catching_bomb_thrower() -> void:
	if int(state.bomb_throw_frame)<0:
		var eligible: bool = (int(state.thrower_state)<2 and int(state.thrower_x)>320) or (int(state.thrower_state)>3 and int(state.thrower_x)<320)
		if eligible:
			var begin := _rng.randi_range(0,9)>=7
			if begin and not bool(state.draining):
				state.bomb_throw_frame=0
				state.bomb_throw_x=_rng.randi_range(0,139)+(160 if int(state.thrower_x)>320 else 360)
	else:
		state.bomb_throw_frame=int(state.bomb_throw_frame)+1
		if int(state.bomb_throw_frame)==8 and not bool(state.bomb): _spawn_catching(int(state.bomb_throw_x),true)
		if int(state.bomb_throw_frame)>=12: state.bomb_throw_frame=-1


func _update_catching_thrower() -> void:
	var mode := int(state.thrower_state)
	var frame := int(state.thrower_frame)
	if mode in [2,3]:
		frame+=1
		if frame>=5:
			state.thrower_state=4 if mode==2 else 0
			frame=0
		state.thrower_frame=frame
		return
	if mode not in [0,4]: return
	var direction := 1 if mode==0 else -1
	if frame<5:
		if frame==int(state.throw_at): _spawn_catching(int(state.thrower_x),false)
		state.thrower_frame=frame+1
		state.thrower_x=int(state.thrower_x)+direction*12
		return
	var beyond_midpoint: bool = int(state.thrower_x)>320 if direction==1 else int(state.thrower_x)<320
	var turn := false
	if beyond_midpoint: turn = _rng.randi_range(0,3)==0
	turn=turn or int(state.thrower_x)==(530 if direction==1 else 110)
	if turn:
		state.thrower_state=2 if direction==1 else 3
	else:
		state.throw_at=_rng.randi_range(0,4)
		state.thrower_x=int(state.thrower_x)+direction*12
	state.thrower_frame=0


func _catching_direction_frames() -> int:
	var frames: Array = _input_data.get("character_frames",[])
	return maxi(1,int((frames.size()-5)/2)) if frames.size()>5 else 10


func _catching_collides(item: Dictionary, character: Vector2) -> bool:
	var frames: Array = _input_data.get("character_frames",[])
	var index := 5+int(state.character_frame)+(int(state.character_direction)-1)*_catching_direction_frames()
	var rect := Rect2(character-Vector2(25,75),Vector2(50,75))
	if index>=0 and index<frames.size():
		var frame: Dictionary = frames[index]
		rect=Rect2(character-Vector2(float(frame.x),float(frame.y)),Vector2(float(frame.width),float(frame.height)))
	var point := Vector2(float(item.get("display_x",item.get("x",0))),float(item.get("y",0)))
	return point.x>rect.position.x and point.x<rect.end.x and point.y>rect.position.y and point.y<rect.end.y


func _catch_item(item: Dictionary) -> void:
	if bool(item.get("caught",false)) or bool(state.bomb): return
	item["caught"]=true
	var item_id := int(item.get("id",0))
	if item_id==4:
		state.bomb=true
		state.character_direction=0
		state.character_reaction=4
		_finish("bomb")
		return
	state.counts[item_id]=int(state.counts[item_id])+1
	state.score=mini(MAX_REWARD,int(state.counts[0])*10+int(state.counts[1])*5+int(state.counts[2])*3+int(state.counts[3]))
	state.reward=int(state.score)


func _finish(reason: String) -> void:
	state["finished"] = true
	state["active"] = false
	state["finish_reason"] = reason
	state["reward"] = int(state.get("score", 0))


func _double_score(value: int) -> int:
	if value >= int(MAX_REWARD) / 2:
		return MAX_REWARD
	return value * 2


func _as_cell(value: Variant, fallback: Vector2i) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(value.x), int(value.y))
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback


func _cell_index(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_STRING:
		var parts := str(value).split(",")
		if parts.size() == 2:
			return int(parts[1]) * 9 + int(parts[0])
	return -1
