extends GutTest
## The reward stack button on the board's inventory panel.

func _panel(g: Game) -> InventoryPanel:
    var p := InventoryPanel.new()
    add_child_autofree(p)
    var bv: BoardView = autofree(BoardView.new())
    p.setup(g, bv)
    return p

func test_button_disabled_when_stack_empty() -> void:
    var p := _panel(Game.fresh(1000.0, 42))
    assert_true(p._reward_btn.disabled)

func test_button_shows_count_and_places_on_press() -> void:
    var g := Game.fresh(1000.0, 42)
    var p := _panel(g)
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    Rewards.grant("205-2", g, 1000.0)
    assert_false(p._reward_btn.disabled)
    assert_string_contains(p._reward_btn.text, "(2)")
    p._reward_btn.pressed.emit()
    assert_eq(g.board.item_at(Vector2i(3, 4)).type, "205")
    assert_string_contains(p._reward_btn.text, "(1)")

func test_board_full_press_emits_rejection() -> void:
    var g := Game.fresh(1000.0, 42)   # board full
    var p := _panel(g)
    watch_signals(p)
    Rewards.grant("205-1", g, 1000.0)
    p._reward_btn.pressed.emit()
    assert_signal_emitted_with_parameters(p, "action_rejected", ["board_full"])
    assert_eq(g.player.reward_stack.size(), 1)

func test_panel_fits_below_board_on_screen() -> void:
    var g := Game.fresh(1000.0, 42)
    var p := _panel(g)
    Rewards.grant("205-1", g, 1000.0)
    g.player.store("201")
    # main.tscn puts the panel at y=1140 on a 1280-tall viewport.
    var h := p.get_combined_minimum_size().y
    gut.p("inventory panel min height: %s" % h)
    assert_lte(h, 1280.0 - 1140.0)
