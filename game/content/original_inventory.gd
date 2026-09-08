extends RefCounted

## Rule data transcribed from both owner executables; no artwork is embedded.
## IDs preserve the five legacy card identifiers used by existing saves.
const CARD_CAPACITY := 15
const TOOL_CAPACITY_PER_TYPE := 9

# id, displayed source name, initial shared supply, point price, source flags.
const CARD_ROWS := [
	["均富", "均富卡", 1, 200, 2, 2],
	["均貧", "均貧卡", 2, 200, 2, 2],
	["購地", "購地卡", 4, 35, 0, 1],
	["換地", "換地卡", 4, 25, 0, 0],
	["換屋", "換屋卡", 4, 20, 0, 0],
	["轉向", "轉向卡", 3, 20, 0, 0],
	["改建", "改建卡", 8, 15, 0, 0],
	["拍賣", "拍賣卡", 3, 20, 0, 1],
	["天使", "天使卡", 2, 160, 2, 0],
	["惡魔", "惡魔卡", 1, 180, 2, 2],
	["怪獸", "怪獸卡", 2, 60, 0, 2],
	["拆除", "拆除卡", 5, 15, 0, 1],
	["搶奪", "搶奪卡", 4, 25, 0, 2],
	["停留", "停留卡", 4, 20, 0, 0],
	["冬眠", "冬眠卡", 2, 100, 2, 2],
	["夢遊", "夢遊卡", 4, 25, 0, 1],
	["陷害", "陷害卡", 4, 20, 0, 2],
	["復仇", "復仇卡", 4, 20, 0, 0],
	["嫁禍", "嫁禍卡", 4, 40, 0, 0],
	["免費", "免費卡", 4, 25, 0, 0],
	["免罪", "免罪卡", 4, 25, 0, 0],
	["送神符", "送神符", 3, 10, 0, 0],
	["請神符", "請神符", 3, 20, 0, 0],
	["紅", "紅卡", 3, 50, 0, 0],
	["黑", "黑卡", 3, 30, 0, 1],
	["查稅", "查稅卡", 4, 35, 0, 1],
	["漲價", "漲價卡", 3, 35, 0, 0],
	["查封", "查封卡", 3, 35, 0, 1],
	["同盟", "同盟卡", 2, 40, 0, 0],
	["烏龜", "烏龜卡", 3, 70, 0, 0],
]

const TOOL_ROWS := [
	["機器娃娃", "機器娃娃", 10, 15, 0, 0],
	["路障", "路障", 10, 30, 0, 1],
	["地雷", "地雷", 10, 25, 0, 1],
	["定時炸彈", "定時炸彈", 10, 25, 0, 1],
	["機車", "機車", 10, 80, 0, 0],
	["汽車", "汽車", 10, 150, 1, 0],
	["飛彈", "飛彈", 10, 100, 1, 2],
	["遙控骰子", "遙控骰子", 10, 30, 1, 0],
	["機器工人", "機器工人", 0, 30, 2, 1],
	["時光機", "時光機", 0, 40, 2, 2],
	["傳送機", "傳送機", 0, 95, 2, 1],
	["工程車", "工程車", 0, 150, 2, 2],
	["核子飛彈", "核子飛彈", 0, 250, 2, 2],
]

static func cards() -> Array:
	return _records(CARD_ROWS)

static func tools() -> Array:
	return _records(TOOL_ROWS)

static func card(id: String) -> Dictionary:
	return _find(CARD_ROWS, id)

static func tool(id: String) -> Dictionary:
	return _find(TOOL_ROWS, id)

static func _records(rows: Array) -> Array:
	var result: Array = []
	for index in range(rows.size()):
		result.append(_record(rows[index], index + 1))
	return result

static func _find(rows: Array, id: String) -> Dictionary:
	for index in range(rows.size()):
		if rows[index][0] == id:
			return _record(rows[index], index + 1)
	return {}

static func _record(row: Array, source_id: int) -> Dictionary:
	return {
		"id": row[0], "name": row[1], "source_id": source_id,
		"initial_supply": row[2], "price": row[3],
		"source_flags": [row[4], row[5]],
	}
