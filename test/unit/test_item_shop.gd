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
        assert_gt(int(slot["count"]), 0)
        assert_false(slot["sold_out"])

func test_fill_populates_all_slots_and_returns_true() -> void:
    var s := ItemShop.new()
    assert_true(s.fill(_rng(), 1000.0))
    for slot in s.slots:
        assert_not_null(slot)
    # already full and not yet refreshing -> no-op returns false
    assert_false(s.fill(_rng(), 1000.0))

func test_buy_spends_coins_grants_and_marks_sold_out() -> void:
    var g := Game.fresh(1000.0, 42)
    g.shop.fill(g.rng, 1000.0)
    # free a board cell so granted items can land
    for p in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 3)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    var n := 1
    var price := int(g.shop.slots[n - 1]["price"])
    g.wallet.add_coins(price + 100)
    var coins0 := g.wallet.coins
    var res := g.shop.buy(n, g.wallet, g, 1000.0)
    assert_true(res["ok"])
    assert_eq(g.wallet.coins, coins0 - price)
    assert_true(g.shop.slots[n - 1]["sold_out"])
    # buying a sold-out slot is rejected without spend
    assert_eq(g.shop.buy(n, g.wallet, g, 1000.0)["reason"], "sold_out")

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
