extends GutTest

func _game() -> Game:
    var g := Game.fresh(1000.0, 42)
    return g

func test_generator_state_charges_and_recovery() -> void:
    # Worked example from HANDOFF: generator 104, caps 80/240, recovery 2s/30s.
    var gs := GeneratorState.for_type("104", 1000.0)
    assert_eq(gs.charges(1000.0), 80)
    for i in range(80):
        assert_true(gs.consume(1000.0))
    assert_eq(gs.charges(1000.0), 0)
    assert_eq(gs.charges(1002.0), 1)   # 1 charge back after 2 s
    assert_eq(gs.charges(1000.0 + 2.0 * 80 * 10), 80)  # capped

func test_non_generator_has_no_state() -> void:
    assert_null(GeneratorState.for_type("101", 0.0))

func test_tap_spawns_weighted_item_and_spends_energy() -> void:
    var g := _game()
    var pos := Vector2i(6, 8)
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)
    g.board.place(pos, ItemInstance.make("104", 1000.0))
    var drop_cell := Vector2i(5, 8)
    g.board.remove(drop_cell)
    g.board.set_state(drop_cell, MergeBoard.CellState.OPEN)
    var before := g.wallet.energy(1000.0)
    var res := g.tap_generator(pos, 1000.0)
    assert_true(res["ok"])
    assert_eq(res["spawned"][0]["type"], "201")  # 104 only ever drops 201
    assert_eq(g.wallet.energy(1000.0), before - 1)  # Spread_CostEnergy 1

func test_tap_fails_without_energy() -> void:
    var g := _game()
    var pos := Vector2i(6, 8)
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)
    g.board.place(pos, ItemInstance.make("104", 1000.0))
    g.wallet.spend_energy(g.wallet.energy(1000.0), 1000.0)
    var res := g.tap_generator(pos, 1000.0)
    assert_false(res["ok"])
    assert_eq(res["reason"], "no_energy")

func test_tap_on_normal_item_rejected() -> void:
    var g := _game()
    var pos := Vector2i(6, 8)
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)
    g.board.place(pos, ItemInstance.make("201", 1000.0))
    assert_eq(g.tap_generator(pos, 1000.0)["reason"], "not_generator")
