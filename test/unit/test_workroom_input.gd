extends GutTest
## Drags on the Workroom board must survive the GUI layer: BoardView reads
## _unhandled_input, so no full-rect Control above it may swallow presses.

const TEST_PATH := "user://test_workroom_input.json"
const TEST_CORRUPT_PATH := "user://test_workroom_input.corrupt.json"

func before_all() -> void:
    SaveManager.path = TEST_PATH
    SaveManager.corrupt_path = TEST_CORRUPT_PATH

func after_all() -> void:
    for p in [TEST_PATH, TEST_CORRUPT_PATH]:
        if FileAccess.file_exists(p):
            DirAccess.remove_absolute(p)
    SaveManager.path = "user://save.json"
    SaveManager.corrupt_path = "user://save.corrupt.json"

func _boot() -> Node:
    if FileAccess.file_exists(TEST_PATH):
        DirAccess.remove_absolute(TEST_PATH)
    var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
    # Own viewport so GUT's runner UI (full-window Controls in the root
    # viewport) can't sit over the game and eat the pointer.
    var sv := SubViewport.new()
    sv.size = Vector2i(720, 1280)
    add_child_autofree(sv)
    sv.add_child(main)
    await wait_process_frames(2)
    while main.home.story_player.is_playing():
        main.home.story_player.skip()
    return main

func _mouse_button(pos: Vector2, pressed: bool) -> InputEventMouseButton:
    var e := InputEventMouseButton.new()
    e.button_index = MOUSE_BUTTON_LEFT
    e.pressed = pressed
    e.position = pos
    e.global_position = pos
    if pressed:
        e.button_mask = MOUSE_BUTTON_MASK_LEFT
    return e

func _motion(pos: Vector2) -> InputEventMouseMotion:
    var e := InputEventMouseMotion.new()
    e.position = pos
    e.global_position = pos
    e.button_mask = MOUSE_BUTTON_MASK_LEFT
    return e

func test_drag_merges_items_through_gui_routing() -> void:
    var main := await _boot()
    var home: HomeScreen = main.home
    home.open_workroom()
    await wait_process_frames(2)
    var bv: BoardView = home.workroom.board_view
    assert_true(bv.input_enabled, "board input enabled in workroom")
    # Starting layout has two open "101" at (1,3) and (1,4).
    var a := Vector2i(1, 3)
    var b := Vector2i(1, 4)
    assert_eq(bv.board.item_at(a).type, "101")
    assert_eq(bv.board.item_at(b).type, "101")
    var from_pt := bv.get_global_transform() * bv._cell_center(a)
    var to_pt := bv.get_global_transform() * bv._cell_center(b)
    var vp: Viewport = main.get_viewport()
    vp.push_input(_motion(from_pt), true)
    await wait_process_frames(1)
    vp.push_input(_mouse_button(from_pt, true), true)
    await wait_process_frames(1)
    vp.push_input(_motion((from_pt + to_pt) / 2.0), true)
    vp.push_input(_motion(to_pt), true)
    await wait_process_frames(1)
    vp.push_input(_mouse_button(to_pt, false), true)
    await wait_process_frames(1)
    assert_null(bv.board.item_at(a), "dragged item left its cell")
    assert_eq(bv.board.item_at(b).type, "102", "the pair merged")

## Merge with main: storage and item-info panels live in the Workroom, and
## Back closes them before leaving the screen.
func test_storage_and_info_panels_wired_and_back_closes_them() -> void:
    var main := await _boot()
    var home: HomeScreen = main.home
    home.open_workroom()
    await wait_process_frames(1)
    var wr: Workroom = home.workroom
    assert_not_null(wr.storage_panel)
    assert_not_null(wr.info_panel)
    wr.inventory.storage_requested.emit()
    assert_true(wr.storage_panel.visible, "inventory opens storage")
    assert_true(home.go_back(), "back handled")
    assert_false(wr.storage_panel.visible, "back closes storage first")
    assert_eq(home.current_screen(), "workroom", "still in the workroom")
