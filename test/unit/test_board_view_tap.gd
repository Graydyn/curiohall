extends GutTest
## Tapping items on the board: first tap selects, tapping the selected item activates it.

const POS := Vector2i(3, 4)
const FREE := Vector2i(2, 4)   # room for generator/chest drops
const CONSUMABLE := "2501"   # CollectRewards ["gem-1"]
const GENERATOR := "104"
const CHEST := "main_g_chest_new_1"

func _open(g: Game, pos: Vector2i) -> void:
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)

func _setup(type: String = CONSUMABLE) -> Array:
    var g := Game.fresh(1000.0, 42)
    _open(g, POS)
    _open(g, FREE)
    g.board.place(POS, ItemInstance.make(type, 1000.0))
    var bv: BoardView = BoardView.new()
    add_child_autofree(bv)
    bv.setup(g)
    return [g, bv]

func _tap(bv: BoardView, pos: Vector2i) -> void:
    bv._begin_drag(pos)
    bv._end_drag(pos)

func test_first_tap_selects_consumable_without_consuming() -> void:
    var s := _setup()
    var g: Game = s[0]
    var bv: BoardView = s[1]
    _tap(bv, POS)
    assert_eq(bv.selected, POS)
    assert_not_null(g.board.item_at(POS))
    assert_eq(g.board.item_at(POS).type, CONSUMABLE)

func test_second_tap_on_selected_consumable_consumes_it() -> void:
    var s := _setup()
    var g: Game = s[0]
    var bv: BoardView = s[1]
    _tap(bv, POS)
    _tap(bv, POS)
    assert_null(g.board.item_at(POS))
    assert_eq(bv.selected, Vector2i(-1, -1))

func test_selecting_elsewhere_then_tapping_consumable_only_selects() -> void:
    var s := _setup()
    var g: Game = s[0]
    var bv: BoardView = s[1]
    _tap(bv, POS)
    bv.selected = Vector2i(0, 0)
    _tap(bv, POS)
    assert_eq(bv.selected, POS)
    assert_not_null(g.board.item_at(POS))

func _assert_select_then_spawn(type: String) -> BoardView:
    var s := _setup(type)
    var g: Game = s[0]
    var bv: BoardView = s[1]
    _tap(bv, POS)
    assert_eq(bv.selected, POS)
    assert_null(g.board.item_at(FREE), "first tap must not spawn")
    _tap(bv, POS)
    assert_not_null(g.board.item_at(FREE), "second tap spawns")
    return bv

func test_generator_needs_select_then_tap_and_stays_selected() -> void:
    var bv := _assert_select_then_spawn(GENERATOR)
    assert_eq(bv.selected, POS)

func test_chest_needs_select_then_tap() -> void:
    var bv := _assert_select_then_spawn(CHEST)
    assert_eq(bv.selected, Vector2i(-1, -1))
