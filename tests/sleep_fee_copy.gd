extends SceneTree
const MainScene = preload("res://game/main.tscn")
func _initialize() -> void:
	var ui = MainScene.instantiate()
	var failures := 0
	var checks := 0
	for reason in {"winter": "冬眠", "dream": "夢遊", "hospital": "住院", "prison": "入獄", "death": "死神附身"}:
		for kind in ["rent", "facility"]:
			checks += 1
			var status: String = {"winter": "冬眠", "dream": "夢遊", "hospital": "住院", "prison": "入獄", "death": "死神附身"}[reason]
			var expected := "地主%s，本次免收%s" % [status, "租金" if kind == "rent" else "設施費"]
			var actual: String = ui._event_detail("property_fee_waived", { "reason": reason, "kind": kind})
			if actual != expected:
				failures += 1
				push_error("Expected %s; got %s" % [expected, actual])
	ui.free()
	print("Sleep fee copy checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
