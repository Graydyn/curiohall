extends GutTest
## Idle merge hint: the board finds a legal merge and the view bounces it.

var board: MergeBoard

func before_each() -> void:
    board = MergeBoard.new()

func _top_id() -> String:
    for id in ConfigDB.items:
        if String(ConfigDB.items[id].get("MergedType", "")) == "":
            return id
    return ""

func test_no_pair_on_empty_board() -> void:
    assert_eq(board.find_merge_pair(), [])

func test_finds_matching_open_pair() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    board.place(Vector2i(3, 2), ItemInstance.make("102"))
    board.place(Vector2i(5, 5), ItemInstance.make("101"))
    var pair := board.find_merge_pair()
    assert_eq(pair.size(), 2)
    assert_true(board.can_merge(pair[0], pair[1]))

func test_ignores_chain_top_pairs() -> void:
    var top := _top_id()
    board.place(Vector2i(0, 0), ItemInstance.make(top))
    board.place(Vector2i(1, 0), ItemInstance.make(top))
    assert_eq(board.find_merge_pair(), [])

func test_covered_item_is_a_target_only() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    board.place(Vector2i(1, 0), ItemInstance.make("101"))
    board.set_state(Vector2i(0, 0), MergeBoard.CellState.COVERED)
    assert_eq(board.find_merge_pair(), [Vector2i(1, 0), Vector2i(0, 0)])
    board.set_state(Vector2i(1, 0), MergeBoard.CellState.COVERED)
    assert_eq(board.find_merge_pair(), [], "two veiled items cannot merge")

func test_boxed_items_are_ignored() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    board.place(Vector2i(1, 0), ItemInstance.make("101"))
    board.set_state(Vector2i(0, 0), MergeBoard.CellState.BOXED)
    assert_eq(board.find_merge_pair(), [])

func _view_with_pair() -> BoardView:
    var g := Game.fresh(1000.0, 42)
    for y in range(g.board.height):
        for x in range(g.board.width):
            g.board.remove(Vector2i(x, y))
            g.board.set_state(Vector2i(x, y), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(1, 1), ItemInstance.make("101"))
    g.board.place(Vector2i(4, 4), ItemInstance.make("101"))
    var bv: BoardView = BoardView.new()
    add_child_autofree(bv)
    bv.setup(g)
    return bv

func test_hint_starts_after_idle_delay() -> void:
    var bv := _view_with_pair()
    bv._process(BoardView.HINT_DELAY - 0.1)
    assert_eq(bv.hint_pair, [])
    bv._process(0.2)
    assert_eq(bv.hint_pair.size(), 2)

func test_input_cancels_hint_and_restores_positions() -> void:
    var bv := _view_with_pair()
    bv._process(BoardView.HINT_DELAY + 0.1)
    assert_eq(bv.hint_pair.size(), 2)
    var ev := InputEventMouseButton.new()
    ev.pressed = true
    bv._input(ev)
    assert_eq(bv.hint_pair, [])
    assert_eq(bv._views[Vector2i(1, 1)].position, bv._cell_center(Vector2i(1, 1)))
    bv._process(BoardView.HINT_DELAY - 0.1)
    assert_eq(bv.hint_pair, [], "idle timer restarted")

func test_no_hint_while_input_disabled() -> void:
    var bv := _view_with_pair()
    bv.input_enabled = false
    bv._process(BoardView.HINT_DELAY + 1.0)
    assert_eq(bv.hint_pair, [])
