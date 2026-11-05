extends GutTest

func test_shop_tables_loaded() -> void:
	assert_gt(ConfigDB.shop_slots.size(), 0)
	assert_eq(ConfigDB.daily_deals.size(), 3)
	assert_eq(ConfigDB.iap_packs.size(), 6)
	assert_eq(ConfigDB.bundles.size(), 1)

func test_shop_slot_shape() -> void:
	var row: Dictionary = ConfigDB.shop_slots[0]
	assert_true(row.has("ChainId"))
	assert_true(row.has("Slot1Weight"))

func test_iap_pack_shape() -> void:
	assert_eq(ConfigDB.iap_packs[0]["goods"], ["gem-100"])

func test_bundle_shape() -> void:
	var b: Dictionary = ConfigDB.bundles[0]
	assert_eq(b["condition"], "Level-3")
	assert_eq(int(b["buyCount"]), 1)
	assert_eq(int(b["lastDuration"]), 172800)

func test_tuning_constants() -> void:
	assert_eq(int(ConfigDB.tuning["shop_refresh_seconds"]), 3600)
	assert_eq(int(ConfigDB.tuning["shop_skip_gems"]), 30)
	assert_eq(int(ConfigDB.tuning["daily_deals_restock_seconds"]), 86400)

func test_item_property_lookup() -> void:
	assert_true(ConfigDB.properties.has("203"))
	assert_eq(int(ConfigDB.properties["203"]["Price"]), 1)
