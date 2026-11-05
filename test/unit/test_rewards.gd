extends GutTest

func test_parse_currency_kinds() -> void:
    assert_eq(Rewards.parse("gold-2"), {"kind": "coins", "id": "gold", "amount": 2})
    assert_eq(Rewards.parse("gem-15"), {"kind": "gems", "id": "gem", "amount": 15})
    assert_eq(Rewards.parse("energy-100"), {"kind": "energy", "id": "energy", "amount": 100})

func test_parse_item_token() -> void:
    var p: Dictionary = Rewards.parse("main_g_chest_new_1-1")
    assert_eq(p["kind"], "item")
    assert_eq(p["id"], "main_g_chest_new_1")
    assert_eq(p["amount"], 1)

func test_grant_currency_credits_wallet() -> void:
    var g := Game.fresh(1000.0, 42)
    var coins0 := g.wallet.coins
    Rewards.grant("gold-5", g, 1000.0)
    Rewards.grant("gem-3", g, 1000.0)
    Rewards.grant("energy-10", g, 1000.0)  # wallet starts full (100), energy grants overfill past max
    assert_eq(g.wallet.coins, coins0 + 5)
    assert_eq(g.wallet.gems, 3)
    assert_eq(g.wallet.energy(1000.0), 110)

func test_grant_item_spawns_or_stores() -> void:
    var g := Game.fresh(1000.0, 42)
    # Fresh board is full; free one cell so a spawn lands.
    g.board.remove(Vector2i(1, 3))
    g.board.set_state(Vector2i(1, 3), MergeBoard.CellState.OPEN)
    Rewards.grant("205-1", g, 1000.0)
    assert_gt(g.board.count_of("205"), 0)

func test_grant_item_falls_back_to_inventory_when_full() -> void:
    var g := Game.fresh(1000.0, 42)  # board full, no free cell
    var inv0 := g.player.inventory.size()
    Rewards.grant("205-1", g, 1000.0)
    assert_eq(g.player.inventory.size(), inv0 + 1)
    assert_eq(g.player.inventory[-1], "205")

func test_unknown_kind_is_skipped_not_crashed() -> void:
    var g := Game.fresh(1000.0, 42)
    Rewards.grant("mystery-9", g, 1000.0)  # "mystery" is not a currency, treated as item id; not in ConfigDB -> skipped
    pass_test("no crash")

func test_parse_exp_token() -> void:
    var r := Rewards.parse("exp-15")
    assert_eq(r["kind"], "xp")
    assert_eq(r["amount"], 15)

func test_grant_exp_adds_xp_and_level_rewards() -> void:
    var g := Game.fresh(1000.0, 42)
    var cost1 := int(ConfigDB.levels[0]["cost"])
    Rewards.grant("exp-%d" % (cost1 + 3), g, 1000.0)
    assert_eq(g.player.level, 2)   # leveled up, level-1 rewards granted via grant_xp
    assert_eq(g.player.xp, 3)
