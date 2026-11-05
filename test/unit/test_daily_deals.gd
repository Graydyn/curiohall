extends GutTest

func _free_cells(g: Game) -> void:
    for p in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 3), Vector2i(2, 4)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)

func test_deals_reflect_config() -> void:
    var d := DailyDeals.new()
    var list := d.deals()
    assert_eq(list.size(), 3)
    # deal 1: 25 gems, deal 2: 10 gems + ad, deal 3: free
    var by_id := {}
    for dl in list: by_id[int(dl["id"])] = dl
    assert_eq(int(by_id[1]["cost_gems"]), 25)
    assert_eq(int(by_id[2]["cost_gems"]), 10)
    assert_true(by_id[2]["is_ad"])
    assert_eq(int(by_id[3]["cost_gems"]), 0)

func test_buy_spends_gems_grants_and_decrements_stock() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    g.wallet.add_gems(100)
    var gems0 := g.wallet.gems
    var res := g.deals.buy(1, g.wallet, g, 1000.0)   # 25 gems
    assert_true(res["ok"])
    assert_eq(g.wallet.gems, gems0 - 25)
    assert_eq(int(g.deals.stock[1]), 0)              # leftCount was 1
    assert_eq(g.deals.buy(1, g.wallet, g, 1000.0)["reason"], "out_of_stock")

func test_buy_free_deal_costs_nothing() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    var gems0 := g.wallet.gems
    assert_true(g.deals.buy(3, g.wallet, g, 1000.0)["ok"])  # free
    assert_eq(g.wallet.gems, gems0)

func test_buy_insufficient_gems_rejected_without_spend() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    g.wallet.spend_gems(g.wallet.gems)  # zero
    var res := g.deals.buy(1, g.wallet, g, 1000.0)
    assert_false(res["ok"])
    assert_eq(res["reason"], "not_enough_gems")

func test_restock_after_24h() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    g.wallet.add_gems(100)
    g.deals.buy(1, g.wallet, g, 1000.0)
    assert_eq(int(g.deals.stock[1]), 0)
    g.deals.tick(1000.0)                 # first tick: arms restock_at, no restock
    assert_eq(int(g.deals.stock[1]), 0)  # still sold out
    var secs := int(ConfigDB.tuning["daily_deals_restock_seconds"])
    g.deals.tick(1000.0 + secs + 1.0)    # second tick past 24h: restocks
    assert_eq(int(g.deals.stock[1]), 1)

func test_round_trip() -> void:
    var d := DailyDeals.new()
    d.stock[1] = 0
    var d2 := DailyDeals.from_dict(d.to_dict())
    assert_eq(int(d2.stock[1]), 0)
