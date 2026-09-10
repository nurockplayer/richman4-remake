extends SceneTree

## Focused synthetic acceptance tests for the private source-help loader.
##
## The committed fixtures are generated in this file under the disposable
## .local/ scratch tree; no original body text or owner data is involved.

const HELP_SCRIPT_PATH := "res://game/platform/original_help.gd"
const SECTION_TOPIC_COUNTS := [1, 6, 12, 3, 16, 18, 30, 13]
const TOTAL_TOPICS := 99
const MAX_INDEX_BYTES := 64 * 1024
const MAX_EDITION_BYTES := 2 * 1024 * 1024

var checks := 0
var failures := 0
var help_script: GDScript = null
var _root := ""
var _next_index := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])

func _initialize() -> void:
	var loaded := load(HELP_SCRIPT_PATH)
	if loaded is GDScript:
		help_script = loaded
	else:
		expect(false, "availability RED: %s is not implemented" % HELP_SCRIPT_PATH)
		quit(1)
		return
	_root = ProjectSettings.globalize_path("res://.local/source-help-loader-worker/gd")
	_reset_tree(_root)
	run()
	_reset_tree(_root)
	if failures:
		push_error("original_help: %d/%d checks failed" % [failures, checks])
	quit(1 if failures else 0)

func run() -> void:
	_test_valid_bundle_both_editions()
	_test_unknown_edition_and_missing_manifest()
	_test_returned_content_is_detached()
	_test_corrupted_edition_does_not_borrow_the_other()
	_test_wrong_edition_binding()
	_test_page_line_rules()
	_test_source_digest_enforced()
	_test_structural_integer_handling()
	_test_unsafe_index_path()
	_test_oversized_index_and_content()
	_test_explicit_path_overrides_environment()
	print("original_help: %d checks, %d failures" % [checks, failures])

func _new_bundle(name: String) -> String:
	var base := _root.path_join(name)
	write_text(base.path_join("content/Game.json"), _edition_text("Game", "Game", "a".repeat(64)))
	write_text(base.path_join("content/MultiverseJourney.json"), _edition_text("MultiverseJourney", "MultiverseJourney", "b".repeat(64)))
	var game_sha := FileAccess.get_sha256(base.path_join("content/Game.json"))
	var mj_sha := FileAccess.get_sha256(base.path_join("content/MultiverseJourney.json"))
	write_text(base.path_join("manifest.json"), _index_text(game_sha, mj_sha))
	return base.path_join("manifest.json")

func _test_valid_bundle_both_editions() -> void:
	var manifest_path := _new_bundle("valid")
	var loader: RefCounted = help_script.new(manifest_path)
	expect(loader.available("Game"), "valid Game bundle is available")
	expect(loader.available("MultiverseJourney"), "valid MJ bundle is available")
	expect_equal(loader.status("Game"), "ok", "valid Game status")
	expect_equal(loader.status("MultiverseJourney"), "ok", "valid MJ status")
	var game: Dictionary = loader.for_edition("Game")
	var mj: Dictionary = loader.for_edition("MultiverseJourney")
	expect_equal(game.get("edition"), "Game", "Game content keeps its edition")
	expect_equal(mj.get("edition"), "MultiverseJourney", "MJ content keeps its edition")
	var topics: Array = game.get("sections", [])[0].get("topics", []) if game.get("sections", []) is Array else []
	expect_equal(topics.size(), SECTION_TOPIC_COUNTS[0], "Game section 0 topic count")
	expect_equal(game.get("sections", []).size(), 8, "Game section count")
	var total := 0
	for section in game.get("sections", []):
		total += section.get("topics", []).size()
	expect_equal(total, TOTAL_TOPICS, "Game keyword total")

func _test_unknown_edition_and_missing_manifest() -> void:
	var manifest_path := _new_bundle("unknown")
	var loader: RefCounted = help_script.new(manifest_path)
	expect(not loader.available("Data3"), "unknown edition is unavailable")
	expect_equal(loader.for_edition("Data3"), {}, "unknown edition content is empty")
	expect(loader.status("Data3").contains("unsupported"), "unknown edition status explains itself")
	var missing: RefCounted = help_script.new(_root.path_join("absent/manifest.json"))
	expect(not missing.available("Game"), "missing manifest is unavailable")
	expect_equal(missing.for_edition("Game"), {}, "missing manifest content is empty")
	expect(not missing.status("Game").is_empty(), "missing manifest status is explicit")

func _test_returned_content_is_detached() -> void:
	var manifest_path := _new_bundle("detached")
	var loader: RefCounted = help_script.new(manifest_path)
	var first: Dictionary = loader.for_edition("Game")
	var original: String = first["sections"][0]["topics"][0]["pages"][0][0]
	first["sections"][0]["topics"][0]["pages"][0][0] = "mutated"
	first["sections"][0]["label"] = "mutated"
	var second: Dictionary = loader.for_edition("Game")
	expect_equal(second["sections"][0]["topics"][0]["pages"][0][0], original, "mutating returned content does not leak back")
	expect_equal(second["sections"][0]["label"], "Game-label-0", "mutating a returned label does not leak back")

func _test_corrupted_edition_does_not_borrow_the_other() -> void:
	var manifest_path := _new_bundle("corrupt")
	var edition_path := _root.path_join("corrupt/content/Game.json")
	write_text(edition_path, _edition_text("Game", "Game", "a".repeat(64)) + " ")
	var loader: RefCounted = help_script.new(manifest_path)
	expect(not loader.available("Game"), "digest-mismatched Game edition is unavailable")
	expect_equal(loader.for_edition("Game"), {}, "corrupted Game edition returns empty content")
	expect(not loader.status("Game").is_empty(), "corrupted Game status is explicit")
	expect(loader.available("MultiverseJourney"), "corrupt Game does not disable MJ")
	expect_equal(loader.for_edition("MultiverseJourney").get("edition"), "MultiverseJourney", "MJ stays independently available")

func _test_wrong_edition_binding() -> void:
	var manifest_path := _new_bundle("binding")
	var edition := _edition_dictionary("MultiverseJourney", "Game", "a".repeat(64))
	var text := JSON.stringify(edition)
	write_text(_root.path_join("binding/content/Game.json"), text)
	var sha := FileAccess.get_sha256(_root.path_join("binding/content/Game.json"))
	write_text(_root.path_join("binding/manifest.json"), _index_text(sha, FileAccess.get_sha256(_root.path_join("binding/content/MultiverseJourney.json"))))
	var loader: RefCounted = help_script.new(manifest_path)
	expect(not loader.available("Game"), "edition field must bind to the index key")
	expect(loader.available("MultiverseJourney"), "binding failure stays local to the edition")

func _test_page_line_rules() -> void:
	var manifest_path := _new_bundle("pages")
	var edition := _edition_dictionary("Game", "Game", "a".repeat(64))
	edition["sections"][0]["topics"][0]["pages"] = [[]]
	write_text(_root.path_join("pages/content/Game.json"), JSON.stringify(edition))
	var loader: RefCounted = help_script.new(manifest_path)
	expect(not loader.available("Game"), "empty page is rejected")
	var sha := FileAccess.get_sha256(_root.path_join("pages/content/Game.json"))
	write_text(_root.path_join("pages/manifest.json"), _index_text(sha, FileAccess.get_sha256(_root.path_join("pages/content/MultiverseJourney.json"))))
	var loader_two: RefCounted = help_script.new(manifest_path)
	expect(not loader_two.available("Game"), "empty page rejection survives reload")
	edition = _edition_dictionary("Game", "Game", "a".repeat(64))
	var long_page: Array = []
	for row in range(15):
		long_page.append("line-%d" % row)
	edition["sections"][0]["topics"][0]["pages"] = [long_page]
	write_text(_root.path_join("pages/content/Game.json"), JSON.stringify(edition))
	sha = FileAccess.get_sha256(_root.path_join("pages/content/Game.json"))
	write_text(_root.path_join("pages/manifest.json"), _index_text(sha, FileAccess.get_sha256(_root.path_join("pages/content/MultiverseJourney.json"))))
	var loader_three: RefCounted = help_script.new(manifest_path)
	expect(not loader_three.available("Game"), "fifteen-line page is rejected")

func _test_source_digest_enforced() -> void:
	var manifest_path := _new_bundle("source_digest")
	var valid: RefCounted = help_script.new(manifest_path)
	expect(valid.available("Game"), "fixture carrying source digest loads")
	var edition := _edition_dictionary("Game", "Game", "a".repeat(64))
	edition["sections"][0]["topics"][0].erase("source_payload_sha256")
	write_text(_root.path_join("source_digest/content/Game.json"), JSON.stringify(edition))
	var sha := FileAccess.get_sha256(_root.path_join("source_digest/content/Game.json"))
	write_text(manifest_path, _index_text(sha, FileAccess.get_sha256(_root.path_join("source_digest/content/MultiverseJourney.json"))))
	var loader: RefCounted = help_script.new(manifest_path)
	expect(not loader.available("Game"), "missing source digest is rejected")
	for bad in ["A".repeat(64), "c".repeat(63), "g".repeat(64), "c".repeat(65)]:
		edition = _edition_dictionary("Game", "Game", "a".repeat(64))
		edition["sections"][0]["topics"][0]["source_payload_sha256"] = bad
		write_text(_root.path_join("source_digest/content/Game.json"), JSON.stringify(edition))
		sha = FileAccess.get_sha256(_root.path_join("source_digest/content/Game.json"))
		write_text(manifest_path, _index_text(sha, FileAccess.get_sha256(_root.path_join("source_digest/content/MultiverseJourney.json"))))
		var broken: RefCounted = help_script.new(manifest_path)
		expect(not broken.available("Game"), "malformed source digest %s is rejected" % bad)
	expect(valid.available("MultiverseJourney"), "source digest rejection stays local to Game")


func _test_structural_integer_handling() -> void:
	var manifest_path := _new_bundle("floats")
	var base_index := FileAccess.open(manifest_path, FileAccess.READ).get_as_text()
	write_text(manifest_path, base_index.replace('"entry_count":100', '"entry_count":100.0'))
	var loader: RefCounted = help_script.new(manifest_path)
	expect(loader.available("Game"), "finite integral float entry_count is accepted")
	var edition_text := _edition_text("Game", "Game", "a".repeat(64)).replace('"resource_index":1,', '"resource_index":1.0,')
	write_text(_root.path_join("floats/content/Game.json"), edition_text)
	var sha := FileAccess.get_sha256(_root.path_join("floats/content/Game.json"))
	write_text(manifest_path, _index_text(sha, FileAccess.get_sha256(_root.path_join("floats/content/MultiverseJourney.json"))))
	var loader_two: RefCounted = help_script.new(manifest_path)
	expect(loader_two.available("Game"), "finite integral float resource_index is accepted")
	edition_text = _edition_text("Game", "Game", "a".repeat(64)).replace('"resource_index":1,', '"resource_index":true,')
	write_text(_root.path_join("floats/content/Game.json"), edition_text)
	sha = FileAccess.get_sha256(_root.path_join("floats/content/Game.json"))
	write_text(manifest_path, _index_text(sha, FileAccess.get_sha256(_root.path_join("floats/content/MultiverseJourney.json"))))
	var loader_three: RefCounted = help_script.new(manifest_path)
	expect(not loader_three.available("Game"), "boolean resource_index is rejected")
	write_text(manifest_path, base_index.replace('"entry_count":100', '"entry_count":true'))
	var loader_four: RefCounted = help_script.new(manifest_path)
	expect(not loader_four.available("Game"), "boolean entry_count invalidates the manifest")

func _test_unsafe_index_path() -> void:
	var manifest_path := _new_bundle("unsafe")
	var index := FileAccess.open(manifest_path, FileAccess.READ).get_as_text()
	write_text(manifest_path, index.replace("content/Game.json", "../Game.json"))
	var loader: RefCounted = help_script.new(manifest_path)
	expect(not loader.available("Game"), "escaping index path is rejected")
	expect(not loader.available("MultiverseJourney"), "unsafe index invalidates the whole manifest")

func _test_oversized_index_and_content() -> void:
	var manifest_path := _new_bundle("oversized")
	write_text(_root.path_join("oversized/manifest.json"), "x".repeat(MAX_INDEX_BYTES + 1))
	var loader: RefCounted = help_script.new(_root.path_join("oversized/manifest.json"))
	expect(not loader.available("Game"), "index above 64KiB is rejected")
	manifest_path = _new_bundle("oversized_content")
	write_text(_root.path_join("oversized_content/content/Game.json"), "x".repeat(MAX_EDITION_BYTES + 1))
	var loader_two: RefCounted = help_script.new(manifest_path)
	expect(not loader_two.available("Game"), "edition content above 2MiB is rejected")

func _test_explicit_path_overrides_environment() -> void:
	var manifest_path := _new_bundle("explicit")
	var previous := OS.get_environment("RICHMAN4_HELP_MANIFEST")
	OS.set_environment("RICHMAN4_HELP_MANIFEST", _root.path_join("absent/manifest.json"))
	var loader: RefCounted = help_script.new(manifest_path)
	expect(loader.available("Game"), "explicit path wins over the environment")
	var from_env: RefCounted = help_script.new()
	expect(not from_env.available("Game"), "environment path is used when no explicit path is given")
	OS.set_environment("RICHMAN4_HELP_MANIFEST", _root.path_join("explicit/manifest.json"))
	var env_loader: RefCounted = help_script.new()
	expect(env_loader.available("MultiverseJourney"), "valid environment path loads")
	OS.set_environment("RICHMAN4_HELP_MANIFEST", previous)

func _edition_dictionary(edition: String, declared: String, archive_sha: String) -> Dictionary:
	var sections: Array = []
	var index := 1
	for section_id in range(8):
		var topics: Array = []
		for _topic in range(SECTION_TOPIC_COUNTS[section_id]):
			topics.append({
				"resource_index": index,
				"title": "%s-topic-%d" % [declared, index],
				"payload_sha256": "0".repeat(64),
				"source_payload_sha256": "c".repeat(64),
				"pages": [["%s line one" % declared, "%s line two" % declared]],
			})
			index += 1
		sections.append({"id": section_id, "label": "%s-label-%d" % [declared, section_id], "topics": topics})
	return {
		"schema": "richman4.help-edition/v1",
		"edition": edition,
		"archive_sha256": archive_sha,
		"sections": sections,
	}

func _edition_text(edition: String, declared: String, archive_sha: String) -> String:
	return JSON.stringify(_edition_dictionary(edition, declared, archive_sha))

func _index_text(game_sha: String, mj_sha: String, game_path := "content/Game.json", mj_path := "content/MultiverseJourney.json") -> String:
	return (
		'{"schema":"richman4.help/v1","editions":{'
		+ '"Game":{"path":"%s","sha256":"%s","archive_sha256":"%s","entry_count":100},'
		+ '"MultiverseJourney":{"path":"%s","sha256":"%s","archive_sha256":"%s","entry_count":100}}}'
	) % [game_path, game_sha, "a".repeat(64), mj_path, mj_sha, "b".repeat(64)]

func _write_edition(base: String, edition: String, declared: String, relative: String) -> String:
	var path := base.path_join(relative)
	write_text(path, _edition_text(edition, declared, "a".repeat(64) if edition == "Game" else "b".repeat(64)))
	return FileAccess.get_sha256(path)

func write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		expect(false, "cannot write synthetic fixture %s" % path)
		return
	file.store_string(text)
	file.close()

func _reset_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_reset_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)
