extends GutTest

func test_shop_tables_loaded() -> void:
	assert_gt(ConfigDB.shop_slots.size(), 0)
	assert_eq(ConfigDB.daily_deals.size(), 3)

func test_shop_slot_shape() -> void:
	var row: Dictionary = ConfigDB.shop_slots[0]
	assert_true(row.has("ChainId"))
	assert_true(row.has("Slot1Weight"))

func test_tuning_constants() -> void:
	assert_eq(int(ConfigDB.tuning["shop_refresh_seconds"]), 3600)
	assert_eq(int(ConfigDB.tuning["shop_skip_gems"]), 30)
	assert_eq(int(ConfigDB.tuning["daily_deals_restock_seconds"]), 86400)

func test_item_property_lookup() -> void:
	assert_true(ConfigDB.properties.has("203"))
	assert_eq(int(ConfigDB.properties["203"]["Price"]), 1)
