extends GutTest
## The item info overlay: title, info lines, and the Sell button.

const POS := Vector2i(3, 4)

func _setup(type: String) -> Array:
    var g := Game.fresh(1000.0, 42)
    g.board.remove(POS)
    g.board.set_state(POS, MergeBoard.CellState.OPEN)
    g.board.place(POS, ItemInstance.make(type, 1000.0))
    var p := InfoPanel.new()
    add_child_autofree(p)
    p.setup(g)
    p.open(POS)
    return [g, p]

func test_shows_title_and_sell_price() -> void:
    var p: InfoPanel = _setup("205")[1]
    assert_true(p.visible)
    assert_eq(p._title.text, "Flour - Tier 5")
    assert_true(p._sell_btn.visible)
    assert_eq(p._sell_btn.text, "Sell (16 coins)")

func test_sell_pays_and_closes() -> void:
    var s := _setup("205")
    var g: Game = s[0]
    var p: InfoPanel = s[1]
    watch_signals(p)
    var before := g.wallet.coins
    p._sell_btn.pressed.emit()
    assert_null(g.board.item_at(POS))
    assert_eq(g.wallet.coins, before + 16)
    assert_signal_emitted(p, "sold")
    assert_false(p.visible)

func test_consumable_has_no_sell_button() -> void:
    var p: InfoPanel = _setup("2501")[1]
    assert_false(p._sell_btn.visible)

func test_sell_after_item_gone_is_noop() -> void:
    var s := _setup("205")
    var g: Game = s[0]
    var p: InfoPanel = s[1]
    watch_signals(p)
    g.board.remove(POS)
    p._sell_btn.pressed.emit()
    assert_signal_not_emitted(p, "sold")
    assert_false(p.visible)
