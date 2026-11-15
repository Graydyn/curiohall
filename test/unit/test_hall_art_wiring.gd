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
    var w: Control = m._wings[3]
    var art: TextureRect = null
    for c in w.get_children():
        if c is TextureRect and (c as TextureRect).texture == HallArt.wing_exterior(3, "boarded"):
            art = c
    assert_not_null(art)
    assert_eq(art.size, w.size)
