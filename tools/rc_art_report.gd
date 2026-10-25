extends SceneTree

## Report which source presenter art a private bundle actually provides.
##
## Usage (headless, no window, no owner userdata):
##   RICHMAN4_USER_ROOT=$(mktemp -d) godot --headless --path . \
##     --script tools/rc_art_report.gd -- /path/to/Contents/Resources/Original
##
## The optional path is the packaged Original directory. When it is omitted the
## existing RICHMAN4_SCENE_MANIFEST is used. Every listed key must resolve to a
## real texture; a missing key makes the report exit non-zero.

const OriginalVisuals = preload("res://game/platform/original_visuals.gd")

const CHECKS := [
	["title", "Data", 1, 0],
	["hud", "Panel", 0, 0],
	["toolbar", "Panel", 1, 0],
	["character_portraits", "Data", 2, 0],
	["calendar", "Panel", 2, 0],
	["setup_atlas", "jump", 4, 0],
	["setup_buttons", "Data", 3, 0],
	["help_icons", "help", 0, 0],
	["bank_calculator", "Panel", 21, 0],
	["bank_front", "Panel", 23, 0],
	["bank_atm", "Panel", 24, 0],
	["monthly_panel", "Panel", 25, 0],
	["monthly_dividend", "Panel", 76, 0],
	["trustee_panel", "Panel", 77, 0],
	["stock_panel", "Panel", 75, 0],
	["shop_panel", "Panel", 10, 0],
	["shop_panel_cart", "Panel", 10, 16],
	["shop_panel_footer", "Panel", 10, 17],
	["shop_held", "Panel", 11, 0],
	["shop_held_rows", "Panel", 11, 15],
	["shop_held_footer", "Panel", 11, 16],
	["sale_board", "Panel", 73, 0],
	["sale_tool_icons", "Panel", 74, 0],
	["sale_confirmation", "Data", 399, 0],
	["lottery_purchase", "Panel", 12, 0],
	["lottery_digits", "Panel", 13, 0],
	["lottery_draw", "Panel", 15, 0],
	["lottery_pool_animation", "Panel", 14, 0],
	["lottery_drum_animation", "Panel", 16, 0],
	["lottery_burst_animation", "Panel", 17, 0],
	["minigame_intro", "Panel", 78, 0],
	["minigame_digits", "Panel", 79, 0],
	["minigame_penguin", "Panel", 80, 0],
	["minigame_walk", "Panel", 82, 0],
	["minigame_balloon", "Panel", 91, 0],
	["minigame_catching", "Panel", 92, 0],
	["minigame_throwers", "Panel", 93, 0],
	["minigame_bomb", "Panel", 94, 0],
	["minigame_items", "Panel", 95, 0],
	["save_load", "Data", 479, 0],
	["loading", "Data", 560, 0],
]

const EDITION_RESOURCES := {
	"setup_atlas": {"Game": 4, "MultiverseJourney": 8},
	"sale_confirmation": {"Game": 399, "MultiverseJourney": 440},
	"save_load": {"Game": 479, "MultiverseJourney": 520},
	"loading": {"Game": 560, "MultiverseJourney": 601},
}

## Minigame presenters query every Panel resource in this range except Panel81,
## which is the click mask rather than artwork.
const MINIGAME_FIRST := 78
const MINIGAME_LAST := 111
const MINIGAME_CLICK_MASK := 81


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var original_root := ""
	if args.size() > 0:
		original_root = str(args[0])
	if not original_root.is_empty():
		OS.set_environment(
			"RICHMAN4_SCENE_MANIFEST",
			original_root.path_join("scenes/manifest.json"),
		)
	var visuals = OriginalVisuals.new()
	if visuals.manifest.is_empty():
		print("ART manifest unavailable")
		quit(1)
		return
	var found := 0
	var missing := 0
	for edition in ["Game", "MultiverseJourney"]:
		for check in CHECKS:
			var presenter: String = check[0]
			var archive: String = check[1]
			var resource: int = int(check[2])
			var chunk: int = int(check[3])
			if EDITION_RESOURCES.has(presenter):
				resource = int(EDITION_RESOURCES[presenter][edition])
			if _check(visuals, edition, presenter, archive, resource, chunk):
				found += 1
			else:
				missing += 1
		for resource in range(MINIGAME_FIRST, MINIGAME_LAST + 1):
			if resource == MINIGAME_CLICK_MASK:
				continue
			if _check(
				visuals, edition, "minigame_%d" % resource, "Panel", resource, 0
			):
				found += 1
			else:
				missing += 1
	if not original_root.is_empty():
		missing += _report_extra(original_root)
	print("SUMMARY\tfound=%d\tfallback=%d\tmaps=%d" % [
		found, missing, visuals.manifest.get("maps", []).size(),
	])
	quit(1 if missing > 0 else 0)


func _check(
	visuals,
	edition: String,
	presenter: String,
	archive: String,
	resource: int,
	chunk: int,
) -> bool:
	var frame: Dictionary = visuals.ui(edition, archive, resource, chunk)
	var texture: Texture2D = visuals.texture(frame)
	var status := "found" if texture != null else "fallback"
	print("ART\t%s\t%s\t%s/%d/%d\t%s" % [
		presenter, edition, archive, resource, chunk, status,
	])
	return texture != null


func _report_extra(original_root: String) -> int:
	var missing := 0
	var catalog_path := original_root.path_join("maps/catalog.json")
	var catalog_status := "missing"
	if FileAccess.file_exists(catalog_path):
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(catalog_path)
		)
		if parsed is Dictionary and parsed.get("maps") is Array:
			if parsed.maps.is_empty():
				catalog_status = "invalid"
			else:
				catalog_status = "maps=%d" % parsed.maps.size()
		else:
			catalog_status = "invalid"
	print("EXTRA\tcatalog\t%s" % catalog_status)
	if not catalog_status.begins_with("maps="):
		missing += 1
	for name in ["help", "audio"]:
		var path := original_root.path_join("%s/manifest.json" % name)
		var status := "missing"
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(path)
			)
			status = "present" if parsed is Dictionary else "invalid"
		print("EXTRA\t%s\t%s" % [name, status])
		if status != "present":
			missing += 1
	return missing
