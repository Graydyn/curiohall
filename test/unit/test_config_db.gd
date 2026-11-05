extends GutTest

func test_items_loaded_by_string_id() -> void:
	assert_true(ConfigDB.items.has("101"))
	assert_eq(ConfigDB.items["101"]["MergedType"], "102")

func test_worked_example_generator_104() -> void:
	var g: Dictionary = ConfigDB.items["104"]
	assert_eq(g["Spread_Weight"], ["201-100"])
	assert_eq(g["Spread_CostEnergy"], 1)
	assert_eq(g["Spread_ItemMaxNumber"], 80)
	assert_eq(g["Spread_StorageMaxNumber"], 240)

func test_board_layout_is_9_rows_of_7() -> void:
	assert_eq(ConfigDB.board_layout.size(), 9)
	for row in ConfigDB.board_layout:
		assert_eq((row as Array).size(), 7)

func test_tuning_loaded() -> void:
	assert_eq(ConfigDB.tuning["energy_max"], 100)

func test_validate_returns_no_errors() -> void:
	assert_eq(ConfigDB.validate(), [])

func test_main_tasks_loaded_and_indexed() -> void:
	assert_eq((ConfigDB.main_tasks[1] as Array).size(), 7)   # day 1 has 7 tasks
	assert_eq(ConfigDB.main_tasks.size(), 282)               # 282 story days
	var row: Dictionary = ConfigDB.main_task_by_key["1_2"]
	assert_eq(int(row["cost"]), 16)
	assert_eq(int(row["area"]), 1)
	assert_true(ConfigDB.area_tasks.has(47))

func test_area_unlocks_loaded() -> void:
	var row: Dictionary = ConfigDB.area_unlocks[3]
	assert_eq(int(row["level"]), 5)
	assert_eq(String(row["condition"]), "TaskCompleted-1_9")

func test_known_vestigial_unlock_condition_is_silent() -> void:
	# Area 3's TaskCompleted-1_9 names a task that no longer exists. It is a known
	# vestigial row, so the shipped config must validate without noise on startup.
	assert_eq(ConfigDB.area_unlock_warnings(), [])

func test_unknown_dangling_unlock_condition_still_warns() -> void:
	# Suppressing the known erratum must not blind the check to a new one.
	var saved: Dictionary = ConfigDB.area_unlocks.duplicate(true)
	ConfigDB.area_unlocks[99] = {"id": 99, "level": 1, "condition": "TaskCompleted-999_1"}
	var warnings := ConfigDB.area_unlock_warnings()
	ConfigDB.area_unlocks = saved
	assert_eq(warnings.size(), 1)
	assert_true(warnings[0].contains("TaskCompleted-999_1"), "warning names the bad condition")

func test_intimacy_tables_loaded() -> void:
	assert_eq(ConfigDB.intimacy_list.size(), 11)
	assert_eq((ConfigDB.intimacy_levels["Cornelia"] as Array).size(), 30)
	assert_eq(int(ConfigDB.intimacy_levels["Cornelia"][0]["Intimacy"]), 36)   # sorted by Level
	assert_eq(int(ConfigDB.intimacy_gifts["flower"]["Coin"]), 40)
	assert_eq(ConfigDB.intimacy_shop.size(), 6)
	assert_eq(ConfigDB.coin_to_gift.size(), 4)
	assert_eq(ConfigDB.intimacy_dialogs.size(), 110)

func test_intimacy_levels_absent_for_unreleased() -> void:
	# Ambrose has no level rows in config; only the 10 released characters do.
	assert_false(ConfigDB.intimacy_levels.has("Ambrose"))

func test_order_special_loaded_sorted() -> void:
	assert_eq(ConfigDB.order_special.size(), 6)
	for i in range(6):
		assert_eq(int(ConfigDB.order_special[i]["Id"]), i + 1)
	assert_eq(String(ConfigDB.order_special[0]["Requirement1"]), "1610")
	assert_eq(String(ConfigDB.order_special[0]["Trigger"]), "taskFinish-2_7")

func test_order_avatars_loaded() -> void:
	var normals_v: Variant = ConfigDB.order_avatars.get("NormalAvatars")
	assert_true(normals_v is Array and (normals_v as Array).size() > 0)
	var specials_v: Variant = ConfigDB.order_avatars.get("SpecialAvatars")
	assert_true(specials_v is Dictionary)
	assert_eq(String((specials_v as Dictionary)["101"]), "Sam")

func test_story_recap_grouped_by_book() -> void:
	assert_eq(ConfigDB.story_recap.size(), 5)
	var b1: Dictionary = ConfigDB.story_recap[1]
	assert_eq(String(b1["task"]), "20_11")
	assert_eq((b1["rows"] as Array).size(), 112)
	var first: Dictionary = (b1["rows"] as Array)[0]
	assert_eq(String(first["Type"]), "title")
	assert_eq(String(first["Content"]), "recap_title_1_1")
	assert_eq(String((ConfigDB.story_recap[5] as Dictionary)["task"]), "52_11")

func test_event_bundle_loaded() -> void:
	var layout: Array = ConfigDB.event_board_layout("dogpark")
	assert_eq(layout.size(), 13)
	assert_eq((layout[0] as Array).size(), 7)
	assert_true(ConfigDB.items.has("pb_dogpark_tar_1"))   # event items merged in
	assert_eq(ConfigDB.event_unlock_level("dogpark"), 12)
	assert_eq(ConfigDB.event_board_layout("nope"), [])

func test_event_paperbox_reward_lookup() -> void:
	# The grid is mostly "0"; find one non-zero cell from config and assert it,
	# plus a known-zero cell and out-of-bounds safety.
	var grid: Array = ConfigDB.event_paper_rewards["dogpark"]
	var found := Vector2i(-1, -1)
	var token := ""
	for y in range(grid.size()):
		for x in range((grid[y] as Array).size()):
			if String((grid[y] as Array)[x]) != "0":
				found = Vector2i(x, y)
				token = String((grid[y] as Array)[x])
	if found != Vector2i(-1, -1):
		assert_eq(ConfigDB.event_paperbox_reward("dogpark", found), token)
	assert_eq(ConfigDB.event_paperbox_reward("dogpark", Vector2i(0, 0)), "" if String((grid[0] as Array)[0]) == "0" else String((grid[0] as Array)[0]))
	assert_eq(ConfigDB.event_paperbox_reward("dogpark", Vector2i(-1, 99)), "")
