extends "res://game/ui/main_ui.gd"

## Small standalone MainUI host for bank UI tests. When a real catalog is
## supplied it uses the production loader; otherwise it exposes only fixture
## map identities for exercising edition selection and the bank host seam.

const Fixture = preload("res://tests/fixtures/company_fixture.gd")


func _setup_audio() -> void:
	pass


func _load_map_catalog(path: String = "", allow_development_fallback: bool = false) -> void:
	if not OS.get_environment("RICHMAN4_MAP_CATALOG").is_empty():
		super._load_map_catalog(path, allow_development_fallback)
		return
	_map_catalog = []
	for edition in ["Game", "MultiverseJourney"]:
		for number in range(1, 5 if edition == "Game" else 9):
			var definition: Dictionary = Fixture.definition().duplicate(true)
			definition.id = "%s:%d" % [edition, number]
			definition.source.edition = edition
			definition.source.map_number = number
			definition.source.archive = edition + "/map.mkf"
			definition.source.entry_index = number
			_map_catalog.append(definition)
	_map_catalog_complete = _catalog_has_complete_original_content(_map_catalog)
	_map_catalog_ok = _map_catalog_complete
	_selected_map_definition = _map_catalog[0].duplicate(true)
	_update_map_selector()
