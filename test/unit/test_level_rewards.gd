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

func test_level_reward_grants_chest_onto_board() -> void:
    var g := Game.fresh(1000.0, 42)
    # free some cells so granted items/chests can land
    for p in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 3), Vector2i(2, 4)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    # level 1 rewards include a chest/item token per LevelConfig; drive a level-up
    g._grant_level_rewards(g.player.add_xp(int(ConfigDB.levels[0]["cost"])), 1000.0)
    # LevelConfig level-1 rewards contain item "104-1" (a generator) -> now on board
    assert_gt(g.board.count_of("104"), 0)

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
