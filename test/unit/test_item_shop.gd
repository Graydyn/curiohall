extends GutTest

func _rng() -> RandomNumberGenerator:
    var r := RandomNumberGenerator.new(); r.seed = 11; return r

func test_roll_slot_yields_real_priced_item() -> void:
    var s := ItemShop.new()
    for n in range(1, ItemShop.SLOTS + 1):
        var slot := s.roll_slot(n, _rng())
        assert_true(ConfigDB.properties.has(slot["item"]))
        assert_true(int(n) in ConfigDB.properties[slot["item"]].get("Slot", []))
        assert_eq(int(slot["price"]), int(ConfigDB.properties[slot["item"]]["Price"]))
        assert_eq(int(slot["left"]), int(ConfigDB.properties[slot["item"]].get("ShopCount", 1)))
        assert_false(slot["sold_out"])

func test_fill_populates_all_slots_and_returns_true() -> void:
    var s := ItemShop.new()
    assert_true(s.fill(_rng(), 1000.0))
    for slot in s.slots:
        assert_not_null(slot)
    # already full and not yet refreshing -> no-op returns false
    assert_false(s.fill(_rng(), 1000.0))

func _slot_with_stock(s: ItemShop, stock: int) -> void:
    s.slots[0] = {"item": "205", "price": 4, "left": stock, "sold_out": false}

func test_buy_spends_price_and_grants_one_item() -> void:
    var g := Game.fresh(1000.0, 42)
    _slot_with_stock(g.shop, 5)
    g.wallet.add_coins(100)
    var coins0 := g.wallet.coins
    var stack0 := g.player.reward_stack.size()
    assert_true(g.shop.buy(1, g.wallet, g, 1000.0)["ok"])
    assert_eq(g.wallet.coins, coins0 - 4)
    assert_eq(g.player.reward_stack.size(), stack0 + 1)
    assert_eq(int(g.shop.slots[0]["left"]), 4)
    assert_false(g.shop.slots[0]["sold_out"])

func test_slot_sells_out_after_its_stock() -> void:
    var g := Game.fresh(1000.0, 42)
    _slot_with_stock(g.shop, 2)
    g.wallet.add_coins(100)
    assert_true(g.shop.buy(1, g.wallet, g, 1000.0)["ok"])
    assert_true(g.shop.buy(1, g.wallet, g, 1000.0)["ok"])
    assert_true(g.shop.slots[0]["sold_out"])
    var coins := g.wallet.coins
    assert_eq(g.shop.buy(1, g.wallet, g, 1000.0)["reason"], "sold_out")
    assert_eq(g.wallet.coins, coins)

func test_old_save_slot_gets_stock_from_count() -> void:
    var d := {"slots": [
        {"item": "205", "price": 4, "count": 5, "sold_out": false},
        {"item": "205", "price": 4, "count": 5, "sold_out": true},
        null, null, null, null], "refresh_at": 0.0}
    var s := ItemShop.from_dict(d)
    assert_eq(int(s.slots[0]["left"]), 5)
    assert_eq(int(s.slots[1]["left"]), 0)
    assert_false(s.slots[0].has("count"))

func test_buy_insufficient_coins_rejected_without_spend() -> void:
    var g := Game.fresh(1000.0, 42)
    g.shop.fill(g.rng, 1000.0)
    g.wallet.spend_coins(g.wallet.coins)  # zero coins
    var res := g.shop.buy(1, g.wallet, g, 1000.0)
    assert_false(res["ok"])
    assert_eq(res["reason"], "not_enough_coins")
    assert_eq(g.wallet.coins, 0)

func test_timed_refresh_and_gem_skip() -> void:
    var s := ItemShop.new()
    s.fill(_rng(), 1000.0)
    s.set_refresh(1000.0)  # start a refresh cooldown
    assert_true(s.is_refreshing(1000.0))
    var secs := int(ConfigDB.tuning["shop_refresh_seconds"])
    assert_almost_eq(s.time_to_refresh(1000.0), float(secs), 1.0)
    var w := EnergyWallet.fresh(1000.0); w.add_gems(100)
    assert_true(s.skip_refresh(w, 1000.0))
    assert_eq(w.gems, 100 - int(ConfigDB.tuning["shop_skip_gems"]))
    assert_false(s.is_refreshing(1000.0))

func test_round_trip() -> void:
    var s := ItemShop.new()
    s.fill(_rng(), 1000.0)
    s.slots[0]["sold_out"] = true
    var s2 := ItemShop.from_dict(s.to_dict())
    assert_eq(s2.slots[0]["sold_out"], true)
    assert_eq(s2.slots.size(), ItemShop.SLOTS)
