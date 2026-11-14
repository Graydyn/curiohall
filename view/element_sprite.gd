class_name ElementSprite
extends Control
## One Hall element in a wing scene. Stage drives the art: OUTLINE draws only
## the ink edge of look 0, IN_PROGRESS dims it under scaffolding with a pip,
## DONE shows the chosen look. Missing art falls back to a palette placeholder.

signal tapped(id: String)

const PLACEHOLDER := Vector2(160, 160)

var id := ""
var stage: HallElements.Stage = HallElements.Stage.OUTLINE
var shown_look := 0
var game: Game
var _row: Dictionary
var _pip := ""

static var _ink_material: ShaderMaterial

func setup(row: Dictionary, g: Game) -> void:
    _row = row
    id = String(row["id"])
    game = g
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    refresh()

func pip_text() -> String:
    return _pip

func refresh() -> void:
    for c in get_children():
        remove_child(c)
        c.free()
    stage = HallElements.stage(id, game.campaign)
    shown_look = game.hall.look_of(id) if stage == HallElements.Stage.DONE else 0
    _pip = ""
    var tex := HallArt.element(id, shown_look)
    var sz := tex.get_size() if tex != null else PLACEHOLDER
    size = sz
    var pos: Array = _row["pos"]
    position = Vector2(float(pos[0]) - sz.x * 0.5, float(pos[1]) - sz.y)
    if tex != null:
        var tr := TextureRect.new()
        tr.name = "Art"
        tr.texture = tex
        tr.size = sz
        tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tr.stretch_mode = TextureRect.STRETCH_SCALE
        tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
        if stage == HallElements.Stage.OUTLINE:
            tr.material = _outline_material()
        elif stage == HallElements.Stage.IN_PROGRESS:
            tr.modulate = Color(1, 1, 1, 0.55)
        add_child(tr)
    else:
        add_child(_placeholder(sz))
    if stage == HallElements.Stage.IN_PROGRESS:
        var scaf := HallArt.ui("scaffold")
        if scaf != null:
            var s := TextureRect.new()
            s.name = "Scaffold"
            s.texture = scaf
            s.size = sz
            s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            s.stretch_mode = TextureRect.STRETCH_SCALE
            s.mouse_filter = Control.MOUSE_FILTER_IGNORE
            add_child(s)
        var p := HallElements.progress(id, game.campaign)
        _pip = "%d/%d" % [p.x, p.y]
        var l := Label.new()
        l.name = "Pip"
        l.text = _pip
        l.position = Vector2(sz.x - 64.0, 0.0)
        l.size = Vector2(64, 36)
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        l.mouse_filter = Control.MOUSE_FILTER_IGNORE
        l.add_theme_font_size_override("font_size", 24)
        l.add_theme_color_override("font_color", CurioTheme.CREAM)
        l.add_theme_color_override("font_outline_color", CurioTheme.INK)
        l.add_theme_constant_override("outline_size", 6)
        add_child(l)

func _outline_material() -> ShaderMaterial:
    if _ink_material == null:
        _ink_material = ShaderMaterial.new()
        _ink_material.shader = load("res://view/shaders/ink_outline.gdshader")
        _ink_material.set_shader_parameter("ink_color", Color(CurioTheme.INK, 0.7))
        _ink_material.set_shader_parameter("width", 2.0)
    return _ink_material

func _placeholder(sz: Vector2) -> Control:
    var fill: Color
    match stage:
        HallElements.Stage.DONE:
            fill = CurioTheme.TEAL_LIGHT
        HallElements.Stage.IN_PROGRESS:
            fill = CurioTheme.TEAL.darkened(0.2)
        _:
            fill = Color(CurioTheme.BURGUNDY, 0.35)
    var p := Panel.new()
    p.name = "Placeholder"
    p.size = sz
    p.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var sb := StyleBoxFlat.new()
    sb.bg_color = fill
    sb.border_color = CurioTheme.BRASS if stage != HallElements.Stage.OUTLINE else Color(CurioTheme.INK, 0.6)
    sb.set_border_width_all(3)
    sb.set_corner_radius_all(24)
    p.add_theme_stylebox_override("panel", sb)
    var l := Label.new()
    l.text = String(_row["name"])
    l.size = sz
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    l.add_theme_font_size_override("font_size", 22)
    l.add_theme_color_override("font_color", CurioTheme.CREAM)
    p.add_child(l)
    return p

## Hit area is at least finger sized around the sprite.
func hit_rect() -> Rect2:
    var r := Rect2(position, size)
    var grow := Vector2(maxf(0.0, 88.0 - r.size.x), maxf(0.0, 88.0 - r.size.y)) * 0.5
    return r.grow_individual(grow.x, grow.y, grow.x, grow.y)

func tap() -> void:
    tapped.emit(id)
