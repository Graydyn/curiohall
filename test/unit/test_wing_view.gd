extends GutTest

var _old_base: String

func before_each() -> void:
    _old_base = HallArt.base_dir
    HallArt.base_dir = "res://nonexistent_art_dir/"
    HallArt.clear_cache()

func after_each() -> void:
    HallArt.base_dir = _old_base
    HallArt.clear_cache()

func _make(g: Game = null, area := 1, focus := "") -> Array:
    if g == null:
        g = Game.fresh(0.0)
        g.wallet.add_coins(1000)
    var w := WingView.new()
    add_child_autofree(w)
    w.size = Vector2(720, 1280)
    w.setup(g, area, focus)
    return [g, w]

func _complete(w: WingView, id: String) -> void:
    w.tap_element(id)
    assert_not_null(w.task_card, "card open for " + id)
    (w.task_card.find_child("Complete", true, false) as Button).pressed.emit()

func test_two_outline_sprites() -> void:
    var w: WingView = _make()[1]
    assert_eq(w.sprite_count(), 2)
    assert_eq(w.sprite("01_001").stage, HallElements.Stage.OUTLINE)
    assert_eq(w.sprite("01_002").stage, HallElements.Stage.OUTLINE)
    assert_false(w.has_tabs())

func test_progress_pip_and_picker_flow() -> void:
    var gw := _make()
    var g: Game = gw[0]
    var w: WingView = gw[1]
    for i in 3:
        _complete(w, "01_001")
    assert_eq(w.sprite("01_001").stage, HallElements.Stage.IN_PROGRESS)
    assert_eq(w.sprite("01_001").pip_text(), "3/4")
    assert_null(w.picker)
    watch_signals(w)
    _complete(w, "01_001")
    assert_not_null(w.picker)
    assert_false(w.picker.has_close())
    assert_eq(w.sprite("01_001").stage, HallElements.Stage.DONE)
    w.picker.pick(1)
    assert_eq(g.hall.look_of("01_001"), 1)
    assert_eq(w.sprite("01_001").shown_look, 1)
    assert_null(w.picker)
    assert_signal_emitted(w, "picks_done")

func test_rebuild_with_pending_opens_picker() -> void:
    var g := Game.fresh(0.0)
    g.wallet.add_coins(1000)
    var w: WingView = _make(g)[1]
    for i in 4:
        _complete(w, "01_001")
    var g2 := Game.from_dict(g.to_dict())
    var w2: WingView = _make(g2)[1]
    assert_not_null(w2.picker)
    assert_eq(w2.picker.element_id, "01_001")

func test_arrange_done_opens_closable_picker() -> void:
    var g := Game.fresh(0.0)
    g.wallet.add_coins(1000)
    var w: WingView = _make(g)[1]
    for i in 4:
        _complete(w, "01_001")
    w.picker.pick(0)
    w.tap_element("01_001")
    assert_null(w.picker, "not in arrange: done element does nothing")
    assert_null(w.task_card)
    (w.find_child("ArrangeToggle", true, false) as Button).button_pressed = true
    w.tap_element("01_001")
    assert_not_null(w.picker)
    assert_true(w.picker.has_close())
    w.picker.close()
    assert_null(w.picker)

func test_task_card_society_and_cast() -> void:
    var w: WingView = _make()[1]
    w.tap_element("01_001")
    assert_eq(w.task_card.asker_text(), "Hugo Pemberton")
    w.task_card.close()
    var row: Dictionary = ConfigDB.main_task_by_key["1_1"]
    var old = row["detail_icon"]
    row["detail_icon"] = "mystery_box"
    w.tap_element("01_001")
    assert_eq(w.task_card.asker_text(), "Society request")
    w.task_card.close()
    row["detail_icon"] = old

func test_card_complete_disabled_when_short() -> void:
    var g := Game.fresh(0.0)
    g.wallet.coins = 5
    var w: WingView = _make(g)[1]
    w.tap_element("01_001")
    assert_true((w.task_card.find_child("Complete", true, false) as Button).disabled)

func test_future_day_element_toasts_not_today() -> void:
    var w: WingView = _make(null, 2)[1]
    watch_signals(w)
    w.tap_element("02_001")
    assert_null(w.task_card)
    assert_signal_emitted_with_parameters(w, "toast", ["not_today"])

func test_setup_twice() -> void:
    var gw := _make()
    var w: WingView = gw[1]
    w.setup(gw[0], 1)
    w.setup(gw[0], 1)
    assert_eq(w.sprite_count(), 2)

func _home() -> HomeScreen:
    var g := Game.fresh(0.0)
    g.wallet.add_coins(1000)
    var h := HomeScreen.new()
    add_child_autofree(h)
    h.size = Vector2(720, 1280)
    h.setup(g)
    await _dismiss_story(h)
    return h

## The map plays pending story scenes (the wing 1 panel) on setup; clear them.
func _dismiss_story(h: HomeScreen) -> void:
    await wait_process_frames(2)
    while h.story_player.is_playing():
        h.story_player.skip()

func test_reopen_wing_has_sprites() -> void:
    var h := await _home()
    h.open_wing(1)
    assert_eq(h.wing_view.sprite_count(), 2)
    h.go_back()
    h.open_wing(1)
    assert_eq(h.wing_view.sprite_count(), 2)

func test_back_with_mandatory_picker_stays() -> void:
    var h := await _home()
    h.open_wing(1)
    for i in 4:
        h.wing_view.tap_element("01_001")
        (h.wing_view.task_card.find_child("Complete", true, false) as Button).pressed.emit()
    assert_not_null(h.wing_view.picker)
    assert_true(h.go_back())
    assert_eq(h.current_screen(), "wing")
    assert_not_null(h.wing_view.picker)

func test_back_closes_card_then_leaves() -> void:
    var h := await _home()
    h.open_wing(1)
    h.wing_view.tap_element("01_001")
    assert_not_null(h.wing_view.task_card)
    assert_true(h.go_back())
    assert_null(h.wing_view.task_card)
    assert_eq(h.current_screen(), "wing")
    assert_true(h.go_back())
    assert_eq(h.current_screen(), "home")

func test_focus_element_scrolls_without_error() -> void:
    var w: WingView = _make(null, 1, "01_002")[1]
    assert_eq(w.sprite_count(), 2)

func test_home_opens_wing_and_returns() -> void:
    var g := Game.fresh(0.0)
    g.wallet.add_coins(1000)
    var h := HomeScreen.new()
    add_child_autofree(h)
    h.size = Vector2(720, 1280)
    h.setup(g)
    await _dismiss_story(h)
    h.open_wing(1, "01_002")
    assert_eq(h.current_screen(), "wing")
    assert_true(h.wing_view.visible)
    assert_eq(h.wing_view.sprite_count(), 2)
    for i in 3:
        h.wing_view.tap_element("01_001")
        (h.wing_view.task_card.find_child("Complete", true, false) as Button).pressed.emit()
    assert_true(h.go_back())
    assert_eq(h.current_screen(), "home")
    assert_false(h.wing_view.visible)
    assert_true(h._next_strip.visible)
