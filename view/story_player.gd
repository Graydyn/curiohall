class_name StoryPlayer
extends CanvasLayer
## On-map story scenes. Beats: dimmed map, portraits sliding in from the sides
## and a cream speech bubble. Panels: heavy dim, a painted card and a caption.
## Tap advances; Skip ends the scene. Swallows all input while playing.

signal finished
signal scene_started(scene: Dictionary)

const BEAT_DIM := 0.25
const PANEL_DIM := 0.85
const PORTRAIT_SIZE := Vector2(300, 420)

var game: Game
var _root: Control
var _dim: ColorRect
var _stage: Control
var _bubble: PanelContainer
var _name_label: Label
var _text_label: Label
var _skip: Button
var _scene: Dictionary = {}
var _index := 0
var _queue_mode := false
var _sides: Dictionary = {}       # speaker -> 0 left / 1 right
var _portraits: Dictionary = {}   # speaker -> TextureRect
var _tween: Tween

func setup(g: Game) -> void:
    game = g
    layer = 30
    visible = false
    _root = Control.new()
    _root.name = "Root"
    _root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_STOP
    _root.gui_input.connect(_on_gui_input)
    add_child(_root)
    _dim = ColorRect.new()
    _dim.name = "Dim"
    _dim.color = Color(0, 0, 0, BEAT_DIM)
    _dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_dim)
    _stage = Control.new()
    _stage.name = "Stage"
    _stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_stage)
    _skip = Button.new()
    _skip.name = "Skip"
    _skip.text = "Skip"
    _skip.offset_left = 570.0
    _skip.offset_right = 710.0
    _skip.offset_top = 64.0
    _skip.offset_bottom = 128.0
    _skip.pressed.connect(skip)
    _root.add_child(_skip)

func is_playing() -> bool:
    return visible

func current_scene() -> Dictionary:
    return _scene

## Plays queued scenes in order, marking each seen, until none remain.
func play_pending() -> void:
    if is_playing():
        return
    if not game.story.has_pending():
        return
    _queue_mode = true
    _next_from_queue()

## Replays one scene without touching the story queue or seen set.
func play(scene: Dictionary) -> void:
    if is_playing():
        return
    _queue_mode = false
    _start(scene)

func _next_from_queue() -> void:
    while game.story.has_pending():
        var scene := game.story.peek()
        if _has_content(scene):
            _start(scene)
            return
        game.story.finish_current()
    _queue_mode = false
    visible = false
    finished.emit()

func _has_content(scene: Dictionary) -> bool:
    var key := "panels" if String(scene.get("kind", "")) == "panel" else "lines"
    return not (scene.get(key, []) as Array).is_empty()

func _start(scene: Dictionary) -> void:
    if _tween != null:
        _tween.kill()
        _tween = null
    _scene = scene
    _index = 0
    _sides.clear()
    _portraits.clear()
    for c in _stage.get_children():
        _stage.remove_child(c)
        c.free()
    _bubble = null
    visible = true
    scene_started.emit(scene)
    _show_step()

func _is_panel() -> bool:
    return String(_scene.get("kind", "")) == "panel"

func _steps() -> Array:
    return _scene.get("panels" if _is_panel() else "lines", [])

## Tap handler (also the test hook).
func advance() -> void:
    if not is_playing():
        return
    _index += 1
    if _index >= _steps().size():
        _end_scene()
    else:
        _show_step()

func skip() -> void:
    if is_playing():
        _end_scene()

func _end_scene() -> void:
    if _queue_mode:
        game.story.finish_current()
        _next_from_queue()
    else:
        visible = false
        finished.emit()

func _on_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.device != InputEvent.DEVICE_ID_EMULATION and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            advance()
    elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
        advance()

func _show_step() -> void:
    if _is_panel():
        _show_panel()
    else:
        _show_line()

func _make_bubble(caption: bool) -> void:
    if _bubble != null:
        return
    _bubble = PanelContainer.new()
    _bubble.name = "Bubble"
    _bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var sb := StyleBoxFlat.new()
    sb.bg_color = CurioTheme.CREAM
    sb.border_color = CurioTheme.BRASS
    sb.set_border_width_all(4)
    sb.set_corner_radius_all(14)
    sb.set_content_margin_all(18)
    _bubble.add_theme_stylebox_override("panel", CurioTheme.art_box("speech_bubble", sb, 56.0, 36.0))
    _bubble.offset_left = 30.0
    _bubble.offset_right = 690.0
    _bubble.offset_top = 880.0 if not caption else 940.0
    _bubble.offset_bottom = 1140.0
    _stage.add_child(_bubble)
    var box := VBoxContainer.new()
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _bubble.add_child(box)
    _name_label = Label.new()
    _name_label.name = "Name"
    var display := load(CurioTheme.DISPLAY_FONT) as Font
    if display != null:
        _name_label.add_theme_font_override("font", display)
    _name_label.add_theme_font_size_override("font_size", 30)
    _name_label.add_theme_color_override("font_color", CurioTheme.BURGUNDY)
    box.add_child(_name_label)
    _text_label = Label.new()
    _text_label.name = "Text"
    _text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _text_label.add_theme_font_size_override("font_size", 28)
    _text_label.add_theme_color_override("font_color", CurioTheme.INK)
    box.add_child(_text_label)

func _show_line() -> void:
    _dim.color.a = BEAT_DIM
    _make_bubble(false)
    var line: Dictionary = _steps()[_index]
    var speaker := String(line.get("speaker", ""))
    _name_label.text = Cast.display_name(speaker) if speaker != "" else ""
    _name_label.visible = speaker != ""
    _text_label.text = String(line.get("text", ""))
    if speaker == "":
        return
    if not _sides.has(speaker):
        _sides[speaker] = _sides.size() % 2
    var tex := HallArt.portrait(speaker, String(line.get("expr", "neutral")))
    var rect: TextureRect = _portraits.get(speaker)
    if rect == null and tex != null:
        rect = _add_portrait(speaker)
    if rect != null:
        rect.texture = tex
    for s in _portraits:
        (_portraits[s] as TextureRect).modulate = Color.WHITE if s == speaker else Color(0.6, 0.6, 0.6)

func _add_portrait(speaker: String) -> TextureRect:
    var r := TextureRect.new()
    r.name = "Portrait_" + speaker
    r.mouse_filter = Control.MOUSE_FILTER_IGNORE
    r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    r.size = PORTRAIT_SIZE
    var left := int(_sides[speaker]) == 0
    var target_x := 10.0 if left else 710.0 - PORTRAIT_SIZE.x
    var start_x := -PORTRAIT_SIZE.x if left else 720.0
    r.position = Vector2(start_x, 880.0 - PORTRAIT_SIZE.y + 60.0)
    _stage.add_child(r)
    _portraits[speaker] = r
    _tween = create_tween()
    _tween.tween_property(r, "position:x", target_x, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    return r

func _show_panel() -> void:
    _dim.color.a = PANEL_DIM
    var tex := HallArt.panel(String(_scene.get("id", "")), _index)
    for c in _stage.get_children():
        _stage.remove_child(c)
        c.free()
    _bubble = null
    if tex != null:
        var tr := TextureRect.new()
        tr.name = "PanelArt"
        tr.texture = tex
        tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
        tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        tr.offset_left = 30.0
        tr.offset_right = 690.0
        tr.offset_top = 200.0
        tr.offset_bottom = 900.0
        _stage.add_child(tr)
    else:
        var card := Panel.new()
        card.name = "PanelCard"
        card.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var sb := StyleBoxFlat.new()
        sb.bg_color = CurioTheme.CREAM
        sb.border_color = CurioTheme.BRASS
        sb.set_border_width_all(4)
        sb.set_corner_radius_all(14)
        card.add_theme_stylebox_override("panel", sb)
        card.offset_left = 30.0
        card.offset_right = 690.0
        card.offset_top = 200.0
        card.offset_bottom = 900.0
        _stage.add_child(card)
    _make_bubble(true)
    _name_label.visible = false
    _text_label.text = String((_steps()[_index] as Dictionary).get("caption", ""))
