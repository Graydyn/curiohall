extends GutTest

func _place_chest(g: Game, pos: Vector2i, type: String, now: float) -> void:
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)
    g.board.place(pos, ItemInstance.make(type, now))

func test_is_chest_predicate() -> void:
    assert_true(ConfigDB.is_chest("main_g_chest_new_1"))  # cost 0, no recovery
    assert_false(ConfigDB.is_chest("104"))                # generator: recharges
    assert_false(ConfigDB.is_chest("205"))                # plain item

func test_item_instance_attaches_chest_not_generator() -> void:
    var it := ItemInstance.make("main_g_chest_new_1", 1000.0)
    assert_not_null(it.chest)
    assert_null(it.gen)
    var gen := ItemInstance.make("104", 1000.0)
    assert_not_null(gen.gen)
    assert_null(gen.chest)

func test_chest_dispenses_up_to_budget_then_spent() -> void:
    # main_g_chest_new_1: Spread_ItemMaxNumber 5, weight ["2401-2","2402-3"], no open duration
    var cs := ChestState.for_type("main_g_chest_new_1", 1000.0)
    var rng := RandomNumberGenerator.new(); rng.seed = 1
    assert_eq(cs.remaining(), 5)
    var dispensed: Array[String] = []
    for i in range(5):
        assert_true(cs.can_open(1000.0))
        dispensed.append(cs.open(1000.0, rng))
    assert_eq(cs.remaining(), 0)
    assert_true(cs.is_spent())
    assert_false(cs.can_open(1000.0))
    assert_eq(cs.open(1000.0, rng), "")
    for d in dispensed:
        assert_true(d == "2401" or d == "2402")

func test_timed_chest_gates_and_skips() -> void:
    # main_t_chest_new_1: Spread_OpenDuration 120, SpeedUpCost 2
    var cs := ChestState.for_type("main_t_chest_new_1", 1000.0)
    var rng := RandomNumberGenerator.new(); rng.seed = 1
    assert_false(cs.can_open(1000.0))                 # must wait 120s
    assert_almost_eq(cs.seconds_to_open(1000.0), 120.0, 0.01)
    assert_true(cs.can_open(1000.0 + 120.0))
    var w := EnergyWallet.fresh(1000.0); w.add_gems(10)
    assert_true(cs.skip_open(w, 1000.0))              # pay 2 gems to skip
    assert_eq(w.gems, 8)
    assert_true(cs.can_open(1000.0))

func test_game_tap_opens_chest_and_removes_when_spent() -> void:
    var g := Game.fresh(1000.0, 42)
    _place_chest(g, Vector2i(1, 3), "main_g_chest_new_1", 1000.0)
    # free neighbors so dispensed tokens have somewhere to land
    for p in [Vector2i(1, 4), Vector2i(2, 3), Vector2i(0, 3), Vector2i(2, 4), Vector2i(0, 4)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    for i in range(5):
        var res := g.tap(Vector2i(1, 3), 1000.0)
        assert_eq(res["kind"], "chest")
        assert_true(res["ok"])
    # 6th tap: chest is spent and already removed from the board
    assert_null(g.board.item_at(Vector2i(1, 3)))

func test_chest_survives_save() -> void:
    var g := Game.fresh(1000.0, 42)
    _place_chest(g, Vector2i(1, 3), "main_g_chest_new_1", 1000.0)
    for p in [Vector2i(1, 4), Vector2i(2, 3)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    g.tap(Vector2i(1, 3), 1000.0)  # dispense one, budget now 4
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.board.item_at(Vector2i(1, 3)).chest.remaining(), 4)
