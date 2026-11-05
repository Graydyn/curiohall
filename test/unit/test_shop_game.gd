extends GutTest

func before_each() -> void:
    SaveManager.path = "user://test_save.json"
    SaveManager.corrupt_path = "user://test_save.corrupt.json"

func after_each() -> void:
    for p in [SaveManager.path, SaveManager.corrupt_path]:
        if FileAccess.file_exists(p):
            DirAccess.remove_absolute(p)
    SaveManager.path = "user://save.json"
    SaveManager.corrupt_path = "user://save.corrupt.json"

func _free_cells(g: Game) -> void:
    for p in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 3), Vector2i(2, 4), Vector2i(0, 3)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)

func test_fresh_game_has_shop_surfaces() -> void:
    var g := Game.fresh(1000.0, 42)
    assert_not_null(g.shop)
    assert_not_null(g.deals)
    assert_not_null(g.iap)
    # shop filled at fresh
    for slot in g.shop.slots:
        assert_not_null(slot)

func test_buy_shop_slot_via_game() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    var price := int(g.shop.slots[0]["price"])
    g.wallet.add_coins(price + 50)
    assert_true(g.buy_shop_slot(1, 1000.0)["ok"])
    assert_true(g.shop.slots[0]["sold_out"])

func test_tick_shop_starts_and_completes_refresh() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    g.wallet.add_coins(1000000)
    for n in range(1, ItemShop.SLOTS + 1):
        g.buy_shop_slot(n, 1000.0)   # sell out all slots
    g.tick_shop(1000.0)              # all sold out -> start refresh cooldown
    assert_true(g.shop.is_refreshing(1000.0))
    var secs := int(ConfigDB.tuning["shop_refresh_seconds"])
    g.tick_shop(1000.0 + secs + 1.0) # cooldown elapsed -> re-roll
    assert_false(g.shop.is_refreshing(1000.0 + secs + 1.0))
    for slot in g.shop.slots:
        assert_not_null(slot)
        assert_false(slot["sold_out"])

func test_skip_shop_refresh_insufficient_gems() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.add_coins(1000000)
    for n in range(1, ItemShop.SLOTS + 1):
        g.buy_shop_slot(n, 1000.0)
    g.tick_shop(1000.0)
    g.wallet.spend_gems(g.wallet.gems)
    assert_eq(g.skip_shop_refresh(1000.0)["reason"], "not_enough_gems")

func test_skip_shop_refresh_not_refreshing() -> void:
    var g := Game.fresh(1000.0, 42)
    assert_false(g.shop.is_refreshing(1000.0))
    var res := g.skip_shop_refresh(1000.0)
    assert_false(res["ok"])
    assert_eq(res["reason"], "not_refreshing")

func test_save_round_trip_preserves_shop_state() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    g.wallet.add_coins(1000)
    g.buy_shop_slot(1, 1000.0)
    g.wallet.add_gems(100)
    g.buy_daily_deal(1, 1000.0)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.to_dict()["save_version"], 10)
    assert_true(g2.shop.slots[0]["sold_out"])
    assert_eq(int(g2.deals.stock[1]), 0)

func test_save_and_load_through_manager() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.add_gems(5)
    SaveManager.save(g)
    var g2 := SaveManager.load_game()
    assert_not_null(g2)
    assert_eq(g2.wallet.gems, 5)
