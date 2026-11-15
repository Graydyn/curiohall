class_name ExteriorMap
extends Control
## The painted Hall exterior: a 2160x3240 canvas of wings, panned by drag and
## zoomed by pinch / ctrl+wheel. Reached wings (ACTIVE/RESTORED) are tappable.

signal wing_tapped(area: int)

const CANVAS := Vector2(2160, 3240)
const ZOOM_MIN := 0.5
const ZOOM_MAX := 1.5
const TAP_SLOP := 12.0

var game: Game
var zoom := 0.6

var _canvas: Control
var _wings: Dictionary = {}    # area -> Control
var _states: Dictionary = {}   # area -> Campaign.AreaState
var _pulses: Array = []        # glow controls to pulse
var _ink_material: ShaderMaterial
var _touches: Dictionary = {}  # finger index -> position
var _pinch_dist := 0.0
var _press_pos := Vector2.ZERO
var _pressing := false
var _dragged := false
var _time := 0.0
var _has_base := false

func setup(g: Game) -> void:
    game = g
    clip_contents = true
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    _canvas = Control.new()
    _canvas.name = "Canvas"
    _canvas.size = CANVAS
    _canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_canvas)
    _ink_material = ShaderMaterial.new()
    _ink_material.shader = load("res://view/shaders/ink_outline.gdshader")
    _ink_material.set_shader_parameter("ink_color", Color(CurioTheme.INK, 0.55))
    _ink_material.set_shader_parameter("width", 2.0)
    var base := HallArt.exterior_base()
    _has_base = base != null
    if base != null:
        var tr := TextureRect.new()
        tr.texture = base
        tr.size = CANVAS
        tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tr.stretch_mode = TextureRect.STRETCH_SCALE
        tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _canvas.add_child(tr)
    else:
        var bg := Panel.new()
        bg.size = CANVAS
        bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bg.add_theme_stylebox_override("panel", _box(CurioTheme.TEAL.darkened(0.35), Color(0, 0, 0, 0), 0, 0))
        _canvas.add_child(bg)
    var areas: Array = ConfigDB.hall_wings.keys()
    areas.sort()
    for a in areas:
        var w := Control.new()
        w.name = "Wing%02d" % int(a)
        w.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _canvas.add_child(w)
        _wings[int(a)] = w
    resized.connect(_apply_view)
    refresh()
    var cur := game.campaign.current_area()
    center_on(cur if cur > 0 else 1)

func wing_count() -> int:
    return _wings.size()

func wing_state(area: int) -> int:
    return int(_states.get(area, Campaign.AreaState.LOCKED))

static func _box(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = bg
    sb.border_color = border
    sb.set_border_width_all(border_w)
    sb.set_corner_radius_all(radius)
    return sb

func refresh() -> void:
    _pulses.clear()
    for a in _wings:
        var w: Control = _wings[a]
        for c in w.get_children():
            w.remove_child(c)
            c.free()
        _build_wing(int(a), w)

func _build_wing(area: int, w: Control) -> void:
    var row: Dictionary = ConfigDB.hall_wings[area]
    var r: Array = row["exterior_rect"]
    w.position = Vector2(float(r[0]), float(r[1]))
    w.size = Vector2(float(r[2]), float(r[3]))
    var st: int = game.campaign.area_state(area, game.player)
    _states[area] = st
    var separate := String(row.get("structure", "interior")) == "separate"
    var locked := st == Campaign.AreaState.LOCKED
    var tex_state := "boarded" if (locked and not separate) else "restored"
    var tex := HallArt.wing_exterior(area, tex_state)
    var inset := w.size * 0.04
    if tex != null:
        var tr := TextureRect.new()
        tr.texture = tex
        tr.size = w.size
        tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
        if locked and separate:
            tr.material = _ink_material
        w.add_child(tr)
    elif locked and _has_base:
        # Painted grounds but no wing art yet: keep the painting clean.
        pass
    elif not (locked and separate):
        w.add_child(_placeholder(row, st, w.size, inset))
    else:
        # Faint ink outline only, no fill.
        var p := Panel.new()
        p.position = inset
        p.size = w.size - inset * 2.0
        p.mouse_filter = Control.MOUSE_FILTER_IGNORE
        p.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0), Color(CurioTheme.INK, 0.45), 18, 2))
        w.add_child(p)
        w.add_child(_label(String(row["name"]), w.size, Color(CurioTheme.CREAM, 0.35)))
    if st == Campaign.AreaState.ACTIVE:
        var halo := _halo_texture() if tex != null else null
        if halo != null:
            # Painted wing: a soft gaslight halo behind the building.
            var hr := TextureRect.new()
            hr.name = "Glow"
            hr.texture = halo
            hr.size = w.size * 1.3
            hr.position = (w.size - hr.size) * 0.5
            hr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            hr.stretch_mode = TextureRect.STRETCH_SCALE
            hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
            w.add_child(hr)
            w.move_child(hr, 0)
            _pulses.append(hr)
        else:
            var glow := Panel.new()
            glow.name = "Glow"
            glow.position = inset
            glow.size = w.size - inset * 2.0
            glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
            var sb := _box(Color(1.0, 0.82, 0.45, 0.10), Color(1.0, 0.82, 0.45, 0.6), 18, 3)
            sb.shadow_color = Color(1.0, 0.75, 0.35, 0.5)
            sb.shadow_size = 24
            glow.add_theme_stylebox_override("panel", sb)
            w.add_child(glow)
            _pulses.append(glow)
        var scaf := HallArt.ui("scaffold")
        if scaf != null:
            var s := TextureRect.new()
            s.name = "Scaffold"
            s.texture = scaf
            s.size = w.size
            s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            s.stretch_mode = TextureRect.STRETCH_SCALE
            s.mouse_filter = Control.MOUSE_FILTER_IGNORE
            w.add_child(s)
    elif st == Campaign.AreaState.RESTORED and tex != null:
        var win := ColorRect.new()
        win.name = "WindowGlow"
        win.color = Color(1.0, 0.8, 0.4, 0.12)
        win.size = w.size
        win.mouse_filter = Control.MOUSE_FILTER_IGNORE
        w.add_child(win)

## Soft radial gaslight halo (drawn in-engine so it always stays soft).
static var _halo: GradientTexture2D

static func _halo_texture() -> GradientTexture2D:
    if _halo == null:
        var g := Gradient.new()
        g.set_color(0, Color(1.0, 0.8, 0.45, 0.55))
        g.set_color(1, Color(1.0, 0.75, 0.35, 0.0))
        _halo = GradientTexture2D.new()
        _halo.gradient = g
        _halo.fill = GradientTexture2D.FILL_RADIAL
        _halo.fill_from = Vector2(0.5, 0.5)
        _halo.fill_to = Vector2(1.0, 0.5)
        _halo.width = 256
        _halo.height = 256
    return _halo

func _placeholder(row: Dictionary, st: int, sz: Vector2, inset: Vector2) -> Control:
    var fill: Color
    var border := CurioTheme.BRASS
    match st:
        Campaign.AreaState.RESTORED:
            fill = CurioTheme.TEAL_LIGHT
        Campaign.AreaState.ACTIVE:
            fill = CurioTheme.TEAL
        _:
            fill = CurioTheme.BURGUNDY.darkened(0.5)
            border = CurioTheme.BRASS.darkened(0.5)
    var holder := Control.new()
    holder.size = sz
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var p := Panel.new()
    p.position = inset
    p.size = sz - inset * 2.0
    p.mouse_filter = Control.MOUSE_FILTER_IGNORE
    p.add_theme_stylebox_override("panel", _box(fill, border, 18, 3))
    holder.add_child(p)
    var tint := CurioTheme.CREAM if st != Campaign.AreaState.LOCKED else Color(CurioTheme.CREAM, 0.5)
    holder.add_child(_label(String(row["name"]), sz, tint))
    return holder

func _label(text: String, sz: Vector2, col: Color) -> Label:
    var l := Label.new()
    l.text = text
    l.size = sz
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    l.add_theme_font_size_override("font_size", 36)
    l.add_theme_color_override("font_color", col)
    return l

func _process(delta: float) -> void:
    _time += delta
    var a := 0.55 + 0.45 * (0.5 + 0.5 * sin(_time * 2.0))
    for g in _pulses:
        if is_instance_valid(g):
            (g as Control).modulate.a = a

## Test hook and tap handler: reached wings emit, locked wings do not.
func tap_wing(area: int) -> void:
    if not _wings.has(area):
        return
    if wing_state(area) == Campaign.AreaState.LOCKED:
        return
    wing_tapped.emit(area)

func wing_at(canvas_pos: Vector2) -> int:
    var areas: Array = _wings.keys()
    areas.sort()
    areas.reverse()
    # Reached wings win over locked ones whose (not yet placed) rects overlap.
    var locked_hit := -1
    for a in areas:
        var w: Control = _wings[a]
        if Rect2(w.position, w.size).has_point(canvas_pos):
            if wing_state(int(a)) != Campaign.AreaState.LOCKED:
                return int(a)
            if locked_hit < 0:
                locked_hit = int(a)
    return locked_hit

func center_on(area: int) -> void:
    if not _wings.has(area):
        return
    var w: Control = _wings[area]
    var c := w.position + w.size * 0.5
    _canvas.position = size * 0.5 - c * zoom
    _apply_view()

func _apply_view() -> void:
    if _canvas == null:
        return
    zoom = clampf(zoom, ZOOM_MIN, ZOOM_MAX)
    _canvas.scale = Vector2(zoom, zoom)
    var scaled := CANVAS * zoom
    var p := _canvas.position
    for axis in 2:
        if scaled[axis] <= size[axis]:
            p[axis] = (size[axis] - scaled[axis]) * 0.5
        else:
            p[axis] = clampf(p[axis], size[axis] - scaled[axis], 0.0)
    _canvas.position = p

func _zoom_at(focus: Vector2, factor: float) -> void:
    var old := zoom
    zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
    if is_equal_approx(old, zoom):
        return
    var canvas_pt := (focus - _canvas.position) / old
    _canvas.position = focus - canvas_pt * zoom
    _apply_view()

func _pan(delta: Vector2) -> void:
    _canvas.position += delta
    _apply_view()

func _finish_tap(pos: Vector2) -> void:
    var a := wing_at((pos - _canvas.position) / zoom)
    if a > 0:
        tap_wing(a)

func _gui_input(event: InputEvent) -> void:
    if _canvas == null:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.device == InputEvent.DEVICE_ID_EMULATION:
            return
        if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
            if mb.ctrl_pressed:
                _zoom_at(mb.position, 1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1)
            return
        if mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.pressed:
                _pressing = true
                _dragged = false
                _press_pos = mb.position
            else:
                if _pressing and not _dragged:
                    _finish_tap(mb.position)
                _pressing = false
    elif event is InputEventMouseMotion:
        var mm := event as InputEventMouseMotion
        if mm.device == InputEvent.DEVICE_ID_EMULATION:
            return
        if _pressing and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
            if _dragged or mm.position.distance_to(_press_pos) > TAP_SLOP:
                _dragged = true
                _pan(mm.relative)
    elif event is InputEventScreenTouch:
        var st := event as InputEventScreenTouch
        if st.pressed:
            _touches[st.index] = st.position
            if _touches.size() == 1:
                _pressing = true
                _dragged = false
                _press_pos = st.position
            else:
                _dragged = true
                _pinch_dist = _touch_distance()
        else:
            _touches.erase(st.index)
            if _touches.is_empty():
                if _pressing and not _dragged:
                    _finish_tap(st.position)
                _pressing = false
            _pinch_dist = 0.0
    elif event is InputEventScreenDrag:
        var sd := event as InputEventScreenDrag
        _touches[sd.index] = sd.position
        if _touches.size() >= 2:
            _dragged = true
            var d := _touch_distance()
            if _pinch_dist > 0.0 and d > 0.0:
                _zoom_at(_touch_center(), d / _pinch_dist)
            _pinch_dist = d
        elif _pressing:
            if _dragged or sd.position.distance_to(_press_pos) > TAP_SLOP:
                _dragged = true
                _pan(sd.relative)
    elif event is InputEventMagnifyGesture:
        var mg := event as InputEventMagnifyGesture
        _zoom_at(mg.position, mg.factor)

func _touch_distance() -> float:
    var pts: Array = _touches.values()
    if pts.size() < 2:
        return 0.0
    return (pts[0] as Vector2).distance_to(pts[1])

func _touch_center() -> Vector2:
    var pts: Array = _touches.values()
    return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
