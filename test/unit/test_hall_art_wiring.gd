extends GutTest
## Painted-art wiring: nine-slice UI art falls back to flat boxes when the art
## is missing, and element sprites draw at the row's "size".

var _old_base: String

func before_each() -> void:
    _old_base = HallArt.base_dir
    HallArt.clear_cache()

func after_each() -> void:
    HallArt.base_dir = _old_base
    HallArt.clear_cache()

func test_art_box_falls_back_when_missing() -> void:
    HallArt.base_dir = "res://nonexistent_art_dir/"
    var flat := StyleBoxFlat.new()
    assert_eq(CurioTheme.art_box("speech_bubble", flat), flat)
    assert_null(CurioTheme.art_box("picker_frame", null))

func test_art_box_uses_texture_when_present() -> void:
    var sb := CurioTheme.art_box("speech_bubble", StyleBoxFlat.new(), 56.0, 36.0)
    assert_true(sb is StyleBoxTexture)
    var t := sb as StyleBoxTexture
    assert_eq(t.content_margin_left, 36.0)
    # Margins never exceed ~half the texture, so tiny art cannot invert.
    assert_true(t.texture_margin_left <= t.texture.get_width() * 0.45)

func test_element_sprite_draws_at_row_size() -> void:
    var g := Game.fresh(0.0)
    var row: Dictionary = ConfigDB.hall_elements["02_016"].duplicate()
    row["size"] = 210
    var s := ElementSprite.new()
    add_child_autofree(s)
    s.setup(row, g)
    assert_not_null(HallArt.element("02_016", 0))
    assert_eq(maxf(s.size.x, s.size.y), 210.0)
    var pos: Array = row["pos"]
    assert_almost_eq(s.position.x + s.size.x * 0.5, float(pos[0]), 0.5)
    assert_almost_eq(s.position.y + s.size.y, float(pos[1]), 0.5)
    # The drawn texture must match too (TextureRect min size used to clamp it
    # to the 384 px texture when size was set before expand_mode).
    var art := s.get_node("Art") as TextureRect
    assert_eq(art.size, s.size)

func test_exterior_wing_art_fits_its_rect() -> void:
    var g := Game.fresh(0.0)
    var m := ExteriorMap.new()
    add_child_autofree(m)
    m.setup(g)
    m.state_override = {3: Campaign.AreaState.RESTORED}
    m.refresh()
    var w: Control = m._wings[3]
    var art := w.get_node_or_null("Art") as TextureRect
    assert_not_null(art)
    assert_eq(art.texture, HallArt.wing_exterior(3, "restored"))
    assert_eq(art.size, w.size)

func test_exterior_state_override_for_previews() -> void:
    var g := Game.fresh(0.0)
    var m := ExteriorMap.new()
    add_child_autofree(m)
    m.setup(g)
    m.state_override = {2: Campaign.AreaState.RESTORED, 3: Campaign.AreaState.LOCKED}
    m.refresh()
    assert_eq(m.wing_state(2), Campaign.AreaState.RESTORED)
    assert_eq(m.wing_state(3), Campaign.AreaState.LOCKED)

func test_every_wing_has_restored_art_the_size_of_its_rect() -> void:
    # The Hall-as-one-building exterior: every wing's restored art is the
    # master painting's pixels of exactly its exterior_rect.
    for area in ConfigDB.hall_wings:
        var tex := HallArt.wing_exterior(int(area), "restored")
        assert_not_null(tex, "wing %d" % int(area))
        if tex == null:
            continue
        var r: Array = ConfigDB.hall_wings[area]["exterior_rect"]
        assert_eq(tex.get_size(), Vector2(float(r[2]), float(r[3])), "wing %d" % int(area))

func test_canvas_is_the_base_painting_size() -> void:
    var m := ExteriorMap.new()
    add_child_autofree(m)
    m.setup(Game.fresh(0.0))
    assert_eq(m.canvas_size, Vector2(HallArt.exterior_base().get_size()))
    assert_eq(m._canvas.size, m.canvas_size)

func test_wing_rects_tile_without_overlap_inside_canvas() -> void:
    var base := Rect2(Vector2.ZERO, Vector2(HallArt.exterior_base().get_size()))
    var m := ExteriorMap.new()
    add_child_autofree(m)
    var min_side := 120.0 / m.zoom   # a 120 px tap at the default zoom
    var rects := {}
    for area in ConfigDB.hall_wings:
        var r: Array = ConfigDB.hall_wings[area]["exterior_rect"]
        rects[int(area)] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
    for a in rects:
        var ra: Rect2 = rects[a]
        assert_true(base.encloses(ra), "wing %d inside canvas" % a)
        assert_true(minf(ra.size.x, ra.size.y) >= min_side, "wing %d big enough to tap" % a)
        for b in rects:
            if b > a:
                assert_false(ra.intersects(rects[b]), "wings %d and %d overlap" % [a, b])

func test_locked_interior_draws_nothing_over_the_boarded_base() -> void:
    var m := ExteriorMap.new()
    add_child_autofree(m)
    m.setup(Game.fresh(0.0))
    m.state_override = {10: Campaign.AreaState.LOCKED}
    m.refresh()
    assert_eq(m._wings[10].get_child_count(), 0)

func test_locked_separate_draws_ink_sketch_of_restored_art() -> void:
    var m := ExteriorMap.new()
    add_child_autofree(m)
    m.setup(Game.fresh(0.0))
    m.state_override = {7: Campaign.AreaState.LOCKED, 8: Campaign.AreaState.RESTORED}
    m.refresh()
    var art := m._wings[7].get_node_or_null("Art") as TextureRect
    assert_not_null(art)
    assert_eq(art.texture, HallArt.wing_exterior(7, "restored"))
    assert_not_null(art.material)
    assert_eq((art.material as ShaderMaterial).shader.resource_path, "res://view/shaders/ink_sketch.gdshader")
    var art8 := m._wings[8].get_node_or_null("Art") as TextureRect
    assert_null(art8.material)

func test_restored_painted_wing_has_no_rect_tint_layer() -> void:
    # Wing textures are crop-sized with feathered alpha; any untextured layer
    # spanning the rect shows as a hard-edged translucent box over the grounds.
    var g := Game.fresh(0.0)
    var m := ExteriorMap.new()
    add_child_autofree(m)
    m.setup(g)
    m.state_override = {2: Campaign.AreaState.RESTORED}
    m.refresh()
    var w: Control = m._wings[2]
    for c in w.get_children():
        assert_false(c is ColorRect, "ColorRect over wing 2: %s" % c.name)
        assert_false(c is Panel, "Panel over wing 2: %s" % c.name)
