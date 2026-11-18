class_name InfoPanel
extends CanvasLayer
## Modal overlay describing one board item: family, tier, where it comes from,
## what it does, and a Sell button for plain items.

signal sold
signal action_rejected(reason: String)

var game: Game
var _pos := Vector2i(-1, -1)
var _type := ""
var _art := TextureRect.new()
var _title := Label.new()
var _lines := VBoxContainer.new()
var _sell_btn := Button.new()

func setup(g: Game) -> void:
    game = g
    layer = 10
    visible = false
    var backdrop := ColorRect.new()
    backdrop.color = Color(0, 0, 0, 0.5)
    backdrop.anchor_right = 1.0
    backdrop.anchor_bottom = 1.0
    backdrop.gui_input.connect(func(e):
        if e is InputEventMouseButton and e.pressed: close())
    add_child(backdrop)
    var center := CenterContainer.new()
    center.anchor_right = 1.0
    center.anchor_bottom = 1.0
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(480, 0)
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.16, 0.15, 0.14)
    style.border_color = Color(1, 0.85, 0.3)
    style.set_border_width_all(2)
    style.set_corner_radius_all(12)
    style.set_content_margin_all(24)
    panel.add_theme_stylebox_override("panel", style)
    center.add_child(panel)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 12)
    panel.add_child(col)
    _art.custom_minimum_size = Vector2(120, 120)
    _art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    col.add_child(_art)
    _title.add_theme_font_size_override("font_size", 28)
    _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    col.add_child(_title)
    col.add_child(_lines)
    _sell_btn.custom_minimum_size = Vector2(0, 56)
    _sell_btn.pressed.connect(_on_sell)
    col.add_child(_sell_btn)
    var close_b := Button.new()
    close_b.text = "Close"
    close_b.pressed.connect(close)
    col.add_child(close_b)

func open(pos: Vector2i) -> void:
    var item := game.board.item_at(pos)
    if item == null:
        return
    _pos = pos
    _type = item.type
    _art.texture = ItemView.art_for(_type)
    _title.text = "%s - Tier %d" % [ItemInfo.family_name(_type), ItemInfo.tier(_type)]
    for c in _lines.get_children():
        _lines.remove_child(c)
        c.queue_free()
    for line in ItemInfo.lines(_type):
        var l := Label.new()
        l.text = line
        l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _lines.add_child(l)
    var price := ItemInfo.sell_price(_type)
    _sell_btn.visible = price > 0
    _sell_btn.text = "Sell (%d coin%s)" % [price, "" if price == 1 else "s"]
    visible = true

func close() -> void:
    visible = false

func _on_sell() -> void:
    var item := game.board.item_at(_pos)
    if item == null or item.type != _type:
        close()
        return
    var res := game.sell(_pos)
    close()
    if res["ok"]:
        sold.emit()
    else:
        action_rejected.emit(res["reason"])
