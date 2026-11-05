extends Node
## Autoload. Loads all phase-1 config verbatim and validates cross-references.

var items: Dictionary = {}        # "101" -> row
var properties: Dictionary = {}   # "101" -> row
var scores: Dictionary = {}       # "101" -> row
var board_layout: Array = []
var order_random: Array = []
var order_items: Array = []
var order_fixed: Array = []   # tutorial orders, sorted by Id
var paperbox_rewards: Array = []   # [y][x] extra reward token for unboxing that cell; "0" = none
var levels: Array = []
var lucky: Array = []
var inventory_cfg: Dictionary = {}
var tuning: Dictionary = {}
var shop_slots: Array = []
var daily_deals: Array = []
var iap_packs: Array = []
var bundles: Array = []
var main_tasks: Dictionary = {}       # day:int -> Array[rows]
var main_task_by_key: Dictionary = {} # "day_id" -> row
var area_tasks: Dictionary = {}       # area:int -> Array[rows]
var area_unlocks: Dictionary = {}     # area id -> row
var intimacy_list: Array = []          # 11 character rows
var intimacy_levels: Dictionary = {}   # character name -> level rows sorted by Level
var intimacy_gifts: Dictionary = {}    # gift type -> row
var intimacy_shop: Array = []          # 6 shop slot rows
var coin_to_gift: Array = []           # order-coin -> gift-count brackets
var intimacy_dialogs: Array = []
var order_special: Array = []      # 6 sequential special orders, sorted by Id
var order_avatars: Dictionary = {} # OrderAvatarConfig groups (NormalAvatars, SpecialAvatars, ...)
var story_recap: Dictionary = {}   # book:int -> {"task": String, "rows": Array}
var event_boards: Dictionary = {}        # variant -> board layout Array
var event_paper_rewards: Dictionary = {} # variant -> [y][x] unbox-extra grid
var event_scroll: Dictionary = {}        # variant -> scroll row (level gate etc.)
var boost_items: Dictionary = {}   # "MoreLuckyProduce"/"ExtraProduce" -> {type -> row}
var boost_lucky: Dictionary = {}   # "MoreLuckyProduce"/"ExtraLuckyProduce" -> Array

func _ready() -> void:
	load_all()
	var errors := validate()
	if not errors.is_empty():
		var msg := "Config validation failed:\n" + "\n".join(errors)
		push_error(msg)
		assert(errors.is_empty(), msg)

func load_all(dir: String = "res://config/") -> void:
	main_tasks.clear()
	main_task_by_key.clear()
	area_tasks.clear()
	area_unlocks.clear()
	intimacy_levels.clear()
	intimacy_gifts.clear()
	story_recap.clear()
	event_boards.clear()
	event_paper_rewards.clear()
	event_scroll.clear()
	boost_items.clear()
	boost_lucky.clear()
	for row in _read(dir + "ItemModelConfig.json"):
		if row != null: items[String(row["Type"])] = row
	for row in _read(dir + "ItemPropertyConfig.json"):
		if row != null: properties[String(row["Type"])] = row
	for row in _read(dir + "MergeItemScoreConfig.json"):
		if row != null: scores[String(row["item_id"])] = row
	board_layout = _read(dir + "BoardModelConfig.json")
	order_random = _read(dir + "OrderRandomConfig.json")
	order_items = _read(dir + "OrderItemConfig.json")
	order_fixed = _read(dir + "OrderFixedConfig.json")
	order_fixed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["Id"]) < int(b["Id"]))
	paperbox_rewards = _read(dir + "MainPaperboxExtraRewardConfig.json")
	intimacy_list = _read(dir + "CharacterIntimacyListConfig.json")
	for row in _read(dir + "CharacterIntimacyLevelConfig.json"):
		if row == null:
			continue
		var who := String(row["Character"])
		if not intimacy_levels.has(who):
			intimacy_levels[who] = []
		intimacy_levels[who].append(row)
	for who in intimacy_levels:
		(intimacy_levels[who] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["Level"]) < int(b["Level"]))
	for row in _read(dir + "CharacterIntimacyGiftConfig.json"):
		if row != null:
			intimacy_gifts[String(row["Type"])] = row
	intimacy_shop = _read(dir + "CharacterIntimacyShopConfig.json")
	coin_to_gift = _read(dir + "CharacterIntimacyCoinToGiftConfig.json")
	intimacy_dialogs = _read(dir + "CharacterIntimacyDialogConfig.json")
	order_special = _read(dir + "OrderSpecialConfig.json")
	order_special.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["Id"]) < int(b["Id"]))
	order_avatars = _read(dir + "OrderAvatarConfig.json")
	for row in _read(dir + "StoryRecapConfig.json"):
		if row == null:
			continue
		var book := int(row["Book"])
		if not story_recap.has(book):
			story_recap[book] = {"task": String(row["Task"]), "rows": []}
		(story_recap[book]["rows"] as Array).append(row)
	levels = _read(dir + "LevelConfig.json")
	lucky = _read(dir + "LuckyProduceConfig.json")
	inventory_cfg = _read(dir + "InventorySlotConfig.json")
	tuning = _read(dir + "curio_hall_tuning.json")
	shop_slots = _read(dir + "ShopSlotConfig.json")
	daily_deals = _read(dir + "ShopDailyDealsConfig.json")
	iap_packs = _read(dir + "ShopIAPConfig.json")
	bundles = _read(dir + "BundleConfig.json")
	for row in _read(dir + "MainTaskConfig.json"):
		if row == null:
			continue
		var task_day := int(row["day"])
		var task_area := int(row["area"])
		if not main_tasks.has(task_day):
			main_tasks[task_day] = []
		main_tasks[task_day].append(row)
		if not area_tasks.has(task_area):
			area_tasks[task_area] = []
		area_tasks[task_area].append(row)
		main_task_by_key["%d_%d" % [task_day, int(row["id"])]] = row
	for row in _read(dir + "AreaUnlockConfig.json"):
		if row != null:
			area_unlocks[int(row["id"])] = row
	_load_event_variant(dir, "Pureboard", "dogpark")
	var boost_model: Dictionary = _read(dir + "GeneratorBoostItemModelConfig.json")
	for mode in boost_model:
		var by_type: Dictionary = {}
		for row in (boost_model[mode] as Array):
			by_type[String((row as Dictionary)["Type"])] = row
		boost_items[mode] = by_type
	boost_lucky = _read(dir + "GeneratorBoostLuckyProduceConfig.json")

## Loads one live-ops event variant: its items join the global item table
## (ids are family-prefixed and collision-checked), its board/reward/scroll
## tables are stored per variant.
func _load_event_variant(dir: String, family: String, variant: String) -> void:
	for row in _read(dir + family + "ItemModelConfig_" + variant + ".json"):
		if row == null:
			continue
		var id := String(row["Type"])
		if items.has(id):
			push_error("event item id collides with existing item: " + id)
			continue
		items[id] = row
	event_boards[variant] = _read(dir + family + "BoardModelConfig_" + variant + ".json")
	event_paper_rewards[variant] = _read(dir + family + "BoardPaperRewardConfig_" + variant + ".json")
	var scroll_rows: Array = _read(dir + family + "BoardScrollConfig_" + variant + ".json")
	event_scroll[variant] = scroll_rows[0] if scroll_rows.size() > 0 else {}

func paperbox_reward(pos: Vector2i) -> String:
	if pos.y < 0 or pos.y >= paperbox_rewards.size():
		return ""
	var row: Array = paperbox_rewards[pos.y]
	if pos.x < 0 or pos.x >= row.size():
		return ""
	var token := String(row[pos.x])
	return "" if token == "0" else token

func event_board_layout(variant: String) -> Array:
	var v: Variant = event_boards.get(variant)
	return v if v is Array else []

func event_paperbox_reward(variant: String, pos: Vector2i) -> String:
	var grid_v: Variant = event_paper_rewards.get(variant)
	var grid: Array = grid_v if grid_v is Array else []
	if pos.y < 0 or pos.y >= grid.size():
		return ""
	var row: Array = grid[pos.y]
	if pos.x < 0 or pos.x >= row.size():
		return ""
	var token := String(row[pos.x])
	return "" if token == "0" else token

func event_unlock_level(variant: String) -> int:
	var row_v: Variant = event_scroll.get(variant)
	var row: Dictionary = row_v if row_v is Dictionary else {}
	return int(row.get("level", 1))

func boost_item_row(mode: String, type: String) -> Dictionary:
	var by_type: Dictionary = boost_items.get(mode, {})
	return by_type.get(type, {})

func boost_lucky_table(mode: String) -> Array:
	var v: Variant = boost_lucky.get(mode)
	return v if v is Array else []

func is_boost_type(type: String) -> bool:
	return (boost_items.get("MoreLuckyProduce", {}) as Dictionary).has(type)

func is_chest(type: String) -> bool:
	var row: Dictionary = items.get(type, {})
	if not row.has("Spread_Weight"):
		return false
	return int(row.get("Spread_CostEnergy", 0)) == 0 \
		and int(row.get("Spread_ItemRecoveryDuration", 0)) == 0

## Area-unlock conditions that name a task id absent from MainTaskConfig. These are
## vestigial rows in the shipped config, not data we can repair, and they cannot
## affect play: Campaign.is_area_unlocked is only consulted once the player's
## current day is already inside that area, so a condition naming an earlier day is
## satisfied by definition. Keyed by condition string so a NEW dangling condition
## still warns.
const KNOWN_VESTIGIAL_UNLOCK_CONDITIONS := {
	# Area 3 (opens day 8). Day 1 appears to have been re-cut from 9 tasks to 7:
	# the _fire variant of MainTaskConfig still carries 9 day-1 rows, with the two
	# extras renamed to ids 1_pre_1/1_pre_2. Reaching day 8 already requires all of
	# day 1, so this gate never bound anything; only its level 5 half does.
	"TaskCompleted-1_9": true,
}

## Dangling TaskCompleted- conditions in AreaUnlockConfig, minus the known-vestigial
## ones. Split out of validate() so it is directly testable.
func area_unlock_warnings() -> Array[String]:
	var warnings: Array[String] = []
	for area_id in area_unlocks:
		var cond := String(area_unlocks[area_id].get("condition", ""))
		if not cond.begins_with("TaskCompleted-"):
			continue
		if main_task_by_key.has(cond.trim_prefix("TaskCompleted-")):
			continue
		if KNOWN_VESTIGIAL_UNLOCK_CONDITIONS.has(cond):
			continue
		warnings.append("AreaUnlockConfig %s: condition task %s missing; treated as satisfied" % [area_id, cond])
	return warnings

func validate() -> Array[String]:
	var errors: Array[String] = []
	for id in items:
		var row: Dictionary = items[id]
		var merged := String(row.get("MergedType", ""))
		# "#"-bearing MergedType values (e.g. "rb#pack_common_5") are reward-box
		# references, not item ids, and never collide with real item ids, which
		# never contain "#" (see ItemModelConfig.json). Only real item ids are
		# cross-referenced here.
		if merged != "" and not merged.contains("#") and not items.has(merged):
			errors.append("ItemModelConfig %s: MergedType %s missing" % [id, merged])
		for entry in row.get("Spread_Weight", []):
			var target: String = Weighted.parse([entry])[0]["id"]
			if not target.contains("#") and not items.has(target):
				errors.append("ItemModelConfig %s: Spread_Weight target %s missing" % [id, target])
	for r in range(board_layout.size()):
		for cell in board_layout[r]:
			var id := String(cell).get_slice("#", String(cell).count("#"))
			if not items.has(id):
				errors.append("BoardModelConfig row %d: item %s missing" % [r, id])
	for w in area_unlock_warnings():
		push_warning(w)
	for row in intimacy_list:
		var prefs_v: Variant = row.get("PreferredGifts")
		var prefs: Array = prefs_v if prefs_v is Array else []
		for g in prefs:
			if not intimacy_gifts.has(String(g)):
				push_warning("CharacterIntimacyListConfig %s: unknown gift type %s" % [row.get("Name"), g])
	for row in intimacy_shop:
		for g in row.get("Gifts", []):
			if not intimacy_gifts.has(String(g)):
				push_warning("CharacterIntimacyShopConfig slot %s: unknown gift type %s" % [row.get("Slot"), g])
	for row in order_special:
		if not items.has(String(row.get("Requirement1", ""))):
			push_warning("OrderSpecialConfig %s: Requirement1 %s missing" % [row.get("Id"), row.get("Requirement1")])
		var chains_v: Variant = row.get("GeneratorChain")
		var chains: Array = chains_v if chains_v is Array else [chains_v]
		for c in chains:
			var chain := String(c)
			var seed_id := (chain + "_1") if chain.begins_with("sp") else (chain + "01")
			if not items.has(seed_id):
				push_warning("OrderSpecialConfig %s: seed item %s missing" % [row.get("Id"), seed_id])
	for book in story_recap:
		var task_key := String(story_recap[book]["task"])
		if not main_task_by_key.has(task_key):
			push_warning("StoryRecapConfig book %s: task %s missing" % [book, task_key])
	for variant in event_boards:
		var elayout: Array = event_boards[variant]
		for r in range(elayout.size()):
			for cell in elayout[r]:
				var cell_str := String(cell)
				if cell_str == "0":
					continue
				var id := cell_str.get_slice("#", cell_str.count("#"))
				if not items.has(id):
					errors.append("event %s layout row %d: item %s missing" % [variant, r, id])
	return errors

func _read(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		var msg := "missing config file: " + path
		push_error(msg)
		assert(false, msg)
		return null
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data == null:
		var msg := "bad JSON in " + path
		push_error(msg)
		assert(false, msg)
		return null
	return _normalize_numbers(data)

## JSON.parse_string returns TYPE_FLOAT for every JSON number. Recursively
## downcast any whole-number float to int so config consumers get the int
## contract the source data actually intends; genuinely fractional floats
## (and strings/bools) pass through untouched.
func _normalize_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _normalize_numbers(value[key])
		return out
	elif value is Array:
		var out: Array = []
		for item in value:
			out.append(_normalize_numbers(item))
		return out
	elif value is float and value == floor(value) and is_finite(value):
		return int(value)
	return value
