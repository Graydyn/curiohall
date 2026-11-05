extends GutTest
## GeneratorBoost config families are
## queryable by mode + type. 32 boosted generator types; 104 is not one.

func test_boost_item_rows_load_both_modes() -> void:
    var more: Dictionary = ConfigDB.boost_item_row("MoreLuckyProduce", "105")
    assert_eq(String(more["MergedType"]), "106")
    # MoreLuckyProduce 105 folds the 202 weight away: ["201-37", "301-5"]
    assert_eq((more["Spread_Weight"] as Array).size(), 2)
    var extra: Dictionary = ConfigDB.boost_item_row("ExtraProduce", "105")
    assert_eq((extra["Spread_Weight"] as Array).size(), 3)  # identical to base
    assert_eq(ConfigDB.boost_item_row("MoreLuckyProduce", "104"), {})

func test_boost_lucky_tables_load_both_modes() -> void:
    var more: Array = ConfigDB.boost_lucky_table("MoreLuckyProduce")
    assert_eq(more.size(), 10)
    var row0: Dictionary = more[0]
    assert_eq(int((row0["lucky_chance"] as Array)[0]), 25)   # boosted 1/25
    var extra: Array = ConfigDB.boost_lucky_table("ExtraLuckyProduce")
    var erow0: Dictionary = extra[0]
    assert_eq(int((erow0["lucky_chance"] as Array)[0]), 60)  # base-rate 1/60
    assert_eq(ConfigDB.boost_lucky_table("nope"), [])

func test_boost_type_membership() -> void:
    assert_true(ConfigDB.is_boost_type("105"))
    assert_true(ConfigDB.is_boost_type("1711"))
    assert_false(ConfigDB.is_boost_type("104"))
    assert_false(ConfigDB.is_boost_type("101"))

func test_boost_tuning_keys_present() -> void:
    assert_eq(int(ConfigDB.tuning["boost_duration_seconds"]), 259200)
    assert_eq((ConfigDB.tuning["boost_tasks"] as Array).size(), 4)
    assert_eq((ConfigDB.tuning["boost_buffs"] as Array).size(), 4)
    assert_eq(String((ConfigDB.tuning["boost_buffs"] as Array)[0]), "moreLuckyProduce")
