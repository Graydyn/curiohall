class_name LookPicker
extends Control
## Three looks side by side. Mandatory after finishing an element (no close
## button); from Arrange it can be dismissed.

signal picked(id: String, look: int)
signal closed

var element_id := ""
var game: Game
var _close_button: Button

func setup(g: Game, id: String, closable: bool) -> void:
    game = g
    element_id = id
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.7)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(dim)
    var row: Dictionary = ConfigDB.hall_elements[id]
    var title := Label.new()
    title.text = "Choose a look: %s" % String(row["name"])
    title.position = Vector2(20, 330)
    title.size = Vector2(680, 50)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 30)
    add_child(title)
    var hb := HBoxContainer.new()
    hb.position = Vector2(20, 400)
    hb.size = Vector2(680, 320)
    hb.add_theme_constant_override("separation", 12)
    add_child(hb)
    var looks: Array = row["looks"]
    for i in looks.size():
        var b := Button.new()
        b.name = "Look%d" % i
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.custom_minimum_size = Vector2(0, 300)
        b.text = String(looks[i]["name"])
        b.icon = HallArt.element(id, i)
        b.expand_icon = true
        b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
        if game.hall.looks.has(id) and game.hall.look_of(id) == i:
            b.text += "\n(current)"
        b.pressed.connect(pick.bind(i))
        hb.add_child(b)
    if closable:
        _close_button = Button.new()
        _close_button.name = "PickerClose"
        _close_button.text = "Close"
        _close_button.position = Vector2(220, 760)
        _close_button.size = Vector2(280, 96)
        _close_button.pressed.connect(close)
        add_child(_close_button)

func has_close() -> bool:
    return _close_button != null

func pick(look: int) -> void:
    var res: Dictionary = game.pick_look(element_id, look)
    if res["ok"]:
        picked.emit(element_id, look)

func close() -> void:
    closed.emit()
