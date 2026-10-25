extends "res://tests/source_lottery_core.gd"
func _initialize() -> void:
	var game = fresh()
	enter(game)
	var saved: Dictionary = game.to_dict()
	for key in ["lottery_tickets", "lottery_pending", "lottery_draw_day"]:
		var missing: Dictionary = saved.duplicate(true)
		missing.erase(key)
		expect(not Game.validate_save(missing).ok and Game.from_dict(missing) == null, "partial lottery state cannot migrate: " + key)
	for key in ["lottery_pending", "lottery_draw_day", "elapsed", "start_date"]:
		for value in [null,[],{},true,"1"]:
			var broken: Dictionary = saved.duplicate(true)
			broken[key] = value
			expect(not Game.validate_save(broken).ok and Game.from_dict(broken) == null, "malformed lottery/calendar fields fail safely: " + key)
	for owner in [null,[],{},true,"1",-1,5,0.5]:
		var broken: Dictionary = saved.duplicate(true)
		broken.lottery_tickets[0] = owner
		expect(not Game.validate_save(broken).ok, "ticket owners are bounded integer IDs")
	var dead: Dictionary = saved.duplicate(true)
	dead.lottery_tickets[0] = 2
	dead.players[1].alive = false
	expect(not Game.validate_save(dead).ok, "bankrupt ticket ownership rejected")
	for key in ["pending_finance", "pending_auction", "pending_bank_visit", "pending_trap"]:
		var overlap: Dictionary = saved.duplicate(true)
		overlap[key] = {"active":true}
		expect(not Game.validate_save(overlap).ok, "lottery cannot overlap another owner: " + key)
	var wrong: Dictionary = saved.duplicate(true)
	wrong.lottery_pending = 1
	expect(not Game.validate_save(wrong).ok, "pending actor matches current owner")
	wrong = saved.duplicate(true)
	wrong.players[0].position = 1
	expect(not Game.validate_save(wrong).ok, "pending encounter requires source lottery location")
	wrong = saved.duplicate(true)
	wrong.phase = "await_action"
	expect(not Game.validate_save(wrong).ok, "pending encounter phase cannot be bypassed")
	wrong = saved.duplicate(true)
	wrong.jackpot = 1000000000001
	expect(not Game.validate_save(wrong).ok, "shared pool upper bound enforced")
	print("Lottery save checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
