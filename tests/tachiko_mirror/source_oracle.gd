extends SceneTree

# Read-only public catalogue witness. No Game instance, private assets or writes.
const Catalogue = preload("res://game/content/original_inventory.gd")

func _initialize() -> void:
	var projection := {
		"card_capacity": Catalogue.CARD_CAPACITY,
		"tool_capacity_per_type": Catalogue.TOOL_CAPACITY_PER_TYPE,
		"cards": Catalogue.cards(),
		"tools": Catalogue.tools(),
	}
	print("RICHMAN4_CATALOG_ORACLE=" + JSON.stringify(projection))
	quit(0)
