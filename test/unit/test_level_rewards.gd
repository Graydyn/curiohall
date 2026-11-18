extends GutTest

func test_add_xp_returns_gained_levels() -> void:
    var p := PlayerState.new()
    var c1 := int(ConfigDB.levels[0]["cost"])
    var gained := p.add_xp(c1)
    assert_eq(gained, [1])          # crossed level 1 -> now level 2
    assert_eq(p.level, 2)

func test_add_xp_multi_level() -> void:
    var p := PlayerState.new()
    var big := int(ConfigDB.levels[0]["cost"]) + int(ConfigDB.levels[1]["cost"])
    var gained := p.add_xp(big)
    assert_eq(gained, [1, 2])
    assert_eq(p.level, 3)

func test_level_reward_queues_items_on_reward_stack() -> void:
    var g := Game.fresh(1000.0, 42)
    var on_board := g.board.count_of("104")
    g._grant_level_rewards(g.player.add_xp(int(ConfigDB.levels[0]["cost"])), 1000.0)
    # LevelConfig level-1 rewards contain item "104-1" (a generator) -> queued, not placed
    assert_has(g.player.reward_stack, "104")
    assert_eq(g.board.count_of("104"), on_board)

func test_deliver_order_uses_pipeline() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.level = 5
    g.orders.orders[0] = {"items": {"203": 1}, "coins": 4, "xp": 4, "created_at": 0.0, "type": 1, "refresh_time": 3600}
    # Free a cell first since board starts FULL from the layout (see test_order_book.gd)
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.spawn("203", Vector2i(3, 4))
    var coins0 := g.wallet.coins
    var res := g.deliver_order(0, 1000.0)
    assert_true(res["ok"])
    assert_eq(g.wallet.coins, coins0 + 4)
    assert_eq(g.player.xp, 4)
