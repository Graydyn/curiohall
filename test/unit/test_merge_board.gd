extends GutTest

var board: MergeBoard

func before_each() -> void:
    board = MergeBoard.new()

func test_merge_advances_tier() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    board.place(Vector2i(1, 0), ItemInstance.make("101"))
    assert_true(board.can_merge(Vector2i(0, 0), Vector2i(1, 0)))
    assert_eq(board.merge(Vector2i(0, 0), Vector2i(1, 0)), "")
    assert_eq(board.item_at(Vector2i(1, 0)).type, "102")
    assert_null(board.item_at(Vector2i(0, 0)))

func test_merge_rejects_mismatch_and_chain_top() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    board.place(Vector2i(1, 0), ItemInstance.make("102"))
    assert_eq(board.merge(Vector2i(0, 0), Vector2i(1, 0)), "mismatch")
    var top_id := ""
    for id in ConfigDB.items:
        if String(ConfigDB.items[id].get("MergedType", "")) == "":
            top_id = id
            break
    board.place(Vector2i(2, 0), ItemInstance.make(top_id))
    board.place(Vector2i(3, 0), ItemInstance.make(top_id))
    assert_eq(board.merge(Vector2i(2, 0), Vector2i(3, 0)), "chain_top")

func test_full_chain_walk_101_to_top() -> void:
    var id := "101"
    var steps := 0
    while String(ConfigDB.items[id].get("MergedType", "")) != "":
        board.place(Vector2i(0, 0), ItemInstance.make(id))
        board.place(Vector2i(1, 0), ItemInstance.make(id))
        assert_eq(board.merge(Vector2i(0, 0), Vector2i(1, 0)), "")
        id = board.item_at(Vector2i(1, 0)).type
        board.remove(Vector2i(1, 0))
        steps += 1
    assert_gt(steps, 5)

func test_move_and_occupied() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    board.place(Vector2i(1, 0), ItemInstance.make("102"))
    assert_eq(board.move(Vector2i(0, 0), Vector2i(2, 2)), "")
    assert_eq(board.item_at(Vector2i(2, 2)).type, "101")
    assert_eq(board.move(Vector2i(2, 2), Vector2i(1, 0)), "occupied")

func test_sell_uses_selling_price_and_rejects_zero() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("103"))
    var res := board.sell(Vector2i(0, 0))
    assert_true(res["ok"])
    assert_eq(res["coins"], 1)
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    assert_false(board.sell(Vector2i(0, 0))["ok"])

func test_spiral_spawn_prefers_near_cell() -> void:
    var pos := board.spawn("201", Vector2i(3, 4))
    assert_eq(pos, Vector2i(3, 4))
    var pos2 := board.spawn("201", Vector2i(3, 4))
    assert_true(pos2.distance_squared_to(Vector2i(3, 4)) <= 2)

func test_spawn_returns_minus_one_when_full() -> void:
    for x in range(MergeBoard.WIDTH):
        for y in range(MergeBoard.HEIGHT):
            board.place(Vector2i(x, y), ItemInstance.make("101"))
    assert_eq(board.spawn("201", Vector2i(0, 0)), Vector2i(-1, -1))

func test_covered_cells_reject_interaction() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    board.set_state(Vector2i(0, 0), MergeBoard.CellState.COVERED)
    board.place(Vector2i(1, 0), ItemInstance.make("101"))
    assert_eq(board.merge(Vector2i(0, 0), Vector2i(1, 0)), "not_open")
    assert_eq(board.move(Vector2i(0, 0), Vector2i(2, 0)), "not_open")

func test_self_merge_is_rejected() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    assert_eq(board.merge(Vector2i(0, 0), Vector2i(0, 0)), "mismatch")
    assert_eq(board.item_at(Vector2i(0, 0)).type, "101")

func test_merge_rejects_reward_box_chain_top() -> void:
    var reward_box_id := ""
    for id in ConfigDB.items:
        var merged := String(ConfigDB.items[id].get("MergedType", ""))
        if "#" in merged:
            reward_box_id = id
            break
    assert_ne(reward_box_id, "")
    board.place(Vector2i(0, 0), ItemInstance.make(reward_box_id))
    board.place(Vector2i(1, 0), ItemInstance.make(reward_box_id))
    assert_eq(board.merge(Vector2i(0, 0), Vector2i(1, 0)), "chain_top")
    assert_eq(board.item_at(Vector2i(0, 0)).type, reward_box_id)
    assert_eq(board.item_at(Vector2i(1, 0)).type, reward_box_id)

func test_merge_onto_covered_matching_item_clears_web() -> void:
    var board := MergeBoard.new()
    board.place(Vector2i(0, 0), ItemInstance.make("201"))
    board.place(Vector2i(1, 0), ItemInstance.make("201"))
    board.set_state(Vector2i(1, 0), MergeBoard.CellState.COVERED)
    assert_eq(board.merge(Vector2i(0, 0), Vector2i(1, 0)), "")
    assert_eq(board.item_at(Vector2i(1, 0)).type, "202")
    assert_eq(board.state_at(Vector2i(1, 0)), MergeBoard.CellState.OPEN)

func test_merge_onto_boxed_target_rejected() -> void:
    var board := MergeBoard.new()
    board.place(Vector2i(0, 0), ItemInstance.make("201"))
    board.place(Vector2i(1, 0), ItemInstance.make("201"))
    board.set_state(Vector2i(1, 0), MergeBoard.CellState.BOXED)
    assert_eq(board.merge(Vector2i(0, 0), Vector2i(1, 0)), "not_open")

func test_merge_onto_covered_mismatch_rejected() -> void:
    var board := MergeBoard.new()
    board.place(Vector2i(0, 0), ItemInstance.make("201"))
    board.place(Vector2i(1, 0), ItemInstance.make("202"))
    board.set_state(Vector2i(1, 0), MergeBoard.CellState.COVERED)
    assert_eq(board.merge(Vector2i(0, 0), Vector2i(1, 0)), "mismatch")

func test_shock_unboxes_target_neighbors_only_and_skips_cobwebs() -> void:
    var board := MergeBoard.new()
    board.place(Vector2i(0, 0), ItemInstance.make("201"))   # source
    board.place(Vector2i(3, 0), ItemInstance.make("201"))   # target
    for setup in [[Vector2i(0, 1), MergeBoard.CellState.BOXED],    # source neighbor: must stay boxed
            [Vector2i(3, 1), MergeBoard.CellState.BOXED],          # target neighbor: unboxes to covered
            [Vector2i(2, 0), MergeBoard.CellState.COVERED]]:       # target neighbor: cobwebs ignore shocks
        board.place(setup[0], ItemInstance.make("301"))
        board.set_state(setup[0], setup[1])
    assert_eq(board.merge(Vector2i(0, 0), Vector2i(3, 0)), "")
    assert_eq(board.state_at(Vector2i(0, 1)), MergeBoard.CellState.BOXED)
    assert_eq(board.state_at(Vector2i(3, 1)), MergeBoard.CellState.COVERED)
    assert_eq(board.state_at(Vector2i(2, 0)), MergeBoard.CellState.COVERED)

func test_custom_dimensions_bounds_and_spawn() -> void:
    var board := MergeBoard.new()
    board.width = 7
    board.height = 14
    assert_true(board.in_bounds(Vector2i(6, 13)))
    assert_false(board.in_bounds(Vector2i(7, 13)))
    assert_false(board.in_bounds(Vector2i(6, 14)))
    # spawn near the bottom row of the taller board works
    assert_eq(board.spawn("201", Vector2i(0, 13)), Vector2i(0, 13))

func test_dimensions_roundtrip() -> void:
    var board := MergeBoard.new()
    board.width = 7
    board.height = 14
    board.place(Vector2i(3, 13), ItemInstance.make("201"))
    var b2 := MergeBoard.from_dict(board.to_dict())
    assert_eq(b2.width, 7)
    assert_eq(b2.height, 14)
    assert_eq(b2.item_at(Vector2i(3, 13)).type, "201")

func test_default_dimensions_unchanged() -> void:
    var board := MergeBoard.new()
    assert_eq(board.width, MergeBoard.WIDTH)
    assert_eq(board.height, MergeBoard.HEIGHT)
    assert_false(board.in_bounds(Vector2i(0, 9)))
