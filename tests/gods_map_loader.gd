extends SceneTree
const Maps = preload("res://game/content/original_maps.gd")
const Fixture = preload("res://tests/fixtures/original_map_fixture.gd")
var checks := 0
var failures := 0
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var raw := Fixture.make()
	raw.nodes[1]["status_bits"] = 0x8000010a
	var loaded := Maps.normalize_map(raw, true)
	expect(loaded.ok, "source status bits normalize")
	if loaded.ok:
		expect(int(loaded.definition.board[1].get("source_status_bits", -1)) == 0x8000010a, "god placement retains full source flags")
		expect(int(loaded.definition.board[1].event_code) == 10, "event low byte remains distinct from actor flags")
		expect(int(loaded.definition.board[4].get("source_status_bits", -1)) == 13, "old cache without full flags retains known event low byte")
	for bad in [-1, 4294967296, 2.5, "10", null]:
		var malformed := raw.duplicate(true)
		malformed.nodes[1]["status_bits"] = bad
		expect(not Maps.normalize_map(malformed, true).ok, "invalid source flags rejected: %s" % str(bad))
	var mismatch := raw.duplicate(true)
	mismatch.nodes[1]["status_bits"] = 11
	expect(not Maps.normalize_map(mismatch, true).ok, "event and source flags must agree on low byte")
	print("God map-loader checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
