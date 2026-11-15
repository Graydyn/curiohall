class_name CurioTheme
## Shared look: deep teal / burgundy / cream / brass, engraved display type
## (IM Fell English SC) over a humanist body face (Alegreya Sans).

const TEAL := Color(0.09, 0.24, 0.27)
const TEAL_LIGHT := Color(0.16, 0.36, 0.38)
const BURGUNDY := Color(0.42, 0.12, 0.17)
const CREAM := Color(0.96, 0.92, 0.82)
const BRASS := Color(0.78, 0.60, 0.25)
const INK := Color(0.14, 0.10, 0.08)

const DISPLAY_FONT := "res://assets/fonts/IMFellEnglishSC-Regular.ttf"
const BODY_FONT := "res://assets/fonts/AlegreyaSans-Regular.ttf"
const BOLD_FONT := "res://assets/fonts/AlegreyaSans-Bold.ttf"

static func _box(bg: Color, border: Color, radius: int = 8, border_w: int = 2) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = bg
    sb.border_color = border
    sb.set_border_width_all(border_w)
    sb.set_corner_radius_all(radius)
    sb.content_margin_left = 12.0
    sb.content_margin_right = 12.0
    sb.content_margin_top = 8.0
    sb.content_margin_bottom = 8.0
    return sb

## Nine-slice painted UI art (assets/map/ui/<art_name>.png) as a stylebox, or
## `fallback` when the art is missing. `margin` is the slice inset in texture
## px; `content` the inner padding in screen px.
static func art_box(art_name: String, fallback: StyleBox, margin: float = 48.0,
        content: float = 18.0) -> StyleBox:
    var tex := HallArt.ui(art_name)
    if tex == null:
        return fallback
    var sb := StyleBoxTexture.new()
    sb.texture = tex
    sb.set_texture_margin_all(minf(margin, minf(tex.get_width(), tex.get_height()) * 0.45))
    sb.set_content_margin_all(content)
    sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
    sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
    return sb

static func build() -> Theme:
    var t := Theme.new()
    var body := load(BODY_FONT) as Font
    var bold := load(BOLD_FONT) as Font
    var display := load(DISPLAY_FONT) as Font
    if body != null:
        t.default_font = body
    t.default_font_size = 20

    t.set_stylebox("panel", "PanelContainer", _box(CREAM, BRASS, 10, 3))
    # Task card frame: PanelContainer variation "CardFrame".
    t.add_type("CardFrame")
    t.set_type_variation("CardFrame", "PanelContainer")
    t.set_stylebox("panel", "CardFrame", art_box("task_card_frame", _box(CREAM, BRASS, 10, 3), 64.0, 40.0))
    # Brass nav buttons: Button variation "NavButton".
    t.add_type("NavButton")
    t.set_type_variation("NavButton", "Button")
    var nav := art_box("nav_button", _box(TEAL, BRASS), 28.0, 10.0)
    t.set_stylebox("normal", "NavButton", nav)
    t.set_stylebox("hover", "NavButton", nav)
    var nav_p := nav.duplicate() as StyleBox
    if nav_p is StyleBoxTexture:
        (nav_p as StyleBoxTexture).modulate_color = Color(0.8, 0.75, 0.7)
    else:
        nav_p = _box(BURGUNDY, BRASS)
    t.set_stylebox("pressed", "NavButton", nav_p)
    t.set_color("font_color", "Label", CREAM)

    t.set_stylebox("normal", "Button", _box(TEAL, BRASS))
    t.set_stylebox("hover", "Button", _box(TEAL_LIGHT, BRASS))
    t.set_stylebox("pressed", "Button", _box(BURGUNDY, BRASS))
    t.set_stylebox("disabled", "Button", _box(Color(TEAL, 0.5), Color(BRASS, 0.4)))
    t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), CREAM))
    for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
        t.set_color(c, "Button", CREAM)
    t.set_color("font_disabled_color", "Button", Color(CREAM, 0.5))
    if bold != null:
        t.set_font("font", "Button", bold)

    # Engraved headers: Label with theme_type_variation = "HeaderLabel".
    t.add_type("HeaderLabel")
    t.set_type_variation("HeaderLabel", "Label")
    if display != null:
        t.set_font("font", "HeaderLabel", display)
    t.set_font_size("font_size", "HeaderLabel", 28)
    t.set_color("font_color", "HeaderLabel", BRASS)
    return t
