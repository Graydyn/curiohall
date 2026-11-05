extends GutTest

func test_levels_up_per_level_config() -> void:
    var p := PlayerState.new()
    var cost1 := int(ConfigDB.levels[0]["cost"])   # 30 xp for level 1
    var gained := p.add_xp(cost1)
    assert_eq(gained, [1])
    assert_eq(p.level, 2)

func test_xp_overflow_carries() -> void:
    var p := PlayerState.new()
    p.add_xp(int(ConfigDB.levels[0]["cost"]) + 5)
    assert_eq(p.level, 2)
    assert_eq(p.xp, 5)

func test_inventory_defaults_and_store_limit() -> void:
    var p := PlayerState.new()
    assert_eq(p.slots, 5)
    for i in range(5):
        assert_true(p.store("201"))
    assert_false(p.store("201"))

func test_slot_unlock_costs_gems() -> void:
    var p := PlayerState.new()
    var expected := int(ConfigDB.inventory_cfg["UnlockCost"][p.slots])
    assert_eq(p.next_slot_cost(), expected)
    var w := EnergyWallet.fresh(0.0)
    w.add_gems(100000)
    assert_true(p.unlock_slot(w))
    assert_eq(p.slots, 6)

func test_withdraw() -> void:
    var p := PlayerState.new()
    p.store("201")
    assert_eq(p.withdraw(0), "201")
    assert_eq(p.inventory.size(), 0)
    assert_eq(p.withdraw(5), "")
