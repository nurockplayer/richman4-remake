extends SceneTree

## Private, deterministic render fixtures for the Issue #101 HUD repair.
##
## This runner is intentionally separate from the acceptance suite. It drives
## controls through their presentation APIs inside a fixed 640x480 SubViewport
## and writes private PNG/JSON evidence. It never sends OS input and its output
## is not ordinary native-input acceptance evidence.

const GameState = preload("res://game/core/game_state.gd")
const MainScene = preload("res://game/main.tscn")
const Maps = preload("res://game/content/original_maps.gd")
const OriginalGods = preload("res://game/content/original_gods.gd")
const OriginalVisuals = preload("res://game/platform/original_visuals.gd")

const SCHEMA := "richman4.issue101-native-render-fixtures/v1"
const REFERENCE_SIZE := Vector2i(640, 480)
const FIXTURE_SEED := 101101
const PLAYER_COUNT := 4
const REQUIRED_SOURCE_MAP := "Game:1"
const FULL_SETUP := {
	"original_inventory": true,
	"original_facilities": true,
	"original_gods": true,
	"original_companies": true,
	"original_statuses": true,
	"original_hazards": true,
	"original_property_cards": true,
	"original_remodel": true,
	"original_research": true,
	"original_building_cards": true,
	"initial_fund": 200000,
	"start_date": {"year": 1998, "month": 1, "day": 1},
}

var output_root := ""
var catalog_path := ""
var scene_manifest_path := ""
var checkout_root := ""
var checkout_head := ""
var catalog_sha256 := ""
var scene_manifest_sha256 := ""
var definition: Dictionary = {}
var source_scene: Dictionary = {}
var viewport: SubViewport
var ui: Control
var shell: Control
var cases: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String, code := 2) -> void:
	push_error(message)
	quit(code)


func _git_directory(project_root: String) -> String:
	var dot_git := project_root.path_join(".git")
	if DirAccess.dir_exists_absolute(dot_git):
		return dot_git
	if not FileAccess.file_exists(dot_git):
		return ""
	var pointer := FileAccess.get_file_as_string(dot_git).strip_edges()
	if not pointer.begins_with("gitdir:"):
		return ""
	var git_directory := pointer.trim_prefix("gitdir:").strip_edges()
	if not git_directory.begins_with("/"):
		git_directory = project_root.path_join(git_directory)
	return git_directory.simplify_path()


func _packed_ref(git_directory: String, reference: String) -> String:
	var packed_refs_path := git_directory.path_join("packed-refs")
	if not FileAccess.file_exists(packed_refs_path):
		return ""
	for line_value in FileAccess.get_file_as_string(packed_refs_path).split("\n"):
		var line := str(line_value).strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with("^"):
			continue
		var fields := line.split(" ", false)
		if fields.size() >= 2 and fields[1] == reference:
			return fields[0]
	return ""


func _checkout_head(project_root: String) -> String:
	var git_directory := _git_directory(project_root)
	if git_directory.is_empty():
		return ""
	var head_path := git_directory.path_join("HEAD")
	if not FileAccess.file_exists(head_path):
		return ""
	var head_value := FileAccess.get_file_as_string(head_path).strip_edges()
	if head_value.begins_with("ref:"):
		var reference := head_value.trim_prefix("ref:").strip_edges()
		var reference_directories: Array[String] = [git_directory]
		var commondir_path := git_directory.path_join("commondir")
		if FileAccess.file_exists(commondir_path):
			var common_directory := FileAccess.get_file_as_string(commondir_path).strip_edges()
			if not common_directory.is_empty():
				if not common_directory.begins_with("/"):
					common_directory = git_directory.path_join(common_directory)
				reference_directories.append(common_directory.simplify_path())
		for reference_directory in reference_directories:
			var reference_path := reference_directory.path_join(reference)
			if FileAccess.file_exists(reference_path):
				return FileAccess.get_file_as_string(reference_path).strip_edges()
			var packed_commit := _packed_ref(reference_directory, reference)
			if not packed_commit.is_empty():
				return packed_commit
	return head_value


func _sha256_text(value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


func _require_hash(path: String, label: String) -> String:
	if not FileAccess.file_exists(path):
		_fail("%s does not exist: %s" % [label, path])
		return ""
	var digest := FileAccess.get_sha256(path)
	if digest.is_empty():
		_fail("unable to hash %s: %s" % [label, path])
		return ""
	return digest


func _globalize_output_path(value: String) -> String:
	if value.begins_with("res://") or value.begins_with("user://"):
		return ProjectSettings.globalize_path(value).simplify_path()
	return value.simplify_path()


func _load_full_catalog() -> bool:
	catalog_path = OS.get_environment("RICHMAN4_MAP_CATALOG")
	scene_manifest_path = OS.get_environment("RICHMAN4_SCENE_MANIFEST")
	output_root = _globalize_output_path(OS.get_environment("RICHMAN4_NATIVE_CAPTURE_DIR"))
	if catalog_path.is_empty() or scene_manifest_path.is_empty() or output_root.is_empty():
		_fail("RICHMAN4_MAP_CATALOG, RICHMAN4_SCENE_MANIFEST, and RICHMAN4_NATIVE_CAPTURE_DIR are required")
		return false
	catalog_sha256 = _require_hash(catalog_path, "map catalog")
	if catalog_sha256.is_empty():
		return false
	scene_manifest_sha256 = _require_hash(scene_manifest_path, "scene manifest")
	if scene_manifest_sha256.is_empty():
		return false
	var catalog := Maps.load_catalog(catalog_path, true)
	if not bool(catalog.get("ok", false)):
		_fail("pinned map catalog is unavailable: %s" % str(catalog.get("error", "unknown error")))
		return false
	for candidate in catalog.get("maps", []):
		if candidate is Dictionary and str(candidate.get("id", "")) == REQUIRED_SOURCE_MAP:
			definition = candidate
			break
	if definition.is_empty():
		_fail("pinned map catalog does not contain %s" % REQUIRED_SOURCE_MAP)
		return false
	var visuals := OriginalVisuals.new(scene_manifest_path)
	source_scene = visuals.scene_for(definition)
	if source_scene.is_empty():
		_fail("scene manifest does not bind the pinned %s source identity" % REQUIRED_SOURCE_MAP)
		return false
	return true


func _new_source_game() -> Object:
	var game: Object = GameState.new_game_on_board(FIXTURE_SEED, PLAYER_COUNT, definition, FULL_SETUP)
	if game == null:
		return null
	return game


func _valid_save(game: Object, label: String) -> Dictionary:
	var validation: Dictionary = GameState.validate_save(game.to_dict())
	if not bool(validation.get("ok", false)):
		_fail("%s fixture failed validate_save: %s" % [label, str(validation.get("errors", []))])
	return validation


func _prepare_property_fixture() -> Object:
	var game := _new_source_game()
	if game == null:
		_fail("property fixture could not create the pinned source game")
		return null
	var property_index := -1
	for index in range(game.state.board.size()):
		var tile: Dictionary = game.state.board[index] if game.state.board[index] is Dictionary else {}
		if str(tile.get("kind", "")) == "property":
			property_index = index
			break
	if property_index < 0:
		_fail("pinned source map has no ordinary property for HUD fixture")
		return null
	var property_tile: Dictionary = game.state.board[property_index]
	property_tile["owner"] = 0
	property_tile["building_level"] = 2
	game.state.players[0]["properties"] = [property_index]
	game._update_tile_rent(property_tile)
	game._recalculate_property_values()
	game._sync_state()
	_valid_save(game, "property")
	return game


func _prepare_stock_fixture() -> Object:
	var game := _new_source_game()
	if game == null:
		_fail("stock fixture could not create the pinned source game")
		return null
	var player: Dictionary = game.state.players[0]
	var row: Dictionary = game.state.market.rows.get("s01", {})
	if row.is_empty():
		_fail("pinned source map has no s01 market row for HUD fixture")
		return null
	player.stocks["s01"] = 3
	player.stock_average_costs["s01"] = 74.5
	row.market_supply = int(row.market_supply) - 3
	game._update_company_owners()
	game._sync_state()
	_valid_save(game, "stock")
	return game


func _prepare_other_fixture() -> Object:
	var game := _new_source_game()
	if game == null:
		_fail("other fixture could not create the pinned source game")
		return null
	var player: Dictionary = game.state.players[0]
	if game.state.god_objects.is_empty():
		_fail("pinned source map has no god object for HUD fixture")
		return null
	var god: Dictionary = game.state.god_objects[0]
	god.owner = 0
	god.days = 5
	god.node = int(player.position)
	player.god_id = int(god.id)
	player.skip_turns = 2
	game.state.phase = "await_action"
	game.state.action_options = ["end_turn"]
	game._sync_state()
	_valid_save(game, "other")
	return game


func _prepare_game_over_fixture() -> Object:
	var game := _new_source_game()
	if game == null:
		_fail("game-over fixture could not create the pinned source game")
		return null
	game.state.phase = "game_over"
	game.state.winner = 0
	game.state.action_options = []
	game._sync_state()
	_valid_save(game, "game_over")
	return game


func _bind_game(game: Object) -> void:
	if shell != null:
		if bool(shell.get("full_map_visible")):
			shell.call("toggle_full_map_view")
		shell.call("close_player_inspector")
	ui.set("game_state", game)
	ui.set("_active_map_definition", definition)
	ui.call("_refresh_from_state")
	await _settle()


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _money_projection(shell_control: Control, property_name: String) -> String:
	var control := shell_control.get(property_name) as Label
	return control.text if control != null else ""


func _projection(case_id: String, game: Object) -> Dictionary:
	var snapshot: Dictionary = game.get_snapshot()
	var projection: Dictionary = {
		"active_tab": str(shell.get("active_tab")),
		"cash": _money_projection(shell, "cash_label"),
		"deposit": _money_projection(shell, "deposit_label"),
		"wealth": _money_projection(shell, "wealth_label"),
		"property": _money_projection(shell, "property_label"),
		"stock": _money_projection(shell, "stock_label"),
		"other": _money_projection(shell, "other_label"),
	}
	var checks: Dictionary = {}
	var players: Array = snapshot.get("players", [])
	var player: Dictionary = players[0] if not players.is_empty() and players[0] is Dictionary else {}
	if case_id == "property-hud":
		var expected_names: Array[String] = []
		for property_value in player.get("properties", []):
			var index := int(property_value)
			var board: Array = snapshot.get("board", [])
			if index >= 0 and index < board.size() and board[index] is Dictionary:
				expected_names.append(str(board[index].get("name", "")))
		projection["expected_property_names"] = expected_names
		checks["property_names"] = expected_names.all(func(name: String) -> bool: return not name.is_empty() and str(projection.property).contains(name))
		checks["property_level"] = str(projection.property).contains("Lv2")
	elif case_id == "stock-hud":
		var row: Dictionary = snapshot.get("market", {}).get("rows", {}).get("s01", {})
		projection["expected_stock_name"] = str(row.get("name", ""))
		projection["expected_stock_price"] = "$%.2f" % float(row.get("price", 0.0))
		checks["stock_name"] = str(projection.stock).contains(str(projection.expected_stock_name))
		checks["stock_holding"] = str(projection.stock).contains("× 3")
		checks["stock_price"] = str(projection.stock).contains(str(projection.expected_stock_price))
	elif case_id == "other-hud":
		var god_id := int(player.get("god_id", 0))
		projection["expected_god"] = OriginalGods.name_for(god_id)
		projection["expected_status"] = "停留 · %d 回合" % int(player.get("skip_turns", 0))
		checks["god"] = str(projection.other).contains(str(projection.expected_god))
		checks["status"] = str(projection.other).contains(str(projection.expected_status))
	var full_map: Control = shell.get("full_map_view") as Control
	var inspector: Control = shell.get("player_inspect_panel") as Control
	projection["full_map_visible"] = full_map != null and full_map.visible
	projection["full_map_points"] = full_map.call("_board_points").size() if full_map != null else 0
	projection["player_inspector_visible"] = inspector != null and inspector.visible
	projection["player_inspector_players"] = shell.get("player_inspect_buttons").get_child_count() if shell.get("player_inspect_buttons") != null else 0
	var end_overlay: Control = ui.get("end_overlay") as Control
	projection["settlement_visible"] = end_overlay != null and end_overlay.visible
	projection["settlement_z_index"] = end_overlay.z_index if end_overlay != null else -1
	if case_id == "full-map":
		checks["full_map_visible"] = bool(projection.full_map_visible)
		checks["full_map_projects_board"] = int(projection.full_map_points) == int(snapshot.get("board", []).size())
	elif case_id == "player-inspect":
		checks["player_inspector_visible"] = bool(projection.player_inspector_visible)
		checks["player_inspector_players"] = int(projection.player_inspector_players) == players.size()
	elif case_id == "game-over-settlement":
		checks["settlement_visible"] = bool(projection.settlement_visible)
		checks["settlement_above_shell"] = end_overlay != null and end_overlay.z_index > shell.z_index
	projection["checks"] = checks
	return projection


func _write_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("unable to write JSON evidence: %s" % path)
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	return true


func _capture_case(case_id: String, game: Object, action: Callable, source_composition: String) -> void:
	await _bind_game(game)
	var before_render := game.to_json()
	action.call()
	await _settle()
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("render fixture produced an empty image: %s" % case_id)
		return
	var image_path := output_root.path_join("%s.png" % case_id)
	if image.save_png(image_path) != OK:
		_fail("unable to write render fixture: %s" % image_path)
		return
	var serialized: Dictionary = game.to_dict()
	var validation: Dictionary = GameState.validate_save(serialized)
	var after_render := game.to_json()
	var record := {
		"schema": SCHEMA,
		"fixture": true,
		"render_fixture": true,
		"case": case_id,
		"runner": "E/native-101-integrated-repair/capture_runner.gd",
		"input": {
			"mode": "programmatic_control_api",
			"os_input": false,
			"native_ordinary_acceptance": false,
		},
		"source_composition": {
			"status": source_composition,
			"exact_source_composition_accepted": false,
			"source_art_binding": "pinned_scene_manifest_identity_checked",
		},
		"checkout": {"root": checkout_root, "head": checkout_head},
		"sources": {
			"map_catalog": {"path": catalog_path, "sha256": catalog_sha256},
			"scene_manifest": {"path": scene_manifest_path, "sha256": scene_manifest_sha256},
			"map": {
				"id": definition.get("id", ""),
				"source": definition.get("source", {}),
				"scene_source_file_sha256": source_scene.get("source_file_sha256", ""),
				"scene_graph_payload_sha256": source_scene.get("graph_payload_sha256", ""),
			},
			"code": {
				"main_scene_sha256": FileAccess.get_sha256("res://game/main.tscn"),
				"main_ui_sha256": FileAccess.get_sha256("res://game/ui/main_ui.gd"),
				"game_shell_sha256": FileAccess.get_sha256("res://game/ui/game_shell.gd"),
			},
		},
		"fixture_state": {
			"seed": FIXTURE_SEED,
			"player_count": PLAYER_COUNT,
			"phase": serialized.get("phase", ""),
			"current_player": serialized.get("current_player", -1),
			"state_sha256": _sha256_text(after_render),
			"validated_save": validation,
			"state": serialized,
		},
		"projection": _projection(case_id, game),
		"simulation_mutated_by_render": before_render != after_render,
		"image": {"path": image_path, "sha256": FileAccess.get_sha256(image_path), "size": [image.get_width(), image.get_height()]},
	}
	var sidecar_path := output_root.path_join("%s.json" % case_id)
	if _write_json(sidecar_path, record):
		cases.append(record)


func _run() -> void:
	checkout_root = ProjectSettings.globalize_path("res://").trim_suffix("/")
	checkout_head = _checkout_head(checkout_root)
	var head_pattern := RegEx.new()
	head_pattern.compile("^[0-9a-fA-F]{40}$")
	if head_pattern.search(checkout_head) == null:
		_fail("unable to read the actual full checkout HEAD SHA")
		return
	if not _load_full_catalog():
		return
	DirAccess.make_dir_recursive_absolute(output_root)

	viewport = SubViewport.new()
	viewport.name = "Issue101RenderFixtureViewport"
	viewport.size = REFERENCE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	ui = MainScene.instantiate()
	ui.name = "Issue101RenderFixtureMain"
	ui.size = Vector2(REFERENCE_SIZE)
	viewport.add_child(ui)
	await _settle()
	ui.call("_set_development_path", true)
	ui.set_process(false)
	shell = ui.get("source_shell") as Control
	if shell == null:
		_fail("MainScene did not build the source shell")
		return

	var property_game := _prepare_property_fixture()
	await _capture_case("property-hud", property_game, func() -> void: shell.call("select_tab", "property"), "manifest_bound_source_hud_projection")
	var stock_game := _prepare_stock_fixture()
	await _capture_case("stock-hud", stock_game, func() -> void: shell.call("select_tab", "stock"), "manifest_bound_source_hud_projection")
	var other_game := _prepare_other_fixture()
	await _capture_case("other-hud", other_game, func() -> void: shell.call("select_tab", "other"), "manifest_bound_source_hud_projection")
	var map_game := _new_source_game()
	await _capture_case("full-map", map_game, func() -> void: shell.call("toggle_full_map_view"), "unknown_exact_source_composition_marked")
	var inspect_game := _new_source_game()
	await _capture_case("player-inspect", inspect_game, func() -> void: shell.call("open_player_inspector"), "unknown_exact_source_composition_marked")
	var game_over_game := _prepare_game_over_fixture()
	await _capture_case("game-over-settlement", game_over_game, func() -> void: pass, "manifest_bound_source_shell_with_reconstructed_overlay")

	var batch := {
		"schema": SCHEMA,
		"fixture": true,
		"render_fixture": true,
		"native_ordinary_acceptance": false,
		"os_input": false,
		"checkout": {"root": checkout_root, "head": checkout_head},
		"sources": {
			"map_catalog": {"path": catalog_path, "sha256": catalog_sha256},
			"scene_manifest": {"path": scene_manifest_path, "sha256": scene_manifest_sha256},
			"map_id": definition.get("id", ""),
			"map_source": definition.get("source", {}),
		},
		"cases": cases.map(func(value: Dictionary) -> String: return str(value.get("case", ""))),
		"runner": "E/native-101-integrated-repair/capture_runner.gd",
	}
	_write_json(output_root.path_join("batch.json"), batch)
	ui.queue_free()
	viewport.queue_free()
	await process_frame
	quit(0)
