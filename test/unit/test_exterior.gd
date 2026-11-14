extends GutTest

var _old_base: String

func before_each() -> void:
    _old_base = HallArt.base_dir
    HallArt.base_dir = "res://nonexistent_art_dir/"
    HallArt.clear_cache()

func after_each() -> void:
    HallArt.base_dir = _old_base
    HallArt.clear_cache()

func _make() -> Array:
    var g := Game.fresh(0.0)
    var m := ExteriorMap.new()
    add_child_autofree(m)
    m.setup(g)
    return [g, m]

func test_art_missing_returns_null() -> void:
    assert_null(HallArt.exterior_base())
    assert_null(HallArt.wing_exterior(1, "restored"))
    assert_null(HallArt.element("01_001", 1))
    assert_null(HallArt.ui("scaffold"))

func test_builds_47_wings_with_states() -> void:
    var gm := _make()
    var g: Game = gm[0]
    var m: ExteriorMap = gm[1]
    assert_eq(m.wing_count(), 47)
    for a in range(1, 48):
        assert_eq(m.wing_state(a), g.campaign.area_state(a, g.player))
    assert_eq(m.wing_state(1), Campaign.AreaState.ACTIVE)

func test_tap_emits_only_for_reached() -> void:
    var gm := _make()
    var m: ExteriorMap = gm[1]
    watch_signals(m)
    m.tap_wing(5)
    assert_signal_not_emitted(m, "wing_tapped")
    m.tap_wing(1)
    assert_signal_emitted_with_parameters(m, "wing_tapped", [1])

func test_complete_campaign_no_active() -> void:
    var gm := _make()
    var g: Game = gm[0]
    var m: ExteriorMap = gm[1]
    g.campaign.day = 283
    m.refresh()
    for a in range(1, 48):
        assert_ne(m.wing_state(a), Campaign.AreaState.ACTIVE)

func test_next_task_strip() -> void:
    var home := HomeScreen.new()
    add_child_autofree(home)
    home.setup(Game.fresh(0.0))
    var strip := home.find_child("NextTaskStrip", true, false) as Button
    assert_not_null(strip)
    assert_true(strip.visible)
    assert_string_contains(strip.text, "Exhibit 01_001")
    assert_string_contains(strip.text, "26")
    home.game.campaign.day = 283
    home.refresh_next_task()
    assert_false(strip.visible)

func test_strip_tap_opens_wing_with_focus() -> void:
    var home := HomeScreen.new()
    add_child_autofree(home)
    home.setup(Game.fresh(0.0))
    var strip := home.find_child("NextTaskStrip", true, false) as Button
    strip.pressed.emit()
    assert_eq(home.current_screen(), "wing")
    assert_eq(home.wing_area, 1)
    assert_eq(home.focus_element, "01_001")

func _mouse(pressed: bool, pos: Vector2) -> InputEventMouseButton:
    var e := InputEventMouseButton.new()
    e.button_index = MOUSE_BUTTON_LEFT
    e.pressed = pressed
    e.position = pos
    return e

func test_drag_beyond_slop_is_not_tap() -> void:
    var gm := _make()
    var m: ExteriorMap = gm[1]
    m.set_anchors_preset(Control.PRESET_TOP_LEFT)
    m.size = Vector2(720, 1280)
    m.center_on(1)
    var w: Control = m._wings[1]
    var pt: Vector2 = m._canvas.position + (w.position + w.size * 0.5) * m.zoom
    watch_signals(m)
    m._gui_input(_mouse(true, pt))
    var mm := InputEventMouseMotion.new()
    mm.position = pt + Vector2(30, 0)
    mm.relative = Vector2(30, 0)
    mm.button_mask = MOUSE_BUTTON_MASK_LEFT
    m._gui_input(mm)
    m._gui_input(_mouse(false, pt + Vector2(30, 0)))
    assert_signal_not_emitted(m, "wing_tapped")
    var pt2: Vector2 = m._canvas.position + (w.position + w.size * 0.5) * m.zoom
    m._gui_input(_mouse(true, pt2))
    m._gui_input(_mouse(false, pt2 + Vector2(3, 0)))
    assert_signal_emitted_with_parameters(m, "wing_tapped", [1])
