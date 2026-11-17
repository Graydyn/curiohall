extends GutTest
## Game.sell pays the item's coin price into the wallet.

const POS := Vector2i(3, 4)

func _game() -> Game:
    var g := Game.fresh(1000.0, 42)
    g.board.remove(POS)
    g.board.set_state(POS, MergeBoard.CellState.OPEN)
    return g

func test_sell_pays_coins_and_clears_cell() -> void:
    var g := _game()
    g.board.place(POS, ItemInstance.make("205", 1000.0))
    var before := g.wallet.coins
    var res := g.sell(POS)
    assert_true(res["ok"])
    assert_eq(res["coins"], 16)
    assert_eq(g.wallet.coins, before + 16)
    assert_null(g.board.item_at(POS))

func test_sell_empty_cell_pays_nothing() -> void:
    var g := _game()
    var before := g.wallet.coins
    assert_false(g.sell(POS)["ok"])
    assert_eq(g.wallet.coins, before)
