extends RefCounted
## Synthetic format fixture; contains no original asset or extracted map data.
static func make() -> Dictionary:
	var nodes: Array = []
	var edges := [[2], [1, 3, 4], [2, 5], [2, 5], [3, 4, 6], [5]]
	for index in range(6):
		nodes.append({"id": index + 1, "x": 100 + index * 80, "y": 100 + (index % 2) * 80,
			"adjacent": edges[index].duplicate(), "type_and_idx": 0, "event_code": 0, "visual_index": 0})
	nodes[0].type_and_idx = 8002
	nodes[1].event_code = 10
	nodes[2].type_and_idx = 2001
	nodes[3].type_and_idx = 2002
	nodes[4].event_code = 13
	nodes[5].event_code = 14
	var lands: Array = []
	for id in [1, 2]:
		lands.append({"id": id, "display_name": "測試路", "name_bytes_hex": "74657374000000000000000000000000",
			"land_price": 1000 * id, "house_price": 300, "rent_by_level": [100, 250, 600, 1200, 2400, 4800], "level": 0, "owner": 0})
	return {"schema": "richman4.map/v1", "version": 1, "edition": "Game", "map_number": 1,
		"archive": "Game/map.mkf", "entry_index": 1, "payload_sha256": "a".repeat(64), "source_file_sha256": "b".repeat(64),
		"nodes": nodes, "lands": lands, "facilities": [], "companies": []}
