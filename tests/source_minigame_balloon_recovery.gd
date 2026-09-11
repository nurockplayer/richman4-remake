extends SceneTree
const Model = preload("res://game/core/source_minigame_model.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func seeded() -> Object:
	# Fix a deterministic seed whose first source bucket is ordinary and whose
	# second draw cannot spawn. No product RNG algorithm override is involved.
	var rng := RandomNumberGenerator.new()
	for seed_value in range(10000):
		rng.seed = seed_value
		var first := rng.randi_range(0, 999)
		if first < 20 and rng.randi_range(0, 999) >= 30:
			return Model.new().configure("balloon", seed_value)
	return null
func occupied(y: int) -> Object:
	var model = seeded()
	for lane in Model.BALLOON_LANES:
		model.state.balloons.append({"id":0,"x":lane,"y":y,"phase":1})
	return model
func _initialize() -> void:
	var model = seeded()
	if model == null:
		print("PRECONDITION_UNMET deterministic source bucket seed")
		quit(2)
		return
	model.tick()
	check(not model.state.balloons.is_empty() and model.state.balloons[0].get("phase",0)==1,
		"one rand%1000 source bucket must populate empty slot0")
	var below = occupied(350)
	below.tick()
	check(below.state.balloons.size()==8,"all eight lanes below y300 exclude new spawns")
	var above = occupied(200)
	above.tick()
	check(above.state.balloons.size()>8,"lanes above y300 permit new source spawns")
	var freeze = seeded()
	freeze.state.balloons=[{"id":0,"x":40,"y":200,"phase":1}]
	freeze.state.effects.freeze_ticks=1
	freeze.tick()
	check(freeze.state.effects.freeze_ticks==0 and freeze.state.balloons[0].y==185,
		"source decrements freeze before movement on its last callback")
	var popped = seeded()
	popped.state.balloons=[{"id":0,"x":40,"y":200,"phase":2,"pop_frame":60}]
	popped.state.effects.freeze_ticks=20
	popped.tick()
	check(popped.state.balloons[0].pop_frame==44,
		"source pop progression is outside the freeze movement gate")
	print("Balloon recovery checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
