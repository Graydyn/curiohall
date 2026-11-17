extends GutTest
## ItemInfo: names, tiers, sources, sell prices and panel lines for board items.

func test_family_name_from_art() -> void:
    assert_eq(ItemInfo.family_name("205"), "Flour")
    assert_eq(ItemInfo.family_name("801"), "Raw Fish")

func test_family_name_falls_back_to_id() -> void:
    assert_eq(ItemInfo.family_name("no_such"), "no_such")

func test_tier_is_position_in_merge_chain() -> void:
    assert_eq(ItemInfo.tier("201"), 1)
    assert_eq(ItemInfo.tier("205"), 5)
    assert_eq(ItemInfo.tier("104"), 4)

func test_sources_are_generator_families() -> void:
    assert_eq(ItemInfo.sources("205"), ["Grocery Bag"])
    assert_eq(ItemInfo.sources("801"), ["Fishing"])   # deduped across 705-711
    assert_eq(ItemInfo.sources("901"), ["Fishing", "Raw Fish"])   # two chains, sorted
    assert_eq(ItemInfo.sources("2401"), [])

func test_sell_price_doubles_per_tier() -> void:
    assert_eq(ItemInfo.sell_price("201"), 1)   # not in shop or orders: formula
    assert_eq(ItemInfo.sell_price("103"), 4)   # pre-generator chain item is plain

func test_sell_price_capped_by_shop_and_order_price() -> void:
    assert_eq(ItemInfo.sell_price("205"), 4)     # min(16, shop 4, order 8)
    assert_eq(ItemInfo.sell_price("212"), 178)   # min(2048, shop 320, order 178)
    assert_eq(ItemInfo.sell_price("903"), 4)     # formula 4 already lowest

func test_no_shop_item_sells_for_more_than_it_costs() -> void:
    for t in ConfigDB.properties:
        var row: Dictionary = ConfigDB.properties[t]
        if not row.get("Slot", []).is_empty() and ItemInfo.is_sellable(t):
            assert_lte(ItemInfo.sell_price(t), int(row["Price"]), t)

func test_specials_are_not_sellable() -> void:
    assert_eq(ItemInfo.sell_price("2501"), 0)                 # consumable
    assert_eq(ItemInfo.sell_price("104"), 0)                  # generator
    assert_eq(ItemInfo.sell_price("main_g_chest_new_1"), 0)   # chest
    assert_false(ItemInfo.is_sellable("2501"))
    assert_true(ItemInfo.is_sellable("205"))

func test_reward_text() -> void:
    assert_eq(ItemInfo.reward_text(["gold-2"]), "2 coins")
    assert_eq(ItemInfo.reward_text(["gem-1"]), "1 gem")
    assert_eq(ItemInfo.reward_text(["gem-3"]), "3 gems")
    assert_eq(ItemInfo.reward_text(["exp-5"]), "5 XP")
    assert_eq(ItemInfo.reward_text(["energy-2", "205-1"]), "2 energy, Flour x1")

func test_lines() -> void:
    var coin := ItemInfo.lines("2401")
    assert_has(coin, "Found in chests")
    assert_has(coin, "Tap twice to collect: 2 coins")
    assert_has(ItemInfo.lines("205"), "Made by: Grocery Bag")
    assert_has(ItemInfo.lines("104"), "Costs 1 energy per tap")
    assert_has(ItemInfo.lines("main_g_chest_new_1"), "Tap twice to open")

func test_family_name_snake_case_art() -> void:
    assert_eq(ItemInfo.family_name("time_skip_1"), "Time Skip")
    assert_eq(ItemInfo.family_name("main_order_chest_s_1"), "Main Order Chest S")

func test_reward_text_special_tokens() -> void:
    assert_eq(ItemInfo.reward_text(["skip-600"]), "time skip (600)")
    assert_eq(ItemInfo.reward_text(["infinite-60"]), "unlimited energy (60)")
