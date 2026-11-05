extends GutTest

func _open_cell(g: Game, pos: Vector2i, type: String) -> void:
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)
    g.board.place(pos, ItemInstance.make(type, 1000.0))

func test_tap_collects_currency_token() -> void:
    var g := Game.fresh(1000.0, 42)
    _open_cell(g, Vector2i(1, 3), "2501")  # CollectRewards ["gem-1"]
    var gems0 := g.wallet.gems
    var res: Dictionary = g.tap(Vector2i(1, 3), 1000.0)
    assert_true(res["ok"])
    assert_eq(res["kind"], "collect")
    assert_eq(g.wallet.gems, gems0 + 1)
    assert_null(g.board.item_at(Vector2i(1, 3)))

func test_tap_collects_coin_and_energy_tokens() -> void:
    var g := Game.fresh(1000.0, 42)
    _open_cell(g, Vector2i(1, 3), "2401")  # ["gold-2"]
    var coins0 := g.wallet.coins
    assert_true(g.tap(Vector2i(1, 3), 1000.0)["ok"])
    assert_eq(g.wallet.coins, coins0 + 2)

func test_tap_generator_still_routes() -> void:
    var g := Game.fresh(1000.0, 42)
    _open_cell(g, Vector2i(1, 3), "104")     # generator
    _open_cell(g, Vector2i(1, 4), "201")     # a free-ish neighbor target
    g.board.remove(Vector2i(1, 4))
    g.board.set_state(Vector2i(1, 4), MergeBoard.CellState.OPEN)
    var res: Dictionary = g.tap(Vector2i(1, 3), 1000.0)
    assert_eq(res["kind"], "generator")
    assert_true(res["ok"])

func test_tap_plain_item_not_tappable() -> void:
    var g := Game.fresh(1000.0, 42)
    _open_cell(g, Vector2i(1, 3), "205")  # no CollectRewards, no Spread_Weight
    var res: Dictionary = g.tap(Vector2i(1, 3), 1000.0)
    assert_false(res["ok"])
    assert_eq(res["kind"], "none")
