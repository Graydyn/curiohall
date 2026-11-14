extends GutTest

const TEST_PATH := "user://test_home_nav.json"
const TEST_CORRUPT_PATH := "user://test_home_nav.corrupt.json"

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
    return main

func test_boot_shows_home() -> void:
    var main := await _boot()
    var home: HomeScreen = main.home
    assert_eq(home.current_screen(), "home")
    assert_true(home.find_child("ExpeditionBanner", true, false).visible)

func test_workroom_and_back() -> void:
    var main := await _boot()
    var home: HomeScreen = main.home
    var seen: Array = []
    home.screen_changed.connect(func(n: String) -> void: seen.append(n))
    (home.find_child("NavWorkroom", true, false) as Button).pressed.emit()
    assert_eq(home.current_screen(), "workroom")
    assert_true((home.find_child("BoardView", true, false) as BoardView).input_enabled)
    assert_true(home.go_back())
    assert_eq(home.current_screen(), "home")
    assert_false(home.go_back())
    assert_eq(home.current_screen(), "home")
    assert_eq(seen, ["workroom", "home"])

func test_board_input_off_at_home() -> void:
    var main := await _boot()
    var bv := main.home.find_child("BoardView", true, false) as BoardView
    assert_false(bv.input_enabled)

func test_wing_placeholder_and_back() -> void:
    var main := await _boot()
    var home: HomeScreen = main.home
    home.open_wing(1)
    assert_eq(home.current_screen(), "wing")
    assert_true(home.go_back())
    assert_eq(home.current_screen(), "home")

func test_back_closes_overlay_first() -> void:
    var main := await _boot()
    var home: HomeScreen = main.home
    (home.find_child("NavShop", true, false) as Button).pressed.emit()
    var shop := home.find_child("ShopPanel", true, false) as ShopPanel
    assert_true(shop.visible)
    assert_true(home.go_back())
    assert_false(shop.visible)
    assert_eq(home.current_screen(), "home")

func test_nav_buttons_exist() -> void:
    var main := await _boot()
    for n in ["NavWorkroom", "NavShop", "NavSociety", "NavChronicle", "ExpeditionBanner", "GalaBanner"]:
        assert_not_null(main.home.find_child(n, true, false), n)

func test_cast_asker_name() -> void:
    assert_eq(Cast.asker_name("imelda"), "Society request")
    assert_eq(Cast.asker_name("cornelia"), "Cornelia Wren")
    assert_true(Cast.is_cast("Cornelia"))
    assert_false(Cast.is_cast("imelda"))
