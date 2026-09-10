class_name Richman4GameState
extends RefCounted

## Deterministic, serializable simulation for the Godot runtime.
##
## The original executable and data files are kept outside this repository. The
## rules below are therefore an explicit provisional reconstruction. They are
## deliberately kept in one small state object so that observed corrections
## can be made without coupling the renderer to the simulation.

const SAVE_VERSION = 1
const GRAPH_SAVE_VERSION = 2
const SETUP_SAVE_VERSION = 3
const INVENTORY_SAVE_VERSION = 4
const FACILITY_SAVE_VERSION = 5
const GODS_SAVE_VERSION = 6
const COMPANY_SAVE_VERSION = 7
const STATUS_SAVE_VERSION = 8
const HAZARD_SAVE_VERSION = 9
const PROPERTY_CARD_SAVE_VERSION = 10
const REMODEL_SAVE_VERSION = 11
const RESEARCH_SAVE_VERSION = 12
const BUILDING_CARD_SAVE_VERSION = 13
const OriginalStockMarket = preload("res://game/core/original_stock_market.gd")
const StockAccounting = preload("res://game/core/stock_accounting.gd")
const RULESET_ID = "richman4_provisional_v1"
const RUNTIME_MAP_SCHEMA = "richman4.runtime-map/v1"
const GRAPH_BOARD_MODE = "graph"
const OriginalMaps = preload("res://game/content/original_maps.gd")
const OriginalInventory = preload("res://game/core/inventory_rules.gd")
const TheftRules = preload("res://game/core/theft_rules.gd")
const OriginalInventoryCatalogue = preload("res://game/content/original_inventory.gd")
const OriginalGods = preload("res://game/content/original_gods.gd")
const EngineeringVehicle = preload("res://game/core/engineering_vehicle.gd")
const NewsEvents = preload("res://game/core/news_events.gd")
const FateEvents = preload("res://game/core/fate_events.gd")
const SleepRules = preload("res://game/core/sleep_rules.gd")
const FinancialRules = preload("res://game/core/financial_cards_rules.gd")
const AllianceRules = preload("res://game/core/alliance_rules.gd")
const AuctionRules = preload("res://game/core/auction_rules.gd")
const MissileRules = preload("res://game/core/missile_rules.gd")
const TimeTransportRules = preload("res://game/core/time_transport_rules.gd")
const BOARD_SIZE = 40
const MIN_PLAYERS = 2
const MAX_PLAYERS = 4
const START_CASH = 15000
const START_POSITION = 0
const MAX_PROPERTY_LEVEL = 5
const FACILITY_TYPE_COUNT = 5
const FACILITY_MAX_LEVELS = [1, 5, 5, 1, 5]
const FACILITY_NAMES = ["公園", "旅館", "購物中心", "加油站", "研究所"]
const FACILITY_RAISED_BASE_STATE = 0x50
const FACILITY_SEALED_BASE_STATE = 0x51
const FACILITY_STATE_STEP = 0x10
const FACILITY_STATE_HIGH_MASK = 0xf0
const FACILITY_STATE_LOW_MASK = 0x0f
const FACILITY_LAB_TYPE = 4
const RESEARCH_TOOL_IDS = ["機器工人", "時光機", "傳送機", "工程車", "核子飛彈"]
const RESEARCH_TOOL_MAX_RANK = 5
const RESEARCH_JOB_TURNS = 5
const FACILITY_SOURCE_TYPE_MIN = 4000
const FACILITY_SOURCE_TYPE_MAX = 5999
const MAX_GRAPH_STEPS = 18
const MAX_AI_TURN_ITERATIONS = 16
const MAX_GRAPH_POINTS = 1000000000000
const MAX_INVENTORY_ROADBLOCKS = 10
const MAX_STATUS_ADMISSION_DAYS = 128
const PASS_START_BONUS = 0 # The reference manual does not support an invented bonus.
const DAYS_PER_MONTH = 30
const MONTHLY_DEPOSIT_RATE = 0.10
const LOAN_TERM_DAYS = 90
const INITIAL_BANK_CASH = 1000000
const INT64_MIN = -9223372036854775808
const INT64_MAX = 9223372036854775807
const MIN_SEED = -2147483648
const MAX_SEED = 2147483647
const SETUP_INITIAL_FUNDS = [300000, 200000, 100000, 50000, 30000, 10000]
const SETUP_DAY_LIMITS = [0, 730, 365, 182, 91, 30]
const SETUP_WEALTH_MULTIPLIERS = [0, 100, 50, 10, 5, 3]
const AI_CASH_RATIOS = [50, 40, 70, 60, 40, 70, 50, 40, 60, 50, 55, 80]
const SETUP_CHARACTER_NAMES = [
	"約翰喬", "沙隆巴斯", "忍太郎", "錢夫人", "阿土伯", "莎拉公主",
	"宮本寶藏", "糖糖", "烏咪", "孫小美", "小丹尼", "金貝貝",
]
const SETUP_CHARACTER_COUNT = 12
const SetupControls = preload("res://game/core/setup_controls.gd")
const LandTenure = preload("res://game/core/land_tenure_rules.gd")
const SETUP_DEFAULT_START_DATE = {"year": 1998, "month": 1, "day": 1}
const GameCalendar = preload("res://game/core/game_calendar.gd")
const SourceLoans = preload("res://game/core/source_loans.gd")
const IMPLEMENTED_CARD_IDS = ["均富", "均貧", "購地", "停留", "轉向", "拆除", "烏龜", "紅", "黑", "漲價", "查封", "搶奪", "免費", "查稅", "拍賣"]
const BUILDING_CARD_IDS = ["天使", "惡魔", "怪獸"]
const GOD_CARD_IDS = ["送神符", "請神符"]
const DISMISS_GOD_IDS = [5, 6, 7, 8, 10]
const AI_SUMMON_GOD_IDS = [1, 2, 3, 4, 12]
const PROPERTY_CARD_IDS = ["換地", "換屋"]
const REMODEL_CARD_ID = "改建"
const STATUS_CARD_IDS = ["陷害", "免罪", "嫁禍", "復仇"]
const IMPLEMENTED_TOOL_IDS = ["機車", "汽車", "路障", "地雷", "定時炸彈", "機器娃娃", "遙控骰子", "機器工人", "時光機", "傳送機", "工程車", "飛彈", "核子飛彈"]
const VEHICLE_TOOL_IDS = {
	"motorcycle": "機車",
	"car": "汽車",
}

const VEHICLE_DICE = {
	"walking": 1,
	"motorcycle": 2,
	"car": 3,
	"engineering": 1,
}
const VEHICLE_COSTS = {
	"walking": 0,
	"motorcycle": 3000,
	"car": 7000,
}

const MAX_GROUND_MINES = 10
const MAX_BOMBS = 10
const MAX_BOMB_STEPS = 38

const STOCK_SYMBOLS = ["tech", "transport", "energy"]
const STOCK_BASE_PRICES = {
	"tech": 120,
	"transport": 100,
	"energy": 80,
}

# Board locations, names, and values are provisional reconstruction data.
const PROPERTY_SPECS = [
	{"index": 1, "name": "和平路", "group": "north", "cost": 1000, "rent": 100, "upgrade_cost": 600},
	{"index": 2, "name": "中山路", "group": "north", "cost": 1200, "rent": 120, "upgrade_cost": 700},
	{"index": 3, "name": "民權路", "group": "north", "cost": 1400, "rent": 140, "upgrade_cost": 800},
	{"index": 5, "name": "忠孝路", "group": "east", "cost": 1600, "rent": 160, "upgrade_cost": 900},
	{"index": 6, "name": "仁愛路", "group": "east", "cost": 1800, "rent": 180, "upgrade_cost": 1000},
	{"index": 7, "name": "信義路", "group": "east", "cost": 2000, "rent": 200, "upgrade_cost": 1100},
	{"index": 9, "name": "復興路", "group": "east", "cost": 2200, "rent": 220, "upgrade_cost": 1200},
	{"index": 10, "name": "敦化路", "group": "east", "cost": 2400, "rent": 240, "upgrade_cost": 1300},
	{"index": 12, "name": "建國路", "group": "south", "cost": 2600, "rent": 260, "upgrade_cost": 1400},
	{"index": 13, "name": "光復路", "group": "south", "cost": 2800, "rent": 280, "upgrade_cost": 1500},
	{"index": 14, "name": "松江路", "group": "south", "cost": 3000, "rent": 300, "upgrade_cost": 1600},
	{"index": 16, "name": "南京路", "group": "south", "cost": 3200, "rent": 320, "upgrade_cost": 1700},
	{"index": 17, "name": "長春路", "group": "south", "cost": 3400, "rent": 340, "upgrade_cost": 1800},
	{"index": 18, "name": "民生路", "group": "south", "cost": 3600, "rent": 360, "upgrade_cost": 1900},
	{"index": 20, "name": "北平路", "group": "west", "cost": 3800, "rent": 380, "upgrade_cost": 2000},
	{"index": 21, "name": "天津路", "group": "west", "cost": 4000, "rent": 400, "upgrade_cost": 2100},
	{"index": 23, "name": "重慶路", "group": "west", "cost": 4200, "rent": 420, "upgrade_cost": 2200},
	{"index": 24, "name": "成都路", "group": "west", "cost": 4400, "rent": 440, "upgrade_cost": 2300},
	{"index": 25, "name": "西寧路", "group": "west", "cost": 4600, "rent": 460, "upgrade_cost": 2400},
	{"index": 27, "name": "華山路", "group": "central", "cost": 4800, "rent": 480, "upgrade_cost": 2500},
	{"index": 28, "name": "八德路", "group": "central", "cost": 5000, "rent": 500, "upgrade_cost": 2600},
	{"index": 29, "name": "光華路", "group": "central", "cost": 5200, "rent": 520, "upgrade_cost": 2700},
	{"index": 31, "name": "基隆路", "group": "central", "cost": 5400, "rent": 540, "upgrade_cost": 2800},
	{"index": 32, "name": "安和路", "group": "central", "cost": 5600, "rent": 560, "upgrade_cost": 2900},
	{"index": 34, "name": "大直路", "group": "harbor", "cost": 5800, "rent": 580, "upgrade_cost": 3000},
	{"index": 35, "name": "士林路", "group": "harbor", "cost": 6000, "rent": 600, "upgrade_cost": 3100},
	{"index": 36, "name": "北投路", "group": "harbor", "cost": 6200, "rent": 620, "upgrade_cost": 3200},
	{"index": 38, "name": "淡水路", "group": "harbor", "cost": 6400, "rent": 640, "upgrade_cost": 3300},
]

const EVENT_CARDS = [
	{"id": "均富", "name": "均富", "kind": "card", "effect": "equalize_cash"},
	{"id": "停留", "name": "停留", "kind": "card", "effect": "stay"},
	{"id": "烏龜", "name": "烏龜", "kind": "card", "effect": "turtle"},
	{"id": "紅", "name": "紅", "kind": "card", "effect": "stock_up"},
	{"id": "黑", "name": "黑", "kind": "card", "effect": "stock_down"},
]

var _settling_company_dividends := false
var _resolving_news := false
var _resolving_fate := false
var _running_sleep_turn := false
var state: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _time_anchors: Dictionary = {}
var _time_anchor_sequence: int = 0


static func new_game(seed_value: int, player_count: int = 4, options: Dictionary = {}) -> Richman4GameState:
	if seed_value < MIN_SEED or seed_value > MAX_SEED:
		return null
	if player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		return null
	if not options.is_empty():
		var setup_options: Dictionary = _normalize_setup_options(options, player_count)
		if setup_options.is_empty() or bool(setup_options.get("original_facilities", false)) or bool(setup_options.get("original_statuses", false)) or bool(setup_options.get("original_hazards", false)) or bool(setup_options.get("original_property_cards", false)) or bool(setup_options.get("original_remodel", false)) or bool(setup_options.get("original_research", false)) or bool(setup_options.get("original_building_cards", false)):
			return null
		var setup_game = new()
		setup_game._initialize_setup(seed_value, player_count, setup_options)
		return setup_game
	var game = new()
	game._initialize(seed_value, player_count)
	return game


static func new_game_on_board(seed_value: int, player_count: int, definition: Dictionary, options: Dictionary = {}) -> Richman4GameState:
	if seed_value < MIN_SEED or seed_value > MAX_SEED:
		return null
	if player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		return null
	if options.has("original_inventory") and typeof(options.get("original_inventory")) != TYPE_BOOL:
		return null
	if options.has("original_facilities") and typeof(options.get("original_facilities")) != TYPE_BOOL:
		return null
	if options.has("original_gods") and typeof(options.get("original_gods")) != TYPE_BOOL:
		return null
	if options.has("original_companies") and typeof(options.get("original_companies")) != TYPE_BOOL:
		return null
	if options.has("original_statuses") and typeof(options.get("original_statuses")) != TYPE_BOOL:
		return null
	if options.has("original_hazards") and typeof(options.get("original_hazards")) != TYPE_BOOL:
		return null
	if options.has("original_property_cards") and typeof(options.get("original_property_cards")) != TYPE_BOOL:
		return null
	if options.has("original_remodel") and typeof(options.get("original_remodel")) != TYPE_BOOL:
		return null
	if options.has("original_research") and typeof(options.get("original_research")) != TYPE_BOOL:
		return null
	if options.has("original_building_cards") and typeof(options.get("original_building_cards")) != TYPE_BOOL:
		return null
	if bool(options.get("original_companies", false)) and not bool(definition.get("supports_original_companies", false)):
		return null
	if bool(options.get("original_statuses", false)) and (typeof(definition.get("supports_original_statuses")) != TYPE_BOOL or not definition.get("supports_original_statuses", false)):
		return null
	if bool(options.get("original_hazards", false)) and (typeof(definition.get("supports_original_hazards")) != TYPE_BOOL or not definition.get("supports_original_hazards", false)):
		return null
	if bool(options.get("original_property_cards", false)) and (typeof(definition.get("supports_original_property_cards")) != TYPE_BOOL or not definition.get("supports_original_property_cards", false)):
		return null
	if bool(options.get("original_remodel", false)) and (typeof(definition.get("supports_original_remodel")) != TYPE_BOOL or not definition.get("supports_original_remodel", false)):
		return null
	if bool(options.get("original_research", false)) and (typeof(definition.get("supports_original_research")) != TYPE_BOOL or not definition.get("supports_original_research", false)):
		return null
	if bool(options.get("original_building_cards", false)) and (typeof(definition.get("supports_original_building_cards")) != TYPE_BOOL or not definition.get("supports_original_building_cards", false)):
		return null
	var original_facilities: bool = bool(options.get("original_facilities", false))
	if definition.has("original_facilities") and typeof(definition.get("original_facilities")) == TYPE_BOOL and bool(definition.get("original_facilities")):
		original_facilities = true
	if original_facilities and options.is_empty():
		return null
	if bool(options.get("original_gods", false)) and not original_facilities:
		return null
	if bool(options.get("original_statuses", false)) and (not original_facilities or not bool(options.get("original_gods", false)) or not bool(options.get("original_companies", false))):
		return null
	if bool(options.get("original_hazards", false)) and (not original_facilities or not bool(options.get("original_gods", false)) or not bool(options.get("original_companies", false)) or not bool(options.get("original_statuses", false))):
		return null
	if bool(options.get("original_property_cards", false)) and (not original_facilities or not bool(options.get("original_inventory", false)) or not bool(options.get("original_gods", false)) or not bool(options.get("original_companies", false)) or not bool(options.get("original_statuses", false)) or not bool(options.get("original_hazards", false))):
		return null
	if bool(options.get("original_remodel", false)) and (not original_facilities or not bool(options.get("original_inventory", false)) or not bool(options.get("original_gods", false)) or not bool(options.get("original_companies", false)) or not bool(options.get("original_statuses", false)) or not bool(options.get("original_hazards", false)) or not bool(options.get("original_property_cards", false))):
		return null
	if bool(options.get("original_research", false)):
		for prerequisite in ["original_inventory", "original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards", "original_property_cards", "original_remodel"]:
			if typeof(options.get(prerequisite, null)) != TYPE_BOOL or not bool(options.get(prerequisite, false)):
				return null
	if bool(options.get("original_building_cards", false)):
		for prerequisite in ["original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards", "original_property_cards", "original_remodel", "original_research"]:
			if typeof(options.get(prerequisite, null)) != TYPE_BOOL or not bool(options.get(prerequisite, false)):
				return null
	if bool(options.get("original_companies", false)) and not _company_definition_errors(definition, player_count).is_empty():
		return null
	var validation: Dictionary = validate_board_definition(definition, original_facilities)
	if not bool(validation.get("ok", false)):
		return null
	if not options.is_empty():
		var effective_options: Dictionary = options.duplicate(true)
		if original_facilities:
			effective_options["original_facilities"] = true
			effective_options["original_inventory"] = true
		var setup_options: Dictionary = _normalize_setup_options(effective_options, player_count)
		if setup_options.is_empty():
			return null
		var setup_game = new()
		setup_game._initialize_graph_setup(seed_value, player_count, validation["definition"], setup_options)
		return setup_game
	var game := new()
	game._initialize_graph(seed_value, player_count, validation["definition"])
	return game


static func _normalize_setup_options(options: Dictionary, player_count: int) -> Dictionary:
	var allowed_keys: Array = ["initial_fund", "day_limit", "wealth_multiplier", "start_date", "character_ids", "human_flags", "initial_vehicle", "land_tenure_months", "original_inventory", "original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards", "original_property_cards", "original_remodel", "original_research", "original_building_cards"]
	for key in options.keys():
		# Dictionary dot assignment produces StringName keys in Godot. Treat
		# those keys as their canonical string spelling so callers that adjust a
		# normalized setup dictionary keep the same validation path.
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not allowed_keys.has(str(key)):
			return {}
	var control_choices: Dictionary = SetupControls.normalize(options, player_count)
	if not bool(control_choices.get("ok", false)):
		return {}
	if options.has("land_tenure_months") and not LandTenure.valid_months(options.land_tenure_months):
		return {}
	if not options.has("start_date") or typeof(options.get("start_date")) != TYPE_DICTIONARY:
		return {}
	var start_date: Dictionary = options["start_date"]
	var normalized_start_date: Dictionary = _canonical_setup_date(start_date)
	if normalized_start_date.is_empty():
		return {}

	var initial_fund: int = 200000
	if options.has("initial_fund"):
		var fund_value: Variant = options["initial_fund"]
		if not _valid_int(fund_value) or not SETUP_INITIAL_FUNDS.has(int(fund_value)):
			return {}
		initial_fund = int(fund_value)
	var day_limit: int = 0
	if options.has("day_limit"):
		var limit_value: Variant = options["day_limit"]
		if not _valid_int(limit_value) or not SETUP_DAY_LIMITS.has(int(limit_value)):
			return {}
		day_limit = int(limit_value)
	var wealth_multiplier: int = 0
	if options.has("wealth_multiplier"):
		var multiplier_value: Variant = options["wealth_multiplier"]
		if not _valid_int(multiplier_value) or not SETUP_WEALTH_MULTIPLIERS.has(int(multiplier_value)):
			return {}
		wealth_multiplier = int(multiplier_value)

	var character_ids: Array = []
	if options.has("character_ids"):
		var character_value: Variant = options["character_ids"]
		if typeof(character_value) != TYPE_ARRAY or character_value.size() != player_count:
			return {}
		var seen_characters: Dictionary = {}
		for character_id in character_value:
			if not _valid_int(character_id, 0, SETUP_CHARACTER_COUNT - 1):
				return {}
			var normalized_character_id: int = int(character_id)
			if seen_characters.has(normalized_character_id):
				return {}
			seen_characters[normalized_character_id] = true
			character_ids.append(normalized_character_id)
	else:
		for player_id in range(player_count):
			character_ids.append(player_id)
	var original_inventory: bool = false
	if options.has("original_inventory"):
		if typeof(options["original_inventory"]) != TYPE_BOOL:
			return {}
		original_inventory = bool(options["original_inventory"])
	var original_facilities: bool = false
	if options.has("original_facilities"):
		if typeof(options["original_facilities"]) != TYPE_BOOL:
			return {}
		original_facilities = bool(options["original_facilities"])
	if original_facilities:
		original_inventory = true
	var original_gods: bool = false
	if options.has("original_gods"):
		if typeof(options["original_gods"]) != TYPE_BOOL:
			return {}
		original_gods = bool(options["original_gods"])
	if original_gods and not original_facilities:
		return {}
	if options.has("original_companies") and typeof(options.original_companies) != TYPE_BOOL:
		return {}
	var original_companies: bool = bool(options.get("original_companies", false))
	if original_companies and not original_gods:
		return {}
	if options.has("original_statuses") and typeof(options["original_statuses"]) != TYPE_BOOL:
		return {}
	var original_statuses: bool = bool(options.get("original_statuses", false))
	if original_statuses and (not original_facilities or not original_gods or not original_companies):
		return {}
	var original_hazards: bool = false
	if options.has("original_hazards"):
		if typeof(options["original_hazards"]) != TYPE_BOOL:
			return {}
		original_hazards = bool(options["original_hazards"])
	if original_hazards and (not original_facilities or not original_gods or not original_companies or not original_statuses):
		return {}
	var original_property_cards: bool = false
	if options.has("original_property_cards"):
		if typeof(options["original_property_cards"]) != TYPE_BOOL:
			return {}
		original_property_cards = bool(options["original_property_cards"])
	if original_property_cards and (not original_inventory or not original_facilities or not original_gods or not original_companies or not original_statuses or not original_hazards):
		return {}
	var original_remodel: bool = false
	if options.has("original_remodel"):
		if typeof(options["original_remodel"]) != TYPE_BOOL:
			return {}
		original_remodel = bool(options["original_remodel"])
	if original_remodel and (not original_inventory or not original_facilities or not original_gods or not original_companies or not original_statuses or not original_hazards or not original_property_cards):
		return {}
	var original_research: bool = false
	if options.has("original_research"):
		if typeof(options["original_research"]) != TYPE_BOOL:
			return {}
		original_research = bool(options["original_research"])
	if original_research and (not original_inventory or not original_facilities or not original_gods or not original_companies or not original_statuses or not original_hazards or not original_property_cards or not original_remodel):
		return {}
	var original_building_cards: bool = false
	if options.has("original_building_cards"):
		if typeof(options["original_building_cards"]) != TYPE_BOOL:
			return {}
		original_building_cards = bool(options["original_building_cards"])
	if original_building_cards and (not original_inventory or not original_facilities or not original_gods or not original_companies or not original_statuses or not original_hazards or not original_property_cards or not original_remodel or not original_research):
		return {}

	var normalized: Dictionary = {
		"initial_fund": initial_fund,
		"day_limit": day_limit,
		"wealth_multiplier": wealth_multiplier,
		"start_date": normalized_start_date,
		"character_ids": character_ids,
		"original_inventory": original_inventory,
		"original_facilities": original_facilities,
		"original_gods": original_gods,
		"original_companies": original_companies,
		"original_statuses": original_statuses,
		"original_hazards": original_hazards,
		"original_property_cards": original_property_cards,
		"original_remodel": original_remodel,
		"original_research": original_research,
		"original_building_cards": original_building_cards,
	}
	normalized.merge(control_choices.choices)
	if options.has("land_tenure_months"):
		normalized["land_tenure_months"] = int(options.land_tenure_months)
	return normalized


func _initialize_setup(seed_value: int, player_count: int, options: Dictionary) -> void:
	_initialize(seed_value, player_count)
	_configure_setup(options, player_count)


func _initialize_graph_setup(seed_value: int, player_count: int, definition: Dictionary, options: Dictionary) -> void:
	_initialize_graph(seed_value, player_count, definition)
	_configure_setup(options, player_count)
	if bool(options.get("original_companies", false)):
		_initialize_original_companies(definition)


func _configure_setup(options: Dictionary, player_count: int) -> void:
	var original_facilities: bool = bool(options.get("original_facilities", false))
	var original_gods: bool = bool(options.get("original_gods", false))
	state["version"] = BUILDING_CARD_SAVE_VERSION if bool(options.get("original_building_cards", false)) else RESEARCH_SAVE_VERSION if bool(options.get("original_research", false)) else REMODEL_SAVE_VERSION if bool(options.get("original_remodel", false)) else PROPERTY_CARD_SAVE_VERSION if bool(options.get("original_property_cards", false)) else HAZARD_SAVE_VERSION if bool(options.get("original_hazards", false)) else STATUS_SAVE_VERSION if bool(options.get("original_statuses", false)) else COMPANY_SAVE_VERSION if bool(options.get("original_companies", false)) else GODS_SAVE_VERSION if original_gods else FACILITY_SAVE_VERSION if original_facilities else INVENTORY_SAVE_VERSION if bool(options.get("original_inventory", false)) else SETUP_SAVE_VERSION
	state["original_facilities"] = original_facilities
	state["original_gods"] = original_gods
	if bool(options.get("original_companies", false)):
		state["original_companies"] = true
	if bool(options.get("original_statuses", false)):
		state["original_statuses"] = true
	if bool(options.get("original_hazards", false)):
		state["original_hazards"] = true
	if bool(options.get("original_property_cards", false)):
		state["original_property_cards"] = true
	if bool(options.get("original_remodel", false)):
		state["original_remodel"] = true
	if bool(options.get("original_research", false)):
		state["original_research"] = true
		state["research_action_used"] = false
	if bool(options.get("original_building_cards", false)):
		state["original_building_cards"] = true
	if original_facilities:
		state["price_index"] = 1
		state["last_roll_total"] = 0
	state["initial_fund"] = int(options["initial_fund"])
	state["day_limit"] = int(options["day_limit"])
	state["wealth_multiplier"] = int(options["wealth_multiplier"])
	state["start_date"] = options["start_date"].duplicate(true)
	state["date"] = options["start_date"].duplicate(true)
	state["elapsed"] = 0
	state["last_settled_month"] = {}
	state["character_ids"] = options["character_ids"].duplicate(true)
	if options.has("human_flags"):
		state["initial_human_flags"] = options.human_flags.duplicate()
	if options.has("initial_vehicle"):
		state["initial_vehicle"] = options.initial_vehicle
	var start_position: int = int(state.get("start_position", START_POSITION))
	state["players"] = _build_setup_players(
		player_count,
		int(options["initial_fund"]),
		options["character_ids"],
		start_position,
		_is_graph(),
		options.get("human_flags", []),
	)
	if bool(options.get("original_statuses", false)):
		for player in state["players"]:
			player["prison_days"] = 0
		state["pending_trap"] = {}
	if _is_hazards():
		for player in state["players"]:
			player["bomb_steps"] = 0
	var total_deposits: int = 0
	for player in state["players"]:
		total_deposits += int(player.get("deposit", 0))
	var bank: Dictionary = state.get("bank", {})
	bank["deposits"] = total_deposits
	state["bank"] = bank
	if _is_inventory():
		state["inventory_supply"] = OriginalInventory.new_supply()
		state["pending_remote_dice"] = {}
		state["roadblocks"] = {}
		if _is_hazards():
			state["ground_hazards"] = {}
		var inventory_result: Dictionary = OriginalInventory.initialize_players(state["players"], state["inventory_supply"])
		if not bool(inventory_result.get("ok", false)):
			state = {}
			return
	if options.has("initial_vehicle") and not SetupControls.apply_vehicle(state.players, state.get("inventory_supply", {}), options.initial_vehicle, _is_inventory()):
		state = {}
		return
	if original_gods:
		_initialize_original_gods()
	if bool(options.get("original_remodel", false)):
		# Source maps are immutable definitions; a fresh v11 game always starts
		# with ordinary housing regardless of any source-side byte value.
		for tile_value in state.get("board", []):
			if typeof(tile_value) == TYPE_DICTIONARY and tile_value.get("kind", "") == "property":
				tile_value["is_chain_store"] = false
	if bool(options.get("original_research", false)):
		for tile_value in state.get("board", []):
			if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility":
				continue
			tile_value["research_tool"] = 0
			tile_value["research_turns"] = 0
	LandTenure.initialize(state, options)
	_sync_state()
	_set_action_options(0)


func _build_setup_players(
	player_count: int,
	initial_fund: int,
	character_ids: Array,
	start_position: int,
	graph_mode: bool,
	human_flags: Array = [],
) -> Array:
	var players: Array = _build_players(player_count, start_position, graph_mode)
	for player_id in range(player_count):
		var player: Dictionary = players[player_id]
		var character_id: int = int(character_ids[player_id])
		var human: bool = SetupControls.initially_human(human_flags, player_id)
		var cash_ratio: int = 50 if human else int(AI_CASH_RATIOS[character_id])
		player["is_human"] = human
		player["is_ai"] = not human
		player["character_id"] = character_id
		player["name"] = SETUP_CHARACTER_NAMES[character_id]
		player["init_cash_ratio"] = cash_ratio
		player["cash"] = int(float(initial_fund * cash_ratio) / 100.0)
		player["deposit"] = initial_fund - int(player["cash"])
	return players


func _is_setup() -> bool:
	return int(state.get("version", 0)) in [SETUP_SAVE_VERSION, INVENTORY_SAVE_VERSION, FACILITY_SAVE_VERSION, GODS_SAVE_VERSION, COMPANY_SAVE_VERSION, STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION]


func _is_inventory() -> bool:
	return int(state.get("version", 0)) in [INVENTORY_SAVE_VERSION, FACILITY_SAVE_VERSION, GODS_SAVE_VERSION, COMPANY_SAVE_VERSION, STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION]


func _is_facilities() -> bool:
	return int(state.get("version", 0)) in [FACILITY_SAVE_VERSION, GODS_SAVE_VERSION, COMPANY_SAVE_VERSION, STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION]


func _is_gods() -> bool:
	return int(state.get("version", 0)) in [GODS_SAVE_VERSION, COMPANY_SAVE_VERSION, STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_gods", false))


func _initialize(seed_value: int, player_count: int) -> void:
	_rng.seed = seed_value
	_time_anchors.clear()
	_time_anchor_sequence = 0
	state = {
		"version": SAVE_VERSION,
		"ruleset": RULESET_ID,
		"seed": seed_value,
		"seed_text": str(seed_value),
		"rng_state": int(_rng.state),
		"phase": "await_roll",
		"turn": 1,
		"round": 1,
		"day": 1,
		"month": 1,
		"day_of_month": 1,
		"weekday": 1,
		"current_player": 0,
		"winner": -1,
		"last_roll": [],
		"last_total": 0,
		"last_event": {},
		"event_log": [],
		"action_options": [],
		"extra_roll": false,
		"doubles_count": 0,
		"property_action_used": false,
		"bank_access": false,
		"bank_landing": false,
		"bank": {
			"cash": INITIAL_BANK_CASH,
			"deposits": 0,
			"loans": 0,
		},
		"market": {
			"prices": STOCK_BASE_PRICES.duplicate(true),
			"open": true,
			"trends": {},
		},
		"board": _build_board(),
		"players": _build_players(player_count),
		"bankruptcy_auctions": [],
	}
	_sync_state()
	_set_action_options(0)
	_record_event("new_game", {"seed": seed_value, "player_count": player_count})


func _initialize_graph(seed_value: int, player_count: int, definition: Dictionary) -> void:
	_rng.seed = seed_value
	_time_anchors.clear()
	_time_anchor_sequence = 0
	var start_position: int = int(definition.get("start_position", 0))
	var board_value: Variant = _canonicalize_json_numbers(definition.get("board", []).duplicate(true))
	var board: Array = board_value
	var map_source_value: Variant = _canonicalize_json_numbers(definition.get("source", {}).duplicate(true))
	var map_source: Dictionary = map_source_value
	state = {
		"version": GRAPH_SAVE_VERSION,
		"ruleset": RULESET_ID,
		"seed": seed_value,
		"seed_text": str(seed_value),
		"rng_state": int(_rng.state),
		"phase": "await_roll",
		"turn": 1,
		"round": 1,
		"day": 1,
		"month": 1,
		"day_of_month": 1,
		"weekday": 1,
		"current_player": 0,
		"winner": -1,
		"last_roll": [],
		"last_total": 0,
		"last_event": {},
		"event_log": [],
		"action_options": [],
		"extra_roll": false,
		"doubles_count": 0,
		"property_action_used": false,
		"bank_access": false,
		"bank_landing": false,
		"bank": {
			"cash": INITIAL_BANK_CASH,
			"deposits": 0,
			"loans": 0,
		},
		"market": {
			"prices": STOCK_BASE_PRICES.duplicate(true),
			"open": true,
			"trends": {},
		},
		"board_mode": GRAPH_BOARD_MODE,
		"map_id": str(definition.get("id", "")),
		"map_name": str(definition.get("name", "")),
		"map_schema": str(definition.get("schema", RUNTIME_MAP_SCHEMA)),
		"map_version": int(definition.get("version", 1)),
		"map_source": map_source,
		"start_position": start_position,
		"board": board,
		"players": _build_players(player_count, start_position, true),
		"bankruptcy_auctions": [],
		"route_options": [],
		"remaining_steps": 0,
		"pending_movement": {},
	}
	_sync_state()
	_set_action_options(0)
	_record_event("new_game", {"seed": seed_value, "player_count": player_count, "map_id": state["map_id"]})


func _build_players(player_count: int, start_position: int = START_POSITION, graph_mode: bool = false) -> Array:
	var players: Array = []
	for player_id in range(player_count):
		var player: Dictionary = {
			"id": player_id,
			"name": "玩家 %d" % (player_id + 1),
			"is_human": player_id == 0,
			"is_ai": player_id != 0,
			"alive": true,
			"bankrupt": false,
			"cash": START_CASH,
			"deposit": 0,
			"position": start_position,
			"properties": [],
			"property_values": 0,
			"stocks": {"tech": 0, "transport": 0, "energy": 0},
			"cards": [],
			"vehicle": "walking",
			"dice_count": 1,
			"vehicles": {"walking": true, "motorcycle": false, "car": false},
			"skip_turns": 0,
			"rent_shield": 0,
			"turtle_days": 0,
			"stay_next": 0,
			"loan": 0,
			"loan_due_day": 0,
			"turns_taken": 0,
			"god_id": 0,
			"hospital_days": 0,
		}
		if graph_mode:
			player["previous_position"] = -1
			player["points"] = 0
		players.append(player)
	return players


func _is_companies() -> bool:
	return int(state.get("version", 0)) in [COMPANY_SAVE_VERSION, STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_companies", false))


func _is_statuses() -> bool:
	return int(state.get("version", 0)) in [STATUS_SAVE_VERSION, HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_statuses", false))


func _is_hazards() -> bool:
	return int(state.get("version", 0)) in [HAZARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_hazards", false))


func _is_property_cards() -> bool:
	return int(state.get("version", 0)) in [PROPERTY_CARD_SAVE_VERSION, REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_property_cards", false))


func _is_remodel() -> bool:
	return int(state.get("version", 0)) in [REMODEL_SAVE_VERSION, RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_remodel", false))


func _is_research() -> bool:
	return int(state.get("version", 0)) in [RESEARCH_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION] and bool(state.get("original_research", false))


func _is_building_cards() -> bool:
	return int(state.get("version", 0)) == BUILDING_CARD_SAVE_VERSION and bool(state.get("original_building_cards", false))


func _status_key(kind: String) -> String:
	return "hospital_days" if kind == "hospital" else "prison_days" if kind == "prison" else ""


func _status_type(kind: String) -> int:
	return 8001 if kind == "hospital" else 8002 if kind == "prison" else -1


func _status_node_index(kind: String) -> int:
	return _status_node_index_in_board(state.get("board", null), kind) if _is_statuses() else -1


static func _status_node_index_in_board(board: Variant, kind: String) -> int:
	var wanted: int = 8001 if kind == "hospital" else 8002 if kind == "prison" else -1
	if typeof(board) != TYPE_ARRAY or wanted < 0:
		return -1
	var result: int = -1
	for index in range(board.size()):
		if typeof(board[index]) == TYPE_DICTIONARY and _valid_int(board[index].get("type_and_idx", null), wanted, wanted):
			result = index
	return result


func _status_active(player: Dictionary, kind: String = "") -> bool:
	if player.is_empty():
		return false
	if kind == "hospital":
		return int(player.get("hospital_days", 0)) > 0
	if kind == "prison":
		return _is_statuses() and int(player.get("prison_days", 0)) > 0
	return int(player.get("hospital_days", 0)) > 0 or (_is_statuses() and int(player.get("prison_days", 0)) > 0)


func _sleep_winter_active(player: Dictionary) -> bool:
	return not player.is_empty() and SleepRules.is_active(player.get("winter_sleep_days", 0))


func _sleep_dream_active(player: Dictionary) -> bool:
	return not player.is_empty() and SleepRules.is_active(player.get("dream_days", 0))


func _sleep_active(player: Dictionary) -> bool:
	return _sleep_winter_active(player) or _sleep_dream_active(player)


func _sleep_kind(player: Dictionary) -> String:
	if _sleep_winter_active(player):
		return "winter"
	if _sleep_dream_active(player):
		return "dream"
	return ""


func _loan_block_active(player: Dictionary) -> bool:
	# The source counter uses 1..127 as the active refusal window.  128 is a
	# retained release marker and therefore intentionally permits a new loan.
	var marker: Variant = player.get("loan_block_days", 0)
	return _valid_int(marker, 1, 127)


func _admit_loan_block(player: Dictionary) -> void:
	if player.is_empty() or not player.has("loan_block_days"):
		return
	var marker: Variant = player.get("loan_block_days", 0)
	if not _valid_int(marker, 0, 128):
		return
	var current: int = int(marker)
	if current == 1:
		player["loan_block_days"] = 128
	elif current == 128:
		player["loan_block_days"] = 0
	elif current > 1:
		player["loan_block_days"] = current - 1


func _pending_trap() -> Dictionary:
	if not _is_statuses():
		return {}
	var value: Variant = state.get("pending_trap", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _pending_trap_card() -> String:
	var value: Variant = state.get("pending_trap_card", "")
	return str(value) if typeof(value) == TYPE_STRING and str(value) == SleepRules.DREAM_CARD else ""


func _pending_finance() -> Dictionary:
	var value: Variant = state.get("pending_finance", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func financial_response() -> Dictionary:
	return FinancialRules.response(self)


func auction_response() -> Dictionary:
	return AuctionRules.response(self)


func tax_target_players(caster_id: int) -> Array:
	return FinancialRules.tax_target_players(self, caster_id)


func alliance_target_players(caster_id: int) -> Array:
	return AllianceRules.target_players(self, caster_id)


func _trap_pending() -> bool:
	return not _pending_trap().is_empty()


func trap_target_players(caster_id: int) -> Array:
	# The attack target list is deliberately limited to living, non-detained
	# players.  It contains only runtime players, so source/NPC actors can never
	# become card targets.
	var targets: Array = []
	if not _is_statuses() or not _valid_player(caster_id, true):
		return targets
	for player in _players():
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var target_id_value: Variant = player.get("id", null)
		if not _valid_int(target_id_value) or int(target_id_value) == caster_id:
			continue
		if not bool(player.get("alive", false)) or _status_active(player):
			continue
		targets.append(int(target_id_value))
	targets.sort()
	return targets


func dream_target_players(caster_id: int) -> Array:
	return SleepRules.dream_target_players(self, caster_id)


func _resolve_sleep_direct(target_id: int, days: int, trigger_revenge: bool = false, caster_id: int = -1) -> Dictionary:
	return SleepRules._resolve_sleep_direct(self, target_id, days, trigger_revenge, caster_id)


func run_sleep_turn() -> Dictionary:
	if _running_sleep_turn:
		return _error("睡眠回合已在執行")
	_running_sleep_turn = true
	var result: Dictionary = SleepRules.run_turn(self)
	_running_sleep_turn = false
	return result


func _release_status_marker(player_id: int, status_kind: String) -> void:
	var player: Dictionary = _player(player_id)
	if player.is_empty():
		return
	var status_key: String = _status_key(status_kind)
	if status_key.is_empty():
		return
	player[status_key] = 0
	state["last_roll"] = []
	state["last_total"] = 0
	state["extra_roll"] = false
	state["doubles_count"] = 0
	state["property_action_used"] = false
	state["bank_access"] = false
	state["bank_landing"] = false
	if _is_facilities():
		state["last_roll_total"] = 0
	_sync_attached_gods()
	_record_event("status_released", {"player_id": player_id, "status_kind": status_kind, "node": int(player.get("position", -1))})


func _ai_trap_target(caster_id: int) -> int:
	for target_id in trap_target_players(caster_id):
		if not _trap_has_card(_player(int(target_id)), "復仇"):
			return int(target_id)
	return -1


## Public inventory choices for the current 搶奪 card action.  The picker
## filters these legal records by visible board nodes; the core validates the
## selected identity again when the action is confirmed.
func theft_choices(player_id: int = -1) -> Array:
	if not _is_inventory():
		return []
	var actor_id: int = int(state.get("current_player", -1)) if player_id < 0 else player_id
	return TheftRules.choices(_players(), actor_id)


func trap_response_targets() -> Array:
	# A scapegoat may point at any other living player, including the caster or
	# a player currently detained.  Detention is resolved by the final direct
	# admission and never recursively invokes another trap defense.
	var targets: Array = []
	if not _is_statuses():
		return targets
	var pending: Dictionary = _pending_trap()
	if pending.size() != 2 or not pending.has("caster_id") or not pending.has("target_id"):
		return targets
	var original_target_value: Variant = pending.get("target_id", null)
	if typeof(original_target_value) != TYPE_INT:
		return targets
	var original_target_id: int = int(original_target_value)
	if _player(original_target_id).is_empty():
		return targets
	for player in _players():
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var target_id_value: Variant = player.get("id", null)
		if typeof(target_id_value) != TYPE_INT or int(target_id_value) == original_target_id:
			continue
		if bool(player.get("alive", false)):
			targets.append(int(target_id_value))
	targets.sort()
	return targets


func _trap_cards(player: Dictionary) -> Array:
	var cards: Variant = player.get("cards", [])
	return cards if typeof(cards) == TYPE_ARRAY else []


func _trap_has_card(player: Dictionary, card_id: String) -> bool:
	return _trap_cards(player).has(card_id)


func _trap_consume_card(player_id: int, card_id: String) -> bool:
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not _trap_has_card(player, card_id):
		return false
	var consumed: Dictionary = OriginalInventory.consume_card(state.get("inventory_supply", {}), player["cards"], card_id)
	return bool(consumed.get("ok", false))


func _trap_valid_pending_context(require_human_target: bool = true) -> bool:
	if not _is_statuses():
		return false
	var pending: Dictionary = _pending_trap()
	if pending.size() != 2 or not pending.has("caster_id") or not pending.has("target_id"):
		return false
	var caster_value: Variant = pending.get("caster_id", null)
	var target_value: Variant = pending.get("target_id", null)
	if typeof(caster_value) != TYPE_INT or typeof(target_value) != TYPE_INT:
		return false
	var dream_pending: bool = not _pending_trap_card().is_empty()
	var caster: Dictionary = _player(int(caster_value))
	var target: Dictionary = _player(int(target_value))
	if caster.is_empty() or target.is_empty() or (not dream_pending and int(caster_value) == int(target_value)):
		return false
	if not bool(caster.get("alive", false)) or not bool(target.get("alive", false)):
		return false
	if int(state.get("current_player", -1)) != int(caster_value):
		return false
	if _status_active(caster):
		return false
	if require_human_target and (not bool(target.get("is_human", false)) or bool(target.get("is_ai", false))):
		return false
	if _status_active(target):
		return false
	if not _trap_has_card(target, "嫁禍") or _trap_has_card(target, "免罪"):
		return false
	var pending_remote: Variant = state.get("pending_remote_dice", {})
	if typeof(pending_remote) != TYPE_DICTIONARY or not pending_remote.is_empty():
		return false
	var phase: String = str(state.get("phase", ""))
	return phase in ["await_roll", "await_action"]


func _resolve_trap_direct(target_id: int, days: int, trigger_revenge: bool = false, caster_id: int = -1) -> Dictionary:
	# This path intentionally calls the status admission primitive directly;
	# redirected targets do not get another immunity, scapegoat, or revenge
	# decision.
	var target: Dictionary = _player(target_id)
	if target.is_empty() or not bool(target.get("alive", false)) or not _valid_int(days, 1, MAX_STATUS_ADMISSION_DAYS):
		return _error("陷害卡目標無效")
	var admission: Dictionary = _admit_player_status(target_id, "prison", days)
	if not bool(admission.get("ok", false)):
		return admission
	if trigger_revenge and caster_id >= 0 and _trap_has_card(target, "復仇"):
		if not _trap_consume_card(target_id, "復仇"):
			return _error("復仇卡無法使用")
		_record_event("trap_revenge", {"caster_id": caster_id, "target_id": target_id})
		var revenge_admission: Dictionary = _admit_player_status(caster_id, "prison", 5)
		if not bool(revenge_admission.get("ok", false)):
			return revenge_admission
	return admission


func _respond_trap(params: Dictionary) -> Dictionary:
	if not _trap_valid_pending_context(true):
		return _error("陷害卡回應已失效")
	var pending: Dictionary = _pending_trap()
	var caster_id: int = int(pending["caster_id"])
	var original_target_id: int = int(pending["target_id"])
	var dream_pending: bool = not _pending_trap_card().is_empty()
	var has_cancel: bool = params.has("cancel")
	if has_cancel and typeof(params.get("cancel")) != TYPE_BOOL:
		return _error("陷害卡回應格式無效")
	var cancel: bool = has_cancel and bool(params.get("cancel", false))
	if has_cancel and cancel:
		state["pending_trap"] = {}
		state.erase("pending_trap_card")
		var direct_result: Dictionary = _resolve_sleep_direct(original_target_id, 4 if dream_pending and original_target_id == caster_id else 5, dream_pending, caster_id) if dream_pending else _resolve_trap_direct(original_target_id, 5, true, caster_id)
		if not bool(direct_result.get("ok", false)):
			return direct_result
		_record_event("trap_resolved", {"caster_id": caster_id, "target_id": original_target_id, "redirected": false, "card_id": SleepRules.DREAM_CARD if dream_pending else "陷害"})
		_set_action_options(int(state.get("current_player", -1)))
		return _result(true, "已接受夢遊狀態" if dream_pending else "已接受陷害處罰", {"target_id": original_target_id, "redirected": false})
	if has_cancel and not cancel and not params.has("target_id"):
		return _error("陷害卡回應缺少目標")
	var response_target_value: Variant = params.get("target_id", null)
	if typeof(response_target_value) != TYPE_INT:
		return _error("陷害卡目標格式無效")
	var response_target_id: int = int(response_target_value)
	if not trap_response_targets().has(response_target_id):
		return _error("陷害卡目標無效")
	# Validate the destination before consuming 嫁禍 or clearing the pending
	# record, keeping malformed responses atomic.
	var destination: Dictionary = _player(response_target_id)
	if destination.is_empty() or not bool(destination.get("alive", false)):
		return _error("陷害卡目標無效")
	if not _trap_consume_card(original_target_id, "嫁禍"):
		return _error("嫁禍卡無法使用")
	state["pending_trap"] = {}
	state.erase("pending_trap_card")
	var days: int = 4 if response_target_id == caster_id else 5
	var direct_result: Dictionary = _resolve_sleep_direct(response_target_id, days) if dream_pending else _resolve_trap_direct(response_target_id, days)
	if not bool(direct_result.get("ok", false)):
		return direct_result
	_record_event("trap_redirected", {"caster_id": caster_id, "from_target_id": original_target_id, "target_id": response_target_id, "days": days, "card_id": SleepRules.DREAM_CARD if dream_pending else "陷害"})
	_set_action_options(int(state.get("current_player", -1)))
	return _result(true, "已將夢遊狀態轉移" if dream_pending else "已將陷害處罰轉移", {"target_id": response_target_id, "redirected": true, "days": days})


func _use_trap_card(player_id: int, target_id: int, cancel: bool = false) -> Dictionary:
	var caster: Dictionary = _player(player_id)
	if caster.is_empty() or not bool(caster.get("alive", false)):
		return _error("目前玩家無法使用陷害卡")
	if not _trap_has_card(caster, "陷害"):
		return _error("沒有這張卡片")
	if cancel:
		return _result(true, "已取消陷害卡")
	if not trap_target_players(player_id).has(target_id):
		return _error("陷害卡目標無效")
	var target: Dictionary = _player(target_id)
	# The attack card is consumed before any defense card is inspected.
	if not _trap_consume_card(player_id, "陷害"):
		return _error("陷害卡無法使用")
	_record_event("card_used", {"player_id": player_id, "card_id": "陷害", "target_id": target_id, "effect": "trap"})
	if _trap_has_card(target, "免罪"):
		if not _trap_consume_card(target_id, "免罪"):
			return _error("免罪卡無法使用")
		_record_event("trap_blocked", {"caster_id": player_id, "target_id": target_id})
		_set_action_options(player_id)
		return _result(true, "免罪卡抵銷陷害", {"blocked": true, "target_id": target_id})
	if _trap_has_card(target, "嫁禍"):
		if bool(target.get("is_human", false)) and not bool(target.get("is_ai", false)):
			state["pending_trap"] = {"caster_id": player_id, "target_id": target_id}
			state["action_options"] = ["respond_trap"]
			_record_event("trap_response_requested", {"caster_id": player_id, "target_id": target_id})
			return _result(true, "等待嫁禍卡回應", {"awaiting_response": true, "target_id": target_id})
		var response_targets: Array = []
		for candidate in _players():
			if typeof(candidate) != TYPE_DICTIONARY or int(candidate.get("id", -1)) == target_id or not bool(candidate.get("alive", false)):
				continue
			response_targets.append(int(candidate.get("id", -1)))
		response_targets.sort()
		if not response_targets.is_empty():
			if not _trap_consume_card(target_id, "嫁禍"):
				return _error("嫁禍卡無法使用")
			var redirected_id: int = int(response_targets[0])
			var redirected_days: int = 4 if redirected_id == player_id else 5
			var redirect_result: Dictionary = _resolve_trap_direct(redirected_id, redirected_days)
			if not bool(redirect_result.get("ok", false)):
				return redirect_result
			_record_event("trap_redirected", {"caster_id": player_id, "from_target_id": target_id, "target_id": redirected_id, "days": redirected_days, "ai": true})
			_set_action_options(player_id)
			return _result(true, "AI 已使用嫁禍卡", {"redirected": true, "target_id": redirected_id, "days": redirected_days})
	# No scapegoat response is available; revenge is checked only on the original
	# target.  Direct admissions never recurse through defense cards.
	var direct_result: Dictionary = _resolve_trap_direct(target_id, 5, true, player_id)
	if not bool(direct_result.get("ok", false)):
		return direct_result
	_record_event("trap_resolved", {"caster_id": player_id, "target_id": target_id, "redirected": false})
	_set_action_options(player_id)
	return _result(true, "已執行陷害處罰", {"target_id": target_id, "redirected": false})


func _admit_player_status(player_id: int, kind: String, added_days: int) -> Dictionary:
	# Validate every input and destination before mutating any player or route
	# field. Status counters intentionally use the source seven-bit wrap rule;
	# zero is therefore a valid post-admission value for a 128-day addition.
	if not _is_statuses() or not ["hospital", "prison"].has(kind):
		return _error("目前地圖不支援此狀態")
	if not _valid_int(added_days, 1, MAX_STATUS_ADMISSION_DAYS):
		return _error("狀態天數無效")
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return _error("目前玩家無法進入狀態設施")
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY or board.is_empty():
		return _error("狀態設施地圖無效")
	var from_node_value: Variant = player.get("position", null)
	if not _valid_int(from_node_value, 0, board.size() - 1):
		return _error("玩家位置無效")
	var destination: int = _status_node_index(kind)
	if destination < 0 or destination >= board.size() or typeof(board[destination]) != TYPE_DICTIONARY:
		return _error("地圖缺少狀態設施")
	var status_key := _status_key(kind)
	var opposite_key := _status_key("prison" if kind == "hospital" else "hospital")
	var old_value: Variant = player.get(status_key, null)
	var opposite_value: Variant = player.get(opposite_key, null)
	if not _valid_int(old_value, 0, MAX_STATUS_ADMISSION_DAYS) or not _valid_int(opposite_value, 0, MAX_STATUS_ADMISSION_DAYS):
		return _error("玩家狀態資料無效")
	var from_node: int = int(from_node_value)
	var remaining: int = (int(old_value) + added_days) & 127
	player[status_key] = remaining
	player[opposite_key] = 0
	player["position"] = destination
	if player.has("previous_position"):
		player["previous_position"] = -1
	var current_player_id: int = int(state.get("current_player", -1))
	if player_id == current_player_id:
		state["route_options"] = []
		state["remaining_steps"] = 0
		state["pending_movement"] = {}
		if state.get("phase", "") == "await_route" or (_is_hazards() and state.get("phase", "") == "await_roll"):
			state["phase"] = "await_action"
	_sync_attached_gods()
	# Insurance is charged for the admission input even when the status wraps or
	# the player already owns the company's facility.
	_pay_company_insurance(player_id, added_days)
	_record_event("status_admitted", {"player_id": player_id, "status_kind": kind, "added_days": added_days, "remaining": remaining, "from_node": from_node, "node": destination})
	if player_id == current_player_id:
		_set_action_options(current_player_id)
	return _result(true, "已送往%s" % ("醫院" if kind == "hospital" else "監獄"), {"status_kind": kind, "remaining": remaining, "from_node": from_node, "node": destination})


func get_stock_symbols() -> Array:
	return OriginalStockMarket.symbols() if _is_companies() else STOCK_SYMBOLS.duplicate()


func get_stock_name(stock_symbol: String) -> String:
	if _is_companies():
		return str(state.get("market", {}).get("rows", {}).get(stock_symbol, {}).get("name", stock_symbol))
	return {"tech":"科技", "transport":"運輸", "energy":"能源"}.get(stock_symbol, stock_symbol)


func _initialize_original_companies(definition: Dictionary) -> void:
	state["companies"] = definition.get("companies", []).duplicate(true)
	state["market"] = OriginalStockMarket.create(definition.get("stock_rows", []))
	state["company_purchase_remaining"] = 1000
	state["company_service_pending"] = 0
	state["company_months"] = 0
	state["jackpot"] = 0
	for company in state.companies:
		company["owner"] = -1
		company["treasury"] = 10000 - int(state.market.rows[OriginalStockMarket.symbol(int(company.stock_index))].market_supply)
	for player in _players():
		player["stocks"] = {}
		player["insurance_status"] = 0
		for stock_symbol in get_stock_symbols():
			player.stocks[stock_symbol] = 0
		StockAccounting.initialize_player(player, get_stock_symbols())
	OriginalStockMarket.reset_turn_supply(state.market, _rng)
	_sync_state()
	_set_action_options(0)


func get_company_at(node_id: int) -> Dictionary:
	if not _is_companies(): return {}
	var tile := _tile_at(node_id)
	var source_id := int(tile.get("source_company_id", 0))
	if source_id == 0:
		var source_type := int(tile.get("type_and_idx", 0))
		if source_type > 6000 and source_type < 8000: source_id = source_type - 6000
	for company in state.get("companies", []):
		if int(company.get("id", 0)) == source_id: return company
	return {}


func _update_company_owners() -> void:
	if not _is_companies(): return
	# Keep source-test fixtures that stage holdings directly saveable without
	# changing the legacy-save rule: a player without cost metadata remains
	# unknown until that position is closed.
	for player in _players():
		for stock_symbol in get_stock_symbols():
			StockAccounting.reconcile_implicit_holding(player, stock_symbol, get_stock_symbols())
	for company in state.get("companies", []):
		var stock_symbol := OriginalStockMarket.symbol(int(company.stock_index))
		var old_owner := int(company.get("owner", -1))
		var maximum := 0
		var candidates: Array = []
		for player in _players():
			if not bool(player.get("alive", false)): continue
			var shares := int(player.stocks.get(stock_symbol, 0))
			if shares > maximum:
				maximum = shares
				candidates = [int(player.id)]
			elif shares == maximum and shares > 0:
				candidates.append(int(player.id))
		var owner := old_owner if candidates.has(old_owner) else int(candidates[0]) if not candidates.is_empty() else -1
		company.owner = owner
		if owner != old_owner:
			_record_event("company_owner_changed", {"company_id":int(company.id), "company_name":str(company.display_name), "owner_id":owner, "previous_owner_id":old_owner})


func _trade_company_market(action: String, params: Dictionary) -> Dictionary:
	if state.get("phase", "") == "game_over": return _error("遊戲已結束")
	if not bool(state.market.open): return _error("證券市場休市")
	var player_id := int(state.current_player)
	var player := _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)): return _error("目前玩家無法交易")
	var stock_symbol := str(params.get("symbol", params.get("stock", ""))).to_lower()
	var quantity_value: Variant = params.get("quantity", params.get("shares", null))
	if not get_stock_symbols().has(stock_symbol) or not _valid_int(quantity_value, 1, 10000): return _error("股票代號或數量無效")
	var quantity := int(quantity_value)
	var row: Dictionary = state.market.rows[stock_symbol]
	if int(row.suspension) > 0: return _error("這檔股票暫停交易")
	var limit_state := OriginalStockMarket.limit_state(float(row.previous_price), float(row.price))
	if action == "buy_stock" and limit_state == 1: return _error("漲停無法買入")
	if action == "sell_stock" and limit_state == 3: return _error("跌停無法賣出")
	var amount := OriginalStockMarket.quote(float(row.price), quantity)
	if action == "buy_stock":
		if quantity > int(row.market_supply) or quantity > int(row.turn_supply): return _error("本回合可購買股數不足")
		var affordable_quantity := floori(float(player.deposit) / float(row.price))
		if quantity > affordable_quantity: return _error("銀行存款不足")
		if int(player.deposit) < amount: return _error("銀行存款不足")
		player.deposit = int(player.deposit) - amount
		state.bank.deposits = int(state.bank.deposits) - amount
		row.market_supply = int(row.market_supply) - quantity
		row.turn_supply = int(row.turn_supply) - quantity
		player.stocks[stock_symbol] = int(player.stocks[stock_symbol]) + quantity
		StockAccounting.record_purchase(player, stock_symbol, quantity, amount, get_stock_symbols())
	else:
		if int(player.stocks[stock_symbol]) < quantity: return _error("持股不足")
		if int(player.deposit) > 1000000000000 - amount or int(state.bank.deposits) > 1000000000000 - amount: return _error("存款超出上限")
		player.deposit = int(player.deposit) + amount
		state.bank.deposits = int(state.bank.deposits) + amount
		row.market_supply = int(row.market_supply) + quantity
		row.turn_supply = int(row.turn_supply) + quantity
		player.stocks[stock_symbol] = int(player.stocks[stock_symbol]) - quantity
		StockAccounting.record_sale(player, stock_symbol, quantity, get_stock_symbols())
	_update_company_owners()
	_record_event("stock_bought" if action == "buy_stock" else "stock_sold", {"player_id":player_id,"symbol":stock_symbol,"stock_name":str(row.name),"quantity":quantity,"price":float(row.price),"amount":amount,"account":"deposit"})
	_set_action_options(player_id)
	return _result(true,"股票交易完成")


func _buy_company_stock(player_id: int, params: Dictionary) -> Dictionary:
	var player := _player(player_id)
	var company := get_company_at(int(player.get("position", -1)))
	if company.is_empty() or _is_gods_hospital_action(player): return _error("目前無法購買企業股份")
	var quantity_value: Variant = params.get("quantity", null)
	if not _valid_int(quantity_value, 1, 1000): return _error("每次造訪最多購買一千股")
	var quantity := int(quantity_value)
	if quantity > int(state.company_purchase_remaining) or quantity > int(company.treasury): return _error("企業剩餘股數或本次造訪額度不足")
	var face_price := int(company.stock_value) / 10000
	var amount: int = face_price * quantity
	if face_price <= 0 or int(player.cash) < amount: return _error("現金不足或企業售價無效")
	var stock_symbol := OriginalStockMarket.symbol(int(company.stock_index))
	player.cash = int(player.cash) - amount
	player.stocks[stock_symbol] = int(player.stocks[stock_symbol]) + quantity
	StockAccounting.record_purchase(player, stock_symbol, quantity, amount, get_stock_symbols())
	company.treasury = int(company.treasury) - quantity
	state.company_purchase_remaining = int(state.company_purchase_remaining) - quantity
	_update_company_owners()
	_record_event("company_shares_bought", {"player_id":player_id,"company_id":int(company.id),"company_name":str(company.display_name),"symbol":stock_symbol,"quantity":quantity,"price":face_price,"amount":amount})
	_set_action_options(player_id)
	return _result(true,"已購入企業股份")


static func _company_definition_errors(definition: Dictionary, player_count: int) -> Array:
	var rows: Variant = definition.get("stock_rows")
	var companies: Variant = definition.get("companies")
	if typeof(definition.get("supports_original_companies")) != TYPE_BOOL or not definition.get("supports_original_companies", false):
		return ["map does not support original companies"]
	if typeof(rows) != TYPE_ARRAY or rows.size() != 12 or typeof(companies) != TYPE_ARRAY:
		return ["missing company source rows"]
	for index in range(rows.size()):
		var row: Variant = rows[index]
		if typeof(row) != TYPE_DICTIONARY or not _valid_int(row.get("index"), index, index) or not OriginalStockMarket._number(row.get("price"), 1.0, 9999.0):
			return ["invalid company source stock"]
		if not _valid_int(row.get("market_supply"), 0, 10000): return ["invalid initial stock supply"]
	var runtime_companies: Array = companies.duplicate(true)
	for company in runtime_companies:
		if typeof(company) != TYPE_DICTIONARY or not _valid_int(company.get("stock_index"), 0, 11): return ["invalid initial company link"]
		company["owner"] = -1
		company["treasury"] = 10000 - int(rows[int(company.stock_index)].market_supply)
	var market := OriginalStockMarket.create(rows)
	var players: Array = []
	for index in range(player_count):
		var player := {"id":index,"alive":true,"stocks":{}}
		for stock_symbol in OriginalStockMarket.symbols(): player.stocks[stock_symbol] = 0
		players.append(player)
	var errors := OriginalStockMarket.validate(market, players, runtime_companies)
	errors.append_array(_validate_companies(runtime_companies, players, definition.get("board")))
	return errors

static func _validate_companies(companies: Variant, players: Variant, board: Variant) -> Array:
	var errors: Array = []
	if typeof(companies) != TYPE_ARRAY or companies.size() > 12: return ["invalid companies"]
	if typeof(players) != TYPE_ARRAY or typeof(board) != TYPE_ARRAY: return ["invalid company context"]
	for tile in board:
		if typeof(tile) != TYPE_DICTIONARY or not tile.has("source_company_id"): continue
		if not _valid_int(tile.get("type_and_idx"),6001,7999) or not _valid_int(tile.get("source_company_id"),1,1999) or int(tile.type_and_idx) != 6000+int(tile.source_company_id):
			errors.append("company metadata does not match board node")
	var used_stocks: Dictionary = {}
	for company in companies:
		if typeof(company) != TYPE_DICTIONARY:
			errors.append("invalid company record")
			continue
		if not _valid_int(company.get("id"), 1, 1999) or not _valid_int(company.get("stock_index"), 0, 11):
			errors.append("invalid company identity")
			continue
		var company_id := int(company.id)
		var stock_index := int(company.stock_index)
		if used_stocks.has(stock_index): errors.append("duplicate company stock link")
		used_stocks[stock_index] = true
		if typeof(company.get("display_name")) != TYPE_STRING or str(company.get("display_name", "")).is_empty() or str(company.get("display_name", "")).length() > 128:
			errors.append("invalid company name")
		if not _valid_int(company.get("company_type"), 0, 255) or not _valid_int(company.get("stock_value"), 0, 4294967295) or not _valid_int(company.get("toll_fee"), 0, 65535):
			errors.append("invalid company price or type")
		for key in ["monthly_profit", "cumulative_profit"]:
			if not _valid_int(company.get(key), -1000000000000, 1000000000000): errors.append("invalid company earnings")
		if not _valid_int(company.get("treasury"), 0, 10000) or not _valid_int(company.get("owner"), -1, players.size()-1):
			errors.append("invalid company ownership")
		var referenced := false
		for tile in board:
			if typeof(tile) == TYPE_DICTIONARY and _valid_int(tile.get("type_and_idx"), 0, 65535) and int(tile.type_and_idx) == 6000 + company_id:
				referenced = true
				if tile.has("source_company_id") and not _valid_int(tile.source_company_id, company_id, company_id): errors.append("company node link mismatch")
		if not referenced: errors.append("unreferenced company")
		var maximum := 0
		var candidates: Array = []
		var stock_symbol := OriginalStockMarket.symbol(stock_index)
		for player in players:
			if typeof(player) != TYPE_DICTIONARY or typeof(player.get("stocks")) != TYPE_DICTIONARY or not _valid_int(player.get("id"),0,players.size()-1): continue
			var shares: Variant = player.stocks.get(stock_symbol)
			if not _valid_int(shares, 0, 10000) or not bool(player.get("alive", false)): continue
			if int(shares) > maximum:
				maximum = int(shares)
				candidates = [int(player.id)]
			elif int(shares) == maximum and maximum > 0: candidates.append(int(player.id))
		if _valid_int(company.get("owner"), -1, players.size()-1):
			if (candidates.is_empty() and int(company.owner) != -1) or (not candidates.is_empty() and not candidates.has(int(company.owner))): errors.append("company largest-holder mismatch")
	return errors

func _company_by_id(company_id: int) -> Dictionary:
	for company in state.get("companies", []):
		if int(company.get("id", 0)) == company_id: return company
	return {}


func _resolve_company_visit(player_id: int, tile: Dictionary) -> void:
	var company := get_company_at(int(tile.get("index", -1)))
	if company.is_empty(): return
	var player := _player(player_id)
	if _is_gods_hospital_action(player): return
	var owner := int(company.get("owner", -1))
	var company_type := int(company.company_type)
	var base := 0
	var insurance_days := 0
	var insurance_rng_before := _rng.state
	var supported := company_type in [3, 4, 5, 6, 11, 12]
	if company_type == 11 and owner >= 0:
		if not get_company_upgrade_targets(player_id).is_empty():
			if _company_payable_upgrade_targets(player_id, company).is_empty():
				_record_event("company_service_unavailable", {"player_id":player_id,"company_id":int(company.id),"company_name":str(company.display_name),"reason":"earnings_limit"})
				return
			state.company_service_pending = int(company.id)
		elif owner != player_id:
			base = 1000 * _facility_price_index()
	if company_type == 4 and owner >= 0:
		insurance_days = _roll_company_insurance_days()
		if owner != player_id: base = insurance_days * int(company.toll_fee) * _facility_price_index()
	if owner >= 0 and owner != player_id:
		match company_type:
			3:
				base = int(company.toll_fee) * int(state.get("elapsed", 0))
			5, 6:
				var vehicle := str(player.get("vehicle", "walking"))
				if vehicle != "walking":
					base = (700 if company_type == 5 else 500) * int(state.get("last_roll_total", 0)) * _facility_price_index() * (2 if vehicle == "car" else 1)
			12:
				base = int(company.toll_fee) * int(state.get("last_roll_total", 0)) * _facility_price_index()
	var amount := _god_charge_amount_value(player_id, base, "company")
	var payable := mini(amount, int(player.cash)+int(player.deposit))
	if payable>0 and (int(company.monthly_profit)>1000000000000-payable or int(company.cumulative_profit)>1000000000000-payable):
		if insurance_days>0: _rng.state=insurance_rng_before
		_record_event("company_service_unavailable", {"player_id":player_id,"company_id":int(company.id),"company_name":str(company.display_name),"reason":"earnings_limit"})
		return
	_record_event("company_visited", {"player_id":player_id,"company_id":int(company.id),"company_name":str(company.display_name),"company_type":company_type,"owner_id":owner,"base_fee":base,"service_supported":supported})
	if insurance_days>0: _grant_company_insurance(player_id, company, insurance_days)
	if base > 0:
		amount = _god_adjust_charge_amount(player_id, base, "company")
		if amount <= 0:
			_record_event("god_charge_waived", {"player_id":player_id,"god_id":_player_god_id(player_id),"reason":"company","amount":base})
			return
		# Negative IDs below -1 identify a corporate creditor. The generic
		# cash/deposit/bankruptcy path then credits only actual payments.
		if not _financial_fee_gate(player_id, amount, -int(company.id)-2, "company", int(tile.get("index", player.get("position", -1)))):
			return
		_charge_amount(player_id, amount, -int(company.id)-2, "company", false)


static func _property_level_cap(tile: Dictionary, remodel_enabled: bool = false) -> int:
	return 1 if remodel_enabled and bool(tile.get("is_chain_store", false)) else MAX_PROPERTY_LEVEL


static func _company_upgrade_target_ids(board: Array, player_id: int, remodel_enabled: bool = false, research_enabled: bool = false) -> Array:
	var targets: Array = []
	var seen_facilities: Dictionary = {}
	for tile in board:
		if typeof(tile) != TYPE_DICTIONARY or not _valid_int(tile.get("owner"), player_id, player_id) or not _valid_int(tile.get("index"),0,board.size()-1): continue
		var kind := str(tile.get("kind", ""))
		var level: Variant = tile.get("building_level")
		if kind == "property" and _valid_int(level, 0, _property_level_cap(tile, remodel_enabled)-1):
			targets.append(int(tile.index))
		elif kind == "facility" and _valid_int(level, 0, 5):
			var facility_type: Variant = tile.get("facility_type")
			if not _facility_type_valid(facility_type) or (int(facility_type) == FACILITY_LAB_TYPE and not research_enabled): continue
			if int(level) > 0 and int(level) >= _facility_type_cap(int(facility_type)): continue
			if not _valid_int(tile.get("source_object_id"),1,1999) or not _valid_int(tile.get("facility_node_index",tile.index),0,board.size()-1): continue
			var source_id := int(tile.get("source_object_id", 0))
			if seen_facilities.has(source_id): continue
			seen_facilities[source_id] = true
			targets.append(int(tile.get("facility_node_index", tile.index)))
	return targets


func get_company_upgrade_targets(player_id: int) -> Array:
	if not _is_companies() or not bool(_player(player_id).get("alive", false)): return []
	return _company_upgrade_target_ids(state.board, player_id, _is_remodel(), _is_research())


func get_company_upgrade_fee(player_id: int, tile_id: int, company_owner_id: int) -> int:
	if company_owner_id == player_id: return 0
	var tile := _tile_at(tile_id)
	return _god_charge_amount_value(player_id, int(tile.get("land_price", tile.get("cost", 0))) * _facility_price_index(), "company")


func _company_payable_upgrade_targets(player_id: int, company: Dictionary) -> Array:
	var targets: Array = []
	var funds := int(_player(player_id).cash)+int(_player(player_id).deposit)
	for tile_id in get_company_upgrade_targets(player_id):
		var payable := mini(get_company_upgrade_fee(player_id, int(tile_id), int(company.owner)), funds)
		if int(company.monthly_profit)<=1000000000000-payable and int(company.cumulative_profit)<=1000000000000-payable:
			targets.append(tile_id)
	return targets


func _company_upgrade(player_id: int, params: Dictionary) -> Dictionary:
	var company := get_company_at(int(_player(player_id).get("position", -1)))
	if company.is_empty() or int(company.company_type) != 11 or int(state.company_service_pending) != int(company.id):
		return _error("目前沒有待處理的建設服務")
	var target_value: Variant = params.get("tile_id")
	if not _valid_int(target_value,0,state.board.size()-1) or not get_company_upgrade_targets(player_id).has(int(target_value)):
		return _error("請選擇自己尚未達最高等級的土地或設施")
	var tile := _tile_at(int(target_value))
	var level := int(tile.building_level)
	var kind := str(tile.kind)
	var cap := _property_level_cap(tile, _is_remodel())
	var facility_type := -1
	if kind == "facility":
		facility_type = int(tile.facility_type)
		if level == 0:
			var requested_type: Variant = params.get("facility_type")
			if not _valid_int(requested_type,0,FACILITY_LAB_TYPE if _is_research() else FACILITY_LAB_TYPE-1): return _error("請選擇有效的設施類型")
			facility_type = int(requested_type)
		cap = _facility_type_cap(facility_type)
	var free_service := int(company.owner) == player_id
	var amount := 0 if free_service else int(tile.get("land_price", tile.get("cost", 0))) * _facility_price_index()
	var payable := mini(get_company_upgrade_fee(player_id, int(target_value), int(company.owner)), int(_player(player_id).cash)+int(_player(player_id).deposit))
	if int(company.monthly_profit)>1000000000000-payable or int(company.cumulative_profit)>1000000000000-payable:
		return _error("企業收益已達可處理上限")
	var next_level := mini(cap,level+(2 if free_service else 1))
	if kind == "facility":
		_update_facility_records(int(tile.source_object_id), {"building_level":next_level,"facility_type":facility_type})
	else:
		tile.building_level = next_level
		_update_tile_rent(tile)
	_recalculate_property_values()
	state.company_service_pending = 0
	_record_event("company_construction", {"player_id":player_id,"company_id":int(company.id),"company_name":str(company.display_name),"tile_id":int(target_value),"from_level":level,"to_level":next_level,"base_fee":amount})
	if amount > 0:
		var adjusted_amount: int = _god_adjust_charge_amount(player_id, amount, "company")
		if adjusted_amount <= 0:
			_record_event("god_charge_waived", {"player_id":player_id,"god_id":_player_god_id(player_id),"reason":"company","amount":amount})
		elif _financial_fee_gate(player_id, adjusted_amount, -int(company.id)-2, "company", int(_player(player_id).get("position", -1))):
			_charge_amount(player_id, adjusted_amount, -int(company.id)-2, "company", false)
	if not bool(_player(player_id).alive) and state.phase != "game_over" and int(state.current_player) == player_id:
		_advance_to_next_alive(player_id)
	_set_action_options(int(state.current_player))
	return _result(true,"企業建設服務完成")


func _tick_company_insurance() -> void:
	if not _is_companies(): return
	for player in _players():
		var status := int(player.get("insurance_status", 0))
		player.insurance_status = 0 if status == 128 else 128 if status == 1 else maxi(0, status - 1)


func _roll_company_insurance_days() -> int:
	# Source mode-3 roulette has six equally likely nonblank outcomes. The
	# replayable remake RNG does not attempt the original wall-clock trace.
	var outcomes: Array = [5, 3, 30, 20, 15, 10]
	return int(outcomes[_rng.randi_range(0, outcomes.size()-1)])


func _grant_company_insurance(player_id: int, company: Dictionary, days: int) -> void:
	var player := _player(player_id)
	player.insurance_status = (int(player.get("insurance_status", 0)) + days) & 0x7f
	_record_event("company_insurance_granted", {"player_id":player_id,"company_id":int(company.id),"company_name":str(company.display_name),"days":days,"insurance_status":int(player.insurance_status)})


func _pay_company_insurance(player_id: int, added_days: int) -> void:
	if not _is_companies() or added_days <= 0: return
	var player := _player(player_id)
	if player.is_empty() or int(player.get("insurance_status", 0)) == 0: return
	var insurer: Dictionary = {}
	for company in state.companies:
		if int(company.company_type) == 4:
			insurer = company
			break
	if insurer.is_empty(): return
	var amount := 2000 * added_days * _facility_price_index()
	if int(player.cash) > 1000000000000-amount or int(insurer.monthly_profit) < -1000000000000+amount or int(insurer.cumulative_profit) < -1000000000000+amount:
		_record_event("company_service_unavailable", {"company_id":int(insurer.id),"reason":"earnings_limit"})
		return
	player.cash = int(player.cash) + amount
	insurer.monthly_profit = int(insurer.monthly_profit) - amount
	insurer.cumulative_profit = int(insurer.cumulative_profit) - amount
	_record_event("company_insurance_paid", {"player_id":player_id,"company_id":int(insurer.id),"company_name":str(insurer.display_name),"days":added_days,"amount":amount})


func _settle_company_dividends() -> void:
	if not _is_companies() or int(state.get("day_of_month", 0)) != 15: return
	var payouts: Dictionary = {}
	var settlements: Array = []
	for player in _players():
		if bool(player.get("alive", false)): payouts[int(player.id)] = 0
	for company in state.companies:
		var stock_symbol := OriginalStockMarket.symbol(int(company.stock_index))
		var total_shares := 0
		for player_id in payouts:
			total_shares += int(_player(int(player_id)).stocks[stock_symbol])
		if total_shares == 0: continue
		var pool := int(company.monthly_profit)
		var distributed := 0
		for player_id in payouts:
			var shares := int(_player(int(player_id)).stocks[stock_symbol])
			# Integer division truncates toward zero for positive and negative pools.
			var payout: int = pool * shares / total_shares
			payouts[player_id] = int(payouts[player_id]) + payout
			distributed += payout
		settlements.append({"company":company,"pool":pool,"distributed":distributed})
	var projected_bank_deposits := int(state.bank.deposits)
	for player_id in payouts:
		var old_deposit := int(_player(int(player_id)).deposit)
		var new_deposit := maxi(0,old_deposit+int(payouts[player_id]))
		projected_bank_deposits += new_deposit-old_deposit
		if new_deposit>1000000000000:
			_record_event("company_dividend_unavailable", {"reason":"balance_limit"})
			return
	if projected_bank_deposits>1000000000000:
		_record_event("company_dividend_unavailable", {"reason":"balance_limit"})
		return
	_settling_company_dividends = true
	for settlement in settlements:
		var company: Dictionary = settlement.company
		company.monthly_profit = 0
		_record_event("company_dividend", {"company_id":int(company.id),"company_name":str(company.display_name),"pool":int(settlement.pool),"distributed":int(settlement.distributed),"rounding_remainder":int(settlement.pool)-int(settlement.distributed)})
	for player_id in payouts:
		var player := _player(int(player_id))
		var payout := int(payouts[player_id])
		var old_deposit := int(player.deposit)
		var new_deposit := old_deposit + payout
		player.deposit = maxi(0, new_deposit)
		state.bank.deposits = int(state.bank.deposits) + int(player.deposit) - old_deposit
		if new_deposit < 0:
			var loss := -new_deposit
			var cash := int(player.cash)
			player.cash = maxi(0, cash-loss)
			if cash < loss: _declare_bankruptcy(int(player_id), -1, loss, "company_dividend")
		_record_event("company_dividend_paid", {"player_id":int(player_id),"amount":payout})
	_update_company_owners()
	_settling_company_dividends = false
	_check_game_over("company_dividend")

func _initialize_original_gods() -> void:
	if not _is_gods() or not _is_graph():
		return
	state["god_objects"] = []
	for god_id in OriginalGods.initial_ids():
		_spawn_god(int(god_id), -1, false)


func _god_object_index(god_id: int) -> int:
	var objects: Variant = state.get("god_objects", [])
	if typeof(objects) != TYPE_ARRAY:
		return -1
	for index in range(objects.size()):
		if typeof(objects[index]) == TYPE_DICTIONARY and int(objects[index].get("id", 0)) == god_id:
			return index
	return -1


func _god_object(god_id: int) -> Dictionary:
	var index: int = _god_object_index(god_id)
	var objects: Array = state.get("god_objects", [])
	if index < 0 or index >= objects.size() or typeof(objects[index]) != TYPE_DICTIONARY:
		return {}
	return objects[index]


func _god_reachable_nodes() -> Dictionary:
	return _graph_reachable_nodes(state.get("board", null), state.get("start_position", 0))


static func _graph_reachable_nodes(board: Variant, start_value: Variant) -> Dictionary:
	if typeof(board) != TYPE_ARRAY or board.is_empty():
		return {}
	if not _valid_int(start_value, 0, board.size() - 1):
		return {}
	var reachable: Dictionary = {int(start_value): true}
	var queue: Array = [int(start_value)]
	while not queue.is_empty():
		var node: int = int(queue.pop_front())
		if typeof(board[node]) != TYPE_DICTIONARY:
			continue
		var adjacent: Variant = board[node].get("adjacent", [])
		if typeof(adjacent) != TYPE_ARRAY:
			continue
		for neighbor in adjacent:
			if not _valid_int(neighbor, 0, board.size() - 1):
				continue
			var next_node: int = int(neighbor)
			if not reachable.has(next_node):
				reachable[next_node] = true
				queue.append(next_node)
	return reachable


func _god_occupied_nodes(ignore_god_id: int = -1) -> Dictionary:
	var occupied: Dictionary = {}
	for player in _players():
		if typeof(player) != TYPE_DICTIONARY or not bool(player.get("alive", false)):
			continue
		var position: Variant = player.get("position", null)
		if _valid_int(position, 0, state.get("board", []).size() - 1):
			occupied[int(position)] = true
	var objects: Variant = state.get("god_objects", [])
	if typeof(objects) == TYPE_ARRAY:
		for actor in objects:
			if typeof(actor) != TYPE_DICTIONARY or int(actor.get("id", 0)) == ignore_god_id:
				continue
			var owner: int = int(actor.get("owner", -1))
			var node: int = int(actor.get("node", -1))
			if owner >= 0:
				var owner_player: Dictionary = _player(owner)
				if not owner_player.is_empty():
					node = int(owner_player.get("position", node))
			if _valid_int(node, 0, state.get("board", []).size() - 1):
				occupied[node] = true
	return occupied


func _god_spawn_candidates(anchor_node: int = -1, require_distance: bool = false, ignore_god_id: int = -1) -> Array:
	if not _is_gods() or not _is_graph():
		return []
	var board: Array = state.get("board", [])
	var occupied: Dictionary = _god_occupied_nodes(ignore_god_id)
	var candidates: Array = OriginalGods.spawn_candidates(board, occupied, anchor_node, require_distance)
	var reachable: Dictionary = _god_reachable_nodes()
	var result: Array = []
	for node in candidates:
		if (reachable.is_empty() or reachable.has(int(node))) and (not _is_hazards() or not _dynamic_road_object_at(int(node))):
			result.append(int(node))
	return result


func _spawn_god(god_id: int, anchor_node: int = -1, replacement: bool = false) -> Dictionary:
	if not _is_gods() or not OriginalGods.is_spawnable(god_id):
		return {}
	if _god_object_index(god_id) >= 0:
		return _god_object(god_id)
	var require_distance: bool = replacement and anchor_node >= 0
	var candidates: Array = _god_spawn_candidates(anchor_node, require_distance)
	if candidates.is_empty():
		_record_event("god_spawn_unavailable", {"god_id": god_id, "anchor": anchor_node, "replacement": replacement})
		return {}
	# The original routine chooses a valid source node through the saved RNG.
	# Keeping selection deterministic by seed also makes save/replay continuation
	# explicit; no unbounded retry loop is allowed here.
	var selected_node: int = int(candidates[_rng.randi_range(0, candidates.size() - 1)])
	var actor: Dictionary = {"id": god_id, "node": selected_node, "owner": -1, "days": 0}
	var objects: Array = state.get("god_objects", [])
	objects.append(actor)
	state["god_objects"] = objects
	_record_event("god_spawned", {"god_id": god_id, "node": selected_node, "replacement": replacement})
	return actor


func _remove_god(god_id: int) -> Dictionary:
	var index: int = _god_object_index(god_id)
	var objects: Array = state.get("god_objects", [])
	if index < 0 or index >= objects.size():
		return {}
	var removed: Dictionary = objects[index].duplicate(true) if typeof(objects[index]) == TYPE_DICTIONARY else {}
	objects.remove_at(index)
	state["god_objects"] = objects
	return removed


func _player_god_id(player_id: int) -> int:
	var player: Dictionary = _player(player_id)
	if player.is_empty():
		return 0
	var value: Variant = player.get("god_id", 0)
	return int(value) if OriginalGods.valid_id(value) else 0


func _god_investment_blocked(player_id: int) -> bool:
	return _is_gods() and _player_god_id(player_id) in [7, 8, 15]


func _property_buy_price(tile: Dictionary) -> int:
	if _is_gods() and tile.get("kind", "") == "property":
		var land_price: int = int(tile.get("land_price", tile.get("cost", 0)))
		var house_price: int = int(tile.get("house_price", tile.get("upgrade_cost", 0)))
		return max(0, land_price + int(tile.get("building_level", 0)) * house_price) * _facility_price_index()
	return int(tile.get("cost", 0))


func _god_pair_respawn(god_id: int, anchor_node: int) -> void:
	var pair_id: int = OriginalGods.pair_for(god_id)
	if pair_id <= 0 or not OriginalGods.is_spawnable(pair_id):
		return
	if _god_object_index(pair_id) >= 0:
		_record_event("god_respawn_skipped", {"god_id": pair_id, "anchor": anchor_node, "reason": "occupied"})
		return
	_spawn_god(pair_id, anchor_node, true)


func _detach_god(god_id: int, reason: String = "detached", respawn: bool = true) -> Dictionary:
	var actor: Dictionary = _god_object(god_id)
	if actor.is_empty():
		return {}
	var owner_id: int = int(actor.get("owner", -1))
	var anchor_node: int = int(actor.get("node", -1))
	if owner_id >= 0:
		var owner: Dictionary = _player(owner_id)
		if not owner.is_empty():
			anchor_node = int(owner.get("position", anchor_node))
			if int(owner.get("god_id", 0)) == god_id:
				owner["god_id"] = 0
	_remove_god(god_id)
	_record_event("god_detached", {"god_id": god_id, "owner": owner_id, "reason": reason})
	if respawn:
		_god_pair_respawn(god_id, anchor_node)
	return actor


func _detach_player_god(player_id: int, reason: String = "replaced") -> void:
	var god_id: int = _player_god_id(player_id)
	if god_id <= 0:
		return
	if _god_object_index(god_id) >= 0:
		_detach_god(god_id, reason, true)
	else:
		# Keep the player-side reference from becoming a save-invalid ghost when
		# an older or partially recovered save omitted the object itself.
		var player: Dictionary = _player(player_id)
		if not player.is_empty():
			player["god_id"] = 0


func _attach_god(player_id: int, god_id: int) -> bool:
	if not _is_gods() or not OriginalGods.is_attachable(god_id):
		return false
	var player: Dictionary = _player(player_id)
	var actor: Dictionary = _god_object(god_id)
	if player.is_empty() or actor.is_empty() or int(actor.get("owner", -1)) >= 0:
		return false
	if god_id == 11:
		return false
	_detach_player_god(player_id, "replaced")
	var current_player_god: int = _player_god_id(player_id)
	if current_player_god != 0:
		return false
	var days: int = OriginalGods.days_for(god_id)
	actor["owner"] = player_id
	actor["node"] = int(player.get("position", actor.get("node", -1)))
	actor["days"] = days
	player["god_id"] = god_id
	_record_event("god_attached", {"player_id": player_id, "god_id": god_id, "days": days})
	_apply_god_attachment_effect(player_id, god_id)
	return true


func _sync_attached_gods() -> void:
	if not _is_gods():
		return
	var objects: Variant = state.get("god_objects", [])
	if typeof(objects) != TYPE_ARRAY:
		return
	var detached_ids: Array = []
	for actor in objects:
		if typeof(actor) != TYPE_DICTIONARY:
			continue
		var owner_id: int = int(actor.get("owner", -1))
		if owner_id < 0:
			continue
		var player: Dictionary = _player(owner_id)
		if player.is_empty() or not bool(player.get("alive", false)):
			detached_ids.append(int(actor.get("id", 0)))
			continue
		actor["node"] = int(player.get("position", actor.get("node", -1)))
	for player in _players():
		if typeof(player) == TYPE_DICTIONARY and not bool(player.get("alive", false)):
			player["god_id"] = 0
	for god_id in detached_ids:
		if _god_object_index(god_id) >= 0:
			_detach_god(god_id, "owner_unavailable", true)


func _encounter_dog(player_id: int, node_id: int) -> bool:
	var dog: Dictionary = _god_object(11)
	if dog.is_empty() or int(dog.get("owner", -1)) >= 0 or int(dog.get("node", -1)) != node_id:
		return false
	var vehicle: String = str(_player(player_id).get("vehicle", "walking"))
	var dog_node: int = int(dog.get("node", node_id))
	_remove_god(11)
	_record_event("dog_encounter", {"player_id": player_id, "node": node_id, "vehicle": vehicle, "hospital_days": 3 if vehicle == "walking" else 0})
	if vehicle == "walking":
		if _is_statuses():
			_admit_player_status(player_id, "hospital", 3)
		else:
			var player: Dictionary = _player(player_id)
			var old_hospital_days := int(player.get("hospital_days", 0))
			player["hospital_days"] = max(old_hospital_days, 3)
			_pay_company_insurance(player_id, int(player["hospital_days"]) - old_hospital_days)
			_record_event("hospital_started", {"player_id": player_id, "hospital_days": int(player["hospital_days"])})
	_god_pair_respawn(11, dog_node)
	return vehicle == "walking"


func _process_god_step(player_id: int, node_id: int, final_landing: bool = true) -> bool:
	if not _is_gods():
		return false
	_sync_attached_gods()
	# v9 source checks the ordinary god/dog object only after the final edge;
	# keeping the sync above preserves attached-god following on every edge.
	if _is_hazards() and not final_landing:
		return false
	if _encounter_dog(player_id, node_id):
		return true
	var objects: Variant = state.get("god_objects", [])
	if typeof(objects) != TYPE_ARRAY:
		return false
	for actor in objects:
		if typeof(actor) != TYPE_DICTIONARY:
			continue
		if int(actor.get("owner", -1)) >= 0 or int(actor.get("node", -1)) != node_id:
			continue
		var god_id: int = int(actor.get("id", 0))
		if OriginalGods.is_attachable(god_id) and god_id != 11:
			_attach_god(player_id, god_id)
			break
	return false


func _tick_gods() -> void:
	if not _is_gods():
		return
	_sync_attached_gods()
	var expiring: Array = []
	var objects: Variant = state.get("god_objects", [])
	if typeof(objects) != TYPE_ARRAY:
		return
	for actor in objects:
		if typeof(actor) != TYPE_DICTIONARY or int(actor.get("owner", -1)) < 0:
			continue
		var days: int = int(actor.get("days", 0)) - 1
		actor["days"] = max(0, days)
		if days <= 0:
			expiring.append(int(actor.get("id", 0)))
	for god_id in expiring:
		if _god_object_index(god_id) >= 0:
			_detach_god(god_id, "expired", true)


func _god_random_cash(large: bool) -> int:
	return _rng.randi_range(1000, 9999) if large else _rng.randi_range(100, 999)


func _god_bank_income(player_id: int, amount: int) -> void:
	if amount <= 0:
		return
	if not _bank_can_pay(amount):
		_record_event("god_cash_unavailable", {"player_id": player_id, "amount": amount, "source": "bank"})
		return
	_bank_subtract_cash(amount)
	var player: Dictionary = _player(player_id)
	player["cash"] = int(player.get("cash", 0)) + amount
	_record_event("god_cash_effect", {"player_id": player_id, "amount": amount, "source": "bank"})


func _drop_god_cards(player_id: int, amount: int) -> void:
	var player: Dictionary = _player(player_id)
	var cards: Array = player.get("cards", [])
	var dropped: Array = []
	var requested: int = min(max(0, amount), cards.size())
	for _index in range(requested):
		if cards.is_empty():
			break
		var card_index: int = _rng.randi_range(0, cards.size() - 1)
		var card_id: String = str(cards[card_index])
		if _is_inventory():
			var result: Dictionary = OriginalInventory.consume_card(state["inventory_supply"], cards, card_id)
			if not bool(result.get("ok", false)):
				break
		else:
			cards.remove_at(card_index)
		dropped.append(card_id)
	player["cards"] = cards
	_record_event("god_card_drop", {"player_id": player_id, "card_ids": dropped, "count": dropped.size()})


func _clear_player_inventory(player_id: int) -> void:
	var player: Dictionary = _player(player_id)
	if player.is_empty():
		return
	var dropped_cards: Array = player.get("cards", []).duplicate()
	var dropped_tools: Dictionary = player.get("tools", {}).duplicate(true)
	if _is_inventory():
		for card_id in dropped_cards.duplicate():
			OriginalInventory.consume_card(state["inventory_supply"], player["cards"], card_id)
		for tool_id in dropped_tools.keys():
			var quantity: int = int(player["tools"].get(tool_id, 0))
			if quantity > 0:
				OriginalInventory.consume_tool(state["inventory_supply"], player["tools"], tool_id, quantity)
		# Equipped vehicles are represented outside tools; return their finite
		# source unit before resetting the player to walking.
		var active_tool: String = _inventory_vehicle_tool_id(str(player.get("vehicle", "walking")))
		if not active_tool.is_empty():
			var supply_tools: Dictionary = state["inventory_supply"].get("tools", {})
			if supply_tools.has(active_tool):
				supply_tools[active_tool] = int(supply_tools[active_tool]) + 1
			state["inventory_supply"]["tools"] = supply_tools
	player["cards"] = []
	player["tools"] = {}
	player["vehicle"] = "walking"
	player["dice_count"] = 1
	player.erase("engineering_vehicle")
	player["vehicles"] = {"walking": true, "motorcycle": false, "car": false}
	_record_event("god_inventory_cleared", {"player_id": player_id, "card_count": dropped_cards.size(), "tool_ids": dropped_tools.keys()})


func _apply_god_attachment_effect(player_id: int, god_id: int) -> void:
	var role: String = OriginalGods.role_for(god_id)
	match role:
		"wealth_small":
			for other in _players():
				var other_id: int = int(other.get("id", -1))
				if other_id < 0 or other_id == player_id or not bool(other.get("alive", false)):
					continue
				_charge_amount(other_id, _god_random_cash(false), player_id, "god_wealth")
		"wealth_large":
			_god_bank_income(player_id, _god_random_cash(true))
		"fortune_small":
			_grant_random_card(player_id, "god_fortune")
		"fortune_large":
			_grant_random_card(player_id, "god_fortune")
			_grant_random_card(player_id, "god_fortune")
		"poor_small":
			for other in _players():
				var other_id: int = int(other.get("id", -1))
				if other_id < 0 or other_id == player_id or not bool(other.get("alive", false)):
					continue
				_charge_amount(player_id, _god_random_cash(false), other_id, "god_poor")
				if not bool(_player(player_id).get("alive", false)):
					break
		"poor_large":
			_charge_amount(player_id, _god_random_cash(true), -1, "god_poor")
		"unlucky_small":
			_drop_god_cards(player_id, 1)
		"unlucky_large":
			_drop_god_cards(player_id, int(floor(float(_player(player_id).get("cards", []).size()) / 2.0)))
		"death":
			_clear_player_inventory(player_id)


func _apply_fortune_construction_bonus(player_id: int, tile: Dictionary) -> void:
	if not _is_gods() or not [3, 4].has(_player_god_id(player_id)) or tile.is_empty():
		return
	var kind: String = str(tile.get("kind", ""))
	if kind == "property":
		var level: int = int(tile.get("building_level", 0))
		if level >= _property_level_cap(tile, _is_remodel()):
			return
		tile["building_level"] = level + 1
		_update_tile_rent(tile)
		_recalculate_property_values()
		_record_event("god_fortune_construction", {"player_id": player_id, "god_id": _player_god_id(player_id), "tile_id": int(tile.get("index", -1)), "from_level": level, "to_level": level + 1})
		return
	if kind == "facility":
		var facility: Dictionary = _facility_record(int(tile.get("index", -1)))
		var facility_type: int = int(facility.get("facility_type", -1))
		var level: int = int(facility.get("building_level", 0))
		if not _facility_type_valid(facility_type) or (facility_type == FACILITY_LAB_TYPE and not _is_research()) or level >= _facility_type_cap(facility_type):
			return
		_update_facility_records(int(facility.get("source_object_id", -1)), {"building_level": level + 1})
		_recalculate_property_values()
		_record_event("god_fortune_construction", {"player_id": player_id, "god_id": _player_god_id(player_id), "tile_id": int(tile.get("index", -1)), "from_level": level, "to_level": level + 1})


func _build_board() -> Array:
	var property_by_index: Dictionary = {}
	for spec in PROPERTY_SPECS:
		property_by_index[int(spec["index"])] = spec
	var board: Array = []
	for index in range(BOARD_SIZE):
		var tile: Dictionary = {
			"index": index,
			"kind": "rest",
			"name": "休息區 %d" % index,
			"owner": -1,
			"building_level": 0,
			"cost": 0,
			"upgrade_cost": 0,
			"base_rent": 0,
			"rent": 0,
			"group": "",
			"tax_amount": 0,
		}
		if property_by_index.has(index):
			var spec: Dictionary = property_by_index[index]
			tile["kind"] = "property"
			tile["name"] = spec["name"]
			tile["cost"] = int(spec["cost"])
			tile["upgrade_cost"] = int(spec["upgrade_cost"])
			tile["base_rent"] = int(spec["rent"])
			tile["rent"] = int(spec["rent"])
			tile["group"] = spec["group"]
		elif index == 0:
			tile["kind"] = "start"
			tile["name"] = "起點"
		elif index in [4, 15, 26, 37]:
			tile["kind"] = "event"
			tile["name"] = "命運"
		elif index in [8, 22]:
			tile["kind"] = "tax"
			tile["name"] = "稅務局"
			tile["tax_amount"] = 1000 if index == 22 else 500
		elif index in [11, 30]:
			tile["kind"] = "bank"
			tile["name"] = "銀行"
		elif index in [19, 33]:
			tile["kind"] = "stock"
			tile["name"] = "證券交易所"
		board.append(tile)
	return board


func get_snapshot() -> Dictionary:
	_sync_state()
	return state.duplicate(true)


func _sync_state() -> void:
	if state.is_empty():
		return
	state["rng_state"] = int(_rng.state)
	state["rng_state_text"] = str(_rng.state)
	var day: int = int(state.get("day", 1))
	if _is_setup():
		var elapsed: int = max(0, day - 1)
		var start_date: Dictionary = state.get("start_date", {})
		var current_date: Dictionary = GameCalendar.add_days(start_date, elapsed)
		if not current_date.is_empty():
			state["elapsed"] = elapsed
			state["date"] = current_date
			state["month"] = int(current_date["month"])
			state["day_of_month"] = int(current_date["day"])
			state["weekday"] = GameCalendar.weekday(current_date)
		else:
			state["elapsed"] = elapsed
		var market: Dictionary = state.get("market", {})
		market["open"] = not _is_sunday() and (not _is_companies() or int(market.get("closed_days", 0)) == 0)
		state["market"] = market
		return
	state["day_of_month"] = ((day - 1) % DAYS_PER_MONTH) + 1
	state["month"] = ((day - 1) / DAYS_PER_MONTH) + 1
	state["weekday"] = ((day - 1) % 7) + 1
	var market: Dictionary = state.get("market", {})
	market["open"] = not _is_sunday() and (not _is_companies() or int(market.get("closed_days", 0)) == 0)
	state["market"] = market


func _is_sunday() -> bool:
	return int(state.get("weekday", 1)) == 7


func _players() -> Array:
	return state.get("players", [])


func _player(player_id: int) -> Dictionary:
	var players: Array = _players()
	if player_id < 0 or player_id >= players.size():
		return {}
	return players[player_id]


func _current_player() -> Dictionary:
	return _player(int(state.get("current_player", -1)))


## Read-only target selectors for the original research transport tool.
## Validation is repeated by the mutating action; these methods only expose the
## currently legal identities to the UI and AI.
func transport_targets(target_kind: String) -> Array:
	return TimeTransportRules.transport_targets(self, target_kind)


func transport_destinations(target_kind: String, target_id: Variant) -> Array:
	return TimeTransportRules.transport_destinations(self, target_kind, target_id)


func time_machine_status() -> Dictionary:
	return TimeTransportRules.time_machine_status(self)


func _time_anchor_snapshot(player_id: int) -> Dictionary:
	var record: Variant = _time_anchors.get(player_id, null)
	if typeof(record) != TYPE_DICTIONARY:
		return {}
	var saved: Variant = record.get("state", null)
	return saved.duplicate(true) if typeof(saved) == TYPE_DICTIONARY else {}


func _capture_time_anchor(player_id: int) -> bool:
	if not TimeTransportRules.is_supported(self):
		return false
	if str(state.get("phase", "")) != "await_roll":
		return false
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)) or not bool(player.get("is_human", false)) or bool(player.get("is_ai", false)):
		return false
	# Keep the anchor private.  It is a complete legal save-shaped snapshot, but
	# it never enters state/to_dict and therefore disappears across JSON load.
	_sync_state()
	_time_anchor_sequence += 1
	_time_anchors[player_id] = {"state": state.duplicate(true), "sequence": _time_anchor_sequence}
	return true


func _replace_time_anchor_after_restore(player_id: int, restored_state: Dictionary) -> void:
	var previous: Variant = _time_anchors.get(player_id, null)
	var sequence: int = 0
	if typeof(previous) == TYPE_DICTIONARY:
		sequence = int(previous.get("sequence", 0))
	if sequence <= 0:
		_time_anchor_sequence += 1
		sequence = _time_anchor_sequence
	# Restoring an earlier world discards anchors captured in the abandoned
	# future, including anchors belonging to another human player.
	for key in _time_anchors.keys().duplicate():
		var record: Variant = _time_anchors.get(key, null)
		if typeof(record) == TYPE_DICTIONARY and int(record.get("sequence", 0)) > sequence:
			_time_anchors.erase(key)
	_time_anchors[player_id] = {"state": restored_state.duplicate(true), "sequence": sequence}


func _valid_player(player_id: int, require_alive: bool = false) -> bool:
	var player: Dictionary = _player(player_id)
	if player.is_empty():
		return false
	return not require_alive or bool(player.get("alive", false))


func _record_event(event_type: String, payload: Dictionary = {}) -> void:
	var event: Dictionary = {"type": event_type, "day": int(state.get("day", 1)), "turn": int(state.get("turn", 1))}
	for key in payload:
		event[key] = payload[key]
	state["last_event"] = event
	var log: Array = state.get("event_log", [])
	log.append(event)
	if log.size() > 200:
		log.pop_front()
	state["event_log"] = log


func _result(ok: bool, message: String = "", extra: Dictionary = {}) -> Dictionary:
	_sync_state()
	var result: Dictionary = {
		"ok": ok,
		"message": message,
		"phase": state.get("phase", ""),
		"current_player": int(state.get("current_player", -1)),
		"event": state.get("last_event", {}).duplicate(true),
		"state": get_snapshot(),
	}
	for key in extra:
		result[key] = extra[key]
	return result


func _error(message: String) -> Dictionary:
	return _result(false, message)


func _require_phase(expected: String) -> bool:
	return state.get("phase", "") == expected


func _is_gods_hospital_action(player: Dictionary) -> bool:
	if not _is_gods() or player.is_empty():
		return false
	if _status_active(player):
		return true
	var last_roll: Variant = state.get("last_roll", [])
	return state.get("phase", "") == "await_action" and bool(state.get("property_action_used", false)) and typeof(last_roll) == TYPE_ARRAY and last_roll.is_empty()


func _set_action_options(player_id: int) -> void:
	# Facility maps retain the complete roll total separately for their source
	# compatibility boundary. Keep the graph-facing total canonical when a
	# caller prepares an action directly with that preserved value.
	if _is_facilities() and _valid_int(state.get("last_roll_total", null), 0, MAX_GRAPH_STEPS):
		state["last_total"] = int(state.get("last_roll_total", 0))
	var phase: String = str(state.get("phase", ""))
	if phase == "game_over":
		state["action_options"] = []
		return
	var options: Array = []
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		state["action_options"] = options
		return
	if not AuctionRules.response(self).is_empty():
		state["action_options"] = ["respond_auction"] if phase == "await_action" else []
		return
	if not _pending_finance().is_empty():
		state["action_options"] = ["respond_finance"] if phase in ["await_roll", "await_action"] else []
		return
	if _trap_pending():
		state["action_options"] = ["respond_trap"]
		return
	if _sleep_active(player):
		state["action_options"] = ["end_turn"] if phase == "await_action" else []
		return
	# v8 status turns expose only their legal turn control.  Keeping this gate
	# here also makes snapshots consumed by the UI agree with choose_action.
	if _is_statuses() and _status_active(player):
		if phase == "await_roll" and int(player.get("tools", {}).get(TimeTransportRules.TIME_MACHINE, 0)) > 0:
			state["action_options"] = ["use_tool"]
		else:
			state["action_options"] = ["end_turn"] if phase == "await_action" else []
		return
	var bank_open: bool = not _is_sunday()
	var stock_open: bool = bank_open and (not _is_companies() or bool(state.get("market", {}).get("open", false)))
	var hospitalized: bool = _is_gods_hospital_action(player)
	if stock_open:
		options.push_front("sell_stock")
		if int(player.get("deposit" if _is_companies() else "cash", 0)) >= (1 if _is_companies() else 10):
			options.push_front("buy_stock")
	if phase != "await_action":
		if _is_inventory() and phase == "await_roll":
			var pending_remote: Variant = state.get("pending_remote_dice", {})
			if typeof(pending_remote) != TYPE_DICTIONARY or pending_remote.is_empty():
				if player.get("cards", []).size() > 0:
					options.push_front("use_card")
				var tools: Dictionary = player.get("tools", {})
				if not _inventory_movement_blocked(player):
					for tool_id in IMPLEMENTED_TOOL_IDS:
						if int(tools.get(tool_id, 0)) > 0:
							options.push_front("use_tool")
							break
		state["action_options"] = options
		return
	options.push_back("end_turn")
	if _is_companies() and int(state.get("company_service_pending",0))>0:
		state["action_options"] = ["company_upgrade"]
		return
	if _is_companies() and not hospitalized:
		var company: Dictionary = get_company_at(int(player.get("position", -1)))
		if not company.is_empty() and int(company.get("treasury", 0)) > 0 and int(state.get("company_purchase_remaining", 0)) > 0 and int(company.get("stock_value", 0)) >= 10000:
			options.push_front("buy_company")
	var tile: Dictionary = _tile_at(int(player.get("position", 0)))
	if not hospitalized and _is_inventory() and _is_graph() and int(tile.get("event_code", -1)) == 15:
		options.push_front("sell_item")
		options.push_front("buy_item")
	if not hospitalized and tile.get("kind", "") == "property" and not bool(state.get("property_action_used", false)):
		var owner: int = int(tile.get("owner", -1))
		if owner == -1 and _player_god_id(player_id) != 12 and not _god_investment_blocked(player_id) and int(player.get("cash", 0)) >= _property_buy_price(tile):
			options.push_front("buy")
		elif owner == player_id and not _god_investment_blocked(player_id):
			var level: int = int(tile.get("building_level", 0))
			var property_cap: int = _property_level_cap(tile, _is_remodel())
			if level < property_cap and int(player.get("cash", 0)) >= _upgrade_price(tile):
				options.push_front("upgrade")
	if not hospitalized and _is_facilities() and _is_graph() and tile.get("kind", "") == "facility" and not bool(state.get("property_action_used", false)):
		var facility: Dictionary = _facility_record(int(player.get("position", -1)))
		var facility_owner: int = int(facility.get("owner", -1))
		if facility_owner == -1 and _player_god_id(player_id) != 12 and not _god_investment_blocked(player_id) and int(player.get("cash", 0)) >= _facility_land_price(facility):
			options.push_front("buy")
		elif facility_owner == player_id and not _god_investment_blocked(player_id):
			var facility_level: int = int(facility.get("building_level", 0))
			var facility_type: int = int(facility.get("facility_type", -1))
			if facility_level == 0 and _facility_type_valid(facility_type) and int(player.get("cash", 0)) >= _facility_land_price(facility):
				options.push_front("build_facility")
			elif _facility_type_valid(facility_type) and (facility_type != FACILITY_LAB_TYPE or _is_research()) and facility_level < _facility_type_cap(facility_type) and int(player.get("cash", 0)) >= _facility_upgrade_price(facility):
				options.push_front("upgrade")
	# Research is a separate action from the land/build action. It remains
	# available after a same-visit laboratory construction, while the
	# per-visit guard prevents a second successful selection.  Share the same
	# landing guard as the public action so skipped/non-movement turns do not
	# expose a research picker.
	if _can_choose_research(player_id):
		options.push_front("choose_research")
	if not hospitalized and tile.get("kind", "") == "bank":
		state["bank_landing"] = bank_open
		if bank_open and not _loan_block_active(player):
			options.push_front("take_loan")
		if bank_open and _is_companies() and int(player.get("loan", 0)) > 0:
			options.push_front("repay_loan")
	if bool(state.get("bank_access", false)) and bank_open:
		if bank_transfer_limit("deposit", player_id) > 0:
			options.push_front("deposit")
		if bank_transfer_limit("withdraw", player_id) > 0:
			options.push_front("withdraw")
	if stock_open:
		options.push_front("sell_stock")
		if int(player.get("deposit" if _is_companies() else "cash", 0)) >= (1 if _is_companies() else 10):
			options.push_front("buy_stock")
		if not hospitalized and not _is_inventory():
			var vehicles: Dictionary = player.get("vehicles", {})
			for vehicle in ["motorcycle", "car"]:
				if not bool(vehicles.get(vehicle, false)) and int(player.get("cash", 0)) >= int(VEHICLE_COSTS[vehicle]):
					options.push_front("buy_vehicle")
	var action_pending_remote: Variant = state.get("pending_remote_dice", {})
	var action_remote_pending: bool = _is_inventory() and typeof(action_pending_remote) == TYPE_DICTIONARY and not action_pending_remote.is_empty()
	if _is_inventory() and not hospitalized and not _stationary_turn() and not action_remote_pending and not _inventory_movement_blocked(player) and not EngineeringVehicle.is_active(player) and int(player.get("tools", {}).get("工程車", 0)) > 0:
		options.push_front("use_tool")
	if player.get("cards", []).size() > 0 and not action_remote_pending:
		var can_use_card: bool = not hospitalized
		if hospitalized:
			for card_value in player.get("cards", []):
				if str(card_value) != "購地":
					can_use_card = true
					break
		if can_use_card:
			options.push_front("use_card")
	state["action_options"] = options


func _can_choose_research(player_id: int) -> bool:
	if not _is_research() or not _is_graph() or not _require_phase("await_action"):
		return false
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return false
	if _status_active(player) or _is_gods_hospital_action(player):
		return false
	if bool(state.get("research_action_used", false)):
		return false
	# An await_action phase can also represent a skipped/end-only turn.  A
	# research choice requires evidence of an actual positive roll and landing.
	var last_roll: Variant = state.get("last_roll", null)
	var last_roll_total: Variant = state.get("last_roll_total", null)
	if typeof(last_roll) != TYPE_ARRAY or last_roll.is_empty():
		return false
	if typeof(last_roll_total) != TYPE_INT or int(last_roll_total) <= 0:
		return false
	var tile: Dictionary = _tile_at(int(player.get("position", -1)))
	if tile.get("kind", "") != "facility":
		return false
	var facility: Dictionary = _facility_record(int(player.get("position", -1)))
	if facility.is_empty() or int(facility.get("owner", -1)) != player_id:
		return false
	if int(facility.get("facility_type", -1)) != FACILITY_LAB_TYPE or int(facility.get("building_level", 0)) <= 0:
		return false
	return not _facility_is_sealed(facility)


func _choose_research(player_id: int, params: Dictionary = {}) -> Dictionary:
	# A valid cancellation acknowledges the request without changing state.
	# The UI may also simply close its picker without dispatching an action.
	if params.has("cancel") and typeof(params.get("cancel")) != TYPE_BOOL:
		return _error("研究選擇取消格式無效")
	if bool(params.get("cancel", false)):
		return _result(true, "已取消研究選擇", {"cancelled": true})
	if not _can_choose_research(player_id):
		return _error("目前無法選擇研究")
	var player: Dictionary = _player(player_id)
	var facility: Dictionary = _facility_record(int(player.get("position", -1)))
	var tool_value: Variant = params.get("tool_id", null)
	if typeof(tool_value) != TYPE_STRING:
		return _error("研究產品格式無效")
	var tool_id: String = str(tool_value)
	var rank: int = RESEARCH_TOOL_IDS.find(tool_id) + 1
	if rank <= 0 or rank > RESEARCH_TOOL_MAX_RANK:
		return _error("研究產品無效")
	var level: int = int(facility.get("building_level", 0))
	if rank > level:
		return _error("研究所等級不足以生產此產品")
	_update_facility_records(int(facility.get("source_object_id", -1)), {"research_tool": rank, "research_turns": RESEARCH_JOB_TURNS})
	state["research_action_used"] = true
	_record_event("research_selected", {"player_id": player_id, "facility_id": _facility_canonical_index(int(player.get("position", -1))), "source_object_id": int(facility.get("source_object_id", -1)), "tool_id": tool_id, "research_rank": rank, "research_turns": RESEARCH_JOB_TURNS})
	_set_action_options(player_id)
	return _result(true, "已選擇研究產品", {"tool_id": tool_id, "research_rank": rank, "research_turns": RESEARCH_JOB_TURNS})


func _tile_at(index: int) -> Dictionary:
	var board: Array = state.get("board", [])
	if index < 0 or index >= board.size():
		return {}
	return board[index]


func _facility_indices(source_object_id: int) -> Array:
	var indices: Array = []
	if source_object_id <= 0:
		return indices
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY:
		return indices
	for index in range(board.size()):
		if typeof(board[index]) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = board[index]
		if tile.get("kind", "") == "facility" and int(tile.get("source_object_id", -1)) == source_object_id:
			indices.append(index)
	return indices


func _facility_canonical_index(tile_index: int) -> int:
	var tile: Dictionary = _tile_at(tile_index)
	if tile.get("kind", "") != "facility":
		return tile_index
	var source_object_id: int = int(tile.get("source_object_id", -1))
	var indices: Array = _facility_indices(source_object_id)
	if indices.is_empty():
		return tile_index
	indices.sort()
	var declared: Variant = tile.get("facility_node_index", null)
	if _valid_int(declared, 0, state.get("board", []).size() - 1) and indices.has(int(declared)):
		return int(declared)
	return int(indices[0])


func _facility_record(tile_index: int) -> Dictionary:
	var canonical_index: int = _facility_canonical_index(tile_index)
	return _tile_at(canonical_index)


func _update_facility_records(source_object_id: int, updates: Dictionary) -> void:
	if source_object_id <= 0:
		return
	var board: Array = state.get("board", [])
	for index in _facility_indices(source_object_id):
		if index < 0 or index >= board.size() or typeof(board[index]) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = board[index]
		for key in updates.keys():
			tile[key] = updates[key]


func _facility_price_index() -> int:
	if not _is_facilities():
		return 1
	var value: Variant = state.get("price_index", 1)
	return int(value) if _valid_int(value, 1, 1000000) else 1


func _facility_land_price(tile: Dictionary) -> int:
	return int(tile.get("land_price", tile.get("cost", 0))) * _facility_price_index()


func _facility_upgrade_price(tile: Dictionary) -> int:
	return int(tile.get("upgrade_cost", 0)) * _facility_price_index()


func inventory_purchase_price(tile: Dictionary) -> int:
	if tile.is_empty():
		return 0
	if tile.get("kind", "") == "facility":
		if not _is_gods():
			return _facility_land_price(tile)
		var facility: Dictionary = _facility_record(int(tile.get("index", -1)))
		if facility.is_empty():
			facility = tile
		var facility_land_price: int = int(facility.get("land_price", facility.get("cost", 0)))
		var facility_upgrade_price: int = int(facility.get("upgrade_cost", 0))
		var facility_level: int = int(facility.get("building_level", 0))
		return max(0, facility_land_price + facility_level * facility_upgrade_price) * _facility_price_index()
	if _is_gods():
		var land_price: int = int(tile.get("land_price", tile.get("cost", 0)))
		var house_price: int = int(tile.get("house_price", tile.get("upgrade_cost", 0)))
		return max(0, land_price + int(tile.get("building_level", 0)) * house_price) * _facility_price_index()
	return int(tile.get("cost", 0))


static func _facility_type_valid(facility_type: Variant) -> bool:
	return _valid_int(facility_type, 0, FACILITY_TYPE_COUNT - 1)


static func _facility_type_cap(facility_type: int) -> int:
	if facility_type < 0 or facility_type >= FACILITY_MAX_LEVELS.size():
		return 0
	return int(FACILITY_MAX_LEVELS[facility_type])


static func _facility_state_valid(facility_state: Variant) -> bool:
	if not _valid_int(facility_state, 0, 0xff):
		return false
	var packed: int = int(facility_state)
	var high: int = packed & FACILITY_STATE_HIGH_MASK
	var low: int = packed & FACILITY_STATE_LOW_MASK
	if high > FACILITY_RAISED_BASE_STATE or low > 1:
		return false
	return high == 0 and low == 0 or high != 0


func _facility_is_sealed(tile: Dictionary) -> bool:
	var packed: int = int(tile.get("facility_state", 0))
	return (packed & FACILITY_STATE_HIGH_MASK) != 0 and (packed & FACILITY_STATE_LOW_MASK) != 0


func _facility_is_raised(tile: Dictionary) -> bool:
	var packed: int = int(tile.get("facility_state", 0))
	return (packed & FACILITY_STATE_HIGH_MASK) != 0 and (packed & FACILITY_STATE_LOW_MASK) == 0


func _facility_service_admitted(tile: Dictionary) -> bool:
	if tile.get("kind", "") != "facility":
		return false
	var facility_type: int = int(tile.get("facility_type", -1))
	return facility_type >= 0 and facility_type < FACILITY_LAB_TYPE and int(tile.get("building_level", 0)) > 0 and not _facility_is_sealed(tile)


func _expire_facility_state(packed_state: int) -> int:
	if not _facility_state_valid(packed_state) or packed_state == 0:
		return 0 if packed_state != 0 and not _facility_state_valid(packed_state) else packed_state
	var high: int = packed_state & FACILITY_STATE_HIGH_MASK
	var low: int = packed_state & FACILITY_STATE_LOW_MASK
	if high <= FACILITY_STATE_STEP:
		return 0
	return (high - FACILITY_STATE_STEP) | low


func _tick_facility_states() -> void:
	if not _is_facilities() or not _is_graph():
		return
	var seen: Dictionary = {}
	for tile_value in state.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility":
			continue
		var source_object_id: int = int(tile_value.get("source_object_id", -1))
		if source_object_id <= 0 or seen.has(source_object_id):
			continue
		seen[source_object_id] = true
		var old_state: int = int(tile_value.get("facility_state", 0))
		var next_state: int = _expire_facility_state(old_state)
		if next_state != old_state:
			_update_facility_records(source_object_id, {"facility_state": next_state})
			_record_event("facility_state_expired", {"source_object_id": source_object_id, "from_state": old_state, "to_state": next_state})


func _tick_research_for_owner(owner_id: int) -> void:
	if not _is_research() or not _is_graph() or not _valid_player(owner_id, true):
		return
	var player: Dictionary = _player(owner_id)
	var seen_sources: Dictionary = {}
	for tile_value in state.get("board", []):
		if typeof(tile_value) != TYPE_DICTIONARY or tile_value.get("kind", "") != "facility":
			continue
		var source_object_id: int = int(tile_value.get("source_object_id", -1))
		if source_object_id <= 0 or seen_sources.has(source_object_id):
			continue
		seen_sources[source_object_id] = true
		var facility: Dictionary = _facility_record(int(tile_value.get("index", -1)))
		if facility.is_empty() or int(facility.get("owner", -1)) != owner_id or int(facility.get("facility_type", -1)) != FACILITY_LAB_TYPE:
			continue
		var research_tool: int = int(facility.get("research_tool", 0))
		var research_turns: int = int(facility.get("research_turns", 0))
		if research_tool < 1 or research_tool > RESEARCH_TOOL_MAX_RANK or research_turns <= 0:
			continue
		var facility_level: int = int(facility.get("building_level", 0))
		var tool_id: String = RESEARCH_TOOL_IDS[research_tool - 1]
		if research_tool > facility_level:
			_update_facility_records(source_object_id, {"research_turns": 0})
			_record_event("research_cancelled", {"player_id": owner_id, "facility_id": _facility_canonical_index(int(tile_value.get("index", -1))), "source_object_id": source_object_id, "tool_id": tool_id, "research_rank": research_tool, "building_level": facility_level, "reason": "facility_level_too_low"})
			continue
		var next_turns: int = research_turns - 1
		_update_facility_records(source_object_id, {"research_turns": next_turns})
		if next_turns > 0:
			_record_event("research_progress", {"player_id": owner_id, "facility_id": _facility_canonical_index(int(tile_value.get("index", -1))), "source_object_id": source_object_id, "tool_id": tool_id, "research_rank": research_tool, "research_turns": next_turns})
			continue
		var grant_result: Dictionary = OriginalInventory.grant_tool(state["inventory_supply"], player["tools"], tool_id)
		_record_event("research_produced", {"player_id": owner_id, "facility_id": _facility_canonical_index(int(tile_value.get("index", -1))), "source_object_id": source_object_id, "tool_id": tool_id, "research_rank": research_tool, "research_turns": 0, "granted": bool(grant_result.get("ok", false))})

static func _is_graph_road_tile(tile: Dictionary) -> bool:
	# The source selector accepts any reachable node with an adjacent edge. A
	# high status bit marks a blocked/object slot; the low event byte alone does
	# not make a node ineligible for a roadblock.
	if tile.has("status_bits"):
		var status_bits: Variant = tile.get("status_bits", null)
		if not _valid_int(status_bits, 0, 0xffffffff) or (int(status_bits) & 0x80ffff00) != 0:
			return false
	var adjacent: Variant = tile.get("adjacent", null)
	return typeof(adjacent) == TYPE_ARRAY and not adjacent.is_empty()


func _inventory_graph_node_reachable(node_id: int) -> bool:
	if not _is_graph():
		return false
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY or node_id < 0 or node_id >= board.size():
		return false
	var start_value: Variant = state.get("start_position", null)
	if not _valid_int(start_value, 0, board.size() - 1):
		return false
	var reachable: Dictionary = {int(start_value): true}
	var queue: Array = [int(start_value)]
	while not queue.is_empty():
		var current: int = int(queue.pop_front())
		if typeof(board[current]) != TYPE_DICTIONARY:
			continue
		var adjacent: Variant = board[current].get("adjacent", [])
		if typeof(adjacent) != TYPE_ARRAY:
			continue
		for neighbor in adjacent:
			if not _valid_int(neighbor, 0, board.size() - 1):
				continue
			var next_node: int = int(neighbor)
			if not reachable.has(next_node):
				reachable[next_node] = true
				queue.append(next_node)
	return reachable.has(node_id)


func _property_card_target_error(player_id: int, card_id: String, tile_id: Variant) -> String:
	if not _is_property_cards() or not _is_inventory() or not _is_graph():
		return "房產交換卡只適用於 v10 原版圖形地圖"
	if not PROPERTY_CARD_IDS.has(card_id):
		return "未知的房產交換卡"
	var phase: String = str(state.get("phase", ""))
	if phase not in ["await_roll", "await_action"]:
		return "房產交換卡只能在擲骰前或行動階段使用"
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return "目前玩家無法行動"
	if _status_active(player) or _is_gods_hospital_action(player):
		return "目前狀態無法使用房產交換卡"
	var cards: Variant = player.get("cards", [])
	if typeof(cards) != TYPE_ARRAY or not cards.has(card_id):
		return "沒有這張卡片"
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY or board.is_empty():
		return "房產交換地圖無效"
	var source_value: Variant = player.get("position", null)
	if not _valid_int(source_value, 0, board.size() - 1):
		return "目前位置無效"
	var source: Variant = board[int(source_value)]
	if typeof(source) != TYPE_DICTIONARY or not ["property", "facility"].has(str(source.get("kind", ""))):
		return "目前位置沒有可交換的地產"
	if not _valid_int(tile_id, 0, board.size() - 1):
		return "目標格位無效"
	var target_id: int = int(tile_id)
	if target_id == int(source_value):
		return "目標必須是另一處地產"
	var target_value: Variant = board[target_id]
	if typeof(target_value) != TYPE_DICTIONARY:
		return "目標格位無效"
	var target: Dictionary = target_value
	var source_kind: String = str(source.get("kind", ""))
	if str(target.get("kind", "")) != source_kind:
		return "房產交換卡只能指定同類地產"
	if source_kind == "facility":
		var source_object_id: Variant = source.get("source_object_id", null)
		var target_object_id: Variant = target.get("source_object_id", null)
		if not _valid_int(source_object_id, 1, 1999) or not _valid_int(target_object_id, 1, 1999):
			return "設施來源身分無效"
		if int(source_object_id) == int(target_object_id):
			return "同一設施的其他入口不能作為目標"
		for facility_value in [source, target]:
			var facility_type: Variant = facility_value.get("facility_type", null)
			var facility_level: Variant = facility_value.get("building_level", null)
			if not _facility_type_valid(facility_type) or not _valid_int(facility_level, 0, MAX_PROPERTY_LEVEL):
				return "設施狀態無效"
			if int(facility_level) > _facility_type_cap(int(facility_type)):
				return "設施等級超出類型上限"
	else:
		var source_object_id: Variant = source.get("source_object_id", null)
		var target_object_id: Variant = target.get("source_object_id", null)
		if not _valid_int(source_object_id, 1, 1999) or not _valid_int(target_object_id, 1, 1999):
			return "住宅來源身分無效"
		if int(source_object_id) == int(target_object_id):
			return "同一住宅不能作為目標"
	return ""


func _remodel_target_error(player_id: int, facility_type: Variant = null) -> String:
	if not _is_remodel() or not _is_inventory() or not _is_graph():
		return "改建卡只適用於 v11 原版圖形地圖"
	var phase: String = str(state.get("phase", ""))
	if phase not in ["await_roll", "await_action"]:
		return "改建卡只能在擲骰前或行動階段使用"
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return "目前玩家無法行動"
	if _status_active(player) or _is_gods_hospital_action(player):
		return "目前狀態無法使用改建卡"
	var cards: Variant = player.get("cards", [])
	if typeof(cards) != TYPE_ARRAY or not cards.has(REMODEL_CARD_ID):
		return "沒有這張卡片"
	var pending_remote: Variant = state.get("pending_remote_dice", {})
	if typeof(pending_remote) == TYPE_DICTIONARY and not pending_remote.is_empty():
		return "遙控骰子已經排程"
	var board: Variant = state.get("board", null)
	var position: Variant = player.get("position", null)
	if typeof(board) != TYPE_ARRAY or not _valid_int(position, 0, board.size() - 1):
		return "目前位置無效"
	var tile_value: Variant = board[int(position)]
	if typeof(tile_value) != TYPE_DICTIONARY:
		return "目前位置沒有可改建的地產"
	var tile: Dictionary = tile_value
	var kind: String = str(tile.get("kind", ""))
	if not ["property", "facility"].has(kind):
		return "目前位置沒有可改建的地產"
	var level_value: Variant = tile.get("building_level", null)
	if not _valid_int(level_value, 1, MAX_PROPERTY_LEVEL):
		return "目前地產尚未建成"
	if kind == "property":
		var chain_value: Variant = tile.get("is_chain_store", false)
		if typeof(chain_value) != TYPE_BOOL:
			return "住宅連鎖店狀態無效"
		if bool(chain_value) and int(level_value) != 1:
			return "連鎖店等級無效"
		return ""
	var facility: Dictionary = _facility_record(int(position))
	if facility.is_empty():
		return "設施狀態無效"
	var current_type: Variant = facility.get("facility_type", null)
	if not _facility_type_valid(current_type) or (int(current_type) == FACILITY_LAB_TYPE and not _is_research()):
		return "研究所尚未開放改建"
	if not _valid_int(facility.get("building_level", null), 1, MAX_PROPERTY_LEVEL):
		return "設施等級無效"
	if not _valid_int(facility_type, 0, FACILITY_LAB_TYPE if _is_research() else FACILITY_LAB_TYPE - 1):
		return "設施類型無效"
	return ""


func _use_remodel_card(player_id: int, facility_type: Variant = null, cancel: bool = false) -> Dictionary:
	if cancel:
		return _error("已取消改建卡")
	var target_error: String = _remodel_target_error(player_id, facility_type)
	if not target_error.is_empty():
		return _error(target_error)
	var player: Dictionary = _player(player_id)
	var position: int = int(player.get("position", -1))
	var tile: Dictionary = _tile_at(position)
	var kind: String = str(tile.get("kind", ""))
	var consume_result: Dictionary = OriginalInventory.consume_card(state["inventory_supply"], player["cards"], REMODEL_CARD_ID)
	if not bool(consume_result.get("ok", false)):
		return _error(str(consume_result.get("error", "卡片無法使用")))
	var effect: String = ""
	if kind == "property":
		var old_chain: bool = bool(tile.get("is_chain_store", false))
		var next_chain: bool = not old_chain
		tile["is_chain_store"] = next_chain
		if next_chain:
			tile["building_level"] = 1
		_update_tile_rent(tile)
		_recalculate_property_values()
		effect = "property_to_chain_store" if next_chain else "chain_store_to_property"
		_record_event("card_used", {"player_id": player_id, "card_id": REMODEL_CARD_ID, "tile_id": position, "level": int(tile.get("building_level", 0)), "is_chain_store": next_chain, "effect": effect})
		_set_action_options(player_id)
		return _result(true, "已改建住宅", {"card_id": REMODEL_CARD_ID, "tile_id": position, "level": int(tile.get("building_level", 0)), "is_chain_store": next_chain, "effect": effect})
	var requested_type: int = int(facility_type)
	var facility: Dictionary = _facility_record(position)
	var source_object_id: int = int(facility.get("source_object_id", -1))
	var current_type: int = int(facility.get("facility_type", -1))
	var current_level: int = int(facility.get("building_level", 0))
	var next_level: int = min(current_level, _facility_type_cap(requested_type))
	_update_facility_records(source_object_id, {"facility_type": requested_type, "building_level": next_level})
	_recalculate_property_values()
	effect = "remodel_facility"
	_record_event("card_used", {"player_id": player_id, "card_id": REMODEL_CARD_ID, "tile_id": _facility_canonical_index(position), "source_object_id": source_object_id, "from_facility_type": current_type, "facility_type": requested_type, "level": next_level, "effect": effect})
	_set_action_options(player_id)
	return _result(true, "已改建設施", {"card_id": REMODEL_CARD_ID, "tile_id": _facility_canonical_index(position), "source_object_id": source_object_id, "facility_type": requested_type, "level": next_level, "effect": effect})


func _property_card_canonical_tile_id(tile_id: int) -> int:
	var tile: Dictionary = _tile_at(tile_id)
	return _facility_canonical_index(tile_id) if tile.get("kind", "") == "facility" else tile_id


func _building_card_target_error(player_id: int, card_id: String, tile_id: Variant) -> String:
	if not _is_building_cards() or not _is_inventory() or not _is_graph():
		return "建物卡只適用於 v13 原版圖形地圖"
	if not BUILDING_CARD_IDS.has(card_id):
		return "未知的建物卡"
	var phase: String = str(state.get("phase", ""))
	if phase not in ["await_roll", "await_action"]:
		return "建物卡只能在擲骰前或行動階段使用"
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return "目前玩家無法行動"
	if _status_active(player) or _is_gods_hospital_action(player):
		return "目前狀態無法使用建物卡"
	var pending_remote: Variant = state.get("pending_remote_dice", {})
	if typeof(pending_remote) == TYPE_DICTIONARY and not pending_remote.is_empty():
		return "遙控骰子已經排程"
	var cards: Variant = player.get("cards", null)
	if typeof(cards) != TYPE_ARRAY or not cards.has(card_id):
		return "沒有這張卡片"
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY or not _valid_int(tile_id, 0, board.size() - 1):
		return "目標格位無效"
	var tile_value: Variant = board[int(tile_id)]
	if typeof(tile_value) != TYPE_DICTIONARY:
		return "目標格位無效"
	var tile: Dictionary = tile_value
	var kind: String = str(tile.get("kind", ""))
	if kind == "property":
		if card_id == "怪獸":
			var owner: int = int(tile.get("owner", -1))
			if owner == player_id:
				return "怪獸卡不能指定自己的建物"
			if int(tile.get("building_level", 0)) <= 0:
				return "怪獸卡只能指定已建成的建物"
		return ""
	if kind == "facility":
		var facility: Dictionary = _facility_record(int(tile_id))
		if facility.is_empty():
			return "設施狀態無效"
		if card_id == "怪獸":
			var facility_owner: int = int(facility.get("owner", -1))
			if facility_owner == player_id:
				return "怪獸卡不能指定自己的建物"
			if int(facility.get("building_level", 0)) <= 0:
				return "怪獸卡只能指定已建成的建物"
		return ""
	return "目標不是可作用的住宅或設施"


func _building_card_group_tiles(target_id: int) -> Array:
	var target: Dictionary = _tile_at(target_id)
	if target.is_empty() or target.get("kind", "") != "property":
		return []
	var target_group: String = str(target.get("group", ""))
	if target_group.is_empty():
		target_group = str(target.get("name", ""))
	var result: Array = []
	for index in range(state.get("board", []).size()):
		var candidate: Dictionary = _tile_at(index)
		if candidate.get("kind", "") != "property":
			continue
		var candidate_group: String = str(candidate.get("group", ""))
		if candidate_group.is_empty():
			candidate_group = str(candidate.get("name", ""))
		if candidate_group == target_group:
			result.append(index)
	return result


func _building_card_facility_tiles(target_id: int) -> Array:
	var target: Dictionary = _tile_at(target_id)
	if target.is_empty() or target.get("kind", "") != "facility":
		return []
	var source_object_id: int = int(target.get("source_object_id", -1))
	return _facility_indices(source_object_id)


func _use_building_card(player_id: int, card_id: String, tile_id: Variant, cancel: bool = false, facility_type: Variant = null) -> Dictionary:
	if cancel:
		return _error("已取消建物卡")
	var target_error: String = _building_card_target_error(player_id, card_id, tile_id)
	if not target_error.is_empty():
		return _error(target_error)
	var target_id: int = int(tile_id)
	var target: Dictionary = _tile_at(target_id)
	var affected_ids: Array = []
	var effect: String = ""
	var facility: Dictionary = {}
	var selected_facility_type: Variant = null
	if target.get("kind", "") == "facility":
		affected_ids = _building_card_facility_tiles(target_id)
		if affected_ids.is_empty():
			return _error("設施來源無效")
		facility = _facility_record(target_id)
		if card_id == "天使":
			selected_facility_type = facility_type
			var current_level: int = int(facility.get("building_level", 0))
			var current_type: int = int(facility.get("facility_type", 0))
			if current_level > 0 and selected_facility_type != null and (not _facility_type_valid(selected_facility_type) or int(selected_facility_type) != current_type):
				return _error("已建成的設施不能更換類型")
			if selected_facility_type == null:
				if current_level <= 0:
					return _error("設施尚未建成，請選擇設施類型")
				selected_facility_type = current_type
			if not _facility_type_valid(selected_facility_type):
				return _error("設施類型無效")
	var player: Dictionary = _player(player_id)
	var consume_result: Dictionary = OriginalInventory.consume_card(state["inventory_supply"], player["cards"], card_id)
	if not bool(consume_result.get("ok", false)):
		return _error(str(consume_result.get("error", "卡片無法使用")))
	if target.get("kind", "") == "property":
		affected_ids = _building_card_group_tiles(target_id) if card_id in ["天使", "惡魔"] else [target_id]
		if card_id == "天使":
			for affected_id in affected_ids:
				var angel_tile: Dictionary = _tile_at(int(affected_id))
				var angel_cap: int = 1 if bool(angel_tile.get("is_chain_store", false)) else MAX_PROPERTY_LEVEL
				angel_tile["building_level"] = min(int(angel_tile.get("building_level", 0)) + 1, angel_cap)
				_update_tile_rent(angel_tile)
			effect = "angel_raise_group"
		elif card_id == "惡魔":
			for affected_id in affected_ids:
				var demon_tile: Dictionary = _tile_at(int(affected_id))
				demon_tile["building_level"] = 0
				demon_tile["is_chain_store"] = false
				_update_tile_rent(demon_tile)
			effect = "demon_clear_group"
		else:
			var monster_tile: Dictionary = target
			monster_tile["building_level"] = 0
			monster_tile["is_chain_store"] = false
			_update_tile_rent(monster_tile)
			effect = "monster_clear_building"
	else:
		if card_id == "天使":
			var cap: int = _facility_type_cap(int(selected_facility_type))
			var next_level: int = min(int(facility.get("building_level", 0)) + 1, cap)
			_update_facility_records(int(facility.get("source_object_id", -1)), {"facility_type": int(selected_facility_type), "building_level": next_level})
			effect = "angel_raise_facility"
		elif card_id == "惡魔":
			_update_facility_records(int(facility.get("source_object_id", -1)), {"facility_type": 0, "building_level": 0})
			effect = "demon_clear_facility"
		else:
			_update_facility_records(int(facility.get("source_object_id", -1)), {"facility_type": 0, "building_level": 0})
			effect = "monster_clear_facility"
	_recalculate_property_values()
	var event_payload: Dictionary = {"player_id": player_id, "card_id": card_id, "tile_id": target_id, "target_tile_id": target_id, "affected_tile_ids": affected_ids, "effect": effect}
	if target.get("kind", "") == "facility":
		event_payload["facility_id"] = target_id
		event_payload["source_object_id"] = int(target.get("source_object_id", -1))
	_record_event("card_used", event_payload)
	_set_action_options(player_id)
	return _result(true, "已使用%s卡" % card_id, {"card_id": card_id, "tile_id": target_id, "affected_tile_ids": affected_ids, "effect": effect})


func _swap_property_references(source_tile_id: int, target_tile_id: int, source_owner: int, target_owner: int) -> void:
	if source_owner == target_owner:
		return
	for player in _players():
		var player_id: int = int(player.get("id", -1))
		_remove_property_reference(player_id, source_tile_id)
		_remove_property_reference(player_id, target_tile_id)
	if source_owner >= 0:
		_add_property_reference(source_owner, target_tile_id)
	if target_owner >= 0:
		_add_property_reference(target_owner, source_tile_id)


func _use_property_card(player_id: int, card_id: String, tile_id: Variant, cancel: bool = false) -> Dictionary:
	if cancel:
		return _error("已取消房產交換卡")
	var target_error: String = _property_card_target_error(player_id, card_id, tile_id)
	if not target_error.is_empty():
		return _error(target_error)
	var player: Dictionary = _player(player_id)
	var source_index: int = int(player.get("position", -1))
	var target_index: int = int(tile_id)
	var source_tile: Dictionary = _tile_at(source_index)
	var target_tile: Dictionary = _tile_at(target_index)
	var source_kind: String = str(source_tile.get("kind", ""))
	var source_asset_id: int = _property_card_canonical_tile_id(source_index)
	var target_asset_id: int = _property_card_canonical_tile_id(target_index)
	var source_owner: int = int(source_tile.get("owner", -1))
	var target_owner: int = int(target_tile.get("owner", -1))
	if source_kind == "facility":
		source_owner = int(_facility_record(source_index).get("owner", source_owner))
		target_owner = int(_facility_record(target_index).get("owner", target_owner))
	var consume_result: Dictionary = OriginalInventory.consume_card(state["inventory_supply"], player["cards"], card_id)
	if not bool(consume_result.get("ok", false)):
		return _error(str(consume_result.get("error", "卡片無法使用")))
	if card_id == "換地":
		if source_kind == "facility":
			_update_facility_records(int(source_tile.get("source_object_id", -1)), {"owner": target_owner})
			_update_facility_records(int(target_tile.get("source_object_id", -1)), {"owner": source_owner})
		else:
			source_tile["owner"] = target_owner
			target_tile["owner"] = source_owner
		_swap_property_references(source_asset_id, target_asset_id, source_owner, target_owner)
		_recalculate_property_values()
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "source_tile_id": source_asset_id, "target_tile_id": target_asset_id, "effect": "swap_ownership"})
		_set_action_options(player_id)
		return _result(true, "已交換地產所有權", {"card_id": card_id, "source_tile_id": source_asset_id, "target_tile_id": target_asset_id, "effect": "swap_ownership"})
	var source_level: int = int(source_tile.get("building_level", 0))
	var target_level: int = int(target_tile.get("building_level", 0))
	if source_kind == "facility":
		var source_type: int = int(source_tile.get("facility_type", 0))
		var target_type: int = int(target_tile.get("facility_type", 0))
		_update_facility_records(int(source_tile.get("source_object_id", -1)), {"building_level": target_level, "facility_type": target_type})
		_update_facility_records(int(target_tile.get("source_object_id", -1)), {"building_level": source_level, "facility_type": source_type})
	else:
		source_tile["building_level"] = target_level
		target_tile["building_level"] = source_level
		if _is_remodel():
			var source_chain: bool = bool(source_tile.get("is_chain_store", false))
			var target_chain: bool = bool(target_tile.get("is_chain_store", false))
			source_tile["is_chain_store"] = target_chain
			target_tile["is_chain_store"] = source_chain
		_update_tile_rent(source_tile)
		_update_tile_rent(target_tile)
	_recalculate_property_values()
	_record_event("card_used", {"player_id": player_id, "card_id": card_id, "source_tile_id": source_asset_id, "target_tile_id": target_asset_id, "effect": "swap_buildings"})
	_set_action_options(player_id)
	return _result(true, "已交換地產建物", {"card_id": card_id, "source_tile_id": source_asset_id, "target_tile_id": target_asset_id, "effect": "swap_buildings"})


func _inventory_target_error(player_id: int, item_id: String, tile_id: Variant) -> String:
	if not _is_inventory() or not _is_graph():
		return "此效果只適用於原版圖形地圖"
	if BUILDING_CARD_IDS.has(item_id):
		return _building_card_target_error(player_id, item_id, tile_id)
	if PROPERTY_CARD_IDS.has(item_id):
		return _property_card_target_error(player_id, item_id, tile_id)
	if MissileRules.is_missile(item_id):
		return MissileRules.target_error(self, player_id, item_id, tile_id)
	if item_id in ["地雷", "定時炸彈"]:
		return _hazard_target_error(player_id, item_id, tile_id)
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return "目前玩家無法行動"
	if item_id in ["路障", "機器工人"] and state.get("phase", "") != "await_roll":
		return "道具只能在擲骰前使用"
	if item_id in ["拆除", "漲價", "查封"] and not state.get("phase", "") in ["await_roll", "await_action"]:
		return "卡片只能在行動前使用"
	if item_id in ["路障", "機器工人", "拆除", "漲價", "查封"]:
		var pending_remote: Variant = state.get("pending_remote_dice", {})
		if typeof(pending_remote) == TYPE_DICTIONARY and not pending_remote.is_empty():
			return "遙控骰子已經排程"
	if _inventory_movement_blocked(player) and item_id in ["路障", "機器工人"]:
		return "目前移動狀態無法使用道具"
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY or not _valid_int(tile_id, 0, board.size() - 1):
		return "目標格位無效"
	var target_id: int = int(tile_id)
	var tile_value: Variant = board[target_id]
	if typeof(tile_value) != TYPE_DICTIONARY:
		return "目標格位無效"
	var tile: Dictionary = tile_value
	var cards: Array = player.get("cards", [])
	var tools: Dictionary = player.get("tools", {})
	if item_id == "路障":
		if int(tools.get(item_id, 0)) <= 0:
			return "玩家沒有這項道具"
		if not _is_graph_road_tile(tile):
			return "路障只能放在可通行道路"
		if not _inventory_graph_node_reachable(target_id):
			return "道路節點無法從起點到達"
		var roadblocks_value: Variant = state.get("roadblocks", null)
		if typeof(roadblocks_value) != TYPE_DICTIONARY:
			return "路障狀態格式無效"
		if roadblocks_value.size() >= MAX_INVENTORY_ROADBLOCKS:
			return "路障已達同時放置上限"
		if roadblocks_value.has(str(target_id)):
			return "目標道路已有路障"
		if _is_hazards() and (_ground_hazard_at(target_id).size() > 0 or _unbound_god_at(target_id)):
			return "目標道路已有物件"
		for candidate in _players():
			var candidate_position: Variant = candidate.get("position", null)
			if _valid_bool(candidate.get("alive", null)) and bool(candidate.get("alive", false)) and _valid_int(candidate_position, 0, board.size() - 1) and int(candidate_position) == target_id:
				return "目標道路已有存活玩家"
		return ""
	if item_id == "機器工人":
		if int(tools.get(item_id, 0)) <= 0:
			return "玩家沒有這項道具"
		if tile.get("kind", "") == "facility":
			var worker_facility: Dictionary = _facility_record(target_id)
			if int(worker_facility.get("owner", -1)) < 0 or int(worker_facility.get("building_level", 0)) <= 0:
				return "機器工人只能作用於已建成的設施"
			var worker_facility_type: int = int(worker_facility.get("facility_type", -1))
			if not _facility_type_valid(worker_facility_type) or (worker_facility_type == FACILITY_LAB_TYPE and not _is_research()):
				return "研究所尚未開放升級"
			if int(worker_facility.get("building_level", 0)) >= _facility_type_cap(worker_facility_type):
				return "設施已達最高等級"
			return ""
		if tile.get("kind", "") != "property" or int(tile.get("owner", -1)) < 0:
			return "機器工人只能作用於已持有的住宅或設施"
		var property_level: int = int(tile.get("building_level", 0))
		var property_cap: int = _property_level_cap(tile, _is_remodel())
		if property_level >= property_cap:
			return "連鎖店已達最高一級" if property_cap == 1 else "住宅已達最高五級"
		return ""
	if item_id == "拆除":
		if cards.find(item_id) < 0:
			return "沒有這張卡片"
		if tile.get("kind", "") in ["property", "facility"] and int(tile.get("building_level", 0)) > 0:
			return ""
		var demolition_roadblocks: Variant = state.get("roadblocks", {})
		if typeof(demolition_roadblocks) == TYPE_DICTIONARY and demolition_roadblocks.has(str(target_id)):
			return ""
		return "目標沒有可拆除物"
	if item_id == "漲價" or item_id == "查封":
		if cards.find(item_id) < 0:
			return "沒有這張卡片"
		if tile.get("kind", "") != "facility" or not _is_facilities():
			return "此卡片只能作用於已建成的設施"
		var status_facility: Dictionary = _facility_record(target_id)
		var status_owner: int = int(status_facility.get("owner", -1))
		var status_level: int = int(status_facility.get("building_level", 0))
		var status_type: int = int(status_facility.get("facility_type", -1))
		if status_owner < 0 or status_level <= 0 or not _facility_type_valid(status_type) or (status_type == FACILITY_LAB_TYPE and not _is_research()):
			return "目標設施尚未提供服務"
		if item_id == "漲價" and status_owner != player_id:
			return "漲價卡只能指定自己的設施"
		if item_id == "查封" and status_owner == player_id:
			return "查封卡只能指定其他玩家的設施"
		return ""
	return "未知的目標效果"


func inventory_target_tiles(item_id: String) -> Array:
	var targets: Array = []
	if not _is_inventory() or not _is_graph():
		return targets
	var normalized_item_id: String = item_id.strip_edges()
	if MissileRules.is_missile(normalized_item_id):
		return MissileRules.target_tiles(self, int(state.get("current_player", -1)), normalized_item_id)
	var player_id: int = int(state.get("current_player", -1))
	var board: Array = state.get("board", [])
	for tile_id in range(board.size()):
		if _inventory_target_error(player_id, normalized_item_id, tile_id).is_empty():
			targets.append(tile_id)
	return targets


func god_card_target(player_id: int, visible_tile_ids: Variant = null) -> Dictionary:
	if not _is_inventory() or not _is_gods() or not _is_graph():
		return {}
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return {}
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY or board.is_empty():
		return {}
	var position: Variant = player.get("position", null)
	if not _valid_int(position, 0, board.size() - 1):
		return {}
	var origin_value: Variant = board[int(position)]
	if typeof(origin_value) != TYPE_DICTIONARY:
		return {}
	var origin: Dictionary = origin_value
	if not _valid_int(origin.get("x", null), -1000000, 1000000) or not _valid_int(origin.get("y", null), -1000000, 1000000):
		return {}

	var visible_nodes: Dictionary = {}
	if visible_tile_ids != null:
		if typeof(visible_tile_ids) != TYPE_ARRAY:
			return {}
		for visible_value in visible_tile_ids:
			if not _valid_int(visible_value, 0, board.size() - 1):
				return {}
			visible_nodes[int(visible_value)] = true

	var objects: Variant = state.get("god_objects", null)
	if typeof(objects) != TYPE_ARRAY:
		return {}
	var selected: Dictionary = {}
	var selected_distance: float = 0.0
	var selected_id: int = 0
	for actor_value in objects:
		if typeof(actor_value) != TYPE_DICTIONARY:
			continue
		var actor: Dictionary = actor_value
		var god_id_value: Variant = actor.get("id", null)
		if not _valid_int(god_id_value, 1, 15) or not OriginalGods.valid_id(god_id_value):
			continue
		var god_id: int = int(god_id_value)
		if not OriginalGods.is_spawnable(god_id) or not OriginalGods.is_attachable(god_id):
			continue
		var owner_value: Variant = actor.get("owner", null)
		if not _valid_int(owner_value, -1, -1):
			continue
		var node_value: Variant = actor.get("node", null)
		if not _valid_int(node_value, 0, board.size() - 1):
			continue
		var node: int = int(node_value)
		if visible_tile_ids != null and not visible_nodes.has(node):
			continue
		var node_tile_value: Variant = board[node]
		if typeof(node_tile_value) != TYPE_DICTIONARY:
			continue
		var node_tile: Dictionary = node_tile_value
		if not _valid_int(node_tile.get("x", null), -1000000, 1000000) or not _valid_int(node_tile.get("y", null), -1000000, 1000000):
			continue
		var days_value: Variant = actor.get("days", null)
		if not _valid_int(days_value, 0, 13):
			continue
		var dx: float = float(int(node_tile.get("x")) - int(origin.get("x")))
		var dy: float = float(int(node_tile.get("y")) - int(origin.get("y")))
		var distance_squared: float = dx * dx + dy * dy
		if distance_squared >= 100000000.0:
			continue
		var is_better: bool = selected.is_empty() or distance_squared < selected_distance or (distance_squared == selected_distance and god_id < selected_id)
		if not is_better:
			continue
		selected = {"id": god_id, "node": node, "owner": -1, "days": int(days_value)}
		selected_distance = distance_squared
		selected_id = god_id
	return selected


func _is_graph() -> bool:
	return state.get("board_mode", "") == GRAPH_BOARD_MODE


func _stationary_turn() -> bool:
	var value: Variant = state.get("stationary_turn", false)
	return typeof(value) == TYPE_BOOL and bool(value)


func item_is_implemented(item_kind: String, item_id: String) -> bool:
	var normalized_kind := item_kind.to_lower().strip_edges()
	if normalized_kind == "card":
		if SleepRules.is_sleep_card(item_id):
			return _is_inventory() and _is_statuses()
		if FinancialRules.is_financial_card(item_id):
			return _is_inventory()
		if AllianceRules.is_alliance_card(item_id):
			return _is_inventory()
		if BUILDING_CARD_IDS.has(item_id):
			return _is_building_cards()
		if GOD_CARD_IDS.has(item_id):
			return _is_inventory() and _is_gods() and _is_graph()
		if item_id == AuctionRules.CARD_ID:
			return _is_inventory() and _is_graph() and _is_gods()
		if item_id == REMODEL_CARD_ID:
			return _is_remodel()
		if PROPERTY_CARD_IDS.has(item_id):
			return _is_property_cards()
		if item_id in ["漲價", "查封"] and not _is_facilities():
			return false
		if STATUS_CARD_IDS.has(item_id):
			return _is_statuses()
		return IMPLEMENTED_CARD_IDS.has(item_id)
	if normalized_kind == "tool":
		if item_id in [TimeTransportRules.TIME_MACHINE, TimeTransportRules.TRANSPORTER]:
			return TimeTransportRules.is_supported(self)
		if item_id in ["地雷", "定時炸彈", "機器娃娃"]:
			return _is_hazards()
		if MissileRules.is_missile(item_id):
			return MissileRules.supports(self)
		return IMPLEMENTED_TOOL_IDS.has(item_id)
	return false


func is_shop_available() -> bool:
	if not _is_inventory() or not _is_graph() or state.get("phase", "") != "await_action":
		return false
	var player: Dictionary = _current_player()
	if player.is_empty() or not bool(player.get("alive", false)):
		return false
	if _is_gods_hospital_action(player):
		return false
	var tile: Dictionary = _tile_at(int(player.get("position", -1)))
	return not tile.is_empty() and int(tile.get("event_code", -1)) == 15


func _inventory_record(item_kind: String, item_id: String) -> Dictionary:
	var normalized_kind := item_kind.to_lower().strip_edges()
	if normalized_kind == "card":
		return OriginalInventoryCatalogue.card(item_id)
	if normalized_kind == "tool":
		return OriginalInventoryCatalogue.tool(item_id)
	return {}


func _shop_item_owned(player: Dictionary, item_kind: String, item_id: String) -> int:
	if item_kind == "card":
		var cards: Array = player.get("cards", [])
		var count: int = 0
		for card_id in cards:
			if str(card_id) == item_id:
				count += 1
		return count
	var tools: Dictionary = player.get("tools", {})
	return int(tools.get(item_id, 0))


func _shop_item_equipped(player: Dictionary, item_kind: String, item_id: String) -> int:
	if item_kind != "tool":
		return 0
	var active_tool_id: String = _inventory_vehicle_tool_id(str(player.get("vehicle", "walking")))
	return 1 if active_tool_id == item_id else 0


func shop_items() -> Array:
	var items: Array = []
	if not _is_inventory():
		return items
	var supply: Dictionary = state.get("inventory_supply", {})
	var card_supply: Dictionary = supply.get("cards", {})
	var tool_supply: Dictionary = supply.get("tools", {})
	var player: Dictionary = _current_player()
	for record in OriginalInventoryCatalogue.cards():
		var item_id: String = str(record["id"])
		items.append({
			"item_kind": "card",
			"item_id": item_id,
			"name": str(record["name"]),
			"price": OriginalInventory.quote_buy("card", item_id, 1),
			"sale_price": OriginalInventory.quote_sale("card", item_id, 1),
			"stock": int(card_supply.get(item_id, 0)),
			"owned": _shop_item_owned(player, "card", item_id),
			"equipped": 0,
			"implemented": item_is_implemented("card", item_id),
		})
	for record in OriginalInventoryCatalogue.tools():
		if int(record["source_id"]) > OriginalInventory.FINITE_TOOL_SOURCE_ID_MAX:
			continue
		var item_id: String = str(record["id"])
		items.append({
			"item_kind": "tool",
			"item_id": item_id,
			"name": str(record["name"]),
			"price": OriginalInventory.quote_buy("tool", item_id, 1),
			"sale_price": OriginalInventory.quote_sale("tool", item_id, 1),
			"stock": int(tool_supply.get(item_id, 0)),
			"owned": _shop_item_owned(player, "tool", item_id),
			"equipped": _shop_item_equipped(player, "tool", item_id),
			"implemented": item_is_implemented("tool", item_id),
		})
	return items


func _array_contains_int(values: Variant, target: int) -> bool:
	if typeof(values) != TYPE_ARRAY:
		return false
	for value in values:
		if _valid_int(value) and int(value) == target:
			return true
	return false


func _upgrade_price(tile: Dictionary) -> int:
	if _is_graph():
		# The original housing record stores one house price.  Each level uses
		# that same price; the rent table, rather than a guessed multiplier,
		# determines the resulting rent.
		return int(tile.get("house_price", tile.get("upgrade_cost", 0)))
	return int(tile.get("upgrade_cost", 0)) * (int(tile.get("building_level", 0)) + 1)


func _player_owns_tile(player_id: int, tile_index: int) -> bool:
	var tile: Dictionary = _tile_at(tile_index)
	return int(tile.get("owner", -1)) == player_id


func set_player_ai(player_id: int, enabled: bool) -> bool:
	if _trap_pending():
		return false
	if not _valid_player(player_id):
		return false
	var player: Dictionary = _player(player_id)
	player["is_ai"] = enabled
	player["is_human"] = not enabled
	return true


func _inventory_vehicle_tool_id(vehicle: String) -> String:
	return str(VEHICLE_TOOL_IDS.get(vehicle, ""))


func _engineering_activation(player_id: int) -> Dictionary:
	if not _is_inventory():
		return _error("工程車只適用於道具地圖")
	if _stationary_turn():
		return _error("停留回合無法使用工程車")
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return _error("目前玩家無法行動")
	if _status_active(player) or _is_gods_hospital_action(player):
		return _error("目前狀態無法使用工程車")
	if _inventory_movement_blocked(player):
		return _error("目前移動狀態無法使用工程車")
	if EngineeringVehicle.is_active(player):
		return _error("工程車效果已經啟用")
	if player.has("engineering_vehicle"):
		return _error("工程車狀態無效")
	var tools_value: Variant = player.get("tools", {})
	if typeof(tools_value) != TYPE_DICTIONARY or int(tools_value.get("工程車", 0)) <= 0:
		return _error("玩家沒有這項道具")
	var previous_vehicle: String = str(player.get("vehicle", "walking"))
	if not EngineeringVehicle.ORDINARY_DICE.has(previous_vehicle):
		return _error("目前交通工具無效")
	var previous_dice: Variant = player.get("dice_count", null)
	if typeof(previous_dice) != TYPE_INT or int(previous_dice) < 1 or int(previous_dice) > EngineeringVehicle.ordinary_dice(previous_vehicle):
		return _error("目前骰子數量無效")
	var staged_tools: Dictionary = tools_value.duplicate(true)
	var engineer_quantity: int = int(staged_tools.get("工程車", 0)) - 1
	if engineer_quantity <= 0:
		staged_tools.erase("工程車")
	else:
		staged_tools["工程車"] = engineer_quantity
	var previous_tool_id: String = _inventory_vehicle_tool_id(previous_vehicle)
	if not previous_tool_id.is_empty():
		if int(staged_tools.get(previous_tool_id, 0)) >= OriginalInventory.VEHICLE_STORAGE_CAPACITY:
			return _error("道具數量超出上限")
		staged_tools[previous_tool_id] = int(staged_tools.get(previous_tool_id, 0)) + 1
	player["tools"] = staged_tools
	player["vehicle"] = EngineeringVehicle.VEHICLE_ID
	player["dice_count"] = 1
	player["engineering_vehicle"] = EngineeringVehicle.metadata(previous_vehicle, int(previous_dice))
	_record_event("tool_used", {"player_id": player_id, "tool_id": "工程車", "effect": "engineering_vehicle", "vehicle": EngineeringVehicle.VEHICLE_ID, "previous_vehicle": previous_vehicle, "previous_dice_count": int(previous_dice), "remaining_admissions": EngineeringVehicle.MAX_ADMISSIONS})
	_set_action_options(player_id)
	return _result(true, "已啟用工程車", {"tool_id": "工程車", "vehicle": EngineeringVehicle.VEHICLE_ID, "remaining_admissions": EngineeringVehicle.MAX_ADMISSIONS})


func _engineering_admit(player_id: int) -> void:
	if not _is_inventory() or not _valid_player(player_id, true):
		return
	var player: Dictionary = _player(player_id)
	if not EngineeringVehicle.is_active(player):
		return
	var timer: Dictionary = EngineeringVehicle.tick(player.get("engineering_vehicle", null))
	if not bool(timer.get("ok", false)):
		player.erase("engineering_vehicle")
		player["vehicle"] = "walking"
		player["dice_count"] = 1
		return
	if not bool(timer.get("expired", false)):
		player["engineering_vehicle"] = timer.get("metadata", {})
		return
	var metadata_value: Dictionary = timer.get("metadata", {})
	var previous_vehicle: String = str(metadata_value.get("previous_vehicle", "walking"))
	var previous_tool_id: String = _inventory_vehicle_tool_id(previous_vehicle)
	var available: bool = previous_tool_id.is_empty() or int(player.get("tools", {}).get(previous_tool_id, 0)) > 0
	var restored: Dictionary = EngineeringVehicle.restore(metadata_value, available)
	var restored_vehicle: String = str(restored.get("vehicle", "walking"))
	var restored_dice: int = int(restored.get("dice_count", 1))
	if available and not previous_tool_id.is_empty():
		_hazard_consume_tool_without_supply(player, previous_tool_id)
	var vehicles: Dictionary = player.get("vehicles", {}).duplicate(true)
	vehicles[restored_vehicle] = true
	player["vehicles"] = vehicles
	player["vehicle"] = restored_vehicle
	player["dice_count"] = restored_dice
	player.erase("engineering_vehicle")
	_record_event("engineering_expired", {"player_id": player_id, "previous_vehicle": previous_vehicle, "previous_dice_count": int(metadata_value.get("previous_dice_count", 1)), "restored_vehicle": restored_vehicle, "restored_dice_count": restored_dice, "restored_from_held": available})


func _engineering_landing_target(player_id: int, allow_unowned: bool = false) -> Dictionary:
	if not _is_inventory() or not _is_graph() or state.get("phase", "") != "await_action":
		return {}
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return {}
	if _stationary_turn():
		return {}
	if typeof(state.get("last_roll", [])) != TYPE_ARRAY or state.get("last_roll", []).is_empty():
		return {}
	var tile: Dictionary = _tile_at(int(player.get("position", -1)))
	if tile.is_empty():
		return {}
	var owner_id: int = int(tile.get("owner", -1))
	var level: int = int(tile.get("building_level", 0))
	if tile.get("kind", "") == "facility":
		tile = _facility_record(int(tile.get("index", -1)))
		owner_id = int(tile.get("owner", -1))
		level = int(tile.get("building_level", 0))
	if tile.get("kind", "") not in ["property", "facility"] or owner_id == player_id or level <= 0 or (owner_id < 0 and not allow_unowned):
		return {}
	return tile


func _engineering_ai_action(player_id: int) -> bool:
	var player: Dictionary = _player(player_id)
	if player.is_empty() or _sleep_active(player):
		return false
	var target: Dictionary = _engineering_landing_target(player_id)
	if target.is_empty():
		return false
	if int(player.get("tools", {}).get("工程車", 0)) > 0:
		var result: Dictionary = _engineering_activation(player_id)
		return bool(result.get("ok", false))
	return false


func _engineering_demolition(player_id: int) -> void:
	if not _is_inventory() or _sleep_active(_player(player_id)) or _stationary_turn() or not EngineeringVehicle.is_active(_player(player_id)):
		return
	var target: Dictionary = _engineering_landing_target(player_id, true)
	if target.is_empty():
		return
	var tile_id: int = int(target.get("index", -1))
	var owner_id: int = int(target.get("owner", -1))
	var level: int = int(target.get("building_level", 0))
	var next_level: int = 0
	var payload: Dictionary = {"player_id": player_id, "tile_id": tile_id, "owner_id": owner_id, "kind": str(target.get("kind", "")), "from_level": level, "to_level": next_level}
	if target.get("kind", "") == "facility":
		var source_object_id: int = int(target.get("source_object_id", -1))
		_update_facility_records(source_object_id, {"building_level": next_level, "facility_type": 0 if next_level == 0 else int(target.get("facility_type", 0))})
		payload["source_object_id"] = source_object_id
	else:
		target["building_level"] = next_level
		if _is_remodel() and next_level == 0:
			target["is_chain_store"] = false
		_update_tile_rent(target)
	_recalculate_property_values()
	_record_event("engineering_demolition", payload)


static func _inventory_movement_blocked(player: Dictionary) -> bool:
	for field in ["skip_turns", "turtle_days", "stay_next"]:
		if _valid_int(player.get(field, 0), 1):
			return true
	return false


func _ground_hazard_at(node_id: int) -> Dictionary:
	if not _is_hazards():
		return {}
	var hazards: Variant = state.get("ground_hazards", {})
	if typeof(hazards) != TYPE_DICTIONARY:
		return {}
	var value: Variant = hazards.get(str(node_id), null)
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _ground_hazard_counts() -> Dictionary:
	var counts: Dictionary = {"mine": 0, "timed_bomb": 0}
	if not _is_hazards():
		return counts
	var hazards: Variant = state.get("ground_hazards", {})
	if typeof(hazards) != TYPE_DICTIONARY:
		return counts
	for value in hazards.values():
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var kind := str(value.get("kind", ""))
		if counts.has(kind):
			counts[kind] = int(counts[kind]) + 1
	return counts


func _carried_bomb_count() -> int:
	if not _is_hazards():
		return 0
	var total := 0
	for player in _players():
		if typeof(player) == TYPE_DICTIONARY and _valid_int(player.get("bomb_steps", 0), 1, MAX_BOMB_STEPS):
			total += 1
	return total


func _hazard_route_overlap_allowed(node_id: int) -> bool:
	if not _is_hazards() or state.get("phase", "") != "await_route":
		return false
	var remaining: Variant = state.get("remaining_steps", null)
	if not _valid_int(remaining, 1, MAX_GRAPH_STEPS):
		return false
	var current_player_id: Variant = state.get("current_player", null)
	if not _valid_int(current_player_id, 0, _players().size() - 1):
		return false
	var player: Dictionary = _player(int(current_player_id))
	return not player.is_empty() and _valid_int(player.get("position", null), node_id, node_id)


func _unbound_god_at(node_id: int) -> bool:
	if not _is_gods():
		return false
	var objects: Variant = state.get("god_objects", [])
	if typeof(objects) != TYPE_ARRAY:
		return false
	for actor in objects:
		if typeof(actor) == TYPE_DICTIONARY and int(actor.get("owner", -1)) < 0 and int(actor.get("node", -1)) == node_id:
			return true
	return false


func _dynamic_road_object_at(node_id: int) -> bool:
	if not _is_graph():
		return false
	var roadblocks: Variant = state.get("roadblocks", {})
	if typeof(roadblocks) == TYPE_DICTIONARY and roadblocks.has(str(node_id)):
		return true
	if not _ground_hazard_at(node_id).is_empty():
		return true
	return _unbound_god_at(node_id)


func _hazard_return_active_vehicle(player: Dictionary) -> String:
	if player.is_empty():
		return ""
	var vehicle := str(player.get("vehicle", "walking"))
	if vehicle == EngineeringVehicle.VEHICLE_ID:
		player.erase("engineering_vehicle")
		player["vehicle"] = "walking"
		player["dice_count"] = 1
		return vehicle
	var tool_id := _inventory_vehicle_tool_id(vehicle)
	if not tool_id.is_empty() and _is_inventory():
		var supply: Variant = state.get("inventory_supply", {})
		if typeof(supply) == TYPE_DICTIONARY and typeof(supply.get("tools", null)) == TYPE_DICTIONARY:
			var tools: Dictionary = supply["tools"]
			tools[tool_id] = int(tools.get(tool_id, 0)) + 1
	player["vehicle"] = "walking"
	player["dice_count"] = 1
	return vehicle


func _hazard_return_tool_to_supply(tool_id: String) -> void:
	if not _is_inventory():
		return
	var supply: Variant = state.get("inventory_supply", {})
	if typeof(supply) == TYPE_DICTIONARY and typeof(supply.get("tools", null)) == TYPE_DICTIONARY:
		var tools: Dictionary = supply["tools"]
		tools[tool_id] = int(tools.get(tool_id, 0)) + 1


func _hazard_consume_tool_without_supply(player: Dictionary, tool_id: String) -> bool:
	var tools: Variant = player.get("tools", {})
	if typeof(tools) != TYPE_DICTIONARY or int(tools.get(tool_id, 0)) <= 0:
		return false
	var quantity: int = int(tools.get(tool_id, 0)) - 1
	if quantity <= 0:
		tools.erase(tool_id)
	else:
		tools[tool_id] = quantity
	return true


func _hazard_target_error(player_id: int, item_id: String, tile_id: Variant) -> String:
	if not _is_hazards() or not ["地雷", "定時炸彈"].has(item_id):
		return "此危險物只適用於 v9 原作道路模式"
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return "目前玩家無法行動"
	if state.get("phase", "") != "await_roll":
		return "危險物只能在擲骰前使用"
	if _inventory_movement_blocked(player):
		return "目前移動狀態無法使用危險物"
	var pending_remote: Variant = state.get("pending_remote_dice", {})
	if typeof(pending_remote) == TYPE_DICTIONARY and not pending_remote.is_empty():
		return "遙控骰子已經排程"
	var tools: Variant = player.get("tools", {})
	if typeof(tools) != TYPE_DICTIONARY or int(tools.get(item_id, 0)) <= 0:
		return "玩家沒有這項道具"
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY or not _valid_int(tile_id, 0, board.size() - 1):
		return "目標格位無效"
	var target_id := int(tile_id)
	var tile_value: Variant = board[target_id]
	if typeof(tile_value) != TYPE_DICTIONARY or not _is_graph_road_tile(tile_value):
		return "危險物只能放在可通行道路"
	if not _inventory_graph_node_reachable(target_id):
		return "道路節點無法從起點到達"
	if _dynamic_road_object_at(target_id):
		return "目標道路已有物件"
	for candidate in _players():
		if typeof(candidate) != TYPE_DICTIONARY or not bool(candidate.get("alive", false)):
			continue
		if _valid_int(candidate.get("position", null), target_id, target_id):
			return "目標道路已有存活玩家"
	var counts := _ground_hazard_counts()
	if item_id == "地雷" and int(counts.get("mine", 0)) >= MAX_GROUND_MINES:
		return "地雷已達同時放置上限"
	if item_id == "定時炸彈" and int(counts.get("timed_bomb", 0)) + _carried_bomb_count() >= MAX_BOMBS:
		return "定時炸彈已達同時存在上限"
	return ""


func _hazard_first_active_player_at(node_id: int, excluding_player_id: int) -> int:
	for candidate in _players():
		if typeof(candidate) != TYPE_DICTIONARY:
			continue
		var candidate_id: int = int(candidate.get("id", -1))
		if candidate_id == excluding_player_id or not bool(candidate.get("alive", false)):
			continue
		if _status_active(candidate) or int(candidate.get("bomb_steps", 0)) > 0:
			continue
		if _valid_int(candidate.get("position", null), node_id, node_id):
			return candidate_id
	return -1


func _hazard_damage_property(node_id: int) -> Dictionary:
	var tile: Dictionary = _tile_at(node_id)
	if tile.is_empty():
		return {"damaged": false, "kind": "", "from_level": 0, "to_level": 0, "tile_id": node_id}
	var kind: String = str(tile.get("kind", ""))
	if kind == "property":
		var property_level: int = int(tile.get("building_level", 0))
		if property_level <= 0:
			return {"damaged": false, "kind": kind, "from_level": property_level, "to_level": property_level, "tile_id": node_id}
		tile["building_level"] = property_level - 1
		if _is_remodel() and int(tile.get("building_level", 0)) == 0:
			tile["is_chain_store"] = false
		_update_tile_rent(tile)
		_recalculate_property_values()
		return {"damaged": true, "kind": kind, "from_level": property_level, "to_level": property_level - 1, "tile_id": node_id}
	if kind == "facility" and _is_facilities():
		var facility: Dictionary = _facility_record(node_id)
		if facility.is_empty():
			return {"damaged": false, "kind": kind, "from_level": 0, "to_level": 0, "tile_id": node_id}
		var facility_level: int = int(facility.get("building_level", 0))
		if facility_level <= 0:
			return {"damaged": false, "kind": kind, "from_level": facility_level, "to_level": facility_level, "tile_id": _facility_canonical_index(node_id)}
		var next_level: int = facility_level - 1
		var updates: Dictionary = {"building_level": next_level}
		# The source mode-0 helper clears the facility's raised/sealed (+18)
		# state when the demolition reaches level zero.
		if next_level == 0:
			updates["facility_state"] = 0
			updates["facility_type"] = 0
		_update_facility_records(int(facility.get("source_object_id", -1)), updates)
		_recalculate_property_values()
		return {"damaged": true, "kind": kind, "from_level": facility_level, "to_level": next_level, "tile_id": _facility_canonical_index(node_id), "source_object_id": int(facility.get("source_object_id", -1))}
	return {"damaged": false, "kind": kind, "from_level": 0, "to_level": 0, "tile_id": node_id}


func _hazard_process_ground(player_id: int, node_id: int) -> bool:
	if not _is_hazards():
		return false
	var hazards: Variant = state.get("ground_hazards", {})
	if typeof(hazards) != TYPE_DICTIONARY:
		return false
	var hazard_value: Variant = hazards.get(str(node_id), null)
	if typeof(hazard_value) != TYPE_DICTIONARY:
		return false
	var hazard: Dictionary = hazard_value
	var kind: String = str(hazard.get("kind", ""))
	if kind == "mine":
		hazards.erase(str(node_id))
		state["ground_hazards"] = hazards
		_hazard_return_tool_to_supply("地雷")
		var player: Dictionary = _player(player_id)
		var vehicle: String = _hazard_return_active_vehicle(player)
		_admit_player_status(player_id, "hospital", 3)
		_record_event("mine_triggered", {"player_id": player_id, "node": node_id, "vehicle": vehicle, "hospital_days": 3})
		return true
	if kind == "timed_bomb":
		var player_with_bomb: Dictionary = _player(player_id)
		if int(player_with_bomb.get("bomb_steps", 0)) > 0:
			return false
		hazards.erase(str(node_id))
		state["ground_hazards"] = hazards
		# Picking up a bomb keeps its finite slot occupied by the carrier.
		player_with_bomb["bomb_steps"] = MAX_BOMB_STEPS
		_record_event("bomb_picked_up", {"player_id": player_id, "node": node_id, "remaining": MAX_BOMB_STEPS})
	return false


func _hazard_explode_bomb(player_id: int, node_id: int) -> bool:
	if not _is_hazards():
		return false
	var player: Dictionary = _player(player_id)
	if player.is_empty() or int(player.get("bomb_steps", 0)) <= 0:
		return false
	player["bomb_steps"] = 0
	# The carried bomb slot is released only when the timed object explodes.
	_hazard_return_tool_to_supply("定時炸彈")
	var vehicle: String = _hazard_return_active_vehicle(player)
	var damage: Dictionary = _hazard_damage_property(node_id)
	_admit_player_status(player_id, "hospital", 5)
	var payload: Dictionary = {"player_id": player_id, "node": node_id, "remaining": 0, "vehicle": vehicle, "hospital_days": 5, "damage": damage}
	_record_event("bomb_exploded", payload)
	return true


func _process_carried_bomb_step(player_id: int, node_id: int) -> bool:
	if not _is_hazards():
		return false
	var player: Dictionary = _player(player_id)
	if player.is_empty():
		return false
	var current_steps: int = int(player.get("bomb_steps", 0))
	if current_steps <= 0:
		return false
	var remaining: int = current_steps - 1
	_record_event("bomb_countdown", {"player_id": player_id, "node": node_id, "remaining": remaining})
	if remaining <= 0:
		return _hazard_explode_bomb(player_id, node_id)
	player["bomb_steps"] = remaining
	var target_id: int = _hazard_first_active_player_at(node_id, player_id)
	if target_id >= 0:
		player["bomb_steps"] = 0
		var target: Dictionary = _player(target_id)
		target["bomb_steps"] = remaining
		_record_event("bomb_transferred", {"from_player_id": player_id, "to_player_id": target_id, "node": node_id, "remaining": remaining})
	return false


func _hazard_clear_unbound_gods(node_id: int) -> Array:
	var removed: Array = []
	if not _is_gods():
		return removed
	var objects: Variant = state.get("god_objects", [])
	if typeof(objects) != TYPE_ARRAY:
		return removed
	for index in range(objects.size() - 1, -1, -1):
		var actor: Variant = objects[index]
		if typeof(actor) != TYPE_DICTIONARY or int(actor.get("owner", -1)) >= 0 or int(actor.get("node", -1)) != node_id:
			continue
		removed.push_back(int(actor.get("id", 0)))
		objects.remove_at(index)
	state["god_objects"] = objects
	removed.sort()
	return removed


func _machine_doll_use(player_id: int) -> Dictionary:
	var player: Dictionary = _player(player_id)
	var current_node: int = int(player.get("position", -1))
	var previous_node: int = int(player.get("previous_position", -1))
	var path: Array = []
	var removed_hazards: Array = []
	var removed_roadblocks: Array = []
	var removed_gods: Array = []
	for _step in range(9):
		var candidates: Array = _graph_candidates(current_node, previous_node)
		if candidates.is_empty():
			break
		var selected_index: int = _rng.randi_range(0, candidates.size() - 1)
		var next_node: int = int(candidates[selected_index])
		previous_node = current_node
		current_node = next_node
		path.append(next_node)
		var hazards: Variant = state.get("ground_hazards", {})
		if typeof(hazards) == TYPE_DICTIONARY and hazards.has(str(next_node)):
			var hazard: Variant = hazards.get(str(next_node), null)
			if typeof(hazard) == TYPE_DICTIONARY:
				removed_hazards.append({"node": next_node, "kind": str(hazard.get("kind", ""))})
				_hazard_return_tool_to_supply("地雷" if str(hazard.get("kind", "")) == "mine" else "定時炸彈")
				hazards.erase(str(next_node))
				state["ground_hazards"] = hazards
		var roadblocks: Variant = state.get("roadblocks", {})
		if typeof(roadblocks) == TYPE_DICTIONARY and roadblocks.has(str(next_node)):
			removed_roadblocks.append(next_node)
			_hazard_return_tool_to_supply("路障")
			roadblocks.erase(str(next_node))
			state["roadblocks"] = roadblocks
		var god_ids: Array = _hazard_clear_unbound_gods(next_node)
		for god_id in god_ids:
			removed_gods.append({"node": next_node, "god_id": int(god_id)})
	_record_event("machine_doll_cleared", {"player_id": player_id, "path": path, "steps": path.size(), "removed_hazards": removed_hazards, "removed_roadblocks": removed_roadblocks, "removed_gods": removed_gods})
	return {"path": path, "steps": path.size(), "removed_hazards": removed_hazards, "removed_roadblocks": removed_roadblocks, "removed_gods": removed_gods}


func _set_inventory_vehicle(vehicle: String, dice_count: int = -1) -> Dictionary:
	if not _require_phase("await_roll"):
		return _error("只能在擲骰前選擇交通工具")
	var player: Dictionary = _current_player()
	if player.is_empty() or not bool(player.get("alive", false)):
		return _error("目前玩家無法行動")
	if not VEHICLE_DICE.has(vehicle):
		return _error("未知的交通工具")
	var pending_remote: Variant = state.get("pending_remote_dice", {})
	if typeof(pending_remote) == TYPE_DICTIONARY and not pending_remote.is_empty():
		return _error("遙控骰子已經排程")
	var maximum: int = int(VEHICLE_DICE[vehicle])
	var selected: int = maximum if dice_count < 1 else dice_count
	if selected < 1 or selected > maximum:
		return _error("骰子數量超出交通工具限制")
	var current_vehicle: String = str(player.get("vehicle", "walking"))
	if vehicle == EngineeringVehicle.VEHICLE_ID:
		return _error("工程車只能透過研究道具啟用")
	if current_vehicle == vehicle:
		player["dice_count"] = selected
		_record_event("vehicle_selected", {"player_id": int(player["id"]), "vehicle": vehicle, "dice_count": selected})
		_set_action_options(int(player["id"]))
		return _result(true, "已選擇交通工具")
	var tools: Dictionary = player.get("tools", {}).duplicate(true)
	var old_tool_id: String = _inventory_vehicle_tool_id(current_vehicle)
	if not old_tool_id.is_empty():
		# Returning an equipped vehicle follows the original cleanup path and may
		# leave ten copies in the backpack.  Refuse only a value that would grow
		# that storage beyond ten, keeping malformed future state fail-closed.
		if int(tools.get(old_tool_id, 0)) >= OriginalInventory.VEHICLE_STORAGE_CAPACITY:
			return _error("道具數量超出上限")
	var new_tool_id: String = _inventory_vehicle_tool_id(vehicle)
	if not new_tool_id.is_empty() and int(tools.get(new_tool_id, 0)) < 1:
		return _error("尚未持有這項交通工具")
	if not old_tool_id.is_empty():
		tools[old_tool_id] = int(tools.get(old_tool_id, 0)) + 1
	if not new_tool_id.is_empty():
		var remaining: int = int(tools.get(new_tool_id, 0)) - 1
		if remaining <= 0:
			tools.erase(new_tool_id)
		else:
			tools[new_tool_id] = remaining
	player["tools"] = tools
	var vehicles: Dictionary = player.get("vehicles", {}).duplicate(true)
	vehicles[vehicle] = true
	player["vehicles"] = vehicles
	player["vehicle"] = vehicle
	player["dice_count"] = selected
	if current_vehicle == EngineeringVehicle.VEHICLE_ID:
		player.erase("engineering_vehicle")
	_record_event("vehicle_selected", {"player_id": int(player["id"]), "vehicle": vehicle, "dice_count": selected})
	_set_action_options(int(player["id"]))
	return _result(true, "已選擇交通工具")


func set_vehicle(vehicle: String, dice_count: int = -1) -> Dictionary:
	if _trap_pending():
		return _error("請先回應陷害卡")
	if _sleep_active(_current_player()):
		return _error("睡眠期間無法切換交通工具")
	if _is_statuses() and _status_active(_current_player()):
		return _error("拘留期間無法切換交通工具")
	if not _require_phase("await_roll"):
		return _error("只能在擲骰前選擇交通工具")
	var player: Dictionary = _current_player()
	if player.is_empty() or not bool(player.get("alive", false)):
		return _error("目前玩家無法行動")
	if vehicle == EngineeringVehicle.VEHICLE_ID:
		if not EngineeringVehicle.is_active(player):
			return _error("工程車只能透過研究道具啟用")
		if dice_count > 1:
			return _error("工程車只能使用一顆骰子")
		player["dice_count"] = 1
		_record_event("vehicle_selected", {"player_id": int(player["id"]), "vehicle": vehicle, "dice_count": 1})
		return _result(true, "已選擇交通工具")
	if not VEHICLE_DICE.has(vehicle):
		return _error("未知的交通工具")
	if _is_inventory():
		return _set_inventory_vehicle(vehicle, dice_count)
	var vehicles: Dictionary = player.get("vehicles", {})
	if not bool(vehicles.get(vehicle, false)):
		return _error("尚未擁有這項交通工具")
	var maximum: int = int(VEHICLE_DICE[vehicle])
	var selected: int = maximum if dice_count < 1 else dice_count
	if selected < 1 or selected > maximum:
		return _error("骰子數量超出交通工具限制")
	player["vehicle"] = vehicle
	player["dice_count"] = selected
	_record_event("vehicle_selected", {"player_id": int(player["id"]), "vehicle": vehicle, "dice_count": selected})
	return _result(true, "已選擇交通工具")


func roll(dice_count: int = -1) -> Dictionary:
	if not AuctionRules.response(self).is_empty():
		return _error("請先回應拍賣")
	if not _pending_finance().is_empty():
		return _error("請先回應付款選擇")
	if _sleep_active(_current_player()) and not _running_sleep_turn:
		return _error("睡眠期間由自動回合移動")
	if _trap_pending():
		return _error("請先回應陷害卡")
	if not _require_phase("await_roll"):
		return _error("目前不是擲骰階段")
	var player_id: int = int(state.get("current_player", -1))
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return _error("目前玩家無法擲骰")
	var hospital_days: int = int(player.get("hospital_days", 0))
	if _is_statuses():
		var status_kind := "hospital" if hospital_days > 0 else "prison" if int(player.get("prison_days", 0)) > 0 else ""
		if not status_kind.is_empty():
			var status_key := _status_key(status_kind)
			var remaining_before: int = int(player.get(status_key, 0))
			if remaining_before == 128:
				_release_status_marker(player_id, status_kind)
			else:
				var remaining_after: int = remaining_before - 1 if remaining_before > 1 else 128
				player[status_key] = remaining_after
				state["last_roll"] = []
				state["last_total"] = 0
				state["extra_roll"] = false
				state["doubles_count"] = 0
				state["property_action_used"] = true
				state["bank_access"] = false
				state["bank_landing"] = false
				if _is_facilities():
					state["last_roll_total"] = 0
				state["phase"] = "await_action"
				_set_action_options(player_id)
				_record_event("status_skipped", {"player_id": player_id, "status_kind": status_kind, "remaining": remaining_after})
				return _result(true, "服刑中，本回合跳過" if status_kind == "prison" else "住院中，本回合休養", {"skipped": true, "status_kind": status_kind, "remaining": remaining_after})
	elif _is_gods() and hospital_days > 0:
		player["hospital_days"] = hospital_days - 1
		state["last_roll"] = []
		state["last_total"] = 0
		state["extra_roll"] = false
		state["doubles_count"] = 0
		state["property_action_used"] = true
		state["bank_access"] = false
		state["bank_landing"] = false
		if _is_facilities():
			state["last_roll_total"] = 0
		state["phase"] = "await_action"
		_set_action_options(player_id)
		_record_event("hospital_skipped", {"player_id": player_id, "days": int(player["hospital_days"])})
		if int(player["hospital_days"]) == 0:
			_record_event("hospital_recovered", {"player_id": player_id})
		return _result(true, "住院中，本回合休養", {"skipped": true, "hospital_days": int(player["hospital_days"])})
	var pending_remote: Dictionary = {}
	if _is_inventory() and typeof(state.get("pending_remote_dice", {})) == TYPE_DICTIONARY:
		pending_remote = state.get("pending_remote_dice", {})
	if not pending_remote.is_empty():
		if int(pending_remote.get("player_id", -1)) != player_id:
			return _error("遙控骰子待命玩家不一致")
		if _inventory_movement_blocked(player):
			return _error("目前移動狀態無法執行遙控骰子")
	if int(player.get("skip_turns", 0)) > 0:
		player["skip_turns"] = int(player.get("skip_turns", 0)) - 1
		state["last_roll"] = []
		state["last_total"] = 0
		state["extra_roll"] = false
		state["doubles_count"] = 0
		state["phase"] = "await_action"
		_set_action_options(player_id)
		_record_event("turn_skipped", {"player_id": player_id, "remaining": int(player["skip_turns"])})
		return _result(true, "本回合跳過")
	var maximum: int = int(VEHICLE_DICE.get(str(player.get("vehicle", "walking")), 1))
	var count: int = int(player.get("dice_count", maximum)) if dice_count < 1 else dice_count
	var turtle_step: bool = int(player.get("turtle_days", 0)) > 0
	if count < 1 or count > maximum:
		return _error("骰子數量超出交通工具限制")
	var stationary_turn: bool = int(player.get("stay_next", 0)) > 0
	# Capture before turtle decrement, pending remote consumption, and any RNG
	# call.  A stationary turn has no movement and therefore keeps its prior
	# anchor.
	if not stationary_turn:
		_capture_time_anchor(player_id)
	if turtle_step:
		player["turtle_days"] = int(player.get("turtle_days", 0)) - 1
	var dice: Array = []
	var total: int = 0
	if not pending_remote.is_empty():
		var remote_value: Variant = pending_remote.get("value", null)
		if not _valid_int(remote_value, 1, 6):
			return _error("遙控骰子待命點數無效")
		dice = [int(remote_value)]
		total = int(remote_value)
		state["pending_remote_dice"] = {}
	elif turtle_step:
		dice = [1]
		total = 1
	else:
		for _index in range(count):
			var face: int = _rng.randi_range(1, 6)
			dice.append(face)
			total += face
	if stationary_turn and _is_inventory() and _is_graph():
		state["stationary_turn"] = true
	else:
		state.erase("stationary_turn")
	state["last_roll"] = dice
	state["last_total"] = total
	if _is_facilities():
		# Keep the complete roll separate from the remaining graph distance. A
		# roadblock may stop movement early, while a gas station still uses the
		# total that was rolled at movement start.
		state["last_roll_total"] = total
	state["property_action_used"] = false
	var graph_should_move: bool = false
	var dog_collision: bool = false
	if stationary_turn:
		player["stay_next"] = int(player.get("stay_next", 0)) - 1
		if _is_research():
			# A positive roll without an edge traversal is not a new research visit.
			# Persist the existing per-visit guard through save/load; admission resets it.
			state["research_action_used"] = true
		_record_event("stay_resolved", {"player_id": player_id, "tile": int(player.get("position", 0))})
	elif _is_graph():
		graph_should_move = true
	else:
		_move_player(player_id, total)
	# The reference movement is one chosen roll per turn. Doubles do not grant
	# Monopoly-style bonus turns or automatic penalties.
	state["doubles_count"] = 0
	state["extra_roll"] = false
	var roll_payload: Dictionary = {"player_id": player_id, "dice": dice, "total": total, "vehicle": player.get("vehicle", "walking")}
	if not pending_remote.is_empty():
		roll_payload["remote_dice"] = true
	_record_event("roll", roll_payload)
	if graph_should_move:
		dog_collision = _graph_begin_movement(player_id, total)
	if (not _is_graph() or state.get("phase", "") != "await_route") and not dog_collision:
		# A stay/status-release turn does not traverse an edge.  Process graph
		# objects only after an actual traversed edge so anchor objects remain
		# preserved when the player merely stays there.
		_resolve_landing(player_id, graph_should_move)
	return _result(true, "擲骰完成", {"dice": dice, "total": total})


func _graph_candidates(current_node: int, previous_node: int) -> Array:
	var tile: Dictionary = _tile_at(current_node)
	if tile.is_empty():
		return []
	var adjacent: Array = tile.get("adjacent", [])
	var candidates: Array = []
	for neighbor in adjacent:
		var neighbor_id: int = int(neighbor)
		if neighbor_id < 0 or neighbor_id >= state.get("board", []).size():
			continue
		if neighbor_id != previous_node and not candidates.has(neighbor_id):
			candidates.append(neighbor_id)
	if candidates.is_empty() and previous_node >= 0 and _array_contains_int(adjacent, previous_node):
		candidates.append(previous_node)
	candidates.sort()
	return candidates


func _graph_begin_movement(player_id: int, steps: int) -> bool:
	var player: Dictionary = _player(player_id)
	var current_node: int = int(player.get("position", -1))
	var previous_node: int = int(player.get("previous_position", -1))
	var requested_steps: int = max(0, steps)
	var roll_total: int = int(state.get("last_total", 0))
	if requested_steps > MAX_GRAPH_STEPS or requested_steps > roll_total:
		state["route_options"] = []
		state["pending_movement"] = {}
		state["remaining_steps"] = 0
		state["phase"] = "await_roll"
		_record_event("movement_invalid", {"player_id": player_id, "steps": requested_steps, "last_total": roll_total})
		return false
	state["bank_access"] = false
	state["bank_landing"] = false
	state["remaining_steps"] = requested_steps
	state["pending_movement"] = {
		"player_id": player_id,
		"current_node": current_node,
		"previous_node": previous_node,
	}
	state["route_options"] = []
	return _graph_continue_movement(player_id)


func _graph_bank_pass_before_god(player_id: int, node_id: int) -> bool:
	if not _is_gods() or _is_sunday() or _sleep_dream_active(_player(player_id)):
		return false
	var tile: Dictionary = _tile_at(node_id)
	if tile.get("kind", "") != "bank":
		return false
	state["bank_access"] = true
	state["bank_landing"] = false
	_record_event("bank_passed", {"player_id": player_id, "tile": node_id})
	return true


func _stop_graph_for_dog(player_id: int) -> void:
	state["route_options"] = []
	state["pending_movement"] = {}
	state["remaining_steps"] = 0
	state["phase"] = "await_action"
	_set_action_options(player_id)


func _stop_graph_for_hazard(player_id: int) -> void:
	state["route_options"] = []
	state["pending_movement"] = {}
	state["remaining_steps"] = 0
	if state.get("phase", "") != "game_over":
		state["phase"] = "await_action"
		_set_action_options(player_id)


func _graph_consume_roadblock(player_id: int, node_id: int) -> bool:
	if not _is_inventory():
		return false
	var roadblocks_value: Variant = state.get("roadblocks", {})
	if typeof(roadblocks_value) != TYPE_DICTIONARY or not roadblocks_value.has(str(node_id)):
		return false
	var placer_value: Variant = roadblocks_value.get(str(node_id), null)
	var placer_id: int = int(placer_value) if _valid_int(placer_value, 0, max(0, _players().size() - 1)) else -1
	roadblocks_value.erase(str(node_id))
	state["roadblocks"] = roadblocks_value
	if _is_hazards():
		_hazard_return_tool_to_supply("路障")
	_record_event("roadblock_hit", {"player_id": player_id, "tile_id": node_id, "placer_player_id": placer_id})
	return true


func _graph_continue_movement(player_id: int) -> bool:
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		state["route_options"] = []
		state["pending_movement"] = {}
		state["remaining_steps"] = 0
		return false
	var remaining: int = int(state.get("remaining_steps", 0))
	var roll_total: int = int(state.get("last_total", 0))
	if remaining < 0 or remaining > MAX_GRAPH_STEPS or remaining > roll_total:
		state["route_options"] = []
		state["pending_movement"] = {}
		state["remaining_steps"] = 0
		state["phase"] = "await_roll"
		_record_event("movement_invalid", {"player_id": player_id, "steps": remaining, "last_total": roll_total})
		return false
	while int(state.get("remaining_steps", 0)) > 0:
		var current_node: int = int(player.get("position", -1))
		var previous_node: int = int(player.get("previous_position", -1))
		var candidates: Array = _graph_candidates(current_node, previous_node)
		if candidates.size() > 1:
			state["phase"] = "await_route"
			state["route_options"] = candidates
			state["pending_movement"] = {
				"player_id": player_id,
				"current_node": current_node,
				"previous_node": previous_node,
			}
			_set_action_options(player_id)
			return false
		if candidates.is_empty():
			# A valid map can contain an isolated non-housing node. Preserve the
			# explicit stop instead of inventing a connection to another node.
			state["remaining_steps"] = 0
			_record_event("movement_blocked", {"player_id": player_id, "node": current_node})
			break
		var next_node: int = int(candidates[0])
		var old_node: int = current_node
		player["previous_position"] = old_node
		player["position"] = next_node
		state["remaining_steps"] = int(state.get("remaining_steps", 0)) - 1
		state["pending_movement"] = {
			"player_id": player_id,
			"current_node": next_node,
			"previous_node": old_node,
		}
		_record_event("move", {"player_id": player_id, "from": old_node, "to": next_node, "steps": 1})
		var bank_passed_before_god: bool = _graph_bank_pass_before_god(player_id, next_node)
		var bomb_collision: bool = _process_carried_bomb_step(player_id, next_node)
		if bomb_collision:
			_stop_graph_for_hazard(player_id)
			return true
		var dog_collision: bool = _process_god_step(player_id, next_node, false)
		if dog_collision:
			_stop_graph_for_dog(player_id)
			return true
		if not bool(player.get("alive", false)) or state.get("phase", "") == "game_over":
			state["route_options"] = []
			state["pending_movement"] = {}
			state["remaining_steps"] = 0
			return false
		if _is_gods() and _status_active(player):
			state["remaining_steps"] = 0
			break
		if _graph_consume_roadblock(player_id, next_node):
			state["remaining_steps"] = 0
			break
		if int(state.get("remaining_steps", 0)) > 0:
			_graph_visit_tile(player_id, _tile_at(next_node), false, bank_passed_before_god)
			if not bool(player.get("alive", false)):
				state["remaining_steps"] = 0
				break
	state["route_options"] = []
	state["pending_movement"] = {}
	state["remaining_steps"] = 0
	state["phase"] = "await_roll"
	return false


func choose_route(route: int) -> Dictionary:
	if not AuctionRules.response(self).is_empty():
		return _error("請先回應拍賣")
	if _sleep_active(_current_player()) and not _running_sleep_turn:
		return _error("睡眠期間由自動回合移動")
	if not _require_phase("await_route"):
		return _error("目前沒有待選路線")
	var player_id: int = int(state.get("current_player", -1))
	var pending: Dictionary = state.get("pending_movement", {})
	if pending.is_empty() or int(pending.get("player_id", -1)) != player_id:
		return _error("待選路線的玩家無效")
	var options: Array = state.get("route_options", [])
	if not _array_contains_int(options, route):
		return _error("選擇的路線無效")
	var remaining_steps: Variant = state.get("remaining_steps", null)
	var roll_total: Variant = state.get("last_total", null)
	if not _valid_int(remaining_steps, 1, MAX_GRAPH_STEPS) or not _valid_int(roll_total, 1, MAX_GRAPH_STEPS) or int(remaining_steps) > int(roll_total):
		return _error("待選路線步數無效")
	var player: Dictionary = _player(player_id)
	if player.is_empty() or int(player.get("position", -1)) != int(pending.get("current_node", -2)):
		return _error("待選路線與玩家位置不一致")
	var current_node: int = int(player.get("position", -1))
	var previous_node: int = int(player.get("previous_position", -1))
	var legal_options: Array = _graph_candidates(current_node, previous_node)
	if not _array_contains_int(legal_options, route):
		return _error("選擇的路線已失效")
	player["previous_position"] = current_node
	player["position"] = route
	state["remaining_steps"] = int(state.get("remaining_steps", 0)) - 1
	state["pending_movement"] = {
		"player_id": player_id,
		"current_node": route,
		"previous_node": current_node,
	}
	_record_event("route_chosen", {"player_id": player_id, "from": current_node, "to": route})
	var bank_passed_before_god: bool = _graph_bank_pass_before_god(player_id, route)
	var bomb_collision: bool = _process_carried_bomb_step(player_id, route)
	if bomb_collision:
		_stop_graph_for_hazard(player_id)
		return _result(true, "已選擇路線", {"route": route, "bomb_collision": true})
	var dog_collision: bool = _process_god_step(player_id, route, false)
	if dog_collision:
		_stop_graph_for_dog(player_id)
		return _result(true, "已選擇路線", {"route": route})
	if not bool(player.get("alive", false)) or state.get("phase", "") == "game_over":
		state["route_options"] = []
		state["pending_movement"] = {}
		state["remaining_steps"] = 0
		return _result(true, "已選擇路線", {"route": route})
	if _is_gods() and _status_active(player):
		state["remaining_steps"] = 0
	var hit_roadblock: bool = _graph_consume_roadblock(player_id, route)
	if hit_roadblock:
		state["remaining_steps"] = 0
	elif int(state.get("remaining_steps", 0)) > 0:
		_graph_visit_tile(player_id, _tile_at(route), false, bank_passed_before_god)
	var continued_dog_collision: bool = _graph_continue_movement(player_id)
	if int(state.get("remaining_steps", 0)) == 0 and state.get("phase", "") != "game_over" and not continued_dog_collision:
		_resolve_landing(player_id)
	return _result(true, "已選擇路線", {"route": route})


func _remove_property_reference(player_id: int, property_id: int) -> void:
	var player: Dictionary = _player(player_id)
	if player.is_empty():
		return
	var properties: Array = player.get("properties", []).duplicate(true)
	while properties.has(property_id):
		properties.erase(property_id)
	player["properties"] = properties


func _add_property_reference(player_id: int, property_id: int) -> void:
	var player: Dictionary = _player(player_id)
	if player.is_empty():
		return
	var properties: Array = player.get("properties", []).duplicate(true)
	if not properties.has(property_id):
		properties.append(property_id)
	player["properties"] = properties


func _occupy_with_land_god(player_id: int, tile: Dictionary) -> bool:
	var old_owner: int = int(tile.get("owner", -1))
	if old_owner < 0 or old_owner == player_id:
		return false
	var property_id: int = int(tile.get("index", -1))
	if tile.get("kind", "") == "facility":
		property_id = _facility_canonical_index(property_id)
		_update_facility_records(int(tile.get("source_object_id", -1)), {"owner": player_id})
	else:
		tile["owner"] = player_id
	_remove_property_reference(old_owner, property_id)
	_add_property_reference(player_id, property_id)
	state["property_action_used"] = true
	_recalculate_property_values()
	return true


func _apply_god_property_effect(player_id: int, tile: Dictionary, final_landing: bool) -> void:
	if not _is_gods() or tile.is_empty():
		return
	var god_id: int = _player_god_id(player_id)
	if god_id <= 0:
		return
	var kind: String = str(tile.get("kind", ""))
	if kind not in ["property", "facility"]:
		return
	if god_id == 12 and final_landing:
		var previous_owner: int = int(tile.get("owner", -1))
		if _occupy_with_land_god(player_id, tile):
			_record_event("god_property_effect", {"player_id": player_id, "god_id": god_id, "tile_id": int(tile.get("index", -1)), "effect": "occupy", "previous_owner": previous_owner})
		return
	if god_id not in [9, 10]:
		return
	var owner_id: int = int(tile.get("owner", -1))
	var level: int = int(tile.get("building_level", 0))
	var next_level: int = level
	var effect: String = ""
	if god_id == 9:
		var angel_cap: int = MAX_PROPERTY_LEVEL
		if kind == "facility":
			var angel_type: int = int(tile.get("facility_type", -1))
			if angel_type == FACILITY_LAB_TYPE and not _is_research():
				return
			angel_cap = _facility_type_cap(angel_type)
		else:
			angel_cap = _property_level_cap(tile, _is_remodel())
		if level >= angel_cap:
			return
		next_level = level + 1
		effect = "angel_raise"
	else:
		if level <= 0:
			return
		next_level = level - 1
		effect = "demon_lower"
	if kind == "facility":
		var facility_updates: Dictionary = {"building_level": next_level}
		if next_level == 0:
			facility_updates["facility_type"] = 0
		_update_facility_records(int(tile.get("source_object_id", -1)), facility_updates)
	else:
		tile["building_level"] = next_level
		if _is_remodel() and next_level == 0:
			tile["is_chain_store"] = false
		_update_tile_rent(tile)
	_recalculate_property_values()
	_record_event("god_property_effect", {"player_id": player_id, "god_id": god_id, "tile_id": int(tile.get("index", -1)), "effect": effect, "from_level": level, "to_level": next_level})


func _resolve_news_landing(player_id: int) -> void:
	if not _valid_player(player_id, true):
		return
	_resolving_news = true
	NewsEvents.apply_landing(self, player_id)
	_resolving_news = false
	var player: Dictionary = _player(player_id)
	if not bool(player.get("alive", false)) and int(state.get("current_player", -1)) == player_id and state.get("phase", "") != "game_over":
		_advance_to_next_alive(player_id)


func _resolve_fate_landing(player_id: int) -> void:
	if not _valid_player(player_id, true):
		return
	_resolving_fate = true
	FateEvents.apply_landing(self, player_id)
	_resolving_fate = false
	var player: Dictionary = _player(player_id)
	if not bool(player.get("alive", false)) and int(state.get("current_player", -1)) == player_id and state.get("phase", "") != "game_over":
		_advance_to_next_alive(player_id)


func _graph_visit_tile(player_id: int, tile: Dictionary, final_landing: bool, bank_passed_before_god: bool = false) -> void:
	if tile.is_empty():
		return
	if _sleep_dream_active(_player(player_id)) and int(tile.get("event_code", 0)) != 0:
		return
	var tile_index: int = int(tile.get("index", -1))
	if _is_statuses() and int(tile.get("type_and_idx", -1)) in [8001, 8002]:
		var status_kind := "hospital" if int(tile.get("type_and_idx", -1)) == 8001 else "prison"
		_record_event("status_facility_landed" if final_landing else "status_facility_passed", {"player_id": player_id, "status_kind": status_kind, "node": tile_index, "name": str(tile.get("name", ""))})
		return
	if _is_companies() and not get_company_at(tile_index).is_empty():
		if final_landing:
			_resolve_company_visit(player_id, tile)
		if not bool(_player(player_id).get("alive", false)) or tile.get("kind", "") == "unsupported":
			return
	match str(tile.get("kind", "rest")):
		"property":
			if final_landing:
				var owner: int = int(tile.get("owner", -1))
				if owner >= 0 and owner != player_id:
					_charge_rent(player_id, owner, _calculate_rent(tile, owner))
		"facility":
			if final_landing:
				_resolve_facility_visit(player_id, tile)
		"tax":
			if final_landing:
				_charge_amount(player_id, int(tile.get("tax_amount", 0)), -1, "tax")
		"stock":
			if final_landing:
				_record_event("stock_landed", {"player_id": player_id, "tile": tile_index})
		"news":
			if final_landing:
				_resolve_news_landing(player_id)
			else:
				_record_event("news_passed", {"player_id": player_id, "tile": tile_index})
		"fate":
			if final_landing:
				_resolve_fate_landing(player_id)
			else:
				_record_event("fate_passed", {"player_id": player_id, "tile": tile_index})
		"event":
			if final_landing:
				_draw_event_card(player_id)
		"points":
			var player: Dictionary = _player(player_id)
			var points: int = int(tile.get("points", 0))
			var current_points: int = clampi(int(player.get("points", 0)), 0, MAX_GRAPH_POINTS)
			var awarded_points: int = clampi(points, 0, MAX_GRAPH_POINTS - current_points)
			player["points"] = current_points + awarded_points
			_record_event("points_landed" if final_landing else "points_passed", {"player_id": player_id, "tile": tile_index, "points": awarded_points, "source_points": points})
		"card":
			if final_landing:
				_draw_event_card(player_id)
			else:
				_grant_random_card(player_id, "card_passed")
		"bank":
			if not _is_sunday():
				state["bank_access"] = true
				if final_landing:
					state["bank_landing"] = true
					_record_event("bank_landed", {"player_id": player_id, "tile": tile_index})
				elif not bank_passed_before_god:
					_record_event("bank_passed", {"player_id": player_id, "tile": tile_index})
		"unsupported":
			_record_event("unsupported_landing" if final_landing else "unsupported_passed", {"player_id": player_id, "tile": tile_index, "name": tile.get("name", "")})


func _facility_roulette(facility_type: int) -> int:
	if facility_type == 1:
		var weighted_slot: int = _rng.randi_range(1, 12)
		if weighted_slot <= 4:
			return 1
		if weighted_slot <= 7:
			return 2
		if weighted_slot <= 9:
			return 3
		return 4
	if facility_type == 2:
		return _rng.randi_range(1, 6)
	return 1


func _facility_fee(tile: Dictionary) -> Dictionary:
	var facility_type: int = int(tile.get("facility_type", -1))
	var level: int = int(tile.get("building_level", 0))
	var fees: Variant = tile.get("fee_by_level", [])
	if not _facility_type_valid(facility_type) or facility_type == FACILITY_LAB_TYPE:
		return {"ok": false, "reason": "facility_type_unavailable", "fee": 0, "base_fee": 0, "resolved_roll": 0}
	if level <= 0 or level > _facility_type_cap(facility_type):
		return {"ok": false, "reason": "facility_level_unavailable", "fee": 0, "base_fee": 0, "resolved_roll": 0}
	if typeof(fees) != TYPE_ARRAY or fees.size() != 6 or not _valid_int(fees[level], 0, 1000000000):
		return {"ok": false, "reason": "facility_fee_table_invalid", "fee": 0, "base_fee": 0, "resolved_roll": 0}
	var base_fee: int = int(fees[level]) * _facility_price_index()
	var resolved_roll: int = _facility_roulette(facility_type) if facility_type in [1, 2] else 0
	var fee: int = base_fee
	if facility_type in [1, 2]:
		fee *= resolved_roll
	if _facility_is_raised(tile):
		fee *= 2
	return {"ok": true, "reason": "", "fee": fee, "base_fee": base_fee, "resolved_roll": resolved_roll}


func _charge_facility(debtor_id: int, creditor_id: int, amount: int, source_object_id: int, free_allowed: bool = true) -> void:
	if amount <= 0:
		return
	var debtor: Dictionary = _player(debtor_id)
	if AllianceRules.are_allied(self, debtor_id, creditor_id):
		_record_event("alliance_fee_waived", {"player_id": debtor_id, "creditor_id": creditor_id, "kind": "facility", "amount": amount})
		return
	var adjusted_amount: int = _god_adjust_charge_amount(debtor_id, amount, "facility")
	if _is_gods() and adjusted_amount <= 0:
		_record_event("god_charge_waived", {"player_id": debtor_id, "god_id": _player_god_id(debtor_id), "reason": "facility", "amount": amount})
		return
	if int(debtor.get("rent_shield", 0)) > 0:
		debtor["rent_shield"] = int(debtor.get("rent_shield", 0)) - 1
		_record_event("facility_blocked", {"player_id": debtor_id, "creditor_id": creditor_id, "source_object_id": source_object_id, "amount": amount})
		return
	if not _financial_fee_gate(debtor_id, adjusted_amount, creditor_id, "facility", int(debtor.get("position", -1)), free_allowed):
		return
	_charge_amount(debtor_id, adjusted_amount, creditor_id, "facility", false)


func _god_property_fee_waiver_reason(owner_id: int) -> String:
	if not _is_gods():
		return ""
	var owner: Dictionary = _player(owner_id)
	if owner.is_empty() or not bool(owner.get("alive", false)):
		return ""
	if _sleep_active(owner):
		return _sleep_kind(owner)
	if _status_active(owner):
		return "hospital" if int(owner.get("hospital_days", 0)) > 0 else "prison"
	if _player_god_id(owner_id) == 15:
		return "death"
	return ""


func _record_god_property_fee_waived(debtor_id: int, owner_id: int, reason: String, kind: String, tile_id: int = -1, source_object_id: int = -1) -> void:
	var payload: Dictionary = {
		"player_id": debtor_id,
		"owner_id": owner_id,
		"reason": reason,
		"kind": kind,
	}
	if tile_id >= 0:
		payload["tile_id"] = tile_id
	if source_object_id > 0:
		payload["source_object_id"] = source_object_id
	_record_event("property_fee_waived", payload)


func _resolve_facility_visit(player_id: int, visited_tile: Dictionary) -> void:
	if not _is_facilities() or not _is_graph() or visited_tile.get("kind", "") != "facility":
		return
	var tile_id: int = int(visited_tile.get("index", -1))
	var tile: Dictionary = _facility_record(tile_id)
	if tile.is_empty():
		return
	var source_object_id: int = int(tile.get("source_object_id", -1))
	var facility_type: int = int(tile.get("facility_type", -1))
	var owner_id: int = int(tile.get("owner", -1))
	var level: int = int(tile.get("building_level", 0))
	var payload: Dictionary = {
		"player_id": player_id,
		"tile_id": tile_id,
		"facility_node_index": _facility_canonical_index(tile_id),
		"source_object_id": source_object_id,
		"facility_type": facility_type,
		"facility_name": FACILITY_NAMES[facility_type] if _facility_type_valid(facility_type) else "未知設施",
		"owner_id": owner_id,
		"building_level": level,
		"facility_state": int(tile.get("facility_state", 0)),
		"price_index": _facility_price_index(),
		"resolved_roll": 0,
		"base_fee": 0,
		"fee": 0,
		"admitted": false,
	}
	if owner_id < 0 or owner_id == player_id:
		payload["reason"] = "unowned_or_self"
		_record_event("facility_service", payload)
		return
	if facility_type == 0:
		payload["admitted"] = true
		payload["reason"] = "park_no_effect"
		_record_event("facility_service", payload)
		return
	if AllianceRules.are_allied(self, player_id, owner_id):
		payload["reason"] = "alliance"
		payload["alliance_waived"] = true
		_record_event("facility_service", payload)
		_record_event("alliance_fee_waived", {"player_id": player_id, "creditor_id": owner_id, "kind": "facility", "tile_id": tile_id, "source_object_id": source_object_id})
		return
	var fee_waiver_reason: String = _god_property_fee_waiver_reason(owner_id)
	if not fee_waiver_reason.is_empty():
		payload["reason"] = "owner_unavailable"
		_record_event("facility_service", payload)
		_record_god_property_fee_waived(player_id, owner_id, fee_waiver_reason, "facility", tile_id, source_object_id)
		return
	if not _facility_service_admitted(tile):
		payload["reason"] = "sealed" if _facility_is_sealed(tile) else "facility_unavailable"
		_record_event("facility_service", payload)
		return
	var fee_result: Dictionary = _facility_fee(tile)
	if not bool(fee_result.get("ok", false)):
		payload["reason"] = str(fee_result.get("reason", "facility_unavailable"))
		_record_event("facility_service", payload)
		return
	payload["admitted"] = true
	payload["reason"] = "service"
	payload["resolved_roll"] = int(fee_result.get("resolved_roll", 0))
	payload["base_fee"] = int(fee_result.get("base_fee", 0))
	payload["fee"] = int(fee_result.get("fee", 0))
	if facility_type == 3:
		var vehicle: String = str(_player(player_id).get("vehicle", "walking"))
		var roll_total: int = int(state.get("last_roll_total", state.get("last_total", 0)))
		var vehicle_multiplier: int = 4 if vehicle == EngineeringVehicle.VEHICLE_ID else 1 if vehicle == "motorcycle" else 2 if vehicle == "car" else 0
		payload["vehicle"] = vehicle
		payload["last_roll_total"] = roll_total
		payload["resolved_roll"] = roll_total
		payload["base_fee"] = 500 * roll_total * vehicle_multiplier * _facility_price_index()
		payload["fee"] = int(payload["base_fee"])
		payload["reason"] = "walking_free" if vehicle_multiplier == 0 else "gas_service"
	if int(payload["fee"]) <= 0:
		_record_event("facility_service", payload)
		return
	_record_event("facility_service", payload)
	_charge_facility(player_id, owner_id, int(payload["fee"]), source_object_id, facility_type != 1)


func _move_player(player_id: int, steps: int) -> void:
	var player: Dictionary = _player(player_id)
	var old_position: int = int(player.get("position", 0))
	var position: int = old_position
	var bank_access: bool = false
	var board: Array = state.get("board", [])
	for step in range(steps):
		position = (position + 1) % BOARD_SIZE
		var crossed: Dictionary = board[position]
		if crossed.get("kind", "") == "bank" and not _is_sunday():
			bank_access = true
			_record_event("bank_passed", {"player_id": player_id, "tile": position})
		if crossed.get("kind", "") == "event" and step < steps - 1:
			_grant_random_card(player_id, "card_passed")
	player["position"] = position
	state["bank_access"] = bank_access
	state["bank_landing"] = false
	_record_event("move", {"player_id": player_id, "from": old_position, "to": position, "steps": steps})


func _resolve_landing(player_id: int, process_graph_objects: bool = true) -> void:
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return
	var tile: Dictionary = _tile_at(int(player.get("position", 0)))
	if tile.is_empty():
		state["phase"] = "await_action"
		_set_action_options(player_id)
		return
	if _is_graph():
		if _is_hazards() and process_graph_objects:
			# Ground hazards and ordinary gods are final-landing effects in v9.
			# A mine or a zero-count bomb moves the actor to hospital and consumes
			# the landing, so do not also resolve the source tile.
			if _hazard_process_ground(player_id, int(player.get("position", -1))):
				_check_game_over()
				return
			if _process_god_step(player_id, int(player.get("position", -1)), true):
				_check_game_over()
				return
			if not bool(player.get("alive", false)) or state.get("phase", "") == "game_over":
				_check_game_over()
				return
		_graph_visit_tile(player_id, tile, true)
		if bool(player.get("alive", false)) and state.get("phase", "") != "game_over":
			state["phase"] = "await_action"
			_set_action_options(player_id)
		_check_game_over()
		return
	match str(tile.get("kind", "rest")):
		"property":
			var owner: int = int(tile.get("owner", -1))
			if owner >= 0 and owner != player_id:
				_charge_rent(player_id, owner, _calculate_rent(tile, owner))
		"tax":
			_charge_amount(player_id, int(tile.get("tax_amount", 0)), -1, "tax")
		"event":
			_draw_event_card(player_id)
		"bank":
			if not _is_sunday():
				state["bank_access"] = true
				state["bank_landing"] = true
				_record_event("bank_landed", {"player_id": player_id, "tile": int(tile["index"])})
		"stock":
			_record_event("stock_landed", {"player_id": player_id, "tile": int(tile["index"])})
		_:
			_record_event("rest", {"player_id": player_id, "tile": int(tile["index"])})
	if bool(player.get("alive", false)) and state.get("phase", "") != "game_over":
		state["phase"] = "await_action"
		_set_action_options(player_id)
	_check_game_over()


func _calculate_rent(tile: Dictionary, owner_id: int) -> int:
	if _is_remodel() and tile.get("kind", "") == "property":
		if owner_id < 0:
			return 0
		if bool(tile.get("is_chain_store", false)):
			var chain_count: int = 0
			for candidate_value in state.get("board", []):
				if typeof(candidate_value) != TYPE_DICTIONARY:
					continue
				var candidate: Dictionary = candidate_value
				if candidate.get("kind", "") == "property" and int(candidate.get("owner", -1)) == owner_id and bool(candidate.get("is_chain_store", false)) and int(candidate.get("building_level", 0)) > 0:
					chain_count += 1
			return chain_count * 2000 * _facility_price_index()
		var target_name: String = str(tile.get("name", ""))
		var target_group: String = str(tile.get("group", ""))
		var normal_rent: int = 0
		for candidate_value in state.get("board", []):
			if typeof(candidate_value) != TYPE_DICTIONARY:
				continue
			var candidate: Dictionary = candidate_value
			if candidate.get("kind", "") != "property" or int(candidate.get("owner", -1)) != owner_id or bool(candidate.get("is_chain_store", false)):
				continue
			var candidate_name: String = str(candidate.get("name", ""))
			var same_road: bool = candidate_name == target_name and not target_name.is_empty()
			if target_name.is_empty():
				same_road = candidate_name.is_empty() and str(candidate.get("group", "")) == target_group
			if not same_road:
				continue
			var level: int = int(candidate.get("building_level", 0))
			var rents: Variant = candidate.get("rent_by_level", null)
			if typeof(rents) == TYPE_ARRAY and level >= 0 and level < rents.size():
				normal_rent += int(rents[level])
			else:
				normal_rent += int(candidate.get("rent", 0))
		return normal_rent * _facility_price_index()
	var group: String = str(tile.get("group", ""))
	var base: int = 0
	var board: Array = state.get("board", [])
	for candidate in board:
		if candidate.get("kind", "") == "property" and int(candidate.get("owner", -1)) == owner_id and str(candidate.get("group", "")) == group:
			base += int(candidate.get("rent", 0))
	# The reference describes same-owner same-road rent as combined. This is a
	# compact reconstruction until exact road segmentation is verified.
	return max(1, base)


func _charge_rent(debtor_id: int, creditor_id: int, amount: int) -> void:
	var debtor: Dictionary = _player(debtor_id)
	if amount <= 0:
		if amount == 0 and not _is_gods() and int(debtor.get("rent_shield", 0)) > 0:
			debtor["rent_shield"] = int(debtor.get("rent_shield", 0)) - 1
			_record_event("rent_blocked", {"player_id": debtor_id, "creditor_id": creditor_id, "amount": amount})
		return
	if AllianceRules.are_allied(self, debtor_id, creditor_id):
		_record_event("alliance_fee_waived", {"player_id": debtor_id, "creditor_id": creditor_id, "kind": "rent", "amount": amount})
		return
	var rent_tile: Dictionary = _tile_at(int(debtor.get("position", -1)))
	var rent_contributions: Array = AllianceRules.rent_contributions(self, rent_tile, creditor_id, amount)
	var nominal_amount: int = amount
	if rent_contributions.size() > 1:
		nominal_amount = 0
		for contribution_value in rent_contributions:
			if typeof(contribution_value) == TYPE_DICTIONARY:
				nominal_amount += max(0, int(contribution_value.get("amount", 0)))
		if nominal_amount <= 0:
			nominal_amount = amount
	var fee_waiver_reason: String = _god_property_fee_waiver_reason(creditor_id)
	if not fee_waiver_reason.is_empty():
		_record_god_property_fee_waived(debtor_id, creditor_id, fee_waiver_reason, "property")
		return
	var adjusted_amount: int = _god_adjust_charge_amount(debtor_id, nominal_amount, "rent")
	if _is_gods() and adjusted_amount <= 0:
		_record_event("god_charge_waived", {"player_id": debtor_id, "god_id": _player_god_id(debtor_id), "reason": "rent", "amount": nominal_amount})
		return
	if int(debtor.get("rent_shield", 0)) > 0:
		debtor["rent_shield"] = int(debtor["rent_shield"]) - 1
		_record_event("rent_blocked", {"player_id": debtor_id, "creditor_id": creditor_id, "amount": nominal_amount})
		return
	if not _financial_fee_gate(debtor_id, adjusted_amount, creditor_id, "rent", int(debtor.get("position", -1))):
		return
	_settle_financial_fee(debtor_id, creditor_id, adjusted_amount, "rent")


func _god_charge_amount_value(debtor_id: int, amount: int, reason: String) -> int:
	if amount <= 0 or not _is_gods() or (not ["rent", "facility"].has(reason) and not (_is_companies() and reason == "company")):
		return amount
	var adjusted_amount: int = amount
	match _player_god_id(debtor_id):
		1:
			adjusted_amount = int(floor(float(amount) / 2.0))
		2:
			adjusted_amount = 0
		5:
			adjusted_amount += int(floor(float(amount) / 2.0))
		6:
			adjusted_amount *= 2
	return adjusted_amount


func _god_adjust_charge_amount(debtor_id: int, amount: int, reason: String) -> int:
	var adjusted_amount := _god_charge_amount_value(debtor_id, amount, reason)
	if adjusted_amount != amount:
		_record_event("god_charge_modifier", {"player_id": debtor_id, "god_id": _player_god_id(debtor_id), "reason": reason, "from_amount": amount, "to_amount": adjusted_amount})
	return adjusted_amount


func _financial_fee_recipients(debtor_id: int, creditor_id: int, amount: int, kind: String) -> Array:
	if amount < 0:
		return []
	if kind != "rent":
		return [{"creditor_id": creditor_id, "amount": amount}]
	var debtor: Dictionary = _player(debtor_id)
	var node_id: int = int(debtor.get("position", -1))
	return AllianceRules.recipient_shares(self, debtor_id, creditor_id, amount, node_id)


func _financial_fee_recipient_caps_ok(debtor_id: int, creditor_id: int, amount: int, kind: String) -> bool:
	if amount < 0:
		return false
	var debtor: Dictionary = _player(debtor_id)
	if debtor.is_empty():
		return false
	var payable: int = mini(amount, int(debtor.get("cash", 0)) + int(debtor.get("deposit", 0)))
	for recipient_value in _financial_fee_recipients(debtor_id, creditor_id, payable, kind):
		if typeof(recipient_value) != TYPE_DICTIONARY:
			return false
		var recipient_id: int = int(recipient_value.get("creditor_id", -1))
		var recipient_amount: int = max(0, int(recipient_value.get("amount", 0)))
		if recipient_amount <= 0:
			continue
		if recipient_id < 0:
			continue
		if not _valid_player(recipient_id, true):
			return false
		if int(_player(recipient_id).get("cash", 0)) > FinancialRules.MAX_CASH - recipient_amount:
			return false
	return true


func _financial_fee_expected_amount(debtor_id: int, creditor_id: int, kind: String, node_id: int) -> int:
	if kind != "rent":
		return -1
	var tile: Dictionary = _tile_at(node_id)
	var base_amount: int = _calculate_rent(tile, creditor_id)
	var contributions: Array = AllianceRules.rent_contributions(self, tile, creditor_id, base_amount)
	if contributions.size() > 1:
		base_amount = 0
		for contribution_value in contributions:
			if typeof(contribution_value) == TYPE_DICTIONARY:
				base_amount += max(0, int(contribution_value.get("amount", 0)))
	return _god_charge_amount_value(debtor_id, base_amount, "rent")


func _financial_fee_gate(debtor_id: int, amount: int, creditor_id: int, kind: String, node_id: int, free_allowed: bool = true) -> bool:
	if amount <= 0:
		return true
	# The bounded player-cash representation is enforced at the financial fee
	# entrance. Generic event/god charges retain their original primitive.
	if not _financial_fee_recipient_caps_ok(debtor_id, creditor_id, amount, kind):
		_record_event("payment_rejected", {"player_id": debtor_id, "creditor_id": creditor_id, "amount": amount, "kind": kind, "error": "cash_cap"})
		return false
	var offer: Dictionary = FinancialRules.maybe_offer_free(self, debtor_id, creditor_id, amount, node_id, kind, free_allowed)
	if not bool(offer.get("offered", false)):
		return true
	if offer.has("error"):
		_record_event("financial_response_error", {"kind": kind, "player_id": debtor_id, "error": str(offer.get("error", ""))})
		return false
	if bool(offer.get("waived", false)):
		_record_event("financial_payment_waived", {"kind": kind, "player_id": debtor_id, "creditor_id": creditor_id, "amount": amount})
		return false
	if bool(offer.get("awaiting_response", false)):
		return false
	return true


func _settle_financial_fee(debtor_id: int, creditor_id: int, amount: int, kind: String) -> void:
	if amount <= 0:
		return
	var debtor: Dictionary = _player(debtor_id)
	if debtor.is_empty() or not bool(debtor.get("alive", false)):
		return
	var recipients: Array = _financial_fee_recipients(debtor_id, creditor_id, amount, kind)
	if recipients.size() < 2:
		_charge_amount(debtor_id, amount, creditor_id, kind, false)
		return
	var payable: int = mini(amount, int(debtor.get("cash", 0)) + int(debtor.get("deposit", 0)))
	if payable > 0:
		var cash_available: int = int(debtor.get("cash", 0))
		if payable > cash_available:
			_withdraw_internal(debtor_id, payable - cash_available)
		var paid_recipients: Array = _financial_fee_recipients(debtor_id, creditor_id, payable, kind)
		for recipient_value in paid_recipients:
			if typeof(recipient_value) != TYPE_DICTIONARY:
				continue
			var recipient_id: int = int(recipient_value.get("creditor_id", -1))
			var recipient_amount: int = max(0, int(recipient_value.get("amount", 0)))
			if recipient_amount > 0:
				_pay_from_player(debtor_id, recipient_amount, recipient_id)
		_record_event("payment", {"player_id": debtor_id, "creditor_id": creditor_id, "amount": payable, "reason": kind})
	if payable < amount:
		_declare_bankruptcy(debtor_id, creditor_id, amount, kind)


func _charge_amount(debtor_id: int, amount: int, creditor_id: int, reason: String, apply_god_modifier: bool = true) -> void:
	if amount <= 0:
		return
	var debtor: Dictionary = _player(debtor_id)
	if debtor.is_empty() or not bool(debtor.get("alive", false)):
		return
	var original_amount: int = amount
	if apply_god_modifier:
		amount = _god_adjust_charge_amount(debtor_id, amount, reason)
		if amount <= 0:
			_record_event("god_charge_waived", {"player_id": debtor_id, "god_id": _player_god_id(debtor_id), "reason": reason, "amount": original_amount})
			return
	# The manual's bankruptcy trigger is based on cash plus deposit. Deposits
	# are withdrawn to meet a charge; properties and shares go to auction only
	# after the player is declared bankrupt, never as a hidden rescue sale.
	var remaining: int = amount
	var cash_payment: int = min(remaining, int(debtor.get("cash", 0)))
	if cash_payment > 0:
		_pay_from_player(debtor_id, cash_payment, creditor_id)
		remaining -= cash_payment
	if remaining > 0 and int(debtor.get("deposit", 0)) > 0:
		var deposit_payment: int = min(remaining, int(debtor.get("deposit", 0)))
		_withdraw_internal(debtor_id, deposit_payment)
		_pay_from_player(debtor_id, deposit_payment, creditor_id)
		remaining -= deposit_payment
	if remaining > 0:
		_declare_bankruptcy(debtor_id, creditor_id, amount, reason)
		return
	_record_event("payment", {"player_id": debtor_id, "creditor_id": creditor_id, "amount": amount, "reason": reason})


func _pay_from_player(player_id: int, amount: int, creditor_id: int) -> void:
	if amount <= 0:
		return
	var player: Dictionary = _player(player_id)
	var paid: int = min(amount, int(player.get("cash", 0)))
	player["cash"] = int(player.get("cash", 0)) - paid
	if _is_companies() and creditor_id <= -2:
		var company := _company_by_id(-creditor_id-2)
		if not company.is_empty():
			company.monthly_profit = int(company.monthly_profit) + paid
			company.cumulative_profit = int(company.cumulative_profit) + paid
			return
	if creditor_id >= 0 and _valid_player(creditor_id, true):
		var creditor: Dictionary = _player(creditor_id)
		creditor["cash"] = int(creditor.get("cash", 0)) + paid
	else:
		_bank_add_cash(paid)


func _declare_bankruptcy(debtor_id: int, creditor_id: int, debt: int, reason: String) -> void:
	var debtor: Dictionary = _player(debtor_id)
	if debtor.is_empty() or not bool(debtor.get("alive", false)):
		return
	AllianceRules.clear_for_player(self, debtor_id)
	var debtor_is_current: bool = int(state.get("current_player", -1)) == debtor_id
	var was_current_movement: bool = debtor_is_current and state.get("phase", "") in ["await_roll", "await_route"]
	if _is_gods():
		# A bankrupt holder can no longer keep an attached god. Detach before the
		# alive flag changes so the owner-side reference and its paired respawn stay
		# consistent even when this charge occurs during graph movement.
		var player_god_id: int = _player_god_id(debtor_id)
		if player_god_id > 0:
			_detach_god(player_god_id, "bankrupt", true)
		# Recover from a partially inconsistent in-memory state where the object
		# points at the player but the player-side god_id was already lost.
		var owner_god_ids: Array = []
		for actor in state.get("god_objects", []):
			if typeof(actor) == TYPE_DICTIONARY and int(actor.get("owner", -1)) == debtor_id:
				owner_god_ids.append(int(actor.get("id", 0)))
		for owner_god_id in owner_god_ids:
			if _god_object_index(owner_god_id) >= 0:
				_detach_god(owner_god_id, "bankrupt", true)
	if EngineeringVehicle.is_active(debtor):
		debtor.erase("engineering_vehicle")
		debtor.erase("dream_vehicle_backup")
		debtor.erase("dream_days")
		debtor.erase("winter_sleep_days")
		debtor["vehicle"] = "walking"
		debtor["dice_count"] = 1
	var auction: Dictionary = _auction_assets(debtor_id, creditor_id)
	var loan: int = int(debtor.get("loan", 0))
	if loan > 0:
		var bank: Dictionary = state.get("bank", {})
		bank["loans"] = max(0, int(bank.get("loans", 0)) - loan)
		state["bank"] = bank
	if _is_hazards() and int(debtor.get("bomb_steps", 0)) > 0:
		# A carried timed bomb is an active road object, so bankruptcy releases
		# its finite slot before the player leaves the active roster.
		debtor["bomb_steps"] = 0
		_hazard_return_tool_to_supply("定時炸彈")
	debtor["cash"] = 0
	debtor["deposit"] = 0
	debtor["loan"] = 0
	debtor["loan_due_day"] = 0
	debtor["alive"] = false
	debtor["bankrupt"] = true
	# Do not let the bankrupt current player continue a pending route or expose
	# its bank state to the next actor. An unrelated debtor may be charged while
	# another player is moving; preserve that mover's route and bank state.
	if debtor_is_current:
		state["route_options"] = []
		state["pending_movement"] = {}
		state["remaining_steps"] = 0
		state["bank_access"] = false
		state["bank_landing"] = false
	var auctions: Array = state.get("bankruptcy_auctions", [])
	auctions.append(auction)
	state["bankruptcy_auctions"] = auctions
	_record_event("bankruptcy", {"player_id": debtor_id, "creditor_id": creditor_id, "debt": debt, "reason": reason, "auction_id": auction["auction_id"]})
	_check_game_over()
	# A landing or route charge advances immediately so a non-final bankruptcy
	# cannot leave a dead player as the current actor. Loan-debt bankruptcy from
	# end_turn is advanced by that caller after its final bookkeeping instead.
	if was_current_movement and not _settling_company_dividends and not _resolving_news and not _resolving_fate and state.get("phase", "") != "game_over":
		_advance_to_next_alive(debtor_id)


func _auction_assets(debtor_id: int, creditor_id: int) -> Dictionary:
	var debtor: Dictionary = _player(debtor_id)
	var board: Array = state.get("board", [])
	var property_ids: Array = debtor.get("properties", []).duplicate()
	var stock_holdings: Dictionary = debtor.get("stocks", {}).duplicate(true)
	var auction_id: int = state.get("bankruptcy_auctions", []).size() + 1
	var transfer_to: int = creditor_id if _valid_player(creditor_id, true) else -1
	var seen_assets: Dictionary = {}
	var auction_property_ids: Array = []
	for property_id in property_ids:
		var tile: Dictionary = _tile_at(int(property_id))
		if tile.is_empty():
			continue
		var asset_id: String = "tile:%d" % int(property_id)
		var canonical_property_id: int = int(property_id)
		if tile.get("kind", "") == "facility":
			var source_object_id: int = int(tile.get("source_object_id", -1))
			asset_id = "facility:%d" % source_object_id
			canonical_property_id = _facility_canonical_index(int(property_id))
		if seen_assets.has(asset_id):
			continue
		seen_assets[asset_id] = true
		auction_property_ids.append(canonical_property_id)
		if tile.get("kind", "") == "facility":
			var facility_updates: Dictionary = {"owner": transfer_to}
			if transfer_to < 0:
				facility_updates["building_level"] = 0
				facility_updates["facility_state"] = 0
			_update_facility_records(int(tile.get("source_object_id", -1)), facility_updates)
		else:
			if transfer_to >= 0:
				tile["owner"] = transfer_to
				var receiver: Dictionary = _player(transfer_to)
				var receiver_properties: Array = receiver.get("properties", [])
				if not receiver_properties.has(canonical_property_id):
					receiver_properties.append(canonical_property_id)
				receiver["properties"] = receiver_properties
			else:
				tile["owner"] = -1
				tile["building_level"] = 0
				if _is_remodel():
					tile["is_chain_store"] = false
				_update_tile_rent(tile)
		if transfer_to >= 0:
			var transferred_receiver: Dictionary = _player(transfer_to)
			var transferred_properties: Array = transferred_receiver.get("properties", [])
			if not transferred_properties.has(canonical_property_id):
				transferred_properties.append(canonical_property_id)
			transferred_receiver["properties"] = transferred_properties
		_record_event("auction_property", {"auction_id": auction_id, "property_id": canonical_property_id, "winner": transfer_to})
	debtor["properties"] = []
	if _is_companies():
		debtor["stocks"] = {}
		for stock_symbol in get_stock_symbols():
			var quantity := int(stock_holdings.get(stock_symbol, 0))
			var row: Dictionary = state.market.rows[stock_symbol]
			row.market_supply = int(row.market_supply) + quantity
			row.turn_supply = int(row.turn_supply) + quantity
			state.jackpot = int(state.jackpot) + OriginalStockMarket.quote(float(row.price), quantity)
			debtor.stocks[stock_symbol] = 0
		StockAccounting.clear_player(debtor, get_stock_symbols())
		_update_company_owners()
	else:
		debtor["stocks"] = {"tech": 0, "transport": 0, "energy": 0}
	if transfer_to >= 0 and not _is_companies():
		var receiver_stocks: Dictionary = _player(transfer_to).get("stocks", {})
		for symbol in get_stock_symbols():
			receiver_stocks[symbol] = int(receiver_stocks.get(symbol, 0)) + int(stock_holdings.get(symbol, 0))
		_player(transfer_to)["stocks"] = receiver_stocks
	# The reference resolves this as an auction. Until bidding is implemented,
	# the deterministic fallback releases assets to the bank.
	_recalculate_property_values()
	return {
		"auction_id": auction_id,
		"debtor": debtor_id,
		"creditor": creditor_id,
		"property_ids": auction_property_ids,
		"stocks": stock_holdings,
		"provisional_resolution": "transfer_to_creditor_or_release_to_bank",
	}


func choose_action(action: String, params: Dictionary = {}) -> Dictionary:
	var normalized: String = action.to_lower().strip_edges()
	if normalized == "respond_auction":
		return AuctionRules.respond(self, params)
	if normalized == "respond_finance":
		return FinancialRules.respond(self, params)
	if not AuctionRules.response(self).is_empty():
		return _error("請先回應拍賣")
	if not _pending_finance().is_empty():
		return _error("請先回應金融付款")
	if normalized == "respond_trap":
		return _respond_trap(params)
	if _trap_pending():
		return _error("請先回應陷害卡")
	if _sleep_active(_current_player()) and normalized != "end_turn":
		return _error("睡眠期間無法執行主動操作")
	var detained_time_machine_action: bool = normalized == "use_tool" and typeof(params.get("tool_id", null)) == TYPE_STRING and str(params.get("tool_id", "")) == TimeTransportRules.TIME_MACHINE
	if _is_statuses() and _status_active(_current_player()) and normalized != "end_turn" and not detained_time_machine_action:
		return _error("拘留期間無法執行主動操作")
	if _is_companies() and int(state.get("company_service_pending",0))>0 and normalized != "company_upgrade":
		return _error("請先選擇企業建設目標")
	if normalized == "set_vehicle":
		if _is_inventory():
			var pending_remote: Variant = state.get("pending_remote_dice", {})
			if typeof(pending_remote) == TYPE_DICTIONARY and not pending_remote.is_empty():
				return _error("遙控骰子已經排程")
		return set_vehicle(str(params.get("vehicle", "walking")), int(params.get("dice_count", -1)))
	if normalized == "end_turn":
		return end_turn()
	if normalized == "buy_stock" or normalized == "sell_stock":
		return _trade_stock(normalized, params)
	var inventory_card_phase: bool = _is_inventory() and normalized == "use_card" and state.get("phase", "") in ["await_roll", "await_action"]
	var requested_tool_id: String = str(params.get("tool_id", ""))
	var engineering_action_phase: bool = _is_inventory() and normalized == "use_tool" and requested_tool_id == "工程車" and state.get("phase", "") == "await_action"
	var inventory_tool_phase: bool = _is_inventory() and normalized == "use_tool" and (state.get("phase", "") == "await_roll" or engineering_action_phase)
	if not inventory_card_phase and not inventory_tool_phase and not _require_phase("await_action"):
		return _error("目前不是行動階段")
	var player_id: int = int(state.get("current_player", -1))
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return _error("目前玩家無法行動")
	if normalized == "use_card" and (BUILDING_CARD_IDS.has(str(params.get("card_id", ""))) or GOD_CARD_IDS.has(str(params.get("card_id", "")))):
		var building_pending_remote: Variant = state.get("pending_remote_dice", {})
		if typeof(building_pending_remote) == TYPE_DICTIONARY and not building_pending_remote.is_empty():
			return _error("遙控骰子已經排程")
	if _is_companies() and normalized in ["take_loan", "repay_loan"] and not _valid_int(params.get("amount", null), 1, MAX_GRAPH_POINTS):
		return _error("貸款或還款金額必須是正整數")
	if _is_sunday() and ["deposit", "withdraw", "take_loan", "repay_loan", "buy_vehicle"].has(normalized):
		return _error("週日銀行休息")
	var action_options_before: Array = state.get("action_options", []).duplicate(true)
	_set_action_options(player_id)
	var allowed_options: Array = state.get("action_options", [])
	if not allowed_options.has(normalized):
		state["action_options"] = action_options_before
		return _error("目前位置不能執行此行動")
	match normalized:
		"company_upgrade":
			return _company_upgrade(player_id,params)
		"buy_company":
			return _buy_company_stock(player_id, params)
		"choose_research":
			return _choose_research(player_id, params)
		"buy":
			return _buy_property(player_id, params)
		"build_facility":
			return _build_facility(player_id, params)
		"upgrade":
			return _upgrade_property(player_id)
		"deposit":
			return _deposit(player_id, int(params.get("amount", 0)))
		"withdraw":
			return _withdraw(player_id, int(params.get("amount", 0)))
		"take_loan", "repay_loan":
			if _is_companies():
				var loan_result: Dictionary = _source_loan_action(player_id, normalized, int(params.get("amount", 0)))
				if not bool(loan_result.get("ok", false)):
					state["action_options"] = action_options_before
				return loan_result
			return _take_loan(player_id, int(params.get("amount", 0)))
		"buy_vehicle":
			return _buy_vehicle(player_id, str(params.get("vehicle", "")))
		"buy_item", "sell_item":
			return _trade_item(player_id, normalized, params)
		"use_tool":
			return _use_tool(player_id, params)
		"use_card":
			var card_id: String = str(params.get("card_id", ""))
			if card_id == AuctionRules.CARD_ID:
				var auction_result: Dictionary = _use_card(player_id, card_id, -1, "", -1, params.get("cancel", false), null, null, null, null, params)
				if not bool(auction_result.get("ok", false)):
					state["action_options"] = action_options_before
				return auction_result
			var selected_target: Variant = player_id
			var selected_item_kind: Variant = null
			var selected_item_id: Variant = null
			var selected_cancel: Variant = false
			if card_id == "搶奪" or SleepRules.is_sleep_card(card_id) or FinancialRules.is_financial_card(card_id) or AllianceRules.is_alliance_card(card_id):
				# Keep raw values for theft, sleep, finance, and alliance boundaries so malformed
				# target and cancel fields are rejected instead of coerced.
				selected_target = params.get("target_id", null)
				selected_item_kind = params.get("item_kind", null)
				selected_item_id = params.get("item_id", null)
				selected_cancel = params.get("cancel", false)
			else:
				selected_target = int(params.get("target_id", player_id))
				selected_cancel = bool(params.get("cancel", false))
			var card_result: Dictionary = _use_card(player_id, card_id, selected_target, str(params.get("symbol", "")).to_lower(), params.get("tile_id", -1), selected_cancel, params.get("facility_type", null), params.get("visible_tile_ids", null), selected_item_kind, selected_item_id)
			if (card_id == "搶奪" or SleepRules.is_sleep_card(card_id) or FinancialRules.is_financial_card(card_id) or AllianceRules.is_alliance_card(card_id) or PROPERTY_CARD_IDS.has(card_id) or card_id == REMODEL_CARD_ID or BUILDING_CARD_IDS.has(card_id) or GOD_CARD_IDS.has(card_id)) and not bool(card_result.get("ok", false)):
				# Refreshing the action list above is needed after staging a card,
				# but a rejected exchange is required to be byte-for-byte atomic.
				state["action_options"] = action_options_before
			return card_result
		_:
			return _error("未知的行動")


func _trade_item(player_id: int, action: String, params: Dictionary) -> Dictionary:
	if not is_shop_available():
		return _error("目前位置沒有商店")
	var player: Dictionary = _player(player_id)
	var item_kind: String = str(params.get("item_kind", "")).to_lower().strip_edges()
	if not ["card", "tool"].has(item_kind):
		return _error("商品類型無效")
	var item_id: String = str(params.get("item_id", ""))
	var record: Dictionary = _inventory_record(item_kind, item_id)
	if record.is_empty():
		return _error("商品代號無效")
	if item_kind == "tool" and int(record.get("source_id", 0)) > OriginalInventory.FINITE_TOOL_SOURCE_ID_MAX:
		return _error("此道具尚未列入商店")
	var quantity_value: Variant = params.get("quantity", 1)
	if typeof(quantity_value) != TYPE_INT or int(quantity_value) <= 0 or int(quantity_value) > OriginalInventory.TOOL_CAPACITY_PER_TYPE:
		return _error("商品數量無效")
	var quantity: int = int(quantity_value)
	if item_kind == "card" and quantity != 1:
		return _error("卡片每次只能交易一張")
	var price: int = OriginalInventory.quote_buy(item_kind, item_id, quantity)
	var sale_price: int = OriginalInventory.quote_sale(item_kind, item_id, quantity)
	if price < 0 or sale_price < 0:
		return _error("商品價格無效")
	var owned: int = _shop_item_owned(player, item_kind, item_id)
	if action == "buy_item":
		if int(player.get("points", 0)) < price:
			return _error("點數不足")
		if item_kind == "card" and player.get("cards", []).size() >= OriginalInventory.CARD_CAPACITY:
			return _error("卡片背包已滿")
		if item_kind == "tool" and owned + quantity > OriginalInventory.TOOL_CAPACITY_PER_TYPE:
			return _error("道具數量超出上限")
		var grant_result: Dictionary
		if item_kind == "card":
			grant_result = OriginalInventory.grant_card(state["inventory_supply"], player["cards"], item_id)
		else:
			grant_result = OriginalInventory.grant_tool(state["inventory_supply"], player["tools"], item_id, quantity)
		if not bool(grant_result.get("ok", false)):
			return _error(str(grant_result.get("error", "商品供給不足")))
		player["points"] = int(player.get("points", 0)) - price
		_record_event("item_bought", {"player_id": player_id, "item_kind": item_kind, "item_id": item_id, "quantity": quantity, "price": price})
	else:
		if item_kind == "card" and owned < quantity:
			return _error("玩家沒有這張卡片")
		if item_kind == "tool" and owned < quantity:
			return _error("玩家沒有足夠的道具")
		if int(player.get("points", 0)) > MAX_GRAPH_POINTS - sale_price:
			return _error("點數超出上限")
		var consume_result: Dictionary
		if item_kind == "card":
			consume_result = OriginalInventory.consume_card(state["inventory_supply"], player["cards"], item_id)
		else:
			consume_result = OriginalInventory.consume_tool(state["inventory_supply"], player["tools"], item_id, quantity)
		if not bool(consume_result.get("ok", false)):
			return _error(str(consume_result.get("error", "商品持有量不足")))
		player["points"] = int(player.get("points", 0)) + sale_price
		_record_event("item_sold", {"player_id": player_id, "item_kind": item_kind, "item_id": item_id, "quantity": quantity, "sale_price": sale_price})
	_set_action_options(player_id)
	return _result(true, "商品交易完成", {"item_kind": item_kind, "item_id": item_id, "quantity": quantity, "price": price, "sale_price": sale_price})


func _use_tool(player_id: int, params: Dictionary) -> Dictionary:
	if not _is_inventory():
		return _error("道具只適用於道具地圖")
	var player: Dictionary = _player(player_id)
	var raw_tool_id: Variant = params.get("tool_id", null)
	if typeof(raw_tool_id) != TYPE_STRING:
		return _error("道具代號格式無效")
	var tool_id: String = str(raw_tool_id)
	if tool_id == TimeTransportRules.TIME_MACHINE:
		return TimeTransportRules.use_time_machine(self, player_id, params)
	if tool_id == TimeTransportRules.TRANSPORTER:
		return TimeTransportRules.use_transport(self, player_id, params)
	if MissileRules.is_missile(tool_id):
		return MissileRules.use(self, player_id, params)
	var engineering_landing: bool = tool_id == "工程車" and state.get("phase", "") == "await_action"
	if state.get("phase", "") != "await_roll" and not engineering_landing:
		return _error("道具只能在擲骰前使用")
	if not IMPLEMENTED_TOOL_IDS.has(tool_id):
		return _error("此道具效果尚未還原")
	if tool_id in ["地雷", "定時炸彈", "機器娃娃"] and not _is_hazards():
		return _error("此道具效果只適用於 v9 原作道路模式")
	var tools: Dictionary = player.get("tools", {})
	if int(tools.get(tool_id, 0)) <= 0:
		return _error("玩家沒有這項道具")
	if tool_id == "工程車":
		if typeof(params.get("cancel", false)) != TYPE_BOOL:
			return _error("工程車操作格式無效")
		if bool(params.get("cancel", false)):
			return _result(true, "已取消工程車", {"tool_id": tool_id, "cancelled": true})
		var pending_engineering_remote: Variant = state.get("pending_remote_dice", {})
		if typeof(pending_engineering_remote) == TYPE_DICTIONARY and not pending_engineering_remote.is_empty():
			return _error("遙控骰子已經排程")
		return _engineering_activation(player_id)
	if tool_id == "遙控骰子" and _inventory_movement_blocked(player):
		return _error("目前移動狀態無法使用遙控骰子")
	if tool_id in ["路障", "機器工人"] and _inventory_movement_blocked(player):
		return _error("目前移動狀態無法使用道具")
	if tool_id == "機器工人" and _god_investment_blocked(player_id):
		return _error("目前神明效果使建設失敗")
	if tool_id == "機器娃娃":
		var doll_consume_result: Dictionary = OriginalInventory.consume_tool(state["inventory_supply"], player["tools"], tool_id, 1)
		if not bool(doll_consume_result.get("ok", false)):
			return _error(str(doll_consume_result.get("error", "道具無法使用")))
		var doll_result: Dictionary = _machine_doll_use(player_id)
		_set_action_options(player_id)
		return _result(true, "機器娃娃已清除道路物件", {"tool_id": tool_id, "path": doll_result.get("path", []), "removed_hazards": doll_result.get("removed_hazards", []), "removed_roadblocks": doll_result.get("removed_roadblocks", []), "removed_gods": doll_result.get("removed_gods", [])})
	if (tool_id == "機車" and str(player.get("vehicle", "walking")) == "motorcycle") or (tool_id == "汽車" and str(player.get("vehicle", "walking")) == "car"):
		return _error("這項交通工具已經啟用")
	var pending_remote: Variant = state.get("pending_remote_dice", {})
	if typeof(pending_remote) == TYPE_DICTIONARY and not pending_remote.is_empty():
		return _error("遙控骰子已經排程")
	if tool_id in ["地雷", "定時炸彈"]:
		var hazard_target_value: Variant = params.get("tile_id", null)
		var hazard_target_error: String = _inventory_target_error(player_id, tool_id, hazard_target_value)
		if not hazard_target_error.is_empty():
			return _error(hazard_target_error)
		var hazard_target_id: int = int(hazard_target_value)
		if _is_hazards():
			if not _hazard_consume_tool_without_supply(player, tool_id):
				return _error("玩家沒有這項道具")
		else:
			var hazard_consume_result: Dictionary = OriginalInventory.consume_tool(state["inventory_supply"], player["tools"], tool_id, 1)
			if not bool(hazard_consume_result.get("ok", false)):
				return _error(str(hazard_consume_result.get("error", "道具無法使用")))
		var hazards: Dictionary = state.get("ground_hazards", {}).duplicate(true)
		hazards[str(hazard_target_id)] = {"kind": "mine" if tool_id == "地雷" else "timed_bomb", "placer_id": player_id}
		state["ground_hazards"] = hazards
		_record_event("tool_used", {"player_id": player_id, "tool_id": tool_id, "tile_id": hazard_target_id, "effect": "mine_placed" if tool_id == "地雷" else "timed_bomb_placed", "kind": "mine" if tool_id == "地雷" else "timed_bomb"})
		_set_action_options(player_id)
		return _result(true, "已使用道具", {"tool_id": tool_id, "tile_id": hazard_target_id})
	if tool_id == "路障" or tool_id == "機器工人":
		var target_id_value: Variant = params.get("tile_id", null)
		var target_error: String = _inventory_target_error(player_id, tool_id, target_id_value)
		if not target_error.is_empty():
			return _error(target_error)
		var target_id: int = int(target_id_value)
		if _is_hazards() and tool_id == "路障":
			if not _hazard_consume_tool_without_supply(player, tool_id):
				return _error("玩家沒有這項道具")
		else:
			var consume_target_result: Dictionary = OriginalInventory.consume_tool(state["inventory_supply"], player["tools"], tool_id, 1)
			if not bool(consume_target_result.get("ok", false)):
				return _error(str(consume_target_result.get("error", "道具無法使用")))
		if tool_id == "路障":
			var roadblocks: Dictionary = state.get("roadblocks", {}).duplicate(true)
			roadblocks[str(target_id)] = player_id
			state["roadblocks"] = roadblocks
			_record_event("tool_used", {"player_id": player_id, "tool_id": tool_id, "tile_id": target_id, "effect": "roadblock"})
		else:
			var worker_tile: Dictionary = _tile_at(target_id)
			if _is_facilities() and _is_graph() and worker_tile.get("kind", "") == "facility":
				var worker_facility: Dictionary = _facility_record(target_id)
				var worker_source_id: int = int(worker_facility.get("source_object_id", -1))
				var worker_level: int = int(worker_facility.get("building_level", 0)) + 1
				_update_facility_records(worker_source_id, {"building_level": worker_level})
				_apply_fortune_construction_bonus(player_id, worker_tile)
				state["property_action_used"] = true
				_recalculate_property_values()
				_record_event("tool_used", {"player_id": player_id, "tool_id": tool_id, "tile_id": _facility_canonical_index(target_id), "source_object_id": worker_source_id, "level": worker_level, "effect": "build_facility"})
			else:
				var worker_level: int = int(worker_tile.get("building_level", 0))
				var worker_cap: int = _property_level_cap(worker_tile, _is_remodel())
				if worker_level >= worker_cap:
					return _error("連鎖店已達最高一級" if worker_cap == 1 else "住宅已達最高五級")
				worker_tile["building_level"] = worker_level + 1
				_update_tile_rent(worker_tile)
				_apply_fortune_construction_bonus(player_id, worker_tile)
				state["property_action_used"] = true
				_recalculate_property_values()
				_record_event("tool_used", {"player_id": player_id, "tool_id": tool_id, "tile_id": target_id, "level": int(worker_tile["building_level"]), "effect": "build"})
		_set_action_options(player_id)
		return _result(true, "已使用道具", {"tool_id": tool_id, "tile_id": target_id})
	if tool_id == "機車":
		var motorcycle_result: Dictionary = _set_inventory_vehicle("motorcycle")
		if bool(motorcycle_result.get("ok", false)):
			motorcycle_result["tool_id"] = tool_id
		return motorcycle_result
	if tool_id == "汽車":
		var car_result: Dictionary = _set_inventory_vehicle("car")
		if bool(car_result.get("ok", false)):
			car_result["tool_id"] = tool_id
		return car_result
	if bool(params.get("cancel", false)):
		_set_action_options(player_id)
		return _result(true, "已取消遙控骰子", {"cancelled": true, "tool_id": tool_id})
	var remote_value: Variant = params.get("value", null)
	if not _valid_int(remote_value, 1, 6):
		return _error("遙控骰子點數必須介於 1 到 6")
	var consume_result: Dictionary = OriginalInventory.consume_tool(state["inventory_supply"], player["tools"], tool_id, 1)
	if not bool(consume_result.get("ok", false)):
		return _error(str(consume_result.get("error", "道具無法使用")))
	state["pending_remote_dice"] = {"player_id": player_id, "value": int(remote_value)}
	_record_event("tool_used", {"player_id": player_id, "tool_id": tool_id, "value": int(remote_value), "effect": "remote_dice"})
	_set_action_options(player_id)
	return _result(true, "遙控骰子已排程", {"tool_id": tool_id, "value": int(remote_value)})


func _buy_property(player_id: int, params: Dictionary = {}) -> Dictionary:
	var player: Dictionary = _player(player_id)
	var tile: Dictionary = _tile_at(int(player.get("position", 0)))
	if _god_investment_blocked(player_id):
		return _error("目前神明效果使買地失敗")
	if _is_gods() and _player_god_id(player_id) == 12 and int(tile.get("owner", -1)) == -1:
		return _error("土地公不能購買空地")
	if bool(state.get("property_action_used", false)):
		return _error("本次造訪已完成土地行動")
	if _is_facilities() and _is_graph() and tile.get("kind", "") == "facility":
		var facility: Dictionary = _facility_record(int(player.get("position", -1)))
		if facility.is_empty() or int(facility.get("owner", -1)) != -1:
			return _error("目前位置沒有可購買的設施用地")
		var facility_price: int = _facility_land_price(facility)
		if int(player.get("cash", 0)) < facility_price:
			return _error("現金不足")
		var facility_level: int = int(facility.get("building_level", 0))
		var fortune_facility_type: int = 0
		var fortune_facility_buy: bool = _is_gods() and _player_god_id(player_id) in [3, 4]
		if fortune_facility_buy and facility_level == 0:
			var requested_type: Variant = params.get("facility_type", null)
			if bool(player.get("is_ai", false)) and not params.has("facility_type"):
				fortune_facility_type = _rng.randi_range(1, FACILITY_LAB_TYPE if _is_research() else FACILITY_LAB_TYPE - 1)
			elif not _valid_int(requested_type, 0, FACILITY_LAB_TYPE if _is_research() else FACILITY_LAB_TYPE - 1):
				return _error("請選擇有效的設施類型")
			else:
				fortune_facility_type = int(requested_type)
		player["cash"] = int(player.get("cash", 0)) - facility_price
		_bank_add_cash(facility_price)
		var source_object_id: int = int(facility.get("source_object_id", -1))
		var facility_updates: Dictionary = {"owner": player_id}
		if fortune_facility_buy and facility_level == 0:
			facility_updates["facility_type"] = fortune_facility_type
		_update_facility_records(source_object_id, facility_updates)
		LandTenure.acquire(self, facility)
		if fortune_facility_buy:
			_apply_fortune_construction_bonus(player_id, _facility_record(int(player.get("position", -1))))
		var properties: Array = player.get("properties", []).duplicate(true)
		var canonical_id: int = _facility_canonical_index(int(player.get("position", -1)))
		if not properties.has(canonical_id):
			properties.append(canonical_id)
		player["properties"] = properties
		state["property_action_used"] = true
		_recalculate_property_values()
		var facility_event: Dictionary = {"player_id": player_id, "facility_id": canonical_id, "source_object_id": source_object_id, "price": facility_price}
		if fortune_facility_buy:
			var purchased_facility: Dictionary = _facility_record(canonical_id)
			facility_event["facility_type"] = int(purchased_facility.get("facility_type", -1))
			facility_event["building_level"] = int(purchased_facility.get("building_level", 0))
		_record_event("facility_bought", facility_event)
		_set_action_options(player_id)
		return _result(true, "已購買設施用地", {"tile_id": canonical_id, "source_object_id": source_object_id, "price": facility_price})
	if tile.get("kind", "") != "property" or int(tile.get("owner", -1)) != -1:
		return _error("目前位置沒有可購買的土地")
	var price: int = _property_buy_price(tile)
	if int(player.get("cash", 0)) < price:
		return _error("現金不足")
	player["cash"] = int(player.get("cash", 0)) - price
	_bank_add_cash(price)
	tile["owner"] = player_id
	LandTenure.acquire(self, tile)
	var properties: Array = player.get("properties", [])
	properties.append(int(tile["index"]))
	player["properties"] = properties
	_apply_fortune_construction_bonus(player_id, tile)
	state["property_action_used"] = true
	_recalculate_property_values()
	_record_event("property_bought", {"player_id": player_id, "property_id": int(tile["index"]), "price": price})
	_set_action_options(player_id)
	return _result(true, "已購買土地")


func _build_facility(player_id: int, params: Dictionary = {}) -> Dictionary:
	if not _is_facilities() or not _is_graph():
		return _error("設施建造只適用於原版設施地圖")
	var player: Dictionary = _player(player_id)
	if _god_investment_blocked(player_id):
		return _error("目前神明效果使建設失敗")
	var tile: Dictionary = _tile_at(int(player.get("position", -1)))
	if bool(state.get("property_action_used", false)):
		return _error("本次造訪已完成土地行動")
	if tile.get("kind", "") != "facility":
		return _error("目前位置不是設施用地")
	var facility: Dictionary = _facility_record(int(player.get("position", -1)))
	if int(facility.get("owner", -1)) != player_id:
		return _error("目前設施用地不是自己的")
	if int(facility.get("building_level", 0)) != 0:
		return _error("設施已經建成")
	var type_value: Variant = params.get("facility_type", null)
	if not _valid_int(type_value, 0, FACILITY_LAB_TYPE if _is_research() else FACILITY_LAB_TYPE - 1):
		return _error("研究所尚未開放建造") if _valid_int(type_value, FACILITY_LAB_TYPE, FACILITY_LAB_TYPE) else _error("設施類型無效")
	var facility_type: int = int(type_value)
	var price: int = _facility_land_price(facility)
	if int(player.get("cash", 0)) < price:
		return _error("現金不足")
	player["cash"] = int(player.get("cash", 0)) - price
	_bank_add_cash(price)
	var source_object_id: int = int(facility.get("source_object_id", -1))
	_update_facility_records(source_object_id, {"facility_type": facility_type, "building_level": 1, "facility_state": 0})
	_apply_fortune_construction_bonus(player_id, tile)
	state["property_action_used"] = true
	_recalculate_property_values()
	_record_event("facility_built", {"player_id": player_id, "facility_id": _facility_canonical_index(int(player.get("position", -1))), "source_object_id": source_object_id, "facility_type": facility_type, "building_level": 1, "price": price})
	_set_action_options(player_id)
	return _result(true, "已建造%s" % FACILITY_NAMES[facility_type], {"facility_type": facility_type, "level": 1, "price": price})


func _upgrade_property(player_id: int) -> Dictionary:
	var player: Dictionary = _player(player_id)
	var tile: Dictionary = _tile_at(int(player.get("position", 0)))
	if _god_investment_blocked(player_id):
		return _error("目前神明效果使加蓋失敗")
	if bool(state.get("property_action_used", false)):
		return _error("本次造訪已完成土地行動")
	if _is_facilities() and _is_graph() and tile.get("kind", "") == "facility":
		var facility: Dictionary = _facility_record(int(player.get("position", -1)))
		if int(facility.get("owner", -1)) != player_id:
			return _error("目前設施不是自己的")
		var facility_type: int = int(facility.get("facility_type", -1))
		var facility_level: int = int(facility.get("building_level", 0))
		if facility_level <= 0:
			return _error("請先選擇設施類型建造")
		if facility_type == FACILITY_LAB_TYPE and not _is_research():
			return _error("研究所尚未開放升級")
		if not _facility_type_valid(facility_type) or facility_level >= _facility_type_cap(facility_type):
			return _error("設施已達最高等級")
		var facility_price: int = _facility_upgrade_price(facility)
		if int(player.get("cash", 0)) < facility_price:
			return _error("現金不足")
		player["cash"] = int(player.get("cash", 0)) - facility_price
		_bank_add_cash(facility_price)
		var source_object_id: int = int(facility.get("source_object_id", -1))
		var next_level: int = facility_level + 1
		_update_facility_records(source_object_id, {"building_level": next_level})
		_apply_fortune_construction_bonus(player_id, _facility_record(int(player.get("position", -1))))
		state["property_action_used"] = true
		_recalculate_property_values()
		_record_event("facility_upgraded", {"player_id": player_id, "facility_id": _facility_canonical_index(int(player.get("position", -1))), "source_object_id": source_object_id, "facility_type": facility_type, "level": next_level, "price": facility_price})
		_set_action_options(player_id)
		return _result(true, "已升級設施", {"facility_type": facility_type, "level": next_level, "price": facility_price})
	if tile.get("kind", "") != "property" or int(tile.get("owner", -1)) != player_id:
		return _error("目前位置不是自己的土地")
	var level: int = int(tile.get("building_level", 0))
	var property_cap: int = _property_level_cap(tile, _is_remodel())
	if level >= property_cap:
		return _error("連鎖店已達最高一級" if property_cap == 1 else "土地已達最高五級")
	var price: int = _upgrade_price(tile)
	if int(player.get("cash", 0)) < price:
		return _error("現金不足")
	player["cash"] = int(player.get("cash", 0)) - price
	_bank_add_cash(price)
	tile["building_level"] = level + 1
	_update_tile_rent(tile)
	_apply_fortune_construction_bonus(player_id, tile)
	state["property_action_used"] = true
	_recalculate_property_values()
	_record_event("property_upgraded", {"player_id": player_id, "property_id": int(tile["index"]), "level": int(tile["building_level"]), "price": price})
	_set_action_options(player_id)
	return _result(true, "已升級土地")


func _buy_vehicle(player_id: int, vehicle: String) -> Dictionary:
	var player: Dictionary = _player(player_id)
	if _is_inventory():
		return _error("原版背包模式不能用現金購買交通工具")
	if not VEHICLE_COSTS.has(vehicle) or vehicle == "walking":
		return _error("交通工具無效")
	var vehicles: Dictionary = player.get("vehicles", {})
	if bool(vehicles.get(vehicle, false)):
		return _error("已擁有這項交通工具")
	var price: int = int(VEHICLE_COSTS[vehicle])
	if int(player.get("cash", 0)) < price:
		return _error("現金不足")
	player["cash"] = int(player.get("cash", 0)) - price
	vehicles[vehicle] = true
	player["vehicles"] = vehicles
	_bank_add_cash(price)
	_record_event("vehicle_bought", {"player_id": player_id, "vehicle": vehicle, "price": price})
	_set_action_options(player_id)
	return _result(true, "已購買交通工具")


func bank_transfer_limit(action: String, player_id: int = -1) -> int:
	var normalized := action.to_lower().strip_edges()
	if normalized not in ["deposit", "withdraw"]:
		return 0
	var resolved_player_id := player_id if player_id >= 0 else int(state.get("current_player", -1))
	var player: Dictionary = _player(resolved_player_id)
	var bank_value: Variant = state.get("bank", null)
	if player.is_empty() or not bool(player.get("alive", false)) or typeof(bank_value) != TYPE_DICTIONARY:
		return 0
	var cash_value: Variant = player.get("cash", null)
	var deposit_value: Variant = player.get("deposit", null)
	var bank_cash_value: Variant = bank_value.get("cash", null)
	var bank_deposits_value: Variant = bank_value.get("deposits", null)
	if not _valid_int(cash_value, 0, MAX_GRAPH_POINTS) or not _valid_int(deposit_value, 0, MAX_GRAPH_POINTS):
		return 0
	if not _valid_int(bank_cash_value, 0, MAX_GRAPH_POINTS) or not _valid_int(bank_deposits_value, 0, MAX_GRAPH_POINTS):
		return 0
	var cash := int(cash_value)
	var deposit := int(deposit_value)
	var bank_cash := int(bank_cash_value)
	var bank_deposits := int(bank_deposits_value)
	if normalized == "deposit":
		return mini(cash, mini(MAX_GRAPH_POINTS - deposit, mini(MAX_GRAPH_POINTS - bank_cash, MAX_GRAPH_POINTS - bank_deposits)))
	return mini(deposit, mini(bank_cash, MAX_GRAPH_POINTS - cash))


func _deposit(player_id: int, amount: int) -> Dictionary:
	var player: Dictionary = _player(player_id)
	if not bool(state.get("bank_access", false)):
		return _error("尚未經過銀行")
	if amount <= 0 or amount > int(player.get("cash", 0)):
		return _error("存款金額無效")
	if amount > bank_transfer_limit("deposit", player_id):
		return _error("存款金額超出可用上限")
	player["cash"] = int(player.get("cash", 0)) - amount
	player["deposit"] = int(player.get("deposit", 0)) + amount
	var bank: Dictionary = state.get("bank", {})
	bank["cash"] = int(bank.get("cash", 0)) + amount
	bank["deposits"] = int(bank.get("deposits", 0)) + amount
	state["bank"] = bank
	_record_event("deposit", {"player_id": player_id, "amount": amount})
	_set_action_options(player_id)
	return _result(true, "已存款")


func _withdraw(player_id: int, amount: int) -> Dictionary:
	var player: Dictionary = _player(player_id)
	if not bool(state.get("bank_access", false)):
		return _error("尚未經過銀行")
	if amount <= 0 or amount > int(player.get("deposit", 0)):
		return _error("提款金額無效")
	if not _bank_can_pay(amount):
		return _error("銀行現金暫不足")
	if amount > bank_transfer_limit("withdraw", player_id):
		return _error("提款金額超出可用上限")
	_withdraw_internal(player_id, amount)
	_record_event("withdraw", {"player_id": player_id, "amount": amount})
	_set_action_options(player_id)
	return _result(true, "已提款")


func _withdraw_internal(player_id: int, amount: int) -> void:
	var player: Dictionary = _player(player_id)
	var actual: int = min(amount, int(player.get("deposit", 0)))
	if actual <= 0:
		return
	player["deposit"] = int(player.get("deposit", 0)) - actual
	player["cash"] = int(player.get("cash", 0)) + actual
	var bank: Dictionary = state.get("bank", {})
	bank["deposits"] = max(0, int(bank.get("deposits", 0)) - actual)
	state["bank"] = bank
	_bank_subtract_cash(actual)


func bank_loan_limit(action: String, player_id: int = -1) -> int:
	if not _is_companies():
		return 0
	var resolved_id: int = player_id if player_id >= 0 else int(state.get("current_player", -1))
	var player: Dictionary = _player(resolved_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return 0
	return SourceLoans.limit(action.to_lower().strip_edges(), player, state.get("bank", {}), _player_wealth(resolved_id))


func _source_loan_action(player_id: int, action: String, amount: int) -> Dictionary:
	var player: Dictionary = _player(player_id)
	if not bool(state.get("bank_landing", false)):
		return _error("只有落在銀行時才能申請或償還貸款")
	if action == "take_loan" and _loan_block_active(player):
		return _error("新聞效果期間暫停申請貸款")
	if amount <= 0 or amount > bank_loan_limit(action, player_id):
		return _error("貸款或還款金額超出可用上限")
	if action == "take_loan":
		SourceLoans.take(player, state.bank, amount, int(state.day), int(state.weekday))
		_record_event("loan_taken", {"player_id": player_id, "amount": amount, "due_day": int(player.loan_due_day)})
	else:
		SourceLoans.repay(player, state.bank, amount)
		_record_event("loan_repaid", {"player_id": player_id, "amount": amount})
	_set_action_options(player_id)
	return _result(true, "貸款已存入帳戶" if action == "take_loan" else "已償還貸款")


func _take_loan(player_id: int, amount: int) -> Dictionary:
	var player: Dictionary = _player(player_id)
	if not bool(state.get("bank_landing", false)):
		return _error("只有落在銀行時才能申請貸款")
	if _loan_block_active(player):
		return _error("新聞效果期間暫停申請貸款")
	if amount <= 0 or amount > 10000:
		return _error("貸款金額必須介於 1 到 10000")
	if not _bank_can_pay(amount):
		return _error("銀行現金暫不足")
	player["cash"] = int(player.get("cash", 0)) + amount
	player["loan"] = int(player.get("loan", 0)) + amount
	player["loan_due_day"] = max(int(player.get("loan_due_day", 0)), int(state.get("day", 1)) + LOAN_TERM_DAYS)
	var bank: Dictionary = state.get("bank", {})
	bank["cash"] = int(bank.get("cash", 0)) - amount
	bank["loans"] = int(bank.get("loans", 0)) + amount
	state["bank"] = bank
	_record_event("loan_taken", {"player_id": player_id, "amount": amount, "due_day": int(player["loan_due_day"])})
	_set_action_options(player_id)
	return _result(true, "已取得三個月免息貸款")


func _trade_stock(action: String, params: Dictionary) -> Dictionary:
	if _is_companies():
		return _trade_company_market(action, params)
	if state.get("phase", "") == "game_over":
		return _error("遊戲已結束")
	if _is_sunday():
		return _error("週日證券市場休市")
	var player_id: int = int(state.get("current_player", -1))
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return _error("目前玩家無法交易")
	var symbol: String = str(params.get("symbol", params.get("stock", ""))).to_lower()
	var raw_quantity: Variant = params.get("quantity", params.get("shares", 0))
	if not get_stock_symbols().has(symbol) or not _valid_int(raw_quantity, 1, 1000000000):
		return _error("股票代號或數量無效")
	var quantity: int = int(raw_quantity)
	var market: Dictionary = state.get("market", {})
	var prices: Dictionary = market.get("prices", {})
	var price: int = int(prices.get(symbol, 0))
	var shares: Dictionary = player.get("stocks", {})
	if action == "buy_stock":
		var cost: int = price * quantity
		if int(player.get("cash", 0)) < cost:
			return _error("現金不足")
		if int(state.get("bank", {}).get("cash", 0)) > 1000000000000 - cost:
			return _error("交易後銀行現金超出上限")
		if int(shares.get(symbol, 0)) > 1000000000 - quantity:
			return _error("交易後持股超出上限")
		player["cash"] = int(player.get("cash", 0)) - cost
		shares[symbol] = int(shares.get(symbol, 0)) + quantity
		_bank_add_cash(cost)
		_record_event("stock_bought", {"player_id": player_id, "symbol": symbol, "quantity": quantity, "price": price})
	else:
		if int(shares.get(symbol, 0)) < quantity:
			return _error("持股不足")
		var proceeds: int = price * quantity
		if not _bank_can_pay(proceeds):
			return _error("銀行現金暫不足")
		if int(player.get("cash", 0)) > 1000000000000 - proceeds:
			return _error("交易後現金超出上限")
		shares[symbol] = int(shares.get(symbol, 0)) - quantity
		player["cash"] = int(player.get("cash", 0)) + proceeds
		_bank_subtract_cash(proceeds)
		_record_event("stock_sold", {"player_id": player_id, "symbol": symbol, "quantity": quantity, "price": price})
	player["stocks"] = shares
	_set_action_options(player_id)
	return _result(true, "股票交易完成")


func _inventory_purchase_card(player_id: int) -> Dictionary:
	var player: Dictionary = _player(player_id)
	var cards: Array = player.get("cards", [])
	if cards.find("購地") < 0:
		return _error("沒有這張卡片")
	if _is_gods_hospital_action(player):
		return _error("住院中不能使用購地卡")
	if bool(state.get("property_action_used", false)):
		return _error("本次造訪已完成土地行動")
	var tile: Dictionary = _tile_at(int(player.get("position", -1)))
	if _is_facilities() and _is_graph() and tile.get("kind", "") == "facility":
		var facility: Dictionary = _facility_record(int(player.get("position", -1)))
		var facility_owner: int = int(facility.get("owner", -1))
		if facility_owner == player_id:
			return _error("目前設施已經是自己的")
		if _is_gods() and facility_owner < 0:
			return _error("購地卡只能購買他人持有的設施")
		if facility_owner >= 0 and not _valid_player(facility_owner):
			return _error("目前設施所有權無效")
		var facility_price: int = inventory_purchase_price(facility)
		if facility_price < 0 or int(player.get("cash", 0)) < facility_price:
			return _error("現金不足")
		var facility_bank: Dictionary = state.get("bank", {})
		if int(facility_bank.get("cash", 0)) > 1000000000000 - facility_price:
			return _error("銀行資產上限不足")
		if facility_owner >= 0:
			var facility_previous_owner: Dictionary = _player(facility_owner)
			if int(facility_previous_owner.get("deposit", 0)) > 1000000000000 - facility_price or int(facility_bank.get("deposits", 0)) > 1000000000000 - facility_price:
				return _error("交易後存款超出上限")
		var facility_consume_result: Dictionary = OriginalInventory.consume_card(state["inventory_supply"], player["cards"], "購地")
		if not bool(facility_consume_result.get("ok", false)):
			return _error(str(facility_consume_result.get("error", "卡片無法使用")))
		player["cash"] = int(player.get("cash", 0)) - facility_price
		if facility_owner >= 0:
			var old_facility_owner: Dictionary = _player(facility_owner)
			var old_facility_properties: Array = old_facility_owner.get("properties", []).duplicate(true)
			var facility_id: int = _facility_canonical_index(int(player.get("position", -1)))
			while old_facility_properties.has(facility_id):
				old_facility_properties.erase(facility_id)
			old_facility_owner["properties"] = old_facility_properties
			old_facility_owner["deposit"] = int(old_facility_owner.get("deposit", 0)) + facility_price
			facility_bank["cash"] = int(facility_bank.get("cash", 0)) + facility_price
			facility_bank["deposits"] = int(facility_bank.get("deposits", 0)) + facility_price
		else:
			facility_bank["cash"] = int(facility_bank.get("cash", 0)) + facility_price
		state["bank"] = facility_bank
		var source_object_id: int = int(facility.get("source_object_id", -1))
		_update_facility_records(source_object_id, {"owner": player_id})
		LandTenure.acquire(self, facility)
		var buyer_facility_properties: Array = player.get("properties", []).duplicate(true)
		var buyer_facility_id: int = _facility_canonical_index(int(player.get("position", -1)))
		if not buyer_facility_properties.has(buyer_facility_id):
			buyer_facility_properties.append(buyer_facility_id)
		player["properties"] = buyer_facility_properties
		state["property_action_used"] = true
		_recalculate_property_values()
		_record_event("card_used", {"player_id": player_id, "card_id": "購地", "facility_id": buyer_facility_id, "source_object_id": source_object_id, "previous_owner": facility_owner, "price": facility_price, "effect": "purchase_facility"})
		_set_action_options(player_id)
		return _result(true, "已使用購地卡", {"card_id": "購地", "tile_id": buyer_facility_id, "source_object_id": source_object_id, "price": facility_price})
	if not _is_graph() or tile.get("kind", "") != "property":
		return _error("目前位置沒有可購買的普通住宅")
	var owner_id: int = int(tile.get("owner", -1))
	if owner_id == player_id:
		return _error("目前土地已經是自己的")
	if _is_gods() and owner_id < 0:
		return _error("購地卡只能購買他人持有的住宅")
	if owner_id >= 0 and not _valid_player(owner_id):
		return _error("目前土地所有權無效")
	var price: int = inventory_purchase_price(tile)
	if price < 0 or int(player.get("cash", 0)) < price:
		return _error("現金不足")
	var purchase_bank: Dictionary = state.get("bank", {})
	if int(purchase_bank.get("cash", 0)) > 1000000000000 - price:
		return _error("銀行資產上限不足")
	if owner_id >= 0:
		var previous_owner: Dictionary = _player(owner_id)
		if int(previous_owner.get("deposit", 0)) > 1000000000000 - price or int(purchase_bank.get("deposits", 0)) > 1000000000000 - price:
			return _error("交易後存款超出上限")
	var consume_result: Dictionary = OriginalInventory.consume_card(state["inventory_supply"], player["cards"], "購地")
	if not bool(consume_result.get("ok", false)):
		return _error(str(consume_result.get("error", "卡片無法使用")))
	player["cash"] = int(player.get("cash", 0)) - price
	if owner_id >= 0:
		var old_owner: Dictionary = _player(owner_id)
		var old_properties: Array = old_owner.get("properties", []).duplicate(true)
		while old_properties.has(int(tile.get("index", -1))):
			old_properties.erase(int(tile.get("index", -1)))
		old_owner["properties"] = old_properties
		old_owner["deposit"] = int(old_owner.get("deposit", 0)) + price
		var transfer_bank: Dictionary = state.get("bank", {})
		transfer_bank["cash"] = int(transfer_bank.get("cash", 0)) + price
		transfer_bank["deposits"] = int(transfer_bank.get("deposits", 0)) + price
		state["bank"] = transfer_bank
	else:
		_bank_add_cash(price)
	tile["owner"] = player_id
	LandTenure.acquire(self, tile)
	var buyer_properties: Array = player.get("properties", []).duplicate(true)
	if not buyer_properties.has(int(tile.get("index", -1))):
		buyer_properties.append(int(tile.get("index", -1)))
	player["properties"] = buyer_properties
	state["property_action_used"] = true
	_recalculate_property_values()
	_record_event("card_used", {"player_id": player_id, "card_id": "購地", "property_id": int(tile.get("index", -1)), "previous_owner": owner_id, "price": price, "effect": "purchase_property"})
	_set_action_options(player_id)
	return _result(true, "已使用購地卡", {"card_id": "購地", "tile_id": int(tile.get("index", -1)), "price": price})


func _inventory_demolition_card(player_id: int, tile_id: Variant) -> Dictionary:
	var target_error: String = _inventory_target_error(player_id, "拆除", tile_id)
	if not target_error.is_empty():
		return _error(target_error)
	var target_id: int = int(tile_id)
	var consume_result: Dictionary = OriginalInventory.consume_card(state["inventory_supply"], _player(player_id)["cards"], "拆除")
	if not bool(consume_result.get("ok", false)):
		return _error(str(consume_result.get("error", "卡片無法使用")))
	var tile: Dictionary = _tile_at(target_id)
	var effect: String = ""
	if _is_facilities() and _is_graph() and tile.get("kind", "") == "facility" and int(tile.get("building_level", 0)) > 0:
		var facility: Dictionary = _facility_record(target_id)
		var source_object_id: int = int(facility.get("source_object_id", -1))
		var next_level: int = max(0, int(facility.get("building_level", 0)) - 1)
		var facility_updates: Dictionary = {"building_level": next_level}
		if next_level == 0:
			facility_updates["facility_state"] = 0
		_update_facility_records(source_object_id, facility_updates)
		state["property_action_used"] = true
		_recalculate_property_values()
		effect = "demolish_facility"
		_record_event("card_used", {"player_id": player_id, "card_id": "拆除", "tile_id": _facility_canonical_index(target_id), "source_object_id": source_object_id, "level": next_level, "effect": effect})
	else:
		if tile.get("kind", "") == "property" and int(tile.get("building_level", 0)) > 0:
			tile["building_level"] = int(tile.get("building_level", 0)) - 1
			if _is_remodel() and int(tile.get("building_level", 0)) == 0:
				tile["is_chain_store"] = false
			_update_tile_rent(tile)
			state["property_action_used"] = true
			_recalculate_property_values()
			effect = "demolish_building"
		else:
			var roadblocks: Dictionary = state.get("roadblocks", {}).duplicate(true)
			var removed_roadblock: bool = roadblocks.has(str(target_id))
			roadblocks.erase(str(target_id))
			state["roadblocks"] = roadblocks
			if removed_roadblock and _is_hazards():
				_hazard_return_tool_to_supply("路障")
			effect = "remove_roadblock"
		_record_event("card_used", {"player_id": player_id, "card_id": "拆除", "tile_id": target_id, "effect": effect})
	_set_action_options(player_id)
	return _result(true, "已使用拆除卡", {"card_id": "拆除", "tile_id": target_id, "effect": effect})


func _use_god_card(player_id: int, card_id: String, visible_tile_ids: Variant = null, cancel: bool = false) -> Dictionary:
	if not _is_inventory() or not _is_gods() or not _is_graph() or not GOD_CARD_IDS.has(card_id):
		return _error("神明卡只適用於現有原版神明圖形地圖")
	if cancel:
		return _error("已取消神明卡")
	if state.get("phase", "") not in ["await_roll", "await_action"]:
		return _error("神明卡只能在擲骰前或行動階段使用")
	var pending_remote: Variant = state.get("pending_remote_dice", {})
	if typeof(pending_remote) == TYPE_DICTIONARY and not pending_remote.is_empty():
		return _error("遙控骰子已經排程")
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return _error("目前玩家無法行動")
	if _status_active(player):
		return _error("目前狀態無法使用神明卡")
	var cards: Variant = player.get("cards", null)
	if typeof(cards) != TYPE_ARRAY or not cards.has(card_id):
		return _error("沒有這張卡片")

	if card_id == "送神符":
		var current_god_id: int = _player_god_id(player_id)
		var dismissed_god_id: int = current_god_id if DISMISS_GOD_IDS.has(current_god_id) else 0
		var god_actor: Dictionary = {}
		if dismissed_god_id > 0:
			god_actor = _god_object(dismissed_god_id)
			if god_actor.is_empty() or int(god_actor.get("owner", -1)) != player_id:
				return _error("目前玩家的神明狀態無效")
		var bomb_steps_value: Variant = player.get("bomb_steps", 0)
		var bomb_steps: int = int(bomb_steps_value) if _valid_int(bomb_steps_value, 0, MAX_BOMB_STEPS) else -1
		var bomb_cleared: bool = _is_hazards() and bomb_steps > 0
		if dismissed_god_id <= 0 and not bomb_cleared:
			return _error("目前沒有可清除的神明或攜帶炸彈")
		var consume_result: Dictionary = OriginalInventory.consume_card(state["inventory_supply"], player["cards"], card_id)
		if not bool(consume_result.get("ok", false)):
			return _error(str(consume_result.get("error", "卡片無法使用")))
		if dismissed_god_id > 0:
			_detach_god(dismissed_god_id, "dismissed", true)
		if bomb_cleared:
			player["bomb_steps"] = 0
			_hazard_return_tool_to_supply("定時炸彈")
		var effect: String = "dismiss_god_and_clear_carried_bomb" if dismissed_god_id > 0 and bomb_cleared else "dismiss_god" if dismissed_god_id > 0 else "clear_carried_bomb"
		_record_event("card_used", {
			"player_id": player_id,
			"card_id": card_id,
			"god_id": dismissed_god_id,
			"bomb_cleared": bomb_cleared,
			"bomb_remaining": int(player.get("bomb_steps", 0)),
			"effect": effect,
		})
		_set_action_options(player_id)
		return _result(true, "已使用送神符", {"card_id": card_id, "god_id": dismissed_god_id, "bomb_cleared": bomb_cleared, "bomb_remaining": int(player.get("bomb_steps", 0)), "effect": effect})

	var target: Dictionary = god_card_target(player_id, visible_tile_ids)
	if target.is_empty():
		return _error("目前沒有可請來的神明")
	var target_god_id: int = int(target.get("id", 0))
	var target_actor: Dictionary = _god_object(target_god_id)
	if target_actor.is_empty() or int(target_actor.get("owner", -1)) >= 0:
		return _error("請神目標已不可用")
	var summon_phase: String = str(state.get("phase", ""))
	var summon_consume_result: Dictionary = OriginalInventory.consume_card(state["inventory_supply"], player["cards"], card_id)
	if not bool(summon_consume_result.get("ok", false)):
		return _error(str(summon_consume_result.get("error", "卡片無法使用")))
	if not _attach_god(player_id, target_god_id):
		return _error("請神目標無法附身")
	var summon_node: int = int(target.get("node", target_actor.get("node", -1)))
	var summon_event: Dictionary = {
		"player_id": player_id,
		"card_id": card_id,
		"god_id": target_god_id,
		"target_node": summon_node,
		"effect": "summon_god",
	}
	var caster_alive: bool = bool(_player(player_id).get("alive", false))
	if not caster_alive and summon_phase == "await_action" and state.get("phase", "") != "game_over" and int(state.get("current_player", -1)) == player_id:
		# Bankruptcy during an action-phase summon has not been handed off by the
		# charge path. Movement-phase summons already advance inside bankruptcy.
		_advance_to_next_alive(player_id)
	_record_event("card_used", summon_event)
	if caster_alive:
		_set_action_options(player_id)
	return _result(true, "已使用請神符", {"card_id": card_id, "god_id": target_god_id, "target_node": summon_node, "effect": "summon_god"})


func _use_theft_card(player_id: int, target_id: Variant, item_kind: Variant, item_id: Variant, cancel: Variant) -> Dictionary:
	if not _is_inventory():
		return _error("搶奪卡只適用於原版背包地圖")
	var transfer: Dictionary = TheftRules.resolve(state.get("inventory_supply", {}), state.get("players", []), player_id, target_id, item_kind, item_id, cancel)
	if not bool(transfer.get("ok", false)):
		return _error(str(transfer.get("error", "搶奪卡無法使用")))
	var event_payload: Dictionary = {
		"player_id": player_id,
		"card_id": "搶奪",
		"target_id": int(transfer.get("target_id", -1)),
		"item_kind": str(transfer.get("item_kind", "")),
		"item_id": str(transfer.get("item_id", "")),
		"quantity": int(transfer.get("quantity", 1)),
		"received": bool(transfer.get("received", false)),
		"capacity_full": bool(transfer.get("capacity_full", false)),
		"evicted_card_id": str(transfer.get("evicted_card_id", "")),
		"robbery_consumed": bool(transfer.get("robbery_consumed", false)),
		"effect": "theft",
	}
	_record_event("card_used", event_payload)
	_set_action_options(player_id)
	var result_extra: Dictionary = event_payload.duplicate(true)
	result_extra.erase("effect")
	var item_kind_text: String = "卡片" if str(transfer.get("item_kind", "")) == "card" else "道具"
	var item_name: String = str(_inventory_record(str(transfer.get("item_kind", "")), str(transfer.get("item_id", ""))).get("name", str(transfer.get("item_id", ""))))
	var result_message: String = "已搶奪%s：%s。" % [item_kind_text, item_name]
	if bool(transfer.get("received", false)):
		result_message += "物品已加入你的背包。"
		var evicted_card_id: String = str(transfer.get("evicted_card_id", ""))
		if not evicted_card_id.is_empty():
			result_message += "手牌已滿，先驅逐點券價格最低的%s。" % str(_inventory_record("card", evicted_card_id).get("name", evicted_card_id))
	else:
		result_message += "目標已失去物品，但你的%s持有數量已滿，物品未加入背包；搶奪卡已消耗。" % item_kind_text
	return _result(true, result_message, result_extra)


func _use_card(player_id: int, card_id: String, target_id: Variant = -1, symbol: String = "", tile_id: Variant = -1, cancel: Variant = false, facility_type: Variant = null, visible_tile_ids: Variant = null, theft_item_kind: Variant = null, theft_item_id: Variant = null, raw_params: Dictionary = {}) -> Dictionary:
	if _is_inventory():
		var pending_remote: Variant = state.get("pending_remote_dice", {})
		if typeof(pending_remote) == TYPE_DICTIONARY and not pending_remote.is_empty():
			return _error("遙控骰子已經排程")
	if SleepRules.is_sleep_card(card_id):
		return SleepRules.use_card(self, player_id, card_id, target_id, cancel)
	if FinancialRules.is_financial_card(card_id):
		return FinancialRules.use_card(self, player_id, card_id, target_id, cancel)
	if AllianceRules.is_alliance_card(card_id):
		return AllianceRules.use_card(self, player_id, target_id, cancel)
	if card_id == AuctionRules.CARD_ID:
		var auction_params: Dictionary = raw_params.duplicate(true) if not raw_params.is_empty() else {"card_id": card_id, "cancel": cancel}
		return AuctionRules.use_card(self, player_id, cancel, auction_params)
	if card_id == "搶奪":
		return _use_theft_card(player_id, target_id, theft_item_kind, theft_item_id, cancel)
	# All non-theft callers provide the legacy integer target and boolean
	# cancellation fields. Keep the rest of this method on its original path.
	var legacy_target_id: int = int(target_id)
	var legacy_cancel: bool = bool(cancel)
	if card_id == "購地" or card_id == "拆除":
		if not _is_inventory():
			return _error("原版背包卡片效果只適用於 v4")
		if card_id == "購地":
			return _inventory_purchase_card(player_id)
		return _inventory_demolition_card(player_id, tile_id)
	if card_id == REMODEL_CARD_ID:
		return _use_remodel_card(player_id, facility_type, legacy_cancel)
	if BUILDING_CARD_IDS.has(card_id):
		if not _is_building_cards():
			return _error("建物卡效果尚未還原")
		return _use_building_card(player_id, card_id, tile_id, legacy_cancel, facility_type)
	if GOD_CARD_IDS.has(card_id):
		return _use_god_card(player_id, card_id, visible_tile_ids, legacy_cancel)
	if card_id == "漲價" or card_id == "查封":
		if not _is_inventory() or not _is_facilities():
			return _error("設施卡片只適用於原版設施地圖")
		var status_target_error: String = _inventory_target_error(player_id, card_id, tile_id)
		if not status_target_error.is_empty():
			return _error(status_target_error)
		var status_player: Dictionary = _player(player_id)
		var status_consume: Dictionary = OriginalInventory.consume_card(state["inventory_supply"], status_player["cards"], card_id)
		if not bool(status_consume.get("ok", false)):
			return _error(str(status_consume.get("error", "卡片無法使用")))
		var status_tile: Dictionary = _tile_at(int(tile_id))
		var status_facility: Dictionary = _facility_record(int(tile_id))
		var status_source_id: int = int(status_facility.get("source_object_id", -1))
		var next_status: int = FACILITY_RAISED_BASE_STATE if card_id == "漲價" else FACILITY_SEALED_BASE_STATE
		var status_changes: Dictionary = {"facility_state": next_status}
		if _is_research() and card_id == "查封" and int(status_facility.get("facility_type", -1)) == FACILITY_LAB_TYPE:
			status_changes["research_turns"] = 0
		_update_facility_records(status_source_id, status_changes)
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "tile_id": int(tile_id), "facility_id": _facility_canonical_index(int(tile_id)), "source_object_id": status_source_id, "facility_state": next_status, "effect": "facility_raised" if card_id == "漲價" else "facility_sealed"})
		_set_action_options(player_id)
		return _result(true, "已使用%s卡" % card_id, {"card_id": card_id, "tile_id": int(tile_id), "facility_state": next_status})
	var player: Dictionary = _player(player_id)
	var cards: Array = player.get("cards", [])
	if card_id.is_empty():
		return _error("卡片代號無效")
	var index: int = cards.find(card_id)
	if index < 0 or index >= cards.size():
		return _error("沒有這張卡片")
	if _is_inventory() and not item_is_implemented("card", card_id):
		return _error("此卡片效果尚未還原")
	if PROPERTY_CARD_IDS.has(card_id):
		return _use_property_card(player_id, card_id, tile_id, legacy_cancel)
	if _is_statuses() and card_id in ["免罪", "嫁禍", "復仇"]:
		return _error("這張卡片只能在陷害時自動觸發")
	if _is_statuses() and card_id == "陷害":
		return _use_trap_card(player_id, target_id, legacy_cancel)
	if legacy_target_id < 0:
		legacy_target_id = player_id
	target_id = legacy_target_id
	if card_id == "停留" or card_id == "烏龜" or card_id == "轉向" or card_id == "均貧":
		var target_check: Dictionary = _player(target_id)
		if target_check.is_empty() or not bool(target_check.get("alive", false)):
			return _error("卡片目標無效")
	if card_id == "均貧" and target_id == player_id:
		return _error("均貧卡只能指定其他存活玩家")
	if card_id == "轉向" and not _is_graph():
		return _error("轉向卡只能在圖形地圖使用")
	if card_id == "紅" or card_id == "黑":
		if not get_stock_symbols().has(symbol):
			return _error("紅／黑卡需要指定股票代號")
		if _is_companies() and not bool(state.market.open):
			return _error("證券市場休市，無法使用紅／黑卡")
	if _is_inventory():
		var consume_result: Dictionary = OriginalInventory.consume_card(state["inventory_supply"], player["cards"], card_id)
		if not bool(consume_result.get("ok", false)):
			return _error(str(consume_result.get("error", "卡片無法使用")))
	else:
		cards.remove_at(index)
		player["cards"] = cards
	if card_id == "均富":
		var alive_players: Array = []
		var total_cash: int = 0
		for candidate in _players():
			if bool(candidate.get("alive", false)):
				alive_players.append(candidate)
				total_cash += int(candidate.get("cash", 0))
		if alive_players.size() > 0:
			var share: int = int(total_cash / alive_players.size())
			var remainder: int = total_cash - share * alive_players.size()
			for candidate in alive_players:
				candidate["cash"] = share
			if remainder > 0:
				player["cash"] = int(player.get("cash", 0)) + remainder
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "effect": "equalize_cash"})
	elif card_id == "均貧":
		var poor_target: Dictionary = _player(target_id)
		var combined_cash: int = int(player.get("cash", 0)) + int(poor_target.get("cash", 0))
		var poor_share: int = int(combined_cash / 2)
		var poor_remainder: int = combined_cash - poor_share * 2
		player["cash"] = poor_share
		poor_target["cash"] = poor_share
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "target_id": target_id, "effect": "equalize_poor", "combined_cash": combined_cash, "share": poor_share, "rounding_remainder": poor_remainder})
	elif card_id == "停留":
		# The target is intentionally supplied through the action's target_id.
		var target: Dictionary = _player(target_id)
		target["stay_next"] = max(1, int(target.get("stay_next", 0)))
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "target_id": target_id, "effect": "stay"})
	elif card_id == "烏龜":
		var turtle_target: Dictionary = _player(target_id)
		turtle_target["turtle_days"] = max(3, int(turtle_target.get("turtle_days", 0)))
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "target_id": target_id, "effect": "turtle"})
	elif card_id == "轉向":
		var turn_target: Dictionary = _player(target_id)
		var current_node: int = int(turn_target.get("position", -1))
		var old_previous_node: int = int(turn_target.get("previous_position", -1))
		var turn_candidates: Array = []
		var turn_tile: Dictionary = _tile_at(current_node)
		var adjacent: Variant = turn_tile.get("adjacent", [])
		if typeof(adjacent) == TYPE_ARRAY:
			for neighbor in adjacent:
				if not _valid_int(neighbor, 0, state.get("board", []).size() - 1):
					continue
				var neighbor_id: int = int(neighbor)
				if neighbor_id != old_previous_node and not turn_candidates.has(neighbor_id):
					turn_candidates.append(neighbor_id)
		turn_candidates.sort()
		var selected_previous: int = -1
		if not turn_candidates.is_empty():
			selected_previous = int(turn_candidates[_rng.randi_range(0, turn_candidates.size() - 1)])
		turn_target["previous_position"] = selected_previous
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "target_id": target_id, "effect": "reverse_direction", "from_previous_position": old_previous_node, "to_previous_position": selected_previous, "candidates": turn_candidates})
	elif card_id == "紅" or card_id == "黑":
		var market: Dictionary = state.get("market", {})
		if _is_companies():
			OriginalStockMarket.apply_card(market, symbol, card_id == "紅")
		else:
			var trends: Dictionary = market.get("trends", {})
			trends[symbol] = {"direction": "up" if card_id == "紅" else "down", "days": 3, "rate": 0.10}
			market["trends"] = trends
		state["market"] = market
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "symbol": symbol, "effect": "stock_up" if card_id == "紅" else "stock_down", "days": 2 if _is_companies() else 3})
	else:
		_record_event("card_used", {"player_id": player_id, "card_id": card_id, "effect": "provisional_unknown"})
	_set_action_options(player_id)
	return _result(true, "已使用卡片")


func _draw_event_card(player_id: int) -> void:
	if _is_inventory():
		var inventory_player: Dictionary = _player(player_id)
		var draw_result: Dictionary = OriginalInventory.receive_random_card(state["inventory_supply"], inventory_player["cards"], _rng)
		if bool(draw_result.get("ok", false)):
			_record_event("event_drawn", {"player_id": player_id, "card_id": str(draw_result.get("drawn_card_id", "")), "evicted_card_id": str(draw_result.get("evicted_card_id", ""))})
		else:
			_record_event("event_draw_failed", {"player_id": player_id, "reason": str(draw_result.get("error", "卡片供給不足"))})
		return
	var card: Dictionary = EVENT_CARDS[_rng.randi_range(0, EVENT_CARDS.size() - 1)].duplicate(true)
	_record_event("event_drawn", {"player_id": player_id, "card_id": card["id"], "name": card["name"]})
	match str(card.get("kind", "")):
		"card":
			_grant_card(player_id, str(card["id"]))
		"fee":
			_charge_amount(player_id, int(card["amount"]), -1, "event")
		"move":
			_move_player(player_id, int(card["amount"]))
			if bool(_player(player_id).get("alive", false)):
				_resolve_landing(player_id)
		"deposit":
			var player: Dictionary = _player(player_id)
			player["deposit"] = int(player.get("deposit", 0)) + int(card["amount"])
			var bank: Dictionary = state.get("bank", {})
			bank["deposits"] = int(bank.get("deposits", 0)) + int(card["amount"])
			state["bank"] = bank
			_record_event("event_deposit", {"player_id": player_id, "amount": int(card["amount"])})


func _grant_random_card(player_id: int, reason: String) -> void:
	if _is_inventory():
		var inventory_player: Dictionary = _player(player_id)
		var draw_result: Dictionary = OriginalInventory.receive_random_card(state["inventory_supply"], inventory_player["cards"], _rng)
		var draw_payload: Dictionary = {"player_id": player_id}
		if bool(draw_result.get("ok", false)):
			draw_payload["card_id"] = str(draw_result.get("drawn_card_id", ""))
			draw_payload["evicted_card_id"] = str(draw_result.get("evicted_card_id", ""))
		else:
			draw_payload["error"] = str(draw_result.get("error", "卡片供給不足"))
		_record_event(reason, draw_payload)
		return
	var card: Dictionary = EVENT_CARDS[_rng.randi_range(0, EVENT_CARDS.size() - 1)]
	if str(card.get("kind", "")) != "card":
		card = EVENT_CARDS[0]
	var grant_result: Dictionary = _grant_card(player_id, str(card["id"]))
	var event_payload: Dictionary = {"player_id": player_id, "card_id": str(card["id"])}
	if _is_inventory() and not bool(grant_result.get("ok", false)):
		event_payload["error"] = str(grant_result.get("error", "卡片供給不足"))
	_record_event(reason, event_payload)


func _grant_card(player_id: int, card_id: String) -> Dictionary:
	if _is_inventory():
		return OriginalInventory.grant_card(state["inventory_supply"], _player(player_id)["cards"], card_id)
	var player: Dictionary = _player(player_id)
	var cards: Array = player.get("cards", [])
	if cards.size() >= 15:
		_record_event("card_limit", {"player_id": player_id, "card_id": card_id, "limit": 15})
		return {"ok": false, "error": "卡片背包已滿"}
	cards.append(card_id)
	player["cards"] = cards
	return {"ok": true, "error": "", "card_id": card_id}


func end_turn() -> Dictionary:
	if not AuctionRules.response(self).is_empty():
		return _error("請先回應拍賣")
	if not _pending_finance().is_empty():
		return _error("請先回應金融付款")
	if _trap_pending():
		return _error("請先回應陷害卡")
	if not _require_phase("await_action"):
		return _error("目前不是結束回合階段")
	if _is_companies() and int(state.get("company_service_pending",0))>0:
		return _error("請先選擇企業建設目標")
	var player_id: int = int(state.get("current_player", -1))
	var player: Dictionary = _player(player_id)
	if bool(player.get("alive", false)):
		player["turns_taken"] = int(player.get("turns_taken", 0)) + 1
		_repay_due_loan(player_id)
		if not _is_setup():
			_tick_market()
		# Original god property effects run at the common landed-node tail, after
		# rent/service and the player's explicit property action. A skipped or
		# dog-stopped turn has no successful landing settlement to mutate.
		var last_roll_value: Variant = state.get("last_roll", [])
		if _is_gods() and typeof(last_roll_value) == TYPE_ARRAY and not last_roll_value.is_empty() and not _status_active(player):
			_apply_god_property_effect(player_id, _tile_at(int(player.get("position", -1))), true)
		if typeof(last_roll_value) == TYPE_ARRAY and not last_roll_value.is_empty() and not _status_active(player):
			# Decide after cards and god effects have settled the real landing.
			if bool(player.get("is_ai", false)):
				_engineering_ai_action(player_id)
			_engineering_demolition(player_id)
	if _sleep_active(player) and not _status_active(player):
		SleepRules._sleep_tick(self, player_id)
	state["bank_access"] = false
	state["bank_landing"] = false
	state["doubles_count"] = 0
	state["property_action_used"] = false
	_advance_to_next_alive(player_id)
	return _result(true, "回合結束")


func _advance_to_next_alive(previous_id: int) -> void:
	_check_game_over()
	state.erase("stationary_turn")
	if state.get("phase", "") == "game_over":
		return
	var players: Array = _players()
	var next_id: int = -1
	for offset in range(1, players.size() + 1):
		var candidate: int = (previous_id + offset) % players.size()
		if bool(players[candidate].get("alive", false)):
			next_id = candidate
			break
	if next_id < 0:
		_check_game_over()
		return
	var wraps: bool = next_id <= previous_id
	if wraps:
		if _is_setup():
			var current_elapsed: int = int(state.get("elapsed", max(0, int(state.get("day", 1)) - 1)))
			var next_date: Dictionary = GameCalendar.add_days(state.get("start_date", {}), current_elapsed + 1)
			if next_date.is_empty():
				_sync_state()
				_check_setup_end_conditions(true)
				return
		state["round"] = int(state.get("round", 1)) + 1
		state["day"] = int(state.get("day", 1)) + 1
		_tick_gods()
		_tick_company_insurance()
		# Facility temporary states decay once per complete player cycle. This is
		# deliberately outside the setup/non-setup branches so a wrapped round
		# cannot decrement the same source record twice.
		_tick_facility_states()
		if _is_setup():
			# The original flow advances the calendar first, settles a deadline or
			# wealth target, then updates the market and pays month-end interest.
			state["turn"] = int(state.get("turn", 1)) + 1
			_sync_state()
			if _check_setup_end_conditions():
				return
			if _is_companies():
				_decrement_market_trends()
			_tick_market()
			if not _is_companies():
				_decrement_market_trends()
			_settle_company_dividends()
			_apply_month_boundary()
			if state.get("phase", "") == "game_over":
				return
			# Source expiry follows deadline, market and month-end settlement.
			LandTenure.expire_today(self)
		else:
			var market: Dictionary = state.get("market", {})
			var trends: Dictionary = market.get("trends", {})
			for symbol in trends.keys():
				var trend: Dictionary = trends[symbol]
				trend["days"] = int(trend.get("days", 0)) - 1
				if int(trend["days"]) <= 0:
					trends.erase(symbol)
				else:
					trends[symbol] = trend
			market["trends"] = trends
			state["market"] = market
			_apply_month_boundary()
	if _is_companies() and not bool(_player(next_id).get("alive", false)):
		for offset in range(1, players.size()+1):
			var candidate := (previous_id+offset) % players.size()
			if bool(_player(candidate).get("alive", false)):
				next_id = candidate
				break
	if not (_is_setup() and wraps):
		state["turn"] = int(state.get("turn", 1)) + 1
	state["current_player"] = next_id
	_admit_loan_block(_player(next_id))
	_engineering_admit(next_id)
	AllianceRules.admit_player(self, next_id)
	if _is_research():
		# The action guard belongs to the newly admitted turn. Production is
		# processed once here, after ownership changes and before the next roll.
		state["research_action_used"] = false
		_tick_research_for_owner(next_id)
	state["phase"] = "await_roll"
	state["last_roll"] = []
	state["last_total"] = 0
	if _is_facilities():
		state["last_roll_total"] = 0
	if _is_companies():
		state["company_purchase_remaining"] = 1000
		state["company_service_pending"] = 0
		OriginalStockMarket.reset_turn_supply(state.market, _rng)
	_set_action_options(next_id)
	_record_event("turn_started", {"player_id": next_id, "day": int(state["day"])})


func _apply_month_boundary() -> void:
	_sync_state()
	if _is_setup():
		var elapsed: int = int(state.get("elapsed", 0))
		if elapsed <= 0:
			return
		var start_date: Dictionary = state.get("start_date", {})
		var previous_date: Dictionary = GameCalendar.add_days(start_date, elapsed - 1)
		var current_date: Dictionary = state.get("date", {})
		if previous_date.is_empty() or current_date.is_empty() or int(previous_date["month"]) == int(current_date["month"]):
			return
		var last_settled_month: Dictionary = state.get("last_settled_month", {})
		if not last_settled_month.is_empty() and int(last_settled_month.get("year", -1)) == int(previous_date["year"]) and int(last_settled_month.get("month", -1)) == int(previous_date["month"]):
			return
		_apply_deposit_interest()
		if _is_companies(): state.company_months = int(state.company_months) + 1
		state["last_settled_month"] = {"year": int(previous_date["year"]), "month": int(previous_date["month"])}
		_record_event("month_end_settlement", {"month": int(previous_date["month"]), "year": int(previous_date["year"])})
		return
	if int(state.get("day_of_month", 1)) != DAYS_PER_MONTH:
		return
	_apply_deposit_interest()
	_record_event("month_end_settlement", {"month": int(state.get("month", 1))})


func _apply_deposit_interest() -> void:
	var players: Array = _players()
	for player in players:
		if not bool(player.get("alive", false)) or int(player.get("loan", 0)) > 0:
			continue
		var deposit: int = int(player.get("deposit", 0))
		if deposit <= 0:
			continue
		var interest: int = int(floor(float(deposit) * MONTHLY_DEPOSIT_RATE))
		if interest <= 0:
			continue
		player["deposit"] = deposit + interest
		var bank: Dictionary = state.get("bank", {})
		bank["deposits"] = int(bank.get("deposits", 0)) + interest
		state["bank"] = bank
		_bank_subtract_cash(interest)
		_record_event("monthly_interest", {"player_id": int(player["id"]), "amount": interest})


func _repay_due_loan(player_id: int) -> void:
	var player: Dictionary = _player(player_id)
	var loan: int = int(player.get("loan", 0))
	if loan <= 0 or int(state.get("day", 1)) < int(player.get("loan_due_day", 0)):
		return
	var available: int = int(player.get("cash", 0)) + int(player.get("deposit", 0))
	if _is_companies():
		var payment: int = bank_loan_limit("repay_loan", player_id)
		if payment > 0:
			SourceLoans.repay(player, state.bank, payment)
		if available < loan:
			_declare_bankruptcy(player_id, -1, int(player.loan), "loan_due")
		elif int(player.loan) == 0:
			_record_event("loan_repaid", {"player_id": player_id, "amount": loan})
		# A saturated bank cash ledger can defer the remaining cash payment;
		# do not overflow a valid save or bankrupt a solvent player.
		return
	if available < loan:
		var deposit_payment: int = int(player.get("deposit", 0))
		if deposit_payment > 0:
			_withdraw_internal(player_id, deposit_payment)
		var cash_payment: int = int(player.get("cash", 0))
		if cash_payment > 0:
			_pay_from_player(player_id, cash_payment, -1)
		var remaining_loan: int = max(0, loan - cash_payment)
		player["loan"] = remaining_loan
		var bank: Dictionary = state.get("bank", {})
		bank["loans"] = max(0, int(bank.get("loans", 0)) - cash_payment)
		state["bank"] = bank
		_declare_bankruptcy(player_id, -1, remaining_loan, "loan_due")
		return
	if int(player.get("cash", 0)) < loan:
		_withdraw_internal(player_id, loan - int(player.get("cash", 0)))
	player["cash"] = int(player.get("cash", 0)) - loan
	player["loan"] = 0
	player["loan_due_day"] = 0
	var bank: Dictionary = state.get("bank", {})
	bank["cash"] = int(bank.get("cash", 0)) + loan
	bank["loans"] = max(0, int(bank.get("loans", 0)) - loan)
	state["bank"] = bank
	_record_event("loan_repaid", {"player_id": player_id, "amount": loan})


func _tick_market() -> void:
	if _is_companies():
		var company_prices: Dictionary = {}
		for company in state.get("companies", []):
			company_prices[int(company.id)] = int(company.stock_value) / 10000
		OriginalStockMarket.tick(state.market, company_prices, _rng)
		_record_event("market_tick", {"prices": state.market.prices.duplicate(true)})
		return
	if _is_sunday():
		return
	var market: Dictionary = state.get("market", {})
	var prices: Dictionary = market.get("prices", {})
	var trends: Dictionary = market.get("trends", {})
	for symbol in get_stock_symbols():
		var old_price: int = int(prices.get(symbol, STOCK_BASE_PRICES.get(symbol, 0)))
		var delta: int = _rng.randi_range(-10, 10)
		var trend: Dictionary = trends.get(symbol, {})
		if int(trend.get("days", 0)) > 0:
			delta += 10 if str(trend.get("direction", "")) == "up" else -10
		prices[symbol] = max(10, int(round(float(old_price) * (100.0 + float(delta)) / 100.0)))
	market["prices"] = prices
	state["market"] = market
	_record_event("market_tick", {"prices": prices.duplicate(true)})


func _decrement_market_trends() -> void:
	if _is_companies():
		OriginalStockMarket.decrement_status(state.market)
		_sync_state()
		return
	var market: Dictionary = state.get("market", {})
	var trends: Dictionary = market.get("trends", {})
	for symbol in trends.keys():
		var trend: Dictionary = trends[symbol]
		trend["days"] = int(trend.get("days", 0)) - 1
		if int(trend["days"]) <= 0:
			trends.erase(symbol)
		else:
			trends[symbol] = trend
	market["trends"] = trends
	state["market"] = market


func _update_tile_rent(tile: Dictionary) -> void:
	if _is_graph() and tile.has("rent_by_level") and tile.get("rent_by_level") is Array:
		var rents: Array = tile.get("rent_by_level", [])
		var graph_level: int = clampi(int(tile.get("building_level", 0)), 0, max(0, rents.size() - 1))
		if not rents.is_empty():
			tile["rent"] = int(rents[graph_level])
			return
	var base: int = int(tile.get("base_rent", 0))
	var level: int = int(tile.get("building_level", 0))
	tile["rent"] = base * (1 + level * 2)


func _recalculate_property_values() -> void:
	var board: Array = state.get("board", [])
	for player in _players():
		var total: int = 0
		var seen_assets: Dictionary = {}
		for property_id in player.get("properties", []):
			if not _valid_int(property_id, 0, board.size() - 1):
				continue
			var tile: Dictionary = board[int(property_id)]
			if tile.get("kind", "") == "facility":
				var source_object_id: int = int(tile.get("source_object_id", -1))
				var facility_key: String = "facility:%d" % source_object_id
				if seen_assets.has(facility_key):
					continue
				seen_assets[facility_key] = true
				total += _facility_land_price(tile) + _facility_upgrade_price(tile) * int(tile.get("building_level", 0))
			else:
				var property_key: String = "tile:%d" % int(property_id)
				if seen_assets.has(property_key):
					continue
				seen_assets[property_key] = true
				total += int(tile.get("cost", 0)) + int(tile.get("upgrade_cost", 0)) * int(tile.get("building_level", 0))
		player["property_values"] = total


func _bank_can_pay(amount: int) -> bool:
	return int(state.get("bank", {}).get("cash", 0)) >= amount


func _bank_add_cash(amount: int) -> void:
	var bank: Dictionary = state.get("bank", {})
	bank["cash"] = int(bank.get("cash", 0)) + max(0, amount)
	state["bank"] = bank


func _bank_subtract_cash(amount: int) -> void:
	var bank: Dictionary = state.get("bank", {})
	bank["cash"] = max(0, int(bank.get("cash", 0)) - max(0, amount))
	state["bank"] = bank


func _player_wealth(player_id: int) -> int:
	var player: Dictionary = _player(player_id)
	if player.is_empty():
		return 0
	var wealth: int = int(player.get("cash", 0)) + int(player.get("deposit", 0)) - int(player.get("loan", 0))
	var prices: Dictionary = state.get("market", {}).get("prices", {})
	var stocks: Dictionary = player.get("stocks", {})
	for symbol in get_stock_symbols():
		# The original routine truncates the per-share market value to an
		# integer, which is already represented by integer prices in this state.
		wealth += int(stocks.get(symbol, 0)) * int(prices.get(symbol, STOCK_BASE_PRICES.get(symbol, 0)))
	var seen_assets: Dictionary = {}
	for property_id in player.get("properties", []):
		var tile: Dictionary = _tile_at(int(property_id))
		if tile.is_empty():
			continue
		if tile.get("kind", "") == "facility":
			var facility_key: String = "facility:%d" % int(tile.get("source_object_id", -1))
			if seen_assets.has(facility_key):
				continue
			seen_assets[facility_key] = true
			wealth += _facility_land_price(tile) + _facility_upgrade_price(tile) * int(tile.get("building_level", 0))
		else:
			var property_key: String = "tile:%d" % int(property_id)
			if seen_assets.has(property_key):
				continue
			seen_assets[property_key] = true
			wealth += int(tile.get("cost", 0)) + int(tile.get("upgrade_cost", 0)) * int(tile.get("building_level", 0))
	return wealth


func get_player_wealth(player_id: int) -> int:
	return _player_wealth(player_id)


func _richest_alive_player() -> int:
	var winner: int = -1
	var setup_save: bool = _is_setup()
	var best_wealth: int = 0 if setup_save else INT64_MIN
	# v3 only reports a winner for positive wealth; older saves retain their
	# original first-player fallback when every alive player has no wealth.
	for player in _players():
		if not bool(player.get("alive", false)):
			continue
		var player_id: int = int(player.get("id", -1))
		var wealth: int = _player_wealth(player_id)
		# Strictly greater preserves the earlier player on a tie.
		if setup_save and wealth <= 0:
			continue
		if winner < 0 or wealth > best_wealth:
			winner = player_id
			best_wealth = wealth
	return winner


func _check_setup_end_conditions(calendar_boundary: bool = false) -> bool:
	if not _is_setup() or state.get("phase", "") == "game_over":
		return false
	var elapsed: int = int(state.get("elapsed", max(0, int(state.get("day", 1)) - 1)))
	var day_limit: int = int(state.get("day_limit", 0))
	var wealth_multiplier: int = int(state.get("wealth_multiplier", 0))
	var wealth_target: int = int(state.get("initial_fund", 0)) * wealth_multiplier
	var target_reached: bool = false
	if wealth_target > 0:
		for player in _players():
			if bool(player.get("alive", false)) and _player_wealth(int(player.get("id", -1))) >= wealth_target:
				target_reached = true
				break
	var deadline_reached: bool = day_limit > 0 and elapsed >= day_limit
	var calendar_limit_reached: bool = calendar_boundary and GameCalendar.is_last_supported_date(state.get("date", {}))
	if not deadline_reached and not target_reached and not calendar_limit_reached:
		return false
	var winner: int = _richest_alive_player()
	if winner < 0 and not calendar_limit_reached:
		return false
	state["winner"] = winner
	state["phase"] = "game_over"
	state["action_options"] = []
	var reason: String = "calendar_limit" if winner < 0 and calendar_limit_reached else "day_limit" if deadline_reached else "wealth_target" if target_reached else "calendar_limit"
	var game_over_event: Dictionary = {
		"winner": winner,
		"reason": reason,
		"elapsed": elapsed,
		"wealth_target": wealth_target,
		"winner_wealth": _player_wealth(winner),
	}
	if calendar_limit_reached:
		game_over_event["calendar_boundary"] = true
	_record_event("game_over", game_over_event)
	return true


func _check_game_over(reason: String = "") -> void:
	if _settling_company_dividends or state.get("phase", "") == "game_over":
		return
	var alive_ids: Array = []
	for player in _players():
		if bool(player.get("alive", false)):
			alive_ids.append(int(player.get("id", -1)))
	if alive_ids.size() <= 1:
		state["winner"] = alive_ids[0] if alive_ids.size() == 1 else -1
		state["phase"] = "game_over"
		state["action_options"] = []
		var result_event := {"winner": int(state["winner"])}
		if _is_companies() and alive_ids.is_empty() and reason == "company_dividend":
			result_event["reason"] = "company_dividend_no_survivors"
		_record_event("game_over", result_event)


func run_ai_turn() -> Dictionary:
	if state.get("phase", "") == "game_over":
		return _error("遊戲已結束")
	if not AuctionRules.response(self).is_empty():
		return AuctionRules.ai_turn(self)
	var player_id: int = int(state.get("current_player", -1))
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		if not player.is_empty():
			_advance_to_next_alive(player_id)
			if state.get("phase", "") == "game_over":
				return _result(true, "AI 對局完成")
			player_id = int(state.get("current_player", -1))
			player = _player(player_id)
		if player.is_empty() or not bool(player.get("alive", false)):
			return _error("目前玩家無法行動")
	if not bool(player.get("is_ai", false)):
		return _error("目前玩家不是 AI")
	if not _pending_finance().is_empty():
		return _result(true, "等待人類玩家回應金融付款", {"player_id": player_id, "awaiting_response": true, "completed": false})
	if _trap_pending():
		# A human defender must answer outside the AI turn loop.  The caster's
		# phase and current-player identity remain unchanged while waiting.
		var pending: Dictionary = _pending_trap()
		var pending_target: Dictionary = _player(int(pending.get("target_id", -1)))
		if bool(pending_target.get("is_human", false)) and not bool(pending_target.get("is_ai", false)):
			return _result(true, "等待人類玩家回應陷害卡", {"player_id": player_id, "awaiting_response": true, "completed": false})
		return _error("陷害卡回應狀態無效")
	if _sleep_active(player):
		return run_sleep_turn()
	var safety: int = 0
	var route_safety: int = 0
	while state.get("phase", "") != "game_over" and int(state.get("current_player", -1)) == player_id:
		# Card actions can create an auction while _ai_action is running.  Dispatch
		# the newly pending auction before the loop retries ordinary actions or
		# attempts to end the turn; the auction owns the bidder control flow until
		# it settles or reaches a human bidder.
		if not AuctionRules.response(self).is_empty():
			return AuctionRules.ai_turn(self)
		if not _pending_finance().is_empty():
			return _result(true, "等待人類玩家回應金融付款", {"player_id": player_id, "awaiting_response": true, "completed": false})
		if _trap_pending():
			var pending: Dictionary = _pending_trap()
			var pending_target: Dictionary = _player(int(pending.get("target_id", -1)))
			if bool(pending_target.get("is_human", false)) and not bool(pending_target.get("is_ai", false)):
				return _result(true, "等待人類玩家回應陷害卡", {"player_id": player_id, "awaiting_response": true, "completed": false})
			return _result(false, "陷害卡回應狀態無效", {"player_id": player_id, "completed": false})
		if state.get("phase", "") == "await_route":
			if route_safety >= MAX_GRAPH_STEPS:
				return _result(false, "AI 路線在限制內未完成", {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": false})
			var options: Array = state.get("route_options", [])
			if options.is_empty():
				return _result(false, "AI 找不到可用路線", {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": false})
			var route_result: Dictionary = choose_route(int(options[0]))
			route_safety += 1
			if not bool(route_result.get("ok", false)):
				return _result(false, str(route_result.get("message", "AI 選路失敗")), {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": false})
			continue
		if safety >= MAX_AI_TURN_ITERATIONS:
			break
		safety += 1
		if state.get("phase", "") == "await_roll":
			if _is_inventory():
				_ai_roll_action(player_id)
			# Immediate card effects can end the match or hand off this turn.
			# Let the loop dispatch the resulting state before attempting a roll.
			if state.get("phase", "") != "await_roll" or int(state.get("current_player", -1)) != player_id:
				continue
			if _trap_pending():
				continue
			var roll_result: Dictionary = roll()
			if not bool(roll_result.get("ok", false)):
				return _result(false, str(roll_result.get("message", "AI 擲骰失敗")), {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": false})
		elif state.get("phase", "") == "await_action":
			if not bool(_player(player_id).get("alive", false)):
				_advance_to_next_alive(player_id)
				break
			_ai_action(player_id)
		else:
			break
	if not _pending_finance().is_empty():
		return _result(true, "等待人類玩家回應金融付款", {"player_id": player_id, "awaiting_response": true, "completed": false})
	if state.get("phase", "") == "await_action" and int(state.get("current_player", -1)) == player_id:
		var end_result: Dictionary = end_turn()
		if not bool(end_result.get("ok", false)):
			return _result(false, str(end_result.get("message", "AI 結束回合失敗")), {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": false})
	var completed: bool = state.get("phase", "") == "game_over" or int(state.get("current_player", -1)) != player_id
	if not completed:
		return _result(false, "AI 回合在限制內未完成", {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": false})
	return _result(true, "AI 回合完成", {"player_id": player_id, "iterations": safety, "route_iterations": route_safety, "completed": true})


func _ai_theft_action(player_id: int) -> bool:
	if not _is_inventory():
		return false
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return false
	var cards_value: Variant = player.get("cards", null)
	if not cards_value is Array or not cards_value.has("搶奪"):
		return false
	var choices: Array = TheftRules.choices(_players(), player_id)
	if choices.is_empty():
		return false
	# Reuse the status target policy where available.  The theft selector itself
	# remains broader for humans, while AI only considers the same living,
	# non-detained target set used by the existing trap evaluator.
	var nearby_targets: Array = []
	var enforce_nearby_policy: bool = _is_statuses()
	if enforce_nearby_policy:
		nearby_targets = trap_target_players(player_id)
	var selected: Dictionary = {}
	var selected_price: int = -1
	for choice_value in choices:
		if not choice_value is Dictionary:
			continue
		var choice: Dictionary = choice_value
		var target_id: int = int(choice.get("target_id", -1))
		if enforce_nearby_policy and not nearby_targets.has(target_id):
			continue
		var item_kind: String = str(choice.get("item_kind", ""))
		# A card hand can evict its cheapest entry, but a full tool type cannot
		# receive another unit and is therefore skipped by the AI.
		if item_kind == "tool" and bool(choice.get("capacity_full", false)):
			continue
		var record: Dictionary = _inventory_record(item_kind, str(choice.get("item_id", "")))
		if record.is_empty():
			continue
		var price: int = int(record.get("price", -1))
		# Strictly greater preserves the deterministic first-choice tie break.
		if price > selected_price:
			selected_price = price
			selected = choice
	if selected.is_empty():
		return false
	var theft_params: Dictionary = {
		"card_id": "搶奪",
		"target_id": int(selected.get("target_id", -1)),
		"item_kind": str(selected.get("item_kind", "")),
		"item_id": str(selected.get("item_id", "")),
	}
	var result: Dictionary = choose_action("use_card", theft_params)
	return bool(result.get("ok", false))


func _ai_action(player_id: int) -> void:
	var player: Dictionary = _player(player_id)
	if _trap_pending():
		return
	# Status turns have no property/company action.  Ending the turn here keeps
	# AI behaviour aligned with the status action gate and avoids retrying a
	# stock/card fallback until the safety limit is reached.
	if _status_active(player):
		end_turn()
		return
	if _is_companies() and int(state.get("company_service_pending",0))>0:
		var targets := _company_payable_upgrade_targets(player_id, get_company_at(int(player.get("position", -1))))
		var selected := -1
		var highest_value := -1
		for target in targets:
			var target_tile := _tile_at(int(target))
			var target_value := inventory_purchase_price(target_tile)
			if target_value>highest_value:
				highest_value=target_value
				selected=int(target)
		if selected>=0:
			choose_action("company_upgrade",{"tile_id":selected,"facility_type":1})
			return
	if _ai_god_card_action(player_id):
		return
	if _ai_remodel_action(player_id):
		return
	if _ai_property_card_action(player_id):
		return
	if _ai_building_card_action(player_id):
		return
	if _ai_theft_action(player_id):
		return
	var tile: Dictionary = _tile_at(int(player.get("position", 0)))
	if tile.get("kind", "") == "property":
		var owner: int = int(tile.get("owner", -1))
		if owner == -1 and not bool(state.get("property_action_used", false)) and int(player.get("cash", 0)) >= _property_buy_price(tile):
			var buy_result: Dictionary = choose_action("buy")
			if bool(buy_result.get("ok", false)):
				return
		var property_cap: int = _property_level_cap(tile, _is_remodel())
		if owner == player_id and not bool(state.get("property_action_used", false)) and int(tile.get("building_level", 0)) < property_cap and int(player.get("cash", 0)) >= _upgrade_price(tile) + 500:
			var upgrade_result: Dictionary = choose_action("upgrade")
			if bool(upgrade_result.get("ok", false)):
				return
	if _is_facilities() and _is_graph() and tile.get("kind", "") == "facility":
		var facility: Dictionary = _facility_record(int(player.get("position", -1)))
		var facility_owner: int = int(facility.get("owner", -1))
		var facility_price: int = _facility_land_price(facility)
		if facility_owner == -1 and not bool(state.get("property_action_used", false)) and int(player.get("cash", 0)) >= facility_price:
			var facility_buy_result: Dictionary = choose_action("buy")
			if bool(facility_buy_result.get("ok", false)):
				return
		elif facility_owner == player_id and not bool(state.get("property_action_used", false)):
			var facility_level: int = int(facility.get("building_level", 0))
			var facility_type: int = int(facility.get("facility_type", -1))
			if facility_level == 0 and int(player.get("cash", 0)) >= facility_price:
				# Source records use type zero for an unbuilt site. Pick the first
				# operational upgradeable type so the next visit has a legal upgrade.
				var build_type: int = facility_type
				if build_type <= 0 or build_type > FACILITY_LAB_TYPE or (build_type == FACILITY_LAB_TYPE and not _is_research()):
					build_type = 1
				var facility_build_result: Dictionary = choose_action("build_facility", {"facility_type": build_type})
				if bool(facility_build_result.get("ok", false)):
					return
			elif _facility_type_valid(facility_type) and (facility_type != FACILITY_LAB_TYPE or _is_research()) and facility_level < _facility_type_cap(facility_type):
				var facility_upgrade_price: int = _facility_upgrade_price(facility)
				if int(player.get("cash", 0)) >= facility_upgrade_price:
					var facility_upgrade_result: Dictionary = choose_action("upgrade")
					if bool(facility_upgrade_result.get("ok", false)):
						return
	if _is_research() and tile.get("kind", "") == "facility" and not bool(state.get("research_action_used", false)):
		var research_facility: Dictionary = _facility_record(int(player.get("position", -1)))
		if int(research_facility.get("owner", -1)) == player_id and int(research_facility.get("facility_type", -1)) == FACILITY_LAB_TYPE and int(research_facility.get("building_level", 0)) > 0 and not _facility_is_sealed(research_facility):
			var highest_rank: int = mini(int(research_facility.get("building_level", 0)), RESEARCH_TOOL_MAX_RANK)
			if highest_rank > 0:
				var research_result: Dictionary = choose_action("choose_research", {"tool_id": RESEARCH_TOOL_IDS[highest_rank - 1]})
				if bool(research_result.get("ok", false)):
					return
	if _is_companies() and not _is_gods_hospital_action(player):
		var company := get_company_at(int(player.get("position", -1)))
		if not company.is_empty():
			var face_price := int(company.stock_value) / 10000
			if face_price > 0:
				var quantity := mini(int(company.treasury), mini(int(state.company_purchase_remaining), maxi(0, int(player.cash)-5000) / face_price))
				if quantity > 0 and choose_action("buy_company", {"quantity":quantity}).get("ok", false): return
	if bool(state.get("bank_access", false)) and not _is_sunday() and int(player.get("cash", 0)) > 5000:
		var deposit_amount := mini(int(player.get("cash", 0)) / 4, bank_transfer_limit("deposit", player_id))
		if deposit_amount > 0 and bool(choose_action("deposit", {"amount": deposit_amount}).get("ok", false)):
			return
	if not _is_sunday() and int(player.get("deposit" if _is_companies() else "cash", 0)) >= 3000:
		var prices: Dictionary = state.get("market", {}).get("prices", {})
		var symbol: String = get_stock_symbols()[player_id % get_stock_symbols().size()]
		var price: int = int(prices.get(symbol, 100))
		if price > 0:
			var stock_result: Dictionary = choose_action("buy_stock", {"symbol": symbol, "quantity": 1})
			if not _is_companies() or bool(stock_result.get("ok", false)):
				return
	if player.get("cards", []).size() > 0:
		if _is_inventory():
			for card_value in player["cards"]:
				var card_id: String = str(card_value)
				if GOD_CARD_IDS.has(card_id):
					continue
				if not item_is_implemented("card", card_id):
					continue
				var inventory_card_params: Dictionary = {"card_id": card_id}
				if BUILDING_CARD_IDS.has(card_id):
					var building_target: Dictionary = _ai_building_card_target(player_id, card_id)
					if building_target.is_empty():
						continue
					inventory_card_params["tile_id"] = int(building_target.get("tile_id", -1))
					if card_id == "天使" and building_target.has("facility_type"):
						inventory_card_params["facility_type"] = int(building_target.get("facility_type", 1))
				if card_id == SleepRules.DREAM_CARD:
					var dream_target: int = SleepRules.ai_dream_target(self, player_id)
					if dream_target < 0:
						continue
					inventory_card_params["target_id"] = dream_target
				elif card_id == "查稅":
					var tax_targets: Array = tax_target_players(player_id)
					if tax_targets.is_empty():
						continue
					inventory_card_params["target_id"] = int(tax_targets[0])
				elif card_id == "免費":
					continue
				elif AllianceRules.is_alliance_card(card_id):
					var alliance_target: int = -1
					for candidate_value in alliance_target_players(player_id):
						if typeof(candidate_value) != TYPE_INT:
							continue
						var candidate_id: int = int(candidate_value)
						if not AllianceRules.are_allied(self, player_id, candidate_id):
							alliance_target = candidate_id
							break
					if alliance_target < 0:
						continue
					inventory_card_params["target_id"] = alliance_target
				if card_id == "陷害":
					var trap_target: int = _ai_trap_target(player_id)
					if trap_target < 0:
						continue
					inventory_card_params["target_id"] = trap_target
				if card_id == "停留" or card_id == "烏龜":
					inventory_card_params["target_id"] = player_id
				elif card_id == "轉向":
					inventory_card_params["target_id"] = player_id
				elif card_id == "購地":
					var purchase_owner: Variant = tile.get("owner", null)
					var purchase_kind_valid: bool = tile.get("kind", "") == "property" or (_is_gods() and tile.get("kind", "") == "facility")
					var purchase_owner_valid: bool = _valid_int(purchase_owner, -1, _players().size() - 1) and int(purchase_owner) != player_id
					if _is_gods():
						purchase_owner_valid = purchase_owner_valid and int(purchase_owner) >= 0
					var purchase_valid: bool = purchase_kind_valid and purchase_owner_valid and not _is_gods_hospital_action(player) and not bool(state.get("property_action_used", false)) and int(player.get("cash", 0)) >= inventory_purchase_price(tile)
					if not purchase_valid:
						continue
				elif card_id == "拆除":
					var demolition_target: int = _inventory_ai_demolition_target(player_id)
					if demolition_target < 0:
						continue
					inventory_card_params["tile_id"] = demolition_target
				elif card_id == REMODEL_CARD_ID:
					# The remodel helper only spends this card when the current
					# asset has a positive deterministic value delta.  Do not let the
					# generic first-card fallback toggle a useful chain store back.
					continue
				elif card_id == "均貧":
					var poor_target_id: int = -1
					for candidate in _players():
						var candidate_id: int = int(candidate.get("id", -1))
						if candidate_id != player_id and bool(candidate.get("alive", false)):
							poor_target_id = candidate_id
							break
					if poor_target_id >= 0:
						inventory_card_params["target_id"] = poor_target_id
					else:
						continue
				elif card_id == "紅" or card_id == "黑":
					inventory_card_params["symbol"] = get_stock_symbols()[player_id % get_stock_symbols().size()]
					if _is_companies() and (not bool(state.market.open) or int(state.market.rows[inventory_card_params.symbol].suspension)>0):
						continue
				var inventory_card_result: Dictionary = choose_action("use_card", inventory_card_params)
				if bool(inventory_card_result.get("ok", false)):
					return
		else:
			var card_id: String = str(player["cards"][0])
			var card_params: Dictionary = {"card_id": card_id}
			if card_id == "停留" or card_id == "烏龜":
				card_params["target_id"] = player_id
			elif card_id == "紅" or card_id == "黑":
				card_params["symbol"] = get_stock_symbols()[player_id % get_stock_symbols().size()]
			choose_action("use_card", card_params)
			return
	end_turn()


func _ai_building_card_action(player_id: int) -> bool:
	if not _is_building_cards() or not _is_inventory():
		return false
	var player: Dictionary = _player(player_id)
	var cards: Variant = player.get("cards", null)
	if typeof(cards) != TYPE_ARRAY:
		return false
	for card_value in cards:
		var card_id: String = str(card_value)
		if not BUILDING_CARD_IDS.has(card_id):
			continue
		var target: Dictionary = _ai_building_card_target(player_id, card_id)
		if target.is_empty():
			continue
		var params: Dictionary = {"card_id": card_id, "tile_id": int(target.get("tile_id", -1))}
		if card_id == "天使" and target.has("facility_type"):
			params["facility_type"] = int(target.get("facility_type", 1))
		var result: Dictionary = choose_action("use_card", params)
		if bool(result.get("ok", false)):
			return true
	return false


func _ai_building_card_target(player_id: int, card_id: String) -> Dictionary:
	if not _is_building_cards() or not BUILDING_CARD_IDS.has(card_id):
		return {}
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY:
		return {}
	var candidates: Array = []
	for tile_id in range(board.size()):
		if not _building_card_target_error(player_id, card_id, tile_id).is_empty():
			continue
		var tile: Dictionary = _tile_at(tile_id)
		if card_id in ["惡魔", "怪獸"]:
			var destructive_owner: int = int(tile.get("owner", -1))
			var destructive_level: int = int(tile.get("building_level", 0))
			if tile.get("kind", "") == "facility":
				var destructive_facility: Dictionary = _facility_record(tile_id)
				destructive_owner = int(destructive_facility.get("owner", destructive_owner))
				destructive_level = int(destructive_facility.get("building_level", destructive_level))
			if destructive_owner < 0 or destructive_owner == player_id or destructive_level <= 0:
				continue
		var own_priority: int = 0
		var score: int = 0
		if tile.get("kind", "") == "property":
			var affected: Array = _building_card_group_tiles(tile_id) if card_id in ["天使", "惡魔"] else [tile_id]
			var collateral: bool = false
			var own_gain: int = 0
			var enemy_gain: int = 0
			for affected_id in affected:
				var affected_tile: Dictionary = _tile_at(int(affected_id))
				var level: int = int(affected_tile.get("building_level", 0))
				var owner: int = int(affected_tile.get("owner", -1))
				if card_id == "天使":
					var cap: int = 1 if bool(affected_tile.get("is_chain_store", false)) else MAX_PROPERTY_LEVEL
					var gain: int = max(0, min(level + 1, cap) - level)
					if owner == player_id:
						own_gain += gain
					else:
						enemy_gain += gain
				elif card_id == "惡魔" and owner == player_id and level > 0:
					collateral = true
				elif card_id == "怪獸" and owner == player_id:
					collateral = true
			if card_id == "惡魔" and collateral:
				continue
			if card_id == "天使":
				if int(tile.get("owner", -1)) != player_id or own_gain <= 0:
					continue
				own_priority = 2 if int(tile.get("owner", -1)) == player_id and own_gain > 0 else 1 if own_gain > 0 else 0
				score = own_gain * 100 - enemy_gain
			else:
				score = int(tile.get("building_level", 0))
		else:
			var facility: Dictionary = _facility_record(tile_id)
			var facility_owner: int = int(facility.get("owner", -1))
			var facility_level: int = int(facility.get("building_level", 0))
			if card_id == "天使":
				var facility_type: int = int(facility.get("facility_type", 1))
				if facility_level <= 0:
					facility_type = 1
				var facility_gain: int = max(0, min(facility_level + 1, _facility_type_cap(facility_type)) - facility_level)
				if facility_owner != player_id or facility_gain <= 0:
					continue
				own_priority = 2 if facility_owner == player_id and facility_gain > 0 else 1 if facility_gain > 0 else 0
				score = facility_gain * 100
			elif card_id == "惡魔":
				if facility_owner == player_id and facility_level > 0:
					continue
				score = facility_level
			else:
				score = facility_level
		candidates.append({"tile_id": tile_id, "own_priority": own_priority, "score": score, "facility_type": 1 if int(tile.get("building_level", 0)) <= 0 else int(tile.get("facility_type", 0))})
	if candidates.is_empty():
		return {}
	# Stable tuple ordering makes strategy independent of dictionary/hash order.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("own_priority", 0)) != int(b.get("own_priority", 0)):
			return int(a.get("own_priority", 0)) > int(b.get("own_priority", 0))
		if int(a.get("score", 0)) != int(b.get("score", 0)):
			return int(a.get("score", 0)) > int(b.get("score", 0))
		return int(a.get("tile_id", -1)) < int(b.get("tile_id", -1))
	)
	return candidates[0]


func _ai_god_card_action(player_id: int) -> bool:
	if not _is_inventory() or not _is_gods() or not _is_graph():
		return false
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return false
	var cards: Variant = player.get("cards", null)
	if typeof(cards) != TYPE_ARRAY:
		return false

	var current_god_id: int = _player_god_id(player_id)
	if cards.has("送神符"):
		var should_dismiss: bool = DISMISS_GOD_IDS.has(current_god_id)
		if current_god_id == 0 and _is_hazards():
			var bomb_steps: Variant = player.get("bomb_steps", 0)
			should_dismiss = _valid_int(bomb_steps, 1, 12)
		if should_dismiss:
			var dismiss_result: Dictionary = choose_action("use_card", {"card_id": "送神符"})
			if bool(dismiss_result.get("ok", false)):
				return true

	if cards.has("請神符") and not AI_SUMMON_GOD_IDS.has(current_god_id):
		# Select the nearest eligible actor before applying the AI's beneficial-god
		# policy.  This preserves the source evaluator's nearest-object decision:
		# a nearest neutral god blocks the card even when a farther good god exists.
		var target: Dictionary = god_card_target(player_id)
		if not target.is_empty() and AI_SUMMON_GOD_IDS.has(int(target.get("id", 0))):
			var summon_result: Dictionary = choose_action("use_card", {"card_id": "請神符"})
			if bool(summon_result.get("ok", false)):
				return true
	return false


func _inventory_ai_worker_target(player_id: int) -> int:
	if not _is_inventory() or not _is_graph():
		return -1
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY:
		return -1
	var player: Dictionary = _player(player_id)
	if player.is_empty():
		return -1
	var candidates: Array = []
	for tile_id in range(board.size()):
		var tile_value: Variant = board[tile_id]
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = tile_value
		var owner_value: Variant = tile.get("owner", null)
		if tile.get("kind", "") != "property" or not _valid_int(owner_value, 0, _players().size() - 1) or int(owner_value) != player_id:
			continue
		if _inventory_target_error(player_id, "機器工人", tile_id).is_empty():
			candidates.append(tile_id)
	if candidates.is_empty():
		return -1
	var current_position: Variant = player.get("position", null)
	if _valid_int(current_position, 0, board.size() - 1) and candidates.has(int(current_position)):
		return int(current_position)
	return int(candidates[0])


func _inventory_ai_roadblock_target(player_id: int) -> int:
	if not _is_inventory() or not _is_graph():
		return -1
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY:
		return -1
	var player: Dictionary = _player(player_id)
	if player.is_empty():
		return -1
	var current_position: Variant = player.get("position", null)
	if not _valid_int(current_position, 0, board.size() - 1):
		return -1
	var current_node: int = int(current_position)
	var previous_position: Variant = player.get("previous_position", -1)
	var previous_node: int = int(previous_position) if _valid_int(previous_position, -1, board.size() - 1) else -1
	var next_nodes: Dictionary = {}
	for next_node_value in _graph_candidates(current_node, previous_node):
		if _valid_int(next_node_value, 0, board.size() - 1):
			next_nodes[int(next_node_value)] = true
	var current_tile: Dictionary = _tile_at(current_node)
	var adjacent: Variant = current_tile.get("adjacent", null)
	if typeof(adjacent) != TYPE_ARRAY:
		return -1
	var candidates: Array = []
	for neighbor in adjacent:
		if not _valid_int(neighbor, 0, board.size() - 1):
			continue
		var neighbor_id: int = int(neighbor)
		if next_nodes.has(neighbor_id) or candidates.has(neighbor_id):
			continue
		if not _inventory_target_error(player_id, "路障", neighbor_id).is_empty():
			continue
		candidates.append(neighbor_id)
	if candidates.is_empty():
		return -1
	candidates.sort()
	var opponent_adjacent: Dictionary = {}
	for candidate in _players():
		if typeof(candidate) != TYPE_DICTIONARY or int(candidate.get("id", -1)) == player_id or not _valid_bool(candidate.get("alive", null)) or not bool(candidate.get("alive", false)):
			continue
		var opponent_position: Variant = candidate.get("position", null)
		if not _valid_int(opponent_position, 0, board.size() - 1):
			continue
		var opponent_tile: Dictionary = _tile_at(int(opponent_position))
		var opponent_adjacent_nodes: Variant = opponent_tile.get("adjacent", null)
		if typeof(opponent_adjacent_nodes) != TYPE_ARRAY:
			continue
		for opponent_neighbor in opponent_adjacent_nodes:
			if _valid_int(opponent_neighbor, 0, board.size() - 1):
				opponent_adjacent[int(opponent_neighbor)] = true
	for candidate_id in candidates:
		if opponent_adjacent.has(int(candidate_id)):
			return int(candidate_id)
	return int(candidates[0])


func _inventory_ai_hazard_target(player_id: int, tool_id: String) -> int:
	if not _is_hazards() or not _is_graph() or not ["地雷", "定時炸彈"].has(tool_id):
		return -1
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY:
		return -1
	var candidates: Array = []
	for tile_id in range(board.size()):
		if _inventory_target_error(player_id, tool_id, tile_id).is_empty():
			candidates.append(tile_id)
	if candidates.is_empty():
		return -1
	# Prefer an immediately reachable free neighbour so AI placement is useful
	# while retaining canonical node ordering for replay.
	var player: Dictionary = _player(player_id)
	var current: int = int(player.get("position", -1))
	for neighbor in _graph_candidates(current, int(player.get("previous_position", -1))):
		if candidates.has(int(neighbor)):
			return int(neighbor)
	return int(candidates[0])


func _inventory_ai_missile_target(player_id: int, tool_id: String) -> int:
	if not MissileRules.is_missile(tool_id):
		return -1
	return MissileRules.ai_target(self, player_id, tool_id)


func _hazard_dynamic_object_count() -> int:
	if not _is_hazards():
		return 0
	var count: int = _ground_hazard_at(-1).size()
	var hazards: Variant = state.get("ground_hazards", {})
	if typeof(hazards) == TYPE_DICTIONARY:
		count += hazards.size()
	var roadblocks: Variant = state.get("roadblocks", {})
	if typeof(roadblocks) == TYPE_DICTIONARY:
		count += roadblocks.size()
	var gods: Variant = state.get("god_objects", [])
	if typeof(gods) == TYPE_ARRAY:
		for actor in gods:
			if typeof(actor) == TYPE_DICTIONARY and int(actor.get("owner", -1)) < 0:
				count += 1
	return count


func _inventory_ai_demolition_target(player_id: int) -> int:
	if not _is_inventory() or not _is_graph():
		return -1
	var board: Variant = state.get("board", null)
	if typeof(board) != TYPE_ARRAY:
		return -1
	for tile_id in range(board.size()):
		var tile_value: Variant = board[tile_id]
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = tile_value
		var owner_value: Variant = tile.get("owner", null)
		if tile.get("kind", "") != "property" or not _valid_int(owner_value, 0, _players().size() - 1) or int(owner_value) == player_id or int(tile.get("building_level", 0)) <= 0:
			continue
		if _inventory_target_error(player_id, "拆除", tile_id).is_empty():
			return tile_id
	var roadblocks: Variant = state.get("roadblocks", null)
	if typeof(roadblocks) != TYPE_DICTIONARY:
		return -1
	var roadblock_ids: Array = []
	for roadblock_key in roadblocks.keys():
		if typeof(roadblock_key) != TYPE_STRING or not str(roadblock_key).is_valid_int():
			continue
		var roadblock_id: int = int(roadblock_key)
		if _valid_int(roadblock_id, 0, board.size() - 1) and str(roadblock_id) == str(roadblock_key):
			var placer_value: Variant = roadblocks.get(roadblock_key, null)
			if _valid_int(placer_value, 0, _players().size() - 1) and int(placer_value) != player_id:
				roadblock_ids.append(roadblock_id)
	roadblock_ids.sort()
	for roadblock_id in roadblock_ids:
		if _inventory_target_error(player_id, "拆除", roadblock_id).is_empty():
			return roadblock_id
	return -1


func _property_card_asset_value(tile: Dictionary) -> int:
	if tile.get("kind", "") == "facility":
		return _facility_land_price(tile) + _facility_upgrade_price(tile) * int(tile.get("building_level", 0))
	return int(tile.get("cost", 0)) + int(tile.get("upgrade_cost", 0)) * int(tile.get("building_level", 0))


func _ai_property_card_delta(player_id: int, card_id: String, source_index: int, target_index: int) -> int:
	var source_tile: Dictionary = _tile_at(_property_card_canonical_tile_id(source_index))
	var target_tile: Dictionary = _tile_at(_property_card_canonical_tile_id(target_index))
	if source_tile.is_empty() or target_tile.is_empty():
		return 0
	var source_owner: int = int(source_tile.get("owner", -1))
	var target_owner: int = int(target_tile.get("owner", -1))
	var source_owned: bool = source_owner == player_id
	var target_owned: bool = target_owner == player_id
	var before: int = 0
	if source_owned:
		before += _property_card_asset_value(source_tile)
	if target_owned:
		before += _property_card_asset_value(target_tile)
	if card_id == "換地":
		var ownership_after: int = 0
		if source_owned:
			ownership_after += _property_card_asset_value(target_tile)
		if target_owned:
			ownership_after += _property_card_asset_value(source_tile)
		return ownership_after - before
	var source_after: Dictionary = source_tile.duplicate(true)
	var target_after: Dictionary = target_tile.duplicate(true)
	source_after["building_level"] = int(target_tile.get("building_level", 0))
	target_after["building_level"] = int(source_tile.get("building_level", 0))
	if source_tile.get("kind", "") == "facility":
		source_after["facility_type"] = int(target_tile.get("facility_type", 0))
		target_after["facility_type"] = int(source_tile.get("facility_type", 0))
	var after: int = 0
	if source_owned:
		after += _property_card_asset_value(source_after)
	if target_owned:
		after += _property_card_asset_value(target_after)
	return after - before


func _ai_property_card_action(player_id: int) -> bool:
	if not _is_property_cards() or not _is_inventory() or not _is_graph():
		return false
	var player: Dictionary = _player(player_id)
	var board: Variant = state.get("board", null)
	if player.is_empty() or typeof(board) != TYPE_ARRAY:
		return false
	var source_value: Variant = player.get("position", null)
	if not _valid_int(source_value, 0, board.size() - 1):
		return false
	var source_index: int = int(source_value)
	for card_value in player.get("cards", []):
		var card_id: String = str(card_value)
		if not PROPERTY_CARD_IDS.has(card_id):
			continue
		for target_index in range(board.size()):
			if not _property_card_target_error(player_id, card_id, target_index).is_empty():
				continue
			if _ai_property_card_delta(player_id, card_id, source_index, target_index) <= 0:
				continue
			var result: Dictionary = choose_action("use_card", {"card_id": card_id, "tile_id": target_index})
			if bool(result.get("ok", false)):
				return true
	return false


func _ai_remodel_action(player_id: int) -> bool:
	if not _is_remodel() or not _is_inventory() or not _is_graph():
		return false
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return false
	var cards: Variant = player.get("cards", null)
	if typeof(cards) != TYPE_ARRAY or not cards.has(REMODEL_CARD_ID):
		return false
	var board: Variant = state.get("board", null)
	var position: Variant = player.get("position", null)
	if typeof(board) != TYPE_ARRAY or not _valid_int(position, 0, board.size() - 1):
		return false
	var tile: Dictionary = _tile_at(int(position))
	if tile.is_empty() or not ["property", "facility"].has(str(tile.get("kind", ""))):
		return false
	var level: Variant = tile.get("building_level", null)
	if not _valid_int(level, 1, MAX_PROPERTY_LEVEL):
		return false
	if tile.get("kind", "") == "property":
		var chain_value: Variant = tile.get("is_chain_store", null)
		if typeof(chain_value) != TYPE_BOOL or bool(chain_value):
			return false
		# The AI only spends a remodel card when the current owner receives a
		# strictly higher deterministic rent.  The card itself remains legal on
		# another owner's property, but using it there has no immediate AI value.
		var owner_id: Variant = tile.get("owner", null)
		if not _valid_int(owner_id, 0, _players().size() - 1) or int(owner_id) != player_id:
			return false
		var normal_rent: int = _calculate_rent(tile, player_id)
		var chain_count: int = 1
		for candidate_value in board:
			if typeof(candidate_value) != TYPE_DICTIONARY:
				continue
			var candidate: Dictionary = candidate_value
			if candidate.get("kind", "") == "property" and int(candidate.get("owner", -1)) == player_id and bool(candidate.get("is_chain_store", false)) and int(candidate.get("building_level", 0)) > 0:
				chain_count += 1
		var chain_rent: int = chain_count * 2000 * _facility_price_index()
		if chain_rent <= normal_rent:
			return false
		var property_result: Dictionary = choose_action("use_card", {"card_id": REMODEL_CARD_ID})
		return bool(property_result.get("ok", false))
	# Facility types offer different services; without a measured benefit,
	# preserve the facility and card instead of cycling equal-level types.
	return false


func _ai_roll_action(player_id: int) -> void:
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("alive", false)):
		return
	# A hospital/prison roll is consumed by the status lifecycle before any
	# inventory action can be resolved.  In particular, do not leave a remote
	# dice request pending when the status branch returns early from roll().
	if _status_active(player):
		return
	# Give the status card a normal pre-roll opportunity before the repeated
	# stock-trading heuristic. Human scapegoat responses pause run_ai_turn.
	if _is_statuses() and _trap_has_card(player, "陷害"):
		var trap_target: int = _ai_trap_target(player_id)
		if trap_target >= 0 and choose_action("use_card", {"card_id": "陷害", "target_id": trap_target}).get("ok", false):
			return
	if _inventory_movement_blocked(player):
		return
	if _ai_transport_action(player_id):
		return
	if _ai_remodel_action(player_id):
		return
	if _ai_property_card_action(player_id):
		return
	if _ai_god_card_action(player_id):
		return
	if _ai_theft_action(player_id):
		return
	var tools: Dictionary = player.get("tools", {})
	var active_vehicle: String = str(player.get("vehicle", "walking"))
	var worker_target: int = _inventory_ai_worker_target(player_id)
	if worker_target >= 0:
		var worker_result: Dictionary = choose_action("use_tool", {"tool_id": "機器工人", "tile_id": worker_target})
		if bool(worker_result.get("ok", false)):
			return
	var roadblock_target: int = _inventory_ai_roadblock_target(player_id)
	if roadblock_target >= 0:
		var roadblock_result: Dictionary = choose_action("use_tool", {"tool_id": "路障", "tile_id": roadblock_target})
		if bool(roadblock_result.get("ok", false)):
			return
	if _is_hazards() and int(tools.get("機器娃娃", 0)) > 0 and _hazard_dynamic_object_count() > 0:
		var doll_result: Dictionary = choose_action("use_tool", {"tool_id": "機器娃娃"})
		if bool(doll_result.get("ok", false)):
			return
	for hazard_tool_id in ["地雷", "定時炸彈"]:
		if int(tools.get(hazard_tool_id, 0)) <= 0:
			continue
		var hazard_target: int = _inventory_ai_hazard_target(player_id, hazard_tool_id)
		if hazard_target < 0:
			continue
		var hazard_result: Dictionary = choose_action("use_tool", {"tool_id": hazard_tool_id, "tile_id": hazard_target})
		if bool(hazard_result.get("ok", false)):
			return
	for missile_tool_id in [MissileRules.MISSILE_ID, MissileRules.NUCLEAR_MISSILE_ID]:
		if int(tools.get(missile_tool_id, 0)) <= 0:
			continue
		var missile_target: int = _inventory_ai_missile_target(player_id, missile_tool_id)
		if missile_target < 0:
			continue
		var missile_result: Dictionary = choose_action("use_tool", {"tool_id": missile_tool_id, "tile_id": missile_target})
		if bool(missile_result.get("ok", false)):
			return
	for tool_id in ["汽車", "機車", "遙控骰子"]:
		if int(tools.get(tool_id, 0)) <= 0:
			continue
		if active_vehicle == EngineeringVehicle.VEHICLE_ID and tool_id in ["汽車", "機車"]:
			continue
		if tool_id == "機車" and active_vehicle == "car":
			continue
		var params: Dictionary = {"tool_id": tool_id}
		if tool_id == "遙控骰子":
			params["value"] = 1 + (player_id % 6)
		var result: Dictionary = choose_action("use_tool", params)
		if bool(result.get("ok", false)):
			return


func _ai_transport_action(player_id: int) -> bool:
	if not TimeTransportRules.is_supported(self):
		return false
	var player: Dictionary = _player(player_id)
	if player.is_empty() or not bool(player.get("is_ai", false)):
		return false
	if int(player.get("tools", {}).get(TimeTransportRules.TRANSPORTER, 0)) <= 0:
		return false
	var current_position: int = int(player.get("position", -1))
	for destination_value in transport_destinations("player", player_id):
		var destination_id: int = int(destination_value)
		if destination_id == current_position:
			continue
		var result: Dictionary = choose_action("use_tool", {
			"tool_id": TimeTransportRules.TRANSPORTER,
			"target_kind": "player",
			"target_id": player_id,
			"destination_id": destination_id,
		})
		if bool(result.get("ok", false)):
			return true
	return false


func run_ai_match(max_turns: int = 10000) -> Dictionary:
	if _trap_pending():
		return _error("請先回應陷害卡")
	if max_turns < 1:
		return _error("最大回合數無效")
	for player in _players():
		if bool(player.get("alive", false)):
			player["is_ai"] = true
			player["is_human"] = false
	var completed: int = 0
	while state.get("phase", "") != "game_over" and completed < max_turns:
		var result: Dictionary = run_ai_turn()
		if not bool(result.get("ok", false)):
			return _result(false, str(result.get("message", "AI 失敗")), {"completed_turns": completed})
		completed += 1
	if state.get("phase", "") != "game_over":
		return _result(false, "AI 對局在限制內未結束", {"completed_turns": completed})
	return _result(true, "AI 對局完成", {"completed_turns": completed, "winner": int(state.get("winner", -1))})


static func _valid_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func _validate_graph_source(source: Variant, expected_id: String = "") -> Array:
	var errors: Array = []
	if typeof(source) != TYPE_DICTIONARY:
		return ["missing map source"]
	var edition: Variant = source.get("edition", null)
	var map_number: Variant = source.get("map_number", null)
	if typeof(edition) != TYPE_STRING or not ["Game", "MultiverseJourney"].has(edition):
		errors.append("invalid map source edition")
	if not _valid_int(map_number, 1, 99):
		errors.append("invalid map source number")
	if typeof(edition) == TYPE_STRING and _valid_int(map_number, 1, 99):
		var canonical_id := "%s:%d" % [edition, int(map_number)]
		if not expected_id.is_empty() and expected_id != canonical_id:
			errors.append("map identity mismatch")
	var archive: Variant = source.get("archive", null)
	if typeof(archive) != TYPE_STRING or (typeof(edition) == TYPE_STRING and archive != "%s/map.mkf" % edition):
		errors.append("invalid map source archive")
	if not _valid_int(source.get("entry_index", null), 0, 999):
		errors.append("invalid map source entry")
	for hash_key in ["payload_sha256", "source_file_sha256"]:
		if not _valid_sha256(source.get(hash_key, null)):
			errors.append("invalid map source hash")
	return errors


static func _validate_facility_price_sources(source: Variant, board: Variant) -> Array:
	var errors: Array = []
	if typeof(board) != TYPE_ARRAY:
		return errors
	var facility_tiles: Array = []
	for tile in board:
		if typeof(tile) == TYPE_DICTIONARY and tile.get("kind", "") == "facility":
			facility_tiles.append(tile)
	if typeof(source) != TYPE_DICTIONARY:
		return errors
	if not source.has("facilities") and facility_tiles.is_empty():
		return errors
	var records: Variant = source.get("facilities", null)
	if typeof(records) != TYPE_ARRAY or records.size() > 1999:
		return ["invalid retained facility source table"]
	var prices_by_id: Dictionary = {}
	for record in records:
		if typeof(record) != TYPE_DICTIONARY or not _valid_int(record.get("id", null), 1, 1999):
			errors.append("invalid retained facility source identity")
			continue
		var source_id: int = int(record.id)
		if prices_by_id.has(source_id):
			errors.append("duplicate retained facility source identity")
			continue
		var prices: Dictionary = OriginalMaps.facility_price_table(record)
		if not bool(prices.get("ok", false)) or not _valid_int(record.get("land_price", null), 0, 1000000):
			errors.append("invalid retained facility source prices")
			continue
		prices_by_id[source_id] = {"land_price": int(record.land_price), "upgrade_cost": prices.upgrade_cost, "fee_by_level": prices.fee_by_level}
	for tile in facility_tiles:
		var source_id: Variant = tile.get("source_object_id", null)
		if not _valid_int(source_id, 1, 1999) or not prices_by_id.has(int(source_id)):
			errors.append("facility has no retained source prices")
			continue
		var expected: Dictionary = prices_by_id[int(source_id)]
		var land_price_value: Variant = tile.get("land_price", null)
		var land_price_matches_source: bool = _valid_int(land_price_value, int(expected.land_price), int(expected.land_price))
		if not land_price_matches_source:
			# News price effects are the one runtime mutation allowed to diverge
			# from immutable source pricing.  Require the explicit marker and a
			# source price that proves the current quote is one bounded 30% step;
			# a direct land-price edit without that provenance remains invalid.
			var override_source: Variant = tile.get("news_price_source", null)
			var override_marked: bool = tile.get("news_price_override", false) == true
			var override_valid: bool = override_marked and _valid_int(override_source, 0, 1000000)
			if override_valid:
				var source_price: int = int(override_source)
				var raised_price: int = NewsEvents.adjusted_land_price(source_price, true)
				var lowered_price: int = NewsEvents.adjusted_land_price(source_price, false)
				override_valid = _valid_int(land_price_value, 0, 1000000) and int(land_price_value) in [raised_price, lowered_price]
			if not override_valid:
				errors.append("facility source price mismatch: land_price")
		if not _valid_int(tile.get("cost", null), land_price_value if _valid_int(land_price_value, 0, 1000000) else 0, land_price_value if _valid_int(land_price_value, 0, 1000000) else 0):
			errors.append("facility source price mismatch: cost")
		if not _valid_int(tile.get("upgrade_cost", null), int(expected.upgrade_cost), int(expected.upgrade_cost)):
			errors.append("facility source price mismatch: upgrade_cost")
		var actual_fees: Variant = tile.get("fee_by_level", null)
		if typeof(actual_fees) != TYPE_ARRAY or actual_fees.size() != 6:
			errors.append("facility source fee table mismatch")
		else:
			for index in range(6):
				if not _valid_int(actual_fees[index], int(expected.fee_by_level[index]), int(expected.fee_by_level[index])):
					errors.append("facility source fee mismatch")
	return errors


static func validate_board_definition(definition: Dictionary, original_facilities: bool = false) -> Dictionary:
	var errors: Array = []
	if typeof(definition) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["map definition must be a dictionary"]}
	var definition_facilities: bool = false
	if definition.has("original_facilities"):
		if typeof(definition.get("original_facilities")) != TYPE_BOOL:
			errors.append("invalid original facilities marker")
		else:
			definition_facilities = bool(definition.get("original_facilities"))
	if definition.has("supports_original_statuses"):
		if typeof(definition.get("supports_original_statuses")) != TYPE_BOOL:
			errors.append("invalid original statuses capability")
		elif definition.get("supports_original_statuses", false):
			for status_kind in ["hospital", "prison"]:
				if _status_node_index_in_board(definition.get("board", null), status_kind) < 0:
					errors.append("status-capable map lacks " + status_kind)
	var facility_mode: bool = original_facilities or definition_facilities
	var research_capability: bool = false
	if definition.has("supports_original_research"):
		if typeof(definition.get("supports_original_research")) != TYPE_BOOL:
			errors.append("invalid original research capability")
		else:
			research_capability = bool(definition.get("supports_original_research", false))
	var property_cards_capability: bool = false
	if definition.has("supports_original_property_cards"):
		if typeof(definition.get("supports_original_property_cards")) != TYPE_BOOL:
			errors.append("invalid original property cards capability")
		else:
			property_cards_capability = bool(definition.get("supports_original_property_cards", false))
			if property_cards_capability and (not facility_mode or typeof(definition.get("supports_original_statuses")) != TYPE_BOOL or not bool(definition.get("supports_original_statuses", false))):
				errors.append("property-card capability requires complete original map support")
	var remodel_capability: bool = false
	if definition.has("supports_original_remodel"):
		if typeof(definition.get("supports_original_remodel")) != TYPE_BOOL:
			errors.append("invalid original remodel capability")
		else:
			remodel_capability = bool(definition.get("supports_original_remodel", false))
			if remodel_capability and (not facility_mode or not property_cards_capability or typeof(definition.get("supports_original_statuses")) != TYPE_BOOL or not bool(definition.get("supports_original_statuses", false))):
				errors.append("remodel capability requires complete property-card map support")
	var building_cards_capability: bool = false
	if definition.has("supports_original_building_cards"):
		if typeof(definition.get("supports_original_building_cards")) != TYPE_BOOL:
			errors.append("invalid original building cards capability")
		else:
			building_cards_capability = bool(definition.get("supports_original_building_cards", false))
			if building_cards_capability and (not research_capability or typeof(definition.get("supports_original_research")) != TYPE_BOOL or not bool(definition.get("supports_original_research", false))):
				errors.append("building cards capability requires complete research map support")
	if research_capability:
		for prerequisite in ["supports_original_statuses", "supports_original_hazards", "supports_original_property_cards", "supports_original_remodel"]:
			if typeof(definition.get(prerequisite, null)) != TYPE_BOOL or not bool(definition.get(prerequisite, false)):
				errors.append("research capability requires " + prerequisite)
		if not facility_mode:
			errors.append("research capability requires original facilities")
	if definition.get("schema", "") != RUNTIME_MAP_SCHEMA:
		errors.append("unsupported map schema")
	if not _valid_int(definition.get("version", null), 1, 1):
		errors.append("unsupported map version")
	var map_id: Variant = definition.get("id", null)
	if typeof(map_id) != TYPE_STRING or str(map_id).is_empty():
		errors.append("invalid map id")
	var map_name: Variant = definition.get("name", null)
	if typeof(map_name) != TYPE_STRING or str(map_name).is_empty():
		errors.append("invalid map name")
	var source_errors: Array = _validate_graph_source(definition.get("source", null), str(map_id) if typeof(map_id) == TYPE_STRING else "")
	errors.append_array(source_errors)
	if typeof(definition.get("supports_new_game", null)) != TYPE_BOOL or not bool(definition.get("supports_new_game", false)):
		errors.append("map does not support new games")
	var board: Variant = definition.get("board", null)
	if typeof(board) != TYPE_ARRAY or board.size() < 2 or board.size() > 4096:
		errors.append("invalid graph board")
	var board_array: Array = board if typeof(board) == TYPE_ARRAY else []
	var property_count := 0
	var facility_count := 0
	var source_properties: Dictionary = {}
	var source_facilities: Dictionary = {}
	for index in range(board_array.size()):
		var tile_value: Variant = board_array[index]
		if typeof(tile_value) != TYPE_DICTIONARY:
			errors.append("invalid graph tile %d" % index)
			continue
		var tile: Dictionary = tile_value
		if not _valid_int(tile.get("index", null), index, index):
			errors.append("graph tile index mismatch %d" % index)
		if not _valid_int(tile.get("source_node_id", null), index + 1, index + 1):
			errors.append("graph source node mismatch %d" % index)
		for coordinate in ["x", "y"]:
			if not _valid_int(tile.get(coordinate, null), -1000000, 1000000):
				errors.append("invalid graph tile coordinate %d" % index)
		var kind: Variant = tile.get("kind", null)
		if _valid_int(tile.get("type_and_idx", null), 2001, 3999) and (typeof(kind) != TYPE_STRING or kind != "property"):
			errors.append("housing source must remain a property %d" % index)
		var graph_kinds: Array = ["start", "rest", "property", "points", "card", "bank", "unsupported", "stock", "tax", "event", "news", "fate"]
		if facility_mode:
			graph_kinds.append("facility")
		if typeof(kind) != TYPE_STRING or not graph_kinds.has(kind):
			errors.append("invalid graph tile kind %d" % index)
		if not tile.get("adjacent") is Array or tile.adjacent.size() > 4:
			errors.append("invalid graph adjacency %d" % index)
		else:
			var adjacent: Array = []
			for neighbor in tile.adjacent:
				if not _valid_int(neighbor, 0, max(0, board_array.size() - 1)) or int(neighbor) == index or adjacent.has(int(neighbor)):
					errors.append("invalid graph edge %d" % index)
				else:
					adjacent.append(int(neighbor))
					var reverse_tile: Variant = board_array[int(neighbor)]
					var reverse_has := false
					if typeof(reverse_tile) == TYPE_DICTIONARY:
						var reverse_edges: Variant = reverse_tile.get("adjacent", null)
						if typeof(reverse_edges) == TYPE_ARRAY:
							for reverse_neighbor in reverse_edges:
								if _valid_int(reverse_neighbor) and int(reverse_neighbor) == index:
									reverse_has = true
									break
					if not reverse_has:
						errors.append("asymmetric graph edge %d" % index)
		for text_key in ["name", "group"]:
			if not _valid_string(tile.get(text_key, null)):
				errors.append("invalid graph tile text %d" % index)
		if not _valid_int(tile.get("owner", null), -1, -1):
			errors.append("graph definition has owned tile %d" % index)
		if not _valid_int(tile.get("building_level", null), 0, 0):
			errors.append("graph definition must start at level zero %d" % index)
		for numeric_key in ["building_level", "cost", "upgrade_cost", "base_rent", "rent", "tax_amount"]:
			if not _valid_int(tile.get(numeric_key, null), 0, 1000000000):
				errors.append("invalid graph tile value %d" % index)
		if typeof(kind) == TYPE_STRING and kind == "property":
			property_count += 1
			if remodel_capability:
				var chain_store_value: Variant = tile.get("is_chain_store", null)
				if typeof(chain_store_value) != TYPE_BOOL:
					errors.append("invalid graph property chain flag %d" % index)
				elif bool(chain_store_value) and _valid_int(tile.get("building_level", null), 0, MAX_PROPERTY_LEVEL) and int(tile.get("building_level")) != 1:
					errors.append("graph chain property must be level one %d" % index)
			var source_object_id: Variant = tile.get("source_object_id", null)
			if not _valid_int(source_object_id, 1, 1999):
				errors.append("invalid graph property identity %d" % index)
			elif source_properties.has(int(source_object_id)):
				errors.append("duplicate graph property identity %d" % index)
			else:
				source_properties[int(source_object_id)] = true
			var land_price: Variant = tile.get("land_price", null)
			var house_price: Variant = tile.get("house_price", null)
			if not _valid_int(land_price, 0, 1000000) or not _valid_int(house_price, 0, 1000000):
				errors.append("invalid graph property prices %d" % index)
			var property_type: Variant = tile.get("type_and_idx", null)
			if not _valid_int(property_type, 2001, 3999):
				errors.append("invalid graph property source type %d" % index)
			elif _valid_int(source_object_id, 1, 1999) and int(property_type) - 2000 != int(source_object_id):
				errors.append("graph property source mismatch %d" % index)
			if _valid_int(land_price, 0, 1000000) and _valid_int(tile.get("cost", null), 0, 1000000000) and int(tile.cost) != int(land_price):
				errors.append("graph property cost mismatch %d" % index)
			if _valid_int(house_price, 0, 1000000) and _valid_int(tile.get("upgrade_cost", null), 0, 1000000000) and int(tile.upgrade_cost) != int(house_price):
				errors.append("graph property upgrade price mismatch %d" % index)
			var rents: Variant = tile.get("rent_by_level", null)
			if typeof(rents) != TYPE_ARRAY or rents.size() != 6:
				errors.append("invalid graph rent table %d" % index)
			else:
				for rent in rents:
					if not _valid_int(rent, 0, 1000000):
						errors.append("invalid graph rent value %d" % index)
				var base_rent: Variant = tile.get("base_rent", null)
				var rent: Variant = tile.get("rent", null)
				if _valid_int(base_rent, 0, 1000000000) and _valid_int(rents[0], 0, 1000000) and int(base_rent) != int(rents[0]):
					errors.append("graph base rent mismatch %d" % index)
				if _valid_int(rent, 0, 1000000000) and _valid_int(rents[0], 0, 1000000) and int(rent) != int(rents[0]):
					errors.append("graph rent mismatch %d" % index)
		elif typeof(kind) == TYPE_STRING and kind == "facility":
			facility_count += 1
			var facility_source_object_id: Variant = tile.get("source_object_id", null)
			if not _valid_int(facility_source_object_id, 1, 1999):
				errors.append("invalid graph facility identity %d" % index)
			var facility_type_value: Variant = tile.get("facility_type", null)
			if not _valid_int(facility_type_value, 0, FACILITY_TYPE_COUNT - 1):
				errors.append("invalid graph facility type %d" % index)
			if research_capability:
				var research_tool_value: Variant = tile.get("research_tool", null)
				var research_turns_value: Variant = tile.get("research_turns", null)
				if not _valid_int(research_tool_value, 0, RESEARCH_TOOL_MAX_RANK) or int(research_tool_value) != 0:
					errors.append("graph definition must start with clear research product %d" % index)
				if not _valid_int(research_turns_value, 0, RESEARCH_JOB_TURNS) or int(research_turns_value) != 0:
					errors.append("graph definition must start with clear research countdown %d" % index)
			var facility_state_value: Variant = tile.get("facility_state", null)
			if not _facility_state_valid(facility_state_value) or int(facility_state_value) != 0:
				errors.append("graph definition must start with clear facility state %d" % index)
			var facility_node_index: Variant = tile.get("facility_node_index", null)
			if not _valid_int(facility_node_index, 0, max(0, board_array.size() - 1)):
				errors.append("invalid graph facility canonical node %d" % index)
			var facility_land_price: Variant = tile.get("land_price", null)
			var facility_upgrade_cost: Variant = tile.get("upgrade_cost", null)
			if not _valid_int(facility_land_price, 0, 1000000) or not _valid_int(facility_upgrade_cost, 0, 1000000):
				errors.append("invalid graph facility prices %d" % index)
			if _valid_int(facility_land_price, 0, 1000000) and _valid_int(tile.get("cost", null), 0, 1000000000) and int(tile.get("cost")) != int(facility_land_price):
				errors.append("graph facility cost mismatch %d" % index)
			var facility_fees: Variant = tile.get("fee_by_level", null)
			if typeof(facility_fees) != TYPE_ARRAY or facility_fees.size() != 6:
				errors.append("invalid graph facility fee table %d" % index)
			else:
				for fee in facility_fees:
					if not _valid_int(fee, 0, 1000000):
						errors.append("invalid graph facility fee value %d" % index)
			if _valid_int(facility_source_object_id, 1, 1999):
				if source_facilities.has(int(facility_source_object_id)):
					var first_facility: Dictionary = source_facilities[int(facility_source_object_id)]
					if _valid_int(facility_node_index, 0, max(0, board_array.size() - 1)) and int(facility_node_index) != int(first_facility.get("facility_node_index", -1)):
						errors.append("graph facility canonical node mismatch %d" % index)
					for immutable_key in ["facility_type", "cost", "land_price", "upgrade_cost", "fee_by_level"]:
						if tile.get(immutable_key, null) != first_facility.get(immutable_key, null):
							errors.append("graph facility duplicate metadata mismatch %d" % index)
				else:
					source_facilities[int(facility_source_object_id)] = tile.duplicate(true)
				if _valid_int(tile.get("type_and_idx", null), FACILITY_SOURCE_TYPE_MIN + 1, FACILITY_SOURCE_TYPE_MAX) and int(tile.get("type_and_idx")) - FACILITY_SOURCE_TYPE_MIN != int(facility_source_object_id):
					errors.append("graph facility source mismatch %d" % index)
			else:
				var owner: Variant = tile.get("owner", null)
				var building_level: Variant = tile.get("building_level", null)
				if _valid_int(owner, -1, -1) and _valid_int(building_level, 0, MAX_PROPERTY_LEVEL) and (int(owner) != -1 or int(building_level) != 0):
					errors.append("non-property graph tile state %d" % index)
		var type_value: Variant = tile.get("type_and_idx", null)
		var event_value: Variant = tile.get("event_code", null)
		if tile.has("source_status_bits") and (not _valid_int(tile.get("source_status_bits", null), 0, 0xffffffff) or (_valid_int(event_value, 0, 255) and (int(tile.get("source_status_bits")) & 0xff) != int(event_value))):
			errors.append("invalid graph source status bits %d" % index)
		if not _valid_int(type_value, 0, 65535) or not _valid_int(event_value, 0, 255):
			errors.append("invalid graph source tile status %d" % index)
		else:
			_validate_graph_source_classification(tile, index, errors, facility_mode)
	var start_position: Variant = definition.get("start_position", null)
	if not _valid_int(start_position, 0, max(0, board_array.size() - 1)):
		errors.append("invalid graph start position")
	else:
		var start_tile: Dictionary = board_array[int(start_position)] if int(start_position) < board_array.size() and typeof(board_array[int(start_position)]) == TYPE_DICTIONARY else {}
		if start_tile.is_empty() or not start_tile.get("adjacent", []) is Array or start_tile.adjacent.is_empty():
			errors.append("graph start is not movable")
	if property_count <= 0 and (not facility_mode or facility_count <= 0):
		errors.append("graph map has no playable housing or facilities")
	if property_cards_capability and property_count < 2 and source_facilities.size() < 2:
		errors.append("property-card capability requires two same-category assets")
	if errors.is_empty():
		var visited: Dictionary = {int(start_position): true}
		var queue: Array = [int(start_position)]
		while not queue.is_empty():
			var node: int = int(queue.pop_front())
			for neighbor in board_array[node].adjacent:
				var next: int = int(neighbor)
				if not visited.has(next):
					visited[next] = true
					queue.append(next)
		for index in range(board_array.size()):
			if board_array[index].get("kind", "") in ["property", "facility"] and not visited.has(index):
				errors.append("housing or facility is unreachable from graph start")
	if facility_mode:
		errors.append_array(_validate_facility_price_sources(definition.get("source", null), board_array))
	return {"ok": errors.is_empty(), "errors": errors, "definition": definition.duplicate(true)}


static func _valid_int(value: Variant, minimum: int = INT64_MIN, maximum: int = INT64_MAX) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= minimum and value <= maximum
	if typeof(value) == TYPE_FLOAT:
		var real: float = value
		return is_finite(real) and floor(real) == real and real >= float(minimum) and real <= float(maximum)
	return false


static func _valid_bool(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL


static func _valid_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING


static func _canonical_setup_date(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var date: Dictionary = value
	if date.size() != 3:
		return {}
	if not _valid_int(date.get("year", null), GameCalendar.MIN_YEAR, GameCalendar.MAX_YEAR):
		return {}
	if not _valid_int(date.get("month", null), 1, 12):
		return {}
	var year: int = int(date["year"])
	var month: int = int(date["month"])
	if not _valid_int(date.get("day", null), 1, GameCalendar.days_in_month(year, month)):
		return {}
	var canonical: Dictionary = {
		"year": year,
		"month": month,
		"day": int(date["day"]),
	}
	if not GameCalendar.is_valid(canonical):
		return {}
	return canonical


static func _valid_setup_date(value: Variant) -> bool:
	return not _canonical_setup_date(value).is_empty()


static func _expected_last_settled_month(
	start_date: Dictionary,
	current_date: Dictionary,
	elapsed: int,
	phase_name: String,
	last_event: Variant,
) -> Dictionary:
	if start_date.is_empty() or current_date.is_empty():
		return {}
	var settlement_date: Dictionary = current_date
	if phase_name == "game_over" and int(current_date.get("day", 0)) == 1 and elapsed > 0 and last_event is Dictionary:
		var reason := str(last_event.get("reason", ""))
		if reason in ["day_limit", "wealth_target"]:
			var before_boundary := GameCalendar.add_days(start_date, elapsed - 1)
			if not before_boundary.is_empty():
				settlement_date = before_boundary
	var start_month_key := int(start_date["year"]) * 12 + int(start_date["month"])
	var settlement_month_key := int(settlement_date["year"]) * 12 + int(settlement_date["month"])
	if settlement_month_key <= start_month_key:
		return {}
	var marker_year := int(settlement_date["year"])
	var marker_month := int(settlement_date["month"]) - 1
	if marker_month == 0:
		marker_year -= 1
		marker_month = 12
	var marker_month_key := marker_year * 12 + marker_month
	if marker_month_key < start_month_key:
		return {}
	return {"year": marker_year, "month": marker_month}


static func _validate_graph_source_classification(tile: Dictionary, index: int, errors: Array, facility_mode: bool = false) -> void:
	var type_value: Variant = tile.get("type_and_idx", null)
	var event_value: Variant = tile.get("event_code", null)
	if not _valid_int(type_value, 0, 65535) or not _valid_int(event_value, 0, 255):
		return
	var classification: Dictionary = OriginalMaps.classify_source_node(type_value, event_value)
	if not bool(classification.get("ok", false)):
		return
	var kind: Variant = tile.get("kind", null)
	var canonical_kind: String = str(classification.get("kind", ""))
	if facility_mode and _valid_int(type_value, FACILITY_SOURCE_TYPE_MIN + 1, FACILITY_SOURCE_TYPE_MAX):
		canonical_kind = "facility"
	# Graph definitions created before the fate dispatcher classified ordinary
	# event-3 roads as unsupported. Keep that source-shaped definition loadable;
	# from_dict() applies the structural migration before save validation.
	if canonical_kind == "fate" and typeof(kind) == TYPE_STRING and str(kind) in ["rest", "unsupported"]:
		return
	if typeof(kind) != TYPE_STRING or str(kind) != canonical_kind:
		errors.append("graph tile kind does not match source %d" % index)
	if canonical_kind == "points":
		var expected_points: int = int(classification.get("points", 0))
		if not _valid_int(tile.get("points", null), expected_points, expected_points):
			errors.append("invalid graph points value %d" % index)
	elif tile.has("points"):
		errors.append("non-points graph tile has points %d" % index)


static func validate_save(data: Dictionary) -> Dictionary:
	var errors: Array = []
	var board_mode_marker: Variant = data.get("board_mode", "")
	var version_marker: Variant = data.get("version", null)
	var building_cards_save: bool = _valid_int(version_marker, BUILDING_CARD_SAVE_VERSION, BUILDING_CARD_SAVE_VERSION)
	var research_save: bool = building_cards_save or _valid_int(version_marker, RESEARCH_SAVE_VERSION, RESEARCH_SAVE_VERSION)
	var remodel_save: bool = research_save or _valid_int(version_marker, REMODEL_SAVE_VERSION, REMODEL_SAVE_VERSION)
	var property_cards_save: bool = remodel_save or _valid_int(version_marker, PROPERTY_CARD_SAVE_VERSION, PROPERTY_CARD_SAVE_VERSION)
	var hazards_save: bool = property_cards_save or _valid_int(version_marker, HAZARD_SAVE_VERSION, HAZARD_SAVE_VERSION)
	var status_save: bool = hazards_save or _valid_int(version_marker, STATUS_SAVE_VERSION, STATUS_SAVE_VERSION)
	var companies_save: bool = status_save or _valid_int(version_marker, COMPANY_SAVE_VERSION, COMPANY_SAVE_VERSION)
	var stock_symbols: Array = OriginalStockMarket.symbols() if companies_save else STOCK_SYMBOLS
	var gods_save: bool = status_save or companies_save or _valid_int(version_marker, GODS_SAVE_VERSION, GODS_SAVE_VERSION)
	var facility_save: bool = status_save or gods_save or _valid_int(version_marker, FACILITY_SAVE_VERSION, FACILITY_SAVE_VERSION)
	var inventory_save: bool = _valid_int(version_marker, INVENTORY_SAVE_VERSION, INVENTORY_SAVE_VERSION) or facility_save
	var setup_save: bool = _valid_int(version_marker, SETUP_SAVE_VERSION, SETUP_SAVE_VERSION) or inventory_save
	var graph_save: bool = facility_save or (typeof(board_mode_marker) == TYPE_STRING and board_mode_marker == GRAPH_BOARD_MODE) or (_valid_int(version_marker) and int(version_marker) == GRAPH_SAVE_VERSION)
	var required_top: Array = [
		"version", "ruleset", "seed", "seed_text", "rng_state", "rng_state_text",
		"phase", "turn", "round", "day", "month", "day_of_month", "weekday",
		"current_player", "winner", "last_roll", "last_total", "last_event",
		"event_log", "action_options", "extra_roll", "doubles_count",
		"property_action_used", "bank_access", "bank_landing", "bank", "market",
		"board", "players", "bankruptcy_auctions",
	]
	if graph_save:
		required_top.append_array(["board_mode", "map_id", "map_name", "map_schema", "map_version", "map_source", "start_position", "route_options", "remaining_steps", "pending_movement"])
	if setup_save:
		required_top.append_array(["initial_fund", "day_limit", "wealth_multiplier", "start_date", "date", "elapsed", "last_settled_month", "character_ids"])
		if data.has("board_mode") and (typeof(board_mode_marker) != TYPE_STRING or board_mode_marker != GRAPH_BOARD_MODE):
			errors.append("invalid setup board mode")
	if inventory_save:
		required_top.append_array(["inventory_supply", "pending_remote_dice", "roadblocks"])
	if facility_save:
		required_top.append_array(["original_facilities", "price_index", "last_roll_total"])
	if gods_save:
		required_top.append_array(["original_gods", "god_objects"])
	if companies_save:
		required_top.append_array(["original_companies", "companies", "company_purchase_remaining", "jackpot", "company_months", "company_service_pending"])
	if status_save:
		required_top.append_array(["original_statuses", "pending_trap"])
	if hazards_save:
		required_top.append_array(["original_hazards", "ground_hazards"])
	if property_cards_save:
		required_top.append("original_property_cards")
	if remodel_save:
		required_top.append("original_remodel")
	if research_save:
		required_top.append_array(["original_research", "research_action_used"])
	if building_cards_save:
		required_top.append("original_building_cards")
	for key in required_top:
		if not data.has(key):
			errors.append("missing %s" % key)
	if data.has("news"):
		var news_validation: Dictionary = NewsEvents.validate_state(data.get("news", null))
		if not bool(news_validation.get("ok", false)):
			for news_error in news_validation.get("errors", []):
				errors.append(str(news_error))
	if data.has("fate"):
		var fate_validation: Dictionary = FateEvents.validate_state(data.get("fate", null))
		if not bool(fate_validation.get("ok", false)):
			for fate_error in fate_validation.get("errors", []):
				errors.append(str(fate_error))
	if data.has("stationary_turn") and typeof(data.get("stationary_turn")) != TYPE_BOOL:
		errors.append("invalid stationary turn")

	var expected_save_version: int = BUILDING_CARD_SAVE_VERSION if building_cards_save else RESEARCH_SAVE_VERSION if research_save else REMODEL_SAVE_VERSION if remodel_save else PROPERTY_CARD_SAVE_VERSION if property_cards_save else HAZARD_SAVE_VERSION if hazards_save else STATUS_SAVE_VERSION if status_save else COMPANY_SAVE_VERSION if companies_save else GODS_SAVE_VERSION if gods_save else FACILITY_SAVE_VERSION if facility_save else INVENTORY_SAVE_VERSION if inventory_save else SETUP_SAVE_VERSION if setup_save else GRAPH_SAVE_VERSION if graph_save else SAVE_VERSION
	if not _valid_int(data.get("version", null), expected_save_version, expected_save_version):
		errors.append("unsupported save version")
	if facility_save:
		if typeof(data.get("original_facilities", null)) != TYPE_BOOL or not bool(data.get("original_facilities", false)):
			errors.append("invalid original facilities marker")
		if not _valid_int(data.get("price_index", null), 1, 1000000):
			errors.append("invalid facility price index")
		if not _valid_int(data.get("last_roll_total", null), 0, MAX_GRAPH_STEPS):
			errors.append("invalid facility last roll total")
	elif data.has("original_facilities") and typeof(data.get("original_facilities")) == TYPE_BOOL and bool(data.get("original_facilities")):
		errors.append("facility marker requires v5 save")
	if gods_save:
		if typeof(data.get("original_gods", null)) != TYPE_BOOL or not bool(data.get("original_gods", false)):
			errors.append("invalid original gods marker")
		if not bool(data.get("original_facilities", false)):
			errors.append("gods marker requires facilities")
	elif data.has("original_gods") and typeof(data.get("original_gods")) == TYPE_BOOL and bool(data.get("original_gods")):
		errors.append("gods marker requires v6 save")
	if companies_save:
		if typeof(data.get("original_companies")) != TYPE_BOOL or not data.get("original_companies", false):
			errors.append("invalid original companies marker")
		if not _valid_int(data.get("company_purchase_remaining"), 0, 1000) or not _valid_int(data.get("jackpot"), 0, 1000000000000) or not _valid_int(data.get("company_months"), 0, 100000):
			errors.append("invalid company turn state")
	elif data.get("original_companies", false) == true:
		errors.append("company marker requires v7 save")
	if status_save:
		if typeof(data.get("original_statuses")) != TYPE_BOOL or not data.get("original_statuses", false):
			errors.append("invalid original statuses marker")
		if not bool(data.get("original_companies", false)) or not bool(data.get("original_gods", false)) or not bool(data.get("original_facilities", false)):
			errors.append("statuses marker requires companies, gods and facilities")
	elif data.get("original_statuses", false) == true:
		errors.append("statuses marker requires v8 save")
	if hazards_save:
		if typeof(data.get("original_hazards")) != TYPE_BOOL or not data.get("original_hazards", false):
			errors.append("invalid original hazards marker")
		if not bool(data.get("original_statuses", false)) or not bool(data.get("original_companies", false)) or not bool(data.get("original_gods", false)) or not bool(data.get("original_facilities", false)):
			errors.append("hazards marker requires statuses, companies, gods and facilities")
	elif data.get("original_hazards", false) == true:
		errors.append("hazards marker requires v9 save")
	if property_cards_save:
		if typeof(data.get("original_property_cards")) != TYPE_BOOL or not data.get("original_property_cards", false):
			errors.append("invalid original property cards marker")
		for prerequisite in ["original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards"]:
			if typeof(data.get(prerequisite)) != TYPE_BOOL or not data.get(prerequisite, false):
				errors.append("property cards marker requires " + prerequisite)
	elif data.get("original_property_cards", false) == true:
		errors.append("property cards marker requires v10 save")
	if remodel_save:
		if typeof(data.get("original_remodel")) != TYPE_BOOL or not data.get("original_remodel", false):
			errors.append("invalid original remodel marker")
		for prerequisite in ["original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards", "original_property_cards"]:
			if typeof(data.get(prerequisite)) != TYPE_BOOL or not data.get(prerequisite, false):
				errors.append("remodel marker requires " + prerequisite)
	elif data.has("original_remodel"):
		if typeof(data.get("original_remodel")) != TYPE_BOOL or bool(data.get("original_remodel", false)):
			errors.append("remodel marker requires v11 save")
	if research_save:
		if typeof(data.get("original_research")) != TYPE_BOOL or not data.get("original_research", false):
			errors.append("invalid original research marker")
		for prerequisite in ["original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards", "original_property_cards", "original_remodel"]:
			if typeof(data.get(prerequisite)) != TYPE_BOOL or not data.get(prerequisite, false):
				errors.append("research marker requires " + prerequisite)
		if typeof(data.get("research_action_used")) != TYPE_BOOL:
			errors.append("invalid research action marker")
	elif data.has("original_research"):
		errors.append("research marker requires v12 save")
	if building_cards_save:
		if typeof(data.get("original_building_cards")) != TYPE_BOOL or not data.get("original_building_cards", false):
			errors.append("invalid original building cards marker")
		for prerequisite in ["original_facilities", "original_gods", "original_companies", "original_statuses", "original_hazards", "original_property_cards", "original_remodel", "original_research"]:
			if typeof(data.get(prerequisite)) != TYPE_BOOL or not data.get(prerequisite, false):
				errors.append("building cards marker requires " + prerequisite)
	elif data.has("original_building_cards"):
		errors.append("building cards marker requires v13 save")
	if not _valid_string(data.get("ruleset", null)) or data.get("ruleset", "") != RULESET_ID:
		errors.append("unsupported ruleset")
	var seed_value: Variant = data.get("seed", null)
	var seed_valid: bool = _valid_int(seed_value, MIN_SEED, MAX_SEED)
	if not seed_valid:
		errors.append("invalid seed")
	var seed_text: Variant = data.get("seed_text", null)
	var seed_text_valid: bool = false
	if typeof(seed_text) == TYPE_STRING and seed_text.is_valid_int():
		var parsed_seed: int = int(seed_text)
		seed_text_valid = seed_valid and parsed_seed >= MIN_SEED and parsed_seed <= MAX_SEED and str(parsed_seed) == seed_text and parsed_seed == int(seed_value)
	if not seed_text_valid:
		errors.append("invalid seed text")
	var rng_value: Variant = data.get("rng_state", null)
	if typeof(rng_value) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("missing rng state")
	var rng_text: Variant = data.get("rng_state_text", null)
	if typeof(rng_text) != TYPE_STRING or not rng_text.is_valid_int():
		errors.append("invalid rng state")
	else:
		var parsed_rng: int = int(rng_text)
		if parsed_rng < INT64_MIN or parsed_rng > INT64_MAX or str(parsed_rng) != rng_text:
			errors.append("invalid rng state")

	var phase: Variant = data.get("phase", null)
	var allowed_phases: Array = ["await_roll", "await_action", "game_over"]
	if graph_save:
		allowed_phases.append("await_route")
	if typeof(phase) != TYPE_STRING or not allowed_phases.has(phase):
		errors.append("invalid phase")
	var phase_name: String = phase if typeof(phase) == TYPE_STRING else ""
	for key in ["turn", "round", "month"]:
		if not _valid_int(data.get(key, null), 1, 1000000000):
			errors.append("invalid %s" % key)
	var day_max: int = 3000001 if setup_save else 1000000000
	if not _valid_int(data.get("day", null), 1, day_max):
		errors.append("invalid day")
	var day_of_month_max: int = 31 if setup_save else DAYS_PER_MONTH
	if not _valid_int(data.get("day_of_month", null), 1, day_of_month_max):
		errors.append("invalid day_of_month")
	if not _valid_int(data.get("weekday", null), 1, 7):
		errors.append("invalid weekday")
	var day_value: Variant = data.get("day", null)
	var day_of_month_value: Variant = data.get("day_of_month", null)
	var month_value: Variant = data.get("month", null)
	var weekday_value: Variant = data.get("weekday", null)
	if setup_save:
		var start_date: Variant = data.get("start_date", null)
		var current_date: Variant = data.get("date", null)
		var canonical_start_date: Dictionary = _canonical_setup_date(start_date)
		var canonical_current_date: Dictionary = _canonical_setup_date(current_date)
		if canonical_start_date.is_empty():
			errors.append("invalid start_date")
		if canonical_current_date.is_empty():
			errors.append("invalid date")
		var elapsed_value: Variant = data.get("elapsed", null)
		if not _valid_int(elapsed_value, 0, 3000000):
			errors.append("invalid elapsed")
		var last_settled_month: Variant = data.get("last_settled_month", null)
		var last_month_valid: bool = false
		var normalized_last_month: Dictionary = {}
		if typeof(last_settled_month) == TYPE_DICTIONARY and last_settled_month.is_empty():
			last_month_valid = true
		elif typeof(last_settled_month) == TYPE_DICTIONARY and last_settled_month.size() == 2 and _valid_int(last_settled_month.get("year", null), 1998, 9999) and _valid_int(last_settled_month.get("month", null), 1, 12):
			last_month_valid = true
			normalized_last_month = {"year": int(last_settled_month.get("year")), "month": int(last_settled_month.get("month"))}
		if not last_month_valid:
			errors.append("invalid last_settled_month")
		if _valid_int(day_value, 1, day_max) and _valid_int(elapsed_value, 0, 3000000) and int(elapsed_value) != int(day_value) - 1:
			errors.append("elapsed mismatch")
		if not canonical_start_date.is_empty() and _valid_int(elapsed_value, 0, 3000000):
			var expected_date: Dictionary = GameCalendar.add_days(canonical_start_date, int(elapsed_value))
			if expected_date.is_empty() or canonical_current_date.is_empty() or canonical_current_date != expected_date:
				errors.append("date mismatch")
			elif not _valid_int(day_of_month_value, 1, 31) or int(day_of_month_value) != int(expected_date["day"]):
				errors.append("day_of_month mismatch")
			elif not _valid_int(month_value, 1, 12) or int(month_value) != int(expected_date["month"]):
				errors.append("month mismatch")
			elif not _valid_int(weekday_value, 1, 7) or int(weekday_value) != GameCalendar.weekday(expected_date):
				errors.append("weekday mismatch")
		if last_month_valid and not canonical_start_date.is_empty() and not canonical_current_date.is_empty() and _valid_int(elapsed_value, 0, 3000000):
			var expected_last_month := _expected_last_settled_month(canonical_start_date, canonical_current_date, int(elapsed_value), phase_name, data.get("last_event", null))
			if normalized_last_month != expected_last_month:
				errors.append("last_settled_month mismatch")
	else:
		if _valid_int(day_value, 1, 1000000000):
			var day_int: int = day_value
			if not _valid_int(day_of_month_value, 1, DAYS_PER_MONTH) or int(day_of_month_value) != ((day_int - 1) % DAYS_PER_MONTH) + 1:
				errors.append("day_of_month mismatch")
			if not _valid_int(month_value, 1, 1000000000) or int(month_value) != ((day_int - 1) / DAYS_PER_MONTH) + 1:
				errors.append("month mismatch")
			if not _valid_int(weekday_value, 1, 7) or int(weekday_value) != ((day_int - 1) % 7) + 1:
				errors.append("weekday mismatch")

	var players: Variant = data.get("players", null)
	var player_count: int = players.size() if typeof(players) == TYPE_ARRAY else 0
	errors.append_array(SetupControls.validate_metadata(data, player_count, setup_save))
	errors.append_array(LandTenure.validate_metadata(data, setup_save))
	if typeof(players) != TYPE_ARRAY or player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		errors.append("invalid player count")
	if data.has("news") and typeof(data.get("news", null)) == TYPE_DICTIONARY:
		var persisted_news: Dictionary = data.get("news", {})
		var persisted_last: Variant = persisted_news.get("last", {})
		if typeof(persisted_last) == TYPE_DICTIONARY and not persisted_last.is_empty() and not _valid_int(persisted_last.get("player_id", null), 0, max(0, player_count - 1)):
			errors.append("news last player is outside save")
	if data.has("fate") and typeof(data.get("fate", null)) == TYPE_DICTIONARY:
		var persisted_fate: Dictionary = data.get("fate", {})
		var persisted_fate_last: Variant = persisted_fate.get("last", {})
		if typeof(persisted_fate_last) == TYPE_DICTIONARY and not persisted_fate_last.is_empty() and not _valid_int(persisted_fate_last.get("player_id", null), 0, max(0, player_count - 1)):
			errors.append("fate last player is outside save")
	if setup_save:
		if not _valid_int(data.get("initial_fund", null)) or not SETUP_INITIAL_FUNDS.has(int(data.get("initial_fund", 0))):
			errors.append("invalid initial_fund")
		if not _valid_int(data.get("day_limit", null)) or not SETUP_DAY_LIMITS.has(int(data.get("day_limit", 0))):
			errors.append("invalid day_limit")
		if not _valid_int(data.get("wealth_multiplier", null)) or not SETUP_WEALTH_MULTIPLIERS.has(int(data.get("wealth_multiplier", 0))):
			errors.append("invalid wealth_multiplier")
		var character_ids: Variant = data.get("character_ids", null)
		if typeof(character_ids) != TYPE_ARRAY or character_ids.size() != player_count:
			errors.append("invalid character_ids")
		else:
			var seen_characters: Dictionary = {}
			for character_id in character_ids:
				if not _valid_int(character_id, 0, SETUP_CHARACTER_COUNT - 1) or seen_characters.has(int(character_id)):
					errors.append("invalid character_ids")
					continue
				seen_characters[int(character_id)] = true
	var board: Variant = data.get("board", null)
	var board_valid: bool = typeof(board) == TYPE_ARRAY
	if board_valid:
		if graph_save:
			board_valid = board.size() >= 2 and board.size() <= 4096
		else:
			board_valid = board.size() == BOARD_SIZE
	if not board_valid:
		errors.append("invalid board")
	var current_value: Variant = data.get("current_player", null)
	if not _valid_int(current_value, 0, max(0, player_count - 1)):
		errors.append("invalid current player")
	var current_player: int = current_value if _valid_int(current_value) else -1
	var winner_value: Variant = data.get("winner", null)
	if not _valid_int(winner_value, -1, max(-1, player_count - 1)):
		errors.append("invalid winner")
	var winner: int = winner_value if _valid_int(winner_value) else -1

	for key in ["extra_roll", "property_action_used", "bank_access", "bank_landing"]:
		if not _valid_bool(data.get(key, null)):
			errors.append("invalid %s" % key)
	var doubles_count_value: Variant = data.get("doubles_count", null)
	var doubles_count_valid: bool = _valid_int(doubles_count_value, 0, 3)
	if not doubles_count_valid:
		errors.append("invalid doubles_count")
	var extra_roll_value: Variant = data.get("extra_roll", null)
	if (_valid_bool(extra_roll_value) and bool(extra_roll_value)) or (doubles_count_valid and int(doubles_count_value) != 0):
		errors.append("unsupported doubles state")

	var last_roll: Variant = data.get("last_roll", null)
	var last_roll_sum: int = 0
	var last_roll_valid: bool = typeof(last_roll) == TYPE_ARRAY and last_roll.size() <= 3
	if typeof(last_roll) != TYPE_ARRAY or last_roll.size() > 3:
		errors.append("invalid last_roll")
	else:
		for face in last_roll:
			if not _valid_int(face, 1, 6):
				errors.append("invalid die face")
			else:
				last_roll_sum += int(face)
	var last_total_value: Variant = data.get("last_total", null)
	var last_total_valid: bool = _valid_int(last_total_value, 0, MAX_GRAPH_STEPS)
	if not last_total_valid:
		errors.append("invalid last_total")
	if facility_save and last_total_valid and _valid_int(data.get("last_roll_total", null), 0, MAX_GRAPH_STEPS) and int(data["last_roll_total"]) != int(last_total_value):
		errors.append("facility preserved roll total mismatch")
	if graph_save and last_roll_valid and last_total_valid:
		if last_roll.is_empty() and int(last_total_value) != 0:
			errors.append("graph last roll is missing for total")
		elif not last_roll.is_empty() and last_roll_sum != int(last_total_value):
			errors.append("graph last roll total mismatch")
	var last_event: Variant = data.get("last_event", null)
	if typeof(last_event) != TYPE_DICTIONARY:
		errors.append("invalid last_event")
	var event_log: Variant = data.get("event_log", null)
	if typeof(event_log) != TYPE_ARRAY or event_log.size() > 200:
		errors.append("invalid event_log")
	else:
		for event in event_log:
			if typeof(event) != TYPE_DICTIONARY:
				errors.append("invalid event entry")
	if inventory_save:
		var pending_remote_value: Variant = data.get("pending_remote_dice", null)
		if typeof(pending_remote_value) != TYPE_DICTIONARY:
			errors.append("invalid pending remote dice")
		else:
			var pending_remote: Dictionary = pending_remote_value
			if not pending_remote.is_empty():
				if pending_remote.size() != 2 or not pending_remote.has("player_id") or not pending_remote.has("value"):
					errors.append("pending remote dice keys are not canonical")
				var pending_remote_player: Variant = pending_remote.get("player_id", null)
				var pending_remote_face: Variant = pending_remote.get("value", null)
				if not _valid_int(pending_remote_player, 0, max(0, player_count - 1)) or int(pending_remote_player) != current_player:
					errors.append("pending remote dice player mismatch")
				if not _valid_int(pending_remote_face, 1, 6):
					errors.append("pending remote dice value invalid")
				if phase_name != "await_roll":
					errors.append("pending remote dice outside roll phase")
				if typeof(players) == TYPE_ARRAY and _valid_int(pending_remote_player, 0, max(0, player_count - 1)) and int(pending_remote_player) < players.size() and typeof(players[int(pending_remote_player)]) == TYPE_DICTIONARY:
					var pending_remote_actor: Dictionary = players[int(pending_remote_player)]
					if _inventory_movement_blocked(pending_remote_actor):
						errors.append("pending remote dice conflicts with movement modifier")
	var action_options: Variant = data.get("action_options", null)
	var known_actions: Array = ["buy", "upgrade", "deposit", "withdraw", "take_loan", "buy_vehicle", "buy_stock", "sell_stock", "use_card", "end_turn"]
	known_actions.append("respond_finance")
	known_actions.append("respond_auction")
	if status_save:
		known_actions.append("respond_trap")
	if facility_save:
		known_actions.append("build_facility")
	if research_save:
		known_actions.append("choose_research")
	if companies_save:
		known_actions.append_array(["buy_company", "company_upgrade", "repay_loan"])
	if inventory_save:
		known_actions.append_array(["buy_item", "sell_item", "use_tool"])
	if typeof(action_options) != TYPE_ARRAY:
		errors.append("invalid action_options")
	else:
		var saved_remote_pending_value: Variant = data.get("pending_remote_dice", {})
		var saved_remote_pending: bool = inventory_save and typeof(saved_remote_pending_value) == TYPE_DICTIONARY and not saved_remote_pending_value.is_empty()
		var saved_current_movement_blocked: bool = false
		if inventory_save and phase_name == "await_roll" and typeof(players) == TYPE_ARRAY and current_player >= 0 and current_player < players.size() and typeof(players[current_player]) == TYPE_DICTIONARY:
			var saved_current_actor: Dictionary = players[current_player]
			saved_current_movement_blocked = _inventory_movement_blocked(saved_current_actor)
		for option in action_options:
			if typeof(option) != TYPE_STRING or not known_actions.has(option):
				errors.append("invalid action option")
			if option == "respond_auction" and not (typeof(data.get("pending_auction", {})) == TYPE_DICTIONARY and not data.get("pending_auction", {}).is_empty()):
				errors.append("respond_auction requires pending auction")
			if inventory_save and option == "buy_vehicle":
				errors.append("inventory save cannot buy vehicle with cash")
			if inventory_save and phase_name == "await_roll" and saved_remote_pending and ["use_card", "use_tool"].has(option):
				errors.append("pending remote dice has unavailable action")
			if inventory_save and phase_name == "await_roll" and saved_current_movement_blocked and option == "use_tool":
				errors.append("movement modifier has unavailable tool action")
		var pending_trap_for_options: bool = status_save and typeof(data.get("pending_trap", {})) == TYPE_DICTIONARY and not data.get("pending_trap", {}).is_empty()
		var pending_finance_for_options: bool = typeof(data.get("pending_finance", {})) == TYPE_DICTIONARY and not data.get("pending_finance", {}).is_empty()
		var pending_auction_for_options: bool = typeof(data.get("pending_auction", {})) == TYPE_DICTIONARY and not data.get("pending_auction", {}).is_empty()
		if phase_name == "await_action" and not pending_trap_for_options and not pending_finance_for_options and not pending_auction_for_options and not action_options.has("end_turn") and not (companies_save and _valid_int(data.get("company_service_pending"),1,1999) and action_options==["company_upgrade"]):
			errors.append("await_action missing end_turn")
		if pending_trap_for_options:
			if action_options != ["respond_trap"]:
				errors.append("pending trap action options mismatch")
		elif pending_auction_for_options:
			if action_options != ["respond_auction"]:
				errors.append("pending auction action options mismatch")
		elif not pending_finance_for_options and phase_name in ["await_roll", "await_route"]:
			var non_action_phase_options: Array = ["buy_stock", "sell_stock"]
			if inventory_save and phase_name == "await_roll":
				non_action_phase_options.append_array(["use_card", "use_tool"])
			for option in action_options:
				if not non_action_phase_options.has(option):
					errors.append("await_roll has non-stock action")
		elif not pending_finance_for_options and phase_name != "await_action" and not action_options.is_empty():
			errors.append("non-action phase has action options")

	var pending_auction_errors: Array = AuctionRules.validate_save(data, player_count, board, phase_name, action_options, inventory_save)
	errors.append_array(pending_auction_errors)
	var pending_finance_errors: Array = FinancialRules.validate_pending(data, player_count, board, phase_name, action_options, inventory_save, status_save, companies_save)
	errors.append_array(pending_finance_errors)

	var bank: Variant = data.get("bank", null)
	if typeof(bank) != TYPE_DICTIONARY:
		errors.append("missing bank")
	else:
		for bank_key in ["cash", "deposits", "loans"]:
			if not _valid_int(bank.get(bank_key, null), 0, 1000000000000):
				errors.append("invalid bank %s" % bank_key)

	var market: Variant = data.get("market", null)
	if typeof(market) != TYPE_DICTIONARY:
		errors.append("missing market")
	else:
		if not _valid_bool(market.get("open", null)):
			errors.append("invalid market open")
		var prices: Variant = market.get("prices", null)
		if typeof(prices) != TYPE_DICTIONARY:
			errors.append("missing market prices")
		else:
			for symbol in stock_symbols:
				if not companies_save and not _valid_int(prices.get(symbol, null), 1, 1000000000):
					errors.append("invalid market price %s" % symbol)
		var trends: Variant = market.get("trends", null)
		if typeof(trends) != TYPE_DICTIONARY:
			errors.append("missing market trends")
		else:
			for symbol in trends.keys():
				if not stock_symbols.has(symbol) or typeof(trends[symbol]) != TYPE_DICTIONARY:
					errors.append("invalid market trend")
					continue
				var trend: Dictionary = trends[symbol]
				if not ["up", "down"].has(str(trend.get("direction", ""))) or not _valid_int(trend.get("days", null), 1, 3):
					errors.append("invalid market trend values")
				var rate_type: int = typeof(trend.get("rate", null))
				if rate_type not in [TYPE_INT, TYPE_FLOAT] or float(trend.get("rate", 0.0)) <= 0.0 or float(trend.get("rate", 0.0)) > 1.0:
					errors.append("invalid market trend rate")
		if setup_save and typeof(market.get("open", null)) == TYPE_BOOL and _valid_setup_date(data.get("date", null)):
			var expected_market_open: bool = GameCalendar.weekday(data["date"]) != 7
			if companies_save and _valid_int(market.get("closed_days"), 0, 255):
				expected_market_open = expected_market_open and int(market.closed_days) == 0
			if bool(market["open"]) != expected_market_open:
				errors.append("market open mismatch")

	var graph_reachable: Dictionary = {}
	var source_properties: Dictionary = {}
	var source_facilities: Dictionary = {}
	var property_owners: Dictionary = {}
	var facility_owners: Dictionary = {}
	var inventory_card_supply: Dictionary = {}
	var inventory_tool_supply: Dictionary = {}
	var hazard_active_tool_counts: Dictionary = {"路障": 0, "地雷": 0, "定時炸彈": 0}
	if inventory_save:
		var inventory_supply: Variant = data.get("inventory_supply", null)
		if typeof(inventory_supply) != TYPE_DICTIONARY:
			errors.append("invalid inventory supply")
		else:
			if inventory_supply.size() != 2 or not inventory_supply.has("cards") or not inventory_supply.has("tools"):
				errors.append("inventory supply keys are not canonical")
			var card_supply: Variant = inventory_supply.get("cards", null)
			if typeof(card_supply) != TYPE_DICTIONARY:
				errors.append("invalid inventory card supply")
			else:
				inventory_card_supply = card_supply
				if card_supply.size() != OriginalInventoryCatalogue.cards().size():
					errors.append("inventory card supply keys are not canonical")
				for key in card_supply.keys():
					if typeof(key) != TYPE_STRING or OriginalInventoryCatalogue.card(str(key)).is_empty():
						errors.append("invalid inventory card supply key")
				for record in OriginalInventoryCatalogue.cards():
					var card_id: String = str(record["id"])
					if not card_supply.has(card_id) or not _valid_int(card_supply.get(card_id, null), 0, 1000000000):
						errors.append("invalid inventory card supply %s" % card_id)
			var tool_supply: Variant = inventory_supply.get("tools", null)
			if typeof(tool_supply) != TYPE_DICTIONARY:
				errors.append("invalid inventory tool supply")
			else:
				inventory_tool_supply = tool_supply
				if tool_supply.size() != OriginalInventoryCatalogue.tools().size():
					errors.append("inventory tool supply keys are not canonical")
				for key in tool_supply.keys():
					if typeof(key) != TYPE_STRING or OriginalInventoryCatalogue.tool(str(key)).is_empty():
						errors.append("invalid inventory tool supply key")
				for record in OriginalInventoryCatalogue.tools():
					var tool_id: String = str(record["id"])
					if not tool_supply.has(tool_id) or not _valid_int(tool_supply.get(tool_id, null), 0, 1000000000):
						errors.append("invalid inventory tool supply %s" % tool_id)
	if typeof(board) == TYPE_ARRAY:
		for index in range(board.size()):
			if typeof(board[index]) != TYPE_DICTIONARY:
				errors.append("invalid board tile %d" % index)
				continue
			var tile: Dictionary = board[index]
			if not _valid_int(tile.get("index", null), index, index):
				errors.append("board index mismatch %d" % index)
			var allowed_board_kinds: Array = ["start", "property", "event", "tax", "bank", "stock", "rest"]
			if graph_save:
				allowed_board_kinds.append_array(["points", "card", "unsupported", "news", "fate"])
			if facility_save:
				allowed_board_kinds.append("facility")
			if not _valid_string(tile.get("kind", null)) or not allowed_board_kinds.has(tile.get("kind", "")):
				errors.append("invalid board kind %d" % index)
			if not _valid_string(tile.get("name", null)) or not _valid_string(tile.get("group", null)):
				errors.append("invalid board text %d" % index)
			var owner_value: Variant = tile.get("owner", null)
			var owner_valid: bool = _valid_int(owner_value, -1, max(-1, player_count - 1))
			if not owner_valid:
				errors.append("invalid board owner %d" % index)
			if not _valid_int(tile.get("building_level", null), 0, MAX_PROPERTY_LEVEL):
				errors.append("invalid board level %d" % index)
			if remodel_save and tile.get("kind", "") == "property":
				var chain_store_value: Variant = tile.get("is_chain_store", null)
				if typeof(chain_store_value) != TYPE_BOOL:
					errors.append("invalid board property chain flag %d" % index)
				elif bool(chain_store_value) and _valid_int(tile.get("building_level", null), 0, MAX_PROPERTY_LEVEL) and int(tile.get("building_level")) != 1:
					errors.append("board chain property must be level one %d" % index)
			for money_key in ["cost", "upgrade_cost", "base_rent", "rent", "tax_amount"]:
				if not _valid_int(tile.get(money_key, null), 0, 1000000000):
					errors.append("invalid board %s %d" % [money_key, index])
			if graph_save and not gods_save and not LandTenure.enabled(data) and owner_valid and int(owner_value) == -1 and _valid_int(tile.get("building_level", null), 1, MAX_PROPERTY_LEVEL):
				errors.append("unowned graph property has improvements %d" % index)
			if owner_valid and tile.get("kind", "") not in ["property", "facility"] and int(owner_value) != -1:
				errors.append("non-property has owner %d" % index)
			if owner_valid and tile.get("kind", "") == "property" and int(owner_value) >= 0:
				property_owners[index] = int(owner_value)
			if facility_save and tile.get("kind", "") == "facility":
				var facility_source_id: Variant = tile.get("source_object_id", null)
				var facility_source_valid: bool = _valid_int(facility_source_id, 1, 1999)
				if not facility_source_valid:
					errors.append("invalid board facility identity %d" % index)
				else:
					var facility_state_value: Variant = tile.get("facility_state", null)
					if not _facility_state_valid(facility_state_value):
						errors.append("invalid board facility state %d" % index)
					var facility_type_value: Variant = tile.get("facility_type", null)
					if not _facility_type_valid(facility_type_value):
						errors.append("invalid board facility type %d" % index)
					var facility_level_value: Variant = tile.get("building_level", null)
					var facility_level_valid: bool = _valid_int(facility_level_value, 0, MAX_PROPERTY_LEVEL)
					if facility_level_valid and _valid_int(facility_type_value, 0, FACILITY_TYPE_COUNT - 1) and int(facility_level_value) > _facility_type_cap(int(facility_type_value)):
						errors.append("board facility level exceeds type cap %d" % index)
					if facility_level_valid and _valid_int(facility_type_value, FACILITY_LAB_TYPE, FACILITY_LAB_TYPE) and int(facility_level_value) > 0 and not research_save:
						errors.append("research facility runtime is unavailable %d" % index)
					if research_save:
						var research_tool_value: Variant = tile.get("research_tool", null)
						var research_turns_value: Variant = tile.get("research_turns", null)
						var research_tool_valid: bool = _valid_int(research_tool_value, 0, RESEARCH_TOOL_MAX_RANK)
						var research_turns_valid: bool = _valid_int(research_turns_value, 0, RESEARCH_JOB_TURNS)
						if not research_tool_valid:
							errors.append("invalid board research tool %d" % index)
						if not research_turns_valid:
							errors.append("invalid board research countdown %d" % index)
						if research_tool_valid and research_turns_valid and int(research_turns_value) > 0 and int(research_tool_value) <= 0:
							errors.append("research countdown requires product %d" % index)
					var facility_node_value: Variant = tile.get("facility_node_index", null)
					if not _valid_int(facility_node_value, 0, max(0, board.size() - 1)):
						errors.append("invalid board facility canonical node %d" % index)
					elif typeof(board[int(facility_node_value)]) != TYPE_DICTIONARY or board[int(facility_node_value)].get("kind", "") != "facility" or int(board[int(facility_node_value)].get("source_object_id", -1)) != int(facility_source_id):
						errors.append("board facility canonical node mismatch %d" % index)
					var facility_fees_value: Variant = tile.get("fee_by_level", null)
					var facility_land_price_value: Variant = tile.get("land_price", null)
					var facility_upgrade_price_value: Variant = tile.get("upgrade_cost", null)
					var facility_land_price_valid: bool = _valid_int(facility_land_price_value, 0, 1000000)
					var facility_upgrade_price_valid: bool = _valid_int(facility_upgrade_price_value, 0, 1000000)
					if not facility_land_price_valid or not facility_upgrade_price_valid or typeof(facility_fees_value) != TYPE_ARRAY or facility_fees_value.size() != 6:
						errors.append("invalid board facility pricing %d" % index)
					else:
						for facility_fee_value in facility_fees_value:
							if not _valid_int(facility_fee_value, 0, 1000000):
								errors.append("invalid board facility fee %d" % index)
					if facility_land_price_valid and _valid_int(tile.get("cost", null), 0, 1000000000) and int(tile.get("cost")) != int(facility_land_price_value):
						errors.append("board facility cost mismatch %d" % index)
					var facility_source_type_value: Variant = tile.get("type_and_idx", null)
					if not _valid_int(facility_source_type_value, FACILITY_SOURCE_TYPE_MIN + 1, FACILITY_SOURCE_TYPE_MAX) or int(facility_source_type_value) - FACILITY_SOURCE_TYPE_MIN != int(facility_source_id):
						errors.append("board facility source mismatch %d" % index)
					if source_facilities.has(int(facility_source_id)):
						var first_facility: Dictionary = source_facilities[int(facility_source_id)]
						var facility_keys: Array = ["facility_type", "facility_node_index", "owner", "building_level", "facility_state", "cost", "land_price", "upgrade_cost", "fee_by_level"]
						if research_save:
							facility_keys.append_array(["research_tool", "research_turns"])
						if LandTenure.enabled(data):
							facility_keys.append("land_expiry")
						for facility_key in facility_keys:
							var tile_field: Variant = _canonicalize_json_numbers(tile.get(facility_key, null))
							var first_field: Variant = _canonicalize_json_numbers(first_facility.get(facility_key, null))
							if typeof(tile_field) != typeof(first_field) or tile_field != first_field:
								errors.append("board facility duplicate mismatch %d" % index)
								break
					else:
						source_facilities[int(facility_source_id)] = tile.duplicate(true)
					if owner_valid and int(owner_value) >= 0:
						facility_owners[int(facility_source_id)] = int(owner_value)

	if graph_save:
		var board_mode_value: Variant = data.get("board_mode", null)
		if typeof(board_mode_value) != TYPE_STRING or board_mode_value != GRAPH_BOARD_MODE:
			errors.append("invalid graph board mode")
		var map_id_value: Variant = data.get("map_id", null)
		if not _valid_string(map_id_value) or str(map_id_value).is_empty():
			errors.append("invalid graph map id")
		var graph_map_id: String = str(map_id_value) if _valid_string(map_id_value) else ""
		var map_name_value: Variant = data.get("map_name", null)
		if not _valid_string(map_name_value) or str(map_name_value).is_empty():
			errors.append("invalid graph map name")
		var map_schema_value: Variant = data.get("map_schema", null)
		if typeof(map_schema_value) != TYPE_STRING or map_schema_value != RUNTIME_MAP_SCHEMA or not _valid_int(data.get("map_version", null), 1, 1):
			errors.append("invalid graph map schema")
		errors.append_array(_validate_graph_source(data.get("map_source", null), graph_map_id))
		if facility_save:
			errors.append_array(_validate_facility_price_sources(data.get("map_source", null), board))
		var graph_start: Variant = data.get("start_position", null)
		var graph_board_size: int = board.size() if typeof(board) == TYPE_ARRAY else 0
		if not _valid_int(graph_start, 0, graph_board_size - 1):
			errors.append("invalid graph start position")
		if typeof(board) == TYPE_ARRAY:
			for index in range(board.size()):
				if typeof(board[index]) != TYPE_DICTIONARY:
					continue
				var tile: Dictionary = board[index]
				for coordinate in ["x", "y"]:
					if not _valid_int(tile.get(coordinate, null), -1000000, 1000000):
						errors.append("invalid graph tile coordinate %d" % index)
				var source_node_id: Variant = tile.get("source_node_id", null)
				if not _valid_int(source_node_id, index + 1, index + 1):
					errors.append("graph source node mismatch %d" % index)
				var type_value: Variant = tile.get("type_and_idx", null)
				var event_value: Variant = tile.get("event_code", null)
				if tile.has("source_status_bits") and (not _valid_int(tile.get("source_status_bits", null), 0, 0xffffffff) or (_valid_int(event_value, 0, 255) and (int(tile.get("source_status_bits")) & 0xff) != int(event_value))):
					errors.append("invalid graph source status bits %d" % index)
				if not _valid_int(type_value, 0, 65535) or not _valid_int(event_value, 0, 255):
					errors.append("invalid graph source tile status %d" % index)
				else:
					_validate_graph_source_classification(tile, index, errors, facility_save)
				var tile_kind: Variant = tile.get("kind", null)
				if _valid_int(tile.get("type_and_idx", null), 2001, 3999) and (typeof(tile_kind) != TYPE_STRING or tile_kind != "property"):
					errors.append("housing source must remain a property %d" % index)
				if typeof(tile_kind) == TYPE_STRING and tile_kind == "property":
					var source_object_id: Variant = tile.get("source_object_id", null)
					var source_object_valid: bool = _valid_int(source_object_id, 1, 1999)
					if not source_object_valid:
						errors.append("invalid graph property identity %d" % index)
					elif source_properties.has(int(source_object_id)):
						errors.append("duplicate graph property identity %d" % index)
					else:
						source_properties[int(source_object_id)] = true
					var land_price: Variant = tile.get("land_price", null)
					var house_price: Variant = tile.get("house_price", null)
					var land_price_valid: bool = _valid_int(land_price, 0, 1000000)
					var house_price_valid: bool = _valid_int(house_price, 0, 1000000)
					if not land_price_valid:
						errors.append("invalid graph property land price %d" % index)
					if not house_price_valid:
						errors.append("invalid graph property house price %d" % index)
					var rents: Variant = tile.get("rent_by_level", null)
					var rents_valid: bool = typeof(rents) == TYPE_ARRAY and rents.size() == MAX_PROPERTY_LEVEL + 1
					if not rents_valid:
						errors.append("invalid graph property rent table %d" % index)
					else:
						for rent_value in rents:
							if not _valid_int(rent_value, 0, 1000000):
								errors.append("invalid graph property rent value %d" % index)
						var base_rent: Variant = tile.get("base_rent", null)
						var rent: Variant = tile.get("rent", null)
						var level: Variant = tile.get("building_level", null)
						var base_rent_valid: bool = _valid_int(base_rent, 0, 1000000000)
						var rent_valid: bool = _valid_int(rent, 0, 1000000000)
						var level_valid: bool = _valid_int(level, 0, MAX_PROPERTY_LEVEL)
						if base_rent_valid and _valid_int(rents[0], 0, 1000000) and int(base_rent) != int(rents[0]):
							errors.append("graph property base rent mismatch %d" % index)
						if rent_valid and level_valid and _valid_int(rents[int(level)], 0, 1000000) and int(rent) != int(rents[int(level)]):
							errors.append("graph property rent mismatch %d" % index)
					if land_price_valid and _valid_int(tile.get("cost", null), 0, 1000000000) and int(tile["cost"]) != int(land_price):
						errors.append("graph property cost mismatch %d" % index)
					if house_price_valid and _valid_int(tile.get("upgrade_cost", null), 0, 1000000000) and int(tile["upgrade_cost"]) != int(house_price):
						errors.append("graph property upgrade price mismatch %d" % index)
					var property_type_valid: bool = _valid_int(type_value, 2001, 3999)
					if not property_type_valid:
						errors.append("invalid graph property source type %d" % index)
					elif source_object_valid and int(type_value) - 2000 != int(source_object_id):
						errors.append("graph property source mismatch %d" % index)
				var adjacent: Variant = tile.get("adjacent", null)
				if typeof(adjacent) != TYPE_ARRAY or adjacent.size() > 4:
					errors.append("invalid graph adjacency %d" % index)
					continue
				var seen_neighbors: Dictionary = {}
				for neighbor in adjacent:
					if not _valid_int(neighbor, 0, max(0, board.size() - 1)) or int(neighbor) == index or seen_neighbors.has(int(neighbor)):
						errors.append("invalid graph edge %d" % index)
						continue
					seen_neighbors[int(neighbor)] = true
					if typeof(board[int(neighbor)]) == TYPE_DICTIONARY:
						var reverse_adjacent: Variant = board[int(neighbor)].get("adjacent", [])
						var reverse_has: bool = false
						if typeof(reverse_adjacent) == TYPE_ARRAY:
							for reverse_neighbor in reverse_adjacent:
								if _valid_int(reverse_neighbor) and int(reverse_neighbor) == index:
									reverse_has = true
									break
						if not reverse_has:
							errors.append("asymmetric graph edge %d" % index)
			if _valid_int(graph_start, 0, graph_board_size - 1):
				graph_reachable[int(graph_start)] = true
				var queue: Array = [int(graph_start)]
				while not queue.is_empty():
					var node: int = int(queue.pop_front())
					if typeof(board[node]) != TYPE_DICTIONARY:
						continue
					var reachable_adjacent: Variant = board[node].get("adjacent", [])
					if typeof(reachable_adjacent) != TYPE_ARRAY:
						continue
					for neighbor in reachable_adjacent:
						if not _valid_int(neighbor, 0, max(0, board.size() - 1)):
							continue
						var next_node: int = int(neighbor)
						if not graph_reachable.has(next_node):
							graph_reachable[next_node] = true
							queue.append(next_node)
				var graph_playable_kinds: Array = ["property"]
				if facility_save:
					graph_playable_kinds.append("facility")
				for index in range(board.size()):
					if typeof(board[index]) == TYPE_DICTIONARY and graph_playable_kinds.has(board[index].get("kind", "")) and not graph_reachable.has(index):
						errors.append("graph property is unreachable %d" % index)
		else:
			for _unused in range(0):
				pass

	if inventory_save:
		var roadblocks_value: Variant = data.get("roadblocks", null)
		if typeof(roadblocks_value) != TYPE_DICTIONARY:
			errors.append("invalid roadblocks")
		elif not graph_save:
			if not roadblocks_value.is_empty():
				errors.append("non-graph inventory save cannot contain roadblocks")
		else:
			if roadblocks_value.size() > MAX_INVENTORY_ROADBLOCKS:
				errors.append("too many roadblocks")
			var graph_board_size_for_roadblocks: int = board.size() if typeof(board) == TYPE_ARRAY else 0
			for roadblock_key in roadblocks_value.keys():
				var roadblock_index_valid: bool = typeof(roadblock_key) == TYPE_STRING and str(roadblock_key).is_valid_int()
				var roadblock_index: int = int(roadblock_key) if roadblock_index_valid else -1
				if not roadblock_index_valid or str(roadblock_index) != str(roadblock_key) or not _valid_int(roadblock_index, 0, graph_board_size_for_roadblocks - 1):
					errors.append("invalid roadblock index")
					continue
				var placer_value: Variant = roadblocks_value[roadblock_key]
				if not _valid_int(placer_value, 0, max(0, player_count - 1)):
					errors.append("invalid roadblock placer")
				if typeof(board) != TYPE_ARRAY or typeof(board[roadblock_index]) != TYPE_DICTIONARY or not _is_graph_road_tile(board[roadblock_index]):
					errors.append("roadblock target is not a road")
				if not graph_reachable.has(roadblock_index):
					errors.append("roadblock target is unreachable")
				# Status teleport/release does not collide with or consume road objects.
				var status_anchor_overlap: bool = status_save and roadblock_index in [_status_node_index_in_board(board, "hospital"), _status_node_index_in_board(board, "prison")]
				if typeof(players) == TYPE_ARRAY and not status_anchor_overlap:
					for roadblock_player in players:
						if typeof(roadblock_player) == TYPE_DICTIONARY and _valid_bool(roadblock_player.get("alive", null)) and bool(roadblock_player.get("alive", false)) and _valid_int(roadblock_player.get("position", null), 0, graph_board_size_for_roadblocks - 1) and int(roadblock_player.get("position")) == roadblock_index:
							errors.append("roadblock target is occupied")
				if hazards_save and typeof(data.get("god_objects", null)) == TYPE_ARRAY:
					for roadblock_god in data.get("god_objects", []):
						if typeof(roadblock_god) == TYPE_DICTIONARY and _valid_int(roadblock_god.get("owner", null), -1, -1) and _valid_int(roadblock_god.get("node", null), roadblock_index, roadblock_index):
							errors.append("roadblock target overlaps dynamic road object")
			if hazards_save:
				hazard_active_tool_counts["路障"] = roadblocks_value.size()

	if hazards_save:
		var ground_hazards_value: Variant = data.get("ground_hazards", null)
		if typeof(ground_hazards_value) != TYPE_DICTIONARY:
			errors.append("invalid ground hazards")
		else:
			var mine_count: int = 0
			var bomb_ground_count: int = 0
			var hazard_board_size: int = board.size() if typeof(board) == TYPE_ARRAY else 0
			var hazard_route_overlap_node: int = -1
			if phase_name == "await_route" and _valid_int(data.get("remaining_steps", null), 1, MAX_GRAPH_STEPS) and typeof(players) == TYPE_ARRAY and _valid_int(current_player, 0, max(0, player_count - 1)) and current_player < players.size() and typeof(players[current_player]) == TYPE_DICTIONARY:
				var route_hazard_player: Dictionary = players[current_player]
				if _valid_int(route_hazard_player.get("position", null), 0, max(0, hazard_board_size - 1)):
					hazard_route_overlap_node = int(route_hazard_player.get("position"))
			for hazard_key in ground_hazards_value.keys():
				var hazard_index_valid: bool = typeof(hazard_key) == TYPE_STRING and str(hazard_key).is_valid_int()
				var hazard_index: int = int(hazard_key) if hazard_index_valid else -1
				if not hazard_index_valid or str(hazard_index) != str(hazard_key) or not _valid_int(hazard_index, 0, hazard_board_size - 1):
					errors.append("invalid ground hazard index")
					continue
				var hazard_object_value: Variant = ground_hazards_value[hazard_key]
				if typeof(hazard_object_value) != TYPE_DICTIONARY:
					errors.append("invalid ground hazard object")
					continue
				var hazard_object: Dictionary = hazard_object_value
				if hazard_object.size() != 2 or not hazard_object.has("kind") or not hazard_object.has("placer_id"):
					errors.append("ground hazard keys are not canonical")
				var hazard_kind: Variant = hazard_object.get("kind", null)
				if typeof(hazard_kind) != TYPE_STRING or not ["mine", "timed_bomb"].has(str(hazard_kind)):
					errors.append("invalid ground hazard kind")
				elif str(hazard_kind) == "mine":
					mine_count += 1
					hazard_active_tool_counts["地雷"] = int(hazard_active_tool_counts.get("地雷", 0)) + 1
				else:
					bomb_ground_count += 1
					hazard_active_tool_counts["定時炸彈"] = int(hazard_active_tool_counts.get("定時炸彈", 0)) + 1
				if not _valid_int(hazard_object.get("placer_id", null), 0, max(0, player_count - 1)):
					errors.append("invalid ground hazard placer")
				if typeof(board) != TYPE_ARRAY or typeof(board[hazard_index]) != TYPE_DICTIONARY or not _is_graph_road_tile(board[hazard_index]):
					errors.append("ground hazard target is not a road")
				if not graph_reachable.has(hazard_index):
					errors.append("ground hazard target is unreachable")
				var hazard_roadblocks_value: Variant = data.get("roadblocks", null)
				var hazard_god_objects_value: Variant = data.get("god_objects", null)
				var overlaps_dynamic: bool = typeof(hazard_roadblocks_value) == TYPE_DICTIONARY and hazard_roadblocks_value.has(str(hazard_index))
				if typeof(hazard_god_objects_value) == TYPE_ARRAY:
					for hazard_god in hazard_god_objects_value:
						if typeof(hazard_god) == TYPE_DICTIONARY and int(hazard_god.get("owner", -1)) < 0 and int(hazard_god.get("node", -1)) == hazard_index:
							overlaps_dynamic = true
				if overlaps_dynamic:
					errors.append("ground hazard overlaps dynamic road object")
				var hazard_status_anchor_overlap: bool = status_save and hazard_index in [_status_node_index_in_board(board, "hospital"), _status_node_index_in_board(board, "prison")]
				if typeof(players) == TYPE_ARRAY:
					for hazard_player in players:
						if typeof(hazard_player) != TYPE_DICTIONARY or not bool(hazard_player.get("alive", false)) or not _valid_int(hazard_player.get("position", null), hazard_index, hazard_index):
							continue
						# Status admission/release teleports through the canonical
						# hospital/prison anchor without running a landing collision.
						if hazard_status_anchor_overlap:
							continue
						if hazard_index == hazard_route_overlap_node:
							continue
						# The source timed-bomb handler is a no-op when the landing
						# player already carries a bomb. The ground object therefore
						# remains under that player until a later eligible landing.
						if str(hazard_kind) == "timed_bomb" and _valid_int(hazard_player.get("bomb_steps", null), 1, MAX_BOMB_STEPS):
							continue
						errors.append("ground hazard target is occupied")
			if mine_count > MAX_GROUND_MINES:
				errors.append("too many ground mines")
			var carried_bombs_in_save: int = 0
			if typeof(players) == TYPE_ARRAY:
				for hazard_player in players:
					if typeof(hazard_player) == TYPE_DICTIONARY and _valid_int(hazard_player.get("bomb_steps", null), 1, MAX_BOMB_STEPS):
						carried_bombs_in_save += 1
				hazard_active_tool_counts["定時炸彈"] = bomb_ground_count + carried_bombs_in_save
			if bomb_ground_count + carried_bombs_in_save > MAX_BOMBS:
				errors.append("too many timed bombs")
	elif data.has("ground_hazards") and typeof(data.get("ground_hazards")) == TYPE_DICTIONARY and not data.get("ground_hazards").is_empty():
		errors.append("ground hazards require v9 save")

	var held_inventory_cards: Dictionary = {}
	var held_inventory_tools: Dictionary = {}
	if typeof(players) == TYPE_ARRAY:
		var position_limit: int = (board.size() - 1) if typeof(board) == TYPE_ARRAY else BOARD_SIZE - 1
		for index in range(players.size()):
			if typeof(players[index]) != TYPE_DICTIONARY:
				errors.append("invalid player %d" % index)
				continue
			var player: Dictionary = players[index]
			var required_player: Array = ["id", "name", "is_human", "is_ai", "alive", "bankrupt", "cash", "deposit", "position", "properties", "property_values", "stocks", "cards", "vehicle", "dice_count", "vehicles", "skip_turns", "rent_shield", "turtle_days", "stay_next", "loan", "loan_due_day", "turns_taken"]
			if graph_save:
				required_player.append("previous_position")
			if graph_save or inventory_save:
				required_player.append("points")
			if inventory_save:
				required_player.append("tools")
			if companies_save:
				required_player.append("insurance_status")
			if gods_save:
				required_player.append_array(["god_id", "hospital_days"])
			if status_save:
				required_player.append("prison_days")
			if hazards_save:
				required_player.append("bomb_steps")
			if setup_save:
				required_player.append_array(["character_id", "init_cash_ratio"])
			for required_key in required_player:
				if not player.has(required_key):
					errors.append("player %d missing %s" % [index, required_key])
			if not _valid_int(player.get("id", null), index, index) or not _valid_string(player.get("name", null)):
				errors.append("player %d identity invalid" % index)
			for bool_key in ["is_human", "is_ai", "alive", "bankrupt"]:
				if not _valid_bool(player.get(bool_key, null)):
					errors.append("player %d %s invalid" % [index, bool_key])
			if _valid_bool(player.get("is_human", null)) and _valid_bool(player.get("is_ai", null)) and bool(player["is_human"]) == bool(player["is_ai"]):
				errors.append("player %d control flags invalid" % index)
			if _valid_bool(player.get("alive", null)) and _valid_bool(player.get("bankrupt", null)) and bool(player["alive"]) == bool(player["bankrupt"]):
				errors.append("player %d alive state invalid" % index)
			if setup_save:
				var character_id_value: Variant = player.get("character_id", null)
				var character_id_valid: bool = _valid_int(character_id_value, 0, SETUP_CHARACTER_COUNT - 1)
				var initially_human: bool = SetupControls.initially_human(data.get("initial_human_flags", []), index)
				var expected_ratio: int = 50 if initially_human else int(AI_CASH_RATIOS[int(character_id_value)]) if character_id_valid else -1
				if not character_id_valid or typeof(data.get("character_ids", null)) != TYPE_ARRAY or index >= data["character_ids"].size() or int(data["character_ids"][index]) != int(character_id_value):
					errors.append("player %d character identity invalid" % index)
				if character_id_valid and _valid_string(player.get("name", null)) and str(player.get("name", "")) != str(SETUP_CHARACTER_NAMES[int(character_id_value)]):
					errors.append("player %d character name mismatch" % index)
				if not _valid_int(player.get("init_cash_ratio", null), 0, 100) or int(player.get("init_cash_ratio", -1)) != expected_ratio:
					errors.append("player %d initial cash ratio invalid" % index)
			for money_key in ["cash", "deposit", "property_values", "loan"]:
				if not _valid_int(player.get(money_key, null), 0, 1000000000000):
					errors.append("player %d %s invalid" % [index, money_key])
				for counter_key in ["position", "skip_turns", "rent_shield", "turtle_days", "stay_next", "loan_due_day", "turns_taken"]:
					if not _valid_int(player.get(counter_key, null), 0, 1000000000):
						errors.append("player %d %s invalid" % [index, counter_key])
				if hazards_save and not _valid_int(player.get("bomb_steps", null), 0, MAX_BOMB_STEPS):
					errors.append("player %d bomb_steps invalid" % index)
				elif hazards_save and not bool(player.get("alive", false)) and int(player.get("bomb_steps", 0)) > 0:
					errors.append("dead player cannot carry bomb")
			var sleep_validation: Dictionary = SleepRules.validate_player(player)
			if not bool(sleep_validation.get("ok", false)):
				errors.append("player %d %s" % [index, str(sleep_validation.get("error", "sleep state invalid"))])
			if player.has("loan_block_days") and not _valid_int(player.get("loan_block_days", null), 0, MAX_STATUS_ADMISSION_DAYS):
				errors.append("player %d loan_block_days invalid" % index)
			if companies_save and not _valid_int(player.get("insurance_status"), 0, 128):
				errors.append("player %d insurance_status invalid" % index)
			if gods_save:
				var player_god_value: Variant = player.get("god_id", null)
				if not _valid_int(player_god_value, 0, 15):
					errors.append("player %d god_id invalid" % index)
				elif int(player_god_value) != 0 and not OriginalGods.valid_id(player_god_value):
					errors.append("player %d god_id unknown" % index)
				var hospital_max: int = MAX_STATUS_ADMISSION_DAYS if status_save else 3
				if not _valid_int(player.get("hospital_days", null), 0, hospital_max):
					errors.append("player %d hospital_days invalid" % index)
				if status_save and not _valid_int(player.get("prison_days", null), 0, MAX_STATUS_ADMISSION_DAYS):
					errors.append("player %d prison_days invalid" % index)
			if graph_save or inventory_save:
				if not _valid_int(player.get("previous_position", null), -1, position_limit):
					if graph_save:
						errors.append("player %d previous_position invalid" % index)
				if not _valid_int(player.get("points", null), 0, 1000000000000):
					errors.append("player %d points invalid" % index)
			var dice_count_value: Variant = player.get("dice_count", null)
			var dice_count_valid: bool = _valid_int(dice_count_value, 1, 3)
			if not dice_count_valid:
				errors.append("player %d dice_count invalid" % index)
			if _valid_int(player.get("position", null)) and int(player["position"]) > position_limit:
				errors.append("player %d position out of range" % index)
			var vehicle_value: Variant = player.get("vehicle", null)
			var vehicle_valid: bool = _valid_string(vehicle_value) and VEHICLE_DICE.has(vehicle_value)
			if dice_count_valid and vehicle_valid and int(dice_count_value) > int(VEHICLE_DICE[vehicle_value]):
				errors.append("player %d dice count exceeds vehicle" % index)
			if not vehicle_valid:
				errors.append("player %d vehicle invalid" % index)
			var engineering_present: bool = player.has("engineering_vehicle") or vehicle_value == EngineeringVehicle.VEHICLE_ID
			if engineering_present and (not inventory_save or not graph_save):
				errors.append("player %d engineering vehicle requires inventory graph save" % index)
			elif engineering_present:
				var engineering_validation: Dictionary = EngineeringVehicle.validate_player(player)
				if not bool(engineering_validation.get("ok", false)):
					errors.append("player %d engineering vehicle invalid: %s" % [index, str(engineering_validation.get("error", ""))])
			var properties: Variant = player.get("properties", null)
			if typeof(properties) != TYPE_ARRAY:
				errors.append("player %d properties invalid" % index)
			else:
				for property_id in properties:
					if not _valid_int(property_id, 0, position_limit):
						errors.append("player %d property invalid" % index)
					elif facility_save and typeof(board) == TYPE_ARRAY and int(property_id) < board.size() and typeof(board[int(property_id)]) == TYPE_DICTIONARY and board[int(property_id)].get("kind", "") == "facility":
						var owned_facility_tile: Dictionary = board[int(property_id)]
						var owned_facility_source: Variant = owned_facility_tile.get("source_object_id", null)
						var owned_facility_canonical: Variant = owned_facility_tile.get("facility_node_index", null)
						if not _valid_int(owned_facility_source, 1, 1999) or not _valid_int(owned_facility_canonical, 0, position_limit):
							errors.append("player %d facility property invalid" % index)
						elif int(property_id) != int(owned_facility_canonical):
							errors.append("player %d facility property is not canonical" % index)
						elif facility_owners.has(int(owned_facility_source)):
							if int(facility_owners[int(owned_facility_source)]) != index:
								errors.append("player %d facility owner mismatch" % index)
							facility_owners.erase(int(owned_facility_source))
						else:
							errors.append("player %d references unowned facility" % index)
					elif property_owners.has(int(property_id)):
						if int(property_owners[int(property_id)]) != index:
							errors.append("player %d property owner mismatch" % index)
						property_owners.erase(int(property_id))
			var stocks: Variant = player.get("stocks", null)
			if typeof(stocks) != TYPE_DICTIONARY:
				errors.append("player %d stocks invalid" % index)
			else:
				for symbol in stock_symbols:
					if not _valid_int(stocks.get(symbol, null), 0, 1000000000):
						errors.append("player %d stock %s invalid" % [index, symbol])
				for symbol in stocks.keys():
					if not stock_symbols.has(symbol):
						errors.append("player %d unknown stock" % index)
			if companies_save:
				errors.append_array(StockAccounting.validate_player(player, stock_symbols))
			var cards: Variant = player.get("cards", null)
			if typeof(cards) != TYPE_ARRAY or cards.size() > 15:
				errors.append("player %d cards invalid" % index)
			else:
				for card_id in cards:
					if not _valid_string(card_id):
						errors.append("player %d card invalid" % index)
					elif inventory_save:
						var card_record: Dictionary = OriginalInventoryCatalogue.card(str(card_id))
						if card_record.is_empty():
							errors.append("player %d card unknown" % index)
						else:
							held_inventory_cards[str(card_id)] = int(held_inventory_cards.get(str(card_id), 0)) + 1
			if inventory_save:
				var player_tool_totals: Dictionary = {}
				var tools: Variant = player.get("tools", null)
				if typeof(tools) != TYPE_DICTIONARY:
					errors.append("player %d tools invalid" % index)
				else:
					for tool_id in tools.keys():
						if typeof(tool_id) != TYPE_STRING or OriginalInventoryCatalogue.tool(str(tool_id)).is_empty():
							errors.append("player %d tool unknown" % index)
							continue
						var tool_quantity: Variant = tools[tool_id]
						var tool_capacity: int = OriginalInventory.VEHICLE_STORAGE_CAPACITY if OriginalInventory.VEHICLE_TOOL_IDS.has(str(tool_id)) else OriginalInventory.TOOL_CAPACITY_PER_TYPE
						if not _valid_int(tool_quantity, 0, tool_capacity):
							errors.append("player %d tool quantity invalid" % index)
							continue
						held_inventory_tools[str(tool_id)] = int(held_inventory_tools.get(str(tool_id), 0)) + int(tool_quantity)
						player_tool_totals[str(tool_id)] = int(player_tool_totals.get(str(tool_id), 0)) + int(tool_quantity)
				if vehicle_valid and VEHICLE_TOOL_IDS.has(str(vehicle_value)):
					var active_tool_id: String = str(VEHICLE_TOOL_IDS[str(vehicle_value)])
					held_inventory_tools[active_tool_id] = int(held_inventory_tools.get(active_tool_id, 0)) + 1
					player_tool_totals[active_tool_id] = int(player_tool_totals.get(active_tool_id, 0)) + 1
				for total_tool_id in player_tool_totals:
					var total_capacity: int = OriginalInventory.VEHICLE_STORAGE_CAPACITY if OriginalInventory.VEHICLE_TOOL_IDS.has(str(total_tool_id)) else OriginalInventory.TOOL_CAPACITY_PER_TYPE
					if int(player_tool_totals[total_tool_id]) > total_capacity:
						errors.append("player %d tool total exceeds capacity %s" % [index, total_tool_id])
			var vehicles: Variant = player.get("vehicles", null)
			if typeof(vehicles) != TYPE_DICTIONARY:
				errors.append("player %d vehicles invalid" % index)
			else:
				for vehicle in ["walking", "motorcycle", "car"]:
					if not _valid_bool(vehicles.get(vehicle, null)):
						errors.append("player %d vehicle ownership invalid" % index)
				if vehicle_valid and vehicle_value != EngineeringVehicle.VEHICLE_ID and (not vehicles.has(vehicle_value) or not bool(vehicles.get(vehicle_value, false))):
					errors.append("player %d selected vehicle is not owned" % index)

	var alliance_errors: Array = AllianceRules.validate_save(data, player_count, inventory_save)
	errors.append_array(alliance_errors)

	if status_save:
		var hospital_node: int = _status_node_index_in_board(board, "hospital")
		var prison_node: int = _status_node_index_in_board(board, "prison")
		if hospital_node < 0:
			errors.append("status save missing hospital node")
		if prison_node < 0:
			errors.append("status save missing prison node")
		if typeof(players) == TYPE_ARRAY and typeof(board) == TYPE_ARRAY:
			for status_player_index in range(players.size()):
				if typeof(players[status_player_index]) != TYPE_DICTIONARY:
					continue
				var status_player: Dictionary = players[status_player_index]
				var hospital_value: Variant = status_player.get("hospital_days", null)
				var prison_value: Variant = status_player.get("prison_days", null)
				var hospital_valid: bool = _valid_int(hospital_value, 0, MAX_STATUS_ADMISSION_DAYS)
				var prison_valid: bool = _valid_int(prison_value, 0, MAX_STATUS_ADMISSION_DAYS)
				if hospital_valid and prison_valid and int(hospital_value) > 0 and int(prison_value) > 0:
					errors.append("player %d has mutually exclusive statuses" % status_player_index)
				var status_position_valid: bool = _valid_int(status_player.get("position", null), 0, board.size() - 1)
				var status_previous_valid: bool = _valid_int(status_player.get("previous_position", null), -1, board.size() - 1)
				if hospital_valid and int(hospital_value) > 0 and hospital_node >= 0:
					if status_position_valid and int(status_player.get("position")) != hospital_node:
						errors.append("player %d hospital position mismatch" % status_player_index)
					if status_previous_valid and int(status_player.get("previous_position")) != -1:
						errors.append("player %d hospital previous position mismatch" % status_player_index)
				if prison_valid and int(prison_value) > 0 and prison_node >= 0:
					if status_position_valid and int(status_player.get("position")) != prison_node:
						errors.append("player %d prison position mismatch" % status_player_index)
					if status_previous_valid and int(status_player.get("previous_position")) != -1:
						errors.append("player %d prison previous position mismatch" % status_player_index)

	if data.has("pending_trap_card"):
		if data.get("pending_trap_card") != "夢遊" or not status_save or typeof(data.get("pending_trap", null)) != TYPE_DICTIONARY or data.get("pending_trap", {}).is_empty():
			errors.append("invalid pending trap card discriminator")
	if status_save:
		var pending_trap_value: Variant = data.get("pending_trap", null)
		if typeof(pending_trap_value) != TYPE_DICTIONARY:
			errors.append("invalid pending trap")
		else:
			var pending_trap: Dictionary = pending_trap_value
			if not pending_trap.is_empty():
				if pending_trap.size() != 2 or not pending_trap.has("caster_id") or not pending_trap.has("target_id"):
					errors.append("pending trap keys are not canonical")
				var pending_caster: Variant = pending_trap.get("caster_id", null)
				var pending_target: Variant = pending_trap.get("target_id", null)
				var pending_ids_valid: bool = _valid_int(pending_caster, 0, max(0, player_count - 1)) and _valid_int(pending_target, 0, max(0, player_count - 1))
				if not pending_ids_valid:
					errors.append("pending trap player id invalid")
				elif int(pending_caster) == int(pending_target) and data.get("pending_trap_card", "") != "夢遊":
					errors.append("pending trap players must differ")
				else:
					var pending_caster_player: Variant = players[int(pending_caster)] if typeof(players) == TYPE_ARRAY and int(pending_caster) < players.size() else null
					var pending_target_player: Variant = players[int(pending_target)] if typeof(players) == TYPE_ARRAY and int(pending_target) < players.size() else null
					if typeof(pending_caster_player) != TYPE_DICTIONARY or typeof(pending_target_player) != TYPE_DICTIONARY:
						errors.append("pending trap players missing")
					else:
						var pending_caster_record: Dictionary = pending_caster_player
						var pending_target_record: Dictionary = pending_target_player
						if int(pending_caster) != current_player:
							errors.append("pending trap caster mismatch")
						if not bool(pending_caster_record.get("alive", false)) or not bool(pending_target_record.get("alive", false)):
							errors.append("pending trap player is dead")
						var pending_caster_hospital: Variant = pending_caster_record.get("hospital_days", null)
						var pending_caster_prison: Variant = pending_caster_record.get("prison_days", null)
						if not _valid_int(pending_caster_hospital, 0, MAX_STATUS_ADMISSION_DAYS) or not _valid_int(pending_caster_prison, 0, MAX_STATUS_ADMISSION_DAYS) or int(pending_caster_hospital) > 0 or int(pending_caster_prison) > 0:
							errors.append("pending trap caster is detained")
						if not bool(pending_target_record.get("is_human", false)) or bool(pending_target_record.get("is_ai", false)):
							errors.append("pending trap target must be human")
						var pending_target_hospital: Variant = pending_target_record.get("hospital_days", null)
						var pending_target_prison: Variant = pending_target_record.get("prison_days", null)
						if not _valid_int(pending_target_hospital, 0, MAX_STATUS_ADMISSION_DAYS) or not _valid_int(pending_target_prison, 0, MAX_STATUS_ADMISSION_DAYS) or int(pending_target_hospital) > 0 or int(pending_target_prison) > 0:
							errors.append("pending trap target is detained")
						var pending_target_cards: Variant = pending_target_record.get("cards", null)
						if typeof(pending_target_cards) != TYPE_ARRAY or not pending_target_cards.has("嫁禍"):
							errors.append("pending trap target lacks scapegoat")
						elif pending_target_cards.has("免罪"):
							errors.append("pending trap target has immunity")
						if phase_name not in ["await_roll", "await_action"]:
							errors.append("pending trap outside action phase")
						var pending_remote_for_trap: Variant = data.get("pending_remote_dice", {})
						if typeof(pending_remote_for_trap) != TYPE_DICTIONARY or not pending_remote_for_trap.is_empty():
							errors.append("pending trap conflicts with remote dice")
						if typeof(action_options) == TYPE_ARRAY and action_options != ["respond_trap"]:
							errors.append("pending trap action options mismatch")
	else:
		var legacy_pending_trap: Variant = data.get("pending_trap", {})
		if typeof(legacy_pending_trap) == TYPE_DICTIONARY and not legacy_pending_trap.is_empty():
			errors.append("pending trap requires v8 save")

	if gods_save:
		var god_objects_value: Variant = data.get("god_objects", null)
		var god_owner_by_id: Dictionary = {}
		var god_route_overlap_node: int = -1
		if hazards_save and phase_name == "await_route" and _valid_int(data.get("remaining_steps", null), 1, MAX_GRAPH_STEPS) and typeof(players) == TYPE_ARRAY and _valid_int(current_player, 0, max(0, player_count - 1)) and current_player < players.size() and typeof(players[current_player]) == TYPE_DICTIONARY:
			var god_route_player: Dictionary = players[current_player]
			if _valid_int(god_route_player.get("position", null), 0, max(0, board.size() - 1) if typeof(board) == TYPE_ARRAY else -1):
				god_route_overlap_node = int(god_route_player.get("position"))
		if typeof(god_objects_value) != TYPE_ARRAY or god_objects_value.size() > 15:
			errors.append("invalid god_objects")
		else:
			var seen_god_ids: Dictionary = {}
			var seen_unbound_god_nodes: Dictionary = {}
			var god_reachable_nodes := _graph_reachable_nodes(board, data.get("start_position", null))
			var god_board_limit: int = board.size() - 1 if typeof(board) == TYPE_ARRAY else -1
			for god_object_index in range(god_objects_value.size()):
				var god_object_value: Variant = god_objects_value[god_object_index]
				if typeof(god_object_value) != TYPE_DICTIONARY:
					errors.append("invalid god object %d" % god_object_index)
					continue
				var god_object: Dictionary = god_object_value
				for god_key in ["id", "node", "owner", "days"]:
					if not god_object.has(god_key):
						errors.append("god object %d missing %s" % [god_object_index, god_key])
				var god_id_value: Variant = god_object.get("id", null)
				var god_id_valid: bool = _valid_int(god_id_value, 1, 15) and OriginalGods.valid_id(god_id_value)
				if not god_id_valid:
					errors.append("god object %d id invalid" % god_object_index)
					continue
				var god_id: int = int(god_id_value)
				if god_id in [13, 14]:
					errors.append("god object %d unsupported" % god_id)
				if seen_god_ids.has(god_id):
					errors.append("duplicate god object %d" % god_id)
				seen_god_ids[god_id] = true
				var god_node_value: Variant = god_object.get("node", null)
				if not _valid_int(god_node_value, 0, god_board_limit):
					errors.append("god object %d node invalid" % god_id)
				var god_owner_value: Variant = god_object.get("owner", null)
				var god_owner_valid: bool = _valid_int(god_owner_value, -1, max(-1, player_count - 1))
				if not god_owner_valid:
					errors.append("god object %d owner invalid" % god_id)
				var god_days_value: Variant = god_object.get("days", null)
				if not _valid_int(god_days_value, 0, 13):
					errors.append("god object %d days invalid" % god_id)
				var god_owner: int = int(god_owner_value) if god_owner_valid else -1
				var god_days: int = int(god_days_value) if _valid_int(god_days_value, 0, 13) else -1
				if god_owner >= 0:
					god_owner_by_id[god_id] = god_owner
					if god_id == 11 or god_id in [13, 14]:
						errors.append("god object %d cannot attach" % god_id)
					if god_days <= 0:
						errors.append("attached god %d has no remaining days" % god_id)
					if god_days > OriginalGods.days_for(god_id):
						errors.append("attached god %d exceeds its duration" % god_id)
					if typeof(players) == TYPE_ARRAY and god_owner < players.size() and typeof(players[god_owner]) == TYPE_DICTIONARY:
						var god_owner_player: Dictionary = players[god_owner]
						if not bool(god_owner_player.get("alive", false)) or int(god_owner_player.get("god_id", 0)) != god_id:
							errors.append("god object %d owner mismatch" % god_id)
						if _valid_int(god_node_value, 0, god_board_limit) and _valid_int(god_owner_player.get("position", null), 0, god_board_limit) and int(god_node_value) != int(god_owner_player.get("position")):
							errors.append("god object %d node does not follow owner" % god_id)
				else:
					if not OriginalGods.is_spawnable(god_id):
						errors.append("unattached god %d is not spawnable" % god_id)
					if god_days != 0:
						errors.append("unattached god %d has remaining days" % god_id)
					if _valid_int(god_node_value, 0, god_board_limit):
						if seen_unbound_god_nodes.has(int(god_node_value)):
							errors.append("duplicate unattached god node %d" % int(god_node_value))
						seen_unbound_god_nodes[int(god_node_value)] = true
						if not god_reachable_nodes.has(int(god_node_value)):
							errors.append("unattached god %d node is unreachable" % god_id)
						if typeof(board[int(god_node_value)]) != TYPE_DICTIONARY or not OriginalGods.source_tile_eligible(board[int(god_node_value)]):
							errors.append("unattached god %d node is not eligible" % god_id)
						if typeof(players) == TYPE_ARRAY and _valid_int(god_node_value, 0, god_board_limit):
							# Admission/release preserves unbound gods at source status anchors.
							# Released players may remain there with a zero counter (stay_next).
							var status_anchor_overlap: bool = status_save and int(god_node_value) in [_status_node_index_in_board(board, "hospital"), _status_node_index_in_board(board, "prison")]
							var route_overlap: bool = hazards_save and int(god_node_value) == god_route_overlap_node
							for god_player in players:
								if not status_anchor_overlap and not route_overlap and typeof(god_player) == TYPE_DICTIONARY and bool(god_player.get("alive", false)) and _valid_int(god_player.get("position", null), 0, god_board_limit) and int(god_player.get("position")) == int(god_node_value):
									errors.append("unattached god %d is on player" % god_id)
			if typeof(players) == TYPE_ARRAY:
				var god_claimed_by_player: Dictionary = {}
				for god_player_index in range(players.size()):
					if typeof(players[god_player_index]) != TYPE_DICTIONARY:
						continue
					var god_player: Dictionary = players[god_player_index]
					var player_god_value: Variant = god_player.get("god_id", 0)
					if _valid_int(player_god_value, 1, 15) and int(player_god_value) != 0:
						var player_god_id: int = int(player_god_value)
						if god_claimed_by_player.has(player_god_id):
							errors.append("god %d claimed by multiple players" % player_god_id)
						else:
							god_claimed_by_player[player_god_id] = god_player_index
						if not god_owner_by_id.has(player_god_id):
							errors.append("player %d god object missing" % god_player_index)
						elif int(god_owner_by_id[player_god_id]) != god_player_index:
							errors.append("player %d god object owner mismatch" % god_player_index)

	if setup_save and typeof(players) == TYPE_ARRAY and typeof(bank) == TYPE_DICTIONARY and _valid_int(bank.get("deposits", null), 0, 1000000000000):
		var setup_deposits: int = 0
		for player in players:
			if typeof(player) == TYPE_DICTIONARY and _valid_int(player.get("deposit", null), 0, 1000000000000):
				setup_deposits += int(player.get("deposit", 0))
		if setup_deposits != int(bank["deposits"]):
			errors.append("bank deposits mismatch")

	if inventory_save:
		for record in OriginalInventoryCatalogue.cards():
			var card_id: String = str(record["id"])
			if not inventory_card_supply.has(card_id):
				continue
			var card_initial: int = int(record["initial_supply"])
			var card_held: int = int(held_inventory_cards.get(card_id, 0))
			var card_supply_value: Variant = inventory_card_supply.get(card_id, null)
			if not _valid_int(card_supply_value, 0, 1000000000):
				continue
			if int(card_supply_value) + card_held != card_initial:
				errors.append("inventory card conservation mismatch %s" % card_id)
		for record in OriginalInventoryCatalogue.tools():
			var tool_id: String = str(record["id"])
			var source_id: int = int(record["source_id"])
			var supply_value: Variant = inventory_tool_supply.get(tool_id, null)
			if not _valid_int(supply_value, 0, 1000000000):
				continue
			var supply_quantity: int = int(supply_value)
			if source_id > OriginalInventory.FINITE_TOOL_SOURCE_ID_MAX:
				if supply_quantity != 0:
					errors.append("research tool pool is not empty %s" % tool_id)
				continue
			var tool_initial: int = int(record["initial_supply"])
			var tool_held: int = int(held_inventory_tools.get(tool_id, 0)) + int(hazard_active_tool_counts.get(tool_id, 0))
			var tool_total: int = supply_quantity + tool_held
			if tool_total != tool_initial:
				errors.append("inventory tool conservation mismatch %s" % tool_id)

	if graph_save:
		var graph_board_size: int = board.size() if typeof(board) == TYPE_ARRAY else 0
		if typeof(players) == TYPE_ARRAY and typeof(board) == TYPE_ARRAY:
			for index in range(players.size()):
				if typeof(players[index]) != TYPE_DICTIONARY:
					continue
				var graph_player: Dictionary = players[index]
				var position: Variant = graph_player.get("position", null)
				var previous_position: Variant = graph_player.get("previous_position", null)
				if _valid_int(position, 0, graph_board_size - 1) and _valid_int(previous_position, -1, max(-1, graph_board_size - 1)):
					if int(previous_position) >= 0 and typeof(board[int(position)]) == TYPE_DICTIONARY:
						var player_adjacent: Variant = board[int(position)].get("adjacent", [])
						var player_previous_valid: bool = false
						if typeof(player_adjacent) == TYPE_ARRAY:
							for player_neighbor in player_adjacent:
								if _valid_int(player_neighbor) and int(player_neighbor) == int(previous_position):
									player_previous_valid = true
									break
						if not player_previous_valid:
							errors.append("player %d previous node is not adjacent" % index)
					if not graph_reachable.has(int(position)):
						errors.append("player %d position is unreachable" % index)
		var route_options: Variant = data.get("route_options", null)
		var remaining_steps_value: Variant = data.get("remaining_steps", null)
		if typeof(route_options) != TYPE_ARRAY:
			errors.append("invalid graph route options")
		if not _valid_int(remaining_steps_value, 0, MAX_GRAPH_STEPS):
			errors.append("invalid graph remaining steps")
		var pending_value: Variant = data.get("pending_movement", null)
		if typeof(pending_value) != TYPE_DICTIONARY:
			errors.append("invalid graph pending movement")
		var pending: Dictionary = pending_value if typeof(pending_value) == TYPE_DICTIONARY else {}
		if phase_name == "await_route":
			if typeof(route_options) != TYPE_ARRAY or route_options.is_empty():
				errors.append("route phase missing route options")
			if not _valid_int(remaining_steps_value, 1, MAX_GRAPH_STEPS):
				errors.append("route phase has no remaining steps")
			if _valid_int(remaining_steps_value, 0, MAX_GRAPH_STEPS) and last_total_valid and int(remaining_steps_value) > int(last_total_value):
				errors.append("route phase exceeds pending roll")
			if not last_roll_valid or last_roll.is_empty():
				errors.append("route phase missing pending roll")
			if last_roll_valid and typeof(players) == TYPE_ARRAY and current_player >= 0 and current_player < players.size() and typeof(players[current_player]) == TYPE_DICTIONARY:
				var pending_actor: Dictionary = players[current_player]
				var pending_vehicle: Variant = pending_actor.get("vehicle", null)
				if _valid_string(pending_vehicle) and VEHICLE_DICE.has(pending_vehicle) and last_roll.size() > int(VEHICLE_DICE[pending_vehicle]):
					errors.append("route phase exceeds vehicle dice limit")
			if pending.is_empty():
				errors.append("route phase missing pending movement")
			else:
				var pending_player_id: Variant = pending.get("player_id", null)
				var pending_current_node: Variant = pending.get("current_node", null)
				var pending_previous_node: Variant = pending.get("previous_node", null)
				var pending_player_valid: bool = _valid_int(pending_player_id, 0, max(0, player_count - 1))
				var pending_current_valid: bool = _valid_int(pending_current_node, 0, graph_board_size - 1)
				var pending_previous_valid: bool = _valid_int(pending_previous_node, -1, max(-1, graph_board_size - 1))
				if not pending_player_valid or int(pending_player_id) != current_player:
					errors.append("pending route player mismatch")
				if not pending_current_valid or not pending_previous_valid:
					errors.append("pending route node invalid")
				if typeof(players) == TYPE_ARRAY and current_player >= 0 and current_player < players.size() and typeof(players[current_player]) == TYPE_DICTIONARY and pending_current_valid and pending_previous_valid:
					var route_player: Dictionary = players[current_player]
					var route_position: Variant = route_player.get("position", null)
					var route_previous_position: Variant = route_player.get("previous_position", null)
					if not _valid_int(route_position, 0, graph_board_size - 1) or not _valid_int(route_previous_position, -1, max(-1, graph_board_size - 1)) or int(route_position) != int(pending_current_node) or int(route_previous_position) != int(pending_previous_node):
						errors.append("pending route position mismatch")
				if pending_current_valid and pending_previous_valid:
					var legal_routes: Array = []
					var pending_tile: Dictionary = {}
					if typeof(board) == TYPE_ARRAY:
						var pending_tile_value: Variant = board[int(pending_current_node)]
						if typeof(pending_tile_value) == TYPE_DICTIONARY:
							pending_tile = pending_tile_value
					var pending_adjacent: Variant = pending_tile.get("adjacent", [])
					if typeof(pending_adjacent) == TYPE_ARRAY:
						for neighbor in pending_adjacent:
							if not _valid_int(neighbor, 0, graph_board_size - 1):
								continue
							var neighbor_id: int = int(neighbor)
							if neighbor_id != int(pending_previous_node):
								legal_routes.append(neighbor_id)
					if legal_routes.is_empty() and int(pending_previous_node) >= 0:
						legal_routes.append(int(pending_previous_node))
					legal_routes.sort()
					var canonical_route_options: Array = []
					if typeof(route_options) == TYPE_ARRAY:
						for route_option in route_options:
							if _valid_int(route_option):
								canonical_route_options.append(int(route_option))
					if canonical_route_options != legal_routes or canonical_route_options.size() != route_options.size():
						errors.append("pending route options are not canonical")
		else:
			if typeof(route_options) == TYPE_ARRAY and not route_options.is_empty():
				errors.append("non-route phase has route options")
			if _valid_int(remaining_steps_value, 0, MAX_GRAPH_STEPS) and int(remaining_steps_value) != 0:
				errors.append("non-route phase has remaining steps")
			if typeof(pending_value) == TYPE_DICTIONARY and not pending.is_empty():
				errors.append("non-route phase has pending movement")

	if not property_owners.is_empty():
		errors.append("board property missing player ownership")
	if not facility_owners.is_empty():
		errors.append("board facility missing player ownership")
	if phase_name != "game_over" and current_player >= 0 and current_player < player_count and typeof(players[current_player]) == TYPE_DICTIONARY:
		var current_actor: Dictionary = players[current_player]
		if not _valid_bool(current_actor.get("alive", null)) or not bool(current_actor.get("alive", false)) or not _valid_bool(current_actor.get("bankrupt", null)) or bool(current_actor.get("bankrupt", false)):
			errors.append("dead current player")
	if phase_name == "game_over":
		if winner < 0:
			var calendar_terminal_event := false
			if setup_save and last_event is Dictionary:
				var event_boundary: Variant = last_event.get("calendar_boundary", false)
				var event_elapsed: Variant = last_event.get("elapsed", null)
				calendar_terminal_event = GameCalendar.is_last_supported_date(data.get("date", {})) \
					and str(last_event.get("type", "")) == "game_over" \
					and str(last_event.get("reason", "")) == "calendar_limit" \
					and typeof(event_boundary) == TYPE_BOOL and bool(event_boundary) \
					and _valid_int(event_elapsed, 0, 3000000) \
					and _valid_int(data.get("elapsed", null), 0, 3000000) \
					and int(event_elapsed) == int(data.get("elapsed", -1))
			var company_terminal_event: bool = companies_save and typeof(last_event)==TYPE_DICTIONARY and last_event.get("type","")=="game_over" and last_event.get("reason","")=="company_dividend_no_survivors" and _valid_int(last_event.get("winner"),-1,-1)
			if company_terminal_event:
				for player in players:
					if typeof(player)!=TYPE_DICTIONARY or not _valid_bool(player.get("alive")) or bool(player.alive): company_terminal_event=false
			if not (setup_save and calendar_terminal_event) and not company_terminal_event:
				errors.append("invalid game over winner")
		elif winner >= 0 and (winner >= player_count or typeof(players[winner]) != TYPE_DICTIONARY or not bool(players[winner].get("alive", false))):
			errors.append("invalid game over winner")
	elif winner != -1:
		errors.append("winner set before game over")

	if companies_save:
		errors.append_array(OriginalStockMarket.validate(data.get("market"), data.get("players"), data.get("companies"), not research_save))
		errors.append_array(_validate_companies(data.get("companies"), data.get("players"), data.get("board")))
		var pending_company: Variant = data.get("company_service_pending")
		if not _valid_int(pending_company,0,1999):
			errors.append("invalid pending company service")
		elif int(pending_company)>0:
			var pending_valid := false
			if typeof(players)==TYPE_ARRAY and _valid_int(data.get("current_player"),0,players.size()-1) and typeof(board)==TYPE_ARRAY and typeof(data.get("companies"))==TYPE_ARRAY:
				var pending_player: Variant = players[int(data.current_player)]
				if typeof(pending_player)==TYPE_DICTIONARY and _valid_int(pending_player.get("position"),0,board.size()-1):
					var pending_tile: Variant = board[int(pending_player.position)]
					if typeof(pending_tile)==TYPE_DICTIONARY and _valid_int(pending_tile.get("type_and_idx"),6000+int(pending_company),6000+int(pending_company)):
						for company in data.companies:
							if typeof(company)==TYPE_DICTIONARY and _valid_int(company.get("id"),int(pending_company),int(pending_company)) and _valid_int(company.get("company_type"),11,11) and _valid_int(company.get("owner"),0,players.size()-1):
								pending_valid=data.get("phase","")=="await_action" and not _company_upgrade_target_ids(board,int(data.current_player),remodel_save,research_save).is_empty()
			if pending_valid and errors.is_empty():
				var pending_game = new()
				pending_game.state = data
				pending_valid = not pending_game._company_payable_upgrade_targets(int(data.current_player), pending_game.get_company_at(int(players[int(data.current_player)].position))).is_empty()
			if not pending_valid: errors.append("pending company service context mismatch")
	var auctions: Variant = data.get("bankruptcy_auctions", null)
	if typeof(auctions) != TYPE_ARRAY:
		errors.append("invalid bankruptcy auctions")
	else:
		for auction in auctions:
			if typeof(auction) != TYPE_DICTIONARY:
				errors.append("invalid bankruptcy auction entry")
	return {"ok": errors.is_empty(), "errors": errors}


func to_dict() -> Dictionary:
	_sync_state()
	var copy: Dictionary = state.duplicate(true)
	copy["rng_state_text"] = str(_rng.state)
	return copy


func to_json() -> String:
	if _is_companies():
		return JSON.stringify(_canonicalize_json_numbers(to_dict()), "", true, true)
	return JSON.stringify(to_dict())


static func _canonicalize_json_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value:
		return int(value)
	if typeof(value) == TYPE_ARRAY:
		var array_value: Array = value.duplicate(true)
		for index in range(array_value.size()):
			array_value[index] = _canonicalize_json_numbers(array_value[index])
		return array_value
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary_value: Dictionary = value.duplicate(true)
		for key in dictionary_value.keys():
			dictionary_value[key] = _canonicalize_json_numbers(dictionary_value[key])
		return dictionary_value
	return value

static func from_dict(data: Dictionary) -> Richman4GameState:
	var candidate: Dictionary = data.duplicate(true)
	_migrate_news_source_kind(candidate)
	var validation: Dictionary = validate_save(candidate)
	if not bool(validation.get("ok", false)):
		return null
	var game = new()
	game.state = candidate
	if int(game.state.get("version", SAVE_VERSION)) >= GRAPH_SAVE_VERSION:
		game.state = _canonicalize_json_numbers(game.state)
	if game._is_companies():
		OriginalStockMarket.normalize_numbers(game.state.market)
		for player in game.state.get("players", []):
			if typeof(player) == TYPE_DICTIONARY:
				StockAccounting.normalize_player(player, OriginalStockMarket.symbols())
		OriginalStockMarket.normalize_price_events(game.state.event_log)
		OriginalStockMarket.normalize_price_events(game.state.last_event)
		if not bool(validate_save(game.state).get("ok", false)): return null
	game._rng = RandomNumberGenerator.new()
	game._rng.seed = int(game.state.get("seed", 0))
	var rng_text: String = str(game.state.get("rng_state_text", ""))
	game._rng.state = int(rng_text) if rng_text != "" else int(game.state.get("rng_state", 0))
	game._sync_state()
	if game.state.get("phase", "") in ["await_roll", "await_action", "await_route"]:
		game._set_action_options(int(game.state.get("current_player", -1)))
	else:
		game.state["action_options"] = []
	return game


static func _migrate_news_source_kind(data: Dictionary) -> void:
	# Pre-event graph saves classified ordinary type-0/event-2 and event-3
	# roads as unsupported. These structural migrations enable current
	# semantics while retaining every other saved field, including RNG and
	# event history.
	var board: Variant = data.get("board", null)
	if typeof(board) != TYPE_ARRAY:
		return
	for tile_value in board:
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = tile_value
		if int(tile.get("type_and_idx", -1)) == 0 and int(tile.get("event_code", -1)) == 2 and str(tile.get("kind", "")) == "unsupported":
			tile["kind"] = "news"
		elif int(tile.get("type_and_idx", -1)) == 0 and int(tile.get("event_code", -1)) == 3 and str(tile.get("kind", "")) in ["rest", "unsupported"]:
			tile["kind"] = "fate"


func save_to_path(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(to_json())
	file.close()
	return true


static func load_from_path(path: String) -> Richman4GameState:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed)
