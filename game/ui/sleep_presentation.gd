extends RefCounted

## UI copy and automatic-turn policy for the two sleep cards.
static func status(player: Dictionary) -> Dictionary:
	for field in ["winter_sleep_days", "dream_days"]:
		var count := int(player.get(field, 0))
		if count > 0:
			return {"kind": "winter" if field == "winter_sleep_days" else "dream", "count": count}
	return {}

static func automatic(player: Dictionary) -> bool:
	return not status(player).is_empty()

static func label(value: Dictionary) -> String:
	var title := "冬眠" if value.get("kind") == "winter" else "夢遊"
	return "待醒來" if int(value.get("count", 0)) == 128 else "%s · 剩餘 %d 回合" % [title, int(value.get("count", 0))]

static func hint(player: Dictionary) -> String:
	var value := status(player)
	if int(value.get("count", 0)) == 128:
		return "即將醒來，恢復操作"
	return "%s，自動推進回合" % label(value)

static func defense_prompt(caster_name: String, card_id: String) -> String:
	var consequence := "夢遊狀態" if card_id == "夢遊" else "入獄處罰"
	return "%s 對你使用%s卡。可將%s轉給另一位玩家；拒絕時保留嫁禍卡。" % [caster_name, card_id, consequence]
