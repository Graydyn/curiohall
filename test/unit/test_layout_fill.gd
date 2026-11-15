extends GutTest

const TEST_PATH := "user://test_layout_fill.json"
const TEST_CORRUPT_PATH := "user://test_layout_fill.corrupt.json"
const VP := Vector2(720, 1280)

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
    add_child_autofree(main)
    await wait_process_frames(2)
    while main.home.story_player.is_playing():
        main.home.story_player.skip()
    return main

func _assert_fills(c: Control, what: String) -> void:
    assert_not_null(c, what)
    if c == null:
        return
    assert_eq(c.get_global_rect().size, VP, what + " fills the viewport")

func test_exterior_and_home_fill() -> void:
    var main := await _boot()
    var home: HomeScreen = main.home
    _assert_fills(home, "home")
    _assert_fills(home.exterior, "exterior")

func test_wing_view_fills() -> void:
    var main := await _boot()
    var home: HomeScreen = main.home
    home.open_wing(2)
    await wait_process_frames(2)
    _assert_fills(home.wing_view, "wing view")

func test_task_card_and_picker_fill() -> void:
    var main := await _boot()
    var home: HomeScreen = main.home
    home.game.wallet.add_coins(1000)
    home.open_wing(1)
    await wait_process_frames(2)
    var w: WingView = home.wing_view
    w.tap_element("01_001")
    await wait_process_frames(2)
    _assert_fills(w.task_card, "task card")
    for i in 4:
        (w.task_card.find_child("Complete", true, false) as Button).pressed.emit()
        if i < 3:
            w.tap_element("01_001")
    await wait_process_frames(2)
    _assert_fills(w.picker, "look picker")

func test_story_player_fills() -> void:
    var main := await _boot()
    var sp: StoryPlayer = main.home.story_player
    sp.play({"kind": "scene", "lines": [{"speaker": "narrator", "text": "Hello."}]})
    await wait_process_frames(2)
    assert_true(sp.is_playing())
    for n in ["Root", "Dim", "Stage"]:
        _assert_fills(sp.find_child(n, true, false) as Control, "story " + n)
